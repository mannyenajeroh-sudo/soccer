extends Node

# ============================================================
#  SetPieces.gd — STREET 3 ELITE  (Phase 3)
#
#  Full set piece system for all 5 types confirmed in the
#  original Street Football APK binary:
#
#    CORNER_KICK    — CornerKick
#    SIDELINE_KICK  — SidelineKick (throw-in)
#    GOAL_KICK      — GoalKick (GK distribution)
#    MIDFIELD_KICK  — MidFieldKick (kickoff / restart)
#    KEEPER_KICK    — KeeperKick (GK punt)
#
#  Each type has:
#    - IDLE phase: ball and players positioned, taker assigned
#    - EXECUTING phase: ball in play from set piece
#    - COMPLETE phase: returned to normal play
#
#  Bug fixes over Phase 2 stub:
#    - Proper enum types (not bare strings)
#    - GameState phase transitions (PLAY -> FREEKICK -> PLAY)
#    - Ball clamped to legal spot per set piece type
#    - Taker selection gated by stat relevance
#    - setup_timer countdown actually drives phase transition
#    - Opponents pushed back 3m during IDLE (fair wall distance)
# ============================================================

@export var ball_physics: BallPhysics

# ── Set piece type enum — names preserved from binary ────────
enum SetPieceType {
	NONE,
	CORNER_KICK,     # CornerKick
	SIDELINE_KICK,   # SidelineKick (throw-in / sideline restart)
	GOAL_KICK,       # GoalKick (GK distribution)
	MIDFIELD_KICK,   # MidFieldKick (kickoff / centre restart)
	KEEPER_KICK,     # KeeperKick (GK punt after catch)
}

# ── Phases matching animation states from binary ─────────────
# Each maps to: Idle (setup) → Executing (ball live) → Complete
enum SetPiecePhase {
	IDLE,       # SidlelineKickIdle / CornerKickIdle / GoalKickIdle / MidFieldKickIdle
	EXECUTING,  # SidlelineKickPassBall / CornerKickPassBall / GoalKickPassBall / MidFieldKickOpenBall
	COMPLETE,
}

# ── Setup times (seconds before taker gets ball) ─────────────
const SETUP_TIME: Dictionary = {
	SetPieceType.CORNER_KICK:   3.0,
	SetPieceType.SIDELINE_KICK: 2.0,
	SetPieceType.GOAL_KICK:     2.5,
	SetPieceType.MIDFIELD_KICK: 3.0,
	SetPieceType.KEEPER_KICK:   1.5,
}

# ── Execution timeout (ball must leave set piece area in N sec) ──
const EXEC_TIMEOUT: Dictionary = {
	SetPieceType.CORNER_KICK:   6.0,
	SetPieceType.SIDELINE_KICK: 5.0,
	SetPieceType.GOAL_KICK:     7.0,
	SetPieceType.MIDFIELD_KICK: 5.0,
	SetPieceType.KEEPER_KICK:   8.0,
}

# ── Min opponent distance during IDLE (fair wall rule) ────────
const OPPONENT_MIN_DIST := 3.0

# ── State ─────────────────────────────────────────────────────
var active_type:  SetPieceType  = SetPieceType.NONE
var active_phase: SetPiecePhase = SetPiecePhase.IDLE
var taking_team:  int           = -1
var taker_node:   Node          = null
var setup_timer:  float         = 0.0
var exec_timer:   float         = 0.0
var _trigger_pos: Vector3       = Vector3.ZERO
var _handed_to_taker := false
var _ai_exec_token   := 0

# ── Signals ───────────────────────────────────────────────────
signal set_piece_started(type: SetPieceType, taker_id: int)
signal set_piece_executed(type: SetPieceType)
signal set_piece_complete()


# ─────────────────────────────────────────────────────────────
#  PROCESS
# ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if active_type == SetPieceType.NONE:
		return

	match active_phase:
		SetPiecePhase.IDLE:
			setup_timer -= delta
			if setup_timer <= 0.0 and not _handed_to_taker:
				_hand_ball_to_taker()
		SetPiecePhase.EXECUTING:
			exec_timer -= delta
			# Ball has moved significantly → set piece is played
			if ball_physics and ball_physics.velocity.length() > 4.0:
				_finish()
			elif exec_timer <= 0.0:
				# Execution timeout → force complete (ball stays)
				_finish()


# ─────────────────────────────────────────────────────────────
#  PUBLIC API
# ─────────────────────────────────────────────────────────────

