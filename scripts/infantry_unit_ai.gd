extends "res://scripts/lab_unit_ai.gd"
## Field orders for spear, militia and Varangian infantry.

const HOLD_CONTACT := 12.0
const CAVALRY_WARNING := 50.0
const SUPPORT_RANGE := 40.0
const SUPPORT_WARNING := 72.0

var flank: Dictionary = {}

func plan_orders(allies: Array, opponents: Array) -> void:
	var target := choose_target(squad, opponents, {})
	var riders := nearest_charge(opponents, squad, CAVALRY_WARNING) if squad.unit_kind == "infantry" else null
	if squad.can_activate_berserk() and squad.morale < 60.0 and squad.center().distance_to(target.center()) < HOLD_CONTACT:
		squad.activate_berserk()
	if guard_post.is_finite() or riders:
		flank.clear()
		var post: Vector3 = guard_post if guard_post.is_finite() else squad.center()
		hold_line(post, riders if riders else target, "Оборона")
	elif (cover_ally(allies, opponents) if squad.unit_kind == "infantry" else relieve_ally(allies, opponents)):
		flank.clear()
	elif not advance_on_flank(allies, opponents):
		assault(target)

func nearest_charge(opponents: Array, threatened: Node3D, limit: float) -> Node3D:
	var nearest: Node3D
	for enemy in opponents:
		if enemy.attack_target != threatened or not enemy.is_melee_cavalry() or not enemy.running_attack:
			continue
		var distance: float = threatened.center().distance_to(enemy.center())
		if distance < limit:
			limit = distance
			nearest = enemy
	return nearest

func hold_line(post: Vector3, target: Node3D, order_name: String) -> void:
	var gap: float = squad.center().distance_to(target.center())
	var facing := ground_direction(post, target.center())
	if facing.is_zero_approx():
		facing = Vector3.FORWARD.rotated(Vector3.UP, squad.order_heading)
	var holding: bool = squad.attack_target == target and squad.defending_order
	if gap <= HOLD_CONTACT and (holding or squad.center().distance_squared_to(post) <= 16.0):
		attack(squad, target, false, true)
		show_decision(order_name + " · встречают в строю", target)
	else:
		position_group(squad, post, facing, squad.center().distance_squared_to(post) > 36.0, false, true)
		show_decision(order_name + " · занимают позицию", target, post)

func cover_ally(allies: Array, opponents: Array) -> bool:
	for ally in allies:
		if not ally.is_ranged() or squad.center().distance_to(ally.center()) > SUPPORT_RANGE:
			continue
		# Counterattack once the enemy reaches the archers' own line.
		for enemy in opponents:
			if enemy.attack_target == ally and enemy.center().distance_to(ally.center()) < 10.0:
				attack(squad, enemy, squad.stamina >= 45.0)
				show_decision("Помощь лучникам · контратака", enemy)
				return true
		var riders := nearest_charge(opponents, ally, SUPPORT_WARNING)
		if riders:
			var centre: Vector3 = ally.center()
			var facing := ground_direction(centre, riders.center())
			var post := FIELD.clamp_ground(centre + facing * 12.0, squad.field_half_size, 12.0)
			hold_line(post, riders, "Помощь лучникам")
			return true
	return false

func relieve_ally(allies: Array, opponents: Array) -> bool:
	for ally in allies:
		for enemy in opponents:
			if enemy.attack_target != ally or enemy.center().distance_to(ally.center()) > 24.0:
				continue
			if squad.center().distance_to(enemy.center()) > SUPPORT_RANGE:
				continue
			# Leave room for a flanker when the allied line already has a melee target.
			if not ally.is_ranged() and ally.attack_target == enemy and ally.morale >= 55.0:
				continue
			attack(squad, enemy, squad.stamina >= 45.0)
			show_decision("Помощь · перехват атакующих союзника", enemy)
			return true
	return false

func advance_on_flank(allies: Array, opponents: Array) -> bool:
	if not flank.is_empty():
		if flank.target in opponents and flank.get("committed", false):
			attack(squad, flank.target, squad.stamina >= 45.0)
			show_decision("Манёвр · удар с фланга", flank.target)
			return true
		if flank.target in opponents and flank.ally in allies and elapsed < flank.deadline:
			# The engaged ally overlaps the target's perimeter on the final approach.
			var blockers := opponents + allies.filter(func(group): return group != flank.ally)
			var origin: Vector3 = squad.center()
			var point: Vector3 = flank.target.center()
			var off_front := ground_direction(point, origin).dot(flank.advance) > -.25
			if off_front and maneuver_path_clear(origin, point, blockers, flank.target):
				flank.committed = true
				attack(squad, flank.target, squad.stamina >= 45.0)
				show_decision("Манёвр · удар с фланга", flank.target)
				return true
			var waypoint := maneuver_bypass(origin, point, flank.target, blockers, flank, 4.0)
			if waypoint.is_finite():
				position_group(squad, waypoint, ground_direction(origin, waypoint), true)
				show_decision("Манёвр · обход строя", flank.target, waypoint)
				return true
		# Finish the engagement directly if the route closes or the ally breaks.
		var previous_target: Node3D = flank.target
		flank.clear()
		if previous_target in opponents:
			assault(previous_target)
			return true

	if is_instance_valid(squad.attack_target) or squad.morale < 60.0 or squad.stamina < 45.0:
		return false
	for ally in allies:
		var target: Node3D = ally.attack_target
		if ally.is_ranged() or not target in opponents or ally.center().distance_to(target.center()) > 18.0:
			continue
		var point: Vector3 = target.center()
		var distance: float = squad.center().distance_to(point)
		if distance < 18.0 or distance > 55.0:
			continue
		var advance := ground_direction(ally.center(), point)
		if advance.is_zero_approx():
			continue
		var side := signf((squad.center() - point).dot(advance.cross(Vector3.UP)))
		flank = {"ally": ally, "target": target, "advance": advance, "side": side if side != 0.0 else 1.0, "deadline": elapsed + 24.0}
		# Let the next decision continue this plan without issuing a frontal order.
		show_decision("Манёвр · выбор фланга", target)
		return true
	return false

func assault(target: Node3D) -> void:
	var gap: float = squad.center().distance_to(target.center())
	var runup := 27.0
	if squad.unit_kind == "militia":
		runup = 13.0
	elif squad.unit_kind == "varangian":
		runup = 22.0
	var running: bool = gap <= runup and squad.stamina >= (30.0 if squad.running_attack else 45.0)
	attack(squad, target, running)
	show_decision("Атака · натиск" if running else "Атака · сближение под щитами", target)

