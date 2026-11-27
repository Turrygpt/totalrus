extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world=current_scene
	world.camera_locked=true;world.profiling_skip_banners=true
	for b in world.banners: b.hide()
	for g in world.squads:
		g.ai_enabled=false;g.stop();g.set_physics_process(false);g.selected=false
		for s in g.soldiers: s.set_physics_process(false);s.hide()
	world.get_node("Terrain").hide()
	var floor_mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(30,30)
	floor_mesh.mesh=plane
	var grey:=StandardMaterial3D.new();grey.albedo_color=Color(.27,.29,.26);grey.roughness=1
	floor_mesh.material_override=grey;world.add_child(floor_mesh)
	var actor=world.squad.soldiers[0]
	actor.position=Vector3(1.1,0,0);actor.rotation.y=0;actor.visual_position_from=actor.position;actor.visual_yaw_from=0
	actor.show();actor.play_clip("idle_spear");actor.player.advance(.1)
	actor.spear.hide();actor.shield.hide();actor.sword.hide()
	var document:=GLTFDocument.new();var data:=GLTFState.new()
	assert(document.append_from_file("C:/Users/Admin/Downloads/knight lp.glb",data)==OK)
	var candidate:=document.generate_scene(data)
	world.add_child(candidate)
	var bounds:=AABB();var first:=true
	for part:MeshInstance3D in candidate.find_children("*","MeshInstance3D",true,false):
		var box:AABB=part.global_transform*part.get_aabb()
		bounds=box if first else bounds.merge(box);first=false
	var scale_factor:=1.8/bounds.size.y
	candidate.scale*=scale_factor
	candidate.rotation.y=PI
	candidate.position=Vector3(-1.1,0,0)-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z).rotated(Vector3.UP,PI)*scale_factor
	print("KNIGHT_BOUNDS ",bounds," scale ",scale_factor)
	for i in 3:
		var offset:=Vector3(0,1.8,-5.5).rotated(Vector3.UP,[0,.7,PI][i])
		world.camera.position=offset;world.camera.look_at(Vector3(0,.95,0))
		await create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/knight_compare_"+str(i)+".png")
	world.queue_free();await process_frame;await process_frame;quit()
