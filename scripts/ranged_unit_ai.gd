extends "res://scripts/lab_unit_ai.gd"

const FIRING_DISTANCE := 56.0
const SUPPORT_DISTANCE := 66.0
const CLEAR_SHOT_MARGIN := 5.0

var destination := Vector3.INF
var move_target: Node3D
var move_deadline := 0.0
var moving_to_flank := false
var flank_target: Node3D
var fire_until := 0.0

func plan_orders(allies: Array, opponents: Array) -> void:
	var target := choose_target(squad, opponents, {})
	if squad.ranged_retreat_goal.is_finite():
		show_decision("Оборона · разрывают дистанцию", target, squad.ranged_retreat_goal)
		return
	if not squad.uses_bows():
		if guard_post.is_finite() and squad.center().distance_to(target.center()) > 12.0:
			position_group(squad, squad.center(), ground_direction(squad.center(), target.center()), false, false, true)
			show_decision("Оборона · держат строй", target)
		else:
			attack(squad, target, squad.is_mounted())
			show_decision("Атака · ближний бой", target)
		return

	var threat := close_threat(opponents)
	var emergency_distance := 9.0 if squad.is_mounted() else 7.0
	if threat and (elapsed >= fire_until or squad.center().distance_to(threat.center()) <= emergency_distance) and (not destination.is_finite() or moving_to_flank):
		move_to(fallback_point(threat, allies, opponents), threat, false)
	if destination.is_finite():
		if move_target in opponents and elapsed < move_deadline and squad.center().distance_squared_to(destination) > 16.0:
			var caption := "Манёвр · выход на фланг" if moving_to_flank else "Оборона · отход с линии атаки"
			show_decision(caption, move_target, destination)
			return
		if moving_to_flank and move_target in opponents:
			flank_target = move_target
		elif not moving_to_flank:
			fire_until = elapsed + (6.5 if squad.is_mounted() else 5.0)
		destination = Vector3.INF

	if flank_target in opponents and squad.center().distance_to(flank_target.center()) <= FIRING_DISTANCE and shot_clear(squad.center(), flank_target, allies):
		fire_at(flank_target, "Манёвр · обстрел с фланга")
		return
	flank_target = null
	var blocked_target: Node3D
	for ally in allies:
		var attacker := threat_to(ally, opponents)
		if attacker == null:
			continue
		if shot_clear(squad.center(), attacker, allies):
			fire_at(attacker, "Помощь · огонь по атакующим союзника")
			return
		var firing_post := flank_post(ally, attacker, allies)
		if firing_post.is_finite():
			move_to(firing_post, attacker, true)
			show_decision("Манёвр · выход на фланг", attacker, firing_post)
			return
		blocked_target = attacker
	if blocked_target:
		if squad.members.any(func(soldier): return soldier.auto_fire):
			squad.stop()
		show_decision("Манёвр · ищут свободную линию огня", blocked_target)
		return

	var in_range: bool = squad.center().distance_to(target.center()) <= FIRING_DISTANCE
	if guard_post.is_finite():
		fire_at(target, "Оборона · огонь с позиции", true)
	elif in_range:
		fire_at(target, "Атака · обстрел")
	else:
		attack(squad, target, squad.is_mounted())
		show_decision("Атака · выход на дистанцию залпа", target)

func close_threat(opponents: Array) -> Node3D:
	var threat: Node3D
	var limit := 55.0 if squad.is_mounted() else 25.0
	for enemy in opponents:
		if enemy.uses_bows() or enemy.attack_target != squad:
			continue
		var gap: float = squad.center().distance_to(enemy.center())
		if gap < limit:
			limit = gap
			threat = enemy
	return threat

func threat_to(ally: Node3D, opponents: Array) -> Node3D:
	var threat: Node3D
	var limit := SUPPORT_DISTANCE
	for enemy in opponents:
		if enemy.attack_target != ally:
			continue
		var gap: float = squad.center().distance_to(enemy.center())
		if gap < limit:
			limit = gap
			threat = enemy
	return threat

func shot_clear(origin: Vector3, target: Node3D, allies: Array) -> bool:
	var end: Vector3 = target.center()
	origin.y = 0.0
	end.y = 0.0
	for ally in allies:
		var centre: Vector3 = ally.center()
		centre.y = 0.0
		var nearest := Geometry3D.get_closest_point_to_segment(centre, origin, end)
		if centre.distance_squared_to(nearest) < pow(ally.formation_width * .5 + CLEAR_SHOT_MARGIN, 2):
			return false
	return true

func flank_post(ally: Node3D, target: Node3D, allies: Array) -> Vector3:
	var end: Vector3 = target.center()
	var forward := ground_direction(ally.center(), end)
	if forward.is_zero_approx():
		return Vector3.INF
	var lateral := forward.cross(Vector3.UP)
	var origin: Vector3 = squad.center()
	var best := Vector3.INF
	var travel := INF
	for side in [-1.0, 1.0]:
		var point := FIELD.clamp_ground(ally.center() + forward * 4.0 + lateral * side * 38.0, squad.field_half_size, 14.0)
		if point.distance_to(end) > FIRING_DISTANCE or not shot_clear(point, target, allies):
			continue
		var gap := origin.distance_squared_to(point)
		if gap < travel:
			travel = gap
			best = point
	return best

func fallback_point(threat: Node3D, allies: Array, opponents: Array) -> Vector3:
	var origin: Vector3 = squad.center()
	var away := ground_direction(threat.center(), origin)
	var distance := 35.0 if squad.is_mounted() else 24.0
	var best := origin
	var best_clearance := -INF
	for angle in [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0]:
		var candidate := FIELD.clamp_ground(origin + away.rotated(Vector3.UP, angle) * distance, squad.field_half_size, 14.0)
		if not maneuver_path_clear(origin, candidate, allies):
			continue
		var clearance := INF
		for enemy in opponents:
			clearance = minf(clearance, candidate.distance_to(enemy.center()))
		# An oblique exit lets mounted archers turn to fire sooner.
		if squad.is_mounted():
			clearance += 12.0 * absf(sin(angle))
		if clearance > best_clearance:
			best_clearance = clearance
			best = candidate
	return best

func move_to(point: Vector3, target: Node3D, flank_move: bool) -> void:
	if squad.center().distance_squared_to(point) <= 16.0:
		return
	destination = point
	move_target = target
	moving_to_flank = flank_move
	move_deadline = elapsed + 14.0
	position_group(squad, point, ground_direction(point, target.center()), true)

func fire_at(target: Node3D, caption: String, hold := false) -> void:
	hold = hold or squad.center().distance_to(target.center()) <= FIRING_DISTANCE
	attack(squad, target, false, hold)
	show_decision(caption, target)
