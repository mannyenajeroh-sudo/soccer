extends CharacterBody3D

# ============================================================
# PlayerController.gd — STREET 3 ELITE
# Unified physics for BOTH human and AI players.
# ============================================================

@onready var _dribble := $DribbleSystem as Node
@onready var _kick := $KickSystem as Node
@onready var _tackle := $TackleSystem as Node
@onready var _skills := $SkillMoves as Node
@onready var _aerial := $AerialMechanics as Node
@onready var _juggle := $JuggleSystem as Node

var _charge_timer     := 0.0
var _charge_aim_dir   := Vector3.ZERO  # Soccer-course: steer shot while charging
var _is_charging      := false
var _power_volley_rdy := false

const MAX_SPEED       := 6.5
const SPRINT_SPEED    := 8.2
const ACCEL_BURST     := 24.0
const ACCEL_SUSTAIN   := 15.0
const DECEL           := 18.0
const BURST_TIME      := 0.15
const TURN_RATE       := 420.0
const TURN_SPRINT     := 300.0
const SPRINT_MAX_TIME := 2.5
const SPRINT_MIN_INPUT:= 0.45

const STAMINA_DRAIN      := 0.35
const STAMINA_REGEN      := 0.28
const STAMINA_SPRINT_MIN := 0.12

const AIM_ASSIST_STRENGTH := 0.14
const AIM_ASSIST_MAX_DIST := 16.0
const COYOTE_TACKLE_TIME  := 0.25
const BALL_ACTION_DIST    := 2.35  # pass/shoot without full possession claim
const PLAYER_COLL_RADIUS  := 0.42
const PLAYER_BUMP_FORCE   := 2.2
const SLIDE_BUMP_MULT     := 1.7

@export var team_id: int = 0
@export var camera: Camera3D

# ── Stats ─────────────────────────────────────────────────────
@export var stats: PlayerStats = null
var baller_data: BallerData = null
var player_rating: float = 0.5

var _stamina_regen_mult: float = 1.0

# Signals
signal sprint_state_changed(is_sprinting: bool)
signal close_control_toggled(active: bool)
signal charge_updated(value: float)
signal stamina_changed(value: float)

# State
var horizontal_velocity := Vector3.ZERO
var facing := 0.0
var is_sprinting := false
var close_control := false
var stamina := 1.0
var _sprint_timer := 0.0
var _foot_phase := 0.0
var _burst_timer := 0.0
var _was_moving := false
var _coyote_timer := 0.0
var _shoot_armed := false
var _pass_armed := false
var _through_armed := false
var _tackle_armed := false
var _last_pass_press_time := -10.0
var _pass_handled_frame := -1

const PASS_DOUBLE_TAP_MIN := 0.10
const PASS_DOUBLE_TAP_MAX := 0.32

# Action buffering
var _buffered_action: StringName = &""
var _buffer_timer: float = 0.0
const BUFFER_WINDOW := 0.22

@onready var facing_pivot    := $FacingPivot
@onready var mesh_instance   := $FacingPivot/MeshInstance3D
@onready var collision_shape := $CollisionShape3D

func _ready() -> void:
	collision_shape.shape.radius = 0.4
	collision_shape.shape.height = 1.8
	collision_shape.position.y   = 0.9
	_sync_stats_to_subsystems()

func set_baller_stats(s: PlayerStats) -> void:
	stats = s
	player_rating = s.get_skill_rating()
	_sync_stats_to_subsystems()

func _sync_stats_to_subsystems() -> void:
	if stats == null:
		return
	if _tackle != null:
		_tackle.tackling_stat = stats.get_tackling_stat()
		_tackle.control_stat  = stats.get_control_stat()
	_stamina_regen_mult = stats.get_stamina_regen_mult()

func get_reaction_delay() -> float:
	if stats != null:
		return stats.get_reaction_delay()
	return 0.20

