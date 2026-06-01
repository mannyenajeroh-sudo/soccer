extends Node

# ============================================================
#  DribbleSystem.gd — STREET 3 ELITE
#  Ball sits in front of the carrier (FacingPivot aim) and is
#  pushed with movement — not dragged behind the capsule.
# ============================================================

const SPRING          := 18.0
const DAMPER          := 4.6
const DIST            := 0.44    # In front of feet (attack direction)
const DIST_CLOSE      := 0.30
const MAX_LEASH       := 0.50
const NOISE_AMP       := 0.004
const PICKUP_RADIUS   := 0.72
const PICKUP_HYSTERESIS := 0.05
const FAST_BALL_PICKUP_RADIUS := 0.36
const FAST_BALL_MAX_SPEED := 13.5
const BALL_MASS       := 0.34

const FOOT_SIDE_AMP   := 0.07
const FOOT_SIDE_FREQ  := 2.0

const DIST_SPRINT_ADD := 0.05
const MAX_SPEED_REF   := 8.2

const TURN_BOBBLE_THRESHOLD := 0.35
const TURN_BOBBLE_SPRING    := 0.40
const TURN_BOBBLE_DURATION  := 0.18

const SNAP_FRAMES       := 5
const PENETRATION_PUSH  := 2.4
const MAGNET_IMPULSE := 2.2

# Push dribble: match carrier horizontal speed so the ball rolls with you.
const PUSH_VEL_BLEND    := 18.0
const PUSH_LEAD_TIME    := 0.15

@export var player: CharacterBody3D
@export var ball_physics: Node

var in_possession   := false
var is_sprinting    := false
var close_control   := false

var _prev_move_dir  := Vector3.ZERO
var _bobble_timer   := 0.0
var _snap_counter   := 0
var _foot_phase     := 0.0
var _pickup_lock_until := 0

func _ready() -> void:
	if player:
		if player.has_signal("sprint_state_changed"):
			player.sprint_state_changed.connect(_on_sprint_changed)
		if player.has_signal("close_control_toggled"):
			player.close_control_toggled.connect(_on_close_control)

func _physics_process(delta: float) -> void:
	if _bobble_timer > 0.0:
		_bobble_timer -= delta
	_update_foot_phase(delta)
	if GameState.phase != GameState.Phase.PLAY:
		return
	if not in_possession or ball_physics == null or player == null:
		return
	_apply_spring(delta)

func _player_forward() -> Vector3:
	if player.has_method("get_facing_forward"):
		return player.get_facing_forward()
	var fwd := -player.transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)

func _player_right() -> Vector3:
	if player.has_method("get_facing_right"):
		return player.get_facing_right()
	var rgt := player.transform.basis.x
	rgt.y = 0.0
	return rgt.normalized() if rgt.length_squared() > 0.01 else Vector3.RIGHT

func _update_foot_phase(delta: float) -> void:
	var spd := player.velocity.length()
	if spd > 0.3:
		_foot_phase = fmod(_foot_phase + delta * FOOT_SIDE_FREQ * (spd / MAX_SPEED_REF), 1.0)

