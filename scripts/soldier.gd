extends CharacterBody3D
const PROF = preload("res://scripts/profile_counters.gd")
const FIELD = preload("res://scripts/battlefield_bounds.gd")
const Experience = preload("res://scripts/unit_experience.gd")
const TroopColors = preload("res://scripts/troop_colors.gd")

const WARRIOR = preload("res://assets/warrior.glb")
const ARCHER_ALBEDO = preload("res://assets/archer_albedo.jpg")
const SOTNIK_TEXTURE = preload("res://assets/sotnik.jpg")
const SPEAR = preload("res://assets/spear.glb")
const SWORD = preload("res://assets/sword.glb")
const WARRIOR_MESHES = preload("res://assets/lod/warrior_meshes.res")
static var warrior_lods_enabled := "--no-warrior-lod" not in OS.get_cmdline_user_args()
const SHIELD = preload("res://assets/shield.glb")
const SPEAR_SHIELDS = preload("res://assets/spear_shield_variants.glb")
const SPEAR_SHIELD_SHADER = preload("res://assets/spear_shield.gdshader")
const SHIELD_VARIANT_COUNT := 9
const ROUND_SHIELD_COUNT := 6
const PROJECTILE = preload("res://scripts/projectile.gd")
const SPEAR_COMBAT = preload("res://scripts/spear_combat.gd")
const BODY_WOUNDS = preload("res://scripts/body_wounds.gd")
const FOOT_PLACEMENT = preload("res://scripts/infantry_foot_placement.gd")
const ATTACK_RUN_SPEED := 3.6
const LOCAL_CONTACT_RADIUS := 2.1
const ACCELERATION := 3.0
const BRAKING := 5.5
const SPEAR_INTERCEPT := "attack_spear_03"
const SPEAR_VS_SWORD_THRUST_SPEED := 1.25
const GALLOP_CONTACT_SPACING := [0.70, 0.70, 0.70, 2.15]
const MOUNT_HALF_LENGTH := 1.25
const MOUNT_HALF_WIDTH := 0.65
const MOUNT_COLLISION_HALF_LENGTH := 1.2
# The crowd solver keeps .24 m of clearance around the combined footprints.
const MOUNT_MELEE_CLEARANCE := .29
const MOUNT_MELEE_SEARCH_RADIUS := 2.0 * MOUNT_COLLISION_HALF_LENGTH + MOUNT_MELEE_CLEARANCE + .4
const MOUNT_MAX_PITCH := deg_to_rad(22.0)
const MOUNT_MAX_ROLL := deg_to_rad(12.0)
const BODY_TEXTURES = [
	null, # Use the material from warrior.glb for the original look.
	preload("res://assets/warrior_lamellar.jpg"),
	preload("res://assets/warrior_green_eyes.jpg"),
]

const HAIR_TONES = [Vector3(.70,.72,.75), Vector3(.82,.78,.72), Vector3.ONE, Vector3(1.16,1.08,.95), Vector3(1.08,.94,.82), Vector3(.92,.98,1.04)]
static var body_materials := {}
static var spear_shield_meshes: Dictionary[PackedScene, Array] = {}
static var spear_shield_materials: Dictionary[Color, ShaderMaterial] = {}
static var charge_brace_library: AnimationLibrary

var index := 0
var is_sotnik := false
var shield_variant := -1
var field_half_size := FIELD.DEFAULT_HALF_SIZE
var appearance_index := 0
var hair_index := 0
var target := Vector3.ZERO
var final_heading := 0.0
var speed_limit := 1.8
var speed_variation := 1.0
var stamina_multiplier := 1.0
var reaction := 0.0
var guarding := false
var front_rank := false
var has_spear := true
var has_sidearm := true
var sword_drawn := false
var busy := false
var throw_target := Vector3.ZERO
var throw_wait := -1.0
var released := false
var animation_name := ""
var animation_clock := 0.0
var navigation_timer := 0.0
var safe_velocity := Vector3.ZERO
var motion_speed := 0.0
var agent: NavigationAgent3D
var model: Node3D
var player: AnimationPlayer
var events: AnimationPlayer
var skeleton: Skeleton3D
var foot_placement: SkeletonModifier3D
var spear: Node3D
var sword: Node3D
var shield: Node3D
var right_socket: BoneAttachment3D
var belt_socket: BoneAttachment3D
var active_action := ""
var animation_map := {}
var team := 0
var hp := 100.0
var max_hp := 100.0
var armor_reduction := 0.0
var alive := true
var combat_target: CharacterBody3D
var attack_order := false
var heading_before_local_contact := INF
var fleeing := false
var disarmed := false
var charge := false
var shield_raised := false
var bracing_charge := false
var charge_push := Vector3.ZERO
var charge_recovery := 0.0
var attack_cooldown := 0.0
var strike_done := false
var strike_target: CharacterBody3D
var spear_attack_bag: Array[String] = []
var previous_spear_attack := ""
var resolved_spear_contacts: Dictionary = {}
var last_spear_contact: Dictionary = {}
var strike_elapsed := 0.0
var strike_speed := 1.0
var strike_impact_time := .32
var strike_duration := .85
var last_hit_result: Dictionary = {}
var damage_flash := 0.0
var step_distance := 0.0
var hoof_beat := 0
var step_galloping := false
var rng := RandomNumberGenerator.new()
var effects: Node3D
var kills := 0
var hold_position := false
var guard_anchor := Vector3.ZERO
var celebrate_pending := false
var weapon_ready := false
var battle_cry_done := false
var contact_eta := INF
var ready_lead := 2.5
var cry_lead := 1.5
var visual_delta := 0.0
var visual_interval := 0.0
var visual_lod_timer := 0.0
var spear_recoil_clip: Animation
var spear_recoil_time := 0.0
var spear_recoil_speed := 1.0
var spear_recoil_tracks: Array[Vector3i] = []
var spear_recoil_track_root := ""
var spear_recoil_wrist := -1
var spear_recoil_weapon := -1
var damage_multiplier := 1.0
var experience_rank := 0
var weapon_damage_multiplier := 1.0
var inspiration_multiplier := 1.0
var cohesion_group: Node3D
var combat_think_timer := 0.0
var movement_elapsed := 0.0
var crowd_visual: RefCounted
var corpse_roll := 0
var corpse_axis := Vector3.FORWARD
var corpse_pivot := Vector3.ZERO
var model_scale := Vector3.ONE
var body_wounds: RefCounted
var native_controlled := false
var native_index := -1
var withdrawn := false
var native_logic_elapsed := 0.0
var native_logic_phase := 0
var native_logic_cadence := 5
var managed_native_logic := false
var native_logic_time := 0.0
var native_query_body := false
var movement_collision_mask := 0
var native_query_transform := Transform3D.IDENTITY
var mounted := false
var detail_cost := 1
var flat_movement := false
var avoidance_timer := 0.0
var avoidance_force := Vector3.ZERO
var visual_position_from := Vector3.ZERO
var visual_yaw_from := 0.0
var mount_slope_point := Vector2.INF
var mount_slope_forward := Vector2.ZERO
var mount_slope := Basis.IDENTITY
var visual_elapsed := 1.0
var movement_duration := .1
var combat_slot_angle := 0.0
var combat_stall := 0.0
var combat_last_position := Vector3.ZERO
var combat_detour := Vector3.INF
var detour_time := 0.0
var approach_check := 0.0
var flank_waypoint := Vector3.INF
var flank_until := -1.0
var flank_side := 0.0
var threat_timer := 0.0
var strike_query: PhysicsRayQueryParameters3D
var corpse_at_rest := false

func _ready() -> void:
	field_half_size = FIELD.for_scene(get_tree().current_scene)
	rng.seed = 817 + index * 1297 + team * 6511
	max_hp = rng.randf_range(92.0, 108.0)
	hp = max_hp
	attack_cooldown = rng.randf_range(0.0, 0.8)
	step_distance = rng.randf_range(0.0, .55 if mounted else .72)
	hoof_beat = index % 4
	combat_think_timer = fmod(index*.017,.10)
	var group_phase:float=float(get_parent().get("serial")) if get_parent().get("serial")!=null else float(team)
	native_logic_phase = index*3+int(group_phase)*2
	threat_timer = fmod(index*.059+group_phase*.127,.54)
	ready_lead = 2.35 + fmod(index*.071,.4)
	cry_lead = 1.2 + fmod(index*.113,.6)
	effects = get_tree().current_scene.get_node_or_null("BattleEffects")
	if not is_instance_valid(cohesion_group) or not cohesion_group.reinforcement_pending:
		add_to_group("combatants")
	collision_layer = 2
	collision_mask = 3
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)
	model = warrior_scene().instantiate()
	model.name = "Model"
	model.rotation.y = PI
	model_scale = model.scale
	apply_appearance()
	add_child(model)
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		mesh.lod_bias = 100.0 # Authored crowd mesh handles distance; avoid destructive imported LODs.
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	player = model.find_children("*", "AnimationPlayer", true, false)[0]
	# Distant figures need fewer skeleton evaluations; gameplay and hit events remain at full rate.
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	visual_lod_timer = fmod(index*.071,.5)
	for full_name in player.get_animation_list():
		var short_name := String(full_name).get_file()
		animation_map[short_name] = full_name
		var animation := player.get_animation(full_name)
		if short_name.begins_with("idle") or short_name.begins_with("walk") or short_name.begins_with("run") or short_name.begins_with("advance") or short_name.begins_with("combat") or short_name.begins_with("backstep") or short_name.begins_with("strafe") or short_name in ["guard_front", "guard_rear", "guard_sword"]:
			animation.loop_mode = Animation.LOOP_LINEAR
	use_sword_animation_pack()
	if has_spear and not mounted:
		var brace_path := "res://assets/foot_brace.tres"
		if charge_brace_library == null and ResourceLoader.exists(brace_path):
			charge_brace_library = load(brace_path)
		if charge_brace_library:
			player.add_animation_library(&"brace", charge_brace_library)
			animation_map["brace_spear"] = &"brace/brace_spear"
	setup_equipment()
	make_animation_events()
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.2
	agent.target_desired_distance = 0.08
	agent.radius = 0.34
	agent.neighbor_distance = 2.8
	agent.max_neighbors = 10
	agent.time_horizon_agents = 0.7
	flat_movement = get_tree().current_scene.get("crowd_movement") != null and "--legacy-movement" not in OS.get_cmdline_user_args()
	# Crowd separation already resolves soldier contacts. Keep the layer for arrows/picking,
	# but do not build a second set of physics contact pairs between all kinematic bodies.
	if flat_movement: collision_mask = 0
	agent.avoidance_enabled = not flat_movement
	agent.max_speed = 4.4
	agent.velocity_computed.connect(func(value: Vector3): safe_velocity = value)
	# The native crowd owns movement in the open arena. Do not register a second
	# navigation agent in the world; retain the object for legacy navigation/QA.
	if not flat_movement:add_child(agent)
	target = position
	speed_variation = 0.96 + fmod(float(index) * 0.031, 0.08)
	visual_position_from = position
	visual_yaw_from = rotation.y
	movement_elapsed = fmod(index*.031,.20)
	native_logic_elapsed = 0.0
	play_clip("idle_spear")
	player.seek(fmod(index * 0.137, 2.0), true)
	if mounted: update_render_model_transform()
	else:
		var terrain: Node3D = get_tree().current_scene.get("terrain")
		if terrain:
			foot_placement = FOOT_PLACEMENT.new(self, terrain)
			skeleton.add_child(foot_placement)

