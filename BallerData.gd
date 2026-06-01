class_name BallerData
extends Resource

# ============================================================
#  BallerData.gd — STREET 3 ELITE  (Phase 1)
#
#  The player-card resource.  Stores identity, position, base
#  stats, equipped skill moves, and card metadata.
#
#  Maps to the original binary's baller-card / Growth system:
#    Growth_ReqBallerCardE, Growth_ReqAllPropDataE,
#    Growth_ReqAddSkillE, Footballer_Wear, Footballer_buy.
# ============================================================

# ── Identity ──────────────────────────────────────────────────
@export_group("Identity")
@export var baller_name: String = "Unknown"
@export var baller_id:   int    = 0          ## Unique card ID (maps to server baller_id)

# ── Position ──────────────────────────────────────────────────
enum Position { STRIKER, MIDFIELDER, DEFENDER, GOALKEEPER }

@export_group("Position")
@export var position: Position = Position.MIDFIELDER

## Returns the role string expected by AIController.
func get_role() -> String:
	match position:
		Position.STRIKER:    return "striker"
		Position.MIDFIELDER: return "midfielder"
		Position.DEFENDER:   return "defender"
		Position.GOALKEEPER: return "goalkeeper"
		_:                   return "midfielder"

# ── Stats ─────────────────────────────────────────────────────
@export_group("Stats")
@export var base_stats: PlayerStats = null   ## Base (un-boosted) stat block

# ── Equipped Skill Moves ──────────────────────────────────────
## Mirrors SkillMove enum in SkillMoves.gd.
## Up to 2 equipped at once (street football rule).
enum SkillSlot { SLOT_A = 0, SLOT_B = 1 }

const MAX_SKILL_SLOTS := 2

# 0 = NONE, matches SkillMoves.SkillMove.NONE
@export_group("Skill Moves")
@export var skill_slot_a: int = 0  ## SkillMove enum value for slot A
@export var skill_slot_b: int = 0  ## SkillMove enum value for slot B

## Returns both equipped skills as an array (ignores NONE slots).
func get_equipped_skills() -> Array[int]:
	var out: Array[int] = []
	if skill_slot_a != 0:
		out.append(skill_slot_a)
	if skill_slot_b != 0:
		out.append(skill_slot_b)
	return out

## Returns true if this baller has the given skill move equipped.
func has_skill(skill_move: int) -> bool:
	return skill_slot_a == skill_move or skill_slot_b == skill_move

## Equip a skill move into the next available slot.  Returns true
## if equipped, false if both slots already used.
func equip_skill(skill_move: int) -> bool:
	if skill_slot_a == 0:
		skill_slot_a = skill_move
		return true
	if skill_slot_b == 0:
		skill_slot_b = skill_move
		return true
	return false

## Unequip a skill move from whichever slot holds it.
func unequip_skill(skill_move: int) -> void:
	if skill_slot_a == skill_move:
		skill_slot_a = 0
	elif skill_slot_b == skill_move:
		skill_slot_b = 0

# ── Card Metadata ─────────────────────────────────────────────
@export_group("Card")
@export var card_level:    int   = 1    ## Upgrade level (1–max)
@export var card_stars:    int   = 3    ## Star rating (1–5)
@export var is_unlocked:   bool  = false
@export var skin_id:       int   = 0    ## Footballer_Wear index

@export_group("Appearance")
@export var height_scale: float = 1.0
@export var skin_tone: Color = Color(0.90, 0.78, 0.62, 1.0)

# ── Factory helpers ───────────────────────────────────────────

## Create a BallerData with default 70-rated stats for quick testing.
static func make_default(name: String, pos: Position) -> BallerData:
	var bd := BallerData.new()
	bd.baller_name = name
	bd.position    = pos
	bd.base_stats  = PlayerStats.new()
	bd.is_unlocked = true
	return bd

## Create a goalkeeper with boosted GK stats.
static func make_goalkeeper(name: String) -> BallerData:
	var bd := make_default(name, Position.GOALKEEPER)
	bd.base_stats.gk_rating = 75
	bd.base_stats.goalie    = 75
	# Outfield stats intentionally reduced for GK
	bd.base_stats.shooting        = 40
	bd.base_stats.shooting_power  = 40
	bd.base_stats.dribbling       = 45
	return bd

## Apply to a PlayerController node — sets all derived properties.
func apply_to_player(player: CharacterBody3D) -> void:
	if base_stats == null:
		return
	# Expose the stats resource directly
	if player.has_method("set_baller_stats"):
		player.set_baller_stats(base_stats)
	# Fallback: write legacy scalar if node doesn't support full stats yet
	elif "player_rating" in player:
		player.player_rating = base_stats.get_overall_rating()
	if is_instance_valid(player):
		player.scale.y = maxf(0.85, minf(height_scale, 1.25))
		var visuals := player.get_node_or_null("PlayerVisuals")
		if visuals and visuals.has_method("set_skin_tone"):
			visuals.set_skin_tone(skin_tone)
