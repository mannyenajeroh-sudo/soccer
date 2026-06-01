extends Node3D

# ============================================================
#  MatchManager.gd — STREET 3 ELITE
#  Spawning, wiring, kickoff, goal detection, momentum.
#  KEY FIXES:
#   - AI players get move_and_slide() called inside AIController._seek()
#   - ball_physics wired correctly in all child nodes
#   - _ai_kickoff_pass waits for PLAY phase before acting
#   - GoalCelebration optional (graceful null check)
#   - AdMob cooldown and near-miss detection fixed
# ============================================================

const AIControllerScript    := preload("res://scripts/AIController.gd")
const ThroughPassScript     := preload("res://scripts/ThroughPass.gd")
const PlayerNameplateScript := preload("res://scripts/PlayerNameplate.gd")
const PitchLineRendererScript := preload("res://scripts/PitchLineRenderer.gd")
const SetPiecesScript       := preload("res://scripts/SetPieces.gd")
const GoalDetectorScript    := preload("res://scripts/GoalDetector.gd")
const TrainingHUDScript     := preload("res://scripts/TrainingHUD.gd")
const SquadControlScript    := preload("res://scripts/SquadControl.gd")
const PassPlayCoordinatorScript := preload("res://scripts/PassPlayCoordinator.gd")

@export var player_scene: PackedScene
@export var ball_physics: BallPhysics
@export var camera_rig: Node3D
@export var _hud: CanvasLayer

var players: Array[Node] = []
var human_player: Node = null
var human_squad: Array = []
var squad_control: Node = null
var pass_play: Node = null
var set_pieces: Node = null
var _goal_cooldown := 0.0

var _momentum := [50.0, 50.0]
const MOMENTUM_PASS_BONUS   := 8.0
const MOMENTUM_TACKLE_BONUS := 18.0
const MOMENTUM_GOAL_BONUS   := 30.0
const MOMENTUM_MISS_PENALTY := 5.0
const MOMENTUM_DECAY        := 0.02

var _near_miss_cooldown := 0.0
var _last_ad_timestamp  := 0.0
const AD_COOLDOWN := 180.0

var _goal_detector: Node = null
var _training_hud: CanvasLayer = null
var _training_slot := 0

# Triangle formation scaled to pitch — works correctly at any PLAY_HALF_X width
# [striker near center, midfielder flanked, defender back]
const TEAM_SPAWN := [
	[Vector3(0.0, 0.1, -2.0), Vector3(-3.5, 0.1, -4.0), Vector3(0.0, 0.1, -7.0)],
	[Vector3(0.0, 0.1,  2.0), Vector3( 3.5, 0.1,  4.0), Vector3(0.0, 0.1,  7.0)],
]

