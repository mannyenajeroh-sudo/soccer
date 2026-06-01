extends MeshInstance3D

# ============================================================
#  NetDeformer.gd — Realistic net indentation
#  Attach to a MeshInstance3D net mesh on each goal.
#  On ball impact → deform vertices near impact point,
#  spring back over 0.8-1.2s.
#  Also handles post/crossbar hit detection for near-miss gasp.
# ============================================================

const DEFORM_RADIUS     := 2.5    # m — vertices within this get displaced
const DEFORM_MAX_DEPTH  := 0.55   # m — max indentation depth
const SPRING_DURATION   := 1.0    # s — return to rest
const NET_ABSORB        := 0.35   # velocity multiplier on net collision
const SPIN_ABSORB       := 0.6

# Net mesh is generated in _ready — a 12×8 grid of quads
const NET_W := 12   # horizontal segments (matches goal width ~7.32m)
const NET_H :=  8   # vertical segments (matches goal height ~2.44m)

@export var goal_half_width: float = 3.66
@export var goal_height:     float = 2.44
@export var net_depth:       float = 0.85   # how deep the net pocket goes
@export var ball_physics:    BallPhysics = null
@export var is_team_a:       bool = true    # which goal (for sign of Z offset)

signal net_hit(impact_point: Vector3)

var _rest_verts:   PackedVector3Array = PackedVector3Array()
var _curr_verts:   PackedVector3Array = PackedVector3Array()
var _vel_verts:    PackedVector3Array = PackedVector3Array()
var _arr_mesh:     ArrayMesh          = null
var _deforming:    bool               = false
var _spring_timer: float              = 0.0
var _impact_pt:    Vector3            = Vector3.ZERO

# Post/crossbar collision trackers
var _post_l_pos:  Vector3 = Vector3.ZERO
var _post_r_pos:  Vector3 = Vector3.ZERO
var _bar_y:       float   = 0.0
var _near_miss_cooldown: float = 0.0

func _ready() -> void:
	_generate_net_mesh()
	# Post/bar positions in world space set by MatchManager or from parent
	_post_l_pos = Vector3(-goal_half_width, goal_height * 0.5, 0.0)
	_post_r_pos = Vector3( goal_half_width, goal_height * 0.5, 0.0)
	_bar_y      = goal_height

func _generate_net_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cols: int = NET_W + 1
	var rows: int = NET_H + 1

	_rest_verts.clear()
	# Build vertex grid: x from -half_width to +half_width, y from 0 to height
	# z offset creates the pocket shape — deeper toward back
	for row in rows:
		for col in cols:
			var u: float = float(col) / float(NET_W)
			var v: float = float(row) / float(NET_H)
			var x: float = lerpf(-goal_half_width, goal_half_width, u)
			var y: float = lerpf(0.0, goal_height, v)
			# Parabolic pocket depth — deepest at center
			var pocket: float = net_depth * 4.0 * u * (1.0 - u) * v
			var z_sign: float = -1.0 if is_team_a else 1.0
			var z: float      = z_sign * pocket
			_rest_verts.append(Vector3(x, y, z))

	# Generate indices for quad grid
	for row in NET_H:
		for col in NET_W:
			var tl: int = row * cols + col
			var tr: int = tl + 1
			var bl: int = tl + cols
			var br: int = bl + 1
			# Two triangles per quad
			st.add_vertex(_rest_verts[tl])
			st.add_vertex(_rest_verts[bl])
			st.add_vertex(_rest_verts[tr])
			st.add_vertex(_rest_verts[tr])
			st.add_vertex(_rest_verts[bl])
			st.add_vertex(_rest_verts[br])

	st.generate_normals()
	_arr_mesh = st.commit()
	mesh = _arr_mesh

	_curr_verts = _rest_verts.duplicate()
	_vel_verts.resize(_rest_verts.size())
	for i in _vel_verts.size():
		_vel_verts[i] = Vector3.ZERO

	# Net material — semi-transparent white mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color        = Color(1.0, 1.0, 1.0, 0.55)
	mat.transparency        = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode        = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode           = BaseMaterial3D.CULL_DISABLED
	mat.render_priority     = 1
	material_override       = mat

func _physics_process(delta: float) -> void:
	if _near_miss_cooldown > 0.0:
		_near_miss_cooldown -= delta
	_check_ball_net_collision()
	if _deforming:
		_step_spring(delta)

