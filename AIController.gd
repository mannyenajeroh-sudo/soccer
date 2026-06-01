extends Node

# ============================================================
#  AIController.gd — STREET 3 ELITE  (Phase 5)
#
#  Full AI state machine with all confirmed states from the
#  Street Football binary reverse-engineering report.
#
#  New in Phase 5:
#   - Formal AIState enum matching binary state names exactly
#   - GK_SAVE, GK_DISTRIBUTE with positional awareness
#   - HIGH_FIGHT_WAIT / HIGH_FIGHT_MOVE aerial contest states
#   - FORCE_OFFBALL_FAST / MANMARK / ACCELERATE support states
#   - SET_PIECE_TAKER / SET_PIECE_RUNNER for set pieces
#   - INTERCEPT_PASS / INTERCEPT_WAIT interception window
#   - Dynamic stamina-gated sprinting per role
#   - All stub implementations filled in with real logic
#   - MatchEventBus wired: all AI actions emit correct events
#   - Phase guard: no AI activity in GOAL/FULLTIME states
# ============================================================

enum AIState {
	WAIT,
	MOVE_TO_BALL,
	TAKE_BALL,
	DRIBBLE_WITH_BALL,
	PASS_BALL,
	SHOOT_BALL,
	INTERCEPT_PASS,
	INTERCEPT_WAIT,
	MANMARK_OPPONENT,
	HIGH_FIGHT_WAIT,
	HIGH_FIGHT_MOVE,
	FORCE_OFFBALL_FAST,
	FORCE_OFFBALL_MANMARK,
	FORCE_OFFBALL_ACCELERATE,
	GK_SAVE,
	GK_DISTRIBUTE,
	SET_PIECE_TAKER,
	SET_PIECE_RUNNER,
	CLEAR_BALL,
	CHIP_SHOT,
	AERIAL_VOLLEY,
	BICYCLE_KICK,
	SKILL_EXECUTE,
}

@export var player: CharacterBody3D
@export var ball: Node
@export var team_id: int = 1
@export var reaction_delay: float = 0.45
@export var is_chaser: bool = false
@export var role: String = "midfielder"
@export var showcase_mode: bool = false
@export var tackling_stat: float = 0.5
@export var aggression: float = 0.5   # 0=passive Easy, 1=aggressive Hard

const ARRIVE_RADIUS   := 3.0
const AVOID_RADIUS    := 2.0
const SHOOT_DIST      := 20.0
const TACKLE_DIST     := 2.4
const PICKUP_DIST     := 0.85
const PASS_MIN_DIST   := 2.2
const PASS_MAX_DIST   := 17.5  # Tuned for 24m-wide 3v3 cage
const FORCE_PASS_HOLD := 1.15  # Recycle possession before hogging
const SPRINT_DIST     := 6.0

const SPREAD_RADIUS   := 4.5
const SPREAD_FORCE    := 2.0
const ANTICIPATE_TIME := 0.22

# GK constants
const GK_DIVE_RANGE       := 5.0   # m from goal centre to dive toward ball
const GK_POSITION_OFFSET  := 1.4   # m off goal line when ball is far
const GK_DISTRIBUTE_WAIT  := 0.6   # s to hold before distributing

# Aerial/high fight constants
const AERIAL_ACTIVATE_HEIGHT := 0.65   # min ball height to enter HIGH_FIGHT
const AERIAL_CONTEST_RANGE   := 2.8

# Intercept constants
const INTERCEPT_RANGE        := 4.5    # m — AI reads passing lanes in this radius
const INTERCEPT_WAIT_TIME    := 0.45   # how long to hold INTERCEPT_WAIT before acting

# Offball constants
const OFFBALL_ACCEL_DIST     := 8.0    # trigger ACCELERATE when this far from ideal spot

var state: AIState = AIState.WAIT

# --- legacy string decision (kept for _execute_decision compatibility) ---
var _decision       := "support"
var _decision_timer := 0.0
var _goal_pos       := Vector3.ZERO
var _own_goal       := Vector3.ZERO
var _teammates: Array = []
var _frame_count    := 0
var _did_action     := false
var _reaction_variance := 1.0
var _shot_align_timer  := 0.0
const SHOT_ALIGN_REQUIRED := 0.06
var ai_skill: float = 0.5

# Phase 5 state vars
var _intercept_wait_timer: float = 0.0
var _gk_distribute_timer:  float = 0.0
var _set_piece_assigned:   bool  = false
var _last_state: AIState = AIState.WAIT
var _ball_hold_timer: float = 0.0
var _forced_pass_target: Node = null
var _intent_target: Vector3 = Vector3.ZERO
var _use_intent_target: bool = false
const FORMATION_SPREAD := 0.78  # Soccer-course SPREAD_ASSIST_FACTOR

func _ready() -> void:
	_goal_pos = PitchConstants.attack_goal_vec(team_id)
	_own_goal = PitchConstants.defend_goal_vec(team_id)
	_reaction_variance = randf_range(0.80, 1.20)
	if showcase_mode and player:
		player.player_rating = 0.95
	_sync_from_player_stats()
	call_deferred("_collect_teammates")

func _sync_from_player_stats() -> void:
	if player == null:
		return
	var s: PlayerStats = player.get("stats") as PlayerStats
	if s == null:
		return
	reaction_delay  = s.get_reaction_delay()
	tackling_stat   = s.get_tackling_stat()
	ai_skill        = s.get_overall_rating()

func _collect_teammates() -> void:
	_teammates = get_tree().get_nodes_in_group("players")

func set_teammates(mates: Array) -> void:
	_teammates = mates

func _physics_process(delta: float) -> void:
	_frame_count += 1
	if player == null or not is_instance_valid(player):
		return
	if ball == null:
		return

	if GameState.phase != GameState.Phase.PLAY:
		# Reset state timers so AI is ready when play resumes
		_shot_align_timer = 0.0
		_intercept_wait_timer = 0.0
		return

	if _try_pass_run(delta):
		return

	var ball_pos: Vector3 = _ball_pos()
	var dist_to_ball: float = player.global_position.distance_to(ball_pos)

	# Skip every-other-frame for far players (perf optimisation)
	if dist_to_ball > 24.0 and _frame_count % 2 != 0:
		return

	# Always try pickup — instant, no decision budget required
	_try_pickup_ball(dist_to_ball)

	if PossessionManager.has_ball(player):
		_ball_hold_timer += delta
		_prime_breaking_runner()
		if player.has_meta("pass_requested_by"):
			_handle_pass_request()
		if role == "goalkeeper":
			_gk_distribute_timer += delta
	else:
		_ball_hold_timer = 0.0
		if role == "goalkeeper":
			_gk_distribute_timer = 0.0

	# Decision refresh
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_update_ai_state()
		_decision_timer = reaction_delay * _role_delay_mult() * _reaction_variance
		_did_action = false

	# Sprint management
	_update_ai_sprint(dist_to_ball)

	# Execute current state
	_execute_state(delta)

# ─────────────────────────────────────────────────────────────
#  STATE SELECTION — maps situation to AIState enum
# ─────────────────────────────────────────────────────────────

