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
	await create_timer(.7).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/warrior_full_close.png")
	actor.set_process(false)
	if not actor.crowd_visual:actor.crowd_visual=load("res://scripts/crowd_visual.gd").new(actor)
	actor.crowd_visual.set_distant(true)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/warrior_lod_close.png")
	world.queue_free();await process_frame;await process_frame;quit()
