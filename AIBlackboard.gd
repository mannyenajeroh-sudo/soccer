extends Node

# ============================================================
#  AIBlackboard.gd — Chess-Zone shared AI memory (autoload)
#  One tick per physics frame. All AI trees read the same board.
# ============================================================

enum Arc { LETHAL, DANGER, CONTEST, SAFE }

const ARC_LETHAL_DIST  := 4.0
const ARC_DANGER_DIST  := 9.0
const ARC_CONTEST_DIST := 16.0

const GRID_COLS := 6
const GRID_ROWS := 4

var ball_pos: Vector3 = Vector3.ZERO
var ball_vel: Vector3 = Vector3.ZERO
var ball_arc_attacking: int = Arc.CONTEST
var ball_grid: Vector2i = Vector2i.ZERO

var possessor: Node = null
var possession_team: int = -1
var last_touch_time: float = 0.0

var _players: Array = []
var _ball: Node = null

# Per-player (indexed by registration order, max 6)
var player_by_id: Dictionary = {}  # instance_id -> index
var player_positions: Array[Vector3] = []
var player_teams: Array[int] = []
var player_roles: Array[String] = []
var player_arc_to_own_goal: Array[int] = []
var player_marked_by: Array[int] = []  # instance_id of marker, -1
var player_flags: Array[String] = []

var zone_occupancy: Array = []  # [24][2] team counts
var zone_pressure: PackedFloat32Array = PackedFloat32Array()

var counter_attack: bool = false
var skill_move_active: bool = false
var press_trigger_high: bool = false

var opening_mark_active: bool = false
var opening_mark_until: float = 0.0
var decision_fidelity: float = 0.80
var press_trigger_dist: float = 2.5
var shot_quality_floor: float = 0.55

func _ready() -> void:
	zone_occupancy.resize(GRID_COLS * GRID_ROWS)
	for i in zone_occupancy.size():
		zone_occupancy[i] = [0, 0]
	zone_pressure.resize(GRID_COLS * GRID_ROWS)
	PossessionManager.possession_changed.connect(_on_possession_changed)

func register_match(players: Array, ball: Node) -> void:
	_players = players.duplicate()
	_ball = ball
	player_by_id.clear()
	player_positions.resize(_players.size())
	player_teams.resize(_players.size())
	player_roles.resize(_players.size())
	player_arc_to_own_goal.resize(_players.size())
	player_marked_by.resize(_players.size())
	player_flags.resize(_players.size())
	for i in _players.size():
		var p: Node = _players[i]
		if not is_instance_valid(p):
			continue
		player_by_id[p.get_instance_id()] = i
		player_teams[i] = int(p.get("team_id"))
		player_roles[i] = _role_for(p)
		player_marked_by[i] = -1
		player_flags[i] = ""
	_apply_difficulty_from_game()

func _apply_difficulty_from_game() -> void:
	var diff: int = int(GameState.get_meta("difficulty", 1))
	var fidelity := [0.40, 0.80, 0.95]
	var press := [1.75, 2.50, 3.25]
	var sq := [0.40, 0.55, 0.70]
	decision_fidelity = fidelity[clampi(diff, 0, 2)]
	press_trigger_dist = press[clampi(diff, 0, 2)]
	shot_quality_floor = sq[clampi(diff, 0, 2)]

func _physics_process(_delta: float) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	if _ball == null or _players.is_empty():
		return
	_tick_board()

func _tick_board() -> void:
	_update_ball()
	_update_players()
	_update_grid()
	_update_marking()
	_update_pressure()
	_detect_counter_attack()
	_clear_stale_flags()

func _update_ball() -> void:
	if "ball_position" in _ball:
		ball_pos = _ball.ball_position
	else:
		ball_pos = _ball.global_position
	if "velocity" in _ball:
		ball_vel = _ball.velocity as Vector3
	else:
		ball_vel = Vector3.ZERO

	possessor = PossessionManager.get_possessor()
	possession_team = -1
	if possessor != null and is_instance_valid(possessor):
		possession_team = int(possessor.get("team_id"))

	var attack_goal := PitchConstants.attack_goal_vec(possession_team if possession_team >= 0 else 0)
	ball_arc_attacking = get_arc_zone(ball_pos, attack_goal)
	ball_grid = world_to_grid(ball_pos, possession_team if possession_team >= 0 else 0)

func _update_players() -> void:
	for i in _players.size():
		var p: Node3D = _players[i] as Node3D
		if p == null or not is_instance_valid(p):
			continue
		player_positions[i] = p.global_position
		var own_goal := PitchConstants.defend_goal_vec(player_teams[i])
		player_arc_to_own_goal[i] = get_arc_zone(p.global_position, own_goal)

