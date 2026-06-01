extends CanvasLayer

# ============================================================
#  GoalCelebration.gd — 8 celebration variants
#  Picks style from GameState "last_goal" quality metadata.
# ============================================================

signal celebration_finished

enum CelebrationType {
	JUMP_FIST,       # Default — weak / standard goals
	SLIDE_KNEES,     # Medium power
	BACKFLIP,        # High power / skill
	SIGNATURE_DANCE, # Skill move goal
	TEAMMATE_PILE,   # Assisted / close range
	CAMERA_SPINMO,   # Long-range screamer
	FIREWORKS_NET,   # Volley / header
	HEART_CROWD,     # Bonus — random flair
}

const TEAM_COLORS := [Color(0.2, 0.45, 1.0), Color(1.0, 0.22, 0.22)]
const DURATION := [1.35, 1.55, 1.75, 2.0, 1.65, 1.9, 2.1, 1.5]

var _root: Control
var _flash: ColorRect
var _banner: Label
var _sub_banner: Label
var _fx_layer: Control
var _active_type: CelebrationType = CelebrationType.JUMP_FIST
var _playing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 12
	visible = false
	_build_ui()
	GameState.phase_changed.connect(_on_phase)

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_root.add_child(_flash)

	_fx_layer = Control.new()
	_fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fx_layer)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 80
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 56)
	_root.add_child(_banner)

	_sub_banner = Label.new()
	_sub_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub_banner.offset_top = 150
	_sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_banner.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	_sub_banner.add_theme_font_size_override("font_size", 22)
	_root.add_child(_sub_banner)

func _on_phase(p: int) -> void:
	if p == GameState.Phase.GOAL and not _playing:
		var team: int = GameState.last_scoring_team
		var meta: Dictionary = GameState.get_meta("last_goal", {})
		_play(team, meta)

func _pick_celebration(meta: Dictionary) -> CelebrationType:
	var shot_type: String = meta.get("shot_type", "normal")
	var speed: float = meta.get("speed", 12.0)
	var charge: float = meta.get("charge", 0.5)
	match shot_type:
		"bicycle": return CelebrationType.BACKFLIP
		"volley", "header": return CelebrationType.FIREWORKS_NET
		"skill": return CelebrationType.SIGNATURE_DANCE
		"assist": return CelebrationType.TEAMMATE_PILE
	if speed >= 22.0 or charge >= 0.85:
		if randf() < 0.45:
			return CelebrationType.CAMERA_SPINMO
		return CelebrationType.BACKFLIP
	if speed >= 17.0:
		return CelebrationType.SLIDE_KNEES
	if speed < 12.0:
		if randf() < 0.2:
			return CelebrationType.HEART_CROWD
		return CelebrationType.JUMP_FIST
	if randf() < 0.12:
		return CelebrationType.HEART_CROWD
	return CelebrationType.JUMP_FIST

func _play(scoring_team: int, meta: Dictionary) -> void:
	if _playing:
		return
	_playing = true
	_active_type = _pick_celebration(meta)
	visible = true

	var team_col: Color = TEAM_COLORS[clampi(scoring_team, 0, 1)]
	var scorer: String = meta.get("scorer_name", "GOAL!")
	_banner.text = "GOAL!"
	_banner.add_theme_color_override("font_color", team_col)
	_sub_banner.text = "%s  ·  %s" % [scorer, _celebration_title(_active_type)]

	if _flash:
		var c := team_col
		c.a = 0.55
		_flash.color = c

	get_tree().paused = true
	Engine.time_scale = 1.0
	ScreenShake.goal()
	Input.vibrate_handheld(180)
	SoundManager.goal_cheer()
	SoundManager.play_celebration(_active_type)

	var goal_pos := PitchConstants.attack_goal_vec(scoring_team)
	VisualEffects.goal_explosion(goal_pos + Vector3(0, 1.2, 0), scoring_team)
	VisualEffects.net_ripple(goal_pos)

	_run_celebration_fx(_active_type, team_col)

	var dur: float = DURATION[_active_type]
	if GameState.is_training():
		dur = minf(dur, 1.2)

	# Safety timeout
	get_tree().create_timer(dur + 2.5, true).timeout.connect(func():
		if _playing:
			_finish())

	await get_tree().create_timer(dur, true).timeout
	_finish()

