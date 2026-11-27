extends RefCounted

const Rider = preload("res://scripts/horseman.gd")
const BODY_RADIUS := .55
const NAV_CELL := .62
const ATTACK_DISTANCE := 2.03
const OUTER_ATTACK_DISTANCE := 2.47

var riders: Array[Rider]
var grid := AStarGrid2D.new()
var painted: Array[Vector2i] = []
var routes: Dictionary = {}
var reroute_at: Dictionary = {}
var last_goals: Dictionary = {}

func _init(group: Array[Rider]) -> void:
	riders = group
	grid.region = Rect2i(-125, -125, 250, 250)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	grid.update()

static func heading(yaw: float) -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))

static func body_gap(point: Vector3, yaw: float, other: Vector3, other_yaw: float) -> float:
	var a := heading(yaw)
	var b := heading(other_yaw)
	var points := Geometry3D.get_closest_points_between_segments(
			point - a * .55, point + a * .78, other - b * .55, other + b * .78)
	return points[0].distance_to(points[1])

func clear_pose(index: int, point: Vector3, angle: float, infantry: Array = []) -> bool:
	var rider := riders[index]
	for i in riders.size():
		if index == i:
			continue
		var other := riders[i]
		if point.distance_squared_to(other.position) > 10.0:
			continue
		var minimum := BODY_RADIUS * (1.75 if other.fallen else 2.0)
		var gap := body_gap(point, angle, other.position, other.rotation.y)
		if gap < minimum:
			var current := body_gap(rider.position, rider.rotation.y, other.position, other.rotation.y)
			if gap + .0001 < current or current >= minimum:
				return false
	var forward := heading(angle)
	var original_forward := heading(rider.rotation.y)
	for soldier in infantry:
		if not soldier.alive or point.distance_squared_to(soldier.global_position) > 3.3:
			continue
		var foot: Vector3 = soldier.global_position
		var closest := Geometry3D.get_closest_point_to_segment(foot, point - forward * .55, point + forward * .78)
		if closest.distance_squared_to(foot) < .62:
			var original := Geometry3D.get_closest_point_to_segment(
					foot, rider.position - original_forward * .55, rider.position + original_forward * .78)
			if closest.distance_squared_to(foot) + .0001 < original.distance_squared_to(foot):
				return false
	return true

func make_room(index: int, travel: Vector3, infantry: Array, distance: float) -> Vector3:
	var rider := riders[index]
	var aim := travel.normalized()
	var side := 1.0 if index % 2 == 0 else -1.0
	var best := rider.position
	var best_score := -INF
	for step in [0.0, .52, -.52, 1.05, -1.05, 1.57, -1.57, 2.2, -2.2, PI]:
		var direction := aim.rotated(Vector3.UP, step * side)
		var next := rider.position + direction * distance
		if not clear_pose(index, next, rider.rotation.y, infantry):
			continue
		var room := clear_pose(index, next + direction * .24, rider.rotation.y, infantry)
		var score := direction.dot(aim) + (.75 if room else 0.0)
		if score > best_score:
			best = next
			best_score = score
	return best

func free_slot(index: int, infantry: Array, reserved: Array[Transform3D]) -> Dictionary:
	var rider := riders[index]
	var best := INF
	var result := {}
	for soldier in infantry:
		if not soldier.alive:
			continue
		var origin: Vector3 = soldier.global_position
		var from_target := origin.direction_to(rider.position)
		var radial := atan2(from_target.x, from_target.z)
		var nearest := maxf(0.0, rider.position.distance_to(origin) - OUTER_ATTACK_DISTANCE)
		if nearest * nearest > best:
			continue
		for reach: float in [ATTACK_DISTANCE, OUTER_ATTACK_DISTANCE]:
			var found := false
			for i in range(12):
				var angle := radial + TAU * i / 12.0
				var point := origin + heading(angle) * reach
				var distance := rider.position.distance_squared_to(point)
				if distance >= best or not _free_destination(index, point, angle + PI, reserved, infantry):
					continue
				best = distance
				found = true
				result = {"target": soldier, "angle": angle, "reach": reach}
			if found:
				break
	return result

func _free_destination(index: int, point: Vector3, angle: float, reserved: Array[Transform3D], infantry: Array) -> bool:
	for pose in reserved:
		if point.distance_squared_to(pose.origin) < 10.0:
			var yaw := atan2(pose.basis.z.x, pose.basis.z.z)
			if body_gap(point, angle, pose.origin, yaw) < BODY_RADIUS * 2.12:
				return false
	return clear_pose(index, point, angle, infantry)

func waypoint(index: int, goal: Vector3, infantry: Array, now: float, force: bool) -> Vector3:
	var point := riders[index].position
	var changed := not last_goals.has(index) or goal.distance_to(last_goals[index]) > .62
	if changed or now >= reroute_at.get(index, 0.0):
		last_goals[index] = goal
		reroute_at[index] = now + .34 + .019 * (index % 6)
		routes[index] = _route(index, point, goal, infantry) if force or not _clear_path(index, point, goal, infantry) else PackedVector3Array()
	var route: PackedVector3Array = routes.get(index, PackedVector3Array())
	while not route.is_empty() and point.distance_squared_to(route[0]) < .20:
		route.remove_at(0)
	var short_cut := mini(route.size() - 1, 5)
	while short_cut > 0:
		if _clear_path(index, point, route[short_cut], infantry):
			for i in short_cut:
				route.remove_at(0)
			break
		short_cut -= 1
	routes[index] = route
	return goal if route.is_empty() else route[0]

func _clear_path(index: int, from: Vector3, to: Vector3, infantry: Array) -> bool:
	for i in riders.size():
		if i == index:
			continue
		var other := riders[i]
		var p := Geometry3D.get_closest_point_to_segment(other.position, from, to)
		if p.distance_squared_to(other.position) < 1.85:
			return false
	for soldier in infantry:
		if soldier.alive:
			var foot: Vector3 = soldier.global_position
			var p := Geometry3D.get_closest_point_to_segment(foot, from, to)
			if p.distance_squared_to(foot) < 1.30:
				return false
	return true

func _route(index: int, from: Vector3, to: Vector3, infantry: Array) -> PackedVector3Array:
	for cell in painted:
		grid.set_point_solid(cell, false)
	painted.clear()
	for i in riders.size():
		if i != index:
			var other := riders[i]
			var forward := heading(other.rotation.y)
			for offset in [-.52, .02, .70]:
				_paint_disk(other.position + forward * offset, .87)
	for soldier in infantry:
		if soldier.alive:
			_paint_disk(soldier.global_position, .79)
	var start := _cell(from)
	var finish := _cell(to)
	var path := PackedVector3Array()
	if not grid.is_in_boundsv(start) or not grid.is_in_boundsv(finish):
		return path
	grid.set_point_solid(start, false)
	grid.set_point_solid(finish, false)
	var cells := grid.get_id_path(start, finish)
	for i in range(1, cells.size() - 1):
		path.append(Vector3(cells[i].x * NAV_CELL, 0, cells[i].y * NAV_CELL))
	return path

func _paint_disk(point: Vector3, radius: float) -> void:
	var around := _cell(point)
	for x in range(around.x - 2, around.x + 3):
		for z in range(around.y - 2, around.y + 3):
			var cell := Vector2i(x, z)
			if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell):
				if point.distance_squared_to(Vector3(x * NAV_CELL, 0, z * NAV_CELL)) < radius * radius:
					grid.set_point_solid(cell, true)
					painted.append(cell)

func _cell(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / NAV_CELL), roundi(point.z / NAV_CELL))
