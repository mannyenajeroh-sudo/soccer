extends CanvasLayer

# ============================================================
#  PostMatchScreen.gd — STREET 3 ELITE  (Phase 6)
#
#  Full post-match statistics overlay shown when Phase = FULLTIME.
#  Pulls data from MatchStatsTracker and MatchEventBus.
#
#  Layout (built entirely in code — no .tscn needed):
#
#  ┌─────────────────────────────────────────────────┐
#  │  FULL TIME                                       │
#  │      BLUE 3  —  2  RED                          │
#  │                                                  │
#  │  [Team Stats side-by-side]                      │
#  │  Possession   62%  ████░░  38%                  │
#  │  Shots         8   ████░░   5                   │
#  │  Passes       34   ████░░  22  (71%)  (55%)     │
#  │  Tackles       9   ████░░   6                   │
#  │  Aerials       4   ████░░   3                   │
#  │  Skill Moves   5   ████░░   2                   │
#  │  Distance    420m  ████░░ 380m                  │
#  │                                                  │
#  │  [PLAY AGAIN]          [MENU]                   │
#  └─────────────────────────────────────────────────┘
# ============================================================

const BLUE := Color(0.15, 0.40, 1.00)
const RED  := Color(1.00, 0.20, 0.15)
const BG   := Color(0.04, 0.04, 0.10, 0.94)
const GOLD := Color(1.00, 0.85, 0.20)
const WHITE := Color(1, 1, 1, 1)
const DIM  := Color(0.6, 0.6, 0.65)

var _root: Control
var _xp_rewarded: bool = false
var _result_recorded: bool = false

func _ready() -> void:
	layer = 10
	visible = false
	_build_ui()
	GameState.phase_changed.connect(_on_phase_changed)
	MatchEventBus.match_over.connect(_on_match_over)

func _build_ui() -> void:
	# Full-screen semi-transparent panel
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Dark backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG
	_root.add_child(bg)

	# Vertical layout container — centred
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -340.0
	vbox.offset_right  =  340.0
	vbox.offset_top    = -340.0
	vbox.offset_bottom =  340.0
	vbox.add_theme_constant_override("separation", 14)
	_root.add_child(vbox)

	# ── FULL TIME header ──
	var ft_label := _make_label("FULL TIME", 32, GOLD, true)
	ft_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ft_label)

	# ── Score ──
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 18)
	vbox.add_child(score_row)

	var team0_lbl := _make_label("BLUE", 22, BLUE, true)
	var score_lbl := _make_label("0 – 0", 36, WHITE, true)
	score_lbl.name = "ScoreLabel"
	var team1_lbl := _make_label("RED",  22, RED,  true)
	score_row.add_child(team0_lbl)
	score_row.add_child(score_lbl)
	score_row.add_child(team1_lbl)

	# ── Result banner ──
	var result_lbl := _make_label("", 20, GOLD, true)
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.name = "ResultLabel"
	vbox.add_child(result_lbl)

	# ── Divider ──
	vbox.add_child(_make_divider())

	# ── Stats table ──
	var stats_container := VBoxContainer.new()
	stats_container.name = "StatsContainer"
	stats_container.add_theme_constant_override("separation", 6)
	vbox.add_child(stats_container)

	# ── XP earned ──
	var xp_lbl := _make_label("", 18, GOLD, false)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_lbl.name = "XPLabel"
	vbox.add_child(xp_lbl)

	vbox.add_child(_make_divider())

	# ── Buttons ──
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	var btn_again := _make_button("PLAY AGAIN", _on_play_again)
	var btn_menu  := _make_button("MENU",       _on_menu)
	btn_row.add_child(btn_again)
	btn_row.add_child(btn_menu)

func _on_phase_changed(phase: int) -> void:
	if phase == GameState.Phase.FULLTIME:
		_populate()
		visible = true

func _on_match_over(_winner: int) -> void:
	# match_over fires together with FULLTIME — _populate handles it
	pass

