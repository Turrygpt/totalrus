extends Node3D

const HORSEMAN = preload("res://scenes/horseman.tscn")
const Rider = preload("res://scripts/horseman.gd")
const Spacing = preload("res://scripts/cavalry_spacing.gd")
const Pennon = preload("res://scripts/cavalry_pennon.gd")
const COLUMNS := 6
const ROWS := 5
const ROW_SPACING := 4.08
const CHARGE = preload("res://scripts/cavalry_charge.gd")
const SPEEDS := [1.8, 6.7]
const GAITS: Array[StringName] = [&"Idle", &"Walk", &"Gallop"]
const ORDER_NAMES := ["Шаг", "Галоп"]
const START := Vector3(0, 0, -21)
const READY_LEAD := 2.55
const CHARGE_SPEED := 9.2
const CHARGE_ACCELERATION := 2.9
const SPEAR_REACH := 2.05
const RUNOUT := 1.7
const RETURN_WINDOW := 5.0
# Leave room to push the rear ranks past the line as the vanguard turns back.
const EXIT_CLEARANCE := (ROWS - 1) * .5 * ROW_SPACING + CHARGE_SPEED * CHARGE_SPEED / 9.0 + 2.0

@onready var camera: Camera3D = $Camera
@onready var marker: MeshInstance3D = $Destination
@onready var status: Label = $Canvas/Panel/Margin/Content/Status
@onready var enemies = $EnemyLine
@onready var enemy_caption: Label3D = $EnemyLine/Caption

var riders: Array[Rider] = []
var slots := PackedVector3Array()
var speeds := PackedFloat32Array()
var hit_wait := PackedFloat32Array()
var charge_contacts := PackedInt64Array()
var returning := PackedByteArray()
var melee_targets: Array[Node3D] = []
var melee_angles := PackedFloat32Array()
var melee_reach := PackedFloat32Array()
var retry_slot := PackedFloat32Array()
var blocked_time := PackedFloat32Array()
var strike_delay := PackedFloat32Array()
var spacing: Spacing
var battle_time := 0.0
var pennons: Dictionary[int, MeshInstance3D] = {}
var center := START
var goal := START
var anchor_yaw := 0.0
var order := 0
var ordered := false
var attacking := false
var ready_time := -1.0
var approach_direction := Vector3.BACK
var maneuver := 0
var march := PackedVector3Array()
var settle_time := 0.0
var rallying := false
var charge_goal := Vector3.ZERO
var charge_front := INF
var charge_rear := INF
var charge_width := Vector2.ZERO
var charge_speed := 0.0
var charge_complete := false
var return_started := false
var turn_started_at := 0.0
var line_alerted := false
var battle_state := "Стоят"
var looking := false
var interpolation_before := false
var last_click := -10000
var last_point := Vector3.ZERO

func _enter_tree() -> void:
	interpolation_before = get_tree().physics_interpolation
	get_tree().physics_interpolation = true

func _ready() -> void:
	get_window().title = "Русь — Конный бой"
	get_viewport().use_taa = false
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for row in ROWS:
		for column in COLUMNS:
			var rider: Rider = HORSEMAN.instantiate()
			var index := row * COLUMNS + column
			var slot := Vector3((column - (COLUMNS - 1) * .5) * 2.45, 0,
					((ROWS - 1) * .5 - row) * ROW_SPACING)
			slot.x += sin(index * 2.17) * .46 + sin(row * 2.4) * .55
			slot.z += cos(index * 1.73) * .76 - .018 * slot.x * slot.x
			rider.position = START + slot
			$Units.add_child(rider)
			rider.reset_physics_interpolation()
			riders.append(rider)
			slots.append(slot)
			speeds.append(0.0)
			hit_wait.append(0.0)
			charge_contacts.append(0)
			returning.append(0)
			melee_targets.append(null)
			melee_angles.append(0.0)
			melee_reach.append(Spacing.ATTACK_DISTANCE)
			retry_slot.append(0.0)
			blocked_time.append(0.0)
			strike_delay.append(-1.0)
			rider.tint_coat(row * COLUMNS + column * 3)
			if index in [0, 5, 8, 12, 19, 23, 27]:
				var flag := Pennon.attach(rider, index)
				if flag:
					pennons[index] = flag
			rider.player.seek(rider.player.get_animation(&"Idle").length * _phase(riders.size() - 1))
	camera.look_at(Vector3(0, 0, -2))
	spacing = Spacing.new(riders)
	reset_physics_interpolation()
	_refresh_status()

