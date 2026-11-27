extends RefCounted

static var cloth: ArrayMesh
static var rest_socket := Transform3D.IDENTITY

static func attach(rider: Node3D, index: int) -> MeshInstance3D:
	var skeleton := rider.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var spear := rider.find_child("Rider*spear", true, false) as MeshInstance3D
	var bone := skeleton.find_bone("SpearRoot")
	if bone < 0 or spear == null:
		return null
	if cloth == null:
		_make_cloth()
		rest_socket = _socket(skeleton, spear, bone)
	var tie := BoneAttachment3D.new()
	tie.bone_name = &"SpearRoot"
	skeleton.add_child(tie)
	var flag := MeshInstance3D.new()
	flag.name = "SpearPennon"
	flag.mesh = cloth
	flag.transform = rest_socket
	flag.extra_cull_margin = .15
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tie.add_child(flag)
	flag.set_instance_shader_parameter("phase", index * .73)
	flag.set_instance_shader_parameter("cloth_color", [Color("#a0473e"), Color("#3c6c87"), Color("#ad8551")][index % 3])
	return flag

static func _socket(skeleton: Skeleton3D, spear: MeshInstance3D, bone: int) -> Transform3D:
	var points: PackedVector3Array = spear.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rest := skeleton.get_bone_global_rest(bone)
	var map := rest.affine_inverse() * skeleton.global_transform.affine_inverse() * spear.global_transform
	for bind in spear.skin.get_bind_count():
		if spear.skin.get_bind_name(bind) == &"SpearRoot" or spear.skin.get_bind_bone(bind) == bone:
			map = spear.skin.get_bind_pose(bind)
			break
	var box := spear.mesh.get_aabb()
	var top := Vector3.ZERO
	var bottom := Vector3.ZERO
	var top_count := 0
	var bottom_count := 0
	for point in points:
		if point.y > box.end.y - box.size.y * .085:
			top += map * point
			top_count += 1
		if point.y < box.position.y + box.size.y * .085:
			bottom += map * point
			bottom_count += 1
	top /= maxi(1, top_count)
	bottom /= maxi(1, bottom_count)
	var shaft := bottom.direction_to(top)
	var backward := rest.basis.inverse() * Vector3.FORWARD
	var trailing := (backward - shaft * shaft.dot(backward)).normalized()
	var size := 1.0 / skeleton.global_basis.get_scale().y
	var frame := Basis(trailing, shaft, trailing.cross(shaft)).scaled(Vector3.ONE * size)
	var tie := top - shaft * .24 * size
	return Transform3D(frame, tie)

static func _make_cloth() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(10):
		var a := float(i) / 10.0
		var b := float(i + 1) / 10.0
		var t := Vector2(a, 0)
		var u := Vector2(b, 0)
		var v := Vector2(a, 1)
		var w := Vector2(b, 1)
		for uv: Vector2 in [t, u, v, v, u, w]:
			surface.set_uv(uv)
			surface.set_normal(Vector3.BACK)
			surface.add_vertex(Vector3(uv.x * .34, (.5 - uv.y) * (.14 - .13 * uv.x), 0))
	cloth = surface.commit()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;
instance uniform vec4 cloth_color : source_color = vec4(.38, .12, .08, 1.0);
instance uniform float flutter = 0.0;
instance uniform float phase = 0.0;
varying float fold;
void vertex() {
	float t = UV.x;
	fold = sin(TIME * 10.5 - t * 11.0 + phase) * (.18 + flutter * .82);
	VERTEX.z += fold * .048 * t;
	VERTEX.y -= t * t * (.092 - flutter * .071);
	VERTEX.y += sin(TIME * 7.0 - t * 8.0 + phase) * .024 * flutter * t;
}
void fragment() {
	ALBEDO = cloth_color.rgb * (.92 + .16 * fold);
	ROUGHNESS = .92;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	cloth.surface_set_material(0, material)
