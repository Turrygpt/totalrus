extends "res://scripts/soldier.gd"
const RIDER_MODEL=preload("res://assets/horseman_quaternius.glb")
const CHARGE = preload("res://scripts/cavalry_charge.gd")
const VIDEO_ATTACKS := preload("res://assets/mounted_spearman_video_strike.tres")
const SPEAR_CONTACT_TIME := .46
const GALLOP_STRIKE := &"video/gallop_strike"
const VISIBLE_SPEAR_REACH := 1.94
static var mounted_materials:Dictionary={}
var charge_impact:=0.0
var brace_immunity:=0.0
var charge_exit := Vector3.INF
var charge_direction := Vector3.ZERO
var charge_time := 0.0
var charge_wait := 0.0
var charge_spent := false
var wedge_charge := false
var charge_contacts := {}
var charge_thrust_started := false
var charge_thrust_left := 0.0

func warrior_scene() -> PackedScene:return RIDER_MODEL
func crowd_kind() -> String:return "cavalry"
func attack_run_speed() -> float:return CHARGE.HEAVY_RUN_SPEED
func weapon_reach() -> float:
	return VISIBLE_SPEAR_REACH if has_spear and animation_map.has("mounted_charge_thrust") else 2.65

func preferred_reach() -> float:
	return 1.82 if has_spear and animation_map.has("mounted_charge_thrust") else 2.4

func braced_fall_damage() -> float:
	return hp + 1.0

func _ready() -> void:
	mounted=true;detail_cost=3
	hair_index=(appearance_index*2)%HAIR_TONES.size()
	super._ready()
	max_hp=165;hp=max_hp
	for child in get_children():
		if child is CollisionShape3D:
			var shape:=CapsuleShape3D.new();shape.radius=.65;shape.height=2.9
			child.shape=shape;child.position.y=1.45
	agent.radius=.9

func apply_appearance() -> void:
	# Share each complete appearance across the cavalry, so the GPU can instance it.
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if mesh.name == &"Mounted warrior":
				mesh.set_surface_override_material(surface, rider_material(source))
				continue
			if mesh.name != &"Horse":
				continue
			var key := [source, appearance_index]
			if not mounted_materials.has(key):
				var material := source.duplicate() as StandardMaterial3D
				material.albedo_color *= [Color.WHITE, Color(.78,.79,.82), Color(1.10,1.0,.88)][appearance_index % 3]
				mounted_materials[key] = material
			mesh.set_surface_override_material(surface, mounted_materials[key])
	TroopColors.dye_saddle(model, uniform_color())

func rider_material(source: StandardMaterial3D) -> ShaderMaterial:
	return TroopColors.dye(source, uniform_color(), TroopColors.Fabric.WARRIOR, BODY_TEXTURES[appearance_index])

func setup_equipment() -> void:
	spear=model.find_child("Rider spear",true,false)
	shield=Node3D.new();shield.name="MountedShield";model.add_child(shield)
	model.find_child("Rider shield",true,false).reparent(shield,true)
	# Reparenting a skinned mesh requires preserving its skeleton path.
	var shield_mesh:MeshInstance3D=shield.get_child(0)
	shield_mesh.skeleton=shield_mesh.get_path_to(skeleton)
	paint_shield()
	sword=Node3D.new();model.add_child(sword);sword.hide()
	right_socket=BoneAttachment3D.new();right_socket.bone_name="RiderHand.R";skeleton.add_child(right_socket)
	belt_socket=BoneAttachment3D.new();belt_socket.bone_name="RiderRoot";skeleton.add_child(belt_socket)

