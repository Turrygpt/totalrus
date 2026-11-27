extends SceneTree
func _initialize() -> void:
	for path in ["res://assets/warrior.glb","res://assets/archer.glb"]:
		var model = load(path).instantiate()
		root.add_child(model)
		var player: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
		var skeleton: Skeleton3D = model.find_children("*","Skeleton3D",true,false)[0]
		var counts := {"total":0,"rest_position":0,"unit_scale":0,"rest_rotation":0}
		for name in player.get_animation_list():
			var anim := player.get_animation(name)
			for t in anim.get_track_count():
				counts.total += 1
				var type := anim.track_get_type(t)
				var bone := skeleton.find_bone(anim.track_get_path(t).get_subname(0))
				if bone < 0: continue
				var rest := skeleton.get_bone_rest(bone)
				var equal := true
				for k in anim.track_get_key_count(t):
					var value = anim.track_get_key_value(t,k)
					if type == Animation.TYPE_POSITION_3D: equal = equal and value.distance_to(rest.origin) < .0001
					elif type == Animation.TYPE_SCALE_3D: equal = equal and value.distance_to(rest.basis.get_scale()) < .0001
					elif type == Animation.TYPE_ROTATION_3D: equal = equal and value.angle_to(rest.basis.get_rotation_quaternion()) < .0001
					else: equal = false
				if equal:
					if type == Animation.TYPE_POSITION_3D: counts.rest_position += 1
					elif type == Animation.TYPE_SCALE_3D: counts.unit_scale += 1
					elif type == Animation.TYPE_ROTATION_3D: counts.rest_rotation += 1
		print(path," ",counts)
		model.queue_free()
	quit()