# ─────────────────────────────────────────────────────────────
# PHYSICS PROCESS
# ─────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	# Shared gravity
	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = 0.0

	# AI players — movement handled by AIController
	if not get_meta("is_human", false):
		move_and_slide()
		_apply_player_collisions()
		_clamp_to_pitch()
		return

	# Human player — freeze during stoppages (goal celebrations, etc.)
	if GameState.phase != GameState.Phase.PLAY:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, 1.0 - exp(-14.0 * delta))
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.z
		move_and_slide()
		_clamp_to_pitch()
		return

	_process_buffer(delta)
	_try_execute_buffered_action()
	_update_foot_phase(delta)
	var dir := _get_world_input()
	var pass_run := _get_pass_run_direction()
	if pass_run.length_squared() > 0.01:
		if dir.length() < 0.22 or pass_run.dot(dir.normalized()) > 0.35:
			dir = pass_run
		is_sprinting = true
	_apply_movement(dir, delta)
	_update_facing(dir, delta)
	_update_sprint(dir, delta)
	_update_stamina(delta)
	_update_coyote(delta)
	_handle_input(delta)

	move_and_slide()
	_apply_player_collisions()
	_clamp_to_pitch()

func _apply_player_collisions() -> void:
	var min_sep: float = PLAYER_COLL_RADIUS * 2.0
	var sliding: bool = _tackle != null and _tackle.is_sliding
	for body in get_tree().get_nodes_in_group("players"):
		if body == self or not is_instance_valid(body):
			continue
		var other: CharacterBody3D = body as CharacterBody3D
		if other == null:
			continue
		var delta_p: Vector3 = global_position - other.global_position
		delta_p.y = 0.0
		var dist: float = delta_p.length()
		if dist >= min_sep or dist < 0.001:
			continue
		var sep: Vector3 = delta_p / dist
		var overlap: float = min_sep - dist
		global_position += sep * overlap * 0.24
		var bump: float = PLAYER_BUMP_FORCE * overlap
		if sliding:
			bump *= SLIDE_BUMP_MULT
		velocity = velocity.lerp(velocity + sep * bump, 0.35)
		other.velocity = other.velocity.lerp(other.velocity - sep * bump * 0.45, 0.25)
		if sliding and other.has_node("TackleSystem"):
			var ots: Node = other.get_node("TackleSystem")
			if ots.has_method("_start_stumble"):
				ots._start_stumble(0.5)

func _clamp_to_pitch() -> void:
	global_position = PitchConstants.clamp_player(global_position)

# ─────────────────────────────────────────────────────────────
# INPUT HANDLING — keyboard/gamepad via _input (reliable just_pressed)
# ─────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not get_meta("is_human", false):
		return
	if GameState.phase == GameState.Phase.FREEKICK:
		_handle_set_piece_input(event)
		return
	if GameState.phase != GameState.Phase.PLAY:
		return

	if event.is_action("shoot"):
		if event.is_pressed():
			if _shoot_armed:
				return
			if _is_busy():
				_buffer_action(&"shoot")
			else:
				_on_shoot_pressed()
				_shoot_armed = _is_charging
		else:
			if _shoot_armed:
				_on_shoot_released()
			_shoot_armed = false
		return

	if event.is_echo():
		return

	if not event.is_pressed():
		return

	if event.is_action("pass"):
		if _is_busy() and (_juggle == null or not _juggle.get("is_active")):
			_buffer_action(&"pass")
		else:
			_handle_pass_action()
	elif event.is_action("through_pass"):
		if _is_busy():
			_buffer_action(&"through_pass")
		else:
			_on_through_pass()
	elif event.is_action("tackle"):
		if _is_busy():
			_buffer_action(&"tackle")
		else:
			_perform_defensive_tackle()
	elif event.is_action("skill_flick"):
		_skills.try_flick_up(_get_action_direction())
	elif event.is_action("skill_stepover"):
		_skills.try_skill(SkillMoves.SkillMove.STEPOVER)
	elif event.is_action("skill_roulette"):
		_skills.try_skill(SkillMoves.SkillMove.MARSEILLE_TURN)

func _get_set_pieces() -> Node:
	for node in get_tree().get_nodes_in_group("set_pieces"):
		if node.has_method("is_active_taker"):
			return node
	return null

func _handle_set_piece_input(event: InputEvent) -> void:
	var sp := _get_set_pieces()
	if sp == null or not sp.is_active_taker(self):
		return
	if event.is_echo():
		return

	if event.is_action("shoot"):
		if event.is_pressed():
			if not _shoot_armed:
				_on_shoot_pressed()
				_shoot_armed = _is_charging
		else:
			if _shoot_armed:
				var dir := _get_action_direction()
				var charge: float = clampf(_charge_timer / 0.8, 0.0, 1.0)
				if charge < 0.12:
					charge = 0.55
				_is_charging = false
				_shoot_armed = false
				_charge_timer = 0.0
				charge_updated.emit(0.0)
				sp.execute_pass(dir, charge)
		return

	if not event.is_pressed():
		return

	if event.is_action("pass"):
		sp.execute_pass(_get_action_direction(), 0.75)