func _exit_tree() -> void:
	if looking:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().physics_interpolation = interpolation_before

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and looking:
		camera.rotation.y -= event.relative.x * .0035
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * .0035, -1.48, .35)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			looking = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
			return
		if not event.pressed:
			return
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				var cursor: Vector2 = get_viewport().get_visible_rect().size * .5 if looking else event.position
				var ray := camera.project_ray_normal(cursor)
				var ground: Variant = Plane(Vector3.UP, 0.0).intersects_ray(
						camera.project_ray_origin(cursor), ray)
				if ground != null:
					var point: Vector3 = ground
					point = point.clamp(Vector3(-36, 0, -46), Vector3(36, 0, 46))
					var now := Time.get_ticks_msec()
					var fast: bool = event.double_click or (now - last_click < 350 and point.distance_to(last_point) < 2.3)
					var attack: bool = enemies.clicked(camera, cursor, point)
					var route := 0
					if attack:
						if event.ctrl_pressed:
							route = 2
						elif event.shift_pressed:
							route = _flank_side(point)
					_order_move(point, 1 if fast else 0, attack, route)
					last_click = now
					last_point = point
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(2.8)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(-2.8)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_X: _stop()
			KEY_R: get_tree().reload_current_scene()
			KEY_ESCAPE:
				looking = false
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _order_move(point: Vector3, pace: int, attack := false, route := 0) -> void:
	if not riders.any(func(rider): return not rider.fallen):
		return
	attack = attack and enemies.alive_count > 0
	var continuing := attack and attacking and (route == 0 or route == maneuver)
	if attacking and not continuing:
		_recenter()
	attacking = attack
	order = pace
	ordered = true
	if not continuing:
		maneuver = route
		march.clear()
		rallying = false
		if attacking:
			if maneuver == 0:
				_begin_charge()
			else:
				_begin_maneuver(point)
		else:
			_lower_weapons()
			goal = point
			battle_state = ORDER_NAMES[order]
	marker.position = (enemies.living_center() if attacking and march.is_empty() else goal) + Vector3.UP * .045
	marker.show()
	_refresh_status()

func _clear_charge() -> void:
	_lower_weapons()
	hit_wait.fill(0.0)
	charge_contacts.fill(0)
	returning.fill(0)
	melee_targets.fill(null)
	retry_slot.fill(0.0)
	blocked_time.fill(0.0)
	strike_delay.fill(-1.0)
	charge_complete = false
	return_started = false
	turn_started_at = 0.0
	charge_speed = 0.0
	rallying = false
	line_alerted = false

func _flank_side(point: Vector3) -> int:
	var lateral: Vector3 = enemies.defense_direction().cross(Vector3.UP)
	var origin: Vector3 = enemies.living_center()
	var side := (point - origin).dot(lateral)
	if absf(side) < 1.4:
		side = (center - origin).dot(lateral)
	return -1 if side < 0.0 else 1

