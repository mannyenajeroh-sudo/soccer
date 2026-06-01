extends Node

# ============================================================
#  GoalDetector.gd - reliable goal-line crossing detection.
# ============================================================

var ball_physics: BallPhysics = null
var match_manager: Node = null

var _prev_pos := Vector3.ZERO
var _enabled := true

const MIN_GOAL_SPEED := 1.8

func setup(ball: BallPhysics, manager: Node) -> void:
	ball_physics = ball
	match_manager = manager
	if ball_physics:
		_prev_pos = ball_physics.ball_position

func set_enabled(on: bool) -> void:
	_enabled = on
	if ball_physics:
		_prev_pos = ball_physics.ball_position

func _physics_process(_delta: float) -> void:
	if not _enabled or ball_physics == null or match_manager == null:
		return
	if GameState.phase != GameState.Phase.PLAY:
		_prev_pos = ball_physics.ball_position
		return

	var pos := ball_physics.ball_position
	var team := PitchConstants.detect_goal_crossing(_prev_pos, pos)
	if team >= 0:
		var spd := ball_physics.velocity.length()
		if spd >= MIN_GOAL_SPEED or PitchConstants.is_fully_in_net(pos, team):
			if match_manager.has_method("register_goal"):
				match_manager.register_goal(team, pos, spd)
	_prev_pos = pos

func resolve_last_touch_team() -> int:
	var touch_team := PossessionManager.get_last_touch_team()
	if touch_team >= 0:
		return touch_team
	var pending: Dictionary = GameState.get_meta("pending_shot", {})
	var pid: int = int(pending.get("player_id", -1))
	if pid >= 0:
		for p in get_tree().get_nodes_in_group("players"):
			if is_instance_valid(p) and p.get_instance_id() == pid:
				return int(p.get("team_id"))
	var possessor := PossessionManager.get_possessor()
	if possessor != null and is_instance_valid(possessor):
		return int(possessor.get("team_id"))
	return -1
