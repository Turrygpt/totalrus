extends SceneTree

# Run with --headless --fixed-fps 60 --script res://tools/weapon_balance_qa.gd.
# Repeat with -- --walk and/or --swap to change the approach and starting side.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var spear_team := 1 if "--swap" in args else 0
	var running := "--walk" not in args
	seed(73452)
	if change_scene_to_file("res://tools/front_qa_world.tscn") != OK:
		quit(1)
		return
	await create_timer(1).timeout
	var world = current_scene
	if not is_instance_valid(world) or not world.has_method("team_alive"):
		push_error("Could not load the weapon balance test battlefield")
		quit(1)
		return
	for group in world.squads:
		for soldier in group.soldiers:
			if group.team != spear_team:
				soldier.has_spear = false
				soldier.spear.hide()
				soldier.take_sword()
	world.squad.command_attack(world.enemy, running)
	world.enemy.command_attack(world.squad, running)
	var first_damage := [-1, -1]
	for frame in 60 * 45:
		await physics_frame
		for group in world.squads:
			if first_damage[group.team] >= 0: continue
			for soldier in group.soldiers:
				if soldier.hp < soldier.max_hp:
					first_damage[group.team] = frame
					break
		if not world.squad.combat_ready() or not world.enemy.combat_ready(): break
	var sword_team := 1 - spear_team
	var sword_count: int = world.team_alive(sword_team)
	var spear_count: int = world.team_alive(spear_team)
	var spear_hit_first: bool = first_damage[sword_team] >= 0 and first_damage[sword_team] < first_damage[spear_team]
	var spears_won: bool = world.team_in_battle(spear_team) > 0 and world.team_in_battle(sword_team) == 0
	var near_target_score := absi(sword_count - 20) <= 8 and absi(spear_count - 40) <= 8
	print("WEAPON_BALANCE_QA ", JSON.stringify({
		"swords": sword_count, "spears": spear_count, "spear_first_hit": spear_hit_first,
		"spears_won": spears_won, "near_target_score": near_target_score,
		"spear_team": spear_team, "running": running,
	}))
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if spear_hit_first and spears_won and near_target_score else 1)
