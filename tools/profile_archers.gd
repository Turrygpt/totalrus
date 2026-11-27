extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	set_meta(&"battle_size", 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world = current_scene
	for g in world.squads:
		g.ai_enabled = false
		g.stop()
	for stage in 5:
		if stage == 1:
			for g in world.squads:
				for s in g.soldiers: s.player.pause()
		if stage == 2:
			for g in world.squads.filter(func(g):return g.unit_kind == "archer"):
				g.set_physics_process(false)
				for s in g.soldiers: s.set_physics_process(false); s.agent.avoidance_enabled = false
		if stage == 3:
			for g in world.squads:
				g.set_physics_process(false)
				for s in g.soldiers: s.set_physics_process(false); s.agent.avoidance_enabled = false
		if stage == 4:
			for g in world.squads: g.hide()
		await create_timer(3).timeout
		print("PROFILE ",stage," fps ",Engine.get_frames_per_second()," process ",Performance.get_monitor(Performance.TIME_PROCESS)*1000," physics ",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	quit()
