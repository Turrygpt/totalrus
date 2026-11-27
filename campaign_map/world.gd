extends Node3D

const FogOfWar = preload("res://campaign_map/fog_of_war.gd")
const WorldWeather = preload("res://scripts/world_weather.gd")
const Geo = preload("res://campaign_map/geography.gd")
const Landscape = preload("res://campaign_map/terrain.gd")
const HORSEMAN = preload("res://scenes/horseman.tscn")
const BATTLE_SCENE := "res://scenes/battlefield.tscn"
const Forces = preload("res://campaign_map/forces.gd")
const MarchNavigation = preload("res://campaign_map/march_navigation.gd")
const BattleLoading = preload("res://campaign_map/battle_loading.gd")
const EnemyTurn = preload("res://campaign_map/enemy_turn.gd")
const CampaignState = preload("res://campaign_map/campaign_state.gd")
const CampaignSave = preload("res://campaign_map/campaign_save.gd")
const CampaignPanel = preload("res://campaign_map/campaign_panel.gd")
const UI = preload("res://campaign_map/ui_theme.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")
const MapPin = preload("res://campaign_map/ui_map_pin.gd")
const TurnSeal = preload("res://campaign_map/ui_turn_seal.gd")
const EncounterUI = preload("res://campaign_map/campaign_encounter.gd")
const CAMPAIGN_TRACKS: Array[AudioStream] = [
	preload("res://assets/music/campaign/frontier_map.mp3"),
	preload("res://assets/music/campaign/fifth_of_the_storm.mp3"),
	preload("res://assets/music/campaign/wistful_rus_march.mp3"),
	preload("res://assets/music/campaign/wistful_rus_campaign.mp3"),
]
const MOVE_PER_TURN := 190.2285
const START_YEAR := 879
const START_MONTH_INDEX := 4
const MIN_MAP_ZOOM := 180.0
const DEFAULT_MAP_ZOOM := 485.0
const MAX_MAP_ZOOM := 1110.0
const MONTH_NAMES := ["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"]
const MONTH_SEASONS := [3,3,3,3,0,1,1,1,2,2,3,3]
const WINTER := 3
const SAVE_FILE := "user://rus_campaign_v1.save"
const CREAM := Color("#eee3c7")
const GOLD := Color("#e7be80")
const MUTED := Color("#b6baa4")
const PROVINCE_LABELS := [Vector2(-241,-150),Vector2(-228,-62),Vector2(-168,72),Vector2(147,206)]

enum StoryStage { NONE, CAPTURE_LADOGA, CAPTURE_RUSSA, CAPTURE_KHOLM, CAPTURE_SMOLENSK, CAPTURE_ORSHA, ORSHA_CAPTURED }

const SMOLENSK_CHAPTER := "Путь на Днепр"
const STORY_ORDERS := {
	StoryStage.CAPTURE_LADOGA: {
		"city":"ladoga",
		"title":"Захватить Ладогу",
		"speech":"Олег · «Ладожский воевода взбунтовался. С ним сотня ополченцев и три десятка всадников. Веди дружину к Ладоге и возьми город».",
		"defender_faction":Geo.REBELS,
		"reply":"Ладожский воевода · «Ладожане встали со мной. Скажи Олегу, что ключей от города я ему не отдам».",
	},
	StoryStage.CAPTURE_RUSSA: {
		"city":"russa",
		"title":"Захватить Старую Руссу",
		"speech":"Олег · «Ладога наша. Теперь веди дружину к Руссе. Возьмём город и закрепимся на южном берегу Ильменя».",
		"defender_faction":Geo.STARTING_OWNERS.russa,
		"reply":"Старейшина Руссы · «Ладога за Ильменем. Здесь наши дома и соляные варницы. Коли Олег пришёл за Руссой, пусть сперва минует наши ворота».",
	},
	StoryStage.CAPTURE_KHOLM: {
		"city":"kholm",
		"title":"Захватить Холм",
		"speech":"Олег · «Руссу взяли. В Новгородской земле остался Холм. Возьми город и поставь дозоры на дороге к Руссе».",
		"defender_faction":Geo.STARTING_OWNERS.kholm,
		"reply":"Холмский воевода · «Из Руссы пришли беженцы. Мы укрыли их за частоколом. Мои люди останутся у ворот, пока не уведут семьи в лес».",
	},
	StoryStage.CAPTURE_SMOLENSK: {
		"city":"smolensk",
		"title":"Захватить Смоленск",
		"speech":"Олег · «У Холма дружина отдохнула. Теперь идём к Днепру. Я послал к Твердиславу гонца. Если ворота останутся заперты, возьми Смоленск силой».",
		"defender_faction":Geo.STARTING_OWNERS.smolensk,
		"reply":"Твердислав · «Я выслушал твоего гонца, Олег. Я обещал смолянам, что чужую дружину в город не пущу. Захочешь войти — ищи брешь в стене».",
	},
	StoryStage.CAPTURE_ORSHA: {
		"city":"orsha",
		"title":"Захватить Оршу",
		"speech":"Олег · «Смоленск взят. Теперь идём вниз по Днепру к Орше. Я предложил воеводе вывести дружину из города. Если он откажется, бери Оршу».",
		"defender_faction":Geo.STARTING_OWNERS.orsha,
		"reply":"Оршанский воевода · «Твой гонец передал мне твои условия, Олег. Я обещал держать Оршу, пока Твердислав сам не велит сложить оружие. Его слова я ещё не слышал».",
	},
}

var terrain: Landscape
var fog := FogOfWar.new()
var fog_timer := 0.0
var last_visibility := 0
var camera: Camera3D
var map_sun: DirectionalLight3D
var map_weather := WorldWeather.new()
var focus := Vector3(85,0,-249)
var zoom := DEFAULT_MAP_ZOOM
var dragging := false
var attack_cursor: ImageTexture
var attack_cursor_visible := false
var army_positions: Array[Vector2] = []
var armies: Array[Node3D] = []
var riders: Array[Node3D] = []
var city_buttons := {}
var army_buttons: Array[Button] = []
var province_labels: Array[Label] = []
var rebel_pieces := {}
var territory_borders: RefCounted
var water_labels: Array[Label] = []
var markers: Control
var status: Label
var turn_label: Label
var turn_button: Button
var serif: Font

var selected_city := ""
var selected_army := 0
var commanded_army := 0
var other_marches := {}
var announced_turn := 0
var construction_warning: ConfirmationDialog
var research_warning_button: Button
var construction_warning_button: Button
var retreat_turns := {}
var current_city := "novgorod"
var destination := ""
var has_route := false
var march_preview := false
var march_notice := ""
var march_obstacle: Variant = null
var march_origin := Vector2.ZERO
var march_origin_city := ""
var navigation: RefCounted
var navigation_thread: Thread
var pending_march := {}
var path := PackedVector2Array()
var distance_marks := PackedFloat32Array()
var traveled := 0.0
var movement := MOVE_PER_TURN
var travel_goal := 0.0
var turn := 1
var route_visual: Node3D
var forces := Forces.new()
var campaign := CampaignState.new()
var story_stage: int = StoryStage.CAPTURE_LADOGA
var management: Control
var battle_menu: PanelContainer
var battle_loading := false
var pending_capture := ""
var campaign_defeated := false
var save_file := SAVE_FILE
var control_rings: Array[MeshInstance3D] = []
var destination_army := -1
var encounter: Dictionary = {}
var battle_summary: Dictionary = {}
var enemy_actor := 0
var enemy_plan: Dictionary = {}
var enemy_operations: Dictionary = {}
var enemy_step := 1
var enemy_budget := 0.0
var enemy_delay := 0.0
var enemy_acted := false
var campaign_music: AudioStreamPlayer
var remaining_campaign_tracks: Array[AudioStream] = []
var campaign_music_position := 0.0

func _ready() -> void:
	get_viewport().use_taa = true
	setup_ladoga()
	name_existing_squads()
	make_scene()
	prepare_navigation()
	campaign.fishing_shores = terrain.fishing_shores
	fog.attach(terrain,camera)
	update_fog(true)
	make_ui()
	add_campaign_panel()
	make_regional_boundaries()
	for city in Geo.CITIES:
		refresh_garrison(city)
	sync_settlement_models()
	focus_player()
	terrain.load_visible_settlement()
	project_markers()
	campaign_music = AudioStreamPlayer.new()
	campaign_music.name = "CampaignMusic"
	campaign_music.volume_db = -16.0
	add_child(campaign_music)
	campaign_music.finished.connect(play_next_campaign_track)
	play_next_campaign_track()

func play_next_campaign_track() -> void:
	if remaining_campaign_tracks.is_empty():
		remaining_campaign_tracks.assign(CAMPAIGN_TRACKS)
		remaining_campaign_tracks.shuffle()
		var last_index := remaining_campaign_tracks.size() - 1
		if remaining_campaign_tracks[last_index] == campaign_music.stream:
			remaining_campaign_tracks[last_index] = remaining_campaign_tracks[0]
			remaining_campaign_tracks[0] = campaign_music.stream
	campaign_music.stream = remaining_campaign_tracks.pop_back()
	campaign_music.play()

func setup_ladoga() -> void:
	var town: Dictionary = campaign.cities.ladoga
	town.owner = Geo.REBELS
	town.rebel = true
	town.order = -100
	forces.holdings.erase("ladoga")
	var defenders := forces.roster("ladoga_rebels",[
		["light_cavalry",30],["militia",45],["militia",45],["militia",10],
	])
	Forces.normalize_units(defenders)
	forces.garrisons.ladoga = defenders
	campaign.note("Бунтовщики удерживают Ладогу. Олегу предстоит взять город.")

func name_existing_squads() -> void:
	var starting_cities := {"ladoga":"ladoga"}
	for index in Geo.ARMIES.size():
		starting_cities[Geo.ARMIES[index].id] = Geo.army_home(index)
	for index in forces.armies.size():
		for unit in forces.armies[index]:
			var prefix := String(unit.id).get_slice("_",0)
			campaign.name_squad(unit,starting_cities.get(prefix,Geo.army_home(index)))
	for city in forces.garrisons:
		for unit in forces.garrisons[city]:
			var prefix := String(unit.id).get_slice("_",0)
			campaign.name_squad(unit,starting_cities.get(prefix,city))
	for city in campaign.rebellions:
		for unit in campaign.rebellions[city].roster:
			campaign.name_squad(unit,city)
	for queue in campaign.recruitment:
		for order in queue:
			campaign.name_squad(order.unit,order.city)

func prepare_navigation() -> void:
	navigation = MarchNavigation.new(terrain)
	navigation_thread = Thread.new()
	if navigation_thread.start(navigation.build_graph) != OK:
		navigation_thread = null
		navigation.build_graph()

func ensure_navigation() -> void:
	if navigation == null: prepare_navigation()
	if navigation_thread == null: return
	navigation_thread.wait_to_finish()
	navigation_thread = null

func make_scene() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#bdcad2")
	environment.ambient_light_energy = 0.37
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_light_energy = .8
	environment.fog_density = .6
	environment.fog_depth_curve = 1.7
	environment.ssao_enabled = true
	environment.ssao_radius = 1.8
	environment.ssao_intensity = 1.1
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	map_sun = sun
	sun.rotation_degrees = Vector3(-9,164,0)
	sun.light_energy = 1.25
	sun.light_angular_distance = .6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1050
	add_child(sun)
	map_weather.install(self,environment,sun,1.05)
	map_weather.set_weather(WorldWeather.for_turn(turn,campaign_season()),campaign_season())
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 40.0
	camera.near = 1.0
	camera.far = 3200
	add_child(camera)
	terrain = Landscape.new()
	add_child(terrain)
	route_visual = Node3D.new()
	add_child(route_visual)
	for i in Geo.ARMIES.size():
		make_army_piece(i,camp_on_land(Geo.army_home(i),i))

func make_army_piece(i: int, p: Vector2) -> void:
	var faction: Dictionary = Geo.FACTIONS[Geo.army_faction(i)]
	var piece := Node3D.new()
	add_child(piece)
	armies.append(piece)
	army_positions.append(p)
	piece.position = terrain.surface(p,0.30)
	var radius := 6.35 if i == 0 else 4.45
	var aura_mesh := SphereMesh.new()
	aura_mesh.radius = 1.0
	aura_mesh.height = 2.0
	aura_mesh.radial_segments = 32
	aura_mesh.rings = 16
	var aura_material := ShaderMaterial.new()
	aura_material.shader = preload("res://campaign_map/hero_aura.gdshader")
	aura_mesh.material = aura_material
	var aura: MeshInstance3D = terrain.place_mesh(aura_mesh,Vector3.UP*radius*.36,piece)
	aura.scale = Vector3(1.42,.58,1.14)*radius
	aura.name = "SelectionAura"
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	aura.visible = i==selected_army
	var rim := TorusMesh.new()
	rim.inner_radius = radius-0.14
	rim.outer_radius = radius+0.04
	rim.rings = 40
	rim.ring_segments = 8
	rim.material = terrain.material(faction.color,true)
	var foot_ring: MeshInstance3D = terrain.place_mesh(rim,Vector3.UP*0.15,piece)
	foot_ring.scale.y = .2
	foot_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rider := HORSEMAN.instantiate() as Node3D
	piece.add_child(rider)
	rider.scale = Vector3.ONE*rider_scale(i)
	rider.position.y = 0.36
	rider.rotation_degrees.y = 66.0
	riders.append(rider)
	var range_mesh := TorusMesh.new()
	var range_radius := 12.5 if i>0 else 17.0
	range_mesh.inner_radius = range_radius-.15
	range_mesh.outer_radius = range_radius+.15
	range_mesh.rings = 48
	range_mesh.ring_segments = 4
	range_mesh.material = terrain.material(faction.color.lightened(.25),true)
	var range_ring: MeshInstance3D = terrain.place_mesh(range_mesh,Vector3.UP*0.5,piece)
	range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	control_rings.append(range_ring)
	var pole: Material = terrain.material(Color("#b19261"))
	var pole_height := 28.5 if i == 0 else 19.2
	var pole_x := -radius*0.55
	terrain.box(Vector3(0.27,pole_height,0.27),pole,Vector3(pole_x,pole_height*0.5,-2.2),piece)
	var cloth := PlaneMesh.new()
	cloth.orientation = PlaneMesh.FACE_Z
	cloth.subdivide_width = 8
	cloth.subdivide_depth = 10
	cloth.size = Vector2(5.3,7.7)
	var fabric := ShaderMaterial.new()
	fabric.shader = preload("res://campaign_map/standard.gdshader")
	fabric.set_shader_parameter("fabric",UI.faction_flag(Geo.army_faction(i)))
	cloth.material = fabric
	terrain.place_mesh(cloth,Vector3(pole_x-2.5,pole_height-4.5,-2.2),piece)


