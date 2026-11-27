extends "res://scripts/battlefield.gd"

const InfantryUnitAI = preload("res://scripts/infantry_unit_ai.gd")
const RangedUnitAI = preload("res://scripts/ranged_unit_ai.gd")
const MountedUnitAI = preload("res://scripts/mounted_unit_ai.gd")
const LabUnitAI = preload("res://scripts/lab_unit_ai.gd")
const SCENARIO_KEY := &"tactical_ai_lab_scenario"
const UNIT_KEY := &"tactical_ai_lab_unit"
const UNIT_KINDS := ["infantry", "militia", "archer", "light_cavalry", "cavalry", "princely", "varangian", "khazar"]
const RANGED_KINDS := ["archer", "khazar"]
const MOUNTED_KINDS := preload("res://scripts/cavalry_charge.gd").UNIT_KINDS
enum Drill { ATTACK, DEFENSE, SUPPORT, MANEUVER }
const DRILLS := ["Атака", "Оборона", "Помощь", "Манёвр"]
const SPEAR_OBJECTIVES := [
	"Сблизиться с ополчением и перейти в натиск.",
	"Удержать позицию и встретить конницу копьями.",
	"Перехватить конницу на подступах к лучникам.",
	"Обойти строй, пока ополчение сдерживает противника.",
]
const RANGED_OBJECTIVES := [
	"Выйти на дистанцию и открыть огонь по ополчению.",
	"Отойти от наступающего отряда и снова открыть огонь.",
	"Поддержать союзный отряд огнём.",
	"Сменить позицию и обстрелять врага сбоку.",
]
const INFANTRY_OBJECTIVES := [
	"Сблизиться с врагом и атаковать.",
	"Удержать рубеж против атакующей пехоты.",
	"Встретить врага, который атакует лучников.",
	"Обойти врага, пока ополчение сдерживает его спереди.",
]
const MOUNTED_OBJECTIVES := [
	"Атаковать ополчение конным натиском.",
	"Дождаться сближения врага и перехватить его.",
	"Защитить лучников встречной атакой.",
	"Обойти передние ряды копейщиков и атаковать с открытой стороны.",
]

var drill: int = Drill.ATTACK
var unit_kind := "infantry"
var controller: LabUnitAI
var ally: Node3D
var orders_issued := false
var decision_label: Label

func _ready() -> void:
	drill = clampi(get_tree().get_meta(SCENARIO_KEY, drill), 0, DRILLS.size() - 1)
	get_tree().remove_meta(SCENARIO_KEY)
	unit_kind = get_tree().get_meta(UNIT_KEY, unit_kind)
	get_tree().remove_meta(UNIT_KEY)
	if not unit_kind in UNIT_KINDS:
		unit_kind = UNIT_KINDS[0]
	super._ready()
	camera_distance = 112.0
	camera_zoom_target = camera_distance
	focus = Vector3(0, 0, 8)
	update_camera()
	deployment_line.hide()

func battle_size() -> int:
	return 1

func unit_spawn_point(point: Vector3) -> Vector3:
	return point

func make_armies() -> void:
	if unit_kind == "infantry":
		make_spear_armies()
	elif unit_kind in RANGED_KINDS:
		make_ranged_armies()
	else:
		make_melee_armies()
	for group in squads:
		# The lab issues all squad orders. Soldiers retain their regular combat behaviour.
		group.ai_enabled = false
		group.selected = group == squad
		group.opponent = enemy if group.team == 0 else squad

