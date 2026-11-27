extends Node3D
const PROF = preload("res://scripts/profile_counters.gd")
const BODY_WOUNDS = preload("res://scripts/body_wounds.gd")
const FOOT_PLACEMENT = preload("res://scripts/infantry_foot_placement.gd")
const CrowdVisual = preload("res://scripts/crowd_visual.gd")
const Warrior = preload("res://scripts/soldier.gd")
var warrior_meshes: Resource = Warrior.WARRIOR_MESHES if Warrior.warrior_lods_enabled else null
# Shared instance buffers: one draw per mesh/material, including GPU-animated bodies.
static var clock_registered := false
var foot_ground: ImageTexture
var batches := {}
var actor_entries := {}
var packed_animation_updates := false
var pose_materials := {}
var coat_materials := {}
var combined := {}
var sleeping_visuals: Array = []
var visual_clock := 0.0
var detailed_actors := {}
var lod_transitions := {}
var lod_materials := {}
var shared_shaders := {}
var lod_transition_cost := 0
var far_cursor := 0
var instant_lod := false
var manages_initial_visuals := false
var pending_visuals := {}
var prepared_archer_teams := {}
var prepared_warrior_meshes := {}
var prepared_wound_models := {}
var mesh_swaps := 0
var mesh_swaps_pending := false
var detailed_promoted_frame := -1
var visual_credit := 0.0
var last_visual_physics_frame := -1
var defer_detail := false
enum Armbands { EXCLUDE, INCLUDE, ONLY }

const MESH_SWAPS_PER_FRAME := 16
var rendered_camera_transform := Transform3D.IDENTITY
const HIDDEN_INSTANCE := -1
const STATIC_INSTANCE := -2
const DETAIL_BUDGET := 16
const TRANSITION_BUDGET := 6
const LOD_MASK := "#include \"res://assets/crowd_lod_mask.gdshaderinc\"\n"

func camera_is_travelling() -> bool:
	var field := get_tree().current_scene
	return field.squads.size() >= 24 and Time.get_ticks_msec() - field.camera_last_moved_ms < 180

func troop_meshes(kind: String) -> Array:
	if not warrior_meshes: return []
	if kind == "soldier": return warrior_meshes.get_meta("body_meshes")
	return warrior_meshes.get_meta("unit_meshes",{}).get(kind,[])

func permit_mesh_swap() -> bool:
	if mesh_swaps >= MESH_SWAPS_PER_FRAME:
		mesh_swaps_pending = true
		return false
	mesh_swaps += 1
	return true

func warrior_lod_in_view(actor: Node3D) -> bool:
	var field := get_tree().current_scene
	if field.squads.size() < 24 or field.camera_distance >= 235.0: return true
	var camera := get_viewport().get_camera_3d()
	return camera == null or camera.is_position_in_frustum(actor.global_position + Vector3.UP)

func allow_detail(actor: Node3D, distance_squared: float) -> bool:
	var large_battle: bool = get_tree().current_scene.squads.size() >= 24
	# The closest baked tier keeps the models animated without waking a full
	# skeleton at the instant the camera stops. Unique leaders keep their rig.
	if large_battle and actor.crowd_kind() != "prince" and actor.crowd_visual and actor.crowd_visual.supports_current():
		return false
	var already_detailed := detailed_actors.has(actor)
	var limit := 22.0 if already_detailed else 18.0
	var camera := get_viewport().get_camera_3d()
	if not camera or not actor.is_visible_in_tree() or distance_squared>limit*limit:
		return false
	var frame := Engine.get_process_frames()
	var limit_promotions := large_battle
	if not already_detailed and (camera_is_travelling() or (limit_promotions and (defer_detail or detailed_promoted_frame == frame))):
		return false
	var sample := actor.global_position + Vector3.UP
	if not camera.is_position_in_frustum(sample):
		if not already_detailed or camera.is_position_behind(sample):
			return false
		var viewport_rect := get_viewport().get_visible_rect()
		if not viewport_rect.grow(viewport_rect.size.y * .12).has_point(camera.unproject_position(sample)):
			return false
	if already_detailed:return true
	var used:=0
	for other in detailed_actors:used+=other.detail_cost
	if used+actor.detail_cost>DETAIL_BUDGET:
		var farthest: Node3D
		var greatest := distance_squared*1.4
		for other:Node3D in detailed_actors:
			var d:float=camera.global_position.distance_squared_to(other.global_position)
			if d>greatest:greatest=d;farthest=other
		if not farthest or used-farthest.detail_cost+actor.detail_cost>DETAIL_BUDGET:return false
		if not farthest.crowd_visual.request_distant(true):return false
		detailed_actors.erase(farthest)
	detailed_actors[actor]=true
	if limit_promotions: detailed_promoted_frame = frame
	return true

func start_lod_transition(visual: RefCounted) -> bool:
	var cost: int = visual.actor.detail_cost
	if lod_transition_cost + cost > TRANSITION_BUDGET: return false
	lod_transitions[visual] = cost
	lod_transition_cost += cost
	return true

func stop_lod_transition(visual: RefCounted) -> void:
	lod_transition_cost -= lod_transitions.get(visual, 0)
	lod_transitions.erase(visual)

