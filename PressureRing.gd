extends Node3D

# ============================================================
#  PressureRing.gd  —  FIFA-style possession ring
#
#  Shows a pulsing ring UNDER THE PLAYER WHO HAS THE BALL,
#  colour-coded by team. Ring breathes smoothly, scales up
#  on shot-charge. No ring when no one has possession.
# ============================================================

const RING_SEGMENTS  := 48
const RING_OUTER     := 0.72   # metres radius outer
const RING_INNER     := 0.48   # metres radius inner
const PULSE_SPEED    := 2.2    # breath cycles per second
const PULSE_MIN_A    := 0.55   # min alpha
const PULSE_MAX_A    := 0.92   # max alpha
const SCALE_BASE     := 1.00
const SCALE_SPRINT   := 1.18   # ring expands slightly when sprinting
const RING_Y         := 0.03   # just above ground

# Team colours matching the kit
const TEAM_COLS := [
	Color(0.15, 0.55, 1.00),  # Team 0 — blue
	Color(1.00, 0.22, 0.22),  # Team 1 — red
]
const HUMAN_TINT := Color(1.0, 1.0, 1.0, 1.0)  # white overlay for human player

var ball_physics: Node3D = null
var all_players: Array   = []

var _ring_mi: MeshInstance3D         = null
var _ring_mat: StandardMaterial3D    = null
var _t: float                        = 0.0

# Track current carrier to avoid rebuilding mesh every frame
var _last_carrier: Node3D            = null

func _ready() -> void:
	_ring_mi  = MeshInstance3D.new()
	_ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.transparency        = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode        = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.cull_mode           = BaseMaterial3D.CULL_DISABLED
	_ring_mat.depth_draw_mode     = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	_ring_mat.no_depth_test       = false
	_ring_mi.material_override    = _ring_mat
	_ring_mi.mesh                 = _build_ring()
	_ring_mi.visible              = false
	add_child(_ring_mi)

func _process(delta: float) -> void:
	_t += delta

	var carrier: Node3D = _find_carrier()
	if carrier == null:
		_ring_mi.visible = false
		_last_carrier    = null
		return

	# Position ring flat on ground under carrier
	var pos := carrier.global_position
	pos.y = RING_Y
	_ring_mi.global_position = pos
	_ring_mi.visible         = true

	# Determine team colour; white tint for human
	var team_id: int = carrier.get("team_id") if carrier.get("team_id") != null else 0
	var is_human: bool = carrier.get_meta("is_human", false)
	var base_col: Color = TEAM_COLS[clampi(team_id, 0, 1)]
	if is_human:
		base_col = base_col.lerp(HUMAN_TINT, 0.4)

	# Breathing alpha
	var breath: float  = sin(_t * PULSE_SPEED * TAU * 0.5) * 0.5 + 0.5
	var alpha: float   = lerpf(PULSE_MIN_A, PULSE_MAX_A, breath)

	# Scale: expand when sprinting
	var sprinting: bool = false
	var drib: Node      = carrier.get("_dribble") if carrier.get("_dribble") != null else null
	if drib: sprinting  = drib.get("is_sprinting") if drib.get("is_sprinting") != null else false
	var s: float = SCALE_SPRINT if sprinting else SCALE_BASE
	# Smooth scale lerp
	var cur_s: float = _ring_mi.scale.x
	var new_s: float = lerpf(cur_s, s, delta * 6.0)
	_ring_mi.scale   = Vector3(new_s, 1.0, new_s)

	_ring_mat.albedo_color = Color(base_col.r, base_col.g, base_col.b, alpha)

func _find_carrier() -> Node3D:
	for p in all_players:
		if not is_instance_valid(p): continue
		var drib: Node = p.get("_dribble") if p.get("_dribble") != null else null
		if drib and drib.get("in_possession"):
			return p as Node3D
	return null

func _build_ring() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(RING_SEGMENTS):
		var a0: float = float(i)       / RING_SEGMENTS * TAU
		var a1: float = float(i + 1)   / RING_SEGMENTS * TAU
		var o0 := Vector3(cos(a0) * RING_OUTER, 0.0, sin(a0) * RING_OUTER)
		var o1 := Vector3(cos(a1) * RING_OUTER, 0.0, sin(a1) * RING_OUTER)
		var i0 := Vector3(cos(a0) * RING_INNER, 0.0, sin(a0) * RING_INNER)
		var i1 := Vector3(cos(a1) * RING_INNER, 0.0, sin(a1) * RING_INNER)
		st.add_vertex(o0); st.add_vertex(o1); st.add_vertex(i0)
		st.add_vertex(i0); st.add_vertex(o1); st.add_vertex(i1)
	return st.commit()
