extends SceneTree
const PROF=preload("res://scripts/profile_counters.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	seed(73452)
	set_meta(&"battle_size", 15 if "--stress-30" in OS.get_cmdline_user_args() else 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(2).timeout
	var world=current_scene
	world.camera_locked=true
	world.start_battle()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var pipeline_monitors:={}
	for name in ClassDB.class_get_integer_constant_list("Performance"):
		if "PIPELINE" in name:pipeline_monitors[name]=ClassDB.class_get_integer_constant("Performance",name)
	var rows:=[];var spikes:=[];var times:=[];var phases:=[]
	var start:=Time.get_ticks_usec();var previous:=start;var last_pipelines:={}
	for name in pipeline_monitors:last_pipelines[name]=Performance.get_monitor(pipeline_monitors[name])
	var did_reform:=false
	while Time.get_ticks_usec()-start<55000000:
		var seconds:float=(Time.get_ticks_usec()-start)/1000000.0
		world.camera_distance=28 if seconds<15 else (8 if seconds<35 else 85)
		world.focus=world.squads[2].center() if seconds<35 else Vector3.ZERO
		world.update_camera()
		await process_frame
		var now:=Time.get_ticks_usec();var ms:float=(now-previous)/1000.0;previous=now
		times.append(ms)
		var changed:={}
		for name in pipeline_monitors:
			var count:float=Performance.get_monitor(pipeline_monitors[name])
			if count!=last_pipelines[name]:changed[name]=count-last_pipelines[name]
			last_pipelines[name]=count
		var row:={"t":seconds,"frame_ms":ms,"cpu_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"scripts_us":PROF.totals.duplicate(),"pipelines":changed}
		PROF.totals.clear()
		rows.append(row)
		if ms>45:
			spikes.append(row)
			print("STUTTER ",JSON.stringify(row))
		if seconds>43 and not did_reform and "--reform" in OS.get_cmdline_user_args():
			did_reform=true
			for g in world.squads:g.stop();g.reform_after_battle()
		if phases.size()<int(seconds/10):
			phases.append(seconds);print("STUTTER_PROGRESS ",seconds," alive ",world.team_alive(0)+world.team_alive(1))
	times.sort()
	var report:={"fps":rows.size()*1000000.0/(Time.get_ticks_usec()-start),"p95_ms":times[int(times.size()*.95)],"p99_ms":times[int(times.size()*.99)],"max_ms":times[-1],"over45":spikes.size(),"spikes":spikes,"pipelines":last_pipelines}
	print("STUTTER_RESULT ",JSON.stringify(report))
	var name:="res://build/stutter_"+("after" if "--after" in OS.get_cmdline_user_args() else "before")
	FileAccess.open(name+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	FileAccess.open(name+"_frames.json",FileAccess.WRITE).store_string(JSON.stringify(rows))
	world.queue_free();await process_frame;await process_frame;quit()
