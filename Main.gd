extends Control

@onready var start_menu: Control = $StartMenu
@onready var match_end: Control = $MatchEnd

# Start Menu references
@onready var mode_btn: Button = $StartMenu/VBoxContainer/ModeButton
@onready var play_btn: Button = $StartMenu/VBoxContainer/PlayButton
@onready var diff_btn: Button = $StartMenu/VBoxContainer/DifficultyButton
@onready var title_lbl: Label = $StartMenu/VBoxContainer/Title

# Match End references
@onready var result_lbl: Label = $MatchEnd/VBoxContainer/ResultLabel
@onready var xp_lbl: Label = $MatchEnd/VBoxContainer/XPLabel
@onready var xp_bar: ProgressBar = $MatchEnd/VBoxContainer/XPBar
@onready var double_xp_btn: Button = $MatchEnd/VBoxContainer/DoubleXPButton
@onready var rematch_btn: Button = $MatchEnd/VBoxContainer/RematchButton
@onready var menu_btn: Button = $MatchEnd/VBoxContainer/MenuButton

var base_xp_earned := 0
var double_xp_claimed := false
var current_difficulty := 1 # 0: EASY, 1: MEDIUM, 2: HARD
var ai_vs_ai_mode := false

func _ready() -> void:
	# Style UI elements procedurally for a premium neon-dark aesthetic
	_style_ui()

	# Load difficulty from metadata if available
	if GameState.has_meta("difficulty"):
		current_difficulty = GameState.get_meta("difficulty")
	else:
		GameState.set_meta("difficulty", current_difficulty)
	_update_difficulty_button_text()
	if GameState.is_ai_vs_ai():
		ai_vs_ai_mode = true
	_update_mode_ui()

	# Connect Start Menu signals
	mode_btn.pressed.connect(_on_mode_pressed)
	play_btn.pressed.connect(_on_play_pressed)
	diff_btn.pressed.connect(_on_difficulty_pressed)

	# Connect Match End signals
	double_xp_btn.pressed.connect(_on_double_xp_pressed)
	rematch_btn.pressed.connect(_on_rematch_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	
	# Connect AdMob reward signal if autoloaded and valid
	if AdMobBridge:
		AdMobBridge.reward_earned.connect(_on_admob_reward_earned)

	# Decide which screen to show
	if GameState.phase == GameState.Phase.FULLTIME:
		_show_match_end()
	else:
		_show_start_menu()

func _style_ui() -> void:
	# Stylize title with deep neon cyan color and thin shadow
	title_lbl.add_theme_color_override("font_color", Color(0.0, 0.8, 1.0))
	title_lbl.add_theme_font_size_override("font_size", 80)
	
	# Create premium styled flat boxes for buttons
	var style_play := _create_button_style(Color(0.0, 0.6, 0.9), Color(0.0, 0.8, 1.0))
	var style_diff := _create_button_style(Color(0.2, 0.2, 0.3), Color(0.3, 0.3, 0.45))
	var style_double_xp := _create_button_style(Color(0.9, 0.6, 0.0), Color(1.0, 0.75, 0.0))
	var style_normal_btn := _create_button_style(Color(0.15, 0.15, 0.25), Color(0.25, 0.25, 0.4))
	
	play_btn.add_theme_stylebox_override("normal", style_play)
	play_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.0, 0.7, 1.0), Color(0.1, 0.9, 1.0)))
	play_btn.add_theme_stylebox_override("pressed", style_play)
	
	diff_btn.add_theme_stylebox_override("normal", style_diff)
	diff_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.25, 0.25, 0.38), Color(0.35, 0.35, 0.55)))
	diff_btn.add_theme_stylebox_override("pressed", style_diff)

	mode_btn.add_theme_stylebox_override("normal", style_diff)
	mode_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.25, 0.25, 0.38), Color(0.35, 0.35, 0.55)))
	mode_btn.add_theme_stylebox_override("pressed", style_diff)
	
	double_xp_btn.add_theme_stylebox_override("normal", style_double_xp)
	double_xp_btn.add_theme_stylebox_override("hover", _create_button_style(Color(1.0, 0.7, 0.0), Color(1.0, 0.85, 0.2)))
	double_xp_btn.add_theme_stylebox_override("pressed", style_double_xp)
	
	rematch_btn.add_theme_stylebox_override("normal", style_play)
	rematch_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.0, 0.7, 1.0), Color(0.1, 0.9, 1.0)))
	rematch_btn.add_theme_stylebox_override("pressed", style_play)
	
	menu_btn.add_theme_stylebox_override("normal", style_normal_btn)
	menu_btn.add_theme_stylebox_override("hover", _create_button_style(Color(0.2, 0.2, 0.32), Color(0.3, 0.3, 0.48)))
	menu_btn.add_theme_stylebox_override("pressed", style_normal_btn)

	# Style the ProgressBar
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.15)
	sb_bg.corner_radius_top_left = 6
	sb_bg.corner_radius_top_right = 6
	sb_bg.corner_radius_bottom_left = 6
	sb_bg.corner_radius_bottom_right = 6
	
	var sb_fg := StyleBoxFlat.new()
	sb_fg.bg_color = Color(0.0, 0.9, 0.5) # sleek emerald green
	sb_fg.corner_radius_top_left = 6
	sb_fg.corner_radius_top_right = 6
	sb_fg.corner_radius_bottom_left = 6
	sb_fg.corner_radius_bottom_right = 6
	
	xp_bar.add_theme_stylebox_override("background", sb_bg)
	xp_bar.add_theme_stylebox_override("fill", sb_fg)

