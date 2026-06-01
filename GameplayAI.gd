extends Node

# ============================================================
#  GameplayAI.gd — STREET 3 ELITE
#  Pitch control grid, xG model, EPV, best-direction sampling.
#  KEY FIX: is_defensive_third() was missing — added below.
#  get_best_pass_value() and get_best_dribble_value() added.
# ============================================================

@export var alpha: float = 0.60
@export var beta:  float = 0.25
@export var gamma: float = 0.35

const GRID_X := 28
const GRID_Z := 18
const PITCH_HALF_X := PitchConstants.PLAY_HALF_X
const PITCH_HALF_Z := PitchConstants.PLAY_HALF_Z

const UPDATE_INTERVAL      := 0.12
const DIRTY_REGION_RADIUS  := 10.0

const XG_BASE_DECAY    := 0.28
const XG_BASE_SCALE    := 0.42
const XG_ANGLE_WEIGHT  := 0.40
const XG_LANE_WEIGHT   := 0.30
const XG_MIN           := 0.02
const XG_MAX           := 0.72

const EPV_MIN          := 0.06
const EPV_MAX          := 0.94
const EPV_XG_SCALE     := 1.5

const PC_INFLUENCE     := 0.75

const DIR_SAMPLES      := 12
const DIR_PROBE_DIST   := 4.0

const DEFENDER_AVOID_RADIUS := 2.8
const DEFENDER_AVOID_WEIGHT := 0.30

# Defensive third threshold (fraction of pitch length from own goal)
const DEFENSIVE_THIRD_FRAC := 0.28   # Shorter cage — own-third clears trigger earlier

var pitch_control: PackedFloat32Array = PackedFloat32Array()
var _players:       Array = []
var _ball_node:     BallPhysics = null
var _pc_timer:      float = 0.0
var _cached_team:   int = -1
var _last_ball_pos: Vector3 = Vector3.ZERO
var _possession_changed: bool = false

func _ready() -> void:
	pitch_control.resize(GRID_X * GRID_Z)
	for i in pitch_control.size():
		pitch_control[i] = 0.5

func register_players(list: Array) -> void:
	_players = list

func register_ball(ball: BallPhysics) -> void:
	_ball_node = ball

func notify_possession_changed() -> void:
	_possession_changed = true
	_pc_timer = 0.0

func _process(delta: float) -> void:
	_pc_timer = maxf(0.0, _pc_timer - delta)

# ── xG ───────────────────────────────────────────────────────
func get_xg(pos: Vector3, goal_pos: Vector3) -> float:
	var flat := Vector3(pos.x, 0.0, pos.z)
	var g    := Vector3(goal_pos.x, 0.0, goal_pos.z)
	var dist := flat.distance_to(g)
	if dist < 0.1: return XG_MAX
	var to_goal   := (g - flat).normalized()
	var angle_pen := 1.0 - absf(to_goal.x) * XG_ANGLE_WEIGHT
	var lane_pen  := 1.0 - _defender_lane_density(flat, g) * XG_LANE_WEIGHT
	var base      := XG_BASE_SCALE / (dist * XG_BASE_DECAY + 1.0)
	return clampf(base * angle_pen * lane_pen, XG_MIN, XG_MAX)

func get_epv(xg: float) -> float:
	var possession_prob := clampf(0.5 + xg * 0.8, 0.0, 1.0)
	var future_xg      := xg * 0.6
	return clampf(lerpf(EPV_MIN, EPV_MAX, (possession_prob + future_xg) * 0.5 * EPV_XG_SCALE), EPV_MIN, EPV_MAX)

func get_pitch_control_at(pos: Vector3, team_id: int) -> float:
	_maybe_refresh(team_id)
	var g: Vector2i = world_to_grid(pos)
	return pitch_control[_grid_index(g.x, g.y)]

func action_weight(pos: Vector3, goal_pos: Vector3, team_id: int, role_mult: float = 1.0) -> float:
	var pc  := get_pitch_control_at(pos, team_id)
	var xg  := get_xg(pos, goal_pos)
	var epv := get_epv(xg)
	return (alpha * pc * epv + beta * epv + gamma * xg) * role_mult

# ── Tactical helpers ─────────────────────────────────────────

func is_defensive_third(ball_pos: Vector3, own_goal: Vector3) -> bool:
	# True if the ball is in the defensive third closest to own_goal
	var pitch_len := PITCH_HALF_Z * 2.0
	var dist_to_own := absf(ball_pos.z - own_goal.z)
	return dist_to_own < pitch_len * DEFENSIVE_THIRD_FRAC

func get_best_pass_value(teammates: Array, goal_pos: Vector3, team_id: int) -> float:
	var best := 0.0
	for mate in teammates:
		if not is_instance_valid(mate): continue
		if mate.get("team_id") != team_id: continue
		var ai: Node = mate.get_node_or_null("AIController")
		var mate_role := str(ai.get("role")) if ai != null else ""
		if mate_role == "goalkeeper":
			continue
		var val: float = action_weight(mate.global_position, goal_pos, team_id)
		var role_mult := 1.0
		match mate_role:
			"striker": role_mult = 1.12
			"midfielder": role_mult = 1.05
		if val * role_mult > best:
			best = val * role_mult
	return best