func lod_material(original: Material) -> ShaderMaterial:
	if lod_materials.has(original): return lod_materials[original]
	var material := ShaderMaterial.new()
	if original is ShaderMaterial:
		var code: String = original.shader.code
		var fragment := code.find("void fragment")
		if fragment < 0: return null
		var start := code.find("{", fragment)
		code = code.insert(start+1, "\nif (lod_threshold(FRAGCOORD.xy) >= lod_detail) { discard; }\n")
		code = code.insert(fragment, "\n" + LOD_MASK + "instance uniform float lod_detail : instance_index(15) = 1.0;\n")
		material.shader = shader_for_code(code)
		for parameter in original.shader.get_shader_uniform_list():
			material.set_shader_parameter(parameter.name, original.get_shader_parameter(parameter.name))
	elif original is StandardMaterial3D:
		material.shader = preload("res://assets/crowd_lod_detail.gdshader")
		material.set_shader_parameter("base_tint", original.albedo_color)
		material.set_shader_parameter("base_texture", original.albedo_texture)
		material.set_shader_parameter("roughness", original.roughness)
		material.set_shader_parameter("roughness_texture", original.roughness_texture)
		material.set_shader_parameter("roughness_channel", texture_channel(original.roughness_texture_channel))
		material.set_shader_parameter("metallic", original.metallic)
		material.set_shader_parameter("metallic_texture", original.metallic_texture)
		material.set_shader_parameter("metallic_channel", texture_channel(original.metallic_texture_channel))
		material.set_shader_parameter("specular", original.metallic_specular)
		material.set_shader_parameter("has_normal", original.normal_enabled)
		material.set_shader_parameter("normal_texture", original.normal_texture)
		material.set_shader_parameter("normal_scale", original.normal_scale)
		material.set_shader_parameter("cutout", original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
		material.set_shader_parameter("cutout_threshold", original.alpha_scissor_threshold)
	else:
		return null
	material.next_pass = original.next_pass
	lod_materials[original] = material
	return material

func texture_channel(channel: int) -> Vector4:
	if channel >= 4: return Vector4(.3333, .3333, .3333, 0)
	var mask := Vector4.ZERO
	mask[channel] = 1.0
	return mask
func shader_for_code(code: String) -> Shader:
	if not shared_shaders.has(code):
		var shader := Shader.new()
		shader.code = code
		shared_shaders[code] = shader
	return shared_shaders[code]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not clock_registered:
		clock_registered = true
		RenderingServer.global_shader_parameter_add("crowd_time",RenderingServer.GLOBAL_VAR_TYPE_FLOAT,0.0)
		RenderingServer.global_shader_parameter_add("crowd_foot_ground",RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,null)
		RenderingServer.global_shader_parameter_add("crowd_foot_grid",RenderingServer.GLOBAL_VAR_TYPE_VEC4,Vector4.ZERO)
	var terrain: Node3D = get_parent().get("terrain")
	if terrain:
		var size: Vector2i = terrain.grid_size
		var ground := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, terrain.heights.to_byte_array())
		foot_ground = ImageTexture.create_from_image(ground)
		var half: Vector2 = terrain.grid_half
		var step: Vector2 = terrain.grid_step
		RenderingServer.global_shader_parameter_set("crowd_foot_ground",foot_ground)
		RenderingServer.global_shader_parameter_set("crowd_foot_grid",Vector4(half.x, half.y, 1.0 / step.x, 1.0 / step.y))

func prepare_visuals(groups: Array[Node3D]) -> void:
	manages_initial_visuals = true
	if "--no-crowd-lod" in OS.get_cmdline_user_args(): return
	for group in groups:
		for actor in group.soldiers:
			var kind: String = actor.crowd_kind()
			if not pending_visuals.has(kind): pending_visuals[kind] = []
			pending_visuals[kind].append(actor)
	for kind in pending_visuals:
		CrowdVisual.request_bank(kind)
	if pending_visuals.has("archer"):
		for tier in CrowdVisual.ARCHER_BANKS: CrowdVisual.request_bank(tier)

func prepare_visual_batch() -> bool:
	var prepared := false
	var deadline := Time.get_ticks_usec()+3500
	var camera := get_viewport().get_camera_3d()
	for kind in pending_visuals.keys():
		if not CrowdVisual.bank_ready(kind): continue
		if kind == "archer" and not CrowdVisual.ARCHER_BANKS.all(func(tier): return CrowdVisual.bank_ready(tier)): continue
		var pending: Array = pending_visuals[kind]
		while not pending.is_empty() and Time.get_ticks_usec()<deadline:
			var actor: Node3D = pending.pop_back()
			if not is_instance_valid(actor) or not actor.alive or actor.crowd_visual != null: continue
			actor.crowd_visual = CrowdVisual.new(actor)
			if DisplayServer.get_name() != "headless" and get_tree().current_scene.squads.size() >= 24:
				var wound_key := [actor.get_script(), actor.crowd_kind()]
				if not prepared_wound_models.has(wound_key):
					prepared_wound_models[wound_key] = true
					BODY_WOUNDS.prepare_body_meshes(actor.model, actor.mounted)
			if actor.crowd_visual.use_warrior_lods:
				prepare_warrior_meshes(actor, actor.crowd_visual.bank)
			if kind == "archer" and not prepared_archer_teams.has(actor.team):
				actor.crowd_visual.prepare_archer_meshes()
				prepared_archer_teams[actor.team] = true
			if camera and not allow_detail(actor,camera.global_position.distance_squared_to(actor.global_position)):
				actor.crowd_visual.set_distant(true)
			prepared = true
		if pending.is_empty(): pending_visuals.erase(kind)
		if Time.get_ticks_usec()>=deadline: break
	return prepared
func batch_for(mesh: Mesh, material: Material, kind: String, shadow_only: bool) -> Dictionary:
	var key := str(mesh.get_rid())+str(material.get_rid()) if material else str(mesh.get_rid())
	key += "shadow" if shadow_only else "visible"
	if not batches.has(key):
		var node := MultiMeshInstance3D.new()
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh.use_custom_data = true
		node.multimesh.use_colors = true
		node.multimesh.mesh = mesh
		node.multimesh.instance_count = 64
		node.multimesh.visible_instance_count = 0
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow_only else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.extra_cull_margin = 3
		add_child(node)
		var buffer := PackedFloat32Array(); buffer.resize(64*20)
		var indices := PackedFloat32Array(); indices.resize(64); indices.fill(-1)
		batches[key] = {"node":node,"entries":[],"free":[],"buffer":buffer,"indices":indices,"manual":{},"fixed_bounds":false,"shadow":shadow_only,"compact":kind != "prince","visible_slots":0}
	return batches[key]

func acquire(mesh: Mesh, material: Material, actor: Node3D, relative: Transform3D, shadow_only := false) -> Dictionary:
	var batch := batch_for(mesh, material, actor.crowd_kind(), shadow_only)
	var i: int = batch.free.pop_back() if not batch.free.is_empty() else batch.entries.size()
	var multimesh: MultiMesh = batch.node.multimesh
	if i >= multimesh.instance_count:
		var capacity := multimesh.instance_count * 2
		# Resizing clears transforms, equipment flags and pose data on the GPU.
		# The packed path uploads them from batch.buffer on the next render step.
		var uploaded := PackedFloat32Array() if packed_animation_updates else multimesh.buffer
		multimesh.instance_count = capacity
		if not uploaded.is_empty():
			uploaded.resize(capacity * 20)
			multimesh.buffer = uploaded
		batch.buffer.resize(capacity*20)
		var old_size: int = batch.indices.size()
		batch.indices.resize(capacity)
		for slot in range(old_size,capacity): batch.indices[slot] = -1
	var entry := {"batch":batch,"slot":i,"actor":actor,"relative":relative,"shown":true}
	if i == batch.entries.size(): batch.entries.append(entry)
	else: batch.entries[i] = entry
	set_visible_slots(batch,batch.entries.size())
	actor_entries.get_or_add(actor,{})[batch.node] = entry
	update_entry_rendering(entry)
	return entry

