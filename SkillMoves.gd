class_name SkillMoves
extends Node

# ============================================================
# SkillMoves.gd — STREET 3 ELITE (Phase 2)
# ============================================================

enum SkillMove {
	NONE,
	ALL_OUT_SHOOTING,
	CROQUETTE,
	MARSEILLE_TURN,
	OX_TAIL,
	RAINBOW_OVER,
	VIRTUAL_PRO_BALL,
	STEPOVER,
	WALL_REBOUND,
}

const DURATION: Dictionary = {
	SkillMove.WALL_REBOUND:    0.55,
	SkillMove.CROQUETTE:       0.55,
	SkillMove.MARSEILLE_TURN:  0.80,
	SkillMove.OX_TAIL:         0.50,
	SkillMove.RAINBOW_OVER:    1.00,
	SkillMove.ALL_OUT_SHOOTING:0.30,
	SkillMove.VIRTUAL_PRO_BALL:0.40,
	SkillMove.STEPOVER:        0.30,
}

const CANCEL_WINDOW: Dictionary = {
	SkillMove.WALL_REBOUND:    0.12,
	SkillMove.CROQUETTE:       0.15,
	SkillMove.MARSEILLE_TURN:  0.20,
	SkillMove.OX_TAIL:         0.10,
	SkillMove.RAINBOW_OVER:    0.18,
	SkillMove.ALL_OUT_SHOOTING:0.08,
	SkillMove.VIRTUAL_PRO_BALL:0.12,
	SkillMove.STEPOVER:        0.10,
}

const STAMINA_COST: Dictionary = {
	SkillMove.WALL_REBOUND:    0.04,
	SkillMove.CROQUETTE:       0.05,
	SkillMove.MARSEILLE_TURN:  0.08,
	SkillMove.OX_TAIL:         0.05,
	SkillMove.RAINBOW_OVER:    0.12,
	SkillMove.ALL_OUT_SHOOTING:0.10,
	SkillMove.VIRTUAL_PRO_BALL:0.06,
	SkillMove.STEPOVER:        0.04,
}

const TIER: Dictionary = {
	SkillMove.WALL_REBOUND:     0.0,
	SkillMove.VIRTUAL_PRO_BALL: 0.30,
	SkillMove.OX_TAIL:          0.30,
	SkillMove.STEPOVER:         0.60,
	SkillMove.CROQUETTE:        0.60,
	SkillMove.MARSEILLE_TURN:   0.85,
	SkillMove.RAINBOW_OVER:     0.85,
	SkillMove.ALL_OUT_SHOOTING: 0.70,
}

var current_skill: SkillMove = SkillMove.NONE
var skill_timer:   float     = 0.0
var elapsed:       float     = 0.0
var _active_tween: Tween     = null

@export var player:         CharacterBody3D
@export var ball_physics:   Node
@export var dribble_system: Node

signal skill_started(skill: SkillMove)
signal skill_finished(skill: SkillMove, completed: bool)
signal skill_executed(move_name: String)

# Legacy gesture trackers
var _roulette_total_rot := 0.0
var _roulette_timer     := 0.0
var _prev_stick_angle   := 0.0
const ROULETTE_ANGLE    := deg_to_rad(270.0)
const ROULETTE_WINDOW   := 0.5

var _stepover_flicks: Array[float] = []
var _stepover_timer := 0.0
const STEPOVER_WINDOW  := 0.4
const STEPOVER_MIN_MAG := 0.7

var _last_shoot_time := 0.0

func _physics_process(delta: float) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	_tick_active_skill(delta)
	_tick_roulette(delta)
	_track_stepover(delta)

func _tick_active_skill(delta: float) -> void:
	if current_skill == SkillMove.NONE:
		return
	skill_timer -= delta
	elapsed += delta
	if skill_timer <= 0.0:
		_complete_skill(true)

# ─────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────

func try_skill(skill: SkillMove) -> bool:
	if current_skill != SkillMove.NONE:
		return false
	if not dribble_system.in_possession:
		if skill != SkillMove.RAINBOW_OVER and skill != SkillMove.VIRTUAL_PRO_BALL:
			return false
	if not _check_tier_for(skill):
		return false
	if not _has_stamina_for(skill):
		return false
	_begin_skill(skill)
	return true

func try_cancel() -> bool:
	if current_skill == SkillMove.NONE:
		return false
	var window: float = CANCEL_WINDOW.get(current_skill, 0.15)
	if elapsed <= window:
		_complete_skill(false)
		return true
	return false

# ─────────────────────────────────────────────────────────────
# STATE MACHINE
# ─────────────────────────────────────────────────────────────

