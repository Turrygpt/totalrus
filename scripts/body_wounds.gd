extends RefCounted

const MAX_WOUNDS := 3
const ROW_COUNT := 2048
const OVERLAY_SHADER = preload("res://assets/body_wound_overlay.gdshader")
const FOOT_SEGMENTS := [
	["Hips", "Spine1"], ["Spine1", "Neck"], ["Head", "HeadTopEnd"],
	["LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftHand"],
	["RightArm", "RightForeArm"], ["RightForeArm", "RightHand"],
	["LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftFoot"],
	["RightUpLeg", "RightLeg"], ["RightLeg", "RightFoot"],
]
const MOUNTED_SEGMENTS := [
	["RiderRoot", "RiderChest"], ["RiderChest", "RiderHead"], ["RiderHead", "RiderHead"],
	["RiderUpperArm.L", "RiderHand.L"], ["RiderUpperArm.R", "RiderHand.R"],
	["RiderThigh.L", "RiderShin.L"], ["RiderThigh.R", "RiderShin.R"],
	["Body", "Torso"], ["Torso", "Neck1"], ["Neck1", "Head"], ["Back", "Body"],
]

static var atlas_image: Image
static var atlas_texture: ImageTexture
static var next_row := 1
static var free_rows: Array[int] = []
static var upload_pending := false
static var mesh_queries := {}
static var materials := {}
static var skin_binds := {}
var row := 0
var next_stamp := 0
var wounded_surfaces := {}
var anchor_segments := PackedInt32Array()

static func prepare_body_meshes(model: Node3D, mounted: bool) -> void:
	for body: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not mounted or body.name in [&"Horse", &"Mounted warrior"]:
			geometry(body.mesh)
		if not mounted:
			break

static func base_material(material: Material) -> Material:
	return material.get_meta(&"body_wound_base", material) if material else null

static func texture() -> ImageTexture:
	if not atlas_texture:
		atlas_image = Image.create(MAX_WOUNDS * 2, ROW_COUNT, false, Image.FORMAT_RGBAF)
		atlas_texture = ImageTexture.create_from_image(atlas_image)
	return atlas_texture

static func flush_atlas() -> void:
	atlas_texture.update(atlas_image)
	upload_pending = false

static func surface_id(body: MeshInstance3D, surface: int, mounted: bool) -> int:
	if not mounted:
		return surface + 1
	if body.name == &"Mounted warrior":
		return surface + 1
	if body.name == &"Horse":
		return surface + 17
	return 0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and row > 0:
		for x in MAX_WOUNDS * 2:
			atlas_image.set_pixel(x, row, Color(0, 0, 0, 0))
		free_rows.append(row)

func add_wound(actor: CharacterBody3D, point: Vector3, outward: Vector3, arrow_hit: bool) -> void:
	var anchor := contact_anchor(actor, point)
	if anchor.is_empty():
		return
	var pose: Transform3D = anchor.pose
	var local_point := pose.affine_inverse() * point
	var normal: Vector3 = (point - anchor.center).normalized()
	if normal.is_zero_approx():
		normal = outward.normalized()
	if normal.is_zero_approx():
		normal = -actor.global_basis.z
	var local_normal := pose.basis.inverse() * normal
	var horse: bool = actor.mounted and not String(anchor.bone).begins_with("Rider")
	var body := body_mesh(actor, horse)
	if not body:
		return
	var bind := bind_transform(body, actor.skeleton, anchor.index, anchor.bone)
	var hit := lookup_uv(body.mesh, bind * local_point, (bind.basis * local_normal).normalized(), .11 if arrow_hit else .17)
	if hit.is_empty():
		return
	if row == 0:
		texture()
		if free_rows.is_empty() and next_row >= ROW_COUNT:
			return
		row = free_rows.pop_back() if not free_rows.is_empty() else next_row
		if row == next_row:
			next_row += 1
	var surface := surface_id(body, hit.surface, actor.mounted)
	var uv: Vector2 = hit.uv
	var axes: Color = hit.axes
	atlas_image.set_pixel(next_stamp * 2, row, Color(uv.x, uv.y, float(surface), 1.0))
	atlas_image.set_pixel(next_stamp * 2 + 1, row, axes)
	next_stamp = (next_stamp + 1) % MAX_WOUNDS
	if not upload_pending:
		upload_pending = true
		actor.get_tree().process_frame.connect(flush_atlas, CONNECT_ONE_SHOT)
	if not wounded_surfaces.has(body):
		wounded_surfaces[body] = {}
	wounded_surfaces[body][hit.surface] = surface
	# The crowd shader reads the atlas directly. Bind its detailed counterpart
	# when the rig is visible so distant hits do not compile unused materials.
	if body.is_visible_in_tree():
		bind_surface(body, hit.surface, surface)

