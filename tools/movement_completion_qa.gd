extends SceneTree
var failures:=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world=current_scene
	world.camera_locked=true
	for g in world.squads:g.ai_enabled=false;g.stop()
	world.set_speed(3)
	var group=world.squad
	for stage in 3:
		if stage==0:group.command_formation({"slots":group.make_formation_slots(group.center(),PI,10,12.6),"heading":PI,"columns":10,"width":12.6},false)
		elif stage==1:group.command(2,Vector3(22,0,8))
		else:group.command_formation({"slots":group.make_formation_slots(Vector3(5,0,29),0,8,10.5),"heading":0.0,"columns":8,"width":10.5},true)
		var until:float=world.battle_time+45
		while world.battle_time<until and not group.members.all(func(s):return s.position.distance_to(s.target)<.25):await create_timer(.5).timeout
		var arrived:int=group.members.filter(func(s):return s.position.distance_to(s.target)<.25).size()
		print("MOVEMENT_COMPLETE ",stage," arrived ",arrived," / ",group.members.size())
		if arrived!=60:failures.append("stage "+str(stage))
	print("MOVEMENT_QA ",failures)
	world.set_speed(1);world.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
