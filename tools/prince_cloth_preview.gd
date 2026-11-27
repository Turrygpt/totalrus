extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	set_meta(&"battle_size", 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world=current_scene
	world.camera_locked=true;world.profiling_skip_banners=true
	for b in world.banners:b.hide()
	for g in world.squads:
		g.ai_enabled=false;g.set_physics_process(false);g.selected=false
		for s in g.soldiers:s.stop();s.set_physics_process(false);s.hide()
	for i in 2:
		var actor=world.squads[2].soldiers[i]
		if actor.crowd_visual and actor.crowd_visual.distant:actor.crowd_visual.set_distant(false)
		actor.show();actor.position=Vector3(-.8+i*1.6,0,0);actor.rotation.y=PI
		actor.visual_position_from=actor.position;actor.visual_yaw_from=PI
		actor.play_clip("attack_spear");actor.player.seek(.4,true);actor.player.advance(0)
		actor.set_process(false)
		if i==1:
			actor.crowd_visual=preload("res://scripts/crowd_visual.gd").new(actor)
			actor.crowd_visual.set_distant(true)
	world.camera.position=Vector3(0,1.7,-4.5);world.camera.look_at(Vector3(0,1,0))
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/cape_quality_comparison.png")
	world.queue_free();await process_frame;await process_frame;quit()