## Trigger a set piece at the given world position for the given team.
## Called from MatchManager / GameplayRules.
func trigger(type: SetPieceType, team_id: int, position: Vector3) -> void:
	if active_type != SetPieceType.NONE:
		return  # Already active — ignore duplicate trigger

	active_type   = type
	active_phase  = SetPiecePhase.IDLE
	taking_team   = team_id
	_trigger_pos  = position
	setup_timer   = SETUP_TIME.get(type, 3.0)
	exec_timer    = EXEC_TIMEOUT.get(type, 6.0)
	taker_node    = null
	_handed_to_taker = false
	_ai_exec_token += 1

	# Freeze the ball
	if ball_physics:
		PossessionManager.force_release()
		ball_physics.velocity           = Vector3.ZERO
		ball_physics.angular_velocity   = Vector3.ZERO
		var legal_pos := _legal_ball_position(type, team_id, position)
		ball_physics.ball_position      = legal_pos
		ball_physics.global_position    = legal_pos

	# Push all opponents back to min distance
	_enforce_opponent_distance(team_id)

	# Set GameState to FREEKICK (pauses AI shooting / normal play decisions)
	if GameState.phase == GameState.Phase.PLAY:
		GameState.set_phase_direct(GameState.Phase.FREEKICK)

	var taker_id := _assign_taker(team_id, type)
	set_piece_started.emit(type, taker_id)

## Called by human player or AI taker to actually play the set piece.
## direction and power are supplied by the taker.
func execute_pass(direction: Vector3, power: float) -> void:
	if active_phase != SetPiecePhase.IDLE or taker_node == null:
		return
	active_phase = SetPiecePhase.EXECUTING
	exec_timer   = EXEC_TIMEOUT.get(active_type, 6.0)

	var kick_sys: Node = taker_node.get_node_or_null("KickSystem")
	if kick_sys == null:
		_finish()
		return

	# Restore PLAY so the kick registers normally
	GameState.set_phase_direct(GameState.Phase.PLAY)

	match active_type:
		SetPieceType.CORNER_KICK:
			# CornerKickPassBall — lofted cross into the box
			kick_sys.lob_pass(direction.normalized())
		SetPieceType.SIDELINE_KICK:
			# SidlelineKickPassBall — ground or driven pass in from side
			kick_sys.ground_pass(direction.normalized(), clampf(power, 0.55, 1.0))
		SetPieceType.GOAL_KICK:
			# GoalKickPassBall — GK-style long clearance
			kick_sys.lob_pass(direction.normalized())
		SetPieceType.MIDFIELD_KICK:
			# MidFieldKickOpenBall — short or medium kick-off pass
			kick_sys.ground_pass(direction.normalized(), clampf(power, 0.45, 0.85))
		SetPieceType.KEEPER_KICK:
			# KeeperKick — GK punt, long lofted kick
			kick_sys.lob_pass(direction.normalized())

	set_piece_executed.emit(active_type)

## Shortcut: trigger a corner kick from last_ball_pos (called by GameplayRules).
func start_corner(team_id: int, last_ball_pos: Vector3) -> void:
	trigger(SetPieceType.CORNER_KICK, team_id, last_ball_pos)

## Shortcut: trigger a goal kick for team_id defending.
func start_goal_kick(defending_team_id: int) -> void:
	var gk_pos := Vector3(0.0, 0.11, PitchConstants.defend_goal_z(defending_team_id) * 0.85)
	trigger(SetPieceType.GOAL_KICK, defending_team_id, gk_pos)

## Shortcut: start a sideline kick at position.
func start_sideline_kick(team_id: int, pos: Vector3) -> void:
	trigger(SetPieceType.SIDELINE_KICK, team_id, pos)

## Shortcut: midfield kickoff (called at match start / after goal).
func start_midfield_kick(team_id: int) -> void:
	trigger(SetPieceType.MIDFIELD_KICK, team_id, Vector3.ZERO)

## Shortcut: keeper punt after GK catches.
func start_keeper_kick(gk_node: Node) -> void:
	if gk_node == null:
		return
	taker_node = gk_node
	trigger(SetPieceType.KEEPER_KICK, gk_node.get("team_id"), gk_node.global_position)

## Legacy API — still called by MatchManager for foul free-kicks.
func start_freekick(pos: Vector3, team_id: int) -> void:
	trigger(SetPieceType.SIDELINE_KICK, team_id, pos)


## True when this player must take the current set piece (human input path).
func is_active_taker(p: Node) -> bool:
	return (
		active_type != SetPieceType.NONE
		and active_phase == SetPiecePhase.IDLE
		and taker_node != null
		and taker_node == p
	)


# ─────────────────────────────────────────────────────────────
#  INTERNAL — SETUP
# ─────────────────────────────────────────────────────────────