func _handle_input(delta: float) -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	# Touch fallback: ensure synthetic InputEventAction also triggers core actions.
	if Input.is_action_just_pressed("pass"):
		if _is_busy() and (_juggle == null or not _juggle.get("is_active")):
			_buffer_action(&"pass")
		else:
			_handle_pass_action()
	if Input.is_action_pressed("pass"):
		_pass_armed = true
	else:
		_pass_armed = false
	if Input.is_action_pressed("through_pass"):
		if not _through_armed:
			if _is_busy():
				_buffer_action(&"through_pass")
			else:
				_on_through_pass()
			_through_armed = true
	else:
		_through_armed = false
	if Input.is_action_pressed("tackle"):
		if not _tackle_armed:
			if _is_busy():
				_buffer_action(&"tackle")
			else:
				_perform_defensive_tackle()
			_tackle_armed = true
	else:
		_tackle_armed = false

	var cc := Input.is_action_pressed("close_control")
	if cc != close_control:
		close_control = cc
		close_control_toggled.emit(cc)

	var stick_raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_skills.track_roulette_input(stick_raw, close_control)
	_skills.track_stepover_input(stick_raw)

	if _is_charging and (Input.is_action_pressed("shoot") or _shoot_armed):
		_charge_timer += delta
		charge_updated.emit(clampf(_charge_timer / 0.8, 0.0, 1.0))
		var aim_adj := _get_pitch_input()
		if aim_adj.length() > 0.08:
			var aim_n := aim_adj.normalized()
			var hvel := Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z)
			if not get_meta("is_human", false) and hvel.length_squared() > 6.25 and aim_n.dot(hvel.normalized()) < -0.35:
				pass  # ignore backward stick while sprinting — keeps run-and-shoot forward
			else:
				_snap_facing_toward(aim_n)
				_charge_aim_dir = _flat_forward()

	if _skills.is_busy():
		if Input.is_action_just_pressed("pass") or Input.is_action_just_pressed("tackle"):
			_skills.try_cancel()

	_update_wall_volley_window()

	# Auto pickup (disabled while juggling — ball stays aerial)
	if _juggle != null and _juggle.get("is_active"):
		pass
	elif not _dribble.in_possession and _dribble.ball_physics != null:
		var bp_pos: Vector3 = _dribble.ball_physics.ball_position
		_dribble.try_pickup(bp_pos)

# ─────────────────────────────────────────────────────────────
# MOVEMENT
# ─────────────────────────────────────────────────────────────

func _get_world_input() -> Vector3:
	var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if raw.length() < 0.15:
		return Vector3.ZERO

	var dir: Vector3
	if camera != null:
		var fwd: Vector3 = -camera.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var rgt: Vector3 = camera.global_basis.x
		rgt.y = 0.0
		rgt = rgt.normalized()
		dir = rgt * raw.x + fwd * (-raw.y)
	else:
		# Desktop fallback before camera rig assigns — world XZ from stick
		dir = Vector3(raw.x, 0.0, -raw.y)

	var mag: float = clampf((raw.length() - 0.15) / 0.85, 0.0, 1.0)
	return dir.normalized() * mag

func _get_pitch_input() -> Vector3:
	var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if raw.length() < 0.15:
		return Vector3.ZERO
	var mag: float = clampf((raw.length() - 0.15) / 0.85, 0.0, 1.0)
	return Vector3(raw.x, 0.0, -raw.y).normalized() * mag

func set_kit_colour(col: Color) -> void:
	var visuals := get_node_or_null("PlayerVisuals")
	if visuals and visuals.has_method("set_kit_colour"):
		visuals.set_kit_colour(col)
	if mesh_instance == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.7
	mat.metallic = 0.1
	mesh_instance.material_override = mat