func _update_ai_state() -> void:
	var has_ball: bool    = PossessionManager.has_ball(player)
	var ball_pos: Vector3 = _ball_pos()
	_use_intent_target = false

	if _set_piece_assigned:
		return

	var intent: Dictionary
	if role == "goalkeeper":
		intent = AIDecisionTrees.decide_gk(self, has_ball, ball_pos)
	elif has_ball:
		intent = AIDecisionTrees.decide_ball_carrier(self)
	elif _team_has_possession():
		_ball_hold_timer = 0.0
		intent = AIDecisionTrees.decide_support(self)
	else:
		_ball_hold_timer = 0.0
		intent = AIDecisionTrees.decide_defend(self, ball_pos)

	intent = AIDecisionTrees.apply_fidelity(intent, AIBlackboard.decision_fidelity, self)
	_apply_intent(intent)

func _apply_intent(intent: Dictionary) -> void:
	if intent.is_empty():
		return
	var new_state: AIState = intent.get("state", state)
	if new_state != state:
		_did_action = false
		_shot_align_timer = 0.0
	state = new_state
	_decision = str(intent.get("decision", _decision))
	if intent.has("target"):
		var t: Variant = intent["target"]
		if t is Node:
			_forced_pass_target = t as Node
		elif t is Vector3:
			_intent_target = t as Vector3
			_use_intent_target = true
	if intent.get("decision", "") == "through_pass" and _forced_pass_target == null:
		_forced_pass_target = intent.get("target") as Node

func _decide_gk(ball_pos: Vector3, has_ball: bool) -> void:
	_apply_intent(AIDecisionTrees.decide_gk(self, has_ball, ball_pos))
	if has_ball and state == AIState.GK_DISTRIBUTE:
		_gk_distribute_timer += get_process_delta_time()

func _decide_with_ball(ball_pos: Vector3) -> void:
	# Defensive third → clear immediately
	if GameplayAI.is_defensive_third(ball_pos, _own_goal):
		state = AIState.CLEAR_BALL
		_decision = "clear"
		return

	# Aerial opportunity
	var bp_y: float = ball_pos.y
	if bp_y > 0.65 and bp_y < 2.6:
		if bp_y > 1.8 and showcase_mode and randf() < 0.35:
			state = AIState.BICYCLE_KICK
			_decision = "bicycle"
			return
		if bp_y > 0.9 and randf() < 0.45:
			state = AIState.AERIAL_VOLLEY
			_decision = "aerial"
			return

	var dist_goal: float  = player.global_position.distance_to(_goal_pos)
	var shoot_val: float  = GameplayAI.action_weight(player.global_position, _goal_pos, team_id, _role_mult_float())
	var pass_val: float   = GameplayAI.get_best_pass_value(_teammates, _goal_pos, team_id)
	var dribble_val: float = GameplayAI.get_best_dribble_value(player.global_position, _goal_pos, team_id, role)
	var xg: float         = GameplayAI.get_xg(player.global_position, _goal_pos)

	# Bible: holding too long → always pass (build-up street football)
	if _ball_hold_timer >= FORCE_PASS_HOLD and pass_val > 0.08:
		state = AIState.PASS_BALL
		_decision = "pass"
		return

	var shoot_bias: float   = lerpf(1.20, 1.05, aggression)
	var pass_bias: float    = lerpf(1.45, 0.95, aggression)
	var xg_threshold: float = lerpf(0.18, 0.08, aggression)
	if showcase_mode:
		pass_bias *= 1.75
		shoot_bias *= 0.72
		xg_threshold *= 0.55

	# Chip opportunity (rarer in showcase — prefer passing triangles)
	if dist_goal < 14.0 and randf() < (0.10 if showcase_mode else 0.18):
		state = AIState.CHIP_SHOT
		_decision = "chip"
		return

	# Pass before shoot when buildup is available (Bible: pass when teammate open)
	if pass_val * pass_bias > max(dribble_val, shoot_val * shoot_bias * 0.85) and dist_goal > 5.0:
		state = AIState.PASS_BALL
		_decision = "pass"
		return

	# Shoot only in good positions (angle + distance)
	var to_goal := (_goal_pos - player.global_position)
	to_goal.y = 0.0
	var angle_ok := true
	if to_goal.length_squared() > 0.01:
		var fwd := -player.transform.basis.z
		fwd.y = 0.0
		angle_ok = rad_to_deg(fwd.angle_to(to_goal.normalized())) < 52.0

	if dist_goal < 14.5 and angle_ok and shoot_val > dribble_val * shoot_bias:
		if xg > xg_threshold or dist_goal < 8.5:
			state = AIState.SHOOT_BALL
			_decision = "shoot"
			return

	# Skill move in showcase mode
	if showcase_mode and randf() < _skill_chance():
		state = AIState.SKILL_EXECUTE
		_decision = "skill"
		return

	# Default: dribble
	state = AIState.DRIBBLE_WITH_BALL
	_decision = "dribble"

func _decide_support(ball_pos: Vector3) -> void:
	var dist_to_ideal: float = player.global_position.distance_to(_support_position_weighted())

	if role == "striker":
		state = AIState.FORCE_OFFBALL_ACCELERATE
		_decision = "run"
	elif dist_to_ideal > OFFBALL_ACCEL_DIST:
		state = AIState.FORCE_OFFBALL_ACCELERATE
		_decision = "support"
	elif role == "midfielder" and randf() < 0.22 and _find_opponent_to_manmark() != null:
		state = AIState.FORCE_OFFBALL_MANMARK
		_decision = "mark"
	else:
		state = AIState.FORCE_OFFBALL_FAST
		_decision = "support"

func _decide_defend(ball_pos: Vector3) -> void:
	# Check intercept opportunity — is the ball heading toward us?
	if _can_intercept():
		if state != AIState.INTERCEPT_PASS:
			state = AIState.INTERCEPT_WAIT
			_intercept_wait_timer = 0.0
		return

	# Aerial contest (any outfield role)
	if ball_pos.y > AERIAL_ACTIVATE_HEIGHT and _is_near_ball(AERIAL_CONTEST_RANGE):
		state = AIState.HIGH_FIGHT_MOVE
		return

	match role:
		"striker":
			# Press loose balls in attacking half; otherwise hold width for through balls
			if _should_striker_press(ball_pos):
				state = AIState.MOVE_TO_BALL
				_decision = "press"
			else:
				state = AIState.FORCE_OFFBALL_FAST
				_decision = "support"
		"midfielder":
			if _should_chase_ball(ball_pos):
				state = AIState.MOVE_TO_BALL
				_decision = "seek_ball"
			elif _is_closest_teammate_to_ball() and player.global_position.distance_to(ball_pos) < 10.0:
				state = AIState.TAKE_BALL
				_decision = "close_down"
			else:
				state = AIState.FORCE_OFFBALL_FAST
				_decision = "support"
		"goalkeeper":
			state = AIState.GK_SAVE
		_:
			if _should_chase_ball(ball_pos):
				state = AIState.MOVE_TO_BALL
			else:
				state = AIState.MANMARK_OPPONENT
				_decision = "mark"

# ─────────────────────────────────────────────────────────────
#  STATE EXECUTION
# ─────────────────────────────────────────────────────────────

