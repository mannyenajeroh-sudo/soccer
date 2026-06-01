extends Node

# ============================================================
#  JuggleSystem.gd — tap Pass to chain foot / chest / head
#  Light quick taps = tight low keepy-ups (easier to steal)
# ============================================================

enum TouchType { FOOT, CHEST, HEAD }

signal juggle_updated(count: int)
signal juggle_started
signal juggle_ended(cause: String)
signal touch_performed(touch_type: int)

const SHOOT_DOUBLE_TAP := 0.30
const TOUCH_COOLDOWN   := 0.14
const CHAIN_TIMEOUT    := 1.25
const COMBO_DECAY      := 3.5
const REACH_DIST       := 2.35
const START_DIST       := 1.85
const ANCHOR_STRENGTH  := 16.0
const DRIFT_DAMP       := 11.0

@export var player: CharacterBody3D
@export var ball_physics: BallPhysics
@export var dribble_system: Node
@export var aerial: Node

var is_active := false
var touch_count := 0

var _next_touch := TouchType.FOOT
var _last_touch_time := -10.0
var _last_shoot_time := -10.0
var _chain_timer := 0.0
var _combo_decay := 0.0
var _drop_timer := 0.0
var _last_tap_strength := 0.75

const TOUCH_TARGET := {
	TouchType.FOOT:  Vector3(0.30, 0.98, 0.0),
	TouchType.CHEST: Vector3(0.24, 1.34, 0.0),
	TouchType.HEAD:  Vector3(0.16, 1.68, 0.0),
}

const TOUCH_HEIGHT := {
	TouchType.FOOT:  Vector2(0.35, 1.32),
	TouchType.CHEST: Vector2(0.72, 1.58),
	TouchType.HEAD:  Vector2(1.02, 2.2),
}

func _ready() -> void:
	add_to_group("juggle_systems")
	if ball_physics == null and player != null:
		ball_physics = player.get_node_or_null("../../BallPhysics") as BallPhysics
	if aerial == null and player != null:
		aerial = player.get_node_or_null("AerialMechanics")

func _physics_process(delta: float) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		if is_active:
			end_juggle("phase", true)
		return

	if not is_active:
		if touch_count > 0:
			_combo_decay -= delta
			if _combo_decay <= 0.0:
				_reset_combo()
		return

	_chain_timer -= delta
	if _chain_timer <= 0.0:
		end_juggle("timeout", false)
		return

	_apply_juggle_anchor(delta)

	if _ball_in_reach():
		_drop_timer = 0.0
	else:
		_drop_timer += delta
		if _drop_timer > 0.38:
			end_juggle("lost", false)

## While juggling: Pass chains the next touch (foot / chest / head).
func register_pass_tap() -> void:
	if not is_active:
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_touch_time < TOUCH_COOLDOWN:
		return
	var gap: float = now - _last_touch_time
	_last_tap_strength = clampf(gap / 0.34, 0.32, 1.0)
	if not _perform_touch():
		end_juggle("miss", false)

func try_start_juggle() -> bool:
	return _try_start_juggle()

func register_shoot_tap() -> bool:
	if not is_active:
		return false
	var now := Time.get_ticks_msec() * 0.001
	if now - _last_shoot_time < SHOOT_DOUBLE_TAP:
		_launch_wall_rebound()
		end_juggle("wall", false)
		return true
	_last_shoot_time = now
	return false

func try_finish_volley(aim_dir: Vector3) -> bool:
	if ball_physics == null or aerial == null:
		return false
	if not is_active and touch_count < 1:
		return false
	var bp: Vector3 = ball_physics.ball_position
	if bp.y < 0.42 or player.global_position.distance_to(bp) > REACH_DIST + 0.55:
		return false

	var fired := false
	if touch_count >= 3 and aerial.has_method("try_power_volley"):
		fired = aerial.try_power_volley(aim_dir)
	if not fired and aerial.has_method("try_volley"):
		fired = aerial.try_volley(aim_dir)
	if fired:
		end_juggle("volley", true)
		return true
	return false

func is_vulnerable() -> bool:
	return is_active

func get_combo() -> int:
	return touch_count

