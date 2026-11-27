extends SceneTree
class Preview extends Node3D:
	var squads:=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Preview.new();root.add_child(world);current_scene=world
	var light:=DirectionalLight3D.new();world.add_child(light);light.rotation_degrees=Vector3(-40,-30,0)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.2,.24,.28);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=.5;world.add_child(env)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(2.4,1.6,-3.2);camera.look_at(Vector3(0,.95,0));camera.fov=38
	var actor:=CharacterBody3D.new();actor.set_script(load("res://scripts/soldier.gd"));world.add_child(actor);actor.set_physics_process(false);actor.set_process(false);actor.agent.avoidance_enabled=false
	await process_frame
	var body:MeshInstance3D=actor.model.find_children("*","MeshInstance3D",true,false)[0]
	if "--grip-test" in OS.get_cmdline_user_args(): actor.spear.rotation = Vector3.ZERO
	var frames:=[]
	var clips:Array=["spear_pack_attack_1","spear_pack_attack_2"] if "--pack" in OS.get_cmdline_user_args() else ["combat_spear","attack_spear"]
	for clip in clips:
		actor.player.play(actor.animation_map[clip],0)
		var count:int=12 if "attack" in clip else 1
		for frame in count:
			var time:float=frame*actor.player.get_animation(actor.animation_map[clip]).length/11.0
			actor.player.seek(time,true);actor.player.advance(0);actor.skeleton.force_update_all_bone_transforms()
			await RenderingServer.frame_post_draw
			var mesh:ArrayMesh=body.bake_mesh_from_current_skeleton_pose()
			var suspect:={}
			for i in actor.skeleton.get_bone_count():
				var scale:Vector3=actor.skeleton.get_bone_pose_scale(i)
				if scale.distance_to(Vector3.ONE)>.01:suspect[actor.skeleton.get_bone_name(i)]=str(scale)
			frames.append({"clip":clip,"t":time,"aabb":str(mesh.get_aabb()),"scale":suspect,"spear_axis":str(actor.spear.global_basis.y.normalized()),"grip":str(actor.right_socket.global_transform)})
			root.get_texture().get_image().save_png("res://build/pose_%s_%02d.png"%[clip,frame])
	var out:=FileAccess.open("res://build/spear_pose_qa.json",FileAccess.WRITE);out.store_string(JSON.stringify(frames,"  "));out.close()
	world.queue_free();await process_frame;quit()
