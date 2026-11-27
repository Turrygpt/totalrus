extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var kinds:Array=["soldier"] if "--soldier-only" in OS.get_cmdline_user_args() else ["soldier","archer"]
	if "--archer-only" in OS.get_cmdline_user_args(): kinds = ["archer"]
	if "--militia-only" in OS.get_cmdline_user_args(): kinds = ["militia"]
	for option in ["archer_mid", "archer_far", "archer_overview"]:
		if "--" + option.replace("_", "-") in OS.get_cmdline_user_args(): kinds = [option]
	if "--varangian-only" in OS.get_cmdline_user_args(): kinds = ["varangian"]
	for kind in kinds:
		var bank := load("res://assets/lod/"+kind+"_poses.res")
		var clips: Dictionary = bank.get_meta("clips")
		if not clips.values()[0].has("meshes"):
			continue
		var mesh: ArrayMesh = clips.values()[0].meshes[0]
		var count := mesh.surface_get_array_len(0)
		var pose_format := Image.FORMAT_RGBAH if kind in ["varangian", "militia"] else Image.FORMAT_RGBAF
		var positions := Image.create(count,clips.size()*8,false,pose_format)
		var normals := Image.create(count,clips.size()*8,false,pose_format)
		var bone_names: Array = clips.values()[0].bones[0].keys()
		var bone_texture := Image.create(bone_names.size()*4,clips.size()*8,false,Image.FORMAT_RGBAF)
		var row := 0
		for name in clips:
			clips[name]["frame_start"] = row
			for frame in 8:
				var pose: ArrayMesh = clips[name].meshes[frame]
				for bone in bone_names.size():
					var t: Transform3D = clips[name].bones[frame][bone_names[bone]]
					for column in 4:
						var v: Vector3 = t.basis[column] if column < 3 else t.origin
						bone_texture.set_pixel(bone*4+column,row,Color(v.x,v.y,v.z,1.0 if column==3 else 0.0))
				var arrays: Array = pose.surface_get_arrays(0)
				for vertex in count:
					var v: Vector3 = arrays[Mesh.ARRAY_VERTEX][vertex]
					var n: Vector3 = arrays[Mesh.ARRAY_NORMAL][vertex]
					positions.set_pixel(vertex,row,Color(v.x,v.y,v.z,1))
					normals.set_pixel(vertex,row,Color(n.x,n.y,n.z,1))
				row += 1
			if kind in ["varangian", "militia"] or kind.begins_with("archer_"): clips[name].erase("meshes")
		bank.set_meta("bone_names",bone_names)
		bank.set_meta("pose_bones",ImageTexture.create_from_image(bone_texture))
		bank.set_meta("clips",clips)
		bank.set_meta("pose_mesh",mesh)
		bank.set_meta("pose_positions",ImageTexture.create_from_image(positions))
		bank.set_meta("pose_normals",ImageTexture.create_from_image(normals))
		ResourceSaver.save(bank,"res://assets/lod/"+kind+"_poses.res",ResourceSaver.FLAG_COMPRESS)
		print("VAT ",kind," ",count," x ",row)
	quit()
