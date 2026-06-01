class_name MatchStats
extends Resource

# ============================================================
#  MatchStats.gd — STREET 3 ELITE  (Phase 6)
#
#  Per-player stat accumulator. Wired to MatchEventBus signals
#  so every game event auto-updates the correct stat.
#
#  Confirmed tracking events from binary:
#    MakeScore / OwnGoal
#    PassBallSuccess / PassBallFail / KeyPassBall / AheadPassBall
#    StatsAutoTackle / StatsTackle / StatsTackleSlide
#    InterceptPass / EffectiveTackleFail / InvalidTackle
#    StatsTakeBallTime
#    ReqBattleHighBallFightE (aerial contests)
#    SkillMove executions
# ============================================================

# ── Goals & Shooting ─────────────────────────────────────────
var goals:               int   = 0
var own_goals:           int   = 0
var assists:             int   = 0
var shots:               int   = 0
var shots_on_target:     int   = 0

# ── Passing ───────────────────────────────────────────────────
var passes_attempted:    int   = 0
var passes_completed:    int   = 0
var key_passes:          int   = 0
var through_balls:       int   = 0

# ── Defending ─────────────────────────────────────────────────
var tackles_attempted:   int   = 0
var tackles_won:         int   = 0
var tackles_lost:        int   = 0
var slide_tackles:       int   = 0
var auto_tackles:        int   = 0
var fouls_committed:     int   = 0
var interceptions:       int   = 0

# ── Aerial ────────────────────────────────────────────────────
var aerial_contests:     int   = 0
var aerial_won:          int   = 0

# ── Possession / Movement ────────────────────────────────────
var possession_time:     float = 0.0   # seconds holding ball
var distance_covered:    float = 0.0   # metres total

# ── Skills ───────────────────────────────────────────────────
var skill_moves_executed: int  = 0

# ── Misc (StatsTakeBallTime) ──────────────────────────────────
var take_ball_time:       float = 0.0

# ─────────────────────────────────────────────────────────────
#  DERIVED STATS
# ─────────────────────────────────────────────────────────────

func get_pass_completion_pct() -> float:
	if passes_attempted == 0: return 0.0
	return float(passes_completed) / passes_attempted * 100.0

func get_tackle_success_pct() -> float:
	if tackles_attempted == 0: return 0.0
	return float(tackles_won) / tackles_attempted * 100.0

func get_shot_accuracy_pct() -> float:
	if shots == 0: return 0.0
	return float(shots_on_target) / shots * 100.0

func get_aerial_win_pct() -> float:
	if aerial_contests == 0: return 0.0
	return float(aerial_won) / aerial_contests * 100.0

# ─────────────────────────────────────────────────────────────
#  SERIALISATION
# ─────────────────────────────────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"goals":                goals,
		"own_goals":            own_goals,
		"assists":              assists,
		"shots":                shots,
		"shots_on_target":      shots_on_target,
		"passes_attempted":     passes_attempted,
		"passes_completed":     passes_completed,
		"pass_completion_pct":  get_pass_completion_pct(),
		"key_passes":           key_passes,
		"through_balls":        through_balls,
		"tackles_attempted":    tackles_attempted,
		"tackles_won":          tackles_won,
		"slide_tackles":        slide_tackles,
		"auto_tackles":         auto_tackles,
		"fouls_committed":      fouls_committed,
		"interceptions":        interceptions,
		"aerial_contests":      aerial_contests,
		"aerial_won":           aerial_won,
		"possession_time":      possession_time,
		"distance_covered":     distance_covered,
		"skill_moves":          skill_moves_executed,
	}

func reset() -> void:
	goals = 0;          own_goals = 0;         assists = 0
	shots = 0;          shots_on_target = 0
	passes_attempted = 0; passes_completed = 0
	key_passes = 0;     through_balls = 0
	tackles_attempted = 0; tackles_won = 0;    tackles_lost = 0
	slide_tackles = 0;  auto_tackles = 0;      fouls_committed = 0
	interceptions = 0
	aerial_contests = 0; aerial_won = 0
	possession_time = 0.0; distance_covered = 0.0
	skill_moves_executed = 0; take_ball_time = 0.0