func _execute_state(delta: float) -> void:
	match state:
		AIState.WAIT:
			pass  # Idle — no movement
		AIState.MOVE_TO_BALL:
			_move_toward_ball(delta)
		AIState.TAKE_BALL:
			_move_toward_ball(delta)
			var tackle_range: float = lerpf(TACKLE_DIST * 0.7, TACKLE_DIST * 1.2, aggression)
			if player.global_position.distance_to(_ball_pos()) < tackle_range:
				_try_tackle()
		AIState.DRIBBLE_WITH_BALL:
			_dribble(delta)
		AIState.PASS_BALL:
			if not _did_action and PossessionManager.has_ball(player):
				_attempt_pass()
			else:
				_seek(_weighted_attack_target(), delta)
		AIState.SHOOT_BALL:
			_face_toward(_goal_pos, delta)
			if not _did_action and PossessionManager.has_ball(player):
				_shot_align_timer += delta
				if _shot_align_timer >= SHOT_ALIGN_REQUIRED:
					_attempt_shot()
					_shot_align_timer = 0.0
			else:
				_shot_align_timer = 0.0
		AIState.CHIP_SHOT:
			_face_toward(_goal_pos, delta)
			if not _did_action and PossessionManager.has_ball(player):
				_do_chip()
		AIState.INTERCEPT_WAIT:
			_wait_for_intercept(delta)
		AIState.INTERCEPT_PASS:
			_intercept(delta)
		AIState.MANMARK_OPPONENT:
			_manmark(delta)
		AIState.HIGH_FIGHT_WAIT:
			_wait_for_aerial()
		AIState.HIGH_FIGHT_MOVE:
			_contest_aerial(delta)
		AIState.FORCE_OFFBALL_FAST:
			_sprint_to_space(delta)
		AIState.FORCE_OFFBALL_MANMARK:
			_shadow_opponent(delta)
		AIState.FORCE_OFFBALL_ACCELERATE:
			_accelerate_to_space(delta)
		AIState.GK_SAVE:
			_goalkeeper_save(delta)
		AIState.GK_DISTRIBUTE:
			_goalkeeper_distribute()
		AIState.SET_PIECE_TAKER:
			_set_piece_take()
		AIState.SET_PIECE_RUNNER:
			_set_piece_run(delta)
		AIState.CLEAR_BALL:
			_execute_clear()
		AIState.AERIAL_VOLLEY:
			if not _did_action:
				_do_aerial()
		AIState.BICYCLE_KICK:
			if not _did_action:
				_do_bicycle()
		AIState.SKILL_EXECUTE:
			if not _did_action and PossessionManager.has_ball(player):
				_do_skill_move()
			else:
				_seek(_weighted_attack_target(), delta)

# ─────────────────────────────────────────────────────────────
#  STATE IMPLEMENTATIONS — all previously stubbed functions
# ─────────────────────────────────────────────────────────────

## MOVE_TO_BALL — anticipate and chase the ball
func _move_toward_ball(delta: float) -> void:
	_seek(_anticipate_ball_pos(), delta)
	# Opportunistic standing tackle while closing in
	var tackle_range: float = lerpf(TACKLE_DIST * 0.7, TACKLE_DIST * 1.2, aggression)
	if player.global_position.distance_to(_ball_pos()) < tackle_range:
		_try_tackle()

## DRIBBLE_WITH_BALL — drive toward goal with spread-aware pathfinding
func _dribble(delta: float) -> void:
	var best_dir := GameplayAI.best_direction(player.global_position, _goal_pos, team_id, role)
	_seek(player.global_position + best_dir * 4.0, delta)
	# Opportunistic skill move while dribbling in showcase
	if showcase_mode and PossessionManager.has_ball(player) and randf() < 0.018:
		_do_skill_move()

## PASS_BALL — find best target and execute pass
func _handle_pass_request() -> void:
	var req_id := int(player.get_meta("pass_requested_by", -1))
	player.remove_meta("pass_requested_by")
	if req_id < 0:
		return
	var requester := instance_from_id(req_id)
	if requester == null or not is_instance_valid(requester):
		return
	if requester.get("team_id") != team_id:
		return
	_forced_pass_target = requester
	state = AIState.PASS_BALL
	_decision = "pass"
	_did_action = false

func _attempt_pass() -> void:
	var mate: CharacterBody3D = null
	if _forced_pass_target != null and is_instance_valid(_forced_pass_target):
		mate = _forced_pass_target as CharacterBody3D
		_forced_pass_target = null
	if mate == null:
		mate = _find_breaking_line_target()
	if mate == null:
		mate = _find_pass_target()
	var kick_sys  := player.get_node_or_null("KickSystem")
	if kick_sys == null: return
	if mate == null:
		var wide := Vector3(signf(player.global_position.x) * -1.0, 0.0, 0.0)
		var space_dir := ((_goal_pos - player.global_position) * 0.55 + wide * 0.45)
		space_dir.y = 0.0
		if space_dir.length_squared() < 0.01:
			space_dir = (_goal_pos - player.global_position)
			space_dir.y = 0.0
		kick_sys.ground_pass(space_dir.normalized(), randf_range(0.62, 0.82))
		_did_action = true
		return

	var dir: Vector3 = mate.global_position - player.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		_did_action = true
		return

	# Lead pass — offset toward where teammate will be
	var mate_vel := Vector3.ZERO
	if "velocity" in mate:
		mate_vel = mate.velocity as Vector3
	var lead_time    := dir.length() / 14.0
	var lead_target  := mate.global_position + (mate_vel * lead_time * 0.6)
	var lead_dir     := (lead_target - player.global_position)
	lead_dir.y = 0.0
	if lead_dir.length() > 0.1:
		dir = lead_dir

	var tp: Node = player.get_node_or_null("ThroughPass")
	var mate_spd: float = mate.get_speed() if mate.has_method("get_speed") else 0.0
	if _decision == "through_pass" and tp:
		if tp.find_and_execute(_teammates):
			_did_action = true
			return
	if tp and (dir.length() > 7.0 or showcase_mode) and mate_spd > 1.0:
		if tp.find_and_execute(_teammates):
			_did_action = true
			return

	var pass_power := 0.78 if _decision == "through_pass" else 0.70
	lead_target.y = player.global_position.y
	if kick_sys.has_method("ground_pass_to"):
		kick_sys.ground_pass_to(lead_target, pass_power)
	else:
		kick_sys.ground_pass(dir.normalized(), pass_power)
	_did_action = true

func _prime_breaking_runner() -> void:
	if _ball_hold_timer < 0.18:
		return
	if player == null or not PossessionManager.has_ball(player):
		return
	var runner := _find_breaking_line_target()
	if runner == null:
		return
	var run_target := _breaking_run_target(runner)
	runner.set_meta("pass_run_target", run_target)
	runner.set_meta("pass_run_mode", "through")
	runner.set_meta("pass_run_expires", Time.get_ticks_msec() * 0.001 + 2.2)
	runner.set_meta("pass_run_sprint", true)
	if _ball_hold_timer > 0.48:
		_forced_pass_target = runner
		_decision = "through_pass"
		state = AIState.PASS_BALL
		_did_action = false

