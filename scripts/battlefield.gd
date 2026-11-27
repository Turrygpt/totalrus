extends Node3D
const UI = preload("res://campaign_map/ui_theme.gd")

signal campaign_battle_finished(result: Dictionary)

const SQUAD = preload("res://scripts/squad.gd")
const TroopColors = preload("res://scripts/troop_colors.gd")
const Equipment = preload("res://scripts/unit_equipment.gd")
const CampaignData = preload("res://campaign_map/campaign_state.gd")
const FIELD = preload("res://scripts/battlefield_bounds.gd")
const MapGenerator = preload("res://scripts/tactical_map_generator.gd")
const LandscapeLighting = preload("res://scripts/battle_landscape_lighting.gd")
const TacticalMapLayout = preload("res://scripts/tactical_map_layout.gd")

@export var standalone_layout: TacticalMapLayout
const TacticalHUD = preload("res://scripts/tactical_hud.gd")
const FIELD_SIZE_SCALE := 1.5
const MAX_CAMERA_DISTANCE := 430.0 * FIELD_SIZE_SCALE
const CAMERA_GROUND_CLEARANCE := 1.5
const CAMERA_TERRAIN_EDGE_INSET := 2.0
const FULL_ROSTER_SIZE := 5
const VARANGIAN_BATTLE_ID := 103
const KHAZAR_BATTLE_ID := 104
const MOUNTED_MELEE_BATTLE_ID := 105
const BATTLE_TRACKS := [
	"res://assets/music/open_fifths_01.mp3",
	"res://assets/music/open_fifths_02.mp3",
	"res://assets/music/shield_wall_press_01.mp3",
	"res://assets/music/shield_wall_press_02.mp3",
]
var squad: Node3D
var enemy: Node3D
var friendly_archers: Node3D
var enemy_archers: Node3D
var squads: Array[Node3D] = []
var selected_squad: Node3D
var squads_per_side := FULL_ROSTER_SIZE
var varangian_battle := false
var khazar_battle := false
var mounted_melee_battle := false
var field_half_size := FIELD.DEFAULT_HALF_SIZE
var terrain: Node3D
var battle_report: Control
var density_button: OptionButton
var effects: Node3D
var listener: AudioListener3D
var battle_music: AudioStreamPlayer
var hud: Control
var banners: Array[Control] = []
var result_text := ""
var camera: Camera3D
var focus := Vector3(0, 0, 0)
var camera_follow := false
var camera_yaw := .20
var camera_pitch := deg_to_rad(44.0)
var camera_distance := 58.0
var camera_zoom_target := 58.0
var camera_zooming := false
var camera_rotating := false
var camera_mouse_origin := Vector2.ZERO
var command_mode := 0
var target_ring: MeshInstance3D
var range_ring: MeshInstance3D
var ui_timer := 0.0
var camera_locked := false
var camera_last_moved_ms := -1000
var crowd_renderer: Node3D
var previous_render_scale := 1.0
var previous_msaa := Viewport.MSAA_DISABLED
var battle_weather: LandscapeLighting.WorldWeather
var crowd_movement: Node
var combat_index: Node
var combat_fronts: Node
var auto_battle := false
var reinforcement_behavior := SQUAD.Behavior.RETALIATE
var speed := 1
var battle_time := 0.0
const BATTLE_TIME_LIMIT := 15.0*60.0
const REINFORCEMENT_TIME := 60.0
const EXTRA_REAR_DEPTH := 100.0
const REINFORCEMENT_REAR_MARGIN := 110.0 + EXTRA_REAR_DEPTH
const REINFORCEMENT_ROW_SIZE := 10
const DEPLOYMENT_FRONT := 25.0
const DEPLOYMENT_EDGE_MARGIN := 12.0
const FORMATION_GROUP_GAP := 3.0
var deploying := true
var deployment_line: MeshInstance3D
var deployment_move := {}
var deployment_elapsed := 0.0
var deployment_duration := 0.0
var time_expired := false
var real_tick := 0
var pause_button: Button
var speed_buttons: Array[Button] = []
var overlay: Control
var formation_preview: Node3D
var right_held := false
var left_held := false
var left_start := Vector2.ZERO
var left_additive := false
var selection_box: Panel
var order_marker: MeshInstance3D
var order_notice := ""
var order_expires := 0
var right_double := false
var last_attack_click := -1000
var last_attack_target: Node3D
var last_attack_pointer := Vector2.INF
var right_start := Vector3.ZERO
var right_screen := Vector2.ZERO
var right_pointer := Vector2.ZERO
var right_time := 0.0
var drag_layout := {}
var hover_timer := 0.0
var profiling_skip_banners := false
var campaign_request: Dictionary = {}
var campaign_groups: Dictionary = {}
var campaign_support: Array = []
var support_plan: Array[Dictionary] = []
var support_totals := Vector2i.ZERO
var support_prepared := 0
var support_arrived := 0
var support_leaders := {}
var tactical_markers: CanvasLayer
var banner_scene = preload("res://scripts/squad_banner.gd")
var campaign_action: Button
var campaign_result: Dictionary = {}
var campaign_leader: CharacterBody3D
var fallen_leader_teams: Array[int] = []
var leader_notice := ""
var rival_leader: CharacterBody3D
var siege_gates: Array[float] = []
const TACTICAL_FORTIFICATIONS := false
var siege_line := -8.0

func _enter_tree() -> void:
	get_tree().current_scene = self

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	previous_render_scale = get_viewport().scaling_3d_scale
	previous_msaa = get_viewport().msaa_3d
	Engine.time_scale = 1.0
	get_tree().paused = true
	var scenario := battle_size()
	khazar_battle = scenario == KHAZAR_BATTLE_ID
	mounted_melee_battle = campaign_request.is_empty() and scenario == MOUNTED_MELEE_BATTLE_ID
	varangian_battle = scenario == VARANGIAN_BATTLE_ID or khazar_battle
	squads_per_side = 1 if mounted_melee_battle else (3 if varangian_battle else scenario)
	field_half_size = Vector2(280,210) if squads_per_side>=3 else Vector2(180,140)
	if not campaign_request.is_empty():
		var largest := maxi(campaign_request.attackers.size(),campaign_request.defenders.size())
		field_half_size = Vector2(maxf(280.0,mini(largest,10)*25.0+80.0),maxf(210.0,ceilf(largest/10.0)*45.0+140.0))
		var support: Array = campaign_request.get("support",[])
		campaign_support = support.filter(func(source): return not source.get("opening",false))
	field_half_size.y += 120.0 + EXTRA_REAR_DEPTH
	field_half_size *= FIELD_SIZE_SCALE
	if standalone_layout != null and campaign_request.is_empty():
		field_half_size = standalone_layout.half_size
	real_tick = Time.get_ticks_usec()
	make_environment()
	make_terrain()
	if campaign_request.get("city_battle",false):
		make_settlement_battle()
	make_navigation()
	# A standalone battle keeps the viewport's MSAA and skips the first-frame TAA setup.
	get_viewport().use_taa = not campaign_request.is_empty()
	effects = Node3D.new()
	effects.set_script(preload("res://scripts/battle_effects.gd"))
	effects.name = "BattleEffects"
	effects.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(effects)
	if get_tree().get_meta(&"battle_music_enabled", false):
		setup_battle_music()
		battle_music.play()
	combat_index = Node.new()
	combat_index.set_script(preload("res://scripts/combat_index.gd"))
	add_child(combat_index)
	combat_fronts = preload("res://scripts/battle_fronts.gd").new()
	add_child(combat_fronts)
	crowd_movement = Node.new()
	crowd_movement.set_script(preload("res://scripts/crowd_movement.gd"))
	add_child(crowd_movement)
	crowd_renderer = Node3D.new()
	crowd_renderer.set_script(preload("res://scripts/crowd_renderer.gd"))
	add_child(crowd_renderer)
	if campaign_request.is_empty():
		make_armies()
		campaign_leader = squad.soldiers[0]
		rival_leader = enemy.soldiers[0]
	else:
		make_campaign_armies()
	configure_crowd_detail()
	add_child(make_tactical_commander())
	camera_distance = maxf(192.0,minf(10.0,ceilf(squads.size()/2.0))*26.0)
	camera_pitch = deg_to_rad(49.0)
	focus.z = 6.0
	# Keep the player's deployment clear of the lower command panel.
	focus.z += camera_distance * .15
	if standalone_layout != null and campaign_request.is_empty():
		camera_distance = 485.0
		camera_yaw = -.28
		camera_pitch = deg_to_rad(42.0)
		focus.x = 177.0
	if mounted_melee_battle:
		camera_distance = 46.0
		focus = Vector3.ZERO
	camera_zoom_target = camera_distance
	selected_squad = squad
	combat_index.rebuild()
	camera = Camera3D.new()
	camera.fov = 48
	camera.far = 1800.0 * FIELD_SIZE_SCALE
	add_child(camera)
	camera.current = true
	listener = AudioListener3D.new()
	camera.add_child(listener)
	listener.make_current()
	update_camera()
	target_ring = make_ring_mesh(null, Color("e6d9a3"))
	range_ring = make_ring_mesh(null, Color("c5a86d"))
	target_ring.visible = false
	range_ring.visible = false
	formation_preview = Node3D.new()
	formation_preview.set_script(preload("res://scripts/formation_preview.gd"))
	add_child(formation_preview)
	formation_preview.hide()
	make_deployment_line()
	make_interface()
	set_speed(1)
	set_battle_paused(true)
	hud.refresh(team_in_battle(0), team_in_battle(1))
	crowd_movement.register_actors(squads)
	crowd_renderer.prepare_visuals(squads)
	plan_campaign_support()
	if mounted_melee_battle:
		set_battle_paused(false)
		select_squad(squad)
		squad.set_melee_mode(true)
		squad.command_attack(enemy, false)
		enemy.command_attack(squad, false)
		set_battle_paused(true)
	if "--combat-qa" in OS.get_cmdline_user_args():
		var qa = load("res://tools/combat_qa.gd").new()
		add_child(qa)
		qa.run(self)
	if "--qa" in OS.get_cmdline_user_args():
		enemy.ai_enabled = false
		squad.ai_enabled = false
		var qa = load("res://tools/qa.gd").new()
		add_child(qa)
		qa.run(self)

