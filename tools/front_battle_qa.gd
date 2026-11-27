extends SceneTree
var failures:=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func run() -> void:
	seed(73452)
	change_scene_to_file("res://tools/front_qa_world.tscn")
	await create_timer(1).timeout
	var world=current_scene
	world.camera_distance=55;world.camera_locked=true;world.camera_yaw=0;world.focus=Vector3.ZERO;world.update_camera()
	if "--close" in OS.get_cmdline_user_args():world.camera_distance=8;world.update_camera()
	var unequal:bool="--unequal" in OS.get_cmdline_user_args()
	var swords:bool="--swords" in OS.get_cmdline_user_args()
	for g in world.squads:
		for s in g.members:
			s.hp=350;s.max_hp=350
			if swords and g.team==0:s.has_spear=false;s.spear.hide();s.take_sword()
	world.squad.command_attack(world.enemy,true)
	world.enemy.command_attack(world.squad,true)
	var samples:=[];var attackers:={};var contacts:=[];var sword_contacts:=[]
	for second in 36:
		await create_timer(1).timeout
		var striking:=0;var near:=0;var moving:=0;var backs:=0;var checks:=0
		var min_x:=INF;var max_x:=-INF;var planned:=0;var wings:=0
		for g in world.squads:
			for s in g.members:
				min_x=minf(min_x,s.position.x);max_x=maxf(max_x,s.position.x)
				if s.has_flank_plan():planned+=1
				if s.flank_waypoint!=Vector3.INF:wings+=1
				if s.motion_speed>.5:moving+=1
				if not is_instance_valid(s.combat_target) or not s.combat_target.alive:continue
				var offset:Vector3=s.combat_target.position-s.position
				if offset.length()<=s.weapon_reach()+.2:near+=1
				if offset.length()<2.5 and not s.busy:
					checks+=1
					if (-s.global_basis.z).dot(offset.normalized())<0:backs+=1
				if s.active_action.begins_with("attack"):
					striking+=1;attackers[s.get_instance_id()]=true
					if s.has_spear:contacts.append(offset.length())
					else:sword_contacts.append(offset.length())
		var sample={"t":second+1,"alive":[world.team_alive(0),world.team_alive(1)],"attacking":striking,"contact":near,"moving":moving,"width":max_x-min_x,"plans":planned,"wings":wings,"backs":backs,"facing_checks":checks}
		samples.append(sample)
		if second%5==4:print("FRONT_SAMPLE ",JSON.stringify(sample))
		if second in [9,24,35]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/front_%s_%d.png"%["unequal" if unequal else ("swords" if swords else "equal"),second+1])
	check(attackers.size()>50 if not unequal else attackers.size()>40,"most front fighters participate in actual attacks")
	check(samples[0].width<15,"no scripted lateral deployment before contact")
	check(samples.any(func(v):return v.plans>0),"blocked rear ranks use flank routes after contact")
	var mean:=0.0
	for d in contacts:mean+=d
	mean/=maxi(1,contacts.size())
	check(mean>1.25 and mean<2.0,"spear strikes retain thrusting distance")
	if swords:
		var sm:=0.0
		for d in sword_contacts:sm+=d
		sm/=maxi(1,sword_contacts.size())
		check(sm<1.2 and sm<mean-.25,"swordsmen close inside spear distance")
		print("SWORD_MEAN ",sm)
	print("FRONT_QA ",JSON.stringify({"failures":failures,"attackers":attackers.size(),"spear_distance":mean,"samples":samples}))
	world.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
