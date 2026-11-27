extends Node3D

const TYPE_ONE = preload("res://scenes/horseman.tscn")
const TYPE_TWO = preload("res://scenes/horseman_tripo.tscn")
const COLUMNS := 6
const ROWS := 5
const GAITS: Array[StringName] = [&"Idle", &"Walk", &"Gallop"]
const LABELS := ["Стойка", "Шаг", "Галоп", "Дыбы", "Падение"]

@onready var camera: Camera3D = $Camera
@onready var buttons: HBoxContainer = $Canvas/Panel/Margin/Content/Buttons
@onready var formations: Array[Node3D] = [$TypeOne, $TypeTwo]

var orbit := .25
var elevation := .63

func _ready() -> void:
	_spawn(0, TYPE_ONE)
	_spawn(1, TYPE_TWO)
	var group := ButtonGroup.new()
	for index in LABELS.size():
		var button := Button.new()
		button.text = "%d  %s" % [index + 1, LABELS[index]]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.button_pressed = index == 0
		button.pressed.connect(_play.bind(index))
		buttons.add_child(button)
	_update_camera()

func _spawn(index: int, template: PackedScene) -> void:
	var formation := formations[index]
	var units := formation.get_node("Units")
	for row in ROWS:
		for column in COLUMNS:
			var actor: Node3D = template.instantiate()
			actor.position = Vector3((column - (COLUMNS - 1) * .5) * 2.55, 0,
					((ROWS - 1) * .5 - row) * 3.55)
			units.add_child(actor)
			var player: AnimationPlayer = actor.player
			player.speed_scale = .96 + .02 * ((row * COLUMNS + column * 3) % 5)
			_seek_phase(player, &"Idle", row * COLUMNS + column)

func _seek_phase(player: AnimationPlayer, clip: StringName, index: int) -> void:
	var length := player.get_animation(clip).length
	var phase := fposmod(index * .61803399, 1.0)
	player.seek(phase * length)

func _play(index: int) -> void:
	buttons.get_child(index).button_pressed = true
	for formation in formations:
		var units := formation.get_node("Units")
		for actor in units.get_children():
			if index == 0 or actor.fallen:
				actor.reset()
			if index == 3:
				actor.set_gait(&"Idle")
				actor.rear()
			elif index == 4:
				actor.die()
			else:
				var clip := GAITS[index]
				actor.set_gait(clip)
				if actor.player.current_animation == clip:
					_seek_phase(actor.player, clip, actor.get_index())

func _process(delta: float) -> void:
	var turn := Input.get_axis("ui_left", "ui_right")
	var tilt := Input.get_axis("ui_down", "ui_up")
	if not is_zero_approx(turn) or not is_zero_approx(tilt):
		orbit += turn * delta * 1.1
		elevation = clampf(elevation + tilt * delta, .25, 1.12)
		_update_camera()

func _update_camera() -> void:
	var focus := Vector3(0.0, .7, 0.0)
	camera.position = focus + 41.0 * Vector3(sin(orbit) * cos(elevation),
			sin(elevation), cos(orbit) * cos(elevation))
	camera.look_at(focus)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if key >= KEY_1 and key <= KEY_5:
			_play(key - KEY_1)
		elif key == KEY_R:
			_play(0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = maxf(11.0, camera.size * .91)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = minf(48.0, camera.size / .91)
