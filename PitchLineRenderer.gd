extends MeshInstance3D

# ============================================================
#  PitchLineRenderer.gd  —  procedural pitch lines
#  Uses Godot 4 ImmediateMesh to draw lines above the grass plane.
#  All dimensions derived from PitchConstants — no hardcoded widths.
# ============================================================

func _ready() -> void:
	var im_mesh := ImmediateMesh.new()
	mesh = im_mesh
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	material_override = mat
	
	im_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var hw: float = PitchConstants.PLAY_HALF_X   # half-width  (12.0)
	var hl: float = PitchConstants.PLAY_HALF_Z   # half-length (9.75)
	var y: float  = 0.01
	
	# Boundary lines
	_draw_line(im_mesh, Vector3(-hw, y, -hl), Vector3(hw, y, -hl))
	_draw_line(im_mesh, Vector3(hw,  y, -hl), Vector3(hw, y,  hl))
	_draw_line(im_mesh, Vector3(hw,  y,  hl), Vector3(-hw, y, hl))
	_draw_line(im_mesh, Vector3(-hw, y,  hl), Vector3(-hw, y, -hl))
	
	# Center line
	_draw_line(im_mesh, Vector3(-hw, y, 0.0), Vector3(hw, y, 0.0))
	
	# Center circle (radius = 3.0 meters)
	_draw_circle(im_mesh, Vector3(0.0, y, 0.0), 3.0)
	
	# Goal area A (negative Z side)
	var ga: float = 4.0   # goal area half-width (3m each side of center)
	var gd: float = 3.0   # goal area depth
	_draw_line(im_mesh, Vector3(-ga, y, -hl),         Vector3(-ga, y, -hl + gd))
	_draw_line(im_mesh, Vector3(-ga, y, -hl + gd),    Vector3(ga,  y, -hl + gd))
	_draw_line(im_mesh, Vector3(ga,  y, -hl + gd),    Vector3(ga,  y, -hl))
	
	# Goal area B (positive Z side)
	_draw_line(im_mesh, Vector3(-ga, y,  hl),         Vector3(-ga, y,  hl - gd))
	_draw_line(im_mesh, Vector3(-ga, y,  hl - gd),    Vector3(ga,  y,  hl - gd))
	_draw_line(im_mesh, Vector3(ga,  y,  hl - gd),    Vector3(ga,  y,  hl))
	
	im_mesh.surface_end()

func _draw_line(im_mesh: ImmediateMesh, start: Vector3, end: Vector3) -> void:
	im_mesh.surface_add_vertex(start)
	im_mesh.surface_add_vertex(end)

func _draw_circle(im_mesh: ImmediateMesh, center: Vector3, radius: float) -> void:
	const STEPS := 32
	var prev_pt := center + Vector3(radius, 0.0, 0.0)
	for i in range(1, STEPS + 1):
		var angle := float(i) / STEPS * TAU
		var pt := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_draw_line(im_mesh, prev_pt, pt)
		prev_pt = pt
