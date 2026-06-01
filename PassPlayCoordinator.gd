extends Node
class_name PassPlayCoordinator

# ============================================================
#  PassPlayCoordinator.gd — Pass support runs
#  Regular pass: ball to feet, receiver holds position.
#  Through pass: receiver runs into space, others support.
# ============================================================

const RECEIVE_FEET_DURATION := 1.8
const THROUGH_DURATION := 2.6
const SUPPORT_DURATION := 2.2
const PASS_ROLL_DECEL := 2.85
const PASS_MIN_SPEED := 9.2
const PASS_MAX_SPEED := 16.0

var _ball: Node = null

func setup(ball: Node) -> void:
	_ball = ball
	if not MatchEventBus.pass_attempted.is_connected(_on_pass_attempted):
		MatchEventBus.pass_attempted.connect(_on_pass_attempted)

func assign_pass(passer: Node, receiver: Node, lead_pos: Vector3 = Vector3.ZERO, is_through: bool = false) -> void:
	if not is_instance_valid(passer) or not is_instance_valid(receiver):
		return
	if is_through:
		var intercept := lead_pos
		if intercept.length_squared() < 0.01:
			intercept = _predict_through_lead(passer, receiver)
		_assign_receive_run(receiver, intercept, "through")
		_assign_support_runs(passer, receiver, intercept)
	else:
		# Regular pass — stay on feet, ball comes to you.
		_assign_receive_run(receiver, _feet_pos(receiver), "feet")

func _on_pass_attempted(passer_id: int, target_id: int, ptype: int) -> void:
	if target_id < 0:
		return
	var passer := instance_from_id(passer_id)
	var receiver := instance_from_id(target_id)
	if not is_instance_valid(passer) or not is_instance_valid(receiver):
		return
	var is_through := ptype == MatchEventBus.PassType.AHEAD
	assign_pass(passer, receiver, Vector3.ZERO, is_through)

func _feet_pos(player: Node) -> Vector3:
	var pos: Vector3 = player.global_position
	pos.y = 0.11
	return pos

func _predict_through_lead(passer: Node, receiver: Node) -> Vector3:
	var recv_pos: Vector3 = receiver.global_position
	var offset: Vector3 = recv_pos - passer.global_position
	offset.y = 0.0
	var dist: float = offset.length()
	if dist < 0.15:
		return _feet_pos(receiver)

	var recv_vel := _estimate_receiver_velocity(receiver)
	var pass_speed: float = clampf(sqrt(2.0 * dist * PASS_ROLL_DECEL), PASS_MIN_SPEED, PASS_MAX_SPEED)
	var travel_t: float = clampf(dist / pass_speed, 0.15, 0.75)
	var lead: Vector3 = recv_pos + recv_vel * travel_t * 1.15
	lead.y = 0.11
	return PitchConstants.clamp_player(lead)

func _estimate_receiver_velocity(receiver: Node) -> Vector3:
	var body := receiver as CharacterBody3D
	if body == null:
		return Vector3.ZERO
	if "horizontal_velocity" in body:
		var hv: Vector3 = body.horizontal_velocity
		hv.y = 0.0
		if hv.length_squared() > 1.0:
			return hv
	if "velocity" in body:
		var v: Vector3 = body.velocity
		v.y = 0.0
		return v
	return Vector3.ZERO

func _assign_receive_run(receiver: Node, target: Vector3, mode: String) -> void:
	receiver.set_meta("pass_run_target", target)
	receiver.set_meta("pass_run_mode", mode)
	var dur := THROUGH_DURATION if mode == "through" else RECEIVE_FEET_DURATION
	receiver.set_meta("pass_run_expires", _now() + dur)
	receiver.set_meta("pass_run_sprint", mode == "through")

func _assign_support_runs(passer: Node, receiver: Node, intercept: Vector3) -> void:
	var team: int = int(passer.get("team_id"))
	var attack_goal: Vector3 = PitchConstants.attack_goal_vec(team)
	var to_goal: Vector3 = attack_goal - intercept
	to_goal.y = 0.0
	if to_goal.length_squared() > 0.01:
		to_goal = to_goal.normalized()
	else:
		to_goal = Vector3(0.0, 0.0, signf(attack_goal.z))

	var lateral: Vector3 = Vector3(-to_goal.z, 0.0, to_goal.x)
	var run_idx := 0
	for p in get_tree().get_nodes_in_group("players"):
		if p == passer or p == receiver:
			continue
		if not is_instance_valid(p) or int(p.get("team_id")) != team:
			continue
		var slot: int = int(p.get_meta("slot_index", run_idx))
		var side: float = 1.0 if slot % 2 == 0 else -1.0
		var depth: float = 3.5 + float(run_idx) * 1.8
		var width: float = 3.2 + float(run_idx) * 0.9
		var run_target: Vector3 = intercept + to_goal * depth + lateral * side * width
		run_target.y = 0.11
		run_target = PitchConstants.clamp_player(run_target)
		p.set_meta("pass_run_target", run_target)
		p.set_meta("pass_run_mode", "support")
		p.set_meta("pass_run_expires", _now() + SUPPORT_DURATION)
		p.set_meta("pass_run_sprint", true)
		run_idx += 1

func _ball_pos() -> Vector3:
	if _ball == null:
		return Vector3.ZERO
	if "ball_position" in _ball:
		return _ball.ball_position
	return _ball.global_position

func _now() -> float:
	return Time.get_ticks_msec() * 0.001

static func clear_pass_run(player: Node) -> void:
	if player == null:
		return
	for key in ["pass_run_target", "pass_run_mode", "pass_run_expires", "pass_run_sprint"]:
		if player.has_meta(key):
			player.remove_meta(key)