func _begin_skill(skill: SkillMove) -> void:
	current_skill = skill
	skill_timer   = DURATION.get(skill, 0.5)
	elapsed       = 0.0

	var cost: float = STAMINA_COST.get(skill, 0.05)
	if "stamina" in player:
		player.stamina = maxf(0.0, player.stamina - cost)

	if _active_tween != null and _active_tween.is_running():
		_active_tween.kill()
	_active_tween = null

	skill_started.emit(skill)
	_run_skill_logic(skill)
	skill_executed.emit(_skill_name(skill))

	if player != null and player.is_inside_tree():
		var ring_col: Color
		match skill:
			SkillMove.MARSEILLE_TURN: ring_col = Color(0.0, 1.0, 0.53)
			SkillMove.RAINBOW_OVER:   ring_col = Color(0.8, 0.2, 1.0)
			SkillMove.OX_TAIL:        ring_col = Color(1.0, 0.6, 0.0)
			SkillMove.CROQUETTE:      ring_col = Color(0.0, 0.8, 1.0)
			_:                        ring_col = Color(1.0, 1.0, 0.2)
		VisualEffects.skill_ring(player.global_position, ring_col)

	MatchEventBus.emit_skill(player, int(skill))

func _complete_skill(completed: bool) -> void:
	var finished := current_skill
	current_skill = SkillMove.NONE
	skill_timer   = 0.0
	elapsed       = 0.0

	if _active_tween != null and _active_tween.is_running():
		_active_tween.kill()
	_active_tween = null

	if completed and dribble_system != null and not dribble_system.in_possession:
		if ball_physics != null:
			dribble_system.try_pickup(ball_physics.ball_position)

	skill_finished.emit(finished, completed)

# ─────────────────────────────────────────────────────────────
# SKILL IMPLEMENTATIONS
# ─────────────────────────────────────────────────────────────

func _run_skill_logic(skill: SkillMove) -> void:
	match skill:
		SkillMove.WALL_REBOUND:     _exec_wall_rebound()
		SkillMove.MARSEILLE_TURN:   _exec_marseille_turn()
		SkillMove.CROQUETTE:        _exec_croquette()
		SkillMove.OX_TAIL:          _exec_ox_tail()
		SkillMove.RAINBOW_OVER:     _exec_rainbow_over()
		SkillMove.ALL_OUT_SHOOTING: _exec_all_out_shooting()
		SkillMove.VIRTUAL_PRO_BALL: _exec_virtual_pro_ball()
		SkillMove.STEPOVER:         _exec_stepover_skill(1.0 if randf() > 0.5 else -1.0)

