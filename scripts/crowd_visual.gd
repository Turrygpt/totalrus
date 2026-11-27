extends RefCounted
static var banks := {}
static var loading_banks := {}
var actor: CharacterBody3D
var bank: Resource
var archer_banks: Array[Resource] = []
var archer_lod := 0
var warrior_lod := 0
var use_warrior_lods := false
var clips := {}
var sockets: Array[BoneAttachment3D] = []
var distant := false
var clock := 0.0
var full_name := ""
var renderer: Node3D
var body_entry := {}
var shadow_entry := {}
var shield_entry := {}
var pose := {}
var last_tick := 0.0
var blend_started := -999.0
var previous_frame := -1.0
var previous_next := 0.0
var detail_meshes: Array[Dictionary] = []
var transition_progress := 0.0
var transition_to_distant := false
var detail_coverage := 0.0
var pose_start := 0.0
var pose_rate := 1.0
const LOD_FADE_SECONDS := .22
const ARCHER_BANKS := ["archer_mid", "archer_far", "archer_overview"]
const ARCHER_ENTER_DISTANCE := [26.0, 52.0, 126.0]
const ARCHER_RETURN_DISTANCE := [22.0, 44.0, 112.0]
const CrowdShadow = preload("res://scripts/crowd_shadow.gd")

static func request_bank(kind: String) -> void:
	if banks.has(kind) or loading_banks.has(kind): return
	var path := "res://assets/lod/"+kind+"_poses.res"
	if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path)==OK:
		loading_banks[kind] = path
	else:
		banks[kind] = null

static func bank_ready(kind: String) -> bool:
	if banks.has(kind): return true
	var path: String = loading_banks[kind]
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
	banks[kind] = ResourceLoader.load_threaded_get(path) if status==ResourceLoader.THREAD_LOAD_LOADED else null
	loading_banks.erase(kind)
	return true