func _ready() -> void:
	add_to_group("match_manager")
	if ball_physics == null or player_scene == null:
		push_error("MatchManager: assign ball_physics and player_scene in MatchScene.")
		return
	_apply_optional_pitch_texture()

	# Procedural pitch lines
	var line_renderer := MeshInstance3D.new()
	line_renderer.set_script(PitchLineRendererScript)
	add_child(line_renderer)

	# Touch controls (human mode only)
	if not GameState.is_ai_vs_ai():
		var adv: Script = load("res://scripts/AdvancedTouchControls.gd") as Script
		if adv:
			var atc := CanvasLayer.new()
			atc.set_script(adv)
			add_child(atc)
		else:
			var touch_scene: PackedScene = load("res://scenes/TouchControls.tscn") as PackedScene
			if touch_scene:
				add_child(touch_scene.instantiate())

	set_pieces = SetPiecesScript.new()
	set_pieces.ball_physics = ball_physics
	add_child(set_pieces)
	set_pieces.add_to_group("set_pieces")

	_spawn_players()
	GameplayAI.register_players(players)
	# Phase 6: register players with stat tracker
	for _p in players:
		MatchStatsTracker.register_player(_p, _p.team_id)

	# World Cup Expansion: apply kit colours from TeamDatabase
	var home_id := GameState.home_team_id
	var away_id := GameState.away_team_id
	if home_id != "" and away_id != "":
		var home_data := TeamDatabase.get_team_by_id(home_id)
		var away_data := TeamDatabase.get_team_by_id(away_id)
		for _p in players:
			var kit_col: Color
			if _p.team_id == 0:
				kit_col = home_data.get("color_home", Color(0.15, 0.40, 1.0))
			else:
				kit_col = away_data.get("color_home", Color(1.0, 0.20, 0.15))
			_apply_kit_colour(_p, kit_col)
	GameplayAI.register_ball(ball_physics)
	PossessionManager.possession_changed.connect(func(_a, _b): GameplayAI.notify_possession_changed())
	GameplayRules.setup(ball_physics, players)

	# Pressure ring visuals
	var pr_script: Script = load("res://scripts/PressureRing.gd") as Script
	if pr_script:
		var pr := Node3D.new()
		pr.set_script(pr_script)
		add_child(pr)
		pr.ball_physics = ball_physics
		pr.all_players  = players

	_reset_ball_and_players_center()

	_goal_detector = GoalDetectorScript.new()
	_goal_detector.name = "GoalDetector"
	add_child(_goal_detector)
	_goal_detector.setup(ball_physics, self)

	pass_play = PassPlayCoordinatorScript.new()
	pass_play.name = "PassPlayCoordinator"
	add_child(pass_play)
	if pass_play.has_method("setup"):
		pass_play.setup(ball_physics)

	if GameState.is_training() and _goal_detector.has_method("set_enabled"):
		_goal_detector.set_enabled(false)

	if GameState.is_training():
		GameState.start_training()
		_setup_training_mode()
	else:
		GameState.start_match()

	MatchEventBus.reset()
	MatchStatsTracker.reset()
	TeamStyleMeter.reset()

	if GameState.is_ai_vs_ai():
		if _hud and _hud.has_method("set_spectator_mode"):
			_hud.set_spectator_mode(true)
		if camera_rig:
			camera_rig.set_ball(ball_physics)
		call_deferred("_kickoff_from_back", randi() % 2)
	elif not GameState.is_training():
		call_deferred("_kickoff_from_back", 0)

	GameState.match_ended.connect(_on_match_ended)
	ball_physics.bounced.connect(func(impact): SoundManager.bounce(impact, ball_physics.global_position))

	# Phase 6: Post-match screen
	var pms_script := load("res://scripts/PostMatchScreen.gd") as Script
	if pms_script:
		var pms := CanvasLayer.new()
		pms.set_script(pms_script)
		add_child(pms)

	var gc := get_node_or_null("GoalCelebration")
	if gc and gc.has_signal("celebration_finished"):
		gc.celebration_finished.connect(_on_goal_celebration_done)

func _apply_optional_pitch_texture() -> void:
	var tex_path := "res://assets/textures/pitch_background.png"
	if not ResourceLoader.exists(tex_path):
		return
	var ground := get_node_or_null("Pitch/Ground") as MeshInstance3D
	if ground == null:
		return
	var mat := ground.get_active_material(0) as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	ground.set_surface_override_material(0, mat)

func _apply_kit_colour(player_node: Node, kit_col: Color) -> void:
	if player_node.has_method("set_kit_colour"):
		player_node.set_kit_colour(kit_col)
		return
	for child in player_node.get_children():
		if child.has_method("set_kit_colour"):
			child.set_kit_colour(kit_col)
			return

func _team_db_id(team: int) -> String:
	if team == 0:
		if GameState.home_team_id != "":
			return GameState.home_team_id
		return "ARG"
	if GameState.away_team_id != "":
		return GameState.away_team_id
	return "BRA"

