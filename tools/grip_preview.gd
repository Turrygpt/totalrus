extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world = current_scene
	world.camera_locked = true
	world.squad.ai_enabled = false
	world.enemy.ai_enabled = false
	for b in world.banners:
		b.queue_free()
	world.banners.clear()
	for unit in world.squad.soldiers + world.enemy.soldiers:
		unit.hide()
		unit.set_physics_process(false)
	var actor = world.squad.soldiers[0]
	actor.show()
	actor.position = Vector3.ZERO
	actor.rotation.y = 0
	actor.has_spear = false
	actor.spear.hide()
	actor.take_sword()
	DirAccess.make_dir_recursive_absolute("res://build/grip_preview")
	for clip in ["pack_idle_sword","pack_guard_sword","pack_attack_4","idle_spear","guard_front"]:
		var full = actor.animation_map[clip]
		actor.player.play(full,0)
		actor.player.advance(0)
		actor.player.seek(actor.player.get_animation(full).length*.55,true)
		actor.player.pause()
		for view in ["front","back"]:
			world.camera.position = Vector3(1.6,1.55,-2.5 if view == "front" else 2.5)
			world.camera.look_at(Vector3(0,1.15,0))
			await create_timer(.15).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/grip_preview/%s_%s.png" % [clip,view])
	quit()
