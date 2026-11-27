extends SceneTree

const SECONDS := 60.0
const VISUAL = preload("res://scripts/crowd_visual.gd")
const CAVALRY = preload("res://scripts/cavalry.gd")
const KHAZAR = preload("res://scripts/khazar.gd")
const COMMANDER_TEXTURE = preload("res://assets/sotnik.jpg")
const HILL_CENTER := Vector3(-22, 0, 61)
const HILL_RADIUS := 17.0
const HILL_HEIGHT := 6.1
const KHAZAR_SHOT_START := 46.0
const KHAZAR_SHOT_END := 50.3
const KHAZAR_RIDE_START := Vector3(-54, 0, 5)
const KHAZAR_RIDE_END := Vector3(-51, 0, -22)

class CinematicField extends "res://scripts/battlefield.gd":
	var cast: Dictionary = {}

	func _enter_tree() -> void:
		get_tree().current_scene = self

	func make_full_roster() -> void:
		for row in [
			["left", 0, Vector3(-31,0,15), "ДРУЖИНА", "infantry"],
			["archers", 0, Vector3(-16,0,28), "ЛУЧНИКИ", "archer"],
			["horse", 0, Vector3(-54,0,21), "КОННИЦА", "cavalry"],
			["center", 0, Vector3(1,0,16), "НОВГОРОДСКАЯ ДРУЖИНА", "infantry"],
			["right", 0, Vector3(24,0,17), "СОКОЛ", "infantry"],
			["reserve", 0, Vector3(45,0,20), "ДРУЖИНА", "infantry"],
			["khazar", 1, Vector3(-69,0,-21), "ХАЗАРЫ", "khazar"],
			["riders", 1, Vector3(-82,0,-41), "ХАЗАРЫ", "khazar"],
			["kyiv", 1, Vector3(1,0,-19), "ДРУЖИНА АСКОЛЬДА И ДИРА", "infantry"],
			["axes", 1, Vector3(24,0,-15), "ВАРЯГИ", "varangian"],
			["axes2", 1, Vector3(45,0,-17), "ВАРЯГИ", "varangian"],
			["axes3", 1, Vector3(67,0,-27), "ВАРЯГИ", "varangian"],
		]:
			cast[row[0]] = make_unit(row[1], row[2], row[3], row[4])
		squad = cast.left
		enemy = cast.axes
		friendly_archers = cast.archers

	func _process(delta: float) -> void:
		# Movie Maker runs a fixed timestep even when encoding takes longer than a frame.
		var previous := battle_time
		super._process(delta)
		battle_time = previous + delta

var field: CinematicField
var title: Label
var curtain: ColorRect
var bars: Array[ColorRect] = []
var commander: CharacterBody3D
var khazar_rider: CharacterBody3D
var cavalry_shot_center := Vector3.ZERO
var elapsed := 0.0
var cue := 0
var last_shot := -1
var preview := false

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	preview = "--preview" in OS.get_cmdline_user_args()
	var dimensions := Vector2i(1280,720) if preview else Vector2i(1920,1080)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(dimensions)
	root.content_scale_size = dimensions
	root.size = dimensions
	set_meta(&"battle_size", 5)
	seed(280195)
	field = CinematicField.new()
	field.name = "CinematicField"
	root.add_child(field)
	field.camera_locked = true
	field.profiling_skip_banners = true
	field.crowd_renderer.instant_lod = true
	for group in field.squads:
		group.ai_enabled = false
		group.selected = false
		if group.is_ranged(): group.stop()
	for child in field.get_children():
		if child is CanvasLayer:
			child.hide()
		elif child is DirectionalLight3D:
			child.rotation_degrees = Vector3(-24, 33, 0)
			child.light_color = Color("ffe1b1")
			child.light_energy = 1.2
		elif child is WorldEnvironment:
			var env: Environment = child.environment
			env.fog_density = .00235
			env.fog_light_color = Color("9caaa2")
			env.ambient_light_color = Color("b8c6db")
			env.ambient_light_energy = .49
			env.adjustment_enabled = true
			env.adjustment_saturation = .80
			env.adjustment_contrast = 1.10
	make_village()
	make_commander_hill()
	var ride := KHAZAR_RIDE_END - KHAZAR_RIDE_START
	khazar_rider = make_cinematic_mount(KHAZAR, 1, KHAZAR_RIDE_START, atan2(-ride.x, -ride.z), "bow_run")
	prepare_khazar_gallop()
	khazar_rider.hide()
	prepare_equipment()
	make_titles()
	compose(0)
	if preview:
		DirAccess.make_dir_absolute("res://build/cinematic_previews")
	process_frame.connect(tick)

