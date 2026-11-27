extends SceneTree
var failures := 0
var visual := false

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures += 1

func capture(path: String) -> void:
	if not visual: return
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func enter_battle(world: Node3D) -> Node3D:
	for roster in [world.encounter.attackers,world.encounter.defenders]:
		for unit in roster: unit.count=8
	world.battle_menu.hide()
	var cover := CanvasLayer.new()
	root.add_child(cover)
	await world.open_tactical_scene(load("res://scenes/battlefield.tscn"),cover)
	for i in 3: await process_frame
	return current_scene

func run() -> void:
	visual="--visual" in OS.get_cmdline_user_args()
	root.size=Vector2i(1920,1080)
	var world=load("res://campaign_map/main.tscn").instantiate()
	world.save_file="res://build/campaign_battle_qa.save"
	root.add_child(world)
	current_scene=world
	await process_frame
	check(world.save_campaign(),"manual save created before battle")
	check(world.management.hud.turn_notice.visible and world.management.hud.turn_notice_date.text.contains("Ход 1"),"campaign displays a start-of-turn notice")
	await capture("res://build/turn_start.png")
	while world.campaign_season() != world.WINTER:
		world.turn += 1
	world.campaign.cities.novgorod.order=-75
	world.campaign.cities.novgorod.revolt_turns=1
	world.campaign.rebellions.novgorod={"roster":world.campaign.rebel_roster("novgorod")}
	world.refresh_ui()
	check(world.rebel_pieces.has("novgorod") and world.rebel_pieces.novgorod.pin.visible,"rebel band appears as a selectable map force")
	world.queue_rebellion("novgorod")
	await process_frame
	check(world.encounter.landscape.heights.size()==289 and world.encounter.landscape.forest.size()==289 and world.encounter.landscape.season==3,"encounter carries local terrain, forest and winter")
	check(world.encounter.banner_factions[1]==world.Geo.REBELS,"rebel encounter has its own faction identity")
	var battle=await enter_battle(world)
	check(battle!=world and world.get_parent() is SubViewport and world.get_parent().process_mode==Node.PROCESS_MODE_DISABLED,"campaign is parked while the battlefield is active")
	check(battle.terrain.snow==1 and battle.siege_gates.is_empty(),"rebel field battle uses winter without city walls")
	if visual:
		battle.camera_distance=235
		battle.camera_zoom_target=235
		battle.camera_pitch=deg_to_rad(42)
		battle.update_camera()
		await capture("res://build/tactical_winter.png")
		battle.camera_distance=48
		battle.camera_zoom_target=48
		battle.camera_pitch=deg_to_rad(28)
		var hut: Vector3=battle.terrain.obstacles[0]
		battle.focus=battle.terrain.ground_point(Vector2(hut.x,hut.y))
		battle.update_camera()
		await capture("res://build/tactical_homestead.png")
	var initial_order: int=world.campaign.cities.novgorod.order
	for group in battle.squads:
		if group.team==1: group.surrender()
	battle.update_battle_end()
	battle.campaign_action_pressed()
	for i in 6: await process_frame
	check(current_scene==world and world.get_parent()==root and not paused,"victory returns to the same campaign scene")
	check(not world.campaign.rebellions.has("novgorod") and not world.rebel_pieces.has("novgorod") and world.campaign.cities.novgorod.order==initial_order+25,"defeated rebels disappear and restore city order")
	check(world.campaign.cities.novgorod.revolt_turns==0,"victory above -70 cancels the countdown")
	world.battle_menu.hide()
	world.battle_summary={}
	world.campaign.cities.russa.buildings.wall=1
	check(world.queue_battle("russa",-1,true),"city encounter can be prepared")
	await process_frame
	check(world.encounter.fortified,"town walls still count in the campaign")
	await capture("res://build/siege_council.png")
	battle=await enter_battle(world)
	check(battle.siege_gates.is_empty(),"city battles have no tactical fortifications")
	var wall_z: float=battle.siege_line
	var allowed: Vector3=battle.constrain_siege_crossing(Vector3(0,0,wall_z+2),Vector3(0,0,wall_z-2))
	check(allowed.z<wall_z,"troops can cross the old wall line anywhere")
	await capture("res://build/tactical_fortified.png")
	battle.finish_campaign_battle("retreat")
	await capture("res://build/tactical_retreat_report.png")
	battle.campaign_action_pressed()
	for i in 6: await process_frame
	check(current_scene==world and not world.campaign_defeated,"retreat also returns to campaign")
	check(world.load_campaign(world.CampaignSave.Slot.BATTLE_END) and world.encounter.is_empty() and world.battle_summary.title=="Отступление","battle-end autosave restores the tactical result")
	check(world.load_campaign(world.CampaignSave.Slot.BATTLE_START) and world.encounter.city=="russa" and world.battle_menu.visible,"battle-start autosave restores the encounter")
	world.resolve_automatically()
	var outcome: String = world.battle_summary.title
	check(world.load_campaign(world.CampaignSave.Slot.BATTLE_END) and world.battle_summary.title==outcome,"auto-resolve replaces the battle-end autosave")
	world.load_campaign(world.CampaignSave.Slot.BATTLE_START)
	var hud = world.management.hud
	hud.menu.show()
	hud.show_load_slots()
	check(not hud.load_buttons[world.CampaignSave.Slot.MANUAL].disabled,"manual slot is available in the load menu")
	hud.load_buttons[world.CampaignSave.Slot.MANUAL].pressed.emit()
	check(world.turn==1 and world.encounter.is_empty() and not world.battle_menu.visible and not hud.menu.visible,"manual save survives battles and can be loaded from the council")
	await campaign_orders(world)
	world.queue_free()
	for i in 3: await process_frame
	print("CAMPAIGN_BATTLE_QA failures=",failures)
	quit(failures)

