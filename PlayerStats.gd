class_name PlayerStats
extends Resource

# ============================================================
#  PlayerStats.gd — STREET 3 ELITE  (Phase 1)
#
#  All 22 stat properties reverse-engineered from the original
#  Street Football APK binary. Names preserved verbatim from
#  the binary where possible.
#
#  Range: 1–99 (integers).  Default 70 = solid professional.
#  GK stats default to 0 for outfield players.
# ============================================================

# ── Physical ──────────────────────────────────────────────────
@export_group("Physical")
@export_range(1, 99) var agility:    int = 70  ## AgilityProperty — acceleration, COD speed
@export_range(1, 99) var balance:    int = 70  ## BalanceProperty — resistance to being pushed
@export_range(1, 99) var strong:     int = 70  ## StrongProperty  — shielding / physical duels
@export_range(1, 99) var stamina_max:int = 70  ## StaminaProperty — endurance over match
@export_range(1, 99) var responding: int = 70  ## RespondingProperty — reaction time

# ── Ball Control ──────────────────────────────────────────────
@export_group("Ball Control")
@export_range(1, 99) var control_ball:   int = 70  ## ControlBallProperty — first touch
@export_range(1, 99) var dribbling:      int = 70  ## DribblingProperty   — dribble skill rating
@export_range(1, 99) var dribble_speed:  int = 70  ## DribbleSpeedProperty — speed while dribbling
@export_range(1, 99) var tack_break:     int = 70  ## TackBreakProperty   — escape a tackle
@export_range(1, 99) var rob_slip_break: int = 70  ## RobSlipBreakProperty — break rob/slip

# ── Passing ───────────────────────────────────────────────────
@export_group("Passing")
@export_range(1, 99) var floor_pass:  int = 70  ## FloorPassBallProperty — ground pass accuracy
@export_range(1, 99) var high_pass:   int = 70  ## HighPassBallProperty  — lofted / cross quality
@export_range(1, 99) var through_ball:int = 70  ## ThroughBallProperty   — through-ball timing

# ── Shooting ─────────────────────────────────────────────────
@export_group("Shooting")
@export_range(1, 99) var shooting:           int = 70  ## ShootingProperty          — composite rating
@export_range(1, 99) var shooting_power:     int = 70  ## ShootingPowerProperty     — shot power
@export_range(1, 99) var shooting_precision: int = 70  ## ShootingPrecisionProperty — accuracy

# ── Aerial ────────────────────────────────────────────────────
@export_group("Aerial")
@export_range(1, 99) var head_ball: int = 70  ## HeadBallProperty — heading accuracy
@export_range(1, 99) var bounce:    int = 70  ## BounceProperty   — aerial win rate

# ── Defending ─────────────────────────────────────────────────
@export_group("Defending")
@export_range(1, 99) var man_to_man: int = 70  ## ManToManProperty   — man-marking
@export_range(1, 99) var intercept:  int = 70  ## InterceptProperty  — reading of play

# ── Goalkeeper ────────────────────────────────────────────────
@export_group("Goalkeeper")
@export_range(0, 99) var gk_rating: int = 0  ## GKProperty    — composite GK (0 = outfield)
@export_range(0, 99) var goalie:    int = 0  ## GoalieProperty — GK-specific skills


# ─────────────────────────────────────────────────────────────
#  Derived helpers
#  All return floats normalised to a useful range for gameplay.
# ─────────────────────────────────────────────────────────────

## Speed multiplier while dribbling. 0.70× (stat 1) → 1.30× (stat 99).
func get_dribble_speed_mult() -> float:
	return 0.70 + (dribble_speed / 99.0) * 0.60

## Effective pass accuracy (0.0–1.0) for a given PassType int.
## 0 = ground, 1 = lofted, 2 = through ball.
func get_pass_accuracy(pass_type: int) -> float:
	match pass_type:
		0: return floor_pass  / 99.0
		1: return high_pass   / 99.0
		2: return through_ball / 99.0
		_: return 0.70

## Shot power multiplier. 0.60× → 1.40×.
func get_shot_power_mult() -> float:
	return 0.60 + (shooting_power / 99.0) * 0.80

## Shot accuracy bias (0.0–1.0). Reduces random error cone.
func get_shot_accuracy() -> float:
	return shooting_precision / 99.0

## Reaction delay in seconds. High responding → fast reaction.
## Range: 0.05s (stat 99) → 0.40s (stat 1).
func get_reaction_delay() -> float:
	return 0.40 - (responding / 99.0) * 0.35

## Tackling win-chance contribution (0.30–0.80).
func get_tackling_stat() -> float:
	return 0.30 + (man_to_man / 99.0) * 0.50

## Ball-control defence stat used by TackleSystem (0.30–0.80).
func get_control_stat() -> float:
	return 0.30 + (control_ball / 99.0) * 0.50

## Aerial contest weight (0.30–0.85).
func get_aerial_stat() -> float:
	return 0.30 + (bounce / 99.0) * 0.55

## Stamina regen modifier (0.80–1.20).
func get_stamina_regen_mult() -> float:
	return 0.80 + (stamina_max / 99.0) * 0.40

## Skill-tier player_rating equivalent (0.0–1.0) — replaces the
## old scalar.  Averaged from dribbling + control_ball + agility.
func get_skill_rating() -> float:
	return (dribbling + control_ball + agility) / (3.0 * 99.0)

## Composite outfield rating (0.0–1.0).  Used for AI difficulty
## scaling and showcase mode.
func get_overall_rating() -> float:
	if gk_rating > 0:
		return (gk_rating + goalie) / (2.0 * 99.0)
	var attrs := [
		agility, balance, strong, stamina_max, responding,
		control_ball, dribbling, dribble_speed, tack_break, rob_slip_break,
		floor_pass, high_pass, through_ball,
		shooting, shooting_power, shooting_precision,
		head_ball, bounce, man_to_man, intercept
	]
	var total := 0
	for v in attrs:
		total += v
	return total / float(attrs.size() * 99)
