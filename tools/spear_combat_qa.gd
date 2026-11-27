extends SceneTree
## Deterministic integration checks for authored spear contacts and legacy users.
## Godot --headless --path . --script res://tools/spear_combat_qa.gd

const SPEAR_COMBAT = preload("res://scripts/spear_combat.gd")
const SOLDIER = preload("res://scripts/soldier.gd")
const ARCHER = preload("res://scripts/archer.gd")
const CAVALRY = preload("res://scripts/cavalry.gd")
const CONTACT_FRAMES := [[10], [17], [14], [16], [15], [15], [19], [25], [12, 28], [30]]
const END_FRAMES := [30, 46, 38, 42, 40, 40, 46, 50, 56, 58]
const REPORT := "res://build/spear_combat_qa.json"

class TestWorld extends Node3D:
	var battle_time := 0.0
	var crowd_movement = null
	var crowd_renderer = null
	var serial := 0
	var wavering := false
	func alert_enemy(_other: Node3D) -> void: pass
	func record_flank_hit(_facing: float, _damage: float) -> void: pass
	func soldier_died(_actor: Node3D) -> void: pass

class EffectsSpy extends Node3D:
	var hits := 0
	var blocks := 0
	var records: Array[Dictionary] = []
	func sound(_kind: String, _point: Vector3, _volume := -6.0) -> bool: return true
	func blood_stain(_point: Vector3, _size := .65) -> void: pass
	func impact(point: Vector3, _direction: Vector3, blocked: bool, _arrow_hit := false, _spear_hit := false) -> void:
		if blocked: blocks += 1
		else: hits += 1
		records.append({"point": str(point), "blocked": blocked})
	func reset() -> void:
		hits = 0
		blocks = 0
		records.clear()

var failures: Array[String] = []
var assertions := 0
var world: TestWorld
var effects: EffectsSpy
var attacker
var defender
var aliases: Array = []
var tested_contacts: Array[Dictionary] = []
var cycle_log: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	assertions += 1
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)

func spawn_actor(script: Script, team_id: int, number: int):
	var actor = CharacterBody3D.new()
	actor.set_script(script)
	actor.team = team_id
	actor.index = number
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.agent.avoidance_enabled = false
	actor.events.process_mode = Node.PROCESS_MODE_DISABLED
	return actor

func reset_actor(actor, point: Vector3, heading: float) -> void:
	actor.events.stop()
	actor.player.stop()
	actor.busy = false
	actor.active_action = ""
	actor.animation_name = ""
	actor.animation_clock = 0
	actor.strike_done = false
	actor.strike_target = null
	actor.combat_target = null
	actor.attack_order = false
	actor.guarding = false
	actor.shield_raised = false
	actor.fleeing = false
	actor.alive = true
	actor.hp = 1000
	actor.max_hp = 1000
	actor.velocity = Vector3.ZERO
	actor.motion_speed = 0
	actor.position = point
	actor.rotation.y = heading
	actor.target = point
	actor.collision_layer = 2
	actor.visual_position_from = point
	actor.visual_yaw_from = heading
	actor.visual_elapsed = 1
	actor.resolved_spear_contacts.clear()
	actor.last_spear_contact.clear()
	actor.last_hit_result.clear()
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.events.process_mode = Node.PROCESS_MODE_DISABLED

func reset_pair(raised := true, backside := false) -> void:
	reset_actor(attacker, Vector3.ZERO, 0)
	reset_actor(defender, Vector3(0, 0, -1.85), 0 if backside else PI)
	attacker.has_spear = true
	defender.shield_raised = raised
	attacker.combat_target = defender
	effects.reset()

func start_alias(actor, victim, wanted: String) -> bool:
	# Exercise the actual selection/initialization path, without changing its bag.
	for attempt in 21:
		actor.events.stop()
		actor.busy = false
		actor.active_action = ""
		actor.animation_name = ""
		actor.combat_target = victim
		actor.begin_strike()
		if actor.active_action == wanted:
			actor.events.advance(0)
			return true
		actor.events.stop()
		actor.action_finished(actor.active_action)
	check(false, "selector can reach " + wanted)
	return false

