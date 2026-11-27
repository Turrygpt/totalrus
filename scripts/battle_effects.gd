extends Node3D

# One shared, bounded effects system for the entire battle.
const PROF = preload("res://scripts/profile_counters.gd")
var profiling_disabled := false
var limit_distant_detail := false
const MAX_VOICES := 32
const MAX_BURSTS := 54
const MAX_STAINS := 180
const MAX_DROPPED_WEAPONS := 96
# SpritePilot, Shield Block (CC0 1.0). https://spritepilot.com/free-game-assets/sound-effects#combat
const SHIELD_WOOD_SOUND = preload("res://assets/audio/shield_wood_00.wav")
var sounds := {}
var voices: Array[AudioStreamPlayer3D] = []
var voice_kinds: Array[String] = []
var last_movement_samples := {}
var bursts := 0
var burst_pool := {}
var idle_bursts := 0
var burst_meshes := {}
var burst_ramp: GradientTexture1D
var stains: Array[Node3D] = []
var dropped_weapons: Array[Node3D] = []
var dust_material: StandardMaterial3D
var blood_material: StandardMaterial3D
var spark_material: StandardMaterial3D
var stain_texture: ImageTexture
var rng := RandomNumberGenerator.new()
var sounds_played := 0
var hits := 0
var blocks := 0
var footsteps := 0
var battle_cries := 0
var large_bursts_prepared := false
var next_stain := 0
const LARGE_BURST_POOL := {"dust": 8, "dust_small": 6, "blood": 12, "spark": 10}
const LARGE_STAIN_POOL_SIZE := 96

func prepare_large_battle_bursts() -> void:
	if large_bursts_prepared or DisplayServer.get_name() == "headless": return
	large_bursts_prepared = true
	for kind in LARGE_BURST_POOL:
		var pool: Array = burst_pool.get_or_add(kind, [])
		for i in LARGE_BURST_POOL[kind]:
			var particles := make_burst(kind)
			particles.hide()
			pool.append(particles)
			idle_bursts += 1
	while stains.size() > LARGE_STAIN_POOL_SIZE:
		stains.pop_front().queue_free()
	for i in range(stains.size(), LARGE_STAIN_POOL_SIZE):
		var stain := make_stain()
		stain.hide()
		stains.append(stain)

func _ready() -> void:
	rng.randomize()
	var audio_files := ResourceLoader.list_directory("res://assets/audio")
	audio_files.sort()
	for kind in ["sword", "clash", "grunt", "death", "boot", "hoof", "charge", "bow", "arrow_wood", "arrow_body", "arrow_fly", "horn"]:
		var bank: Array[AudioStream] = []
		for file in audio_files:
			if file.begins_with(kind + "_") and file.get_extension() in ["ogg", "wav"]:
				bank.append(load("res://assets/audio/" + file))
		sounds["swing" if kind == "sword" else kind] = bank
	sounds["shield_wood"] = [SHIELD_WOOD_SOUND]
	for i in MAX_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.unit_size = 9.0
		voice.max_distance = 65.0
		voice.attenuation_filter_cutoff_hz = 10000.0
		voice.max_db = -2.0
		add_child(voice)
		voices.append(voice)
		voice_kinds.append("")
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(0, limiter)
	dust_material = particle_material(Color(.53, .44, .31, .22), true)
	blood_material = particle_material(Color(.34, .018, .009, .92), false)
	spark_material = particle_material(Color(1.0, .68, .21), false)
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stain_texture = make_stain_texture()