func _create_button_style(color: Color, border_color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = border_color
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 4
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _show_start_menu() -> void:
	start_menu.visible = true
	match_end.visible = false
	play_btn.grab_focus()

func _show_match_end() -> void:
	start_menu.visible = false
	match_end.visible = true
	double_xp_claimed = false
	double_xp_btn.disabled = false
	double_xp_btn.text = "2x XP (WATCH AD)"
	rematch_btn.grab_focus()
	
	var blue := GameState.score[0]
	var red := GameState.score[1]
	var spectator := GameState.is_ai_vs_ai()

	if spectator:
		if blue > red:
			result_lbl.text = "BLUE WINS  %d – %d" % [blue, red]
			result_lbl.add_theme_color_override("font_color", Color(0.2, 0.55, 1.0))
		elif red > blue:
			result_lbl.text = "RED WINS  %d – %d" % [blue, red]
			result_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		else:
			result_lbl.text = "DRAW  %d – %d" % [blue, red]
			result_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		base_xp_earned = 25 + (blue + red) * 15
	else:
		var won := blue > red
		var draw := blue == red
		if won:
			result_lbl.text = "VICTORY! %d - %d" % [blue, red]
			result_lbl.add_theme_color_override("font_color", Color(0.0, 0.9, 0.4))
		elif draw:
			result_lbl.text = "DRAW MATCH %d - %d" % [blue, red]
			result_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		else:
			result_lbl.text = "DEFEAT %d - %d" % [blue, red]
			result_lbl.add_theme_color_override("font_color", Color(0.95, 0.2, 0.25))
		var win_bonus := 100 if won else (50 if draw else 0)
		base_xp_earned = win_bonus + blue * 50
	
	# Apply progression XP rewards
	ProgressionSystem.add_xp(base_xp_earned)
	
	# Update XP Label & Progress Bar
	_update_xp_display()

func _update_xp_display() -> void:
	var current_lvl := ProgressionSystem.level
	var current_xp := ProgressionSystem.xp
	var needed_xp := current_lvl * current_lvl * 50
	
	xp_lbl.text = "LEVEL %d\nXP: %d / %d (+%d XP)" % [current_lvl, current_xp, needed_xp, base_xp_earned * (2 if double_xp_claimed else 1)]
	
	xp_bar.max_value = needed_xp
	xp_bar.value = current_xp

func _update_difficulty_button_text() -> void:
	var diff_labels := ["DIFFICULTY: EASY", "DIFFICULTY: MEDIUM", "DIFFICULTY: HARD"]
	diff_btn.text = diff_labels[current_difficulty]

func _update_mode_ui() -> void:
	if ai_vs_ai_mode:
		mode_btn.text = "MODE: AI vs AI (WATCH)"
		play_btn.text = "WATCH MATCH"
	else:
		mode_btn.text = "MODE: YOU vs AI"
		play_btn.text = "PLAY MATCH"

func _on_mode_pressed() -> void:
	ai_vs_ai_mode = not ai_vs_ai_mode
	GameState.set_match_mode(
		GameState.MATCH_MODE_AI_VS_AI if ai_vs_ai_mode else GameState.MATCH_MODE_HUMAN
	)
	_update_mode_ui()

func _on_play_pressed() -> void:
	GameState.set_match_mode(
		GameState.MATCH_MODE_AI_VS_AI if ai_vs_ai_mode else GameState.MATCH_MODE_HUMAN
	)
	GameState.set_meta("game_mode", GameState.MODE_ARCADE)
	GameState.configure_match("ARG", "BRA", false)
	GameState.set_phase_direct(GameState.Phase.PREGAME)
	GameState.score = [0, 0]
	GameState.timer = GameState.MATCH_DURATION
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MatchScene.tscn")

func _on_difficulty_pressed() -> void:
	current_difficulty = (current_difficulty + 1) % 3
	GameState.set_meta("difficulty", current_difficulty)
	_update_difficulty_button_text()

func _on_double_xp_pressed() -> void:
	if double_xp_claimed: return
	double_xp_btn.disabled = true
	double_xp_btn.text = "LOADING AD..."

	if AdMobBridge and AdMobBridge.is_ready():
		# Trigger real rewarded ad
		AdMobBridge.show_rewarded_ad()
	else:
		# Fallback Mock Ad: simulating playing a video ad for 1.2 seconds
		await get_tree().create_timer(1.2).timeout
		_on_double_xp_rewarded()

func _on_admob_reward_earned(_type: String, _amount: int) -> void:
	_on_double_xp_rewarded()

func _on_double_xp_rewarded() -> void:
	if double_xp_claimed: return
	double_xp_claimed = true
	double_xp_btn.text = "2x XP CLAIMED! ✓"
	
	# Reward user with an additional batch of XP
	ProgressionSystem.add_xp(base_xp_earned)
	
	# Refresh UI display
	_update_xp_display()

func _on_rematch_pressed() -> void:
	_on_play_pressed()

func _on_menu_pressed() -> void:
	# Reset phase to PREGAME and show start menu
	GameState.set_phase_direct(GameState.Phase.PREGAME)
	_show_start_menu()
