extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failures.append(message)
func run() -> void:
	set_meta(&"battle_size", 2)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world = current_scene
	for group in world.squads:
		group.stop()
		group.ai_enabled = false
		group.set_physics_process(false)
		for s in group.soldiers:
			s.set_physics_process(false)
			s.agent.avoidance_enabled = false
	world.set_battle_paused(false)
	var archers = world.friendly_archers
	var a = archers.soldiers[0]
	var b = world.enemy.soldiers[0]
	a.position = Vector3(45,0,30)
	b.position = Vector3(45,0,10)
	a.order_attack(b,false)
	a.scan_enemies()
	a.start_shot()
	a.show_arrow()
	a.order_move(Vector3(38,0,30),0,4.2,false,false)
	check(not a.busy and not a.held_arrow.visible and a.manual_move,"movement interrupts a bow draw immediately")
	a.stop()
	a.update_combat()
	check(not a.attack_order and not a.auto_fire and not a.busy,"stop prevents automatic shooting")
	a.order_fire_area(Vector3(45,0,5))
	a.scan_enemies()
	a.start_shot()
	a.events.stop()
	a.active_action = "bow_release"
	var ammo: int = archers.ammo_count()
	archers.members = [a]
	archers.volley_archers = [a]
	a.mark_arrow_ready()
	archers.release_volley()
	check(archers.ammo_count() == ammo-1 and a.fire_area,"area bombardment spends one squad arrow")
	a.cancel_shot()
	a.order_attack(b,false,true)
	b.position = a.position+Vector3(0,0,-8)
	a.scan_enemies()
	a.update_combat()
	check(not a.retreating and a.hold_position,"hold position disables automatic retreat")
	a.stop()
	archers.arrows_remaining = 0
	a.order_attack(b,false)
	a.scan_enemies()
	a.update_combat()
	await create_timer(.7).timeout
	check(a.sword_drawn and a.bow.get_parent() == a.bow_back,"empty quiver switches to knife")
	a.stop()
	a.celebrate_victory()
	check(a.animation_name == "bow_victory" and a.busy,"archer victory animation plays with weapon raised")
	await create_timer(3.0).timeout
	check(not a.busy,"archer celebration finishes")
	print("ARCHER_ORDERS_QA ",JSON.stringify({"failures":failures}))
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
