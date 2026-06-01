extends Node

# ============================================================
#  SquadControl.gd — Intelligent auto-switch for human squad
#  No manual switch button: pass → receiver, press → best tackler,
#  loose ball / teammate possession → nearest logical player.
# ============================================================

const SWITCH_COOLDOWN := 0.32
const PASS_SWITCH_DELAY := 0.02
const POSSESSION_SWITCH_DELAY := 0.12
const DEFENSIVE_REEVAL_INTERVAL := 0.45
const SWITCH_MARGIN := 2.8  # m — only swap defender if clearly better

var _manager: Node = null
var _squad: Array = []
var _human_team: int = 0
var _cooldown: float = 0.0
var _pending_target: Node = null
var _pending_timer: float = 0.0
var _defensive_timer: float = 0.0

func setup(manager: Node, squad: Array, human_team: int = 0) -> void:
	_manager = manager
	_squad = squad.duplicate()
	_human_team = human_team
	if not PossessionManager.possession_changed.is_connected(_on_possession_changed):
		PossessionManager.possession_changed.connect(_on_possession_changed)
	if MatchEventBus.has_signal("pass_attempted") and not MatchEventBus.pass_attempted.is_connected(_on_pass_attempted):
		MatchEventBus.pass_attempted.connect(_on_pass_attempted)
	if MatchEventBus.has_signal("tackle_won") and not MatchEventBus.tackle_won.is_connected(_on_tackle_won):
		MatchEventBus.tackle_won.connect(_on_tackle_won)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if _pending_timer > 0.0:
		_pending_timer -= delta
		if _pending_timer <= 0.0 and is_instance_valid(_pending_target):
			_apply_switch(_pending_target)
			_pending_target = null
	if GameState.is_training() or GameState.is_ai_vs_ai():
		return
	if GameState.phase != GameState.Phase.PLAY:
		return
	_defensive_timer -= delta
	if _defensive_timer <= 0.0:
		_defensive_timer = DEFENSIVE_REEVAL_INTERVAL
		_maybe_switch_defensive()

func schedule_pass_switch(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	# Immediate switch on pass — bypass defensive cooldown.
	if _manager and _manager.has_method("switch_control_to"):
		_manager.switch_control_to(target)

func request_defensive_switch() -> Node:
	var best := pick_best_tackler()
	if best == null:
		return _get_human()
	if _manager and _manager.has_method("switch_control_to"):
		_manager.switch_control_to(best)
	return best

func pick_best_tackler() -> Node:
	var ball_pos := _ball_pos()
	var carrier := PossessionManager.get_possessor()
	var best: Node = null
	var best_score: float = -999.0
	for p in _squad:
		if not is_instance_valid(p):
			continue
		if int(p.get("team_id")) != _human_team:
			continue
		var body := p as CharacterBody3D
		if body == null:
			continue
		var ts: Node = p.get_node_or_null("TackleSystem")
		if ts != null and (bool(ts.get("is_sliding")) or bool(ts.get("is_stumbling"))):
			continue
		var score: float = 0.0
		var to_ball: Vector3 = ball_pos - body.global_position
		to_ball.y = 0.0
		var dist_ball: float = to_ball.length()
		score += 14.0 / (dist_ball + 0.6)
		if carrier != null and is_instance_valid(carrier) and int(carrier.get("team_id")) != _human_team:
			var to_carrier: Vector3 = carrier.global_position - body.global_position
			to_carrier.y = 0.0
			score += 8.0 / (to_carrier.length() + 0.8)
			if dist_ball < 4.5 and to_ball.normalized().dot(to_carrier.normalized()) > 0.25:
				score += 1.2
		var role_bonus: float = 0.0
		var slot: int = int(p.get_meta("slot_index", 1))
		if slot == 1:
			role_bonus = 0.35
		elif slot == 0:
			role_bonus = 0.15
		elif slot == 2:
			var own_goal: Vector3 = PitchConstants.defend_goal_vec(_human_team)
			if body.global_position.distance_to(own_goal) > 8.0:
				role_bonus = -2.5
		score += role_bonus
		if score > best_score:
			best_score = score
			best = p
	return best

func _on_tackle_won(tackler_id: int, _opponent_id: int) -> void:
	for p in _squad:
		if is_instance_valid(p) and p.get_instance_id() == tackler_id:
			_apply_switch(p)
			return

func _on_pass_attempted(passer_id: int, target_id: int, _ptype: int) -> void:
	if target_id < 0:
		return
	for p in _squad:
		if is_instance_valid(p) and p.get_instance_id() == target_id:
			schedule_pass_switch(p)
			return

func _on_possession_changed(new_p: Node, _old_p: Node) -> void:
	if _cooldown > 0.0:
		return
	if new_p == null or not is_instance_valid(new_p):
		call_deferred("_maybe_switch_loose_ball")
		return
	if int(new_p.get("team_id")) != _human_team:
		return
	if new_p not in _squad:
		return
	var human := _get_human()
	if new_p == human:
		return
	_pending_target = new_p
	_pending_timer = POSSESSION_SWITCH_DELAY

func _maybe_switch_loose_ball() -> void:
	if _cooldown > 0.0:
		return
	if PossessionManager.get_possessor() != null:
		return
	var best := _closest_to_ball()
	if best != null:
		_apply_switch(best)

func _maybe_switch_defensive() -> void:
	if _cooldown > 0.0:
		return
	var carrier := PossessionManager.get_possessor()
	if carrier == null or not is_instance_valid(carrier):
		_maybe_switch_loose_ball()
		return
	if int(carrier.get("team_id")) == _human_team:
		return
	var human := _get_human()
	if human == null:
		return
	var best := pick_best_tackler()
	if best == null or best == human:
		return
	var ball_pos := _ball_pos()
	var human_dist: float = human.global_position.distance_to(ball_pos)
	var best_dist: float = best.global_position.distance_to(ball_pos)
	if human_dist - best_dist >= SWITCH_MARGIN:
		_apply_switch(best)

func _closest_to_ball() -> Node:
	var ball_pos := _ball_pos()
	var best: Node = null
	var best_d: float = 999.0
	for p in _squad:
		if not is_instance_valid(p):
			continue
		var body := p as Node3D
		if body == null:
			continue
		var d: float = body.global_position.distance_to(ball_pos)
		if d < best_d:
			best_d = d
			best = p
	return best

func _apply_switch(target: Node) -> void:
	if _cooldown > 0.0:
		return
	if not is_instance_valid(target) or target == _get_human():
		return
	if _manager and _manager.has_method("switch_control_to"):
		_manager.switch_control_to(target)
		_cooldown = SWITCH_COOLDOWN

func _get_human() -> Node:
	if _manager and "human_player" in _manager:
		return _manager.human_player
	return null

func _ball_pos() -> Vector3:
	if _manager and "ball_physics" in _manager and _manager.ball_physics:
		var bp = _manager.ball_physics
		if "ball_position" in bp:
			return bp.ball_position
		return bp.global_position
	return Vector3.ZERO
