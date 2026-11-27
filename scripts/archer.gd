extends "res://scripts/soldier.gd"

const ARCHER = preload("res://assets/archer_infantry.glb")
const BOW = preload("res://assets/recurve_bow.glb")
const QUIVER = preload("res://assets/quiver.glb")
const KNIFE = preload("res://assets/knife.glb")
const ARROW = preload("res://assets/arrow.glb")
const ARROW_FLIGHT = preload("res://scripts/arrow.gd")
const BOW_RANGE := 68.0
const KEEP_DISTANCE := 19.0
const RETREAT_DISTANCE := 12.0
const GAIT_SPEEDS := {
	"bow_walk": 1.0,
	"bow_run": 3.3,
	"bow_backstep": .8,
	"bow_retreat": 2.45,
	"bow_left": 2.4,
	"bow_right": 2.65,
	"knife_run": 3.65,
}
const ARMBAND_SHADER := preload("res://assets/archer_armband.gdshader")
static var armband_materials: Dictionary[Color, ShaderMaterial] = {}
var bow: Node3D
var bow_back: BoneAttachment3D
var held_arrow: Node3D
var bow_socket: BoneAttachment3D
var strings: Array[MeshInstance3D] = []
var retreating := false
var manual_move := false
var auto_fire := true
var scan_timer := 0.0
var shoot_cooldown := 0.0
var threat: CharacterBody3D
var fire_area := false
var area_point := Vector3.ZERO
var arrow_released := false
var arrow_ready := false
var shots_fired := 0
var shot_point := Vector3.ZERO
var aim_spine := -1
var aim_override := false
var unpitched_spine := Quaternion.IDENTITY
var firing_slot := Vector3.ZERO

func _ready() -> void:
	has_spear = false
	super._ready()
	max_hp = rng.randf_range(70,85)
	hp = max_hp
	shoot_cooldown = rng.randf_range(.2,1.6)
	guarding = false
	make_team_bands()
	firing_slot = position
	for bone in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone).ends_with("Spine1"):
			aim_spine = bone
			break
	skeleton.skeleton_updated.connect(update_bow_string)
	update_bow_string()

func warrior_scene() -> PackedScene:
	return ARCHER

func apply_appearance() -> void:
	apply_archer_tunic()

func make_team_bands() -> void:
	# Mounted archers use dyed cloth and saddlecloth for team identification.
	if mounted: return
	var color := uniform_color()
	if not armband_materials.has(color):
		var material := ShaderMaterial.new()
		material.shader = ARMBAND_SHADER
		material.set_shader_parameter("base_tint", color)
		armband_materials[color] = material
	var arm_names := ["mixamorig:LeftArm", "mixamorig:RightArm"]
	var units_per_meter := equipment_scale()
	var mesh := CylinderMesh.new()
	mesh.top_radius = .062 * units_per_meter
	mesh.bottom_radius = .070 * units_per_meter
	mesh.height = .105 * units_per_meter
	mesh.radial_segments = 10
	mesh.rings = 0
	mesh.cap_top = false
	mesh.cap_bottom = false
	for arm_name: String in arm_names:
		var socket := make_socket(arm_name)
		var forearm_name := String(socket.bone_name).replace("Arm", "ForeArm")
		var forearm := skeleton.find_bone(forearm_name)
		var upper_arm := skeleton.get_bone_rest(forearm).origin
		var band := MeshInstance3D.new()
		band.name = "TeamArmband"
		band.hide() # The crowd renderer uses this mesh on distant archers.
		band.mesh = mesh
		band.material_override = armband_materials[color]
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		band.position = upper_arm * .48
		band.quaternion = Quaternion(Vector3.UP, upper_arm.normalized())
		socket.add_child(band)