func set_visible_slots(batch: Dictionary, slots: int) -> void:
	if batch.visible_slots != slots:
		batch.visible_slots = slots
		batch.node.multimesh.visible_instance_count = slots

func update_actor_rendering(actor: Node3D) -> void:
	for entry in actor_entries.get(actor,{}).values():
		update_entry_rendering(entry)

func update_entry_rendering(entry: Dictionary) -> void:
	var batch: Dictionary = entry.batch
	var slot: int = entry.slot
	var frozen: bool = entry.actor.corpse_at_rest
	batch.indices[slot] = render_slot(entry)
	if frozen:
		var transform: Transform3D = entry.actor.render_model_transform() * entry.relative
		write_render_transform(batch.buffer,slot,transform)
	if not frozen and (entry.actor.mounted or not entry.actor.native_controlled):
		batch.manual[slot] = entry
	else:
		batch.manual.erase(slot)

func render_slot(entry: Dictionary) -> int:
	if not entry.shown: return HIDDEN_INSTANCE
	if entry.actor.corpse_at_rest: return STATIC_INSTANCE
	return entry.actor.native_index if entry.actor.native_controlled else HIDDEN_INSTANCE

func write_render_transform(buffer: PackedFloat32Array, slot: int, transform: Transform3D) -> void:
	var basis := transform.basis
	for row in 3:
		var at := slot * 20 + row * 4
		buffer[at] = basis.x[row]
		buffer[at+1] = basis.y[row]
		buffer[at+2] = basis.z[row]
		buffer[at+3] = transform.origin[row]

func release(entry: Dictionary) -> void:
	if entry.is_empty(): return
	var batch: Dictionary = entry.batch
	if not packed_animation_updates:
		batch.node.multimesh.set_instance_transform(entry.slot,Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO))
	var entries: Dictionary = actor_entries[entry.actor]
	entries.erase(batch.node)
	if entries.is_empty(): actor_entries.erase(entry.actor)
	batch.manual.erase(entry.slot)
	batch.entries[entry.slot] = null
	batch.indices[entry.slot] = -1
	batch.free.append(entry.slot)
func appearance(entry: Dictionary, data: Color) -> void:
	var batch: Dictionary = entry.batch
	var offset: int = entry.slot*20+12
	batch.buffer[offset] = data.r; batch.buffer[offset+1] = data.g; batch.buffer[offset+2] = data.b; batch.buffer[offset+3] = data.a
	batch.indices[entry.slot] = render_slot(entry)
	if not packed_animation_updates: batch.node.multimesh.set_instance_color(entry.slot,data)

func custom(entry: Dictionary, data: Color) -> void:
	var batch: Dictionary = entry.batch
	var offset: int = entry.slot*20+16
	batch.buffer[offset] = data.r; batch.buffer[offset+1] = data.g; batch.buffer[offset+2] = data.b; batch.buffer[offset+3] = data.a
	if not packed_animation_updates: batch.node.multimesh.set_instance_custom_data(entry.slot,data)

func replace_body_mesh(entry: Dictionary, mesh: ArrayMesh) -> Dictionary:
	var actor: Node3D = entry.actor
	var shown: bool = entry.shown
	var offset: int = entry.slot * 20
	var buffer: PackedFloat32Array = entry.batch.buffer
	var flags := Color(buffer[offset+12],buffer[offset+13],buffer[offset+14],buffer[offset+15])
	var animation := Color(buffer[offset+16],buffer[offset+17],buffer[offset+18],buffer[offset+19])
	release(entry)
	var replacement := acquire(mesh,null,actor,Transform3D.IDENTITY)
	replacement.shown = shown
	appearance(replacement,flags)
	custom(replacement,animation)
	return replacement

func _process(delta: float) -> void:
	mesh_swaps = 0
	var retry_mesh_swaps := mesh_swaps_pending
	mesh_swaps_pending = false
	var prepared := prepare_visual_batch() if not pending_visuals.is_empty() else false
	if get_tree().paused:
		var field := get_tree().current_scene
		var camera := get_viewport().get_camera_3d()
		var moved := camera != null and camera.global_transform != rendered_camera_transform
		var changed := false
		if moved or retry_mesh_swaps:
			for group in field.squads:
				for actor in group.soldiers:
					if actor.crowd_visual and actor.crowd_visual.refresh_distance_lod(): changed = true
		if not prepared and not changed:
			if not moved: return
			if field.squads.size() < 24 or field.crowd_movement.previous_state.is_empty():
				rendered_camera_transform = camera.global_transform
				return
	var started := Time.get_ticks_usec() if PROF.enabled else 0
	render_step(0.0 if get_tree().paused else delta)
	if PROF.enabled: PROF.add("renderer",started)

func prepare_warrior_meshes(actor: Node3D, bank: Resource) -> void:
	if not bank: return
	var body: MeshInstance3D = actor.model.find_children("*","MeshInstance3D",true,false)[0]
	var material := BODY_WOUNDS.base_material(body.get_active_material(0))
	var key := [actor.get_script(),material,actor.appearance_index,actor.team,actor.get("axe_variant")]
	if prepared_warrior_meshes.has(key): return
	prepared_warrior_meshes[key] = true
	var sockets: Array[BoneAttachment3D] = []
	sockets.assign(actor.skeleton.get_children().filter(func(node): return node is BoneAttachment3D))
	for level in 3: batch_for(combined_mesh(actor,bank,sockets,level), null, actor.crowd_kind(), false)

