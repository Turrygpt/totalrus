extends Node3D

const Generator = preload("res://scripts/tactical_map_generator.gd")
const Lighting = preload("res://scripts/battle_landscape_lighting.gd")
const Terrain = preload("res://scripts/terrain.gd")
const UI = preload("res://campaign_map/ui_theme.gd")
const REFERENCE = preload("res://scenes/tactical_maps/msta_terrace.tres")

var terrain: Node3D
var lighting: Node3D
var weather: Lighting.WorldWeather
var camera: Camera3D
var focus := Vector2.ZERO
var yaw := 0.0
var pitch := .52
var distance := 235.0
var profile_picker: OptionButton
var season_picker: OptionButton
var seed_input: LineEdit
var map_title: Label
var status: Label
var build_button: Button
var random_button: Button
var rebuilding := false
var seed_random := RandomNumberGenerator.new()

func _ready() -> void:
	seed_random.randomize()
	camera = Camera3D.new()
	camera.far = 2700.0
	add_child(camera)
	build_controls()
	rebuild(REFERENCE.seed_value, REFERENCE.profile, 0)

func rebuild(seed_value: int, profile: int, season: int) -> void:
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.queue_free()
	if is_instance_valid(lighting):
		remove_child(lighting)
		lighting.queue_free()
	lighting = Node3D.new()
	lighting.name = "LandscapeLighting"
	add_child(lighting)
	var condition := Lighting.WorldWeather.Weather.SNOW if season == Lighting.WorldWeather.WINTER else Lighting.WorldWeather.Weather.CLEAR
	weather = Lighting.install(lighting, season, condition)
	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.field_half_size = REFERENCE.half_size
	var reference := seed_value == REFERENCE.seed_value and profile == REFERENCE.profile
	terrain.landscape = REFERENCE.landscape(season) if reference else {
		"seed": seed_value, "profile": profile, "season": season,
	}
	add_child(terrain)
	map_title.text = REFERENCE.title if reference else Generator.TITLES[profile]
	reset_camera()

func reset_camera() -> void:
	distance = 235.0
	pitch = .52
	yaw = .45
	var generator: Generator = terrain.generator
	focus = Vector2(generator.road.x * .7, generator.landmark_depth)
	match generator.profile:
		Generator.Profile.WOODLAND, Generator.Profile.RIDGES:
			focus.x = generator.flank * REFERENCE.half_size.x * .48
			yaw = -generator.flank * .72
		Generator.Profile.SHORE:
			var along := generator.landmark_depth if generator.coast < 2 else generator.road.x
			focus = generator.shore_point(-112.0, along)
			yaw = [1.14, -1.14, .4, PI + .40][generator.coast]
	update_camera()

func build_controls() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.theme = UI.theme()
	panel.add_theme_stylebox_override("panel", UI.campaign_frame(12))
	panel.position = Vector2(28, 26)
	layer.add_child(panel)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 394
	content.add_theme_constant_override("separation", 11)
	panel.add_child(content)
	UI.label(content, "ГЕНЕРАТОР ТАКТИЧЕСКИХ КАРТ", 17, UI.GOLD)
	map_title = UI.label(content, "", 34, UI.BONE, true)

	var settings := GridContainer.new()
	settings.columns = 2
	settings.add_theme_constant_override("h_separation", 14)
	settings.add_theme_constant_override("v_separation", 9)
	content.add_child(settings)
	UI.label(settings, "Местность", 19)
	profile_picker = OptionButton.new()
	profile_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for profile in Generator.PLAYABLE_PROFILES:
		profile_picker.add_item(Generator.TITLES[profile], profile)
	profile_picker.select(profile_picker.get_item_index(Generator.Profile.SHORE))
	settings.add_child(profile_picker)
	UI.label(settings, "Сезон", 19)
	season_picker = OptionButton.new()
	season_picker.add_item("Лето", 0)
	season_picker.add_item("Зима", 3)
	settings.add_child(season_picker)
	UI.label(settings, "Seed", 19)
	seed_input = LineEdit.new()
	seed_input.text = str(Generator.DEFAULT_SEED)
	seed_input.text_submitted.connect(func(_value: String): request_rebuild())
	settings.add_child(seed_input)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	content.add_child(buttons)
	build_button = Button.new()
	build_button.text = "Сгенерировать"
	build_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.accent_button(build_button)
	build_button.pressed.connect(request_rebuild)
	buttons.add_child(build_button)
	random_button = Button.new()
	random_button.text = "Случайный seed"
	random_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random_button.pressed.connect(randomize_seed)
	buttons.add_child(random_button)
	status = UI.label(content, "", 16)
	status.hide()

	var help := Label.new()
	help.theme = panel.theme
	help.text = "WASD / стрелки  ·  перемещение     ПКМ  ·  обзор     Колесо  ·  масштаб     Home  ·  исходный вид"
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.add_theme_font_size_override("font_size", 19)
	help.add_theme_color_override("font_color", UI.BONE)
	help.add_theme_color_override("font_shadow_color", Color("191c1b"))
	help.add_theme_constant_override("shadow_offset_x", 1)
	help.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 26)

func randomize_seed() -> void:
	seed_input.text = str(seed_random.randi())
	request_rebuild()

func request_rebuild() -> void:
	if rebuilding:
		return
	var value := seed_input.text.strip_edges()
	var digits := value.trim_prefix("-").trim_prefix("+")
	if not value.is_valid_int() or digits.length() > 18:
		status.text = "Введите целое число до 18 цифр."
		status.show()
		return
	seed_input.release_focus()
	rebuilding = true
	build_button.disabled = true
	random_button.disabled = true
	var profile := profile_picker.get_selected_id()
	var season := season_picker.get_selected_id()
	status.text = "Построение поля…"
	status.show()
	await get_tree().process_frame
	await get_tree().process_frame
	rebuild(value.to_int(), profile, season)
	status.hide()
	build_button.disabled = false
	random_button.disabled = false
	rebuilding = false

func _process(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() == seed_input:
		return
	var direction := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	direction.x += float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	direction.y += float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	if direction.is_zero_approx():
		return
	focus += direction.limit_length().rotated(-yaw) * maxf(40.0, distance * .78) * delta
	var camera_limit: Vector2 = REFERENCE.half_size + Vector2.ONE * 75.0
	focus = focus.clamp(-camera_limit, camera_limit)
	update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * .007
		pitch = clampf(pitch + event.relative.y * .006, .12, 1.48)
		update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance * (.87 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.15), 12.0, 790.0)
			update_camera()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_HOME:
		reset_camera()

func update_camera() -> void:
	var target: Vector3 = terrain.ground_point(focus, 1.1)
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	var camera_point := target + offset
	camera_point.y = maxf(camera_point.y, terrain.height_at(Vector2(camera_point.x, camera_point.z)) + 3.0)
	camera.position = camera_point
	camera.look_at(target)
	Lighting.update_view(weather, camera, distance)