func use_sword_animation_pack() -> void:
	for clip in ["bow_idle","bow_aim","bow_walk","bow_run","bow_backstep","bow_retreat","bow_left","bow_right","knife_idle","knife_run"]:
		player.get_animation(animation_map[clip]).loop_mode = Animation.LOOP_LINEAR
	for alias in ["idle_spear","idle_sword","combat_sword","guard_sword","guard_enter_sword","guard_exit_sword"]:
		animation_map[alias] = animation_map["bow_idle"]
	animation_map["draw_sword"] = animation_map["knife_draw"]
	animation_map["death_sword"] = animation_map["bow_death"]
	animation_map["hit"] = animation_map["bow_hit"]
	animation_map["attack_sword"] = animation_map["knife_attack"]
	animation_map["attack_sword_alt"] = animation_map["knife_attack"]
	for alias in ["walk_sword","advance_sword","run_sword","charge_sword","backstep_sword","strafe_left_sword","strafe_right_sword"]:
		animation_map[alias] = animation_map["bow_walk"]

func equipment(scene: PackedScene, socket: Node3D) -> Node3D:
	var item := scene.instantiate()
	item.scale = Vector3.ONE * equipment_scale()
	item.rotation.x = PI/2
	socket.add_child(item)
	return item

func equipment_scale() -> float:
	return 1.0 / 1.8

func melee_weapon_scene() -> PackedScene:
	return KNIFE

func bow_scene() -> PackedScene:
	return BOW

func bow_string_knot(top: bool) -> Vector3:
	return Vector3(.222,.578,0) if top else Vector3(.222,-.591,0)

func firing_height() -> float:
	return 1.28

func retreat_speed() -> float:
	return 4.55

func setup_equipment() -> void:
	right_socket = make_socket("GripRight")
	belt_socket = make_socket("SwordBelt")
	bow_socket = make_socket("GripLeft")
	bow_back = make_socket("BowBack")
	bow = equipment(bow_scene(),bow_socket)
	bow.position = bow_grip_offset()
	sword = equipment(melee_weapon_scene(),belt_socket)
	var quiver := equipment(QUIVER,make_socket("QuiverBack"))
	quiver.scale *= 2.0/3.0
	held_arrow = equipment(ARROW,right_socket)
	held_arrow.hide()
	spear = Node3D.new()
	shield = Node3D.new()
	add_child(spear)
	add_child(shield)
	spear.hide()
	shield.hide()
	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color("b4a082")
	for i in 2:
		var line := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = .0016
		mesh.bottom_radius = .0016
		mesh.height = 1
		mesh.radial_segments = 4
		line.mesh = mesh
		line.material_override = string_mat
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bow.add_child(line)
		strings.append(line)

func bow_grip_offset() -> Vector3:
	# The socket starts near the wrist. Centre the grip between the curled fingers.
	return Vector3.ZERO if mounted else Vector3(-.020, .014, 0.0)

func bow_back_shift() -> Vector3:
	return Vector3.ZERO

func make_animation_events() -> void:
	events = AnimationPlayer.new()
	add_child(events)
	var library := AnimationLibrary.new()
	for name in ["bow_draw","bow_aim","bow_release","draw_sword","attack_sword","celebrate"]:
		var clip := Animation.new()
		clip.length = {"bow_draw":1.15,"bow_aim":.55,"bow_release":.5,"draw_sword":.5,"attack_sword":1.0,"celebrate":2.8}[name]
		if name in ["bow_draw","bow_release","draw_sword","attack_sword"]:
			var method: String = {"bow_draw":"show_arrow","bow_release":"mark_arrow_ready","draw_sword":"take_sword","attack_sword":"resolve_strike"}[name]
			var moment: float = {"bow_draw":.40,"bow_release":.08,"draw_sword":.25,"attack_sword":.14}[name]
			var track := clip.add_track(Animation.TYPE_METHOD)
			clip.track_set_path(track,NodePath("."))
			clip.track_insert_key(track,moment,{"method":method,"args":[]})
		library.add_animation(name,clip)
	events.add_animation_library("",library)
	events.animation_finished.connect(action_finished)