func advance_to(actor, seconds: float) -> void:
	actor.events.advance(maxf(0, seconds - actor.events.current_animation_position))
	# Method tracks can be deferred; flush them before observing HP/effects.
	await process_frame
	await process_frame

func total_impacts() -> int:
	return effects.hits + effects.blocks

func run() -> void:
	world = TestWorld.new()
	root.add_child(world)
	current_scene = world
	effects = EffectsSpy.new()
	effects.name = "BattleEffects"
	world.add_child(effects)
	attacker = spawn_actor(SOLDIER, 0, 501)
	defender = spawn_actor(SOLDIER, 1, 502)
	aliases.assign(SPEAR_COMBAT.attack_names())
	check(aliases.size() == 10, "ten authored spear attack aliases are available")
	if aliases.size() != 10:
		await finish()
		return
	aliases.sort()
	await physics_frame
	await physics_frame
	test_inventory()
	test_rotation()
	await test_all_contacts()
	await test_shield_contexts()
	await test_misses_and_interruptions()
	await test_legacy_users()
	await finish()

func test_inventory() -> void:
	for i in aliases.size():
		var alias: String = aliases[i]
		check(attacker.animation_map.has(alias) and attacker.events.has_animation(alias), alias + " has visual and event clips")
		if not attacker.animation_map.has(alias) or not attacker.events.has_animation(alias): continue
		var visual: Animation = attacker.player.get_animation(attacker.animation_map[alias])
		var event: Animation = attacker.events.get_animation(alias)
		check(absf(visual.length - END_FRAMES[i] / 30.0) < .002 and absf(event.length - visual.length) < .002, alias + " event duration matches authored animation")
		check(visual.loop_mode == Animation.LOOP_NONE, alias + " is a one-shot")
		var contacts: Array = []
		for track in event.get_track_count():
			if event.track_get_type(track) != Animation.TYPE_METHOD: continue
			for key in event.track_get_key_count(track):
				var value: Dictionary = event.track_get_key_value(track, key)
				if String(value.get("method", "")) == "resolve_spear_contact":
					contacts.append({"time": event.track_get_key_time(track, key), "args": value.get("args", [])})
		check(contacts.size() == CONTACT_FRAMES[i].size(), alias + " contains the authored number of contacts")
		for j in mini(contacts.size(), CONTACT_FRAMES[i].size()):
			check(absf(float(contacts[j].time) - CONTACT_FRAMES[i][j] / 30.0) < .0001 and contacts[j].args == [j], alias + " contact %d has exact time/index" % j)
	var guard_matches: bool = attacker.animation_map.get("combat_spear", "") == attacker.animation_map.get("spear_ready_loop", "missing")
	if not guard_matches:
		print("GUARD_ALIAS_DIAGNOSTIC ", JSON.stringify({"combat_spear": attacker.animation_map.get("combat_spear"), "spear_ready_loop": attacker.animation_map.get("spear_ready_loop"), "ready_names": attacker.animation_map.keys().filter(func(name): return "spear_ready" in name), "definition": SPEAR_COMBAT.definitions().get("guard", {})}))
	check(guard_matches, "combat stance uses the new common guard")

func test_rotation() -> void:
	reset_pair()
	var previous := ""
	for cycle in 3:
		var seen := {}
		for i in 10:
			attacker.begin_strike()
			var selected: String = attacker.active_action
			seen[selected] = true
			cycle_log.append(selected)
			check(selected != previous, "spear selection does not repeat immediately at strike %d" % (cycle * 10 + i))
			previous = selected
			attacker.events.stop()
			attacker.action_finished(selected)
		check(seen.size() == 10 and aliases.all(func(alias): return seen.has(alias)), "selection cycle %d uses all ten attacks exactly once" % (cycle + 1))

