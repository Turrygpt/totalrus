extends "res://scripts/archer.gd"

const CHARGE = preload("res://scripts/cavalry_charge.gd")
const MOUNT = preload("res://assets/khazar_mounted.glb")
const SABRE = preload("res://assets/khazar_sabre.glb")
const RIDING_BOW = preload("res://assets/khazar_bow.glb")
const MOUNT_HEALTH_MULTIPLIER := 1.064
const SABRE_IMPACT_PHASE := .46
const SABRE_DAMAGE_MULTIPLIER := 1.20

func _ready() -> void:
	mounted = true
	detail_cost = 3
	super._ready()
	max_hp = rng.randf_range(96.0, 111.0) * MOUNT_HEALTH_MULTIPLIER
	hp = max_hp
	aim_spine = skeleton.find_bone("RiderChest")
	for child in get_children():
		if child is CollisionShape3D:
			var capsule := CapsuleShape3D.new()
			capsule.radius = .64
			capsule.height = 2.65
			child.shape = capsule
			child.position.y = capsule.height * .5
	agent.radius = .85

func warrior_scene() -> PackedScene:
	return MOUNT

func crowd_kind() -> String:
	return "khazar"

func melee_weapon_scene() -> PackedScene:
	return SABRE

func bow_scene() -> PackedScene:
	return RIDING_BOW

func bow_grip_offset() -> Vector3:
	return Vector3(-.10, 0, 0)

func bow_back_shift() -> Vector3:
	# BowBack is tilted, so lifting along the rider's back uses both socket axes.
	return Vector3(-.30, 0, .53)

func bow_string_knot(top: bool) -> Vector3:
	return Vector3(.178,.444,0) if top else Vector3(.176,-.454,0)

func equipment_scale() -> float:
	return 1.0 / .395

func firing_height() -> float:
	return 2.24

func retreat_speed() -> float:
	return attack_run_speed()

func attack_run_speed() -> float:
	return CHARGE.KHAZAR_RUN_SPEED

func weapon_reach() -> float:
	return 1.85

func melee_damage_scale() -> float:
	return super.melee_damage_scale() * SABRE_DAMAGE_MULTIPLIER

func apply_appearance() -> void:
	var rider := model.find_child("Mounted warrior", true, false) as MeshInstance3D
	rider.set_surface_override_material(0, TroopColors.dye(rider.get_active_material(0),
		uniform_color(), TroopColors.Fabric.KHAZAR))
	TroopColors.dye_saddle(model, uniform_color())

func use_sword_animation_pack() -> void:
	var names := {
		"bow_idle":"Idle", "bow_walk":"Walk", "bow_run":"Gallop",
		"bow_backstep":"Walk", "bow_retreat":"Gallop", "bow_left":"Walk", "bow_right":"Walk",
		"bow_draw":"RiderDraw", "bow_aim":"RiderAim", "bow_release":"RiderLoose", "bow_hit":"ReadyIdle",
		"bow_death":"Death", "bow_death_front":"DeathProne", "bow_victory":"Rear",
		"knife_idle":"ReadyIdle", "knife_walk":"ReadyWalk", "knife_run":"ReadyGallop",
		"knife_draw":"ReadyIdle", "knife_attack":"RiderSabre",
	}
	for name: String in names:
		animation_map[name] = names[name]
	super.use_sword_animation_pack()
	player.get_animation(animation_map["knife_walk"]).loop_mode = Animation.LOOP_LINEAR
	animation_map["mount_death_side"] = &"DeathSide"
	for clip in ["Rear", "Death", "DeathSide", "DeathProne", "RiderDraw", "RiderLoose", "RiderSabre"]:
		player.get_animation(clip).loop_mode = Animation.LOOP_NONE

func start_strike(action: String, speed: float) -> void:
	super.start_strike(action, speed)
	strike_duration = player.get_animation(animation_map[action]).length
	strike_impact_time = strike_duration * SABRE_IMPACT_PHASE

func take_sword() -> void:
	super.take_sword()
	sword.scale = Vector3.ONE * equipment_scale()

func order_move(destination: Vector3, heading: float, speed: float, defend: bool, front: bool) -> void:
	super.order_move(destination, heading, attack_run_speed() if speed > 3.0 else 2.0, defend, front)

func combat_heading(offset: Vector3) -> float:
	var heading := super.combat_heading(offset)
	if sword_drawn and offset.length_squared() <= 9.0 and absf(angle_difference(final_heading, heading)) < .14:
		return final_heading
	return heading

func is_gait(clip: String) -> bool:
	return clip == "knife_walk" or super.is_gait(clip)

func update_motion_animation(distance: float, facing_enemy: bool) -> void:
	if animation_clock > 0.0:
		return
	if sword_drawn and facing_enemy:
		var step_threshold := .22 if animation_name == "knife_walk" else .44
		if motion_speed <= step_threshold:
			play_clip("knife_idle")
			return
	if motion_speed > .18:
		var galloping := motion_speed > 3.5
		if galloping:
			play_clip("knife_run" if sword_drawn else ("bow_retreat" if retreating or fleeing else "bow_run"))
		else:
			play_clip("knife_walk" if sword_drawn else "bow_walk")
		player.speed_scale = clampf(motion_speed / (attack_run_speed() if galloping else 2.0), .16, 1.2)
	else:
		super.update_motion_animation(distance, facing_enemy)

func flee(destination: Vector3, heading: float) -> void:
	super.flee(destination, heading)
	speed_limit = retreat_speed()

func death_clip() -> String:
	return ["bow_death", "mount_death_side", "bow_death_front"][rng.randi_range(0, 2)]
