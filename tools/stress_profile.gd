extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	set_meta(&"battle_size", 15 if "--stress-30" in OS.get_cmdline_user_args() else 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(2).timeout
	var world = current_scene
	world.camera_distance=85; world.update_camera(); world.start_battle()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for stage in 7:
		if stage == 1: world.effects.profiling_disabled = true
		if stage == 2:
			for g in world.squads:
				for s in g.soldiers: s.set_process(false)
		if stage == 3:
			for g in world.squads:
				g.set_physics_process(false)
				for s in g.soldiers: s.set_physics_process(false)
		if stage == 4:
			for g in world.squads:
				for s in g.soldiers: s.agent.avoidance_enabled=false
		if stage == 5:
			for g in world.squads: g.hide()
		if stage == 6: world.combat_index.set_physics_process(false)
		preload("res://scripts/profile_counters.gd").totals.clear()
		var until := Time.get_ticks_msec()+5000
		var frames := 0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec()<until:
			await process_frame
			frames+=1
		if stage == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/stress_current.png")
		print("SCRIPT_TIMING ",preload("res://scripts/profile_counters.gd").totals)
		print("STRESS_PROFILE ",stage," ",JSON.stringify({"fps":frames*1000.0/(Time.get_ticks_msec()-t0),"frame_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}))
	world.queue_free(); await process_frame; await process_frame; quit()