func is_gait(clip: String) -> bool:
	return super.is_gait(clip) or clip in ["bow_walk","bow_run","bow_backstep","bow_retreat","bow_left","bow_right","knife_run"]

func play_clip(clip: String, blend := .18) -> void:
	var actual := clip
	if clip in ["idle_spear","idle_sword","combat_sword","guard_sword","guard_enter_sword","guard_exit_sword"]:
		actual = "knife_idle" if sword_drawn else "bow_idle"
	elif clip in ["walk_sword","advance_sword"]: actual = "knife_run" if mounted and sword_drawn else "bow_walk"
	elif clip in ["run_sword","charge_sword"]: actual = "knife_run" if sword_drawn else "bow_run"
	elif clip == "backstep_sword": actual = "bow_retreat" if motion_speed > 2.5 else "bow_backstep"
	elif clip == "strafe_left_sword": actual = "bow_left"
	elif clip == "strafe_right_sword": actual = "bow_right"
	elif clip == "victory_sword": actual = "bow_victory"
	if not animation_map.has(actual): actual = "bow_idle"
	super.play_clip(actual,blend)

func movement_clip_rate(movement_clip: String, running: bool) -> float:
	if mounted or not GAIT_SPEEDS.has(animation_name):
		return super.movement_clip_rate(movement_clip, running)
	# Match the speed of the planted foot in the selected archer clip.
	return clampf(motion_speed / float(GAIT_SPEEDS[animation_name]), .16, 2.5)

func _physics_process(delta: float) -> void:
	scan_timer -= delta
	shoot_cooldown = maxf(0,shoot_cooldown-delta * Experience.attack_tempo(experience_rank))
	if manual_move and global_position.distance_to(target) < .3: manual_move = false
	super._physics_process(delta)

func can_batch_native_logic() -> bool:
	# Volley readiness is checked by the squad between the fighter's decision ticks.
	return false

func visual_pose_will_update() -> void:
	if aim_override:
		skeleton.set_bone_pose_rotation(aim_spine, unpitched_spine)
		aim_override = false

func visual_pose_updated() -> void:
	var pitch := bow_pitch()
	if aim_spine >= 0 and not is_zero_approx(pitch):
		visual_pose_will_update()
		unpitched_spine = skeleton.get_bone_pose_rotation(aim_spine)
		var parent_pose := skeleton.get_bone_global_pose(skeleton.get_bone_parent(aim_spine))
		var axis := ((skeleton.global_basis * parent_pose.basis).inverse() * global_basis.x).normalized()
		skeleton.set_bone_pose_rotation(aim_spine, Quaternion(axis, pitch) * unpitched_spine)
		aim_override = true
		skeleton.force_update_all_bone_transforms()
		for socket in skeleton.get_children():
			if socket is BoneAttachment3D and socket.bone_idx >= 0:
				socket.transform = skeleton.get_bone_global_pose(socket.bone_idx)
		update_bow_string()

func bow_pitch() -> float:
	if not active_action in ["bow_draw", "bow_aim", "bow_release"]:
		return 0.0
	var origin := global_position + Vector3.UP * firing_height()
	var velocity_at_release := ARROW_FLIGHT.launch_velocity(origin, shot_point)
	var elevation := atan2(velocity_at_release.y, Vector2(velocity_at_release.x, velocity_at_release.z).length())
	var weight := 1.0
	var phase := events.current_animation_position if events.current_animation == active_action else 0.0
	if active_action == "bow_draw":
		weight = smoothstep(.22, .94, phase)
	elif active_action == "bow_release":
		weight = 1.0 - smoothstep(.12, .48, phase)
	return clampf(elevation, -.12, .40) * weight

