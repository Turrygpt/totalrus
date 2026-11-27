extends SceneTree

func _initialize() -> void: call_deferred("run")

func simplified(mesh: Mesh, budgets: Array[int]) -> Array[ArrayMesh]:
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	importer.generate_lods(25.0, 60.0, [])
	var result: Array[ArrayMesh] = []
	for budget in budgets:
		var best := PackedInt32Array()
		for index in importer.get_surface_lod_count(0):
			var indices := importer.get_surface_lod_indices(0,index)
			if indices.size() > best.size() and indices.size() <= budget * 3:
				best = indices
		var arrays := mesh.surface_get_arrays(0)
		if best.is_empty():
			push_error("No valid LOD under %d triangles" % budget)
			return []
		# Preserve vertex indices used by the existing baked animation textures.
		arrays[Mesh.ARRAY_INDEX] = best
		var lod := ArrayMesh.new()
		lod.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		lod.surface_set_material(0,mesh.surface_get_material(0))
		result.append(lod)
		print("MESH ",mesh.surface_get_array_index_len(0)/3," -> ",best.size()/3," triangles")
	return result

func troop_lods(mesh: ArrayMesh, bank: Resource, protect_uniform := false) -> Array[ArrayMesh]:
	var mid := ArrayMesh.new()
	var far := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var index_count := mesh.surface_get_array_index_len(surface)
		var mid_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var far_indices := mid_indices
		var animated: Array[PackedInt32Array] = []
		if index_count > 420: animated = animated_lod_indices(arrays,bank,surface,protect_uniform)
		if animated.size() == 2:
			mid_indices = animated[0]
			far_indices = animated[1]
		elif index_count > 420:
			var locked := PackedInt32Array()
			if protect_uniform:
				var editable := PackedInt32Array()
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bounds := mesh.get_aabb()
				for index in range(0,mid_indices.size(),3):
					var inside := true
					for corner in 3:
						var point := vertices[mid_indices[index+corner]]
						var height := (point.y-bounds.position.y)/bounds.size.y
						if height < .48 or height > .76 or absf(point.x-bounds.get_center().x) > bounds.size.x*.23:
							inside = false
							break
					var target := editable if inside else locked
					for corner in 3: target.append(mid_indices[index+corner])
					if inside: editable = target
					else: locked = target
				mid_indices = editable
				arrays[Mesh.ARRAY_INDEX] = editable
			var importer := ImporterMesh.new()
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays)
			importer.generate_lods(25.0,60.0,[])
			var parents := connected_vertices(arrays[Mesh.ARRAY_VERTEX],mid_indices)
			var original := split_components(mid_indices,parents)
			var levels: Array[Dictionary] = []
			for level in importer.get_surface_lod_count(0):
				var indices := importer.get_surface_lod_indices(0,level)
				levels.append(split_components(indices,parents))
			mid_indices = component_lod(original,levels,.58)
			far_indices = component_lod(original,levels,.24)
			mid_indices.append_array(locked)
			far_indices.append_array(locked)
		arrays[Mesh.ARRAY_INDEX] = mid_indices
		mid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		arrays[Mesh.ARRAY_INDEX] = far_indices
		far.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return [mid,far]

func animated_lod_indices(arrays: Array, bank: Resource, surface: int, protect_uniform: bool) -> Array[PackedInt32Array]:
	var tool := ProjectSettings.globalize_path("res://build/pose_mesh_simplifier.exe")
	if not FileAccess.file_exists(tool): return []
	var input_path := ProjectSettings.globalize_path("res://build/pose_mesh_input.bin")
	var output_path := ProjectSettings.globalize_path("res://build/pose_mesh_output.bin")
	var input := FileAccess.open(input_path,FileAccess.WRITE)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var texture: Texture2D = bank.get_meta("pose_positions")
	var poses := texture.get_image()
	var offsets: Array = bank.get_meta("surface_offsets",[])
	var offset: int = offsets[surface] if not offsets.is_empty() else 0
	var rows := [mini(3,poses.get_height()-1),poses.get_height()/3,poses.get_height()*2/3]
	input.store_32(vertices.size())
	input.store_32(indices.size())
	input.store_32(5 + rows.size()*3)
	input.store_32(int(protect_uniform))
	for vertex in vertices:
		input.store_float(vertex.x)
		input.store_float(vertex.y)
		input.store_float(vertex.z)
	for index in vertices.size():
		var texcoord := uv[index] if not uv.is_empty() else Vector2.ZERO
		var normal := normals[index] if not normals.is_empty() else Vector3.UP
		input.store_float(texcoord.x)
		input.store_float(texcoord.y)
		input.store_float(normal.x)
		input.store_float(normal.y)
		input.store_float(normal.z)
		for row: int in rows:
			var pose := poses.get_pixel(offset+index,row)
			input.store_float(pose.r-vertices[index].x)
			input.store_float(pose.g-vertices[index].y)
			input.store_float(pose.b-vertices[index].z)
	for index in indices: input.store_32(index)
	input.close()
	var result := OS.execute(tool,[input_path,output_path],[],true)
	DirAccess.remove_absolute(input_path)
	if result != 0: return []
	var output := FileAccess.open(output_path,FileAccess.READ)
	var levels: Array[PackedInt32Array] = []
	for level in 2:
		var count := output.get_32()
		levels.append(output.get_buffer(count*4).to_int32_array())
	output.close()
	DirAccess.remove_absolute(output_path)
	return levels