func make_tactical_commander() -> Node:
	return preload("res://scripts/tactical_commander.gd").new()

func battle_size() -> int:
	var args := OS.get_cmdline_user_args()
	var infantry_only := "--combat-qa" in args or "--qa" in args or "--infantry-only" in args
	var initial_size := 1 if infantry_only else FULL_ROSTER_SIZE
	if "--mounted-melee" in args and campaign_request.is_empty():
		initial_size = MOUNTED_MELEE_BATTLE_ID
	elif "--four-squads" in args:
		initial_size = 2
	elif "--stress-30" in args and not infantry_only:
		initial_size = 15
	return get_tree().get_meta(&"battle_size", initial_size)

func make_armies() -> void:
	if mounted_melee_battle:
		squad = make_unit(0, Vector3(0, 0, 15), "ХАЗАРЫ", "khazar")
		enemy = make_unit(1, Vector3(0, 0, -15), "КОННЫЕ КОПЕЙЩИКИ", "cavalry")
		for group in squads: group.ai_enabled = false
	elif squads_per_side <= 2:
		squad = make_unit(0,Vector3(0,0,15),"СОКОЛ","infantry")
		enemy = make_unit(1,Vector3(0,0,-15),"ВЕПРЬ","infantry")
		if squads_per_side == 2:
			friendly_archers = make_unit(0,Vector3(-18,0,27),"СОВА","archer")
			enemy_archers = make_unit(1,Vector3(18,0,-27),"КОРШУН","archer")
	elif squads_per_side == 3:
		squad = make_unit(0, Vector3(0, 0, 27), "ВАРЯГИ" if varangian_battle else "СОКОЛ", "varangian" if varangian_battle else "infantry")
		enemy = make_unit(1, Vector3(0, 0, -27), "ВЕПРЬ", "infantry")
		friendly_archers = make_unit(0, Vector3(-26, 0, 37), "СОВА", "archer")
		enemy_archers = make_unit(1, Vector3(26, 0, -37), "КОРШУН", "archer")
		make_unit(0, Vector3(35, 0, 31), "ХАЗАРЫ" if khazar_battle else "КОННИЦА СОКОЛА", "khazar" if khazar_battle else "cavalry")
		make_unit(1, Vector3(-35, 0, -31), "КОННИЦА ВЕПРЯ", "cavalry")
	elif squads_per_side == FULL_ROSTER_SIZE:
		make_full_roster()
	else:
		var repeat_count := 3 if squads_per_side == 15 else 1
		for team in 2:
			var side := 1.0 if team == 0 else -1.0
			for block in repeat_count:
				for i in 5:
					var kind: String = ["infantry","infantry","princely","archer","archer"][i]
					if repeat_count>1 and block>0 and i==4:kind="cavalry"
					var title: String = (["СОКОЛ","ВОЛК","КНЯЖЕСКАЯ","СОВА","СТРИЖ"] if team == 0 else ["ВЕПРЬ","МЕДВЕДЬ","КНЯЖЕСКАЯ","КОРШУН","ВОРОН"])[i]
					if kind=="cavalry":title="КОННИЦА"
					var point := Vector3([-20,20,0,-20,20][i],0,[13,13,20,32,32][i]*side)
					if repeat_count > 1:
						point = Vector3((i-2)*22,0,(8+block*13)*side)
						if kind=="cavalry":point.z=(18.0 if block==1 else 36.0)*side
						title += " "+str(block+1)
					var group := make_unit(team,point,title,kind)
					if block == 0 and i == 0:
						if team == 0: squad = group
						else: enemy = group
					if block == 0 and i == 3:
						if team == 0: friendly_archers = group
						else: enemy_archers = group
	for group in squads:
		group.selected = group == squad
		group.opponent = enemy if group.team == 0 else squad

func make_full_roster() -> void:
	for team in 2:
		var side := 1.0 if team == 0 else -1.0
		var infantry := make_unit(team, Vector3(0, 0, 24) * side, "СОКОЛ" if team == 0 else "ВЕПРЬ", "infantry")
		var archers := make_unit(team, Vector3(0, 0, 40) * side, "СОВА" if team == 0 else "КОРШУН", "archer")
		make_unit(team, Vector3(39, 0, 28) * side, "КОННИЦА СОКОЛА" if team == 0 else "КОННИЦА ВЕПРЯ", "cavalry")
		make_unit(team, Vector3(-23, 0, 27) * side, "ВАРЯГИ", "varangian")
		make_unit(team, Vector3(-46, 0, 34) * side, "ХАЗАРЫ", "khazar")
		if team == 0:
			squad = infantry
			friendly_archers = archers
		else:
			enemy = infantry
			enemy_archers = archers

func make_campaign_armies() -> void:
	var garrison_ids: Array = campaign_request.get("garrison",[]).map(func(unit): return unit.id)
	var opening_commanders := {}
	for source in campaign_request.get("support",[]):
		if not source.get("opening",false): continue
		if source.has("city"):
			garrison_ids.append_array(source.roster.map(func(unit): return unit.id))
		elif source.has("army"):
			for unit in source.roster:
				if unit.kind == "princely": opening_commanders[unit.id] = source
	var support_ids := {}
	for source in campaign_support:
		for unit in source.roster:
			support_ids[unit.id] = true
	for team in 2:
		var roster: Array = campaign_request["attackers"] if team == 0 else campaign_request["defenders"]
		roster = roster.filter(func(unit): return not support_ids.has(unit.id))
		var side := 1.0 if team == 0 else -1.0
		var commanders := roster.filter(func(unit): return is_campaign_commander(unit,garrison_ids))
		var line := roster.filter(func(unit): return not is_campaign_commander(unit,garrison_ids))
		roster = line + commanders
		for i in roster.size():
			var unit: Dictionary = roster[i]
			var row := floori(i/10.0)
			var row_count := mini(10,line.size()-row*10)
			var depth := (70.0 if unit.kind in ["archer","cavalry","light_cavalry","princely","varangian","khazar"] else 56.0)+row*22.0
			var point := Vector3((i%10-(row_count-1)*0.5)*23.0,0,side*depth)
			var commander := i >= line.size()
			if commander:
				var column := float(i-line.size())-(commanders.size()-1)*.5
				point = Vector3(column*26.0,0,side*(70.0+ceilf(line.size()/10.0)*22.0+8.0))
			var group := make_campaign_unit(team,point,unit)
			if opening_commanders.has(unit.id):
				var source: Dictionary = opening_commanders[unit.id]
				name_commander(group,source.name,source.portrait,source.faction)
				support_leaders[source.army] = group.soldiers[0]
			elif commander:
				var names: Array = campaign_request.get("commander_names",["",""])
				var portraits: Array = campaign_request.get("commander_portraits",["",""])
				var factions: Array = campaign_request.get("banner_factions",[0,0])
				var city: String = campaign_request.get("city", "") if team == 1 else ""
				name_commander(group,names[team],portraits[team],factions[team],city)
				if team == 0:
					campaign_leader = group.soldiers[0]
				else:
					rival_leader = group.soldiers[0]
			if i == 0 or commander:
				if team == 0:
					squad = group
				else:
					enemy = group
	for group in squads:
		group.selected = group == squad
		group.opponent = enemy if group.team == 0 else squad

