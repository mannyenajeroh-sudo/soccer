extends Control

# Draws dual team style meters for match HUD.

var _team0 := 0.0
var _team1 := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_top = 8.0
	offset_bottom = 36.0
	TeamStyleMeter.style_changed.connect(_on_style)
	_team0 = TeamStyleMeter.get_style(0)
	_team1 = TeamStyleMeter.get_style(1)
	queue_redraw()

func _on_style(team_id: int, value: float, _peak: bool) -> void:
	if team_id == 0:
		_team0 = value
	else:
		_team1 = value
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var bar_h := 10.0
	var y := 4.0
	var half := w * 0.5 - 12.0
	_draw_meter(Rect2(12, y, half, bar_h), _team0, Color(0.15, 0.55, 1.0), true)
	_draw_meter(Rect2(w * 0.5 + 4, y, half, bar_h), _team1, Color(1.0, 0.22, 0.22), false)
	var font := ThemeDB.fallback_font
	var fs := 11
	draw_string(font, Vector2(12, y + bar_h + 12), "STYLE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.45))
	if _team0 >= 85.0 or _team1 >= 85.0:
		draw_string(font, Vector2(w * 0.5 - 24, y + bar_h + 12), "ON FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.55, 0.1, 0.9))

func _draw_meter(rect: Rect2, value: float, col: Color, left_to_right: bool) -> void:
	draw_rect(rect, Color(0, 0, 0, 0.35), true)
	var fill_w := rect.size.x * clampf(value / 100.0, 0.0, 1.0)
	if fill_w < 1.0:
		return
	var fill_rect := rect
	if left_to_right:
		fill_rect.size.x = fill_w
	else:
		fill_rect.position.x += rect.size.x - fill_w
		fill_rect.size.x = fill_w
	var glow := col.lightened(0.25) if value >= 85.0 else col
	draw_rect(fill_rect, glow, true)
