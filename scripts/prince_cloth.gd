extends Node3D
## A small world-space cloth grid. Shoulders follow the chest; the hem retains inertia.
## Structural/shear/bending links, body capsules and a horse-body ellipsoid prevent penetration.
const STEP := 1.0 / 120.0
const COLUMNS := 17
const ROWS := 23
const SIM_COLUMNS := 5
const SIM_ROWS := 12
var model: Node3D
var skeleton: Skeleton3D
var mounted := false
var source: MeshInstance3D
var cloth_mesh: MeshInstance3D
var wool_material: ShaderMaterial
var dynamic_mesh := ArrayMesh.new()
var chest := -1
var skin_frame := Transform3D.IDENTITY
var inverse_rest := Transform3D.IDENTITY
var rest := PackedVector3Array()
var points := PackedVector3Array()
var previous := PackedVector3Array()
var pinned := PackedByteArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()
var render_rest := PackedVector3Array()
var render_uvs := PackedVector2Array()
var render_cells := PackedInt32Array()
var render_weights := PackedVector2Array()
var render_folds := PackedVector3Array()
var links_a := PackedInt32Array()
var links_b := PackedInt32Array()
var lengths := PackedFloat32Array()
var stiffness := PackedFloat32Array()
var capsules: Array[Vector4] = []
var capsule_ends := PackedVector3Array()
var body_pairs: Array = []
var horse_frame := Transform3D.IDENTITY
var horse_inverse := Transform3D.IDENTITY
var horse_bone := -1
var horse_contact := true
var collar_rest := Vector3.ZERO
var back_direction := Vector3.BACK
var elapsed := 0.0
var accumulator := 0.0
var last_frame := Transform3D.IDENTITY
var last_origin := Vector3.ZERO
var airflow := Vector3.ZERO
var wind_velocity := Vector3.ZERO
var carrier_velocity := Vector3.ZERO
var suspended := false
var ground_y := .025