func _apply_movement(dir: Vector3, delta: float) -> void:
	if _tackle != null:
		if _tackle.is_sliding:
			# Bypass user input to let slide velocity carry through naturally
			horizontal_velocity = Vector3(velocity.x, 0.0, velocity.z)
			return
		if _tackle.is_stumbling:
			# Decay velocity rapidly during stumbling
			horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, 1.0 - exp(-12.0 * delta))
			velocity.x = horizontal_velocity.x
			velocity.z = horizontal_velocity.z
			return

	var spd_mult := clampf(0.6 + stamina * 0.4, 0.6, 1.0)
	var speed: float = (SPRINT_SPEED if is_sprinting else MAX_SPEED) * spd_mult
	if close_control:
		speed = minf(speed, 4.5)

	var target: Vector3 = dir * speed if dir.length() > 0.01 else Vector3.ZERO
	var has_input: bool = dir.length() > 0.01
	var aligned: bool = horizontal_velocity.dot(dir) >= 0.0 if has_input else false

	var rate: float
	if has_input and aligned:
		if not _was_moving:
			_burst_timer = 0.0
		_burst_timer += delta
		rate = ACCEL_BURST if _burst_timer < BURST_TIME else ACCEL_SUSTAIN
	else:
		_burst_timer = 0.0
		rate = DECEL

	_was_moving = has_input
	horizontal_velocity = horizontal_velocity.lerp(target, 1.0 - exp(-rate * delta))

	if horizontal_velocity.length() < 0.05 and not has_input:
		horizontal_velocity = Vector3.ZERO

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

func _update_facing(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.08:
		return
	var target_angle: float = atan2(dir.x, dir.z)
	var rate: float = deg_to_rad(TURN_SPRINT if is_sprinting else TURN_RATE)
	facing = lerp_angle(facing, target_angle, rate * delta)
	if facing_pivot:
		facing_pivot.rotation.y = facing
	# Keep root transform aligned so kick/dribble aim matches the visible facing.
	rotation.y = facing

## Direction for pass / shoot / tackle: where the capsule faces (not raw camera stick).
func _get_action_direction() -> Vector3:
	var stick := _get_pitch_input()
	if stick.length() > 0.12:
		_snap_facing_toward(stick.normalized())
	return _flat_forward()

func _flat_forward() -> Vector3:
	var fwd := get_facing_forward()
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		return Vector3(0.0, 0.0, -1.0)
	return fwd.normalized()

## Shot aim: charge direction, then sprint velocity, then facing — no release-time stick snap.
func _get_shot_direction() -> Vector3:
	var dir := Vector3.ZERO
	if _charge_aim_dir.length_squared() > 0.01:
		dir = _charge_aim_dir

	var hvel := Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z)
	if not get_meta("is_human", false) and hvel.length_squared() > 6.25:
		var vel_n := hvel.normalized()
		if dir.length_squared() < 0.01 or dir.dot(vel_n) < 0.35:
			dir = vel_n

	if dir.length_squared() < 0.01:
		dir = _flat_forward()

	if not get_meta("is_human", false):
		dir = _get_aim_assisted_dir(dir)
	if dir.length_squared() > 0.01:
		_snap_facing_toward(dir)
	return dir.normalized() if dir.length_squared() > 0.01 else dir

func _snap_facing_toward(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	facing = atan2(dir.x, dir.z)
	if facing_pivot:
		facing_pivot.rotation.y = facing
	rotation.y = facing

## Flat forward/right from FacingPivot (not stale CharacterBody basis).
func get_facing_forward() -> Vector3:
	if facing_pivot:
		var f: Vector3 = -facing_pivot.global_transform.basis.z
		f.y = 0.0
		if f.length_squared() > 0.01:
			return f.normalized()
	var f2 := Vector3(sin(facing), 0.0, cos(facing))
	return f2 if f2.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)

func get_facing_right() -> Vector3:
	if facing_pivot:
		var r: Vector3 = facing_pivot.global_transform.basis.x
		r.y = 0.0
		if r.length_squared() > 0.01:
			return r.normalized()
	return Vector3(cos(facing), 0.0, -sin(facing))

# ─────────────────────────────────────────────────────────────
# SPRINT & STAMINA
# ─────────────────────────────────────────────────────────────

func _update_sprint(dir: Vector3, delta: float) -> void:
	if not get_meta("is_human", false):
		return
	var sprint_input: bool = Input.is_action_pressed("sprint") and dir.length() > SPRINT_MIN_INPUT
	if sprint_input and not is_sprinting and stamina >= STAMINA_SPRINT_MIN:
		is_sprinting = true
		_sprint_timer = 0.0
		sprint_state_changed.emit(true)

	if is_sprinting:
		_sprint_timer += delta
		if _sprint_timer >= SPRINT_MAX_TIME or not sprint_input or stamina <= 0.0:
			is_sprinting = false
			sprint_state_changed.emit(false)

