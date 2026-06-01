extends CanvasLayer

# ============================================================
#  AdvancedTouchControls.gd — Android-ready mobile controls
#  Left half:  dynamic joystick (any-touch-position)
#  Right half: action buttons (Shoot, Pass, Sprint/Skill, Tackle)
#  All buttons use InputEventScreenTouch for real multi-touch.
#
#  FIXES:
#   - Proportional button layout — safe on any screen size
#   - Shoot button shows charge arc (fills clockwise, orange→white)
#   - Sprint label updated to communicate multi-function
#   - Joystick zone is < 45% width to avoid centre conflicts
# ============================================================

const DOUBLE_TAP_WINDOW  := 0.28
const HOLD_THRESHOLD     := 0.18
const CHARGE_FLASH_FREQ  := 8.0

const COL_SHOOT   := Color(0.95, 0.30, 0.10, 0.82)
const COL_PASS    := Color(0.05, 0.65, 0.95, 0.82)
const COL_SPRINT  := Color(0.55, 0.10, 0.88, 0.82)
const COL_TACKLE  := Color(0.95, 0.75, 0.05, 0.82)
const COL_PRESSED := Color(1.0,  1.0,  1.0,  0.95)

# ---- Touch state ----
var _js_touch_idx    := -1
var _js_center       := Vector2.ZERO
var _js_active       := false

# Button touch tracking — each button owns a touch finger index
var _btn_touch: Dictionary = {}  # action_name → touch_index

# Button nodes for visual feedback
var _btns: Dictionary = {}  # action_name → ColorRect

# Dynamic label/color management for merged buttons
var _btn_labels: Dictionary = {}
var _btn_colors: Dictionary = {}
var _last_has_possession: bool = false

# Tap tracking
var _last_tap:    Dictionary = {}
var _down_time:   Dictionary = {}
var _shoot_charging := false
var _charge_flash_t := 0.0
var _charge_value   := 0.0   # 0–1, received from player
var _close_control_active := false
var _touch_in_use := false

# Joystick visual nodes
var _js_base: Control = null
var _js_knob: Control = null
const JS_MAX_R := 70.0

func _ready() -> void:
	set_process_input(true)
	_build_ui()
	# Enable multi-touch
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, false)

func _build_ui() -> void:
	var root := Control.new()
	root.name = "TouchUI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ---- Left: Joystick base (invisible until touched) ----
	_js_base = Control.new()
	_js_base.name = "JSBase"
	_js_base.size = Vector2(JS_MAX_R * 2.0 + 20.0, JS_MAX_R * 2.0 + 20.0)
	_js_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_js_base.draw.connect(_draw_js_base)
	root.add_child(_js_base)

	_js_knob = Control.new()
	_js_knob.name = "JSKnob"
	_js_knob.size = Vector2(50.0, 50.0)
	_js_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_js_knob.draw.connect(_draw_js_knob)
	root.add_child(_js_knob)

	# ---- Right: Action buttons — proportional diamond layout ----
	# All positions are % of screen height so they're safe on any resolution.
	# Diamond:   SPRINT (top)
	#       TACKLE    (middle-left)
	#            SHOOT (middle-right)
	#        PASS (bottom)
	var vp := get_viewport().get_visible_rect().size

	var shoot_r  := vp.y * 0.072   # ~78px on 1080p landscape
	var other_r  := vp.y * 0.058   # ~63px

	# Anchor the cluster: shoot sits near bottom-right
	var sx := vp.x - vp.y * 0.14
	var sy := vp.y * 0.82

	_make_btn(root, "shoot",   "SHOOT",      Vector2(sx,              sy),              COL_SHOOT,  shoot_r)
	_make_btn(root, "pass",    "PASS",        Vector2(sx - vp.y * 0.14, sy + vp.y * 0.04), COL_PASS,   other_r)
	_make_btn(root, "sprint",  "RUN ★",      Vector2(sx,              sy - vp.y * 0.20), COL_SPRINT, other_r)

