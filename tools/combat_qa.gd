extends Node

class DuelRoot extends Node3D:
	func alert_enemy(_other: Node3D) -> void:
		pass

var failures: Array[String] = []
var world: Node3D
var output := "res://build/combat_qa"
var lowest_fps := 9999

func check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func screenshot(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(filename + ".png"))

func click_enemy(double := false, banner := false) -> void:
	var target = world.enemy.living()[0]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.double_click = double
	click.position = world.camera.unproject_position(target.global_position + Vector3.UP * .8)
	if banner:
		click.position = world.camera.unproject_position(world.banners[1].world_standard.fabric.global_position)
	get_viewport().push_input(click, true)
	click.pressed = false
	get_viewport().push_input(click, true)

func run(battlefield: Node3D) -> void:
	world = battlefield
	world.set_battle_paused(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await wait(2.0)
	check(world.squad.alive_count() == 60 and world.enemy.alive_count() == 60, "two squads, 120 living combatants")
	for group in [world.squad, world.enemy]:
		var textures := [0,0,0]
		for soldier in group.soldiers:
			textures[soldier.appearance_index] += 1
		check(textures == [20,20,20], "balanced randomized appearances on team %d" % group.team)
	var animations: Dictionary = world.squad.soldiers[0].animation_map
	check(["advance_spear","advance_sword","attack_spear","attack_sword","attack_sword_alt","hit","block","death_back","death_side"].all(func(c): return animations.has(c)), "all combat clips imported")
	check(world.effects.sounds.values().all(func(bank): return bank.size() >= 4), "downloaded swing, clash, voice and footstep banks loaded")
	var allied_shield: ShaderMaterial = world.squad.soldiers[0].shield.get_child(0).material_override
	var enemy_shield: ShaderMaterial = world.enemy.soldiers[0].shield.get_child(0).material_override
	check(allied_shield.get_shader_parameter("team_color") == world.squad.uniform_color
		and enemy_shield.get_shader_parameter("team_color") == world.enemy.uniform_color,
		"shields use their side's uniform color")
	check(world.banners.size() == 2, "both squads have a banner")
	check(world.squad.soldiers.all(func(s): return s.get_children().filter(func(n): return n is MeshInstance3D and n.mesh is QuadMesh).is_empty()), "no individual HP bars")
	await screenshot("01_two_squads")
	await test_duel()
	if "--sword-battle" in OS.get_cmdline_user_args():
		for soldier in world.squad.soldiers + world.enemy.soldiers:
			soldier.has_spear = false
			soldier.spear.hide()
			soldier.take_sword()
	click_enemy()
	await wait(.35)
	check(world.squad.attack_target == world.enemy, "right click on opponent issues attack order")
	check(world.squad.soldiers.all(func(s): return s.attack_order and not s.charge and s.shield_raised), "walking attack raises shields")
	await wait(1.5)
	check(world.squad.soldiers.any(func(s): return s.animation_name.begins_with("advance_")), "shielded advance animation plays")
	await screenshot("02_advance")
	click_enemy(true, true)
	await wait(1.0)
	check(world.squad.soldiers.all(func(s): return s.charge), "double right click on enemy banner changes to charge")
	check(world.squad.soldiers.any(func(s): return s.motion_speed > 2.5 and ((s.weapon_ready and s.shield_raised and s.animation_name.begins_with("charge_")) or (not s.weapon_ready and not s.shield_raised and s.animation_name.begins_with("run_")))), "charge uses carry at distance and combat-ready pose near contact")
	await screenshot("03_charge")
	var elapsed := 0.0
	while elapsed < 160.0 and world.squad.alive_count() > 0 and world.enemy.alive_count() > 0:
		await wait(2.0)
		elapsed += 2.0
		if elapsed > 8:
			lowest_fps = mini(lowest_fps, Engine.get_frames_per_second())
		if int(elapsed) % 10 == 0:
			print("BATTLE ",elapsed," alive=",world.squad.alive_count(),"/",world.enemy.alive_count()," hits=",world.effects.hits," blocks=",world.effects.blocks," fps=",Engine.get_frames_per_second())
		if elapsed == 10.0:
			await screenshot("04_melee_overview")
			var pair = world.squad.living().filter(func(s): return is_instance_valid(s.combat_target) and s.global_position.distance_to(s.combat_target.global_position)<2.5)
			if not pair.is_empty():
				world.focus = pair[0].global_position + Vector3.UP * .65
				world.camera_distance = 9.0
				world.update_camera()
		if elapsed == 12.0:
			await screenshot("05_melee_close")
		if elapsed == 16.0:
			world.focus = (world.squad.center()+world.enemy.center())*.5
			world.camera_distance = 35.0
			world.update_camera()
	check(world.effects.hits > 20 and world.effects.blocks > 0, "live melee resolves damage and frontal shield blocks")
	check(world.effects.footsteps > 20 and world.effects.sounds_played > 20, "movement and combat trigger spatial audio")
	check(world.squad.alive_count() == 0 or world.enemy.alive_count() == 0, "battle reaches a winner without stranded attackers")
	check(world.squad.soldiers.any(func(s): return not s.alive) and world.enemy.soldiers.any(func(s): return not s.alive), "casualties on both sides")
	for group in [world.squad, world.enemy]:
		check(group.soldiers.all(func(s): return s.hp >= 0.0 and s.hp <= s.max_hp), "HP stays in valid range")
		check(group.soldiers.all(func(s): return s.alive or (not s.agent.avoidance_enabled and not s.busy and s.collision_layer == 0)), "dead soldiers leave combat and navigation")
	var winner = world.squad if world.squad.alive_count() > 0 else world.enemy
	if winner.alive_count() > 0:
		await wait(.25)
		check(winner.living().any(func(s): return s.active_action == "celebrate"), "victors raise their weapons")
		await screenshot("06_victory")
		await wait(3.0)
		check(winner.living().all(func(s): return not s.busy), "victory celebration finishes")
		winner.command(2,Vector3(32,0,24))
		check(winner.living().all(func(s): return s.target.x < 59 and s.target.z < 44 and not s.attack_order), "survivors can leave battle and reform")
	await wait(2)
	await screenshot("06_result")
	var report := {"failures":failures,"survivors":[world.squad.alive_count(),world.enemy.alive_count()],"hits":world.effects.hits,"blocks":world.effects.blocks,"min_fps":lowest_fps,"seconds":elapsed}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("COMBAT_QA ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func test_duel() -> void:
	var sandbox := DuelRoot.new()
	world.add_child(sandbox)
	var a := CharacterBody3D.new()
	a.set_script(preload("res://scripts/soldier.gd"))
	a.position = Vector3(42,0,30)
	a.index = 121
	sandbox.add_child(a)
	var b := CharacterBody3D.new()
	b.set_script(preload("res://scripts/soldier.gd"))
	b.position = Vector3(42,0,28.15)
	b.rotation.y = PI
	b.team = 1
	b.index = 122
	sandbox.add_child(b)
	a.set_physics_process(false)
	b.set_physics_process(false)
	b.team = 0
	var original: float = b.hp
	b.receive_hit(20,a)
	check(b.hp == original,"friendly melee cannot damage allies")
	b.team = 1
	a.combat_target = b
	a.begin_strike()
	a.events.process_mode = Node.PROCESS_MODE_DISABLED
	var strike_contacts: Array = a.SPEAR_COMBAT.contacts(a.active_action)
	var first_contact: float = strike_contacts[0].time
	var first_length: float = a.events.current_animation_length
	a.events.advance(first_contact - .02)
	await get_tree().process_frame
	check(b.hp == original,"windup does not deal early damage")
	a.events.advance(.04)
	await get_tree().process_frame
	await get_tree().process_frame
	check(b.hp < original,"animation contact event deals individual damage")
	var after_hit: float = b.hp
	a.resolve_spear_contact(0)
	a.resolve_strike()
	check(b.hp == after_hit,"strike event cannot deal damage twice")
	a.events.advance(first_length - a.events.current_animation_position + .02)
	await get_tree().process_frame
	after_hit = b.hp
	a.events.process_mode = Node.PROCESS_MODE_INHERIT
	a.play_clip("combat_spear")
	a.begin_strike()
	var second_length: float = a.events.current_animation_length
	b.position.z -= 5
	await wait(second_length + .05)
	check(b.hp == after_hit,"out-of-range target is not hit")
	a.play_clip("idle_spear")
	b.position = Vector3(42,0,17)
	a.order_throw(b.position,0)
	a.set_physics_process(true)
	await wait(4.5)
	check(not a.has_spear and a.sword_drawn,"throw finishes with sword in hand")
	check(b.hp < after_hit,"ballistic spear can damage an opponent")
	a.set_physics_process(false)
	var c := CharacterBody3D.new()
	c.set_script(preload("res://scripts/soldier.gd"))
	c.position = a.position + Vector3(0,0,-1.0)
	c.team = 1
	c.index = 123
	sandbox.add_child(c)
	c.set_physics_process(false)
	a.combat_target = c
	a.play_clip("combat_sword")
	a.begin_strike()
	await wait(1.4)
	check(c.hp < c.max_hp,"drawn sword deals damage using sword animation")
	c.guarding = true
	c.rotation.y = PI
	var block_count: int = world.effects.blocks
	for i in 20:
		c.receive_hit(.5,a)
	check(world.effects.blocks > block_count,"front-facing shield blocks attacks")
	c.rotation.y = 0.0
	block_count = world.effects.blocks
	for i in 8:
		c.receive_hit(.5,a)
	check(world.effects.blocks == block_count,"shield cannot block attacks from behind")
	var d := CharacterBody3D.new()
	d.set_script(preload("res://scripts/soldier.gd"))
	d.position = (a.position+c.position)*.5
	d.index = 124
	sandbox.add_child(d)
	d.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var protected_hp: float = c.hp
	a.play_clip("combat_sword")
	a.begin_strike()
	await wait(1.4)
	check(c.hp == protected_hp,"melee cannot strike through a warrior in front")
	d.queue_free()
	await get_tree().physics_frame
	a.active_action = ""
	a.busy = false
	a.animation_clock = 0
	a.events.stop()
	a.rotation.y = 0
	a.attack_cooldown = 10
	c.position = a.position + Vector3(0,0,-.60)
	a.order_attack(c,false)
	a.reaction = 0
	a.set_physics_process(true)
	await wait(.30)
	check(absf(a.rotation.y) < .15 and a.velocity.z > .05 and a.animation_name == "backstep_sword", "close fighter backpedals while facing opponent")
	a.set_physics_process(false)
	a.stop()
	var victim_spear: bool = b.has_spear
	b.order_throw(a.position,0)
	b.active_action = "throw_spear"
	b.events.play("throw_spear")
	b.die()
	await wait(1.7)
	check(b.has_spear == victim_spear and not b.alive and not b.busy,"death cancels pending release event")
	check(world.get_children().filter(func(n): return n.get_script() == preload("res://scripts/projectile.gd")).is_empty(),"spent projectiles fade and are removed")
	if "--duel-preview" in OS.get_cmdline_user_args():
		world.focus = b.global_position + Vector3.UP * .5
		world.camera_distance = 5
		world.update_camera()
		await screenshot("death_detail")
		world.focus = Vector3.ZERO
		world.camera_distance = 58.0
		world.update_camera()
	sandbox.queue_free()