func warrior_scene() -> PackedScene:
	return WARRIOR

func crowd_kind() -> String:
	return "archer" if get_script()==preload("res://scripts/archer.gd") else "soldier"

func attack_run_speed() -> float:
	return ATTACK_RUN_SPEED

func attack_damage_scale() -> float:
	return damage_multiplier * weapon_damage_multiplier * inspiration_multiplier * stamina_multiplier

func melee_damage_scale() -> float:
	return attack_damage_scale()

func set_stamina_multiplier(value: float) -> void:
	speed_variation *= value / stamina_multiplier
	stamina_multiplier = value

func set_inspired(enabled: bool) -> void:
	var multiplier := 1.2 if enabled else 1.0
	var change := multiplier / inspiration_multiplier
	inspiration_multiplier = multiplier
	max_hp *= change
	hp *= change
	speed_variation *= change

func _exit_tree() -> void:
	if is_instance_valid(agent) and not agent.is_inside_tree():agent.free()

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec() if PROF.enabled else 0
	visual_step(delta)
	if PROF.enabled: PROF.add("visual",started)

func visual_step(delta: float) -> void:
	visual_elapsed += delta
	if not is_instance_valid(player): return
	if not crowd_visual and "--no-crowd-lod" not in OS.get_cmdline_user_args():
		var renderer: Node = get_tree().current_scene.get("crowd_renderer")
		if renderer and not renderer.manages_initial_visuals:
			crowd_visual = load("res://scripts/crowd_visual.gd").new(self)
	if not (crowd_visual and crowd_visual.distant):
		update_render_model_transform()
	visual_delta += delta
	visual_lod_timer -= delta
	if visual_lod_timer <= 0 and not spear_recoil_clip:
		visual_lod_timer = .5
		var camera := get_viewport().get_camera_3d()
		var distance_squared := camera.global_position.distance_squared_to(global_position) if camera else 0.0
		visual_interval = (1.0/12.0 if distance_squared > 3600 else (1.0/18.0 if distance_squared > 1225 else 1.0/24.0)) if distance_squared > 324 else 0.0
		if camera and not camera.is_position_in_frustum(global_position+Vector3.UP): visual_interval = .2
		if crowd_visual and crowd_visual.renderer:
			var detailed: bool = crowd_visual.renderer.allow_detail(self,distance_squared)
			if not crowd_visual.request_distant(not detailed):
				if detailed and crowd_visual.distant: crowd_visual.renderer.detailed_actors.erase(self)
				visual_lod_timer = .08
			elif not detailed:
				crowd_visual.renderer.detailed_actors.erase(self)
			crowd_visual.refresh_distance_lod()
			if crowd_visual.distant: visual_interval = .2
	if (player.is_playing() or spear_recoil_clip or (crowd_visual and crowd_visual.distant)) and visual_delta >= visual_interval:
		if crowd_visual and crowd_visual.distant: crowd_visual.advance(visual_delta)
		else:
			visual_pose_will_update()
			player.advance(visual_delta)
			if spear_recoil_clip:
				update_spear_recoil(visual_delta)
			visual_pose_updated()
		visual_delta = 0.0

func place_for_deployment(point: Vector3, heading: float) -> void:
	position = point
	if native_query_body: sync_native_query_position()
	target = point
	guard_anchor = point
	combat_last_position = point
	rotation.y = heading
	final_heading = heading
	visual_position_from = point
	visual_yaw_from = heading
	update_render_model_transform()
	if foot_placement and foot_placement.active: skeleton.advance(0.0)
	reset_physics_interpolation()

func update_render_model_transform() -> void:
	var rendered := render_model_transform()
	var offset := (rendered.origin-position).rotated(Vector3.UP,-rotation.y)
	var yaw := PI+angle_difference(rotation.y,lerp_angle(visual_yaw_from,rotation.y,minf(1.0,visual_elapsed/movement_duration)))
	var model_basis := Basis(Vector3.UP, yaw)
	if mounted:
		model_basis = Basis(Vector3.UP, -rotation.y) * rendered.basis * Basis(Vector3.UP, PI)
	var posture := Transform3D(model_basis.scaled(model_scale), offset)
	if corpse_roll > 1:
		var phase := 1.0
		if player.is_playing():
			phase = player.current_animation_position / maxf(.001, player.current_animation_length)
		var weight := smoothstep(.52, 1.0, phase)
		var angle: float = [0.0, 0.0, .98, -.98, 2.52, -2.52][corpse_roll] * weight
		var roll := Basis(corpse_axis, angle)
		var lift := Vector3.UP * weight * (.08 if corpse_roll < 4 else .14)
		posture = Transform3D(roll, corpse_pivot - roll * corpse_pivot + lift) * posture
	if model.transform != posture:
		model.transform = posture

func render_weight() -> float:
	if native_controlled:
		return minf(1.0,get_tree().current_scene.crowd_movement.render_clock/movement_duration)
	return minf(1.0,visual_elapsed/movement_duration)

func render_position() -> Vector3:
	return visual_position_from.lerp(position,render_weight())

func render_transform() -> Transform3D:
	var weight := render_weight()
	return Transform3D(Basis(Vector3.UP,lerp_angle(visual_yaw_from,rotation.y,weight)),visual_position_from.lerp(position,weight))

func render_model_transform() -> Transform3D:
	var rendered := render_transform()
	if not mounted: return rendered
	var point := Vector2(rendered.origin.x, rendered.origin.z)
	var forward := Vector2(rendered.basis.z.x, rendered.basis.z.z)
	if point != mount_slope_point or forward != mount_slope_forward:
		var terrain: Node3D = get_tree().current_scene.get("terrain")
		if not terrain: return rendered
		# Sample across the mount's footprint to smooth transitions between terrain triangles.
		var longitudinal := forward * MOUNT_HALF_LENGTH
		var lateral := Vector2(forward.y, -forward.x) * MOUNT_HALF_WIDTH
		var rise: float = terrain.height_at(point + longitudinal) - terrain.height_at(point - longitudinal)
		var cross_rise: float = terrain.height_at(point + lateral) - terrain.height_at(point - lateral)
		var pitch := clampf(atan2(rise, 2.0 * MOUNT_HALF_LENGTH), -MOUNT_MAX_PITCH, MOUNT_MAX_PITCH)
		var roll := clampf(atan2(cross_rise, 2.0 * MOUNT_HALF_WIDTH), -MOUNT_MAX_ROLL, MOUNT_MAX_ROLL)
		mount_slope = Basis.from_euler(Vector3(-pitch, 0.0, roll))
		mount_slope_point = point
		mount_slope_forward = forward
	rendered.basis *= mount_slope
	return rendered

func visual_pose_updated() -> void:
	pass

func visual_pose_will_update() -> void:
	pass

func setup_equipment() -> void:
	right_socket = make_socket("GripRight")
	var left_socket := make_socket("GripLeft")
	spear = SPEAR.instantiate()
	shield = make_spear_shield() if shield_variant >= 0 else SHIELD.instantiate()
	right_socket.add_child(spear)
	left_socket.add_child(shield)
	if shield_variant < 0:
		paint_shield()
	var worn := [spear, shield]
	if has_sidearm:
		belt_socket = make_socket("SwordBelt")
		sword = SWORD.instantiate()
		if warrior_lods_enabled:
			var blade := sword.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			blade.mesh = WARRIOR_MESHES.get_meta("sword")
		belt_socket.add_child(sword)
		worn.append(sword)
		make_scabbard()
	# The sockets inherit the character's 1.8 scale; equipment already uses metres.
	for equipment in worn:
		equipment.scale = Vector3.ONE / 1.8
		equipment.rotation.x = PI / 2.0
	# The outward normal of the fitted shield points along its local Z.
	if shield_variant >= 0:
		shield.position += shield.basis.z * .055

func make_spear_shield(scene := SPEAR_SHIELDS, count := SHIELD_VARIANT_COUNT) -> Node3D:
	if not spear_shield_meshes.has(scene):
		var meshes: Array[Mesh] = []
		var collection := scene.instantiate()
		for i in count:
			var part := collection.get_node("Shield%02d" % (i + 1)) as MeshInstance3D
			meshes.append(part.mesh)
		collection.free()
		spear_shield_meshes[scene] = meshes
	var part := MeshInstance3D.new()
	part.mesh = spear_shield_meshes[scene][shield_variant]
	var color := uniform_color()
	var source := part.get_active_material(0) as StandardMaterial3D
	if scene == SPEAR_SHIELDS:
		if not spear_shield_materials.has(color):
			var material := ShaderMaterial.new()
			material.shader = SPEAR_SHIELD_SHADER
			material.set_shader_parameter("base_texture", source.albedo_texture)
			material.set_shader_parameter("team_color", color)
			spear_shield_materials[color] = material
		part.material_override = spear_shield_materials[color]
	else:
		part.material_override = TroopColors.dye(source, color, TroopColors.Fabric.VARANGIAN_SHIELD)
	var prop := Node3D.new()
	prop.name = "SpearShield"
	prop.add_child(part)
	return prop

func has_kite_shield() -> bool:
	return shield_variant >= ROUND_SHIELD_COUNT