func prepare_equipment() -> void:
	# Build the complete far meshes and their weapon surfaces before the first
	# shot. Each close-up can then switch straight to an already loaded rig.
	for group in field.squads:
		for actor in group.soldiers:
			actor.crowd_visual = VISUAL.new(actor)
			actor.crowd_visual.set_distant(true)
			actor.visual_lod_timer = 0.0
	print("CINEMATIC GEOMETRY READY ", field.crowd_renderer.combined.size(), " mesh variants")

func make_village() -> void:
	var cabin_scene: PackedScene = load("res://assets/cinematic_log_cabin.glb")
	var models := cabin_scene.instantiate()
	for placement in [
		["Cabin01", Vector3(-9,0,37), .25, 1.10], ["Cabin03", Vector3(1,0,37), -.20, 1.0],
		["Cabin02", Vector3(11,0,37), .42, .88], ["Cabin04", Vector3(-2,0,46), .70, .95],
		["Cabin01", Vector3(10,0,47), -.24, .97],
	]:
		var cabin := models.get_node(placement[0]).duplicate() as MeshInstance3D
		field.add_child(cabin)
		cabin.position = placement[1]
		cabin.rotation.y = placement[2]
		cabin.scale = Vector3(placement[3], 1.0, placement[3])
		cabin.lod_bias = 20.0
	models.free()

func hill_height(x: float, z: float) -> float:
	var slope := maxf(0.0, 1.0 - (x * x + z * z) / (HILL_RADIUS * HILL_RADIUS))
	return HILL_HEIGHT * slope * slope

func make_commander_hill() -> void:
	var terrain := field.get_node("Terrain")
	var ground := terrain.get_child(0) as MeshInstance3D
	var geometry := SurfaceTool.new()
	geometry.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SLICES := 44
	const RINGS := 15
	for ring in range(RINGS + 1):
		var radius := HILL_RADIUS * ring / float(RINGS)
		for i in SLICES:
			var angle := TAU * i / SLICES
			var x := cos(angle) * radius
			var z := sin(angle) * radius
			var lift := hill_height(x, z)
			var dx := hill_height(x + .04, z) - hill_height(x - .04, z)
			var dz := hill_height(x, z + .04) - hill_height(x, z - .04)
			geometry.set_normal(Vector3(-dx, .08, -dz).normalized())
			geometry.add_vertex(Vector3(x, lift - .018, z))
	for ring in RINGS:
		for i in SLICES:
			var a := ring * SLICES + i
			var b := ring * SLICES + (i + 1) % SLICES
			for index in [a, a + SLICES, b + SLICES, a, b + SLICES, b]:
				geometry.add_index(index)
	var hill := MeshInstance3D.new()
	hill.mesh = geometry.commit()
	hill.material_override = ground.material_override
	hill.position = HILL_CENTER
	field.add_child(hill)
	for child in terrain.get_children():
		if not child is MultiMeshInstance3D: continue
		var cover := MultiMeshInstance3D.new()
		var patches := MultiMesh.new()
		patches.transform_format = MultiMesh.TRANSFORM_3D
		patches.mesh = child.multimesh.mesh
		patches.instance_count = 4800
		var rng := RandomNumberGenerator.new()
		rng.seed = 6207
		for i in patches.instance_count:
			var angle := rng.randf_range(0, TAU)
			var radius := sqrt(rng.randf()) * HILL_RADIUS
			var x := cos(angle) * radius
			var z := sin(angle) * radius
			var scale := rng.randf_range(.68, 1.15)
			patches.set_instance_transform(i, Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale),
				Vector3(x, hill_height(x, z) - .024, z)))
		cover.multimesh = patches
		cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hill.add_child(cover)
		break
	commander = make_cinematic_mount(CAVALRY, 0, HILL_CENTER + Vector3(0, HILL_HEIGHT - .028, 0), -.29, "idle_spear")
	var rider_body := commander.model.find_child("Mounted warrior", true, false) as MeshInstance3D
	var rider_material := rider_body.get_active_material(0).duplicate() as StandardMaterial3D
	rider_material.albedo_texture = COMMANDER_TEXTURE
	rider_body.set_surface_override_material(0, rider_material)