func render_step(delta: float, use_native_interpolation := true) -> void:
	var field := get_tree().current_scene
	var time: float = field.battle_time
	var movement: Node = field.crowd_movement
	var fast: bool = use_native_interpolation and movement.native != null and not movement.previous_state.is_empty() and movement.native.has_method("render_grounded_buffer")
	packed_animation_updates = fast
	var stage_started := Time.get_ticks_usec() if PROF.enabled else 0
	# Spread visual state refreshes across frames; poses themselves run continuously on GPU.
	var pose_interval := .20 if bool(movement.high_load) else .10
	var count := sleeping_visuals.size()
	var requested := count * delta / (pose_interval * Engine.time_scale)
	var budget := mini(count,ceili(requested))
	var physics_frame := Engine.get_physics_frames()
	defer_detail = bool(movement.high_load) and physics_frame != last_visual_physics_frame and physics_frame == movement.heavy_physics_frame
	last_visual_physics_frame = physics_frame
	var deadline := 0
	if movement.high_load and delta > 0.0:
		visual_credit = minf(visual_credit + requested,count*.25)
		budget = mini(count,floori(visual_credit))
		deadline = Time.get_ticks_usec() + (500 if defer_detail else 1900)
	# A slow frame must not trigger a full-army visual catch-up on the next frame.
	budget = mini(budget,maxi(24,ceili(count/8.0)))
	var processed := 0
	for i in budget:
		if sleeping_visuals.is_empty():break
		if deadline > 0 and i % 8 == 0 and i > 0 and Time.get_ticks_usec() >= deadline: break
		far_cursor=posmod(far_cursor,sleeping_visuals.size())
		var visual=sleeping_visuals[far_cursor]
		var elapsed:float=maxf(0,time-visual.last_tick)
		visual.last_tick=time
		visual.actor.visual_step(elapsed)
		if visual.distant:far_cursor+=1
		processed += 1
	if deadline > 0: visual_credit = maxf(0,visual_credit-processed)
	for visual in lod_transitions.keys():
		if is_instance_valid(visual.actor): visual.update_lod_transition(delta / Engine.time_scale)
		else: stop_lod_transition(visual)
	if PROF.enabled:
		PROF.add("render_poses",stage_started)
		stage_started = Time.get_ticks_usec()
	RenderingServer.global_shader_parameter_set("crowd_time",time)
	for material in coat_materials.values(): material.set_shader_parameter("battle_time",time)
	var weight := clampf(movement.render_clock/movement.step_duration,0,1)
	var large_battle: bool = field.squads.size() >= 24
	var overview: bool = large_battle and field.camera_distance >= 235.0
	var planes := PackedFloat32Array()
	var frustum: Array[Plane] = []
	var camera := get_viewport().get_camera_3d()
	if camera: rendered_camera_transform = camera.global_transform
	if fast and large_battle and not overview and camera and movement.native.has_method("compact_render_buffer"):
		frustum = camera.get_frustum()
		for plane in frustum:
			planes.append_array(PackedFloat32Array([plane.normal.x,plane.normal.y,plane.normal.z,plane.d]))
	var bounds := AABB()
	# Buffers retain their original capacity after compaction. Explicit bounds avoid
	# rebuilding the MultiMesh AABB from all slots after every buffer upload.
	if large_battle:
		var half_size: Vector2 = field.field_half_size + Vector2(12.0,12.0)
		bounds = AABB(Vector3(-half_size.x,-24.0,-half_size.y),
			Vector3(half_size.x*2.0,field.terrain.highest_ground+36.0,half_size.y*2.0))
	var cache_poses: bool = fast and large_battle and movement.native.has_method("prepare_render_frame")
	if cache_poses:
		cache_poses = movement.native.call("prepare_render_frame",movement.state,movement.previous_state,
			movement.render_heights,movement.ground_heights,movement.ground_config,planes,weight) > 0
	var mounted_transforms := {}
	var offscreen_mounts := {}
	for batch in batches.values():
		if batch.entries.size() == batch.free.size():
			set_visible_slots(batch, 0)
			continue
		if batch.fixed_bounds != large_battle:
			batch.fixed_bounds = large_battle
			batch.node.multimesh.custom_aabb = bounds
		if cache_poses:
			var buffer: PackedFloat32Array = batch.buffer
			var indices: PackedFloat32Array = batch.indices
			for slot in batch.manual:
				var entry: Dictionary = batch.manual[slot]
				var actor: Node3D = entry.actor
				if actor.native_controlled or not entry.shown: continue
				write_render_transform(buffer,slot,actor.render_model_transform() * entry.relative)
				indices[slot] = STATIC_INSTANCE
			var margin := -1.0
			if not planes.is_empty() and batch.compact: margin = 14.0 if batch.shadow else 4.0
			buffer = movement.native.call("assemble_render_batch",buffer,indices,batch.entries.size(),margin)
			var slots: int = movement.native.call("visible_render_count")
			set_visible_slots(batch,slots)
			if slots > 0: batch.node.multimesh.buffer = buffer
		elif fast:
			var buffer: PackedFloat32Array = movement.native.call("render_grounded_buffer",batch.buffer,batch.indices,movement.state,movement.previous_state,weight,movement.render_heights)
			for slot in batch.manual:
				var entry: Dictionary = batch.manual[slot]
				if not entry.shown: continue
				var actor: Node3D = entry.actor
				if batch.compact and actor.mounted and not frustum.is_empty():
					if not offscreen_mounts.has(actor):
						var center: Vector3 = actor.render_position() + Vector3.UP
						offscreen_mounts[actor] = outside_render_margin(center, frustum)
					if offscreen_mounts[actor]: continue
				if not mounted_transforms.has(actor):
					mounted_transforms[actor] = actor.render_model_transform()
				var transform: Transform3D = mounted_transforms[actor] * entry.relative
				write_render_transform(buffer,slot,transform)
			var slots: int = batch.entries.size()
			if not planes.is_empty() and batch.compact:
				buffer = movement.native.call("compact_render_buffer",buffer,planes,slots,14.0 if batch.shadow else 4.0)
				slots = movement.native.call("visible_render_count")
			set_visible_slots(batch,slots)
			if slots > 0: batch.node.multimesh.buffer = buffer
			continue
		else:
			set_visible_slots(batch,batch.entries.size())
			for entry in batch.entries:
				if entry == null: continue
				var transform: Transform3D = entry.actor.render_model_transform()*entry.relative
				if not entry.shown: transform.basis = Basis.from_scale(Vector3.ZERO)
				batch.node.multimesh.set_instance_transform(entry.slot,transform)
	if PROF.enabled: PROF.add("render_buffers",stage_started)

func outside_render_margin(center: Vector3, frustum: Array[Plane]) -> bool:
	for plane in frustum:
		# Use the larger shadow margin for both batches so both can share the result.
		if plane.distance_to(center) > 14.1: return true
	return false

