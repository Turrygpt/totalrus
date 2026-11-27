extends SceneTree

class PreviewWorld extends Node3D:
	var squads := []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := PreviewWorld.new()
	root.add_child(world)
	current_scene = world
	root.size = Vector2i(1200, 900)
	var camera := Camera3D.new()
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-40, -30, 0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.16, .19, .23)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .7
	world.add_child(env)
	var actor := CharacterBody3D.new()
	actor.set_script(load("res://scripts/varangian.gd"))
	actor.shield_variant = 0
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.agent.avoidance_enabled = false
	actor.shield.hide()
	# The cached calibration must produce the same grip on subsequent actors.
	var other := CharacterBody3D.new()
	other.set_script(load("res://scripts/varangian.gd"))
	other.shield_variant = 0
	world.add_child(other)
	assert(actor.sword.transform.is_equal_approx(other.sword.transform))
	other.free()
	DirAccess.make_dir_recursive_absolute("res://build/axe_grip")
	for clip in ["idle_sword", "walk_sword", "run_sword", "charge_sword", "guard_sword", "attack_sword", "attack_sword_alt"]:
		for phase in [.0, .25, .5, .75]:
			actor.player.play(actor.animation_map[clip], 0)
			actor.player.seek(actor.player.get_animation(actor.animation_map[clip]).length * phase, true)
			actor.player.advance(0)
			actor.skeleton.force_update_all_bone_transforms()
			await process_frame
			var hand: Vector3 = actor.right_socket.global_position
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = .85
			camera.position = hand + Vector3(1.5, .7, -2)
			camera.look_at(hand + Vector3(0, .1, 0))
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/axe_grip/%s_%d.png" % [clip, int(phase * 100)])
	print("AXE GRIP: 28 pose samples rendered; repeated-instance calibration passed")
	quit()
