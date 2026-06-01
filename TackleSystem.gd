extends Node

# ============================================================
#  TackleSystem.gd — standing + overpowered slide tackles
# ============================================================

const TACKLE_COOLDOWN   := 0.65
const STUMBLE_WIN       := 0.45
const STUMBLE_LOSE      := 0.55
const SLIDE_SPEED       := 11.5
const SLIDE_DECEL_TIME  := 0.52
const SLIDE_BUMP_RADIUS := 1.05
const FOUL_THRESHOLD    := 0.12
const WIN_MARGIN        := 0.12
const LOSE_MARGIN       := 0.18

const PRESSURE_RING_NEAR := 1.5
const PRESSURE_RING_MED  := 2.5

@export var player: CharacterBody3D
@export var ball_physics: Node
@export var tackling_stat := 0.5
@export var control_stat  := 0.5

signal tackle_success
signal tackle_foul

var _cooldown_timer := 0.0
var is_sliding      := false
var is_stumbling    := false
var _slide_timer    := 0.0
var _stumble_timer  := 0.0
var _slide_direction := Vector3.ZERO

func _physics_process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
	if is_sliding:
		_update_slide(delta)
	if is_stumbling:
		_update_stumble(delta)

func try_standing_tackle(target: CharacterBody3D) -> void:
	if ball_physics == null or player == null:
		return
	if _cooldown_timer > 0.0 or is_sliding or is_stumbling:
		return
	_cooldown_timer = TACKLE_COOLDOWN
	MatchEventBus.emit_tackle(player, target, false)
	var att: float = tackling_stat + randf_range(-0.1, 0.1)
	var ts_node := target.get_node_or_null("TackleSystem")
	var def_base: float = ts_node.control_stat if ts_node != null else 0.5
	var def: float = def_base + randf_range(-0.1, 0.1)
	if att > def + WIN_MARGIN:
		PossessionManager.force_release()
		var knock: Vector3 = _player_forward() * 5.5 + Vector3(0.0, 1.2, 0.0)
		_knock_ball(knock, 1.05)
		SoundManager.tackle_at(player.global_position)
		tackle_success.emit()
		MatchEventBus.emit_tackle_won(player, target)
		Input.vibrate_handheld(50)
		_stumble_opponent(target, STUMBLE_WIN)
		ScreenShake.medium()
		var td: Node = get_node_or_null("/root/TimeDilation")
		if td and td.has_method("_dilate"):
			td._dilate(0.90, 0.08)
	elif def > att + LOSE_MARGIN:
		MatchEventBus.tackle_failed.emit(player.get_instance_id() if player else -1)
		_start_stumble(STUMBLE_LOSE)
	else:
		PossessionManager.force_release()
		var impulse := _player_forward() * randf_range(2.5, 4.0) + Vector3(0.0, 0.6, 0.0)
		_knock_ball(impulse, 0.9)

func start_slide_tackle() -> void:
	if _cooldown_timer > 0.0 or is_sliding or is_stumbling:
		return
	if PossessionManager.has_ball(player):
		return
	MatchEventBus.emit_tackle(player, null, true)
	MatchEventBus.tackle_attempted.emit(player.get_instance_id() if player else -1, -1, true)
	is_sliding = true
	_slide_timer = 0.0
	_slide_direction = _player_forward()
	_slide_direction.y = 0.0
	_slide_direction = _slide_direction.normalized()
	player.velocity = _slide_direction * SLIDE_SPEED
	_cooldown_timer = 1.0
	ScreenShake.light()

func _update_slide(delta: float) -> void:
	_slide_timer += delta
	var progress := clampf(_slide_timer / SLIDE_DECEL_TIME, 0.0, 1.0)
	var spd := lerpf(SLIDE_SPEED, 2.0, progress)
	player.velocity.x = _slide_direction.x * spd
	player.velocity.z = _slide_direction.z * spd
	_check_slide_hits()
	if progress >= 1.0:
		is_sliding = false
		_start_stumble(0.35)

func _check_slide_hits() -> void:
	if ball_physics == null or player == null:
		return

	var ball_pos: Vector3 = ball_physics.global_position
	if ball_physics.has_method("get") and ball_physics.get("ball_position"):
		ball_pos = ball_physics.ball_position as Vector3
	var ball_dist: float = player.global_position.distance_to(ball_pos)
	if ball_dist < 1.15:
		var foul: bool = _slide_timer >= FOUL_THRESHOLD and _slide_timer < FOUL_THRESHOLD + 0.08
		if foul:
			tackle_foul.emit()
			MatchEventBus.tackle_invalid.emit(player.get_instance_id() if player else -1)
		else:
			PossessionManager.force_release()
			_knock_ball(_slide_direction * 10.0 + Vector3(0.0, 2.5, 0.0), 1.15)
			tackle_success.emit()
			MatchEventBus.tackle_won.emit(player.get_instance_id() if player else -1, -1)
			Input.vibrate_handheld(60)
			ScreenShake.medium()
			var td: Node = get_node_or_null("/root/TimeDilation")
			if td:
				td.slow(0.85, 0.12)
		is_sliding = false
		return

	for body in player.get_tree().get_nodes_in_group("players"):
		if body == player or body.get("team_id") == player.team_id:
			continue
		var opp: CharacterBody3D = body as CharacterBody3D
		if opp == null:
			continue
		var d: float = player.global_position.distance_to(opp.global_position)
		if d > SLIDE_BUMP_RADIUS:
			continue
		var sep: Vector3 = (opp.global_position - player.global_position)
		sep.y = 0.0
		if sep.length_squared() < 0.01:
			sep = _slide_direction
		sep = sep.normalized()
		opp.velocity += sep * SLIDE_SPEED * 0.85 + Vector3(0.0, 1.5, 0.0)
		player.velocity += sep * 2.0
		_stumble_opponent(opp, 0.55)
		if PossessionManager.get_possessor() == opp:
			PossessionManager.force_release()
			_knock_ball(_slide_direction * 8.0 + Vector3.UP * 2.0, 1.0)
			tackle_success.emit()
			MatchEventBus.tackle_won.emit(player.get_instance_id() if player else -1, opp.get_instance_id())
			is_sliding = false
			ScreenShake.medium()
			return

func _knock_ball(impulse: Vector3, scale: float) -> void:
	if ball_physics == null:
		return
	ball_physics.wake()
	if ball_physics.has_method("apply_kick_impulse"):
		ball_physics.apply_kick_impulse(impulse, Vector3(randf_range(-2.0, 2.0), 0.0, 0.0), scale)
	else:
		ball_physics.apply_impulse(impulse * scale, Vector3.ZERO)

func _player_forward() -> Vector3:
	if player != null and player.has_method("get_facing_forward"):
		return player.get_facing_forward()
	var f: Vector3 = -player.transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)

func _stumble_opponent(target: CharacterBody3D, duration: float) -> void:
	var ts := target.get_node_or_null("TackleSystem")
	if ts:
		ts._start_stumble(duration)

func _start_stumble(duration: float) -> void:
	is_stumbling = true
	_stumble_timer = duration

func _update_stumble(delta: float) -> void:
	_stumble_timer -= delta
	if _stumble_timer <= 0.0:
		is_stumbling = false
