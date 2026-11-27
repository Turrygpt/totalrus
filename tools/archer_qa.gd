extends SceneTree

const FIELD = preload("res://scripts/battlefield_bounds.gd")
var failures: Array[String] = []
var world: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failures.append(message)
func wait(seconds: float) -> void: await create_timer(seconds).timeout
func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/archer_qa/"+name+".png")
func click_banner(index: int, button: int) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.position = world.camera.unproject_position(world.banners[index].world_standard.fabric.global_position)
	click.pressed = true
	root.push_input(click,true)
	click.pressed = false
	root.push_input(click,true)

func run() -> void:
	set_meta(&"battle_size", 2)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await wait(1)
	world = current_scene
	DirAccess.make_dir_recursive_absolute("res://build/archer_qa")
	check(world.squads.size() == 4 and world.team_alive(0) == 90 and world.team_alive(1) == 90,"four squads: 60 infantry and 30 archers on each side")
	check(world.friendly_archers.alive_count() == 30 and world.enemy_archers.alive_count() == 30,"both archer units contain 30 fighters")
	click_banner(2,MOUSE_BUTTON_LEFT)
	await wait(.1)
	check(world.selected_squad == world.friendly_archers and not world.squad.selected,"archer banner selects its own unit")
	world.set_battle_paused(false)
	click_banner(3,MOUSE_BUTTON_RIGHT)
	await wait(.1)
	check(world.friendly_archers.attack_target == world.enemy_archers,"enemy banner directs selected archers")
	await shot("01_four_squads")
	for group in world.squads:
		group.stop()
		group.ai_enabled = false
		for s in group.soldiers:
			s.set_physics_process(false)
			s.agent.avoidance_enabled = false
			s.collision_layer = 0
	var archers = world.friendly_archers
	var a = archers.soldiers[0]
	var b = world.enemy.soldiers[0]
	for group in world.squads:
		for s in group.soldiers:
			if s != a and s != b:
				s.remove_from_group("combatants")
	a.position = FIELD.project(Vector3(40,0,25))
	b.position = FIELD.project(Vector3(40,0,3))
	a.target = a.position
	b.target = b.position
	b.max_hp = 500
	b.hp = 500
	b.guarding = false
	b.shield_raised = false
	a.collision_layer = 2
	b.collision_layer = 2
	a.rotation.y = 0
	a.final_heading = 0
	a.agent.avoidance_enabled = true
	a.set_physics_process(true)
	archers.members = [a]
	archers.refresh_center()
	world.enemy.refresh_center()
	archers.command_attack(world.enemy,false)
	a.order_attack(b,false)
	a.shoot_cooldown = 0
	await wait(10)
	check(a.shots_fired >= 2 and archers.ammo_count() == 12 - a.shots_fired,"ranged fire consumes one squad arrow per volley")
	check(b.hp < b.max_hp,"ballistic arrows hit and damage an enemy")
	var count: int = archers.ammo_count()
	archers.release_volley()
	check(archers.ammo_count() == count,"completed volley cannot fire twice")
	a.cancel_shot()
	b.position = FIELD.project(a.position+Vector3(0,0,-6))
	var before: float = a.position.distance_to(b.position)
	await wait(1.6)
	check(a.retreating and a.position.distance_to(b.position) > before+2,"archer runs away from approaching enemy")
	archers.stop()
	archers.ranged_retreat_cooldown = 10.0
	a.velocity = Vector3.ZERO
	a.safe_velocity = Vector3.ZERO
	b.position = FIELD.project(a.position+Vector3(0,0,-1.4))
	archers.command_attack(world.enemy,false)
	a.order_attack(b,false)
	await wait(1.0)
	check(a.sword_drawn and a.bow.get_parent() == a.bow_back,"close enemy makes archer stow bow and draw knife")
	var health: float = b.hp
	await wait(3)
	check(b.hp < health,"archer fights with knife at close range")
	b.position = FIELD.project(a.position+Vector3(0,0,-10))
	await wait(1.8)
	check(not a.sword_drawn and a.bow.get_parent() == a.bow_socket,"archer returns to bow after separation")
	a.cancel_shot()
	a.order_attack(b,false)
	a.start_shot()
	count = archers.ammo_count()
	a.die()
	await wait(2.5)
	check(archers.ammo_count() == count and not a.busy,"death cancels a pending shot")
	change_scene_to_file("res://scenes/battlefield.tscn")
	await wait(1)
	world = current_scene
	world.set_battle_paused(false)
	world.squad.command_attack(world.enemy,true)
	world.friendly_archers.command_attack(world.enemy,true)
	var elapsed := 0.0
	var min_fps := 1000
	while elapsed < 85 and world.team_alive(0) > 0 and world.team_alive(1) > 0:
		await wait(2)
		elapsed += 2
		if elapsed >= 8: min_fps = mini(min_fps,Engine.get_frames_per_second())
		if int(elapsed)%10 == 0:
			print("ARCHER_BATTLE ",elapsed," alive ",world.team_alive(0),"/",world.team_alive(1)," shots ",world.friendly_archers.soldiers.reduce(func(sum,s):return sum+s.shots_fired,0),"/",world.enemy_archers.soldiers.reduce(func(sum,s):return sum+s.shots_fired,0))
		if elapsed == 10: await shot("02_battle")
		if elapsed == 14:
			world.focus = world.friendly_archers.center()+Vector3.UP*.6
			world.camera_distance = 14
			world.update_camera()
			await shot("03_archers_firing")
		if elapsed == 18:
			world.focus = Vector3.ZERO
			world.camera_distance = 58
			world.update_camera()
	check(world.friendly_archers.soldiers.any(func(s):return s.shots_fired > 0) and world.enemy_archers.soldiers.any(func(s):return s.shots_fired > 0),"both sides use bows in a full battle")
	var bounds := FIELD.for_scene(world)
	check(world.squads.all(func(g):return g.soldiers.all(func(s):
		return absf(s.position.x) <= bounds.x and absf(s.position.z) <= bounds.y
	)), "all fighters remain on the field")
	check(world.effects.battle_cries > 0,"infantry battle cries accompany the approach")
	await shot("04_result")
	var report := {"failures":failures,"survivors":[world.team_alive(0),world.team_alive(1)],"min_fps":min_fps,"seconds":elapsed}
	FileAccess.open("res://build/archer_qa/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ARCHER_QA ",JSON.stringify(report))
	for group in world.squads:
		group.ai_enabled = false
		group.stop()
	await wait(9)
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
