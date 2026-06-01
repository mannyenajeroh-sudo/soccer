class_name AIDecisionTrees
extends RefCounted

# ============================================================
#  Chess-Zone decision trees — read AIBlackboard, return intents
# ============================================================

const Arc := AIBlackboard.Arc

static func decide_ball_carrier(ai: Node) -> Dictionary:
	var player: CharacterBody3D = ai.player
	var goal: Vector3 = ai._goal_pos
	var team_id: int = ai.team_id
	var bb := AIBlackboard

	var arc: int = bb.get_arc_zone(player.global_position, goal)
	var to_goal: Vector3 = goal - player.global_position
	to_goal.y = 0.0
	var angle_deg: float = 90.0
	if to_goal.length_squared() > 0.01:
		var fwd := -player.transform.basis.z
		fwd.y = 0.0
		angle_deg = rad_to_deg(fwd.angle_to(to_goal.normalized()))

	var kick: Node = player.get_node_or_null("KickSystem")
	var quality: float = 0.7
	if kick and kick.has_method("contact_quality"):
		quality = kick.contact_quality(to_goal.normalized() if to_goal.length_squared() > 0.01 else Vector3.FORWARD)

	if bb.get_arc_zone(player.global_position, ai._own_goal) <= Arc.DANGER and GameplayAI.is_defensive_third(player.global_position, ai._own_goal):
		return {"state": ai.AIState.CLEAR_BALL, "decision": "clear"}

	match arc:
		Arc.LETHAL:
			if angle_deg < 45.0 and quality >= bb.shot_quality_floor:
				return {"state": ai.AIState.SHOOT_BALL, "decision": "shoot"}
			var tm := bb.best_open_teammate(team_id, player, goal)
			if tm:
				return {"state": ai.AIState.PASS_BALL, "decision": "pass", "target": tm}
		Arc.DANGER:
			if bb.teammate_in_arc(team_id, Arc.LETHAL, goal, player):
				var lethal_mate := bb.best_open_teammate(team_id, player, goal)
				if lethal_mate:
					return {"state": ai.AIState.PASS_BALL, "decision": "through_pass", "target": lethal_mate}
			if angle_deg < 60.0 and quality >= bb.shot_quality_floor * 0.9:
				return {"state": ai.AIState.SHOOT_BALL, "decision": "shoot"}
		Arc.CONTEST:
			var open := bb.best_open_teammate(team_id, player, goal)
			if open:
				return {"state": ai.AIState.PASS_BALL, "decision": "pass", "target": open}
			var side: float = signf(player.global_position.x) if absf(player.global_position.x) > 0.3 else 1.0
			if bb.flank_open(team_id, player.global_position, goal):
				return {"state": ai.AIState.DRIBBLE_WITH_BALL, "decision": "carry_wide"}
			if bb.defenders_near(player.global_position, team_id, 2.0) > 0:
				var layoff := bb.best_open_teammate(team_id, player, goal)
				if layoff:
					return {"state": ai.AIState.PASS_BALL, "decision": "layoff", "target": layoff}
				return {"state": ai.AIState.PASS_BALL, "decision": "layoff"}
		Arc.SAFE:
			var safe_mate := bb.best_open_teammate(team_id, player, goal)
			if safe_mate:
				return {"state": ai.AIState.PASS_BALL, "decision": "recycle", "target": safe_mate}
			if bb.forward_lane_clear(player, goal):
				return {"state": ai.AIState.DRIBBLE_WITH_BALL, "decision": "advance"}
			return {"state": ai.AIState.PASS_BALL, "decision": "recycle"}

	if ai._ball_hold_timer >= ai.FORCE_PASS_HOLD:
		return {"state": ai.AIState.PASS_BALL, "decision": "pass"}

	return {"state": ai.AIState.DRIBBLE_WITH_BALL, "decision": "dribble"}