func _spawn_players() -> void:
	if GameState.is_training():
		var p: Node = player_scene.instantiate()
		add_child(p)
		p.global_position = Vector3(0.0, 0.1, 1.5)
		p.set_meta("spawn_position", p.global_position)
		p.team_id = 0
		p.set_meta("slot_index", 0)
		p.add_to_group("players")
		var bp: BallPhysics = ball_physics
		var baller := BallerData.make_default("Freestyle", BallerData.Position.STRIKER)
		baller.apply_to_player(p)
		if "baller_data" in p:
			p.baller_data = baller
		var visuals := p.get_node_or_null("PlayerVisuals")
		if visuals:
			if visuals.has_method("set_player_name"):
				visuals.set_player_name("Freestyle")
			if visuals.has_method("set_show_name"):
				visuals.set_show_name(false)
			visuals.set("team_id", 0)
		var drib := p.get_node_or_null("DribbleSystem")
		var kick := p.get_node_or_null("KickSystem")
		var tackle := p.get_node_or_null("TackleSystem")
		var skills := p.get_node_or_null("SkillMoves")
		var aerial := p.get_node_or_null("AerialMechanics")
		var juggle := p.get_node_or_null("JuggleSystem")
		if drib and kick and tackle and skills and aerial:
			drib.set("player", p)
			drib.set("ball_physics", bp)
			kick.set("player", p)
			kick.set("ball_physics", bp)
			kick.set("dribble_system", drib)
			tackle.set("player", p)
			tackle.set("ball_physics", bp)
			skills.set("player", p)
			skills.set("ball_physics", bp)
			skills.set("dribble_system", drib)
			aerial.set("player", p)
			aerial.set("ball_physics", bp)
			aerial.set("goal_pos", PitchConstants.attack_goal_vec(0))
			_wire_juggle_system(juggle, p, bp, drib, aerial)
		p.set_meta("is_human", true)
		p.set_meta("is_ai", false)
		_wire_human_player(p, aerial)
		players.append(p)
		AIBlackboard.register_match(players, ball_physics)
		_color_teams()
		if is_instance_valid(ball_physics):
			VisualEffects.register_ball(ball_physics)
		return

	for team in 2:
		var db_id := _team_db_id(team)
		var squad_indices := PlayerDatabase.get_match_squad_indices(db_id)
		var slots: Array[int] = [0, 1, 2]
		if GameState.is_training() and team == 1:
			slots = [2]   # goalkeeper only
		for i in slots:
			var p: Node = player_scene.instantiate()
			add_child(p)
			p.global_position = TEAM_SPAWN[team][i]
			p.set_meta("spawn_position", TEAM_SPAWN[team][i])
			p.team_id = team
			p.set_meta("slot_index", i)
			p.add_to_group("players")

			var bp: BallPhysics = ball_physics

			var baller := PlayerDatabase.build_baller(squad_indices[i], i)
			baller.apply_to_player(p)
			if "baller_data" in p:
				p.baller_data = baller
			var visuals := p.get_node_or_null("PlayerVisuals")
			if visuals:
				if visuals.has_method("set_player_name"):
					visuals.set_player_name(baller.baller_name)
				if visuals.has_method("set_show_name"):
					visuals.set_show_name(true)
				visuals.set("team_id", team)

			var drib := p.get_node_or_null("DribbleSystem")
			var kick := p.get_node_or_null("KickSystem")
			var tackle := p.get_node_or_null("TackleSystem")
			var skills := p.get_node_or_null("SkillMoves")
			var aerial := p.get_node_or_null("AerialMechanics")
			var juggle := p.get_node_or_null("JuggleSystem")
			if drib == null or kick == null or tackle == null or skills == null or aerial == null:
				push_error("MatchManager: Player scene missing required child nodes.")
				continue

			drib.set("player", p)
			drib.set("ball_physics", bp)
			kick.set("player", p)
			kick.set("ball_physics", bp)
			kick.set("dribble_system", drib)
			tackle.set("player", p)
			tackle.set("ball_physics", bp)
			tackle.tackle_success.connect(_on_tackle_success.bind(team))
			tackle.tackle_foul.connect(_on_tackle_foul.bind(team))
			skills.set("player", p)
			skills.set("ball_physics", bp)
			skills.set("dribble_system", drib)
			aerial.set("player", p)
			aerial.set("ball_physics", bp)
			aerial.set("goal_pos", PitchConstants.attack_goal_vec(team))
			_wire_juggle_system(juggle, p, bp, drib, aerial)

			# ThroughPass (dynamic child)
			var tp := ThroughPassScript.new()
			tp.set("ball_physics", bp)
			tp.set("kicker", p)
			tp.set("team_id", team)
			p.add_child(tp)

			# Nameplate
			var np := Node3D.new()
			np.set_script(PlayerNameplateScript)
			np.team_id = team
			np.player_number = i + 1
			p.add_child(np)

			# Meta flags
			var ai_vs_ai := GameState.is_ai_vs_ai()
			p.set_meta("is_human", false)
			p.set_meta("is_ai", true)

			if GameState.is_training() and team == 0:
				var is_active: bool = (i == _training_slot)
				p.set_meta("is_human", is_active)
				p.set_meta("is_ai", not is_active)
				if is_active:
					_wire_human_player(p, aerial)
				else:
					_attach_ai_controller(p, team, i, false)
					var ai_node := p.get_child(p.get_child_count() - 1)
					if ai_node and "aggression" in ai_node:
						ai_node.aggression = 0.15
						ai_node.is_chaser = false
			elif not ai_vs_ai and team == 0 and i == 0:
				p.set_meta("is_human", true)
				p.set_meta("is_ai", false)
				_wire_human_player(p, aerial)
			else:
				if ai_vs_ai:
					# Showcase mode: elite-rated players (Phase 1)
					var elite_stats := PlayerStats.new()
					elite_stats.agility           = 90
					elite_stats.balance           = 88
					elite_stats.strong            = 85
					elite_stats.stamina_max       = 88
					elite_stats.responding        = 90
					elite_stats.control_ball      = 90
					elite_stats.dribbling         = 90
					elite_stats.dribble_speed     = 88
					elite_stats.tack_break        = 80
					elite_stats.rob_slip_break    = 80
					elite_stats.floor_pass        = 88
					elite_stats.high_pass         = 85
					elite_stats.through_ball      = 85
					elite_stats.shooting          = 88
					elite_stats.shooting_power    = 88
					elite_stats.shooting_precision= 87
					elite_stats.head_ball         = 82
					elite_stats.bounce            = 82
					elite_stats.man_to_man        = 85
					elite_stats.intercept         = 85
					if p.has_method("set_baller_stats"):
						p.set_baller_stats(elite_stats)
					else:
						p.player_rating = 0.95
					# Showcase: equip full skill set based on slot
					var elite_baller := BallerData.make_default("Elite %d-%d" % [team, i + 1],
						[BallerData.Position.STRIKER, BallerData.Position.MIDFIELDER, BallerData.Position.DEFENDER][i])
					elite_baller.base_stats = elite_stats
					match i:
						0:
							elite_baller.skill_slot_a = SkillMoves.SkillMove.RAINBOW_OVER
							elite_baller.skill_slot_b = SkillMoves.SkillMove.ALL_OUT_SHOOTING
						1:
							elite_baller.skill_slot_a = SkillMoves.SkillMove.MARSEILLE_TURN
							elite_baller.skill_slot_b = SkillMoves.SkillMove.CROQUETTE
						2:
							elite_baller.skill_slot_a = SkillMoves.SkillMove.OX_TAIL
							elite_baller.skill_slot_b = SkillMoves.SkillMove.VIRTUAL_PRO_BALL
					if "baller_data" in p:
						p.baller_data = elite_baller
				_attach_ai_controller(p, team, i, ai_vs_ai)

			players.append(p)

	_wire_ai_teammates()
	AIBlackboard.register_match(players, ball_physics)
	_color_teams()
	if is_instance_valid(ball_physics):
		VisualEffects.register_ball(ball_physics)
	_setup_squad_control()