func test_all_contacts() -> void:
	for i in aliases.size():
		reset_pair()
		var alias: String = aliases[i]
		if not start_alias(attacker, defender, alias): continue
		var previous_hp: float = defender.hp
		for j in CONTACT_FRAMES[i].size():
			var moment: float = CONTACT_FRAMES[i][j] / 30.0
			await advance_to(attacker, moment - .002)
			check(total_impacts() == j and is_equal_approx(defender.hp, previous_hp), alias + " contact %d cannot hit during anticipation" % j)
			await advance_to(attacker, moment + .002)
			check(total_impacts() == j + 1 and defender.hp < previous_hp, alias + " contact %d resolves at its animation event" % j)
			check(attacker.resolved_spear_contacts.size() == j + 1, alias + " contact bookkeeping counts each attempt once")
			var committed_hp: float = defender.hp
			attacker.resolve_spear_contact(j)
			attacker.resolve_strike()
			await process_frame
			check(is_equal_approx(defender.hp, committed_hp) and total_impacts() == j + 1, alias + " duplicate/legacy callbacks cannot deal extra damage")
			tested_contacts.append({"clip": alias, "index": j, "result": attacker.last_spear_contact.duplicate(true), "victim": defender.last_hit_result.duplicate(true)})
			previous_hp = defender.hp
			check(attacker.strike_done == (j == CONTACT_FRAMES[i].size() - 1), alias + " remains active until all authored contacts are attempted")
		await advance_to(attacker, END_FRAMES[i] / 30.0 + .02)
		check(not attacker.busy and attacker.active_action == "", alias + " recovery finishes and releases action state")
		check(total_impacts() == CONTACT_FRAMES[i].size(), alias + " recovery has no extra hit event")
	# Clip 10's feint at frame 12 is intentionally not a damage event.
	reset_pair()
	if start_alias(attacker, defender, "attack_spear_10"):
		await advance_to(attacker, .70)
		check(total_impacts() == 0 and defender.hp == 1000, "high feint never causes a premature body/shield hit")

func test_shield_contexts() -> void:
	# Same authored contact, different defender protection/orientation.
	for setup in ["frontal", "lowered", "backside", "backside_range"]:
		reset_pair(setup != "lowered", setup.begins_with("backside"))
		# Turning moves this short jab's shield point to the victim's far side.
		# Step into its actual reach so this checks shield orientation, not range.
		if setup == "backside": defender.position.z = -.85
		if not start_alias(attacker, defender, "attack_spear_01"): continue
		await advance_to(attacker, 10.0 / 30.0 + .002)
		if setup == "backside_range":
			check(total_impacts() == 0 and defender.hp == 1000, "short jab cannot reach far-side shield target from behind at 1.85m")
			continue
		var should_block: bool = setup == "frontal"
		if total_impacts() != 1:
			print("SHIELD_CONTEXT_DIAGNOSTIC ", setup, " ", JSON.stringify({"contact": attacker.last_spear_contact, "victim": defender.last_hit_result}))
		check(bool(defender.last_hit_result.get("blocked", false)) == should_block and total_impacts() == 1, "shield-targeted jab: " + setup + " protection is respected")
		check((1000.0 - defender.hp < 5.0) if should_block else (1000.0 - defender.hp > 10.0), "shield-targeted jab: " + setup + " applies appropriate damage")
	for alias in ["attack_spear_02", "attack_spear_03", "attack_spear_04", "attack_spear_05", "attack_spear_07", "attack_spear_08", "attack_spear_10"]:
		reset_pair()
		if not start_alias(attacker, defender, alias): continue
		var index: int = aliases.find(alias)
		await advance_to(attacker, CONTACT_FRAMES[index][0] / 30.0 + .002)
		check(effects.hits == 1 and effects.blocks == 0 and not bool(defender.last_hit_result.get("blocked", true)), alias + " reaches its open zone despite frontal raised shield")
	reset_pair()
	if start_alias(attacker, defender, "attack_spear_09"):
		await advance_to(attacker, 12.0 / 30.0 + .002)
		check(effects.blocks == 1 and effects.hits == 0, "double jab first contact hits shield")
		await advance_to(attacker, 28.0 / 30.0 + .002)
		check(effects.blocks == 1 and effects.hits == 1, "double jab translates from shield to exposed knee")

