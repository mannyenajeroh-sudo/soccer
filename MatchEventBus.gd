extends Node

# ============================================================
#  MatchEventBus.gd — STREET 3 ELITE  (Phase 4)
#
#  Central autoload event bus.  All gameplay systems emit here;
#  consumers (HUD, MatchStats, ProgressionSystem, SoundManager)
#  subscribe here.  This fully decouples producers from consumers.
#
#  Signal naming follows the original binary event identifiers:
#    MakeScore / OwnGoal / GoalRePlay
#    PassBallSuccess / PassBallFail / KeyPassBall / AheadPassBall
#    StatsAutoTackle / StatsTackle / StatsTackleSlide
#    InterceptPass / BreakAndPass
#    ReqBattleHighBallFightE (aerial contest)
#
#  Phase 4 wiring targets:
#    MatchManager   → goal_scored, match_phase_changed
#    KickSystem     → shot_taken, pass_attempted, pass_completed
#    TackleSystem   → tackle_attempted, tackle_won, tackle_failed
#    AerialMechanics→ aerial_contest_started, aerial_contest_won
#    SetPieces      → set_piece_started, set_piece_executed
#    SkillMoves     → skill_move_executed
#    PossessionManager → possession_changed
# ============================================================


# ─────────────────────────────────────────────────────────────
#  PASS TYPES  (mirrors PassType in reverse-engineering doc)
# ─────────────────────────────────────────────────────────────
enum PassType {
	FLOOR_CLOSE,   # PassFloorClose — short ground pass
	FLOOR_FLY,     # PassFloorFly  — driven ground pass
	HIGH_FLY,      # PassHighFly   — lofted ball
	FRONT_FLOOR,   # FrontFloorPass — forward ground pass
	FRONT_HIGH,    # FrontHighPass  — forward lofted pass
	AHEAD,         # AheadPassBall  — through ball
	KEY,           # KeyPassBall    — key pass (chance created)
}

# ─────────────────────────────────────────────────────────────
#  GOAL EVENTS — MakeScore / OwnGoal / GoalRePlay
# ─────────────────────────────────────────────────────────────
signal goal_scored(team_id: int, scorer_id: int, is_own_goal: bool)
signal goal_replay_trigger()
signal match_over(winner_team: int)

# ─────────────────────────────────────────────────────────────
#  PASS EVENTS
#  PassBallSuccess / PassBallFail / KeyPassBall / AheadPassBall
#  ObstructPassBall / InterceptPass / BreakAndPass / NoPassBall
# ─────────────────────────────────────────────────────────────
signal pass_attempted(passer_id: int, target_id: int, pass_type: PassType)
signal pass_completed(passer_id: int, target_id: int, xg_delta: float)
signal pass_failed(passer_id: int, reason: String)
signal key_pass_made(passer_id: int, target_id: int)
signal through_ball_played(passer_id: int, target_id: int)
signal pass_intercepted(interceptor_id: int, passer_id: int)

# ─────────────────────────────────────────────────────────────
#  SHOOTING EVENTS — ShootGoal / shot tracking
# ─────────────────────────────────────────────────────────────
signal shot_taken(shooter_id: int, power: float, xg: float)
signal shot_on_target(shooter_id: int, xg: float)
signal shot_missed(shooter_id: int)

# ─────────────────────────────────────────────────────────────
#  TACKLE EVENTS
#  StatsAutoTackle / StatsTackle / StatsTackleSlide
#  EffectiveTackleFail / InvalidTackle / StatsTakeBallTime
# ─────────────────────────────────────────────────────────────
signal tackle_attempted(tackler_id: int, target_id: int, is_slide: bool)
signal tackle_won(tackler_id: int, target_id: int)
signal tackle_failed(tackler_id: int)
signal tackle_invalid(tackler_id: int)   # foul
signal auto_tackle(tackler_id: int)      # StatsAutoTackle

# ─────────────────────────────────────────────────────────────
#  AERIAL EVENTS — ReqBattleHighBallFightE
#  HighBallFightPass / HighBallFightShoot / HighBallFightClearance
# ─────────────────────────────────────────────────────────────
signal aerial_contest_started(player_a_id: int, player_b_id: int)
signal aerial_contest_won(winner_id: int, loser_id: int)
signal aerial_header(player_id: int, outcome: String)   # "pass"/"shoot"/"clearance"

