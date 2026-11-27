extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	set_meta(&"battle_size", 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(2).timeout
	var world = current_scene
	world.camera_distance = 72
	world.update_camera()
	for g in world.squads: g.ai_enabled = false; g.stop()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for stage in 4:
		for g in world.squads:
			if g.unit_kind == "archer":
				g.command(2,Vector3((-1 if stage%2 == 0 else 1)*35,0,25 if g.team == 0 else -25))
		if stage == 1:
			for g in world.squads: g.selection_rings.hide(); g.set_process(false)
		if stage == 2:
			for g in world.squads:
				for s in g.soldiers:
					if g.unit_kind == "archer": s.skeleton.skeleton_updated.disconnect(s.update_bow_string)
		if stage == 3:
			for g in world.squads:
				for s in g.soldiers: s.set_process(false)
		await create_timer(2).timeout
		var samples := []
		for i in 4:
			await create_timer(.5).timeout
			samples.append({"fps":Engine.get_frames_per_second(),"frame_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		print("MOVEMENT_PROFILE ",stage," ",JSON.stringify(samples))
		if stage == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/movement_profile.png")
	for g in world.squads: g.stop()
	await create_timer(2).timeout
	world.queue_free(); await process_frame; await process_frame
	quit()