func is_campaign_commander(unit: Dictionary, garrison_ids: Array) -> bool:
	return unit.get("commander",false) or (unit.kind == "princely" and unit.id not in garrison_ids)

func make_campaign_unit(team: int, point: Vector3, unit: Dictionary) -> Node3D:
	var group := make_unit(team,point,unit.title,unit.kind,unit.count,unit)
	campaign_groups[unit.id] = group
	return group

func name_commander(group: Node3D, title: String, portrait: String, faction: int, city := "") -> void:
	if not title.is_empty():
		group.display_name = title
		group.commander_portrait = portrait
	group.commander_guard = true
	group.faction_standard = UI.faction_flag(faction, city)
	if group.unit_kind == "princely":
		group.soldiers[0].set_faction_crest(group.faction_standard)

func plan_campaign_support() -> void:
	var slots := Vector2i.ZERO
	var command_slots := Vector2i.ZERO
	var command_totals := Vector2i.ZERO
	# Preserve the reinforcement march distance when the playable area grows.
	var first_row_depth := field_half_size.y / FIELD_SIZE_SCALE - REINFORCEMENT_REAR_MARGIN
	for source in campaign_support:
		support_totals[source.team] += source.roster.size()
		if source.has("army"):
			command_totals[source.team] += source.roster.filter(func(unit): return unit.kind == "princely").size()
	for source in campaign_support:
		var team: int = source.team
		var side := 1.0 if team == 0 else -1.0
		for unit in source.roster:
			var commander: bool = source.has("army") and unit.kind == "princely"
			var point: Vector3
			if commander:
				var column := command_slots[team] - (command_totals[team]-1)*.5
				point = Vector3(column*26.0,0,side*(first_row_depth+24.0))
				command_slots[team] += 1
			else:
				var slot := slots[team]
				slots[team] += 1
				var row := floori(float(slot)/REINFORCEMENT_ROW_SIZE)
				var columns := mini(REINFORCEMENT_ROW_SIZE,support_totals[team]-command_totals[team]-row*REINFORCEMENT_ROW_SIZE)
				var depth := first_row_depth - row * 30.0
				point = Vector3((slot%REINFORCEMENT_ROW_SIZE-(columns-1)*.5)*34.0,0,side*depth)
			var portrait: String = source.get("portrait", "") if commander else ""
			UI.request_art(unit.kind)
			if not portrait.is_empty(): UI.request_art(portrait)
			support_plan.append({"source":source,"unit":unit,"point":point,"portrait":portrait,"group":null})

func prepare_campaign_support() -> void:
	if support_prepared >= support_plan.size(): return
	var entry := support_plan[support_prepared]
	var group: Node3D = entry.group
	if group == null:
		var unit: Dictionary = entry.unit
		entry.group = make_unit(entry.source.team,entry.point,unit.title,unit.kind,unit.count,unit,squads.size()+support_prepared-support_arrived)
		return
	if group.members.size() < group.unit_count: return
	if not UI.art_ready(group.unit_kind) or (not entry.portrait.is_empty() and not UI.art_ready(entry.portrait)): return
	UI.art(group.unit_kind)
	if not entry.portrait.is_empty():
		UI.art(entry.portrait)
		UI.faction_flag(entry.source.faction)
	var side := 1.0 if group.team == 0 else -1.0
	group.command(2,entry.point-Vector3.BACK*side*70.0)
	var groups: Array[Node3D] = [group]
	crowd_renderer.prepare_visuals(groups)
	support_prepared += 1

func bring_in_support() -> void:
	if support_arrived < support_prepared:
		var entry := support_plan[support_arrived]
		var group: Node3D = entry.group
		var source: Dictionary = entry.source
		campaign_groups[entry.unit.id] = group
		squads.append(group)
		configure_crowd_detail()
		var groups: Array[Node3D] = [group]
		crowd_movement.register_actors(groups)
		group.activate_reinforcement()
		if group.team == 0:
			group.set_behavior(reinforcement_behavior)
		group.opponent = enemy if group.team == 0 else squad
		if source.has("army") and entry.unit.kind == "princely" and not support_leaders.has(source.army):
			name_commander(group,source.name,source.portrait,source.faction)
			support_leaders[source.army] = group.soldiers[0]
		add_squad_banner(group)
		hud.add_unit_card(group)
		support_arrived += 1
	if support_arrived < support_plan.size(): return
	campaign_support.clear()
	support_plan.clear()
	order_notice = "Подошла подмога с обеих сторон" if support_totals.x > 0 and support_totals.y > 0 else ("Подошла наша подмога" if support_totals.x > 0 else "Подошла вражеская подмога")
	order_expires = Time.get_ticks_msec()+5000

func make_unit(team: int, point: Vector3, title: String, kind: String, campaign_count := -1, unit := {}, pending_serial := -1) -> Node3D:
	var group := Node3D.new()
	group.set_script(SQUAD)
	group.team = team
	group.behavior_controlled = team == 0
	var banner_colors: Array = campaign_request.get("banner_colors", [])
	if team < banner_colors.size():
		group.uniform_dye = TroopColors.uniform_color(banner_colors[team])
	group.unit_kind = kind
	group.unit_count = 30 if kind in ["archer", "cavalry", "light_cavalry", "khazar", "princely"] else 60
	group.experience_points = unit.get("xp",0)
	if not unit.is_empty():
		group.experience_capacity = unit.get("max",CampaignData.UNITS[kind][1])
	group.equipment = Equipment.levels(unit)
	var research: Array = campaign_request.get("research_bonuses",[])
	if team < research.size():
		var bonuses: Dictionary = research[team]
		group.morale_bonus = bonuses.morale
		group.stamina_discount = bonuses.stamina
		if kind in bonuses.armored_units:
			group.armor_reduction = bonuses.armor
	if kind == "archer": group.unit_script = preload("res://scripts/archer.gd")
	elif kind == "cavalry":group.unit_script=preload("res://scripts/cavalry.gd")
	elif kind == "light_cavalry": group.unit_script = preload("res://scripts/light_cavalry.gd")
	elif kind == "khazar": group.unit_script = preload("res://scripts/khazar.gd")
	elif kind == "princely": group.unit_script = preload("res://scripts/princely.gd")
	elif kind == "militia": group.unit_script = preload("res://scripts/militia.gd")
	elif kind == "varangian":
		group.unit_count = 40
		group.unit_script = preload("res://scripts/varangian.gd")
	if campaign_count > 0:
		group.unit_count = campaign_count
	group.spawn_center = unit_spawn_point(point)
	group.spawn_heading = 0.0 if team == 0 else PI
	group.display_name = title
	group.selected = false
	if pending_serial >= 0:
		group.serial = pending_serial
		group.reinforcement_pending = true
		group.process_mode = Node.PROCESS_MODE_DISABLED
		group.hide()
	add_child(group)
	if pending_serial < 0:
		squads.append(group)
	return group

func unit_spawn_point(point: Vector3) -> Vector3:
	if campaign_request.is_empty() and not mounted_melee_battle:
		point.z += 28.0 * signf(point.z)
	return point

func selected_groups() -> Array[Node3D]:
	return squads.filter(func(group): return group.team == 0 and group.selected and group.combat_ready())

func friendly_groups() -> Array[Node3D]:
	return squads.filter(func(group): return group.team == 0 and not group.surrendered and group.alive_count() > 0)

func set_squad_behavior(index: int, all_groups: bool) -> void:
	if not result_text.is_empty() or index < 0 or index >= SQUAD.BEHAVIOR_NAMES.size():
		return
	var groups := friendly_groups() if all_groups else selected_groups()
	if all_groups:
		reinforcement_behavior = index
	for group in groups:
		group.set_behavior(index)
	hud.refresh_selection()

func select_squad(group: Node3D, additive := false) -> void:
	if not is_instance_valid(group) or group.team != 0 or not group.combat_ready(): return
	var selection := selected_groups() if additive else ([] as Array[Node3D])
	if additive and selection.has(group):
		selection.erase(group)
	else:
		selection.append(group)
	apply_squad_selection(selection)

