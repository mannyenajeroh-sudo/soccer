extends Node3D

# ============================================================
#  BallVisuals.gd — IMPROVED: shot tracer color = power level
#  Post-save deflection particles, spinning stripe rotation
# ============================================================

@export var ball_physics: BallPhysics
@export var ball_mesh: MeshInstance3D
@export var trail_particles: GPUParticles3D
@export var ball_model_scene_path: String = ""
@export var ball_model_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

const TRAIL_SPEED_THRESHOLD := 16.0
const POWER_SPEED_THRESHOLD := 22.0  # Full-power shot

var _tween: Tween
var _procedural_trail: CPUParticles3D = null
var _deflect_particles: CPUParticles3D = null
var _trail_material: StandardMaterial3D = null
var _spin_target: Node3D = null

func _ready() -> void:
	if ball_physics:
		ball_physics.bounced.connect(_on_bounce)
	_try_spawn_ball_model()
	if ball_mesh:
		ball_mesh.visible = true if _spin_target == ball_mesh else false
	_create_trail()
	_create_deflect_particles()

func _try_spawn_ball_model() -> void:
	_spin_target = ball_mesh
	if ball_physics == null or ball_model_scene_path == "":
		return
	if not ResourceLoader.exists(ball_model_scene_path):
		return
	var packed := load(ball_model_scene_path) as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return
	var root := inst as Node3D
	root.name = "BallModel"
	root.scale = ball_model_scale
	root.position = Vector3.ZERO
	ball_physics.add_child(root)
	_spin_target = root
	if ball_mesh:
		ball_mesh.visible = false

func _create_trail() -> void:
	var trail := CPUParticles3D.new()
	trail.name = "ProceduralTrail"
	trail.emitting = false
	trail.amount = 30
	trail.lifetime = 0.35
	trail.one_shot = false
	trail.speed_scale = 1.0
	trail.explosiveness = 0.0
	trail.randomness = 0.15
	trail.local_coords = false

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.06
	sphere_mesh.height = 0.12
	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
	_trail_material.vertex_color_use_as_albedo = true
	sphere_mesh.material = _trail_material
	trail.mesh = sphere_mesh

	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 1.0, 0.75))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	trail.color_ramp = grad

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	trail.scale_amount_curve = curve

	add_child(trail)
	_procedural_trail = trail

func _create_deflect_particles() -> void:
	var ps := CPUParticles3D.new()
	ps.name = "DeflectParticles"
	ps.emitting = false
	ps.amount = 20
	ps.lifetime = 0.4
	ps.one_shot = true
	ps.explosiveness = 0.9
	ps.randomness = 0.3
	ps.speed_scale = 1.0
	ps.local_coords = false
	ps.direction = Vector3(0, 1, 0)
	ps.spread = 180.0
	ps.initial_velocity_min = 2.0
	ps.initial_velocity_max = 5.0
	ps.gravity = Vector3(0, -5, 0)

	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	var m := StandardMaterial3D.new()
	m.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.7, 0.85)
	sm.material = m
	ps.mesh = sm

	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.6, 0.9))
	grad.set_color(1, Color(1.0, 0.5, 0.0, 0.0))
	ps.color_ramp = grad

	add_child(ps)
	_deflect_particles = ps

func _process(delta: float) -> void:
	if ball_physics == null:
		return
	# Spin stripe rotation from physics angular velocity
	var omega: Vector3 = ball_physics.angular_velocity as Vector3
	if omega.length_squared() > 0.001 and _spin_target != null:
		_spin_target.rotate(omega.normalized(), omega.length() * delta)

	# Shot tracer: color shifts red → orange → white by speed (IMPROVED)
	var spd := ball_physics.velocity.length()
	var is_fast: bool = spd > TRAIL_SPEED_THRESHOLD
	var power_t := clampf((spd - TRAIL_SPEED_THRESHOLD) / (POWER_SPEED_THRESHOLD - TRAIL_SPEED_THRESHOLD), 0.0, 1.0)

	if trail_particles:
		trail_particles.emitting = is_fast
	if _procedural_trail:
		_procedural_trail.emitting = is_fast
		_procedural_trail.global_position = ball_physics.global_position
		if _trail_material and is_fast:
			# Color by power: white → orange → red
			var trail_color := Color(1.0, 1.0 - power_t * 0.6, 1.0 - power_t * 0.9, 0.75)
			_trail_material.albedo_color = trail_color

func _on_bounce(impact_speed: float) -> void:
	if _spin_target == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	var s := clampf(impact_speed / 20.0, 0.1, 0.4)
	_tween = create_tween()
	_tween.tween_property(_spin_target, "scale",
		Vector3(1.0 + s, 1.0 - s, 1.0 + s), 0.04
	).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_spin_target, "scale",
		Vector3.ONE, 0.10
	).set_ease(Tween.EASE_IN_OUT)

	# Post-save deflection particles on big impacts
	if impact_speed > 8.0 and _deflect_particles:
		_deflect_particles.global_position = ball_physics.global_position
		_deflect_particles.restart()