func use_sword_animation_pack() -> void:
	for name in ["Idle","Walk","Gallop","ReadyIdle","ReadyWalk","ReadyGallop","Trot"]:
		player.get_animation(name).loop_mode=Animation.LOOP_LINEAR
	for name in ["Rear","Death","DeathSide","DeathProne","MeleeStrike"]:player.get_animation(name).loop_mode=Animation.LOOP_NONE
	for weapon in ["spear","sword"]:
		for prefix in ["idle_"]:animation_map[prefix+weapon]="Idle"
		for prefix in ["combat_","guard_"]:animation_map[prefix+weapon]="ReadyIdle"
		for prefix in ["walk_","backstep_","strafe_left_","strafe_right_"]:animation_map[prefix+weapon]="Walk"
		animation_map["advance_"+weapon]="ReadyWalk"
		animation_map["run_"+weapon]="Gallop"
		animation_map["charge_"+weapon]="ReadyGallop"
		animation_map["attack_"+weapon]="MeleeStrike"
		animation_map["victory_"+weapon]="Rear"
	for name in ["guard_front","guard_rear","guard_enter","guard_exit","guard_enter_sword","guard_exit_sword","block","block_sword","hit","draw_sword","throw_spear"]:animation_map[name]="ReadyIdle"
	animation_map["death_back"] = "Death"
	animation_map["death_side"] = "DeathSide"
	animation_map["death_sword"] = "DeathProne"
	animation_map["attack_sword_alt"]="MeleeStrike"
	if warrior_scene() == RIDER_MODEL:
		player.add_animation_library(&"video", VIDEO_ATTACKS)
		animation_map["attack_spear"] = &"video/strike"
		animation_map["mounted_charge_thrust"] = GALLOP_STRIKE

func make_animation_events() -> void:
	super.make_animation_events()
	var rear:=Animation.new();rear.length=1.6
	events.get_animation_library("").add_animation("braced_rear",rear)

func update_motion_animation(distance:float,facing_enemy:bool) -> void:
	if animation_clock>0:return
	if charge_thrust_left > 0.0 and penetrating_charge():
		return
	if motion_speed>.18:
		var prefix:="charge_" if motion_speed>3.5 and weapon_ready else ("run_" if motion_speed>3.5 else ("advance_" if weapon_ready else "walk_"))
		play_clip(prefix+"spear")
		player.speed_scale=clampf(motion_speed/(attack_run_speed() if motion_speed>3.5 else 1.8),.2,1.2)
	else:play_clip("combat_spear" if attack_order or guarding else "idle_spear")

func order_move(destination:Vector3,heading:float,speed:float,defend:bool,front:bool) -> void:
	reset_charge_pass()
	super.order_move(destination,heading,attack_run_speed() if speed>3 else 1.8,defend,front)

func order_throw(_point:Vector3,_delay:float) -> void:pass

func stop() -> void:
	reset_charge_pass()
	super.stop()

func order_attack(opponent: CharacterBody3D, running: bool, hold := false) -> void:
	if not attack_order or running != charge:
		reset_charge_pass()
	super.order_attack(opponent, running, hold)

func reset_charge_pass() -> void:
	charge_exit = Vector3.INF
	charge_direction = Vector3.ZERO
	charge_contacts.clear()
	charge_spent = false
	wedge_charge = false
	charge_thrust_started = false
	charge_thrust_left = 0.0

func penetrating_charge() -> bool:
	return charge and charge_exit != Vector3.INF and not busy and alive and not fleeing

func track_combat_progress(delta:float) -> void:
	charge_thrust_left = maxf(0.0, charge_thrust_left - delta)
	if penetrating_charge():
		animate_charge_thrust()
		charge_wait = maxf(0.0, charge_wait - delta)
		charge_time -= delta
		if charge_wait <= 0.0 and motion_speed > 2.5:
			resolve_charge_contact(combat_last_position)
	super.track_combat_progress(delta)
	brace_immunity=maxf(0,brace_immunity-delta)

func animate_charge_thrust() -> void:
	if charge_thrust_started or not has_spear or not animation_map.has("mounted_charge_thrust") or not is_instance_valid(combat_target):
		return
	var distance := (combat_target.position - position).dot(charge_direction)
	if distance > VISIBLE_SPEAR_REACH + motion_speed * SPEAR_CONTACT_TIME:
		return
	charge_thrust_started = true
	charge_thrust_left = .60
	play_clip("mounted_charge_thrust", .10)

