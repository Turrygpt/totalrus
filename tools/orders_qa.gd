extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ",message)
	if not condition: failures.append(message)

func run() -> void:
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world = current_scene
	world.enemy.ai_enabled = false
	world.squad.ai_enabled = false
	world.squad.command(4,world.squad.center()+Vector3(-16,0,0))
	world.squad.command_attack(world.enemy,true)
	check(world.squad.pending_order.has("enemy"),"attack waits for committed throw and draw")
	await create_timer(4.5).timeout
	check(world.squad.spear_count() == 0 and world.squad.soldiers.all(func(s): return s.sword_drawn),"queued attack preserves all weapon transitions")
	check(world.squad.pending_order.is_empty() and world.squad.attack_target == world.enemy,"queued attack starts after the draw")
	world.squad.stop()
	check(world.squad.pending_order.is_empty() and world.squad.soldiers.all(func(s): return not s.attack_order),"stop cancels combat orders")
	var tones := {}
	for unit in world.squad.soldiers: tones[unit.hair_index] = true
	check(tones.size() >= 4,"subtle hair shades vary across the squad")
	await create_timer(7).timeout
	check(world.get_children().filter(func(n): return n.get_script() == preload("res://scripts/projectile.gd")).is_empty(),"entire volley dissolves and releases its objects")
	print("ORDERS_QA ",JSON.stringify({"failures":failures}))
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
