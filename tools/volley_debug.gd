extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	set_meta(&"battle_size", 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var w = current_scene
	w.start_battle()
	for i in 24:
		await create_timer(.5).timeout
		var report := []
		for g in w.squads:
			if g.unit_kind != "archer": continue
			var states := {}
			for a in g.soldiers:
				var state: String = (a.active_action if a.busy else ("retreat" if a.retreating else "idle"))
				states[state] = states.get(state,0)+1
			report.append({"unit":g.display_name,"ready":g.ranged_ready,"volley":g.volley_count,"shots":g.soldiers.reduce(func(t,a):return t+a.shots_fired,0),"states":states,"max_distance":g.soldiers.map(func(a):return a.position.distance_to(a.combat_target.position) if is_instance_valid(a.combat_target) else -1).max()})
		print("VOLLEY ",i*.5," ",JSON.stringify(report))
	quit()
