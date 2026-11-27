extends Node3D

const ATTACK := preload("res://assets/spearman_video_lunge.tres")
const SPEAR := preload("res://assets/spear.glb")
const SHIELDS := preload("res://assets/spear_shield_variants.glb")
const CLIP := &"preview/video_lunge"
const FRAME_STEP := 1.0 / 30.0
const LOOP_PAUSE := .40
const ORBIT_TARGET := Vector3(0, .92, -.70)
const SPEEDS := [1.0, .5, .25]

@onready var camera: Camera3D = $Camera3D
@onready var player: AnimationPlayer = $Warrior.find_children("*", "AnimationPlayer", true, false)[0]
@onready var skeleton: Skeleton3D = $Warrior.find_children("*", "Skeleton3D", true, false)[0]
@onready var play_button: Button = %Play
@onready var time_label: Label = %Time
@onready var timeline: HSlider = %Timeline
@onready var speed_control: OptionButton = %Speed
@onready var view_control: OptionButton = %View

var time := 0.0
var wait_time := 0.0
var playing := true
var azimuth := 1.30
var elevation := .17
var distance := 4.9
var orbiting := false

func _ready() -> void:
	get_viewport().get_window().content_scale_size = Vector2i(1280, 720)
	var spear := SPEAR.instantiate() as Node3D
	mount_equipment(spear, &"GripRight")
	var shield_scene := SHIELDS.instantiate()
	var template := shield_scene.get_node("Shield01") as MeshInstance3D
	var shield := MeshInstance3D.new()
	shield.mesh = template.mesh
	shield_scene.free()
	mount_equipment(shield, &"GripLeft")
	shield.position += shield.basis.z * .055

	var library := AnimationLibrary.new()
	library.add_animation(&"video_lunge", ATTACK)
	player.add_animation_library(&"preview", library)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(CLIP)
	player.advance(0)

	make_grid()
	timeline.max_value = ATTACK.length
	timeline.value_changed.connect(scrub)
	play_button.pressed.connect(toggle_playback)
	%Replay.pressed.connect(replay)
	for caption in ["1×", "0,5×", "0,25×"]:
		speed_control.add_item(caption)
	for caption in ["Сбоку", "Три четверти", "Спереди"]:
		view_control.add_item(caption)
	view_control.item_selected.connect(set_view)
	set_view(0)
	show_time(0)

func mount_equipment(equipment: Node3D, bone: StringName) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	attachment.add_child(equipment)
	equipment.scale = Vector3.ONE / 1.8
	equipment.rotation.x = PI / 2.0

func make_grid() -> void:
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("3b474d")
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for i in range(-6, 7):
		var offset := i * .5
		lines.surface_add_vertex(Vector3(-3.0, .002, offset))
		lines.surface_add_vertex(Vector3(3.0, .002, offset))
		lines.surface_add_vertex(Vector3(offset, .002, -3.0))
		lines.surface_add_vertex(Vector3(offset, .002, 3.0))
	lines.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = lines
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grid)

func _process(delta: float) -> void:
	if not playing:
		return
	if time < ATTACK.length:
		show_time(minf(ATTACK.length, time + delta * SPEEDS[speed_control.selected]))
		return
	if not %Loop.button_pressed:
		set_playing(false)
		return
	wait_time += delta
	if wait_time >= LOOP_PAUSE:
		wait_time = 0.0
		show_time(0.0)

func show_time(value: float) -> void:
	time = value
	player.seek(time, true, true)
	timeline.set_value_no_signal(time)
	time_label.text = "%.2f / %.2f с" % [time, ATTACK.length]

func scrub(value: float) -> void:
	set_playing(false)
	wait_time = 0.0
	show_time(value)

func replay() -> void:
	wait_time = 0.0
	show_time(0.0)
	set_playing(true)

func toggle_playback() -> void:
	if not playing and time >= ATTACK.length:
		replay()
		return
	set_playing(not playing)

func set_playing(active: bool) -> void:
	playing = active
	play_button.text = "Пауза" if active else "Играть"

func set_view(index: int) -> void:
	azimuth = [1.39, .84, .05][index]
	elevation = .15
	distance = 4.9
	update_camera()

func update_camera() -> void:
	var horizontal := cos(elevation)
	var orbit := Vector3(sin(azimuth) * horizontal, sin(elevation), -cos(azimuth) * horizontal)
	camera.position = ORBIT_TARGET + orbit * distance
	camera.look_at(ORBIT_TARGET)

func _input(event: InputEvent) -> void:
	# End a drag even if the pointer is released over the controls.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		orbiting = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				if not event.echo:
					toggle_playback()
			KEY_LEFT:
				scrub(maxf(0.0, (ceilf(time / FRAME_STEP - .0001) - 1.0) * FRAME_STEP))
			KEY_RIGHT:
				scrub(minf(ATTACK.length, (floorf(time / FRAME_STEP + .0001) + 1.0) * FRAME_STEP))
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				orbiting = true
			MOUSE_BUTTON_WHEEL_UP:
				distance = maxf(2.6, distance * .90)
				update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = minf(9.0, distance / .90)
				update_camera()
	elif event is InputEventMouseMotion and orbiting:
		azimuth -= event.relative.x * .008
		elevation = clampf(elevation + event.relative.y * .008, -.08, 1.10)
		update_camera()