func make_cinematic_mount(script: Script, team: int, point: Vector3, heading: float, clip: String) -> CharacterBody3D:
	var actor := CharacterBody3D.new()
	actor.set_script(script)
	actor.team = team
	actor.position = point
	actor.rotation.y = heading
	field.add_child(actor)
	actor.remove_from_group("combatants")
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.play_clip(clip, 0.0)
	actor.player.advance(0.0)
	return actor

func prepare_khazar_gallop() -> void:
	# Hold the bow forward with the left arm while keeping the horse and rider's seat in gallop.
	var player: AnimationPlayer = khazar_rider.player
	var gallop := player.get_animation("Gallop").duplicate() as Animation
	var aim := player.get_animation("RiderAim")
	var bow_arm := [&"RiderUpperArm.L", &"RiderForearm.L", &"RiderHand.L", &"GripLeft"]
	for track in gallop.get_track_count():
		var path := gallop.track_get_path(track)
		if path.get_subname_count() == 0 or path.get_subname(0) not in bow_arm:
			continue
		var source := aim.find_track(path, gallop.track_get_type(track))
		if source == -1:
			continue
		var pose: Variant = aim.track_get_key_value(source, 0)
		for key in gallop.track_get_key_count(track):
			gallop.track_set_key_value(track, key, pose)
	var library := AnimationLibrary.new()
	library.add_animation(&"GallopWithBow", gallop)
	player.add_animation_library(&"cinematic", library)
	player.play(&"cinematic/GallopWithBow", 0.0)
	player.advance(0.0)

func make_titles() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	root.add_child(layer)
	for i in 2:
		var bar := ColorRect.new()
		bar.color = Color("06090b")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(bar)
		bars.append(bar)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Times New Roman"])
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", serif)
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_color_override("font_shadow_color", Color("101518"))
	title.add_theme_color_override("font_color", Color("fff0d4"))
	layer.add_child(title)
	curtain = ColorRect.new()
	curtain.color = Color.BLACK
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(curtain)

func tick() -> void:
	var fps := Engine.max_fps
	# The entry point expects --fixed-fps, so use the engine's frame delta.
	var delta := field.get_process_delta_time()
	if delta <= 0: delta = 1.0 / maxi(fps,30)
	elapsed += delta
	stage_orders()
	compose(elapsed)
	if elapsed < 3.7:
		commander.player.advance(delta)
	if khazar_rider.visible:
		khazar_rider.player.advance(delta)
	for banner in field.banners: banner.world_standard.follow(banner.squad)
	if elapsed >= SECONDS + .05:
		var shots := 0
		for gunner in field.cast.khazar.soldiers + field.cast.riders.soldiers:
			shots += gunner.shots_fired
		print("CINEMATIC ", elapsed, " seconds; hits ", field.effects.hits,
			" blocks ", field.effects.blocks, " Khazar arrows ", shots,
			" fighters left ", field.team_alive(0), "/", field.team_alive(1))
		quit()
	if "--opening-check" in OS.get_cmdline_user_args() and elapsed > 2.5:
		quit()
	if "--riders-check" in OS.get_cmdline_user_args() and elapsed > 17.0:
		quit()