func make_spear_armies() -> void:
	match drill:
		Drill.DEFENSE:
			squad = make_unit(0, Vector3(0, 0, 14), "Копейщики ИИ", "infantry", 36)
			enemy = make_unit(1, Vector3(0, 0, -35), "Конница", "cavalry", 16)
		Drill.SUPPORT:
			squad = make_unit(0, Vector3(-5, 0, 8), "Копейщики ИИ", "infantry", 36)
			ally = make_unit(0, Vector3(13, 0, 24), "Союзные лучники", "archer", 20)
			enemy = make_unit(1, Vector3(13, 0, -39), "Конница", "cavalry", 16)
		Drill.MANEUVER:
			squad = make_unit(0, Vector3(-15, 0, 26), "Копейщики ИИ", "infantry", 36)
			ally = make_unit(0, Vector3(7, 0, 6), "Союзное ополчение", "militia", 45)
			enemy = make_unit(1, Vector3(7, 0, -7), "Копейщики противника", "infantry", 42)
		_:
			squad = make_unit(0, Vector3(0, 0, 22), "Копейщики ИИ", "infantry", 36)
			enemy = make_unit(1, Vector3(0, 0, -23), "Ополчение", "militia", 32)

func make_ranged_armies() -> void:
	var title: String = CampaignData.UNITS[unit_kind][0] + " ИИ"
	var mounted := unit_kind == "khazar"
	var count := 16 if mounted else 24
	match drill:
		Drill.DEFENSE:
			squad = make_unit(0, Vector3(0, 0, 12), title, unit_kind, count)
			var raider := "light_cavalry" if mounted else "militia"
			var enemy_z := -39.0 if mounted else -10.0
			enemy = make_unit(1, Vector3(0, 0, enemy_z), CampaignData.UNITS[raider][0], raider, 14)
		Drill.SUPPORT:
			squad = make_unit(0, Vector3(-41, 0, 8), title, unit_kind, count)
			ally = make_unit(0, Vector3(7, 0, 16), "Союзные копейщики", "infantry", 24)
			enemy = make_unit(1, Vector3(7, 0, -11), "Вражеское ополчение", "militia", 32)
		Drill.MANEUVER:
			squad = make_unit(0, Vector3(-11, 0, 30), title, unit_kind, count)
			ally = make_unit(0, Vector3(3, 0, 7), "Союзные копейщики", "infantry", 30)
			enemy = make_unit(1, Vector3(3, 0, -11), "Вражеские лучники", "archer", 18)
		_:
			squad = make_unit(0, Vector3(0, 0, 30), title, unit_kind, count)
			enemy = make_unit(1, Vector3(0, 0, -52), "Вражеское ополчение", "militia", 24)

func make_melee_armies() -> void:
	var title: String = CampaignData.UNITS[unit_kind][0] + " ИИ"
	var mounted := unit_kind in MOUNTED_KINDS
	var count := 18 if mounted else 36
	match drill:
		Drill.DEFENSE:
			squad = make_unit(0, Vector3(0, 0, 14), title, unit_kind, count)
			enemy = make_unit(1, Vector3(0, 0, -34), "Вражеское ополчение", "militia", 24)
		Drill.SUPPORT:
			squad = make_unit(0, Vector3(-12, 0, 8), title, unit_kind, count)
			ally = make_unit(0, Vector3(7, 0, 16), "Союзные лучники", "archer", 20)
			enemy = make_unit(1, Vector3(7, 0, -7), "Вражеское ополчение", "militia", 32)
			if unit_kind == "princely":
				ally.morale = 72.0
		Drill.MANEUVER:
			var entry_x := -26.0 if mounted else -15.0
			squad = make_unit(0, Vector3(entry_x, 0, 26), title, unit_kind, count)
			ally = make_unit(0, Vector3(7, 0, 6), "Союзное ополчение", "militia", 45)
			enemy = make_unit(1, Vector3(7, 0, -7), "Вражеские копейщики", "infantry", 42)
		_:
			squad = make_unit(0, Vector3(0, 0, 22), title, unit_kind, count)
			enemy = make_unit(1, Vector3(0, 0, -23), "Вражеское ополчение", "militia", 24)

func make_tactical_commander() -> Node:
	if unit_kind in MOUNTED_KINDS:
		controller = MountedUnitAI.new()
	elif unit_kind in RANGED_KINDS:
		controller = RangedUnitAI.new()
	else:
		controller = InfantryUnitAI.new()
	controller.squad = squad
	if drill == Drill.DEFENSE:
		controller.guard_post = FIELD.project(squad.spawn_center)
	return controller

