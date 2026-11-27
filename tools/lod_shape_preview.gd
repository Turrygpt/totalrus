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
	var actor=world.squad.soldiers[0]
	actor.position=Vector3.ZERO;actor.rotation.y=0;actor.visual_position_from=Vector3.ZERO;actor.visual_yaw_from=0
	actor.show();actor.play_clip("idle_spear");actor.player.advance(.1)
	world.camera.position=Vector3(1.2,1.8,-3.8);world.camera.look_at(Vector3(0,1,0))
	await create_timer(.5).timeout
	actor.set_process(false)
	var body:MeshInstance3D=actor.model.find_children("*","MeshInstance3D",true,false)[0]
	var baked: ArrayMesh=body.bake_mesh_from_current_skeleton_pose()
	var surface:=RenderingServer.mesh_get_surface(body.mesh.get_rid(),0)
	var copy:=MeshInstance3D.new()
	world.add_child(copy);copy.global_transform=body.global_transform
	copy.material_override=body.get_active_material(0)
	body.hide()
	for i in surface.lods.size():
		var arrays:=baked.surface_get_arrays(0)
		var indices:=PackedInt32Array()
		var bytes:PackedByteArray=surface.lods[i].index_data
		for j in bytes.size()/2: indices.append(bytes.decode_u16(j*2))
		arrays[Mesh.ARRAY_INDEX]=indices
		arrays[Mesh.ARRAY_BONES]=null;arrays[Mesh.ARRAY_WEIGHTS]=null
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		copy.mesh=mesh
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/lod_shape_"+str(i)+".png")
		print("LOD_SHAPE ",i," triangles ",indices.size()/3)
	world.queue_free();await process_frame;await process_frame;quit()