func _make_btn(parent: Control, action: String, label: String,
		center_pos: Vector2, col: Color, radius: float) -> void:
	_btn_labels[action] = label
	_btn_colors[action] = col
	var btn := Control.new()
	btn.name = action + "_btn"
	btn.size = Vector2(radius * 2.0, radius * 2.0)
	btn.position = center_pos - Vector2(radius, radius)
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := radius; var act := action
	btn.draw.connect(func():
		var ctr := btn.size * 0.5
		var pressed: bool = _btns.has(act) and _btn_touch.get(act, -1) >= 0
		var c: Color = _btn_colors.get(act, col)
		var lbl: String = _btn_labels.get(act, label)
		var draw_col: Color = c.lightened(0.35) if pressed else c
		# Outer glow ring
		btn.draw_arc(ctr, r - 2.0, 0.0, TAU, 64, draw_col.lightened(0.2), 4.0, true)
		# Fill
		btn.draw_circle(ctr, r - 6.0, draw_col)
		# Inner highlight
		btn.draw_circle(ctr + Vector2(0, -r * 0.25), r * 0.35, Color(1,1,1,0.15))

		# ---- Shoot charge arc (fills clockwise, orange → white) ----
		if act == "shoot" and _shoot_charging and _charge_value > 0.02:
			var arc_col: Color = Color(1.0, lerpf(0.35, 1.0, _charge_value), 0.0, 0.92)
			var arc_end: float = -PI * 0.5 + TAU * _charge_value
			btn.draw_arc(ctr, r - 4.0, -PI * 0.5, arc_end, 48, arc_col, 5.0, true)
			# Flash bright ring at full charge
			if _charge_value >= 0.95:
				btn.draw_arc(ctr, r - 2.0, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.85), 3.0, true)

		# Label
		var font := ThemeDB.fallback_font
		var fs := int(r * 0.28)
		var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		btn.draw_string(font, ctr + Vector2(-tw * 0.5, fs * 0.35), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

		# Sprint sub-label: hint at hold/double-tap actions
		if act == "sprint":
			var hint := "hold: control  •  ×2: skill  •  auto-switch"
			var hfs := int(r * 0.16)
			var htw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
			btn.draw_string(font, ctr + Vector2(-htw * 0.5, r + hfs * 1.2), hint,
				HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, Color(1.0, 1.0, 1.0, 0.6))
	)
	parent.add_child(btn)
	_btns[action] = btn
	_btn_touch[action] = -1
	_last_tap[action] = -99.0
	_down_time[action] = 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_screen_touch(event)
	elif event is InputEventScreenDrag:
		_on_screen_drag(event)

func _on_screen_touch(event: InputEventScreenTouch) -> void:
	var pos := event.position
	var vp_w := get_viewport().get_visible_rect().size.x

	if event.pressed:
		_touch_in_use = true
		# Left 45% → joystick  (10% dead band prevents accidental joystick on centre taps)
		if pos.x < vp_w * 0.45:
			if _js_touch_idx == -1:
				_js_touch_idx = event.index
				_js_center = pos
				_js_active = true
				_js_base.position = pos - _js_base.size * 0.5
				_js_knob.position = pos - _js_knob.size * 0.5
				_js_base.queue_redraw()
				_js_knob.queue_redraw()
		else:
			# Right side → check each button
			_try_claim_button(event.index, pos)
	else:
		# Released
		if event.index == _js_touch_idx:
			_js_touch_idx = -1
			_js_active = false
			_inject_axis(Vector2.ZERO)
			_js_base.queue_redraw()
			_js_knob.queue_redraw()
		else:
			_release_button_by_touch(event.index)

func _on_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index == _js_touch_idx:
		var delta := event.position - _js_center
		var dist := delta.length()
		if dist > JS_MAX_R:
			delta = delta.normalized() * JS_MAX_R
		_js_knob.position = _js_center + delta - _js_knob.size * 0.5
		var raw := delta / JS_MAX_R
		_inject_axis(raw)
		_js_knob.queue_redraw()

func _try_claim_button(touch_idx: int, pos: Vector2) -> void:
	for action in _btns.keys():
		var btn: Control = _btns[action]
		if _btn_touch[action] >= 0:
			continue  # Already claimed
		var btn_center := btn.global_position + btn.size * 0.5
		var r := btn.size.x * 0.5 + 20.0  # slightly enlarged hit area
		if pos.distance_to(btn_center) < r:
			_btn_touch[action] = touch_idx
			_down_time[action] = _now()
			_on_button_pressed(action)
			btn.queue_redraw()
			return

func _release_button_by_touch(touch_idx: int) -> void:
	for action in _btn_touch.keys():
		if _btn_touch[action] == touch_idx:
			_btn_touch[action] = -1
			_on_button_released(action)
			if _btns.has(action):
				_btns[action].queue_redraw()
			return

func _on_button_pressed(action: String) -> void:
	match action:
		"shoot":
			_inject(action, true)
			_shoot_charging = false
			_charge_flash_t = 0.0
			_charge_value   = 0.0
		"sprint":
			_inject("sprint", true)
		"pass":
			_inject("pass", true)
		"tackle":
			_inject_action_once("tackle")

func _on_button_released(action: String) -> void:
	var hold: float = _now() - _down_time.get(action, 0.0)
	match action:
		"shoot":
			_inject("shoot", false)
			_shoot_charging = false
			_charge_value   = 0.0
			if _btns.has("shoot"):
				_btns["shoot"].queue_redraw()
		"sprint":
			_inject("sprint", false)
			# Check for double-tap → skill
			var since_last: float = _now() - (_last_tap.get("sprint", -99.0) as float)
			if hold < HOLD_THRESHOLD and since_last < DOUBLE_TAP_WINDOW:
				_execute_contextual_skill()
			_last_tap["sprint"] = _now()
		"pass":
			_inject("pass", false)
			var since_last: float = _now() - (_last_tap.get("pass", -99.0) as float)
			if hold < HOLD_THRESHOLD and since_last < DOUBLE_TAP_WINDOW:
				_inject_action_once("through_pass")
			_last_tap["pass"] = _now()

