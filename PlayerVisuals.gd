extends Node3D

@export var player_name: String = ""
@export var show_name: bool = true
@export var team_id: int = 0
@export var skin_tone: Color = Color(0.90, 0.78, 0.62, 1.0)
@export var idle_bounce_amp: float = 0.05
@export var run_bounce_amp: float = 0.08
@export var bounce_speed_idle: float = 3.5
@export var bounce_speed_run: float = 8.0
@export var player_model_scene_path: String = ""
@export var player_model_scale: Vector3 = Vector3(1.0, 1.0, 1.0)

var _player: CharacterBody3D = null
var _dribble: Node = null
var _body_mesh: MeshInstance3D = null
var _head_mesh: MeshInstance3D = null
var _shadow: MeshInstance3D = null
var _name_label: Label3D = null
var _status_ring: MeshInstance3D = null
var _kit_mat: StandardMaterial3D = null
var _skin_mat: StandardMaterial3D = null
var _ring_mat: StandardMaterial3D = null
var _model_root: Node3D = null
var _model_anim: AnimationPlayer = null
var _stamina: float = 1.0
var _skill_active: bool = false
var _aura_phase: float = 0.0
var _base_height: float = 0.92
var _pending_kit_color: Color = Color(0.05, 0.10, 1.0, 1.0)
var _juggle_punch: float = 0.0
var _juggle_punch_dir: float = 0.0

func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player != null:
		_dribble = _player.get_node_or_null("DribbleSystem")
	var juggle := _player.get_node_or_null("JuggleSystem")
	if juggle != null and juggle.has_signal("touch_performed"):
		juggle.touch_performed.connect(_on_juggle_touch)
	if team_id == 0:
		_pending_kit_color = Color(0.05, 0.10, 1.0)
	else:
		_pending_kit_color = Color(1.0, 0.12, 0.12)
	_build_visual_tree()

