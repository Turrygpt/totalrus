extends SceneTree

var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failures.append(message)

func run() -> void:
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world = current_scene
	for group in world.squads:
		group.ai_enabled = false
		for s in group.soldiers:
			s.set_physics_process(false)
			s.agent.avoidance_enabled = false
	var a = world.squad.soldiers[0]
	var b = world.enemy.soldiers[0]
	a.position = Vector3(40,0,30)
	b.position = Vector3(40,0,10)
	a.rotation.y = 0
	a.reaction = 0
	b.attack_order = false
	b.velocity = Vector3.ZERO
	a.order_attack(b,true)
	a.update_combat()
	check(not a.weapon_ready and not a.battle_cry_done,"distant charge carries weapon normally")
	var run_speed: float = a.attack_run_speed()
	var closing_speed: float = run_speed * a.speed_variation
	b.position.z = a.position.z - a.weapon_reach() - closing_speed * (a.ready_lead - .05)
	a.update_combat()
	check(a.weapon_ready and a.shield_raised and is_equal_approx(a.speed_limit,run_speed),"weapon readied around 2.5 seconds before contact")
	b.position.z = a.position.z - a.weapon_reach() - closing_speed * (a.cry_lead - .05)
	a.motion_speed = closing_speed
	a.update_combat()
	var cries: int = world.effects.battle_cries
	check(a.battle_cry_done and cries > 0,"battle cry before contact")
	for i in 10:
		a.order_attack(b,true)
		a.update_combat()
	check(world.effects.battle_cries == cries,"target reassignment does not repeat the cry")
	a.stop()
	a.has_spear = false
	a.spear.hide()
	a.take_sword()
	a.order_attack(b,true)
	a.update_combat()
	check(a.weapon_ready and a.animation_map.has("charge_sword"),"swordsmen also ready weapons on approach")
	var head: int = a.skeleton.find_bone("mixamorig:Head")
	for i in a.skeleton.get_bone_count():
		if String(a.skeleton.get_bone_name(i)).ends_with("Head"): head = i
	check(head >= 0,"head bone imported")
	for clip in ["walk_spear","walk_sword"]:
		a.player.play(a.animation_map[clip],0)
		a.player.advance(0)
		var start: Quaternion
		var swing := 0.0
		for i in 31:
			a.player.seek(a.player.current_animation_length*i/30.0,true)
			a.skeleton.force_update_all_bone_transforms()
			var q: Quaternion = a.skeleton.get_bone_global_pose(head).basis.get_rotation_quaternion()
			if i == 0: start = q
			swing = maxf(swing,rad_to_deg(start.angle_to(q)))
		check(swing < 2.0,"steady head in %s: %.2f degrees" % [clip,swing])
	print("CHARGE_QA ",JSON.stringify({"failures":failures}))
	quit(0 if failures.is_empty() else 1)
