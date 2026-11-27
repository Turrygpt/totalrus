extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition: failures += 1

func inflict_losses(group: Node3D, fraction: float) -> void:
	for i in roundi(group.unit_count * fraction):
		group.soldiers[i].die()
	group.combat_timer = 0.0

func morale_seconds(group: Node3D, seconds: float) -> void:
	for step in roundi(seconds * 10.0): group.update_morale(.1)

func run() -> void:
	seed(3842)
	set_meta(&"battle_size", 4)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(.4).timeout
	var world = current_scene
	world.set_battle_paused(false)
	for group in world.squads:
		group.ai_enabled = false
		group.set_physics_process(false)
	var infantry: Node3D = world.squad
	infantry.stamina = 70.0
	for soldier in infantry.members: soldier.motion_speed = 1.8
	infantry.update_stamina(2.0)
	check(is_equal_approx(infantry.stamina, 70.88), "walking restores .44 stamina per second")
	for soldier in infantry.members: soldier.motion_speed = 0.0
	infantry.update_stamina(2.0)
	check(is_equal_approx(infantry.stamina, 71.8), "stationary stamina recovery remains .46 per second")
	infantry.stamina = 100.0
	var commander: Node3D = world.squads.filter(func(g): return g.team == 0 and g.unit_kind == "princely")[0]
	var victim: CharacterBody3D = infantry.soldiers.back()
	var attacker: CharacterBody3D = world.enemy.soldiers[0]
	var attacker_start := attacker.position
	var facing := -victim.global_basis.z
	attacker.position = victim.position + facing * 1.5
	victim.receive_hit(10.0, attacker)
	check(infantry.incoming_pressure > 0.0 and is_zero_approx(infantry.flank_pressure), "frontal hit adds pressure without a flank bonus")
	attacker.position = victim.position + facing.cross(Vector3.UP) * 1.5
	victim.receive_hit(10.0, attacker)
	var flank_pressure: float = infantry.flank_pressure
	attacker.position = victim.position - facing * 1.5
	victim.receive_hit(10.0, attacker)
	check(flank_pressure > 0.0 and infantry.flank_pressure - flank_pressure > flank_pressure, "rear hits add more pressure than flank hits")
	attacker.position = attacker_start

	inflict_losses(infantry, .45)
	infantry.flank_pressure = 26.0
	var prince_center: Vector3 = commander.cached_center
	commander.cached_center = infantry.center()
	var supported_morale: float = infantry.morale_target()
	commander.cached_center = infantry.center() + Vector3.RIGHT * 25.0
	check(is_equal_approx(supported_morale - infantry.morale_target(), 20.0), "nearby commander supports a damaged squad with doubled morale")
	morale_seconds(infantry, 2.0)
	check(infantry.morale >= 50.0 and not infantry.wavering, "shock takes time to affect even a heavily damaged squad")
	var banner: Control = world.banners.filter(func(b): return b.squad == infantry)[0]
	banner.refresh_stats()
	check(banner.world_standard.morale_signal == 0, "morale above fifty has no visual feedback")
	morale_seconds(infantry, 11.0)
	check(infantry.wavering and not infantry.routed and infantry.combat_ready(), "damaged and flanked infantry wavers but keeps fighting")
	infantry.command(1, infantry.center())
	check(not infantry.routed and infantry.members.all(func(s): return not s.fleeing), "wavering troops still obey commands")
	infantry.flank_pressure = 0.0
	infantry.casualty_shock = 0.0
	morale_seconds(infantry, 10.0)
	check(not infantry.wavering and not infantry.routed and infantry.morale >= 50.0, "relieved pressure allows wavering troops to rally")
	commander.cached_center = prince_center

	var militia: Node3D = world.make_unit(0, Vector3(75, 0, 15), "Ополчение", "militia", 24)
	militia.ai_enabled = false
	militia.set_physics_process(false)
	world.select_squad(militia)
	check(militia.morale == 100.0 and militia.combat_ready(), "fresh militia starts at the morale cap and accepts selection")
	var militia_start: Vector3 = militia.center()
	for i in 16:
		var defender: CharacterBody3D = militia.soldiers[i]
		attacker.position = defender.position - defender.global_basis.z * 1.5
		defender.receive_hit(defender.max_hp if i < 5 else defender.max_hp * .43, attacker)
	world.combat_index.rebuild()
	morale_seconds(militia, 15.0)
	check(not militia.routed and militia.alive_count() == 19, "light losses and frontal pressure alone do not cause flight")
	inflict_losses(militia, .58)
	morale_seconds(militia, 16.0)
	check(militia.routed and militia.alive_count() == 10 and is_zero_approx(militia.flank_pressure), "sustained frontal pressure can break militia after heavy losses")
	check(militia not in world.selected_groups() and militia.pending_order.is_empty(), "rout locks player orders and clears the queue")
	morale_seconds(militia, 4.5)
	check(militia.routed and not militia.recovering_from_rout, "pursuit delays rally")
	attacker.position = attacker_start
	world.combat_index.rebuild()
	militia.set_physics_process(true)
	world.set_speed(3)
	var rally_deadline := Time.get_ticks_msec() + 15000
	while militia.routed and Time.get_ticks_msec() < rally_deadline:
		await create_timer(.15,true,false,true).timeout
	world.set_speed(1)
	militia.set_physics_process(false)
	check(militia.center().z > militia_start.z + 8.0 and militia in world.selected_groups(), "militia moves to the rear and returns to player control")
	var nearest_direction := Vector3.ZERO
	var nearest_distance := INF
	for group in world.squads:
		if group.team == militia.team or not group.combat_ready():
			continue
		var offset: Vector3 = group.center() - militia.center()
		offset.y = 0.0
		if offset.length_squared() < nearest_distance:
			nearest_distance = offset.length_squared()
			nearest_direction = offset.normalized()
	var militia_front := Vector3.FORWARD.rotated(Vector3.UP, militia.order_heading)
	check(militia.reforming and militia_front.dot(nearest_direction) > .999 and militia.members.all(func(s): return is_equal_approx(s.final_heading, militia.order_heading)), "rallied militia reforms facing the nearest active enemy")
	var march_target: Vector3 = militia.center() + Vector3.RIGHT * 12.0
	world.command_selected(2, march_target)
	check(militia.combat_ready() and militia.members.all(func(s): return not s.fleeing and s.target.x > militia.center().x), "normal player command moves the rallied militia")

	var routed_archers: Node3D = world.enemy_archers
	var survivor: CharacterBody3D = routed_archers.soldiers.back()
	var start_z := survivor.position.z
	routed_archers.command(4, infantry.center())
	survivor.start_shot()
	check(survivor.active_action == "bow_draw", "archer starts preparing a shot before the rout")
	infantry.command_attack(routed_archers, true)
	inflict_losses(routed_archers, .7)
	routed_archers.flank_pressure = 20.0
	routed_archers.record_morale_hit(.25,false)
	morale_seconds(routed_archers, 10.0)
	check(routed_archers.wavering and not routed_archers.routed, "severe shock first produces wavering, not immediate flight")
	morale_seconds(routed_archers, 8.0)
	await create_timer(.7).timeout
	check(routed_archers.routed and routed_archers.alive_count() == 9, "archers rout with survivors")
	check(not survivor.disarmed and survivor.bow.visible, "retreat keeps weapons")
	check(survivor.fleeing and survivor.position.z < start_z and not survivor.attack_order, "routed archers run toward their edge")
	check(survivor.shots_fired == 0 and not survivor.active_action.begins_with("bow_"), "rout cancels the prepared shot")
	infantry.assign_combat_targets()
	check(infantry.attack_target == routed_archers, "attackers can pursue a routed target")
	check(survivor not in world.combat_index.nearby(survivor.position, 0, 1.0), "routed warriors disappear from combat queries")
	var retreat_goal: Vector3 = survivor.target
	routed_archers.stop()
	routed_archers.command(2, Vector3.ZERO)
	routed_archers.command_attack(infantry, true)
	check(survivor.target == retreat_goal and not survivor.attack_order, "new orders cannot interrupt the rout")

	var steady_enemy: Node3D = world.enemy
	for group in world.squads:
		if group.team == 1 and group != steady_enemy and not group.routed:
			inflict_losses(group, .9)
			group.flank_pressure = 20.0
			group.begin_rout()
	await create_timer(.7).timeout
	check(world.team_alive(1) > steady_enemy.alive_count() and world.team_in_battle(1) == steady_enemy.alive_count(), "routing preserves survivor counts")
	check(world.result_text.is_empty() and not infantry.victory_started, "a steady squad keeps the battle going while routed units recover")
	var routed_banner: Control = world.banners.filter(func(b): return b.squad == routed_archers)[0]
	routed_banner.refresh_stats()
	check(routed_banner.world_standard.morale_signal == 2, "routed squad signals retreat on its standard")
	routed_archers.cached_center = Vector3(-90, 0, -70)
	routed_archers.rout_safe_time = 0.0
	routed_archers.recent_hit_time = 0.0
	routed_archers.morale = 27.0
	routed_archers.flank_pressure = 0.0
	routed_archers.casualty_shock = 0.0
	morale_seconds(routed_archers, 5.0)
	check(routed_archers.routed and routed_archers.recovering_from_rout and routed_archers.morale > 27.0, "routed morale builds gradually once clear of the enemy")
	morale_seconds(routed_archers, 9.0)
	check(routed_archers.combat_ready() and not survivor.fleeing, "rallied soldiers rejoin the battle")
	routed_archers.command(2, Vector3(-30, 0, -15))
	check(survivor.target != retreat_goal and not survivor.fleeing, "rallied troops obey a new movement order")
	routed_archers.morale = 19.0
	routed_archers.flank_pressure = 20.0
	routed_archers.record_morale_hit(.25,false)
	morale_seconds(routed_archers, 3.0)
	check(not routed_archers.routed, "a rallied squad does not repeatedly rout from its existing losses")
	inflict_losses(routed_archers,.84)
	morale_seconds(routed_archers,4.0)
	check(routed_archers.routed and not routed_archers.surrendered, "fresh losses under pressure can force another retreat")
	routed_archers.record_morale_hit(.25, false)
	morale_seconds(routed_archers, 12.2)
	check(routed_archers.surrendered, "sustained pursuit and very low morale cause surrender")
	check(survivor.disarmed and survivor.fleeing and not survivor.bow.visible, "surrendered archers drop weapons and flee")

	steady_enemy.wavering = true
	world.ui_timer = 0.0
	await process_frame
	await process_frame
	check(world.result_text == "ПОБЕДА", "a side with only wavering or routed squads loses even with survivors")
	for group in world.squads:
		if group.team == 1 and not group.surrendered:
			group.surrender()
			check(group.members.all(func(s): return s.disarmed and s.fleeing), "surrendered troops leave their posts and drop weapons")
	check(world.team_alive(1) > 0 and world.team_in_battle(1) == 0, "surrender leaves survivors but removes the side from combat")
	var surviving_enemies := 0
	var escaped := 0
	for group in world.squads:
		if group.team != 1: continue
		surviving_enemies += group.survivor_count()
		for soldier in group.members:
			soldier.position.z = -group.field_half_size.y + 1.0
		group.withdraw_surrendered_soldiers()
		escaped += group.survivor_count()
	check(escaped == surviving_enemies and not survivor.visible and survivor.withdrawn, "surrendered soldiers disappear from the field and count as survivors")
	reload_current_scene()
	await create_timer(.4).timeout
	check(current_scene.result_text.is_empty() and current_scene.enemy.morale == 100.0 and not current_scene.enemy.routed, "new battle resets morale and result")
	current_scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
