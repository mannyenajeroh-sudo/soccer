extends CanvasLayer

# ============================================================
#  MatchHUD.gd  —  all in-match UI elements.
#  Uses GameState signals — never polls state directly.
# ============================================================

@onready var timer_label    := $Timer/Label
@onready var juggle_counter := $JuggleCounter
@onready var power_ready    := $PowerVolleyReady
@onready var charge_arc     := $ChargeArc        # Control with _draw() override
@onready var team0_score    := $Score/Team0
@onready var team1_score    := $Score/Team1
@onready var score_vs       := $Score/Label

var _charge := 0.0   # 0–1, set externally by KickSystem
var _juggle_count := 0
var _spectator := false

# ---- Stamina bar ----
var _stamina_bar: Control = null
var _stamina_value: float = 1.0
const STAMINA_BAR_W := 120.0
const STAMINA_BAR_H := 8.0

func _ready() -> void:
	GameState.score_changed.connect(_on_score)
	GameState.timer_tick.connect(_on_timer)
	GameState.phase_changed.connect(_on_phase)
	power_ready.visible = false
	juggle_counter.visible = false
	_on_score(GameState.score[0], GameState.score[1])
	timer_label.text = GameState.get_time_string()
	_build_stamina_bar()
	if not GameState.is_training():
		var style_ui := Control.new()
		style_ui.set_script(load("res://scripts/StyleMeterDraw.gd"))
		style_ui.name = "StyleMeter"
		add_child(style_ui)

func _build_stamina_bar() -> void:
	_stamina_bar = Control.new()
	_stamina_bar.name = "StaminaBar"
	# Position: bottom-left, above the joystick zone
	_stamina_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stamina_bar.offset_left   = 20.0
	_stamina_bar.offset_bottom = -30.0
	_stamina_bar.offset_right  = 20.0 + STAMINA_BAR_W + 6.0
	_stamina_bar.offset_top    = -30.0 - STAMINA_BAR_H - 6.0
	_stamina_bar.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	var sv := _stamina_value
	_stamina_bar.draw.connect(func():
		var w := STAMINA_BAR_W; var h := STAMINA_BAR_H
		# Background track
		_stamina_bar.draw_rect(Rect2(0, 0, w + 4, h + 4), Color(0, 0, 0, 0.45), true, 0.0)
		# Colour: cyan → yellow → red
		var col: Color
		if _stamina_value > 0.5:
			col = Color(0.0, 1.0, 0.9, 0.85).lerp(Color(1.0, 0.9, 0.0, 0.85), (1.0 - _stamina_value) * 2.0)
		else:
			col = Color(1.0, 0.9, 0.0, 0.85).lerp(Color(1.0, 0.1, 0.1, 0.85), (0.5 - _stamina_value) * 2.0)
		var filled_w := maxf(2.0, _stamina_value * w)
		_stamina_bar.draw_rect(Rect2(2, 2, filled_w, h), col, true, 0.0)
		# Outline
		_stamina_bar.draw_rect(Rect2(0, 0, w + 4, h + 4), Color(1, 1, 1, 0.25), false, 1.0)
	)
	add_child(_stamina_bar)

# Called when human player is spawned — connect stamina signal
func connect_player_stamina(player: Node) -> void:
	if player.has_signal("stamina_changed"):
		player.stamina_changed.connect(_on_stamina_changed)

func _on_stamina_changed(value: float) -> void:
	_stamina_value = clampf(value, 0.0, 1.0)
	if _stamina_bar:
		_stamina_bar.queue_redraw()

func _on_phase(phase) -> void:
	if phase == GameState.Phase.GOAL:
		_on_score(GameState.score[0], GameState.score[1])
	elif phase == GameState.Phase.FULLTIME:
		timer_label.text = "FT"
		_on_score(GameState.score[0], GameState.score[1])

func _process(_delta: float) -> void:
	if GameState.phase == GameState.Phase.PLAY:
		timer_label.text = GameState.get_time_string()
		team0_score.text = str(GameState.score[0])
		team1_score.text = str(GameState.score[1])

# ---- Score ----------------------------------------------
func set_spectator_mode(on: bool) -> void:
	_spectator = on
	if on:
		team0_score.add_theme_color_override("font_color", Color(0.2, 0.45, 1.0))
		team1_score.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		if score_vs:
			score_vs.text = "–"
		if not has_node("SpectatorBanner"):
			var banner := Label.new()
			banner.name = "SpectatorBanner"
			banner.text = "AI vs AI"
			banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			banner.add_theme_font_size_override("font_size", 18)
			banner.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
			banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
			banner.offset_top = 48.0
			banner.offset_bottom = 72.0
			add_child(banner)
	elif has_node("SpectatorBanner"):
		get_node("SpectatorBanner").queue_free()
	# Hide stamina bar in spectator mode
	if _stamina_bar:
		_stamina_bar.visible = not on

func _on_score(a: int, b: int) -> void:
	team0_score.text = str(a)
	team1_score.text = str(b)

# ---- Timer (red at 30s) ---------------------------------
func _on_timer(remaining: float) -> void:
	var t := int(remaining)
	timer_label.text = "%d:%02d" % [t / 60, t % 60]
	if remaining <= 30.0:
		timer_label.add_theme_color_override("font_color", Color.RED)
	else:
		timer_label.remove_theme_color_override("font_color")

# ---- Charge arc -----------------------------------------
func set_charge(c: float) -> void:
	_charge = clampf(c, 0.0, 1.0)
	if charge_arc:
		charge_arc.charge = _charge
		charge_arc.queue_redraw()

# In ChargeArc Control node, override _draw():
# func _draw():
#   var r = 28.0; var c = size * 0.5
#   draw_arc(c, r, -PI*0.5, -PI*0.5 + TAU*charge, 32, Color.WHITE, 3.0)

# ---- Juggle counter -------------------------------------
func set_juggle_count(count: int) -> void:
	_juggle_count = count
	if count == 0:
		juggle_counter.visible = false
		power_ready.visible = false
		return
	juggle_counter.visible = true
	juggle_counter.text = "x%d" % count
	# Animate scale on increment
	var tw := create_tween()
	tw.tween_property(juggle_counter, "scale", Vector2(1.3, 1.3), 0.06)
	tw.tween_property(juggle_counter, "scale", Vector2.ONE, 0.10)
	if count >= 5:
		power_ready.visible = true
		_pulse_power_ready()

func _pulse_power_ready() -> void:
	var tw := create_tween()
	tw.set_loops(3)
	tw.tween_property(power_ready, "modulate:a", 0.4, 0.2)
	tw.tween_property(power_ready, "modulate:a", 1.0, 0.2)

## World Cup Expansion: show team names in HUD if set in GameState.
func _update_team_names() -> void:
	var home_id := GameState.home_team_id
	var away_id := GameState.away_team_id
	if home_id == "" or away_id == "":
		return
	var home_data := TeamDatabase.get_team_by_id(home_id)
	var away_data := TeamDatabase.get_team_by_id(away_id)
	var home_name_node := get_node_or_null("TopBar/HomeTeamName")
	var away_name_node := get_node_or_null("TopBar/AwayTeamName")
	if home_name_node:
		home_name_node.text = "%s %s" % [TeamDatabase.get_flag(home_id), home_data.get("name","")]
	if away_name_node:
		away_name_node.text = "%s %s" % [TeamDatabase.get_flag(away_id), away_data.get("name","")]