func use_sword_animation_pack() -> void:
	var aliases := {
		"idle_sword":"pack_idle_sword", "combat_sword":"pack_idle_sword",
		"guard_sword":"pack_guard_sword", "run_sword":"pack_run_sword",
		"backstep_sword":"pack_backstep_sword",
		"strafe_left_sword":"pack_strafe_left_sword", "strafe_right_sword":"pack_strafe_right_sword",
		"attack_sword":"pack_attack_2", "attack_sword_alt":"pack_attack_4",
		"guard_enter_sword":"pack_block_enter", "guard_exit_sword":"pack_block_exit",
		"block_sword":"pack_block_enter", "death_sword":"pack_death"
	}
	for alias: String in aliases:
		animation_map[alias] = animation_map[aliases[alias]]
		var looping: bool = alias.begins_with("idle") or alias.begins_with("combat") or alias.begins_with("run") or alias.begins_with("backstep") or alias.begins_with("strafe") or alias == "guard_sword"
		player.get_animation(animation_map[alias]).loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	for clip in ["idle_spear","combat_spear","walk_spear","walk_sword","advance_spear","advance_sword","run_spear","charge_spear","charge_sword","backstep_spear","strafe_left_spear","strafe_right_spear"]:
		animation_map[clip] = animation_map["motion_"+clip]
		player.get_animation(animation_map[clip]).loop_mode = Animation.LOOP_LINEAR
	for clip in ["run_spear", "run_sword"]:
		turn_run_shield(player.get_animation(animation_map[clip]))
	for entry in ["attack_spear", "attack_spear_alt"]:
		var source: String = "spear_pack_attack_1" if entry == "attack_spear" else "spear_pack_attack_2"
		if animation_map.has(source):
			animation_map[entry] = animation_map[source]
			player.get_animation(animation_map[entry]).loop_mode = Animation.LOOP_NONE
	for alias in SPEAR_COMBAT.attack_names():
		var source: String = SPEAR_COMBAT.attack(alias).clip
		if animation_map.has(source):
			animation_map[alias] = animation_map[source]
			player.get_animation(animation_map[alias]).loop_mode = Animation.LOOP_NONE
	var spear_guard: Dictionary = SPEAR_COMBAT.definitions().get("guard", {})
	for entry in [["combat_spear", "ready"], ["guard_enter", "enter"], ["guard_exit", "exit"]]:
		var source: String = spear_guard.get(entry[1], {}).get("clip", "")
		# Godot recognizes and strips the author's _loop naming suffix on import.
		if source.ends_with("_loop") and not animation_map.has(source) and animation_map.has(source.trim_suffix("_loop")):
			animation_map[source] = animation_map[source.trim_suffix("_loop")]
		if animation_map.has(source):
			animation_map[entry[0]] = animation_map[source]
			player.get_animation(animation_map[source]).loop_mode = Animation.LOOP_LINEAR if entry[1] == "ready" else Animation.LOOP_NONE

func turn_run_shield(animation: Animation) -> void:
	# The imported clips are shared. Turn each grip track once, about the shield's vertical axis.
	if animation.has_meta("run_shield_turned"):
		return
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D or not String(animation.track_get_path(track)).ends_with(":GripLeft"):
			continue
		var half_turn := Quaternion(Vector3.BACK, PI)
		for key in animation.track_get_key_count(track):
			var pose: Quaternion = animation.track_get_key_value(track, key)
			animation.track_set_key_value(track, key, (pose * half_turn).normalized())
		animation.set_meta("run_shield_turned", true)
		return

func make_socket(bone_name: String) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	if skeleton.find_bone(bone_name) < 0:
		for i in skeleton.get_bone_count():
			var candidate := skeleton.get_bone_name(i)
			if candidate.replace(":","").replace("_","") == bone_name.replace(":","").replace("_",""):
				bone_name = candidate
				break
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	return attachment

func uniform_color() -> Color:
	if is_instance_valid(cohesion_group):
		return cohesion_group.uniform_color
	return TroopColors.SKIRMISH_COLORS[team]

func apply_archer_tunic() -> void:
	var body := model.find_child("WarriorBody", true, false) as MeshInstance3D
	body.set_surface_override_material(0, TroopColors.dye(body.get_active_material(0),
		uniform_color(), TroopColors.Fabric.ARCHER, ARCHER_ALBEDO))

func apply_appearance() -> void:
	var body := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	# The downloaded sotnik uses the same rest mesh and UV layout as WarriorBody.
	var color := uniform_color()
	var key := [color, -1 if is_sotnik else appearance_index * HAIR_TONES.size() + hair_index]
	if not body_materials.has(key):
		var original := body.get_active_material(0) as StandardMaterial3D
		var shader := Shader.new()
		shader.code = """shader_type spatial;
#include "res://assets/troop_dye.gdshaderinc"
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D shirt_mask : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 team_color : source_color;
uniform vec3 hair_tone = vec3(1.0);
uniform float surface_roughness = .88;
uniform float surface_metallic = .05;
void fragment(){
 vec3 base=texture(base_texture,UV).rgb;
 float luminance=dot(base,vec3(.30,.59,.11));
 float saturation=(max(base.r,max(base.g,base.b))-min(base.r,min(base.g,base.b)))/max(.001,max(base.r,max(base.g,base.b)));
 // UV2 marks the head. Dark, warm hair is separated from skin and grey helmet metal.
 float hair=UV2.x*(1.0-smoothstep(.16,.28,luminance))*smoothstep(.08,.30,saturation)*smoothstep(.015,.06,base.r-base.b);
 // All infantry appearances share this atlas. Limit dye to the exposed shirt.
 float gold_trim=smoothstep(.14,.25,(base.g-base.b)/max(base.r,.001));
 float fabric=texture(shirt_mask,UV).r*(1.0-gold_trim);
 vec3 dyed=troop_dye(base,team_color.rgb,fabric,-VERTEX.z);
 ALBEDO=mix(dyed,base*hair_tone,hair);
 ROUGHNESS=surface_roughness;
 METALLIC=surface_metallic;
}
"""
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var texture: Texture2D = original.albedo_texture if appearance_index == 0 else BODY_TEXTURES[appearance_index]
		mat.set_shader_parameter("base_texture", SOTNIK_TEXTURE if is_sotnik else texture)
		mat.set_shader_parameter("shirt_mask", TroopColors.SHIRT_MASK)
		mat.set_shader_parameter("team_color", color)
		mat.set_shader_parameter("hair_tone", Vector3.ONE if is_sotnik else HAIR_TONES[hair_index])
		mat.set_shader_parameter("surface_roughness", original.roughness)
		mat.set_shader_parameter("surface_metallic", original.metallic)
		body_materials[key] = mat
	body.set_surface_override_material(0, body_materials[key])

func paint_shield() -> void:
	for mesh: MeshInstance3D in shield.find_children("*", "MeshInstance3D", true, false):
		var source := mesh.get_active_material(0) as StandardMaterial3D
		mesh.material_override = TroopColors.dye(source, uniform_color(), TroopColors.Fabric.SHIELD)

func make_scabbard() -> void:
	var sheath := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = Vector3(0.036, 0.90, 0.075) / 1.8
	sheath.mesh = shape
	sheath.rotation.x = PI / 2.0
	sheath.position.z = 0.43 / 1.8
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color("31271f")
	leather.roughness = 0.94
	sheath.material_override = leather
	belt_socket.add_child(sheath)
	var belt_loop := MeshInstance3D.new()
	var loop_shape := BoxMesh.new()
	loop_shape.size = Vector3(0.10, 0.12, 0.065) / 1.8
	belt_loop.mesh = loop_shape
	belt_loop.rotation.x = PI / 2.0
	belt_loop.position.z = 0.055
	belt_loop.material_override = leather
	belt_socket.add_child(belt_loop)

func make_animation_events() -> void:
	events = AnimationPlayer.new()
	events.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
	add_child(events)
	var library := AnimationLibrary.new()
	var actions := ["throw_spear", "draw_sword", "attack_spear", "attack_sword", "attack_sword_alt"]
	if animation_map.has("attack_spear_alt"): actions.append("attack_spear_alt")
	for action in actions:
		var clip := Animation.new()
		clip.length = player.get_animation(animation_map[action]).length
		var track := clip.add_track(Animation.TYPE_METHOD)
		clip.track_set_path(track, NodePath("."))
		var method := "release_spear" if action == "throw_spear" else "take_sword"
		var moment := 0.85 if action == "throw_spear" else 0.5
		if action.begins_with("attack"):
			method = "resolve_strike"
			moment = {"attack_spear":19.0/30.0,"attack_spear_alt":20.0/30.0,"attack_sword":.60,"attack_sword_alt":.14}[action]
		clip.track_insert_key(track, moment, {"method": method, "args": []})
		library.add_animation(action, clip)
	if not mounted:
		for alias in SPEAR_COMBAT.attack_names():
			if not animation_map.has(alias): continue
			var clip := Animation.new()
			clip.length = player.get_animation(animation_map[alias]).length
			var track := clip.add_track(Animation.TYPE_METHOD)
			clip.track_set_path(track, NodePath("."))
			var contacts: Array = SPEAR_COMBAT.contacts(alias)
			for i in contacts.size():
				clip.track_insert_key(track, float(contacts[i].time), {"method": "resolve_spear_contact", "args": [i]})
			library.add_animation(alias, clip)
	var cheer := Animation.new()
	cheer.length = 2.8
	library.add_animation("celebrate", cheer)
	events.add_animation_library("", library)
	events.animation_finished.connect(action_finished)

func play_clip(clip: String, blend := 0.18) -> void:
	if animation_name == clip:
		return
	spear_recoil_clip = null
	var phase := -1.0
	if is_gait(animation_name) and is_gait(clip) and player.current_animation_length > 0:
		phase = crowd_visual.phase() if crowd_visual and crowd_visual.distant else fmod(player.current_animation_position/player.current_animation_length,1.0)
	animation_name = clip
	player.speed_scale = 1.0
	if crowd_visual and crowd_visual.distant:
		crowd_visual.changed_clip(phase)
		return
	player.play(animation_map.get(clip, clip), blend)
	if phase >= 0:
		player.seek(phase*player.get_animation(animation_map[clip]).length)
	if crowd_visual: crowd_visual.changed_clip(phase)

func is_gait(clip: String) -> bool:
	var separator := clip.find("_")
	if separator < 0: return false
	match clip.substr(0,separator):
		"walk", "run", "advance", "charge", "backstep", "strafe": return true
	return false

