extends Node3D

const NEAR_SCENES := [
	preload("res://assets/trees/oak.glb"),
	preload("res://assets/trees/birch.glb"),
	preload("res://assets/trees/scots_pine.glb"),
	preload("res://assets/trees/aspen.glb"),
]
const FAR_SCENES := [
	preload("res://assets/trees/oak_far.glb"),
	preload("res://assets/trees/birch_far.glb"),
	preload("res://assets/trees/scots_pine_far.glb"),
	preload("res://assets/trees/aspen_far.glb"),
]
const ASPEN := 3
const CHUNK_SIZE := 64.0
const DETAIL_DISTANCE := 240.0
const FADE_MARGIN := 42.0

func plant(groups: Array, snow: float) -> void:
	for kind in groups.size():
		if groups[kind].is_empty():
			continue
		var near_mesh := prepared_mesh(NEAR_SCENES[kind], kind, snow, false)
		var far_mesh := prepared_mesh(FAR_SCENES[kind], kind, snow, true)
		var chunks := {}
		for placement: Transform3D in groups[kind]:
			var point := placement.origin
			var cell := Vector2i(floori(point.x / CHUNK_SIZE), floori(point.z / CHUNK_SIZE))
			if not chunks.has(cell):
				chunks[cell] = []
			chunks[cell].append(placement)
		for cell: Vector2i in chunks:
			make_batch(chunks[cell], Vector3(cell.x * CHUNK_SIZE, 0.0, cell.y * CHUNK_SIZE), near_mesh, far_mesh)

func prepared_mesh(scene: PackedScene, kind: int, snow: float, distant: bool) -> ArrayMesh:
	var root := scene.instantiate()
	var node := root as MeshInstance3D
	if node == null:
		var models := root.find_children("*", "MeshInstance3D", true, false)
		if not models.is_empty():
			node = models[0] as MeshInstance3D
	var mesh := node.mesh.duplicate() as ArrayMesh
	root.free()
	for i in mesh.get_surface_count():
		var source := mesh.surface_get_material(i) as StandardMaterial3D
		if source == null:
			continue
		var material := source.duplicate() as StandardMaterial3D
		material.vertex_color_use_as_albedo = true
		if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.alpha_scissor_threshold = .30 if distant else .23
			if kind == ASPEN:
				material.albedo_color *= Color(.68, .91, .77)
		if distant:
			material.albedo_color *= Color(.77, .79, .76)
		material.albedo_color *= Color.WHITE.lerp(Color(1.0, 1.03, 1.11), snow)
		mesh.surface_set_material(i, material)
	return mesh

func make_batch(placements: Array, origin: Vector3, near_mesh: Mesh, far_mesh: Mesh) -> void:
	var near_data := new_tree_multimesh(near_mesh, placements.size())
	var far_data := new_tree_multimesh(far_mesh, placements.size())
	var local_bounds := near_mesh.get_aabb().merge(far_mesh.get_aabb())
	var bounds: AABB
	for i in placements.size():
		var placement: Transform3D = placements[i]
		var point := placement.origin
		var tint := .85 + .17 * absf(sin(point.x * 12.7 + point.z * 3.1))
		placement.origin -= origin
		var color := Color(tint, tint, tint * .95)
		near_data.set_instance_transform(i, placement)
		near_data.set_instance_color(i, color)
		far_data.set_instance_transform(i, placement)
		far_data.set_instance_color(i, color)
		var footprint := placement * local_bounds
		bounds = footprint if i == 0 else bounds.merge(footprint)
	# Both passes need the same bounds so that the renderer bases the fade on the same center.
	var padded_bounds := bounds.grow(.20)
	near_data.custom_aabb = padded_bounds
	far_data.custom_aabb = padded_bounds
	add_detail_level(near_data, origin, false)
	add_detail_level(far_data, origin, true)

func new_tree_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.use_colors = true
	data.mesh = mesh
	data.instance_count = count
	return data

func add_detail_level(data: MultiMesh, origin: Vector3, distant: bool) -> void:
	var node := MultiMeshInstance3D.new()
	node.position = origin
	node.multimesh = data
	var supports_fade := RenderingServer.get_current_rendering_method() == "forward_plus"
	var margin := FADE_MARGIN if supports_fade else 0.0
	if supports_fade:
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if distant:
		node.visibility_range_begin = DETAIL_DISTANCE
		node.visibility_range_begin_margin = margin
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		node.visibility_range_end = DETAIL_DISTANCE
		node.visibility_range_end_margin = margin
	add_child(node)
