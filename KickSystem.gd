extends Node

# ============================================================
#  KickSystem.gd — STREET 3 ELITE
#  Contact quality system, stamina-aware power,
#  running shot bonus, natural swerve on passes.
#  KEY FIX: release_possession before apply_impulse so ball
#  is free before velocity is set — prevents spring fighting kick.
#  Phase 1: stat-driven power / accuracy when PlayerStats present.
# ============================================================

const SHOT_MAX := 22.5
const SUPER_SHOT_MAX := 31.0
const BANANA_SPIN_MIN := 9.0
const BANANA_SPIN_MAX := 18.0
const PASS_MIN := 11.0
const PASS_MAX := 18.5
# Soccer-course pass_to: v = sqrt(2 * distance * decel) — scaled for street cage
const PASS_ROLL_DECEL := 2.85
const PASS_HIGH_DIST  := 13.0

@export var player: CharacterBody3D
@export var ball_physics: Node
@export var dribble_system: Node

var arc_line_node: Node = null

func contact_quality(kick_dir: Vector3) -> float:
	if player == null or ball_physics == null:
		return 0.15
	var is_human: bool = player.get_meta("is_human", false)
	var fwd: Vector3 = _player_forward()
	var aim_n: Vector3 = kick_dir.normalized()
	if aim_n.length_squared() < 0.01:
		aim_n = fwd
	var align: float = clampf(fwd.dot(aim_n), 0.0, 1.0)
	var spd     : float   = player.get_speed()
	# Balance stat reduces quality loss at high speed (Phase 1)
	var s := _get_stats()
	var bal_mult := 1.0 - 0.25 * (1.0 if spd > 0.9 * 6.5 else 0.0)
	if s != null:
		bal_mult = 1.0 - (0.25 * (1.0 if spd > 0.9 * 6.5 else 0.0)) * (1.0 - s.balance / 99.0)
	var timing  : float   = clampf(1.0 - absf(player.get_foot_phase() - 0.5) * 1.8, 0.0, 1.0)
	var h_err   : float   = absf(ball_physics.ball_position.y - 0.12)
	var height  : float   = exp(-h_err * 8.0)
	var pressure: float   = _defender_pressure()
	if is_human:
		return clampf(0.76 + timing * 0.08 + height * 0.10 - pressure * 0.35, 0.68, 1.0)
	return clampf(align * 0.35 + bal_mult * 0.25 + timing * 0.20 + height * 0.20 - pressure, 0.15, 1.0)

func _defender_pressure() -> float:
	var pressure := 0.0
	for body in get_tree().get_nodes_in_group("players"):
		if body == player or body.get("team_id") == player.team_id: continue
		var d: float = player.global_position.distance_to(body.global_position)
		if d < 2.5:
			pressure += 0.12 * (1.0 - d / 2.5)
	return clampf(pressure, 0.0, 0.45)

func _get_stamina_mult() -> float:
	if player == null or not "stamina" in player: return 1.0
	return clampf(0.7 + player.stamina * 0.3, 0.7, 1.0)

func _get_running_bonus() -> float:
	if player == null: return 0.0
	var spd: float = player.get_speed() if player.has_method("get_speed") else 0.0
	return clampf(spd / 8.2 * 0.12, 0.0, 0.12)

## Returns PlayerStats from the player node, or nil if not yet assigned.
func _get_stats() -> PlayerStats:
	if player == null:
		return null
	return player.get("stats") as PlayerStats