func reset_approach() -> void:
	if is_finite(heading_before_local_contact):
		final_heading = heading_before_local_contact
		heading_before_local_contact = INF
	flank_waypoint=Vector3.INF
	flank_until=-1.0
	weapon_ready = false
	battle_cry_done = false
	contact_eta = INF
	combat_stall=0.0
	combat_detour=Vector3.INF
	detour_time=0.0
	combat_last_position=position

func order_move(destination: Vector3, heading: float, speed: float, defend: bool, front: bool) -> void:
	if not alive:
		return
	destination = FIELD.project(destination)
	var field := get_tree().current_scene
	if field != null and field.get("terrain") != null:
		destination = field.terrain.constrain(destination)
	if active_action == "celebrate":
		events.stop()
		busy = false
		active_action = ""
	celebrate_pending = false
	reset_approach()
	attack_order = false
	combat_target = null
	shield_raised = false
	hold_position = defend
	guard_anchor = destination
	target = destination
	final_heading = heading
	speed_limit = speed
	front_rank = front
	if guarding and not defend and not busy:
		play_clip("guard_exit" if has_spear else "guard_exit_sword")
		animation_clock = player.get_animation(animation_map[animation_name]).length
	guarding = defend
	reaction = fmod(index * 0.071, 0.28)
	navigation_timer = 0.0

func order_throw(point: Vector3, delay: float) -> void:
	if not has_sidearm:
		return
	if not alive or not has_spear or busy:
		return
	reset_approach()
	attack_order = false
	combat_target = null
	shield_raised = false
	guarding = false
	target = global_position
	throw_target = point
	final_heading = atan2(-(point.x - global_position.x), -(point.z - global_position.z))
	throw_wait = delay
	busy = true
	active_action = "aim"

func stop() -> void:
	if not alive:
		return
	reset_approach()
	attack_order = false
	combat_target = null
	celebrate_pending = false
	target = global_position
	guarding = false
	if active_action in ["aim", "celebrate"]:
		events.stop()
		busy = false
		throw_wait = -1.0
		active_action = ""

func flee(destination: Vector3, heading: float) -> void:
	fleeing = true
	events.stop()
	busy = false
	active_action = ""
	throw_wait = -1.0
	strike_target = null
	strike_done = true
	animation_clock = 0.0
	order_move(destination, heading, 4.8, false, false)

func disarm_for_surrender() -> void:
	if disarmed:
		return
	if crowd_visual:
		crowd_visual.sync_sockets()
	drop_held_weapon(global_basis.z*.36+global_basis.x*.18)
	if is_instance_valid(spear):
		spear.hide()
	if is_instance_valid(sword):
		sword.hide()
	disarmed = true

func leave_battlefield() -> void:
	withdrawn = true
	velocity = Vector3.ZERO
	agent.avoidance_enabled = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group("combatants")
	if crowd_visual and is_instance_valid(crowd_visual.renderer):
		crowd_visual.renderer.detailed_actors.erase(self)
		crowd_visual.renderer.sleeping_visuals.erase(crowd_visual)
		crowd_visual.renderer.stop_lod_transition(crowd_visual)
		crowd_visual.release_crowd()
	hide()
	set_process(false)
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if not alive: return
	if native_controlled:
		native_logic_elapsed += delta
		if (Engine.get_physics_frames()+native_logic_phase)%native_logic_cadence != 0: return
		run_native_logic(native_logic_elapsed)
		native_logic_elapsed = 0.0
		return
	var started := Time.get_ticks_usec() if PROF.enabled else 0
	physics_step(delta)
	if PROF.enabled: PROF.add("soldier_physics",started)

func can_batch_native_logic() -> bool:
	return true

func set_native_query_body(enabled: bool) -> void:
	if native_query_body == enabled: return
	native_query_body = enabled
	if enabled:
		movement_collision_mask = collision_mask
		collision_mask = 0
		PhysicsServer3D.body_set_mode(get_rid(),PhysicsServer3D.BODY_MODE_STATIC)
		native_query_transform = global_transform
		set_notify_transform(false)
		sync_native_query_position()
	else:
		set_notify_transform(true)
		PhysicsServer3D.body_set_mode(get_rid(),PhysicsServer3D.BODY_MODE_KINEMATIC)
		if alive and not withdrawn:
			collision_mask = movement_collision_mask
			PhysicsServer3D.body_set_state(get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,global_transform)

func sync_native_query_position() -> void:
	# A vertical capsule is radially symmetric. Keep its query transform
	# synchronized with movement without resubmitting every animation turn.
	native_query_transform.origin = global_position
	PhysicsServer3D.body_set_state(get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,native_query_transform)

func run_managed_native_logic(physics_time: float) -> void:
	if not managed_native_logic or not alive or withdrawn: return
	var elapsed := physics_time - native_logic_time
	native_logic_time = physics_time
	run_native_logic(elapsed)

func run_native_logic(elapsed: float) -> void:
	var started := Time.get_ticks_usec() if PROF.enabled else 0
	tick_native_logic(elapsed)
	if PROF.enabled: PROF.add("soldier_physics",started)

func physics_step(delta: float) -> void:
	movement_elapsed += delta
	var field := get_tree().current_scene
	var unit_total: int = field.squads.size()
	var interval := 0.0
	if unit_total > 10:
		interval = .13 if not crowd_visual else (.16 if crowd_visual.distant else .05)
	elif unit_total > 4:
		interval = .05
	interval *= Engine.time_scale
	if movement_elapsed < interval: return
	delta = movement_elapsed
	movement_elapsed = 0.0
	visual_position_from=position
	visual_yaw_from=rotation.y
	movement_duration=maxf(.001,delta)
	visual_elapsed=0.0
	attack_cooldown = maxf(0.0, attack_cooldown - delta * Experience.attack_tempo(experience_rank))
	damage_flash = maxf(0.0, damage_flash - delta)
	combat_think_timer -= delta
	if combat_think_timer <= 0:
		combat_think_timer = .18 if unit_total > 10 else .10
		var started := Time.get_ticks_usec() if PROF.enabled else 0
		update_combat()
		if PROF.enabled: PROF.add("combat",started)
	reaction = maxf(0.0, reaction - delta)
	track_combat_progress(delta)
	navigation_timer -= delta
	animation_clock = maxf(0.0, animation_clock - delta)
	var terrain: Node3D = field.terrain
	var fortified: bool = field.has_method("siege_waypoint") and not field.siege_gates.is_empty()
	var start_position := position
	var goal := movement_goal()
	var distance := global_position.distance_to(goal)
	var desired := Vector3.ZERO
	var can_move := not busy or moving_strike()
	if can_move and reaction <= 0.0 and distance > 0.10:
		if navigation_timer <= 0.0:
			if not flat_movement: agent.target_position = goal
			navigation_timer = 0.18
		var next := goal if flat_movement else agent.get_next_path_position()
		if fortified: next = field.siege_waypoint(position,goal,cohesion_group)
		if terrain: next = terrain.waypoint(position,next)
		var direction := next - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			desired = direction.normalized() * minf(speed_limit * speed_variation, distance * 2.8)
	var acceleration := BRAKING if desired.length_squared() < velocity.length_squared() else ACCELERATION
	var maximum_speed := speed_limit * speed_variation
	if not flat_movement: agent.max_speed = maximum_speed
	if flat_movement:
		var started := Time.get_ticks_usec() if PROF.enabled else 0
		avoidance_timer -= delta
		if desired.length_squared() > .001 and can_move:
			if avoidance_timer <= 0:
				avoidance_timer = .12
				avoidance_force = get_tree().current_scene.crowd_movement.avoidance(self,desired)-desired
			safe_velocity = (desired+avoidance_force).limit_length(maximum_speed)
		else:
			safe_velocity = Vector3.ZERO
			avoidance_force = Vector3.ZERO
		if PROF.enabled: PROF.add("avoidance",started)
	else:
		agent.velocity = velocity.move_toward(desired, delta * acceleration)
	# Avoidance must not turn a short sidestep into a sprint or bypass acceleration.
	velocity = velocity.move_toward(safe_velocity.limit_length(maximum_speed), delta * acceleration)
	velocity.y = 0.0
	if distance < 0.10 and desired.length() < 0.01:
		velocity = velocity.move_toward(Vector3.ZERO, delta * 10.0)
	if not can_move:
		velocity = velocity.move_toward(Vector3.ZERO, delta * 12.0)
	if velocity.length_squared() > .000001:
		if flat_movement:
			position += velocity*delta
		elif delta > get_physics_process_delta_time()*1.1:
			var collision := move_and_collide(velocity*delta)
			if collision:
				var remaining := collision.get_remainder().slide(collision.get_normal())
				if remaining.length_squared() > .000001: move_and_collide(remaining)
				velocity = velocity.slide(collision.get_normal())
		else: move_and_slide()
	position += step_charge_push(delta)
	if terrain and position != start_position: position = terrain.constrain(position)
	if fortified: position = field.constrain_siege_crossing(start_position,position)
	if absf(position.x) > field_half_size.x - .6 or absf(position.z) > field_half_size.y - .6:
		position = FIELD.clamp_ground(position, field_half_size, .6)
	motion_speed = velocity.length()
	update_footsteps(delta)
	var heading := final_heading
	var facing_enemy := faces_combat_target()
	if motion_speed > 0.15 and not busy and not facing_enemy:
		heading = atan2(-velocity.x, -velocity.z)
	if absf(angle_difference(rotation.y,heading)) > .00001:
		rotation.y = rotate_toward(rotation.y, heading, delta * 3.5)
	if busy:
		if active_action == "aim":
			throw_wait -= delta
			play_clip("idle_spear")
			if throw_wait <= 0.0 and absf(angle_difference(rotation.y, final_heading)) < 0.08 and motion_speed < 0.1:
				active_action = "throw_spear"
				play_clip("throw_spear", 0.12)
				events.play("throw_spear")
		return
	update_motion_animation(distance,facing_enemy)

func update_footsteps(delta: float) -> void:
	if not alive or motion_speed <= .18: return
	var galloping := mounted and motion_speed > 3.5
	if mounted and galloping != step_galloping:
		var old_spacing: float = GALLOP_CONTACT_SPACING[hoof_beat] if step_galloping else .55
		var new_spacing: float = GALLOP_CONTACT_SPACING[hoof_beat] if galloping else .55
		step_distance *= new_spacing / old_spacing
		step_galloping = galloping
	step_distance += motion_speed * delta
	var spacing := (1.05 if motion_speed > 2.5 else .72)
	if mounted:
		spacing = GALLOP_CONTACT_SPACING[hoof_beat] if motion_speed > 3.5 else .55
	# Bound catch-up after a long frame; never queue footsteps after the actor stops.
	for contact in 4:
		if step_distance < spacing: break
		step_distance -= spacing
		if effects: effects.footstep(global_position, motion_speed, index, mounted)
		if mounted:
			hoof_beat = (hoof_beat + 1) % 4
			spacing = GALLOP_CONTACT_SPACING[hoof_beat] if motion_speed > 3.5 else .55
	step_distance = minf(step_distance, spacing)

