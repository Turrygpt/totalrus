extends SceneTree
## Renderer-backed 60 versus 60 integration and crowd-animation coverage.
## Run with --windowed --resolution 960x600 --rendering-method gl_compatibility.
const SPEAR_COMBAT = preload("res://scripts/spear_combat.gd")
const REPORT := "res://build/spear_battle_qa.json"
const OVERVIEW := "res://build/spear_battle_overview.png"
const CLOSEUP := "res://build/spear_battle_close.png"
const SIMULATION_SECONDS := 36.0
const WALL_LIMIT_SECONDS := 49.0

var failures: Array[String] = []
var samples: Array[Dictionary] = []
var aliases: Array[String] = []
var actors: Array = []
var histogram: Dictionary = {}
var starts: Dictionary = {}
var previous_actions: Dictionary = {}
var participants: Dictionary = {}
var missing_sources: Dictionary = {}
var world
var real_start := 0
var simulation_start := 0.0
var max_distant := 0
var distant_attack_samples := 0
var max_detailed := 0
var close_set := false
var close_saved := false
var overview_set := false
var overview_saved := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func wall_seconds() -> float:
	return (Time.get_ticks_msec() - real_start) / 1000.0

func run() -> void:
	real_start = Time.get_ticks_msec()
	seed(73452)
	change_scene_to_file("res://tools/front_qa_world.tscn")
	await create_timer(1.1).timeout
	world = current_scene
	world.camera_locked = true
	world.camera_distance = 38
	world.camera_yaw = .25
	world.focus = Vector3.ZERO
	world.update_camera()
	# Keep a full 36 simulated seconds within the wall budget even on cold GL setup.
	world.set_speed(2)
	aliases.assign(SPEAR_COMBAT.attack_names())
	for alias in aliases:
		histogram[alias] = 0
		starts[alias] = 0
	for group in world.squads:
		group.ai_enabled = false
		for actor in group.soldiers:
			actor.hp = 500
			actor.max_hp = 500
			actors.append(actor)
	check(actors.size() == 120 and world.squad.alive_count() == 60 and world.enemy.alive_count() == 60, "renderer battle starts with 60 spear fighters per side")
	check(DisplayServer.get_name() != "headless", "battle runs with an actual rendering backend")
	world.squad.command_attack(world.enemy, true)
	world.enemy.command_attack(world.squad, true)
	simulation_start = world.battle_time
	var next_progress := 5.0
	while world.battle_time - simulation_start < SIMULATION_SECONDS and wall_seconds() < WALL_LIMIT_SECONDS:
		await create_timer(.1).timeout
		var elapsed: float = world.battle_time - simulation_start
		var sample := sample_battle(elapsed)
		samples.append(sample)
		if elapsed >= next_progress:
			print("SPEAR_BATTLE_SAMPLE ", JSON.stringify(sample))
			next_progress += 5
		if elapsed >= 18 and not close_set:
			world.focus = fight_focus()
			world.camera_distance = 7
			world.camera_yaw = .45
			world.update_camera()
			close_set = true
		if elapsed >= 19 and not close_saved:
			await screenshot(CLOSEUP)
			close_saved = true
		if elapsed >= 26 and not overview_set:
			world.focus = (world.squad.center() + world.enemy.center()) * .5
			world.camera_distance = 38
			world.camera_yaw = .25
			world.update_camera()
			overview_set = true
		if elapsed >= 27 and not overview_saved:
			await screenshot(OVERVIEW)
			overview_saved = true
	var simulated_seconds: float = world.battle_time - simulation_start
	check(simulated_seconds >= 30, "battle runs for at least 30 simulated seconds within its wall-clock budget")
	check(aliases.size() == 10 and aliases.all(func(alias): return int(histogram.get(alias, 0)) > 0), "all ten authored spear attacks appear in live AI combat")
	check(missing_sources.is_empty(), "every observed spear attack has a supported baked crowd source")
	check(max_distant > 0 and distant_attack_samples > 0, "distant crowd fighters actually perform authored spear attacks")
	check(world.effects.hits > 0 and world.effects.blocks > 0, "live combat produces both body hits and shield blocks")
	check(actors.any(func(actor): return actor.hp < 500), "live contact events reduce individual health")
	check(close_saved and overview_saved, "close fight and overview screenshots were rendered")
	# Stop issuing attacks, then let committed event animations recover naturally.
	for group in world.squads:
		group.ai_enabled = false
		group.attack_target = null
		group.set_physics_process(false)
	world.combat_fronts.set_physics_process(false)
	world.crowd_movement.set_physics_process(false)
	world.crowd_movement.set_process(false)
	var draining := 0
	for actor in actors:
		if actor.busy and SPEAR_COMBAT.is_attack(actor.active_action): draining += 1
		actor.attack_order = false
		actor.combat_target = null
		actor.set_physics_process(false)
	await create_timer(3.0).timeout
	var stuck: Array = []
	for actor in actors:
		if actor.alive and actor.busy and SPEAR_COMBAT.is_attack(actor.active_action):
			stuck.append({"team": actor.team, "index": actor.index, "action": actor.active_action, "event_playing": actor.events.is_playing(), "event_position": actor.events.current_animation_position})
	check(stuck.is_empty(), "committed spear attacks release busy state after recovery")
	var report := {
		"failures": failures, "simulation_seconds": simulated_seconds, "wall_seconds": wall_seconds(),
		"simulation_speed": 2,
		"actors": actors.size(), "alive": [world.team_alive(0), world.team_alive(1)],
		"hits": world.effects.hits, "blocks": world.effects.blocks, "observed_attackers": participants.size(),
		"attack_sample_histogram": histogram, "observed_attack_starts": starts,
		"max_distant": max_distant, "distant_attack_samples": distant_attack_samples, "max_detailed": max_detailed,
		"missing_crowd_sources": missing_sources, "draining_attacks": draining, "stuck_attacks": stuck,
		"screenshots": [CLOSEUP, OVERVIEW], "samples": samples,
	}
	FileAccess.open(REPORT, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("SPEAR_BATTLE_QA ", JSON.stringify({"failures": failures, "hits": report.hits, "blocks": report.blocks, "observed_attack_starts": starts, "wall_seconds": report.wall_seconds, "report": REPORT}))
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func sample_battle(elapsed: float) -> Dictionary:
	var attacking := 0
	var distant := 0
	var distant_attacking := 0
	for actor in actors:
		var actor_id: int = actor.get_instance_id()
		var action: String = actor.active_action
		var visual = actor.crowd_visual
		if visual and visual.distant: distant += 1
		if SPEAR_COMBAT.is_attack(action):
			attacking += 1
			participants[actor_id] = true
			histogram[action] = int(histogram.get(action, 0)) + 1
			if previous_actions.get(actor_id, "") != action: starts[action] = int(starts.get(action, 0)) + 1
			if visual and visual.distant:
				distant_attacking += 1
				distant_attack_samples += 1
			if not visual or not visual.supports_current():
				var source: String = actor.animation_map.get(actor.animation_name, "")
				missing_sources[action + ":" + source] = true
		previous_actions[actor_id] = action
	max_distant = maxi(max_distant, distant)
	max_detailed = maxi(max_detailed, world.crowd_renderer.detailed_actors.size())
	return {"t": elapsed, "attacking": attacking, "distant": distant, "distant_attacking": distant_attacking,
		"detailed": world.crowd_renderer.detailed_actors.size(), "hits": world.effects.hits, "blocks": world.effects.blocks,
		"alive": [world.team_alive(0), world.team_alive(1)], "camera_distance": world.camera_distance}

func fight_focus() -> Vector3:
	for actor in actors:
		if actor.alive and SPEAR_COMBAT.is_attack(actor.active_action) and is_instance_valid(actor.strike_target):
			return (actor.global_position + actor.strike_target.global_position) * .5 + Vector3.UP * .65
	return (world.squad.center() + world.enemy.center()) * .5 + Vector3.UP * .65

func screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	check(result == OK, "saved " + path.get_file())
