extends SceneTree
const SOLDIER = preload("res://scripts/soldier.gd")
const CROWD = preload("res://scripts/crowd_visual.gd")
const SPEAR = preload("res://scripts/spear_combat.gd")
const ALIAS := "attack_spear_01"
const RATE := 2.35

class ProbeSoldier extends "res://scripts/soldier.gd":
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

class RendererSpy extends Node3D:
	var values: Dictionary = {}
	var writes := 0
	func custom(entry: Dictionary, value: Color) -> void:
		values[entry.tag] = value
		writes += 1
	func appearance(_entry: Dictionary, _value: Color) -> void: pass

class ProbeWorld extends Node3D:
	var battle_time := 120.0
	var crowd_renderer: Node3D

var failures: Array[String] = []
var results: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, name: String, value: Variant = null) -> void:
	print("PASS " if ok else "FAIL ", name, " ", value)
	results[name] = value
	if not ok: failures.append(name)

func run() -> void:
	var world := ProbeWorld.new()
	root.add_child(world)
	current_scene = world
	var renderer := RendererSpy.new()
	world.add_child(renderer)
	world.crowd_renderer = renderer
	var actor := ProbeSoldier.new()
	world.add_child(actor)
	actor.player = AnimationPlayer.new()
	actor.add_child(actor.player)
	actor.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.events = AnimationPlayer.new()
	actor.add_child(actor.events)
	actor.events.process_mode = Node.PROCESS_MODE_DISABLED
	var definition: Dictionary = SPEAR.attack(ALIAS)
	var source: String = definition.clip
	actor.animation_map[ALIAS] = source
	for pair in [[actor.player, source], [actor.events, ALIAS]]:
		var library := AnimationLibrary.new()
		var clip := Animation.new()
		clip.length = float(definition.duration)
		library.add_animation(pair[1], clip)
		pair[0].add_animation_library("", library)
	actor.animation_name = ALIAS
	actor.player.play(source)
	actor.player.advance(.25)
	actor.events.play(ALIAS)
	actor.events.advance(.20)
	actor.visual_delta = .37
	actor.start_strike(ALIAS, RATE)
	actor.player.advance(0)
	actor.events.advance(0)
	check(is_zero_approx(actor.visual_delta), "detailed accumulated delta resets", actor.visual_delta)
	check(is_zero_approx(actor.player.current_animation_position), "detailed same playing clip restarts at zero", actor.player.current_animation_position)
	check(is_zero_approx(actor.events.current_animation_position), "same event clip restarts at zero", actor.events.current_animation_position)
	check(is_equal_approx(actor.player.speed_scale, RATE) and is_equal_approx(actor.events.get_playing_speed(), RATE), "detailed and contact clocks use requested speed", [actor.player.speed_scale, actor.events.get_playing_speed()])
	actor.player.advance(.03)
	actor.events.advance(.03)
	check(absf(actor.player.current_animation_position - .03 * RATE) < .00001, "detailed advances only fresh elapsed time", actor.player.current_animation_position)
	check(absf(actor.events.current_animation_position - .03 * RATE) < .00001, "event clock advances at accelerated rate", actor.events.current_animation_position)
	actor.events.stop()
	var visual = CROWD.new(actor)
	actor.crowd_visual = visual
	visual.renderer = renderer
	visual.distant = true
	visual.full_name = source
	visual.clock = .41
	visual.last_tick = world.battle_time - 3.0
	visual.body_entry = {"shown": true, "tag": "body"}
	visual.shadow_entry = {"shown": true, "tag": "shadow"}
	actor.visual_delta = .29
	actor.start_strike(ALIAS, RATE)
	check(is_zero_approx(actor.visual_delta), "distant accumulated delta resets", actor.visual_delta)
	check(is_equal_approx(visual.last_tick, world.battle_time), "distant scheduler timestamp resets", visual.last_tick)
	check(is_zero_approx(visual.clock), "distant same clip restarts at zero", visual.clock)
	for tag in ["body", "shadow"]:
		var data: Color = renderer.values.get(tag, Color(-1, -1, -1, -1))
		check(is_equal_approx(data.a, RATE), tag + " VAT receives accelerated rate immediately", data.a)
		check(is_equal_approx(data.b, world.battle_time), tag + " VAT starts on current battle timestamp", data.b)
	world.battle_time += .03
	var fresh: float = world.battle_time - visual.last_tick
	visual.advance(fresh)
	check(absf(visual.clock - .03 * RATE) < .00001, "next distant update excludes time accumulated before attack", visual.clock)
	visual.clock = .52
	visual.last_tick = world.battle_time - .6
	actor.visual_delta = .6
	actor.start_strike(ALIAS, RATE)
	check(is_zero_approx(visual.clock) and is_zero_approx(actor.visual_delta) and is_equal_approx(visual.last_tick, world.battle_time), "repeated distant strike resets all clocks again", [visual.clock, actor.visual_delta, visual.last_tick])
	var report := {"failures": failures, "results": results, "vat_writes": renderer.writes}
	FileAccess.open("res://build/spear_visual_sync_qa.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("SPEAR_VISUAL_SYNC_QA ", JSON.stringify({"failures": failures, "vat_writes": renderer.writes}))
	actor.crowd_visual = null
	world.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