func _init(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor
	var kind:String = actor.crowd_kind()
	if not banks.has(kind):
		var path := "res://assets/lod/"+kind+"_poses.res"
		banks[kind] = load(path) if ResourceLoader.exists(path) else null
	bank = banks[kind]
	if kind == "archer":
		for tier in ARCHER_BANKS: archer_banks.append(banks.get(tier))
	if bank:
		clips = bank.get_meta("clips")
		turn_baked_run_shields()
	renderer = actor.get_tree().current_scene.get("crowd_renderer")
	use_warrior_lods = renderer != null and not renderer.troop_meshes(kind).is_empty()

func turn_baked_run_shields() -> void:
	if bank.has_meta("run_shield_turned") or not bank.has_meta("pose_bones"):
		return
	var run_clips := ["motion_run_spear", "pack_run_sword", "axe/shield_charge"]
	if not run_clips.any(func(clip): return clips.has(clip)):
		return
	var bone_names: Array = bank.get_meta("bone_names")
	var grip := bone_names.find("GripLeft")
	if grip < 0:
		return
	var texture: ImageTexture = bank.get_meta("pose_bones")
	var image := texture.get_image()
	var half_turn := Basis(Vector3.BACK, PI)
	for clip in run_clips:
		if not clips.has(clip):
			continue
		var record: Dictionary = clips[clip]
		for frame in record.bones.size():
			var pose: Transform3D = record.bones[frame]["GripLeft"]
			pose.basis *= half_turn
			record.bones[frame]["GripLeft"] = pose
			for axis in 3:
				var column := pose.basis[axis]
				image.set_pixel(grip * 4 + axis, record.frame_start + frame, Color(column.x, column.y, column.z, 0.0))
	texture.update(image)
	bank.set_meta("run_shield_turned", true)

func supports_current() -> bool:
	return not actor.spear_recoil_clip and renderer != null and bank != null and bank.has_meta("pose_mesh") and clips.has(actor.animation_map.get(actor.animation_name,""))

func request_distant(value: bool) -> bool:
	if not supports_current():
		set_distant(false)
		renderer.detailed_actors.erase(actor)
		return true
	if not detail_meshes.is_empty(): return transition_to_distant == value
	if value == distant: return true
	if renderer.instant_lod or renderer.camera_is_travelling():
		set_distant(value)
		return true
	var camera := actor.get_viewport().get_camera_3d()
	if not camera or not actor.is_visible_in_tree() or camera.global_position.distance_squared_to(actor.global_position) > 32.0 * 32.0 or not camera.is_position_in_frustum(actor.global_position + Vector3.UP):
		set_distant(value)
		return true
	if not renderer.start_lod_transition(self): return false
	transition_to_distant = value
	transition_progress = 0.0
	if value:
		acquire_crowd()
	else:
		distant = false
		restore_rig()
	use_lod_materials()
	apply_lod_coverage(.9375 if value else 0.0, true)
	return true

func use_lod_materials() -> void:
	for mesh: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
		if not mesh.mesh or (mesh.get_parent() != actor and not actor.model.is_ancestor_of(mesh)):
			continue
		var state := {"mesh": mesh, "material": mesh.material_override, "surfaces": []}
		if mesh.material_override:
			var fade: ShaderMaterial = renderer.lod_material(mesh.material_override)
			if fade: mesh.material_override = fade
		else:
			for surface in mesh.mesh.get_surface_count():
				state.surfaces.append(mesh.get_surface_override_material(surface))
				var original := mesh.get_active_material(surface)
				var fade: ShaderMaterial = renderer.lod_material(original) if original else null
				if fade: mesh.set_surface_override_material(surface, fade)
		detail_meshes.append(state)

func restore_lod_materials() -> void:
	for state in detail_meshes:
		var mesh: MeshInstance3D = state.mesh
		if not is_instance_valid(mesh): continue
		mesh.material_override = state.material
		for surface in state.surfaces.size():
			mesh.set_surface_override_material(surface, state.surfaces[surface])
		mesh.set_instance_shader_parameter(&"lod_detail", 1.0)
	if actor.body_wounds:
		actor.body_wounds.restore_materials()
	detail_meshes.clear()
	detail_coverage = 0.0
	renderer.stop_lod_transition(self)

func apply_lod_coverage(value: float, force := false) -> void:
	if force or detail_coverage != value:
		detail_coverage = value
		for state in detail_meshes:
			if is_instance_valid(state.mesh): state.mesh.set_instance_shader_parameter(&"lod_detail", value)
	sync_crowd_to_rig()

func update_lod_transition(delta: float) -> void:
	# Keep several mixed frames even if the first use compiles a new material.
	transition_progress += minf(delta, .05) / LOD_FADE_SECONDS
	if transition_progress >= 1.0 or not supports_current():
		set_distant(transition_to_distant and supports_current())
		return
	var position := smoothstep(0.0, 1.0, transition_progress)
	if transition_to_distant: position = 1.0 - position
	apply_lod_coverage(minf(.9375, roundf(position * 16.0) / 16.0))

func sync_crowd_to_rig() -> void:
	full_name = actor.animation_map.get(actor.animation_name,"")
	if not clips.has(full_name): return
	clock = actor.player.current_animation_position
	advance(0.0, true)

func set_distant(value: bool) -> void:
	var started:=Time.get_ticks_usec() if preload("res://scripts/profile_counters.gd").enabled else 0
	set_distant_impl(value)
	if preload("res://scripts/profile_counters.gd").enabled:preload("res://scripts/profile_counters.gd").add("lod_switch",started)

func set_distant_impl(value: bool) -> void:
	value = value and supports_current()
	if not detail_meshes.is_empty():
		restore_lod_materials()
		if not value: release_crowd()
	if value == distant: return
	if value:
		renderer.detailed_actors.erase(actor)
		if body_entry.is_empty(): acquire_crowd(wanted_archer_lod(), wanted_warrior_lod())
		sync_crowd_to_rig()
		distant = true
		actor.player.pause()
		# Keep the skin and its attachments registered while the batched body is visible.
		actor.model.hide()
		if actor.foot_placement: actor.foot_placement.active = false
		if actor.has_method("set_distant_details"): actor.set_distant_details(true)
		var movement: Node = renderer.get_tree().current_scene.crowd_movement
		if movement.native != null:
			# The batched model follows the solver, so the hidden rig can stop
			# inheriting transforms from the moving fighter until it is shown again.
			if movement.high_load: actor.model.top_level = true
			last_tick=renderer.get_tree().current_scene.battle_time
			if not is_instance_valid(actor.cohesion_group) or not actor.cohesion_group.reinforcement_pending:
				renderer.sleeping_visuals.append(self)
			actor.set_process(false)
	else:
		distant = false
		restore_rig()
		release_crowd()

func wanted_archer_lod() -> int:
	if archer_banks.is_empty(): return 0
	var camera := actor.get_viewport().get_camera_3d()
	if not camera: return 0
	var distance := camera.global_position.distance_squared_to(actor.global_position)
	for index in range(archer_banks.size() - 1, -1, -1):
		var limit: float = ARCHER_RETURN_DISTANCE[index] if archer_lod >= index + 1 else ARCHER_ENTER_DISTANCE[index]
		if archer_banks[index] and distance > limit * limit: return index + 1
	return 0

func wanted_warrior_lod() -> int:
	if not use_warrior_lods: return 0
	var camera := actor.get_viewport().get_camera_3d()
	if not camera: return 0
	var distance := camera.global_position.distance_squared_to(actor.global_position)
	var size_scale := 1.22 if actor.mounted else 1.0
	var far_limit := (51.0 if warrior_lod == 2 else 60.0) * size_scale
	var mid_limit := (27.0 if warrior_lod >= 1 else 34.0) * size_scale
	if distance > far_limit * far_limit: return 2
	return 1 if distance > mid_limit * mid_limit else 0

func refresh_distance_lod() -> bool:
	if (archer_banks.is_empty() and not use_warrior_lods) or not distant or not detail_meshes.is_empty() or body_entry.is_empty(): return false
	var wanted := wanted_archer_lod()
	var wanted_warrior := wanted_warrior_lod()
	if wanted == archer_lod and wanted_warrior == warrior_lod: return false
	if wanted_warrior != warrior_lod and not renderer.warrior_lod_in_view(actor): return false
	if not renderer.permit_mesh_swap(): return false
	if wanted == archer_lod:
		warrior_lod = wanted_warrior
		body_entry = renderer.replace_body_mesh(body_entry, renderer.combined_mesh(actor,bank,sockets,warrior_lod))
		return true
	var blend_frame := previous_frame
	release_crowd()
	acquire_crowd(wanted, wanted_warrior)
	previous_frame = blend_frame
	# A settled corpse still needs its final pose written into the new slots.
	advance(0.0, true)
	return true

func prepare_archer_meshes() -> void:
	if not bank: return
	sockets.assign(actor.skeleton.get_children().filter(func(n):return n is BoneAttachment3D))
	renderer.batch_for(renderer.combined_mesh(actor,bank,sockets), null, actor.crowd_kind(), false)
	for lod_bank in archer_banks:
		if lod_bank: renderer.batch_for(renderer.combined_mesh(actor,lod_bank,sockets), null, actor.crowd_kind(), false)
	renderer.batch_for(CrowdShadow.new().build(actor,bank,sockets), null, actor.crowd_kind(), true)
	var body_only: Array[BoneAttachment3D] = []
	renderer.batch_for(CrowdShadow.new().build(actor,bank,body_only), null, actor.crowd_kind(), true)

func acquire_crowd(lod := 0, infantry_lod := 0) -> void:
	sockets.assign(actor.skeleton.get_children().filter(func(n):return n is BoneAttachment3D))
	archer_lod = lod
	warrior_lod = infantry_lod
	var render_bank := archer_banks[lod - 1] if lod > 0 else bank
	var shadow_sockets: Array[BoneAttachment3D] = []
	if not render_bank.get_meta("archer_body_only",false): shadow_sockets = sockets
	body_entry=renderer.acquire(renderer.combined_mesh(actor,render_bank,sockets,warrior_lod),null,actor,Transform3D.IDENTITY)
	shadow_entry=renderer.acquire(CrowdShadow.new().build(actor,bank,shadow_sockets),null,actor,Transform3D.IDENTITY,true)
	if actor.shield_variant >= 0:
		shield_entry = renderer.acquire(renderer.spear_shield_mesh(actor, bank), null, actor, Transform3D.IDENTITY)
	previous_frame = -1.0

func restore_rig() -> void:
	renderer.sleeping_visuals.erase(self)
	actor.set_process(true)
	actor.visual_delta = 0.0
	actor.model.top_level = false
	actor.update_render_model_transform()
	actor.visual_pose_will_update()
	var record: Dictionary = clips.get(full_name, {})
	if not record.is_empty():
		var current_time: float = actor.get_tree().current_scene.battle_time
		clock = maxf(0.0, (current_time-pose_start)*pose_rate)
		clock = fmod(clock, record.duration) if record.loop else minf(clock, record.duration)
		actor.player.play(full_name,0)
		actor.player.seek(clock,true); actor.player.advance(0)
		actor.skeleton.force_update_all_bone_transforms()
	elif actor.player.has_animation(full_name):
		actor.player.play(full_name, 0)
		actor.player.advance(0)
	if actor.body_wounds:
		actor.body_wounds.restore_materials()
	actor.model.show()
	if actor.foot_placement and actor.alive:
		actor.foot_placement.active = true
		actor.skeleton.advance(0.0)
	actor.visual_pose_updated()
	if actor.has_method("set_distant_details"): actor.set_distant_details(false)

func release_crowd() -> void:
	renderer.release(body_entry); body_entry={}
	renderer.release(shadow_entry); shadow_entry={}
	renderer.release(shield_entry)
	shield_entry = {}
func changed_clip(value: float) -> void:
	if not distant: return
	if actor.get_tree().paused:
		previous_frame = -1.0
	elif clips.has(full_name):
		var old:Dictionary=clips[full_name]
		var phase:float=clock/maxf(.001,old.duration)*(8 if old.loop else 7)
		var frame:=mini(7,floori(phase))
		previous_frame=old.frame_start+frame+fmod(phase,1.0)
		previous_next=old.frame_start+((frame+1)%8 if old.loop else mini(frame+1,7))
		blend_started=actor.get_tree().current_scene.battle_time
	full_name = actor.animation_map.get(actor.animation_name,"")
	if not clips.has(full_name): set_distant(false); return
	clock = maxf(0,value)*float(clips[full_name].duration)
	advance(0)
func phase() -> float:
	return fmod(clock/maxf(.001,float(clips[full_name].duration)),1.0) if distant else -1.0
func advance(delta: float, force := false) -> void:
	if body_entry.is_empty(): return
	var shown := actor.is_visible_in_tree()
	var record: Dictionary = clips[full_name]
	if not force and not actor.alive and actor.corpse_at_rest and not record.loop and clock >= record.duration and shown == body_entry.shown:
		return
	body_entry.shown = shown
	shadow_entry.shown = shown
	clock += delta*actor.player.speed_scale
	clock = fmod(clock,record.duration) if record.loop else minf(clock,record.duration)
	var frame := mini(7,int(clock/record.duration*(8 if record.loop else 7)))
	pose = record.bones[frame]
	var rate: float = maxf(.001,actor.player.speed_scale)
	var start: float = actor.get_tree().current_scene.battle_time-clock/rate
	pose_start = start
	pose_rate = rate
	renderer.custom(body_entry,Color(record.frame_start,record.duration if record.loop else -record.duration,start,rate))
	renderer.custom(shadow_entry,Color(record.frame_start,record.duration if record.loop else -record.duration,start,rate))
	var held: Node3D=actor.get("held_arrow")
	# Travel normally encodes 0–48. Value 63 marks weapons dropped on surrender.
	var travel := 63.0 if actor.disarmed else roundf(clampf(actor.motion_speed,0,6)*8)
	var flags:=float(actor.has_spear)+(0.0 if actor.alive else 2.0)+float(actor.sword_drawn)*4.0+(float(held.visible)*8.0 if held else 0.0)+16.0*travel
	var data:=Color(flags + detail_coverage,blend_started,previous_frame,previous_next)
	# The visible batch packs pitch and wound rows above the ten bits used by pose data.
	var row: int = actor.body_wounds.row if actor.body_wounds else 0
	var aim := 0
	if actor.has_method("bow_pitch"):
		var pitch: float = actor.bow_pitch()
		if not is_zero_approx(pitch):
			aim = roundi(rad_to_deg(pitch) * 2.0) + 64
	if not actor.alive:
		aim = actor.corpse_roll
	renderer.appearance(body_entry,Color(data.r + aim * 1024, data.g, data.b, data.a + row * 1024))
	renderer.appearance(shadow_entry, Color(data.r + actor.corpse_roll * 1024, data.g, data.b, data.a))
	if not shield_entry.is_empty():
		shield_entry.shown = body_entry.shown
		renderer.custom(shield_entry, Color(record.frame_start, record.duration if record.loop else -record.duration, start, rate))
		renderer.appearance(shield_entry, Color(data.r + aim * 1024, data.g, data.b, data.a))

func corpse_hinge() -> Dictionary:
	var clip: String = actor.animation_map.get(actor.animation_name, "")
	if not clips.has(clip):
		return {}
	var bones: Dictionary = clips[clip].bones[-1]
	var hip := Transform3D.IDENTITY
	var neck := Transform3D.IDENTITY
	for name: String in bones:
		if name.ends_with("_Hips") or name.ends_with(":Hips"): hip = bones[name]
		if name.ends_with("_Neck") or name.ends_with(":Neck"): neck = bones[name]
	var axis := (neck.origin - hip.origin).slide(Vector3.UP).normalized()
	return {} if axis.is_zero_approx() else {"axis": axis, "pivot": hip.origin}
func sync_sockets() -> void:
	if not distant: return
	for socket in sockets:
		if pose.has(socket.bone_name): socket.global_transform=actor.global_transform*pose[socket.bone_name]

func bone_transform(bone: String) -> Transform3D:
	var record: Dictionary = clips[full_name]
	var phase: float = clock / record.duration * (8.0 if record.loop else 7.0)
	var frame := mini(7, floori(phase))
	var next := (frame + 1) % 8 if record.loop else mini(7, frame + 1)
	var current: Transform3D = record.bones[frame].get(bone, Transform3D.IDENTITY)
	var following: Transform3D = record.bones[next].get(bone, current)
	return current.interpolate_with(following, fmod(phase, 1.0))