# ─────────────────────────────────────────────────────────────
#  POSSESSION EVENTS
# ─────────────────────────────────────────────────────────────
signal possession_changed(new_team_id: int, gaining_player_id: int)
signal ball_out_of_play(type: int, team_id: int, position: Vector3)

# ─────────────────────────────────────────────────────────────
#  MATCH FLOW EVENTS
# ─────────────────────────────────────────────────────────────
signal match_phase_changed(new_phase: int)
signal match_stats_updated(home_stats: Dictionary, away_stats: Dictionary)
signal match_kickoff(team_id: int)
signal match_halftime()

# ─────────────────────────────────────────────────────────────
#  SET PIECE EVENTS
# ─────────────────────────────────────────────────────────────
signal set_piece_triggered(sp_type: int, team_id: int, position: Vector3)
signal set_piece_played(sp_type: int, taker_id: int)
signal corner_kick(team_id: int)
signal goal_kick(team_id: int)
signal sideline_kick(team_id: int, position: Vector3)

# ─────────────────────────────────────────────────────────────
#  SKILL MOVE EVENTS
# ─────────────────────────────────────────────────────────────
signal skill_move_executed(player_id: int, skill: int)
signal skill_move_failed(player_id: int, skill: int)


# ─────────────────────────────────────────────────────────────
#  INTERNAL STAT ACCUMULATOR
#  Light per-team aggregates updated in real time.
#  Full per-player stats live in MatchStats resources (Phase 6).
# ─────────────────────────────────────────────────────────────
var _team_stats: Array[Dictionary] = [
	{ "goals": 0, "shots": 0, "passes": 0, "passes_completed": 0,
	  "tackles": 0, "tackles_won": 0, "interceptions": 0,
	  "possession_time": 0.0, "skills": 0 },
	{ "goals": 0, "shots": 0, "passes": 0, "passes_completed": 0,
	  "tackles": 0, "tackles_won": 0, "interceptions": 0,
	  "possession_time": 0.0, "skills": 0 },
]

# Possession timer — updated every frame
var _possession_holder: int = -1   # 0 or 1, -1 = loose
var _last_passer_id: Dictionary = { 0: -1, 1: -1 }  # team → last passer node ID

func _ready() -> void:
	# Self-connect to update _team_stats live
	goal_scored.connect(_on_goal_scored)
	shot_taken.connect(_on_shot_taken)
	pass_attempted.connect(_on_pass_attempted)
	pass_completed.connect(_on_pass_completed)
	tackle_attempted.connect(_on_tackle_attempted)
	tackle_won.connect(_on_tackle_won)
	pass_intercepted.connect(_on_interception)
	skill_move_executed.connect(_on_skill_executed)
	possession_changed.connect(_on_possession_changed)

func _process(delta: float) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	if _possession_holder >= 0 and _possession_holder <= 1:
		_team_stats[_possession_holder]["possession_time"] += delta


# ─────────────────────────────────────────────────────────────
#  CONVENIENCE EMITTERS
#  Systems call these instead of referencing signal names directly.
# ─────────────────────────────────────────────────────────────

## Emit goal_scored with automatic own-goal detection.
func emit_goal(scoring_team: int, scorer_node: Node, own_goal: bool = false) -> void:
	var sid := scorer_node.get_instance_id() if scorer_node else -1
	goal_scored.emit(scoring_team, sid, own_goal)
	_team_stats[scoring_team]["goals"] += 1

## Emit shot signal with xG calculation.
func emit_shot(shooter_node: Node, kick_power: float, team_id: int) -> void:
	var sid := shooter_node.get_instance_id() if shooter_node else -1
	var goal_pos := PitchConstants.attack_goal_vec(team_id)
	var xg := GameplayAI.get_xg(
		shooter_node.global_position if shooter_node else Vector3.ZERO,
		goal_pos
	)
	shot_taken.emit(sid, kick_power, xg)

