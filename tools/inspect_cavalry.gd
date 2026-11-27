extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var model=load("res://assets/horseman_quaternius.glb").instantiate()
	root.add_child(model)
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		print("MESH ",mesh.get_path()," surfaces ",mesh.mesh.get_surface_count()," bones ",mesh.skin.get_bind_count() if mesh.skin else 0," skeleton ",mesh.skeleton)
		for i in mesh.mesh.get_surface_count():print("SURFACE ",mesh.mesh.surface_get_array_len(i)," tri ",mesh.mesh.surface_get_array_index_len(i)/3," mat ",mesh.get_active_material(i).resource_name)
	for sk:Skeleton3D in model.find_children("*","Skeleton3D",true,false):
		var names:=[]
		for i in sk.get_bone_count():names.append(sk.get_bone_name(i))
		print("BONES ",sk.get_path()," ",names)
	var player:AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	for name in player.get_animation_list():print("CLIP ",name," ",player.get_animation(name).length)
	model.queue_free();await process_frame;quit()
