extends CanvasLayer

# ============================================================
#  TrainingHUD.gd — Freestyle practice (no goal scoring)
# ============================================================

signal reset_ball_requested
signal drill_changed(drill: String)

const DRILLS := ["freestyle", "passing", "juggle"]

var style_points := 0
var touches := 0
var passes := 0
var shots_total := 0
var _drill_index := 0

var _title_lbl: Label
var _stats_lbl: Label
var _hint_lbl: Label

func _ready() -> void:
	layer = 5
	_build_ui()
	if TeamStyleMeter.has_signal("style_changed"):
		TeamStyleMeter.style_changed.connect(_on_style)

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 16
	panel.offset_right = -16
	panel.offset_top = 16
	panel.offset_bottom = 120
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_title_lbl = _mk_label("FREESTYLE TRAINING", 20, Color(0.0, 1.0, 0.55))
	vbox.add_child(_title_lbl)

	_stats_lbl = _mk_label("Style: 0  |  Touches: 0", 16, Color(1, 1, 1))
	vbox.add_child(_stats_lbl)

	_hint_lbl = _mk_label("Flair: double-tap F juggle · tap F chain · double-tap Space wall · Space volley", 13, Color(0.55, 0.55, 0.6))
	vbox.add_child(_hint_lbl)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var reset_btn := Button.new()
	reset_btn.text = "RESET BALL (R)"
	reset_btn.pressed.connect(func(): reset_ball_requested.emit())
	row.add_child(reset_btn)

	var drill_btn := Button.new()
	drill_btn.text = "DRILL ▼"
	drill_btn.pressed.connect(_cycle_drill)
	row.add_child(drill_btn)

	var menu_btn := Button.new()
	menu_btn.text = "MENU"
	menu_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
	)
	row.add_child(menu_btn)

func _mk_label(txt: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l

func _on_style(_team_id: int, value: float, _peak: bool) -> void:
	if _team_id == 0:
		style_points = int(value)
		_refresh()

func register_touch() -> void:
	touches += 1
	_refresh()

func register_pass() -> void:
	passes += 1
	_refresh()

func register_goal(_speed: float) -> void:
	# Freestyle: goals do not increment — flair only
	pass

func register_shot(_on_target: bool, _speed: float) -> void:
	shots_total += 1
	_refresh()

func _refresh() -> void:
	_stats_lbl.text = "Style: %d  |  Touches: %d  |  Passes: %d  |  Shots: %d" % [
		style_points, touches, passes, shots_total
	]

func _cycle_drill() -> void:
	_drill_index = (_drill_index + 1) % DRILLS.size()
	var d: String = DRILLS[_drill_index]
	_title_lbl.text = "TRAINING — %s" % d.to_upper()
	drill_changed.emit(d)

func get_drill() -> String:
	return DRILLS[_drill_index]