func rider_scale(index: int) -> float:
	return 9.3 if index == 0 else 6.1

func update_camera() -> void:
	var close_angle := smoothstep(111.0,175.0,zoom)
	camera.fov = lerpf(46.0,40.0,close_angle)
	var close_tilt := lerpf(10.0,39.0,close_angle)
	var angle := deg_to_rad(lerpf(close_tilt,62.0,smoothstep(160.0,1000.0,zoom)))
	var distance := zoom / (2.0*tan(deg_to_rad(camera.fov)*.5))
	var offset := Vector3(0,sin(angle),cos(angle))*distance
	var camera_point := focus + offset
	camera_point.y = maxf(camera_point.y,terrain.surface(Vector2(camera_point.x,camera_point.z),4.0).y)
	camera.position = camera_point
	camera.look_at(focus)
	camera.size = zoom
	map_sun.directional_shadow_max_distance = minf(1450.0,distance+zoom*.65)
	map_weather.update_view(camera,1.0-smoothstep(108.0,225.0,zoom),distance+zoom*.20,distance+zoom*1.75)
	var scale_factor := lerpf(1.0,1.48,smoothstep(220.0,895.0,zoom))
	for i in armies.size():
		armies[i].scale = Vector3.ONE*scale_factor
		control_rings[i].scale = Vector3.ONE/scale_factor