func _update_stamina(delta: float) -> void:
	if is_sprinting:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN * delta)
	else:
		stamina = minf(1.0, stamina + STAMINA_REGEN * _stamina_regen_mult * delta)

	if get_meta("is_human", false):
		stamina_changed.emit(stamina)

func _update_coyote(delta: float) -> void:
	if _coyote_timer > 0.0:
		_coyote_timer -= delta

func _update_foot_phase(delta: float) -> void:
	var walk_speed: float = horizontal_velocity.length()
	if walk_speed > 0.5:
		_foot_phase = fmod(_foot_phase + delta * (walk_speed / MAX_SPEED) * 2.2, 1.0)

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

func get_foot_phase() -> float: 
	return _foot_phase

func get_speed() -> float: 
	return horizontal_velocity.length()

func set_sprinting(state: bool) -> void:
	if state != is_sprinting:
		is_sprinting = state
		sprint_state_changed.emit(state)

# ─────────────────────────────────────────────────────────────
# SHOOT / PASS / TACKLE
# ─────────────────────────────────────────────────────────────

func _update_wall_volley_window() -> void:
	if not has_meta("wall_volley_ready") or not bool(get_meta("wall_volley_ready")):
		_power_volley_rdy = false
		return
	var until: int = int(get_meta("wall_volley_until", 0))
	if Time.get_ticks_msec() > until:
		remove_meta("wall_volley_ready")
		remove_meta("wall_volley_until")
		_power_volley_rdy = false
		return
	if _dribble == null or _dribble.ball_physics == null:
		return
	var bp: Vector3 = _dribble.ball_physics.ball_position
	var dist: float = global_position.distance_to(bp)
	if bp.y < 0.35 or bp.y > 2.4 or dist > 3.2:
		return
	var to_player: Vector3 = global_position - bp
	to_player.y = 0.0
	var ball_vel: Vector3 = _dribble.ball_physics.velocity
	if to_player.length_squared() > 0.04 and ball_vel.dot(to_player.normalized()) > 0.5:
		_power_volley_rdy = true

func _try_wall_return_volley(aim_dir: Vector3) -> bool:
	if not _power_volley_rdy and not (has_meta("wall_volley_ready") and bool(get_meta("wall_volley_ready"))):
		return false
	if _aerial.try_volley(aim_dir):
		_power_volley_rdy = false
		if has_meta("wall_volley_ready"):
			remove_meta("wall_volley_ready")
		if has_meta("wall_volley_until"):
			remove_meta("wall_volley_until")
		return true
	return false

func _handle_pass_action() -> void:
	var frame := Engine.get_physics_frames()
	if _pass_handled_frame == frame:
		return
	_pass_handled_frame = frame

	if _juggle != null and _juggle.get("is_active"):
		if _juggle.has_method("register_pass_tap"):
			_juggle.register_pass_tap()
		return

	var now := Time.get_ticks_msec() * 0.001
	var gap: float = now - _last_pass_press_time

	if gap >= PASS_DOUBLE_TAP_MIN and gap < PASS_DOUBLE_TAP_MAX and _last_pass_press_time > 0.0:
		_last_pass_press_time = -10.0
		if _juggle != null and _juggle.has_method("try_start_juggle"):
			_juggle.try_start_juggle()
		return

	_last_pass_press_time = now
	_on_pass_or_press()

func _on_shoot_pressed() -> void:
	if _skills.is_busy():
		_is_charging = false
		return
	if _juggle != null and _juggle.get("is_active"):
		if _juggle.has_method("register_shoot_tap"):
			_juggle.register_shoot_tap()
		_is_charging = false
		return
	if _skills.register_shoot_tap():
		_is_charging = false
		_charge_timer = 0.0
		charge_updated.emit(0.0)
		return
	_is_charging = true
	_charge_timer = 0.0
	var hvel := Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z)
	if hvel.length_squared() > 6.25:
		_charge_aim_dir = hvel.normalized()
	else:
		_charge_aim_dir = _flat_forward()