func _find_breaking_line_target() -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_score := -999.0
	if player == null:
		return null
	var my_pos := player.global_position
	var to_goal := _goal_pos - my_pos
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.01:
		return null
	to_goal = to_goal.normalized()
	for mate in _teammates:
		var p := mate as CharacterBody3D
		if p == null or p == player or not is_instance_valid(p):
			continue
		if int(p.get("team_id")) != team_id:
			continue
		var mate_ai := p.get_node_or_null("AIController")
		if mate_ai and str(mate_ai.get("role")) == "goalkeeper":
			continue
		var offset := p.global_position - my_pos
		offset.y = 0.0
		var dist := offset.length()
		if dist < 4.0 or dist > PASS_MAX_DIST:
			continue
		var forward := offset.normalized().dot(to_goal)
		if forward < 0.25:
			continue
		var run_target := _breaking_run_target(p)
		var lane_score := _passing_lane_score(run_target)
		var space_score := _space_score(run_target)
		var score := forward * 1.2 + lane_score * 1.5 + space_score * 1.1 - dist * 0.025
		if score > best_score:
			best_score = score
			best = p
	return best if best_score > 1.45 else null

func _breaking_run_target(runner: CharacterBody3D) -> Vector3:
	var to_goal := _goal_pos - runner.global_position
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.01:
		to_goal = _goal_pos - player.global_position
		to_goal.y = 0.0
	to_goal = to_goal.normalized() if to_goal.length_squared() > 0.01 else Vector3(0.0, 0.0, signf(_goal_pos.z))
	var side := 1.0 if runner.global_position.x >= player.global_position.x else -1.0
	var lateral := Vector3(-to_goal.z, 0.0, to_goal.x) * side
	var target := runner.global_position + to_goal * 5.5 + lateral * 1.5
	target.y = 0.11
	return PitchConstants.clamp_player(target)

func _passing_lane_score(target: Vector3) -> float:
	var from := player.global_position
	var lane := target - from
	lane.y = 0.0
	var dist := lane.length()
	if dist < 0.1:
		return 0.0
	var dir := lane / dist
	var score := 1.0
	for body_obj in get_tree().get_nodes_in_group("players"):
		var body := body_obj as Node3D
		if body == null or not is_instance_valid(body):
			continue
		if int(body.get("team_id")) == team_id:
			continue
		var rel := body.global_position - from
		rel.y = 0.0
		var along := clampf(rel.dot(dir), 0.0, dist)
		var closest := from + dir * along
		var d := body.global_position.distance_to(closest)
		if d < 1.4:
			score -= 0.45 * (1.0 - d / 1.4)
	return clampf(score, 0.0, 1.0)

func _space_score(target: Vector3) -> float:
	var nearest := 6.0
	for body_obj in get_tree().get_nodes_in_group("players"):
		var body := body_obj as Node3D
		if body == null or not is_instance_valid(body):
			continue
		if int(body.get("team_id")) == team_id:
			continue
		nearest = minf(nearest, body.global_position.distance_to(target))
	return clampf(nearest / 6.0, 0.0, 1.0)

## SHOOT_BALL — aim and fire with xG-scaled charge
func _attempt_shot() -> void:
	var kick_sys: Node = player.get_node_or_null("KickSystem")
	if kick_sys == null: return
	if not PossessionManager.has_ball(player): return

	var aim: Vector3 = (_goal_pos - player.global_position).normalized()
	var xg: float    = GameplayAI.get_xg(player.global_position, _goal_pos)
	var aim_spread: float = lerpf(0.18, 0.05, aggression)
	var aim_offset   := Vector3(randf_range(-aim_spread, aim_spread), 0.0, 0.0)
	aim = (aim + aim_offset).normalized()

	if showcase_mode and randf() < 0.20:
		var curl_side: float = signf(player.global_position.x) * -1.0
		kick_sys.curl_shot(aim, curl_side)
	elif xg > 0.25:
		var charge: float = clampf(0.6 + xg * 0.35, 0.55, 0.98)
		kick_sys.power_shot(aim, charge)
	else:
		var min_charge: float = lerpf(0.35, 0.50, aggression)
		var max_charge: float = lerpf(0.68, 0.82, aggression)
		kick_sys.power_shot(aim, randf_range(min_charge, max_charge))
	_did_action = true

## INTERCEPT_WAIT — hold position and time the intercept
func _wait_for_intercept(delta: float) -> void:
	_intercept_wait_timer += delta
	# Small lateral shuffle toward passing lane
	var lane_pos := _estimate_passing_lane()
	_seek(lane_pos, delta)
	if _intercept_wait_timer >= INTERCEPT_WAIT_TIME:
		state = AIState.INTERCEPT_PASS
		_intercept_wait_timer = 0.0

## INTERCEPT_PASS — burst toward ball flight path
func _intercept(delta: float) -> void:
	var intercept_pos := _anticipate_ball_pos()
	_seek(intercept_pos, delta)
	# Grab ball if we reach it
	var dist := player.global_position.distance_to(intercept_pos)
	if dist < PICKUP_DIST * 1.5:
		var drib := player.get_node_or_null("DribbleSystem")
		if drib and drib.has_method("try_pickup"):
			drib.try_pickup(_ball_pos())
			if PossessionManager.has_ball(player):
				MatchEventBus.pass_intercepted.emit(
					player.get_instance_id(), -1
				)
				state = AIState.DRIBBLE_WITH_BALL

## MANMARK_OPPONENT — tight man-marking with zonal positioning
func _manmark(delta: float) -> void:
	var mark_pos := _mark_position_zonal()
	_seek(mark_pos, delta)
	# Try tackle if in range
	var tackle_range: float = lerpf(TACKLE_DIST * 0.7, TACKLE_DIST * 1.2, aggression)
	if player.global_position.distance_to(_ball_pos()) < tackle_range:
		_try_tackle()

## HIGH_FIGHT_WAIT — position for aerial, hold, wait for ball to peak
func _wait_for_aerial() -> void:
	var ball_pos := _ball_pos()
	if ball_pos.y < AERIAL_ACTIVATE_HEIGHT:
		state = AIState.WAIT
		return
	# Hold position under ball's projected landing spot
	var land_xy := Vector3(ball_pos.x, 0.0, ball_pos.z)
	if player.global_position.distance_to(land_xy) > 1.5:
		state = AIState.HIGH_FIGHT_MOVE

## HIGH_FIGHT_MOVE — contest aerial ball with heading/clearance
func _contest_aerial(delta: float) -> void:
	var ball_pos := _ball_pos()
	if ball_pos.y < AERIAL_ACTIVATE_HEIGHT:
		# Ball dropped — return to normal defend
		state = AIState.MOVE_TO_BALL
		return
	# Move under ball
	var land_xy := Vector3(ball_pos.x, 0.0, ball_pos.z)
	_seek(land_xy, delta)
	# Attempt header/aerial contest when close enough
	if player.global_position.distance_to(land_xy) < AERIAL_CONTEST_RANGE * 0.6:
		var aerial_sys := player.get_node_or_null("AerialMechanics")
		if aerial_sys and aerial_sys.has_method("try_header"):
			var aim_dir := (_goal_pos - player.global_position).normalized()
			aerial_sys.try_header(aim_dir)
			MatchEventBus.aerial_contest_started.emit(
				player.get_instance_id(), -1
			)
			state = AIState.HIGH_FIGHT_WAIT