func test_misses_and_interruptions() -> void:
	for scenario in ["range", "facing", "friendly", "obstruction"]:
		reset_pair(false)
		if not start_alias(attacker, defender, "attack_spear_02"): continue
		var blocker = null
		match scenario:
			"range": defender.position.z = -5.0
			"facing": attacker.rotation.y = PI
			"friendly": defender.team = attacker.team
			"obstruction":
				blocker = spawn_actor(SOLDIER, 0, 590)
				reset_actor(blocker, Vector3(0, 0, -.85), 0)
		await physics_frame
		await physics_frame
		await advance_to(attacker, 17.0 / 30.0 + .002)
		check(defender.hp == 1000 and total_impacts() == 0, scenario + " prevents a spear hit")
		check(attacker.resolved_spear_contacts.size() == 1, scenario + " still consumes the contact event")
		defender.team = 1
		if is_instance_valid(blocker):
			blocker.queue_free()
			await physics_frame
	for scenario in ["flinch", "death", "flee"]:
		reset_pair(false)
		if not start_alias(attacker, defender, "attack_spear_09"): continue
		await advance_to(attacker, 12.0 / 30.0 + .002)
		var hp_after_first: float = defender.hp
		match scenario:
			"flinch": attacker.receive_hit(5.0, defender)
			"death": attacker.die()
			"flee": attacker.flee(Vector3(0, 0, 5), 0)
		var impacts_after_interrupt := total_impacts()
		attacker.resolve_spear_contact(1)
		attacker.events.advance(.8)
		await process_frame
		await process_frame
		check(is_equal_approx(defender.hp, hp_after_first) and total_impacts() == impacts_after_interrupt, scenario + " cancels double-jab second contact")

func test_legacy_users() -> void:
	reset_pair(false)
	attacker.has_spear = false
	defender.position.z = -.85
	attacker.begin_strike()
	var sword_action: String = attacker.active_action
	check(sword_action in ["attack_sword", "attack_sword_alt"], "infantry sword retains its existing attack selection")
	await advance_to(attacker, .75)
	check(defender.hp < 1000 and effects.hits == 1, "legacy sword method event still deals exactly one hit")
	attacker.position = Vector3(30, 0, 30)
	attacker.collision_layer = 0
	var archer = spawn_actor(ARCHER, 0, 601)
	reset_actor(archer, Vector3(8, 0, 0), 0)
	reset_actor(defender, Vector3(8, 0, -.8), PI)
	archer.has_spear = false
	archer.take_sword()
	archer.combat_target = defender
	effects.reset()
	archer.begin_strike()
	await advance_to(archer, .16)
	check(defender.hp < 1000 and effects.hits == 1, "archer knife keeps no-argument resolve_strike event")
	# Authored context follows the preserved optional projectile contact argument.
	archer.hp = 1000
	archer.shield_raised = true
	var context := {"contact": {}, "origin": defender.global_position + Vector3.UP, "point": archer.global_position + Vector3.UP, "zone": "shield_center"}
	archer.receive_hit(20.0, defender, false, false, false, Vector3.INF, context)
	check(archer.hp == 980 and not bool(archer.last_hit_result.get("blocked", true)), "shieldless archer accepts authored context and cannot block")
	archer.position = Vector3(35, 0, 35)
	archer.collision_layer = 0
	var rider = spawn_actor(CAVALRY, 0, 602)
	reset_actor(rider, Vector3(16, 0, 0), 0)
	reset_actor(defender, Vector3(16, 0, -1.8), PI)
	await physics_frame
	await physics_frame
	rider.combat_target = defender
	effects.reset()
	rider.begin_strike()
	check(rider.active_action == "attack_spear" and rider.animation_map["attack_spear"] == &"video/strike", "mounted fighter uses the new spear animation")
	await advance_to(rider, CAVALRY.SPEAR_CONTACT_TIME + .002)
	check(defender.hp < 1000 and effects.hits == 1, "cavalry deals one hit at the new contact frame")
	rider.queue_free()
	archer.queue_free()

func finish() -> void:
	var report := {"assertions": assertions, "failures": failures, "selection_cycles": cycle_log, "contacts": tested_contacts}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	FileAccess.open(REPORT, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("SPEAR_COMBAT_QA ", JSON.stringify({"assertions": assertions, "failures": failures, "report": REPORT}))
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