func _setup_squad_control() -> void:
	if GameState.is_training() or GameState.is_ai_vs_ai():
		return
	human_squad.clear()
	for p in players:
		if p.team_id == 0:
			human_squad.append(p)
	if human_squad.is_empty():
		return
	if squad_control != null and is_instance_valid(squad_control):
		squad_control.queue_free()
	squad_control = SquadControlScript.new()
	squad_control.name = "SquadControl"
	add_child(squad_control)
	squad_control.setup(self, human_squad, 0)
	if human_player == null and not human_squad.is_empty():
		switch_control_to(human_squad[0])

func schedule_pass_switch(target: Node) -> void:
	if squad_control and squad_control.has_method("schedule_pass_switch"):
		squad_control.schedule_pass_switch(target)

func assign_pass_play(passer: Node, receiver: Node, lead_pos: Vector3 = Vector3.ZERO, is_through: bool = false) -> void:
	if pass_play and pass_play.has_method("assign_pass"):
		pass_play.assign_pass(passer, receiver, lead_pos, is_through)

func request_defensive_switch() -> Node:
	if squad_control and squad_control.has_method("request_defensive_switch"):
		return squad_control.request_defensive_switch()
	return human_player

func switch_control_to(p: Node) -> void:
	if GameState.is_training() or GameState.is_ai_vs_ai():
		return
	if not is_instance_valid(p) or p == human_player:
		return
	if p.team_id != 0:
		return
	var aerial: Node = p.get_node_or_null("AerialMechanics")
	var old := human_player
	if old != null and is_instance_valid(old) and old != p:
		old.set_meta("is_human", false)
		old.set_meta("is_ai", true)
		_ensure_ai_controller(old)
	p.set_meta("is_human", true)
	p.set_meta("is_ai", false)
	_strip_ai_controller(p)
	_wire_human_player(p, aerial)

func _strip_ai_controller(p: Node) -> void:
	for child in p.get_children():
		if child.get_script() == AIControllerScript:
			child.queue_free()

func _ensure_ai_controller(p: Node) -> void:
	for child in p.get_children():
		if child.get_script() == AIControllerScript:
			return
	var slot: int = int(p.get_meta("slot_index", 1))
	_attach_ai_controller(p, int(p.get("team_id")), slot, false)

func _wire_juggle_system(juggle: Node, p: Node, bp: BallPhysics, drib: Node, aerial: Node) -> void:
	if juggle == null:
		return
	juggle.set("player", p)
	juggle.set("ball_physics", bp)
	juggle.set("dribble_system", drib)
	juggle.set("aerial", aerial)