## GK_SAVE — goalkeeper positioning + dive toward ball trajectory
func _goalkeeper_save(delta: float) -> void:
	if player == null: return
	var ball_pos := _ball_pos()
	var ball_vel := Vector3.ZERO
	if ball != null and "velocity" in ball:
		ball_vel = ball.velocity as Vector3

	# Project ball to goal line
	var goal_line_z := _own_goal.z
	var time_to_line := 9999.0
	if absf(ball_vel.z) > 0.1:
		time_to_line = (goal_line_z - ball_pos.z) / ball_vel.z

	var target_x := ball_pos.x
	if time_to_line > 0.0 and time_to_line < 2.5:
		# Ball heading toward goal — predict landing x
		target_x = ball_pos.x + ball_vel.x * time_to_line * 0.85
		target_x = clampf(target_x, -PitchConstants.GOAL_HALF_WIDTH, PitchConstants.GOAL_HALF_WIDTH)

	# GK hugs goal line, offset slightly toward ball x
	var gk_z: float = _own_goal.z + sign(_goal_pos.z - _own_goal.z) * GK_POSITION_OFFSET
	var ideal_pos := Vector3(
		lerpf(player.global_position.x, target_x, 0.25),
		0.1,
		gk_z
	)

	# Soccer-course: dive when ball trajectory threatens the goal mouth
	var threatens_goal := time_to_line > 0.0 and time_to_line < 1.4 and absf(target_x) < PitchConstants.GOAL_HALF_WIDTH + 0.5
	var dist_to_ball := player.global_position.distance_to(ball_pos)
	if threatens_goal and dist_to_ball < GK_DIVE_RANGE and ball_vel.length() > 5.0:
		var aerial_sys := player.get_node_or_null("AerialMechanics")
		if aerial_sys and aerial_sys.has_method("try_gk_dive"):
			aerial_sys.try_gk_dive(Vector3(target_x, 0.0, _own_goal.z) - player.global_position)
			return
		# Fallback: sprint directly at ball
		_seek(ball_pos, delta)
	else:
		_seek(ideal_pos, delta)

## GK_DISTRIBUTE — goalkeeper pass/punt after claiming ball
func _goalkeeper_distribute() -> void:
	if not PossessionManager.has_ball(player): return
	var kick_sys := player.get_node_or_null("KickSystem")
	if kick_sys == null: return

	# Find the most forward free teammate
	var best_mate := _find_gk_outlet()
	if best_mate != null:
		var dir: Vector3 = (best_mate.global_position - player.global_position).normalized()
		if player.global_position.distance_to(best_mate.global_position) > 10.0:
			kick_sys.lob_pass(dir)
		else:
			kick_sys.ground_pass(dir, 0.75)
	else:
		# No outlet — punt long down the middle
		var punt_dir := (_goal_pos - player.global_position)
		punt_dir.y = 0.0
		kick_sys.lob_pass(punt_dir.normalized())
	_did_action = true
	state = AIState.GK_SAVE

## FORCE_OFFBALL_FAST — sprint to ideal support position
func _sprint_to_space(delta: float) -> void:
	var ideal := _intent_target if _use_intent_target else _support_position_spread_aware()
	_seek(ideal, delta)

## FORCE_OFFBALL_MANMARK — shadow a specific opponent
func _shadow_opponent(delta: float) -> void:
	var opp := _find_opponent_to_manmark()
	if opp == null:
		state = AIState.FORCE_OFFBALL_FAST
		return
	# Stay goal-side of opponent
	var goal_dir: Vector3 = (_own_goal - opp.global_position).normalized()
	var shadow_pos: Vector3 = opp.global_position + goal_dir * 1.0
	_seek(shadow_pos, delta)

## FORCE_OFFBALL_ACCELERATE — burst to distant ideal position
func _accelerate_to_space(delta: float) -> void:
	var ideal := _intent_target if _use_intent_target else _support_position_weighted()
	_seek(ideal, delta)
	# Transition to FAST once close enough
	if player.global_position.distance_to(ideal) < OFFBALL_ACCEL_DIST * 0.5:
		state = AIState.FORCE_OFFBALL_FAST

## SET_PIECE_TAKER — AI executes the set piece kick
func _set_piece_take() -> void:
	if _did_action: return
	var kick_sys := player.get_node_or_null("KickSystem")
	if kick_sys == null or not PossessionManager.has_ball(player): return
	var aim := (_goal_pos - player.global_position).normalized()
	# Lofted cross/corner, grounded free-kick
	if player.global_position.distance_to(_goal_pos) > 12.0:
		kick_sys.lob_pass(aim)
	else:
		kick_sys.power_shot(aim, 0.85)
	_did_action = true
	_set_piece_assigned = false
	state = AIState.WAIT

## SET_PIECE_RUNNER — position for incoming set piece delivery
func _set_piece_run(delta: float) -> void:
	# Run to the near post / penalty spot area
	var run_target := Vector3(
		randf_range(-1.5, 1.5),
		0.1,
		_goal_pos.z + sign(_own_goal.z - _goal_pos.z) * randf_range(0.5, 2.5)
	)
	_seek(run_target, delta)

# ─────────────────────────────────────────────────────────────
#  SPRINT / MOVEMENT HELPERS
# ─────────────────────────────────────────────────────────────

func _update_ai_sprint(dist_to_ball: float) -> void:
	if player == null or not player.has_method("set_sprinting"):
		return
	var has_ball := PossessionManager.has_ball(player)
	var should_sprint := false
	if has_ball:
		var to_goal := (_goal_pos - player.global_position).length()
		should_sprint = false
		match state:
			AIState.PASS_BALL, AIState.SHOOT_BALL, AIState.CHIP_SHOT, AIState.CLEAR_BALL:
				should_sprint = false
			AIState.DRIBBLE_WITH_BALL:
				should_sprint = to_goal > 9.0 and player.stamina > 0.35
			_:
				should_sprint = to_goal > 6.0 and player.stamina > 0.3
	else:
		match state:
			AIState.FORCE_OFFBALL_ACCELERATE:
				should_sprint = player.stamina > 0.20
			AIState.INTERCEPT_PASS, AIState.HIGH_FIGHT_MOVE:
				should_sprint = player.stamina > 0.15
			_:
				var sprint_threshold := lerpf(SPRINT_DIST * 1.4, SPRINT_DIST * 0.7, aggression)
				should_sprint = dist_to_ball > sprint_threshold and player.stamina > 0.25
	player.set_sprinting(should_sprint)

func _role_delay_mult() -> float:
	var m := 0.70 if showcase_mode else 1.0
	match role:
		"striker":    return 0.75 * m
		"defender":   return 1.10 * m
		"goalkeeper": return 0.90 * m
		_:            return 1.00 * m

func _role_mult_float() -> float:
	match role:
		"striker":  return 1.25
		"defender": return 0.85
		_:          return 1.00

func _skill_chance() -> float:
	match role:
		"striker":    return 0.20
		"midfielder": return 0.13
		_:            return 0.06

# ─────────────────────────────────────────────────────────────
#  SENSING / EVALUATION HELPERS
# ─────────────────────────────────────────────────────────────

