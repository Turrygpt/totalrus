extends RefCounted
## Authored contact data and inexpensive, LOD-independent shield coverage.
const DATA_PATH := "res://assets/spear_combat.json"
const THRUST_SAMPLES := [.16, .20, .24, .28, .32, .36, .40, .44, .48, .52]
static var data: Dictionary = {}
static var attacks: Dictionary = {}

static func definitions() -> Dictionary:
	if data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if not parsed is Dictionary:
			push_error("Cannot load authored spear combat data: " + DATA_PATH)
			return {}
		data = parsed
		for i in data.get("attacks", []).size():
			attacks["attack_spear_%02d" % (i + 1)] = data.attacks[i]
	return data

static func attack_names() -> Array[String]:
	definitions()
	var result: Array[String] = []
	result.assign(attacks.keys())
	return result

static func attack(alias: String) -> Dictionary:
	definitions()
	return attacks.get(alias, {})

static func contacts(alias: String) -> Array:
	return attack(alias).get("contacts", [])

static func is_attack(alias: String) -> bool:
	return not attack(alias).is_empty()

static func actor_point(blender_point: Array) -> Vector3:
	# glTF's Z-up conversion followed by the model's existing PI turn.
	return Vector3(-float(blender_point[0]), float(blender_point[2]), float(blender_point[1]))

static func contact_ray(attacker: Node3D, victim: Node3D, contact: Dictionary) -> Dictionary:
	var reference: Array = definitions().get("targeting", {}).get("defender_position", [0, -1.85, 0])
	var authored: Array = contact.position
	# Point in the defender's frame; shield coverage changes when they turn.
	var local_target := Vector3(float(authored[0]), float(authored[2]), -float(authored[1]) + float(reference[1]))
	var origin: Vector3 = attacker.global_transform * actor_point(contact.grip_position)
	var point: Vector3 = victim.global_transform * local_target
	return {"origin": origin, "point": point, "zone": contact.zone,
		"kind": contact.kind, "reach": float(contact.reach)}

static func sample_bone_chain(skeleton: Skeleton3D, skeleton_path: String, clip: Animation, bone: int, time: float) -> Transform3D:
	var transform := Transform3D.IDENTITY
	while bone >= 0:
		var path := NodePath(skeleton_path + ":" + skeleton.get_bone_name(bone))
		var pose := skeleton.get_bone_rest(bone)
		var position_track := clip.find_track(path, Animation.TYPE_POSITION_3D)
		var rotation_track := clip.find_track(path, Animation.TYPE_ROTATION_3D)
		if position_track >= 0:
			pose.origin = clip.position_track_interpolate(position_track, time)
		if rotation_track >= 0:
			pose.basis = Basis(clip.rotation_track_interpolate(rotation_track, time))
		transform = pose * transform
		bone = skeleton.get_bone_parent(bone)
	return transform

static func visible_contact(attacker: CharacterBody3D, victim: CharacterBody3D, origin: Vector3, tip: Vector3) -> Dictionary:
	if origin.distance_squared_to(tip) < .000001:
		return {}
	var query := PhysicsRayQueryParameters3D.create(origin, tip, 2, [attacker.get_rid()])
	var hit := attacker.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != victim:
		return {}
	var point: Vector3 = hit.get("position", tip)
	var shield := shield_intersection(victim, origin, point)
	if hit.is_empty() and shield.is_empty():
		return {}
	var surface: Vector3 = shield.get("point", point)
	var fraction := clampf(origin.distance_to(surface) / maxf(.0001, origin.distance_to(tip)), 0.0, 1.0)
	return {"origin": origin, "point": point, "zone": "body", "fraction": fraction}

static func shield_intersection(victim: CharacterBody3D, origin: Vector3, point: Vector3) -> Dictionary:
	if not victim.has_shield(): return {}
	var ready: bool = victim.guarding or victim.shield_raised or (victim.attack_order and victim.motion_speed < 2.4)
	if not ready: return {}
	var incoming := origin - victim.global_position
	incoming.y = 0
	var profile: Dictionary = definitions().get("shield_profile", {})
	if incoming.length_squared() < .00001 or (-victim.global_basis.z).dot(incoming.normalized()) <= float(profile.get("front_threshold", .35)): return {}
	# Ellipsoid measured from the round shield, including rim and thickness.
	# It works identically when the rendered skeleton is frozen for crowd LOD.
	var center_data: Array = profile.get("center", [-.309, 1.106, -.367])
	var radii_data: Array = profile.get("radii", [.349, .386, .115])
	var center := Vector3(center_data[0], center_data[1], center_data[2])
	var radii := Vector3(radii_data[0], radii_data[1], radii_data[2])
	if victim.has_kite_shield():
		center.y -= .07
		radii.x *= .76
		radii.y *= 1.18
	if victim.guarding: center.y += .08
	if victim.mounted: center.y += 1.1
	var inverse := victim.global_transform.affine_inverse()
	var a := (inverse * origin - center) / radii
	var b := (inverse * point - center) / radii
	var delta := b - a
	var aa := delta.dot(delta)
	if aa < .000001: return {}
	var bb := 2.0 * a.dot(delta)
	var cc := a.dot(a) - 1.0
	var discriminant := bb * bb - 4.0 * aa * cc
	if discriminant < 0: return {}
	var fraction := (-bb - sqrt(discriminant)) / (2.0 * aa)
	if cc <= 0: fraction = 0.0
	if fraction < 0 or fraction > 1.0: return {}
	return {"point": origin.lerp(point, fraction), "fraction": fraction}
