extends SceneTree

class TestWorld extends Node3D:
	var squads := []

var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1

func run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	current_scene = world
	var actor := CharacterBody3D.new()
	actor.set_script(load("res://scripts/archer.gd"))
	world.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.agent.avoidance_enabled = false
	var body: MeshInstance3D = actor.model.find_children("*","MeshInstance3D",true,false)[0]
	var head := -1
	for i in actor.skeleton.get_bone_count():
		if actor.skeleton.get_bone_name(i).ends_with("Head"): head = i
	var head_name: StringName = actor.skeleton.get_bone_name(head)
	var head_bind := -1
	for i in body.skin.get_bind_count():
		if body.skin.get_bind_name(i) == head_name: head_bind = i
	check(head_bind >= 0,"head bind exists in the imported skin")
	var data := body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var weights: PackedFloat32Array = data[Mesh.ARRAY_WEIGHTS]
	var bones: PackedInt32Array = data[Mesh.ARRAY_BONES]
	var stride := weights.size() / vertices.size()
	var bounds := body.mesh.get_aabb()
	var face_count := 0
	var bad := 0
	var face_uvs := {}
	var source_uvs: PackedVector2Array = data[Mesh.ARRAY_TEX_UV]
	for i in vertices.size():
		var rear := clampf((.045 - vertices[i].z / 1.8) / .028,0.0,1.0)
		var jaw_y := bounds.position.y + bounds.size.y * (.838 + .040 * rear)
		if vertices[i].y < jaw_y: continue
		face_count += 1
		face_uvs[source_uvs[i]] = true
		var head_weight := 0.0
		for slot in stride:
			if bones[i*stride+slot] == head_bind: head_weight += weights[i*stride+slot]
		if head_weight < .999: bad += 1
	check(face_count > 1500 and bad == 0,"entire imported face, chin and beard follow the head (%d vertices, %d bad)" % [face_count,bad])
	var bank := load("res://assets/lod/archer_poses.res")
	var pose_mesh: ArrayMesh = bank.get_meta("pose_mesh")
	check(pose_mesh.surface_get_array_index_len(0) == body.mesh.surface_get_array_index_len(0),
		"GPU archer retains the original triangles across clothing and skin seams")
	var clips: Dictionary = bank.get_meta("clips")
	var body_transform: Transform3D = bank.get_meta("body_transform")
	var reference: Dictionary = clips[actor.animation_map["bow_idle"]]
	var first: PackedVector3Array = reference.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var first_head: Transform3D = reference.bones[0][head_name]
	# Match the compact LOD to the original face through the unchanged UVs.
	# Classifying an animated vertex by height would also include raised arms.
	var lod_uvs: PackedVector2Array = reference.meshes[0].surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var rigid := {}
	for i in first.size():
		var local: Vector3 = first_head.affine_inverse() * body_transform * first[i]
		if face_uvs.has(lod_uvs[i]):
			rigid[i] = local
	var peak := 0.0
	var worst := ""
	for clip: Dictionary in clips.values():
		for frame in 8:
			var posed: PackedVector3Array = clip.meshes[frame].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var head_inverse: Transform3D = (clip.bones[frame][head_name] as Transform3D).affine_inverse()
			for i: int in rigid:
				var error: float = (head_inverse * body_transform * posed[i]).distance_to(rigid[i])
				if error > peak:
					peak = error
					worst = "clip %s frame %d vertex %d" % [clips.find_key(clip),frame,i]
	print("LOD worst ",worst)
	check(rigid.size() > 500 and peak < .0001,"distant face remains rigid in all %d clips (%d vertices; error %.6f)" % [clips.size(),rigid.size(),peak])
	check(bank.get_meta("pose_positions").get_height() == clips.size()*8,"GPU animation texture contains all rebuilt poses")
	var budgets := [6200, 3000, 1000]
	var tiers := ["archer_mid", "archer_far", "archer_overview"]
	for index in tiers.size():
		var tier: String = tiers[index]
		var lod: Resource = load("res://assets/lod/%s_poses.res" % tier)
		var lod_mesh: ArrayMesh = lod.get_meta("pose_mesh")
		check(lod_mesh.surface_get_array_index_len(0) <= budgets[index] * 3, "%s surface fits its triangle budget" % tier)
		check(bool(lod.get_meta("archer_body_only")) == (index > 0), "%s uses the correct equipment detail" % tier)
		var lod_clips: Dictionary = lod.get_meta("clips")
		var aligned: bool = clips.keys() == lod_clips.keys() and bank.get_meta("bone_names") == lod.get_meta("bone_names")
		if aligned:
			for name in clips:
				var source: Dictionary = clips[name]
				var alternate: Dictionary = lod_clips[name]
				if alternate.frame_start != source.frame_start or alternate.duration != source.duration or alternate.loop != source.loop:
					aligned = false
					break
		check(aligned, "%s shares the main archer animation layout" % tier)
	quit(failures)