func set_battle_paused(pause: bool) -> void:
	super.set_battle_paused(pause)
	if pause or orders_issued:
		return
	orders_issued = true
	match drill:
		Drill.DEFENSE:
			enemy.command_attack(squad, true)
		Drill.SUPPORT:
			enemy.command_attack(ally, true)
			hold_group(ally, enemy)
		Drill.MANEUVER:
			if unit_kind in RANGED_KINDS:
				hold_group(ally, enemy)
			else:
				ally.command_attack(enemy, false)
			hold_group(enemy, ally)
		Drill.ATTACK:
			if unit_kind in MOUNTED_KINDS:
				enemy.command_attack(squad, false)
			else:
				hold_group(enemy, squad)

func hold_group(group: Node3D, target: Node3D) -> void:
	var direction := controller.ground_direction(group.center(), target.center())
	controller.position_group(group, group.spawn_center, direction, false, false, true)
	group.command_attack(target, false, true)

func make_interface() -> void:
	super.make_interface()
	for button in hud.command_buttons:
		button.hide()
	density_button.hide()
	hud.command_hint.hide()
	hud.objective_panel.hide()

func add_battle_size_control(_parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 320
	panel.add_theme_stylebox_override("panel", UI.campaign_frame(12))
	hud.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -338.0
	panel.offset_right = -18.0
	panel.offset_top = 18.0

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	UI.label(content, "Полигон ИИ", 22, UI.GOLD, true)
	var units := OptionButton.new()
	units.focus_mode = Control.FOCUS_NONE
	for kind in UNIT_KINDS:
		units.add_item(CampaignData.UNITS[kind][0])
	units.select(UNIT_KINDS.find(unit_kind))
	units.item_selected.connect(func(index: int): load_drill(drill, UNIT_KINDS[index]))
	content.add_child(units)
	var controls := HBoxContainer.new()
	content.add_child(controls)
	var scenarios := OptionButton.new()
	scenarios.focus_mode = Control.FOCUS_NONE
	scenarios.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in DRILLS:
		scenarios.add_item(item)
	scenarios.select(drill)
	scenarios.item_selected.connect(load_drill)
	controls.add_child(scenarios)
	var restart := Button.new()
	restart.text = "Заново"
	restart.tooltip_text = "Повторить сценарий · R"
	restart.focus_mode = Control.FOCUS_NONE
	restart.pressed.connect(restart_battle)
	controls.add_child(restart)
	var objective := UI.label(content, drill_objective(), 16)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	decision_label = UI.label(content, "", 16, UI.GOLD)
	decision_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func drill_objective() -> String:
	if unit_kind in MOUNTED_KINDS:
		return MOUNTED_OBJECTIVES[drill]
	if unit_kind in RANGED_KINDS:
		return RANGED_OBJECTIVES[drill]
	if unit_kind == "infantry":
		return SPEAR_OBJECTIVES[drill]
	return INFANTRY_OBJECTIVES[drill]

func _process(delta: float) -> void:
	super._process(delta)
	var caption := controller.decision
	if is_instance_valid(controller.decision_target):
		caption += "\nЦель — " + controller.decision_target.display_name
	decision_label.text = caption

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_R and not event.echo:
			restart_battle()
			return
		if key in [KEY_B, KEY_G, KEY_X, KEY_4, KEY_5, KEY_6, KEY_F9]:
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		return
	super._unhandled_input(event)

func attack_enemy(_target: Node3D, _running: bool) -> void:
	# Banners can issue attack orders directly, without going through _unhandled_input.
	pass

func restart_battle() -> void:
	load_drill(drill)

func load_drill(index: int, kind := unit_kind) -> void:
	get_tree().set_meta(SCENARIO_KEY, index)
	get_tree().set_meta(UNIT_KEY, kind)
	super.restart_battle()