func _wire_human_player(p: Node, aerial: Node) -> void:
	human_player = p
	if camera_rig:
		camera_rig.set_ball(ball_physics)
		if camera_rig.has_method("set_human_team"):
			camera_rig.set_human_team(int(p.team_id))
		p.camera = camera_rig.get_camera()
	if _hud:
		if p.has_signal("charge_updated") and not p.charge_updated.is_connected(_hud.set_charge):
			p.charge_updated.connect(_hud.set_charge)
		var juggle := p.get_node_or_null("JuggleSystem")
		if juggle != null and juggle.has_signal("juggle_updated"):
			if not juggle.juggle_updated.is_connected(_hud.set_juggle_count):
				juggle.juggle_updated.connect(_hud.set_juggle_count)
		elif aerial != null and aerial.has_signal("juggle_updated"):
			if not aerial.juggle_updated.is_connected(_hud.set_juggle_count):
				aerial.juggle_updated.connect(_hud.set_juggle_count)
		if _hud.has_method("connect_player_stamina"):
			_hud.connect_player_stamina(p)
	for ui_child in get_children():
		if ui_child is CanvasLayer and ui_child.has_method("set_charge"):
			if p.has_signal("charge_updated") and not p.charge_updated.is_connected(ui_child.set_charge):
				p.charge_updated.connect(ui_child.set_charge)

func _setup_training_mode() -> void:
	if _hud:
		_hud.visible = false
	_training_hud = TrainingHUDScript.new()
	_training_hud.name = "TrainingHUD"
	add_child(_training_hud)
	_training_hud.reset_ball_requested.connect(_training_reset_ball)
	PossessionManager.possession_changed.connect(_on_training_possession)
	MatchEventBus.pass_attempted.connect(_on_training_pass)
	_place_ball_for_training_shot()

func _spawn_shooting_targets() -> void:
	var goal_z := PitchConstants.GOAL_Z_TEAM1_DEFENDS
	for off in [Vector3(-1.4, 0.9, 0), Vector3(0, 1.3, 0), Vector3(1.4, 0.7, 0)]:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.9, 0.05)
		m.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.85, 0.1, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.position = Vector3(off.x, off.y, goal_z - 0.35)
		m.name = "ShootingTarget"
		add_child(m)

func _place_ball_for_training_shot() -> void:
	PossessionManager.force_release()
	ball_physics.wake()
	ball_physics.ball_position = Vector3(0, 0.11, 4.0)
	ball_physics.velocity = Vector3.ZERO
	ball_physics.angular_velocity = Vector3.ZERO
	ball_physics.global_position = ball_physics.ball_position
	if human_player:
		# Keep player inside immediate action range so pass/shot works instantly.
		human_player.global_position = Vector3(0, 0.1, 2.55)

func _training_reset_ball() -> void:
	_place_ball_for_training_shot()
	if _goal_detector:
		_goal_detector.set_enabled(false)

func _on_training_possession(new_p: Node, _old: Node) -> void:
	if not GameState.is_training() or _training_hud == null:
		return
	if new_p != null and new_p.get_meta("is_human", false):
		_training_hud.register_touch()

func _on_training_pass(passer_id: int, _target_id: int, _ptype: int) -> void:
	if not GameState.is_training() or _training_hud == null or human_player == null:
		return
	if passer_id == human_player.get_instance_id():
		_training_hud.register_pass()

func _apply_training_control() -> void:
	if players.is_empty():
		return
	var p := players[0]
	if is_instance_valid(p):
		p.set_meta("is_human", true)
		p.set_meta("is_ai", false)
		human_player = p
		if camera_rig:
			if camera_rig.has_method("set_human_team"):
				camera_rig.set_human_team(int(p.team_id))
			p.camera = camera_rig.get_camera()
	return

func _input(event: InputEvent) -> void:
	if not GameState.is_training():
		return
	if event.is_action_pressed("reset_ball"):
		_training_reset_ball()