func stage_orders() -> void:
	var groups := field.cast
	if cue == 0 and elapsed >= 6.9:
		groups.khazar.command(2, Vector3(-13,0,-21))
		groups.riders.command(2, Vector3(-26,0,-41))
		cue += 1
	if cue == 1 and elapsed >= 14.8:
		groups.khazar.command_attack(groups.left, false)
		cue += 1
	if cue == 2 and elapsed >= 16.7:
		groups.archers.command_attack(groups.khazar,false)
		groups.horse.command_attack(groups.riders,true)
		groups.riders.command_attack(groups.horse,true)
		groups.left.command_attack(groups.khazar,true)
		cue += 1
	if cue == 3 and elapsed >= 23.1:
		groups.center.command_attack(groups.kyiv,true)
		groups.kyiv.command_attack(groups.center,true)
		groups.axes.command_attack(groups.right,true)
		groups.right.command_attack(groups.axes,true)
		groups.axes2.command_attack(groups.reserve,true)
		groups.reserve.command_attack(groups.axes2,true)
		groups.axes3.command_attack(groups.reserve,true)
		cue += 1
	if cue == 4 and elapsed >= 38.0:
		groups.archers.command_attack(groups.axes,false)
		cue += 1

func anchor(group: String, index: int) -> Transform3D:
	return field.cast[group].soldiers[index].render_transform()

func place(a: Vector3, b: Vector3, a_target: Vector3, b_target: Vector3, u: float, lens: float) -> void:
	field.camera.fov = lens
	field.camera.position = a.lerp(b,u)
	field.camera.look_at(a_target.lerp(b_target,u))

func track(group: String, index: int, a: Vector3, b: Vector3, target: Vector3, u: float, lens: float) -> void:
	var subject := anchor(group,index)
	var focal := subject * target
	place(subject*a,subject*b,focal,focal,u,lens)

func rendered_center(group: Node3D) -> Vector3:
	var center := Vector3.ZERO
	for rider in group.members:
		center += rider.render_transform().origin
	return center / group.members.size()

func track_khazar_column(u: float) -> void:
	var lead := rendered_center(field.cast.khazar)
	var rear := rendered_center(field.cast.riders)
	var camera_anchor := lead.lerp(rear, .23)
	var foreground := lead + Vector3(3.0, 1.5, -1.5)
	var background := lead.lerp(rear, .36) + Vector3(5.2, 1.6, 0.0)
	place(camera_anchor + Vector3(13.0, 4.15, 11.8), camera_anchor + Vector3(9.5, 4.65, 14.3),
		foreground, background, u, 47)

func film_cavalry_formation(u: float) -> void:
	# Pick the point of interest once at the cut. The dolly runs in world space.
	if last_shot != 5:
		cavalry_shot_center = rendered_center(field.cast.horse)
	var center := cavalry_shot_center
	place(center + Vector3(9.0, 2.15, -9.5), center + Vector3(10.0, 2.7, -4.2),
		center + Vector3(-1.5, 1.4, -1.5), center + Vector3(-1.5, 1.4, -3.5), u, 46)

func film_khazar_ride(u: float) -> void:
	# The rider and camera move on separate paths, so even the gallop cannot shake the frame.
	khazar_rider.position = KHAZAR_RIDE_START.lerp(KHAZAR_RIDE_END, u)
	place(KHAZAR_RIDE_START + Vector3(-5.5, 2.05, -1.65), KHAZAR_RIDE_END + Vector3(-4.9, 1.95, -1.25),
		KHAZAR_RIDE_START + Vector3(0, 1.4, -.55), KHAZAR_RIDE_END + Vector3(0, 1.46, -.75), u, 43)

