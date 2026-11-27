extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/" + name + ".png")

func run() -> void:
	change_scene_to_file("res://scenes/battlefield.tscn")
	await create_timer(2).timeout
	var world = current_scene
	await capture("terrain_baseline")
	var grass: Array = []
	for mesh in world.get_node("Terrain").get_children():
		if mesh is MultiMeshInstance3D and mesh.multimesh.instance_count == 2400:
			grass.append(mesh)
			mesh.visible = false
	await capture("terrain_no_grass")
	for mesh in grass:
		mesh.visible = true
	var env = world.find_children("*","WorldEnvironment",true,false)[0].environment
	env.ssao_enabled = false
	for light in world.find_children("*","DirectionalLight3D",true,false):
		light.shadow_enabled = false
	await capture("terrain_no_shadows")
	var mat = grass[0].multimesh.mesh.surface_get_material(0)
	mat.shader.code = mat.shader.code.replace("fade*=edge_x*edge_z;", "fade=1.0;")
	await capture("terrain_no_fade")
	for mesh in grass:
		mesh.visible = false
	var ground = world.get_node("Terrain").get_children()[0]
	var terrain_shader = ground.material_override.shader
	terrain_shader.code = terrain_shader.code.replace("float macro=noise(world.xz*.11);", "float macro=.5;")
	await capture("terrain_no_macro")
	terrain_shader.code = terrain_shader.code.replace("NORMAL_MAP=texture(grass_normal,uv).rgb;", "NORMAL_MAP=vec3(.5,.5,1.0);")
	await capture("terrain_no_normal")
	quit()
