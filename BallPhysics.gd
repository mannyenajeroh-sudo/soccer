extends Node3D
class_name BallPhysics

const MASS        := 0.43
const RADIUS      := 0.11
const RHO         := 1.225
const CD          := 0.30
const CM          := 1.45
const E_BOUNCE    := 0.62
const MU_ROLL     := 0.018
const MU_K        := 0.60
const SPIN_DECAY  := 0.25
const GRAVITY     := 9.81

const AREA        := PI * RADIUS * RADIUS
const K_DRAG      := 0.5 * RHO * CD * AREA
const K_MAGNUS    := 0.5 * RHO * CM * AREA * RADIUS
const I_BALL      := 0.4 * MASS * RADIUS * RADIUS

const FIXED_DT    := 1.0 / 60.0
const MAX_SUBSTEPS := 4
const SLEEP_SPEED := 0.10
const SLEEP_TIME  := 0.5
const GROUND_Y    := RADIUS

# Surface friction zones (Section 2.1)
const MU_ROLL_CENTER  := MU_ROLL * 0.85   # Center circle — faster
const MU_ROLL_WINGS   := MU_ROLL * 1.08   # Edges are only slightly slower.
const CENTER_ZONE_R   := 4.0              # radius of center zone

var ball_position   := Vector3.ZERO
var velocity        := Vector3.ZERO
var angular_velocity := Vector3.ZERO
var on_ground       := false
var sleeping        := false

var _accumulator    := 0.0
var _prev_position  := Vector3.ZERO
var _curr_position  := Vector3.ZERO
var _sleep_timer    := 0.0
var _prev_vy        := 0.0

signal bounced(impact_speed: float)
signal rolled_to_stop
signal impact_applied(power: float, spin_mag: float)

func _ready() -> void:
	ball_position = global_position
	_curr_position = ball_position
	_prev_position = _curr_position

func _process(delta: float) -> void:
	if sleeping:
		return
	if GameState.phase == GameState.Phase.GOAL:
		return
	_accumulator += minf(delta, 0.10)
	var steps := 0
	while _accumulator >= FIXED_DT and steps < MAX_SUBSTEPS:
		_prev_position = _curr_position
		_physics_step(FIXED_DT)
		_curr_position = ball_position
		_accumulator -= FIXED_DT
		steps += 1
	if steps >= MAX_SUBSTEPS:
		_accumulator = 0.0
	var alpha := _accumulator / FIXED_DT
	global_position = _prev_position.lerp(_curr_position, alpha)

func _physics_step(dt: float) -> void:
	var spd := velocity.length()

	if spd > 0.05:
		var F_drag   := -K_DRAG * spd * velocity
		var F_magnus := Vector3.ZERO
		if angular_velocity.length_squared() > 0.09:
			var magnus: Vector3 = K_MAGNUS * angular_velocity.cross(velocity)
			# Extra bend for absurd street curlers
			if angular_velocity.length() > 4.0:
				magnus *= 1.0 + clampf((angular_velocity.length() - 4.0) / 12.0, 0.0, 0.85)
			F_magnus = magnus
		var F_grav   := Vector3(0.0, -GRAVITY * MASS, 0.0)
		velocity += (F_drag + F_magnus + F_grav) / MASS * dt
		if angular_velocity.length_squared() > 0.09:
			var decay := clampf(1.0 - SPIN_DECAY * (spd / 15.0) * dt, 0.0, 1.0)
			angular_velocity *= decay
		_apply_knuckleball(spd, dt)
	else:
		velocity.y -= GRAVITY * dt

	ball_position += velocity * dt
	_update_net_lock(dt)
	_resolve_arena_walls(dt)
	_resolve_ground(dt)
	_check_sleep(dt)

func _get_surface_mu() -> float:
	# Section 2.1: surface zone friction variation
	var flat_dist := Vector2(ball_position.x, ball_position.z).length()
	if flat_dist < CENTER_ZONE_R:
		return MU_ROLL_CENTER
	var half_x := PitchConstants.PLAY_HALF_X
	var half_z := PitchConstants.PLAY_HALF_Z
	var edge_factor := maxf(
		absf(ball_position.x) / half_x,
		absf(ball_position.z) / half_z
	)
	return lerpf(MU_ROLL, MU_ROLL_WINGS, clampf((edge_factor - 0.6) / 0.4, 0.0, 1.0))

