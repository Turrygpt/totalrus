extends SceneTree
var failures:=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func run() -> void:
	change_scene_to_file("res://tools/front_qa_world.tscn")
	await create_timer(1).timeout
	var world=current_scene
	world.combat_fronts.set_physics_process(false)
	for g in world.squads:
		g.set_physics_process(false)
		for s in g.soldiers:
			s.stop();s.alive=false;s.collision_layer=0;s.set_physics_process(false)
	var a=world.squad.soldiers[0]
	var front=world.enemy.soldiers[0]
	var rear=world.enemy.soldiers[1]
	for s in [a,front,rear]:
		s.alive=true;s.collision_layer=2;s.busy=false;s.animation_clock=0;s.velocity=Vector3.ZERO;s.hp=1000
	a.position=Vector3.ZERO;front.position=Vector3(0,0,-2);rear.position=Vector3(10,0,10)
	world.combat_index.rebuild()
	a.order_attack(front,false);a.threat_timer=0;a.update_combat()
	var spear_stop:float=a.target.distance_to(front.position)
	check(spear_stop>1.5 and spear_stop<1.85,"spear approach stops at thrusting distance")
	a.has_spear=false;a.threat_timer=0;a.update_combat()
	var sword_stop:float=a.target.distance_to(front.position)
	check(sword_stop<1.0 and sword_stop<spear_stop-.5,"swordsman approaches half a metre closer than spearman")
	check(not a.active_action.begins_with("attack"),"sword cannot strike from spear range")
	a.has_spear=true;front.position=Vector3(0,0,-.85);world.combat_index.rebuild();a.threat_timer=0;a.update_combat()
	check(a.target.z>.3 and a.speed_limit<=1.1,"crowded spearman backs away to make room")
	front.position=Vector3(0,0,-5);rear.position=Vector3(0,0,1.5)
	rear.combat_target=a;rear.attack_order=true
	a.combat_target=front;a.rotation.y=0;a.threat_timer=0;world.combat_index.rebuild();a.update_combat()
	check(a.combat_target==rear and absf(angle_difference(a.final_heading,PI))<.01,"nearby attacker behind replaces distant pursuit target")
	a.attack_cooldown=20;a.set_physics_process(true)
	await create_timer(1.3).timeout
	check((-a.global_basis.z).dot((rear.position-a.position).normalized())>.85,"fighter turns his shield toward the nearby rear threat")
	print("WEAPON_SPACING_QA ",JSON.stringify({"failures":failures,"spear_stop":spear_stop,"sword_stop":sword_stop}))
	world.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