func configure(visual: Node3D, riding: bool) -> void:
	model = visual
	mounted = riding
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	source = model.find_child("PrinceCloak", true, false)
	chest = skeleton.find_bone("RiderChest" if mounted else "mixamorig_Spine2")
	if chest < 0:
		chest = skeleton.find_bone("RiderChest" if mounted else "mixamorig:Spine2")
	assert(source != null and chest >= 0, "Prince cape requires its matching skeleton")
	var arrays := source.mesh.surface_get_arrays(0)
	render_rest = arrays[Mesh.ARRAY_VERTEX]
	render_uvs = arrays[Mesh.ARRAY_TEX_UV]
	indices = arrays[Mesh.ARRAY_INDEX]
	# Godot's imported vertices already include the object scale. The skin's
	# inverse bind, rather than inverse bone rest alone, accounts for that scale.
	var bindings: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	inverse_rest = source.skin.get_bind_pose(bindings[0])
	skin_frame = Transform3D.IDENTITY
	var authored_grid := {}
	for i in render_rest.size():
		authored_grid[Vector2i(roundi(render_uvs[i].x * (COLUMNS - 1)), roundi(render_uvs[i].y * (ROWS - 1)))] = i
	# Simulate 60 particles, then reconstruct all 391 authored vertices and folds.
	# Keeping the detail mesh out of the solver makes the commander affordable in a battle.
	for row in SIM_ROWS:
		for column in SIM_COLUMNS:
			var authored: int = authored_grid[Vector2i(column * 4, row * 2)]
			rest.append(render_rest[authored])
			uvs.append(render_uvs[authored])
	for i in render_rest.size():
		var cell := Vector2(render_uvs[i].x * (SIM_COLUMNS - 1), render_uvs[i].y * (SIM_ROWS - 1))
		var column := mini(floori(cell.x), SIM_COLUMNS - 2)
		var row := mini(floori(cell.y), SIM_ROWS - 2)
		var a := row * SIM_COLUMNS + column
		var weight := cell - Vector2(column, row)
		var base := rest[a].lerp(rest[a + 1], weight.x).lerp(rest[a + SIM_COLUMNS].lerp(rest[a + SIM_COLUMNS + 1], weight.x), weight.y)
		render_cells.append(a)
		render_weights.append(weight)
		render_folds.append(render_rest[i] - base)
	var grid := {}
	var top_uv := 0.0
	var highest := -INF
	for i in rest.size():
		var height := (skin_frame * rest[i]).y
		if height > highest:
			highest = height
			top_uv = uvs[i].y
		grid[Vector2i(roundi(uvs[i].x * (SIM_COLUMNS - 1)), roundi(uvs[i].y * (SIM_ROWS - 1)))] = i
	pinned.resize(rest.size())
	for i in rest.size():
		pinned[i] = 1 if absf(uvs[i].y - top_uv) < .001 else 0
		if pinned[i]: collar_rest += rest[i]
	collar_rest /= maxf(1.0, pinned.count(1))
	var start := anchor_frame()
	points.resize(rest.size())
	for i in rest.size():
		points[i] = start * rest[i]
	previous = points.duplicate()
	for key: Vector2i in grid:
		for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(2, 0), Vector2i(0, 2)]:
			if grid.has(key + offset):
				var a: int = grid[key]
				var b: int = grid[key + offset]
				links_a.append(a); links_b.append(b)
				lengths.append(points[a].distance_to(points[b]))
				stiffness.append(.28 if offset.length_squared() == 4 else (.65 if offset.length_squared() == 2 else 1.0))
	var names: Array
	if mounted:
		names = [["RiderRoot", "RiderHead", .18], ["RiderUpperArm.L", "RiderForearm.L", .10], ["RiderUpperArm.R", "RiderForearm.R", .10]]
		horse_bone = skeleton.find_bone("Torso2")
	else:
		names = [["Hips", "Neck", .18], ["LeftArm", "LeftForeArm", .10], ["RightArm", "RightForeArm", .10], ["LeftUpLeg", "LeftLeg", .15], ["RightUpLeg", "RightLeg", .15], ["LeftLeg", "LeftFoot", .115], ["RightLeg", "RightFoot", .115]]
	for entry in names:
		var a := find_bone(entry[0])
		var b := find_bone(entry[1])
		if a >= 0 and b >= 0:
			body_pairs.append([a, b, entry[2]])
	cloth_mesh = MeshInstance3D.new()
	cloth_mesh.name = "Wool"
	cloth_mesh.mesh = dynamic_mesh
	cloth_mesh.top_level = true
	cloth_mesh.extra_cull_margin = 1.0
	wool_material = ShaderMaterial.new()
	wool_material.shader = preload("res://assets/prince/wool.gdshader")
	cloth_mesh.material_override = wool_material
	source.material_override = wool_material
	add_child(cloth_mesh)
	cloth_mesh.global_transform = Transform3D.IDENTITY
	source.hide()
	process_priority = 50
	last_frame = start
	last_origin = model.global_position
	update_colliders()
	for iteration in 36:
		simulate(STEP, start)
	upload_mesh()

func set_color(color: Color) -> void:
	wool_material.set_shader_parameter("wool_color", color)

func use_skinned_mesh() -> void:
	set_process(false)
	cloth_mesh.hide()
	source.show()

func find_bone(short_name: String) -> int:
	for candidate in [short_name, "mixamorig:" + short_name, "mixamorig_" + short_name]:
		var index := skeleton.find_bone(candidate)
		if index >= 0: return index
	return -1

func anchor_frame() -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(chest) * inverse_rest * skin_frame

func bone_point(index: int) -> Vector3:
	return skeleton.to_global(skeleton.get_bone_global_pose(index).origin)