func _begin_maneuver(point: Vector3) -> void:
	_clear_charge()
	settle_time = 0.0
	var origin: Vector3 = enemies.living_center()
	var forward: Vector3 = enemies.defense_direction()
	var lateral := forward.cross(Vector3.UP) * (_flank_side(point) if maneuver == 2 else maneuver)
	var span: Vector2 = enemies.charge_span(forward)
	var edge: Vector2 = enemies.charge_span(lateral)
	var front := span.x - origin.dot(forward) - 13.0
	var rear := span.y - origin.dot(forward) + 13.0
	var wing := edge.y - origin.dot(lateral) + 13.0
	var relative := center - origin
	var depth := relative.dot(forward)
	var already_wide := relative.dot(lateral) >= wing - .3
	if not already_wide:
		var near_edge := front if depth < 0.0 else rear
		if depth > front and depth < rear:
			_append_corner(center + forward * (near_edge - depth))
		_append_corner(origin + lateral * wing + forward * near_edge)
	if maneuver == 2:
		if depth < rear or not already_wide:
			_append_corner(origin + lateral * wing + forward * rear)
		_append_corner(origin + forward * (span.y - origin.dot(forward) + 31.5))
	else:
		_append_corner(origin + lateral * (edge.y - origin.dot(lateral) + 31.5))
	if march.is_empty():
		_begin_charge()
		return
	goal = march[0]
	_align_formation(goal - center)
	battle_state = "Обход в тыл" if maneuver == 2 else "Обход с фланга"

func _append_corner(point: Vector3) -> void:
	var before := center if march.is_empty() else march[march.size() - 1]
	if point.distance_squared_to(before) > .25:
		march.append(point)

func _next_corner() -> void:
	march.remove_at(0)
	if march.is_empty():
		_begin_charge()
		marker.position = enemies.living_center() + Vector3.UP * .045
	else:
		goal = march[0]
		_align_formation(goal - center)
		marker.position = goal + Vector3.UP * .045
	settle_time = 0.0

func _begin_charge() -> void:
	_clear_charge()
	approach_direction = center.direction_to(enemies.living_center())
	if approach_direction.is_zero_approx():
		approach_direction = Vector3(sin(anchor_yaw), 0.0, cos(anchor_yaw))
	_align_formation(approach_direction)
	var span: Vector2 = enemies.charge_span(approach_direction)
	charge_front = span.x
	charge_rear = span.y
	charge_width = enemies.charge_span(approach_direction.cross(Vector3.UP))
	charge_goal = center + approach_direction * (span.y + EXIT_CLEARANCE - center.dot(approach_direction))
	var living := riders.filter(func(rider): return not rider.fallen)
	var turned := living.filter(func(rider): return rider.basis.z.dot(approach_direction) > .86)
	rallying = turned.size() < ceili(living.size() * .77)
	settle_time = 0.0
	goal = center if rallying else charge_goal
	battle_state = "Разворот перед натиском" if rallying else "Сближение"

func _align_formation(direction: Vector3) -> void:
	if direction.is_zero_approx():
		return
	var yaw := atan2(direction.x, direction.z)
	if absf(angle_difference(anchor_yaw, yaw)) < .44:
		return
	# Reassign places on sharp turns so riders need not cross the whole formation.
	anchor_yaw = yaw
	var living: Array[int] = []
	for i in riders.size():
		if not riders[i].fallen:
			living.append(i)
	var remaining: Array[int] = []
	remaining.assign(living)
	var homes := slots.duplicate()
	var claimed := PackedByteArray()
	claimed.resize(riders.size())
	while not remaining.is_empty():
		var best := INF
		var rider_index := -1
		var slot_index := -1
		for i in living:
			if claimed[i]:
				continue
			for candidate in remaining:
				var point := center + homes[candidate].rotated(Vector3.UP, yaw)
				var distance := riders[i].position.distance_squared_to(point)
				if distance < best:
					best = distance
					rider_index = i
					slot_index = candidate
		slots[rider_index] = homes[slot_index]
		claimed[rider_index] = 1
		remaining.erase(slot_index)

func _lower_weapons() -> void:
	ready_time = -1.0
	enemies.relax_brace()
	for rider in riders:
		rider.cancel_melee_strike()
		rider.set_weapon_ready(false)