func update_combat() -> void:
	if penetrating_charge():
		var remaining := (charge_exit - position).dot(charge_direction)
		if charge_time > 0.0 and remaining > 1.2:
			target = charge_exit
			return
		charge_exit = Vector3.INF
	if not busy and animation_clock <= 0.0 and attack_order and is_instance_valid(combat_target) and combat_target.alive and not combat_target.withdrawn and not combat_target.disarmed and not combat_target.fleeing and charge and not charge_spent:
		var group := get_parent()
		var heavy: bool = group.has_method("is_heavy_cavalry") and group.is_heavy_cavalry()
		var wedge: bool = heavy and group.can_wedge_charge()
		if wedge or (not heavy and not combat_target.mounted):
			var offset := (combat_target.position - position).slide(Vector3.UP)
			var distance := offset.length()
			if distance < 11.0 and motion_speed > 2.5 and velocity.dot(offset.normalized()) > 2.0:
				commit_charge_pass(wedge)
				return
			if distance > melee_reach_against(combat_target) and distance < 11.0:
				super.update_combat()
				if not busy and is_instance_valid(combat_target):
					target = combat_target.position
					speed_limit = attack_run_speed()
				return
	super.update_combat()
	if pursues_routed_rider(combat_target):
		speed_limit = attack_approach_speed()

func pursues_routed_rider(opponent: CharacterBody3D) -> bool:
	return (
		attack_order and not hold_position and not fleeing
		and is_instance_valid(opponent) and opponent.alive and not opponent.withdrawn
		and not opponent.disarmed and opponent.mounted and opponent.fleeing
	)

func moving_strike() -> bool:
	return active_action.begins_with("attack") and pursues_routed_rider(strike_target)

func movement_destination() -> Vector3:
	var opponent := strike_target if busy else combat_target
	if not pursues_routed_rider(opponent) or (busy and not moving_strike()) or penetrating_charge():
		return target
	# Keep pace with the target through the weapon wind-up.
	var direction := (opponent.position - position).slide(Vector3.UP).normalized()
	var travel := opponent.velocity.slide(Vector3.UP)
	var forward := Vector3.FORWARD.rotated(Vector3.UP, opponent.final_heading)
	var side := forward.cross(Vector3.UP) * (1.0 if index % 2 == 0 else -1.0)
	var rear_approach := clampf(direction.dot(forward), 0.0, 1.0)
	return opponent.position + travel * .4 - direction * preferred_reach() + side * rear_approach

func melee_reach_against(opponent: CharacterBody3D) -> float:
	if not pursues_routed_rider(opponent):
		return super.melee_reach_against(opponent)
	# A pursuing rider can hit the horse before reaching the rider at its centre.
	var offset := (position - opponent.position).slide(Vector3.UP).normalized()
	var along_horse := absf(opponent.global_basis.z.dot(offset))
	return weapon_reach() + lerpf(.35, .95, along_horse)

func commit_charge_pass(wedge := false) -> void:
	charge_direction = (combat_target.position - position).slide(Vector3.UP).normalized()
	var group := combat_target.get_parent()
	var depth := (combat_target.position-position).dot(charge_direction)
	for defender in group.living():
		depth = maxf(depth, (defender.position - position).dot(charge_direction))
	charge_exit = FIELD.clamp_ground(position + charge_direction * (depth + 5.0), field_half_size, 1.2)
	charge_time = maxf(3.0, (depth + 5.0) / attack_run_speed() * 1.6)
	charge_wait = 0.0
	charge_spent = true
	wedge_charge = wedge
	target = charge_exit
	weapon_ready = true
	final_heading = atan2(-charge_direction.x, -charge_direction.z)
	speed_limit = attack_run_speed()