## Compute the legal ball position for a set piece type.
func _legal_ball_position(type: SetPieceType, team_id: int, original_pos: Vector3) -> Vector3:
	match type:
		SetPieceType.CORNER_KICK:
			# Ball goes to the corner nearest where it went out
			var corner_x := PitchConstants.PLAY_HALF_X - 0.3
			var corner_z := PitchConstants.PLAY_HALF_Z - 0.3
			# Place at nearest corner — use sign of original position
			var sx := signf(original_pos.x) if absf(original_pos.x) > 0.5 else 1.0
			var sz := signf(original_pos.z) if absf(original_pos.z) > 0.5 else 1.0
			return Vector3(sx * corner_x, 0.11, sz * corner_z)

		SetPieceType.GOAL_KICK:
			# Ball on the 6-yard-box edge of the defending GK's goal
			var gz := PitchConstants.defend_goal_z(team_id)
			var inset := 1.5 * signf(gz)  # pull in from the line
			return Vector3(0.0, 0.11, gz - inset)

		SetPieceType.MIDFIELD_KICK:
			return Vector3(0.0, 0.11, 0.0)

		SetPieceType.SIDELINE_KICK:
			# Clamp ball to the sideline nearest the original pos
			var sx := signf(original_pos.x) if absf(original_pos.x) > 0.5 else 1.0
			var clamped_z := clampf(original_pos.z, -PitchConstants.PLAY_HALF_Z + 0.3, PitchConstants.PLAY_HALF_Z - 0.3)
			return Vector3(sx * (PitchConstants.PLAY_HALF_X - 0.15), 0.11, clamped_z)

		SetPieceType.KEEPER_KICK:
			# Ball stays at GK's position (already held)
			return original_pos

		_:
			return original_pos

## Assign the best taker from the taking_team.
## Returns taker node's index and stores in taker_node.
func _assign_taker(team_id: int, type: SetPieceType) -> int:
	if taker_node != null:
		# Already assigned (e.g. keeper kick)
		return _node_index(taker_node)

	var ball_pos := ball_physics.ball_position if ball_physics else Vector3.ZERO
	var best_node: Node = null
	var best_score := -1.0

	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p): continue
		if p.get("team_id") != team_id: continue

		var score := _taker_score(p, type)
		if score > best_score:
			best_score = score
			best_node  = p

	taker_node = best_node
	return _node_index(taker_node)

## Score a player as a set piece taker — higher = better choice.
## Uses PlayerStats where available; falls back to player_rating.
func _taker_score(p: Node, type: SetPieceType) -> float:
	var s: PlayerStats = p.get("stats") as PlayerStats
	match type:
		SetPieceType.CORNER_KICK:
			# Best crosser/lofter
			return s.high_pass if s else (p.get("player_rating") as float if p.get("player_rating") != null else 0.5) * 99.0
		SetPieceType.SIDELINE_KICK:
			# Best ground passer
			return s.floor_pass if s else (p.get("player_rating") as float if p.get("player_rating") != null else 0.5) * 99.0
		SetPieceType.GOAL_KICK, SetPieceType.KEEPER_KICK:
			# GK or best high-passer — prefer goalkeeper position
			var gk_bonus := 20.0 if (p.get("baller_data") != null and
				(p.get("baller_data") as BallerData).position == BallerData.Position.GOALKEEPER) else 0.0
			return (s.high_pass if s else 50.0) + gk_bonus
		SetPieceType.MIDFIELD_KICK:
			# Nearest player to centre
			var dist_penalty: float = p.global_position.distance_to(Vector3.ZERO) * 5.0
			return (s.floor_pass if s else 50.0) - dist_penalty
		_:
			return 50.0

## Give ball to taker and let them execute.
func _hand_ball_to_taker() -> void:
	if taker_node == null or not is_instance_valid(taker_node):
		_finish()
		return

	# Move taker to ball if too far
	var ball_pos := ball_physics.ball_position if ball_physics else Vector3.ZERO
	if taker_node.global_position.distance_to(ball_pos) > 2.5:
		taker_node.global_position = ball_pos + Vector3(0.0, 0.0, 0.5)

	# Give possession to taker
	var drib: Node = taker_node.get_node_or_null("DribbleSystem")
	if drib:
		drib.try_pickup(ball_pos)

	_handed_to_taker = true

	# AI taker auto-executes after short reaction delay
	var ai_ctrl: Node = taker_node.get_node_or_null("AIController")
	if ai_ctrl != null or not taker_node.get_meta("is_human", false):
		_ai_execute_set_piece()

## Push all opponents back to minimum fair distance.
func _enforce_opponent_distance(team_id: int) -> void:
	if ball_physics == null:
		return
	var ball_pos := ball_physics.ball_position
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p): continue
		if p.get("team_id") == team_id: continue  # Only push opponents
		var to_p: Vector3 = p.global_position - ball_pos
		to_p.y = 0.0
		var dist := to_p.length()
		if dist < OPPONENT_MIN_DIST and dist > 0.01:
			p.global_position = ball_pos + to_p.normalized() * (OPPONENT_MIN_DIST + 0.1)

