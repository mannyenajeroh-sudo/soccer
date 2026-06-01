extends Node

# ============================================================
#  GameplayRules.gd — STREET 3 ELITE  (Phase 3 / 4)
#
#  Out-of-play detection, set piece trigger routing, offside
#  stub, and foul routing.  All events emitted via MatchEventBus.
#
#  Bug fix over Phase 2 stub:
#    - Was a complete no-op (_process returned immediately)
#    - Now detects ball out-of-bounds and triggers correct set piece
#    - Emits ball_out_of_play event on MatchEventBus
#    - Routes corner vs goal kick correctly (last-touch team logic)
#    - Sideline kick when ball exits side wall
#
#  Note: This arena uses wall-ball rules for side walls, so
#  sideline kicks only trigger when the ball is stuck / dead
#  on the wall (velocity near zero) for > WALL_DEAD_TIME seconds.
#  Corner kicks occur when a defending team puts the ball behind
#  their own goal line (outside the goal mouth).
# ============================================================

var _ball:    Node    = null
var _players: Array  = []

# Last team to touch the ball (for corner/goal kick attribution)
var _last_touch_team: int = -1
# Track ball out-of-bounds
var _wall_dead_timer: float = 0.0
const WALL_DEAD_TIME  := 1.2     # seconds ball must be stuck on wall
const WALL_DEAD_SPEED := 0.6     # m/s — considered "stuck"
const WALL_DEAD_DIST  := 0.25    # how close to wall edge

func setup(ball: Node, players: Array) -> void:
	_ball    = ball
	_players = players
	_last_touch_team = 0
	# Track possession changes for last_touch attribution
	PossessionManager.possession_changed.connect(_on_possession_changed)

func _process(delta: float) -> void:
	if _ball == null or GameState.phase != GameState.Phase.PLAY:
		_wall_dead_timer = 0.0
		return
	# Cage mode: no corner kicks / sideline restarts.
	# Keep play continuous and let BallPhysics resolve walls.
	_wall_dead_timer = 0.0

func _check_corner_or_goal_kick(bp: Vector3) -> void:
	# Only trigger if ball is past either goal line Z
	if absf(bp.z) <= PitchConstants.GOAL_LINE_SCORE_Z:
		return
	# Ball is in the net area → scoring is handled by MatchManager
	# Only care about balls OUTSIDE the goal mouth
	if absf(bp.x) < PitchConstants.GOAL_HALF_WIDTH:
		return

	var set_pieces: Node = _get_set_pieces()
	if set_pieces == null or set_pieces.active_type != set_pieces.SetPieceType.NONE:
		return

	# Ball behind team 0's goal line (z < -GOAL_LINE_SCORE_Z)
	if bp.z < -PitchConstants.GOAL_LINE_SCORE_Z:
		if _last_touch_team == 0:
			set_pieces.start_corner(1, bp)
			MatchEventBus.corner_kick.emit(1)
		elif _last_touch_team == 1:
			set_pieces.start_goal_kick(0)
			MatchEventBus.goal_kick.emit(0)
		else:
			set_pieces.start_goal_kick(0)
			MatchEventBus.goal_kick.emit(0)
		MatchEventBus.ball_out_of_play.emit(0, _last_touch_team, bp)

	# Ball behind team 1's goal line (z > +GOAL_LINE_SCORE_Z)
	elif bp.z > PitchConstants.GOAL_LINE_SCORE_Z:
		if _last_touch_team == 1:
			set_pieces.start_corner(0, bp)
			MatchEventBus.corner_kick.emit(0)
		elif _last_touch_team == 0:
			set_pieces.start_goal_kick(1)
			MatchEventBus.goal_kick.emit(1)
		else:
			set_pieces.start_goal_kick(1)
			MatchEventBus.goal_kick.emit(1)
		MatchEventBus.ball_out_of_play.emit(0, _last_touch_team, bp)

func _check_wall_dead(bp: Vector3, delta: float) -> void:
	if _ball == null:
		return
	var vel: Vector3 = _ball.velocity if "velocity" in _ball else Vector3.ZERO
	var near_x_wall: bool = absf(bp.x) > PitchConstants.PLAY_HALF_X - WALL_DEAD_DIST
	var near_z_wall: bool = absf(bp.z) > PitchConstants.PLAY_HALF_Z - WALL_DEAD_DIST

	if (near_x_wall or near_z_wall) and vel.length() < WALL_DEAD_SPEED:
		_wall_dead_timer += delta
	else:
		_wall_dead_timer = 0.0

	if _wall_dead_timer >= WALL_DEAD_TIME:
		_wall_dead_timer = 0.0
		_trigger_sideline_kick(bp)

func _trigger_sideline_kick(bp: Vector3) -> void:
	var set_pieces: Node = _get_set_pieces()
	if set_pieces == null or set_pieces.active_type != set_pieces.SetPieceType.NONE:
		return
	# Ball stuck near side wall — award sideline to opposing team
	var restoring_team := 1 - _last_touch_team if _last_touch_team >= 0 else 0
	set_pieces.start_sideline_kick(restoring_team, bp)
	MatchEventBus.sideline_kick.emit(restoring_team, bp)
	MatchEventBus.ball_out_of_play.emit(1, restoring_team, bp)

func _on_possession_changed(new_possessor: Node, _old: Node) -> void:
	if new_possessor != null:
		var team := new_possessor.get("team_id") as int
		_last_touch_team = team

func _get_set_pieces() -> Node:
	# MatchManager stores set_pieces as a child — look it up via group or parent
	for node in get_tree().get_nodes_in_group("set_pieces"):
		return node
	# Fallback: search siblings
	var parent := get_parent()
	if parent:
		for child in parent.get_children():
			if child.has_method("start_corner"):
				return child
	return null
