extends "res://scripts/battlefield.gd"

const VIDEO_FIGHTER = preload("res://scripts/spearman_video_fighter.gd")
const LINE_SIZE := 6
const LINE_SPACING := 1.55
const START_DISTANCE := 3.6

func _ready() -> void:
	super._ready()
	camera_distance = 17.0
	camera_zoom_target = camera_distance
	camera_pitch = deg_to_rad(29.0)
	camera_yaw = .70
	focus = Vector3(1.0, 0.65, 0.95)
	update_camera()

func battle_size() -> int:
	return 1

func make_terrain() -> void:
	field_half_size = Vector2(34, 30)
	super.make_terrain()

func deployment_zone() -> Rect2:
	return Rect2(-10, 1.5, 20, 9.5)

func make_armies() -> void:
	squad = make_line(0, "Сокол")
	enemy = make_line(1, "Вепрь")
	squad.opponent = enemy
	enemy.opponent = squad

func make_line(side: int, title: String, distance := START_DISTANCE) -> Node3D:
	var line := Node3D.new()
	line.set_script(SQUAD)
	line.team = side
	line.unit_script = VIDEO_FIGHTER
	line.unit_count = LINE_SIZE
	line.formation_columns = LINE_SIZE
	line.formation_width = LINE_SPACING * (LINE_SIZE - 1)
	line.spawn_center = Vector3(0, 0, distance if side == 0 else -distance)
	line.spawn_heading = 0.0 if side == 0 else PI
	line.display_name = title
	line.ai_enabled = false
	add_child(line)
	for actor in line.soldiers:
		actor.video_attack_only = true
	squads.append(line)
	return line

func add_battle_size_control(parent: Control) -> void:
	UI.label(parent, "Два ряда копейщиков", 20, UI.BONE)

func set_battle_paused(pause: bool) -> void:
	var first_advance := deploying and not pause
	super.set_battle_paused(pause)
	if first_advance:
		order_opening()

func order_opening() -> void:
	squad.command_attack(enemy, false)
	enemy.command_attack(squad, false)