func _process(delta: float) -> void:
	# Contextual PASS / PRESS dynamic button updates
	var has_possession := _team_has_possession()
	if has_possession != _last_has_possession:
		_last_has_possession = has_possession
		if has_possession:
			_btn_labels["pass"] = "PASS"
			_btn_colors["pass"] = COL_PASS
		else:
			_btn_labels["pass"] = "PRESS"
			_btn_colors["pass"] = COL_TACKLE
		if _btns.has("pass"):
			_btns["pass"].queue_redraw()

	# Only synthesize close_control while touch UI is active — never spam keyboard input on desktop.
	if not _touch_in_use and _js_touch_idx < 0 and not _any_touch_button_held():
		if _close_control_active:
			_close_control_active = false
			_inject("close_control", false)
		return

	var want_close := false
	if _btn_touch.get("sprint", -1) >= 0:
		var held: float = _now() - (_down_time.get("sprint", 0.0) as float)
		if held > HOLD_THRESHOLD:
			want_close = true
	if want_close != _close_control_active:
		_close_control_active = want_close
		_inject("close_control", want_close)

	# Shoot charge → read from PlayerController signal / track locally
	if _btn_touch.get("shoot", -1) >= 0:
		var held: float = _now() - (_down_time.get("shoot", 0.0) as float)
		if held > HOLD_THRESHOLD:
			_shoot_charging = true
			# Estimate charge progress (0→1 over ~1.2s) if no signal available
			_charge_value = clampf((held - HOLD_THRESHOLD) / 1.2, 0.0, 1.0)
	if _shoot_charging and _btns.has("shoot"):
		_charge_flash_t += delta * CHARGE_FLASH_FREQ
		_btns["shoot"].queue_redraw()

func _get_human_player() -> Node:
	var parent := get_parent()
	if parent and "human_player" in parent:
		return parent.human_player
	return null

func _team_has_possession() -> bool:
	var p := _get_human_player()
	if p == null or not is_instance_valid(p):
		return false
	var possessor := PossessionManager.get_possessor()
	if possessor != null and is_instance_valid(possessor):
		return possessor.team_id == p.team_id
	return false

# Called by PlayerController's charge_updated signal if wired
func set_charge(v: float) -> void:
	_charge_value = clampf(v, 0.0, 1.0)
	if _btns.has("shoot"):
		_btns["shoot"].queue_redraw()

func _execute_contextual_skill() -> void:
	var stick := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if stick.length() > 0.5:
		if absf(stick.x) > absf(stick.y):
			_inject_action_once("skill_stepover")
		else:
			_inject_action_once("skill_flick")
	else:
		_inject_action_once("skill_roulette")

# ---- Helpers ----
func _any_touch_button_held() -> bool:
	for v in _btn_touch.values():
		if int(v) >= 0:
			return true
	return false

func _inject_axis(out: Vector2) -> void:
	_set_axis("move_left",  "move_right", -out.x)
	_set_axis("move_up",    "move_down",   out.y)

func _set_axis(neg: StringName, pos_action: StringName, val: float) -> void:
	var en := InputEventAction.new(); en.action = neg
	en.strength = maxf(0.0, -val); en.pressed = en.strength > 0.0
	Input.parse_input_event(en)
	var ep := InputEventAction.new(); ep.action = pos_action
	ep.strength = maxf(0.0, val); ep.pressed = ep.strength > 0.0
	Input.parse_input_event(ep)

func _inject(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action; ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)

func _inject_action_once(action: StringName) -> void:
	var ev_down := InputEventAction.new()
	ev_down.action = action; ev_down.pressed = true
	Input.parse_input_event(ev_down)
	get_tree().create_timer(0.05, false).timeout.connect(func():
		var ev_up := InputEventAction.new()
		ev_up.action = action; ev_up.pressed = false
		Input.parse_input_event(ev_up)
	)

func _now() -> float:
	return Time.get_ticks_msec() * 0.001

# ---- Joystick draw callbacks ----
func _draw_js_base() -> void:
	if not _js_active: return
	var c := _js_base.size * 0.5
	var r := JS_MAX_R
	_js_base.draw_circle(c, r, Color(0.0, 0.6, 1.0, 0.12))
	_js_base.draw_arc(c, r, 0.0, TAU, 64, Color(0.0, 0.8, 1.0, 0.22), 5.0, true)
	_js_base.draw_arc(c, r, 0.0, TAU, 64, Color(0.0, 0.95, 1.0, 0.75), 2.0, true)
	_js_base.draw_circle(c, r * 0.18, Color(0.0, 0.8, 1.0, 0.10))

func _draw_js_knob() -> void:
	if not _js_active: return
	var c := _js_knob.size * 0.5
	var r := _js_knob.size.x * 0.5
	_js_knob.draw_circle(c, r, Color(0.0, 0.7, 1.0, 0.92))
	_js_knob.draw_circle(c + Vector2(0, -r * 0.25), r * 0.38, Color(1.0, 1.0, 1.0, 0.88))