func _can_intercept() -> bool:
	if ball == null: return false
	if "velocity" not in ball: return false
	var bvel := ball.velocity as Vector3
	if bvel.length() < 3.0: return false   # Ball barely moving
	var bpos := _ball_pos()
	# Estimate where ball will be in 0.5s
	var future := bpos + bvel * 0.5
	future.y = 0.0
	var dist := player.global_position.distance_to(future)
	return dist < INTERCEPT_RANGE

func _estimate_passing_lane() -> Vector3:
	if ball == null: return player.global_position
	var bpos := _ball_pos()
	var bvel := Vector3.ZERO
	if "velocity" in ball:
		bvel = ball.velocity as Vector3
	var future := bpos + bvel * 0.3
	future.y = 0.0
	return future

func _is_near_ball(radius: float) -> bool:
	return player.global_position.distance_to(_ball_pos()) < radius

func _team_has_possession() -> bool:
	for mate in _teammates:
		if mate != player and is_instance_valid(mate) and PossessionManager.has_ball(mate):
			return true
	return false

func _count_team_chasers() -> int:
	var count := 0
	for mate in _teammates:
		if not is_instance_valid(mate) or mate == player:
			continue
		var ai: Node = mate.get_node_or_null("AIController")
		if ai == null:
			continue
		var s: int = ai.state
		if s == AIState.MOVE_TO_BALL or s == AIState.TAKE_BALL:
			count += 1
	return count

## Soccer-course: repel extras when multiple teammates crowd the ball.
func _ball_density_repulsion() -> Vector3:
	if is_chaser and (state == AIState.MOVE_TO_BALL or state == AIState.TAKE_BALL):
		return Vector3.ZERO
	var ball_pos := _ball_pos()
	var nearby := 0
	for mate in _teammates:
		if mate == player or not is_instance_valid(mate):
			continue
		if mate.get("team_id") != team_id:
			continue
		if mate.global_position.distance_to(ball_pos) < 5.0:
			nearby += 1
	if nearby == 0:
		return Vector3.ZERO
	var weight := 1.0 - 1.0 / float(nearby + 1)
	var away := player.global_position - ball_pos
	away.y = 0.0
	if away.length_squared() < 0.01:
		return Vector3.ZERO
	return away.normalized() * weight * 2.8

func _is_closest_teammate_to_ball() -> bool:
	var ball_pos := _ball_pos()
	var my_dist := player.global_position.distance_to(ball_pos)
	for mate in _teammates:
		if mate == player or not is_instance_valid(mate):
			continue
		if mate.get("team_id") != team_id:
			continue
		if PossessionManager.has_ball(mate):
			continue
		if mate.global_position.distance_to(ball_pos) < my_dist - 0.45:
			return false
	return true

func _should_chase_ball(ball_pos: Vector3) -> bool:
	if not is_chaser:
		return false
	if _count_team_chasers() > 0 and not _is_closest_teammate_to_ball():
		return false
	return player.global_position.distance_to(ball_pos) < 22.0

func _should_striker_press(ball_pos: Vector3) -> bool:
	if player.global_position.distance_to(ball_pos) > 13.0:
		return false
	if not _is_closest_teammate_to_ball():
		return false
	var mid_z := (PitchConstants.GOAL_Z_TEAM0_DEFENDS + PitchConstants.GOAL_Z_TEAM1_DEFENDS) * 0.5
	var in_attacking_half := signf(ball_pos.z - mid_z) == signf(_goal_pos.z - mid_z)
	return in_attacking_half or player.global_position.distance_to(ball_pos) < 7.0

func _find_opponent_to_manmark() -> Node:
	var ball_pos := _ball_pos()
	var best: Node = null
	var best_score := -1.0
	for body in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(body): continue
		if body.get("team_id") == team_id: continue
		# Score = threat level: proximity to our goal + proximity to ball
		var dist_own_goal: float = body.global_position.distance_to(_own_goal)
		var dist_ball: float     = body.global_position.distance_to(ball_pos)
		var score: float = 1.0 / (dist_own_goal * 0.6 + dist_ball * 0.4 + 0.1)
		if score > best_score:
			best_score = score
			best = body
	return best

func _find_gk_outlet() -> Node:
	var best: Node = null
	var best_score := -1.0
	for mate in _teammates:
		if not is_instance_valid(mate) or mate == player: continue
		if mate.get("team_id") != team_id: continue
		# Choose the most forward teammate not under heavy pressure
		var dist_to_goal: float = mate.global_position.distance_to(_goal_pos)
		var pressure := 0.0
		for body in get_tree().get_nodes_in_group("players"):
			if body.get("team_id") == team_id or not is_instance_valid(body): continue
			if body.global_position.distance_to(mate.global_position) < 3.0:
				pressure += 1.0
		var score: float = 1.0 / (dist_to_goal * 0.1 + pressure * 5.0 + 1.0)
		if score > best_score:
			best_score = score
			best = mate
	return best

# ─────────────────────────────────────────────────────────────
#  MOVEMENT PRIMITIVES (unchanged from Phase 3/4)
# ─────────────────────────────────────────────────────────────

func _anticipate_ball_pos() -> Vector3:
	if ball and ball.has_method("get") and "velocity" in ball:
		var anticipated := _ball_pos() + (ball.velocity as Vector3) * ANTICIPATE_TIME
		anticipated.y = 0.0
		return anticipated
	return _ball_pos()

func _support_position_spread_aware() -> Vector3:
	var ideal := _support_position_weighted()
	for mate in _teammates:
		if mate == player or not is_instance_valid(mate): continue
		if mate.get("team_id") != team_id: continue
		var to_self: Vector3 = player.global_position - mate.global_position
		to_self.y = 0.0
		var dist: float = to_self.length()
		if dist < SPREAD_RADIUS and dist > 0.1:
			ideal += to_self.normalized() * (SPREAD_RADIUS - dist) * SPREAD_FORCE * 0.1
	return ideal

func _mark_position_zonal() -> Vector3:
	var assigned := AIBlackboard.get_mark_target(player)
	if assigned != null and is_instance_valid(assigned):
		var opp: Node3D = assigned as Node3D
		if opp != null:
			var ball_pos := _ball_pos()
			var goal_dir: Vector3 = (_own_goal - opp.global_position).normalized()
			var ball_side := signf((ball_pos - opp.global_position).cross(goal_dir).y)
			var lateral_offset := Vector3(ball_side * 1.1, 0.0, 0.0)
			return opp.global_position.lerp(_own_goal, 0.28) + lateral_offset

	var ball_pos := _ball_pos()
	for body in get_tree().get_nodes_in_group("players"):
		if body.get("team_id") == team_id: continue
		if not is_instance_valid(body): continue
		var goal_dir: Vector3 = (_own_goal - body.global_position).normalized()
		var ball_side := signf((ball_pos - body.global_position).cross(goal_dir).y)
		var lateral_offset := Vector3(ball_side * 1.2, 0.0, 0.0)
		return body.global_position.lerp(_own_goal, 0.3) + lateral_offset
	return _own_goal

