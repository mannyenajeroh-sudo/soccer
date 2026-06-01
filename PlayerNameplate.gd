extends Node3D

# ============================================================
#  PlayerNameplate.gd  —  billboard number above each player.
#  Dynamically instantiates and styles a Label3D child.
# ============================================================

@export var team_id       : int = 0
@export var player_number : int = 1

const TEAM_COLORS := [Color(0.2, 0.4, 1.0), Color(1.0, 0.2, 0.2)]

func _ready() -> void:
	var label := Label3D.new()
	label.text = str(player_number)
	label.modulate = TEAM_COLORS[team_id]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.005 # neat readable scale
	label.font_size = 42
	label.position.y = 2.0   # float exactly 2 meters above player base
	add_child(label)