func _on_shoot_released() -> void:
	if not _is_charging:
		return
	_is_charging = false
	var charge: float = clampf(_charge_timer / 0.8, 0.0, 1.0)
	if charge < 0.12:
		charge = 0.38
	charge_updated.emit(0.0)

	var dir := _get_shot_direction()

	if _try_wall_return_volley(dir):
		return
	if _juggle != null and _juggle.has_method("try_finish_volley") and _juggle.try_finish_volley(dir):
		return
	# Volley before possession claim — ball must be in air near feet.
	if not _dribble.in_possession and _aerial.try_volley(dir):
		return
	if _aerial.try_bicycle_kick(dir): return
	if _aerial.try_header(dir): return

	if not _try_claim_ball_for_action():
		return
	if _dribble.in_possession:
		_kick.power_shot(dir, charge)
	else:
		var to_ball: Vector3 = _dribble.ball_physics.ball_position - global_position
		to_ball.y = 0.0
		var shot_dir := to_ball.normalized() if to_ball.length() > 0.15 else dir
		PossessionManager.force_release()
		_kick.power_shot(shot_dir, maxf(charge, 0.38) * 0.88)

	_charge_timer = 0.0

func _ensure_ball_contact() -> bool:
	return _try_claim_ball_for_action()

func _try_claim_ball_for_action() -> bool:
	if _dribble == null or _dribble.ball_physics == null:
		return false
	if _dribble.in_possession:
		return true
	var bp_pos: Vector3 = _dribble.ball_physics.ball_position
	_dribble.try_pickup(bp_pos)
	if _dribble.in_possession:
		return true
	var to_ball: Vector3 = bp_pos - global_position
	to_ball.y = 0.0
	return to_ball.length() < BALL_ACTION_DIST

func _on_pass_or_press() -> void:
	if _dribble.in_possession:
		_on_pass()
		return
	if _team_has_possession():
		_request_pass_from_teammate()
		return
	_perform_defensive_tackle()

func _request_pass_from_teammate() -> void:
	var possessor := PossessionManager.get_possessor()
	if possessor == null or possessor == self or not is_instance_valid(possessor):
		return
	if possessor.team_id != team_id:
		return
	if not possessor.get_meta("is_ai", false):
		return
	possessor.set_meta("pass_requested_by", get_instance_id())
	possessor.set_meta("pass_request_target", global_position)

func _team_has_possession() -> bool:
	var possessor := PossessionManager.get_possessor()
	if possessor != null and is_instance_valid(possessor):
		return possessor.team_id == team_id
	return false

func _on_pass() -> void:
	if not _try_claim_ball_for_action():
		return
	var raw_dir := _get_action_direction()
	if not _dribble.in_possession:
		PossessionManager.force_release()
		_kick.ground_pass(raw_dir.normalized(), 0.62)
		return
	var pick := _pick_pass_target(raw_dir)
	var target: Node = pick.get("target")
	if target != null:
		var feet: Vector3 = pick.lead
		_notify_pass_switch(target, feet, false)
		_kick.ground_pass_to(feet, 0.74, target, true)
	else:
		_kick.ground_pass(pick.dir, 0.70)

func _pick_pass_target(raw_dir: Vector3) -> Dictionary:
	var result := {"target": null, "lead": Vector3.ZERO, "dir": Vector3.FORWARD}
	var best_target: CharacterBody3D = null
	var best_score: float = -999.0
	var my_pos: Vector3 = global_position
	var input_dir: Vector3 = raw_dir.normalized() if raw_dir.length() > 0.1 else Vector3.ZERO
	var has_input := raw_dir.length() > 0.1
	var facing_dir: Vector3 = get_facing_forward()
	facing_dir.y = 0.0
	if facing_dir.length_squared() > 0.01:
		facing_dir = facing_dir.normalized()
	for teammate_obj in get_tree().get_nodes_in_group("players"):
		var teammate: CharacterBody3D = teammate_obj as CharacterBody3D
		if teammate == null or teammate == self or teammate.team_id != team_id:
			continue
		if not is_instance_valid(teammate):
			continue
		var to_mate: Vector3 = teammate.global_position - my_pos
		to_mate.y = 0.0
		var dist: float = to_mate.length()
		if dist < 1.4 or dist > 22.0:
			continue
		var to_mate_dir: Vector3 = to_mate.normalized()
		var alignment: float = input_dir.dot(to_mate_dir) if has_input else facing_dir.dot(to_mate_dir)
		var min_align: float = 0.08 if not has_input else 0.92
		if alignment < min_align:
			continue
		var obstruction: float = 0.0
		for opponent_obj in get_tree().get_nodes_in_group("players"):
			var opponent: CharacterBody3D = opponent_obj as CharacterBody3D
			if opponent == null or opponent.team_id == team_id or not is_instance_valid(opponent):
				continue
			var opp_pos: Vector3 = opponent.global_position
			var proj: Vector3 = my_pos + to_mate_dir * clampf((opp_pos - my_pos).dot(to_mate_dir), 0.0, dist)
			var dist_to_line: float = (opp_pos - proj).length()
			if dist_to_line < 1.3:
				obstruction += (1.3 - dist_to_line) / 1.3
		var run_bonus: float = 0.0
		if teammate.has_meta("pass_run_target"):
			var run_t: Vector3 = teammate.get_meta("pass_run_target") as Vector3
			var run_dir: Vector3 = run_t - teammate.global_position
			run_dir.y = 0.0
			if run_dir.length_squared() > 0.2:
				run_bonus += run_dir.normalized().dot(to_mate_dir) * 0.45
		if teammate.velocity.length() > 1.5:
			run_bonus += teammate.velocity.normalized().dot(to_mate_dir) * 0.28
		var attack_goal: Vector3 = PitchConstants.attack_goal_vec(team_id)
		var forward_bonus: float = to_mate_dir.dot((attack_goal - my_pos).normalized()) * 0.22
		var dist_score: float = 1.0 - (dist / 24.0)
		var score: float = alignment * 1.55 + dist_score * 0.42 + run_bonus + forward_bonus - obstruction * 0.55
		if score > best_score:
			best_score = score
			best_target = teammate
	if best_target and best_score > 0.28:
		var feet := _pass_target_feet(best_target)
		result.target = best_target
		result.lead = feet
		result.dir = (feet - my_pos).normalized()
		return result
	var fallback_dir: Vector3 = input_dir if has_input else facing_dir
	if fallback_dir.length_squared() < 0.01:
		fallback_dir = facing_dir
	result.dir = fallback_dir
	return result

