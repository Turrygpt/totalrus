extends SceneTree
var failures:=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func reset_actor(s:Node3D,point:Vector3,heading:float,active:bool) -> void:
	s.events.stop();s.busy=false;s.active_action="";s.attack_order=false;s.combat_target=null
	s.hp=1000;s.max_hp=1000;s.velocity=Vector3.ZERO;s.position=point;s.rotation.y=heading;s.target=point
	s.visual_position_from=point;s.visual_yaw_from=heading;s.visual_elapsed=1
	s.collision_layer=2;s.show();s.set_physics_process(active);s.has_spear=false;s.spear.hide();s.take_sword()
	s.attack_cooldown=0;s.animation_clock=0;s.guarding=false;s.reset_approach()
func run() -> void:
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world=current_scene
	world.camera_locked=true;world.camera_distance=32;world.focus=Vector3(0,0,1);world.update_camera()
	for g in world.squads:
		g.ai_enabled=false;g.set_physics_process(false)
		for s in g.soldiers:s.stop();s.set_physics_process(false);s.hide();s.collision_layer=0
	var a=world.squad.soldiers[0];var b=world.squad.soldiers[1];var foe=world.enemy.soldiers[0]
	world.squad.members=[a,b];world.enemy.members=[foe]
	world.squad.formation_width=1.8;world.enemy.formation_width=1.8
	reset_actor(a,Vector3(-.45,0,3.5),0,true);reset_actor(b,Vector3(.45,0,3.5),0,true)
	reset_actor(foe,Vector3.ZERO,PI,true)
	world.squad.refresh_center();world.enemy.refresh_center();world.combat_index.rebuild()
	a.order_attack(foe,true);b.order_attack(foe,true);foe.order_attack(a,false)
	check(absf(angle_difference(a.combat_slot_angle,b.combat_slot_angle))>.8,"two attackers reserve distinct approach sectors")
	var attacking:={};var minimum:=INF;var until:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<until:
		await process_frame
		for s in [a,b]:
			if s.active_action.begins_with("attack"):attacking[s.index]=true
		minimum=minf(minimum,a.position.distance_to(b.position))
	check(attacking.size()==2 and foe.hp<950,"both attackers reach and strike the same enemy")
	check(minimum>.48,"attackers do not occupy the same body space")
	reset_actor(a,Vector3(0,0,4),0,true);reset_actor(b,Vector3(0,0,1.25),0,false)
	reset_actor(foe,Vector3.ZERO,PI,false)
	world.squad.refresh_center();world.enemy.refresh_center();world.combat_index.rebuild()
	a.order_attack(foe,true)
	var flanked:=false;until=Time.get_ticks_msec()+14000
	while Time.get_ticks_msec()<until:
		await process_frame
		if absf(a.position.x)>.55:flanked=true
	check(flanked and foe.hp<990,"blocked attacker goes around an ally and strikes")
	world.camera_distance=8;world.update_camera();await create_timer(1).timeout
	check(world.crowd_renderer.detailed_actors.size()<=16,"close camera respects skeleton budget")
	print("FLOW_QA ",JSON.stringify({"failures":failures,"minimum_gap":minimum,"enemy_hp":foe.hp,"attacker_position":str(a.position)}))
	world.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