func apply_squad_selection(selection: Array[Node3D]) -> void:
	if not selection.is_empty(): selected_squad = selection[-1]
	for item in squads:
		item.selected = item in selection
		item.update_selection_rings()
	command_mode = 0
	right_held = false
	formation_preview.hide()
	if is_instance_valid(hud):
		hud.refresh_selection(true)

func select_in_box(rect: Rect2, additive := false) -> void:
	var selection := selected_groups() if additive else ([] as Array[Node3D])
	for group in squads:
		if group.team != 0 or not group.combat_ready() or group in selection: continue
		for soldier in group.members:
			var point: Vector3 = soldier.global_position+Vector3.UP
			if not camera.is_position_behind(point) and rect.has_point(camera.unproject_position(point)):
				selection.append(group)
				break
	apply_squad_selection(selection)

func command_selected(action: int, point: Vector3, confirm := false) -> void:
	var groups := selected_groups()
	if groups.is_empty() or not result_text.is_empty(): return
	var center := Vector3.ZERO
	for group in groups: center += group.center()
	center /= groups.size()
	for group in groups:
		var destination := point
		if groups.size()>1 and action in [1,2]:
			var offset: Vector3 = group.center()-center
			offset.y = 0
			destination = FIELD.project(point+offset)
		group.command(action,destination)
	if confirm:
		order_notice = "Приказ принят · движение"
		order_expires = Time.get_ticks_msec()+1200
		order_marker.position = FIELD.project(point)+Vector3.UP*.14
		order_marker.show()
		hud.refresh_selection()

func attack_enemy(target: Node3D, running: bool) -> void:
	if deploying or not result_text.is_empty() or not is_instance_valid(target) or target.team != 1 or target.surrendered or target.alive_count() == 0: return
	var groups := selected_groups()
	if groups.is_empty(): return
	var now := Time.get_ticks_msec()
	running = running or (last_attack_target == target and now - last_attack_click <= 400)
	last_attack_click = -1000 if running else now
	last_attack_target = target
	last_attack_pointer = get_viewport().get_mouse_position()
	for group in groups: group.command_attack(target,running)
	order_notice = "Приказ принят · атака бегом" if running else "Приказ принят · атака"
	order_expires = Time.get_ticks_msec()+1200
	order_marker.hide()
	command_mode = 0
	hud.refresh_selection()

func stop_selected() -> void:
	for group in selected_groups(): group.stop()
	command_mode = 0

func toggle_selected_melee() -> void:
	if deploying or not result_text.is_empty(): return
	var bow_units := selected_groups().filter(func(group): return group.is_ranged() and group.ammo_count() > 0)
	if bow_units.is_empty(): return
	var enable := bow_units.any(func(group): return group.uses_bows())
	for group in bow_units: group.set_melee_mode(enable)
	command_mode = 0
	hud.refresh_selection()

func fortify_selected() -> void:
	if deploying or not result_text.is_empty(): return
	for group in selected_groups():
		if group.uses_spear_formation():
			group.command(5, group.center() + Vector3.FORWARD.rotated(Vector3.UP, group.order_heading))
	command_mode = 0
	hud.refresh_selection()

func team_alive(team: int) -> int:
	var total := 0
	for group in squads:
		if group.team == team: total += group.alive_count()
	return total

func team_in_battle(team: int) -> int:
	var total := 0
	for group in squads:
		if group.team == team and group.combat_ready(): total += group.alive_count()
	return total

func team_holds(team: int) -> bool:
	return squads.any(func(group): return group.team == team and group.combat_ready() and not group.wavering)

func team_health(team: int) -> float:
	var value := 0.0
	var count := 0
	for group in squads:
		if group.team == team:
			value += group.total_health()*group.unit_count
			count += group.unit_count
	return value/maxi(1,count)

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.95
	return result

func make_environment() -> void:
	var season: int = campaign_request.get("landscape", {}).get("season", 0)
	var condition: int = campaign_request.get("weather", LandscapeLighting.WorldWeather.Weather.CLEAR)
	battle_weather = LandscapeLighting.install(self, season, condition)

func make_terrain() -> void:
	terrain = Node3D.new()
	terrain.set_script(preload("res://scripts/terrain.gd"))
	terrain.name = "Terrain"
	terrain.field_half_size = field_half_size
	if campaign_request.is_empty() and standalone_layout != null:
		terrain.landscape = standalone_layout.landscape(0)
	elif campaign_request.is_empty():
		terrain.landscape = {
			"seed": get_tree().get_meta(&"tactical_map_seed", MapGenerator.DEFAULT_SEED),
			"opening_half_width": 78.0,
			"profile": get_tree().get_meta(&"tactical_map_profile", MapGenerator.Profile.MEADOW),
		}
	else:
		var landscape: Dictionary = campaign_request.get("landscape", {}).duplicate()
		landscape["city"] = campaign_request.get("city_battle", landscape.get("city", false))
		terrain.landscape = landscape
	add_child(terrain)
	FIELD.terrain_ref = weakref(terrain)

func make_navigation() -> void:
	var region := NavigationRegion3D.new()
	var navmesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	const CELLS := int(40 * FIELD_SIZE_SCALE)
	for z in CELLS+1:
		for x in CELLS+1:
			vertices.append(FIELD.project(Vector3(lerpf(-field_half_size.x+.5,field_half_size.x-.5,x/float(CELLS)),0,lerpf(-field_half_size.y+.5,field_half_size.y-.5,z/float(CELLS)))))
	navmesh.vertices = vertices
	for z in CELLS:
		for x in CELLS:
			var i := z*(CELLS+1)+x
			navmesh.add_polygon(PackedInt32Array([i,i+CELLS+1,i+CELLS+2,i+1]))
	region.navigation_mesh = navmesh
	add_child(region)

func settlement_box(size: Vector3, point: Vector3, color: Color) -> MeshInstance3D:
	var prop := MeshInstance3D.new()
	var model := BoxMesh.new()
	model.size = size
	model.material = material(color)
	prop.mesh = model
	add_child(prop)
	prop.position = point+Vector3.UP*terrain.height_at(Vector2(point.x,point.z))
	return prop

func make_settlement_battle() -> void:
	var city_direction := 1.0 if campaign_request.get("defending_city",false) else -1.0
	siege_line = absf(siege_line)*city_direction
	if TACTICAL_FORTIFICATIONS and campaign_request.get("fortified",false):
		siege_gates.append(-field_half_size.x*0.35)
		siege_gates.append(field_half_size.x*0.35 if campaign_request.get("ram",false) else field_half_size.x*0.78)
		for i in range(ceili(-field_half_size.x),floori(field_half_size.x),3):
			var opening := false
			for gate in siege_gates:
				if absf(i-gate)<6.2:
					opening = true
			if not opening:
				settlement_box(Vector3(3.1,4.3,1.35),Vector3(i,2.15,siege_line),Color("#574332"))
		for gate in siege_gates:
			for side in [-1,1]:
				var pier: float = gate+side*6.8
				settlement_box(Vector3(3.0,8.2,3.8),Vector3(pier,4.1,siege_line),Color("#594336"))
		if campaign_request.get("ram",false):
			settlement_box(Vector3(3.2,2.65,7.2),Vector3(siege_gates[-1],1.35,siege_line-city_direction*6.0),Color("#6e5842"))
	for i in 5:
		var x := field_half_size.x*(0.72 if i%2==0 else -0.72)
		var z := city_direction*(field_half_size.y-9.0-i*5.3)
		settlement_box(Vector3(6.0,3.5,4.4),Vector3(x,1.75,z),Color("#614a32"))
		for side in [-1,1]:
			var roof := settlement_box(Vector3(6.5,.25,2.8),Vector3(x,4.14,z+side*1.11),Color("#3e3028"))
			roof.rotation.x = side*.56

func siege_waypoint(from: Vector3, goal: Vector3, group: Node3D = null) -> Vector3:
	if siege_gates.is_empty() or (from.z-siege_line)*(goal.z-siege_line)>=0.0:
		return goal
	var crossing := lerpf(from.x,goal.x,(siege_line-from.z)/(goal.z-from.z))
	var reference: float = group.center().x if group else crossing
	var gate: float = group.siege_gate if group and group.siege_gate != INF else nearest_siege_gate(reference)
	if absf(crossing-gate)<3.8:
		return goal
	return Vector3(gate+clampf(crossing-gate,-3.6,3.6),0,siege_line+3.0*signf(goal.z-siege_line))

