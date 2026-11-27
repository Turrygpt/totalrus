extends SceneTree

func _initialize() -> void: call_deferred("run")
func run() -> void:
	set_meta(&"battle_size", 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(2).timeout
	var world = current_scene
	world.squad.command_attack(world.enemy,true)
	world.friendly_archers.command_attack(world.enemy,true)
	var samples := []
	for i in 24:
		await create_timer(1).timeout
		if i == 12:
			world.focus = world.friendly_archers.center()+Vector3.UP*.6
			world.camera_distance = 14
			world.update_camera()
		if i == 18:
			world.focus = Vector3.ZERO
			world.camera_distance = 58
			world.update_camera()
		var sample := {"second":i+1,"fps":Engine.get_frames_per_second(),"frame_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"alive":world.team_alive(0)+world.team_alive(1)}
		samples.append(sample)
		print("PERFORMANCE ",JSON.stringify(sample))
	FileAccess.open("res://build/performance.json",FileAccess.WRITE).store_string(JSON.stringify(samples,"  "))
	world.queue_free()
	await process_frame
	await process_frame
	quit()