func _celebration_title(t: CelebrationType) -> String:
	match t:
		CelebrationType.JUMP_FIST: return "FIST PUMP"
		CelebrationType.SLIDE_KNEES: return "SLIDE"
		CelebrationType.BACKFLIP: return "BACKFLIP"
		CelebrationType.SIGNATURE_DANCE: return "SIGNATURE"
		CelebrationType.TEAMMATE_PILE: return "PILE-UP"
		CelebrationType.CAMERA_SPINMO: return "SCREAMER"
		CelebrationType.FIREWORKS_NET: return "NET BURST"
		CelebrationType.HEART_CROWD: return "CROWD LOVE"
		_: return ""

func _run_celebration_fx(t: CelebrationType, col: Color) -> void:
	for c in _fx_layer.get_children():
		c.queue_free()

	match t:
		CelebrationType.JUMP_FIST:
			_animate_banner_pop()
		CelebrationType.SLIDE_KNEES:
			_animate_banner_pop()
			_spawn_confetti(col, 6)  # Clean, minimal broadcast style accent
		CelebrationType.BACKFLIP:
			_animate_banner_pop()
			var td := get_node_or_null("/root/TimeDilation")
			if td:
				td.slow(0.55, 0.35)
		CelebrationType.SIGNATURE_DANCE:
			_animate_banner_pop()
			_spawn_confetti(col, 6)
		CelebrationType.TEAMMATE_PILE:
			_sub_banner.text += "\nTEAM CELEBRATION"
			_spawn_confetti(col, 6)
		CelebrationType.CAMERA_SPINMO:
			_animate_banner_pop()
			var td2 := get_node_or_null("/root/TimeDilation")
			if td2:
				td2.slow(0.4, 0.5)
			ScreenShake.goal()
			_spawn_confetti(col, 8)
		CelebrationType.FIREWORKS_NET:
			VisualEffects.goal_flash(0)
			_spawn_firework_burst(col)
		CelebrationType.HEART_CROWD:
			_animate_banner_pop()
			_spawn_confetti(col, 6)

	if _flash:
		var tw := create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(_flash, "color:a", 0.0, 0.65)

func _animate_banner_pop() -> void:
	_banner.scale = Vector2(0.2, 0.2)
	_banner.pivot_offset = _banner.size * 0.5
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_banner, "scale", Vector2(1.2, 1.2), 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.12)

func _animate_banner_spin() -> void:
	# Clean pop fallback to replace spinning gimmicks
	_animate_banner_pop()

func _animate_banner_wiggle() -> void:
	# Clean pop fallback to replace wiggling gimmicks
	_animate_banner_pop()

func _spawn_confetti(col: Color, count: int) -> void:
	var vp := get_viewport().get_visible_rect().size
	var n := mini(count, 12)  # clamp to a tiny professional quantity
	for i in n:
		var p := ColorRect.new()
		p.size = Vector2(6, 12)
		p.color = col.lightened(randf_range(-0.15, 0.25))
		p.position = Vector2(randf_range(0, vp.x), -20)
		_fx_layer.add_child(p)
		var tw := create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(p, "position:y", randf_range(vp.y * 0.35, vp.y * 0.85), randf_range(0.6, 1.1))
		tw.parallel().tween_property(p, "rotation", randf_range(-1.5, 1.5), 1.0)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 0.95)

func _spawn_firework_burst(col: Color) -> void:
	_spawn_confetti(col, 10)  # clean minimal accent
	VisualEffects.screen_flash(col, 0.22)

func _finish() -> void:
	if not _playing:
		return
	_playing = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	visible = false
	_banner.scale = Vector2.ONE
	_banner.rotation = 0.0
	celebration_finished.emit()