func movement_goal(project_height := true) -> Vector3:
	if is_finite(heading_before_local_contact):
		var contact_goal := position
		if is_instance_valid(combat_target) and combat_target.alive:
			var offset: Vector3 = (combat_target.position - position).slide(Vector3.UP)
			var gap := offset.length()
			var reach := weapon_reach()
			if gap > reach and gap <= LOCAL_CONTACT_RADIUS:
				contact_goal += offset / gap * (gap - reach * .9)
		return FIELD.project(contact_goal) if project_height else contact_goal
	var goal := movement_destination()
	if cohesion_group == null or not cohesion_group.is_physics_processing():
		return FIELD.project(goal) if project_height else goal
	# Move orders already assign a slot. Clipping distant slots to a circle
	# around the squad pulls both flanks inward as they march.
	if attack_order or fleeing:
		var centre: Vector3 = cohesion_group.center()
		goal = centre + (goal - centre).limit_length(cohesion_group.cohesion_radius)
	if cohesion_group.siege_counterattack:
		goal.z = minf(goal.z,get_tree().current_scene.siege_line - .8)
	return FIELD.project(goal) if project_height else goal

func movement_destination() -> Vector3:
	return target

func faces_combat_target() -> bool:
	return (attack_order or is_finite(heading_before_local_contact)) and not fleeing and is_instance_valid(combat_target) and combat_target.alive and not combat_target.withdrawn and (
		position.distance_squared_to(combat_target.position) < 20.25 or keeps_shield_forward()
	)

func combat_heading(offset: Vector3) -> float:
	return atan2(-offset.x, -offset.z)

func keeps_shield_forward() -> bool:
	return false

func penetrating_charge() -> bool:
	return false

func moving_strike() -> bool:
	return false

func tick_native_logic(delta: float) -> void:
	attack_cooldown=maxf(0,attack_cooldown-delta * Experience.attack_tempo(experience_rank))
	animation_clock=maxf(0,animation_clock-delta)
	reaction=maxf(0,reaction-delta)
	track_combat_progress(delta)
	if busy and active_action.begins_with("attack"):
		bracing_charge = false
		return
	var started:=Time.get_ticks_usec() if PROF.enabled else 0
	update_combat()
	if PROF.enabled: PROF.add("combat",started)
	if busy:
		if active_action=="aim":
			throw_wait-=delta
			play_clip("idle_spear")
			if throw_wait<=0 and absf(angle_difference(rotation.y,final_heading))<.08 and motion_speed<.1:
				active_action="throw_spear"
				play_clip("throw_spear",.12)
				events.play("throw_spear")
		return
	update_motion_animation(position.distance_to(target),faces_combat_target())

func update_motion_animation(distance: float, facing_enemy: bool) -> void:
	if animation_clock > 0.0:
		return
	var planted: bool = has_spear and front_rank and guarding and hold_position and distance < .24 and get_parent().get("fortified") == true
	if (bracing_charge or planted) and motion_speed < .45:
		play_clip("brace_spear" if animation_map.has("brace_spear") else "guard_front", .20)
		return
	var weapon := "spear" if has_spear else "sword"
	if motion_speed > 0.18:
		var running := motion_speed > 2.5
		var movement_clip := ("run_" if running else ("advance_" if shield_raised else "walk_")) + weapon
		if running and attack_order and (weapon_ready or keeps_shield_forward()):
			movement_clip = "charge_" + weapon
		if facing_enemy:
			var local_velocity := global_basis.inverse() * velocity
			if local_velocity.z > .12 and absf(local_velocity.z) > absf(local_velocity.x):
				movement_clip = "backstep_" + weapon
			elif absf(local_velocity.x) > .15 and absf(local_velocity.x) > absf(local_velocity.z):
				movement_clip = ("strafe_right_" if local_velocity.x > 0 else "strafe_left_") + weapon
		if not animation_map.has(movement_clip):
			movement_clip = "advance_" + weapon
		play_clip(movement_clip)
		player.speed_scale = movement_clip_rate(movement_clip, running)
	elif (attack_order or is_finite(heading_before_local_contact)) and is_instance_valid(combat_target) and combat_target.alive:
		play_clip("combat_" + weapon)
	elif guarding and distance < 0.16:
		var hold := "guard_sword" if not has_spear else ("guard_front" if front_rank else "guard_rear")
		if not animation_name.begins_with("guard"):
			play_clip("guard_enter" if has_spear else "guard_enter_sword")
			animation_clock = player.get_animation(animation_map[animation_name]).length
		else:
			play_clip(hold, 0.25)
	else:
		play_clip("idle_" + weapon)

func movement_clip_rate(movement_clip: String, running: bool) -> float:
	var clip_speed := 4.2 if running else 1.8
	if movement_clip.begins_with("run_") or movement_clip.begins_with("charge_"): clip_speed = 3.7
	elif movement_clip.begins_with("backstep_"): clip_speed = 3.92
	elif movement_clip.begins_with("strafe_"): clip_speed = 3.0
	return clampf(motion_speed / clip_speed, 0.16, 1.35)

func release_spear() -> void:
	if not alive or released or not has_spear:
		return
	if crowd_visual: crowd_visual.sync_sockets()
	released = true
	has_spear = false
	var projectile := Node3D.new()
	projectile.set_script(PROJECTILE)
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	projectile.source_team = team
	projectile.shooter = self
	get_tree().current_scene.add_child(projectile)
	var equipment := SPEAR.instantiate()
	projectile.add_child(equipment)
	var release_transform := spear.global_transform.orthonormalized()
	projectile.launch(release_transform, throw_target)
	spear.visible = false

func take_sword() -> void:
	if not alive or sword_drawn or not is_instance_valid(sword):
		return
	sword_drawn = true
	sword.reparent(right_socket, false)
	sword.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3.ONE / 1.8), Vector3.ZERO)

func action_finished(action: StringName) -> void:
	if not alive:
		return
	if action == &"celebrate":
		busy = false
		active_action = ""
		play_clip("idle_spear" if has_spear else "idle_sword")
		return
	if String(action).begins_with("attack"):
		busy = false
		active_action = ""
		strike_target = null
		attack_cooldown = rng.randf_range(.23, .52) if has_spear else rng.randf_range(.18, .45)
		if get_parent().get("wavering") == true: attack_cooldown *= 1.2
		return
	if action == &"throw_spear":
		active_action = "draw_sword"
		play_clip("draw_sword", 0.12)
		events.play("draw_sword")
	elif action == &"draw_sword":
		busy = false
		active_action = ""
		play_clip("idle_sword")
		if celebrate_pending:
			celebrate_victory()

func celebrate_victory() -> void:
	if not alive:
		return
	if busy and active_action in ["aim", "throw_spear", "draw_sword"]:
		celebrate_pending = true
		return
	stop()
	busy = true
	active_action = "celebrate"
	play_clip("victory_spear" if has_spear else "victory_sword", .2)
	player.speed_scale = .93 + fmod(index*.037,.14)
	events.play("celebrate")
	if effects and index % 8 == 0:
		effects.sound("grunt",global_position+Vector3.UP,-4.0)

func weapon_reach() -> float:
	return 1.85 if has_spear else 1.18

func preferred_reach() -> float:
	return 1.80 if has_spear else weapon_reach() * .80

func has_flank_plan() -> bool:
	return attack_order and get_tree().current_scene.battle_time < flank_until

func has_shield() -> bool:
	return true

func attack_approach_speed() -> float:
	if hold_position:
		return 1.8
	if mounted:
		var group := get_parent()
		if not group.has_method("can_run") or group.can_run():
			return attack_run_speed()
		return 1.8
	return attack_run_speed() if charge else 1.8

func nearby_attack_contact() -> CharacterBody3D:
	var battle := get_tree().current_scene
	if mounted:
		var rider := nearby_mounted_melee_target()
		if rider: return rider
	return battle.combat_index.nearest(position, team, weapon_reach() + .45)

func nearby_mounted_melee_target() -> CharacterBody3D:
	var best: CharacterBody3D
	var best_distance := INF
	for enemy in get_tree().current_scene.combat_index.nearby(position, team, MOUNT_MELEE_SEARCH_RADIUS):
		if not enemy.mounted: continue
		var offset: Vector3 = (enemy.position - position).slide(Vector3.UP)
		var distance := offset.length()
		if distance < best_distance and distance <= melee_reach_against(enemy) and clear_strike(enemy):
			best = enemy
			best_distance = distance
	return best