func _attach_ai_controller(p: Node, team: int, i: int, ai_vs_ai: bool) -> void:
	var ai := AIControllerScript.new()
	ai.player      = p
	ai.ball        = ball_physics
	ai.team_id     = team
	ai.role        = ["striker", "midfielder", "goalkeeper"][i]
	# 3v3: midfielder hunts loose balls; striker makes runs / presses high
	ai.is_chaser   = (i == 1)
	ai.showcase_mode = ai_vs_ai
	var diff: int  = int(GameState.get_meta("difficulty", 1))
	var delays     := [0.80, 0.45, 0.22]
	ai.reaction_delay = delays[clamp(diff, 0, 2)]
	# Full difficulty wiring: Easy=0, Medium=1, Hard=2
	# tackling_stat: how effective the AI tackle is
	# aggression: gates tackle range, sprint eagerness, and pass/shoot bias
	var tackling_stats := [0.30, 0.55, 0.80]
	var aggressions    := [0.25, 0.50, 0.75]
	ai.tackling_stat   = tackling_stats[clamp(diff, 0, 2)]
	ai.aggression      = aggressions[clamp(diff, 0, 2)]
	if ai_vs_ai:
		ai.reaction_delay = maxf(0.18, ai.reaction_delay * 0.52)
		ai.aggression = 0.65  # Showcase AI plays decisively
	p.add_child(ai)

## Kickoff from the back — ball near own goal, deepest outfielder plays out.
func _kickoff_from_back(kicking_team: int) -> void:
	await get_tree().process_frame
	if GameState.phase != GameState.Phase.PLAY:
		return

	var own_goal: Vector3 = PitchConstants.defend_goal_vec(kicking_team)
	var attack_goal: Vector3 = PitchConstants.attack_goal_vec(kicking_team)
	var to_center: Vector3 = attack_goal - own_goal
	to_center.y = 0.0
	if to_center.length_squared() < 0.01:
		to_center = Vector3(0.0, 0.0, signf(attack_goal.z - own_goal.z))
	to_center = to_center.normalized()

	# Ball just ahead of own goal line in the defensive third
	var ball_spot: Vector3 = own_goal + to_center * 3.2
	ball_spot.y = 0.11
	PossessionManager.force_release()
	ball_physics.wake()
	ball_physics.ball_position = ball_spot
	ball_physics.velocity = Vector3.ZERO
	ball_physics.angular_velocity = Vector3.ZERO
	ball_physics.global_position = ball_spot

	# Deepest outfielder (slot 1 midfielder) takes kickoff; GK stays on line
	var taker_idx: int = kicking_team * 3 + 1
	if taker_idx >= players.size():
		return
	var taker: Node = players[taker_idx]
	if not is_instance_valid(taker):
		return
	var taker_body: CharacterBody3D = taker as CharacterBody3D
	if taker_body:
		taker_body.global_position = ball_spot - to_center * 1.1
		taker_body.velocity = Vector3.ZERO
		if "horizontal_velocity" in taker_body:
			taker_body.horizontal_velocity = Vector3.ZERO

	var drib: Node = taker.get_node_or_null("DribbleSystem")
	if drib:
		drib.try_pickup(ball_spot)

	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree() or GameState.phase != GameState.Phase.PLAY:
		return

	var kick: Node = taker.get_node_or_null("KickSystem")
	if kick == null or not PossessionManager.has_ball(taker):
		return

	var receiver_idx: int = kicking_team * 3  # striker ahead
	var pass_target: Vector3 = ball_spot + to_center * 8.0
	if receiver_idx < players.size() and is_instance_valid(players[receiver_idx]):
		var recv: Node3D = players[receiver_idx] as Node3D
		if recv:
			pass_target = recv.global_position + to_center * 1.5
			pass_target.y = 0.11

	if kick.has_method("ground_pass_to"):
		kick.ground_pass_to(pass_target, 0.68)
	else:
		var dir: Vector3 = (pass_target - taker.global_position)
		dir.y = 0.0
		if dir.length_squared() > 0.01:
			kick.ground_pass(dir.normalized(), 0.68)

	AIBlackboard.start_opening_mark(12.0)
	if receiver_idx < players.size() and is_instance_valid(players[receiver_idx]):
		assign_pass_play(taker, players[receiver_idx], pass_target)

	SoundManager.kick(12.0, ball_spot)

func _wire_ai_teammates() -> void:
	for p in players:
		var mates: Array = []
		for other in players:
			if other.team_id == p.team_id:
				mates.append(other)
		for child in p.get_children():
			if child.has_method("set_teammates"):
				child.set_teammates(mates)
			if child.get_script() == AIControllerScript:
				child._teammates = mates

func _color_teams() -> void:
	for p in players:
		var mesh: MeshInstance3D = p.get_node_or_null("FacingPivot/MeshInstance3D")
		if mesh == null: continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.10, 1.0) if p.team_id == 0 else Color(1.0, 0.12, 0.12)
		mat.roughness = 0.7
		mat.metallic = 0.1
		mesh.material_override = mat

