extends Node3D

const CLIPS: Array[StringName] = [&"Idle", &"Walk", &"Gallop", &"Rear", &"Death"]
const TITLES := ["Стойка", "Шаг", "Галоп", "Дыбы", "Падение"]

@onready var horseman = $Horseman
@onready var camera: Camera3D = $Camera
@onready var buttons: HBoxContainer = $Canvas/Panel/Margin/Content/Buttons

var orbit := .98
var focus := Vector3(0, 1.48, 0)

func _ready() -> void:
	for index in CLIPS.size():
		var button := Button.new()
		button.text = "%d  %s" % [index + 1, TITLES[index]]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_play.bind(index))
		buttons.add_child(button)
	var reset := Button.new()
	reset.text = "R  Сброс"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(horseman.reset)
	buttons.add_child(reset)
	_update_camera()

func _process(delta: float) -> void:
	var turn := Input.get_axis("ui_left", "ui_right")
	orbit += turn * delta * 1.35
	var target := Vector3(.95, .65, 0) if horseman.fallen else Vector3(0, 1.48, 0)
	if not is_zero_approx(turn) or not focus.is_equal_approx(target):
		focus = focus.lerp(target, 1.0 - exp(-4.0 * delta))
		_update_camera()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if key >= KEY_1 and key <= KEY_5:
		_play(key - KEY_1)
	elif key == KEY_R:
		horseman.reset()

func _play(index: int) -> void:
	var clip := CLIPS[index]
	if horseman.fallen:
		horseman.reset()
	if clip == &"Rear":
		horseman.set_gait(&"Idle")
		horseman.rear()
	elif clip == &"Death":
		horseman.die()
	else:
		horseman.set_gait(clip)

func _update_camera() -> void:
	camera.position = focus + Vector3(sin(orbit) * 5.55, 1.37, cos(orbit) * 5.55)
	camera.look_at(focus)