func resolve_charge_contact(previous: Vector3) -> void:
	var index_service: Node = get_tree().current_scene.combat_index
	var defender: CharacterBody3D
	var best := INF
	for candidate in index_service.nearby(position, team, 4.6, true):
		if (candidate.mounted and not wedge_charge) or candidate.charge_recovery > 0 or charge_contacts.has(candidate):
			continue
		var score := CHARGE.contact_score(candidate.position, previous, position, charge_direction)
		if score < best:
			best = score
			defender = candidate
	if not defender:
		return
	var across := charge_direction.cross(Vector3.UP)
	var side := signf((defender.position - position).dot(across))
	if side == 0.0:
		side = 1.0 if defender.index % 2 == 0 else -1.0
	var momentum := minf(attack_run_speed(), motion_speed)
	var facing: float = defender.global_basis.z.dot(charge_direction)
	var planted: bool = defender.bracing_charge and facing > .76
	var veteran_impact := Experience.charge_impact(experience_rank)
	var damage := CHARGE.damage(momentum) * attack_damage_scale() * veteran_impact
	var push := CHARGE.impulse(charge_direction, side, momentum) * veteran_impact
	if wedge_charge:
		damage *= 1.3
		push *= 1.35
	if planted:
		damage *= .59
		var axial := charge_direction * push.dot(charge_direction)
		push = axial * .39 + (push - axial) * .68
	elif facing > .45 and defender.shield_raised:
		damage *= .72
	elif facing < .25:
		damage *= lerpf(.60, .87, clampf(-facing, 0.0, 1.0))
	defender.receive_charge(damage, self, push, planted)
	if animation_name == "mounted_charge_thrust" and not spear_recoil_clip and (not crowd_visual or not crowd_visual.distant):
		withdraw_spear(clampf(.60 - charge_thrust_left, 0.0, .52), 3.0)
	charge_contacts[defender] = true
	charge_wait = CHARGE.CONTACT_INTERVAL
	velocity = velocity.move_toward(Vector3.ZERO, .57)
	if planted and brace_immunity <= 0:
		var impact := clampf((momentum - 3.0) / 6.2, 0.0, 1.0)
		var fall_chance := .08 + .19 * impact
		var roll: float = defender.rng.randf()
		brace_immunity = 1.6
		receive_hit(braced_fall_damage() if roll < fall_chance else 23.0 + 22.0 * impact, defender, false, false, false, Vector3.INF, {"charge_impact": true})
		if alive and roll < fall_chance + .32 + .14 * impact:
			charge_exit = Vector3.INF
			busy = true
			active_action = "braced_rear"
			play_clip("victory_spear", .10)
			target = position
			events.play("braced_rear")

func begin_strike() -> void:
	charge_impact=clampf(motion_speed/attack_run_speed(),0,1)
	if charge_impact>.6 and brace_immunity<=0 and not combat_target.mounted and combat_target.has_spear and combat_target.shield_raised:
		var toward:Vector3=(position-combat_target.position).normalized()
		if (-combat_target.global_basis.z).dot(toward)>.5:
			brace_immunity=3
			receive_hit(20+charge_impact*22,combat_target)
			if not alive:return
			busy=true;active_action="braced_rear"
			play_clip("victory_spear",.1);target=position;events.play("braced_rear")
			return
	super.begin_strike()

func start_strike(action: String, speed: float) -> void:
	if action == "attack_spear" and animation_map.has("mounted_charge_thrust"):
		animation_map[action] = GALLOP_STRIKE if motion_speed > 3.5 else &"video/strike"
	super.start_strike(action, speed)
	strike_impact_time = .34

func action_finished(action:StringName) -> void:
	if action==&"braced_rear":busy=false;active_action="";animation_clock=0
	else:super.action_finished(action)

func resolve_strike() -> void:
	var original:=damage_multiplier
	damage_multiplier *= 1.15 + charge_impact * .8
	super.resolve_strike()
	damage_multiplier=original

func resume_after_spear_recoil() -> void:
	charge_thrust_left = 0.0
	super.resume_after_spear_recoil()

func drop_held_weapon(impulse: Vector3) -> void:
	super.drop_held_weapon(impulse)
	var bone := skeleton.find_bone("RiderShield")
	var pose := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	if crowd_visual and crowd_visual.distant:
		pose = global_transform * crowd_visual.bone_transform("RiderShield")
	pose = pose.orthonormalized()
	pose.basis = pose.basis.scaled(Vector3.ONE * .94)
	var part := shield.get_child(0) as MeshInstance3D
	shield.hide()
	if effects:
		effects.drop_weapon(SHIELD, pose, impulse * .90 + global_basis.z * .35, .94, part.material_override)