func particle_material(color: Color, soft: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.roughness = 1.0
	if soft:
		var gradient := Gradient.new()
		gradient.set_color(0, Color.WHITE)
		gradient.set_color(1, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 32
		texture.height = 32
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(.5, .5)
		texture.fill_to = Vector2(1, .5)
		mat.albedo_texture = texture
	return mat

func sound(kind: String, point: Vector3, volume := -6.0) -> bool:
	var bank: Array = sounds.get(kind, [])
	if bank.is_empty():
		return false
	var movement := kind == "boot" or kind == "hoof"
	var listener := get_viewport().get_audio_listener_3d()
	var listener_point: Vector3 = listener.global_position if listener else point
	var distance_squared := point.distance_squared_to(listener_point)
	var audible_distance := 45.0 if movement else 65.0
	if distance_squared > audible_distance * audible_distance:
		return false
	var active := 0
	var slot := -1
	var furthest := -1
	var furthest_distance := distance_squared + 4.0
	for i in voices.size():
		if not voices[i].playing:
			if slot < 0: slot = i
		elif voice_kinds[i] == kind:
			active += 1
			if movement:
				var playing_distance := voices[i].global_position.distance_squared_to(listener_point)
				if playing_distance > furthest_distance:
					furthest_distance = playing_distance
					furthest = i
	var limit: int = {"boot": 7, "hoof": 6, "swing": 5, "grunt": 4, "death": 5, "clash": 10, "charge":6}.get(kind, 6)
	if active >= limit:
		# Keep nearby footsteps audible even when distant ranks fill their voice budget.
		if not movement or furthest < 0: return false
		slot = furthest
	if slot < 0:
		return false
	var sample := rng.randi_range(0, bank.size() - 1)
	if movement:
		if bank.size() > 1 and sample == int(last_movement_samples.get(kind, -1)):
			sample = (sample + rng.randi_range(1, bank.size() - 1)) % bank.size()
		last_movement_samples[kind] = sample
	var voice := voices[slot]
	voice.stop()
	voice.global_position = point
	voice.stream = bank[sample]
	voice.volume_db = volume + (linear_to_db(.5) if movement else 0.0)
	voice.unit_size = (10.0 if kind == "hoof" else 7.0) if movement else 9.0
	voice.max_distance = 45.0 if movement else 65.0
	voice.pitch_scale = rng.randf_range(.94, 1.06) if movement else rng.randf_range(.88, 1.12)
	if kind == "horn":
		voice.unit_size = 28.0
		voice.max_distance = 190.0
		voice.pitch_scale = 1.0
	voice.stream_paused = get_tree().paused
	voice_kinds[slot] = kind
	voice.play()
	sounds_played += 1
	return true

func battle_cry(point: Vector3) -> void:
	if sound("charge",point,-3.0):
		battle_cries += 1

func footstep(point: Vector3, speed: float, index: int, mounted := false) -> void:
	var started := Time.get_ticks_usec() if PROF.enabled else 0
	footstep_effect(point,speed,index,mounted)
	if PROF.enabled: PROF.add("footstep",started)

func footstep_effect(point: Vector3, speed: float, index: int, mounted := false) -> void:
	if profiling_disabled or speed <= .18: return
	footsteps += 1
	var listener := get_viewport().get_audio_listener_3d()
	var distance_squared := point.distance_squared_to(listener.global_position) if listener else 0.0
	if distance_squared > 45.0 * 45.0: return
	# Spatial voices and particles are thinned, while all soldiers keep their own gait.
	# Native and script movement share this one filter; near individual steps stay audible.
	if distance_squared < 12.0 * 12.0 or index % (2 if mounted else 3) == 0:
		if mounted: sound("hoof", point, -10.0 if speed < 3.5 else -6.0)
		else: sound("boot", point, -9.0 if speed < 2.5 else -5.0)
	# Audio detail must not multiply GPU dust emitters across an entire army.
	if index % (4 if mounted else 8) != 0: return
	if speed > 2.5 and index % 2 == 0:
		burst(point + Vector3.UP * .06, Vector3.UP, "dust")
	elif index % 5 == 0:
		burst(point + Vector3.UP * .04, Vector3.UP, "dust_small")

func impact(point: Vector3, direction: Vector3, blocked: bool, arrow_hit := false, spear_hit := false) -> void:
	if blocked:
		blocks += 1
		if arrow_hit:
			sound("arrow_wood", point, -7.0)
		elif spear_hit:
			sound("shield_wood", point, -5.0)
			burst(point, direction, "spark")
		else:
			sound("clash", point, -5.0)
			burst(point, direction, "spark")
	else:
		hits += 1
		sound("arrow_body" if arrow_hit else "clash", point, -9.0 if arrow_hit else -12.0)
		burst(point, direction, "blood")
		if rng.randf() < .55:
			blood_stain(Vector3(point.x, 0.0, point.z), .22)

func burst(point: Vector3, direction: Vector3, kind: String) -> void:
	var started:=Time.get_ticks_usec() if PROF.enabled else 0
	spawn_burst(point,direction,kind)
	if PROF.enabled:PROF.add("burst_spawn",started)

func visible_combat_detail(point: Vector3, distance: float) -> bool:
	if limit_distant_detail: distance = minf(distance,48.0)
	var camera := get_viewport().get_camera_3d()
	return camera == null or camera.global_position.distance_squared_to(point) <= distance * distance

func spawn_burst(point: Vector3, direction: Vector3, kind: String) -> void:
	if profiling_disabled: return
	var limit := 24 if limit_distant_detail else MAX_BURSTS
	if bursts >= limit or DisplayServer.get_name() == "headless" or not visible_combat_detail(point,75.0):
		return
	var available: Array = burst_pool.get_or_add(kind, [])
	var particles: GPUParticles3D
	if available.is_empty():
		if limit_distant_detail: return
		particles = make_burst(kind)
	else:
		particles = available.pop_back()
		idle_bursts -= 1
	var process := particles.process_material as ParticleProcessMaterial
	process.direction = direction
	particles.global_position = point
	particles.show()
	particles.restart()
	bursts += 1
	get_tree().create_timer(particles.lifetime + .3, false).timeout.connect(func():
		bursts -= 1
		if not limit_distant_detail and idle_bursts >= limit:
			particles.queue_free()
			return
		particles.emitting = false
		particles.hide()
		available.append(particles)
		idle_bursts += 1
	)

func make_burst(kind: String) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 10 if kind == "blood" else (7 if kind == "spark" else 4)
	particles.lifetime = .65 if kind in ["blood", "spark"] else 1.15
	particles.visibility_aabb = AABB(Vector3(-3,-2,-3), Vector3(6,6,6))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not burst_meshes.has(kind):
		var mesh := QuadMesh.new()
		mesh.size = Vector2(.035, .06) if kind == "blood" else (Vector2(.015,.045) if kind == "spark" else Vector2(.65,.65))
		mesh.material = blood_material if kind == "blood" else (spark_material if kind == "spark" else dust_material)
		burst_meshes[kind] = mesh
	particles.draw_pass_1 = burst_meshes[kind]
	var process := ParticleProcessMaterial.new()
	process.spread = 42
	process.initial_velocity_min = .35 if kind.begins_with("dust") else 1.0
	process.initial_velocity_max = .7 if kind.begins_with("dust") else 3.0
	process.gravity = Vector3(.25, .18, .1) if kind.begins_with("dust") else Vector3(0,-5,0)
	process.scale_min = .35 if kind == "dust_small" else .6
	process.scale_max = .7 if kind == "dust_small" else 1.4
	if not burst_ramp:
		var gradient := Gradient.new()
		gradient.set_color(0, Color.WHITE)
		gradient.set_color(1, Color(1, 1, 1, 0))
		burst_ramp = GradientTexture1D.new()
		burst_ramp.gradient = gradient
	process.color_ramp = burst_ramp
	particles.process_material = process
	add_child(particles)
	return particles

func make_stain_texture() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2(x-32, y-32) / 32.0
			var a := atan2(p.y, p.x)
			var edge := .68 + sin(a*7.0)*.12 + cos(a*11.0)*.06
			var alpha := clampf((edge-p.length())*6.0,0.0,1.0)
			image.set_pixel(x,y,Color(.24,.015,.01,alpha*.78))
	return ImageTexture.create_from_image(image)

func drop_weapon(weapon_scene: PackedScene, origin: Transform3D, impulse: Vector3, weapon_scale: float, material: Material = null) -> void:
	if DisplayServer.get_name() == "headless" or not visible_combat_detail(origin.origin,100.0):
		return
	var weapon := weapon_scene.instantiate() as Node3D
	weapon.name = "DroppedWeapon"
	add_child(weapon)
	dropped_weapons.append(weapon)
	if dropped_weapons.size() > (48 if limit_distant_detail else MAX_DROPPED_WEAPONS):
		var oldest: Node3D = dropped_weapons.pop_front()
		oldest.hide()
		oldest.queue_free()
	var start := origin.origin
	var destination := start + impulse.limit_length(1.55)
	var from := origin.basis.orthonormalized().get_rotation_quaternion()
	var yaw := rng.randf_range(-PI, PI)
	var floor_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * .5)
	var floor_pose := floor_basis.get_rotation_quaternion()
	var floor_transform := Transform3D(floor_basis.scaled(Vector3.ONE * weapon_scale), Vector3.ZERO)
	var lowest := 0.0
	for mesh: MeshInstance3D in weapon.find_children("*", "MeshInstance3D", true, false):
		if material:
			mesh.material_override = material
		var mesh_local := weapon.global_transform.affine_inverse() * mesh.global_transform
		lowest = minf(lowest, ((floor_transform * mesh_local) * mesh.get_aabb()).position.y)
	destination.y = preload("res://scripts/battlefield_bounds.gd").project(Vector3(destination.x,0,destination.z)).y+.035-lowest
	weapon.global_transform = Transform3D(Basis(from).scaled(Vector3.ONE * weapon_scale), start)
	var tumble := weapon.create_tween()
	tumble.tween_method(func(t: float):
		var point := start.lerp(destination, t)
		point.y += .17 * sin(t * PI)
		var orientation := from.slerp(floor_pose, smoothstep(0.0, .94, t))
		weapon.global_transform = Transform3D(Basis(orientation).scaled(Vector3.ONE * weapon_scale), point)
	, 0.0, 1.0, rng.randf_range(.36, .58))

func blood_stain(point: Vector3, size := .65) -> void:
	if DisplayServer.get_name() == "headless" or not visible_combat_detail(point,65.0):
		return
	var stain: Decal
	if large_bursts_prepared:
		stain = stains[next_stain]
		next_stain = (next_stain + 1) % stains.size()
	else:
		stain = make_stain()
		stains.append(stain)
		if stains.size() > MAX_STAINS:
			stains.pop_front().queue_free()
	stain.size = Vector3(size * 2, .3, size * 2)
	stain.position = preload("res://scripts/battlefield_bounds.gd").project(point) + Vector3.UP * .08
	stain.rotation.y = rng.randf_range(0, TAU)
	stain.show()

func make_stain() -> Decal:
	var stain := Decal.new()
	stain.texture_albedo = stain_texture
	stain.distance_fade_enabled = true
	stain.distance_fade_begin = 45.0
	stain.distance_fade_length = 12.0
	add_child(stain)
	return stain