func _pass_target_feet(target: CharacterBody3D) -> Vector3:
	var feet := target.global_position
	feet.y = 0.11
	return PitchConstants.clamp_player(feet)

func _lead_pass_position(target: CharacterBody3D) -> Vector3:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var lead := target.global_position
	var recv_vel := Vector3.ZERO
	if target.has_meta("pass_run_target"):
		var run_t: Vector3 = target.get_meta("pass_run_target") as Vector3
		var to_run: Vector3 = run_t - target.global_position
		to_run.y = 0.0
		if to_run.length_squared() > 0.2:
			recv_vel = to_run.normalized() * 6.8
	elif "horizontal_velocity" in target:
		var hv: Vector3 = target.horizontal_velocity
		hv.y = 0.0
		if hv.length_squared() > 1.0:
			recv_vel = hv
	elif "velocity" in target:
		recv_vel = Vector3(target.velocity.x, 0.0, target.velocity.z)
	var pass_speed: float = clampf(sqrt(2.0 * to_target.length() * 2.85), 9.2, 16.0)
	var lead_time: float = clampf(to_target.length() / pass_speed, 0.12, 0.58)
	lead += recv_vel * lead_time
	lead.y = global_position.y
	return PitchConstants.clamp_player(lead)

func _on_through_pass() -> void:
	if not _ensure_ball_contact() or not _dribble.in_possession:
		return
	var tp: Node = get_node_or_null("ThroughPass")
	if tp:
		var all_players := get_tree().get_nodes_in_group("players")
		if tp.find_and_execute(all_players):
			return
	var action_dir := _get_action_direction()
	var pick := _pick_pass_target(action_dir)
	var target: Node = pick.get("target")
	if target != null:
		var lead: Vector3 = _lead_pass_position(target as CharacterBody3D)
		_notify_pass_switch(target, lead, true)
		_kick.ground_pass_to(lead, 0.86, target, false, true)
		return
	var raw_dir: Vector3 = pick.dir
	if raw_dir.length_squared() < 0.01:
		raw_dir = action_dir
	_kick.ground_pass(raw_dir.normalized(), 0.86)

func _perform_defensive_tackle() -> void:
	var tackler: Node = self
	var mm := _get_match_manager()
	if mm and mm.has_method("request_defensive_switch"):
		tackler = mm.request_defensive_switch()
	if tackler and tackler.has_method("_on_tackle"):
		tackler._on_tackle()

