extends SceneTree
var failures:=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,message:String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func key(code:int,unicode_value:=0) -> void:
	var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=code;event.unicode=unicode_value
	Input.parse_input_event(event);event=event.duplicate();event.pressed=false;Input.parse_input_event(event)
func mouse(point:Vector2,pressed:bool,double_click:=false) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=pressed;event.double_click=double_click;event.position=point;event.global_position=point
	root.push_input(event,true)
func run() -> void:
	set_meta(&"battle_size", 15)
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(1).timeout
	var world=current_scene;world.camera_locked=true
	for g in world.squads:g.ai_enabled=false;g.stop()
	check(paused,"large battle starts paused")
	key(KEY_P,0x0437);await process_frame
	check(not paused,"physical P resumes with Cyrillic character")
	key(KEY_P,0x0437);await process_frame
	check(paused,"physical P pauses with Cyrillic character")
	key(KEY_2);await process_frame
	check(paused and world.speed==2 and world.command_mode==0,"2 changes time speed without entering move targeting")
	key(KEY_P,0x0437);key(KEY_1);await process_frame
	var point:Vector2=world.camera.unproject_position(Vector3(35,0,20))
	mouse(point,true);mouse(point,false);await process_frame
	check(world.squad.state_text=="Шаг" and world.squad.soldiers[0].speed_limit==1.8,"single RMB sends walking order")
	mouse(point,true,true);mouse(point,false,true);await process_frame
	check(world.squad.state_text=="Бег" and world.squad.soldiers[0].speed_limit==4.2,"double RMB sends running order")
	key(KEY_X);await process_frame
	point=world.camera.unproject_position(Vector3(30,0,15))
	mouse(point,true)
	var preview_deadline := Time.get_ticks_msec()+1000
	while world.right_held and not world.formation_preview.visible and Time.get_ticks_msec() < preview_deadline:
		await process_frame
	check(world.right_held and world.formation_preview.visible,"holding RMB opens formation preview")
	mouse(point,false);await process_frame
	check(world.squad.reforming and not world.formation_preview.visible,"RMB release confirms formation")
	key(KEY_G,0x043f);await process_frame
	check(world.command_mode==3,"physical G selects defence with Cyrillic character")
	key(KEY_ESCAPE);await process_frame
	check(world.command_mode==0,"Escape cancels targeting")
	for distance in [85.0,28.0,8.0]:
		world.camera_distance=distance;world.focus=Vector3.ZERO;world.update_camera()
		for angle in [0.0,1.4,3.1]:
			world.camera_yaw=angle;world.update_camera()
			await process_frame
			check(world.banners.all(func(banner): return not banner.is_visible_in_tree()),
				"no floating squad labels during camera rotation or zoom")
	var faction_banner = preload("res://scripts/squad_banner.gd")
	check(world.banners.all(func(banner):
		var fabric: ShaderMaterial = banner.world_standard.fabric_material
		return fabric.get_shader_parameter("cloth_tint") == banner.squad.uniform_color and (
			fabric.get_shader_parameter("heraldry") == faction_banner.HERALDRY[banner.squad.unit_kind]
		)
	), "standards use their leader's colors and unit emblems")
	var veteran = world.banners[0]
	var fighter = veteran.squad.soldiers[0]
	for sample in [[0,0],[9,0],[10,1],[19,1],[20,2],[29,2],[30,3],[40,4],[60,6],[70,7],[90,9]]:
		fighter.kills = sample[0]
		veteran.squad.set_experience(sample[0])
		veteran.refresh_stats()
		check(veteran.experience_rank == sample[1] and veteran.world_standard.fabric_material.get_shader_parameter("experience_rank") == sample[1],
			"banner displays rank %d at %d kills" % [sample[1], sample[0]])
	fighter.die()
	veteran.refresh_stats()
	check(veteran.experience_rank == 9, "banner keeps honours after the fighter who earned them falls")
	var victim=world.squads[2]
	for s in victim.soldiers:s.die()
	await process_frame;await process_frame
	check(not world.banners[2].world_standard.visible,"destroyed squad standard disappears")
	print("INPUT_BANNER_QA ",failures)
	world.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