func _populate() -> void:
	if not _root: return

	if not _result_recorded:
		_record_tournament_result()
		_result_recorded = true

	# Score
	var score_lbl: Label = _root.get_node_or_null("../PostMatchScreen/CanvasLayer/Control/VBoxContainer/HBoxContainer/ScoreLabel")
	# Traverse safely
	var vbox := _root.get_child(1)  # VBoxContainer
	if vbox == null: return

	# Score label — child 1 of score row (child 1 of vbox)
	var score_row: HBoxContainer = vbox.get_child(1) as HBoxContainer
	if score_row:
		var sl: Label = score_row.get_child(1) as Label
		if sl:
			sl.text = "%d – %d" % [GameState.score[0], GameState.score[1]]

	# Result label — child 2
	var result_lbl: Label = vbox.get_child(2) as Label
	if result_lbl:
		var winner := -1
		if GameState.score[0] > GameState.score[1]:
			winner = 0
		elif GameState.score[1] > GameState.score[0]:
			winner = 1
		if winner == 0:
			result_lbl.text = "BLUE WINS!"
			result_lbl.add_theme_color_override("font_color", BLUE)
		elif winner == 1:
			result_lbl.text = "RED WINS!"
			result_lbl.add_theme_color_override("font_color", RED)
		else:
			result_lbl.text = "DRAW!"
			result_lbl.add_theme_color_override("font_color", GOLD)

	# Stats table — child 4 (after header, score, result, divider)
	var stats_container: VBoxContainer = vbox.get_child(4) as VBoxContainer
	if stats_container:
		# Clear existing rows
		for child in stats_container.get_children():
			child.queue_free()
		var t0 := MatchStatsTracker.get_team_stats(0)
		var t1 := MatchStatsTracker.get_team_stats(1)
		_add_stat_row(stats_container, "Possession",
			"%.0f%%" % t0.get("possession_pct", 50.0),
			t0.get("possession_pct", 50.0) / 100.0,
			"%.0f%%" % t1.get("possession_pct", 50.0))
		_add_stat_row(stats_container, "Shots",
			str(t0.get("shots", 0)), _safe_ratio(t0.get("shots", 0), t0.get("shots", 0) + t1.get("shots", 0)),
			str(t1.get("shots", 0)))
		_add_stat_row(stats_container, "Passes",
			"%d (%.0f%%)" % [t0.get("passes_completed", 0), t0.get("pass_completion_pct", 0.0)],
			_safe_ratio(t0.get("passes_completed", 0), t0.get("passes_completed", 0) + t1.get("passes_completed", 0)),
			"%d (%.0f%%)" % [t1.get("passes_completed", 0), t1.get("pass_completion_pct", 0.0)])
		_add_stat_row(stats_container, "Tackles",
			str(t0.get("tackles_won", 0)), _safe_ratio(t0.get("tackles_won", 0), t0.get("tackles_won", 0) + t1.get("tackles_won", 0)),
			str(t1.get("tackles_won", 0)))
		_add_stat_row(stats_container, "Interceptions",
			str(t0.get("interceptions", 0)), _safe_ratio(t0.get("interceptions", 0), t0.get("interceptions", 0) + t1.get("interceptions", 0)),
			str(t1.get("interceptions", 0)))
		_add_stat_row(stats_container, "Aerials Won",
			str(t0.get("aerial_won", 0)), _safe_ratio(t0.get("aerial_won", 0), t0.get("aerial_won", 0) + t1.get("aerial_won", 0)),
			str(t1.get("aerial_won", 0)))
		_add_stat_row(stats_container, "Skill Moves",
			str(t0.get("skill_moves", 0)), _safe_ratio(t0.get("skill_moves", 0), t0.get("skill_moves", 0) + t1.get("skill_moves", 0)),
			str(t1.get("skill_moves", 0)))
		_add_stat_row(stats_container, "Distance",
			"%.0fm" % t0.get("distance_covered", 0.0),
			_safe_ratio(t0.get("distance_covered", 0.0), t0.get("distance_covered", 0.0) + t1.get("distance_covered", 0.0)),
			"%.0fm" % t1.get("distance_covered", 0.0))

	# XP reward (child 5)
	if not _xp_rewarded:
		_xp_rewarded = true
		var xp_earned := _compute_xp()
		ProgressionSystem.add_xp(xp_earned)
		var xp_lbl: Label = vbox.get_child(5) as Label
		if xp_lbl:
			xp_lbl.text = "+%d XP  (Level %d)" % [xp_earned, ProgressionSystem.level]

func _compute_xp() -> int:
	var base := 50
	var score_bonus := (GameState.score[0] + GameState.score[1]) * 8
	var win_bonus := 0
	if GameState.score[0] > GameState.score[1]:
		win_bonus = 30
	elif GameState.score[0] == GameState.score[1]:
		win_bonus = 10
	return base + score_bonus + win_bonus

# ─────────────────────────────────────────────────────────────
#  UI FACTORIES
# ─────────────────────────────────────────────────────────────

