extends RefCounted

const WorldWeather = preload("res://scripts/world_weather.gd")

static func install(parent: Node3D, season: int, condition: int) -> WorldWeather:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d5dfed")
	environment.ambient_light_energy = 0.34
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_density = 0.36
	environment.fog_depth_begin = 180.0
	environment.fog_depth_end = 950.0
	environment.fog_depth_curve = 1.6
	environment.ssao_enabled = true
	environment.ssao_radius = 1.1
	environment.ssao_intensity = 1.5
	world.environment = environment
	parent.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-11, 162, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 450
	parent.add_child(sun)
	var weather := WorldWeather.new()
	weather.install(parent, environment, sun, 0.78)
	weather.set_weather(condition, season)
	return weather

static func update_view(weather: WorldWeather, camera: Camera3D, distance: float) -> void:
	var close_view := 1.0 - smoothstep(28.0, 115.0, distance)
	weather.update_view(camera, close_view, 180.0, 950.0)