func _apply_juggle_anchor(delta: float) -> void:
	if player == null or ball_physics == null:
		return
	var fwd := _player_forward()
	var anchor: Vector3 = player.global_position + fwd * 0.28 + Vector3(0.0, 1.02 + _last_tap_strength * 0.12, 0.0)
	var pos: Vector3 = ball_physics.ball_position
	var pull: Vector3 = anchor - pos
	pull.y *= 0.35
	var damp: Vector3 = Vector3(ball_physics.velocity.x, 0.0, ball_physics.velocity.z)
	var strength: float = ANCHOR_STRENGTH * lerpf(0.55, 1.0, _last_tap_strength)
	ball_physics.velocity += pull * strength * delta - damp * DRIFT_DAMP * delta * 0.35
	var max_h: float = lerpf(1.25, 1.85, _last_tap_strength)
	if pos.y > max_h and ball_physics.velocity.y > 0.0:
		ball_physics.velocity.y *= 0.82

func _try_start_juggle() -> bool:
	if player == null or ball_physics == null:
		return false
	if not _can_start():
		return false

	if dribble_system != null and dribble_system.in_possession:
		dribble_system.release_possession()
	elif not _ball_near_player(START_DIST):
		return false

	is_active = true
	_next_touch = TouchType.FOOT
	_chain_timer = CHAIN_TIMEOUT
	_drop_timer = 0.0
	_last_touch_time = Time.get_ticks_msec() * 0.001
	_last_tap_strength = 0.72

	if aerial != null and aerial.has_method("start_juggle"):
		aerial.start_juggle()
	else:
		touch_count = 0
		juggle_updated.emit(0)

	_apply_touch_impulse(TouchType.FOOT, true)
	_advance_touch_cycle()
	_sync_aerial_count()
	juggle_started.emit()
	TeamStyleMeter.add_style(int(player.team_id), 3.0)
	return true

func _perform_touch() -> bool:
	if player == null or ball_physics == null:
		return false
	var bp: Vector3 = ball_physics.ball_position
	var h_range: Vector2 = TOUCH_HEIGHT[_next_touch]
	var dist: float = player.global_position.distance_to(bp)

	if dist > REACH_DIST or bp.y < h_range.x - 0.4 or bp.y > h_range.y + 0.45:
		return false

	var performed := _next_touch
	_apply_touch_impulse(performed, false)
	touch_performed.emit(performed)
	_advance_touch_cycle()
	_chain_timer = CHAIN_TIMEOUT
	_last_touch_time = Time.get_ticks_msec() * 0.001
	_sync_aerial_count()
	juggle_updated.emit(touch_count)
	if aerial != null and aerial.has_method("juggle_tick"):
		aerial.juggle_tick()
	return true

func _apply_touch_impulse(touch: int, is_start: bool) -> void:
	var fwd := _player_forward()
	var local: Vector3 = TOUCH_TARGET[touch]
	var target: Vector3 = player.global_position + fwd * local.x + Vector3(0.0, local.y, 0.0)
	var pos: Vector3 = ball_physics.ball_position
	var to_target: Vector3 = target - pos
	var strength: float = _last_tap_strength if not is_start else 0.72

	var up_boost: float
	var horizontal: float
	match touch:
		TouchType.FOOT:
			up_boost = lerpf(3.2, 4.8, strength)
			horizontal = lerpf(1.0, 2.8, strength)
		TouchType.CHEST:
			up_boost = lerpf(3.5, 4.6, strength)
			horizontal = lerpf(0.8, 2.2, strength)
		TouchType.HEAD:
			up_boost = lerpf(3.2, 4.2, strength)
			horizontal = lerpf(0.5, 1.6, strength)

	if is_start:
		up_boost *= 1.08

	to_target.y = 0.0
	var impulse := Vector3.ZERO
	if to_target.length_squared() > 0.02:
		impulse += to_target.normalized() * horizontal
	impulse.y = up_boost

	ball_physics.wake()
	ball_physics.velocity *= lerpf(0.08, 0.22, strength)
	if ball_physics.has_method("apply_kick_impulse"):
		ball_physics.apply_kick_impulse(impulse, Vector3(randf_range(-0.35, 0.35), 0.0, 0.0) * strength, 0.85 + strength * 0.2)
	else:
		ball_physics.apply_impulse(impulse, Vector3.ZERO)

	if player != null and "team_id" in player:
		PossessionManager.register_touch(int(player.team_id))

	player.set_meta("last_juggle_touch", touch)
	VisualEffects.skill_ring(player.global_position, _touch_color(touch))
	SoundManager.bounce(3.0 + strength * 4.0, pos)
	var td: Node = get_node_or_null("/root/TimeDilation")
	if td and td.has_method("on_juggle_touch"):
		td.on_juggle_touch()