func update_bow_string() -> void:
	if crowd_visual and crowd_visual.distant: return
	# Reparenting equipment briefly takes it out of the tree while the skeleton updates.
	if not is_inside_tree() or not is_instance_valid(bow) or not bow.is_inside_tree(): return
	if not right_socket.is_inside_tree() or not bow_socket.is_inside_tree(): return
	var top := bow_string_knot(true)
	var bottom := bow_string_knot(false)
	var drawn := held_arrow.visible and active_action.begins_with("bow_")
	if drawn:
		var nock := bow.to_local(right_socket.global_position)
		pose_string_segment(strings[0], top, nock)
		pose_string_segment(strings[1], nock, bottom)
	else:
		pose_string_segment(strings[0], top, bottom)
	strings[0].visible = alive
	strings[1].visible = alive and drawn
	if held_arrow.visible:
		var origin := right_socket.global_position
		var direction := ARROW_FLIGHT.launch_velocity(origin, shot_point).normalized()
		if direction.length_squared() < .2: direction = -global_basis.z
		var side := direction.cross(Vector3.UP).normalized()
		var arrow_basis := Basis(side, direction, side.cross(direction))
		held_arrow.global_transform = Transform3D(arrow_basis.scaled(Vector3.ONE * ARROW_FLIGHT.MODEL_SCALE), origin)

