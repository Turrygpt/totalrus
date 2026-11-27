extends SceneTree
var world: Node3D
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func wait(seconds: float) -> void: await create_timer(seconds).timeout
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/army_qa/"+name+".png")
func run() -> void:
	set_meta(&"battle_size", 15 if "--stress-30" in OS.get_cmdline_user_args() else 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await wait(2)
	world = current_scene
	var stress := "--stress-30" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute("res://build/army_qa")
	var overview_distance: float = world.camera_distance
	world.update_camera()
	await shot("30_units" if stress else "10_units")
	world.start_battle()
	await wait(1)
	await shot("orders")
	var elapsed := 0.0
	var min_fps := 9999
	var samples := []
	var max_time := 45.0 if stress else 300.0
	while elapsed < max_time and world.result_text.is_empty():
		await wait(5)
		elapsed += 5
		var sample := {"seconds":elapsed,"fps":Engine.get_frames_per_second(),"alive":[world.team_alive(0),world.team_alive(1)],"arrows":0,"volleys":0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"frame_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000}
		for group in world.squads:
			if group.is_ranged():
				sample.volleys += group.volley_count
				for s in group.soldiers: sample.arrows += s.shots_fired
		samples.append(sample)
		min_fps = mini(min_fps,Engine.get_frames_per_second())
		print("ARMY ",JSON.stringify(sample))
		if elapsed == 15: await shot("30_melee" if stress else "10_melee")
		if elapsed == 30 and not stress: world.set_speed(3)
		if elapsed == 40 and not stress:
			world.focus = world.friendly_archers.center()
			world.camera_distance = 21
			world.update_camera()
			await shot("volley_close")
		if elapsed == 45 and not stress:
			world.focus = Vector3.ZERO; world.camera_distance = overview_distance; world.update_camera()
	if not stress and world.result_text.is_empty(): failures.append("battle did not finish")
	for group in world.squads:
		var bounds: Vector2 = world.field_half_size
		if not group.soldiers.all(func(s):return absf(s.position.x)<bounds.x and absf(s.position.z)<bounds.y): failures.append("field bounds")
	await shot("30_result" if stress else "10_result")
	var report := {"failures":failures,"samples":samples,"min_fps":min_fps,"seconds":elapsed,"survivors":[world.team_alive(0),world.team_alive(1)],"squads":world.squads.size()}
	FileAccess.open("res://build/army_qa/"+("stress30" if stress else "battle10")+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ARMY_QA ",JSON.stringify(report))
	for g in world.squads: g.ai_enabled=false; g.stop()
	world.set_speed(1)
	await wait(8)
	world.queue_free(); await process_frame; await process_frame
	quit(0 if failures.is_empty() else 1)
