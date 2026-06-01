extends Node

enum Phase { PREGAME, KICKOFF, PLAY, FREEKICK, CORNER, GOAL_KICK, SIDELINE, PENALTY, GOAL, HALFTIME, FULLTIME }

signal phase_changed(new_phase: Phase)
signal score_changed(team_a: int, team_b: int)
signal timer_tick(remaining: float)
signal match_ended(winner: int)

const MATCH_DURATION := 90.0  # 90s — snappy for mobile testing; feels intense on a tight pitch
const MATCH_MODE_HUMAN := "human"
const MATCH_MODE_AI_VS_AI := "ai_vs_ai"

var phase: Phase = Phase.PREGAME
var score: Array[int] = [0, 0]
var timer: float = MATCH_DURATION
var last_scoring_team: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not has_meta("match_mode"):
		set_meta("match_mode", MATCH_MODE_HUMAN)

func is_ai_vs_ai() -> bool:
	return get_meta("match_mode", MATCH_MODE_HUMAN) == MATCH_MODE_AI_VS_AI

func set_match_mode(mode: String) -> void:
	set_meta("match_mode", mode)

func start_match() -> void:
	score = [0, 0]
	timer = MATCH_DURATION
	last_scoring_team = 0
	_set_phase(Phase.PLAY)
	score_changed.emit(score[0], score[1])
	timer_tick.emit(timer)

func set_play() -> void:
	_set_phase(Phase.PLAY)

func goal_scored(team: int) -> void:
	if phase == Phase.GOAL or phase == Phase.FULLTIME:
		return
	# Training is freestyle — no competitive scoring.
	if is_training():
		return
	if team == 0 or team == 1:
		score[team] += 1
	last_scoring_team = team
	score_changed.emit(score[0], score[1])
	if get_meta("sudden_death", false) and score[0] != score[1]:
		set_meta("sudden_death_decided", true)
	_set_phase(Phase.GOAL)

func resume_from_goal() -> void:
	if get_meta("sudden_death_decided", false):
		remove_meta("sudden_death_decided")
		remove_meta("sudden_death")
		_end_match()
		return
	_set_phase(Phase.PLAY)

func is_training() -> bool:
	return get_meta("game_mode", MODE_ARCADE) == MODE_TRAINING

func start_training() -> void:
	score = [0, 0]
	timer = 99999.0
	last_scoring_team = 0
	_set_phase(Phase.PLAY)
	score_changed.emit(score[0], score[1])
	timer_tick.emit(timer)

func _process(delta: float) -> void:
	if phase != Phase.PLAY:
		return
	if get_tree().paused:
		return
	if is_training():
		return
	timer = maxf(0.0, timer - delta)
	timer_tick.emit(timer)
	if timer <= 0.0:
		_end_match()

func get_time_string() -> String:
	var t := int(timer)
	return "%d:%02d" % [t / 60, t % 60]

func _set_phase(p: Phase) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)

## Public alias for _set_phase — used by SetPieces, GameplayRules.
## Prefer using the specific helper methods (goal_scored, etc.) where possible.
func set_phase_direct(p: Phase) -> void:
	_set_phase(p)

# ── World Cup Expansion additions ────────────────────────────
const MODE_ARCADE      := "arcade"
const MODE_WORLD_CUP   := "world_cup"
const MODE_TOURNAMENT  := "tournament"
const MODE_ONLINE      := "online"
const MODE_TRAINING    := "training"

var home_team_id:       String = ""
var away_team_id:       String = ""
var is_knockout:        bool   = false
var extra_time:         bool   = false
var penalty_shootout:   bool   = false

signal extra_time_started
signal penalty_shootout_started

func configure_match(home: String, away: String, knockout: bool = false) -> void:
	home_team_id     = home
	away_team_id     = away
	is_knockout      = knockout
	extra_time       = false
	penalty_shootout = false
	score            = [0, 0]
	timer            = MATCH_DURATION
	_set_phase(Phase.PREGAME)

func _end_match() -> void:
	if is_knockout and score[0] == score[1] and not extra_time and not penalty_shootout:
		_start_extra_time()
		return
	elif is_knockout and score[0] == score[1] and extra_time and not penalty_shootout:
		_start_penalties()
		return
	_set_phase(Phase.FULLTIME)
	var winner := -1
	if score[0] > score[1]:   winner = 0
	elif score[1] > score[0]: winner = 1
	match_ended.emit(winner)

func _start_extra_time() -> void:
	extra_time = true
	timer = 60.0   # 1 min extra time (street scale)
	extra_time_started.emit()
	_set_phase(Phase.PLAY)

func _start_penalties() -> void:
	penalty_shootout = true
	penalty_shootout_started.emit()
	# Sudden-death extra time until dedicated shootout UI ships.
	timer = 45.0
	_set_phase(Phase.PLAY)
	set_meta("sudden_death", true)

func get_game_mode() -> String:
	return get_meta("game_mode", MODE_ARCADE)
