extends Node

var _camera: Camera3D = null
var _base_offset := Vector3.ZERO
var _trauma      := 0.0
var _time        := 0.0

const DECAY := 3.5

func register_camera(cam: Camera3D) -> void:
	_camera = cam

func update_base(offset: Vector3) -> void:
	_base_offset = offset

func _process(delta: float) -> void:
	if _camera == null:
		return
	if _trauma <= 0.0:
		_camera.position = _base_offset
		return
	_time   += delta * 20.0
	_trauma  = maxf(0.0, _trauma - DECAY * delta)
	var shake := _trauma * _trauma
	var offset := Vector3(
		sin(_time * 1.7) * shake * 0.3,
		sin(_time * 2.3) * shake * 0.2,
		0.0
	)
	_camera.position = _base_offset + offset

func _add(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)

func light()      -> void: _add(0.15)
func medium()     -> void: _add(0.30)
func shot()       -> void: _add(0.25)
func power_shot() -> void: _add(0.45)
func bicycle()    -> void: _add(0.50)
func skill_move() -> void: _add(0.12)
func goal()       -> void: _add(0.60)   # Big shake on goal