func _node_index(node: Node) -> int:
	if node == null: return -1
	return node.get_instance_id() % 1000  # lightweight unique ID for signal


# ─────────────────────────────────────────────────────────────
#  AI SET PIECE EXECUTION
# ─────────────────────────────────────────────────────────────

## AI taker chooses direction and plays the set piece.
func _ai_execute_set_piece() -> void:
	if taker_node == null or ball_physics == null:
		_finish()
		return

	# Short reaction delay before execution
	var stats := taker_node.get("stats") as PlayerStats
	var delay: float = stats.get_reaction_delay() if stats != null else 0.25

	var token := _ai_exec_token
	await get_tree().create_timer(delay + randf_range(0.05, 0.20)).timeout

	if token != _ai_exec_token or active_type == SetPieceType.NONE or not is_instance_valid(taker_node):
		return

	var team_id: int = taker_node.get("team_id") as int
	var goal_pos := PitchConstants.attack_goal_vec(team_id)
	var aim: Vector3

	match active_type:
		SetPieceType.CORNER_KICK:
			# Aim between goal post and penalty spot — find a runner if possible
			var runner := _find_runner_in_box(team_id)
			if runner:
				aim = (runner.global_position - taker_node.global_position)
				aim.y = 0.0
				aim = aim.normalized()
			else:
				# Float to the far post area
				aim = (goal_pos - taker_node.global_position).normalized()

		SetPieceType.SIDELINE_KICK:
			# Ground pass to nearest teammate in good position
			var target := _find_open_teammate(team_id)
			if target:
				aim = (target.global_position - taker_node.global_position)
				aim.y = 0.0
				aim = aim.normalized()
			else:
				aim = (goal_pos - taker_node.global_position).normalized()

		SetPieceType.GOAL_KICK, SetPieceType.KEEPER_KICK:
			# Long clearance toward attack half
			var target := _find_open_teammate(team_id)
			aim = (target.global_position if target else goal_pos) - taker_node.global_position
			aim.y = 0.0
			aim = aim.normalized()

		SetPieceType.MIDFIELD_KICK:
			# Short kickoff pass to nearest teammate
			var target := _find_open_teammate(team_id)
			if target:
				aim = (target.global_position - taker_node.global_position)
				aim.y = 0.0
				aim = aim.normalized()
			else:
				aim = (goal_pos - taker_node.global_position).normalized()

		_:
			aim = (goal_pos - taker_node.global_position).normalized()

	execute_pass(aim, randf_range(0.60, 0.90))


# ─────────────────────────────────────────────────────────────
#  INTERNAL — HELPERS
# ─────────────────────────────────────────────────────────────

## Find a teammate making a run into the penalty box.
func _find_runner_in_box(team_id: int) -> Node:
	var goal_pos := PitchConstants.attack_goal_vec(team_id)
	var best: Node = null
	var best_d := 999.0
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p): continue
		if p.get("team_id") != team_id: continue
		if p == taker_node: continue
		var d: float = p.global_position.distance_to(goal_pos)
		# Must be in the attacking third
		if d < 8.0 and d < best_d:
			best_d = d
			best   = p
	return best

## Find an open teammate (no opponent within 2m).
func _find_open_teammate(team_id: int) -> Node:
	var best: Node = null
	var best_score := -1.0
	var goal_pos := PitchConstants.attack_goal_vec(team_id)
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p): continue
		if p.get("team_id") != team_id: continue
		if p == taker_node: continue
		# Check closeness to nearest opponent
		var pressure := _nearest_opponent_dist(p, team_id)
		# Forward progress value
		var fwd_val := GameplayAI.action_weight(p.global_position, goal_pos, team_id)
		var score := fwd_val + clampf((pressure - 2.0) * 0.1, 0.0, 0.5)
		if score > best_score:
			best_score = score
			best = p
	return best

func _nearest_opponent_dist(node: Node, team_id: int) -> float:
	var min_d := 99.0
	for p in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(p): continue
		if p.get("team_id") == team_id: continue
		var d: float = node.global_position.distance_to(p.global_position)
		if d < min_d:
			min_d = d
	return min_d

## Finish the set piece and return to normal play.
func _finish() -> void:
	var finished := active_type
	_ai_exec_token += 1
	_handed_to_taker = false
	active_type   = SetPieceType.NONE
	active_phase  = SetPiecePhase.COMPLETE
	taker_node    = null
	taking_team   = -1
	setup_timer   = 0.0
	exec_timer    = 0.0
	# Ensure we're in PLAY phase
	if GameState.phase == GameState.Phase.FREEKICK:
		GameState.set_phase_direct(GameState.Phase.PLAY)
	set_piece_complete.emit()
	# Small buffer: emit with NONE type for "completed" callback users
	set_piece_executed.emit(finished)