# ──────────────────────────────────────────────────────────────
func _exec_marseille_turn() -> void:
	if ball_physics == null or player == null: return
	dribble_system.release_possession()
	var dur  := DURATION[SkillMove.MARSEILLE_TURN]
	var dir  := _get_spin_dir()
	var pivot := player.global_position

	SoundManager.roulette()
	ScreenShake.skill_move()

	var tween := player.create_tween()
	tween.tween_property(
		player.get_node_or_null("FacingPivot") if player.has_node("FacingPivot") else player,
		"rotation:y",
		(player.get_node_or_null("FacingPivot").rotation.y if player.has_node("FacingPivot") else player.rotation.y) + dir * TAU,
		dur
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween = tween

	var orbit_tween := player.create_tween()
	orbit_tween.tween_method(_orbit_ball.bind(dir, pivot, dur), 0.0, 1.0, dur)

func _get_spin_dir() -> float:
	if player.get_meta("is_human", false):
		var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		return signf(stick.x) if stick.length() > 0.3 else 1.0
	return 1.0 if randf() > 0.5 else -1.0

func _orbit_ball(t: float, dir: float, pivot: Vector3, _dur: float) -> void:
	if ball_physics == null: return
	var angle   := t * dir * TAU
	const ORB   := 0.60
	var desired := pivot + Vector3(sin(angle) * ORB, 0.11, cos(angle) * ORB)
	var diff: Vector3 = desired - ball_physics.ball_position   # ← Explicit type
	ball_physics.velocity = diff * 22.0
	ball_physics.wake()

# ──────────────────────────────────────────────────────────────
func _exec_croquette() -> void:
	if ball_physics == null or player == null: return
	dribble_system.release_possession()
	var side_dir: Vector3 = player.transform.basis.x * _croquette_side()
	var dur := DURATION[SkillMove.CROQUETTE]

	var tween := player.create_tween()
	tween.tween_method(_croquette_curve.bind(side_dir, player.global_position), 0.0, 1.0, dur)
	_active_tween = tween

func _croquette_side() -> float:
	if player.get_meta("is_human", false):
		var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		return signf(stick.x) if stick.length() > 0.3 else 1.0
	return 1.0 if randf() > 0.5 else -1.0

func _croquette_curve(t: float, side_dir: Vector3, pivot: Vector3) -> void:
	if ball_physics == null: return
	var desired: Vector3
	var fwd := -player.transform.basis.z
	if t < 0.40:
		var p := t / 0.40
		desired = pivot + fwd * 0.3 + side_dir * lerp(0.0, 0.7, p)
	elif t < 0.70:
		desired = pivot + side_dir * 0.7 + fwd * 0.1
	else:
		var p := (t - 0.70) / 0.30
		desired = pivot + side_dir * lerp(0.7, 0.0, p) + fwd * lerp(0.1, 0.35, p)

	var diff: Vector3 = desired - ball_physics.ball_position   # ← Explicit type
	diff.y = 0.0
	ball_physics.velocity = diff * 18.0
	ball_physics.wake()

# ──────────────────────────────────────────────────────────────
# (Rest of the file remains unchanged)
# ──────────────────────────────────────────────────────────────

func _exec_ox_tail() -> void:
	if ball_physics == null or dribble_system == null: return
	dribble_system.release_possession()
	var back := player.transform.basis.z
	var noise := Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	ball_physics.apply_impulse(back * 3.5 + Vector3(0.0, 4.0, 0.0) + noise, Vector3.ZERO)
	SoundManager.heel_flick()
	ScreenShake.skill_move()

func _exec_rainbow_over() -> void:
	if ball_physics == null: return
	dribble_system.release_possession()
	var fwd := -player.transform.basis.z
	ball_physics.apply_impulse(fwd * 5.0 + Vector3(0.0, 9.5, 0.0), Vector3(randf_range(-1.5, 1.5), 0.0, 0.0))
	SoundManager.flick_up()
	ScreenShake.skill_move()

func _exec_all_out_shooting() -> void:
	player.set_meta("skill_shot_boost", 1.30)
	ScreenShake.light()
	var clear_timer := player.get_tree().create_timer(2.0, false)
	clear_timer.timeout.connect(func(): 
		if player.has_meta("skill_shot_boost"):
			player.remove_meta("skill_shot_boost")
	)

func _exec_virtual_pro_ball() -> void:
	if ball_physics == null or dribble_system == null: return
	if not ball_physics.on_ground:
		_complete_skill(false)
		return
	var s: PlayerStats = player.get("stats") as PlayerStats
	var lift: float = 4.0 + (s.agility / 99.0 * 0.5 if s != null else 0.25)
	var dir := _get_flick_input_dir()
	ball_physics.apply_impulse(Vector3(dir.x * 2.5, lift, dir.z * 2.5), Vector3.ZERO)
	ball_physics.on_ground = false
	dribble_system.release_possession()
	SoundManager.flick_up()
	ScreenShake.skill_move()

func _get_flick_input_dir() -> Vector3:
	if player.get_meta("is_human", false):
		var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if raw.length() > 0.3:
			return Vector3(raw.x, 0.0, -raw.y).normalized()
	return -player.transform.basis.z

func _exec_stepover_skill(final_dir: float) -> void:
	var side := player.transform.basis.x * signf(final_dir)
	player.velocity += side * 3.5
	ScreenShake.skill_move()

# ─────────────────────────────────────────────────────────────
# HUMAN INPUT + AI HELPERS (unchanged)
# ─────────────────────────────────────────────────────────────

func track_roulette_input(stick: Vector2, close_control_held: bool) -> void:
	if not close_control_held or not _check_tier_for(SkillMove.MARSEILLE_TURN):
		_roulette_total_rot = 0.0
		return
	if current_skill != SkillMove.NONE: return

	var angle := atan2(stick.y, stick.x)
	var da := angle_difference(_prev_stick_angle, angle)
	_prev_stick_angle = angle

	if stick.length() > 0.5:
		_roulette_total_rot += da
		_roulette_timer += get_physics_process_delta_time()
	else:
		_roulette_timer = 0.0
		_roulette_total_rot = 0.0

	if absf(_roulette_total_rot) >= ROULETTE_ANGLE and _roulette_timer <= ROULETTE_WINDOW:
		_roulette_total_rot = 0.0
		try_skill(SkillMove.MARSEILLE_TURN)

func track_stepover_input(stick: Vector2) -> void:
	if not _check_tier_for(SkillMove.STEPOVER) or current_skill != SkillMove.NONE: return
	if player.get_speed() > 5.0 or stick.length() < STEPOVER_MIN_MAG: return

	_stepover_flicks.append(signf(stick.x))
	_stepover_timer = STEPOVER_WINDOW

	if _stepover_flicks.size() >= 2:
		var last := _stepover_flicks[-1]
		var prev := _stepover_flicks[-2]
		if last != prev:
			_stepover_flicks.clear()
			try_skill(SkillMove.STEPOVER)

const SHOOT_DOUBLE_TAP := 0.30

func register_shoot_tap() -> bool:
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_shoot_time < SHOOT_DOUBLE_TAP:
		if try_wall_rebound():
			return true
	_last_shoot_time = now
	return false

## Universal skill: chip off the cage wall, then volley on the return.
func try_wall_rebound() -> bool:
	if not dribble_system.in_possession:
		return false
	return try_skill(SkillMove.WALL_REBOUND)

func _exec_wall_rebound() -> void:
	if ball_physics == null or player == null or dribble_system == null:
		return
	dribble_system.release_possession()
	var wall_dir := _wall_rebound_direction()
	var up_strength := 11.5
	var into_wall := 8.5
	var impulse := (wall_dir * into_wall + Vector3.UP * up_strength).normalized() * 14.5
	ball_physics.apply_impulse(impulse, Vector3(randf_range(-1.0, 1.0), 0.0, 0.0))
	player.set_meta("wall_volley_ready", true)
	player.set_meta("wall_volley_until", Time.get_ticks_msec() + 2800)
	SoundManager.flick_up()
	ScreenShake.light()
	TeamStyleMeter.add_style(int(player.team_id), 4.0)

func _wall_rebound_direction() -> Vector3:
	var pos := player.global_position
	var hx := PitchConstants.PLAY_HALF_X
	var hz := PitchConstants.PLAY_HALF_Z
	var to_left := Vector3(-1.0, 0.0, 0.0)
	var to_right := Vector3(1.0, 0.0, 0.0)
	var to_near_z := Vector3(0.0, 0.0, signf(pos.z)) if absf(pos.z) > 0.5 else Vector3.ZERO
	var to_far_z := -to_near_z
	var dist_l := hx - pos.x
	var dist_r := hx + pos.x
	var dist_nz := hz - absf(pos.z) if to_near_z.length_squared() > 0.01 else 999.0
	var best := to_left
	var best_d := dist_l
	if dist_r < best_d:
		best = to_right
		best_d = dist_r
	if to_near_z.length_squared() > 0.01 and dist_nz < best_d:
		best = to_near_z
	if player.has_method("get_facing_forward"):
		var fwd: Vector3 = player.get_facing_forward()
		if fwd.dot(best) < 0.2:
			best = (best + fwd * 0.45).normalized()
	return best.normalized()

func try_flick_up(input_dir: Vector3) -> bool:
	if input_dir.length() < 0.3 or player.get_speed() > 4.0: return false
	return try_skill(SkillMove.VIRTUAL_PRO_BALL)

func try_rainbow() -> bool:      return try_skill(SkillMove.RAINBOW_OVER)
func try_croquette() -> bool:    return try_skill(SkillMove.CROQUETTE)
func try_all_out_shooting() -> bool: return try_skill(SkillMove.ALL_OUT_SHOOTING)

# AI bridges
func ai_execute(skill: SkillMove) -> bool:
	var bd: BallerData = player.get("baller_data") as BallerData
	if bd != null and skill != SkillMove.NONE:
		if not bd.has_skill(int(skill)): return false
	return try_skill(skill)

# ... (rest of AI fallback methods unchanged)

func _tick_roulette(delta: float) -> void:
	if _roulette_timer > 0.0:
		_roulette_timer -= delta
		if _roulette_timer <= 0.0:
			_roulette_total_rot = 0.0

func _track_stepover(delta: float) -> void:
	if _stepover_timer > 0.0:
		_stepover_timer -= delta
		if _stepover_timer <= 0.0:
			_stepover_flicks.clear()

func _check_tier_for(skill: SkillMove) -> bool:
	if player == null: return false
	var min_r: float = TIER.get(skill, 0.0)
	if min_r <= 0.0: return true
	var s: PlayerStats = player.get("stats") as PlayerStats
	var rating: float = s.get_skill_rating() if s != null else player.player_rating
	return rating >= min_r

func _has_stamina_for(skill: SkillMove) -> bool:
	var cost: float = STAMINA_COST.get(skill, 0.0)
	if cost <= 0.0: return true
	if not "stamina" in player: return true
	return player.stamina >= cost

func _skill_name(skill: SkillMove) -> String:
	match skill:
		SkillMove.WALL_REBOUND:     return "wall_rebound"
		SkillMove.ALL_OUT_SHOOTING: return "all_out_shooting"
		SkillMove.CROQUETTE:        return "croquette"
		SkillMove.MARSEILLE_TURN:   return "marseille_turn"
		SkillMove.OX_TAIL:          return "ox_tail"
		SkillMove.RAINBOW_OVER:     return "rainbow_over"
		SkillMove.VIRTUAL_PRO_BALL: return "virtual_pro_ball"
		SkillMove.STEPOVER:         return "stepover"
		_: return "none"

func is_busy() -> bool:
	return current_skill != SkillMove.NONE
