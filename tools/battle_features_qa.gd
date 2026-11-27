extends SceneTree
var failures: Array[String] = []
var world: Node3D
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failures.append(message)
func wait(seconds: float) -> void: await create_timer(seconds,true,false,true).timeout
func run() -> void:
	set_meta(&"battle_size", 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await wait(1)
	world = current_scene
	check(paused and is_zero_approx(world.battle_time),"battle starts paused at zero battle time")
	world.set_battle_paused(false)
	for g in world.squads: g.ai_enabled = false; g.stop()
	check(world.squads.size() == 10 and world.team_alive(0) == 190 and world.team_alive(1) == 190,"ten squads / 380 fighters")
	check(world.squads.all(func(g): return g.formation_density == 2) and world.density_button.selected == 2,
		"battle starts in loose formation with the matching control selected")
	for team in 2:
		var kinds: Array = world.squads.filter(func(g): return g.team == team).map(func(g): return g.unit_kind)
		kinds.sort()
		check(kinds == ["archer", "cavalry", "infantry", "khazar", "varangian"], "all five unit types on side %d" % team)
	var heraldry := {}
	for banner in world.banners:
		var fabric: ShaderMaterial = banner.world_standard.fabric_material
		var texture: Texture2D = fabric.get_shader_parameter("heraldry")
		heraldry[banner.squad.unit_kind] = texture.resource_path
		check(fabric.get_shader_parameter("cloth_tint") == banner.squad.uniform_color,
			"%s uses its leader's cloth color" % banner.squad.display_name)
	var textures := heraldry.values()
	check(textures.size() == 5 and textures.all(func(path):
		return path.begins_with("res://assets/banners/") and textures.count(path) == 1
	), "each unit type has a distinct emblem")
	var a = world.squad.soldiers[0]
	world.squad.command(2,Vector3(-15,0,27))
	await wait(.5)
	world.toggle_pause()
	var before: Vector3 = a.position
	var frame: float = a.player.current_animation_position
	var time: float = world.battle_time
	await wait(.5)
	check(a.position.distance_to(before) < .0001 and is_equal_approx(frame,a.player.current_animation_position) and world.battle_time == time,"pause freezes movement, animation and cape clock")
	world.set_speed(3)
	check(paused and Engine.time_scale == 3,"speed selection preserves pause")
	var layout: Dictionary = world.squad.formation_from_drag(Vector3(-30,0,29),Vector3(-6,0,29))
	world.squad.command_formation(layout,true)
	check(world.squad.formation_columns == layout.columns and layout.columns > 10 and a.position == before,"wide formation can be ordered while paused")
	world.toggle_pause()
	for speed in [1,2,3]:
		world.set_speed(speed)
		var sim: float = world.battle_time
		await wait(.35)
		check(absf((world.battle_time-sim)-.35*speed) < .16,"speed %dx advances simulation at selected rate" % speed)
	world.set_speed(1)
	world.squad.stop()
	var narrow: Dictionary = world.squad.formation_from_drag(Vector3(-26,0,20),Vector3(-22,0,20))
	check(narrow.columns < layout.columns and narrow.slots.size() == 60,"drag compresses frontage and retains all fighters")
	for g in world.squads:
		g.stop(); g.set_physics_process(false)
		for s in g.soldiers:
			s.set_physics_process(false); s.agent.avoidance_enabled = false; s.collision_layer = 0
	var archers = world.friendly_archers
	var foe = world.enemy
	check(archers.ammo_count() == 12, "foot archers have 12 squad arrows")
	check(world.squads.filter(func(g): return g.unit_kind == "khazar").all(func(g): return g.ammo_count() == 14),
		"mounted archers have 14 squad arrows")
	for i in archers.soldiers.size():
		var s = archers.soldiers[i]
		s.position = Vector3(-10+(i%10)*1.5,0,20+floori(i/10.0)*1.4)
		s.rotation.y = 0
		s.manual_move = false
		s.auto_fire = true
		var target = foe.soldiers[i]
		target.position = s.position+Vector3(0,0,-(archers.BOW_RANGE - 4.0))
		s.order_attack(target,false)
		s.final_heading = 0
		s.motion_speed = 0
		s.shoot_cooldown = 0
	archers.refresh_center(); foe.refresh_center()
	archers.attack_target = foe
	for i in range(19, 30):
		archers.soldiers[i].combat_target.position.z -= 8
	archers.update_ranged_position()
	archers.update_volley(2.0)
	check(archers.volley_archers.is_empty() and archers.ammo_count() == 12, "19 of 30 cannot start a volley")
	archers.soldiers[19].combat_target.position.z += 8
	archers.update_volley(.5)
	check(archers.volley_archers.is_empty(), "20 ready archers wait briefly for the rest")
	archers.update_volley(1.2)
	check(archers.soldiers.filter(func(s): return s.active_action == "bow_draw").size() == 20,
		"20 of 30 start drawing in the same tick")
	archers.soldiers[19].cancel_shot()
	for _tick in 116:
		await physics_frame
		archers.update_volley(0.0)
	check(archers.ammo_count() == 12 and archers.volley_count == 0, "interrupted volley fires nothing below 66 percent")
	for i in 30:
		var s = archers.soldiers[i]
		s.cancel_shot()
		s.shoot_cooldown = 0
		if i >= 20: s.combat_target.position.z += 8
	archers.update_ranged_position()
	archers.volley_timer = 0
	archers.update_volley(.02)
	check(archers.soldiers.all(func(s): return s.active_action == "bow_draw"), "all 30 ready archers draw immediately")
	for _tick in 116:
		await physics_frame
		archers.update_volley(0.0)
	check(archers.soldiers.all(func(s): return s.shots_fired == 1) and archers.ammo_count() == 11,
		"all 30 release exactly once and spend one squad arrow")
	archers.arrows_remaining = 1
	for i in 30:
		var s = archers.soldiers[i]
		s.cancel_shot()
		s.shoot_cooldown = 0
		if i >= 20: s.combat_target.position.z -= 8
	archers.update_ranged_position()
	archers.volley_timer = 0
	archers.update_volley(1.6)
	for _tick in 116:
		await physics_frame
		archers.update_volley(0.0)
	check(archers.soldiers.filter(func(s): return s.shots_fired == 2).size() == 20 and archers.ammo_count() == 0
		and not archers.uses_bows() and archers.soldiers.all(func(s): return s.using_knife()),
		"20 of 30 release the last volley together and the whole squad runs out")
	var friend = world.squad.soldiers[1]
	friend.hp = 100; friend.guarding = false; friend.shield_raised = false; friend.attack_order = false
	var enemy = world.enemy.soldiers[59]
	enemy.hp = 100; enemy.guarding = false; enemy.shield_raised = false; enemy.attack_order = false
	friend.receive_hit(25*.5,archers.soldiers[0],true,true)
	enemy.receive_hit(25,archers.soldiers[0],true,false)
	check(is_equal_approx(100-friend.hp,(100-enemy.hp)*.5),"friendly arrow damage is 50 percent")
	var kills: int = archers.soldiers[0].kills
	friend.receive_hit(1000,archers.soldiers[0],true,true)
	check(archers.soldiers[0].kills == kills,"friendly casualties do not award kills")
	world.squad.reform_after_battle()
	check(world.squad.reforming and world.squad.living().all(func(s):return not s.attack_order),"unengaged survivors receive formation slots")
	FileAccess.open("res://build/battle_features_report.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures},"  "))
	print("FEATURE_QA ",failures)
	world.queue_free(); await process_frame; await process_frame
	quit(0 if failures.is_empty() else 1)
