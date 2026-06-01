extends Node3D

@export var follow_speed := 8.5
@export var follow_speed_vertical := 6.0
@export var pitch_angle := -39.0  # raised 4 for narrower pitch - better depth perception
@export var min_height := 12.0
@export var max_height := 22.0
@export var side_offset := 16.0
@export var depth_offset := 9.0
@export var dynamic_zoom := true

@onready var camera := $Camera3D

var _ball: Node3D = null
var _look_target := Vector3.ZERO
var _depth_sign := 1.0  # +Z offset from ball; flipped from human attack direction

func _ready() -> void:
	if camera:
		ScreenShake.register_camera(camera)
	var ball_node := get_parent().get_node_or_null("Ball") as Node3D
	if ball_node:
		set_ball(ball_node)

func set_ball(ball: Node3D) -> void:
	_ball = ball
	if _ball:
		_snap_to_ball()

## Place the rig behind the human's attack direction so stick-up runs toward goal.
func set_human_team(team_id: int) -> void:
	var attack_z := PitchConstants.attack_goal_z(team_id)
	_depth_sign = -signf(attack_z) if absf(attack_z) > 0.01 else 1.0

func _depth_vec() -> Vector3:
	return Vector3(0.0, 0.0, depth_offset * _depth_sign)

func _snap_to_ball() -> void:
	var ball_h := _ball_height()
	var h := lerpf(min_height, max_height, clampf(ball_h / 8.0, 0.0, 1.0))
	global_position = _ball.global_position + Vector3(side_offset, h, 0.0) + _depth_vec()
	_look_target = _ball.global_position + Vector3(0.0, 1.5, 0.0)
	look_at(_look_target, Vector3.UP)
	_update_fov(ball_h)

func _process(delta: float) -> void:
	if _ball == null:
		return

	var ball_h := _ball_height()
	var target_h := lerpf(min_height, max_height, clampf(ball_h / 8.0, 0.0, 1.0))
	var target_pos := _ball.global_position + Vector3(side_offset, target_h, 0.0) + _depth_vec()
	var cur := global_position
	cur.x = lerpf(cur.x, target_pos.x, follow_speed * delta)
	cur.z = lerpf(cur.z, target_pos.z, follow_speed * delta)
	cur.y = lerpf(cur.y, target_pos.y, follow_speed_vertical * delta)
	global_position = cur
	ScreenShake.update_base(Vector3.ZERO)

	var vel := _ball_velocity()
	var ahead := 4.0 * signf(vel.z) if absf(vel.z) > 0.5 else 0.0
	_look_target = _look_target.lerp(
		_ball.global_position + Vector3(0.0, 1.5, ahead),
		6.0 * delta
	)
	look_at(_look_target, Vector3.UP)
	_update_fov(ball_h)

func _ball_height() -> float:
	if _ball.has_method("get") and _ball.get("ball_position"):
		return (_ball.get("ball_position") as Vector3).y
	return _ball.global_position.y

func _ball_velocity() -> Vector3:
	if _ball.get("velocity"):
		return _ball.get("velocity") as Vector3
	return Vector3.ZERO

func _update_fov(ball_h: float) -> void:
	if not camera or not dynamic_zoom:
		return
	camera.fov = lerpf(52.0, 68.0, clampf(ball_h / 10.0, 0.0, 1.0))

func get_camera() -> Camera3D:
	return camera

func get_shadow_camera() -> Camera3D:
	return camera