func campaign_orders(world: Node3D) -> void:
	world.battle_menu.hide()
	world.campaign.factions[0].silver = 500
	world.refresh_ui()
	check(world.city_buttons.novgorod.construction_idle,"idle city with affordable construction has a badge")
	world.request_end_turn()
	check(world.enemy_actor==0 and is_instance_valid(world.construction_warning) and world.construction_warning.visible,"end turn warns before skipping affordable construction")
	world.construction_warning.hide()
	world.campaign.factions[0].silver = 0
	world.refresh_ui()
	check(not world.city_buttons.novgorod.construction_idle,"unaffordable construction does not show a badge")
	world.campaign.factions[0].silver = 500
	var cost: int = world.campaign.hero_cost("novgorod")
	var population: int = world.campaign.province_manpower(0,0)
	world.movement = 18.0
	var hero: int = world.armies.size()
	check(cost==world.campaign.recruit_cost("novgorod","cavalry")+25 and world.recruit_hero("novgorod"),"hire a new commander for a premium over heavy cavalry")
	check(world.commanded_army==hero and world.is_player_army(hero) and world.forces.armies[hero][0].count==30,"hired commander gets a controllable army and personal guard")
	check(world.campaign.factions[0].silver==500-cost and world.campaign.province_manpower(0,0)==population-30,"hiring pays silver and provincial population exactly once")
	world.select_army(0)
	check(is_equal_approx(world.movement,18.0),"each commander retains a separate movement budget")
	world.select_army(hero)
	check(world.save_campaign(),"manual save includes the recruited commander")
	world.select_army(0)
	world.load_campaign()
	check(world.commanded_army==hero and world.armies.size()==hero+1 and world.other_marches[0].movement==18.0,"hired commander and both movement budgets survive save and load")
	var hero_origin: Vector2 = world.army_positions[hero]
	var prince_origin: Vector2 = world.army_positions[0]
	world.ensure_navigation()
	for i in 8:
		var point := hero_origin+Vector2.from_angle(i*TAU/8.0)*12.0
		if world.navigation.land_segment(hero_origin,point):
			world.order_to_point(point)
			check(world.travel_goal==0.0 and world.march_preview,"first order previews the march")
			world.order_to_point(point)
			break
	for i in 20:
		if world.traveled>=world.travel_goal: break
		world._process(.1)
	check(world.army_positions[hero].distance_to(hero_origin)>5.0 and world.army_positions[0]==prince_origin,"marching the recruited commander does not move the prince")
	world.set_player_camp("novgorod")
	world.start_enemy_attack(1,hero)
	var friendly_garrison: bool = world.encounter.get("support",[]).any(func(source):
		return source.get("city","")=="novgorod" and source.team==0)
	check(friendly_garrison and world.encounter.attackers.size()>world.forces.armies[hero].size(),"attacked commander receives nearby garrison reinforcement")
	world.withdraw_encounter()
	check(world.encounter.is_empty() and world.retreat_turns.get(hero)==world.turn and world.forces.armies[hero].size()==1,"retreat returns reinforcement to the garrison")
	world.start_enemy_attack(1,hero)
	check(not world.encounter.retreat_allowed,"second retreat by the same commander is disabled")
	world.withdraw_encounter()
	check(not world.encounter.is_empty(),"second retreat is rejected by campaign logic")
	world.turn += 1
	world.set_encounter_identity()
	check(world.encounter.retreat_allowed,"retreat becomes available in the next turn")
	world.encounter = {}
	world.battle_menu.hide()
	world.battle_summary = {}
	check(world.queue_battle("russa",-1,true),"new commander can attack a settlement")
	world.maintain_siege()
	check(world.campaign.sieges.russa.army==hero and world.siege_turns_remaining("russa")==5,"besieging army and surrender countdown recorded")
	check(world.city_buttons.russa.info.contains("Осада"),"strategic city badge shows the siege")
	world.focus_at(world.Geo.position_of("russa"))
	await capture("res://build/siege_map.png")
	world.campaign.sieges.russa.turns = 4
	world.finish_enemy_turn()
	check(world.pending_capture=="russa" and not world.campaign.sieges.has("russa"),"city surrenders at the end of the announced siege")
	var saved_turn: int = world.turn
	world.settle_capture("occupy")
	check(world.management.hud.turn_notice_date.text.contains("Ход %d" % world.turn),"turn notice appears when the player can act after surrender")
	check(world.load_campaign(world.CampaignSave.Slot.END_TURN) and world.turn==saved_turn and world.pending_capture=="russa","turn-end autosave restores the new turn and pending capture")
