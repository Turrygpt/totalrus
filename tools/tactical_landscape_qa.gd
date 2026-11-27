extends SceneTree
const FIELD = preload("res://scripts/battlefield_bounds.gd")
const BATTLE = preload("res://scenes/battlefield.tscn")
var failures := 0
var returned := {}

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures += 1

func unit(id: String, kind := "infantry") -> Dictionary:
	return {"id":id,"kind":kind,"count":8,"title":"Одинаковое название","xp":0}

func run() -> void:
	var heights := PackedFloat32Array()
	var forests := PackedFloat32Array()
	for z in 17:
		for x in 17:
			heights.append(8+x*.9+z*.35)
			forests.append(.8)
	var battle = BATTLE.instantiate()
	battle.campaign_request={"attackers":[unit("our_general","princely"),unit("our_a"),unit("our_b")],"defenders":[unit("their_general","princely"),unit("their_a"),unit("their_b")],"commander_names":["Наш воевода","Вражеский воевода"],"landscape":{"seed":91,"season":3,"heights":heights,"forest":forests,"water_side":0,"city":false}}
	root.add_child(battle)
	for i in 4: await process_frame
	check(paused,"battle begins paused")
	check(battle.field_half_size.x>=280 and battle.field_half_size.y>=210,"large campaign battlefield")
	check(battle.terrain.snow==1.0,"winter follows campaign season")
	check(absf(battle.terrain.height_at(Vector2(-130,30))-battle.terrain.height_at(Vector2(130,30)))>3,"strategic elevation changes tactical ground")
	check(battle.terrain.obstacles.size()>0,"homesteads have movement obstacles")
	var arrays: Array=battle.terrain.get_node("Relief").mesh.surface_get_arrays(0)
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	check(normals[normals.size()/2].y>.5,"terrain faces upward")
	var grounded := true
	for group in battle.squads:
		group.ai_enabled=false
		group.stop()
		for soldier in group.soldiers:
			grounded = grounded and absf(soldier.position.y-FIELD.project(soldier.position).y)<.01
	check(grounded,"all infantry and mounted troops spawn on the surface")
	check(battle.fallen_leader_teams.is_empty() and not battle.hud.announcement.visible,"living generals produce no death announcement")
	var group=battle.campaign_groups.our_a
	var second: Node3D = battle.campaign_groups.our_b
	var enemy: Node3D = battle.campaign_groups.their_a
	battle.select_squad(group)
	battle.select_squad(second,true)
	check(battle.selected_groups().size()==2,"Shift selection adds a second squad")
	battle.set_battle_paused(false)
	battle.banner_clicked(MOUSE_BUTTON_RIGHT,false,enemy)
	check(group.attack_target==enemy and second.attack_target==enemy and battle.order_notice.contains("атака"),"RMB assigns both squads the same attack and confirms the order")
	battle.stop_selected()
	var view: Rect2 = root.get_visible_rect()
	battle.select_in_box(view)
	check(battle.selected_groups().size()==3,"selection box selects friendly squads only")
	battle.select_squad(group)
	var before: Vector3=group.center()
	group.command(2,before+Vector3(18,0,0))
	await create_timer(2.0).timeout
	check(group.center().x>before.x+1,"unpaused troops move across the relief")
	grounded=true
	for soldier in group.members:
		grounded = grounded and absf(soldier.position.y-FIELD.project(soldier.position).y)<.06
	check(grounded,"moving troops stay on slopes")
	var arrow=preload("res://scripts/arrow.gd").new()
	battle.add_child(arrow)
	var origin: Vector3=FIELD.project(Vector3(-100,0,0))+Vector3.UP*4
	arrow.launch(origin,origin-Vector3.UP*4)
	var spear=preload("res://scripts/projectile.gd").new()
	battle.add_child(spear)
	spear.launch(Transform3D(Basis.IDENTITY,origin+Vector3(4,0,0)),FIELD.project(origin+Vector3(4,0,0)))
	await create_timer(1.4).timeout
	check(arrow.landed and arrow.global_position.y>0,"arrow lands on raised terrain")
	check(spear.landed and spear.global_position.y>0,"thrown spear lands on raised terrain")
	battle.set_battle_paused(true)
	battle.campaign_leader.die()
	await process_frame
	await process_frame
	check(battle.fallen_leader_teams==[0] and battle.hud.notice_title.text.begins_with("Наш"),"our general death is announced once")
	battle.rival_leader.die()
	for i in 4: await process_frame
	check(battle.fallen_leader_teams.size()==2 and battle.hud.notices.size()==1,"enemy general death is queued without repeated notices")
	battle.hud.notice_until=0
	for i in 3: await process_frame
	check(battle.hud.notice_title.text.begins_with("Вражеский"),"enemy general announcement appears after ours")
	battle.campaign_groups.our_a.soldiers[0].die()
	battle.campaign_groups.their_a.soldiers[0].die()
	for enemy_group in battle.squads:
		if enemy_group.team==1: enemy_group.surrender()
	battle.update_battle_end()
	check(battle.campaign_result.get("outcome")=="win" and is_instance_valid(battle.battle_report) and paused,"last enemy surrender opens victory report and pauses battle")
	check(battle.campaign_result.survivors.our_a==7 and battle.campaign_result.survivors.our_b==8 and battle.campaign_result.survivors.their_a==7,"losses follow IDs despite identical types and names")
	check(battle.campaign_result.leader_lost and battle.campaign_result.rival_leader_lost,"both commander losses reach the campaign result")
	var report_id: int=battle.battle_report.get_instance_id()
	battle.update_battle_end()
	check(battle.battle_report.get_instance_id()==report_id,"result window is not duplicated")
	battle.campaign_battle_finished.connect(func(result): returned=result)
	battle.campaign_action_pressed()
	check(returned==battle.campaign_result,"return action emits the completed result")
	battle.queue_free()
	await process_frame
	await process_frame
	paused=false
	set_meta("battle_size",1)
	battle=BATTLE.instantiate()
	root.add_child(battle)
	for i in 3: await process_frame
	for soldier in battle.enemy.soldiers: soldier.die()
	battle.update_battle_end()
	check(battle.result_text=="ПОБЕДА" and is_instance_valid(battle.battle_report) and paused,"standalone battle also displays results after elimination")
	battle.queue_free()
	await process_frame
	await process_frame
	paused=false
	for enemy_attack in [false,true]:
		battle=BATTLE.instantiate()
		battle.campaign_request={"attackers":[unit("a")],"defenders":[unit("b")],"enemy_attack":enemy_attack}
		root.add_child(battle)
		await process_frame
		check(battle.hud.battle_state.text.contains("15:00"),"countdown starts at fifteen minutes")
		battle.battle_time=battle.BATTLE_TIME_LIMIT-.05
		await process_frame
		check(battle.result_text.is_empty() and battle.battle_time<battle.BATTLE_TIME_LIMIT,"pause holds the countdown")
		battle.set_battle_paused(false)
		await create_timer(.4).timeout
		check(battle.time_expired and paused and battle.campaign_result.get("outcome")==("win" if enemy_attack else "loss"),"time expiry awards victory to the defender")
		battle.queue_free()
		await process_frame
		await process_frame
		paused=false
	print("TACTICAL_LANDSCAPE_QA failures=",failures)
	quit(failures)