func _check_ball_net_collision() -> void:
	if ball_physics == null or not is_instance_valid(ball_physics):
		return
	var bp: Vector3 = ball_physics.ball_position
	# Only check when ball is within goal mouth area
	var local_bp: Vector3 = to_local(bp)
	if absf(local_bp.x) > goal_half_width + 0.3:
		return
	if local_bp.y < -0.2 or local_bp.y > goal_height + 0.3:
		return

	# Check post hits
	if _near_miss_cooldown <= 0.0:
		_check_post_crossbar_hit(bp, local_bp)

	# Net impact — ball entering net pocket
	var z_sign: float = -1.0 if is_team_a else 1.0
	var net_front_z: float = 0.0  # front of net
	var net_back_z: float  = z_sign * net_depth

	var ball_crossed: bool = (is_team_a and local_bp.z < net_front_z and local_bp.z > net_back_z - 0.2) or \
							 (not is_team_a and local_bp.z > net_front_z and local_bp.z < net_back_z + 0.2)

	if ball_crossed and ball_physics.velocity.length() > 2.0:
		_on_ball_hit_net(bp, ball_physics.velocity)

func _on_ball_hit_net(world_impact: Vector3, vel: Vector3) -> void:
	var local_impact: Vector3 = to_local(world_impact)
	_impact_pt    = local_impact
	_deforming    = true
	_spring_timer = 0.0

	# Deform vertices near impact point
	var strength: float = clampf(vel.length() / 20.0, 0.1, 1.0) * DEFORM_MAX_DEPTH
	for i in _curr_verts.size():
		var v: Vector3 = _curr_verts[i]
		var dist: float = v.distance_to(local_impact)
		if dist < DEFORM_RADIUS:
			var push: float = strength * (1.0 - dist / DEFORM_RADIUS)
			var z_sign: float = -1.0 if is_team_a else 1.0
			_vel_verts[i] = Vector3(0.0, 0.0, z_sign * push * 12.0)  # impulse

	# Absorb ball velocity
	ball_physics.velocity   *= NET_ABSORB
	ball_physics.angular_velocity *= SPIN_ABSORB

	net_hit.emit(world_impact)
	SoundManager.bounce(vel.length() * 0.4, world_impact)
	_rebuild_mesh()

func _step_spring(delta: float) -> void:
	_spring_timer += delta
	var settled: bool = true
	for i in _curr_verts.size():
		var rest: Vector3  = _rest_verts[i]
		var curr: Vector3  = _curr_verts[i]
		var offset: Vector3 = rest - curr
		# Spring force toward rest
		var spring_f: Vector3 = offset * 18.0
		var damp_f: Vector3   = -_vel_verts[i] * 6.0
		_vel_verts[i] += (spring_f + damp_f) * delta
		_curr_verts[i] += _vel_verts[i] * delta
		if offset.length() > 0.005:
			settled = false
	if settled or _spring_timer > SPRING_DURATION * 1.5:
		# Fully reset
		for i in _curr_verts.size():
			_curr_verts[i] = _rest_verts[i]
			_vel_verts[i]  = Vector3.ZERO
		_deforming = false
	_rebuild_mesh()

func _check_post_crossbar_hit(world_bp: Vector3, local_bp: Vector3) -> void:
	var bv: Vector3 = ball_physics.velocity
	if bv.length() < 5.0:
		return
	# Left post
	if absf(local_bp.x - (-goal_half_width)) < 0.25 and local_bp.y < goal_height:
		SoundManager.bounce(bv.length() * 0.6, world_bp)
		SoundManager.near_miss()
		_near_miss_cooldown = 2.0
		ball_physics.velocity = bv.bounce(Vector3(1.0, 0.0, 0.0)) * 0.65
		return
	# Right post
	if absf(local_bp.x - goal_half_width) < 0.25 and local_bp.y < goal_height:
		SoundManager.bounce(bv.length() * 0.6, world_bp)
		SoundManager.near_miss()
		_near_miss_cooldown = 2.0
		ball_physics.velocity = bv.bounce(Vector3(-1.0, 0.0, 0.0)) * 0.65
		return
	# Crossbar
	if absf(local_bp.y - goal_height) < 0.2 and absf(local_bp.x) < goal_half_width:
		SoundManager.bounce(bv.length() * 0.6, world_bp)
		SoundManager.near_miss()
		_near_miss_cooldown = 2.0
		ball_physics.velocity = bv.bounce(Vector3(0.0, 1.0, 0.0)) * 0.65

func _rebuild_mesh() -> void:
	# Rebuild surface with deformed vertices
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: int = NET_W + 1
	for row in NET_H:
		for col in NET_W:
			var tl: int = row * cols + col
			var tr: int = tl + 1
			var bl: int = tl + cols
			var br: int = bl + 1
			st.add_vertex(_curr_verts[tl])
			st.add_vertex(_curr_verts[bl])
			st.add_vertex(_curr_verts[tr])
			st.add_vertex(_curr_verts[tr])
			st.add_vertex(_curr_verts[bl])
			st.add_vertex(_curr_verts[br])
	st.generate_normals()
	mesh = st.commit()
