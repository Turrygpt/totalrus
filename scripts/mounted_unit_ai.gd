extends "res://scripts/lab_unit_ai.gd"

const COVER_RANGE := 43.0
const GUARD_RANGE := 43.0
const REAR_DEPTH_FOR_CHARGE := 10.0

var approach: Dictionary = {}

func plan_orders(allies: Array, opponents: Array) -> void:
	var light: bool = squad.unit_kind == "light_cavalry"
	var target := preferred_target(opponents, light)
	var ally_under_attack := threatened_ally(allies, opponents)
	if not ally_under_attack.is_empty():
		var ally: Node3D = ally_under_attack.ally
		if squad.can_activate_inspiration() and ally.morale < 76.0:
			squad.activate_inspiration()
		approach.clear()
		charge(ally_under_attack.enemy, "Помощь · перехват атакующих союзника")
		return

	if guard_post.is_finite():
		var gap: float = target.center().distance_to(guard_post)
		var intercept_range := 32.0 if light else 25.0
		if gap < intercept_range or (squad.attack_target == target and gap <= GUARD_RANGE):
			charge(target, "Оборона · встречный натиск")
		else:
			position_group(squad, guard_post, ground_direction(guard_post, target.center()), true, false, true)
			show_decision("Оборона · держат позицию", target, guard_post)
		return

	if approach.get("target") in opponents:
		target = approach.target
	elif squad.attack_target in opponents:
		target = squad.attack_target

	var line := allies.filter(func(group): return not group.is_mounted() and not group.is_ranged())
	var support := supporting_infantry(target, line)
	var spear_line: bool = target.spear_count() * 2 >= target.alive_count() and target.defending_order
	if support or spear_line or approach.get("target") == target:
		if attack_flank(target, support, opponents, light):
			return
	charge(target, "Атака · конный натиск")

func preferred_target(opponents: Array, light: bool) -> Node3D:
	if light:
		var exposed := opponents.filter(func(group): return group.is_ranged() and not group.is_mounted())
		if not exposed.is_empty():
			return choose_target(squad, exposed, {})
	return choose_target(squad, opponents, {})

func threatened_ally(allies: Array, opponents: Array) -> Dictionary:
	var selected := {}
	var near := COVER_RANGE
	for ally in allies:
		if not ally.is_ranged() and ally.morale >= 55.0:
			continue
		for enemy in opponents:
			if enemy.attack_target != ally:
				continue
			var gap: float = ally.center().distance_to(enemy.center())
			if gap < near and squad.center().distance_to(ally.center()) < COVER_RANGE + 10.0:
				near = gap
				selected = {"ally": ally, "enemy": enemy}
	return selected

func attack_flank(target: Node3D, support: Node3D, opponents: Array, light: bool) -> bool:
	var origin: Vector3 = squad.center()
	var point: Vector3 = target.center()
	if approach.get("target") != target:
		var advance := ground_direction(support.center(), point) if support else Vector3.BACK.rotated(Vector3.UP, target.order_heading)
		if advance.is_zero_approx():
			advance = ground_direction(origin, point)
		if advance.is_zero_approx():
			return false
		var side := signf((origin - point).dot(advance.cross(Vector3.UP)))
		approach = {"target": target, "advance": advance, "side": side if side != 0.0 else 1.0, "deadline": elapsed + 24.0}
	if approach.get("committed", false):
		if approach.get("fallback", false):
			return false
		charge(target, "Манёвр · удар во фланг" if light else "Манёвр · удар с тыла")
		return true

	var forward: Vector3 = approach.advance
	var from_side := ground_direction(point, origin).dot(forward)
	var depth: float = (origin - point).dot(forward)
	var past_front := from_side > -.25 if light else from_side > .24 and depth >= REAR_DEPTH_FOR_CHARGE
	if past_front and maneuver_path_clear(origin, point, opponents, target):
		approach.committed = true
		charge(target, "Манёвр · удар во фланг" if light else "Манёвр · удар с тыла")
		return true

	if elapsed < approach.deadline:
		var waypoint := maneuver_bypass(origin, point, target, opponents, approach, 5.0 if light else 18.0)
		if waypoint.is_finite():
			position_group(squad, waypoint, ground_direction(origin, waypoint), true)
			show_decision("Манёвр · обход фланга" if light else "Манёвр · заход в тыл", target, waypoint)
			return true
	# Keep the chosen target when its formation closes the intended route.
	approach.committed = true
	approach.fallback = true
	return false

func charge(target: Node3D, caption: String) -> void:
	attack(squad, target, squad.stamina >= 30.0)
	show_decision(caption, target)
