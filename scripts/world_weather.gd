extends Node3D

const SKY_SHADER = preload("res://scripts/weather_sky.gdshader")
const CLOUD_MAP = preload("res://scripts/weather_clouds.tres")
const PRECIPITATION_SHADER = preload("res://scripts/precipitation.gdshader")
const WINTER := 3
const RAIN_DIRECTION := Vector3(0.24, -1.0, -0.12)

enum Weather { CLEAR, RAIN, SNOW, FOG }

var condition := Weather.CLEAR
var season := -1
var environment: Environment
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var precipitation: GPUParticles3D
var precipitation_material: ShaderMaterial
var close_view := 0.0
var camera_position := Vector3.ZERO
var daylight := 1.0
var winter_daylight := 1.0
var clear_fog := 0.0
var fog_strength := 0.0
var base_fog_begin := 0.0
var base_fog_end := 0.0

static func for_turn(turn: int, current_season: int) -> int:
	match posmod(turn - 1, 6):
		1, 4:
			return Weather.SNOW if current_season == WINTER else Weather.RAIN
		3:
			return Weather.FOG
	return Weather.CLEAR

func install(parent: Node3D, scene_environment: Environment, scene_sun: DirectionalLight3D, cold_daylight: float) -> void:
	name = "Weather"
	environment = scene_environment
	sun = scene_sun
	daylight = sun.light_energy
	winter_daylight = cold_daylight
	clear_fog = environment.fog_density
	base_fog_begin = environment.fog_depth_begin
	base_fog_end = environment.fog_depth_end
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("cloud_map", CLOUD_MAP)
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_sky_affect = 0.0
	parent.add_child(self)

func set_weather(next: int, current_season: int) -> void:
	var winter := current_season == WINTER
	if next == Weather.RAIN and winter:
		next = Weather.SNOW
	if next == condition and season == current_season:
		return
	season = current_season
	condition = next
	var zenith := Color("#4088c1")
	var horizon := Color("#a9c8db")
	var clouds := 0.22
	var sunlight := 1.0
	var light_energy := 1.0
	fog_strength = 0.0
	match condition:
		Weather.RAIN:
			zenith = Color("#576674")
			horizon = Color("#9eacb5")
			clouds = 0.94
			sunlight = 0.0
			light_energy = 0.52
			fog_strength = 0.48
		Weather.SNOW:
			zenith = Color("#7890a5")
			horizon = Color("#c0cdd6")
			clouds = 0.85
			sunlight = 0.0
			light_energy = 0.65
			fog_strength = 0.62
		Weather.FOG:
			zenith = Color("#899ca9")
			horizon = Color("#bac6cb")
			clouds = 0.73
			sunlight = 0.16
			light_energy = 0.58
			fog_strength = 1.0
		Weather.CLEAR:
			if winter:
				zenith = Color("#6b9ac1")
				horizon = Color("#d2e0e9")
	sky_material.set_shader_parameter("zenith", zenith)
	sky_material.set_shader_parameter("horizon", horizon)
	sky_material.set_shader_parameter("cloudiness", clouds)
	sky_material.set_shader_parameter("sunlight", sunlight)
	sun.light_energy = (winter_daylight if winter else daylight) * light_energy
	sun.light_color = Color("#d9e7f5") if winter or sunlight < 0.5 else Color("#fff1d4")
	environment.fog_light_color = horizon.darkened(0.12)
	clear_precipitation()
	update_visibility()

func update_view(camera: Camera3D, amount: float, fog_begin: float, fog_end: float) -> void:
	var position_changed := camera_position != camera.global_position
	camera_position = camera.global_position
	if position_changed and precipitation != null:
		global_position = camera_position
	if amount == close_view and fog_begin == base_fog_begin and fog_end == base_fog_end:
		return
	close_view = amount
	base_fog_begin = fog_begin
	base_fog_end = fog_end
	update_visibility()

func update_visibility() -> void:
	environment.fog_depth_begin = base_fog_begin * lerpf(1.0, 0.68, fog_strength * close_view)
	environment.fog_depth_end = base_fog_end * lerpf(1.0, 0.55, fog_strength * close_view)
	environment.fog_density = lerpf(clear_fog, 0.94, fog_strength * lerpf(0.20, 1.0, close_view))
	if close_view <= 0.015 or condition not in [Weather.RAIN, Weather.SNOW]:
		clear_precipitation()
		return
	if DisplayServer.get_name() == "headless":
		return
	var snow := condition == Weather.SNOW
	if precipitation == null:
		global_position = camera_position
		make_precipitation(snow)
	precipitation_material.set_shader_parameter("opacity", close_view * (0.76 if snow else 0.54))

func clear_precipitation() -> void:
	if precipitation == null:
		return
	remove_child(precipitation)
	precipitation.queue_free()
	precipitation = null
	precipitation_material = null

func make_precipitation(snow: bool) -> void:
	precipitation = GPUParticles3D.new()
	precipitation.name = "Snowfall" if snow else "Rain"
	precipitation.amount = 600 if snow else 720
	precipitation.lifetime = 6.5 if snow else 1.25
	precipitation.preprocess = precipitation.lifetime
	precipitation.local_coords = true
	precipitation.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	precipitation.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD if snow else GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	precipitation.visibility_aabb = AABB(Vector3(-29, -46, -28), Vector3(58, 65, 56))
	precipitation.position.y = 7.0

	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(19, 8, 19)
	motion.direction = RAIN_DIRECTION.normalized()
	motion.spread = 24.0 if snow else 3.0
	motion.gravity = Vector3(0.0, -0.15 if snow else -1.0, 0.0)
	motion.initial_velocity_min = 1.4 if snow else 17.0
	motion.initial_velocity_max = 3.2 if snow else 23.0
	motion.scale_min = 0.6
	motion.scale_max = 1.4
	precipitation.process_material = motion

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.13, 0.13) if snow else Vector2(0.031, 0.48)
	precipitation_material = ShaderMaterial.new()
	precipitation_material.shader = PRECIPITATION_SHADER
	precipitation_material.set_shader_parameter("snow", snow)
	precipitation_material.set_shader_parameter("tint", Color("#f2f7ff") if snow else Color("#d5e6f7"))
	mesh.material = precipitation_material
	precipitation.draw_pass_1 = mesh
	add_child(precipitation)