func nearest_siege_gate(x: float) -> float:
	var nearest := INF
	for gate in siege_gates:
		if absf(x - gate) < absf(x - nearest):
			nearest = gate
	return nearest

func constrain_siege_crossing(from: Vector3, goal: Vector3) -> Vector3:
	if siege_gates.is_empty() or (from.z-siege_line)*(goal.z-siege_line)>=0.0:
		return goal
	var crossing := lerpf(from.x,goal.x,(siege_line-from.z)/(goal.z-from.z))
	for gate in siege_gates:
		if absf(crossing-gate)<5.8:
			return goal
	return Vector3(goal.x,goal.y,siege_line+0.72*signf(from.z-siege_line))

func make_ring(radius: float, color: Color) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - .045
	mesh.outer_radius = radius + .045
	mesh.rings = 96
	mesh.ring_segments = 6
	return make_ring_mesh(mesh, color)

func make_ring_mesh(mesh: Mesh, color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	var style := material(color)
	style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if mesh == null: style.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = style
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	return ring

func drape_ring(ring: MeshInstance3D, point: Vector3, radius: float) -> void:
	var center := Vector2(point.x, point.z)
	var origin := Vector3(point.x, 0.0, point.z)
	var mesh: ImmediateMesh = ring.mesh
	if mesh == null:
		mesh = ImmediateMesh.new()
		ring.mesh = mesh
	if mesh.get_surface_count() > 0 and ring.get_meta(&"radius") == radius and ring.position.distance_squared_to(origin) < .0064:
		return
	ring.position = origin
	ring.set_meta(&"radius", radius)
	var half_width := maxf(.045, radius * .00225)
	var steps := maxi(40, ceili(TAU * radius / .8))
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for step in range(steps + 1):
		var direction := Vector2.from_angle(TAU * step / steps)
		for edge in [radius - half_width, radius + half_width]:
			var offset: Vector2 = direction * edge
			mesh.surface_add_vertex(Vector3(offset.x, terrain.height_at(center + offset) + .10, offset.y))
	mesh.surface_end()

func deployment_zone() -> Rect2:
	var width := field_half_size.x - DEPLOYMENT_EDGE_MARGIN
	var depth := field_half_size.y - DEPLOYMENT_EDGE_MARGIN - DEPLOYMENT_FRONT
	return Rect2(-width,DEPLOYMENT_FRONT,2.0*width,depth)

func make_deployment_line() -> void:
	var zone := deployment_zone()
	var corners := [zone.position,Vector2(zone.end.x,zone.position.y),zone.end,Vector2(zone.position.x,zone.end.y)]
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for side in 4:
		var first: Vector2 = corners[side]
		var last: Vector2 = corners[(side+1)%4]
		var segments := ceili(first.distance_to(last)/3.0)
		for i in segments:
			var a := first.lerp(last,float(i)/segments)
			var b := first.lerp(last,float(i+1)/segments)
			mesh.surface_add_vertex(FIELD.project(Vector3(a.x,0,a.y))+Vector3.UP*.25)
			mesh.surface_add_vertex(FIELD.project(Vector3(b.x,0,b.y))+Vector3.UP*.25)
	mesh.surface_end()
	var style := material(Color("e4c878"))
	style.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	deployment_line = MeshInstance3D.new()
	deployment_line.mesh = mesh
	deployment_line.material_override = style
	deployment_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deployment_line)