func update_colliders() -> void:
	back_direction = -anchor_frame().basis.z.normalized()
	capsules.clear()
	capsule_ends.clear()
	for pair in body_pairs:
		var origin := bone_point(pair[0])
		capsules.append(Vector4(origin.x, origin.y, origin.z, pair[2]))
		capsule_ends.append(bone_point(pair[1]))
	if horse_bone >= 0:
		# Horse torso only: head and legs are outside the cape's working area.
		var body_rest := skeleton.get_bone_global_rest(horse_bone)
		var rear := skeleton.get_bone_global_rest(skeleton.find_bone("Back")).origin
		var center := (body_rest.origin + rear) * .5
		horse_frame = skeleton.global_transform * skeleton.get_bone_global_pose(horse_bone) * body_rest.affine_inverse() * Transform3D(Basis.IDENTITY, center)
		horse_frame.basis = horse_frame.basis.orthonormalized()
		horse_inverse = horse_frame.affine_inverse()
		# During a fall the authored rider briefly crosses the horse collider.
		# Never pull the attached collar away from the rider to resolve that overlap.
		var collar := horse_inverse * (anchor_frame() * collar_rest)
		horse_contact = (collar / Vector3(.35, .44, .74)).length_squared() > 1.15
	ground_y = model.global_position.y + .025

func _process(delta: float) -> void:
	if not is_instance_valid(skeleton) or points.is_empty(): return
	var camera := get_viewport().get_camera_3d()
	if not model.is_visible_in_tree() or (camera and camera.global_position.distance_squared_to(model.global_position) > 6400):
		# Keep a skinned silhouette at long range; never leave world-space cloth behind.
		cloth_mesh.hide()
		source.visible = model.is_visible_in_tree()
		suspended = true
		return
	cloth_mesh.show()
	source.hide()
	var frame := anchor_frame()
	var shift := model.global_position - last_origin
	if suspended or shift.length() > 2.0 or delta > .25:
		for i in points.size(): points[i] = frame * rest[i]
		previous = points.duplicate()
		last_frame = frame
		accumulator = 0
		suspended = false
		shift = Vector3.ZERO
	last_origin = model.global_position
	var velocity := shift / maxf(delta, .001)
	carrier_velocity = velocity
	airflow = airflow.lerp((-velocity * .9 + wind_velocity).limit_length(10.0), 1.0 - exp(-delta * 5.0))
	elapsed += delta
	update_colliders()
	accumulator += minf(delta, .1)
	var steps := mini(floori(accumulator / STEP), 12)
	for step in steps:
		var interpolated := last_frame.interpolate_with(frame, float(step + 1) / steps)
		simulate(STEP, interpolated)
		accumulator -= STEP
	last_frame = frame
	for i in points.size():
		if pinned[i]:
			points[i] = frame * rest[i]
			previous[i] = points[i]
	upload_mesh()