func nearest_melee_contact() -> CharacterBody3D:
	var battle := get_tree().current_scene
	var index_service: Node = battle.get("combat_index")
	if not index_service:
		return null
	var pursuit_limit: float = battle.siege_line - .7 if get_parent().get("siege_counterattack") == true else INF
	var nearest: CharacterBody3D
	var nearest_distance := INF
	var exposed: CharacterBody3D
	var exposed_distance := INF
	for enemy in index_service.nearby(position, team, LOCAL_CONTACT_RADIUS, true):
		if enemy.position.z >= pursuit_limit:
			continue
		var distance := position.distance_squared_to(enemy.position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
		if distance < exposed_distance and clear_strike(enemy):
			exposed = enemy
			exposed_distance = distance
	# If all nearby enemies are screened, an attacking fighter still closes locally.
	return exposed if exposed or not attack_order else nearest

func commit_formation_advance() -> void:
	if active_action in ["aim","throw_spear","draw_sword"]:
		events.stop()
		active_action = ""
		busy = false
		animation_clock = 0.0

func order_attack(opponent: CharacterBody3D, running: bool, hold := false) -> void:
	if not alive:
		return
	if not attack_order or opponent != combat_target or running != charge:
		reset_approach()
	if running: commit_formation_advance()
	attack_order = true
	combat_think_timer = 0.0
	combat_target = opponent
	var index_service:Node=get_tree().current_scene.get("combat_index")
	if index_service and is_instance_valid(opponent):combat_slot_angle=index_service.claim_angle(self,opponent)
	combat_last_position=position
	charge = running
	hold_position = hold
	guarding = hold
	shield_raised = not running or weapon_ready
	speed_limit = attack_approach_speed()
	reaction = rng.randf_range(0.0, .2)

func track_combat_progress(delta:float) -> void:
	update_strike_timer(delta)
	charge_recovery = maxf(0.0, charge_recovery - delta)
	threat_timer-=delta
	detour_time=maxf(0,detour_time-delta)
	approach_check-=delta
	if not attack_order or busy or animation_clock>0 or not is_instance_valid(combat_target):
		combat_stall=0.0
	elif combat_detour==Vector3.INF and (position-combat_last_position).dot((combat_target.position-combat_last_position).normalized())<.12*delta:
		combat_stall+=delta
	else:combat_stall=maxf(0,combat_stall-delta*.5)
	combat_last_position=position
	if detour_time<=0 or (combat_detour!=Vector3.INF and position.distance_squared_to(combat_detour)<1):combat_detour=Vector3.INF

func plan_flank() -> void:
	if hold_position or not is_instance_valid(combat_target):return
	# Local fallback for isolated duels only. Unit-scale flanks belong to battle_fronts.
	if has_flank_plan() or is_instance_valid(get_parent().attack_target): return
	var forward:Vector3=(combat_target.position-position).normalized()
	var right:=Vector3(forward.z,0,-forward.x)
	var side:=1.0 if index%2==0 else -1.0
	combat_detour=position+right*side*1.2+forward*.25
	combat_detour = FIELD.clamp_ground(combat_detour, field_half_size, 1.2)
	detour_time=1.4
	combat_stall=0

func time_to_contact(distance: float, direction: Vector3) -> float:
	var enemy_closing: float = -combat_target.velocity.dot(direction)
	if combat_target.attack_order and not combat_target.hold_position and is_instance_valid(combat_target.combat_target):
		var enemy_direction: Vector3 = (combat_target.combat_target.global_position-combat_target.global_position).normalized()
		enemy_closing = -enemy_direction.dot(direction)*combat_target.attack_run_speed()*combat_target.speed_variation
	var closing := (0.0 if hold_position else attack_run_speed()*speed_variation)+enemy_closing
	return maxf(0,distance-weapon_reach())/closing if closing > .25 else INF

func try_brace_charge() -> bool:
	var riders: Node3D = get_parent().get("incoming_cavalry")
	if not is_instance_valid(riders) or riders.attack_target != get_parent() or not riders.running_attack:
		return false
	var index_service: Node = get_tree().current_scene.get("combat_index")
	if not index_service:
		return false
	var incoming: CharacterBody3D
	var nearest := INF
	for rider in index_service.nearby(position, team, 9.0):
		if rider.get_parent() != riders or not rider.charge or not rider.attack_order:
			continue
		var offset: Vector3 = rider.position - position
		var distance := offset.length_squared()
		if distance < nearest and (-global_basis.z).dot(offset.normalized()) > .30 and rider.velocity.dot(offset) < -1.0:
			incoming = rider
			nearest = distance
	if not incoming:
		return false
	bracing_charge = true
	shield_raised = true
	var offset := incoming.position - position
	final_heading = atan2(-offset.x, -offset.z)
	target = position
	return true

func step_charge_push(delta: float) -> Vector3:
	if charge_push.is_zero_approx():
		return Vector3.ZERO
	var offset := charge_push * delta
	charge_push = charge_push.move_toward(Vector3.ZERO, delta * 14.0)
	return offset

func receive_charge(damage: float, attacker: CharacterBody3D, push: Vector3, planted: bool) -> void:
	receive_hit(damage, attacker, false, false, false, global_position + Vector3.UP, {"charge_impact": true})
	if not alive:
		return
	charge_recovery = .85 if planted else 1.8
	charge_push = (charge_push + push).limit_length(9.0)
	reaction = maxf(reaction, .38 if planted else .65)
	bracing_charge = false

func update_combat() -> void:
	bracing_charge = false
	if not attack_order and get_parent().has_method("allows_local_contact") and not get_parent().allows_local_contact():
		return
	if not fleeing and has_spear and not mounted and not busy and charge_recovery <= 0.0 and try_brace_charge() and not attack_order:
		return
	if fleeing:
		return
	if not attack_order:
		if not mounted and not busy:
			update_local_contact()
		return
	var contact := nearest_melee_contact() if not mounted and not busy else null
	if mounted and not busy and is_instance_valid(combat_target) and combat_target.mounted and not combat_target.fleeing:
		var gap := (combat_target.position - position).slide(Vector3.UP).length()
		if gap > melee_reach_against(combat_target) or not clear_strike(combat_target):
			contact = nearby_mounted_melee_target()
	if contact:
		combat_target = contact
		combat_stall = 0.0
		combat_detour = Vector3.INF
	if not is_instance_valid(combat_target) or not combat_target.alive or combat_target.withdrawn or combat_target.disarmed: return
	var offset: Vector3 = combat_target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > .15 and not busy:
		var squad := get_parent()
		if hold_position and squad.get("fortified") == true and distance > weapon_reach() + .5:
			final_heading = squad.get("order_heading")
		else:
			final_heading = combat_heading(offset)
	if not weapon_ready or not battle_cry_done:
		contact_eta = time_to_contact(distance,offset.normalized())
	if not hold_position and contact_eta <= ready_lead:
		weapon_ready = true
	shield_raised = not charge or weapon_ready or distance < 2.6
	if weapon_ready and not battle_cry_done and not busy and contact_eta <= cry_lead and distance > weapon_reach() and motion_speed > .5:
		battle_cry_done = true
		if effects: effects.battle_cry(global_position+Vector3.UP*1.6)
	if busy or animation_clock > 0.0:
		return
	var desired_range := preferred_reach()
	var minimum_range := .15
	var ready_to_strike := attack_cooldown <= 0.0 and absf(angle_difference(rotation.y, final_heading)) < .68
	var keep_anchor: bool = hold_position and get_parent().get("behavior_controlled") == true
	if ready_to_strike and not keep_anchor and can_intercept_swordsman(offset, distance):
		start_strike(SPEAR_INTERCEPT, SPEAR_VS_SWORD_THRUST_SPEED)
		return
	var planned := not contact and has_flank_plan()
	var strike_range := melee_reach_against(combat_target)
	var in_contact := distance <= strike_range
	var approach_speed := attack_approach_speed()
	speed_limit = approach_speed
	if hold_position:
		target = global_position if contact and in_contact else guard_anchor
	elif distance < minimum_range and not ready_to_strike:
		# Spears need room to thrust. Swords and knives deliberately close this gap.
		target = global_position-offset.normalized()*minf(.65,desired_range-distance)
		speed_limit = 1.1
	elif in_contact:
		target = global_position
		if not ready_to_strike and is_infantry_swordsman(self) and combat_target.has_spear and not combat_target.mounted:
			target += offset.normalized() * clampf(distance - desired_range, 0.0, .30)
		combat_stall=0.0
		combat_detour=Vector3.INF
		flank_until=-1.0
		flank_waypoint=Vector3.INF
	elif planned:
		if flank_waypoint!=Vector3.INF and position.distance_squared_to(flank_waypoint)<.65:
			flank_waypoint=Vector3.INF
		target=flank_waypoint if flank_waypoint!=Vector3.INF else combat_target.position-offset.normalized()*desired_range
	else:
		target=combat_target.position-offset.normalized()*desired_range
		if not contact and combat_stall>.9 and combat_detour==Vector3.INF: plan_flank()
		if combat_detour!=Vector3.INF: target=combat_detour
	# Follow a retreating opponent while closing with a short weapon.
	if not keep_anchor and not has_spear and distance<2.0 and distance>strike_range and (not planned or flank_waypoint==Vector3.INF):
		target+=combat_target.velocity.limit_length(1.1)*.45
	if distance<4.5 and not in_contact:
		var travel:=target-position
		if travel.length_squared()>.02 and travel.normalized().dot(offset.normalized())<.5:
			speed_limit=minf(speed_limit,1.45) # shield towards the threat while stepping sideways/back
		elif not mounted and not has_spear and combat_target.velocity.dot(offset.normalized())>.2:
			speed_limit=minf(speed_limit,1.8) # keep closing on a backpedalling spearman
		else: speed_limit=minf(speed_limit,maxf(.7,sqrt(5*maxf(0,distance-desired_range))))
	if in_contact and ready_to_strike:
		if clear_strike(combat_target):
			begin_strike()
		elif mounted and threat_timer <= .23:
			var exposed: CharacterBody3D = get_tree().current_scene.combat_index.immediate_threat(self,combat_target)
			if exposed: combat_target = exposed

func mount_support(direction: Vector3) -> float:
	# Match the horse footprint in the native crowd solver.
	var along := global_basis.z.dot(direction)
	return sqrt(lerpf(MOUNT_HALF_WIDTH ** 2, MOUNT_COLLISION_HALF_LENGTH ** 2, along * along))

func melee_reach_against(opponent: CharacterBody3D) -> float:
	var reach := weapon_reach()
	if mounted and opponent.mounted:
		var direction := (opponent.position - position).slide(Vector3.UP).normalized()
		reach = maxf(reach, mount_support(direction) + opponent.mount_support(direction) + MOUNT_MELEE_CLEARANCE)
	return reach

func update_local_contact() -> void:
	if threat_timer > 0.0 and not is_finite(heading_before_local_contact):
		return
	threat_timer = .18
	var reach := weapon_reach()
	var enemy := nearest_melee_contact()
	if not enemy:
		if is_finite(heading_before_local_contact):
			final_heading = heading_before_local_contact
			heading_before_local_contact = INF
			combat_target = null
		return
	if not is_finite(heading_before_local_contact):
		heading_before_local_contact = final_heading
	combat_target = enemy
	var offset := (enemy.global_position - global_position).slide(Vector3.UP)
	if offset.length_squared() > .0225:
		final_heading = combat_heading(offset)
	if offset.length_squared() <= reach * reach and animation_clock <= 0.0 and attack_cooldown <= 0.0 and absf(angle_difference(rotation.y, final_heading)) < .68:
		var ordered_destination := target
		begin_strike()
		target = ordered_destination

func can_intercept_swordsman(offset: Vector3, distance: float) -> bool:
	if not has_spear or mounted or distance <= preferred_reach() or distance > 4.0:
		return false
	if not is_infantry_swordsman(combat_target):
		return false
	if not combat_target.attack_order or combat_target.busy or not animation_map.has(SPEAR_INTERCEPT):
		return false
	var direction := offset / distance
	var enemy_velocity: Vector3 = combat_target.velocity.slide(Vector3.UP)
	if enemy_velocity.dot(-direction) < .6 or (-combat_target.global_basis.z).dot(-direction) < .5:
		return false
	var contact: Dictionary = SPEAR_COMBAT.contacts(SPEAR_INTERCEPT)[0]
	var advance := maxf(0.0, velocity.dot(direction))
	# The spearman brakes during the wind-up while the swordsman is still closing.
	var stopping_distance := advance * advance / (2.0 * (BRAKING + 12.0))
	var predicted := offset + enemy_velocity * (float(contact.time) / SPEAR_VS_SWORD_THRUST_SPEED) - direction * stopping_distance
	return predicted.length() <= weapon_reach() and clear_strike(combat_target)

func is_infantry_swordsman(fighter: CharacterBody3D) -> bool:
	return not fighter.has_spear and not fighter.mounted and fighter.has_shield()

func clear_strike(victim: CharacterBody3D) -> bool:
	if not strike_query:
		strike_query = PhysicsRayQueryParameters3D.new()
		strike_query.collision_mask = 2
		strike_query.exclude = [get_rid()]
	strike_query.from = global_position + Vector3.UP * 1.05
	strike_query.to = victim.global_position + Vector3.UP * 1.05
	var hit := get_world_3d().direct_space_state.intersect_ray(strike_query)
	return hit.is_empty() or hit.collider == victim

func begin_strike() -> void:
	var action := "attack_spear" if has_spear else ("attack_sword" if rng.randf() < .55 else "attack_sword_alt")
	var speed := 1.0
	if has_spear and not mounted:
		action = next_spear_attack()
		if is_infantry_swordsman(combat_target): speed = SPEAR_VS_SWORD_THRUST_SPEED
	elif has_spear and animation_map.has("attack_spear_alt") and rng.randf() < .45:
		action = "attack_spear_alt"
	elif is_infantry_swordsman(self) and combat_target.has_spear and not combat_target.mounted:
		speed = 1.13
	start_strike(action, speed)

func start_strike(action: String, speed: float) -> void:
	busy = true
	strike_done = false
	strike_elapsed = 0.0
	strike_speed = speed
	strike_impact_time = .36 if has_spear else .28
	strike_duration = .88 if has_spear else .72
	resolved_spear_contacts.clear()
	last_spear_contact.clear()
	strike_target = combat_target
	target = global_position
	active_action = action
	# Keep both visual representations in sync with the simulation timer.
	visual_delta = 0.0
	animation_name = ""
	if crowd_visual and crowd_visual.distant:
		crowd_visual.last_tick = get_tree().current_scene.battle_time
	play_clip(active_action, .12)
	player.speed_scale = speed
	if crowd_visual and crowd_visual.distant:
		crowd_visual.advance(0.0)
	else:
		player.seek(0.0, true)
	events.stop()
	if effects:
		effects.sound("swing", global_position + Vector3.UP, -9.0)
		if rng.randf() < .16:
			effects.sound("grunt", global_position + Vector3.UP, -7.0)

func update_strike_timer(delta: float) -> void:
	if not busy or not active_action.begins_with("attack"): return
	strike_elapsed += delta * strike_speed
	if not strike_done and strike_elapsed >= strike_impact_time:
		resolve_strike()
	if alive and busy and strike_elapsed >= strike_duration:
		action_finished(active_action)

func withdraw_spear(contact_time: float, speed := 2.0) -> void:
	if crowd_visual and crowd_visual.distant:
		crowd_visual.set_distant(false)
	var clip := player.get_animation(animation_map.get(animation_name, animation_name))
	if not clip:
		return
	var root_path := String(player.get_node(player.root_node).get_path_to(skeleton))
	var names := ["RiderUpperArm.R", "RiderForearm.R", "RiderHand.R"] if mounted else [
		"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand", "GripRight"
	]
	spear_recoil_tracks.clear()
	for name: String in names:
		var bone := skeleton.find_bone(name)
		if bone < 0:
			continue
		var path := NodePath(root_path + ":" + name)
		var position_track := clip.find_track(path, Animation.TYPE_POSITION_3D)
		var rotation_track := clip.find_track(path, Animation.TYPE_ROTATION_3D)
		if position_track >= 0 or rotation_track >= 0:
			spear_recoil_tracks.append(Vector3i(bone, position_track, rotation_track))
	if spear_recoil_tracks.is_empty():
		return
	spear_recoil_clip = clip
	spear_recoil_time = clampf(contact_time, 0.0, clip.length)
	spear_recoil_speed = speed * absf(player.speed_scale)
	spear_recoil_track_root = root_path
	spear_recoil_wrist = skeleton.find_bone("RiderHand.R") if mounted else -1
	spear_recoil_weapon = skeleton.find_bone("SpearRoot") if mounted else -1
	visual_delta = 0.0
	visual_interval = 0.0
	player.seek(maxf(player.current_animation_position, spear_recoil_time), true, true)
	update_spear_recoil(0.0)

func update_spear_recoil(delta: float) -> void:
	spear_recoil_time = maxf(0.0, spear_recoil_time - delta * spear_recoil_speed)
	var clip := spear_recoil_clip
	for track in spear_recoil_tracks:
		if track.y >= 0:
			skeleton.set_bone_pose_position(track.x, clip.position_track_interpolate(track.y, spear_recoil_time))
		if track.z >= 0:
			skeleton.set_bone_pose_rotation(track.x, clip.rotation_track_interpolate(track.z, spear_recoil_time))
	if spear_recoil_weapon >= 0 and spear_recoil_wrist >= 0:
		# The rider's spear is parented to the saddle rig, so preserve its pose relative to the hand.
		var wrist := SPEAR_COMBAT.sample_bone_chain(skeleton, spear_recoil_track_root, clip, spear_recoil_wrist, spear_recoil_time)
		var weapon := SPEAR_COMBAT.sample_bone_chain(skeleton, spear_recoil_track_root, clip, spear_recoil_weapon, spear_recoil_time)
		var current_wrist := skeleton.get_bone_global_pose(spear_recoil_wrist)
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(spear_recoil_weapon))
		skeleton.set_bone_pose(spear_recoil_weapon, parent.affine_inverse() * current_wrist * wrist.affine_inverse() * weapon)
	if spear_recoil_time == 0.0:
		spear_recoil_clip = null
		visual_lod_timer = 0.0
		resume_after_spear_recoil()