func _update_grid() -> void:
	for i in zone_occupancy.size():
		zone_occupancy[i] = [0, 0]
		zone_pressure[i] = 0.0
	for i in _players.size():
		var p: Node3D = _players[i] as Node3D
		if p == null or not is_instance_valid(p):
			continue
		var g := world_to_grid(p.global_position, player_teams[i])
		var idx := grid_index(g.x, g.y)
		if idx < 0 or idx >= zone_occupancy.size():
			continue
		zone_occupancy[idx][player_teams[i]] += 1
		zone_pressure[idx] += 1.0

func start_opening_mark(duration: float = 12.0) -> void:
	opening_mark_active = true
	opening_mark_until = Time.get_ticks_msec() * 0.001 + duration

func get_mark_target(defender: Node) -> Node:
	if defender == null:
		return null
	var def_id := defender.get_instance_id()
	for i in _players.size():
		if player_marked_by[i] == def_id:
			var opp: Node = _players[i]
			if is_instance_valid(opp):
				return opp
	return null

func _update_marking() -> void:
	for i in player_marked_by.size():
		player_marked_by[i] = -1
	if opening_mark_active:
		_assign_opening_marks()
		if Time.get_ticks_msec() * 0.001 > opening_mark_until:
			opening_mark_active = false
		return
	for i in _players.size():
		var defender: Node3D = _players[i] as Node3D
		if defender == null or not is_instance_valid(defender):
			continue
		if player_roles[i] == "goalkeeper":
			continue
		var opp := _nearest_opponent_ahead(defender, i)
		if opp >= 0:
			player_marked_by[opp] = defender.get_instance_id()

func _assign_opening_marks() -> void:
	for team in [0, 1]:
		var def_indices: Array[int] = []
		var opp_indices: Array[int] = []
		for i in _players.size():
			if player_roles[i] == "goalkeeper":
				continue
			if player_teams[i] == team:
				def_indices.append(i)
			else:
				opp_indices.append(i)
		var used_opps: Dictionary = {}
		for di in def_indices:
			var defender: Node3D = _players[di] as Node3D
			if defender == null or not is_instance_valid(defender):
				continue
			var best_opp := -1
			var best_score: float = -1.0
			for oi in opp_indices:
				if used_opps.has(oi):
					continue
				var opp: Node3D = _players[oi] as Node3D
				if opp == null or not is_instance_valid(opp):
					continue
				var own_goal := PitchConstants.defend_goal_vec(team)
				var threat: float = 1.0 / (opp.global_position.distance_to(own_goal) + 0.6)
				threat += 1.0 / (opp.global_position.distance_to(defender.global_position) + 0.4)
				threat += 1.0 / (opp.global_position.distance_to(ball_pos) + 1.0)
				if threat > best_score:
					best_score = threat
					best_opp = oi
			if best_opp >= 0:
				used_opps[best_opp] = true
				player_marked_by[best_opp] = defender.get_instance_id()

func _update_pressure() -> void:
	press_trigger_high = false
	if possessor == null or not is_instance_valid(possessor):
		return
	var poss_team: int = int(possessor.get("team_id"))
	var defend_team: int = 1 - poss_team
	if get_arc_zone(ball_pos, PitchConstants.defend_goal_vec(defend_team)) >= Arc.SAFE:
		for i in _players.size():
			if player_teams[i] != defend_team:
				continue
			var p: Node3D = _players[i] as Node3D
			if p == null:
				continue
			if p.global_position.distance_to(ball_pos) < press_trigger_dist + 1.0:
				press_trigger_high = true
				break

func _detect_counter_attack() -> void:
	counter_attack = false
	if possession_team < 0:
		return
	if ball_vel.length() < 8.0:
		return
	var to_goal := PitchConstants.attack_goal_vec(possession_team) - ball_pos
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.01:
		return
	if ball_vel.normalized().dot(to_goal.normalized()) > 0.65:
		counter_attack = true

func _clear_stale_flags() -> void:
	for i in player_flags.size():
		if player_flags[i] == "calling_for_pass":
			player_flags[i] = ""

func _on_possession_changed(_new_p, _old) -> void:
	last_touch_time = Time.get_ticks_msec() / 1000.0

static func get_arc_zone(from: Vector3, toward: Vector3) -> int:
	var d: float = Vector2(from.x - toward.x, from.z - toward.z).length()
	if d <= ARC_LETHAL_DIST:
		return Arc.LETHAL
	if d <= ARC_DANGER_DIST:
		return Arc.DANGER
	if d <= ARC_CONTEST_DIST:
		return Arc.CONTEST
	return Arc.SAFE