func _build_visual_tree() -> void:
	# Visual root under PlayerVisuals for clean transform control.
	var body := CapsuleMesh.new()
	body.radius = 0.28
	body.height = 0.95
	_body_mesh = MeshInstance3D.new()
	_body_mesh.mesh = body
	_body_mesh.position = Vector3(0.0, _base_height, 0.0)
	_kit_mat = StandardMaterial3D.new()
	_kit_mat.roughness = 0.65
	_kit_mat.metallic = 0.05
	_body_mesh.material_override = _kit_mat
	add_child(_body_mesh)

	var head := SphereMesh.new()
	head.radius = 0.19
	head.height = 0.38
	_head_mesh = MeshInstance3D.new()
	_head_mesh.mesh = head
	_head_mesh.position = Vector3(0.0, _base_height + 0.58, 0.0)
	_skin_mat = StandardMaterial3D.new()
	_skin_mat.albedo_color = skin_tone
	_skin_mat.roughness = 0.85
	_head_mesh.material_override = _skin_mat
	add_child(_head_mesh)

	var sh := CylinderMesh.new()
	sh.top_radius = 0.32
	sh.bottom_radius = 0.32
	sh.height = 0.01
	_shadow = MeshInstance3D.new()
	_shadow.mesh = sh
	_shadow.position = Vector3(0.0, 0.02, 0.0)
	var sh_mat := StandardMaterial3D.new()
	sh_mat.albedo_color = Color(0, 0, 0, 0.32)
	sh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = sh_mat
	add_child(_shadow)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.31
	ring.outer_radius = 0.34
	ring.rings = 12
	ring.ring_segments = 12
	_status_ring = MeshInstance3D.new()
	_status_ring.mesh = ring
	_status_ring.rotation_degrees.x = 90.0
	_status_ring.position = Vector3(0.0, 0.03, 0.0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.emission_enabled = true
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_status_ring.material_override = _ring_mat
	add_child(_status_ring)

	_name_label = Label3D.new()
	_name_label.text = player_name
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.font_size = 26
	_name_label.outline_size = 5
	_name_label.modulate = Color(1, 1, 1, 0.95)
	_name_label.outline_modulate = Color(0, 0, 0, 0.9)
	_name_label.position = Vector3(0.0, _base_height + 0.95, 0.0)
	_name_label.visible = show_name
	add_child(_name_label)
	set_kit_colour(_pending_kit_color)
	_try_spawn_player_model()

func _try_spawn_player_model() -> void:
	if player_model_scene_path == "":
		return
	if not ResourceLoader.exists(player_model_scene_path):
		return
	var packed := load(player_model_scene_path) as PackedScene
	if packed == null:
		return
	var inst := packed.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return
	_model_root = inst as Node3D
	_model_root.name = "PlayerModel"
	_model_root.position = Vector3(0.0, 0.0, 0.0)
	_model_root.scale = player_model_scale
	add_child(_model_root)
	_align_model_to_ground()
	_try_play_model_animation()
	# Hide procedural placeholders when real model is present.
	if _body_mesh:
		_body_mesh.visible = false
	if _head_mesh:
		_head_mesh.visible = false

func _align_model_to_ground() -> void:
	if _model_root == null:
		return
	var min_y := INF
	for n in _model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var aabb := mi.mesh.get_aabb()
		var y0 := mi.position.y + aabb.position.y * mi.scale.y
		var y1 := mi.position.y + (aabb.position.y + aabb.size.y) * mi.scale.y
		min_y = minf(min_y, minf(y0, y1))
	if min_y == INF:
		_model_root.position.y = 0.02
		return
	_model_root.position.y = 0.02 - min_y

func _try_play_model_animation() -> void:
	if _model_root == null:
		return
	var anim_nodes := _model_root.find_children("*", "AnimationPlayer", true, false)
	if anim_nodes.is_empty():
		return
	_model_anim = anim_nodes[0] as AnimationPlayer
	if _model_anim == null:
		return
	var names := _model_anim.get_animation_list()
	if names.is_empty():
		return
	var clip := names[0]
	_model_anim.play(clip)

func _process(delta: float) -> void:
	if _player != null:
		_stamina = _player.stamina
	_update_bounce_and_stride(delta)
	_update_ring(delta)

func _update_bounce_and_stride(_delta: float) -> void:
	if _body_mesh == null or _head_mesh == null:
		return
	var speed := 0.0
	if _player != null:
		speed = _player.horizontal_velocity.length()
	var move_t := clampf(speed / 7.0, 0.0, 1.0)
	var amp := lerpf(idle_bounce_amp, run_bounce_amp, move_t)
	var bspd := lerpf(bounce_speed_idle, bounce_speed_run, move_t)
	var phase := _get_visual_phase()
	var bounce := sin(Time.get_ticks_msec() * 0.001 * bspd + phase * TAU) * amp
	if _juggle_punch > 0.0:
		_juggle_punch = maxf(0.0, _juggle_punch - _delta * 5.5)
		bounce += sin((1.0 - _juggle_punch) * PI) * 0.11 * _juggle_punch_dir
	if _model_root != null:
		_model_root.position.y = 0.02 + bounce
		if _model_anim != null and _model_anim.is_playing():
			_model_anim.speed_scale = lerpf(0.6, 1.35, move_t)
	else:
		_body_mesh.position.y = _base_height + bounce
		_head_mesh.position.y = (_base_height + 0.58) + bounce * 1.1
	# Leg/stride hint tied to the exact dribble oscillator.
	var stride_x := sin(phase * TAU) * 0.02 * move_t
	if _model_root != null:
		_model_root.position.x = stride_x
	else:
		_body_mesh.position.x = stride_x

func _get_visual_phase() -> float:
	if _dribble != null and _dribble.has_method("get_foot_phase"):
		return _dribble.get_foot_phase()
	if _player != null and _player.has_method("get_foot_phase"):
		return _player.get_foot_phase()
	return 0.0

func _update_ring(delta: float) -> void:
	if _ring_mat == null:
		return
	var col: Color
	if _stamina > 0.5:
		col = Color(0.0, 1.0, 0.55).lerp(Color(1.0, 0.9, 0.0), (1.0 - _stamina) * 2.0)
	else:
		col = Color(1.0, 0.9, 0.0).lerp(Color(1.0, 0.15, 0.15), (0.5 - _stamina) * 2.0)
	_ring_mat.emission = col
	_ring_mat.albedo_color = Color(col.r, col.g, col.b, 0.78)
	_aura_phase += delta * 6.5
	if _skill_active:
		_ring_mat.emission_energy = 1.8 + sin(_aura_phase) * 0.9
	else:
		_ring_mat.emission_energy = 1.2

func set_kit_colour(col: Color) -> void:
	_pending_kit_color = col
	if _kit_mat != null:
		_kit_mat.albedo_color = col

func set_skin_tone(col: Color) -> void:
	skin_tone = col
	if _skin_mat != null:
		_skin_mat.albedo_color = col

func set_player_name(n: String) -> void:
	player_name = n
	if _name_label != null:
		_name_label.text = n

func set_show_name(v: bool) -> void:
	show_name = v
	if _name_label != null:
		_name_label.visible = v

func set_stamina(s: float) -> void:
	_stamina = clampf(s, 0.0, 1.0)

func set_skill_aura(active: bool) -> void:
	_skill_active = active

func _on_juggle_touch(touch_type: int) -> void:
	_juggle_punch = 1.0
	match touch_type:
		1: _juggle_punch_dir = 0.85   # chest — body dip
		2: _juggle_punch_dir = 1.15   # head — taller pop
		_: _juggle_punch_dir = 0.55   # foot keepy-up
