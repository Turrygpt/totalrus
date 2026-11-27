extends Node3D
var dots := MultiMeshInstance3D.new()
var line := MeshInstance3D.new()
var style := StandardMaterial3D.new()
func _ready() -> void:
	style.albedo_color = Color(.5,.85,.85,.85)
	style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	style.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	style.no_depth_test = true
	var marker := CylinderMesh.new()
	marker.top_radius = .22
	marker.bottom_radius = .22
	marker.height = .015
	marker.radial_segments = 8
	marker.material = style
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = marker
	dots.multimesh = multi
	dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dots)
	line.mesh = ImmediateMesh.new()
	line.material_override = style
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)
func show_formations(formations: Array) -> void:
	var count := 0
	for layout in formations: count += layout.slots.size()
	if dots.multimesh.instance_count != count:
		dots.multimesh.instance_count = count
	var mesh := line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var has_front := formations.any(func(layout): return layout.slots.size() >= 2)
	if has_front: mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var index := 0
	for layout in formations:
		for slot in layout.slots:
			dots.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,slot+Vector3.UP*.06))
			index += 1
		add_front_line(mesh,layout.slots,layout.heading,layout.columns)
	if has_front: mesh.surface_end()

func add_front_line(mesh: ImmediateMesh, slots: Array[Vector3], heading: float, columns: int) -> void:
	if slots.size() < 2: return
	var left := slots[0]+Vector3.UP*.07
	var right := slots[mini(columns,slots.size())-1]+Vector3.UP*.07
	var center := (left+right)*.5
	var forward := Vector3.FORWARD.rotated(Vector3.UP,heading)
	var side := Vector3.RIGHT.rotated(Vector3.UP,heading)
	for p in [left,right,center,center+forward*2,center+forward*2,center+forward*1.2+side*.5,center+forward*2,center+forward*1.2-side*.5]: mesh.surface_add_vertex(p)