func pose_string_segment(segment: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var length := start.distance_to(end)
	if length <= .001: return
	var axis := (end - start) / length
	var side := axis.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < .1: side = Vector3.RIGHT
	segment.transform = Transform3D(Basis(side, axis * length, side.cross(axis)), (start + end) * .5)

func scan_enemies() -> void:
	threat = get_tree().current_scene.combat_index.nearest(position,team,8.0)
	if not is_instance_valid(threat) and is_instance_valid(combat_target) and combat_target.alive and not combat_target.withdrawn and not combat_target.fleeing: threat = combat_target
	if not is_instance_valid(get_parent().attack_target) and (not is_instance_valid(combat_target) or not combat_target.alive or combat_target.withdrawn):
		combat_target = threat

func update_combat() -> void:
	if fleeing or active_action == "celebrate": return
	update_weapon_mode()
	if not attack_order and not fire_area and get_parent().get("behavior_controlled") == true:
		return
	if using_knife():
		if sword_drawn and not manual_move and not retreating: super.update_combat()
		return
	if retreating or manual_move or not auto_fire: return
	if scan_timer <= 0:
		scan_timer = .20 + index*.001
		scan_enemies()
	var threat_distance := global_position.distance_to(threat.global_position) if is_instance_valid(threat) and threat.alive and not threat.fleeing else INF
	if sword_drawn:
		if threat_distance > 3.5 and not busy:
			stow_knife()
		else:
			if threat_distance < INF: combat_target = threat
			super.update_combat()
		return
	if not fire_area and (not is_instance_valid(combat_target) or not combat_target.alive or combat_target.withdrawn):
		if active_action.begins_with("bow_"): return
		if threat_distance >= 2.8 and is_instance_valid(get_parent().attack_target): return
		combat_target = threat if threat_distance < INF else null
		if not is_instance_valid(combat_target):
			attack_order = false
			return
	if not attack_order and not fire_area:
		if threat_distance >= RETREAT_DISTANCE: return
		attack_order = true
	var aim_point: Vector3 = area_point if fire_area else combat_target.global_position
	var distance := global_position.distance_to(aim_point)
	final_heading = atan2(-(aim_point.x-global_position.x),-(aim_point.z-global_position.z))
	shield_raised = false
	guarding = false
	if threat_distance < 2.8:
		if active_action != "draw_sword": draw_knife()
		return
	if busy or animation_clock > 0: return
	if distance > BOW_RANGE and not hold_position:
		target = firing_slot
		speed_limit = (attack_run_speed() if mounted else 4.2) if charge else 1.8
	else:
		target = global_position

func ready_to_loose() -> bool:
	if not alive or busy or shoot_cooldown > 0.0 or animation_clock > 0.0 or motion_speed >= .3:
		return false
	if not fire_area and (not is_instance_valid(combat_target) or not combat_target.alive or combat_target.withdrawn): return false
	var aim: Vector3 = area_point if fire_area else combat_target.position
	return position.distance_squared_to(aim) <= BOW_RANGE * BOW_RANGE and absf(angle_difference(rotation.y,final_heading)) < .30

func order_skirmish_retreat(destination: Vector3, heading: float) -> void:
	order_move(destination,heading,retreat_speed(),false,false)
	speed_limit = retreat_speed()
	retreating = true

func start_shot() -> void:
	if busy or using_knife() or sword_drawn or not alive: return
	if not fire_area and (not is_instance_valid(combat_target) or not combat_target.alive or combat_target.withdrawn): return
	busy = true
	active_action = "bow_draw"
	arrow_released = false
	arrow_ready = false
	shot_point = area_point+Vector3.UP*.9 if fire_area else combat_target.global_position+Vector3.UP*1.05
	target = global_position
	play_clip("bow_draw",.12)
	player.speed_scale = player.get_animation(animation_map["bow_draw"]).length/1.15
	events.play("bow_draw")

func show_arrow() -> void:
	if alive and not arrow_released:
		held_arrow.show()
		update_bow_string()

func mark_arrow_ready() -> void:
	arrow_ready = true

func prepare_arrow() -> PackedVector3Array:
	if not alive or arrow_released or not arrow_ready or active_action != "bow_release": return []
	if crowd_visual: crowd_visual.sync_sockets()
	var aim_point := shot_point
	if not fire_area and is_instance_valid(combat_target) and combat_target.alive and not combat_target.withdrawn:
		var flight := global_position.distance_to(combat_target.global_position)/27.0
		aim_point = combat_target.global_position+Vector3.UP*1.05+combat_target.velocity*flight*.8
	var spread := .65 if fire_area else .42
	var scatter := Vector3(rng.randf_range(-spread, spread), rng.randf_range(-.10, .15),
		rng.randf_range(-spread, spread))
	aim_point += scatter * Experience.projectile_spread(experience_rank)
	var origin := bow_socket.global_position
	if crowd_visual and crowd_visual.distant:
		var pivot := global_position + Vector3.UP * (firing_height() - .20)
		origin = pivot + (origin - pivot).rotated(global_basis.x, bow_pitch())
	if ARROW_FLIGHT.ally_blocks_launch(self, origin, aim_point):
		return []
	return PackedVector3Array([origin, aim_point])

func launch_arrow(origin: Vector3, aim_point: Vector3) -> void:
	held_arrow.hide()
	update_bow_string()
	arrow_released = true
	shots_fired += 1
	var arrow := Node3D.new()
	arrow.set_script(ARROW_FLIGHT)
	arrow.process_mode = Node.PROCESS_MODE_PAUSABLE
	arrow.shooter = self
	arrow.source_team = team
	arrow.bow_damage_scale = 0.88 if mounted else 0.60
	get_tree().current_scene.add_child(arrow)
	arrow.launch(origin,aim_point)
	if effects: effects.sound("bow",global_position+Vector3.UP,-7)

func action_finished(action: StringName) -> void:
	if not alive: return
	if action == &"bow_draw":
		active_action = "bow_aim"
		play_clip("bow_aim",.12)
		events.play("bow_aim")
	elif action == &"bow_aim":
		active_action = "bow_release"
		play_clip("bow_release",.06)
		player.speed_scale = player.get_animation(animation_map["bow_release"]).length/.5
		events.play("bow_release")
	elif action == &"bow_release":
		busy = false
		active_action = ""
		held_arrow.hide()
		update_bow_string()
		shoot_cooldown = rng.randf_range(.85,1.45)
	else: super.action_finished(action)

func cancel_shot() -> void:
	if not active_action.begins_with("bow_"): return
	events.stop()
	held_arrow.hide()
	busy = false
	active_action = ""
	shoot_cooldown = maxf(shoot_cooldown,.35)

func using_knife() -> bool:
	return not get_parent().uses_bows()

func update_weapon_mode() -> void:
	if busy or not alive or fleeing: return
	if using_knife():
		if not sword_drawn and (attack_order or get_parent().melee_mode):
			var destination := target
			draw_knife()
			if manual_move: target = destination
	elif sword_drawn and not attack_order:
		stow_knife()

func draw_knife() -> void:
	cancel_shot()
	if busy: return
	retreating = false
	target = global_position
	busy = true
	active_action = "draw_sword"
	bow.reparent(bow_back,false)
	bow.transform = Transform3D(Basis(Vector3.RIGHT,PI/2).scaled(Vector3.ONE * equipment_scale()),
		bow_grip_offset() + bow_back_shift())
	update_bow_string()
	play_clip("draw_sword",.12)
	events.play("draw_sword")

func stow_knife() -> void:
	sword_drawn = false
	if is_instance_valid(get_parent().attack_target): combat_target = null
	sword.reparent(belt_socket,false)
	sword.transform = Transform3D(Basis(Vector3.RIGHT,PI/2).scaled(Vector3.ONE * equipment_scale()),Vector3.ZERO)
	bow.reparent(bow_socket,false)
	bow.transform = Transform3D(Basis(Vector3.RIGHT,PI/2).scaled(Vector3.ONE * equipment_scale()),bow_grip_offset())
	shoot_cooldown = 1.0
	play_clip("bow_idle",.25)

func begin_strike() -> void:
	start_strike("attack_sword",1.0)

func weapon_reach() -> float:
	return .90

func melee_damage_scale() -> float:
	return super.melee_damage_scale() * (0.85 if mounted else 0.75)

func has_shield() -> bool:
	return false

func order_attack(opponent: CharacterBody3D, running: bool, hold := false) -> void:
	manual_move = false
	auto_fire = true
	fire_area = false
	retreating = false
	super.order_attack(opponent,running,hold)
	shield_raised = false

func order_move(destination: Vector3, heading: float, speed: float, defend: bool, front: bool) -> void:
	cancel_shot()
	manual_move = true
	auto_fire = true
	fire_area = false
	retreating = false
	super.order_move(destination,heading,speed,defend,front)
	guarding = false

func order_fire_area(point: Vector3) -> void:
	cancel_shot()
	auto_fire = true
	manual_move = false
	retreating = false
	attack_order = true
	fire_area = true
	area_point = point
	target = global_position

func stop() -> void:
	cancel_shot()
	auto_fire = false
	manual_move = false
	retreating = false
	fire_area = false
	super.stop()

func receive_hit(damage: float, attacker: CharacterBody3D, projectile_hit := false, friendly_fire := false, arrow_hit := false, contact := Vector3.INF, hit_context: Dictionary = {}) -> bool:
	if is_instance_valid(attacker) and attacker.team == team and not friendly_fire: return false
	cancel_shot()
	return super.receive_hit(damage,attacker,projectile_hit,friendly_fire,arrow_hit,contact,hit_context)

func death_clip() -> String:
	return "bow_death" if rng.randf() < .5 else "bow_death_front"

func drop_held_weapon(impulse: Vector3) -> void:
	if sword_drawn:
		release_death_weapon(sword, melee_weapon_scene(), sword.global_transform, impulse)
	else:
		release_death_weapon(bow, bow_scene(), bow.global_transform, impulse)

func disarm_for_surrender() -> void:
	super.disarm_for_surrender()
	bow.hide()

func die(hit_direction := Vector3.ZERO) -> void:
	cancel_shot()
	held_arrow.hide()
	super.die(hit_direction)
	for line in strings: line.hide()
