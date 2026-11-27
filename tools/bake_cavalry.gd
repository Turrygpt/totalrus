extends SceneTree
func _initialize() -> void:call_deferred("run")

func choose_indices(node:MeshInstance3D,surface:int) -> PackedInt32Array:
	var source:=RenderingServer.mesh_get_surface(node.mesh.get_rid(),surface)
	var lods:Array=source.get("lods",[])
	var bytes:PackedByteArray=source.index_data
	if not lods.is_empty():
		if node.name=="Mounted warrior" or node.name=="Rider spear":bytes=lods[0].index_data
		elif node.name=="Rider shield":bytes=lods[maxi(0,lods.size()-2)].index_data
	var indices:=PackedInt32Array()
	var stride:=2 if int(source.vertex_count)<65536 else 4
	for i in bytes.size()/stride:indices.append(bytes.decode_u16(i*stride) if stride==2 else bytes.decode_u32(i*stride))
	return indices

func run() -> void:
	var khazar := "--khazar" in OS.get_cmdline_user_args()
	var world:=Node3D.new();root.add_child(world);current_scene=world
	var model_path := "res://assets/khazar_mounted.glb" if khazar else "res://assets/horseman_quaternius.glb"
	var model:Node3D=load(model_path).instantiate()
	model.rotation.y=PI;world.add_child(model)
	var player:AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if not khazar:
		player.add_animation_library(&"video", preload("res://assets/mounted_spearman_video_strike.tres"))
	var skeleton:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
	var groups:={};var offsets:=[];var sources:=[];var count:=0
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var key:=str(mesh.get_active_material(surface).get_instance_id())
			if mesh.name in ["Rider shield","Rider spear"]:key+=str(mesh.name)
			if not groups.has(key):groups[key]=[]
			var remap:={};var used:=PackedInt32Array();var indices:=PackedInt32Array()
			for original in choose_indices(mesh,surface):
				if not remap.has(original):remap[original]=used.size();used.append(original)
				indices.append(remap[original])
			groups[key].append({"node":mesh,"surface":surface,"used":used,"indices":indices})
	for parts in groups.values():
		offsets.append(count)
		sources.append({"mesh":String(parts[0].node.name),"surface":parts[0].surface})
		for part in parts:count+=part.used.size()
	print("CAVALRY_VERTICES ",count," surfaces ",groups.size())
	assert(count<16384)
	var clip_names:=player.get_animation_list()
	var positions:=Image.create(count,clip_names.size()*8,false,Image.FORMAT_RGBAH)
	var normals:=Image.create(count,clip_names.size()*8,false,Image.FORMAT_RGBAH)
	var bone_names:=[]
	for i in skeleton.get_bone_count():bone_names.append(skeleton.get_bone_name(i))
	var bone_texture:=Image.create(bone_names.size()*4,clip_names.size()*8,false,Image.FORMAT_RGBAF)
	var base:=ArrayMesh.new();var records:={};var row:=0;var triangles:=0
	for name in clip_names:
		var clip:=player.get_animation(name)
		var loop:bool=String(name) not in ["MeleeStrike","Rear","RiderDraw","RiderLoose","RiderSabre"] and not String(name).begins_with("Death") and not String(name).begins_with("video/")
		clip.loop_mode=Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		var bones:=[];var start:=row
		for frame in 8:
			player.play(name,0);player.seek(clip.length*frame/float(8 if loop else 7),true);player.advance(0)
			skeleton.force_update_all_bone_transforms()
			await RenderingServer.frame_post_draw
			var poses:={}
			for i in bone_names.size():
				var t:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(i)
				poses[bone_names[i]]=t
				for column in 4:
					var v:Vector3=t.basis[column] if column<3 else t.origin
					bone_texture.set_pixel(i*4+column,row,Color(v.x,v.y,v.z,1 if column==3 else 0))
			bones.append(poses)
			var vertex:=0
			for parts in groups.values():
				var vertices:=PackedVector3Array();var normal_values:=PackedVector3Array();var uvs:=PackedVector2Array();var indices:=PackedInt32Array()
				for part in parts:
					var mesh:MeshInstance3D=part.node
					var pose:ArrayMesh=mesh.bake_mesh_from_current_skeleton_pose()
					var arrays:Array=pose.surface_get_arrays(part.surface)
					var offset:=vertices.size()
					for used in part.used:
						var point:Vector3=mesh.global_transform*arrays[Mesh.ARRAY_VERTEX][used]
						var normal:Vector3=(mesh.global_basis*arrays[Mesh.ARRAY_NORMAL][used]).normalized()
						positions.set_pixel(vertex,row,Color(point.x,point.y,point.z,1))
						normals.set_pixel(vertex,row,Color(normal.x,normal.y,normal.z,1));vertex+=1
						if row==0:
							vertices.append(point);normal_values.append(normal)
							uvs.append(arrays[Mesh.ARRAY_TEX_UV][used] if arrays[Mesh.ARRAY_TEX_UV]!=null else Vector2.ZERO)
					if row==0:
						for index in part.indices:indices.append(offset+index)
				if row==0:
					var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
					arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normal_values;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
					base.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);triangles+=indices.size()/3
			row+=1
		records[name]={"frame_start":start,"duration":clip.length,"loop":loop,"bones":bones}
		print("CAVALRY_POSES ",name)
	var bank:=Resource.new()
	bank.set_meta("clips",records);bank.set_meta("pose_mesh",base)
	bank.set_meta("pose_positions",ImageTexture.create_from_image(positions));bank.set_meta("pose_normals",ImageTexture.create_from_image(normals))
	bank.set_meta("pose_bones",ImageTexture.create_from_image(bone_texture));bank.set_meta("bone_names",bone_names)
	bank.set_meta("body_transform",Transform3D.IDENTITY);bank.set_meta("full_model",true)
	bank.set_meta("surface_offsets",offsets);bank.set_meta("material_sources",sources)
	if khazar: bank.set_meta("bow_pivot", 2.04)
	var bank_path := "res://assets/lod/khazar_poses.res" if khazar else "res://assets/lod/cavalry_poses.res"
	var saved := ResourceSaver.save(bank,bank_path,ResourceSaver.FLAG_COMPRESS)
	if saved != OK:
		push_error("Cannot save cavalry pose bank: " + error_string(saved))
		quit(saved)
		return
	print("CAVALRY_BAKED ",count," vertices ",triangles," triangles ",row," frames")
	world.queue_free();await process_frame;await process_frame;quit()
