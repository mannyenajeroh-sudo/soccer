extends MeshInstance3D

# ============================================================
#  BallShadow.gd — IMPROVED: trajectory prediction arc
#  Shadow scales + alpha by height. Arc shows when ball is airborne.
# ============================================================

@export var ball: Node3D
@export var max_height := 8.0
@export var min_scale  := 0.15

var _mat: StandardMaterial3D

# Trajectory prediction line
var _traj_mesh: MeshInstance3D = null
var _traj_mat: StandardMaterial3D = null

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.6)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.no_depth_test = false
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_mat.render_priority = 1
	material_override = _mat

	# Create trajectory prediction mesh
	_traj_mesh = MeshInstance3D.new()
	_traj_mat = StandardMaterial3D.new()
	_traj_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	_traj_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	_traj_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_traj_mat.no_depth_test = false
	_traj_mat.render_priority = 2
	_traj_mesh.material_override = _traj_mat
	add_child(_traj_mesh)

func _process(_delta: float) -> void:
	if ball == null:
		return
	# Shadow position on ground
	global_position = Vector3(ball.global_position.x, 0.005, ball.global_position.z)
	var h := maxf(ball.global_position.y - 0.11, 0.0)
	var s := clampf(1.0 - h / max_height, min_scale, 1.0)
	scale = Vector3(s, 1.0, s)
	_mat.albedo_color.a = s * 0.6

	# Trajectory prediction when ball is airborne and moving fast
	if ball.has_method("get") and ball.get("velocity") != null:
		var vel: Vector3 = ball.get("velocity") as Vector3
		var ball_h := ball.global_position.y
		if ball_h > 0.3 and vel.length() > 5.0:
			_draw_landing_prediction(ball.global_position, vel)
		else:
			_traj_mesh.mesh = null

func _draw_landing_prediction(start_pos: Vector3, vel: Vector3) -> void:
	# Simulate a few steps to find landing point
	const STEPS := 30
	const DT := 1.0 / 60.0
	const GRAVITY := 9.81
	var pos := start_pos
	var v := vel
	var pts := PackedVector3Array()
	pts.append(pos)
	for _i in STEPS:
		v.y -= GRAVITY * DT
		pos += v * DT
		pts.append(pos)
		if pos.y <= 0.11:
			break
	if pts.size() < 2:
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(pts.size() - 1):
		var t := float(i) / float(pts.size())
		im.surface_set_color(Color(1.0, 1.0, 1.0, (1.0 - t) * 0.5))
		im.surface_add_vertex(pts[i])
		im.surface_set_color(Color(1.0, 1.0, 1.0, (1.0 - (t + 1.0/pts.size())) * 0.5))
		im.surface_add_vertex(pts[i + 1])
	im.surface_end()
	_traj_mesh.mesh = im