func _advance_touch_cycle() -> void:
	touch_count += 1
	_next_touch = (touch_count % 3) as TouchType

func _sync_aerial_count() -> void:
	if aerial != null:
		aerial.juggle_count = touch_count

func end_juggle(cause: String, reset_combo: bool) -> void:
	if not is_active and not reset_combo:
		return
	is_active = false
	_drop_timer = 0.0
	juggle_ended.emit(cause)
	if reset_combo:
		_reset_combo()
	else:
		_combo_decay = COMBO_DECAY

func _reset_combo() -> void:
	touch_count = 0
	if aerial != null:
		aerial.juggle_count = 0
	juggle_updated.emit(0)

func _can_start() -> bool:
	if dribble_system != null and dribble_system.in_possession:
		return true
	return _ball_near_player(START_DIST)

func _ball_near_player(max_dist: float) -> bool:
	if player == null or ball_physics == null:
		return false
	var bp: Vector3 = ball_physics.ball_position
	if bp.y > 2.4:
		return false
	return player.global_position.distance_to(bp) <= max_dist

func _ball_in_reach() -> bool:
	return _ball_near_player(REACH_DIST) and ball_physics.ball_position.y > 0.22

func _player_forward() -> Vector3:
	if player != null and player.has_method("get_facing_forward"):
		return player.get_facing_forward()
	var f: Vector3 = -player.transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)

func _player_right() -> Vector3:
	if player != null and player.has_method("get_facing_right"):
		return player.get_facing_right()
	var r: Vector3 = player.transform.basis.x
	r.y = 0.0
	return r.normalized() if r.length_squared() > 0.01 else Vector3.RIGHT

func _touch_color(touch: int) -> Color:
	match touch:
		TouchType.CHEST: return Color(0.2, 0.85, 1.0)
		TouchType.HEAD:  return Color(1.0, 0.85, 0.2)
		_:             return Color(0.4, 1.0, 0.5)

func _launch_wall_rebound() -> void:
	if ball_physics == null or player == null:
		return
	var wall_dir := _pick_wall_direction()
	var impulse := (wall_dir * 8.0 + Vector3.UP * 11.0).normalized() * 14.0
	if ball_physics.has_method("apply_kick_impulse"):
		ball_physics.apply_kick_impulse(impulse, Vector3(randf_range(-0.8, 0.8), 0.0, 0.0), 1.0)
	else:
		ball_physics.apply_impulse(impulse, Vector3.ZERO)
	player.set_meta("wall_volley_ready", true)
	player.set_meta("wall_volley_until", Time.get_ticks_msec() + 2800)
	SoundManager.flick_up()
	ScreenShake.light()
	if "team_id" in player:
		PossessionManager.register_touch(int(player.team_id))
		TeamStyleMeter.add_style(int(player.team_id), 4.0)

func _pick_wall_direction() -> Vector3:
	var pos := player.global_position
	var hx := PitchConstants.PLAY_HALF_X
	var hz := PitchConstants.PLAY_HALF_Z
	var best := Vector3(-1.0, 0.0, 0.0)
	var best_d := hx - pos.x
	var d_r := hx + pos.x
	if d_r < best_d:
		best = Vector3(1.0, 0.0, 0.0)
		best_d = d_r
	if absf(pos.z) > 0.4:
		var nz := hz - absf(pos.z)
		if nz < best_d:
			best = Vector3(0.0, 0.0, signf(pos.z))
	var fwd := _player_forward()
	if fwd.dot(best) < 0.15:
		best = (best + fwd * 0.5).normalized()
	return best.normalized()