static func decide_support(ai: Node) -> Dictionary:
	var player: CharacterBody3D = ai.player
	var bb := AIBlackboard
	var carrier := PossessionManager.get_possessor()
	if carrier == null:
		return {"state": ai.AIState.FORCE_OFFBALL_FAST, "decision": "support"}

	var goal: Vector3 = ai._goal_pos
	var carrier_arc: int = bb.get_arc_zone(carrier.global_position, goal)
	var side: float = -1.0 if player.global_position.x < 0.0 else 1.0
	var target: Vector3 = ai._support_position_weighted()

	match carrier_arc:
		Arc.SAFE:
			if AIBlackboard.opening_mark_active and ai.role != "goalkeeper":
				var open_side: float = -1.0 if player.global_position.x < carrier.global_position.x else 1.0
				target = carrier.global_position + Vector3(open_side * 5.5, 0.0, signf(goal.z - carrier.global_position.z) * 4.5)
			else:
				target = carrier.global_position + Vector3(side * 4.0, 0.0, signf(goal.z - carrier.global_position.z) * -3.0)
		Arc.CONTEST:
			if AIBlackboard.opening_mark_active and ai.role != "goalkeeper":
				var wide_side: float = -1.0 if player.global_position.x < carrier.global_position.x else 1.0
				target = carrier.global_position + Vector3(wide_side * 6.0, 0.0, signf(goal.z - carrier.global_position.z) * 3.5)
			elif not bb.teammate_in_arc(ai.team_id, Arc.DANGER, goal, player):
				target = goal + Vector3(side * 3.5, 0.0, signf(ai._own_goal.z - goal.z) * 2.0)
			else:
				target = Vector3(side * 9.0, 0.1, carrier.global_position.z - 2.0)
		Arc.DANGER:
			if not bb.has_marker(player):
				bb.set_flag(player, "calling_for_pass")
				target = player.global_position
			else:
				target = player.global_position + Vector3(side * 5.0, 0.0, 0.0)

	if ai.role == "striker":
		return {"state": ai.AIState.FORCE_OFFBALL_ACCELERATE, "decision": "support", "target": target}
	return {"state": ai.AIState.FORCE_OFFBALL_FAST, "decision": "support", "target": target}

static func decide_defend(ai: Node, ball_pos: Vector3) -> Dictionary:
	var bb := AIBlackboard
	var player: CharacterBody3D = ai.player

	if ai._can_intercept():
		if ai.state != ai.AIState.INTERCEPT_PASS:
			return {"state": ai.AIState.INTERCEPT_WAIT, "decision": "intercept_wait"}
		return {"state": ai.state, "decision": "intercept"}

	if ball_pos.y > ai.AERIAL_ACTIVATE_HEIGHT and ai._is_near_ball(ai.AERIAL_CONTEST_RANGE):
		return {"state": ai.AIState.HIGH_FIGHT_MOVE, "decision": "aerial"}

	match ai.role:
		"striker":
			if ai._should_striker_press(ball_pos):
				return {"state": ai.AIState.MOVE_TO_BALL, "decision": "press"}
			return {"state": ai.AIState.FORCE_OFFBALL_FAST, "decision": "support"}
		"midfielder":
			if ai.is_chaser and ai._should_chase_ball(ball_pos):
				return {"state": ai.AIState.MOVE_TO_BALL, "decision": "seek_ball"}
			if ai._is_closest_teammate_to_ball() and player.global_position.distance_to(ball_pos) < 10.0:
				return {"state": ai.AIState.TAKE_BALL, "decision": "close_down"}
			return {"state": ai.AIState.FORCE_OFFBALL_FAST, "decision": "support"}
		"goalkeeper":
			return {"state": ai.AIState.GK_SAVE, "decision": "gk"}
		_:
			if AIBlackboard.opening_mark_active:
				return {"state": ai.AIState.MANMARK_OPPONENT, "decision": "opening_mark"}
			if bb.press_trigger_high and ball_pos.distance_to(ai._own_goal) > 12.0:
				return {"state": ai.AIState.MOVE_TO_BALL, "decision": "high_press"}
			return {"state": ai.AIState.MANMARK_OPPONENT, "decision": "mark"}

static func decide_gk(ai: Node, has_ball: bool, ball_pos: Vector3) -> Dictionary:
	if has_ball:
		if ai._gk_distribute_timer < ai.GK_DISTRIBUTE_WAIT:
			return {"state": ai.AIState.WAIT, "decision": "gk_hold"}
		return {"state": ai.AIState.GK_DISTRIBUTE, "decision": "distribute"}
	var own_goal: Vector3 = ai._own_goal
	var arc: int = AIBlackboard.get_arc_zone(ball_pos, own_goal)
	if arc <= Arc.LETHAL:
		return {"state": ai.AIState.GK_SAVE, "decision": "gk_dive_ready"}
	return {"state": ai.AIState.GK_SAVE, "decision": "gk_line"}

static func apply_fidelity(intent: Dictionary, fidelity: float, ai: Node) -> Dictionary:
	if fidelity >= 0.98:
		return intent
	if randf() > fidelity and intent.get("decision", "") == "shoot":
		return {"state": ai.AIState.PASS_BALL, "decision": "pass", "target": intent.get("target")}
	return intent