func combined_mesh(actor: Node3D, bank: Resource, sockets: Array[BoneAttachment3D], warrior_lod := 0) -> ArrayMesh:
	if bank.has_meta("full_model"):return combined_mounted_mesh(actor,bank,sockets,warrior_lod)
	if bank.has_meta("archer_lod_material"):
		var body_only: bool = bank.get_meta("archer_body_only")
		var color: Color = actor.uniform_color()
		var lod_key := ["archer_lod", bank.get_instance_id(), color]
		if not combined.has(lod_key):
			var lod_mesh := ArrayMesh.new()
			var base: ArrayMesh = bank.get_meta("pose_mesh")
			lod_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base.surface_get_arrays(0))
			var source: StandardMaterial3D = bank.get_meta("archer_lod_material")
			var dyed := Warrior.TroopColors.dye(source, color, Warrior.TroopColors.Fabric.ARCHER)
			lod_mesh.surface_set_material(0, animated_material(dyed, bank, -1, -1, 0))
			if body_only:
				append_archer_sticks(lod_mesh, actor, bank, sockets)
				append_socket_meshes(lod_mesh, actor, bank, sockets, false, Armbands.ONLY)
			else:
				append_socket_meshes(lod_mesh, actor, bank, sockets, false, Armbands.INCLUDE)
			combined[lod_key] = lod_mesh
		return combined[lod_key]
	var body: MeshInstance3D = actor.model.find_children("*","MeshInstance3D",true,false)[0]
	var body_material := BODY_WOUNDS.base_material(body.get_active_material(0))
	var key := str(body_material.get_rid())+str(actor.team)+str(bank.get_instance_id())+str(actor.get_script().resource_path)
	if warrior_lod > 0: key += ":lod%d" % warrior_lod
	if actor.get("axe_variant") != null:
		key += ":axe%d" % actor.axe_variant
	if combined.has(key): return combined[key]
	var mesh := ArrayMesh.new()
	var base: ArrayMesh = bank.get_meta("pose_mesh")
	if warrior_lod > 0: base = troop_meshes(actor.crowd_kind())[warrior_lod - 1]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,base.surface_get_arrays(0))
	mesh.surface_set_material(0,animated_material(body_material,bank,-1,-1,0,Transform3D.IDENTITY,1))
	append_socket_meshes(mesh, actor, bank, sockets, warrior_lod == 2)
	combined[key]=mesh
	return mesh

func append_archer_sticks(mesh: ArrayMesh, actor: Node3D, bank: Resource, sockets: Array[BoneAttachment3D]) -> void:
	var bones: Array = bank.get_meta("bone_names")
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("604831")
	add_equipment_stick(mesh, actor.bow.transform, 1.20, .035)
	mesh.surface_set_material(mesh.get_surface_count() - 1,
		animated_material(wood, bank, bones.find("GripLeft"), bones.find("BowBack"), 3))
	for socket in sockets:
		if socket.bone_name == &"QuiverBack" and socket.get_child_count() > 0:
			var holder: Node3D = socket.get_child(0)
			var local := holder.transform.translated_local(Vector3.UP * .07)
			add_equipment_stick(mesh, local, .64, .058)
			mesh.surface_set_material(mesh.get_surface_count() - 1,
				animated_material(wood, bank, bones.find("QuiverBack"), -1, 6))
			break

func add_equipment_stick(mesh: ArrayMesh, local: Transform3D, length: float, radius: float) -> void:
	var stick := CylinderMesh.new()
	stick.height = length
	stick.top_radius = radius * .75
	stick.bottom_radius = radius
	stick.radial_segments = 4
	stick.rings = 0
	var arrays := stick.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		vertices[i] = local * vertices[i]
		normals[i] = (local.basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func append_socket_meshes(mesh: ArrayMesh, actor: Node3D, bank: Resource, sockets: Array[BoneAttachment3D],
		simple_weapons := false, armbands := Armbands.EXCLUDE) -> void:
	var bone_names: Array = bank.get_meta("bone_names")
	for socket in sockets:
		for part: MeshInstance3D in socket.find_children("*","MeshInstance3D",true,false):
			var armband := part.name == &"TeamArmband"
			if armband and armbands == Armbands.EXCLUDE: continue
			if not armband and armbands == Armbands.ONLY: continue
			if part.mesh is PrimitiveMesh and not armband: continue
			if actor.shield_variant >= 0 and part.get_parent() == actor.shield: continue
			var grip: int = bone_names.find(socket.bone_name)
			if armband and grip < 0: continue
			var alternate := -1
			var tag := 0
			var bow_back_shift := Vector3.ZERO
			var root: Node = part
			while root != socket:
				if root == actor.spear: tag=1
				if root == actor.sword: tag=2
				if actor.get("bow") != null and root == actor.bow: tag=3
				if actor.get("held_arrow") != null and root == actor.held_arrow: tag=4
				root=root.get_parent()
			var material: Material = part.get_active_material(0)
			if material is ShaderMaterial and "wool_color" in material.shader.code: tag=5
			var is_axe: bool = tag == 2 and actor.get("axe_variant") != null
			if is_axe:
				# Varangians always carry their axe on the actual hand bone.
				tag = 11
			elif tag == 2:
				grip=bone_names.find("SwordBelt"); alternate=bone_names.find("GripRight")
			if tag == 3:
				grip=bone_names.find("GripLeft"); alternate=bone_names.find("BowBack")
				bow_back_shift = actor.bow_back_shift()
			if tag == 4:
				alternate=bone_names.find("GripLeft")
			if socket.bone_name == &"QuiverBack":
				tag=6
			var arrays: Array = part.mesh.surface_get_arrays(0)
			var local: Transform3D = socket.global_transform.affine_inverse()*part.global_transform
			if tag == 3 and socket == actor.bow_back:
				local.origin -= bow_back_shift
			if tag == 4:
				# The held arrow is posed in world space by the detailed rig.
				local = actor.held_arrow.global_transform.affine_inverse() * part.global_transform
			if simple_weapons and tag == 4: continue
			var keep_sabre: bool = tag == 2 and actor.crowd_kind() == "khazar"
			if simple_weapons and tag in [1, 2, 3, 6] and not keep_sabre:
				var bounds := part.mesh.get_aabb()
				var stick_material := StandardMaterial3D.new()
				stick_material.albedo_color = Color("785b3f") if tag == 1 else Color("777770")
				add_equipment_stick(mesh, local.translated_local(bounds.get_center()), bounds.size.y, .025)
				mesh.surface_set_material(mesh.get_surface_count() - 1,
					animated_material(stick_material, bank, grip, alternate, tag, local, 0, bow_back_shift))
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in vertices.size():
				vertices[i]=local*vertices[i]
				normals[i]=(local.basis*normals[i]).normalized()
			arrays[Mesh.ARRAY_VERTEX]=vertices
			arrays[Mesh.ARRAY_NORMAL]=normals
			var surface := RenderingServer.mesh_get_surface(part.mesh.get_rid(),0)
			var lods: Array=surface.get("lods",[])
			# Axes already have a low triangle count. Imported simplification can
			# remove their disconnected blade or haft when switching to the crowd.
			if not lods.is_empty() and tag not in [3, 4] and not is_axe and not keep_sabre:
				# Thin spear tips and cloth collars disappear in the coarsest imported level.
				var bytes: PackedByteArray=lods[0 if tag in [1,5] else -1].index_data
				var indices:=PackedInt32Array()
				var stride:=2 if int(surface.vertex_count)<65536 else 4
				for i in bytes.size()/stride: indices.append(bytes.decode_u16(i*stride) if stride==2 else bytes.decode_u32(i*stride))
				arrays[Mesh.ARRAY_INDEX]=indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1,
				animated_material(material, bank, grip, alternate, tag, local, 0, bow_back_shift))

