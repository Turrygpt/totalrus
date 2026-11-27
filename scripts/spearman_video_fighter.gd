extends "res://scripts/soldier.gd"

const VIDEO_LUNGE := preload("res://assets/spearman_video_lunge.tres")
const VIDEO_CHARGE := preload("res://assets/spearman_video_charge.tres")
const ATTACK := "attack_spear_video"
const CONTACT_TIME := .42
const AIM_YAWS := [0.0, 4.0, 8.0]
const AIM_PITCH := -7.3
# Apex of the blade in the coordinate space of the existing spear scene.
const SPEAR_TIP := Vector3(-.002971, 1.30988, .002294)

static var aimed_clips: Array[Animation] = []
var actor_skeleton: Transform3D
var skeleton_path: String
var contact_grips: Array[Vector3] = []
var contact_tips: Array[Vector3] = []
var current_aim := 1
var video_attack_only := false

func use_sword_animation_pack() -> void:
	super.use_sword_animation_pack()
	var animation_root := player.get_node(player.root_node)
	skeleton_path = String(animation_root.get_path_to(skeleton))
	actor_skeleton = global_transform.affine_inverse() * skeleton.global_transform
	if aimed_clips.is_empty():
		for yaw: float in AIM_YAWS:
			aimed_clips.append(make_aim_variant(yaw))
	var library := AnimationLibrary.new()
	library.add_animation(&"charge", VIDEO_CHARGE)
	for i in aimed_clips.size():
		library.add_animation("lunge_%d" % i, aimed_clips[i])
	player.add_animation_library(&"video", library)
	animation_map["charge_spear"] = &"video/charge"
	animation_map[ATTACK] = &"video/lunge_1"

func make_animation_events() -> void:
	super.make_animation_events()
	for clip in aimed_clips:
		var grip := actor_skeleton * SPEAR_COMBAT.sample_bone_chain(skeleton, skeleton_path, clip, skeleton.find_bone(right_socket.bone_name), CONTACT_TIME)
		contact_grips.append(grip.origin)
		contact_tips.append(grip * spear.transform * SPEAR_TIP)

func spear_attack_pool() -> Array[String]:
	if video_attack_only:
		return [ATTACK]
	var attacks := super.spear_attack_pool()
	attacks.append(ATTACK)
	return attacks

func start_strike(action: String, speed: float) -> void:
	if action == ATTACK:
		current_aim = choose_aim()
		animation_map[ATTACK] = "video/lunge_%d" % current_aim
	super.start_strike(action, speed)
	if action == ATTACK: strike_impact_time = CONTACT_TIME

func choose_aim() -> int:
	var target := to_local(combat_target.global_position) if is_instance_valid(combat_target) else Vector3.FORWARD
	var lateral := target.x + rng.randf_range(-.14, .14)
	var best := 0
	var best_error := INF
	for i in contact_tips.size():
		var grip := contact_grips[i]
		var tip := contact_tips[i]
		var depth := clampf(inverse_lerp(grip.z, tip.z, target.z), 0.0, 1.0)
		var error := absf(lerpf(grip.x, tip.x, depth) - lateral)
		if error < best_error:
			best = i
			best_error = error
	return best

func make_aim_variant(yaw: float) -> Animation:
	var clip := VIDEO_LUNGE.duplicate() as Animation
	var arm := skeleton.find_bone("mixamorig_RightArm")
	var parent := skeleton.get_bone_parent(arm)
	var path := NodePath(skeleton_path + ":" + skeleton.get_bone_name(arm))
	var track := clip.find_track(path, Animation.TYPE_ROTATION_3D)
	for key in clip.track_get_key_count(track):
		var time := clip.track_get_key_time(track, key)
		var weight := smoothstep(.12, .34, time) * (1.0 - smoothstep(.96, 1.32, time))
		if weight == 0.0:
			continue
		# Aim from the shoulder so the wrist, spear and elbow keep their relative pose.
		var parent_basis := (actor_skeleton * SPEAR_COMBAT.sample_bone_chain(skeleton, skeleton_path, VIDEO_LUNGE, parent, time)).basis.orthonormalized()
		var adjustment := Basis(Vector3.UP, deg_to_rad(yaw * weight)) * Basis(Vector3.RIGHT, deg_to_rad(AIM_PITCH * weight))
		var original: Quaternion = clip.track_get_key_value(track, key)
		var rotation := parent_basis.inverse() * adjustment * parent_basis * Basis(original)
		clip.track_set_key_value(track, key, rotation.get_rotation_quaternion())
	return clip