static func body_mesh(actor: CharacterBody3D, horse: bool) -> MeshInstance3D:
	var body_name := ("Horse" if horse else "Mounted warrior") if actor.mounted else "*"
	for candidate: MeshInstance3D in actor.model.find_children("*", "MeshInstance3D", true, false):
		if body_name == "*" or candidate.name == body_name:
			return candidate
	return null

func restore_materials() -> void:
	for body: MeshInstance3D in wounded_surfaces:
		for surface: int in wounded_surfaces[body]:
			bind_surface(body, surface, wounded_surfaces[body][surface])

func bind_surface(body: MeshInstance3D, surface: int, shader_surface: int) -> void:
	var base := body.get_active_material(surface)
	if not base:
		return
	var key := [base, shader_surface]
	if not materials.has(key):
		var overlay := ShaderMaterial.new()
		overlay.shader = OVERLAY_SHADER
		overlay.set_shader_parameter(&"body_wound_data", atlas_texture)
		overlay.set_shader_parameter(&"body_wound_surface", shader_surface)
		var wrapped: Material = base.duplicate()
		wrapped.next_pass = overlay
		wrapped.set_meta(&"body_wound_base", base_material(base))
		materials[key] = wrapped
		materials[[wrapped, shader_surface]] = wrapped
	var material: Material = materials[key]
	if body.get_surface_override_material(surface) != material:
		body.set_surface_override_material(surface, material)
		body.set_instance_shader_parameter(&"body_wound_row", row)

func contact_anchor(actor: CharacterBody3D, point: Vector3) -> Dictionary:
	if anchor_segments.is_empty():
		var names := {}
		for index in actor.skeleton.get_bone_count():
			var imported: String = actor.skeleton.get_bone_name(index)
			names[imported.replace(":", "").replace("_", "")] = index
		var segments := MOUNTED_SEGMENTS if actor.mounted else FOOT_SEGMENTS
		var prefix := "" if actor.mounted else "mixamorig"
		for segment in segments:
			anchor_segments.append(names.get(prefix + segment[0], -1))
			anchor_segments.append(names.get(prefix + segment[1], -1))
	var distance := INF
	var best := {}
	for index in range(0, anchor_segments.size(), 2):
		var start := anchor_segments[index]
		var end := anchor_segments[index+1]
		if start < 0 or end < 0:
			continue
		var pose := world_bone(actor, start)
		var end_point := world_bone(actor, end).origin
		var center := Geometry3D.get_closest_point_to_segment(point, pose.origin, end_point)
		var separation := center.distance_squared_to(point)
		if separation < distance:
			distance = separation
			best = {"index": start, "bone": actor.skeleton.get_bone_name(start), "pose": pose, "center": center}
	return best

func arrow_anchor(actor: CharacterBody3D, point: Vector3) -> Dictionary:
	var anchor := contact_anchor(actor, point)
	if anchor.is_empty() or (actor.mounted and not String(anchor.bone).begins_with("Rider")):
		return {}
	var body := body_mesh(actor, false)
	if not body:
		return {}
	var normal: Vector3 = (point - anchor.center).normalized()
	if normal.is_zero_approx():
		return {}
	# The combat ray hits the capsule. Confirm a nearby surface on the warrior mesh.
	var pose: Transform3D = anchor.pose
	var to_mesh := bind_transform(body, actor.skeleton, anchor.index, anchor.bone) * pose.affine_inverse()
	var bvh: TriangleMesh = geometry(body.mesh).bvh
	var hit := bvh.intersect_segment(to_mesh * (point + normal * .15), to_mesh * (point - normal * .35))
	if hit.is_empty():
		return {}
	anchor.tip = to_mesh.affine_inverse() * hit.position - normal * .045
	return anchor

