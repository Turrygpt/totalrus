extends SkeletonModifier3D

var actor: CharacterBody3D
var terrain: Node3D
var legs: Array[Vector4i] = []
var contact_height := Vector2.ZERO

static func contact_reference(archer: bool) -> Vector2:
	return Vector2(.14, .07) if archer else Vector2(.105, .035)

static func bone_index(names: Array, suffix: String) -> int:
	for i in names.size():
		if String(names[i]).ends_with(suffix): return i
	return -1

static func configure_material(material: ShaderMaterial, bank: Resource) -> void:
	if bank.has_meta("full_model"): return
	var names: Array = bank.get_meta("bone_names")
	for side in ["Left", "Right"]:
		var leg := Vector3i(bone_index(names, side + "Leg"), bone_index(names, side + "Foot"),
			bone_index(names, side + "ToeBase"))
		if leg.x < 0 or leg.y < 0 or leg.z < 0: return
		material.set_shader_parameter("foot_" + side.to_lower(), leg)
	material.set_shader_parameter("foot_contact_height", contact_reference(bank.get_meta("clips").has("bow_idle")))

func _init(infantry: CharacterBody3D, ground: Node3D) -> void:
	actor = infantry
	terrain = ground
	contact_height = contact_reference(actor.crowd_kind() == "archer")
	var names := []
	for i in actor.skeleton.get_bone_count():
		names.append(actor.skeleton.get_bone_name(i))
	for side in ["Left", "Right"]:
		var leg := Vector4i(bone_index(names, side + "UpLeg"), bone_index(names, side + "Leg"),
			bone_index(names, side + "Foot"), bone_index(names, side + "ToeBase"))
		if leg.x >= 0 and leg.y >= 0 and leg.z >= 0 and leg.w >= 0: legs.append(leg)

func _process_modification_with_delta(_delta: float) -> void:
	if not actor.alive or not actor.model.is_visible_in_tree() or not is_instance_valid(terrain): return
	var rig := get_skeleton()
	var center: Vector3 = actor.model.global_position
	var base_height: float = terrain.height_at(Vector2(center.x, center.z))
	var rig_to_world := rig.global_transform
	var local_up := rig_to_world.basis.inverse() * Vector3.UP
	for leg in legs:
		var boot := rig.get_bone_global_pose(leg.z)
		var ankle := rig_to_world * boot.origin
		var toe := rig_to_world * rig.get_bone_global_pose(leg.w).origin
		var clearance := minf(ankle.y - contact_height.x, toe.y - contact_height.y) - center.y
		var contact := 1.0 - smoothstep(.025, .095, clearance)
		if contact <= 0.0: continue
		var step := ankle.lerp(toe, .55)
		var height: float = terrain.height_at(Vector2(step.x, step.z))
		var offset := clampf(height - base_height, -.18, .22) * contact
		if absf(offset) < .001: continue
		plant_leg(rig, leg, boot, local_up * offset)

static func plant_leg(rig: Skeleton3D, leg: Vector4i, boot: Transform3D, offset: Vector3) -> void:
	var thigh := rig.get_bone_global_pose(leg.x)
	var shin := rig.get_bone_global_pose(leg.y)
	var upper := shin.origin - thigh.origin
	var lower := boot.origin - shin.origin
	var a := upper.length()
	var b := lower.length()
	if minf(a, b) < .001: return
	var span := boot.origin + offset - thigh.origin
	if span.length_squared() < .000001: return
	var axis := span.normalized()
	var distance := clampf(span.length(), absf(a - b) + .0001, a + b - .0001)
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var bend := upper.slide(axis)
	if bend.length_squared() < .000001:
		bend = thigh.basis.x.slide(axis)
	var knee := thigh.origin + axis * along + bend.normalized() * sqrt(maxf(0.0, a * a - along * along))
	boot.origin = thigh.origin + axis * distance
	thigh.basis = Basis(Quaternion(upper.normalized(), (knee - thigh.origin).normalized())) * thigh.basis
	shin.basis = Basis(Quaternion(lower.normalized(), (boot.origin - knee).normalized())) * shin.basis
	shin.origin = knee
	rig.set_bone_global_pose(leg.x, thigh)
	rig.set_bone_global_pose(leg.y, shin)
	rig.set_bone_global_pose(leg.z, boot)
