extends CanvasLayer

@onready var right_buttons := $RightButtons
@onready var shoot_btn := $RightButtons/ShootBtn
@onready var pass_btn := $RightButtons/PassBtn
@onready var sprint_btn := $RightButtons/SprintBtn

func _ready() -> void:
	# Position RightButtons container bottom-right
	right_buttons.size = Vector2(300, 300)
	right_buttons.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	right_buttons.anchor_left = 1.0
	right_buttons.anchor_right = 1.0
	right_buttons.anchor_top = 1.0
	right_buttons.anchor_bottom = 1.0
	right_buttons.offset_left = -350
	right_buttons.offset_top = -350
	right_buttons.offset_right = -50
	right_buttons.offset_bottom = -50
	
	# Position individual buttons relative to container
	shoot_btn.size = Vector2(100, 100)
	shoot_btn.position = Vector2(160, 40) # top right in container
	
	pass_btn.size = Vector2(90, 90)
	pass_btn.position = Vector2(40, 150) # bottom left in container
	
	sprint_btn.size = Vector2(90, 90)
	sprint_btn.position = Vector2(170, 170) # bottom right in container
	
	# Style buttons procedurally for high-end look
	_style_btn(shoot_btn, Color(0.95, 0.35, 0.1, 0.65), Color(1.0, 0.5, 0.2, 0.85))   # neon orange
	_style_btn(pass_btn, Color(0.0, 0.7, 0.9, 0.65), Color(0.1, 0.85, 1.0, 0.85))     # neon cyan
	_style_btn(sprint_btn, Color(0.65, 0.15, 0.9, 0.65), Color(0.8, 0.3, 1.0, 0.85))   # neon purple
	
	# Connect signals to virtual input actions
	shoot_btn.button_down.connect(func(): _set_action("shoot", true))
	shoot_btn.button_up.connect(func(): _set_action("shoot", false))
	
	pass_btn.button_down.connect(func(): _set_action("pass", true))
	pass_btn.button_up.connect(func(): _set_action("pass", false))
	
	sprint_btn.button_down.connect(func(): _set_action("sprint", true))
	sprint_btn.button_up.connect(func(): _set_action("sprint", false))

func _style_btn(btn: Button, normal_color: Color, border_color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = normal_color
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = border_color
	sb.corner_radius_top_left = 50 # circle
	sb.corner_radius_top_right = 50
	sb.corner_radius_bottom_left = 50
	sb.corner_radius_bottom_right = 50
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 5
	
	var sb_pressed := sb.duplicate()
	sb_pressed.bg_color = normal_color.lerp(Color.WHITE, 0.2)
	sb_pressed.border_color = border_color.lerp(Color.WHITE, 0.2)
	
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	
	# Text styling
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 16)

func _set_action(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	# Keep parity with AdvancedTouchControls: explicit strength helps
	# Godot's action pressed/released state update reliably.
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)