func world_bone(actor: CharacterBody3D, index: int, rendered := false) -> Transform3D:
	if actor.crowd_visual and actor.crowd_visual.distant:
		var name: String = actor.skeleton.get_bone_name(index)
		if rendered: return actor.render_model_transform() * actor.crowd_visual.bone_transform(name)
		return actor.global_transform * actor.crowd_visual.bone_transform(name)
	if rendered: return actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(index)
	var skeleton_in_actor: Transform3D = actor.model.transform.affine_inverse() * actor.global_transform.affine_inverse() * actor.skeleton.global_transform
	return actor.global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * skeleton_in_actor * actor.skeleton.get_bone_global_pose(index)

static func bind_transform(body: MeshInstance3D, skeleton: Skeleton3D, bone_index: int, bone_name: StringName) -> Transform3D:
	var skin := body.skin
	if skin:
		if not skin_binds.has(skin):
			var binds := {}
			for i in skin.get_bind_count():
				var name := skin.get_bind_name(i)
				var key: Variant = name if not name.is_empty() else skin.get_bind_bone(i)
				binds[key] = skin.get_bind_pose(i).affine_inverse()
			skin_binds[skin] = binds
		var binds: Dictionary = skin_binds[skin]
		if binds.has(bone_name):
			return binds[bone_name]
		if binds.has(bone_index):
			return binds[bone_index]
	return body.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(bone_index)

static func geometry(mesh: Mesh) -> Dictionary:
	var key := mesh.get_instance_id()
	if mesh_queries.has(key):
		return mesh_queries[key]
	var points := PackedVector3Array()
	var uv := PackedVector2Array()
	var surfaces := PackedInt32Array()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var coords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if coords.is_empty():
			continue
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for i in count:
			var index := indices[i] if not indices.is_empty() else i
			points.append(vertices[index])
			uv.append(coords[index])
		for triangle in range(count / 3):
			surfaces.append(surface)
	var bvh := TriangleMesh.new()
	bvh.create_from_faces(points)
	var result := {"bvh": bvh, "points": points, "uv": uv, "surfaces": surfaces}
	mesh_queries[key] = result
	return result

static func lookup_uv(mesh: Mesh, point: Vector3, direction: Vector3, size: float) -> Dictionary:
	var data := geometry(mesh)
	var bvh: TriangleMesh = data.bvh
	var hit := bvh.intersect_segment(point + direction * .42, point - direction * .37)
	if hit.is_empty():
		for axis in [Vector3.UP, Vector3.RIGHT, Vector3.FORWARD]:
			var contender := bvh.intersect_segment(point + axis * .24, point - axis * .24)
			if not contender.is_empty() and (hit.is_empty() or point.distance_squared_to(contender.position) < point.distance_squared_to(hit.position)):
				hit = contender
	if hit.is_empty():
		return {}
	var vertex: int = hit.face_index * 3
	var a: Vector3 = data.points[vertex]
	var b: Vector3 = data.points[vertex + 1]
	var c: Vector3 = data.points[vertex + 2]
	var ua: Vector2 = data.uv[vertex]
	var ub: Vector2 = data.uv[vertex + 1]
	var uc: Vector2 = data.uv[vertex + 2]
	var tangent: Vector3 = hit.normal.cross(Vector3.UP).normalized()
	if tangent.is_zero_approx():
		tangent = (b - a).normalized()
	var bitangent: Vector3 = tangent.cross(hit.normal).normalized()
	var center := triangle_uv(Geometry3D.get_triangle_barycentric_coords(hit.position, a, b, c), ua, ub, uc)
	var axis_u := triangle_uv(Geometry3D.get_triangle_barycentric_coords(hit.position + tangent * size, a, b, c), ua, ub, uc) - center
	var axis_v := triangle_uv(Geometry3D.get_triangle_barycentric_coords(hit.position + bitangent * size, a, b, c), ua, ub, uc) - center
	if absf(axis_u.cross(axis_v)) < .0000001:
		return {}
	return {"surface": data.surfaces[hit.face_index], "uv": center, "axes": Color(axis_u.x, axis_u.y, axis_v.x, axis_v.y)}

static func triangle_uv(weights: Vector3, a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	return a * weights.x + b * weights.y + c * weights.z
