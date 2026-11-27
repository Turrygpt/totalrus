extends SceneTree
class Preview extends Node3D:
	var squads:=[]
var failures:=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func run()->void:
	var world:=Preview.new();root.add_child(world);current_scene=world
	var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-35,-30,0)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(2.4,1.6,-3.2);camera.look_at(Vector3(0,.95,0));camera.fov=38
	var actor:=CharacterBody3D.new();actor.set_script(load("res://scripts/soldier.gd"));world.add_child(actor);actor.set_physics_process(false);actor.set_process(false);actor.agent.avoidance_enabled=false
	var body:MeshInstance3D=actor.model.find_children("*","MeshInstance3D",true,false)[0]
	await process_frame
	var arrays:=body.mesh.surface_get_arrays(0)
	var skin:Skin=body.skin
	var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var stride:int=bones.size()/arrays[Mesh.ARRAY_VERTEX].size()
	var torso:=PackedInt32Array()
	for vertex in arrays[Mesh.ARRAY_VERTEX].size():
		var influence:=0.0
		for slot in stride:
			var bind:int=bones[vertex*stride+slot]
			var name:String=skin.get_bind_name(bind)
			if name.is_empty() and skin.get_bind_bone(bind)>=0:name=actor.skeleton.get_bone_name(skin.get_bind_bone(bind))
			if name in ["mixamorig_Spine","mixamorig_Spine1","mixamorig_Spine2","mixamorig:Spine","mixamorig:Spine1","mixamorig:Spine2"]:influence+=weights[vertex*stride+slot]
		if influence>.8:torso.append(vertex)
	check(torso.size()>100,"torso vertex selection available for deformation regression")
	var reference:=Vector3.ZERO
	var min_ratio:=1.0;var max_scale_error:=0.0;var min_height:=INF
	for clip in ["attack_spear","attack_spear_alt"]:
		actor.play_clip("combat_spear",0);actor.player.advance(.1)
		for frame in 120:
			if frame==1:actor.play_clip(clip,.18)
			if frame==88:actor.play_clip("combat_spear",.18)
			actor.player.advance(1.0/60.0);actor.skeleton.force_update_all_bone_transforms()
			await RenderingServer.frame_post_draw
			var mesh:ArrayMesh=body.bake_mesh_from_current_skeleton_pose()
			var points:PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var spine:int=actor.skeleton.find_bone("mixamorig:Spine2")
			if spine<0:spine=actor.skeleton.find_bone("mixamorig_Spine2")
			var to_torso:Transform3D=(actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(spine)).affine_inverse()*body.global_transform
			var lo:=Vector3.INF;var hi:=-Vector3.INF
			for index in torso:
				var v:Vector3=to_torso*points[index];lo=lo.min(v);hi=hi.max(v)
			if reference==Vector3.ZERO:reference=hi-lo
			if not torso.is_empty():
				var ratio:Vector3=(hi-lo)/reference;min_ratio=minf(min_ratio,minf(ratio.x,minf(ratio.y,ratio.z)))
			min_height=minf(min_height,mesh.get_aabb().size.y*1.8)
			for bone in actor.skeleton.get_bone_count():max_scale_error=maxf(max_scale_error,actor.skeleton.get_bone_pose_scale(bone).distance_to(Vector3.ONE))
			if frame in [1,24,40,65,95]:root.get_texture().get_image().save_png("res://build/transition_%s_%d.png"%[clip,frame])
	check(min_ratio>.82,"full skeleton keeps torso volume through attack blends")
	check(max_scale_error<.001 and min_height>1.45,"no bone scaling or body collapse during close animation")
	var bank:Resource=load("res://assets/lod/soldier_poses.res")
	var clips:Dictionary=bank.get_meta("clips")
	for name in ["attack_spear","attack_spear_alt"]:
		check(clips.has(actor.animation_map[name]),"GPU pose bank includes "+name)
		var event:Animation=actor.events.get_animation(name)
		check(event.track_get_key_count(0)==1 and event.track_get_key_time(0,0)<event.length,"one timed impact for "+name)
	print("SPEAR_TRANSITION ",JSON.stringify({"failures":failures,"torso_min_ratio":min_ratio,"scale_error":max_scale_error,"height_min":min_height}))
	world.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
