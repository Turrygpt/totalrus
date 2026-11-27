extends Node3D

const GAITS: Array[StringName] = [&"Idle", &"Walk", &"Gallop"]
const ACTIONS: Array[StringName] = [&"Rear", &"Death"]

@onready var player: AnimationPlayer = $Model/AnimationPlayer

var fallen := false
var gait: StringName = &"Idle"
var weapon_ready := false
var health := 100.0
var action_left := 0.0
var spear_immunity := 0.0
static var coats: Dictionary[int, Material] = {}

func _ready() -> void:
	for clip in GAITS:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		var armed := StringName("Ready" + String(clip))
		if player.has_animation(armed):
			player.get_animation(armed).loop_mode = Animation.LOOP_LINEAR
	for clip in ACTIONS:
		player.get_animation(clip).loop_mode = Animation.LOOP_NONE
	if player.has_animation(&"MeleeStrike"):
		player.get_animation(&"MeleeStrike").loop_mode = Animation.LOOP_NONE
	player.animation_finished.connect(_finish_action)
	player.play(gait)

func set_gait(next_gait: StringName) -> void:
	if not GAITS.has(next_gait):
		return
	gait = next_gait
	_play_gait(.085 if gait == &"Gallop" else .14)

func set_weapon_ready(ready: bool) -> void:
	if weapon_ready == ready:
		return
	weapon_ready = ready
	_play_gait(.27, true)

func _play_gait(blend: float, keep_phase := false) -> void:
	if fallen or action_left > 0.0 or player.current_animation == &"Rear":
		return
	var clip := StringName("Ready" + String(gait)) if weapon_ready else gait
	if not player.has_animation(clip):
		clip = gait
	if player.current_animation == clip:
		return
	var phase := player.current_animation_position / player.current_animation_length if keep_phase and player.current_animation_length > 0 else -1.0
	player.play(clip, blend)
	if phase >= 0:
		player.seek(player.get_animation(clip).length * phase)

func tint_coat(index: int) -> void:
	var horse := $Model.find_child("Horse", true, false) as MeshInstance3D
	if horse == null:
		return
	var tints := [Color(1, 1, 1), Color(.83, .84, .86), Color(1.12, 1.03, .93),
			Color(.92, .87, .85), Color(1.04, 1.06, 1.08)]
	var shade := index % tints.size()
	if not coats.has(shade):
		var mat := horse.get_active_material(0).duplicate() as StandardMaterial3D
		mat.albedo_color *= tints[shade]
		coats[shade] = mat
	horse.set_surface_override_material(0, coats[shade])

func rear() -> void:
	if not fallen and player.current_animation != &"Rear":
		player.play(&"Rear", .12)

func die() -> void:
	if not fallen:
		fallen = true
		action_left = 0.0
		player.speed_scale = 1.0
		player.play(&"Death", .10)

func receive_cavalry_hit(damage: float) -> void:
	if not fallen:
		health -= damage
		if health <= 0:
			die()

func receive_braced_spear(speed: float, roll: float) -> bool:
	if fallen or spear_immunity > 0.0:
		return false
	var impact := clampf((speed - 3.0) / 6.2, 0.0, 1.0)
	var fall_chance := .08 + .19 * impact
	if roll < fall_chance:
		health = 0.0
		die()
	else:
		receive_cavalry_hit(23.0 + 22.0 * impact)
		if not fallen and roll < fall_chance + .32 + .14 * impact:
			player.speed_scale = 1.0
			rear()
			action_left = player.get_animation(&"Rear").length
	spear_immunity = maxf(.7, action_left)
	return true

func start_melee_strike() -> bool:
	if fallen or action_left > 0.0 or not player.has_animation(&"MeleeStrike"):
		return false
	action_left = player.get_animation(&"MeleeStrike").length
	player.speed_scale = 1.0
	player.play(&"MeleeStrike", .075)
	return true

func tick_combat(delta: float) -> void:
	spear_immunity = maxf(0.0, spear_immunity - delta)
	if action_left > 0.0:
		action_left = maxf(0.0, action_left - delta)
		if action_left == 0.0 and not fallen:
			_resume_after_action()

func cancel_melee_strike() -> void:
	if player.current_animation == &"MeleeStrike":
		action_left = 0.0
		_resume_after_action()

func _resume_after_action() -> void:
	# A charge interrupted by a rear or a thrust resumes in the current gait.
	player.play(gait, .12)
	_play_gait(.12)

func reset() -> void:
	fallen = false
	weapon_ready = false
	health = 100.0
	action_left = 0.0
	spear_immunity = 0.0
	gait = &"Idle"
	player.stop()
	player.play(gait)
	player.advance(0)

func _finish_action(clip: StringName) -> void:
	if clip in [&"Rear", &"MeleeStrike"] and not fallen:
		action_left = 0.0
		_resume_after_action()