func _process(delta: float) -> void:
	if _goal_cooldown > 0.0:
		_goal_cooldown -= delta
	if _near_miss_cooldown > 0.0:
		_near_miss_cooldown -= delta
	_check_near_miss()
	_decay_momentum(delta)

func _check_goals() -> void:
	if GameState.phase != GameState.Phase.PLAY or _goal_cooldown > 0.0:
		return
	var team := PitchConstants.scoring_team_for_ball(ball_physics.ball_position)
	if team >= 0:
		register_goal(team, ball_physics.ball_position, ball_physics.velocity.length())

func _check_near_miss() -> void:
	if GameState.phase != GameState.Phase.PLAY:
		return
	if _near_miss_cooldown > 0.0:
		return
	var bp  := ball_physics.ball_position
	var vel := ball_physics.velocity
	if (absf(bp.x) < PitchConstants.GOAL_HALF_WIDTH + 0.4 and
		absf(bp.z) > PitchConstants.GOAL_LINE_SCORE_Z - 0.5 and
		absf(bp.z) < PitchConstants.GOAL_LINE_SCORE_Z + 1.0 and
		bp.y < PitchConstants.GOAL_MAX_HEIGHT + 0.4 and
		vel.length() > 8.0):
		SoundManager.near_miss()
		_near_miss_cooldown = 3.0
		if _training_hud:
			_training_hud.register_shot(true, vel.length())
		# Phase 6: emit shot_on_target for last shooter
		var prev := PossessionManager.get_possessor()
		if prev != null:
			var goal_pos := PitchConstants.attack_goal_vec(prev.team_id)
			var xg := GameplayAI.get_xg(bp, goal_pos)
			MatchEventBus.shot_on_target.emit(prev.get_instance_id(), xg)

func _is_own_goal_disallowed(scoring_team: int) -> bool:
	var touch_team := PossessionManager.get_last_touch_team()
	if touch_team < 0:
		var pending: Dictionary = GameState.get_meta("pending_shot", {})
		var pid: int = int(pending.get("player_id", -1))
		if pid >= 0:
			for p in players:
				if is_instance_valid(p) and p.get_instance_id() == pid:
					touch_team = int(p.team_id)
					break
		if touch_team < 0:
			var possessor := PossessionManager.get_possessor()
			if possessor != null and is_instance_valid(possessor):
				touch_team = int(possessor.team_id)
	if touch_team < 0:
		return false
	return touch_team == (1 - scoring_team)

func register_goal(scoring_team: int, ball_pos: Vector3 = Vector3.ZERO, shot_speed: float = 0.0) -> void:
	if GameState.is_training():
		return
	if _goal_cooldown > 0.0 or GameState.phase != GameState.Phase.PLAY:
		return
	_goal_cooldown = 2.5
	if _goal_detector:
		_goal_detector.set_enabled(false)

	var meta := _build_goal_meta(scoring_team, ball_pos, shot_speed)
	GameState.set_meta("last_goal", meta)
	PossessionManager.force_release()

	# Clear pass-run state before celebration — avoids AI/human meta crashes on concede.
	for p in players:
		if is_instance_valid(p):
			PassPlayCoordinator.clear_pass_run(p)

	# Defer goal sequence so physics frame finishes cleanly (prevents concede crashes).
	call_deferred("_finish_goal_sequence", scoring_team)

func _on_tackle_success(team: int) -> void:
	_add_momentum(team, MOMENTUM_TACKLE_BONUS)

func _on_tackle_foul(team: int) -> void:
	SoundManager.whistle()
	var foul_pos := ball_physics.ball_position
	if set_pieces:
		set_pieces.start_freekick(foul_pos, 1 - team)

func _decay_momentum(delta: float) -> void:
	for i in 2:
		_momentum[i] = lerpf(_momentum[i], 50.0, MOMENTUM_DECAY * delta)

func _add_momentum(team: int, amount: float) -> void:
	_momentum[team] = clampf(_momentum[team] + amount, 0.0, 100.0)

func get_momentum(team: int) -> float:
	return _momentum[team]

var _celebration_handled := false

func _finish_goal_sequence(scoring_team: int) -> void:
	if not is_inside_tree() or GameState.phase == GameState.Phase.FULLTIME:
		return
	if GameState.phase != GameState.Phase.PLAY:
		return

	GameState.goal_scored(scoring_team)
	var meta: Dictionary = GameState.get_meta("last_goal", {})
	MatchEventBus.emit_goal(scoring_team, null, bool(meta.get("own_goal", false)))
	_add_momentum(scoring_team, MOMENTUM_GOAL_BONUS)
	_add_momentum(1 - scoring_team, -MOMENTUM_GOAL_BONUS)

	# GoalCelebration handles VFX + pause; fallback if missing.
	var gc := get_node_or_null("GoalCelebration")
	if gc == null:
		call_deferred("_on_goal_celebration_done")