func power_shot(aim_dir: Vector3, charge: float) -> void:
	var is_human: bool = player != null and player.get_meta("is_human", false)
	var q     := contact_quality(aim_dir)
	var stam  := _get_stamina_mult()
	var run   := _get_running_bonus()
	# ── Stat-driven power multiplier (Phase 1) ──
	var s := _get_stats()
	var stat_power_mult := s.get_shot_power_mult()   if s != null else 1.0
	var stat_acc        := s.get_shot_accuracy()      if s != null else 0.70
	# ── ALL_OUT_SHOOTING skill boost (Phase 2) ──
	var skill_boost: float = 1.0
	if player != null and player.has_meta("skill_shot_boost"):
		skill_boost = float(player.get_meta("skill_shot_boost"))
		player.remove_meta("skill_shot_boost")
	var box_bonus := 1.0
	if player != null:
		var dist_goal := player.global_position.distance_to(PitchConstants.attack_goal_vec(player.team_id))
		if dist_goal < 11.0:
			box_bonus = lerpf(1.0, 1.08, 1.0 - dist_goal / 11.0)
	var speed: float = lerp(12.5, SHOT_MAX, charge) * (0.5 + 0.5 * q) * stam * stat_power_mult * skill_boost * box_bonus + run * SHOT_MAX

	var shot_type := "normal"
	var fwd: Vector3 = _player_forward()
	var aim_n: Vector3 = aim_dir.normalized()
	var curl_side: float = signf(fwd.cross(aim_n).y)
	if absf(curl_side) < 0.01:
		curl_side = 1.0 if randf() > 0.5 else -1.0

	var is_super: bool = charge >= 0.88 and (skill_boost > 1.05 or q >= 0.68)
	var is_banana: bool = (not is_human) and not is_super and charge >= 0.55 and player.get_speed() > 3.8 and fwd.dot(aim_n) < 0.92

	var spin_y: float = 0.0 if is_human else randf_range(0.0, 2.0) * (1.0 - q)
	var impact_scale: float = 1.0
	if is_super:
		shot_type = "super"
		speed = lerpf(SHOT_MAX * 1.05, SUPER_SHOT_MAX, charge) * stat_power_mult * skill_boost
		spin_y = 0.0 if is_human else curl_side * lerpf(14.0, 22.0, charge)
		impact_scale = 1.12
	elif is_banana:
		shot_type = "banana"
		spin_y = curl_side * lerpf(BANANA_SPIN_MIN, BANANA_SPIN_MAX, charge * q)
		speed *= 1.04

	GameState.set_meta("pending_shot", {
		"shot_type": shot_type,
		"speed": speed,
		"charge": charge,
		"player_id": player.get_instance_id() if player else -1,
	})
	var angle: float = deg_to_rad(lerp(7.0, 17.0, charge))
	if is_super:
		angle = deg_to_rad(lerp(10.0, 22.0, charge))
	var err_mag := (1.0 - q) * 0.10 * (1.0 - stat_acc * 0.5)
	if is_human:
		err_mag = 0.0
	if is_super:
		err_mag *= 0.45
	elif is_banana:
		err_mag *= 0.72
	if player != null:
		var dg := player.global_position.distance_to(PitchConstants.attack_goal_vec(player.team_id))
		err_mag *= lerpf(1.0, 0.55, clampf(1.0 - dg / 12.0, 0.0, 1.0))
	var aim_err := _shot_aim_error(err_mag)
	var final_aim := (aim_n + aim_err).normalized()
	var vel: Vector3 = (final_aim + Vector3(0.0, tan(angle), 0.0)).normalized() * speed
	_apply_kick(vel, Vector3(0.0, spin_y, 0.0), false, impact_scale, shot_type)
	# Phase 4: event bus
	if Engine.has_singleton("MatchEventBus") or get_node_or_null("/root/MatchEventBus"):
		MatchEventBus.emit_shot(player, speed, player.team_id if player else 0)
	var td: Node = get_node_or_null("/root/TimeDilation")
	if td: td.on_kick(q, speed)

func curl_shot(aim_dir: Vector3, curl_side: float) -> void:
	var q     := contact_quality(aim_dir)
	var speed: float = lerp(14.0, 18.0, q)
	var angle: float = deg_to_rad(12.0)
	var side: float  = lerp(8.0, 13.0, absf(curl_side)) * signf(curl_side)
	var vel: Vector3 = (aim_dir.normalized() + Vector3(0.0, tan(angle), 0.0)).normalized() * speed
	_apply_kick(vel, Vector3(0.0, side, 0.0))

func chip_shot(aim_dir: Vector3) -> void:
	var q     := contact_quality(aim_dir)
	var speed: float = lerp(10.0, 14.0, q)
	var angle: float = deg_to_rad(30.0)
	var vel: Vector3 = (aim_dir.normalized() + Vector3(0.0, tan(angle), 0.0)).normalized() * speed
	_apply_kick(vel, Vector3(-5.0, 0.0, 0.0))

