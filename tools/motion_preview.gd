extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world = current_scene
	world.camera_locked = true
	for group in world.squads:
		group.ai_enabled = false
		for s in group.soldiers:
			s.hide()
			s.set_physics_process(false)
	for b in world.banners:b.queue_free()
	world.banners.clear()
	var actor = world.squad.soldiers[0]
	actor.show()
	actor.position = Vector3.ZERO
	actor.rotation.y = 0
	world.camera.position = Vector3(2,1.75,-3.5)
	world.camera.look_at(Vector3(0,1,0))
	DirAccess.make_dir_recursive_absolute("res://build/motion_preview")
	for clip in ["walk_spear","run_spear","charge_spear","charge_sword"]:
		if clip.ends_with("sword"):
			actor.has_spear = false
			actor.spear.hide()
			actor.take_sword()
		actor.player.play(actor.animation_map[clip],0)
		actor.player.advance(0)
		for phase in [.25,.70]:
			actor.player.seek(actor.player.current_animation_length*phase,true)
			actor.player.pause()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/motion_preview/%s_%d.png" % [clip,int(phase*100)])
	quit()
