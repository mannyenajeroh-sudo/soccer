extends Node

# ============================================================
#  PossessionManager.gd — STREET 3 ELITE Autoload Singleton
#  Single source of truth for who has the ball.
#  KEY FIX: claim() now releases from previous holder's DribbleSystem
#  so there's never a state where two players think they have the ball.
# ============================================================

signal possession_changed(new_possessor, old_possessor)
signal ball_loose

var current_possessor: Node = null
var last_touch_team: int = -1
var _loose_timer: float     = 0.0
const LOOSE_MIN_TIME := 0.15    # hysteresis

func register_touch(team: int) -> void:
	if team >= 0 and team <= 1:
		last_touch_team = team

func get_last_touch_team() -> int:
	return last_touch_team

func claim(player: Node) -> void:
	if current_possessor == player:
		return
	var old := current_possessor
	# Force-release old holder's DribbleSystem so spring stops
	if old != null and is_instance_valid(old):
		var old_drib := old.get_node_or_null("DribbleSystem")
		if old_drib and old_drib.has_method("release_possession"):
			old_drib.in_possession = false   # direct flag clear — no re-emit
	current_possessor = player
	_loose_timer = 0.0
	if player != null and "team_id" in player:
		register_touch(int(player.team_id))
	possession_changed.emit(player, old)
	# Phase 4: event bus
	MatchEventBus.emit_possession_change(player)

func release(player: Node) -> void:
	if current_possessor != player:
		return
	current_possessor = null
	_loose_timer = 0.0
	ball_loose.emit()

func force_release() -> void:
	var old := current_possessor
	# Clear DribbleSystem on previous possessor
	if old != null and is_instance_valid(old):
		var old_drib := old.get_node_or_null("DribbleSystem")
		if old_drib:
			old_drib.in_possession = false
	current_possessor = null
	_loose_timer = 0.0
	if old:
		possession_changed.emit(null, old)
		ball_loose.emit()

func has_ball(player: Node) -> bool:
	return current_possessor == player

func is_loose() -> bool:
	return current_possessor == null and _loose_timer >= LOOSE_MIN_TIME

func get_possessor() -> Node:
	return current_possessor

func _process(delta: float) -> void:
	if current_possessor == null:
		_loose_timer += delta
	# Validate possessor is still alive
	if current_possessor != null and not is_instance_valid(current_possessor):
		force_release()