func spear_shield_mesh(actor: Node3D, bank: Resource) -> ArrayMesh:
	# Shields share their own batches across body appearances.
	var part: MeshInstance3D = actor.shield.get_child(0)
	var material := part.get_active_material(0)
	var key := "shield:%d:%d:%d" % [bank.get_instance_id(), material.get_instance_id(), actor.shield_variant]
	if combined.has(key):
		return combined[key]
	var local: Transform3D = actor.shield.transform * part.transform
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		vertices[i] = local * vertices[i]
		normals[i] = (local.basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var bone_names: Array = bank.get_meta("bone_names")
	mesh.surface_set_material(0, animated_material(material, bank, bone_names.find("GripLeft"), -1, 11))
	combined[key] = mesh
	return mesh

func combined_mounted_mesh(actor:Node3D,bank:Resource,sockets: Array[BoneAttachment3D],lod:=0) -> ArrayMesh:
	var rider := actor.model.find_child("Mounted warrior",true,false) as MeshInstance3D
	var appearance := rider.get_active_material(0).get_instance_id() if rider else 0
	var key := "mounted:%d:%d:%d:%d:%d" % [bank.get_instance_id(), actor.team, actor.appearance_index, appearance, lod]
	if combined.has(key):return combined[key]
	var mesh:=ArrayMesh.new()
	var base:ArrayMesh=bank.get_meta("pose_mesh")
	if lod > 0: base = troop_meshes(actor.crowd_kind())[lod - 1]
	var sources:Array=bank.get_meta("material_sources")
	var offsets:Array=bank.get_meta("surface_offsets")
	for surface in base.get_surface_count():
		var original:MeshInstance3D=actor.model.find_child(sources[surface].mesh,true,false)
		if lod == 2 and original.name == &"Rider spear" and add_mounted_spear_stick(mesh,bank,base,surface): continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,base.surface_get_arrays(surface))
		var source_surface: int = sources[surface].surface
		var wound_surface := BODY_WOUNDS.surface_id(original, source_surface, true)
		var body_material := BODY_WOUNDS.base_material(original.get_active_material(source_surface))
		var tag := 7 if original.name == &"Rider spear" else (10 if original.name == &"Rider shield" else 0)
		if actor.has_method("bow_pitch"):
			tag = 8 if original.name == &"Mounted warrior" else 9
		var material:ShaderMaterial=animated_material(body_material,bank,-1,-1,tag,Transform3D.IDENTITY,wound_surface)
		material.set_shader_parameter("pose_vertex_offset",offsets[surface])
		mesh.surface_set_material(surface,material)
	append_socket_meshes(mesh, actor, bank, sockets, lod == 2, Armbands.INCLUDE)
	combined[key]=mesh
	return mesh

func add_mounted_spear_stick(mesh: ArrayMesh, bank: Resource, source: ArrayMesh, surface: int) -> bool:
	var names: Array = bank.get_meta("bone_names")
	var hand_index := names.find("RiderHand.R")
	if hand_index < 0: return false
	var clips: Dictionary = bank.get_meta("clips")
	var hand: Transform3D = clips.values()[0].bones[0][names[hand_index]]
	var to_hand: Transform3D = hand.affine_inverse() * bank.get_meta("body_transform")
	var vertices: PackedVector3Array = source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var start := vertices[0]
	var end := start
	for vertex in vertices:
		if vertex.distance_squared_to(start) > end.distance_squared_to(start): end = vertex
	for vertex in vertices:
		if vertex.distance_squared_to(end) > start.distance_squared_to(end): start = vertex
	start = to_hand * start
	end = to_hand * end
	var axis := (end - start).normalized()
	var right := axis.cross(Vector3.FORWARD).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	var local := Transform3D(Basis(right,axis,right.cross(axis)),(start+end)*.5)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("785b3f")
	add_equipment_stick(mesh, local, start.distance_to(end), .024)
	mesh.surface_set_material(mesh.get_surface_count()-1,animated_material(wood,bank,hand_index,-1,7))
	return true

