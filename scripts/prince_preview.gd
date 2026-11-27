extends Node3D
const FACTIONS = preload("res://campaign_map/geography.gd").FACTIONS
var foot: Node3D
var rider: Node3D
var camera: Camera3D
var players: Array[AnimationPlayer] = []
var angle := .28
var distance := 6.4
var target := Vector3(0, 1.3, 0)
var dragging := false
var mode := 0
var clock := 0.0
var capture_stage := 0
var capture := false
var hud: CanvasLayer
var shields: Array[Node3D] = []
var crest_button: CheckButton

func _ready() -> void:
	get_tree().root.content_scale_size = Vector2i(1440, 1000)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("242a33")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b2bcd0")
	environment.environment.ambient_light_energy = .65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(environment)
	for entry in [[Vector3(-3, 5, 4), 2.0, Color("ffe2b5")], [Vector3(3, 4, -3), 1.5, Color("b8d5ff")]]:
		var light := DirectionalLight3D.new()
		add_child(light)
		light.position = entry[0]
		light.look_at(Vector3(0, 1, 0))
		light.light_energy = entry[1]
		light.light_color = entry[2]
		light.shadow_enabled = true
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("303741")
	floor_material.roughness = .95
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	foot = preload("res://scenes/prince_foot.tscn").instantiate()
	foot.position.x = -1.30
	add_child(foot)
	add_foot_equipment()
	rider = preload("res://scenes/prince_mounted.tscn").instantiate()
	rider.position.x = 1.1
	add_child(rider)
	shields.append(rider.find_child("Rider shield", true, false))
	for actor in [foot, rider]:
		players.append(actor.find_children("*", "AnimationPlayer", true, false)[0])
	camera = Camera3D.new()
	camera.fov = 40
	add_child(camera)
	update_camera()
	make_hud()
	set_faction(0)
	set_motion(0)
	capture = "--capture-prince" in OS.get_cmdline_user_args()
	if capture:
		DirAccess.make_dir_recursive_absolute("res://build/prince")

func add_foot_equipment() -> void:
	var skeleton: Skeleton3D = foot.find_children("*", "Skeleton3D", true, false)[0]
	for entry in [["GripRight", "spear"], ["GripLeft", "shield"]]:
		var socket := BoneAttachment3D.new()
		socket.bone_name = entry[0]
		skeleton.add_child(socket)
		var equipment: Node3D = load("res://assets/%s.glb" % entry[1]).instantiate()
		socket.add_child(equipment)
		equipment.scale = Vector3.ONE / 1.8
		equipment.rotation.x = PI / 2.0
		if entry[1] == "shield": shields.append(equipment)

func make_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 20)
	hud.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var title := Label.new()
	title.text = "КНЯЗЬ · ПЛАЩ И ГЕРБ"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color("e6d2ad"))
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for i in 3:
		var button := Button.new()
		button.text = ["Покой", "Шаг", "Бег / галоп"][i]
		button.pressed.connect(set_motion.bind(i))
		row.add_child(button)
	var factions := OptionButton.new()
	for faction in FACTIONS: factions.add_item(faction.name)
	factions.add_item("Без герба — чистая ткань")
	factions.item_selected.connect(set_faction)
	row.add_child(factions)
	var back := Button.new()
	back.text = "Спереди / сзади"
	back.pressed.connect(func(): angle += PI; update_camera())
	row.add_child(back)
	crest_button = CheckButton.new()
	crest_button.text = "Показать герб"
	crest_button.toggled.connect(func(value: bool):
		for shield in shields: shield.visible = not value)
	row.add_child(crest_button)
	var help := Label.new()
	help.text = "Зажмите ЛКМ и вращайте · колесо — масштаб · 1 / 2 / 3 — движение · пробел — пауза"
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color("acb8c8")
	box.add_child(help)

func set_faction(index: int) -> void:
	var texture: Texture2D = null
	var color := Color(.25, .34, .44)
	if index < FACTIONS.size():
		texture = load("res://assets/banners/factions/%s.svg" % FACTIONS[index].banner)
		color = FACTIONS[index].color
	foot.set_faction_crest(texture)
	rider.set_faction_crest(texture)
	foot.set_cloak_color(color)
	rider.set_cloak_color(color)

func set_motion(index: int) -> void:
	mode = index
	for i in 2:
		var player := players[i]
		var wanted: String = [["motion_idle_spear", "motion_walk_spear", "motion_run_spear"], ["Idle", "Walk", "Gallop"]][i][index]
		for full_name in player.get_animation_list():
			if String(full_name).get_file() == wanted:
				player.get_animation(full_name).loop_mode = Animation.LOOP_LINEAR
				player.play(full_name, .25)
				break
	foot.cloth.wind_velocity = Vector3(0, 0, -[0.0, 1.4, 3.8][index])
	rider.cloth.wind_velocity = Vector3(0, 0, -[0.0, 1.7, 6.0][index])

func update_camera() -> void:
	camera.position = target + Vector3(sin(angle) * distance, distance * .23, cos(angle) * distance)
	camera.look_at(target)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance + (-.35 if event.button_index == MOUSE_BUTTON_WHEEL_UP else .35), 2.0, 12.0)
			update_camera()
	if event is InputEventMouseMotion and dragging:
		angle -= event.relative.x * .008
		update_camera()
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_1, KEY_2, KEY_3]: set_motion(event.keycode - KEY_1)
		if event.keycode == KEY_SPACE:
			var speed := 0.0 if players[0].speed_scale > 0 else 1.0
			for player in players: player.speed_scale = speed
			foot.cloth.set_process(speed > 0)
			rider.cloth.set_process(speed > 0)

func _process(delta: float) -> void:
	if not capture: return
	clock += delta
	if clock < 2.5: return
	clock = 0.0
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/prince/preview_%d.png" % capture_stage)
	print("PRINCE_CAPTURE ", capture_stage, " FOOT ", foot.cloth.diagnostics(), " RIDER ", rider.cloth.diagnostics())
	capture_stage += 1
	if capture_stage == 1:
		angle = PI + .4; update_camera(); set_motion(1)
	elif capture_stage == 2:
		set_motion(2)
	elif capture_stage == 3:
		angle = .05; distance = 2.9; target = Vector3(-1.3, 1.23, 0); update_camera(); set_motion(0)
		crest_button.button_pressed = true
	elif capture_stage == 4:
		get_tree().quit()