func _recenter() -> void:
	var total := Vector3.ZERO
	var count := 0
	for rider in riders:
		if not rider.fallen:
			total += rider.position
			count += 1
	if count > 0:
		center = total / count

func _charge_limit(delta: float) -> float:
	var approach: float = SPEEDS[order]
	if ready_time < 0:
		var lead := -INF
		for rider in riders:
			if not rider.fallen:
				lead = maxf(lead, rider.position.dot(approach_direction))
		var lift_speed := maxf(charge_speed, approach)
		var ramp := minf(READY_LEAD, (CHARGE_SPEED - lift_speed) / CHARGE_ACCELERATION)
		var run_up := lift_speed * ramp + .5 * CHARGE_ACCELERATION * ramp * ramp
		run_up += CHARGE_SPEED * (READY_LEAD - ramp)
		if charge_front - lead - SPEAR_REACH <= run_up:
			ready_time = 0.0
			battle_state = "Разгон · копья и щиты на изготовку"
			for rider in riders:
				rider.set_weapon_ready(true)
	if ready_time >= 0:
		ready_time += delta
		if not line_alerted:
			_alert_spearmen()
	charge_speed = move_toward(charge_speed, CHARGE_SPEED if ready_time >= 0 else approach,
			CHARGE_ACCELERATION * delta)
	return charge_speed

func _alert_spearmen() -> void:
	var defense: Vector3 = enemies.defense_direction()
	if defense.dot(approach_direction) > .83:
		line_alerted = true
	else:
		var transverse := approach_direction.cross(Vector3.UP)
		for i in riders.size():
			var rider := riders[i]
			if rider.fallen or speeds[i] < 3.0 or rider.basis.z.dot(approach_direction) < .76:
				continue
			var lane := rider.position.dot(transverse)
			if lane < charge_width.x - 1.28 or lane > charge_width.y + 1.28:
				continue
			var distance := charge_front - rider.position.dot(approach_direction) - SPEAR_REACH
			if distance <= minf(20.0, speeds[i] * 2.20):
				line_alerted = true
				break
	if line_alerted:
		enemies.brace(approach_direction)

func _stop(state := "Стоят") -> void:
	if attacking:
		_recenter()
	ordered = false
	attacking = false
	maneuver = 0
	rallying = false
	march.clear()
	_lower_weapons()
	marker.hide()
	battle_state = state
	for i in riders.size():
		speeds[i] = 0.0
		_set_gait(riders[i], 0, 0.0, i)
	_refresh_status()