func _try_pass_run(delta: float) -> bool:
	if player == null or not player.has_meta("pass_run_target"):
		return false
	var mode: String = str(player.get_meta("pass_run_mode", ""))
	if mode == "feet" or mode == "receive":
		return false
	if Time.get_ticks_msec() * 0.001 > float(player.get_meta("pass_run_expires", 0.0)):
		PassPlayCoordinator.clear_pass_run(player)
		return false
	if PossessionManager.has_ball(player):
		PassPlayCoordinator.clear_pass_run(player)
		if mode == "through" and not _did_action:
			_attempt_one_touch()
		return false

	var target: Vector3 = player.get_meta("pass_run_target") as Vector3
	if player.has_method("set_sprinting"):
		player.set_sprinting(true)
	_seek(target, delta)

	var ball_dist: float = player.global_position.distance_to(_ball_pos())
	if mode == "through" and ball_dist < 2.4:
		_try_pickup_ball(ball_dist)
		if PossessionManager.has_ball(player) and not _did_action:
			_attempt_one_touch()
	return true

func _attempt_one_touch() -> void:
	if not PossessionManager.has_ball(player):
		return
	var kick_sys: Node = player.get_node_or_null("KickSystem")
	if kick_sys == null:
		return
	var dist_goal: float = player.global_position.distance_to(_goal_pos)
	if dist_goal < 16.0 and GameplayAI.get_xg(player.global_position, _goal_pos) > 0.12:
		state = AIState.SHOOT_BALL
		_attempt_shot()
		_did_action = true
		PassPlayCoordinator.clear_pass_run(player)
		return
	var mate := _find_pass_target()
	if mate != null:
		var lead: Vector3 = mate.global_position
		if "velocity" in mate:
			lead += (mate.velocity as Vector3) * 0.18
		lead.y = player.global_position.y
		if kick_sys.has_method("ground_pass_to"):
			kick_sys.ground_pass_to(lead, 0.78, mate)
		else:
			var dir: Vector3 = lead - player.global_position
			dir.y = 0.0
			if dir.length_squared() > 0.01:
				kick_sys.ground_pass(dir.normalized(), 0.78)
		_did_action = true
		PassPlayCoordinator.clear_pass_run(player)

func _seek(target_pos: Vector3, delta: float) -> void:
	if player == null or not is_instance_valid(player): return
	var desired_dir := (target_pos - player.global_position)
	desired_dir.y = 0.0

	# Dynamic steering separation from nearby players to prevent crowding and body fighting
	var separation := Vector3.ZERO
	var neighbors := get_tree().get_nodes_in_group("players")
	for other_obj in neighbors:
		var other: Node3D = other_obj as Node3D
		if other == null or other == player or not is_instance_valid(other):
			continue
		var to_self: Vector3 = player.global_position - other.global_position
		to_self.y = 0.0
		var d: float = to_self.length()
		var min_sep := 1.4
		if d < min_sep and d > 0.01:
			var force: float = (min_sep - d) / min_sep
			var strength: float = 3.5
			if state == AIState.MOVE_TO_BALL or state == AIState.TAKE_BALL:
				strength = 1.8 # allow close contests for active ball chasers
			separation += to_self.normalized() * force * strength

	desired_dir += separation
	desired_dir += _ball_density_repulsion()

	var dist: float = desired_dir.length()
	if dist < 0.3:
		player._apply_movement(Vector3.ZERO, delta)
		return
	var mag := clampf(dist / ARRIVE_RADIUS, 0.0, 1.0)
	mag *= GameplayAI.bicircular_weight(
		player.global_position, target_pos, 1.2, 0.12, ARRIVE_RADIUS, 1.0
	)
	var dir := desired_dir.normalized() * mag
	player._apply_movement(dir, delta)
	player._update_facing(dir, delta)

func _face_toward(target_pos: Vector3, delta: float) -> void:
	if player == null: return
	var look_dir := (target_pos - player.global_position)
	look_dir.y = 0.0
	if player.has_method("_update_facing") and look_dir.length_squared() > 0.01:
		player._update_facing(look_dir.normalized(), delta)

func _ball_pos() -> Vector3:
	if ball == null: return Vector3.ZERO
	if "ball_position" in ball:
		return ball.ball_position
	return ball.global_position

func _support_position_weighted() -> Vector3:
	var ball_pos := _ball_pos()
	var possessor := PossessionManager.get_possessor()
	
	# Create intelligent support triangles relative to the active ball carrier
	if possessor != null and is_instance_valid(possessor) and possessor.team_id == team_id:
		var possessor_3d: Node3D = possessor as Node3D
		if possessor_3d == null:
			return ball_pos.lerp(_goal_pos, 0.5)
		var carrier_pos: Vector3 = possessor_3d.global_position
		var to_goal: Vector3 = (_goal_pos - carrier_pos).normalized()
		var lateral: Vector3 = Vector3(-to_goal.z, 0.0, to_goal.x) # Perpendicular vector
		
		var slot: int = int(player.get_meta("slot_index", 0)) if player else 0
		var side_sign: float = 1.0 if slot % 2 == 0 else -1.0

		# Soccer-course: maintain spawn-relative shape around ball carrier
		if player.has_meta("spawn_position") and possessor.has_meta("spawn_position"):
			var carrier_spawn: Vector3 = possessor.get_meta("spawn_position") as Vector3
			var my_spawn: Vector3 = player.get_meta("spawn_position") as Vector3
			var spawn_diff: Vector3 = carrier_spawn - my_spawn
			spawn_diff.y = 0.0
			var formation_spot: Vector3 = carrier_pos - spawn_diff * FORMATION_SPREAD
			var role_spot: Vector3 = carrier_pos
			match role:
				"striker":
					role_spot = carrier_pos + to_goal * 6.5 + lateral * (side_sign * 3.8)
				"midfielder":
					role_spot = carrier_pos + to_goal * 3.0 + lateral * (side_sign * 4.5)
				"goalkeeper":
					return _own_goal
			return formation_spot.lerp(role_spot, 0.45)
		
		match role:
			"striker":
				# Attacking run: ahead and wide (3v3 overload)
				return carrier_pos + to_goal * 6.5 + lateral * (side_sign * 3.8)
			"goalkeeper":
				return _own_goal
			"midfielder":
				# Triangle vertex: lateral + slightly ahead of carrier
				return carrier_pos + to_goal * 3.0 + lateral * (side_sign * 4.5)
			_:
				return carrier_pos + to_goal * 2.0 + lateral * (side_sign * 4.0)

	# Fallback if ball is loose: zone-anchoring spacing scaled to pitch
	var slot: int = int(player.get_meta("slot_index", 0)) if player else 0
	var side_sign := 1.0 if slot % 2 == 0 else -1.0
	var wide := Vector3(side_sign * 5.0, 0.0, 0.0)
	match role:
		"striker":
			return ball_pos.lerp(_goal_pos, 0.38) + wide * 0.75
		"midfielder":
			return (ball_pos + _goal_pos) * 0.5 + wide * 0.55
		"goalkeeper":
			return _own_goal
		_:
			return ball_pos.lerp(_own_goal, 0.42) + wide * 0.4

func _weighted_attack_target() -> Vector3:
	return player.global_position.move_toward(_goal_pos, 5.0)

# ─────────────────────────────────────────────────────────────
#  ACTION HELPERS (unchanged from Phase 3/4)
# ─────────────────────────────────────────────────────────────

