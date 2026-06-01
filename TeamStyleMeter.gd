extends Node

# ============================================================
#  TeamStyleMeter.gd — Street flair / buildup meter (0–100 per team)
#  Fills on passes, skills, dribble turns, chained possession.
#  Decays slowly when play is stagnant.
# ============================================================

signal style_changed(team_id: int, value: float, peak: bool)

const MAX_STYLE := 100.0
const DECAY_RATE := 4.5          # per second when idle
const CHAIN_WINDOW := 2.8        # seconds to chain possession bonus

const GAIN_PASS := 8.0
const GAIN_KEY_PASS := 14.0
const GAIN_SKILL := 12.0
const GAIN_SHOT_ON_TARGET := 6.0
const GAIN_POSSESSION_CHAIN := 3.5
const GAIN_DRIBBLE_TURN := 4.0

var _style: Array[float] = [0.0, 0.0]
var _chain_team: int = -1
var _chain_timer: float = 0.0
var _last_touch_team: int = -1

func _ready() -> void:
	if MatchEventBus.has_signal("pass_attempted"):
		MatchEventBus.pass_attempted.connect(_on_pass_attempted)
	if MatchEventBus.has_signal("skill_move_executed"):
		MatchEventBus.skill_move_executed.connect(_on_skill)
	if MatchEventBus.has_signal("shot_on_target"):
		MatchEventBus.shot_on_target.connect(_on_shot_on_target)
	PossessionManager.possession_changed.connect(_on_possession_changed)

func _process(delta: float) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	if _chain_timer > 0.0:
		_chain_timer -= delta
		if _chain_timer <= 0.0:
			_chain_team = -1
	for i in 2:
		if _style[i] > 0.0:
			var prev := _style[i]
			_style[i] = maxf(0.0, _style[i] - DECAY_RATE * delta)
			if absf(_style[i] - prev) > 0.05:
				style_changed.emit(i, _style[i], _style[i] >= 85.0)

func get_style(team_id: int) -> float:
	if team_id < 0 or team_id > 1:
		return 0.0
	return _style[team_id]

func add_style(team_id: int, amount: float) -> void:
	if team_id < 0 or team_id > 1 or amount <= 0.0:
		return
	var prev := _style[team_id]
	_style[team_id] = clampf(_style[team_id] + amount, 0.0, MAX_STYLE)
	if _style[team_id] != prev:
		style_changed.emit(team_id, _style[team_id], _style[team_id] >= 85.0)

func reset() -> void:
	_style = [0.0, 0.0]
	_chain_team = -1
	_chain_timer = 0.0
	_last_touch_team = -1
	style_changed.emit(0, 0.0, false)
	style_changed.emit(1, 0.0, false)

func _on_pass_attempted(_passer_id: int, _target_id: int, ptype: int) -> void:
	var team := _last_touch_team
	if team < 0:
		return
	var gain := GAIN_PASS
	if ptype == MatchEventBus.PassType.AHEAD or ptype == MatchEventBus.PassType.KEY:
		gain = GAIN_KEY_PASS
	add_style(team, gain)

func _on_skill(_player_id: int, _skill: int) -> void:
	if _last_touch_team >= 0:
		add_style(_last_touch_team, GAIN_SKILL)

func _on_shot_on_target(_shooter_id: int, _xg: float) -> void:
	if _last_touch_team >= 0:
		add_style(_last_touch_team, GAIN_SHOT_ON_TARGET)

func _on_possession_changed(new_possessor: Node, _old: Node) -> void:
	if new_possessor == null:
		_chain_team = -1
		return
	var team: int = new_possessor.get("team_id") as int
	_last_touch_team = team
	if team == _chain_team:
		add_style(team, GAIN_POSSESSION_CHAIN)
		_chain_timer = CHAIN_WINDOW
	else:
		_chain_team = team
		_chain_timer = CHAIN_WINDOW

func register_dribble_turn(team_id: int) -> void:
	add_style(team_id, GAIN_DRIBBLE_TURN)
