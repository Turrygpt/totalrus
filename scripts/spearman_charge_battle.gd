extends "res://scripts/spearman_line_battle.gd"

const VIDEO_RIDER = preload("res://scripts/spearman_video_rider.gd")
const RIDERS := 4
const APPROACH_START := 10.0

func _ready() -> void:
	super._ready()
	camera_distance = 23.0
	camera_zoom_target = camera_distance
	camera_pitch = deg_to_rad(30.0)
	camera_yaw = .80
	focus = Vector3(1.0, .65, 1.5)
	update_camera()

func deployment_zone() -> Rect2:
	return Rect2(-10, 2, 20, 17)

func make_armies() -> void:
	squad = make_line(0, "Пешие копейщики", APPROACH_START)
	enemy = Node3D.new()
	enemy.set_script(SQUAD)
	enemy.team = 1
	enemy.unit_kind = "cavalry"
	enemy.unit_script = VIDEO_RIDER
	enemy.unit_count = RIDERS
	enemy.spawn_center = Vector3(0, 0, -APPROACH_START)
	enemy.spawn_heading = PI
	enemy.display_name = "Конные копейщики"
	enemy.ai_enabled = false
	add_child(enemy)
	squads.append(enemy)
	squad.opponent = enemy
	enemy.opponent = squad

func add_battle_size_control(parent: Control) -> void:
	UI.label(parent, "Натиск копейщиков", 20, UI.BONE)

func order_opening() -> void:
	squad.command_attack(enemy, true)
	enemy.command_attack(squad, true)
