extends SceneTree
## Targeted rig/cloth checks: real motion, turns, teleports, death, and separate crest materials.
var failures: Array[String] = []
var report := {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var actors: Array[Node3D] = []
	for kind in ["foot", "mounted"]:
		var actor: Node3D = load("res://scenes/prince_%s.tscn" % kind).instantiate()
		stage.add_child(actor)
		actors.append(actor)
		var player: AnimationPlayer = actor.find_children("*", "AnimationPlayer", true, false)[0]
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		actor.cloth.set_process(false)
		check(actor.cloth.render_rest.size() == 391 and actor.cloth.points.size() == 60, kind + " cloth detail and simulation topology")
		check(actor.cloth.pinned.count(1) == 5, kind + " shoulder attachments")
		var cases: Array = [["motion_walk_spear", 1.6], ["motion_run_spear", 3.8], ["death_back", 0.0]] if kind == "foot" else [["Walk", 1.8], ["Gallop", 6.7], ["Rear", 0.0], ["DeathSide", 0.0]]
		var observations := []
		for entry in cases:
			var clip := ""
			for name in player.get_animation_list():
				if String(name).get_file() == entry[0]: clip = name
			check(not clip.is_empty(), kind + " clip " + entry[0])
			if clip.is_empty(): continue
			player.get_animation(clip).loop_mode = Animation.LOOP_NONE if entry[0].to_lower().contains("death") or entry[0] == "Rear" else Animation.LOOP_LINEAR
			player.play(clip, .12)
			actor.cloth.suspended = true
			var largest := 1.0
			var anchor_error := 0.0
			var worst := {}
			var cloth_cpu_us := 0
			for frame in 150:
				var speed: float = entry[1] if frame < 105 else 0.0
				actor.rotation.y += .012 if frame > 45 and frame < 90 else 0.0
				actor.position += actor.basis.z * speed / 60.0
				player.advance(1.0 / 60.0)
				actor.cloth.skeleton.force_update_all_bone_transforms()
				var started := Time.get_ticks_usec()
				actor.cloth._process(1.0 / 60.0)
				cloth_cpu_us += Time.get_ticks_usec() - started
				var stats: Dictionary = actor.cloth.diagnostics()
				check(stats.finite, kind + " finite vertices in " + clip)
				if stats.structural_stretch > largest:
					largest = stats.structural_stretch
					for link in actor.cloth.lengths.size():
						var a: int = actor.cloth.links_a[link]
						var b: int = actor.cloth.links_b[link]
						if actor.cloth.stiffness[link] == 1.0 and actor.cloth.points[a].distance_to(actor.cloth.points[b]) / actor.cloth.lengths[link] > largest - .001:
							worst = {"frame": frame, "uv_a": str(actor.cloth.uvs[a]), "uv_b": str(actor.cloth.uvs[b]), "a": str(actor.to_local(actor.cloth.points[a])), "b": str(actor.to_local(actor.cloth.points[b]))}
				anchor_error = maxf(anchor_error, stats.anchor_error)
				if frame % 30 == 0: await process_frame
			check(anchor_error < .001, kind + " detached shoulder in " + clip)
			check(largest < 2.0, kind + " excessive cloth stretch in " + clip + ": " + str(largest))
			observations.append({"clip": clip, "max_structural_stretch": largest, "max_anchor_error_m": anchor_error, "cloth_mean_ms": cloth_cpu_us / 150000.0, "worst": worst})
		actor.position += Vector3(100, 0, 40)
		actor.cloth._process(.5)
		check(actor.cloth.diagnostics().finite, kind + " teleport reset")
		report[kind] = observations
	check(actors[0].embroidery != actors[1].embroidery, "independent heraldry materials")
	actors[0].set_faction_crest(null)
	check(not actors[0].embroidery.get_shader_parameter("has_crest"), "blank embroidery panel")
	check(actors[1].embroidery.get_shader_parameter("has_crest"), "other actor crest preserved")
	var crest := load("res://assets/banners/factions/kyiv.svg")
	actors[0].set_faction_crest(crest)
	check(actors[0].embroidery.get_shader_parameter("crest_texture") == crest, "faction texture replacement")
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.position = actors[0].position + Vector3(0, 4, 100)
	actors[0].cloth._process(1.0 / 60.0)
	check(actors[0].cloth.source.visible and not actors[0].cloth.cloth_mesh.visible, "distant cape follows skeleton")
	camera.position = actors[0].position + Vector3(0, 2, 4)
	actors[0].cloth._process(1.0 / 60.0)
	check(not actors[0].cloth.source.visible and actors[0].cloth.cloth_mesh.visible, "near cloth resumes")
	report["failures"] = failures
	DirAccess.make_dir_recursive_absolute("res://build/prince")
	var output := FileAccess.open("res://build/prince/qa.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("PRINCE_QA ", JSON.stringify(report))
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