## Soccer-course style: pass speed derived from travel distance (sqrt(2*d*decel)).
func ground_pass_to(target_pos: Vector3, power: float, pass_target: Node = null, sharp_to_feet: bool = false, is_through: bool = false) -> void:
	if player == null:
		return
	var offset := target_pos - player.global_position
	offset.y = 0.0
	var dist := offset.length()
	if dist < 0.12:
		ground_pass(_player_forward(), power, pass_target, sharp_to_feet, is_through)
		return
	_execute_ground_pass(offset.normalized(), power, dist, pass_target, sharp_to_feet, is_through)

func ground_pass(aim_dir: Vector3, power: float, pass_target: Node = null, sharp_to_feet: bool = false, is_through: bool = false) -> void:
	var dist_hint := clampf(power * 18.0, 4.0, 18.0)
	if player != null and pass_target != null and is_instance_valid(pass_target):
		dist_hint = player.global_position.distance_to(pass_target.global_position)
	elif player != null:
		dist_hint = player.global_position.distance_to(
			player.global_position + aim_dir.normalized() * dist_hint
		)
	_execute_ground_pass(aim_dir, power, dist_hint, pass_target, sharp_to_feet, is_through)

func volley_shot(aim_dir: Vector3) -> bool:
	if player == null or ball_physics == null:
		return false
	var bp_pos: Vector3 = ball_physics.ball_position
	var to_ball: Vector3 = bp_pos - player.global_position
	to_ball.y = 0.0
	if to_ball.length() > 2.75:
		return false
	if bp_pos.y < 0.30 or bp_pos.y > 2.45:
		return false

	var q: float = maxf(contact_quality(aim_dir), 0.72)
	var speed: float = lerpf(17.5, 23.5, q)
	var angle: float = deg_to_rad(lerpf(7.0, 13.0, q))
	GameState.set_meta("pending_shot", {
		"shot_type": "volley",
		"speed": speed,
		"charge": 0.85,
		"player_id": player.get_instance_id(),
	})
	var vel: Vector3 = (aim_dir.normalized() + Vector3(0.0, tan(angle), 0.0)).normalized() * speed
	_apply_kick(vel, Vector3.ZERO, false, 1.05, "volley")
	MatchEventBus.emit_shot(player, speed, player.team_id)
	var td: Node = get_node_or_null("/root/TimeDilation")
	if td and q > 0.7:
		td.on_juggle_touch()
	return true

func _execute_ground_pass(aim_dir: Vector3, power: float, travel_dist: float, pass_target: Node = null, sharp_to_feet: bool = false, is_through: bool = false) -> void:
	var q: float = contact_quality(aim_dir)
	var final_power: float = power
	var is_human: bool = player != null and player.get_meta("is_human", false)
	if is_human:
		final_power = maxf(power, 0.72)
	var s: PlayerStats = _get_stats()
	var pass_acc: float = s.get_pass_accuracy(0) if s != null else 0.70
	var physics_speed: float = sqrt(2.0 * travel_dist * PASS_ROLL_DECEL)
	var speed: float
	var angle: float
	var swerve: float = 0.0
	if sharp_to_feet and pass_target != null:
		q = maxf(q, 0.88)
		speed = clampf(physics_speed, PASS_MIN * 0.92, PASS_MAX * 1.02)
		angle = 0.0
		swerve = 0.0
	else:
		var arcade_speed: float = lerpf(PASS_MIN, PASS_MAX, final_power)
		var blend: float = clampf(travel_dist / 16.0, 0.2, 0.9)
		speed = lerpf(arcade_speed, physics_speed, blend) * (0.62 + 0.38 * q)
		speed = clampf(speed, PASS_MIN * 0.85, PASS_MAX * 1.08)
		if is_human:
			speed = maxf(speed, lerpf(PASS_MIN, PASS_MAX, final_power) * 0.92)
		angle = deg_to_rad(lerp(0.0, 2.8, power))
		if travel_dist > PASS_HIGH_DIST:
			angle = deg_to_rad(lerp(8.0, 18.0, clampf((travel_dist - PASS_HIGH_DIST) / 8.0, 0.0, 1.0)))
		if player and player.get_speed() > 3.0 and not is_human:
			swerve = randf_range(-1.2, 1.2) * (1.0 - q) * 0.5 * (1.0 - pass_acc * 0.4)
	var vel: Vector3 = (aim_dir.normalized() + Vector3(0.0, tan(angle), 0.0)).normalized() * speed
	_apply_kick(vel, Vector3(0.0, swerve, 0.0), true)
	MatchEventBus.emit_pass(player, aim_dir, final_power, travel_dist > PASS_HIGH_DIST, is_through, pass_target)

