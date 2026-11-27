extends RefCounted

const Soldier = preload("res://scripts/soldier.gd")

static func make(soldier: Soldier) -> AnimationLibrary:
	var skeleton := soldier.skeleton
	soldier.play_clip("guard_front", 0.0)
	soldier.player.advance(0.0)
	var hips := _bone(skeleton, "Hips")
	var spine := _bone(skeleton, "Spine")
	var legs: Array[Dictionary] = []
	for side in ["Left", "Right"]:
		var thigh := _bone(skeleton, side + "UpLeg")
		var knee := _bone(skeleton, side + "Leg")
		var foot := _bone(skeleton, side + "Foot")
		legs.append({
			"thigh": thigh, "knee": knee, "foot": foot,
			"upper": skeleton.get_bone_global_pose(thigh),
			"lower": skeleton.get_bone_global_pose(knee),
			"boot": skeleton.get_bone_global_pose(foot),
		})
	var pelvis := skeleton.get_bone_global_pose(hips)
	pelvis.origin += Vector3(0.0, -.082, .009)
	skeleton.set_bone_global_pose(hips, pelvis)
	var upper_body := skeleton.get_bone_global_pose(spine)
	upper_body.basis = Basis(Vector3.RIGHT, .15) * upper_body.basis
	skeleton.set_bone_global_pose(spine, upper_body)
	for leg in legs:
		_plant_leg(skeleton, leg)

	var animation := Animation.new()
	animation.length = 1.0
	animation.loop_mode = Animation.LOOP_LINEAR
	var player_root := soldier.player.get_node(soldier.player.root_node)
	var skeleton_path := player_root.get_path_to(skeleton)
	for bone in skeleton.get_bone_count():
		var path := NodePath(str(skeleton_path) + ":" + skeleton.get_bone_name(bone))
		var translation := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(translation, path)
		animation.position_track_insert_key(translation, 0.0, skeleton.get_bone_pose_position(bone))
		var rotation := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(rotation, path)
		animation.rotation_track_insert_key(rotation, 0.0, skeleton.get_bone_pose_rotation(bone).normalized())
	var library := AnimationLibrary.new()
	library.add_animation(&"brace_spear", animation)
	return library

static func _bone(skeleton: Skeleton3D, name: String) -> int:
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_name(index).replace(":", "").replace("_", "") == "mixamorig" + name:
			return index
	return -1

static func _plant_leg(skeleton: Skeleton3D, leg: Dictionary) -> void:
	var upper: Transform3D = leg.upper
	var lower: Transform3D = leg.lower
	var boot: Transform3D = leg.boot
	var root := skeleton.get_bone_global_pose(leg.thigh).origin
	var span := boot.origin - root
	var axis := span.normalized()
	var length_a := upper.origin.distance_to(lower.origin)
	var length_b := lower.origin.distance_to(boot.origin)
	var distance := minf(span.length(), length_a + length_b - .0001)
	var along := (length_a * length_a - length_b * length_b + distance * distance) / (2.0 * distance)
	var bend := Vector3.BACK
	bend = (bend - axis * bend.dot(axis)).normalized()
	var knee := root + axis * along + bend * sqrt(maxf(0.0, length_a * length_a - along * along))
	var upper_turn := Quaternion((lower.origin - upper.origin).normalized(), (knee - root).normalized())
	var lower_turn := Quaternion((boot.origin - lower.origin).normalized(), (boot.origin - knee).normalized())
	skeleton.set_bone_global_pose(leg.thigh, Transform3D(Basis(upper_turn) * upper.basis, root))
	skeleton.set_bone_global_pose(leg.knee, Transform3D(Basis(lower_turn) * lower.basis, knee))
	skeleton.set_bone_global_pose(leg.foot, boot)