func _apply_spring(delta: float) -> void:
	var bp_pos: Vector3 = ball_physics.ball_position
	var bp_vel: Vector3 = ball_physics.velocity
	var player_pos     := player.global_position
	var player_hvel    := Vector3(player.velocity.x, 0.0, player.velocity.z)

	var fwd: Vector3 = _player_forward()
	var rgt: Vector3 = _player_right()

	var eff_dist := DIST_CLOSE if close_control else DIST
	var spd := player_hvel.length()
	eff_dist += DIST_SPRINT_ADD * clampf(spd / MAX_SPEED_REF, 0.0, 1.0)

	var side_swing: float = sin(_foot_phase * TAU) * FOOT_SIDE_AMP * clampf(spd / 4.0, 0.0, 1.0)

	var noise := Vector3(
		randf_range(-NOISE_AMP, NOISE_AMP),
		0.0,
		randf_range(-NOISE_AMP, NOISE_AMP)
	)

	# Lead target slightly in movement direction so the ball stays ahead while running.
	var lead := player_hvel * PUSH_LEAD_TIME
	var target: Vector3 = player_pos + fwd * eff_dist + lead + rgt * side_swing + Vector3(0.0, 0.11, 0.0) + noise

	var eff_spring := SPRING
	if close_control:
		eff_spring *= 1.2

	var move_dir := player_hvel.normalized() if spd > 0.5 else _prev_move_dir
	if _prev_move_dir.length() > 0.1 and move_dir.length() > 0.1:
		var turn_dot := _prev_move_dir.dot(move_dir)
		if turn_dot < TURN_BOBBLE_THRESHOLD:
			_bobble_timer = TURN_BOBBLE_DURATION
			if player and "team_id" in player:
				TeamStyleMeter.register_dribble_turn(int(player.team_id))
	if move_dir.length() > 0.1:
		_prev_move_dir = move_dir
	if _bobble_timer > 0.0:
		eff_spring *= TURN_BOBBLE_SPRING

	if _snap_counter > 0:
		_snap_counter -= 1
		eff_spring = SPRING * 3.8

	var offset     := target - bp_pos
	var sep_2d     := Vector2(bp_pos.x - player_pos.x, bp_pos.z - player_pos.z).length()
	if sep_2d > MAX_LEASH:
		eff_spring = maxf(eff_spring, SPRING * 3.5)

	var F_spring   := offset * eff_spring
	var rel_vel    := bp_vel - player_hvel
	var F_damp     := -rel_vel * DAMPER
	var accel      := (F_spring + F_damp) / BALL_MASS
	ball_physics.velocity = bp_vel + accel * delta

	# Push: blend ball horizontal velocity toward carrier (roll with feet, don't drag).
	if sep_2d < MAX_LEASH * 0.92:
		var push_vel := player_hvel + fwd * 0.35
		var blend := 1.0 - exp(-PUSH_VEL_BLEND * delta)
		var new_h := Vector2(bp_vel.x, bp_vel.z).lerp(Vector2(push_vel.x, push_vel.z), blend)
		ball_physics.velocity.x = new_h.x
		ball_physics.velocity.z = new_h.y

	var sep := bp_pos - player_pos
	sep.y = 0.0
	var sep_len := sep.length()
	if sep_len < 0.26 and sep_len > 0.001:
		# Nudge ball to the front arc if it slipped behind the capsule.
		var behind := fwd.dot(sep.normalized()) < -0.15
		var push_dir := fwd if behind else sep.normalized()
		ball_physics.velocity += push_dir * PENETRATION_PUSH

	ball_physics.wake()

func try_pickup(ball_pos: Vector3) -> bool:
	if player == null or ball_physics == null:
		return false
	if Time.get_ticks_msec() < _pickup_lock_until:
		return false
	var current := PossessionManager.get_possessor()
	if current != null and current != player:
		var steal_dist := PICKUP_RADIUS * 0.95
		if _carrier_is_juggling(current):
			steal_dist = PICKUP_RADIUS * 1.35
		if player.global_position.distance_to(ball_pos) >= steal_dist:
			return false
	var dist := player.global_position.distance_to(ball_pos)
	var ball_speed: float = ball_physics.velocity.length()
	if not in_possession and ball_speed > 7.5:
		if ball_speed > FAST_BALL_MAX_SPEED or dist > FAST_BALL_PICKUP_RADIUS:
			return false
	var threshold := (PICKUP_RADIUS + PICKUP_HYSTERESIS) if in_possession else PICKUP_RADIUS
	if dist < threshold:
		if not in_possession:
			in_possession = true
			_snap_counter = SNAP_FRAMES
			PossessionManager.claim(player)
			var ph := Vector3(player.velocity.x, 0.0, player.velocity.z)
			if dist > 0.25:
				var to_player: Vector3 = (player.global_position - ball_physics.global_position)
				to_player.y = 0.0
				if to_player.length_squared() > 0.01:
					ball_physics.velocity = ph + to_player.normalized() * MAGNET_IMPULSE
			elif ph.length_squared() > 0.04:
				ball_physics.velocity = ph + _player_forward() * 0.4
			ball_physics.wake()
		return true
	return false

func release_possession() -> void:
	in_possession = false
	_bobble_timer = 0.0
	_snap_counter = 0
	_pickup_lock_until = 0
	PossessionManager.release(player)

func release_for_pass() -> void:
	in_possession = false
	_bobble_timer = 0.0
	_snap_counter = 0
	_pickup_lock_until = Time.get_ticks_msec() + 380
	PossessionManager.release(player)

func release_for_shot(shot_speed: float) -> void:
	in_possession = false
	_bobble_timer = 0.0
	_snap_counter = 0
	var lock_ms: int = int(lerpf(180.0, 320.0, clampf(shot_speed / 22.0, 0.0, 1.0)))
	_pickup_lock_until = Time.get_ticks_msec() + lock_ms
	PossessionManager.release(player)

func _on_sprint_changed(sprinting: bool) -> void:
	is_sprinting = sprinting

func _on_close_control(active: bool) -> void:
	close_control = active

func get_foot_phase() -> float:
	return _foot_phase

func _carrier_is_juggling(carrier: Node) -> bool:
	var juggle := carrier.get_node_or_null("JuggleSystem")
	if juggle == null:
		return false
	return juggle.get("is_active") == true
