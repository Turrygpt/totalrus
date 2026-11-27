extends Node3D

const CLOTH_SHADER = preload("res://assets/squad_standard_3d.gdshader")
const CLOTH_HEIGHT := 1.25
const CLOTH_CENTER := Vector3(0, 2.20, -.025)
const READABILITY_START := 55.0
const READABILITY_END := 215.0
var bearer: CharacterBody3D
var fabric: MeshInstance3D
var fabric_material: ShaderMaterial
var morale_signal := 0

func configure(texture: Texture2D, tint: Color) -> void:
	var shaft := CylinderMesh.new()
	shaft.height = 2.7
	shaft.top_radius = .018
	shaft.bottom_radius = .026
	shaft.radial_segments = 7
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("674829")
	wood.roughness = .87
	shaft.material = wood
	var pole := MeshInstance3D.new()
	pole.mesh = shaft
	pole.position.y = 1.35
	add_child(pole)
	var cloth := PlaneMesh.new()
	cloth.orientation = PlaneMesh.FACE_Z
	cloth.subdivide_width = 8
	cloth.subdivide_depth = 12
	cloth.size = Vector2(CLOTH_HEIGHT * texture.get_width() / texture.get_height(), CLOTH_HEIGHT)
	fabric_material = ShaderMaterial.new()
	fabric_material.shader = CLOTH_SHADER
	fabric_material.set_shader_parameter("heraldry", texture)
	fabric_material.set_shader_parameter("cloth_tint", tint)
	cloth.material = fabric_material
	fabric = MeshInstance3D.new()
	fabric.mesh = cloth
	fabric.position = CLOTH_CENTER
	add_child(fabric)

func show_morale(signal_level: int) -> void:
	if morale_signal == signal_level:
		return
	morale_signal = signal_level
	fabric_material.set_shader_parameter("morale_signal", morale_signal)

func follow(squad: Node3D, camera: Camera3D = null) -> void:
	if not is_instance_valid(bearer) or not bearer.alive or bearer.withdrawn:
		var candidate: CharacterBody3D
		var distance := INF
		var anchor: Vector3 = bearer.global_position if is_instance_valid(bearer) else squad.center()
		for soldier: CharacterBody3D in squad.members:
			if not soldier.alive:
				continue
			if soldier.is_sotnik:
				candidate = soldier
				break
			var delta: float = soldier.global_position.distance_squared_to(anchor)
			if delta < distance:
				distance = delta
				candidate = soldier
		bearer = candidate
		if not bearer:
			hide()
			return
		reparent(bearer, false)
		show()
	var offset := Vector3(-.23, 1.64 if bearer.mounted else .48, .23)
	var placement: Transform3D = bearer.render_transform() * Transform3D(Basis.IDENTITY, offset)
	if global_transform != placement:
		global_transform = placement
	if camera:
		update_cloth(placement, camera.global_position)

func update_cloth(placement: Transform3D, camera_position: Vector3) -> void:
	var to_camera := camera_position - placement * CLOTH_CENTER
	var clarity := smoothstep(READABILITY_START, READABILITY_END, to_camera.length())
	var size := lerpf(1.0, 2.4, clarity)
	to_camera.y = 0.0
	var yaw := 0.0
	if not to_camera.is_zero_approx():
		var direction := placement.basis.inverse() * to_camera.normalized()
		yaw = atan2(direction.x, direction.z)
	var center := CLOTH_CENTER + Vector3.UP * ((size - 1.0) * CLOTH_HEIGHT * .5)
	fabric.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, size, size)), center)

func contains_screen_point(camera: Camera3D, pointer: Vector2) -> bool:
	if not is_instance_valid(bearer) or not bearer.alive or not is_visible_in_tree():
		return false
	if camera.is_position_behind(fabric.global_position):
		return false
	var half: Vector2 = fabric.mesh.size * .5
	var outline := PackedVector2Array()
	for point in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		outline.append(camera.unproject_position(fabric.to_global(Vector3(point.x, point.y, 0))))
	return Geometry2D.is_point_in_polygon(pointer, outline)