func simulate(delta: float, frame: Transform3D) -> void:
	var breeze := Vector3(.18 * sin(elapsed * 1.7), .0, .12 * cos(elapsed * 1.1))
	var force := Vector3(0, -9.81, 0) + airflow + breeze
	for i in points.size():
		if pinned[i]:
			points[i] = frame * rest[i]
			previous[i] = points[i]
		else:
			var current := points[i]
			# Damping is relative to the moving wearer. Damping world velocity
			# would incorrectly brake the cape against a horse moving at 7 m/s.
			var carried := carrier_velocity * delta
			points[i] += carried + (points[i] - previous[i] - carried) * exp(-5.0 * delta) + force * delta * delta
			var yoke := 1.0 - smoothstep(.015, .15, uvs[i].y)
			points[i] = points[i].lerp(frame * rest[i], yoke * .325)
			previous[i] = current
	for iteration in 6:
		for cursor in links_a.size():
			var link := cursor if iteration % 2 == 0 else links_a.size() - 1 - cursor
			var a := links_a[link]
			var b := links_b[link]
			var direction := points[b] - points[a]
			var distance := direction.length()
			var free := 2 - int(pinned[a]) - int(pinned[b])
			if distance < .000001 or free == 0: continue
			var correction := direction * ((distance - lengths[link]) / distance * stiffness[link] / free)
			if not pinned[a]: points[a] += correction
			if not pinned[b]: points[b] -= correction
		for i in points.size():
			if pinned[i]: continue
			var point := points[i]
			for k in capsules.size():
				if k == 0 and uvs[i].y < .08: continue
				# The short shoulder yoke is sewn in place; arms pass beneath it.
				if k in [1, 2] and uvs[i].y < .18: continue
				var capsule := capsules[k]
				var start := Vector3(capsule.x, capsule.y, capsule.z)
				var segment := capsule_ends[k] - start
				var along := (point - start).dot(segment) / maxf(segment.length_squared(), .0001)
				var closest := start + segment * clampf(along, 0, 1)
				var offset := point - closest
				if k == 0 and along > 0 and along < 1 and back_direction.y > -.6:
					# Keep the cape on the back side even during a fast torso turn.
					# An unsigned nearest-surface projection could tunnel it to the chest.
					var side := segment.normalized().cross(back_direction).normalized()
					var lateral := offset.dot(side) / .245
					if absf(lateral) < 1.0:
						var rear_surface := .185 * sqrt(1.0 - lateral * lateral)
						point += back_direction * maxf(0.0, rear_surface - offset.dot(back_direction))
					offset = point - closest
				if offset.length_squared() < capsule.w * capsule.w:
					point = closest + offset.normalized() * capsule.w
			if horse_bone >= 0 and horse_contact:
				var local := horse_inverse * point
				var radius := Vector3(.35, .44, .74)
				var normalized := local / radius
				if normalized.length_squared() < 1.0:
					point = horse_frame * (normalized.normalized() * radius)
			point.y = maxf(point.y, ground_y)
			points[i] = point
	# Finish with a strain limit so sudden animation/volume contacts cannot tear
	# a short edge into a long spike. Contact errors relax on the next substep.
	for sweep in 16:
		var largest_error := 1.0
		for cursor in links_a.size():
			var link := cursor if sweep % 2 == 0 else links_a.size() - 1 - cursor
			if stiffness[link] != 1.0: continue
			var a := links_a[link]
			var b := links_b[link]
			var difference := points[b] - points[a]
			var distance := difference.length()
			largest_error = maxf(largest_error, distance / lengths[link])
			var limit := lengths[link] * 1.12
			var free := 2 - int(pinned[a]) - int(pinned[b])
			if distance <= limit or free == 0: continue
			var correction := difference * ((distance - limit) / distance / free)
			if not pinned[a]: points[a] += correction
			if not pinned[b]: points[b] -= correction
		if largest_error < 1.18: break

func upload_mesh() -> void:
	var vertices := PackedVector3Array()
	vertices.resize(render_rest.size())
	var frame := anchor_frame()
	for i in vertices.size():
		var a := render_cells[i]
		var weight := render_weights[i]
		vertices[i] = points[a].lerp(points[a + 1], weight.x).lerp(points[a + SIM_COLUMNS].lerp(points[a + SIM_COLUMNS + 1], weight.x), weight.y) + frame.basis * render_folds[i]
		if render_uvs[i].y < .001:
			vertices[i] = frame * render_rest[i]
		else:
			vertices[i].y = maxf(vertices[i].y, ground_y)
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for triangle in range(0, indices.size(), 3):
		var a := indices[triangle]
		var b := indices[triangle + 1]
		var c := indices[triangle + 2]
		var normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		normals[a] += normal; normals[b] += normal; normals[c] += normal
	for i in normals.size(): normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = render_uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	dynamic_mesh.clear_surfaces()
	dynamic_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func diagnostics() -> Dictionary:
	var anchor_error := 0.0
	var max_stretch := 1.0
	var structural_stretch := 1.0
	var frame := anchor_frame()
	for i in points.size():
		if pinned[i]: anchor_error = maxf(anchor_error, points[i].distance_to(frame * rest[i]))
	for i in lengths.size():
		max_stretch = maxf(max_stretch, points[links_a[i]].distance_to(points[links_b[i]]) / lengths[i])
		if stiffness[i] == 1.0:
			structural_stretch = maxf(structural_stretch, points[links_a[i]].distance_to(points[links_b[i]]) / lengths[i])
	return {"vertices": render_rest.size(), "particles": points.size(), "pinned": pinned.count(1), "anchor_error": anchor_error, "max_stretch": max_stretch, "structural_stretch": structural_stretch, "finite": points.size() > 0 and Array(points).all(func(p: Vector3): return p.is_finite())}