func formation_footprint(points: Array) -> Rect2:
	var bounds := Rect2(Vector2(points[0].x,points[0].z),Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(Vector2(point.x,point.z))
	return bounds.grow(.7)

func deploy_selected(point: Vector3, layout: Dictionary) -> void:
	var groups := selected_groups()
	if groups.is_empty(): return
	finish_deployment_move()
	var occupied: Array[Rect2] = []
	for group in squads:
		if group.team == 0 and group not in groups:
			occupied.append(formation_footprint(group.members.map(func(soldier): return soldier.position)))
	var placements := {}
	var center := Vector3.ZERO
	for group in groups: center += group.center()
	center /= groups.size()
	var zone := deployment_zone()
	for group in groups:
		var slots: Array[Vector3] = []
		if layout.is_empty():
			for soldier in group.members:
				slots.append(FIELD.project(soldier.position+point-center))
		else:
			slots = layout[group].slots
		var footprint := formation_footprint(slots)
		var blocked := slots.any(func(slot):
			var ground: Vector3 = terrain.constrain(slot)
			return Vector2(slot.x-ground.x,slot.z-ground.z).length_squared() > .01
		)
		if blocked or not zone.encloses(footprint) or occupied.any(func(rect): return rect.intersects(footprint)):
			order_notice = "Выберите свободное место внутри зоны расстановки"
			order_expires = Time.get_ticks_msec()+2800
			return
		var formation: Dictionary = layout.get(group,{})
		placements[group] = {
			"slots": slots,
			"heading": formation.get("heading",group.order_heading),
			"columns": formation.get("columns",group.formation_columns),
			"width": formation.get("width",group.formation_width),
		}
	deployment_move = placements
	if layout.size() > 1:
		begin_deployment_move()
	else:
		finish_deployment_move()

func begin_deployment_move() -> void:
	deployment_elapsed = 0.0
	var longest := 0.0
	for group in deployment_move:
		var layout: Dictionary = deployment_move[group]
		var slots: Array[Vector3] = layout.slots
		var assignment: PackedInt32Array = group.assign_slots(slots,group.members)
		var starts: Array[Vector3] = []
		var destinations: Array[Vector3] = []
		for i in group.members.size():
			var start: Vector3 = group.members[i].position
			var destination := slots[assignment[i]]
			starts.append(start)
			destinations.append(destination)
			longest = maxf(longest,start.distance_to(destination))
		layout.slots = destinations
		layout.starts = starts
	deployment_duration = clampf(longest / 12.0,.55,2.6)
	order_notice = "Отряды занимают позиции"
	order_expires = Time.get_ticks_msec()+ceili(deployment_duration*1000)

func advance_deployment_move(delta: float) -> void:
	deployment_elapsed += delta
	if deployment_elapsed >= deployment_duration:
		finish_deployment_move()
		return
	var progress := deployment_elapsed / deployment_duration
	var travel := smoothstep(0.0,1.0,progress)
	var turn := smoothstep(.65,1.0,progress)
	for group in deployment_move:
		var layout: Dictionary = deployment_move[group]
		for i in group.members.size():
			var start: Vector3 = layout.starts[i]
			var destination: Vector3 = layout.slots[i]
			var direction := destination-start
			var heading: float = layout.heading
			if Vector2(direction.x,direction.z).length_squared() > .01:
				heading = lerp_angle(atan2(-direction.x,-direction.z),heading,turn)
			var soldier: CharacterBody3D = group.members[i]
			var point := FIELD.project(start.lerp(destination,travel))
			soldier.motion_speed = soldier.position.distance_to(point) / maxf(delta,.001)
			soldier.place_for_deployment(point,heading)
			soldier.update_motion_animation(0.0,false)
			soldier.visual_step(delta)
		group.refresh_center()
		group.update_selection_rings()
	combat_index.rebuild()
	crowd_renderer.render_step(0.0,false)

func finish_deployment_move() -> void:
	if deployment_move.is_empty(): return
	for group in deployment_move:
		var layout: Dictionary = deployment_move[group]
		group.deploy_formation(layout.slots,layout.heading,layout.columns,layout.width)
		if layout.has("starts"):
			for soldier in group.members:
				soldier.motion_speed = 0.0
				soldier.update_motion_animation(0.0,false)
				soldier.visual_step(0.0)
	deployment_move.clear()
	combat_index.rebuild()
	crowd_renderer.render_step(0.0,false)
	order_notice = "Отряды расставлены"
	order_expires = Time.get_ticks_msec()+1400

func make_interface() -> void:
	tactical_markers = CanvasLayer.new()
	tactical_markers.layer = 1
	add_child(tactical_markers)
	overlay = preload("res://scripts/order_overlay.gd").new()
	overlay.world = self
	tactical_markers.add_child(overlay)
	set_tactical_markers_visible(false)
	for group in squads:
		add_squad_banner(group)
	var interface := CanvasLayer.new()
	interface.layer = 2
	add_child(interface)
	hud = TacticalHUD.new()
	hud.world = self
	interface.add_child(hud)
	selection_box = Panel.new()
	selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.add_theme_stylebox_override("panel",UI.box(Color(.83,.72,.45,.13),Color("e7ca84"),0))
	interface.add_child(selection_box)
	selection_box.hide()
	order_marker = make_ring(1.45,Color("ead086"))
	order_marker.hide()

func add_squad_banner(group: Node3D) -> void:
	var banner := banner_scene.new()
	banner.squad = group
	tactical_markers.add_child(banner)
	banners.append(banner)

func add_battle_size_control(parent: Control) -> void:
	var size_button := OptionButton.new()
	size_button.focus_mode = Control.FOCUS_NONE
	size_button.custom_minimum_size.y = 34
	size_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_button.tooltip_text = "Начать новый бой в выбранном масштабе"
	size_button.add_item("1 × 1 · Копейщики", 1)
	if squads.size() == 4:
		size_button.add_item("2 × 2 · Пехота и лучники", 2)
	size_button.add_item("3 × 3 · Копья, луки и конница", 3)
	size_button.add_item("3 × 3 · Варяги", VARANGIAN_BATTLE_ID)
	size_button.add_item("3 × 3 · Варяги и хазары", KHAZAR_BATTLE_ID)
	size_button.add_item("1 × 1 · Хазары и конные копейщики", MOUNTED_MELEE_BATTLE_ID)
	size_button.add_item("5 × 5 · Все виды отрядов", FULL_ROSTER_SIZE)
	size_button.add_item("15 × 15 · Большой бой", 15)
	var scenario := MOUNTED_MELEE_BATTLE_ID if mounted_melee_battle else (KHAZAR_BATTLE_ID if khazar_battle else (VARANGIAN_BATTLE_ID if varangian_battle else squads_per_side))
	size_button.select(size_button.get_item_index(scenario))
	size_button.item_selected.connect(func(index: int):
		get_tree().set_meta(&"battle_size", size_button.get_item_id(index))
		get_tree().reload_current_scene())
	parent.add_child(size_button)

func set_tactical_markers_visible(enabled: bool) -> void:
	overlay.visible = enabled
	for group in squads:
		group.show_selection_rings = enabled
		group.update_selection_rings()

func banner_clicked(button: int, double_click: bool, group: Node3D, additive := false) -> void:
	if button == MOUSE_BUTTON_LEFT and group.team == 0:
		select_squad(group,additive or Input.is_key_pressed(KEY_SHIFT))
	elif button == MOUSE_BUTTON_RIGHT and group.team == 1:
		attack_enemy(group,double_click)

func update_camera() -> void:
	var direction := Vector2(sin(camera_yaw), cos(camera_yaw))
	var focus_xz := Vector2(focus.x, focus.z)
	var terrain_limit: Vector2 = terrain.grid_half - Vector2.ONE * CAMERA_TERRAIN_EDGE_INSET
	var edge_room := terrain_limit - focus_xz * direction.sign()
	var edge_distance := edge_room / direction.abs().max(Vector2.ONE * .000001)
	var horizontal_distance := minf(camera_distance * cos(camera_pitch), minf(edge_distance.x, edge_distance.y))
	var camera_xz := focus_xz + direction * horizontal_distance
	# Steepen the orbit at the edge to keep the requested zoom distance.
	var orbit_height := sqrt(maxf(0.0, camera_distance * camera_distance - horizontal_distance * horizontal_distance))
	var ground_height: float = terrain.height_at(camera_xz)
	var camera_height := maxf(focus.y + orbit_height, ground_height + CAMERA_GROUND_CLEARANCE)
	var camera_point := Vector3(camera_xz.x, camera_height, camera_xz.y)
	var next_transform := Transform3D(Basis.looking_at(focus - camera_point), camera_point)
	if camera.transform != next_transform:
		camera.transform = next_transform
		camera_last_moved_ms = Time.get_ticks_msec()
	LandscapeLighting.update_view(battle_weather, camera, camera_distance)

func stop_camera_rotation(restore_cursor := true) -> void:
	if not camera_rotating: return
	camera_rotating = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if restore_cursor:
		get_viewport().warp_mouse(camera_mouse_origin)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		stop_camera_rotation(false)

func configure_crowd_detail() -> void:
	if squads.size() <= 10: return
	var scale := .70 if squads.size() >= 24 else .82
	var viewport := get_viewport()
	viewport.scaling_3d_scale = minf(previous_render_scale,scale)
	var largest_battle := squads.size() >= 24
	if largest_battle:
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		battle_weather.environment.ssao_enabled = false
		effects.limit_distant_detail = true
		effects.prepare_large_battle_bursts()
		if crowd_renderer.warrior_meshes: crowd_renderer.instant_lod = true
		for group in squads:
			if group.unit_kind == "princely":
				group.soldiers[0].model.use_skinned_cape()
	terrain.grass_range = 48.0 if largest_battle else 72.0
	terrain.grass_instances_per_chunk = 128 if largest_battle else 320

func _exit_tree() -> void:
	get_viewport().scaling_3d_scale = previous_render_scale
	get_viewport().msaa_3d = previous_msaa
	stop_camera_rotation(false)

func _input(event: InputEvent) -> void:
	if not result_text.is_empty():
		return
	if right_held and event is InputEventMouseMotion:
		right_pointer = event.position
	if left_held:
		if event is InputEventMouseMotion:
			var drag := Rect2(left_start,event.position-left_start).abs()
			selection_box.position = drag.position
			selection_box.size = drag.size
			selection_box.visible = left_start.distance_to(event.position)>8.0
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			left_held = false
			selection_box.hide()
			if left_start.distance_to(event.position)>8.0:
				var bounds := Rect2(0,hud.map_top_y(),get_viewport().get_visible_rect().size.x,hud.map_bottom_y()-hud.map_top_y())
				select_in_box(Rect2(left_start,event.position-left_start).abs().intersection(bounds),left_additive)
			else:
				var soldier := pick_soldier(event.position)
				if soldier and soldier.team == 0: select_squad(soldier.get_parent(),left_additive)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and right_held and event.position.y >= hud.map_bottom_y():
		right_held = false
		drag_layout.clear()
		formation_preview.hide()
	# Handle camera input before GUI so controls cannot swallow the drag or release.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			if camera_locked: return
			camera_mouse_origin = event.position
			camera_rotating = true
			left_held = false
			selection_box.hide()
			right_held = false
			drag_layout.clear()
			formation_preview.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			stop_camera_rotation()
		get_viewport().set_input_as_handled()
		return
	if not camera_rotating: return
	if event is InputEventKey and event.pressed:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_ESCAPE:
			stop_camera_rotation()
	if event is InputEventMouseMotion:
		if camera_locked:
			stop_camera_rotation()
		else:
			camera_yaw -= event.relative.x * .0035
			camera_pitch = clampf(camera_pitch + event.relative.y * .0035, deg_to_rad(10.0), deg_to_rad(85.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		get_viewport().set_input_as_handled()

func setup_battle_music() -> void:
	var playlist := AudioStreamPlaylist.new()
	playlist.stream_count = BATTLE_TRACKS.size()
	for i in BATTLE_TRACKS.size():
		playlist.set_list_stream(i, load(BATTLE_TRACKS[i]) as AudioStream)
	battle_music = AudioStreamPlayer.new()
	battle_music.name = "BattleMusic"
	battle_music.stream = playlist
	battle_music.volume_db = -16.0 + linear_to_db(1.2)
	add_child(battle_music)

func toggle_battle_music() -> void:
	var enabled: bool = not get_tree().get_meta(&"battle_music_enabled", false)
	get_tree().set_meta(&"battle_music_enabled", enabled)
	if battle_music == null:
		setup_battle_music()
	if enabled and not battle_music.playing:
		battle_music.play()
	battle_music.stream_paused = not enabled

func toggle_pause() -> void:
	if result_text.is_empty(): set_battle_paused(not get_tree().paused)

func set_battle_paused(pause: bool) -> void:
	if not pause and deploying:
		finish_deployment_move()
		deploying = false
		deployment_line.hide()
		right_held = false
		formation_preview.hide()
		order_expires = 0
	get_tree().paused = pause
	hud.update_pause(pause)
	hud.refresh_selection()
	for voice in effects.voices:
		voice.stream_paused = pause

func show_inspiration(origin: Vector3, radius: float) -> void:
	effects.sound("horn",origin+Vector3.UP*2.4,-1.0)
	var ring := make_ring(radius,Color("e4c483"))
	ring.position = origin + Vector3.UP*.19
	ring.process_mode = Node.PROCESS_MODE_PAUSABLE
	await get_tree().create_timer(1.75,false).timeout
	if is_instance_valid(ring): ring.queue_free()

func set_speed(rate: int) -> void:
	speed = clampi(rate,1,3)
	Engine.time_scale = speed
	for i in speed_buttons.size(): speed_buttons[i].button_pressed = i+1 == speed

func start_battle() -> void:
	if not result_text.is_empty(): return
	if deploying:
		set_battle_paused(false)
	auto_battle = true
	set_squad_behavior(SQUAD.Behavior.AGGRESSIVE, true)
	for group in friendly_groups():
		send_to_nearest(group)

func send_to_nearest(group: Node3D) -> void:
	if not group.combat_ready(): return
	if group.reforming_after_rout:
		return
	var target: Node3D
	var nearest := INF
	var fleeing_target: Node3D
	var nearest_fleeing := INF
	for other in squads:
		if other.team == group.team or other.surrendered or other.alive_count() == 0: continue
		var distance: float = group.center().distance_squared_to(other.center())
		if other.routed:
			if distance < nearest_fleeing:
				nearest_fleeing = distance
				fleeing_target = other
			continue
		if distance < nearest: nearest = distance; target = other
	if not target: target = fleeing_target
	if target: group.command_attack(target,true,false,true)

func ground_point(screen: Vector2):
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(screen)*camera.far,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else null

func change_formation_density(level: int) -> void:
	command_mode = 0
	for group in selected_groups(): group.set_formation_density(level)
	density_button.select(selected_squad.formation_density)

func _unhandled_input(event: InputEvent) -> void:
	if not result_text.is_empty():
		if campaign_request.is_empty() and event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_R or event.keycode == KEY_R): restart_battle()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		match key:
			KEY_SPACE,KEY_P: toggle_pause()
			KEY_1,KEY_2,KEY_3: set_speed(key-KEY_0)
			KEY_B: start_battle()
			KEY_V: toggle_selected_melee()
			KEY_G: command_mode = 3 if not deploying and not selected_groups().is_empty() else 0
			KEY_4, KEY_5, KEY_6:
				if deploying: return
				if key == KEY_4 and event.shift_pressed:
					command_mode = 4 if selected_groups().any(func(group): return group.can_bombard()) else 0
				else:
					change_formation_density(key - KEY_4)
			KEY_X:
				if not deploying: stop_selected()
			KEY_ESCAPE:
				command_mode = 0
				right_held = false
				left_held = false
				formation_preview.hide()
				selection_box.hide()
			KEY_F: focus = selected_squad.center()
			KEY_C: camera_follow = not camera_follow
			KEY_R:
				if campaign_request.is_empty():
					get_tree().reload_current_scene()
			KEY_M: AudioServer.set_bus_mute(0,not AudioServer.is_bus_mute(0))
			KEY_F7:
				if campaign_request.is_empty():
					var weather := LandscapeLighting.WorldWeather.Weather
					var next := (battle_weather.condition + 1) % weather.size()
					battle_weather.set_weather(next, battle_weather.season)
			KEY_F8: toggle_battle_music()
			KEY_F9: set_tactical_markers_visible(not overlay.visible)
	if event is InputEventMouseButton:
		if event.pressed and command_mode == 0 and (event.button_index == MOUSE_BUTTON_LEFT or (event.button_index == MOUSE_BUTTON_RIGHT and not deploying)):
			for banner in banners:
				var standard: Node3D = banner.world_standard
				var friendly: bool = banner.squad.team == 0
				if friendly == (event.button_index == MOUSE_BUTTON_LEFT) and standard.contains_screen_point(camera, event.position):
					banner_clicked(event.button_index,event.double_click,banner.squad,event.shift_pressed)
					get_viewport().set_input_as_handled()
					return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if event.position.y >= hud.map_bottom_y(): return
				if event.double_click and not deploying:
					var soldier := pick_soldier(event.position)
					if soldier and soldier.team == 1:
						right_held = false
						formation_preview.hide()
						attack_enemy(soldier.get_parent(),true)
						return
					if is_instance_valid(last_attack_target) and Time.get_ticks_msec()-last_attack_click <= 400 and event.position.distance_squared_to(last_attack_pointer) < 400.0:
						right_held = false
						formation_preview.hide()
						attack_enemy(last_attack_target,true)
						return
				if selected_groups().is_empty(): return
				var ground = ground_point(event.position)
				if ground == null: return
				right_held = true
				right_double = event.double_click
				right_time = 0
				right_start = ground
				right_screen = event.position
				right_pointer = event.position
				drag_layout.clear()
			elif right_held:
				right_held = false
				if not right_double and event.position.distance_to(right_screen) > 9.0:
					update_formation_drag(event.position)
				if deploying:
					deploy_selected(right_start,drag_layout if formation_preview.visible else {})
				elif formation_preview.visible:
					for group in drag_layout:
						if group.combat_ready(): group.command_formation(drag_layout[group])
					order_notice = "Приказ принят · перестроение"
					order_expires = Time.get_ticks_msec()+1400
					hud.refresh_selection()
				else:
					var picked := pick_soldier(event.position)
					if picked and picked.team == 1: attack_enemy(picked.get_parent(),right_double)
					else: command_selected(2 if right_double else 1,right_start,true)
				formation_preview.hide()
				command_mode = 0
			return
		if not event.pressed: return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if camera_locked: return
			if not camera_zooming: camera_zoom_target = camera_distance
			var factor := .88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12
			camera_zoom_target = clampf(camera_zoom_target * factor, 6.0, MAX_CAMERA_DISTANCE)
			camera_zooming = true
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var point = ground_point(event.position)
			if command_mode > 0 and point != null:
				command_selected(command_mode,point)
				command_mode = 0
			elif event.position.y >= hud.map_top_y() and event.position.y < hud.map_bottom_y():
				left_held = true
				left_start = event.position
				left_additive = event.shift_pressed

func update_formation_drag(pointer: Vector2) -> void:
	var point = ground_point(pointer)
	var groups := selected_groups()
	if point == null or groups.is_empty():
		formation_preview.hide()
		drag_layout.clear()
		return
	if point.distance_to(right_start) < 1.2:
		point = right_start + Vector3.RIGHT.rotated(Vector3.UP,camera_yaw)*selected_squad.formation_width
	if groups.size() == 1:
		var group := groups[0]
		drag_layout = {group: group.formation_from_drag(right_start,point)}
	else:
		drag_layout = group_formation_from_drag(groups,right_start,point)
	formation_preview.show_formations(drag_layout.values())
	formation_preview.show()

func group_formation_from_drag(groups: Array[Node3D], first: Vector3, last: Vector3) -> Dictionary:
	var line := (last-first).slide(Vector3.UP)
	var side := line.normalized()
	if side.is_zero_approx(): side = Vector3.RIGHT
	groups.sort_custom(func(a,b): return a.center().dot(side) < b.center().dot(side))
	var available_width := maxf(0.0,line.length() - (groups.size()-1)*FORMATION_GROUP_GAP)
	var total_width := 0.0
	for group in groups: total_width += maxf(1.2,group.formation_width)
	var layouts := {}
	var span := 0.0
	var bounds := Rect2()
	for group in groups:
		var width := maxf(1.2,available_width * maxf(1.2,group.formation_width) / total_width)
		var layout: Dictionary = group.formation_from_drag(Vector3.ZERO,side*width)
		var slots: Array[Vector3] = layout.slots
		var left := INF
		var right := -INF
		for slot in slots:
			left = minf(left,slot.dot(side))
			right = maxf(right,slot.dot(side))
		for i in slots.size():
			slots[i] += side*(span-left)
			var point := Vector2(slots[i].x,slots[i].z)
			bounds = Rect2(point,Vector2.ZERO) if layouts.is_empty() and i == 0 else bounds.expand(point)
		span += right-left+FORMATION_GROUP_GAP
		layouts[group] = layout
	var shift := (first+last)*.5 - side*(span-FORMATION_GROUP_GAP)*.5
	var limit := field_half_size-Vector2.ONE
	if bounds.size.x <= 2.0*limit.x:
		shift.x = clampf(shift.x,-limit.x-bounds.position.x,limit.x-bounds.end.x)
	if bounds.size.y <= 2.0*limit.y:
		shift.z = clampf(shift.z,-limit.y-bounds.position.y,limit.y-bounds.end.y)
	for layout in layouts.values():
		var slots: Array[Vector3] = layout.slots
		for i in slots.size():
			slots[i] = FIELD.project(slots[i]+shift)
	return layouts

func pick_soldier(screen_point: Vector2) -> CharacterBody3D:
	var origin := camera.project_ray_origin(screen_point)
	var ray := camera.project_ray_normal(screen_point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + ray * 500, 2)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.collider as CharacterBody3D
	var ground = ground_point(screen_point)
	if ground == null:
		return null
	# Gaps between warriors are part of the group click target.
	var nearest: CharacterBody3D
	var distance := 2.2 * 2.2
	for team in 2:
		# Include the neighbouring cells a rider could reach between index rebuilds.
		for soldier in combat_index.nearby(ground,team,4.2,true):
			var d: float = soldier.global_position.distance_squared_to(ground)
			if d < distance:
				distance = d
				nearest = soldier
	return nearest

func _process(_delta: float) -> void:
	for leader in [campaign_leader, rival_leader]:
		if is_instance_valid(leader) and not leader.alive and not leader.team in fallen_leader_teams:
			fallen_leader_teams.append(leader.team)
			for group in squads:
				if group.team == leader.team:
					group.morale = maxf(0.0, group.morale - 20.0)
					group.update_morale(0.0)
			leader_notice = "Наш полководец погиб" if leader.team == 0 else "Вражеский полководец погиб"
			hud.announce_commander(leader.team,leader.get_parent().display_name)

	var now := Time.get_ticks_usec()
	var delta := clampf((now-real_tick)/1000000.0,0.0,.10)
	real_tick = now
	if not deployment_move.is_empty():
		advance_deployment_move(delta)
	if result_text.is_empty():
		prepare_campaign_support()
	if not get_tree().paused:
		battle_time = minf(BATTLE_TIME_LIMIT,battle_time+delta*speed)
		if not campaign_support.is_empty() and battle_time >= REINFORCEMENT_TIME:
			bring_in_support()
	if order_marker.visible and Time.get_ticks_msec()>=order_expires: order_marker.hide()
	if not selected_squad.combat_ready():
		command_mode = 0
		right_held = false
		formation_preview.hide()
		var available := selected_groups()
		if not available.is_empty():
			selected_squad = available[-1]
	if right_held and not right_double:
		right_time += delta
		if right_pointer.distance_to(right_screen) > 9 or (right_time > .24 and selected_groups().size() == 1):
			update_formation_drag(right_pointer)
	hover_timer -= delta
	if hover_timer <= 0:
		hover_timer = .08
		var hovered := pick_soldier(get_viewport().get_mouse_position())
		overlay.hovered = hovered.get_parent() if hovered and hovered.team == 1 else null
	if not camera_locked:
		if camera_zooming:
			camera_distance = lerpf(camera_distance, camera_zoom_target, 1.0 - exp(-18.0 * delta))
			if absf(camera_distance - camera_zoom_target) < .015:
				camera_distance = camera_zoom_target
				camera_zooming = false
		var movement := Vector3.ZERO
		movement.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		movement.z = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		if movement != Vector3.ZERO:
			camera_follow = false
		if camera_follow and selected_squad.alive_count() > 0:
			var follow_target: Vector3 = selected_squad.center()
			focus = focus.lerp(follow_target, 1.0 - exp(-5.0 * delta))
		focus += movement.rotated(Vector3.UP, camera_yaw).limit_length(1.0) * camera_distance * .65 * delta
		var clamped_focus := FIELD.clamp_ground(focus, field_half_size, -5.0)
		focus.x = clamped_focus.x
		focus.z = clamped_focus.z
		camera_yaw += (float(Input.is_physical_key_pressed(KEY_Q)) - float(Input.is_physical_key_pressed(KEY_E))) * delta
		focus.y = terrain.height_at(Vector2(focus.x,focus.z))
		update_camera()
	var profile_started := Time.get_ticks_usec() if preload("res://scripts/profile_counters.gd").enabled else 0
	update_squad_standards()
	if preload("res://scripts/profile_counters.gd").enabled: preload("res://scripts/profile_counters.gd").add("banners",profile_started)
	var throw_radius: float = SQUAD.BOW_RANGE if selected_squad.uses_bows() else 20.0
	if command_mode > 0:
		var intersection = ground_point(get_viewport().get_mouse_position())
		target_ring.visible = intersection != null
		if target_ring.visible:
			var hover_point := FIELD.clamp_ground(intersection,field_half_size,1.0)
			if command_mode == 4:
				var center: Vector3 = selected_squad.center()
				hover_point = center + (hover_point-center).slide(Vector3.UP).limit_length(throw_radius)
			drape_ring(target_ring, hover_point, 1.2)
	else:
		target_ring.hide()
	range_ring.visible = command_mode == 4
	if range_ring.visible:
		drape_ring(range_ring, selected_squad.center(), throw_radius)
	ui_timer -= delta
	if ui_timer <= 0:
		ui_timer = .2
		var ours := team_in_battle(0)
		var theirs := team_in_battle(1)
		if result_text.is_empty():
			update_battle_end()
		hud.refresh(ours,theirs)

func attacking_team() -> int:
	return 1 if campaign_request.get("enemy_attack",false) else 0

func update_battle_end() -> void:
	if not result_text.is_empty(): return
	var our_side := team_holds(0)
	var their_side := team_holds(1)
	if (not our_side and campaign_support.any(func(source): return source.team == 0)) or (not their_side and campaign_support.any(func(source): return source.team == 1)):
		return
	if our_side and their_side:
		if battle_time < BATTLE_TIME_LIMIT: return
		time_expired = true
		our_side = attacking_team()==1
		their_side = not our_side
	var outcome := "draw" if our_side == their_side else ("win" if our_side else "loss")
	if not campaign_request.is_empty():
		finish_campaign_battle(outcome)
		return
	auto_battle = false
	for group in squads:
		if group.team == (0 if our_side else 1) and outcome != "draw" and group.combat_ready():
			group.celebrate()
	result_text = {"win": "ПОБЕДА", "loss": "ПОРАЖЕНИЕ", "draw": "НИЧЬЯ"}[outcome]
	set_battle_paused(true)
	pause_button.disabled = true
	show_results(outcome)

func campaign_action_pressed() -> void:
	if campaign_result.is_empty():
		if campaign_request.get("defending_city",false) or not campaign_request.get("retreat_allowed",true): return
		finish_campaign_battle("retreat")
	else:
		campaign_action.disabled = true
		campaign_battle_finished.emit(campaign_result)

func finish_campaign_battle(outcome: String) -> void:
	var survivors := {}
	var experience := {}
	for source in campaign_support:
		for unit in source.roster:
			survivors[unit.id] = unit.count
	for id in campaign_groups:
		var group: Node3D = campaign_groups[id]
		survivors[id] = group.survivor_count()
		if group.participated or outcome != "retreat":
			experience[id] = group.experience_points
	var leader_lost: bool = is_instance_valid(campaign_leader) and not campaign_leader.alive
	var rival_lost: bool = is_instance_valid(rival_leader) and not rival_leader.alive
	campaign_result = {"outcome":outcome, "survivors":survivors, "experience":experience, "leader_lost":leader_lost, "rival_leader_lost":rival_lost,"time_expired":time_expired}
	campaign_result["fallen_support"] = support_leaders.keys().filter(func(index): return not support_leaders[index].alive)
	result_text = {"win": "ПОБЕДА", "loss": "ПОРАЖЕНИЕ", "draw": "НИЧЬЯ", "retreat": "ОТСТУПЛЕНИЕ"}[outcome]
	auto_battle = false
	right_held = false
	formation_preview.hide()
	stop_camera_rotation()
	set_battle_paused(true)
	pause_button.disabled = true
	campaign_action.text = "Вернуться на карту"
	campaign_action.disabled = false
	campaign_action.tooltip_text = ""
	hud.refresh(team_in_battle(0),team_in_battle(1))
	show_results(outcome)

func update_squad_standards() -> void:
	if profiling_skip_banners: return
	for banner in banners:
		banner.world_standard.follow(banner.squad, camera)

func show_results(outcome: String) -> void:
	if is_instance_valid(battle_report): return
	finish_deployment_move()
	for group in squads:
		if group.routed: group.withdraw_fleeing_soldiers(true)
	stop_camera_rotation(false)
	right_held=false
	left_held=false
	selection_box.hide()
	order_marker.hide()
	command_mode=0
	formation_preview.hide()
	battle_report=preload("res://scripts/battle_report.gd").new()
	battle_report.world=self
	battle_report.outcome=outcome
	hud.add_child(battle_report)

func restart_battle() -> void:
	get_tree().paused=false
	Engine.time_scale=1
	get_tree().reload_current_scene()