func _physics_process(delta: float) -> void:
	battle_time += delta
	for rider in riders:
		rider.tick_combat(delta)
	enemies.defend(riders, speeds, delta, attacking and charge_complete)
	if not ordered:
		return
	if not riders.any(func(rider): return not rider.fallen):
		_stop("Отряд разбит")
		return
	if attacking and enemies.alive_count == 0 and charge_complete:
		_stop("Копейщики разбиты")
		return
	var maneuvering := not march.is_empty()
	var limit: float = SPEEDS[order]
	if maneuvering:
		limit = 5.85
	elif rallying:
		limit = 2.7
	elif attacking and not charge_complete:
		limit = _charge_limit(delta)
	var ahead := goal - center
	var remaining := ahead.length()
	if remaining > .04:
		var heading := atan2(ahead.x, ahead.z)
		anchor_yaw = rotate_toward(anchor_yaw, heading, 1.9 * delta)
		var alignment := maxf(.10, cos(angle_difference(anchor_yaw, heading)))
		center = center.move_toward(goal, minf(limit, sqrt(9.0 * remaining)) * alignment * delta)
	else:
		center = goal

	var all_arrived := center.is_equal_approx(goal)
	var near_slots := 0
	var ready_ranks := 0
	var passing := attacking and ready_time >= .27 and not charge_complete
	var all_clear := passing
	var runout_ready := passing and center.dot(approach_direction) >= charge_rear + EXIT_CLEARANCE - 1.0
	var charge_spent := return_started and battle_time - turn_started_at >= RETURN_WINDOW
	var slot_index := 0
	var reserved: Array[Transform3D] = []
	if attacking and return_started:
		for i in riders.size():
			var target = melee_targets[i]
			if not riders[i].fallen and target and target.alive:
				reserved.append(_melee_slot(target, i))
	for i in riders.size():
		var rider := riders[i]
		if rider.fallen:
			continue
		var destination := center + slots[i].rotated(Vector3.UP, anchor_yaw)
		slot_index += 1
		var distance_to_exit := charge_rear + RUNOUT - rider.position.dot(approach_direction)
		if runout_ready and distance_to_exit > 0.0:
			destination = rider.position + approach_direction * (distance_to_exit + .95)
		if rider.position.distance_squared_to(destination) < 5.5:
			near_slots += 1
			if rallying and rider.basis.z.dot(approach_direction) > .85:
				ready_ranks += 1
		if passing and (distance_to_exit <= 0.0 or charge_spent) and returning[i] == 0:
			returning[i] = 1
			if not return_started:
				battle_state = "Разворот · атака"
				return_started = true
				turn_started_at = battle_time
				marker.hide()
		if attacking and returning[i] == 1 and enemies.alive_count > 0:
			_fight(i, reserved, delta)
			continue
		if rider.action_left > 0.0:
			speeds[i] = 0.0
			all_arrived = false
			if returning[i] == 0:
				all_clear = false
			continue
		var previous := rider.position
		var step := destination
		var facing := anchor_yaw
		if attacking and blocked_time[i] > .30:
			var obstacles: Array = enemies.soldiers if maneuvering else []
			step = spacing.waypoint(i, destination, obstacles, battle_time, true)
			var travel := previous.direction_to(step)
			if not travel.is_zero_approx():
				facing = atan2(travel.x, travel.z)
		if not _advance_rider(rider, step, facing, limit, delta, i, maneuvering or rallying):
			all_arrived = false
		if attacking:
			var advance := previous.distance_to(rider.position) / delta
			if advance < .36 and previous.distance_squared_to(destination) > .10:
				blocked_time[i] += delta
			elif advance > 1.0:
				blocked_time[i] = maxf(0.0, blocked_time[i] - 1.6 * delta)
		if attacking and ready_time >= .27:
			_resolve_strike(i, previous, delta)
		if returning[i] == 0:
			all_clear = false
	if maneuvering and center.is_equal_approx(goal):
		settle_time += delta
		if all_arrived or near_slots >= ceili(slot_index * .83) or settle_time > 4.25:
			_next_corner()
	elif rallying:
		settle_time += delta
		if ready_ranks >= ceili(slot_index * .77) or settle_time >= 7.5:
			rallying = false
			goal = charge_goal
			battle_state = "Сближение"
	elif all_clear:
		charge_complete = true
		_recenter()
		goal = center
		enemies.relax_brace()
		marker.hide()
		if enemies.alive_count == 0:
			_stop("Копейщики разбиты")
	elif all_arrived and not attacking:
		_stop()
	_refresh_status()

func _melee_slot(target: Node3D, index: int) -> Transform3D:
	var angle := melee_angles[index]
	return Transform3D(Basis(Vector3.UP, angle + PI),
			target.global_position + Spacing.heading(angle) * melee_reach[index])

