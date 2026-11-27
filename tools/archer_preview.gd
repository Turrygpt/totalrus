extends SceneTree

func _initialize() -> void: call_deferred("run")
func run() -> void:
	set_meta(&"battle_size", 2)
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
	var a = world.friendly_archers.soldiers[0]
	a.show()
	a.position = Vector3.ZERO
	a.rotation.y = 0
	world.camera.position = Vector3(2,1.75,-3.5)
	world.camera.look_at(Vector3(0,1,0))
	DirAccess.make_dir_recursive_absolute("res://build/archer_preview")
	for clip in ["bow_idle","bow_draw","bow_aim","bow_release","bow_run","bow_victory","knife_idle","knife_attack"]:
		if clip.begins_with("knife"):
			a.take_sword()
			a.bow.reparent(a.bow_back,false)
			a.bow.transform = Transform3D(Basis(Vector3.RIGHT,PI/2).scaled(Vector3.ONE/1.8),Vector3.ZERO)
		a.active_action = clip
		a.held_arrow.visible = clip in ["bow_draw","bow_aim"]
		a.player.play(a.animation_map[clip],0)
		a.player.advance(0)
		for phase in [.25,.70]:
			a.player.seek(a.player.current_animation_length*phase,true)
			a.player.pause()
			await process_frame
			a.update_bow_string()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/archer_preview/%s_%d.png" % [clip,int(phase*100)])
	quit()