func resume_after_spear_recoil() -> void:
	# The strike was still running forward under the arm layer. Don't blend that arm back in.
	player.stop(true)
	update_motion_animation(position.distance_to(target), faces_combat_target())

func next_spear_attack() -> String:
	if spear_attack_bag.is_empty():
		for alias in spear_attack_pool():
			if animation_map.has(alias): spear_attack_bag.append(alias)
		if spear_attack_bag.is_empty(): return "attack_spear"
		for i in range(spear_attack_bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap := spear_attack_bag[i]
			spear_attack_bag[i] = spear_attack_bag[j]
			spear_attack_bag[j] = swap
		if spear_attack_bag.size() > 1 and spear_attack_bag[-1] == previous_spear_attack:
			var swap := spear_attack_bag[0]
			spear_attack_bag[0] = spear_attack_bag[-1]
			spear_attack_bag[-1] = swap
	previous_spear_attack = spear_attack_bag.pop_back()
	return previous_spear_attack

func spear_attack_pool() -> Array[String]:
	return SPEAR_COMBAT.attack_names()

func resolve_spear_contact(contact_index: int) -> void:
	if not alive or not busy or not has_spear or mounted or not SPEAR_COMBAT.is_attack(active_action): return
	var contacts: Array = SPEAR_COMBAT.contacts(active_action)
	if contact_index < 0 or contact_index >= contacts.size() or resolved_spear_contacts.has(contact_index): return
	resolved_spear_contacts[contact_index] = true
	strike_done = resolved_spear_contacts.size() == contacts.size()
	var contact: Dictionary = contacts[contact_index]
	last_spear_contact = {"clip": active_action, "index": contact_index, "zone": contact.zone, "outcome": "miss"}
	if not is_instance_valid(strike_target) or not strike_target.alive: return
	var offset: Vector3 = strike_target.global_position - global_position
	if offset.length() > weapon_reach() + .22 or (-global_basis.z).dot(offset.normalized()) < .72: return
	var ray: Dictionary = SPEAR_COMBAT.contact_ray(self, strike_target, contact)
	last_spear_contact["point"] = ray.point
	if ray.origin.distance_to(ray.point) > float(ray.reach) + .22: return
	var query := PhysicsRayQueryParameters3D.create(ray.origin, ray.point, 2, [get_rid()])
	var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty() and obstruction.collider != strike_target: return
	if is_infantry_swordsman(strike_target):
		# A thrust at spear distance can check the advance before swords make contact.
		ray["checks_advance"] = offset.length() > strike_target.weapon_reach()
		ray["short_thrust"] = not ray["checks_advance"]
	var damage := rng.randf_range(19.0, 28.0) * attack_damage_scale()
	if ray.get("short_thrust", false):
		# At sword distance the spear has less room to build force.
		damage *= .82
	strike_target.receive_hit(damage, self, false, false, false, ray.point, ray)
	last_spear_contact["outcome"] = strike_target.last_hit_result.get("outcome", "miss")
	if strike_done and last_spear_contact.outcome in ["body", "shield"]:
		withdraw_spear(float(contact.time))

func resolve_strike() -> void:
	if not alive or strike_done or not active_action.begins_with("attack"):
		return
	strike_done = true
	if not is_instance_valid(strike_target) or not strike_target.alive:
		return
	if strike_target.withdrawn: return
	var offset: Vector3 = (strike_target.global_position - global_position).slide(Vector3.UP)
	var distance := offset.length()
	if distance > melee_reach_against(strike_target) + .38 or (distance > .4 and (-global_basis.z).dot(offset / distance) < .45):
		return
	if not clear_strike(strike_target): return
	var damage := rng.randf_range(19.0, 28.0) if has_spear else rng.randf_range(22.0, 32.0)
	var context := {"timed_melee": true}
	if has_spear:
		context["checks_advance"] = not mounted and is_infantry_swordsman(strike_target) and distance > strike_target.weapon_reach()
		context["short_thrust"] = distance < 1.0
		if context.short_thrust: damage *= .82
		if active_action == "attack_spear_video": context["shield_damage_multiplier"] = .25
	strike_target.receive_hit(damage*melee_damage_scale(),self,false,false,false,Vector3.INF,context)
	if has_spear:
		last_spear_contact = {"clip":active_action,"outcome":strike_target.last_hit_result.get("outcome","miss")}

func receive_hit(damage: float, attacker: CharacterBody3D, projectile_hit := false, friendly_fire := false, arrow_hit := false, contact := Vector3.INF, hit_context: Dictionary = {}) -> bool:
	last_hit_result = {"outcome": "ignored", "blocked": false, "damage": 0.0, "zone": hit_context.get("zone", "body")}
	if not alive or withdrawn or disarmed or (is_instance_valid(attacker) and attacker.team == team and not friendly_fire):
		return false
	var direction := Vector3.FORWARD
	var attacking_squad: Node
	var hostile_melee := false
	if is_instance_valid(attacker):
		direction = (attacker.global_position - global_position).normalized()
		if attacker.team != team and damage > 0.0:
			hostile_melee = not projectile_hit
			if hostile_melee:
				damage *= Experience.melee_attack(attacker.experience_rank)
			attacking_squad = attacker.get_parent()
			if is_instance_valid(attacking_squad) and attacking_squad.has_method("set_experience"):
				attacking_squad.participated = true
			var defending_squad := get_parent()
			if not fleeing and defending_squad.has_method("set_experience"):
				defending_squad.participated = true
		if attacker.team != team and damage > 0.0 and not fleeing and get_parent().has_method("alert_enemy"):
			get_parent().alert_enemy(attacker.get_parent(),arrow_hit)
		if attacker.team != team and not projectile_hit and not fleeing and not attacker.fleeing and not busy and (not is_instance_valid(combat_target) or not combat_target.alive):
			# A nearby attacker, including one at our back, is an immediate threat.
			combat_target=attacker
			threat_timer=.6
	var facing := (-global_basis.z).dot(direction)
	var frontal := facing > .35
	var arrow_cover := arrow_hit and frontal and has_shield()
	var check_advance: bool = frontal and attack_order and hit_context.get("checks_advance", false)
	var ready_shield := has_shield() and (guarding or shield_raised or (attack_order and motion_speed < 2.4))
	var block_chance := .64 if guarding else .43
	if arrow_hit:
		block_chance *= .75
	if busy and active_action.begins_with("attack"):
		block_chance *= .55
	var blocked: bool = (hit_context.is_empty() or hit_context.get("timed_melee",false) == true) and ready_shield and frontal and rng.randf() < block_chance
	var authored_impact: Vector3 = hit_context.get("point", contact)
	if hit_context.has("origin"):
		var shield_contact: Dictionary = SPEAR_COMBAT.shield_intersection(self, hit_context.origin, hit_context.point)
		blocked = not shield_contact.is_empty()
		authored_impact = shield_contact.get("point", hit_context.point)
	if check_advance and get_parent().has_method("record_spear_pressure"):
		get_parent().record_spear_pressure(damage * (.25 if blocked else 1.0))
	last_hit_result["blocked"] = blocked
	last_hit_result["point"] = authored_impact
	var body_damage := damage * (1.0 - armor_reduction)
	if arrow_cover:
		body_damage *= .60
	if hostile_melee:
		body_damage *= 1.0 - Experience.melee_defense(experience_rank)
	if blocked:
		var shield_damage := damage * .08
		var minimum_hp := 1.0
		if hit_context.has("shield_damage_multiplier"):
			shield_damage = body_damage * float(hit_context.shield_damage_multiplier)
			minimum_hp = 0.0
		last_hit_result["outcome"] = "shield"
		last_hit_result["damage"] = minf(maxf(0.0, hp - minimum_hp), shield_damage)
		hp = maxf(minimum_hp, hp - shield_damage)
		if effects:
			var spear_hit: bool = not arrow_hit and (projectile_hit or (is_instance_valid(attacker) and attacker.has_spear))
			effects.impact(authored_impact if authored_impact.is_finite() else global_position + Vector3.UP * 1.15 - global_basis.z * .3, direction, true, arrow_hit, spear_hit)
		if hp <= 0.0:
			finish_hit_death(attacker, attacking_squad, direction)
		elif not busy:
			if check_advance: target = global_position
			play_clip("block" if has_spear else "block_sword", .06)
			animation_clock = player.get_animation(animation_map[animation_name]).length
		return false
	last_hit_result["outcome"] = "body"
	damage = body_damage
	last_hit_result["damage"] = minf(hp, damage)
	hp = maxf(0.0, hp - damage)
	var defending_squad := get_parent()
	if is_instance_valid(attacker) and attacker.team != team and defending_squad.has_method("record_morale_hit"):
		defending_squad.record_morale_hit(last_hit_result.damage / max_hp, hit_context.get("charge_impact", false))
		if not projectile_hit:
			defending_squad.record_flank_hit(facing, damage)
	damage_flash = 4.0
	if effects:
		var impact_point := authored_impact
		if not impact_point.is_finite():
			var toward_attacker := Vector3(direction.x, 0, direction.z).normalized()
			impact_point = global_position + Vector3.UP * 1.1 + toward_attacker * (.65 if mounted else .25)
		effects.impact(impact_point, -direction, false, arrow_hit)
		if DisplayServer.get_name() != "headless" and effects.visible_combat_detail(impact_point,70.0):
			if not body_wounds:
				body_wounds = BODY_WOUNDS.new()
			body_wounds.add_wound(self, impact_point, direction, arrow_hit)
	if hp <= 0.0:
		finish_hit_death(attacker, attacking_squad, direction)
	else:
		# Flinches interrupt attacks, but not an already committed throw/draw sequence.
		var committed_cut := busy and active_action.begins_with("attack") and damage < 32.0
		var covered_charge := arrow_cover and mounted and charge
		if not committed_cut and not covered_charge and (not busy or active_action.begins_with("attack")):
			if check_advance: target = global_position
			events.stop()
			busy = false
			active_action = ""
			strike_done = true
			play_clip("hit", .06)
			animation_clock = .48
			attack_cooldown = maxf(attack_cooldown, .45)
		if effects and rng.randf() < .40:
			effects.sound("grunt", global_position + Vector3.UP, -5.0)
	return true

func finish_hit_death(attacker: CharacterBody3D, attacking_squad: Node, direction: Vector3) -> void:
	if is_instance_valid(attacker) and attacker.team != team:
		attacker.kills += 1
		if is_instance_valid(attacking_squad) and attacking_squad.has_method("record_experience_kill"):
			attacking_squad.record_experience_kill(fleeing)
	die(direction)

func death_clip() -> String:
	var options := ["death_back", "death_side", "death_sword"]
	return options[rng.randi_range(0, options.size() - 1)]

func drop_held_weapon(impulse: Vector3) -> void:
	if has_spear:
		if mounted:
			var grip := right_socket.global_transform.orthonormalized()
			grip.basis *= Basis(Vector3.RIGHT, PI * .5)
			release_death_weapon(spear, SPEAR, grip, impulse)
		else:
			release_death_weapon(spear, SPEAR, spear.global_transform, impulse)
	elif sword_drawn:
		release_death_weapon(sword, SWORD, sword.global_transform, impulse)

func release_death_weapon(held: Node3D, scene: PackedScene, origin: Transform3D, impulse: Vector3) -> void:
	if not is_instance_valid(held) or not held.visible:
		return
	held.hide()
	if effects and effects.has_method("drop_weapon"):
		effects.drop_weapon(scene, origin, impulse, origin.basis.x.length())

func die(hit_direction := Vector3.ZERO) -> void:
	if not alive:
		return
	var fall_direction := -hit_direction.slide(Vector3.UP)
	var initial_velocity := velocity.slide(Vector3.UP)
	if fall_direction.is_zero_approx():
		fall_direction = global_basis.z
	var drift := fall_direction.normalized().rotated(Vector3.UP, rng.randf_range(-.7, .7))
	drift = drift * rng.randf_range(.14, .56) + initial_velocity.limit_length(3.0) * .10
	var start := global_position
	var destination := FIELD.clamp_ground(start + drift, field_half_size, .6)
	var heading := rotation.y
	var turn := rng.randf_range(-.66, .66)
	var fall_clip := death_clip()
	var show_dropped_weapon: bool = not effects or effects.visible_combat_detail(start,100.0)
	if crowd_visual and show_dropped_weapon:
		crowd_visual.sync_sockets()
	var weapon_impulse := drift + global_basis.x * .23
	if mounted:
		var side := 1.0 if fall_clip in ["death_side", "mount_death_side"] else -1.0
		weapon_impulse = drift * .55 + global_basis.x * side * 1.42
	if not disarmed and show_dropped_weapon:
		drop_held_weapon(weapon_impulse)
	alive = false
	if foot_placement: foot_placement.active = false
	if get_parent().has_method("soldier_died"): get_parent().soldier_died(self)
	hp = 0.0
	busy = false
	attack_order = false
	combat_target = null
	strike_target = null
	strike_done = true
	events.stop()
	active_action = "dead"
	velocity = Vector3.ZERO
	agent.velocity = Vector3.ZERO
	agent.avoidance_enabled = false
	collision_layer = 0
	PhysicsServer3D.body_set_shape_disabled(get_rid(),0,true)
	if crowd_visual and not mounted:
		corpse_roll = rng.randi_range(1, 5)
	play_clip(fall_clip, .09)
	if corpse_roll > 1:
		var hinge: Dictionary = crowd_visual.corpse_hinge()
		if hinge.is_empty():
			corpse_roll = 0
		else:
			corpse_pivot = hinge.pivot
			corpse_axis = hinge.axis
	player.speed_scale = rng.randf_range(.84, 1.18)
	var fall := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fall.tween_method(func(progress: float):
		global_position = start.lerp(destination, progress)
		rotation.y = heading + turn * progress
		visual_position_from = position
		visual_yaw_from = rotation.y
	, 0.0, 1.0, rng.randf_range(.28, .53))
	fall.finished.connect(func():
		corpse_at_rest = true
		if crowd_visual: crowd_visual.renderer.update_actor_rendering(self)
	)
	if effects:
		effects.sound("death", global_position + Vector3.UP * .6, -3.0)
		effects.blood_stain(global_position)
	# The last animation frame is retained, so corpses stay on the ground.
	set_physics_process(false)