func _resolve_arena_walls(dt: float) -> void:
	var hx := PitchConstants.PLAY_HALF_X
	var hz := PitchConstants.PLAY_HALF_Z
	var gw := PitchConstants.GOAL_HALF_WIDTH

	if absf(ball_position.x) > hx:
		ball_position.x = signf(ball_position.x) * hx
		velocity.x *= -E_BOUNCE
		bounced.emit(absf(velocity.x))

	# Freestyle training cage: ball bounces off every wall, including goal mouth.
	if GameState.is_training():
		if ball_position.z < -hz:
			ball_position.z = -hz
			velocity.z *= -E_BOUNCE
			bounced.emit(absf(velocity.z))
		elif ball_position.z > hz:
			ball_position.z = hz
			velocity.z *= -E_BOUNCE
			bounced.emit(absf(velocity.z))
		return

	# Inside a goal mouth past the line — let the ball travel into the net (no end-wall bounce).
	if PitchConstants.is_in_scoring_zone(ball_position) or absf(ball_position.z) > hz:
		if absf(ball_position.z) > hz and absf(ball_position.x) < PitchConstants.GOAL_HALF_WIDTH + 1.2:
			var back0 := PitchConstants.goal_back_wall_z(0)
			var back1 := PitchConstants.goal_back_wall_z(1)
			if ball_position.z < back0:
				ball_position.z = back0
				velocity *= 0.22
				velocity.z = absf(velocity.z) * 0.12
			elif ball_position.z > back1:
				ball_position.z = back1
				velocity *= 0.22
				velocity.z = -absf(velocity.z) * 0.12
			else:
				velocity *= clampf(1.0 - 0.35 * dt, 0.55, 1.0)

			# Soft side-net boundaries inside the recess
			var side_limit := PitchConstants.GOAL_HALF_WIDTH + 0.1
			if absf(ball_position.x) > side_limit:
				ball_position.x = signf(ball_position.x) * side_limit
				velocity.x *= -0.22
			return

	if ball_position.z < -hz:
		if absf(ball_position.x) > gw + PitchConstants.GOAL_MOUTH_MARGIN_X:
			ball_position.z = -hz
			velocity.z *= -E_BOUNCE
			bounced.emit(absf(velocity.z))
	elif ball_position.z > hz:
		if absf(ball_position.x) > gw + PitchConstants.GOAL_MOUTH_MARGIN_X:
			ball_position.z = hz
			velocity.z *= -E_BOUNCE
			bounced.emit(absf(velocity.z))

func _resolve_ground(dt: float) -> void:
	if ball_position.y > GROUND_Y:
		on_ground = false
		return

	if not on_ground:
		_prev_vy = velocity.y
		if velocity.y < -0.3:
			ball_position.y = GROUND_Y
			velocity.y = -E_BOUNCE * velocity.y
			var v_slip := velocity.x - angular_velocity.z * RADIUS
			var J_f    := minf(MU_K * MASS * absf(_prev_vy), 0.5 * MASS * absf(v_slip))
			velocity.x        -= (J_f / MASS) * signf(v_slip)
			angular_velocity.z += (J_f * RADIUS / I_BALL) * signf(v_slip)
			angular_velocity   *= 0.85
			var impact_spd := absf(_prev_vy)
			bounced.emit(impact_spd)
			if impact_spd > 3.5:
				impact_applied.emit(impact_spd, angular_velocity.length())
		else:
			ball_position.y = GROUND_Y
			velocity.y = 0.0
			on_ground = true
	else:
		ball_position.y = GROUND_Y
		velocity.y = 0.0
		var gspeed := Vector2(velocity.x, velocity.z).length()
		if gspeed > 0.15:
			var mu := _get_surface_mu()  # Surface-zone friction!
			var decel_total := (mu * GRAVITY + 0.0035 * gspeed * gspeed) * dt
			var hvel        := Vector2(velocity.x, velocity.z)
			var new_speed   := maxf(0.0, gspeed - decel_total)
			hvel = hvel.normalized() * new_speed
			velocity.x = hvel.x
			velocity.z = hvel.y
		else:
			velocity.x = 0.0
			velocity.z = 0.0

func _apply_knuckleball(spd: float, dt: float) -> void:
	if angular_velocity.length_squared() > 0.25 or spd < 18.0:
		return
	var t   := Time.get_ticks_msec() * 0.001
	var amp := clampf((spd - 18.0) / 10.0, 0.0, 1.0) * 0.25
	var F := Vector3(
		(sin(t * 2.5 * TAU) + sin(t * 3.7 * 0.3)) * 0.5,
		0.0,
		(cos(t * 2.1 * TAU) + cos(t * 4.1 * 0.25)) * 0.5
	) * amp
	velocity += F / MASS * dt

func _check_sleep(dt: float) -> void:
	if velocity.length() < SLEEP_SPEED:
		_sleep_timer += dt
		if _sleep_timer > SLEEP_TIME:
			sleeping = true
			velocity = Vector3.ZERO
			rolled_to_stop.emit()
	else:
		_sleep_timer = 0.0
		sleeping = false

func wake() -> void:
	sleeping = false
	_sleep_timer = 0.0

func apply_impulse(impulse: Vector3, spin: Vector3 = Vector3.ZERO) -> void:
	apply_kick_impulse(impulse, spin, 1.0)

## Street impact: sets velocity, spin, and notifies VFX/camera from strike power.
func apply_kick_impulse(impulse: Vector3, spin: Vector3 = Vector3.ZERO, impact_scale: float = 1.0) -> void:
	wake()
	var scaled: Vector3 = impulse * impact_scale
	velocity = scaled
	angular_velocity = spin
	var power: float = scaled.length()
	var spin_mag: float = spin.length()
	impact_applied.emit(power, spin_mag)
	if power > 6.0:
		bounced.emit(power)

func get_prev_vy() -> float:
	return _prev_vy

# ---- Net / goal-mouth integration ----------------------
signal entered_goal_net(impact_point: Vector3, velocity: Vector3)

var _in_net: bool = false
var _net_lock_timer: float = 0.0

func on_goal_net_collision(net_normal: Vector3, _impact_point: Vector3) -> void:
	# Called by NetDeformer — heavily absorb velocity so ball stays in net
	velocity = velocity.bounce(net_normal) * 0.35
	angular_velocity *= 0.6
	_in_net = true
	_net_lock_timer = 0.4   # brief period of soft physics

func _update_net_lock(dt: float) -> void:
	if not _in_net:
		return
	_net_lock_timer -= dt
	# Dampen while inside net
	velocity   *= clampf(1.0 - dt * 4.0, 0.0, 1.0)
	if _net_lock_timer <= 0.0:
		_in_net = false
