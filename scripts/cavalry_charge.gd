extends RefCounted

const UNIT_KINDS := ["cavalry","light_cavalry","princely"]
const HEAVY_KINDS := ["cavalry","princely"]
const LIGHT_RUN_SPEED := 7.2
const KHAZAR_RUN_SPEED := LIGHT_RUN_SPEED * .8
const HEAVY_RUN_SPEED := LIGHT_RUN_SPEED * .7
const LIGHT_STAMINA_COST := .75
const WEDGE_MIN_STAMINA := 55.0
const WEDGE_STAMINA_DRAIN := 2.0
const WEDGE_RUN_UP := 7.0
const CONTACT_INTERVAL := .11

static func contact_score(point: Vector3, from: Vector3, to: Vector3, forward: Vector3) -> float:
	point.y = 0.0
	from.y = 0.0
	to.y = 0.0
	forward = forward.slide(Vector3.UP).normalized()
	var depth := (point - from).dot(forward)
	if depth < -.35:
		return INF
	var flank := forward.cross(Vector3.UP) * .30
	var lance := Geometry3D.get_closest_point_to_segment(point, from + flank, to + flank + forward * 2.08)
	var body := Geometry3D.get_closest_point_to_segment(point, from, to + forward * 1.14)
	var lateral := point.distance_squared_to(body)
	var reach := point.distance_squared_to(lance)
	return maxf(0.0, depth) + .36 * minf(lateral, reach) if lateral < 1.36 or reach < 1.03 else INF

static func damage(momentum: float) -> float:
	return 23.0 + momentum * 8.35

static func impulse(forward: Vector3, side: float, momentum: float) -> Vector3:
	return forward * momentum * .42 + forward.cross(Vector3.UP) * side * (2.7 + momentum * .88)
