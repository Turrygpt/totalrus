extends SceneTree
var failures:=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func run() -> void:
	change_scene_to_file("res://tools/cavalry_qa_world.tscn")
	await create_timer(2).timeout
	var world=current_scene
	world.camera_locked=true;world.camera_distance=8;world.focus=world.squad.soldiers[2].position;world.update_camera()
	await create_timer(1).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/cavalry_integrated_close.png")
	var a=world.squad.soldiers[0]
	check(world.squad.alive_count()==30 and a.mounted,"thirty mounted combatants")
	check(a.crowd_visual.bank!=null,"mounted GPU pose bank loaded")
	world.camera_distance=38;world.focus=Vector3(0,0,5);world.update_camera()
	await create_timer(1).timeout
	check(world.squad.members.all(func(s):return s.crowd_visual.distant),"whole mounted squad uses instanced animation at distance")
	world.squad.command_attack(world.enemy,true);world.enemy.command_attack(world.squad,false)
	var riders_hit:={};var max_speed:=0.0;var peak_ready:=0
	for second in 28:
		await create_timer(1).timeout
		var ready:=0
		for s in world.squad.members:
			max_speed=maxf(max_speed,s.motion_speed)
			if s.weapon_ready:ready+=1
			if s.active_action.begins_with("attack"):riders_hit[s.index]=true
		peak_ready=maxi(peak_ready,ready)
		if second in [5,14,27]:
			print("MOUNTED_SAMPLE ",second+1," alive ",world.team_alive(0)," / ",world.team_alive(1)," hits ",world.effects.hits," peak_speed ",max_speed)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/cavalry_contact_"+str(second+1)+".png")
	check(max_speed>5 and max_speed<7.5,"cavalry gallops within its speed cap")
	check(peak_ready>20,"riders lower weapons before contact")
	check(riders_hit.size()>8 and world.effects.hits>20,"mounted warriors fight and exchange damage with infantry")
	check(world.squad.members.all(func(s):return absf(s.position.x)<60 and absf(s.position.z)<45),"mounted units stay on the battlefield")
	print("CAVALRY_QA ",JSON.stringify({"failures":failures,"attackers":riders_hit.size(),"max_speed":max_speed}))
	world.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