func animated_material(original: Material, bank: Resource, grip: int, alternate: int, tag: int,
		part_transform := Transform3D.IDENTITY, wound_surface := 0, bow_back_shift := Vector3.ZERO) -> Material:
	var material := ShaderMaterial.new()
	var code := ""
	if original is ShaderMaterial: code=original.shader.code
	else: code="shader_type spatial; uniform sampler2D base_texture:source_color,filter_linear_mipmap_anisotropic; uniform vec4 base_tint:source_color=vec4(1); uniform bool has_texture=true; uniform float material_roughness=.9; uniform float material_metallic=0.0; void fragment(){ ALBEDO=(has_texture ? texture(base_texture,UV).rgb : vec3(1))*base_tint.rgb; ROUGHNESS=material_roughness; METALLIC=material_metallic; }"
	# The fractional part of the flags carries the detailed model's coverage.
	var fragment := code.find("void fragment")
	code = code.insert(fragment, "\n" + LOD_MASK + "varying flat float lod_detail;\n")
	code = code.insert(code.find("{", code.find("void fragment"))+1, "\nif (lod_threshold(FRAGCOORD.xy) < lod_detail) { discard; }\n")
	if wound_surface > 0:
		code = code.insert(code.find("void fragment()"), "\n#include \"res://assets/body_wounds.gdshaderinc\"\nvarying flat int wound_row;\n")
		code = code.insert(code.rfind("}"), "\n vec4 blood = body_wound_color(wound_row, UV); ALBEDO = mix(ALBEDO, blood.rgb, blood.a);\n")
	code+="""
uniform sampler2D pose_positions:filter_nearest,repeat_disable;
uniform sampler2D pose_normals:filter_nearest,repeat_disable;
uniform sampler2D pose_bones:filter_nearest,repeat_disable;
uniform mat4 body_transform;
uniform int pose_vertex_offset=0;
uniform int grip_index;
uniform int alternate_grip;
uniform int part_tag;
uniform int corpse_hips=-1;
uniform int corpse_neck=-1;
uniform mat4 cape_to_bone;
uniform float bow_pivot = 1.08;
uniform vec3 bow_back_shift;
global uniform float crowd_time;
mat4 bone_pose(int bone,int frame){
 return mat4(texelFetch(pose_bones,ivec2(bone*4,frame),0),texelFetch(pose_bones,ivec2(bone*4+1,frame),0),texelFetch(pose_bones,ivec2(bone*4+2,frame),0),texelFetch(pose_bones,ivec2(bone*4+3,frame),0));
}
void vertex(){
 lod_detail=fract(COLOR.r);
 float flags=mod(floor(COLOR.r),1024.0);
 bool fallen=mod(floor(flags/2.0),2.0)>.5;
 bool sword_held=mod(floor(flags/4.0),2.0)>.5;
 bool disarmed=floor(flags/16.0)>62.5;
 float aim_code=floor(COLOR.r/1024.0);
 float duration=max(.001,abs(INSTANCE_CUSTOM.y));
 float t=max(0.0,(crowd_time-INSTANCE_CUSTOM.z)*INSTANCE_CUSTOM.w);
 float phase=INSTANCE_CUSTOM.y>0.0 ? mod(t,duration)/duration*8.0 : min(t/duration,1.0)*7.0;
 int frame=int(floor(phase));
 int next_frame=INSTANCE_CUSTOM.y>0.0 ? (frame+1)%8 : min(frame+1,7);
 int start=int(INSTANCE_CUSTOM.x);
 float blend=COLOR.b<0.0 ? 1.0 : smoothstep(0.0,.18,crowd_time-COLOR.g);
 int previous=int(floor(max(0.0,COLOR.b)));
 int previous_next=int(mod(max(0.0,COLOR.a),1024.0));
 if(grip_index<0){
  VERTEX=(body_transform*vec4(mix(texelFetch(pose_positions,ivec2(VERTEX_ID+pose_vertex_offset,start+frame),0).xyz,texelFetch(pose_positions,ivec2(VERTEX_ID+pose_vertex_offset,start+next_frame),0).xyz,fract(phase)),1.0)).xyz;
  NORMAL=normalize(mat3(body_transform)*mix(texelFetch(pose_normals,ivec2(VERTEX_ID+pose_vertex_offset,start+frame),0).xyz,texelFetch(pose_normals,ivec2(VERTEX_ID+pose_vertex_offset,start+next_frame),0).xyz,fract(phase)));
  if(blend<1.0){
   vec3 old=mix(texelFetch(pose_positions,ivec2(VERTEX_ID+pose_vertex_offset,previous),0).xyz,texelFetch(pose_positions,ivec2(VERTEX_ID+pose_vertex_offset,previous_next),0).xyz,fract(COLOR.b));
   vec3 normal=mix(texelFetch(pose_normals,ivec2(VERTEX_ID+pose_vertex_offset,previous),0).xyz,texelFetch(pose_normals,ivec2(VERTEX_ID+pose_vertex_offset,previous_next),0).xyz,fract(COLOR.b));
   VERTEX=mix((body_transform*vec4(old,1.0)).xyz,VERTEX,blend);
   NORMAL=normalize(mix(mat3(body_transform)*normal,NORMAL,blend));
  }
 } else {
  int bone=(part_tag!=4 && alternate_grip>=0 && sword_held) ? alternate_grip : grip_index;
  if(part_tag==3 && sword_held && alternate_grip>=0) VERTEX+=bow_back_shift;
  mat4 a=bone_pose(bone,start+frame); mat4 b=bone_pose(bone,start+next_frame);
  mat4 final_bone=mat4(mix(a[0],b[0],fract(phase)),mix(a[1],b[1],fract(phase)),mix(a[2],b[2],fract(phase)),mix(a[3],b[3],fract(phase)));
  vec3 local=VERTEX;
  VERTEX=mix((a*vec4(VERTEX,1.0)).xyz,(b*vec4(VERTEX,1.0)).xyz,fract(phase));
  NORMAL=normalize(mix(mat3(a)*NORMAL,mat3(b)*NORMAL,fract(phase)));
  if(blend<1.0){
   mat4 old_a=bone_pose(bone,previous);mat4 old_b=bone_pose(bone,previous_next);
   VERTEX=mix(mix((old_a*vec4(local,1)).xyz,(old_b*vec4(local,1)).xyz,fract(COLOR.b)),VERTEX,blend);
   final_bone=mat4(mix(mix(old_a[0],old_b[0],fract(COLOR.b)),final_bone[0],blend),mix(mix(old_a[1],old_b[1],fract(COLOR.b)),final_bone[1],blend),mix(mix(old_a[2],old_b[2],fract(COLOR.b)),final_bone[2],blend),mix(mix(old_a[3],old_b[3],fract(COLOR.b)),final_bone[3],blend));
  }
  if(part_tag==5){
   mat4 cape_pose=final_bone*cape_to_bone;
   vec3 cloth=(inverse(cape_to_bone)*vec4(local,1)).xyz;
   float bottom=1.0-UV.y;
   float fallen=mod(floor(flags/2.0),2.0);
   float travel=min(floor(flags/16.0),48.0)/8.0;
   float seed=float(INSTANCE_ID)*.731;
   float flex=bottom*bottom*(.045*sin(crowd_time*2.2+seed-bottom*3.4)+.065*(sin(crowd_time*1.15+seed*.7)*.5+.5)+travel*.065);
   vec3 rear=normalize(vec3(cape_pose[2].x,0,cape_pose[2].z)+vec3(.00001,0,0));
   vec3 side=normalize(cape_pose[0].xyz);
   vec3 hanging=cape_pose[3].xyz+side*(cloth.x+sin(crowd_time*1.7+seed-bottom*2.8)*.025*bottom)+vec3(0,cloth.y,0)+rear*(cloth.z+flex);
   VERTEX=mix(VERTEX,hanging,smoothstep(.04,.55,bottom)*(1.0-fallen));
   if(fallen>.5) VERTEX.y=mix(VERTEX.y,max(.045,min(VERTEX.y,.12)),smoothstep(.1,.65,bottom));
  }
  if(part_tag==4 && alternate_grip>=0){
   vec3 nock=final_bone[3].xyz;
   vec3 at=mix(bone_pose(alternate_grip,start+frame)[3].xyz,bone_pose(alternate_grip,start+next_frame)[3].xyz,fract(phase));
   vec3 axis=normalize(at-nock+vec3(0.00001,0.0,0.0));
   vec3 side=normalize(cross(axis,vec3(0.0,1.0,0.0))+vec3(0.00001,0.0,0.0));
   mat3 arrow_basis=mat3(side,axis,cross(side,axis));
   VERTEX=nock+arrow_basis*local;
  }
  if((part_tag==1 && mod(flags,2.0)<.5)||(part_tag==4 && mod(floor(flags/8.0),2.0)<.5)) VERTEX=vec3(0.0,-50.0,0.0);
 }
 if(aim_code>0.0 && !fallen && ((grip_index<0 && part_tag!=9) || part_tag==3 || part_tag==4 || part_tag==6)){
  float weight=grip_index<0 ? smoothstep(bow_pivot-.14,bow_pivot+.20,VERTEX.y) : 1.0;
  float pitch=radians((aim_code-64.0)*.5)*weight;
  float cs=cos(pitch), sn=sin(pitch);
  mat2 lift=mat2(vec2(cs,sn),vec2(-sn,cs));
  VERTEX.yz=lift*(VERTEX.yz-vec2(bow_pivot,0.0))+vec2(bow_pivot,0.0);
  NORMAL.yz=lift*NORMAL.yz;
 }
 if(fallen && aim_code>1.0 && corpse_hips>=0 && corpse_neck>=0){
  vec3 pivot=bone_pose(corpse_hips,start+7)[3].xyz;
  vec3 other=bone_pose(corpse_neck,start+7)[3].xyz;
  vec3 axis=normalize(vec3(other.x-pivot.x,0.0,other.z-pivot.z));
  float weight=smoothstep(.52,1.0,phase/7.0);
  float angle=(aim_code<4.0 ? .98 : 2.52)*(mod(aim_code,2.0)<.5 ? 1.0 : -1.0)*weight;
  vec3 relative=VERTEX-pivot;
  VERTEX=pivot+relative*cos(angle)+cross(axis,relative)*sin(angle)+axis*dot(axis,relative)*(1.0-cos(angle));
  VERTEX.y+=weight*(aim_code<4.0 ? .08 : .14);
  NORMAL=normalize(NORMAL*cos(angle)+cross(axis,NORMAL)*sin(angle)+axis*dot(axis,NORMAL)*(1.0-cos(angle)));
 }
 if(fallen && (part_tag==1 || part_tag==4 || part_tag==7 || part_tag==10 || (part_tag==2 && sword_held) || (part_tag==3 && !sword_held))){
  VERTEX=vec3(0.0,-50.0,0.0);
 }
 if(disarmed && (part_tag==1 || part_tag==2 || part_tag==3 || part_tag==4 || part_tag==7 || part_tag==11)){
  VERTEX=vec3(0.0,-50.0,0.0);
 }
}
"""
	if wound_surface > 0:
		code = code.replace("void vertex(){", "void vertex(){\n wound_row = int(floor(COLOR.a / 1024.0));")
	var plant_feet := grip < 0 and not bank.has_meta("full_model")
	if plant_feet:
		code = code.replace("uniform mat4 body_transform;", "uniform mat4 body_transform;\n#include \"res://assets/crowd_foot_placement.gdshaderinc\"\n")
		code = code.replace(" } else {\n  int bone=", """
  if (!fallen) {
   VERTEX.y += foot_placement(VERTEX, MODEL_MATRIX, ivec2(start + frame, start + next_frame),
    fract(phase), ivec2(previous, previous_next), fract(COLOR.b), blend);
  }
 } else {
  int bone=""")
	material.shader = shader_for_code(code)
	if plant_feet: FOOT_PLACEMENT.configure_material(material, bank)
	if wound_surface > 0:
		material.set_shader_parameter("body_wound_data", BODY_WOUNDS.texture())
		material.set_shader_parameter("body_wound_surface", wound_surface)
	if original is ShaderMaterial:
		for parameter in original.shader.get_shader_uniform_list(): material.set_shader_parameter(parameter.name,original.get_shader_parameter(parameter.name))
	else:
		material.set_shader_parameter("base_texture",original.albedo_texture)
		material.set_shader_parameter("base_tint",original.albedo_color)
		material.set_shader_parameter("has_texture",original.albedo_texture!=null)
		material.set_shader_parameter("material_roughness",original.roughness)
		material.set_shader_parameter("material_metallic",original.metallic)
	material.set_shader_parameter("pose_positions",bank.get_meta("pose_positions"))
	material.set_shader_parameter("pose_normals",bank.get_meta("pose_normals"))
	material.set_shader_parameter("pose_bones",bank.get_meta("pose_bones"))
	material.set_shader_parameter("body_transform",bank.get_meta("body_transform"))
	material.set_shader_parameter("grip_index",grip)
	material.set_shader_parameter("alternate_grip",alternate)
	material.set_shader_parameter("part_tag",tag)
	if tag == 3:
		material.set_shader_parameter("bow_back_shift", bow_back_shift)
	if bank.has_meta("bow_pivot"):
		material.set_shader_parameter("bow_pivot", bank.get_meta("bow_pivot"))
	var names: Array = bank.get_meta("bone_names")
	for index in names.size():
		var name: String = names[index]
		if name.ends_with("_Hips") or name.ends_with(":Hips"): material.set_shader_parameter("corpse_hips", index)
		if name.ends_with("_Neck") or name.ends_with(":Neck"): material.set_shader_parameter("corpse_neck", index)
	material.set_shader_parameter("cape_to_bone",part_transform)
	pose_materials[material.get_instance_id()]=material
	return material
func _exit_tree() -> void:
	pending_visuals.clear()
	sleeping_visuals.clear()
	detailed_actors.clear()
	lod_transitions.clear()
	actor_entries.clear()
	for batch in batches.values():
		batch.entries.clear()
		batch.manual.clear()
	batches.clear()