func _on_tackle() -> void:
	if _dribble.in_possession:
		return
	# Face tackle / slide direction before engaging.
	var tackle_dir := _get_action_direction()
	_snap_facing_toward(tackle_dir)
	var nearest: CharacterBody3D = null
	var search_dist: float = 3.5 if _coyote_timer > 0.0 else 3.0
	var best_d: float = search_dist
	for body in get_tree().get_nodes_in_group("players"):
		if body == self or body.team_id == team_id:
			continue
		var d: float = global_position.distance_to(body.global_position)
		if d < best_d:
			best_d = d
			nearest = body
	var ball_dist: float = 999.0
	if _dribble.ball_physics != null:
		ball_dist = global_position.distance_to(_dribble.ball_physics.global_position)
	var slide_priority: bool = is_sprinting or get_speed() > 4.2 or (nearest != null and best_d > ball_dist + 0.4)
	if slide_priority and _tackle.has_method("start_slide_tackle"):
		_tackle.start_slide_tackle()
		_coyote_timer = 0.0
		return
	if nearest:
		_tackle.try_standing_tackle(nearest)
		_coyote_timer = 0.0
	else:
		_tackle.start_slide_tackle()
		_coyote_timer = COYOTE_TACKLE_TIME

func _get_match_manager() -> Node:
	var nodes := get_tree().get_nodes_in_group("match_manager")
	if nodes.size() > 0:
		return nodes[0]
	return null

func _notify_pass_switch(target: Node, lead_pos: Vector3 = Vector3.ZERO, is_through: bool = false) -> void:
	var mm := _get_match_manager()
	if mm and mm.has_method("schedule_pass_switch"):
		mm.schedule_pass_switch(target)
	if mm and mm.has_method("assign_pass_play"):
		mm.assign_pass_play(self, target, lead_pos, is_through)

func _get_pass_run_direction() -> Vector3:
	if not has_meta("pass_run_target"):
		return Vector3.ZERO
	var mode: String = str(get_meta("pass_run_mode", ""))
	# Regular passes go to feet — don't pull the receiver into space.
	if mode == "feet" or mode == "receive":
		return Vector3.ZERO
	if Time.get_ticks_msec() * 0.001 > float(get_meta("pass_run_expires", 0.0)):
		PassPlayCoordinator.clear_pass_run(self)
		return Vector3.ZERO
	if _dribble != null and _dribble.in_possession:
		PassPlayCoordinator.clear_pass_run(self)
		return Vector3.ZERO
	var target: Vector3 = get_meta("pass_run_target") as Vector3
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length_squared() < 0.12:
		return Vector3.ZERO
	return to.normalized()

func _get_aim_assisted_dir(raw_dir: Vector3) -> Vector3:
	if _dribble == null or not _dribble.in_possession:
		return raw_dir
	var team_goal := PitchConstants.attack_goal_vec(team_id)
	var dist_to_goal := global_position.distance_to(team_goal)
	if dist_to_goal > AIM_ASSIST_MAX_DIST:
		return raw_dir
	var to_goal := (team_goal - global_position)
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.01:
		return raw_dir
	to_goal = to_goal.normalized()
	var assist := lerpf(0.0, AIM_ASSIST_STRENGTH, 1.0 - (dist_to_goal / AIM_ASSIST_MAX_DIST))
	var out := (raw_dir + to_goal * assist).normalized()
	# Close range: never let assist flip a run-at-goal shot backward.
	if dist_to_goal < 10.0 and raw_dir.dot(to_goal) > 0.45 and out.dot(to_goal) < raw_dir.dot(to_goal):
		out = (raw_dir * 0.82 + to_goal * 0.18).normalized()
	return out

func _is_busy() -> bool:
	if _tackle != null and (_tackle.is_sliding or _tackle.is_stumbling):
		return true
	if _skills != null and _skills.is_busy():
		return true
	return false

func _buffer_action(action: StringName) -> void:
	_buffered_action = action
	_buffer_timer = BUFFER_WINDOW

func _process_buffer(delta: float) -> void:
	if _buffer_timer > 0.0:
		_buffer_timer -= delta
		if _buffer_timer <= 0.0:
			_buffered_action = &""

func _try_execute_buffered_action() -> void:
	if _buffered_action == &"":
		return
	if _is_busy():
		return
		
	var action := _buffered_action
	_buffered_action = &""
	_buffer_timer = 0.0
	
	match action:
		&"shoot":
			if _try_claim_ball_for_action():
				var dir := _get_shot_direction()
				var buf_charge := clampf(_charge_timer / 0.8, 0.38, 1.0) if _charge_timer > 0.0 else 0.42
				PossessionManager.force_release()
				_kick.power_shot(dir, buf_charge)
				_charge_timer = 0.0
		&"pass":
			_on_pass_or_press()
		&"through_pass":
			_on_through_pass()
		&"tackle":
			_perform_defensive_tackle()