func _try_pickup_ball(dist_to_ball: float) -> void:
	if dist_to_ball <= PICKUP_DIST and not PossessionManager.has_ball(player):
		var dribble_sys := player.get_node_or_null("DribbleSystem")
		if dribble_sys and dribble_sys.has_method("try_pickup"):
			var bpos: Vector3 = ball.ball_position if "ball_position" in ball else ball.global_position
			dribble_sys.try_pickup(bpos)

func _try_tackle() -> void:
	var tackle_sys := player.get_node_or_null("TackleSystem")
	if tackle_sys == null or not tackle_sys.has_method("try_standing_tackle"): return
	if "tackling_stat" in tackle_sys:
		tackle_sys.tackling_stat = tackling_stat
	for body in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(body): continue
		if body == player or body.get("team_id") == team_id: continue
		if player.global_position.distance_to(body.global_position) < TACKLE_DIST:
			tackle_sys.try_standing_tackle(body)
			break

func _do_chip() -> void:
	var kick_sys: Node = player.get_node_or_null("KickSystem")
	if kick_sys == null or not PossessionManager.has_ball(player): return
	var aim: Vector3 = (_goal_pos - player.global_position).normalized()
	kick_sys.chip_shot(aim)
	_did_action = true

func _execute_clear() -> void:
	var kick_sys := player.get_node_or_null("KickSystem")
	if kick_sys and PossessionManager.has_ball(player):
		var clear_dir := (_goal_pos - player.global_position).normalized()
		kick_sys.lob_pass(clear_dir)
		_did_action = true

func _do_aerial() -> void:
	var aerial_sys := player.get_node_or_null("AerialMechanics")
	if aerial_sys and aerial_sys.has_method("try_volley"):
		aerial_sys.try_volley((_goal_pos - player.global_position).normalized())
		_did_action = true

func _do_bicycle() -> void:
	var aerial_sys := player.get_node_or_null("AerialMechanics")
	if aerial_sys and aerial_sys.has_method("try_bicycle_kick"):
		aerial_sys.try_bicycle_kick((_goal_pos - player.global_position).normalized())
		_did_action = true

func _do_skill_move() -> void:
	var skill_sys := player.get_node_or_null("SkillMoves")
	if skill_sys == null: return
	if skill_sys.is_busy(): return

	var bd: BallerData = player.get("baller_data") as BallerData
	var equipped: Array[int] = bd.get_equipped_skills() if bd != null else []

	if equipped.size() > 0:
		var chosen: int = equipped[randi() % equipped.size()]
		if skill_sys.ai_execute(chosen):
			_did_action = true
			return

	match randi() % 4:
		0: skill_sys.ai_execute_flick_up(-player.transform.basis.z)
		1: skill_sys.ai_execute_heel_flick()
		2: skill_sys.ai_execute_roulette()
		3: skill_sys.ai_execute_stepover(1.0 if randf() > 0.5 else -1.0)
	_did_action = true

func _find_pass_target() -> CharacterBody3D:
	var best_mate: CharacterBody3D = null
	var best_score: float = -999.0
	if player == null: return null

	var to_goal: Vector3 = (_goal_pos - player.global_position).normalized()
	var my_pos: Vector3 = player.global_position
	
	# Detect if the ball carrier is under pressure from nearby defenders
	var under_pressure := false
	var neighbors := get_tree().get_nodes_in_group("players")
	for body_obj in neighbors:
		var body: Node3D = body_obj as Node3D
		if body == null or not is_instance_valid(body):
			continue
		if body.get("team_id") == team_id:
			continue
		if my_pos.distance_to(body.global_position) < 2.8:
			under_pressure = true
			break

	for mate in _teammates:
		var player_node := mate as CharacterBody3D
		if player_node == null or player_node == player: continue
		if player_node.get("team_id") != team_id: continue
		if not is_instance_valid(player_node): continue
		var mate_ai := player_node.get_node_or_null("AIController")
		if mate_ai and mate_ai.get("role") == "goalkeeper":
			continue

		var d: float = my_pos.distance_to(player_node.global_position)
		if d < PASS_MIN_DIST or d > PASS_MAX_DIST:
			continue

		var to_mate: Vector3 = (player_node.global_position - my_pos).normalized()
		
		# Base control-grid weight from GameplayAI
		var val: float = GameplayAI.action_weight(player_node.global_position, _goal_pos, team_id)
		
		# Scoring based on direction and tactical pressure
		var direction_score: float = to_mate.dot(to_goal)
		var pass_dir_weight: float = 0.6
		
		if under_pressure:
			# Prefer lateral/backward recycling passes when pressured
			if direction_score < 0.2:
				direction_score = 1.0 - absf(direction_score)
				pass_dir_weight = 1.2
			else:
				direction_score = -0.5 # Penalize forward forcing
				pass_dir_weight = 1.0

		# Assess pressure on the target teammate
		var mate_pressure: float = 0.0
		for body_obj2 in neighbors:
			var body2: Node3D = body_obj2 as Node3D
			if body2 == null or not is_instance_valid(body2):
				continue
			if body2.get("team_id") == team_id:
				continue
			var dist_opp: float = player_node.global_position.distance_to(body2.global_position)
			if dist_opp < 3.0:
				mate_pressure += 1.0 - (dist_opp / 3.0)
					
		# Check passing lane obstruction
		var lane_obstruction := 0.0
		for body_obj in neighbors:
			var body: Node3D = body_obj as Node3D
			if body == null or not is_instance_valid(body):
				continue
			if body.get("team_id") == team_id:
				continue
			var opp_pos: Vector3 = body.global_position
			var proj: Vector3 = my_pos + to_mate * clampf((opp_pos - my_pos).dot(to_mate), 0.0, d)
			var dist_to_line: float = (opp_pos - proj).length()
			if dist_to_line < 1.2:
				lane_obstruction += 1.0
					
		var open_bonus := 1.5 * (1.0 - clampf(mate_pressure, 0.0, 1.0))
		var lane_penalty := -1.8 * lane_obstruction
		
		# Distance weighting: prefer comfortable 5-15m support passes
		var dist_score := 1.0
		if d < 5.0:
			dist_score = 0.5 + 0.5 * (d / 5.0)
		elif d > 15.0:
			dist_score = 1.0 - 0.5 * ((d - 15.0) / 10.0)

		var total_score: float = val + direction_score * pass_dir_weight + open_bonus + lane_penalty + dist_score * 0.5

		if "velocity" in player_node:
			total_score += (player_node.velocity as Vector3).dot(to_goal) * 0.25

		if total_score > best_score:
			best_score = total_score
			best_mate  = player_node

	return best_mate

# ─────────────────────────────────────────────────────────────
#  PUBLIC API — called by MatchManager / SetPieces
# ─────────────────────────────────────────────────────────────

## Assign this AI as the set piece taker.
func assign_set_piece_taker() -> void:
	_set_piece_assigned = true
	state = AIState.SET_PIECE_TAKER
	_did_action = false

## Assign this AI as a set piece runner.
func assign_set_piece_runner() -> void:
	_set_piece_assigned = true
	state = AIState.SET_PIECE_RUNNER

## Called when set piece completes — return to normal decision-making.
func clear_set_piece_assignment() -> void:
	_set_piece_assigned = false
	state = AIState.WAIT
