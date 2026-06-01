extends Node

# ============================================================
#  AerialMechanics.gd — Headers, volleys, bicycle kicks
# ============================================================

@export var player : CharacterBody3D
@export var ball_physics : BallPhysics
@export var goal_pos : Vector3 = Vector3.ZERO

signal juggle_updated(count: int)

var juggle_count : int = 0
const JUGGLE_COMBO := 3

const KEEPER_HAND_NORMAL := Vector3(0.0, 0.3, 1.0)
const KEEPER_REFLECT_FACTOR := 0.6
const SPIN_PRESERVE_FACTOR := 0.8
const VOLLEY_REACH := 2.75

func _ready() -> void:
	if ball_physics == null:
		ball_physics = get_node_or_null("../../BallPhysics")

func _ball_in_volley_range() -> bool:
	if player == null or ball_physics == null:
		return false
	var bp_pos: Vector3 = ball_physics.ball_position
	var to_ball: Vector3 = bp_pos - player.global_position
	to_ball.y = 0.0
	if to_ball.length() > VOLLEY_REACH:
		return false
	return bp_pos.y >= 0.30 and bp_pos.y <= 2.45

func try_header(aim_dir: Vector3) -> bool:
	var bp_pos : Vector3 = ball_physics.ball_position as Vector3
	if bp_pos.y < 0.9 or bp_pos.y > 2.2:
		return false
	var to_ball: Vector3 = bp_pos - player.global_position
	to_ball.y = 0.0
	if to_ball.length() > VOLLEY_REACH:
		return false
	PossessionManager.force_release()
	var power := 18.0
	ball_physics.wake()
	ball_physics.apply_impulse(aim_dir.normalized() * power, Vector3.ZERO)
	GameState.set_meta("pending_shot", {"shot_type": "header", "speed": power, "charge": 0.7, "player_id": player.get_instance_id() if player else -1})
	SoundManager.kick(power, bp_pos)
	ScreenShake.medium()
	return true

func try_volley(aim_dir: Vector3) -> bool:
	if not _ball_in_volley_range():
		return false
	var kick_sys: Node = player.get_node_or_null("KickSystem") if player else null
	if kick_sys != null and kick_sys.has_method("volley_shot"):
		return kick_sys.volley_shot(aim_dir)
	var bp_pos: Vector3 = ball_physics.ball_position
	PossessionManager.force_release()
	ball_physics.wake()
	var contact_q := contact_quality_override(aim_dir)
	var power: float = lerp(17.0, 23.5, contact_q)
	ball_physics.apply_impulse(aim_dir.normalized() * power, Vector3.ZERO)
	GameState.set_meta("pending_shot", {"shot_type": "volley", "speed": power, "charge": 0.85, "player_id": player.get_instance_id() if player else -1})
	SoundManager.kick(power, bp_pos)
	ScreenShake.shot()
	return true

func try_power_volley(aim_dir: Vector3) -> bool:
	if juggle_count < JUGGLE_COMBO:
		return false
	if not _ball_in_volley_range():
		return false
	var kick_sys: Node = player.get_node_or_null("KickSystem") if player else null
	if kick_sys != null and kick_sys.has_method("volley_shot"):
		juggle_count = 0
		juggle_updated.emit(0)
		return kick_sys.volley_shot(aim_dir)
	var bp_pos : Vector3 = ball_physics.ball_position
	var base_q : float = clampf(contact_quality_override(aim_dir) + 0.20, 0.15, 1.0)
	var speed  : float = lerp(24.0, 30.0, base_q)
	PossessionManager.force_release()
	ball_physics.wake()
	ball_physics.apply_impulse(aim_dir.normalized() * speed, Vector3.ZERO)
	juggle_count = 0
	juggle_updated.emit(0)
	SoundManager.kick(speed, bp_pos)
	ScreenShake.power_shot()
	return true

func try_bicycle_kick(aim_dir: Vector3) -> bool:
	var bp_pos : Vector3 = ball_physics.ball_position as Vector3
	if bp_pos.y < 1.0 or bp_pos.y > 2.5:
		return false
	var to_ball: Vector3 = bp_pos - player.global_position
	to_ball.y = 0.0
	if to_ball.length() > 3.0:
		return false
	PossessionManager.force_release()
	ball_physics.wake()
	var power := 28.0
	ball_physics.apply_impulse(aim_dir.normalized() * power, Vector3.ZERO)
	GameState.set_meta("pending_shot", {"shot_type": "bicycle", "speed": power, "charge": 1.0, "player_id": player.get_instance_id() if player else -1})
	ScreenShake.bicycle()
	var td : Node = get_node_or_null("/root/TimeDilation")
	if td:
		td.slow(0.65, 0.6)
	SoundManager.kick(power, bp_pos)
	return true

func goalkeeper_deflect(shot_speed: float, angle_quality: float) -> void:
	var save_chance := clampf(1.0 - (shot_speed / 30.0) * (1.0 - angle_quality), 0.2, 0.9)
	if randf() < save_chance:
		var hand_normal := KEEPER_HAND_NORMAL.normalized()
		var reflected := ball_physics.velocity.bounce(hand_normal) * KEEPER_REFLECT_FACTOR
		ball_physics.velocity = reflected
		ball_physics.angular_velocity *= SPIN_PRESERVE_FACTOR
		SoundManager.bounce(shot_speed * 0.5, ball_physics.global_position)

func start_juggle() -> void:
	juggle_count = 0
	juggle_updated.emit(0)

func juggle_tick() -> void:
	juggle_count += 1
	juggle_updated.emit(juggle_count)
	var td : Node = get_node_or_null("/root/TimeDilation")
	if td:
		td.on_juggle_touch()

func contact_quality_override(kick_dir: Vector3) -> float:
	if player == null:
		return 0.5
	var fwd: Vector3 = player.get_facing_forward() if player.has_method("get_facing_forward") else -player.transform.basis.z
	var align : float   = clampf(fwd.dot(kick_dir.normalized()), 0.0, 1.0)
	return align

func handle_aerial_input(aim_dir: Vector3, input_type: String) -> bool:
	match input_type:
		"header":
			return try_header(aim_dir)
		"volley":
			return try_volley(aim_dir)
		"power_volley":
			return try_power_volley(aim_dir)
		"bicycle":
			return try_bicycle_kick(aim_dir)
	return false
