extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	set_meta(&"battle_size", 5)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world = current_scene
	world.camera_locked = true
	for group in world.squads:
		group.ai_enabled = false
		group.stop()
		for s in group.soldiers: s.hide(); s.set_physics_process(false)
	for b in world.banners: b.queue_free()
	world.banners.clear()
	var actor = world.squads.filter(func(g): return g.unit_kind == "princely")[0].soldiers[0]
	actor.show()
	actor.position = Vector3.ZERO
	actor.rotation.y = 0
	world.camera.position = Vector3(2,1.8,3.6)
	world.camera.look_at(Vector3(0,1,0))
	DirAccess.make_dir_recursive_absolute("res://build/princely_preview")
	for clip in ["idle_spear","run_spear","charge_spear","death_back"]:
		actor.play_clip(clip,0)
		await create_timer(.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/princely_preview/"+clip+".png")
	quit()
