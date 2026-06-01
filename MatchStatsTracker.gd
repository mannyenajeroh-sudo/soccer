extends Node

# ============================================================
#  MatchStatsTracker.gd — STREET 3 ELITE  (Phase 6)
#
#  Autoload singleton.  Subscribes to every MatchEventBus signal
#  and maintains per-player MatchStats resources.  Also tracks
#  team-level aggregates for the post-match screen.
#
#  Usage:
#    MatchStatsTracker.get_player_stats(player_id)  → MatchStats
#    MatchStatsTracker.get_team_stats(team_id)      → Dictionary
#    MatchStatsTracker.get_match_summary()          → Dictionary
#    MatchStatsTracker.reset()                      — call on match start
# ============================================================

# player instance_id → MatchStats
var _player_stats: Dictionary = {}
# team_id (0/1) → aggregated Dictionary
var _team_agg: Array[Dictionary] = [
	_empty_team_dict(),
	_empty_team_dict(),
]

# Instance-id → player node (weak refs for distance tracking)
var _player_nodes: Dictionary = {}
var _last_positions: Dictionary = {}

# Scorer of the last pass → tracks assist
var _last_passer_per_team: Dictionary = { 0: -1, 1: -1 }

# ─────────────────────────────────────────────────────────────
#  LIFECYCLE
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	# Connect to MatchEventBus — Phase 6 wires every signal
	MatchEventBus.goal_scored.connect(_on_goal_scored)
	MatchEventBus.shot_taken.connect(_on_shot_taken)
	MatchEventBus.shot_on_target.connect(_on_shot_on_target)
	MatchEventBus.pass_attempted.connect(_on_pass_attempted)
	MatchEventBus.pass_completed.connect(_on_pass_completed)
	MatchEventBus.pass_failed.connect(_on_pass_failed)
	MatchEventBus.key_pass_made.connect(_on_key_pass)
	MatchEventBus.through_ball_played.connect(_on_through_ball)
	MatchEventBus.pass_intercepted.connect(_on_interception)
	MatchEventBus.tackle_attempted.connect(_on_tackle_attempted)
	MatchEventBus.tackle_won.connect(_on_tackle_won)
	MatchEventBus.tackle_failed.connect(_on_tackle_failed)
	MatchEventBus.tackle_invalid.connect(_on_tackle_invalid)
	MatchEventBus.auto_tackle.connect(_on_auto_tackle)
	MatchEventBus.aerial_contest_started.connect(_on_aerial_started)
	MatchEventBus.aerial_contest_won.connect(_on_aerial_won)
	MatchEventBus.skill_move_executed.connect(_on_skill_executed)
	MatchEventBus.possession_changed.connect(_on_possession_changed)

func _process(delta: float) -> void:
	# Track distance covered per player each frame
	for pid in _player_nodes.keys():
		var node: Node = _player_nodes.get(pid)
		if node == null or not is_instance_valid(node):
			_player_nodes.erase(pid)
			continue
		var cur_pos: Vector3 = node.global_position
		if pid in _last_positions:
			var moved: float = cur_pos.distance_to(_last_positions[pid])
			# Cap per-frame movement to avoid teleport spikes
			if moved < 2.0:
				var stats := _get_or_create(pid)
				stats.distance_covered += moved
		_last_positions[pid] = cur_pos

# ─────────────────────────────────────────────────────────────
#  PUBLIC API
# ─────────────────────────────────────────────────────────────

## Register a player node so distance tracking works.
## Called by MatchManager after spawning each player.
func register_player(player_node: Node, team_id: int) -> void:
	var pid := player_node.get_instance_id()
	_player_nodes[pid] = player_node
	_last_positions[pid] = player_node.global_position
	var stats := _get_or_create(pid)
	# Tag with team for aggregate lookups
	stats.set_meta("team_id", team_id)

## Returns the MatchStats resource for a player (by instance_id).
func get_player_stats(player_id: int) -> MatchStats:
	return _get_or_create(player_id)

## Returns aggregated team stats Dictionary for team 0 or 1.
func get_team_stats(team_id: int) -> Dictionary:
	_rebuild_team_agg(team_id)
	return _team_agg[team_id]

## Returns a full match summary including both teams and all players.
func get_match_summary() -> Dictionary:
	_rebuild_team_agg(0)
	_rebuild_team_agg(1)
	var player_list: Array[Dictionary] = []
	for pid in _player_stats.keys():
		var ps: MatchStats = _player_stats[pid]
		var d := ps.to_dict()
		d["player_id"] = pid
		d["team_id"]   = ps.get_meta("team_id", -1)
		player_list.append(d)
	return {
		"team_0": _team_agg[0],
		"team_1": _team_agg[1],
		"players": player_list,
	}

## Reset all stats — call at match start.
func reset() -> void:
	_player_stats.clear()
	_player_nodes.clear()
	_last_positions.clear()
	_last_passer_per_team = { 0: -1, 1: -1 }
	_team_agg[0] = _empty_team_dict()
	_team_agg[1] = _empty_team_dict()

# ─────────────────────────────────────────────────────────────
#  SIGNAL HANDLERS — one per MatchEventBus event
# ─────────────────────────────────────────────────────────────