func _process(delta: float) -> void:
	if navigation_thread != null and not navigation_thread.is_alive():
		ensure_navigation()
	if navigation_thread == null and not pending_march.is_empty():
		var order := pending_march
		pending_march = {}
		march_notice = ""
		if player_orders_allowed() and not forces.armies[commanded_army].is_empty():
			var point: Vector2 = army_positions[order.army] if order.army > 0 else order.point
			start_march(point,order.city,order.army,order.confirmed)
	update_attack_cursor()
	fog_timer -= delta
	var fog_updated := fog_timer <= 0.0
	if fog_updated:
		fog_timer = .18
		update_fog()
	if campaign_defeated or not encounter.is_empty() or not pending_capture.is_empty() or (battle_menu.visible and not battle_summary.is_empty()):
		return
	var pan := Vector2(
		float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	if pan != Vector2.ZERO and not (is_instance_valid(management) and management.details.visible):
		move_camera(pan.normalized()*zoom*delta*0.60)
	if enemy_actor > 0:
		advance_enemy_turn(delta)
		project_markers()
		return
	if traveled < travel_goal:
		if fog_updated:
			var remaining_path := path.slice(segment_index(traveled)+1)
			remaining_path.insert(0,army_positions[commanded_army])
			var obstacle: Variant = find_march_obstacle(remaining_path,destination,destination_army)
			if obstacle != null:
				movement += travel_goal-traveled
				travel_goal = traveled
				has_route = false
				if traveled > 0.01: current_city = ""
				destination = ""
				destination_army = -1
				riders[commanded_army].set_gait(&"Idle")
				draw_route()
				report_march_obstacle(obstacle)
				project_markers()
				return
		traveled = minf(travel_goal,traveled+delta*74.0)
		var p := route_position(traveled)
		var heading := route_position(minf(traveled+1.0,distance_marks[-1]))-p
		if heading.length_squared() > 0.01:
			riders[commanded_army].rotation.y = lerp_angle(riders[commanded_army].rotation.y,atan2(heading.x,heading.y),minf(delta*10.0,1.0))
		army_positions[commanded_army] = p
		armies[commanded_army].position = terrain.surface(p,0.28)
		armies[commanded_army].position.y = maxf(armies[commanded_army].position.y,Landscape.WATER_LEVEL+0.75)
		if traveled >= travel_goal:
			riders[commanded_army].set_gait(&"Idle")
			if traveled >= distance_marks[-1]-0.01:
				arrive()
			draw_route()
			refresh_ui()
	project_markers()

func move_camera(amount: Vector2) -> void:
	focus.x = clampf(focus.x+amount.x,-Landscape.HALF.x+18,Landscape.HALF.x-18)
	focus.z = clampf(focus.z+amount.y,-Landscape.HALF.y+18,Landscape.HALF.y-18)
	update_camera()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		dragging = false

func _unhandled_input(event: InputEvent) -> void:
	if not encounter.is_empty():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				pick_map_object(event.position,event.button_index == MOUSE_BUTTON_RIGHT)
			MOUSE_BUTTON_MIDDLE:
				dragging = true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var factor := 0.87 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.15
				zoom = clampf(zoom*factor,MIN_MAP_ZOOM,MAX_MAP_ZOOM)
				update_camera()
	elif event is InputEventMouseMotion and dragging:
		var ratio := zoom/get_viewport().get_visible_rect().size.y
		move_camera(-event.relative*Vector2(ratio,ratio*1.26))
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_HOME:
		overview()

func pick_map_object(mouse: Vector2, march: bool) -> void:
	var index := pick_map_army(mouse,march)
	if index >= 0:
		if march: attack_army(index)
		else: select_army(index)
		return
	var city := pick_map_city(mouse)
	if not city.is_empty():
		if march: order_to(city)
		else: select_city(city)
	elif march:
		var point: Variant = pick_ground(mouse)
		if point is Vector2: order_to_point(point)

func pick_map_army(mouse: Vector2, hostile_only: bool) -> int:
	for i in armies.size():
		if not armies[i].visible or not can_see_army(i) or (hostile_only and is_player_army(i)):
			continue
		var screen := camera.unproject_position(armies[i].position+Vector3.UP*rider_scale(i)*1.1)
		if screen.distance_to(mouse) < 34.0:
			return i
	return -1

func pick_map_city(mouse: Vector2) -> String:
	var closest := ""
	var radius := 33.0
	for id in Geo.CITIES:
		if not fog.visible_at(Geo.position_of(id)): continue
		var location: Vector3 = terrain.surface(Geo.position_of(id),1.3)
		var distance := camera.unproject_position(location).distance_to(mouse)
		if distance < radius:
			radius = distance
			closest = id
	return closest

func update_attack_cursor() -> void:
	var attacking := false
	if player_orders_allowed() and not dragging and not forces.armies[commanded_army].is_empty() and campaign.stances[commanded_army] != "forced" and not battle_menu.visible:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered is Button and hovered in army_buttons:
			attacking = not is_player_army(army_buttons.find(hovered))
		elif hovered is MapPin and hovered in city_buttons.values():
			attacking = can_attack_city(city_buttons.find_key(hovered))
		elif hovered == null:
			var mouse := get_viewport().get_mouse_position()
			attacking = pick_map_army(mouse,true) >= 0
			if not attacking:
				var city := pick_map_city(mouse)
				attacking = not city.is_empty() and can_attack_city(city)
	set_attack_cursor(attacking)

func set_attack_cursor(enabled: bool) -> void:
	if attack_cursor_visible == enabled: return
	attack_cursor_visible = enabled
	if enabled and attack_cursor == null:
		var image := Image.new()
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34"><path fill="#fff4dd" stroke="#261e1b" stroke-width="1.5" d="M1 1v19l5-5 4 8 4-2-4-8h8z"/><path fill="#eb8e76" stroke="#261e1b" stroke-width="1.5" d="m16 26 4-4-3-3 2-2 3 2 9-9 2-1-1 5-8 8 3 3-2 2-3-3-4 5z"/></svg>')
		attack_cursor = ImageTexture.create_from_image(image)
	for shape in [Input.CURSOR_ARROW,Input.CURSOR_POINTING_HAND]:
		Input.set_custom_mouse_cursor(attack_cursor if enabled else null,shape)

func _exit_tree() -> void:
	if navigation_thread != null: ensure_navigation()
	set_attack_cursor(false)

func pick_ground(screen: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var distance := maxf(0.0,(origin.y-45.0)/-direction.y)
	var previous := distance
	while origin.y + direction.y*distance > -3.0:
		var hit := origin+direction*distance
		var point := Vector2(hit.x,hit.z)
		if absf(point.x) < Landscape.HALF.x and absf(point.y) < Landscape.HALF.y:
			if hit.y <= maxf(terrain.surface(point).y,Landscape.WATER_LEVEL):
				for i in 8:
					var middle := (previous+distance)*0.5
					var check := origin+direction*middle
					var height: float = maxf(terrain.surface(Vector2(check.x,check.z)).y,Landscape.WATER_LEVEL)
					if check.y > height:
						previous = middle
					else:
						distance = middle
				var intersection := origin+direction*distance
				return Vector2(intersection.x,intersection.z)
		previous = distance
		distance += 2.0
	return null

func overview() -> void:
	focus = Vector3(0,0,150)
	zoom = MAX_MAP_ZOOM
	update_camera()

func select_city(id: String) -> void:
	if not fog.visible_at(Geo.position_of(id)): return
	selected_city = id
	refresh_ui()
	if is_instance_valid(management) and management.details.visible:
		management.close_details()

func select_army(index: int) -> void:
	if not can_see_army(index): return
	if is_player_army(index) and index != commanded_army:
		if not player_orders_allowed(): return
		command_army(index)
	selected_army = index
	selected_city = ""
	refresh_ui()
	if is_instance_valid(management) and management.details.visible:
		management.close_details()

func attack_army(index: int, confirm_now := false) -> void:
	if not is_player_army(index) and armies[index].visible and can_see_army(index):
		order_to(region_at(army_positions[index]),index,confirm_now)

func is_player_army(index: int) -> bool:
	return index == 0 or (index >= Geo.ARMIES.size() and index < forces.armies.size())

func command_army(index: int) -> void:
	if index == commanded_army: return
	other_marches[commanded_army] = march_state()
	commanded_army = index
	var state: Dictionary = other_marches.get(index,{"city":forces.stations[index],"movement":MOVE_PER_TURN*stance_movement()})
	other_marches.erase(index)
	restore_march(state)
	draw_route()

func recruit_hero(city: String) -> bool:
	if not player_orders_allowed(): return false
	var leader := campaign.hire_hero(city)
	if leader.is_empty(): return false
	var index := forces.armies.size()
	var roster := forces.roster(leader.family_id,[["princely",CampaignState.UNITS.princely[1]]])
	campaign.name_squad(roster[0],city)
	forces.armies.append(roster)
	forces.stations.append(city)
	make_army_piece(index,camp_on_land(city,index))
	make_army_pin(index)
	select_army(index)
	focus_at(army_positions[index])
	update_fog(true)
	refresh_ui()
	return true

func order_to(id: String, target_army := -1, confirm_now := false) -> void:
	if not player_orders_allowed() or forces.armies[commanded_army].is_empty():
		return
	march_obstacle = null
	if campaign.stances[commanded_army]=="forced" and (target_army>0 or can_attack_city(id)):
		pending_march.clear()
		march_notice = "В форсированном марше атаковать нельзя"
		refresh_ui()
		return
	var target := army_positions[target_army] if target_army > 0 else Geo.position_of(id)
	if target_army < 0 and id == current_city:
		if not can_attack_city(id):
			if not pending_march.is_empty(): march_notice = ""
			pending_march.clear()
			clear_march_preview()
			refresh_ui()
			return
		target = army_positions[commanded_army]
	start_march(target,id,target_army,confirm_now)

func order_to_point(point: Vector2) -> void:
	if not player_orders_allowed() or forces.armies[commanded_army].is_empty():
		return
	start_march(point,"",-1)

func same_march_target(point: Vector2, city: String, target_army: int, old_point: Vector2, old_city: String, old_army: int) -> bool:
	if target_army != old_army: return false
	if target_army > 0: return true
	return city == old_city and (not city.is_empty() or point.distance_squared_to(old_point) <= 36.0)

func clear_march_preview() -> void:
	if not march_preview: return
	march_preview = false
	has_route = false
	destination = ""
	destination_army = -1
	march_notice = ""
	draw_route()

func start_march(point: Vector2, city: String, target_army: int, confirm_now := false) -> void:
	if not pending_march.is_empty() and same_march_target(point,city,target_army,pending_march.point,pending_march.city,pending_march.army):
		confirm_now = true
		point = pending_march.point
	if navigation_thread != null and navigation_thread.is_alive():
		pending_march = {"point":point,"city":city,"army":target_army,"confirmed":confirm_now}
		march_notice = "Прокладываем маршрут…"
		refresh_ui()
		return
	ensure_navigation()
	pending_march.clear()
	march_obstacle = null
	var from := army_positions[commanded_army]
	if has_route and not path.is_empty() and same_march_target(point,city,target_army,path[-1],destination,destination_army):
		if target_army <= 0 or point.is_equal_approx(path[-1]):
			var remaining := path.slice(segment_index(traveled)+1) if path.size()>1 else PackedVector2Array()
			remaining.insert(0,from)
			var blocker: Variant = find_march_obstacle(remaining,city,target_army)
			if blocker != null:
				clear_march_preview()
				report_march_obstacle(blocker)
				return
			confirm_march()
			return
		confirm_now = true
	var next_path: PackedVector2Array = navigation.route(from,point)
	if from.is_equal_approx(point) and not city.is_empty():
		next_path = PackedVector2Array([from])
	elif next_path.size() < 2:
		clear_march_preview()
		march_notice = "Сюда нет прохода" if not from.is_equal_approx(point) else ""
		refresh_ui()
		return
	var alternative: PackedVector2Array = navigation.direct_route(from,point)
	if alternative == next_path:
		alternative.clear()
	var obstacle: Variant = find_march_obstacle(next_path,city,target_army)
	if obstacle != null and not alternative.is_empty() and find_march_obstacle(alternative,city,target_army) == null:
		next_path = alternative
		obstacle = null
	if obstacle != null:
		clear_march_preview()
		report_march_obstacle(obstacle)
		return
	march_origin = army_positions[commanded_army]
	march_origin_city = current_city if not has_route or march_preview else ""
	has_route = true
	march_preview = not confirm_now
	march_notice = ""
	destination = city
	destination_army = target_army
	selected_army = target_army if target_army > 0 else commanded_army
	selected_city = "" if target_army > 0 else city
	battle_summary.clear()
	path = next_path
	distance_marks = PackedFloat32Array([0.0])
	for i in range(1,path.size()):
		distance_marks.append(distance_marks[-1]+navigation.segment_cost(path[i-1],path[i]))
	traveled = 0.0
	travel_goal = 0.0
	if march_preview:
		draw_route()
		refresh_ui()
	else:
		confirm_march()

func confirm_march() -> void:
	march_preview = false
	march_notice = ""
	if path.size() == 1:
		arrive()
		draw_route()
		refresh_ui()
		return
	begin_leg()

func find_march_obstacle(points: PackedVector2Array, city: String, target_army: int) -> Variant:
	var defending_army := city_guard(city) if not city.is_empty() and can_attack_city(city) else -1
	var blockers := {}
	for rival in range(1,Geo.ARMIES.size()):
		if rival != target_army and rival != defending_army and armies[rival].visible and can_see_army(rival):
			blockers[rival] = Vector3(army_positions[rival].x,army_positions[rival].y,12.5)
	for id: String in Geo.CITIES:
		var pos := Geo.position_of(id)
		if id != city and can_attack_city(id) and fog.explored_at(pos):
			var radius := 12.0 if Geo.CITIES[id][3] else 8.0
			blockers[id] = Vector3(pos.x,pos.y,radius)
	for i in range(1,points.size()):
		var first: Variant = null
		var nearest := INF
		for id in blockers:
			var blocker: Vector3 = blockers[id]
			var center := Vector2(blocker.x,blocker.y)
			if points[0].distance_squared_to(center) <= blocker.z*blocker.z:
				continue
			var hit := Geometry2D.segment_intersects_circle(points[i-1],points[i],center,blocker.z)
			if hit >= 0.0 and hit < nearest:
				nearest = hit
				first = id
		if first != null:
			return first
	return null

func report_march_obstacle(obstacle: Variant) -> void:
	march_obstacle = obstacle
	if obstacle is int:
		march_notice = "Путь перекрыт · воевода %s" % campaign.leaders[obstacle].name
	else:
		march_notice = "Путь перекрыт · город %s" % Geo.CITIES[obstacle][0]
	refresh_ui()

func can_attack_city(id: String) -> bool:
	return campaign.cities[id].rebel or campaign.owner(id) != 0

func region_at(point: Vector2) -> String:
	return campaign.region_at(point,terrain.province_at(point))

func player_orders_allowed() -> bool:
	return not campaign_defeated and enemy_actor == 0 and traveled >= travel_goal and encounter.is_empty() and pending_capture.is_empty()

func arrive() -> void:
	var id := destination
	var opposing_army := destination_army
	destination = ""
	destination_army = -1
	has_route = false
	march_preview = false
	if id.is_empty():
		current_city = ""
		return
	if opposing_army < 0 and campaign.rebellions.has(id):
		queue_rebellion(id)
		return
	var city_battle := opposing_army < 0 and can_attack_city(id)
	if city_battle:
		opposing_army = city_guard(id)
	if (opposing_army > 0 or city_battle) and queue_battle(id,opposing_army,city_battle):
		return
	if city_battle:
		capture_city(id)
	if city_battle or opposing_army < 0:
		set_player_camp(id)
	else:
		current_city = ""

func city_guard(id: String, limit := EnemyTurn.GUARD_RANGE) -> int:
	if campaign.cities[id].rebel:
		return -1
	var position := Geo.position_of(id)
	var nearest := limit * limit
	var guard := -1
	for index in range(1,armies.size()):
		if not armies[index].visible or Geo.army_faction(index) != campaign.owner(id):
			continue
		var distance := army_positions[index].distance_squared_to(position)
		if distance <= nearest:
			nearest = distance
			guard = index
	return guard

func queue_battle(city: String, opposing_army: int, city_battle: bool, enemy_attack := false, sortie := false) -> bool:
	var garrison: Array = mobilize_city(city) if city_battle else []
	var opposition := garrison.duplicate()
	if city_battle and not sortie and not garrison.is_empty():
		opposing_army = -1
	elif city_battle and not sortie and opposing_army < 0:
		opposing_army = city_guard(city,EnemyTurn.ARMY_SUPPORT_RANGE)
	if opposing_army > 0:
		opposition.append_array(forces.armies[opposing_army])
	var target: String = Geo.CITIES[city][0] if city_battle else campaign.leaders[opposing_army].name
	var title := "Бой за город · %s" % target if city_battle else "Полевое сражение · %s" % target
	if enemy_attack:
		title = ("Вылазка гарнизона · %s" if sortie else "Оборона дружины · %s") % target
	encounter = {
		"city": city, "army": opposing_army, "city_battle": city_battle, "enemy_attack": enemy_attack,
		"target": target, "title": title, "garrison": garrison,
		"attackers": forces.armies[commanded_army], "defenders": opposition,
		"fortified": city_battle and not sortie and campaign.building_level(city,"wall") > 0, "sortie":sortie,
		"ram": campaign.sieges.get(city,{}).get("ram",0) >= 2,
	}
	if not gather_battle_support():
		encounter = {}
		return false
	set_encounter_identity()
	show_battle_menu.call_deferred()
	return true

func nearby_battle_sources() -> Array[Dictionary]:
	ensure_navigation()
	var sources: Array[Dictionary] = []
	var at_city: bool = encounter.city_battle or encounter.get("rebellion",false)
	var point := Geo.position_of(encounter.city) if at_city else army_positions[commanded_army]
	for city in Geo.CITIES:
		if (at_city and city == encounter.city) or not EnemyTurn.within_support_range(navigation,Geo.position_of(city),point,EnemyTurn.CITY_SUPPORT_RANGE):
			continue
		var faction := Geo.REBELS if campaign.cities[city].rebel else campaign.owner(city)
		sources.append({"city":city,"faction":faction})
	for index in armies.size():
		if index == encounter.army or (index == commanded_army and encounter.get("player_field",true)): continue
		if not armies[index].visible or forces.armies[index].is_empty(): continue
		if EnemyTurn.within_support_range(navigation,army_positions[index],point,EnemyTurn.ARMY_SUPPORT_RANGE):
			sources.append({"army":index,"faction":Geo.army_faction(index),
				"name":campaign.leaders[index].name,"portrait":campaign.leader_portrait(index)})
	return sources

func gather_battle_support() -> bool:
	var rival_faction := encounter_rival_faction()
	var candidates := nearby_battle_sources()
	encounter["support"] = []
	for team in 2:
		var faction := 0 if team == 0 else rival_faction
		var side := "attackers" if team == 0 else "defenders"
		var opening := forces.headcount(encounter[side]) == 0
		var has_support := false
		for source in candidates:
			if source.faction != faction: continue
			if source.has("city"):
				if campaign.cities[source.city].rebel or campaign.sieges.has(source.city): continue
				var garrison: Array = forces.garrisons.get(source.city,[])
				if forces.headcount(garrison) + campaign.militia_reserve(source.city,garrison,turn) <= 0: continue
			elif forces.headcount(forces.armies[source.army]) <= 0:
				continue
			source.merge({"team":team,"opening":opening})
			encounter.support.append(source)
			has_support = true
		if opening and not has_support:
			return false
	for source in encounter.support:
		var roster: Array = mobilize_city(source.city) if source.has("city") else forces.armies[source.army]
		source["roster"] = roster.duplicate(true)
		var side := "attackers" if source.team == 0 else "defenders"
		encounter[side] = encounter[side]+roster
	return true

func validate_saved_battle_support() -> void:
	var support: Array = encounter.get("support",[])
	if support.is_empty(): return
	var nearby := {}
	for source in nearby_battle_sources():
		if source.has("city") and (campaign.cities[source.city].rebel or campaign.sieges.has(source.city)):
			continue
		var id: Variant = source.get("city",source.get("army"))
		nearby[id] = source.faction
	var rival_faction := encounter_rival_faction()
	for source in support.duplicate():
		var id: Variant = source.get("city",source.get("army"))
		if nearby.get(id,-1) == (0 if source.team == 0 else rival_faction): continue
		var side := "attackers" if source.team == 0 else "defenders"
		var removed := {}
		for unit in source.roster: removed[unit.id] = true
		encounter[side] = encounter[side].filter(func(unit): return not removed.has(unit.id))
		support.erase(source)
	if forces.headcount(encounter.attackers) == 0 or forces.headcount(encounter.defenders) == 0:
		if encounter.get("defending_city",false) and forces.headcount(encounter.attackers) == 0:
			lose_city(encounter.city,encounter.army)
		encounter = {}

func queue_city_defense(city: String, rival: int) -> void:
	var garrison := mobilize_city(city)
	var defender := nearest_player_army(Geo.position_of(city),EnemyTurn.ARMY_SUPPORT_RANGE)
	var field_army := garrison.is_empty() and defender >= 0
	if field_army: command_army(defender)
	var troops := garrison.duplicate()
	if field_army: troops.append_array(forces.armies[commanded_army])
	encounter = {"city":city,"army":rival,"city_battle":true,"enemy_attack":true,"defending_city":true,
		"fortified":campaign.building_level(city,"wall") > 0,"ram":false,
		"target":Geo.CITIES[city][0],"title":"Оборона города · "+Geo.CITIES[city][0],"garrison":garrison,
		"attackers":troops,"defenders":forces.armies[rival],"player_field":field_army}
	if not gather_battle_support():
		encounter = {}
		lose_city(city,rival)
		update_faction_defeats()
		if campaign_defeated: show_battle_menu()
		return
	set_encounter_identity()
	show_battle_menu.call_deferred()

func encounter_rival_faction() -> int:
	if encounter.get("rebellion",false) or (encounter.city_battle and campaign.cities[encounter.city].rebel and not encounter.get("defending_city",false)):
		return Geo.REBELS
	return Geo.army_faction(encounter.army) if encounter.army > 0 else campaign.owner(encounter.city)

func set_encounter_identity() -> void:
	encounter["landscape"] = battle_landscape()
	encounter["besieged_city"] = ""
	if encounter.enemy_attack and not encounter.city_battle:
		for city in campaign.sieges:
			if campaign.sieges[city].get("army",0) != commanded_army: continue
			if army_positions[commanded_army].distance_to(Geo.position_of(city)) <= EnemyTurn.SIEGE_CAMP_RANGE:
				encounter.besieged_city = city
				break
	encounter["retreat_allowed"] = not encounter.get("defending_city",false) and (
		not encounter.get("player_field",true) or retreat_turns.get(commanded_army,0)!=turn)
	var rival_faction := encounter_rival_faction()
	encounter["banner_factions"] = [0,rival_faction]
	set_encounter_banner_colors()
	set_encounter_commanders()

func set_encounter_banner_colors() -> void:
	var rival: int = encounter.banner_factions[1]
	encounter.banner_colors = [Geo.FACTIONS[0].color, Geo.faction_appearance(rival, encounter.city).color]

func set_encounter_commanders() -> void:
	var opponent: int = encounter.army
	var own := commanded_army if encounter.get("player_field",true) else -1
	var names := []
	var portraits := []
	for index: int in [own,opponent]:
		names.append(campaign.leaders[index].name if index >= 0 else "")
		portraits.append(campaign.leader_portrait(index) if index >= 0 else "militia")
	if opponent < 0:
		for unit in encounter.defenders:
			if unit.get("commander",false):
				names[1] = unit.title
				portraits[1] = unit.kind
				break
	encounter["commander_names"] = names
	encounter["commander_portraits"] = portraits

func mobilize_city(city: String) -> Array:
	var garrison: Array = forces.garrisons.get_or_add(city,[])
	campaign.muster_militia(city,garrison,turn)
	return garrison

func lose_city(city: String, rival: int) -> void:
	campaign.capture(city,Geo.army_faction(rival),"occupy")
	forces.holdings.erase(city)
	forces.garrisons.erase(city)
	refresh_garrison(city)
	enemy_operations.erase(rival)
	if not forces.armies[rival].is_empty():
		forces.stations[rival] = city
		update_army_piece(rival)
	sync_settlement_models()

func set_player_camp(id: String) -> void:
	place_player(camp_on_land(id,commanded_army),id)

func camp_on_land(id: String, index := 0) -> Vector2:
	var camp := Geo.army_camp(index,id)
	return Geo.position_of(id) if terrain.surface(camp).y <= Landscape.WATER_LEVEL+0.1 else camp

func place_player(point: Vector2, city: String) -> void:
	current_city = city
	forces.stations[commanded_army] = city
	army_positions[commanded_army] = point
	armies[commanded_army].position = terrain.surface(point,0.30)

func story_order() -> Dictionary:
	return STORY_ORDERS.get(story_stage,{})

func skip_held_story_targets() -> void:
	while STORY_ORDERS.has(story_stage) and campaign.owner(STORY_ORDERS[story_stage].city) == 0:
		story_stage += 1

func advance_story(city: String) -> String:
	if city != story_order().get("city",""):
		return ""
	skip_held_story_targets()
	var order := story_order()
	if order.is_empty():
		return "Сюжетная цель выполнена"
	if story_stage == StoryStage.CAPTURE_SMOLENSK:
		return "Новая глава «%s» · %s" % [SMOLENSK_CHAPTER,order.title]
	return "Новая сюжетная цель · " + order.title

func capture_city(id: String, choice := "occupy") -> void:
	var reward := campaign.capture(id,0,choice)
	if not reward.is_empty():
		march_notice = reward
	var story_notice := advance_story(id)
	if not story_notice.is_empty():
		campaign.note(story_notice)
		march_notice = story_notice
		if not reward.is_empty(): march_notice += " · " + reward
	if id not in forces.holdings:
		forces.holdings.append(id)
	forces.garrisons.erase(id)
	refresh_garrison(id)
	sync_settlement_models()
	for index in range(1,Geo.ARMIES.size()):
		if forces.stations[index] == id:
			forces.retreat_army(index,id,campaign)
			enemy_operations.erase(index)
			update_army_piece(index)
	update_faction_defeats()

func update_faction_defeats() -> PackedStringArray:
	var notices := campaign.update_faction_defeats()
	if not notices.is_empty():
		var reward := march_notice
		march_notice = " · ".join(notices)
		if not reward.is_empty(): march_notice += " · " + reward
	campaign_defeated = campaign.factions[0].get("defeated",false)
	if campaign_defeated: enemy_actor = 0
	return notices

func update_army_piece(index: int, reposition := true) -> void:
	var city := forces.stations[index]
	armies[index].visible = not forces.armies[index].is_empty()
	if armies[index].visible and reposition and not city.is_empty():
		var camp := camp_on_land(city,index)
		army_positions[index] = camp
		armies[index].position = terrain.surface(camp,0.30)

func start_tactical_battle() -> void:
	battle_loading = true
	var cover := BattleLoading.new()
	get_tree().root.add_child(cover)
	cover.retry_requested.connect(func(): load_tactical_scene(cover))
	cover.cancel_requested.connect(func():
		cover.queue_free()
		battle_loading = false
		if not encounter.enemy_attack:
			place_player(march_origin,march_origin_city)
		encounter = {}
		march_notice = "Загрузка боя отменена"
		refresh_ui())
	load_tactical_scene(cover)

func load_tactical_scene(cover: CanvasLayer) -> void:
	cover.begin(encounter.title)
	if ResourceLoader.load_threaded_request(BATTLE_SCENE) != OK:
		cover.failed()
		return
	var progress := []
	while true:
		match ResourceLoader.load_threaded_get_status(BATTLE_SCENE,progress):
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if not progress.is_empty():
					cover.set_progress(float(progress[0])*0.85)
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				var scene := ResourceLoader.load_threaded_get(BATTLE_SCENE) as PackedScene
				if scene == null:
					cover.failed()
					return
				cover.preparing()
				await get_tree().process_frame
				await get_tree().process_frame
				open_tactical_scene(scene,cover)
				return
			ResourceLoader.THREAD_LOAD_FAILED:
				ResourceLoader.load_threaded_get(BATTLE_SCENE)
				cover.failed()
				return
			_:
				cover.failed()
				return

func open_tactical_scene(scene: PackedScene, cover: CanvasLayer) -> void:
	# Park the existing map in its own world so its meshes aren't rebuilt on return.
	var tree := get_tree()
	var root := tree.root
	var battle := scene.instantiate()
	save_campaign(CampaignSave.Slot.BATTLE_START)
	battle.campaign_request = encounter.duplicate()
	battle.campaign_request["weather"] = map_weather.condition
	battle.campaign_request["research_bonuses"] = [campaign.battle_research(0),campaign.battle_research(encounter_rival_faction())]
	battle.campaign_battle_finished.connect(return_from_battle.bind(battle),CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	var parking := SubViewport.new()
	parking.own_world_3d = true
	parking.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parking.process_mode = Node.PROCESS_MODE_DISABLED
	if tree.current_scene == self:
		tree.current_scene = null
	campaign_music_position = campaign_music.get_playback_position()
	campaign_music.stop()
	root.remove_child(self)
	root.add_child(battle)
	battle.add_child(parking)
	parking.add_child(self)
	await tree.process_frame
	cover.queue_free()

func return_from_battle(result: Dictionary, battle: Node) -> void:
	var tree := get_tree()
	var root := tree.root
	var parking := get_parent()
	parking.remove_child(self)
	tree.paused = false
	Engine.time_scale = 1.0
	tree.current_scene = null
	root.remove_child(battle)
	battle.queue_free()
	root.add_child(self)
	tree.current_scene = self
	campaign_music.play(campaign_music_position)
	camera.make_current()
	battle_loading = false
	complete_map_battle(result)
	project_markers()

func apply_battle_result(result: Dictionary) -> void:
	var city: String = encounter.city
	var opposing_army: int = encounter.army
	var city_battle: bool = encounter.city_battle
	var enemy_attack: bool = encounter.enemy_attack
	var defending_city: bool = encounter.get("defending_city",false)
	var player_field: bool = encounter.get("player_field",true)
	var victory: bool = result.outcome == "win"
	var combat_xp: Dictionary = result.get("experience",{})
	var enemy_victory: bool = result.outcome == "loss"
	var expired: bool = result.get("time_expired",false)
	if result.outcome == "retreat" and player_field:
		retreat_turns[commanded_army] = turn
	if result.outcome == "retreat" and city_battle and not enemy_attack:
		campaign.sieges.erase(city)
	var ours := forces.survivors(encounter.attackers,result.survivors,combat_xp,victory)
	var theirs := forces.survivors(encounter.defenders,result.survivors,combat_xp,enemy_victory)
	battle_summary = {
		"title": {"win": "Победа", "loss": "Поражение", "draw": "Ничья", "retreat": "Отступление"}[result.outcome],
		"target": encounter.target,
		"own_losses": forces.headcount(encounter.attackers)-forces.headcount(ours),
		"enemy_losses": forces.headcount(encounter.defenders)-forces.headcount(theirs),
		"remaining": forces.headcount(ours),
		"time_expired":expired,
	}
	var own_roster: Array = forces.armies[commanded_army]
	if player_field:
		forces.armies[commanded_army] = forces.survivors(own_roster,result.survivors,combat_xp,victory)
		armies[commanded_army].visible = not forces.armies[commanded_army].is_empty()
	var besieged_city: String = encounter.get("besieged_city","")
	if not besieged_city.is_empty() and (not victory or forces.armies[commanded_army].is_empty()):
		campaign.sieges.erase(besieged_city)
		battle_summary["siege_lifted"] = Geo.CITIES[besieged_city][0]
		sync_siege_models()
	var fallen_support: Array = result.get("fallen_support",[])
	var fallen_leaders: Array[int] = []
	for source in encounter.get("support",[]):
		var remaining := forces.survivors(source.roster,result.survivors,combat_xp,victory if source.team == 0 else enemy_victory)
		if source.has("city"):
			forces.garrisons[source.city] = remaining
		else:
			var index: int = source.army
			if index in fallen_support or field_leader_lost(source.roster,remaining):
				fallen_leaders.append(index)
			forces.armies[index] = remaining
			update_army_piece(index,false)
	if player_field:
		if result.get("leader_lost",false) or field_leader_lost(own_roster,forces.armies[commanded_army]):
			fallen_leaders.append(commanded_army)
		battle_summary.remaining = forces.headcount(forces.armies[commanded_army])
	if opposing_army > 0:
		var enemy_survivors := forces.survivors(forces.armies[opposing_army],result.survivors,combat_xp,enemy_victory)
		if result.get("rival_leader_lost",false) or field_leader_lost(forces.armies[opposing_army],enemy_survivors):
			fallen_leaders.append(opposing_army)
		forces.armies[opposing_army] = enemy_survivors
		if victory and not enemy_survivors.is_empty():
			forces.retreat_army(opposing_army,city,campaign)
			enemy_operations.erase(opposing_army)
		update_army_piece(opposing_army,victory)
	if encounter.get("rebellion",false):
		if victory:
			campaign.defeat_rebel_band(city)
		else: campaign.rebellions[city].roster = theirs
	elif defending_city:
		if enemy_victory or result.outcome == "retreat":
			lose_city(city,opposing_army)
			battle_summary["lost_city"] = Geo.CITIES[city][0]
		else:
			forces.garrisons[city] = forces.survivors(encounter.garrison,result.survivors,combat_xp,victory)
	elif city_battle:
		if victory and not encounter.get("sortie",false):
			pending_capture = city
		else:
			forces.garrisons[city] = forces.survivors(encounter.garrison,result.survivors,combat_xp,enemy_victory)
			if not victory and encounter.get("sortie",false):
				campaign.sieges.erase(city)
	for index in fallen_leaders:
		record_fallen_leader(index,city)
	var defeated_factions := update_faction_defeats()
	if not defeated_factions.is_empty():
		battle_summary["faction_defeats"] = defeated_factions
	if victory and player_field and commanded_army not in fallen_leaders:
		campaign.award_leader_victory(commanded_army,city_battle)
		campaign.factions[0].influence = mini(100,campaign.factions[0].influence+5)
	elif enemy_victory and opposing_army >= 0 and opposing_army not in fallen_leaders:
		campaign.award_leader_victory(opposing_army,city_battle)
	if campaign_defeated:
		battle_summary.title = "Кампания проиграна"
		pending_capture = ""
	elif commanded_army not in fallen_leaders:
		if enemy_attack or result.outcome == "loss":
			if not victory and player_field:
				retreat_player(opposing_army)
		elif victory and city_battle:
			set_player_camp(city)
		elif victory:
			current_city = ""
		else:
			place_player(march_origin,march_origin_city)
	selected_city = ""
	selected_army = commanded_army
	encounter = {}
	if not campaign_defeated and forces.armies[commanded_army].is_empty():
		var reserve := nearest_player_army(army_positions[commanded_army])
		command_army(reserve if reserve >= 0 else 0)
		selected_army = commanded_army
	draw_route()

func field_leader_lost(before: Array, remaining: Array) -> bool:
	if before.is_empty(): return false
	return remaining.is_empty() or (before.any(func(unit): return unit.kind == "princely") and not remaining.any(func(unit): return unit.kind == "princely"))

func record_fallen_leader(index: int, city: String) -> void:
	var leader: Dictionary = campaign.leaders[index]
	if leader.get("fallen",false): return
	leader.fallen = true
	campaign.note("Воевода %s пал" % leader.name)
	for city_id in campaign.sieges.keys():
		if campaign.sieges[city_id].get("army",0) == index:
			campaign.sieges.erase(city_id)
	forces.retreat_army(index,city,campaign)
	var refuge := forces.stations[index]
	if not refuge.is_empty():
		var garrison: Array = forces.garrisons.get_or_add(refuge,[])
		for unit in forces.armies[index]:
			if unit.kind == "princely":
				unit.kind = "cavalry"
				unit.title = CampaignState.UNITS.cavalry[0]
				unit.max = CampaignState.UNITS.cavalry[1]
			garrison.append(unit)
	forces.armies[index] = []
	forces.stations[index] = ""
	enemy_operations.erase(index)
	other_marches.erase(index)
	if index == commanded_army:
		current_city = ""
		has_route = false
		march_preview = false
		destination = ""
		destination_army = -1
		travel_goal = traveled
		pending_march.clear()
		riders[index].set_gait(&"Idle")
		draw_route()
	update_army_piece(index,false)

func retreat_player(opponent := -1) -> void:
	has_route = false
	march_preview = false
	destination = ""
	destination_army = -1
	travel_goal = traveled
	riders[commanded_army].set_gait(&"Idle")
	var closest := ""
	var distance := INF
	var origin := army_positions[commanded_army]
	var hostile := army_positions[opponent] if opponent > 0 else Vector2.INF
	for city in forces.holdings:
		var camp := camp_on_land(city,commanded_army)
		if camp.distance_to(hostile) <= EnemyTurn.CONTACT_RANGE*2: continue
		var candidate := origin.distance_squared_to(camp)
		if candidate < distance:
			closest = city
			distance = candidate
	if not closest.is_empty():
		set_player_camp(closest)
		return
	var heading := (origin-hostile).angle() if hostile.is_finite() else 0.0
	for step in 8:
		var point := origin+Vector2.from_angle(heading+TAU*step/8.0)*24.0
		if point.distance_to(hostile)<=EnemyTurn.CONTACT_RANGE*2: continue
		if absf(point.x)>=Landscape.HALF.x or absf(point.y)>=Landscape.HALF.y: continue
		if terrain.surface(point).y>Landscape.WATER_LEVEL+.1:
			place_player(point,"")
			return

func segment_index(distance: float) -> int:
	return clampi(distance_marks.bsearch(distance)-1,0,distance_marks.size()-2)

func route_position(distance: float) -> Vector2:
	var leg_index := segment_index(distance)
	var span: float = distance_marks[leg_index+1]-distance_marks[leg_index]
	return path[leg_index].lerp(path[leg_index+1],clampf((distance-distance_marks[leg_index])/span,0.0,1.0))

func begin_leg() -> void:
	if has_route and not march_preview and movement > 0.01:
		if destination_army > 0 and (not armies[destination_army].visible or not can_see_army(destination_army)):
			has_route = false
			destination = ""
			destination_army = -1
			draw_route()
			refresh_ui()
			return
		travel_goal = minf(traveled+movement,distance_marks[-1])
		movement -= travel_goal-traveled
		riders[commanded_army].set_gait(&"Walk")
	draw_route()
	refresh_ui()

func end_turn() -> void:
	if not player_orders_allowed():
		return
	ensure_navigation()
	pending_march.clear()
	enemy_actor = 1
	enemy_budget = EnemyTurn.MOVE
	enemy_delay = 0.28
	march_notice = ""
	march_obstacle = null
	refresh_ui()

func request_end_turn() -> void:
	if not player_orders_allowed(): return
	var ready_cities := PackedStringArray()
	var first := ""
	for city in forces.holdings:
		if campaign.cities[city].get("advisor","off") != "off" or campaign.available_construction(city).is_empty(): continue
		if first.is_empty(): first = city
		ready_cities.append(Geo.CITIES[city][0])
	var idle := campaign.research_idle(0)
	if ready_cities.is_empty() and not idle:
		end_turn()
		return
	if construction_warning == null:
		construction_warning = ConfirmationDialog.new()
		construction_warning.ok_button_text = "Завершить ход"
		construction_warning.cancel_button_text = "Вернуться"
		construction_warning_button = construction_warning.add_button("К строительству",true,"build")
		research_warning_button = construction_warning.add_button("К исследованиям",true,"research")
		construction_warning.confirmed.connect(end_turn)
		construction_warning.custom_action.connect(open_turn_warning_action)
		add_child(construction_warning)
	construction_warning.title = "Перед концом хода"
	construction_warning_button.visible = not ready_cities.is_empty()
	research_warning_button.visible = idle
	construction_warning.set_meta("city",first)
	var reminders := PackedStringArray()
	if idle: reminders.append("Исследование свободно. Откройте «Знания и ремёсла», чтобы выбрать новое знание.")
	if not ready_cities.is_empty():
		reminders.append("Можно построить или улучшить здания в городах\n"+", ".join(ready_cities))
	construction_warning.dialog_text = "\n\n".join(reminders)
	construction_warning.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	construction_warning.popup_centered(Vector2i(560,170))

func open_turn_warning_action(action: StringName) -> void:
	construction_warning.hide()
	if action == &"research":
		if management.screen != "research" or not management.details.visible:
			management.open("research")
		return
	var city: String = construction_warning.get_meta("city")
	var key := campaign.available_construction(city)
	if key.is_empty(): return
	select_city(city)
	focus_at(Geo.position_of(city))
	management.open_building(key)

func advance_enemy_turn(delta: float) -> void:
	if enemy_actor >= Geo.ARMIES.size():
		finish_enemy_turn()
		return
	if not armies[enemy_actor].visible:
		enemy_operations.erase(enemy_actor)
		next_enemy_actor()
		return
	enemy_delay -= delta
	if enemy_delay > 0.0:
		return
	if not enemy_acted:
		enemy_acted = true
		enemy_budget = EnemyTurn.MOVE * Forces.march_multiplier(forces.armies[enemy_actor])
		var orders := {}
		for index in army_positions.size():
			if not is_player_army(index) or forces.armies[index].is_empty(): continue
			var march: Dictionary = march_state() if index == commanded_army else other_marches.get(index,{})
			orders[index] = march.get("destination","") if not march.get("preview",false) and march.get("destination_army",-1) < 0 else ""
		var planner := EnemyTurn.new(army_positions,forces,navigation,campaign,turn,enemy_operations,orders)
		enemy_plan = planner.plan(enemy_actor)
		if enemy_plan.has("city"):
			enemy_operations[enemy_actor] = {"kind":enemy_plan.kind,"city":enemy_plan.city}
		else:
			enemy_operations.erase(enemy_actor)
		refresh_ui()
		var screen := camera.unproject_position(armies[enemy_actor].position)
		if can_see_army(enemy_actor) and not get_viewport().get_visible_rect().has_point(screen):
			focus_at(army_positions[enemy_actor])
	var waypoints: PackedVector2Array = enemy_plan.get("path",PackedVector2Array())
	var kind: String = enemy_plan.get("kind","")
	var city: String = enemy_plan.get("city","")
	var target_army: int = enemy_plan.get("player_army",-1)
	var index := enemy_actor
	var city_assault := kind in ["retake","attack_city"]
	if waypoints.size() < 2:
		next_enemy_actor()
		if target_army >= 0:
			start_enemy_attack(index,target_army)
		elif city_assault:
			queue_city_defense(city,index)
		elif not city.is_empty():
			forces.stations[index] = city
		return
	forces.stations[index] = ""
	riders[index].set_gait(&"Walk")
	var remaining := minf(delta*86.0,enemy_budget)
	while remaining > 0.001 and enemy_step < waypoints.size():
		var point := army_positions[index]
		var target := waypoints[enemy_step]
		var distance := point.distance_to(target)
		var cost: float = terrain.movement_cost(waypoints[enemy_step-1].lerp(target,0.5))
		var step := minf(distance,remaining/cost)
		if distance > 0.001:
			var heading := target-point
			riders[index].rotation.y = lerp_angle(riders[index].rotation.y,atan2(heading.x,heading.y),minf(delta*12.0,1.0))
			army_positions[index] = point.move_toward(target,step)
			armies[index].position = terrain.surface(army_positions[index],0.30)
			armies[index].position.y = maxf(armies[index].position.y,Landscape.WATER_LEVEL+0.75)
		remaining -= step*cost
		enemy_budget -= step*cost
		if distance-step < 0.001:
			enemy_step += 1
	var close_contact := target_army >= 0 and army_positions[index].distance_to(army_positions[target_army]) <= EnemyTurn.CONTACT_RANGE
	if close_contact and enemy_step < waypoints.size():
		close_contact = navigation.is_land(army_positions[index]) and navigation.land_segment(army_positions[index],army_positions[target_army])
	if close_contact or enemy_step >= waypoints.size() or enemy_budget <= 0.001:
		var arrived := enemy_step >= waypoints.size()
		if arrived and not city_assault and not city.is_empty():
			forces.stations[index] = city
			enemy_operations.erase(index)
		riders[index].set_gait(&"Idle")
		next_enemy_actor()
		if close_contact:
			start_enemy_attack(index,target_army)
		elif arrived and city_assault:
			queue_city_defense(city,index)

func next_enemy_actor() -> void:
	enemy_actor += 1
	enemy_plan = {}
	enemy_step = 1
	enemy_budget = EnemyTurn.MOVE
	enemy_delay = 0.23
	enemy_acted = false
	refresh_ui()

func nearest_player_army(point: Vector2, limit := INF) -> int:
	var nearest := -1
	var distance := limit*limit
	for i in armies.size():
		if not is_player_army(i) or forces.armies[i].is_empty(): continue
		var candidate := point.distance_squared_to(army_positions[i])
		if candidate <= distance:
			distance = candidate
			nearest = i
	return nearest

func start_enemy_attack(index: int, target := 0) -> void:
	command_army(target)
	if has_route and traveled > 0.01:
		current_city = ""
	has_route = false
	march_preview = false
	destination = ""
	destination_army = -1
	selected_army = commanded_army
	selected_city = ""
	draw_route()
	queue_battle(region_at(army_positions[index]),index,false,true)

func finish_enemy_turn() -> void:
	enemy_actor = 0
	turn += 1
	advance_campaign()
	if campaign_defeated:
		show_battle_menu()
		save_campaign(CampaignSave.Slot.END_TURN)
		return
	if not campaign_defeated and forces.armies[commanded_army].is_empty() and encounter.is_empty() and pending_capture.is_empty():
		var reserve := nearest_player_army(army_positions[commanded_army])
		if reserve >= 0: command_army(reserve)
	if not forces.armies[commanded_army].is_empty():
		focus_player()
	save_campaign(CampaignSave.Slot.END_TURN)
	if not encounter.is_empty():
		return
	if not pending_capture.is_empty():
		show_battle_menu()
		return
	draw_route()
	refresh_ui()

func draw_route() -> void:
	for child in route_visual.get_children():
		child.queue_free()
	if not has_route:
		return
	var solid: Material = terrain.material(Color("#ffd58b"),true)
	var future: Material = terrain.material(Color("#aa8d5c"),true)
	var dot := SphereMesh.new()
	dot.radius = 0.68
	dot.height = 0.85
	dot.radial_segments = 8
	dot.rings = 3
	var bright := dot.duplicate() as SphereMesh
	bright.material = solid
	dot.material = future
	if path.size() == 1:
		terrain.place_mesh(bright,terrain.surface(path[0],.68),route_visual)
		return
	var marked_goal := minf(traveled+movement,distance_marks[-1]) if march_preview else travel_goal
	for i in range(1,ceili((distance_marks[-1]-traveled)/4.0)+1):
		var distance := minf(traveled+i*4.0,distance_marks[-1])
		var p := route_position(distance)
		var position_on_road: Vector3 = terrain.surface(p,0.68)
		position_on_road.y = maxf(position_on_road.y,Landscape.WATER_LEVEL+0.9)
		var mesh := bright if distance <= marked_goal+0.01 else dot
		terrain.place_mesh(mesh,position_on_road,route_visual)

func label(parent: Node, value: String, size: int, color := CREAM, display := false) -> Label:
	var item := Label.new()
	item.add_theme_font_override("font",UI.FONT)
	item.text = value
	item.add_theme_font_size_override("font_size",size)
	item.add_theme_color_override("font_color",color)
	if display:
		item.add_theme_font_override("font",serif)
	parent.add_child(item)
	return item

func button(parent: Node, value: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = value
	item.focus_mode = Control.FOCUS_NONE
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func make_ui() -> void:
	serif = UI.DISPLAY
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	layer.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = UI.theme()
	markers = Control.new()
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(markers)
	markers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for p in Geo.PROVINCES:
		var caption := label(markers,p[0].to_upper(),29,Color("e4dfc4b5"),true)
		caption.add_theme_color_override("font_outline_color",Color("314031b0"))
		caption.add_theme_constant_override("outline_size",3)
		province_labels.append(caption)
	for feature in Geo.WATER_NAMES:
		var caption := label(markers,feature[0],23 if feature[3] else 24,Color("e0eff3"),true)
		caption.add_theme_color_override("font_outline_color",Color("253e4a"))
		caption.add_theme_constant_override("outline_size",4)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		water_labels.append(caption)
	for id in Geo.CITIES:
		var data: Array = Geo.CITIES[id]
		var pin := MapPin.new()
		pin.text = data[0]
		pin.capital = Geo.is_province_capital(id)
		pin.lettering = 23 if data[3] else 21
		pin.pressed.connect(select_city.bind(id))
		markers.add_child(pin)
		pin.add_theme_font_size_override("font_size",23 if data[3] else 21)
		pin.icon = UI.icon("town") if data[3] else UI.icon("shield")
		pin.expand_icon = true
		pin.add_theme_constant_override("icon_max_width",19)
		pin.add_theme_color_override("icon_normal_color",UI.RED)
		pin.gui_input.connect(city_input.bind(id))
		city_buttons[id] = pin
	for i in Geo.ARMIES.size():
		make_army_pin(i)
	# HUD adopts these live controls after the map markers have been built.
	var staging := Control.new()
	ui.add_child(staging)
	staging.hide()
	status = label(staging,"",17,UI.BRASS)
	turn_label = label(staging,"",24,UI.BONE,true)
	turn_button = TurnSeal.new()
	staging.add_child(turn_button)
	turn_button.pressed.connect(request_end_turn)


func make_army_pin(i: int) -> void:
	var pin := MapPin.new()
	pin.text = campaign.leaders[i].name
	pin.army = true
	pin.pressed.connect(select_army.bind(i))
	markers.add_child(pin)
	pin.add_theme_font_size_override("font_size",20)
	pin.icon = UI.icon("sword")
	pin.expand_icon = true
	pin.add_theme_constant_override("icon_max_width",20)
	pin.gui_input.connect(army_input.bind(i))
	army_buttons.append(pin)


func city_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		order_to(id)
		city_buttons[id].accept_event()

func army_input(event: InputEvent, index: int) -> void:
	if not is_player_army(index) and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		attack_army(index)
		army_buttons[index].accept_event()

func focus_province(index: int) -> void:
	var id := Geo.province_capital(index)
	select_city(id)
	focus_at(Geo.position_of(id))

func focus_player() -> void:
	select_army(commanded_army)
	center_camera_on_player()

func center_camera_on_player() -> void:
	focus = armies[commanded_army].position + Vector3.UP * (rider_scale(commanded_army)*.78)
	update_camera()

func focus_at(p: Vector2, map_width := MIN_MAP_ZOOM) -> void:
	focus = Vector3(p.x,0,p.y)
	zoom = clampf(map_width,MIN_MAP_ZOOM,MAX_MAP_ZOOM)
	update_camera()

func enemy_turn_status() -> String:
	if not encounter.is_empty() or not pending_capture.is_empty():
		return "Ожидается решение по сражению"
	if enemy_actor <= 0 or enemy_actor >= Geo.ARMIES.size() or not armies[enemy_actor].visible or not can_see_army(enemy_actor):
		return "Действия скрыты туманом войны"
	var actor: String = campaign.leaders[enemy_actor].name
	match enemy_plan.get("kind",""):
		"intercept": return "%s атакует дружину" % actor
		"retake": return "%s идёт отбивать город %s" % [actor,Geo.CITIES[enemy_plan.city][0]]
		"attack_city": return "%s идёт на город %s" % [actor,Geo.CITIES[enemy_plan.city][0]]
		"defend": return "%s идёт на защиту города %s" % [actor,Geo.CITIES[enemy_plan.city][0]]
		"muster": return "%s собирает подкрепления в городе %s" % [actor,Geo.CITIES[enemy_plan.city][0]]
		"patrol": return "%s идёт к городу %s" % [actor,Geo.CITIES[enemy_plan.city][0]]
	return actor

func calendar_month_index() -> int:
	return START_MONTH_INDEX+turn-1

func campaign_season() -> int:
	return MONTH_SEASONS[calendar_month_index()%MONTH_NAMES.size()]

func refresh_ui() -> void:
	sync_rebel_pieces()
	sync_siege_models()
	if is_instance_valid(territory_borders): territory_borders.refresh()
	var season := campaign_season()
	terrain.set_season(season)
	map_weather.set_weather(WorldWeather.for_turn(turn,season),season)
	var active := not player_orders_allowed()
	var has_army: bool = not forces.armies[commanded_army].is_empty()
	if campaign_defeated:
		status.text = "Кампания проиграна"
	elif enemy_actor > 0:
		status.text = ""
	elif not march_notice.is_empty():
		status.text = march_notice
	elif has_route:
		var target := "выбранная точка"
		if destination_army > 0:
			target = campaign.leaders[destination_army].name
		elif not destination.is_empty():
			target = Geo.CITIES[destination][0]
		if march_preview:
			status.text = "ПКМ ещё раз — начать марш → " + target
		else:
			status.text = ("Дружина в пути → " if traveled < travel_goal else "Марш ожидает приказа → ") + target
	else:
		var place: String = "В походе" if current_city.is_empty() else Geo.CITIES[current_city][0]
		status.text = "Дружина · %s" % place if has_army else "Дружина уничтожена"
	var calendar_month := calendar_month_index()
	var year := START_YEAR+floori(float(calendar_month)/MONTH_NAMES.size())
	turn_label.text = "%s %d  ·  Ход %d" % [MONTH_NAMES[calendar_month%MONTH_NAMES.size()],year,turn]
	turn_button.disabled = active
	for id in city_buttons:
		var selected: bool = id == selected_city
		var pin: Button = city_buttons[id]
		var city_owner := campaign.owner(id)
		var appearance := Geo.faction_appearance(city_owner, id)
		pin.selected = selected
		pin.blocks_march = march_obstacle is String and march_obstacle == id
		pin.tone = appearance.color
		pin.flag = UI.faction_flag(city_owner, id)
		pin.info = Geo.FACTIONS[city_owner].name
		var available_building := campaign.available_construction(id)
		pin.construction_idle = not available_building.is_empty()
		if campaign.cities[id].rebel: pin.info += " · мятеж"
		var siege: Dictionary = campaign.sieges.get(id,{})
		if not siege.is_empty():
			pin.info = "Осада · до сдачи %d ход." % siege_turns_remaining(id)
			pin.tone = appearance.color.lerp(UI.RED,.62)
		var revolt_turns: int = campaign.cities[id].revolt_turns
		var revolt_warning := ""
		if city_owner == 0 and revolt_turns > 0:
			revolt_warning = "До мятежа %d ход." % revolt_turns
			pin.info = revolt_warning if siege.is_empty() else pin.info+" · "+revolt_warning
			pin.tone = appearance.color.lerp(UI.RED,.62)
		var garrison: Array = forces.garrisons.get(id,[])
		pin.tooltip_text = "%s · %s\nДоход: %d серебра\nГарнизон: %d воинов" % [Geo.CITIES[id][0],Geo.FACTIONS[city_owner].name,campaign.town_yield(id).silver,forces.headcount(garrison)]
		pin.tooltip_text += "\nМестные товары · "+campaign.trade_goods_text(id)
		var garrison_squads := Forces.squad_tooltip(garrison)
		if not garrison_squads.is_empty(): pin.tooltip_text += "\n"+garrison_squads
		var reserve := campaign.militia_reserve(id,garrison,turn)
		if reserve>0: pin.tooltip_text += "\nОполчение при нападении: до %d воинов" % reserve
		if pin.construction_idle:
			pin.tooltip_text += "\nМожно улучшить здание" if campaign.cities[id].buildings.has(available_building) else "\nМожно начать строительство"
		if not siege.is_empty(): pin.tooltip_text += "\n"+pin.info
		elif not revolt_warning.is_empty(): pin.tooltip_text += "\n"+revolt_warning
		pin.custom_minimum_size = pin.marker_size()
		pin.queue_redraw()
	for i in army_buttons.size():
		var faction := Geo.army_faction(i)
		control_rings[i].visible = armies[i].visible and (i == selected_army or (i > 0 and zoom < 600))
		var selected := i == selected_army and selected_city.is_empty()
		armies[i].get_node("SelectionAura").visible = selected and can_see_army(i)
		army_buttons[i].text = campaign.leaders[i].name
		army_buttons[i].custom_minimum_size = army_buttons[i].marker_size()
		army_buttons[i].selected = selected
		army_buttons[i].blocks_march = march_obstacle is int and march_obstacle == i
		army_buttons[i].tone = Geo.FACTIONS[faction].color
		army_buttons[i].flag = UI.faction_flag(faction)
		var roster: Array = forces.armies[i]
		army_buttons[i].tooltip_text = "%s · %s · %d воинов" % [campaign.leaders[i].name,Geo.FACTIONS[faction].name,forces.headcount(roster)]
		var squads := Forces.squad_tooltip(roster)
		if not squads.is_empty(): army_buttons[i].tooltip_text += "\n"+squads
		army_buttons[i].queue_redraw()
	if is_instance_valid(management): management.refresh()
	if is_instance_valid(management) and not active and announced_turn != turn:
		announced_turn = turn
		management.hud.show_turn_start()

func project_markers() -> void:
	project_rebels()
	for i in province_labels.size():
		var caption := province_labels[i]
		caption.visible = zoom > 544.0
		if caption.visible:
			var location: Vector3 = terrain.surface(Geo.province_center(i),1.5)
			caption.position = camera.unproject_position(location)-caption.size*0.5
	var occupied: Array[Rect2] = []
	var screen := get_viewport().get_visible_rect().grow(-10.0)
	if is_instance_valid(management):
		screen.position.y = 71.0 * management.hud.canvas.scale.y
		screen.end.y = management.hud.dock.get_global_rect().position.y - 6.0
	for id in city_buttons:
		if not city_buttons[id].blocks_march and not fog.visible_at(Geo.position_of(id)):
			city_buttons[id].hide()
			continue
		var p := Geo.position_of(id)
		var capital: bool = Geo.CITIES[id][3]
		var clearance := (8.7 if capital else 5.2) * get_viewport().get_visible_rect().size.y / zoom
		var offset := Vector2(0,maxf(24.0,clearance))
		if id == "novgorod":
			offset.x = -17
		project_pin(city_buttons[id],terrain.surface(p,0.5),offset)
		if city_buttons[id].visible:
			occupied.append(city_buttons[id].get_global_rect())
	for i in army_buttons.size():
		if not armies[i].visible or not can_see_army(i):
			army_buttons[i].hide()
			continue
		var label_height: float = rider_scale(i)*2.5*armies[i].scale.y
		var offset := Vector2(0,-39)
		if Geo.army_faction(i) == 6:
			offset.x = lerpf(6.0,43.0,smoothstep(225.0,800.0,zoom)) * (1.0 if Geo.ARMIES[i].id == "dir" else -1.0)
		project_pin(army_buttons[i],armies[i].position+Vector3.UP*label_height,offset)
		if army_buttons[i].visible:
			place_clear_label(army_buttons[i],occupied,screen)
	for i in water_labels.size():
		var feature: Array = Geo.WATER_NAMES[i]
		var position: Vector2 = feature[1] * Geo.MAP_SCALE
		var tangent: Vector2 = feature[2]
		var origin := Vector3(position.x,Landscape.WATER_LEVEL+.8,position.y)
		var point := camera.unproject_position(origin)
		var caption := water_labels[i]
		caption.visible = fog.explored_at(position) and screen.grow(19.0).has_point(point)
		if caption.visible:
			caption.size = caption.get_minimum_size()
			caption.pivot_offset = caption.size*.5
			var along := camera.unproject_position(origin+Vector3(tangent.x,0,tangent.y)*10)-point
			var angle := wrapf(along.angle(),-PI*.5,PI*.5)
			caption.rotation = 0.0 if feature[3] else clampf(angle,-.48,.48)
			caption.position = point-caption.pivot_offset
			place_clear_label(caption,occupied,screen)
	if is_instance_valid(management) and management.atlas:
		management.atlas.queue_redraw()

func place_clear_label(control: Control, occupied: Array[Rect2], screen: Rect2) -> void:
	var anchor := control.position
	var gap := control.size.y + 4.0
	var side := control.size.x*.72
	for offset in [Vector2.ZERO,Vector2(0,-gap),Vector2(0,gap),Vector2(-side,0),Vector2(side,0),Vector2(-side,-gap),Vector2(side,-gap)]:
		var point: Vector2 = (anchor+offset).clamp(screen.position,screen.end-control.size)
		var bounds := Rect2(point,control.size)
		if not occupied.any(func(rect): return rect.grow(3.0).intersects(bounds)):
			control.position = point
			occupied.append(bounds)
			return
	occupied.append(Rect2(anchor,control.size))

func project_pin(pin: Button, location: Vector3, offset: Vector2) -> void:
	var point := camera.unproject_position(location)
	var rect := get_viewport().get_visible_rect()
	pin.visible = rect.grow(-10.0).has_point(point)
	if pin.visible:
		pin.size = pin.get_combined_minimum_size()
		pin.position = point+offset-Vector2(pin.size.x*0.5,0)


func add_campaign_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	management = CampaignPanel.new()
	management.world = self
	layer.add_child(management)
	battle_menu = PanelContainer.new()
	Chrome.decorate(battle_menu,27)
	management.hud.canvas.add_child(battle_menu)
	battle_menu.theme = UI.theme()
	battle_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	battle_menu.offset_left = -400
	battle_menu.offset_right = 400
	battle_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	battle_menu.hide()

func show_battle_menu() -> void:
	for child in battle_menu.get_children():
		battle_menu.remove_child(child)
		child.queue_free()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	battle_menu.add_child(column)
	if not campaign_defeated and pending_capture.is_empty() and encounter.is_empty() and battle_summary.is_empty():
		battle_menu.hide()
		return
	var council := not campaign_defeated and pending_capture.is_empty()
	battle_menu.add_theme_stylebox_override("panel",EncounterUI.frame() if council else UI.campaign_frame(28))
	EncounterUI.render(self,column)
	var height := battle_menu.get_combined_minimum_size().y
	battle_menu.offset_top = -height * .5
	battle_menu.offset_bottom = height * .5
	if management.visible:
		management.close_details()
	battle_menu.show()
	refresh_ui()

func restart_campaign() -> void:
	get_tree().reload_current_scene()

func begin_manual_battle() -> void:
	if encounter.is_empty(): return
	battle_menu.hide()
	start_tactical_battle()

func settle_capture(choice: String) -> void:
	if pending_capture.is_empty(): return
	var city := pending_capture
	pending_capture = ""
	capture_city(city,choice)
	battle_summary["captured"] = Geo.CITIES[city][0]
	battle_menu.hide()
	refresh_ui()
	sync_settlement_models()

func maintain_siege() -> void:
	if encounter.is_empty() or not encounter.city_battle or encounter.enemy_attack: return
	var city: String = encounter.city
	if not campaign.sieges.has(city):
		campaign.sieges[city] = {"turns":0,"ram":0,"army":commanded_army}
	else:
		campaign.sieges[city].army = commanded_army
	battle_menu.hide()
	encounter = {}
	campaign.note("Осада: "+Geo.CITIES[city][0])
	set_player_camp(city)
	selected_city = city
	update_fog(true)
	project_markers()
	refresh_ui()

func siege_turns_remaining(city: String) -> int:
	var siege: Dictionary = campaign.sieges.get(city,{})
	var faction := Geo.army_faction(siege.get("army",commanded_army))
	return maxi(0,CampaignState.SIEGE_TURNS-campaign.tech_bonus(faction,"siege")-siege.get("turns",0))

func withdraw_encounter() -> void:
	if encounter.is_empty() or encounter.get("defending_city",false) or not encounter.get("retreat_allowed",true): return
	var counts := {}
	for combatant in encounter.attackers+encounter.defenders:
		counts[combatant.id] = combatant.count
	complete_map_battle({"outcome":"retreat","survivors":counts})

func resolve_automatically() -> void:
	if encounter.is_empty(): return
	save_campaign(CampaignSave.Slot.BATTLE_START)
	var own_research: Dictionary = campaign.battle_research(0)
	var rival_research: Dictionary = campaign.battle_research(encounter_rival_faction())
	var own_power := Forces.roster_power(encounter.attackers,own_research)
	var rival_power := Forces.roster_power(encounter.defenders,rival_research)
	var attack := own_power
	var defense := rival_power
	if encounter.fortified:
		if encounter.get("defending_city",false):
			attack *= 1.45
		else:
			defense *= 1.16 if encounter.ram else 1.45
	var win := attack >= defense
	var ratio := minf(attack,defense)/maxf(1.0,maxf(attack,defense))
	var losses := {}
	var own_losses := Forces.auto_casualties(encounter.attackers,own_research,0.14+0.31*ratio if win else 0.58+0.16*ratio,losses)
	var rival_losses := Forces.auto_casualties(encounter.defenders,rival_research,0.58+0.16*ratio if win else 0.14+0.31*ratio,losses)
	var experience := Forces.auto_experience(encounter.attackers,rival_losses,own_research,own_power)
	experience.merge(Forces.auto_experience(encounter.defenders,own_losses,rival_research,rival_power))
	var fallen_support: Array = []
	for source in encounter.get("support",[]):
		if source.has("army") and Forces.auto_leader_lost(forces.armies[source.army],losses,turn):
			fallen_support.append(source.army)
	var own_lost: bool = encounter.get("player_field",true) and Forces.auto_leader_lost(forces.armies[commanded_army],losses,turn)
	var rival: int = encounter.army
	var rival_lost := rival >= 0 and Forces.auto_leader_lost(forces.armies[rival],losses,turn)
	complete_map_battle({"outcome":"win" if win else "loss","survivors":losses,"experience":experience,
		"leader_lost":own_lost,"rival_leader_lost":rival_lost,"fallen_support":fallen_support})

func roster_power(roster: Array) -> float:
	return Forces.roster_power(roster)

func complete_map_battle(result: Dictionary) -> void:
	battle_menu.hide()
	apply_battle_result(result)
	show_battle_menu()
	save_campaign(CampaignSave.Slot.BATTLE_END)

func stance_movement(index := -1) -> float:
	var army_index := commanded_army if index < 0 else index
	var stance: float = {"march":1.0,"forced":1.5,"ambush":0.5,"raid":0.75,"camp":0.65}[campaign.stances[army_index]]
	return stance * Forces.march_multiplier(forces.armies[army_index])

func stationed_city(index: int) -> String:
	if campaign.leaders[index].get("fallen",false): return ""
	var faction := Geo.army_faction(index)
	var id := current_city if index == commanded_army else (other_marches.get(index,{}).get("city",forces.stations[index]) as String)
	if id.is_empty() or campaign.owner(id) != faction or campaign.cities[id].rebel:
		return ""
	var point := army_positions[index]
	if point.distance_squared_to(Geo.position_of(id)) <= 9.0 or point.distance_squared_to(camp_on_land(id,index)) <= 9.0:
		return id
	return ""

func detached_troops(faction: int) -> Array:
	var troops := []
	for city in forces.garrisons:
		if campaign.owner(city) == faction:
			for unit in forces.garrisons[city]:
				if not Forces.is_city_militia(city,unit):
					troops.append(unit)
	return troops

func faction_finances(faction: int) -> Dictionary:
	var troops := detached_troops(faction)
	for i in armies.size():
		if Geo.army_faction(i) == faction:
			troops.append_array(forces.armies[i])
	return campaign.finances(faction,troops)

func recruitment_issue(city: String, kind: String, garrison: bool) -> String:
	for requirement in recruitment_requirements(city,kind,garrison):
		if not requirement.issue.is_empty(): return requirement.issue
	return ""

func recruitment_requirements(city: String, kind: String, garrison: bool) -> Array[Dictionary]:
	var checks: Array[Dictionary] = []
	if not garrison and campaign.leaders[commanded_army].get("fallen",false):
		checks.append({"label":"","issue":"Сначала соберите войско под началом нового воеводы."})
	if not garrison and not CampaignState.MERCENARY_REGIONS.has(kind) and stationed_city(commanded_army) != city:
		checks.append({"label":"","issue":"Войдите в свой город, чтобы нанять обычные войска."})
	if not garrison and CampaignState.MERCENARY_REGIONS.has(kind) and region_at(army_positions[commanded_army]) != city:
		checks.append({"label":"","issue":"В этой местности нет выбранных наёмников."})
	var roster: Array = forces.garrisons.get(city,[]) if garrison else forces.armies[commanded_army]
	checks.append_array(campaign.recruit_requirements(0,city,kind,roster,garrison))
	return checks

func can_disband_unit(city: String, unit: Dictionary) -> bool:
	if not player_orders_allowed() or unit.kind == "princely" or unit.get("commander",false): return false
	if not city.is_empty() and (campaign.owner(city) != 0 or Forces.is_city_militia(city,unit)): return false
	return true

func disband_unit(city: String, unit_id: String) -> bool:
	var roster: Array = forces.armies[commanded_army] if city.is_empty() else forces.garrisons.get(city,[])
	var index := roster.find_custom(func(unit): return unit.id == unit_id)
	if index < 0 or not can_disband_unit(city,roster[index]) or (city.is_empty() and roster.size() <= 1):
		return false
	var unit: Dictionary = roster.pop_at(index)
	campaign.note("Распущен отряд «%s» (%d воинов)" % [Forces.squad_name(unit),unit.count])
	movement = minf(movement,MOVE_PER_TURN*stance_movement())
	refresh_ui()
	return true

func transfer_issue(id: String, unit: Dictionary, to_garrison: bool) -> String:
	if not player_orders_allowed(): return "Дождитесь начала своего хода."
	if id.is_empty() or stationed_city(commanded_army) != id: return "Приведите дружину в этот город."
	if Forces.is_city_militia(id,unit): return "Городское ополчение защищает только свой город."
	if unit.kind == "princely": return "Личная дружина остаётся при воеводе."
	if to_garrison:
		if forces.armies[commanded_army].size() <= 1: return "При воеводе должен остаться хотя бы один отряд."
		if forces.garrisons[id].size()+campaign.pending_recruits(0,id).size() >= CampaignState.LIMIT: return "Гарнизон заполнен."
	elif forces.armies[commanded_army].size() + campaign.pending_recruits(0).size() >= CampaignState.LIMIT:
		return "В дружине нет свободного места."
	return ""

func upgrade_unit_equipment(city: String, unit_id: String, field: bool, armor: bool) -> bool:
	if not player_orders_allowed() or campaign.owner(city) != 0:
		return false
	if field and stationed_city(commanded_army) != city:
		return false
	var roster: Array = forces.armies[commanded_army] if field else forces.garrisons.get(city,[])
	var index := roster.find_custom(func(unit): return unit.id == unit_id)
	if index < 0 or Forces.is_city_militia(city,roster[index]):
		return false
	return campaign.improve_equipment(0,city,roster[index],armor)

func transfer_unit(id: String, unit_id: String, to_garrison: bool) -> bool:
	var garrison: Array = forces.garrisons.get(id,[])
	var army: Array = forces.armies[commanded_army]
	var source := army if to_garrison else garrison
	var target := garrison if to_garrison else army
	var index := source.find_custom(func(unit): return unit.id == unit_id)
	if index < 0:
		return false
	var unit: Dictionary = source[index]
	if not transfer_issue(id,unit,to_garrison).is_empty():
		return false
	source.remove_at(index)
	target.append(unit)
	movement = minf(movement,MOVE_PER_TURN*stance_movement())
	armies[commanded_army].show()
	refresh_ui()
	return true

func refresh_garrison(id: String, replenish := false) -> void:
	var town: Dictionary = campaign.cities[id]
	var barracks: int = 0 if town.damage.has("barracks") else town.buildings.get("barracks",0)
	var wall: int = 0 if town.damage.has("wall") else town.buildings.get("wall",0)
	var maximum := 38 + wall * 12 + barracks * 6
	if barracks >= 2:
		maximum += 12 + barracks * 4
	var count := 0 if forces.garrisons.has(id) else maximum
	var reserve_xp_total := 0.0
	var detachments := []
	for unit in forces.garrisons.get(id,[]):
		if Forces.is_local_garrison(id,unit):
			count += unit.count
			reserve_xp_total += float(unit.get("xp",0)) * unit.count
		else:
			if replenish and not Forces.is_city_militia(id,unit): campaign.replenish_from_province(unit,id,.12)
			detachments.append(unit)
	var veterans := count
	var reserve_xp := reserve_xp_total / maxi(1,veterans)
	if replenish:
		var faction: int = campaign.owner(id)
		var province: int = Geo.CITIES[id][1]
		var replacements := mini(maxi(0,maximum-count),ceili(maximum*.2))
		replacements = mini(replacements,campaign.province_manpower(faction,province))
		if replacements > 0 and campaign.spend_manpower(faction,province,replacements):
			count += replacements
	count = mini(count,maximum)
	if count > 0:
		detachments.push_front({"id":id+"_garrison_militia", "kind":"militia", "title":"Ополченцы", "count":count, "max":maximum, "xp":reserve_xp})
	forces.garrisons[id] = detachments

func advance_campaign() -> void:
	for faction in Geo.FACTIONS.size():
		if faction == Geo.REBELS or campaign.factions[faction].get("defeated",false): continue
		# Crisis measures take this turn's budget and food ahead of development and field recruitment.
		var routine_ai := faction > 0 and not campaign.prepare_ai_order(faction,campaign_army_entries(faction),turn,forces.garrisons,detached_troops(faction))
		if routine_ai:
			manage_ai(faction)
		var army_turns: Array[Dictionary] = []
		var previous_rosters := {}
		for index in armies.size():
			if Geo.army_faction(index) != faction:
				continue
			if routine_ai:
				manage_ai_army(index,faction)
			if forces.armies[index].is_empty(): continue
			previous_rosters[index] = forces.armies[index].duplicate()
			army_turns.append(campaign_army_entry(index))
		campaign.advance(faction,army_turns,turn,detached_troops(faction),forces.garrisons)
		for entry in army_turns:
			var aged_oleg: bool = entry.index == 0 and campaign.leaders[0].age >= 62
			if aged_oleg or field_leader_lost(previous_rosters[entry.index],entry.roster):
				record_fallen_leader(entry.index,entry.region)
	update_faction_defeats()
	movement = MOVE_PER_TURN*stance_movement()
	for index in other_marches:
		other_marches[index].movement = MOVE_PER_TURN*stance_movement(index)
	if not campaign_defeated:
		campaign.run_advisors()
	armies[0].visible = not forces.armies[0].is_empty()
	for index in range(1,armies.size()):
		update_army_piece(index,false)
	forces.holdings = forces.holdings.filter(func(id): return campaign.owner(id)==0)
	for city in Geo.CITIES:
		if not campaign.sieges.has(city) and not campaign.cities[city].rebel:
			refresh_garrison(city,province_finances(campaign.owner(city),Geo.CITIES[city][1]).food > 0 and campaign.occupation_issue(city).is_empty())
	if campaign_defeated:
		sync_settlement_models()
		sync_siege_models()
		return
	for city in campaign.sieges.keys():
		var siege: Dictionary = campaign.sieges[city]
		var besieger: int = siege.get("army",0)
		if forces.armies[besieger].is_empty() or army_positions[besieger].distance_to(Geo.position_of(city)) > EnemyTurn.SIEGE_CAMP_RANGE or not can_attack_city(city):
			campaign.sieges.erase(city)
			continue
		siege.turns += 1
		siege.ram += 1
		for unit in forces.garrisons.get(city,[]).duplicate():
			unit.count -= ceili(unit.count*0.14)
			if unit.count <= 0: forces.garrisons[city].erase(unit)
		if siege_turns_remaining(city) == 0:
			command_army(besieger)
			pending_capture = city
			campaign.sieges.erase(city)
			battle_summary = {"title":"Гарнизон сдался","target":Geo.CITIES[city][0],"own_losses":0,"enemy_losses":0,"remaining":forces.headcount(forces.armies[besieger])}
			break
		elif siege.turns >= 2 and not siege.get("sortie",false):
			var guard := city_guard(city)
			var power := roster_power(forces.garrisons.get(city,[]))
			if guard>0: power += roster_power(forces.armies[guard])
			if power>roster_power(forces.armies[besieger])*0.82:
				command_army(besieger)
				siege.sortie = true
				queue_battle(city,guard,true,true,true)
				break
	sync_settlement_models()
	sync_siege_models()

func manage_ai(faction: int) -> void:
	for key in CampaignState.AI_TECH_ORDER:
		if campaign.research(faction,key): break
	var entries := campaign_army_entries(faction)
	for id in Geo.CITIES:
		if campaign.owner(id) != faction:
			continue
		var town: Dictionary = campaign.cities[id]
		if not town.queue.is_empty():
			continue
		if not town.damage.is_empty():
			campaign.build(faction,id,town.damage.keys()[0],"repair")
			continue
		var food: int = campaign.province_account(faction,Geo.CITIES[id][1],entries,forces.garrisons).food
		var forecast: Dictionary = campaign.order_forecast(id,food,entries,forces.garrisons)
		var needs_order: bool = forecast.next < town.order or forecast.next <= CampaignState.UNREST_ORDER
		if needs_order and campaign.ai_shrine_viable(id,food) and campaign.build(faction,id,"shrine"):
			continue
		var trading_city: bool = id in Geo.TRADE_CITIES
		var can_develop_market: bool = trading_city and campaign.ai_market_viable(id,food,entries,forces.garrisons)
		if town.buildings.size()<campaign.building_slots(id):
			var priority := ["market","warehouse","barracks"] if trading_city else ["barracks","forge","range","stables","farm"]
			priority.insert(1,CampaignState.local_special_building(id))
			for key in priority:
				if key == "market" and not can_develop_market: continue
				if not town.buildings.has(key) and campaign.build(faction,id,key): break
		elif campaign.factions[faction].silver > 280:
			var preferred := "farm" if food < 5 else ("market" if can_develop_market else "barracks")
			if preferred == "farm" and campaign.build(faction,id,"farm","build",CampaignState.FISHING_BRANCH):
				continue
			if campaign.build(faction,id,preferred):
				continue
			if campaign.ai_wall_upgrade_viable(id,faction_finances(faction).net) and campaign.build(faction,id,"wall"):
				continue
			campaign.build(faction,id,"hall")
	if campaign.factions[faction].loyalty < 40:
		campaign.patronage(faction)
	for province in Geo.PROVINCES.size():
		if not campaign.factions[faction].edicts.has(province):
			campaign.edict(faction,province,"trade")
func manage_ai_army(index: int, faction: int) -> void:
	if forces.armies[index].is_empty():
		raise_army(index)
		return
	var station := stationed_city(index)
	if not station.is_empty() and forces.armies[index].size()<6:
		var province: int = Geo.CITIES[region_at(army_positions[index])][1]
		var budget := ai_recruitment_budget(faction,province)
		for kind in ["cavalry","light_cavalry","infantry","archer","militia"]:
			if not CampaignState.unit_fits_upkeep(kind,budget): continue
			if campaign.recruit(faction,station,kind,forces.armies[index]): break

func ai_recruitment_budget(faction: int, province: int) -> Vector2i:
	var food: int = province_finances(faction,province).food
	return campaign.recruitment_upkeep_budget(faction,province,faction_finances(faction).net,food)

func raise_army(index: int) -> bool:
	var faction := Geo.army_faction(index)
	if campaign.factions[faction].get("defeated",false) or not forces.armies[index].is_empty():
		return false
	var fallen: bool = campaign.leaders[index].get("fallen",false)
	if index == 0 and fallen: return false
	if faction == 0 and campaign.factions[faction].silver < 110: return false
	var town := ""
	for city in Geo.CITIES:
		if campaign.owner(city)==faction and not campaign.cities[city].rebel and campaign.occupation_issue(city).is_empty():
			if faction != 0:
				if not campaign.hero_hire_issue(city,faction).is_empty(): continue
				var province: int = Geo.CITIES[city][1]
				if not CampaignState.unit_fits_upkeep("princely",ai_recruitment_budget(faction,province)): continue
			town = city
			if city == Geo.army_home(index): break
	if town.is_empty():
		return false
	if faction != 0:
		if not campaign.spend_manpower(faction,Geo.CITIES[town][1],CampaignState.UNITS.princely[1]): return false
		campaign.factions[faction].silver -= campaign.hero_cost(town)
	else:
		campaign.factions[faction].silver -= 110
	if fallen:
		campaign.succession(index)
	campaign.serial += 1
	forces.armies[index] = forces.roster("raised_%d" % campaign.serial,[["princely",CampaignState.UNITS.princely[1]]])
	campaign.name_squad(forces.armies[index][0],town)
	forces.stations[index] = town
	if index == commanded_army:
		place_player(camp_on_land(town,index),town)
	armies[index].show()
	update_army_piece(index)
	campaign.note("%s собирает войско в городе %s" % [campaign.leaders[index].name,Geo.CITIES[town][0]])
	return true

func march_state() -> Dictionary:
	return {"movement":movement,"city":current_city,"destination":destination,"destination_army":destination_army,
		"has_route":has_route,"preview":march_preview,"path":path,"marks":distance_marks,"traveled":traveled,"goal":travel_goal,
		"origin":march_origin,"origin_city":march_origin_city}

func restore_march(state: Dictionary) -> void:
	pending_march.clear()
	movement = state.movement
	current_city = state.city
	destination = state.get("destination","")
	destination_army = state.get("destination_army",-1)
	has_route = state.get("has_route",false)
	march_preview = has_route and state.get("preview",false)
	path = state.get("path",PackedVector2Array())
	distance_marks = state.get("marks",PackedFloat32Array())
	traveled = state.get("traveled",0.0)
	travel_goal = state.get("goal",0.0)
	march_origin = state.get("origin",army_positions[commanded_army])
	march_origin_city = state.get("origin_city",current_city)
	march_notice = ""
	march_obstacle = null

func campaign_slot_path(slot: CampaignSave.Slot) -> String:
	return CampaignSave.slot_path(save_file,slot)

func can_load_campaign() -> bool:
	return not battle_loading and get_parent() == get_tree().root

func save_campaign(slot := CampaignSave.Slot.MANUAL) -> bool:
	if slot == CampaignSave.Slot.MANUAL and (not can_load_campaign() or not player_orders_allowed()): return false
	var data := march_state()
	data.merge({"version":CampaignSave.VERSION,"campaign":campaign.snapshot(),"armies":forces.armies,"stations":forces.stations,"garrisons":forces.garrisons,"positions":army_positions,
		"explored":fog.explored,"turn":turn,"commanded_army":commanded_army,"other_marches":other_marches,"retreat_turns":retreat_turns,
		"enemy_actor":enemy_actor,"operations":enemy_operations,"encounter":encounter,"capture":pending_capture,"summary":battle_summary,"defeated":campaign_defeated,
		"story_stage":story_stage,"show_summary":battle_menu.visible and encounter.is_empty()})
	var error := CampaignSave.write(campaign_slot_path(slot),data)
	if slot == CampaignSave.Slot.MANUAL:
		march_notice = "Кампания сохранена" if error == OK else "Не удалось записать сохранение"
		refresh_ui()
	elif error != OK:
		campaign.note("Не удалось записать автосохранение")
		push_warning("Campaign autosave failed: %s" % error_string(error))
	return error == OK

func load_campaign(slot := CampaignSave.Slot.MANUAL) -> bool:
	if not can_load_campaign(): return false
	var file := FileAccess.open(campaign_slot_path(slot),FileAccess.READ)
	if file == null:
		march_notice = "Не удалось открыть сохранение"
		refresh_ui()
		return false
	var data: Variant = file.get_var(false)
	file.close()
	if data is Dictionary and data.get("campaign") is Dictionary:
		data = CampaignSave.upgrade(data)
	if not data is Dictionary or data.is_empty() or not data.get("campaign") is Dictionary:
		march_notice = "Файл кампании повреждён или имеет несовместимую версию"
		refresh_ui()
		return false
	for key in ["armies","positions","stations"]:
		if not data.get(key) is Array:
			march_notice = "Не удалось восстановить армии из сохранения"
			refresh_ui()
			return false
	var count: int = data.armies.size()
	if count < Geo.ARMIES.size() or data.get("positions",[]).size()!=count or data.get("stations",[]).size()!=count or data.campaign.get("leaders",[]).size()!=count or data.campaign.get("stances",[]).size()!=count:
		march_notice = "Не удалось восстановить армии из сохранения"
		refresh_ui()
		return false
	battle_menu.hide()
	if is_instance_valid(construction_warning): construction_warning.hide()
	management.close_details()
	dragging = false
	var rewards := campaign.restore(data.campaign)
	story_stage = data.get("story_stage",StoryStage.NONE)
	# Earlier saves ended after Ladoga (2), Russa (3), Kholm (4) or Smolensk (5).
	skip_held_story_targets()
	forces.armies = data.armies
	forces.stations.assign(data.stations)
	forces.garrisons = data.garrisons
	while armies.size()>count:
		armies.pop_back().queue_free()
		army_buttons.pop_back().queue_free()
		army_positions.pop_back()
		riders.pop_back()
		control_rings.pop_back()
	while armies.size()<count:
		var index := armies.size()
		make_army_piece(index,data.positions[index])
		make_army_pin(index)
	commanded_army = data.get("commanded_army",0)
	if not is_player_army(commanded_army): commanded_army = 0
	selected_army = commanded_army
	selected_city = ""
	other_marches = data.get("other_marches",{})
	retreat_turns = data.get("retreat_turns",{})
	for army in forces.armies:
		Forces.normalize_units(army)
	for garrison in forces.garrisons.values():
		Forces.normalize_units(garrison)
	name_existing_squads()
	for faction in campaign.recruitment.size():
		var queue: Array = campaign.recruitment[faction]
		for item in queue.duplicate():
			if item.unit.kind == "princely":
				queue.erase(item)
				campaign.factions[faction].silver += CampaignState.UNITS.princely[2]
		campaign.finish_legacy_field_recruits(faction,forces.armies[faction])
	forces.holdings.clear()
	for id in Geo.CITIES:
		if campaign.owner(id) == 0: forces.holdings.append(id)
	fog.restore(data.get("explored"))
	army_positions.assign(data.positions)
	for i in armies.size():
		armies[i].visible = not forces.armies[i].is_empty()
		armies[i].position = terrain.surface(army_positions[i],0.30)
		riders[i].set_gait(&"Idle")
	update_fog(true)
	turn = data.turn
	announced_turn = 0
	restore_march(data)
	enemy_actor = data.enemy_actor
	enemy_operations = data.get("operations",{})
	for index in data.get("patrols",{}):
		enemy_operations[index] = {"kind":"patrol","city":data.patrols[index]}
	enemy_acted = false
	enemy_plan.clear()
	enemy_budget = EnemyTurn.MOVE
	enemy_step = 1
	enemy_delay = 0.0
	encounter = data.encounter
	var legacy := int(data.version) < 4
	if legacy:
		for id in Geo.CITIES:
			refresh_garrison(id)
	if not encounter.is_empty():
		# A saved encounter contains copies of the campaign units.
		var city: String = encounter.city
		var rebellion: bool = encounter.get("rebellion",false)
		var roster: Array = campaign.rebellions.get(city,{}).get("roster",[]) if rebellion else forces.garrisons.get(city,[])
		var saved_roster: Array = encounter.defenders if rebellion else encounter.get("garrison",[])
		for unit in saved_roster:
			for original in roster:
				if original.id == unit.id and original.has("squad_name"):
					unit["squad_name"] = original.squad_name
					break
		if encounter.has("landscape"):
			encounter.landscape["season"] = campaign_season()
		Forces.normalize_units(encounter.attackers)
		Forces.normalize_units(encounter.defenders)
		Forces.normalize_units(encounter.get("garrison",[]))
		if encounter.has("support_city"):
			var team := 0 if encounter.support_side == "attackers" else 1
			encounter["support"] = [{"city":encounter.support_city,"team":team,"roster":encounter.reinforcements}]
			for key in ["support_city","support_side","reinforcements"]: encounter.erase(key)
		for source in encounter.get("support",[]):
			Forces.normalize_units(source.roster)
		if encounter.city_battle and legacy:
			var side := "attackers" if encounter.get("defending_city",false) else "defenders"
			var old_garrison_ids: Array = encounter.garrison.map(func(unit): return unit.id)
			var field_troops: Array = encounter[side].filter(func(unit): return unit.id not in old_garrison_ids)
			encounter.garrison = forces.garrisons[encounter.city]
			encounter[side] = encounter.garrison + field_troops
		if legacy:
			set_encounter_identity()
		else:
			set_encounter_commanders()
			set_encounter_banner_colors()
		if encounter.get("defending_city",false): encounter.retreat_allowed = false
		for source in encounter.get("support",[]):
			if source.has("army"):
				source.portrait = campaign.leader_portrait(source.army)
		validate_saved_battle_support()
	battle_summary = data.summary
	pending_capture = data.capture
	if legacy or data.campaign.get("schema",0) < 6:
		if data.get("defeated",false) and battle_summary.get("leader_fell",false):
			record_fallen_leader(0,region_at(army_positions[0]))
		for index in forces.armies.size():
			if forces.armies[index].is_empty():
				campaign.leaders[index].fallen = true
		if battle_summary.get("title","") == "Кампания проиграна":
			battle_summary.title = "Поражение"
	var defeat_notices := update_faction_defeats()
	if enemy_actor > 0: ensure_navigation()
	if campaign_defeated or not encounter.is_empty() or not pending_capture.is_empty() or (data.get("show_summary",false) and not battle_summary.is_empty()):
		show_battle_menu()
	if traveled < travel_goal:
		riders[commanded_army].set_gait(&"Walk")
	draw_route()
	sync_settlement_models()
	zoom = DEFAULT_MAP_ZOOM
	center_camera_on_player()
	project_markers()
	march_notice = rewards[0] if rewards.size() == 1 else "Кампания загружена"
	if rewards.size() > 1:
		march_notice = "Награды за объединение областей · +%d серебра" % (rewards.size()*CampaignState.PROVINCE_UNIFICATION_REWARD)
	if not defeat_notices.is_empty():
		march_notice = " · ".join(defeat_notices)
	refresh_ui()
	return true

func sync_settlement_models() -> void:
	for id in Geo.CITIES:
		var town: Dictionary = campaign.cities[id]
		terrain.sync_district(id,town.buildings,town.damage,town.building_branches,Geo.faction_appearance(town.owner, id).color.lightened(.28))

func sync_siege_models() -> void:
	var visible_sieges := {}
	for id in campaign.sieges:
		if fog.visible_at(Geo.position_of(id)):
			visible_sieges[id] = campaign.sieges[id].get("turns",0)
	terrain.sync_sieges(visible_sieges)

func make_regional_boundaries() -> void:
	territory_borders = preload("res://campaign_map/territory_borders.gd").new()
	territory_borders.build(self)

func can_see_army(index: int) -> bool:
	return is_player_army(index) or fog.visible_at(army_positions[index])

func update_fog(force := false) -> void:
	var sources: Array[Vector3] = []
	for i in armies.size():
		if is_player_army(i) and not forces.armies[i].is_empty():
			var point: Vector2 = army_positions[i].snapped(Vector2.ONE*2.0)
			sources.append(Vector3(point.x,point.y,140.0))
	for id in Geo.CITIES:
		if campaign.owner(id) == 0 and not campaign.cities[id].rebel:
			var point := Geo.position_of(id)
			sources.append(Vector3(point.x,point.y,115.0))
	var order := story_order()
	if not order.is_empty():
		var target := Geo.position_of(order.city)
		sources.append(Vector3(target.x,target.y,18.0))
	fog.update(sources,force)
	var visibility := []
	for i in armies.size():
		var seen := can_see_army(i)
		visibility.append(seen)
		for child in armies[i].get_children():
			if child is Node3D:
				child.visible = seen and (child.name != "SelectionAura" or (i==selected_army and selected_city.is_empty()))
		control_rings[i].visible = seen and (i==selected_army or (i>0 and zoom<600))
	if selected_army > 0 and not can_see_army(selected_army):
		selected_army = commanded_army
		if is_instance_valid(management): refresh_ui()
	if not selected_city.is_empty() and not fog.visible_at(Geo.position_of(selected_city)):
		selected_city = ""
		if is_instance_valid(management): management.close_details()
	var signature := hash(visibility)
	if signature != last_visibility:
		last_visibility = signature
		if is_instance_valid(management): refresh_ui()
	elif not campaign.sieges.is_empty():
		sync_siege_models()

func campaign_army_entry(index: int) -> Dictionary:
	return {"index":index,"roster":forces.armies[index],"region":region_at(army_positions[index]),"station":stationed_city(index)}

func campaign_army_entries(faction: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for index in armies.size():
		if Geo.army_faction(index) == faction and not forces.armies[index].is_empty():
			entries.append(campaign_army_entry(index))
	return entries

func city_order_forecast(id: String) -> Dictionary:
	var faction: int = campaign.owner(id)
	var entries := campaign_army_entries(faction)
	var local: Dictionary = campaign.province_account(faction,Geo.CITIES[id][1],entries,forces.garrisons)
	return campaign.order_forecast(id,local.food,entries,forces.garrisons)

func province_finances(faction: int, province: int) -> Dictionary:
	var entries := []
	for i in armies.size():
		if Geo.army_faction(i) == faction:
			entries.append({"roster":forces.armies[i],"region":region_at(army_positions[i])})
	return campaign.province_account(faction,province,entries,forces.garrisons)

func queue_rebellion(city: String) -> void:
	if not player_orders_allowed() or not campaign.rebellions.has(city): return
	encounter = {"city":city,"army":-1,"city_battle":false,"enemy_attack":false,"rebellion":true,
		"target":"Повстанцы у города "+Geo.CITIES[city][0],"title":"Подавление мятежа · "+Geo.CITIES[city][0],
		"garrison":[],"attackers":forces.armies[commanded_army],"defenders":campaign.rebellions[city].roster,"fortified":false,"ram":false}
	if not gather_battle_support():
		encounter = {}
		return
	set_encounter_identity()
	show_battle_menu.call_deferred()

func attack_rebels(city: String) -> void:
	if not player_orders_allowed(): return
	if army_positions[commanded_army].distance_to(Geo.position_of(city)) < 34:
		queue_rebellion(city)
	else: order_to(city,-1,true)

func sync_rebel_pieces() -> void:
	if city_buttons.is_empty(): return
	for id in rebel_pieces.keys():
		if not campaign.rebellions.has(id):
			rebel_pieces[id].piece.queue_free()
			rebel_pieces[id].pin.queue_free()
			rebel_pieces.erase(id)
	for id in campaign.rebellions:
		if rebel_pieces.has(id): continue
		var piece := Node3D.new()
		add_child(piece)
		piece.position = terrain.surface(Geo.position_of(id)+Vector2(-24,14),.2)
		var rider := HORSEMAN.instantiate() as Node3D
		piece.add_child(rider)
		rider.scale = Vector3.ONE*5.5
		terrain.box(Vector3(.3,18,.3),terrain.material(Color("88714f")),Vector3(-3,9,0),piece)
		var cloth := PlaneMesh.new()
		cloth.orientation = PlaneMesh.FACE_Z
		cloth.size = Vector2(5,7)
		var fabric := StandardMaterial3D.new()
		fabric.albedo_texture = UI.faction_flag(Geo.REBELS, id)
		fabric.cull_mode = BaseMaterial3D.CULL_DISABLED
		cloth.material = fabric
		terrain.place_mesh(cloth,Vector3(-5.4,14,0),piece)
		var pin := preload("res://campaign_map/ui_map_pin.gd").new()
		pin.text = "Повстанцы"
		pin.army = true
		pin.tone = Geo.faction_appearance(Geo.REBELS, id).color
		pin.flag = UI.faction_flag(Geo.REBELS, id)
		pin.pressed.connect(attack_rebels.bind(id))
		city_buttons.values()[0].get_parent().add_child(pin)
		pin.size = pin.marker_size()
		rebel_pieces[id] = {"piece":piece,"pin":pin}
	for id in rebel_pieces:
		var pin: Button = rebel_pieces[id].pin
		pin.tooltip_text = "Разгромить отряд повстанцев: +25 к порядку и снятие штрафа за отряд."
		var squads := Forces.squad_tooltip(campaign.rebellions[id].roster)
		if not squads.is_empty(): pin.tooltip_text += "\n"+squads
	project_rebels()

func project_rebels() -> void:
	for id in rebel_pieces:
		var entry: Dictionary = rebel_pieces[id]
		var seen := fog.visible_at(Geo.position_of(id))
		entry.piece.visible = seen
		entry.pin.visible = seen and not camera.is_position_behind(entry.piece.position)
		if entry.pin.visible:
			entry.pin.position = camera.unproject_position(entry.piece.position+Vector3.UP*18)-entry.pin.size*.5

func battle_landscape() -> Dictionary:
	var point: Vector2 = Geo.position_of(encounter.city) if encounter.city_battle else army_positions[commanded_army]
	var samples := PackedFloat32Array()
	var trees := PackedFloat32Array()
	for z in 17:
		for x in 17:
			var at := point+Vector2(x-8,z-8)*9.0
			samples.append(terrain.relief_height(at))
			trees.append(terrain.forest_cover(at))
	var water_side := -1
	var nearest := 50.0
	for i in 4:
		var direction: Vector2 = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN][i]
		var distance: float = terrain.signed_water_distance(point+direction*38.0)
		if distance < nearest:
			nearest = distance
			water_side = i
	return {"seed":hash(encounter.city+str(point.snapped(Vector2.ONE*10))),"season":campaign_season(),
		"heights":samples,"forest":trees,"water_side":water_side if nearest<5.0 else -1,
		"caption":Geo.PROVINCES[Geo.CITIES[encounter.city][1]][0],"city":encounter.city_battle}
