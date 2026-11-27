extends Node

var failures: Array[String] = []
var world: Node3D
var output := "res://build/qa"

func check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func settled() -> bool:
	return world.squad.soldiers.all(func(s): return s.global_position.distance_to(s.target) < 0.25)

func wait_for_formation(timeout: float) -> void:
	var elapsed := 0.0
	while elapsed < timeout and not settled():
		await wait(.5)
		elapsed += .5

func run(battlefield: Node3D) -> void:
	world = battlefield
	world.set_battle_paused(false)
	if not OS.has_feature("editor"):
		output = OS.get_executable_path().get_base_dir().path_join("qa")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await wait(2)
	check(world.squad.soldiers.size() == 60, "60 soldiers")
	check(world.squad.spear_count() == 60, "60 spears")
	var first = world.squad.soldiers[0]
	print("ANIMATIONS ", first.player.get_animation_list())
	print("SOCKETS ", first.right_socket.bone_idx, " ", first.belt_socket.bone_idx)
	check(first.right_socket.bone_idx >= 0 and first.belt_socket.bone_idx >= 0, "equipment attachment bones")
	if "--profile" in OS.get_cmdline_user_args():
		for stage in 5:
			if stage == 1:
				for s in world.squad.soldiers: s.player.pause()
			if stage == 2:
				for s in world.squad.soldiers: s.set_physics_process(false); s.agent.avoidance_enabled = false
			if stage == 3:
				for light in world.find_children("*", "DirectionalLight3D", true, false): light.shadow_enabled = false
			if stage == 4:
				for s in world.squad.soldiers: s.model.visible = false
			await wait(5)
			print("PROFILE ", stage, " fps=", Engine.get_frames_per_second(), " process=", Performance.get_monitor(Performance.TIME_PROCESS), " physics=", Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS), " navigation=", Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS), " draws=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		get_tree().quit()
		return
	await screenshot("01_overview")
	world.camera_locked = true
	world.focus = first.global_position + Vector3(0,.85,0)
	world.camera_distance = 4.0
	world.update_camera()
	await wait(.4)
	await screenshot("02_close_idle")
	if "--animation-preview" in OS.get_cmdline_user_args():
		for s in world.squad.soldiers:
			if s != first: s.visible = false
		world.camera.position = first.position + Vector3(0,1.8,-3.8)
		world.camera.look_at(first.position + Vector3(0,1,0))
		await wait(.3)
		await screenshot("detail_idle")
		first.order_throw(first.position + Vector3(0,0,-15),0)
		await wait(.45)
		await screenshot("detail_windup")
		await wait(.45)
		await screenshot("detail_release")
		await wait(.95)
		await screenshot("detail_draw")
		await wait(1.3)
		await screenshot("detail_sword")
		get_tree().quit()
		return
	if "--preview-only" in OS.get_cmdline_user_args():
		get_tree().quit(0)
		return
	world.camera_locked = false
	world.camera_distance = 30
	world.focus = Vector3(0,0,0)
	world.update_camera()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.position = world.camera.unproject_position(Vector3(9,0,-7))
	click.pressed = true
	get_viewport().push_input(click, true)
	await wait(.1)
	check(world.squad.state_text == "Шаг", "right click starts walking")
	click.pressed = false
	get_viewport().push_input(click, true)
	var double_click := click.duplicate() as InputEventMouseButton
	double_click.pressed = true
	double_click.double_click = true
	get_viewport().push_input(double_click, true)
	await wait(.1)
	check(world.squad.state_text == "Бег", "double right click switches to running")
	get_viewport().push_input(click, true)
	# Physical keys keep the command usable with a Cyrillic keyboard layout.
	var before_camera: Vector3 = world.focus
	var russian_key := InputEventKey.new()
	russian_key.physical_keycode = KEY_W
	russian_key.keycode = 0x446
	russian_key.unicode = 0x446
	russian_key.pressed = true
	Input.parse_input_event(russian_key)
	await wait(.15)
	russian_key.pressed = false
	Input.parse_input_event(russian_key)
	check(world.focus.distance_to(before_camera) > .1, "physical camera key with Cyrillic character")
	await wait(2)
	await screenshot("03_running")
	world.squad.command(1, Vector3(-5,0,6))
	await wait_for_formation(22)
	check(settled(), "diagonal move, reverse and walking arrival")
	world.squad.command(3, world.squad.center() + Vector3(0,0,-10))
	await wait_for_formation(14)
	await wait(1)
	check(settled(), "shield wall assembled")
	world.focus = world.squad.center() + Vector3(0,.5,0)
	world.camera_distance = 17
	world.update_camera()
	await screenshot("04_guard")
	var minimum_distance := INF
	for i in 60:
		for j in range(i+1,60):
			minimum_distance = minf(minimum_distance, world.squad.soldiers[i].position.distance_to(world.squad.soldiers[j].position))
	check(minimum_distance > .48, "body separation in defense")
	world.squad.command(4, world.squad.center() + Vector3(0,0,-17))
	await wait(.9)
	await screenshot("05_throw")
	world.squad.command(2, world.squad.center() + Vector3(5,0,2))
	check(not world.squad.pending_order.is_empty(), "movement queued during weapon transition")
	await wait(5)
	check(world.squad.spear_count() == 0, "all 60 spears released")
	check(world.squad.soldiers.all(func(s): return s.sword_drawn), "all 60 swords drawn")
	world.squad.command(4, Vector3.ZERO)
	await wait_for_formation(12)
	check(not world.squad.is_busy(), "repeat throw cannot consume another spear")
	check(settled(), "queued movement completed")
	world.squad.command(3, world.squad.center() + Vector3(0,0,-8))
	await wait_for_formation(12)
	await wait(1)
	world.focus = world.squad.center()
	world.update_camera()
	await screenshot("06_sword_guard")
	world.squad.command(2, Vector3(100,0,100))
	check(world.squad.soldiers.all(func(s): return absf(s.target.x) < 59.5 and absf(s.target.z) < 44.5), "formation targets clamped at boundary")
	await wait_for_formation(30)
	check(world.squad.soldiers.all(func(s): return absf(s.position.x) < 60 and absf(s.position.z) < 45), "60 soldiers remain inside field")
	world.squad.stop()
	await wait(1)
	check(world.squad.soldiers.all(func(s): return s.motion_speed < .15), "stop command")
	var report := {"failures":failures, "fps":Engine.get_frames_per_second(), "minimum_guard_spacing":minimum_distance}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("QA_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