## Emit a pass attempt with type auto-classification.
func emit_pass(passer_node: Node, direction: Vector3, power: float, is_lofted: bool, is_through: bool, target_node: Node = null) -> void:
	var pid := passer_node.get_instance_id() if passer_node else -1
	var tid := target_node.get_instance_id() if target_node != null and is_instance_valid(target_node) else -1
	var ptype: PassType
	if is_through:
		ptype = PassType.AHEAD
	elif is_lofted:
		ptype = PassType.HIGH_FLY if power > 0.6 else PassType.FRONT_HIGH
	elif power < 0.5:
		ptype = PassType.FLOOR_CLOSE
	else:
		ptype = PassType.FLOOR_FLY
	pass_attempted.emit(pid, tid, ptype)
	if is_through and tid >= 0:
		through_ball_played.emit(pid, tid)
	var team: int = passer_node.get("team_id") as int if passer_node else 0
	_last_passer_id[team] = pid

## Emit possession change.
func emit_possession_change(new_holder: Node) -> void:
	if new_holder == null:
		_possession_holder = -1
		return
	var team := new_holder.get("team_id") as int
	_possession_holder = team
	possession_changed.emit(team, new_holder.get_instance_id())

## Emit tackle attempt.
func emit_tackle(tackler: Node, target: Node, is_slide: bool) -> void:
	var tid := tackler.get_instance_id() if tackler else -1
	var oid := target.get_instance_id() if target else -1
	tackle_attempted.emit(tid, oid, is_slide)

## Emit tackle won.
func emit_tackle_won(tackler: Node, target: Node) -> void:
	var tid := tackler.get_instance_id() if tackler else -1
	var oid := target.get_instance_id() if target else -1
	tackle_won.emit(tid, oid)

## Emit skill executed.
func emit_skill(player_node: Node, skill: int) -> void:
	var pid := player_node.get_instance_id() if player_node else -1
	skill_move_executed.emit(pid, skill)


# ─────────────────────────────────────────────────────────────
#  STAT LISTENERS
# ─────────────────────────────────────────────────────────────

func _on_goal_scored(_team_id: int, _scorer_id: int, _own_goal: bool) -> void:
	# Goals counted once in emit_goal() — avoid double-counting bus stats.
	pass

func _on_shot_taken(_shooter_id: int, _power: float, _xg: float) -> void:
	# Can't determine team from ID here without player registry
	# Full stats tracked in MatchStats (Phase 6)
	pass

func _on_pass_attempted(_passer_id: int, _target_id: int, _ptype: PassType) -> void:
	pass

func _on_pass_completed(passer_id: int, _target_id: int, _xg_delta: float) -> void:
	# Find team by passer_id
	for team in range(2):
		if _last_passer_id[team] == passer_id:
			_team_stats[team]["passes_completed"] += 1

func _on_tackle_attempted(tackler_id: int, _target_id: int, _is_slide: bool) -> void:
	pass

func _on_tackle_won(_tackler_id: int, _target_id: int) -> void:
	pass

func _on_interception(_interceptor_id: int, _passer_id: int) -> void:
	pass

func _on_skill_executed(_player_id: int, _skill: int) -> void:
	pass

func _on_possession_changed(new_team_id: int, _gaining_player_id: int) -> void:
	_possession_holder = new_team_id


# ─────────────────────────────────────────────────────────────
#  QUERY HELPERS
# ─────────────────────────────────────────────────────────────

## Returns a snapshot of both teams' live stats.
func get_team_stats() -> Array[Dictionary]:
	return _team_stats

func get_possession_percent(team_id: int) -> float:
	var total: float = _team_stats[0]["possession_time"] + _team_stats[1]["possession_time"]
	if total < 0.001:
		return 50.0
	return (_team_stats[team_id]["possession_time"] / total) * 100.0

func reset() -> void:
	for i in range(2):
		_team_stats[i] = {
			"goals": 0, "shots": 0, "passes": 0, "passes_completed": 0,
			"tackles": 0, "tackles_won": 0, "interceptions": 0,
			"possession_time": 0.0, "skills": 0
		}
	_possession_holder = -1
	_last_passer_id = { 0: -1, 1: -1 }
