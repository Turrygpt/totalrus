extends RefCounted

static var terrain_ref: WeakRef

const DEFAULT_HALF_SIZE := Vector2(60.0, 45.0)
const MANEUVER_HALF_SIZE := Vector2(96.0, 72.0)

static func for_scene(scene: Node) -> Vector2:
	if not is_instance_valid(scene):
		return DEFAULT_HALF_SIZE
	var bounds: Variant = scene.get(&"field_half_size")
	return bounds if bounds is Vector2 else DEFAULT_HALF_SIZE

static func clamp_ground(point: Vector3, bounds: Vector2, inset: float) -> Vector3:
	var limit := (bounds - Vector2.ONE * inset).max(Vector2.ZERO)
	return project(Vector3(
		clampf(point.x, -limit.x, limit.x),
		0.0,
		clampf(point.z, -limit.y, limit.y)
	))

static func project(point: Vector3) -> Vector3:
	var terrain: Node = terrain_ref.get_ref() if terrain_ref else null
	if is_instance_valid(terrain): point.y = terrain.height_at(Vector2(point.x,point.z))
	return point