func _build_goal_meta(scoring_team: int, ball_pos: Vector3, shot_speed: float) -> Dictionary:
	var meta: Dictionary = {}
	var fallback_speed: float = 14.0
	if GameState.has_meta("pending_shot"):
		var pending = GameState.get_meta("pending_shot")
		if pending is Dictionary:
			meta = (pending as Dictionary).duplicate()
			fallback_speed = float(meta.get("speed", 14.0))
		GameState.remove_meta("pending_shot")
	meta["speed"] = shot_speed if shot_speed > 0.0 else fallback_speed
	meta["scoring_team"] = scoring_team
	meta["own_goal"] = _last_touch_team() == (1 - scoring_team)
	meta["scorer_name"] = _find_scorer_name(scoring_team)
	if meta["own_goal"]:
		meta["scorer_name"] = _find_last_touch_name(1 - scoring_team, int(meta.get("player_id", -1)))
	if meta.get("shot_type", "") == "":
		meta["shot_type"] = "normal"
	if shot_speed < 12.0:
		meta["shot_type"] = "weak"
	return meta

func _last_touch_team() -> int:
	var touch_team := PossessionManager.get_last_touch_team()
	if touch_team >= 0:
		return touch_team
	var pending: Dictionary = GameState.get_meta("pending_shot", {})
	var pid: int = int(pending.get("player_id", -1))
	if pid >= 0:
		for p in players:
			if is_instance_valid(p) and p.get_instance_id() == pid:
				return int(p.team_id)
	var possessor := PossessionManager.get_possessor()
	if possessor != null and is_instance_valid(possessor):
		return int(possessor.team_id)
	return -1

func _find_last_touch_name(team_id: int, player_id: int = -1) -> String:
	for p in players:
		if not is_instance_valid(p) or int(p.team_id) != team_id:
			continue
		if player_id >= 0 and p.get_instance_id() != player_id:
			continue
		if "baller_data" in p and p.baller_data:
			return p.baller_data.baller_name
		return "Player %d" % (team_id + 1)
	return "OWN GOAL"

func _find_scorer_name(scoring_team: int) -> String:
	var goal_z := PitchConstants.attack_goal_z(scoring_team)
	var best_dist := 10.0
	var name := "STREET STAR"
	for p in players:
		if not is_instance_valid(p) or p.team_id != scoring_team:
			continue
		var d := absf(p.global_position.z - goal_z)
		if d < best_dist:
			best_dist = d
			if "baller_data" in p and p.baller_data:
				name = p.baller_data.baller_name
			else:
				name = "Player %d" % (scoring_team + 1)
	return name

func _on_goal_celebration_done() -> void:
	if _celebration_handled:
		return
	_celebration_handled = true
	Engine.time_scale = 1.0
	if get_tree().paused:
		get_tree().paused = false
	for p in players:
		if is_instance_valid(p):
			PassPlayCoordinator.clear_pass_run(p)
	_reset_ball_and_players_center()
	SoundManager.whistle()
	GameState.resume_from_goal()
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	_celebration_handled = false
	_goal_cooldown = 0.0
	if _goal_detector:
		_goal_detector.set_enabled(true)
	var kick_team: int = 1 - GameState.last_scoring_team if GameState.last_scoring_team >= 0 else randi() % 2
	call_deferred("_kickoff_from_back", kick_team)

func _reset_ball_and_players_center() -> void:
	PossessionManager.force_release()
	ball_physics.wake()
	ball_physics.ball_position      = Vector3(0.0, 0.11, 0.0)
	ball_physics.velocity           = Vector3.ZERO
	ball_physics.angular_velocity   = Vector3.ZERO
	ball_physics.global_position    = ball_physics.ball_position
	for team in 2:
		for i in 3:
			var idx := team * 3 + i
			if idx < players.size() and is_instance_valid(players[idx]):
				var p: CharacterBody3D = players[idx] as CharacterBody3D
				if p:
					p.global_position    = TEAM_SPAWN[team][i]
					p.set_meta("spawn_position", TEAM_SPAWN[team][i])
					p.velocity           = Vector3.ZERO
					p.horizontal_velocity = Vector3.ZERO

func _on_match_ended(_winner: int) -> void:
	# PostMatchScreen handles navigation when phase == FULLTIME.
	MatchEventBus.match_over.emit(_winner)
