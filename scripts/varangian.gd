extends "res://scripts/soldier.gd"

const BODY = preload("res://assets/varangian_body.glb")
const GEAR = preload("res://assets/varangian_gear.glb")
const AXE_COUNT := 3
const SHIELD_COUNT := 6
const HEAVY_SWING_SCALE := 1.20
static var body_mesh: Mesh
static var body_skin: Skin
static var axes: Array[PackedScene] = []
static var swing_library: AnimationLibrary
static var axe_hand_offset := Transform3D.IDENTITY
static var axe_hand_center := Vector3.ZERO
var axe_variant := 0

func _ready() -> void:
	has_spear = false
	sword_drawn = true
	super._ready()
	play_clip("idle_sword", 0.0)

func crowd_kind() -> String:
	return "varangian"

func apply_appearance() -> void:
	if body_mesh == null:
		var source := BODY.instantiate()
		var imported: MeshInstance3D = source.find_children("*", "MeshInstance3D", true, false)[0]
		body_mesh = imported.mesh
		body_skin = imported.skin
		source.free()
	var body: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	body.mesh = body_mesh
	body.skin = body_skin
	body.set_surface_override_material(0, TroopColors.dye(body.get_active_material(0),
		uniform_color(), TroopColors.Fabric.VARANGIAN))

func setup_equipment() -> void:
	if axes.is_empty():
		var collection := GEAR.instantiate()
		for i in AXE_COUNT:
			var part := collection.get_node("Axe%02d" % (i + 1)).duplicate() as MeshInstance3D
			var root := Node3D.new()
			root.name = "Axe"
			root.add_child(part)
			part.owner = root
			var scene := PackedScene.new()
			scene.pack(root)
			axes.append(scene)
			root.free()
		collection.free()
	right_socket = make_socket("mixamorig:RightHand")
	if axe_hand_offset == Transform3D.IDENTITY:
		# Use the authored idle grip as a fixed offset from the hand.
		# The sword rig's separate GripRight track can shift during a run.
		player.play(animation_map["idle_sword"], 0.0)
		player.seek(.23, true)
		player.advance(0)
		skeleton.force_update_all_bone_transforms()
		var palm := skeleton.get_bone_global_pose(right_socket.bone_idx)
		var grip := skeleton.get_bone_global_pose(skeleton.find_bone("GripRight"))
		axe_hand_offset = palm.affine_inverse() * grip
		# Measure the closed fist once in the same reference pose as the offset.
		# Later instances have not sampled idle yet and would measure the rest pose.
		for digit in ["Index", "Middle", "Ring", "Pinky"]:
			for joint in [1, 3]:
				var bone := skeleton.find_bone("mixamorig_RightHand%s%d" % [digit, joint])
				axe_hand_center += (palm.affine_inverse() * skeleton.get_bone_global_pose(bone)).origin / 8.0
	shield = make_spear_shield(GEAR, SHIELD_COUNT)
	sword = axes[axe_variant].instantiate()
	make_socket("GripLeft").add_child(shield)
	right_socket.add_child(sword)
	for prop in [shield, sword]:
		prop.scale = Vector3.ONE / 1.8
		prop.rotation.x = PI / 2.0
	# The haft runs along local Y; point the cutting edge forward, away from the body.
	sword.rotate_object_local(Vector3.UP, deg_to_rad(55.0))
	# A slight cant follows the fist; leave some handle below the little finger.
	sword.rotate_object_local(Vector3.BACK, deg_to_rad(4.0))
	sword.transform = axe_hand_offset * sword.transform
	sword.position = axe_hand_center - sword.basis.y * .065

func use_sword_animation_pack() -> void:
	super.use_sword_animation_pack()
	if swing_library == null:
		swing_library = AnimationLibrary.new()
		swing_library.add_animation(&"chop", adapt_swing("attack_sword", .37, .24))
		swing_library.add_animation(&"hook", adapt_swing("attack_sword_alt", .17, -.18))
		swing_library.add_animation(&"shield_charge", adapt_charge_shield())
	player.add_animation_library(&"axe", swing_library)
	animation_map["attack_sword"] = &"axe/chop"
	animation_map["attack_sword_alt"] = &"axe/hook"
	animation_map["charge_sword"] = &"axe/shield_charge"

func adapt_charge_shield() -> Animation:
	var run := player.get_animation(animation_map["run_sword"])
	var charge := player.get_animation(animation_map["charge_sword"]).duplicate() as Animation
	# Keep the charge footwork and raised axe. Carry the shield with the
	# lower arm motion from the regular run so the helmet clears the rim.
	for track in range(charge.get_track_count() - 1, -1, -1):
		if is_shield_arm_track(charge.track_get_path(track)):
			charge.remove_track(track)
	for track in run.get_track_count():
		if not is_shield_arm_track(run.track_get_path(track)):
			continue
		run.copy_track(track, charge)
		var copied := charge.get_track_count() - 1
		for key in range(charge.track_get_key_count(copied) - 1, -1, -1):
			var time := run.track_get_key_time(track, key)
			charge.track_set_key_time(copied, key, time / run.length * charge.length)
	return charge

func is_shield_arm_track(path: NodePath) -> bool:
	var bone := String(path.get_concatenated_subnames())
	return bone.ends_with("LeftShoulder") or bone.ends_with("LeftArm") or bone.ends_with("LeftForeArm") \
		or bone.contains("LeftHand") or bone == "GripLeft"

func adapt_swing(action: String, impact_phase: float, wrist_turn: float) -> Animation:
	var base := player.get_animation(animation_map[action])
	var clip := base.duplicate() as Animation
	clip.length = base.length * HEAVY_SWING_SCALE
	for track in clip.get_track_count():
		var path := String(clip.track_get_path(track))
		for key in range(clip.track_get_key_count(track) - 1, -1, -1):
			var time := base.track_get_key_time(track, key)
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				var phase := time / base.length
				var swing := sin(PI * clampf((phase - impact_phase + .16) / .42, 0.0, 1.0))
				var pose: Quaternion = base.track_get_key_value(track, key)
				if path.ends_with("RightForeArm"):
					pose *= Quaternion(Vector3.RIGHT, wrist_turn * .55 * swing)
				elif path.ends_with("RightHand"):
					pose *= Quaternion(Vector3.RIGHT, wrist_turn * swing)
				elif path.ends_with("GripRight"):
					pose *= Quaternion(Vector3.FORWARD, wrist_turn * .32 * swing)
				clip.track_set_key_value(track, key, pose.normalized())
			clip.track_set_key_time(track, key, time * HEAVY_SWING_SCALE)
	return clip

func make_animation_events() -> void:
	super.make_animation_events()
	events.get_animation("attack_sword").track_set_key_time(0, 0, .60 * HEAVY_SWING_SCALE)
	events.get_animation("attack_sword_alt").track_set_key_time(0, 0, .14 * HEAVY_SWING_SCALE)

func weapon_reach() -> float:
	return 1.26

func drop_held_weapon(impulse: Vector3) -> void:
	release_death_weapon(sword, axes[axe_variant], sword.global_transform, impulse)