func lob_pass(aim_dir: Vector3) -> void:
	var q     := contact_quality(aim_dir)
	var speed: float = lerp(8.0, 13.0, q)
	var angle: float = deg_to_rad(24.0)
	var vel: Vector3 = (aim_dir.normalized() + Vector3(0.0, tan(angle), 0.0)).normalized() * speed
	_apply_kick(vel, Vector3(1.5, 0.0, 0.0))
	# Phase 4: event bus
	MatchEventBus.emit_pass(player, aim_dir, q, true, false)

func try_trap(relative_speed: float, player_control: float) -> String:
	var jitter := randf_range(-0.1, 0.1)
	var q    := player_control - (relative_speed * 0.05) + jitter
	if q > 0.70:   return "clean"
	elif q >= 0.40: return "heavy"
	else:           return "miscontrol"

func _player_forward() -> Vector3:
	if player != null and player.has_method("get_facing_forward"):
		return player.get_facing_forward()
	var fwd := -player.transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)

## Spread error in camera space so fixed side-view does not bias every miss to screen-right.
func _shot_aim_error(err_mag: float) -> Vector3:
	if player == null or err_mag <= 0.0:
		return Vector3.ZERO
	var cam: Camera3D = player.get("camera") as Camera3D
	if cam == null:
		return Vector3(randf_range(-err_mag, err_mag), 0.0, randf_range(-err_mag, err_mag))
	var rgt := cam.global_basis.x
	rgt.y = 0.0
	if rgt.length_squared() > 0.01:
		rgt = rgt.normalized()
	else:
		rgt = Vector3.RIGHT
	var cam_fwd := -cam.global_basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length_squared() > 0.01:
		cam_fwd = cam_fwd.normalized()
	else:
		cam_fwd = Vector3.FORWARD
	return rgt * randf_range(-err_mag, err_mag) + cam_fwd * randf_range(-err_mag, err_mag)

func _apply_kick(vel: Vector3, spin: Vector3, is_pass: bool = false, impact_scale: float = 1.0, shot_kind: String = "") -> void:
	if ball_physics == null:
		return
	if player != null and "team_id" in player:
		PossessionManager.register_touch(int(player.team_id))
	if dribble_system and dribble_system.has_method("release_possession"):
		if is_pass and dribble_system.has_method("release_for_pass"):
			dribble_system.release_for_pass()
		elif (not is_pass) and dribble_system.has_method("release_for_shot"):
			dribble_system.release_for_shot(vel.length())
		else:
			dribble_system.release_possession()
	ball_physics.wake()
	if ball_physics.has_method("apply_kick_impulse"):
		ball_physics.apply_kick_impulse(vel, spin, impact_scale)
	else:
		ball_physics.apply_impulse(vel, spin)
	var power: float = vel.length() * impact_scale
	SoundManager.kick(power, ball_physics.global_position)
	_feed_impact_feedback(power, spin.length(), shot_kind, is_pass)

func _feed_impact_feedback(power: float, spin_mag: float, shot_kind: String, is_pass: bool) -> void:
	if shot_kind == "super":
		ScreenShake.power_shot()
		var td: Node = get_node_or_null("/root/TimeDilation")
		if td:
			td.slow(0.72, 0.35)
	elif shot_kind == "banana":
		ScreenShake.shot()
	elif power > 18.0 and not is_pass:
		ScreenShake.shot()
	elif power > 12.0 and is_pass:
		ScreenShake.light()
	if spin_mag > 10.0:
		for node in get_tree().get_nodes_in_group("camera_rig"):
			if node.has_method("punch_impact"):
				node.punch_impact(clampf(spin_mag / 22.0, 0.08, 0.35))
