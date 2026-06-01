extends Node

# Street arena: continuous walls, recessed goals with back-wall bounce. No out-of-bounds.
# Pitch width reduced from 31.5m to 24m for tighter 3v3 street feel.

const PLAY_HALF_X := 12.0    # was 15.75 — total 24m wide, cage-match intensity
const PLAY_HALF_Z := 9.75
const PLAYER_HALF_X := 11.6  # was 15.35
const PLAYER_HALF_Z := 9.35
const BALL_RADIUS := 0.11

const GOAL_HALF_WIDTH := 2.9             # 3v3 size (was 3.66 — full 11-a-side)
const GOAL_HEIGHT     := 2.0             # Crossbar height for 3v3 (was 2.44)
const GOAL_Z_TEAM0_DEFENDS := -10.0
const GOAL_Z_TEAM1_DEFENDS := 10.0
const GOAL_LINE_SCORE_Z := 9.75          # Goal line aligned with pitch boundary PLAY_HALF_Z
const GOAL_MAX_HEIGHT := 2.05            # Must match GOAL_HEIGHT + tolerance
const GOAL_NET_BACK_OFFSET := 1.25       # Deeper net pocket — ball settles inside net
const GOAL_MOUTH_MARGIN_X := 0.35        # Extra width for posts / detection

static func clamp_ball(pos: Vector3) -> Vector3:
	return Vector3(
		clampf(pos.x, -PLAY_HALF_X, PLAY_HALF_X),
		pos.y,
		clampf(pos.z, -PLAY_HALF_Z - GOAL_NET_BACK_OFFSET, PLAY_HALF_Z + GOAL_NET_BACK_OFFSET)
	)

static func is_in_goal_mouth_xz(pos: Vector3) -> bool:
	if absf(pos.x) >= GOAL_HALF_WIDTH + 0.12:
		return false
	return absf(pos.z) >= GOAL_LINE_SCORE_Z - 0.85

## Keep outfield players out of the goal mouth — prevents net glitches / lost control.
static func push_player_from_goal_mouth(pos: Vector3) -> Vector3:
	if not is_in_goal_mouth_xz(pos):
		return pos
	var out := pos
	var safe_z: float = GOAL_LINE_SCORE_Z - 1.15
	if pos.z >= 0.0:
		out.z = minf(pos.z, safe_z)
	else:
		out.z = maxf(pos.z, -safe_z)
	return out

static func clamp_player(pos: Vector3) -> Vector3:
	var out := Vector3(
		clampf(pos.x, -PLAYER_HALF_X, PLAYER_HALF_X),
		pos.y,
		clampf(pos.z, -PLAYER_HALF_Z, PLAYER_HALF_Z)
	)
	return push_player_from_goal_mouth(out)

static func is_in_goal_mouth(pos: Vector3) -> bool:
	return absf(pos.x) < GOAL_HALF_WIDTH + GOAL_MOUTH_MARGIN_X

## Ball has fully crossed the goal line (inside the mouth).
static func is_past_goal_line(pos: Vector3, defending_team: int) -> bool:
	if not is_in_goal_mouth(pos):
		return false
	if pos.y > GOAL_MAX_HEIGHT + 0.35:
		return false
	if defending_team == 0:
		return pos.z < -GOAL_LINE_SCORE_Z - BALL_RADIUS
	return pos.z > GOAL_LINE_SCORE_Z + BALL_RADIUS

## Volume from goal line through the net — no end-wall bounce here.
static func is_in_scoring_zone(pos: Vector3) -> bool:
	if not is_in_goal_mouth(pos):
		return false
	if pos.y > GOAL_MAX_HEIGHT + 0.4:
		return false
	if pos.z > GOAL_LINE_SCORE_Z:
		return true
	if pos.z < -GOAL_LINE_SCORE_Z:
		return true
	return false

static func is_fully_in_net(pos: Vector3, scoring_team: int) -> bool:
	var def_team := 1 - scoring_team
	var back_z := goal_back_wall_z(def_team)
	if not is_in_goal_mouth(pos):
		return false
	if scoring_team == 0:
		return pos.z > GOAL_LINE_SCORE_Z + 0.15 and pos.z < back_z + 0.2
	return pos.z < -GOAL_LINE_SCORE_Z - 0.15 and pos.z > back_z - 0.2

## Line-crossing detection (prev → curr). Returns scoring team or -1.
static func detect_goal_crossing(prev: Vector3, curr: Vector3) -> int:
	# Team 0 scores in the +Z goal (team 1 defends)
	if _crossed_plane(prev.z, curr.z, GOAL_LINE_SCORE_Z + BALL_RADIUS):
		if _valid_goal_sample(curr, 0):
			return 0
	# Team 1 scores in the -Z goal
	if _crossed_plane(prev.z, curr.z, -GOAL_LINE_SCORE_Z - BALL_RADIUS):
		if _valid_goal_sample(curr, 1):
			return 1
	# Fallback: ball already deep in net (large physics step)
	var t0 := scoring_team_for_ball(curr)
	if t0 >= 0 and is_fully_in_net(curr, t0):
		return t0
	return -1

static func _crossed_plane(prev_z: float, curr_z: float, plane_z: float) -> bool:
	if plane_z > 0.0:
		return prev_z < plane_z and curr_z >= plane_z
	return prev_z > plane_z and curr_z <= plane_z

static func _valid_goal_sample(pos: Vector3, scoring_team: int) -> bool:
	if not is_in_goal_mouth(pos):
		return false
	if pos.y > GOAL_MAX_HEIGHT + 0.35:
		return false
	return is_past_goal_line(pos, 1 - scoring_team)

static func scoring_team_for_ball(pos: Vector3) -> int:
	if pos.y > GOAL_MAX_HEIGHT + 0.35:
		return -1
	if absf(pos.x) >= GOAL_HALF_WIDTH + GOAL_MOUTH_MARGIN_X:
		return -1
	if pos.z > GOAL_LINE_SCORE_Z + BALL_RADIUS:
		return 0
	if pos.z < -GOAL_LINE_SCORE_Z - BALL_RADIUS:
		return 1
	return -1

static func goal_back_wall_z(defending_team: int) -> float:
	if defending_team == 0:
		return GOAL_Z_TEAM0_DEFENDS - GOAL_NET_BACK_OFFSET
	return GOAL_Z_TEAM1_DEFENDS + GOAL_NET_BACK_OFFSET

static func attack_goal_z(team_id: int) -> float:
	return GOAL_Z_TEAM1_DEFENDS if team_id == 0 else GOAL_Z_TEAM0_DEFENDS

static func defend_goal_z(team_id: int) -> float:
	return GOAL_Z_TEAM0_DEFENDS if team_id == 0 else GOAL_Z_TEAM1_DEFENDS

static func attack_goal_vec(team_id: int) -> Vector3:
	return Vector3(0.0, 0.0, attack_goal_z(team_id))

static func defend_goal_vec(team_id: int) -> Vector3:
	return Vector3(0.0, 0.0, defend_goal_z(team_id))