func connected_vertices(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedInt32Array:
	var parents := PackedInt32Array()
	parents.resize(vertices.size())
	var welded := {}
	for i in vertices.size():
		var p := Vector3i((vertices[i] * 100000.0).round())
		parents[i] = welded.get_or_add(p,i)
	for i in range(0,indices.size(),3):
		var root := component_root(parents,indices[i])
		parents[component_root(parents,indices[i+1])] = root
		parents[component_root(parents,indices[i+2])] = root
	for i in vertices.size(): parents[i] = component_root(parents,i)
	return parents

func component_root(parents: PackedInt32Array, index: int) -> int:
	while parents[index] != index: index = parents[index]
	return index

func split_components(indices: PackedInt32Array, parents: PackedInt32Array) -> Dictionary:
	var components := {}
	for i in range(0,indices.size(),3):
		var component := parents[indices[i]]
		if parents[indices[i+1]] != component or parents[indices[i+2]] != component: continue
		var target: Array = components.get_or_add(component,[])
		target.append(indices[i])
		target.append(indices[i+1])
		target.append(indices[i+2])
	return components

func component_lod(original: Dictionary, levels: Array[Dictionary], ratio: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	for component in original:
		var source: Array = original[component]
		var budget := floori(source.size()*ratio)
		var minimum := mini(source.size(),maxi(24,floori(source.size()*ratio*.55)))
		var best: Array = []
		# Restore a missing shell from the least expensive level that kept it.
		for level in levels:
			var candidate: Array = level.get(component,[])
			if candidate.size() < minimum: continue
			if best.is_empty() or (best.size() > budget and candidate.size() < best.size()) or (candidate.size() <= budget and candidate.size() > best.size()):
				best = candidate
		result.append_array(PackedInt32Array(source if best.is_empty() else best))
	return result

func triangles(mesh: ArrayMesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count(): count += mesh.surface_get_array_index_len(surface) / 3
	return count

func run() -> void:
	var bank: Resource = load("res://assets/lod/soldier_poses.res")
	var main_body: ArrayMesh = bank.get_meta("pose_mesh")
	var body := troop_lods(main_body,bank,true)
	print("TROOP soldier ",triangles(main_body)," -> ",triangles(body[0])," -> ",triangles(body[1]))
	var scene: PackedScene = load("res://assets/sword.glb")
	var root_sword := scene.instantiate()
	var part := root_sword.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
	var sword := simplified(part.mesh, [650])
	root_sword.free()
	if body.size() != 2 or sword.size() != 1:
		quit(2)
		return
	var library := Resource.new()
	library.set_meta("body_meshes",body)
	library.set_meta("sword",sword[0])
	var groups := {}
	for kind in ["varangian","cavalry","khazar"]:
		var pose_bank: Resource = load("res://assets/lod/%s_poses.res" % kind)
		var main: ArrayMesh = pose_bank.get_meta("pose_mesh")
		var levels := troop_lods(main,pose_bank)
		groups[kind] = levels
		print("TROOP ",kind," ",triangles(main)," -> ",triangles(levels[0])," -> ",triangles(levels[1]))
	library.set_meta("unit_meshes",groups)
	quit(ResourceSaver.save(library,"res://assets/lod/warrior_meshes.res",ResourceSaver.FLAG_COMPRESS))
