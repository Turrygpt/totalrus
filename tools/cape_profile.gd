extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	seed(73452)
	set_meta(&"battle_size", 15 if "--stress-30" in OS.get_cmdline_user_args() else 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(2).timeout
	var world = current_scene
	world.camera_distance = 8 if "--close" in OS.get_cmdline_user_args() else 85
	if "--close" in OS.get_cmdline_user_args():world.focus=world.squads[2].center()
	world.camera_locked = true
	world.update_camera()
	world.start_battle()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await create_timer(3).timeout
	var has_capes:bool=world.squads.any(func(g):return g.soldiers.any(func(s):return s.get("cape_mesh")!=null))
	var samples := []
	for window in 4:
		preload("res://scripts/profile_counters.gd").totals.clear()
		var t0 := Time.get_ticks_usec()
		var frames := 0
		var gpu := 0.0
		var physics := 0.0
		var draws := 0.0
		var times := []
		var previous := t0
		while Time.get_ticks_usec()-t0 < 5000000:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now-previous)/1000.0)
			previous = now
			frames += 1
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		times.sort()
		var sample := {"window":window,"capes":has_capes,"fps":frames*1000000.0/(Time.get_ticks_usec()-t0),"p95_ms":times[int(times.size()*.95)],"gpu_ms":gpu/frames,"physics_ms":physics/frames,"draws":draws/frames,"alive":world.team_alive(0)+world.team_alive(1)}
		samples.append(sample)
		print("CAPE_PROFILE ",JSON.stringify(sample))
		if preload("res://scripts/profile_counters.gd").enabled: print("SCRIPT_TIMING ",preload("res://scripts/profile_counters.gd").totals)
		if window==3:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/latest_close_battle.png")
	world.queue_free()
	await process_frame
	await process_frame
	quit()
