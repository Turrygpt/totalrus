extends "res://scripts/tactical_commander.gd"
## Controls one squad on the AI range using regular tactical orders.

const DECISION_INTERVAL := .35

var squad: Node3D
var guard_post := Vector3.INF
var decision := "Ожидают начала"
var decision_target: Node3D
var decision_point := Vector3.INF
var elapsed := 0.0

func _physics_process(delta: float) -> void:
	elapsed += delta
	clock -= delta
	if clock > 0.0:
		return
	clock = DECISION_INTERVAL
	if not squad.combat_ready():
		show_decision("Вышли из боя")
		return
	var allies := []
	var opponents := []
	for group in get_parent().squads:
		if group == squad or not group.combat_ready():
			continue
		if group.team == squad.team:
			allies.append(group)
		else:
			opponents.append(group)
	if opponents.is_empty():
		if is_instance_valid(squad.attack_target) and squad.attack_target.routed:
			squad.stop()
		show_decision("Удерживают строй")
		return
	plan_orders(allies, opponents)

func plan_orders(_allies: Array, _opponents: Array) -> void:
	pass

func show_decision(value: String, target: Node3D = null, point := Vector3.INF) -> void:
	decision = value
	decision_target = target
	decision_point = point
