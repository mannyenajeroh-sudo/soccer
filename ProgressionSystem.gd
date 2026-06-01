extends Node

# ============================================================
#  ProgressionSystem.gd — STREET 3 ELITE Autoload
#  Tracks player level and XP. Persists via ConfigFile.
# ============================================================

var level : int   = 1
var xp    : int   = 0

const SAVE_PATH := "user://progression.cfg"

func _ready() -> void:
	_load()

func add_xp(amount: int) -> void:
	xp += amount
	_check_level_up()
	_save()

func _check_level_up() -> void:
	var needed := level * level * 50
	while xp >= needed:
		xp    -= needed
		level += 1
		needed = level * level * 50

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "level", level)
	cfg.set_value("player", "xp",    xp)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		level = cfg.get_value("player", "level", 1)
		xp    = cfg.get_value("player", "xp",    0)
