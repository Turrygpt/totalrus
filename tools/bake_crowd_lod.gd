extends SceneTree
class BakeWorld extends Node3D:
	var squads := []
class FarArcher extends "res://scripts/archer.gd":
	var asset_name: String

	func warrior_scene() -> PackedScene:
		return load("res://assets/lod/%s.glb" % asset_name)
	func apply_appearance() -> void:
		pass
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := BakeWorld.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,1,4)
	DirAccess.make_dir_recursive_absolute("res://assets/lod")
	var kinds:Array=["soldier"] if "--soldier-only" in OS.get_cmdline_user_args() else ["soldier","archer"]
	if "--archer-only" in OS.get_cmdline_user_args(): kinds = ["archer"]
	if "--militia-only" in OS.get_cmdline_user_args(): kinds = ["militia"]
	var archer_lod := ""
	for option in ["archer_mid", "archer_far", "archer_overview"]:
		if "--" + option.replace("_", "-") in OS.get_cmdline_user_args(): archer_lod = option
	if not archer_lod.is_empty(): kinds = ["archer"]
	if "--varangian-only" in OS.get_cmdline_user_args(): kinds = ["varangian"]
	var brace_only := "--brace-only" in OS.get_cmdline_user_args()
	var video_only := "--spearman-video-only" in OS.get_cmdline_user_args()
	if brace_only or video_only: kinds = ["soldier"]
	for kind in kinds:
		var actor := FarArcher.new() if not archer_lod.is_empty() else CharacterBody3D.new()
		var actor_script: String = "spearman_video_fighter" if kind == "soldier" else kind
		if archer_lod.is_empty(): actor.set_script(load("res://scripts/"+actor_script+".gd"))
		else: actor.asset_name = archer_lod
		if kind == "varangian": actor.shield_variant = 0
		world.add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.agent.avoidance_enabled = false
		var body: MeshInstance3D = actor.model.find_children("*","MeshInstance3D",true,false)[0]
		await process_frame
		var source := RenderingServer.mesh_get_surface(body.mesh.get_rid(),0)
		if "--inspect" in OS.get_cmdline_user_args():
			print("SURFACE ",kind," ",source.keys()," vertices ",source.get("vertex_count"))
			for lod in source.get("lods",[]):
				print("LOD ",lod.keys()," edge ",lod.get("edge_length")," bytes ",lod.get("index_data",PackedByteArray()).size())
		if "--inspect" in OS.get_cmdline_user_args(): continue
		var aliases: Array = ["idle_spear","idle_sword","combat_spear","combat_sword","walk_spear","walk_sword","advance_spear","advance_sword","run_spear","run_sword","charge_spear","charge_sword","backstep_spear","backstep_sword","strafe_left_spear","strafe_right_spear","strafe_left_sword","strafe_right_sword","guard_front","guard_rear","guard_sword","guard_enter","guard_exit","guard_enter_sword","guard_exit_sword","throw_spear","draw_sword","attack_spear","attack_sword","attack_sword_alt","hit","block","block_sword","death_back","death_side","death_sword","victory_spear","victory_sword"]
		var video_clips: Array[String] = []
		if kind == "soldier":
			for full_name in actor.player.get_animation_list():
				if full_name.begins_with("video/"):
					video_clips.append(full_name)
					actor.animation_map[full_name] = full_name
			aliases.append("motion_charge_spear")
			aliases.append_array(video_clips)
			if not actor.animation_map.has("brace_spear"):
				var library := preload("res://scripts/cavalry_brace_pose.gd").make(actor)
				ResourceSaver.save(library, "res://assets/foot_brace.tres")
				actor.player.add_animation_library(&"brace", library)
				actor.animation_map["brace_spear"] = &"brace/brace_spear"
			aliases.append("brace_spear")
		if kind == "archer": aliases = ["bow_idle","bow_draw","bow_aim","bow_release","bow_walk","bow_run","bow_backstep","bow_retreat","bow_left","bow_right","bow_hit","bow_death","bow_death_front","knife_idle","knife_attack","knife_run","knife_draw","bow_victory"]
		elif kind == "varangian": aliases = ["idle_sword", "combat_sword", "walk_sword", "advance_sword", "run_sword", "charge_sword", "backstep_sword", "strafe_left_sword", "strafe_right_sword", "guard_sword", "guard_enter_sword", "guard_exit_sword", "attack_sword", "attack_sword_alt", "hit", "death_back", "death_side", "death_sword", "victory_sword"]
		else:
			if actor.animation_map.has("attack_spear_alt"): aliases.append("attack_spear_alt")
			var spear_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/spear_combat.json"))
			for attack: Dictionary in spear_data.get("attacks", []):
				aliases.append(attack["clip"])
			for guard: Dictionary in spear_data.get("guard", {}).values():
				aliases.append(guard["clip"])
		var bank_path: String = "res://assets/lod/%s_poses.res" % (kind if archer_lod.is_empty() else archer_lod)
		var incremental := brace_only or video_only
		var bank := load(bank_path) if incremental else Resource.new()
		var records: Dictionary = bank.get_meta("clips") if incremental else {}
		if brace_only:
			aliases = ["brace_spear"]
			records.erase(actor.animation_map["brace_spear"])
		elif video_only:
			aliases = video_clips
			for full_name in video_clips:
				records.erase(full_name)
		var socket_bones := []
		for socket in actor.skeleton.get_children():
			if socket is BoneAttachment3D: socket_bones.append(socket.bone_name)
		for i in actor.skeleton.get_bone_count():
			var name: String = actor.skeleton.get_bone_name(i)
			if name not in socket_bones: socket_bones.append(name)
		var indices := PackedInt32Array()
		var lods: Array = source.get("lods",[])
		# Imported LODs can bridge UV seams on the archer and militia bodies.
		# Preserve their original topology in the GPU pose banks.
		var index_bytes: PackedByteArray = source["index_data"]
		if kind not in ["archer", "militia"] and not lods.is_empty():
			index_bytes = lods[0]["index_data"]
		var stride := 2 if int(source["vertex_count"]) < 65536 else 4
		for i in index_bytes.size()/stride: indices.append(index_bytes.decode_u16(i*stride) if stride == 2 else index_bytes.decode_u32(i*stride))
		for alias in aliases:
			if not actor.animation_map.has(alias): continue
			var full: String = actor.animation_map[alias]
			if records.has(full): continue
			var clip: Animation = actor.player.get_animation(full)
			var looping: bool = clip.loop_mode != Animation.LOOP_NONE
			var meshes: Array[ArrayMesh] = []
			var bones: Array = []
			var frames := 8
			for frame in frames:
				actor.player.play(full,0)
				actor.player.seek(clip.length*frame/float(frames if looping else frames-1),true)
				actor.player.advance(0)
				actor.skeleton.force_update_all_bone_transforms()
				await RenderingServer.frame_post_draw
				var baked: ArrayMesh = body.bake_mesh_from_current_skeleton_pose()
				meshes.append(compact_mesh(baked,indices))
				var transforms := {}
				for bone in socket_bones:
					var index: int = actor.skeleton.find_bone(bone)
					if index >= 0: transforms[bone] = actor.global_transform.affine_inverse()*actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(index)
				bones.append(transforms)
			records[full] = {"meshes":meshes,"bones":bones,"duration":clip.length,"loop":looping}
			print("POSES ",kind," ",full," ",frames)
		bank.set_meta("clips",records)
		if not archer_lod.is_empty():
			bank.set_meta("archer_lod_material", body.get_active_material(0))
			bank.set_meta("archer_body_only", archer_lod != "archer_mid")
		bank.set_meta("body_transform",actor.global_transform.affine_inverse()*body.global_transform)
		if not incremental and kind != "archer":
			bank.set_meta("run_shield_turned", true)
		var saved := ResourceSaver.save(bank,bank_path,ResourceSaver.FLAG_COMPRESS)
		if saved != OK:
			push_error("Cannot save pose bank: " + error_string(saved))
			quit(saved)
			return
		actor.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	quit()

func compact_mesh(source: ArrayMesh, indices: PackedInt32Array) -> ArrayMesh:
	var original := source.surface_get_arrays(0)
	var remap := {}
	var used: Array[int] = []
	var compact_indices := PackedInt32Array()
	for index in indices:
		if not remap.has(index):
			remap[index] = used.size()
			used.append(index)
		compact_indices.append(remap[index])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var uv2 := PackedVector2Array()
	for index in used:
		vertices.append(original[Mesh.ARRAY_VERTEX][index])
		normals.append(original[Mesh.ARRAY_NORMAL][index])
		uvs.append(original[Mesh.ARRAY_TEX_UV][index])
		if original[Mesh.ARRAY_TEX_UV2] != null and not original[Mesh.ARRAY_TEX_UV2].is_empty(): uv2.append(original[Mesh.ARRAY_TEX_UV2][index])
		for component in 4: tangents.append(original[Mesh.ARRAY_TANGENT][index*4+component])
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TANGENT] = tangents
	if not uv2.is_empty(): arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = compact_indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