func compose(t: float) -> void:
	var shot := 0
	var caption := ""
	var opacity := 0.0
	var title_height := .69
	khazar_rider.visible = t >= KHAZAR_SHOT_START and t < KHAZAR_SHOT_END
	if t < 3.7:
		shot = 14
		var summit := commander.position
		place(summit + Vector3(-6.9,3.05,4.5), summit + Vector3(-4.4,3.25,7.1),
			summit + Vector3(2.1,-.65,-12.0), summit + Vector3(3.1,-2.2,-16.0), t/3.7, 51)
		caption = "РУСЬ: ЭПОХА ВОЙН"
		opacity = smoothstep(.55,1.35,t)*(1-smoothstep(3.16,3.6,t))
	elif t < 6.4:
		place(Vector3(-61,55,91),Vector3(-46,36,63),Vector3(-3,0,-4),Vector3(-5,0,-6),(t-3.7)/2.7,43)
	elif t < 9.5:
		shot = 1
		track("left",35,Vector3(-3.9,1.70,-5.8),Vector3(1.0,1.48,-3.05),Vector3(0,1.36,.25),(t-6.4)/3.1,37)
	elif t < 14.8:
		shot = 2
		track_khazar_column((t-9.5)/5.3)
		caption = "Хазары на Юге"
		opacity = smoothstep(9.63,10.15,t)*(1-smoothstep(13.9,14.7,t))
	elif t < 17.1:
		shot = 3
		place(Vector3(-15,3.1,15),Vector3(-17,2.85,13),Vector3(-38,1.85,-18),
			Vector3(-38,1.85,-18),(t-14.8)/2.3,44)
	elif t < 20.6:
		shot = 4
		place(Vector3(-15,2.05,6),Vector3(-23,1.76,2),Vector3(-38,1.45,-7),Vector3(-37,1.45,-4),(t-17.1)/3.5,47)
	elif t < 24.3:
		shot = 5
		film_cavalry_formation((t-20.6)/3.7)
	elif t < 28.3:
		shot = 6
		track("axes",4,Vector3(3.35,1.55,-5.5),Vector3(1.73,1.47,-3.1),Vector3(.05,1.23,-.10),(t-24.3)/4,39)
		caption = "Варяги на севере"
		opacity = smoothstep(24.55,25.12,t)*(1-smoothstep(26.8,27.9,t))
	elif t < 32.0:
		shot = 7
		place(Vector3(8,4.20,4),Vector3(15,2.7,2),Vector3(25,1.3,0),Vector3(25,1.20,0),(t-28.3)/3.7,40)
	elif t < 36.0:
		shot = 8
		track("right",5,Vector3(-3.2,1.8,-3.6),Vector3(-2.7,2.0,-3.7),Vector3(.3,1.2,-.9),(t-32.0)/4,43)
	elif t < 40.3:
		shot = 9
		place(Vector3(9,3.15,6),Vector3(7,2.85,5),Vector3(.4,1.55,-2),
			Vector3(.4,1.60,-2),(t-36)/4.3,40)
		caption = "Аскольд и Дир • Измена в Киеве"
		opacity = smoothstep(36.3,37,t)*(1-smoothstep(38.7,40.1,t))
	elif t < KHAZAR_SHOT_START:
		shot = 10
		place(Vector3(63,18,25),Vector3(34,30,40),Vector3(32,0,0),Vector3(5,0,0),(t-40.3)/5.7,45)
	elif t < KHAZAR_SHOT_END:
		shot = 11
		film_khazar_ride((t-KHAZAR_SHOT_START)/(KHAZAR_SHOT_END-KHAZAR_SHOT_START))
	elif t < 55.4:
		shot = 12
		track("right",35,Vector3(2.8,1.72,-4.4),Vector3(1.45,1.50,-3.1),Vector3(0,1.32,-1),(t-KHAZAR_SHOT_END)/5.1,38)
	else:
		shot = 13
		place(Vector3(24,11,31),Vector3(18,48,75),Vector3(20,0,0),Vector3(1,0,-5),clampf((t-55.4)/4.6,0,1),43)
		caption = "РУСЬ: ЭПОХА ВОЙН"
		opacity = smoothstep(56.4,57.3,t)*(1-smoothstep(59.25,60,t))
		title_height = .39
	var size := root.get_visible_rect().size
	for i in 2:
		bars[i].position = Vector2(0, 0 if i == 0 else size.y*.935)
		bars[i].size = Vector2(size.x, size.y*.065)
	curtain.size = size
	title.text = caption
	title.modulate.a = opacity
	title.position = Vector2(0,size.y * title_height)
	title.size.x = size.x
	title.add_theme_font_size_override("font_size", roundi(size.y*.070))
	curtain.color.a = maxf(1-smoothstep(0,.8,t),smoothstep(58.9,60,t))
	if shot != last_shot:
		last_shot = shot
		print("SHOT ", shot, " @ ", snappedf(t,.01))
		if preview: capture_preview(shot)

func capture_preview(shot: int) -> void:
	await create_timer(1.65).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg("res://build/cinematic_previews/%02d.jpg" % shot,.91)