## One row of the stats table: [left_val] [bar] [right_val] under a label
func _add_stat_row(parent: VBoxContainer, label: String, left_val: String, left_frac: float, right_val: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	# Left value (blue team)
	var lv := _make_label(left_val, 16, BLUE, false)
	lv.custom_minimum_size = Vector2(110, 0)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(lv)

	# Bar container
	var bar_wrap := Control.new()
	bar_wrap.custom_minimum_size = Vector2(140, 20)
	row.add_child(bar_wrap)
	# Draw dual bar
	bar_wrap.draw.connect(func():
		var w := 140.0; var h := 16.0; var y := 2.0
		# Background
		bar_wrap.draw_rect(Rect2(0, y, w, h), Color(0.2, 0.2, 0.2, 0.7), true)
		# Blue (left) fill
		bar_wrap.draw_rect(Rect2(0, y, left_frac * w, h), BLUE.lerp(Color.WHITE, 0.15) , true)
		# Red (right) fill  — grows from right
		var rf := clampf(1.0 - left_frac, 0.0, 1.0)
		bar_wrap.draw_rect(Rect2(w - rf * w, y, rf * w, h), RED.lerp(Color.WHITE, 0.15), true)
		# Centre divider
		bar_wrap.draw_rect(Rect2(w * 0.5 - 1, y - 2, 2, h + 4), WHITE, true)
	)
	bar_wrap.queue_redraw()

	# Stat label (centre below bar — actually an overlay label on top)
	var stat_lbl := _make_label(label, 14, DIM, false)
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_lbl.custom_minimum_size = Vector2(140, 0)
	# Add stat label as overlay — place in bar_wrap
	stat_lbl.set_anchors_preset(Control.PRESET_CENTER)
	stat_lbl.offset_left   = -70
	stat_lbl.offset_right  =  70
	stat_lbl.offset_top    = -10
	stat_lbl.offset_bottom =  10
	bar_wrap.add_child(stat_lbl)

	# Right value (red team)
	var rv := _make_label(right_val, 16, RED, false)
	rv.custom_minimum_size = Vector2(110, 0)
	rv.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(rv)

static func _safe_ratio(a, total) -> float:
	if total == 0 or total == 0.0: return 0.5
	return clampf(float(a) / float(total), 0.0, 1.0)

func _make_label(text: String, font_size: int, color: Color, bold: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl

func _make_divider() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(1, 1, 1, 0.15))
	return sep

func _make_button(label_text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(180, 52)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(callback)
	return btn

# ─────────────────────────────────────────────────────────────
#  BUTTON ACTIONS
# ─────────────────────────────────────────────────────────────

func _record_tournament_result() -> void:
	var mode := GameState.get_game_mode()
	if mode not in ["world_cup", "tournament"]:
		return
	var home := GameState.home_team_id
	var away := GameState.away_team_id
	if home == "" or away == "":
		return
	var hg: int = GameState.score[0]
	var ag: int = GameState.score[1]
	if GameState.get_meta("is_knockout", false):
		TournamentManager.record_knockout_result(home, away, hg, ag)
	else:
		var fx: Dictionary = GameState.get_meta("current_fixture", {})
		if fx.is_empty():
			return
		TournamentManager.record_group_result(fx["group"], home, away, hg, ag)
		_mark_group_fixture_played(fx, [hg, ag])

func _mark_group_fixture_played(fx: Dictionary, result: Array) -> void:
	var saved: Array = GameState.get_meta("group_fixtures", [])
	if saved.is_empty():
		return
	for f in saved:
		if f.get("home", "") == fx.get("home", "") and f.get("away", "") == fx.get("away", ""):
			f["played"] = true
			f["result"] = result
	GameState.set_meta("group_fixtures", saved)

func _on_play_again() -> void:
	_xp_rewarded = false
	_result_recorded = false
	MatchStatsTracker.reset()
	MatchEventBus.reset()
	GameState.set_phase_direct(GameState.Phase.PREGAME)
	var mode := GameState.get_game_mode()
	match mode:
		"world_cup", "tournament":
			if GameState.get_meta("is_knockout", false):
				get_tree().change_scene_to_file("res://scenes/menus/TournamentBracket.tscn")
			else:
				get_tree().change_scene_to_file("res://scenes/menus/GroupStage.tscn")
		_:
			get_tree().change_scene_to_file("res://scenes/MatchScene.tscn")

func _on_menu() -> void:
	_xp_rewarded = false
	_result_recorded = false
	MatchStatsTracker.reset()
	MatchEventBus.reset()
	var mode := GameState.get_game_mode()
	if mode in ["world_cup", "tournament"]:
		if GameState.get_meta("is_knockout", false):
			get_tree().change_scene_to_file("res://scenes/menus/TournamentBracket.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/menus/GroupStage.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")