func _fight(index: int, reserved: Array[Transform3D], delta: float) -> void:
	var rider := riders[index]
	var target = melee_targets[index]
	hit_wait[index] = maxf(0.0, hit_wait[index] - delta)
	if strike_delay[index] >= 0.0:
		strike_delay[index] -= delta
		if strike_delay[index] <= 0.0:
			strike_delay[index] = -1.0
			if target and target.alive and rider.player.current_animation == &"MeleeStrike":
				var reach: Vector3 = target.global_position - rider.position
				if reach.length_squared() < 6.7 and rider.basis.z.dot(reach.normalized()) > .6:
					enemies.hit(target, 26.0, rider.basis.z * .90)
		return
	if rider.action_left > 0.0:
		speeds[index] = 0.0
		return
	if not target or not target.alive:
		if battle_time < retry_slot[index]:
			_set_gait(rider, 0, 0.0, index)
			return
		var assignment := spacing.free_slot(index, enemies.soldiers, reserved)
		target = assignment.get("target")
		melee_targets[index] = target
		if not target:
			retry_slot[index] = battle_time + .47 + float(index % 6) * .037
			_set_gait(rider, 0, 0.0, index)
			return
		melee_angles[index] = assignment.angle
		melee_reach[index] = assignment.reach
		blocked_time[index] = 0.0
		reserved.append(_melee_slot(target, index))
	var offset: Vector3 = target.global_position - rider.position
	var distance := offset.length()
	var direction := offset.normalized()
	var heading := atan2(direction.x, direction.z)
	var slot := _melee_slot(target, index)
	if distance <= minf(melee_reach[index] + .25, 2.55) and rider.position.distance_squared_to(slot.origin) < .27:
		var yaw := rotate_toward(rider.rotation.y, heading, 3.0 * delta)
		if spacing.clear_pose(index, rider.position, yaw, enemies.soldiers):
			rider.rotation.y = yaw
		speeds[index] = 0.0
		_set_gait(rider, 0, 0.0, index)
		if hit_wait[index] <= 0 and rider.basis.z.dot(direction) > .75 and rider.start_melee_strike():
			strike_delay[index] = .35
			hit_wait[index] = .99 + float(index % 5) * .09
			blocked_time[index] = 0.0
			battle_state = "Ближний бой"
		elif rider.basis.z.dot(direction) <= .75:
			blocked_time[index] += delta
	else:
		var before := rider.position
		var waypoint := spacing.waypoint(index, slot.origin, enemies.soldiers, battle_time, blocked_time[index] > .40)
		var travel := before.direction_to(waypoint)
		var face := heading if waypoint.distance_squared_to(slot.origin) < .05 else atan2(travel.x, travel.z)
		_advance_rider(rider, waypoint, face, SPEEDS[0], delta, index, true)
		var velocity := before.distance_to(rider.position) / delta
		if velocity < .36:
			blocked_time[index] += delta
		elif velocity > 1.0:
			blocked_time[index] = maxf(0.0, blocked_time[index] - delta * 1.6)
	if blocked_time[index] > 2.25:
		melee_targets[index] = null
		retry_slot[index] = battle_time + .25 + float(index % 5) * .067
		blocked_time[index] = 0.0

func _resolve_strike(index: int, previous: Vector3, delta: float) -> void:
	hit_wait[index] = maxf(0.0, hit_wait[index] - delta)
	if hit_wait[index] > 0:
		return
	var rider := riders[index]
	var velocity := (rider.position - previous).length() / delta
	if velocity < 1.0 or rider.basis.z.dot(approach_direction) < .5:
		return
	var forward := rider.basis.z
	var flank := forward.cross(Vector3.UP)
	var defender = enemies.charge_target(previous, rider.position, forward, charge_contacts[index])
	if defender == null:
		return
	var side := signf((defender.global_position - rider.position).dot(flank))
	if side == 0.0:
		side = 1.0 if defender.index % 2 == 0 else -1.0
	var momentum := minf(velocity, CHARGE_SPEED)
	var sustained := .66 if return_started and battle_time - turn_started_at > 1.5 else 1.0
	enemies.hit(defender, CHARGE.damage(momentum) * sustained, CHARGE.impulse(forward, side, momentum), forward)
	speeds[index] = maxf(1.1, speeds[index] - .57)
	hit_wait[index] = CHARGE.CONTACT_INTERVAL
	charge_contacts[index] |= 1 << defender.index
	if not return_started:
		battle_state = "Прорыв строя"