func world_to_grid(pos: Vector3, for_team: int) -> Vector2i:
	var hx := PitchConstants.PLAY_HALF_X
	var hz := PitchConstants.PLAY_HALF_Z
	var nx: float = (pos.x + hx) / (hx * 2.0)
	var nz: float = (pos.z + hz) / (hz * 2.0)
	if for_team == 1:
		nz = 1.0 - nz
	var col: int = clampi(int(nx * float(GRID_COLS)), 0, GRID_COLS - 1)
	var row: int = clampi(int(nz * float(GRID_ROWS)), 0, GRID_ROWS - 1)
	return Vector2i(col, row)

static func grid_index(col: int, row: int) -> int:
	return row * GRID_COLS + col

func grid_band(col: int) -> int:
	if col <= 1:
		return 0  # DEF
	if col <= 3:
		return 1  # MID
	return 2  # ATT

func best_open_teammate(team_id: int, exclude: Node, goal_pos: Vector3) -> Node:
	var best: Node = null
	var best_arc: int = Arc.SAFE + 1
	for i in _players.size():
		var mate: Node = _players[i]
		if mate == exclude or not is_instance_valid(mate):
			continue
		if player_teams[i] != team_id:
			continue
		if player_roles[i] == "goalkeeper":
			continue
		if has_marker(mate):
			continue
		var arc: int = get_arc_zone(mate.global_position, goal_pos)
		if arc < best_arc:
			best_arc = arc
			best = mate
	return best

func teammate_in_arc(team_id: int, arc: int, goal_pos: Vector3, exclude: Node = null) -> bool:
	for i in _players.size():
		var mate: Node = _players[i]
		if mate == exclude or not is_instance_valid(mate):
			continue
		if player_teams[i] != team_id:
			continue
		if get_arc_zone(mate.global_position, goal_pos) <= arc:
			return true
	return false

func has_marker(player_node: Node) -> bool:
	var idx := _index_of(player_node)
	if idx < 0:
		return false
	return player_marked_by[idx] >= 0

func set_flag(player_node: Node, flag: String) -> void:
	var idx := _index_of(player_node)
	if idx >= 0:
		player_flags[idx] = flag

func has_flag(player_node: Node, flag: String) -> bool:
	var idx := _index_of(player_node)
	if idx < 0:
		return false
	return player_flags[idx] == flag

func flank_open(team_id: int, from_pos: Vector3, goal_pos: Vector3) -> bool:
	var side: float = signf(from_pos.x) if absf(from_pos.x) > 0.5 else 1.0
	var wide_x: float = side * PitchConstants.PLAY_HALF_X * 0.55
	var probe := Vector3(wide_x, 0.0, from_pos.z)
	for i in _players.size():
		var opp: Node3D = _players[i] as Node3D
		if opp == null or player_teams[i] == team_id:
			continue
		if opp.global_position.distance_to(probe) < 2.2:
			return false
	return true

func forward_lane_clear(carrier: Node3D, goal_pos: Vector3) -> bool:
	if carrier == null or not is_instance_valid(carrier):
		return false
	var from := carrier.global_position
	var dir := goal_pos - from
	dir.y = 0.0
	var lane_len := dir.length()
	if lane_len < 0.01:
		return false
	dir /= lane_len
	var team_id: int = int(carrier.get("team_id"))
	for i in _players.size():
		if player_teams[i] == team_id:
			continue
		var opp: Node3D = _players[i] as Node3D
		if opp == null or not is_instance_valid(opp):
			continue
		var to_opp: Vector3 = opp.global_position - from
		to_opp.y = 0.0
		var proj: float = to_opp.dot(dir)
		if proj < 0.5 or proj > lane_len:
			continue
		if (to_opp - dir * proj).length() < 1.4:
			return false
	return true

func defenders_near(pos: Vector3, defending_team: int, radius: float) -> int:
	var count := 0
	for i in _players.size():
		if player_teams[i] == defending_team:
			continue
		var opp: Node3D = _players[i] as Node3D
		if opp and opp.global_position.distance_to(pos) < radius:
			count += 1
	return count

func _index_of(player_node: Node) -> int:
	if player_node == null:
		return -1
	return int(player_by_id.get(player_node.get_instance_id(), -1))

func _nearest_opponent_ahead(defender: Node3D, def_idx: int) -> int:
	var best := -1
	var best_score: float = -1.0
	var own_goal := PitchConstants.defend_goal_vec(player_teams[def_idx])
	for i in _players.size():
		if player_teams[i] == player_teams[def_idx]:
			continue
		var opp: Node3D = _players[i] as Node3D
		if opp == null:
			continue
		var threat: float = 1.0 / (opp.global_position.distance_to(own_goal) + 0.5)
		threat += 1.0 / (opp.global_position.distance_to(ball_pos) + 1.0)
		if threat > best_score:
			best_score = threat
			best = i
	return best

func _role_for(p: Node) -> String:
	var ai: Node = p.get_node_or_null("AIController")
	if ai and ai.get("role"):
		return str(ai.get("role"))
	return "midfielder"
