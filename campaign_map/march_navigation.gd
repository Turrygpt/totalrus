extends RefCounted

const Landscape = preload("res://campaign_map/terrain.gd")
const STEP := 6.0
const OFF_ROAD_COST := 2.5
const ROAD_RADIUS := Landscape.ROAD_PAINT_RADIUS

class MarchGraph extends AStar2D:
	var first_road_id: int

	func _compute_cost(from_id: int, to_id: int) -> float:
		var a := get_point_position(from_id)
		var b := get_point_position(to_id)
		var on_road := from_id >= first_road_id and to_id >= first_road_id
		return a.distance_to(b)*(1.0 if on_road else OFF_ROAD_COST)

var ground: Node3D
var graph := MarchGraph.new()
var cells: Vector2i
var offset: Vector2
var terrain_grid: PackedVector3Array
var road_routes: Array[PackedVector2Array]

func _init(terrain: Node3D) -> void:
	ground = terrain
	terrain_grid = terrain.terrain_grid
	road_routes = terrain.road_routes.duplicate()
	offset = -Landscape.HALF + Vector2.ONE*STEP
	cells = Vector2i((Landscape.HALF*2.0-Vector2.ONE*STEP*2.0)/STEP)+Vector2i.ONE
	graph.first_road_id = cells.x*cells.y

func build_graph() -> void:
	# Only the worker's graph and the immutable terrain snapshot are used here.
	var capacity := graph.first_road_id
	for points in road_routes:
		capacity += points.size()
	graph.reserve_space(capacity)
	for y in cells.y:
		for x in cells.x:
			var id := y*cells.x+x
			var point := offset+Vector2(x,y)*STEP
			if is_land(point):
				graph.add_point(id,point)
				for neighbor in [Vector2i(x-1,y),Vector2i(x,y-1),Vector2i(x-1,y-1),Vector2i(x+1,y-1)]:
					if neighbor.x < 0 or neighbor.x >= cells.x or neighbor.y < 0:
						continue
					var other: int = neighbor.y*cells.x+neighbor.x
					if graph.has_point(other) and land_segment(point,graph.get_point_position(other)):
						graph.connect_points(id,other)
	add_roads()

func is_land(point: Vector2) -> bool:
	return (absf(point.x) < Landscape.HALF.x and absf(point.y) < Landscape.HALF.y
		and Landscape.sample_surface_height(terrain_grid,point) > Landscape.WATER_LEVEL+Landscape.BANK_CLEARANCE)

func land_segment(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1,ceili(a.distance_to(b)/1.4))
	for i in range(1,steps+1):
		if not is_land(a.lerp(b,float(i)/steps)):
			return false
	return true

func connector(point: Vector2) -> int:
	var cell := Vector2i(((point-offset)/STEP).round())
	var best := -1
	var distance := INF
	for y in range(maxi(0,cell.y-3),mini(cells.y,cell.y+4)):
		for x in range(maxi(0,cell.x-3),mini(cells.x,cell.x+4)):
			var id := y*cells.x+x
			if not graph.has_point(id):
				continue
			var target := graph.get_point_position(id)
			var cost := point.distance_squared_to(target)
			if cost < distance and land_segment(point,target):
				best = id
				distance = cost
	return best

func add_roads() -> void:
	var next_id := graph.first_road_id
	var junctions: Dictionary[Vector2i,int] = {}
	for points in road_routes:
		var previous := -1
		for i in points.size():
			var point := points[i]
			var endpoint := i == 0 or i == points.size()-1
			var id := next_id
			if endpoint:
				id = junctions.get(Vector2i((point*1000.0).round()),next_id)
			if id == next_id:
				graph.add_point(id,point)
				next_id += 1
				if endpoint:
					junctions[Vector2i((point*1000.0).round())] = id
			if previous >= 0 and previous != id:
				# Water spans along the sampled roads are the rendered bridges.
				graph.connect_points(previous,id)
			if (endpoint or i%5 == 0) and is_land(point):
				var grid_id := connector(point)
				if grid_id >= 0:
					graph.connect_points(id,grid_id)
			previous = id

func route_connector(point: Vector2) -> int:
	var closest := graph.get_closest_point(point)
	if closest >= 0 and land_segment(point,graph.get_point_position(closest)):
		return closest
	return connector(point)

func direct_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not from.is_equal_approx(to) and is_land(from) and land_segment(from,to):
		return split_surfaces(PackedVector2Array([from,to]))
	return PackedVector2Array()

func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	if from.is_equal_approx(to):
		return PackedVector2Array()
	if not is_land(to):
		return PackedVector2Array()
	var direct := direct_route(from,to)
	var direct_cost := INF if direct.is_empty() else preference_cost(from,to)
	if direct_cost <= from.distance_to(to)+0.01:
		return direct
	var start := route_connector(from)
	if not is_land(from):
		# A new order can be given between turns while the army stands on a bridge.
		start = graph.get_closest_point(from)
	var end := route_connector(to)
	if start < 0 or end < 0:
		return direct
	var points := graph.get_point_path(start,end)
	if points.is_empty():
		return direct
	points.insert(0,from)
	points.append(to)
	var costs := PackedFloat32Array([0.0])
	for j in range(1,points.size()):
		costs.append(costs[-1]+preference_cost(points[j-1],points[j]))
	var result := PackedVector2Array([from])
	var i := 0
	while i < points.size()-1:
		var next := i+1
		for j in range(i+2,mini(i+9,points.size())):
			if not is_land(points[i]) or not land_segment(points[i],points[j]):
				break
			if preference_cost(points[i],points[j]) <= costs[j]-costs[i]+0.01:
				next = j
		if not result[-1].is_equal_approx(points[next]):
			result.append(points[next])
		i = next
	var result_cost := 0.0
	for j in range(1,result.size()):
		result_cost += preference_cost(result[j-1],result[j])
	if direct_cost <= result_cost:
		return direct
	return split_surfaces(result)

func preference_cost(a: Vector2, b: Vector2) -> float:
	var length := a.distance_to(b)
	var steps := maxi(1,ceili(length))
	var cost := 0.0
	for i in steps:
		var on_road: bool = ground.movement_cost(a.lerp(b,(i+0.5)/steps),ROAD_RADIUS) < 1.0
		cost += 1.0 if on_road else OFF_ROAD_COST
	return cost*length/steps

func split_surfaces(points: PackedVector2Array) -> PackedVector2Array:
	# Keep transitions as waypoints so movement can change speed mid-segment.
	var result := PackedVector2Array([points[0]])
	for i in range(1,points.size()):
		var a := points[i-1]
		var b := points[i]
		if a.is_equal_approx(b):
			continue
		var steps := ceili(a.distance_to(b))
		var previous: float = ground.movement_cost(a.lerp(b,0.5/steps))
		for j in range(1,steps):
			var cost: float = ground.movement_cost(a.lerp(b,(j+0.5)/steps))
			if cost != previous:
				result.append(a.lerp(b,float(j)/steps))
				previous = cost
		result.append(b)
	return result

func segment_cost(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)*ground.movement_cost(a.lerp(b,0.5))

func route_cost(points: PackedVector2Array) -> float:
	var cost := 0.0
	for i in range(1,points.size()):
		cost += segment_cost(points[i-1],points[i])
	return cost