func _advance_rider(rider: Rider, destination: Vector3, facing: float, limit: float, delta: float, index: int, melee := false) -> bool:
	var offset := destination - rider.position
	var distance := offset.length()
	var obstacles: Array = enemies.soldiers if melee else []
	if distance < .16:
		var yaw := rotate_toward(rider.rotation.y, facing, 2.6 * delta)
		var point := rider.position.move_toward(destination, 1.4 * delta)
		if spacing.clear_pose(index, point, yaw, obstacles):
			rider.position = point
			rider.rotation.y = yaw
		speeds[index] = 0.0
		_set_gait(rider, 0, 0.0, index)
		return absf(angle_difference(rider.rotation.y, facing)) < .05

	var heading := atan2(offset.x, offset.z)
	var yaw := rotate_toward(rider.rotation.y, heading, 2.8 * delta)
	var alignment := maxf(0.0, cos(angle_difference(yaw, heading)))
	var target_speed := minf(limit * (1.12 + .038 * sin(index * 1.23)), sqrt(10.0 * distance)) * alignment
	speeds[index] = move_toward(speeds[index], target_speed, 5.5 * delta)
	var velocity := speeds[index] * alignment
	var point := rider.position + Spacing.heading(yaw) * minf(distance, velocity * delta)
	if spacing.clear_pose(index, point, yaw, obstacles):
		rider.position = point
		rider.rotation.y = yaw
	else:
		if spacing.clear_pose(index, rider.position, yaw, obstacles):
			rider.rotation.y = yaw
		speeds[index] = 0.0
		velocity = 0.0
		if (melee or attacking) and blocked_time[index] > .32:
			var before := rider.position
			rider.position = spacing.make_room(index, offset, obstacles, .83 * delta)
			velocity = before.distance_to(rider.position) / delta
	var gallop_threshold := 2.25 if rider.gait == &"Gallop" else 3.0
	var gait := 0 if velocity < .18 else (2 if limit > SPEEDS[0] and velocity >= gallop_threshold else 1)
	_set_gait(rider, gait, velocity, index)
	return false

func _set_gait(rider: Rider, gait: int, velocity: float, index: int) -> void:
	var clip := GAITS[gait]
	if rider.gait != clip:
		rider.set_gait(clip)
		rider.player.seek(rider.player.current_animation_length * _phase(index))
	rider.player.speed_scale = 1.0 if gait == 0 else clampf(velocity / SPEEDS[gait - 1], .78, 1.3)

func _phase(index: int) -> float:
	return fposmod(index * .61803399, 1.0)

func _process(delta: float) -> void:
	for index in pennons:
		var power := 0.0 if riders[index].fallen else clampf(speeds[index] / 6.5, 0.0, 1.0)
		pennons[index].set_instance_shader_parameter("flutter", power)
	var lateral := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var advance := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	var forward := -camera.basis.z
	forward.y = 0
	camera.position += (camera.basis.x * lateral + forward.normalized() * advance) * 16.0 * delta
	_refresh_status()

func _zoom(amount: float) -> void:
	camera.position -= camera.basis.z * amount
	camera.position.y = clampf(camera.position.y, 3.3, 54.0)

func _refresh_status() -> void:
	var distant := camera.position.distance_squared_to(enemy_caption.global_position) > 80.0
	enemy_caption.visible = enemies.alive_count > 0 and not (attacking and return_started) and distant
	var alive := 0
	for rider in riders:
		alive += int(not rider.fallen)
	var text := "Конники %d  ·  Копейщики %d  ·  %s" % [alive, enemies.alive_count, battle_state]
	if status.text != text:
		status.text = text