func _on_goal_scored(team_id: int, scorer_id: int, is_own_goal: bool) -> void:
	if scorer_id < 0: return
	var s := _get_or_create(scorer_id)
	if is_own_goal:
		s.own_goals += 1
	else:
		s.goals += 1
	# Assist: last passer on the scoring team
	var last_passer: int = _last_passer_per_team.get(team_id, -1)
	if last_passer >= 0 and last_passer != scorer_id:
		_get_or_create(last_passer).assists += 1

func _on_shot_taken(shooter_id: int, _power: float, _xg: float) -> void:
	_get_or_create(shooter_id).shots += 1

func _on_shot_on_target(shooter_id: int, _xg: float) -> void:
	_get_or_create(shooter_id).shots_on_target += 1

func _on_pass_attempted(passer_id: int, _target_id: int, _pass_type) -> void:
	_get_or_create(passer_id).passes_attempted += 1
	# Infer team from node registry
	var node: Node = _player_nodes.get(passer_id)
	if node:
		_last_passer_per_team[node.get("team_id")] = passer_id

func _on_pass_completed(passer_id: int, _target_id: int, _xg_delta: float) -> void:
	_get_or_create(passer_id).passes_completed += 1

func _on_pass_failed(passer_id: int, _reason: String) -> void:
	# passes_attempted already incremented by _on_pass_attempted
	pass

func _on_key_pass(passer_id: int, _target_id: int) -> void:
	_get_or_create(passer_id).key_passes += 1

func _on_through_ball(passer_id: int, _target_id: int) -> void:
	_get_or_create(passer_id).through_balls += 1

func _on_interception(interceptor_id: int, _passer_id: int) -> void:
	_get_or_create(interceptor_id).interceptions += 1

func _on_tackle_attempted(tackler_id: int, _target_id: int, is_slide: bool) -> void:
	var s := _get_or_create(tackler_id)
	s.tackles_attempted += 1
	if is_slide:
		s.slide_tackles += 1

func _on_tackle_won(tackler_id: int, _target_id: int) -> void:
	_get_or_create(tackler_id).tackles_won += 1

func _on_tackle_failed(tackler_id: int) -> void:
	_get_or_create(tackler_id).tackles_lost += 1

func _on_tackle_invalid(tackler_id: int) -> void:
	_get_or_create(tackler_id).fouls_committed += 1

func _on_auto_tackle(tackler_id: int) -> void:
	var s := _get_or_create(tackler_id)
	s.auto_tackles += 1
	s.tackles_won  += 1   # auto-tackle always wins

func _on_aerial_started(player_a_id: int, _player_b_id: int) -> void:
	_get_or_create(player_a_id).aerial_contests += 1

func _on_aerial_won(winner_id: int, _loser_id: int) -> void:
	_get_or_create(winner_id).aerial_won += 1

func _on_skill_executed(player_id: int, _skill: int) -> void:
	_get_or_create(player_id).skill_moves_executed += 1

func _on_possession_changed(_new_team_id: int, _gaining_player_id: int) -> void:
	# Possession time is tracked by MatchEventBus internally;
	# distance_covered is tracked per-frame above
	pass

# ─────────────────────────────────────────────────────────────
#  HELPERS
# ─────────────────────────────────────────────────────────────

func _get_or_create(player_id: int) -> MatchStats:
	if not _player_stats.has(player_id):
		_player_stats[player_id] = MatchStats.new()
	return _player_stats[player_id]

func _rebuild_team_agg(team_id: int) -> void:
	var agg := _empty_team_dict()
	for pid in _player_stats.keys():
		var ps: MatchStats = _player_stats[pid]
		if ps.get_meta("team_id", -1) != team_id:
			continue
		agg["goals"]            += ps.goals
		agg["own_goals"]        += ps.own_goals
		agg["shots"]            += ps.shots
		agg["shots_on_target"]  += ps.shots_on_target
		agg["passes_attempted"] += ps.passes_attempted
		agg["passes_completed"] += ps.passes_completed
		agg["key_passes"]       += ps.key_passes
		agg["through_balls"]    += ps.through_balls
		agg["tackles_won"]      += ps.tackles_won
		agg["interceptions"]    += ps.interceptions
		agg["aerial_won"]       += ps.aerial_won
		agg["skill_moves"]      += ps.skill_moves_executed
		agg["distance_covered"] += ps.distance_covered
	# Pass completion %
	var pa: int = agg["passes_attempted"]
	var pc: int = agg["passes_completed"]
	agg["pass_completion_pct"] = (float(pc) / pa * 100.0) if pa > 0 else 0.0
	# Possession % — from MatchEventBus live tracker
	agg["possession_pct"] = MatchEventBus.get_possession_percent(team_id)
	_team_agg[team_id] = agg

static func _empty_team_dict() -> Dictionary:
	return {
		"goals": 0, "own_goals": 0,
		"shots": 0, "shots_on_target": 0,
		"passes_attempted": 0, "passes_completed": 0,
		"pass_completion_pct": 0.0,
		"key_passes": 0, "through_balls": 0,
		"tackles_won": 0, "interceptions": 0,
		"aerial_won": 0, "skill_moves": 0,
		"distance_covered": 0.0,
		"possession_pct": 0.0,
	}