func get_best_dribble_value(pos: Vector3, goal_pos: Vector3, team_id: int, role: String) -> float:
	var role_mult := 1.0
	match role:
		"striker":  role_mult = 1.20
		"defender": role_mult = 0.80
	var best_dir := best_direction(pos, goal_pos, team_id, role)
	var probe    := pos + best_dir * DIR_PROBE_DIST
	return action_weight(probe, goal_pos, team_id, role_mult)

func best_direction(origin: Vector3, goal_pos: Vector3, team_id: int, role: String, samples: int = DIR_SAMPLES) -> Vector3:
	var best_w   := -1.0
	var best_dir := (goal_pos - origin)
	best_dir.y = 0.0
	best_dir = best_dir.normalized()
	for i in samples:
		var angle := (float(i) / float(samples)) * TAU
		var dir   := Vector3(sin(angle), 0.0, cos(angle))
		var probe := origin + dir * DIR_PROBE_DIST
		probe = PitchConstants.clamp_player(probe)
		var w  := action_weight(probe, goal_pos, team_id)
		# Penalise directions toward defenders
		var defender_penalty := 0.0
		for p in _players:
			if not is_instance_valid(p): continue
			if p.get("team_id") == team_id: continue
			var d: float = probe.distance_to(p.global_position)
			if d < DEFENDER_AVOID_RADIUS:
				defender_penalty += DEFENDER_AVOID_WEIGHT * (1.0 - d / DEFENDER_AVOID_RADIUS)
		w -= defender_penalty
		if w > best_w:
			best_w   = w
			best_dir = dir
	return best_dir

# ── Soccer-course steering helper (bicircular falloff) ────────
static func bicircular_weight(
	position: Vector3,
	center: Vector3,
	inner_radius: float,
	inner_weight: float,
	outer_radius: float,
	outer_weight: float
) -> float:
	var d := Vector2(position.x - center.x, position.z - center.z).length()
	if d > outer_radius:
		return outer_weight
	if d < inner_radius:
		return inner_weight
	var t := (d - inner_radius) / maxf(outer_radius - inner_radius, 0.001)
	return lerpf(inner_weight, outer_weight, t)

# ── Internal helpers ─────────────────────────────────────────

func _maybe_refresh(team_id: int) -> void:
	if _pc_timer > 0.0 and _cached_team == team_id and not _possession_changed:
		return
	_possession_changed = false
	_cached_team = team_id
	_pc_timer = UPDATE_INTERVAL
	_refresh_pitch_control(team_id)

func _refresh_pitch_control(team_id: int) -> void:
	for gz in GRID_Z:
		for gx in GRID_X:
			var world := grid_to_world(Vector2i(gx, gz))
			var control := _compute_pc_at(world, team_id)
			pitch_control[_grid_index(gx, gz)] = control

func _compute_pc_at(pos: Vector3, team_id: int) -> float:
	var team_inf := 0.0
	var opp_inf  := 0.0
	for p in _players:
		if not is_instance_valid(p): continue
		var d: float = pos.distance_to(p.global_position)
		var inf: float = exp(-d * PC_INFLUENCE)
		if p.get("team_id") == team_id:
			team_inf += inf
		else:
			opp_inf += inf
	var total := team_inf + opp_inf
	if total < 0.0001: return 0.5
	return team_inf / total

func _defender_lane_density(from: Vector3, to: Vector3) -> float:
	var density := 0.0
	var dir := (to - from).normalized()
	var dist := from.distance_to(to)
	for p in _players:
		if not is_instance_valid(p): continue
		var to_p: Vector3 = p.global_position - from
		to_p.y = 0.0
		var proj: float = to_p.dot(dir)
		if proj < 0.0 or proj > dist: continue
		var perp: float = (to_p - dir * proj).length()
		if perp < 1.5:
			density += 1.0 - (perp / 1.5)
	return clampf(density, 0.0, 1.0)

func world_to_grid(pos: Vector3) -> Vector2i:
	var gx := int((pos.x + PITCH_HALF_X) / (PITCH_HALF_X * 2.0) * float(GRID_X))
	var gz := int((pos.z + PITCH_HALF_Z) / (PITCH_HALF_Z * 2.0) * float(GRID_Z))
	return Vector2i(clamp(gx, 0, GRID_X - 1), clamp(gz, 0, GRID_Z - 1))

func grid_to_world(g: Vector2i) -> Vector3:
	var x := (float(g.x) / float(GRID_X)) * PITCH_HALF_X * 2.0 - PITCH_HALF_X
	var z := (float(g.y) / float(GRID_Z)) * PITCH_HALF_Z * 2.0 - PITCH_HALF_Z
	return Vector3(x, 0.0, z)

func _grid_index(gx: int, gz: int) -> int:
	return gz * GRID_X + gx
