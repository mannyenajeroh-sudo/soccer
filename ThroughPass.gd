extends Node

# ============================================================
#  ThroughPass.gd — STREET 3 ELITE
#  Finds best through-ball target and executes via KickSystem.
# ============================================================

@export var ball_physics: Node
@export var kicker: CharacterBody3D
@export var team_id: int = 0

const MIN_FORWARD_COMPONENT := 0.12  # 3v3: allow diagonal runs into space
const MAX_DISTANCE          := 17.0
const MIN_DISTANCE          := 3.2

func find_and_execute(all_players: Array) -> bool:
	if kicker == null or ball_physics == null:
		return false
	var kick_sys := kicker.get_node_or_null("KickSystem")
	if kick_sys == null:
		return false

	var goal_pos := PitchConstants.attack_goal_vec(team_id)
	var best_target: CharacterBody3D = null
	var best_score  := -1.0

	for p in all_players:
		var player_node := p as CharacterBody3D
		if player_node == null or player_node == kicker: continue
		if player_node.get("team_id") != team_id: continue
		if not is_instance_valid(player_node): continue

		var dist: float = kicker.global_position.distance_to(player_node.global_position)
		if dist < MIN_DISTANCE or dist > MAX_DISTANCE: continue

		# Must be ahead of kicker (toward their goal)
		var to_mate: Vector3 = player_node.global_position - kicker.global_position
		to_mate.y = 0.0
		var to_goal: Vector3 = (goal_pos - kicker.global_position)
		to_goal.y = 0.0
		if to_goal.length_squared() < 0.01: continue
		var fwd_comp := to_mate.normalized().dot(to_goal.normalized())
		var run_bonus := 0.0
		if "velocity" in player_node:
			var mv := player_node.velocity as Vector3
			mv.y = 0.0
			if mv.length() > 1.2:
				run_bonus = mv.normalized().dot(to_goal.normalized()) * 0.35
		if fwd_comp < MIN_FORWARD_COMPONENT and run_bonus < 0.15:
			continue

		var xg := GameplayAI.get_xg(player_node.global_position, goal_pos)
		var score := xg + fwd_comp * 0.35 + run_bonus

		# Check no defender blocking the lane
		if _lane_blocked(kicker.global_position, player_node.global_position, all_players):
			score *= 0.5

		if score > best_score:
			best_score  = score
			best_target = player_node

	if best_target == null:
		return false

	var pass_dir: Vector3 = best_target.global_position - kicker.global_position
	pass_dir.y = 0.0
	var lead_pos: Vector3 = best_target.global_position
	if "velocity" in best_target:
		var lead_time := pass_dir.length() / 14.0
		lead_pos = best_target.global_position + (best_target.velocity as Vector3) * lead_time * 0.75
	lead_pos.y = 0.11
	if pass_dir.length_squared() < 0.01:
		return false
	kick_sys.ground_pass_to(lead_pos, 0.86, best_target, false, true)
	_notify_squad_switch(best_target)
	var mm := _find_match_manager()
	if mm and mm.has_method("assign_pass_play"):
		mm.assign_pass_play(kicker, best_target, lead_pos, true)
	return true

func _notify_squad_switch(target: Node) -> void:
	var mm := _find_match_manager()
	if mm and mm.has_method("schedule_pass_switch"):
		mm.schedule_pass_switch(target)

func _find_match_manager() -> Node:
	if kicker == null:
		return null
	var nodes := kicker.get_tree().get_nodes_in_group("match_manager")
	if nodes.size() > 0:
		return nodes[0]
	return null

func _lane_blocked(from: Vector3, to: Vector3, all_players: Array) -> bool:
	var dir  := (to - from)
	dir.y = 0.0
	var dist := dir.length()
	if dist < 0.1: return false
	dir = dir.normalized()
	for p in all_players:
		if p.get("team_id") == team_id: continue
		if not is_instance_valid(p): continue
		var to_p: Vector3 = p.global_position - from
		to_p.y = 0.0
		var proj: float = to_p.dot(dir)
		if proj < 0.5 or proj > dist: continue
		var perp: float = (to_p - dir * proj).length()
		if perp < 1.2:
			return true
	return false
