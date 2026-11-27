extends SceneTree
var failures:=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	seed(73452)
	set_meta(&"battle_size", 15 if "--stress-30" in OS.get_cmdline_user_args() else 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(2).timeout
	var world=current_scene
	if "--stress-30" in OS.get_cmdline_user_args():
		var mounted:Array=world.squads.filter(func(g):return g.unit_kind=="cavalry")
		if world.squads.size()!=30 or mounted.size()!=4 or mounted.any(func(g):return g.unit_count!=30):failures.append("mounted army composition")
		print("ARMY_COMPOSITION ",world.squads.size()," squads / ",world.team_alive(0)+world.team_alive(1)," fighters / ",mounted.size()," mounted squads")
	world.camera_locked=true
	world.start_battle()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var samples:=[]
	var participants:={}
	for stage in 6:
		var distance:float=[85.0,28.0,8.0][stage%3]
		for window in 2:
			var start:=Time.get_ticks_usec();var previous:=start;var frames:=0;var times:=[];var gpu:=0.0
			while Time.get_ticks_usec()-start<5000000:
				world.camera_distance=distance
				world.focus=Vector3.ZERO if stage%3==0 else world.squads[2].center()
				world.update_camera()
				await process_frame
				var now:=Time.get_ticks_usec();times.append((now-previous)/1000.0);previous=now;frames+=1
				gpu+=RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			times.sort()
			var attacking:=0;var moving:=0;var close_idle:=0;var flanking:=0
			for g in world.squads:
				for s in g.members:
					if s.active_action.begins_with("attack"):attacking+=1;participants[s.get_instance_id()]=true
					if s.motion_speed>.2:moving+=1
					if s.has_flank_plan():flanking+=1
					if s.attack_order and not s.busy and s.animation_clock<=0 and s.attack_cooldown<=0 and is_instance_valid(s.combat_target) and s.position.distance_to(s.combat_target.position)<s.weapon_reach() and s.combat_stall>1:close_idle+=1
			var sample:={"view_distance":distance,"seconds":world.battle_time,"fps":frames*1000000.0/(Time.get_ticks_usec()-start),"p95_ms":times[int(times.size()*.95)],"gpu_ms":gpu/frames,"full_skeletons":world.crowd_renderer.detailed_actors.size(),"alive":[world.team_alive(0),world.team_alive(1)],"attacking":attacking,"moving":moving,"flanking":flanking,"blocked_in_reach":close_idle}
			samples.append(sample);print("CAMERA_BATTLE ",JSON.stringify(sample))
			if sample.full_skeletons>16:failures.append("skeleton budget")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/battle_view_"+str(stage)+".png")
	for g in world.squads:
		for s in g.soldiers:
			if absf(s.position.x)>60 or absf(s.position.z)>45:failures.append("field bounds")
	var report:={"samples":samples,"failures":failures,"observed_attacking_fighters":participants.size()}
	FileAccess.open("res://build/latest_battle_performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CAMERA_QA ",JSON.stringify(report))
	world.camera_distance=85;world.focus=Vector3.ZERO;world.update_camera();world.set_speed(3)
	while world.team_in_battle(0)>0 and world.team_in_battle(1)>0 and world.battle_time<650:
		await create_timer(20).timeout
		print("FULL_BATTLE ",world.battle_time," alive ",world.team_alive(0)," / ",world.team_alive(1))
	world.set_speed(1)
	print("BATTLE_RESULT combat-ready ",world.team_in_battle(0)," / ",world.team_in_battle(1)," alive ",world.team_alive(0)," / ",world.team_alive(1))
	var mounted_strikers:=0
	for g in world.squads:
		if g.unit_kind=="cavalry":
			for s in g.soldiers:
				if s.kills>0:mounted_strikers+=1
	print("CAVALRY_KILLERS ",mounted_strikers)
	await create_timer(4).timeout
	world.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
