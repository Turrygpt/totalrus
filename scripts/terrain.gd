extends Node3D
const FIELD = preload("res://scripts/battlefield_bounds.gd")
const TacticalWoodland = preload("res://scripts/tactical_woodland.gd")
const CABIN = preload("res://assets/cinematic_log_cabin.glb")
const SMITHY = preload("res://assets/blacksmith_forge_lod1.glb")
const MapGenerator = preload("res://scripts/tactical_map_generator.gd")
const WELL = preload("res://assets/props/timber_well.glb")
const SMITHY_SCALE := 8.0
const GRASS_COLOR = preload("res://assets/terrain/grass_color.jpg")
const GRASS_NORMAL = preload("res://assets/terrain/grass_normalgl.jpg")
const DIRT_COLOR = preload("res://assets/terrain/msta_compacted_earth.jpg")
const LITTER_COLOR = preload("res://assets/terrain/msta_leaf_litter.jpg")
const SILT_COLOR = preload("res://assets/terrain/msta_wet_silt.jpg")
const WATTLE = preload("res://assets/props/msta_wattle.res")
const DEADWOOD = preload("res://assets/props/msta_deadwood.res")
const OUTCROP = preload("res://assets/props/msta_outcrop.res")
const PEBBLES = preload("res://assets/props/msta_pebbles.res")
const PROP_CHUNK_SIZE := 64.0
const ROCK_COLOR = preload("res://assets/terrain/rock_color.jpg")
const ROCK_NORMAL = preload("res://assets/terrain/rock_normalgl.jpg")
const GRASS_CHUNK_SIZE := 18.0
const GRASS_RANGE := 105.0
const GRASS_CHUNKS_PER_FRAME := 8
var rng := RandomNumberGenerator.new()
var grass_rng := RandomNumberGenerator.new()
var grass_mesh: Mesh
var grass_range := GRASS_RANGE
var grass_instances_per_chunk := 320
var grass_chunks: Dictionary[Vector2i, bool] = {}
var grass_queue: Array[Vector2i] = []
var grass_camera_cell := Vector2i.MAX
var highest_ground := 0.0
var field_half_size := FIELD.DEFAULT_HALF_SIZE
var landscape: Dictionary = {}
var snow := 0.0
var generator: MapGenerator
var yards: Array[Vector2] = []
var tracks := PackedVector4Array()
var grid_size := Vector2i.ZERO
var grid_half := Vector2.ZERO
var grid_step := Vector2.ONE
var heights := PackedFloat32Array()
var ground_cover := PackedColorArray()
var obstacles: Array[Vector3] = []
var ground_material: ShaderMaterial

func _ready() -> void:
	generator = MapGenerator.new(field_half_size, landscape)
	snow = 1.0 if landscape.get("season",0)==3 else 0.0
	grid_half = field_half_size+Vector2(160,160)
	grid_size = Vector2i(ceili(grid_half.x*2/4)+1,ceili(grid_half.y*2/4)+1)
	grid_step = grid_half*2/Vector2(grid_size-Vector2i.ONE)
	heights.resize(grid_size.x*grid_size.y)
	for z in grid_size.y:
		for x in grid_size.x:
			var height := generator.height_at(Vector2(x, z) * grid_step - grid_half)
			heights[z * grid_size.x + x] = height
			highest_ground = maxf(highest_ground, height)
	plan_yards()
	plan_shore_approach()
	make_ground()
	make_homesteads()
	make_rocks()
	make_trees()
	make_reeds()
	make_landmarks()

func height_at(p: Vector2) -> float:
	if heights.is_empty(): return generator.height_at(p)
	var uv := ((p+grid_half)/grid_step).clamp(Vector2.ZERO,Vector2(grid_size-Vector2i.ONE)-Vector2.ONE*.001)
	var cell := Vector2i(uv.floor())
	var weight := uv-Vector2(cell)
	var i := cell.y*grid_size.x+cell.x
	var a := heights[i]
	var b := heights[i+1]
	var c := heights[i+grid_size.x]
	var d := heights[i+grid_size.x+1]
	return a+(b-a)*weight.x+(c-a)*weight.y if weight.x+weight.y<=1 else d+(c-d)*(1-weight.x)+(b-d)*(1-weight.y)

func ground_point(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x,height_at(p)+lift,p.y)

func road_x(z: float) -> float:
	return generator.road_x(z)

func add_track(from: Vector2, to: Vector2) -> void:
	tracks.append(Vector4(from.x, from.y, to.x, to.y))

func plan_shore_approach() -> void:
	var points := generator.shore_approach()
	for i in range(1, points.size()):
		add_track(points[i - 1], points[i])

func path_distance(point: Vector2) -> float:
	var distance := absf(point.x - road_x(point.y))
	for track in tracks:
		if (point.y < minf(track.y, track.w) - 5.0 or point.y > maxf(track.y, track.w) + 5.0
				or point.x < minf(track.x, track.z) - 5.0 or point.x > maxf(track.x, track.z) + 5.0):
			continue
		var start := Vector2(track.x, track.y)
		var finish := Vector2(track.z, track.w)
		var closest := Geometry2D.get_closest_point_to_segment(point, start, finish)
		distance = minf(distance, point.distance_to(closest) * 2.2)
	return distance

func plan_yards() -> void:
	for point in generator.yard_candidates():
		if absf(point.x) + 32.0 > field_half_size.x or absf(point.y) + 38.0 > field_half_size.y:
			continue
		if generator.coast >= 0 and generator.shore_distance(point) > -64.0:
			continue
		if height_at(point) < 1.0 or grade_at(point, 9.0) > .26:
			continue
		yards.append(point)
		var road_z := point.y + 7.0
		add_track(Vector2(road_x(road_z), road_z), point - Vector2(signf(generator.road.x) * 4.0, 0))
		var foundation_height := height_at(point)
		level_plot(point, Vector2(7.0, 6.0), foundation_height)
		if yards.size() == 1:
			level_plot(well_point(), Vector2(2.0, 2.0), foundation_height)
		if yards.size() == MapGenerator.YARD_COUNT[generator.profile]:
			break

func well_point() -> Vector2:
	var yard := yards[0]
	return yard + Vector2(-signf(generator.road.x) * 4.0, 12.5)

func grade_at(point: Vector2, run: float) -> float:
	var x := Vector2(run, 0)
	var z := Vector2(0, run)
	return maxf(absf(height_at(point + x) - height_at(point - x)),
		absf(height_at(point + z) - height_at(point - z))) / (2.0 * run)

func level_plot(center: Vector2, footprint: Vector2, foundation_height: float) -> void:
	# Keep all triangles under the footprint in the flat part of the pad.
	var pad := footprint + grid_step
	var transition := grid_step * 3.0
	var extent := pad + transition
	var start := Vector2i(((center - extent + grid_half) / grid_step).floor()).max(Vector2i.ZERO)
	var end := Vector2i(((center + extent + grid_half) / grid_step).ceil()).min(grid_size - Vector2i.ONE)
	for z in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			var point := Vector2(x, z) * grid_step - grid_half
			var blend := ((point - center).abs() - pad) / transition
			var index := z * grid_size.x + x
			heights[index] = lerpf(foundation_height, heights[index], smoothstep(0.0, 1.0, maxf(blend.x, blend.y)))

func make_ground() -> void:
	ground_material = ShaderMaterial.new()
	ground_material.shader = preload("res://scripts/battle_ground.gdshader")
	ground_material.set_shader_parameter("grass_color",GRASS_COLOR)
	ground_material.set_shader_parameter("grass_normal", GRASS_NORMAL)
	ground_material.set_shader_parameter("dirt_color", DIRT_COLOR)
	ground_material.set_shader_parameter("litter_color", LITTER_COLOR)
	ground_material.set_shader_parameter("silt_color", SILT_COLOR)
	ground_material.set_shader_parameter("rock_color", ROCK_COLOR)
	ground_material.set_shader_parameter("rock_normal", ROCK_NORMAL)
	ground_material.set_shader_parameter("snow",snow)
	ground_material.set_shader_parameter("road_curve", generator.road)
	var padded_tracks := tracks.duplicate()
	padded_tracks.resize(MapGenerator.MAX_TRACKS)
	ground_material.set_shader_parameter("tracks", padded_tracks)
	ground_material.set_shader_parameter("track_count", tracks.size())
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	ground_cover.resize(heights.size())
	for z in grid_size.y:
		for x in grid_size.x:
			var point := Vector2(x, z) * grid_step - grid_half
			var index := z * grid_size.x + x
			vertices.append(Vector3(point.x, heights[index], point.y))
			uv.append(Vector2(x, z))
			var west := maxi(0, x - 1)
			var east := mini(grid_size.x - 1, x + 1)
			var north := maxi(0, z - 1)
			var south := mini(grid_size.y - 1, z + 1)
			var grade_x := (heights[z * grid_size.x + east] - heights[z * grid_size.x + west]) / ((east - west) * grid_step.x)
			var grade_z := (heights[south * grid_size.x + x] - heights[north * grid_size.x + x]) / ((south - north) * grid_step.y)
			ground_cover[index] = generator.surface_weights(point, Vector2(grade_x, grade_z).length())
	for z in grid_size.y-1:
		for x in grid_size.x-1:
			var i := z*grid_size.x+x
			indices.append_array(PackedInt32Array([i,i+1,i+grid_size.x,i+1,i+grid_size.x+1,i+grid_size.x]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_COLOR] = ground_cover
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var surface := SurfaceTool.new()
	surface.create_from(mesh,0)
	surface.generate_normals()
	surface.generate_tangents()
	var ground := MeshInstance3D.new()
	ground.name="Relief"
	ground.mesh=surface.commit()
	ground.material_override=ground_material
	add_child(ground)
	add_ground_collision(ground)
	if generator.coast >= 0:
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size=grid_half*2
		water.mesh=plane
		var mat := ShaderMaterial.new()
		mat.shader=preload("res://scripts/battle_water.gdshader")
		water.material_override=mat
		water.position.y = MapGenerator.WATER_HEIGHT
		water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)

func ground_cover_at(point: Vector2) -> Color:
	var cell := Vector2i(((point + grid_half) / grid_step).round()).clamp(Vector2i.ZERO, grid_size - Vector2i.ONE)
	return ground_cover[cell.y * grid_size.x + cell.x]

func add_ground_collision(ground: MeshInstance3D) -> void:
	# The regular height grid can be used directly as a collider.
	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = grid_size.x
	heightmap.map_depth = grid_size.y
	heightmap.map_data = heights
	var collision := CollisionShape3D.new()
	collision.shape = heightmap
	collision.scale = Vector3(grid_step.x, 1.0, grid_step.y)
	var body := StaticBody3D.new()
	body.add_child(collision)
	ground.add_child(body)

func clear_for_scenery(point: Vector2) -> bool:
	# This strip covers the opening formations, the middle of the field and reinforcement rows.
	var far_bank := (generator.profile == MapGenerator.Profile.SHORE
		and generator.shore_distance(point) > 80.0)
	if absf(point.x) < generator.opening_half_width and not far_bank:
		return false
	if path_distance(point) < 8.0:
		return false
	if generator.profile == MapGenerator.Profile.SETTLEMENT and (
		absf(point.y) < 45.0 or absf(point.y) > field_half_size.y - 45.0
	):
		return false
	for obstacle in obstacles:
		if point.distance_squared_to(Vector2(obstacle.x, obstacle.y)) < pow(obstacle.z + 7.0, 2):
			return false
	for yard in yards:
		if point.distance_squared_to(yard) < 23.0 * 23.0:
			return false
	return height_at(point) > .8

func make_trees() -> void:
	rng.seed = hash([generator.seed_value, "trees"])
	var groups := [[], [], [], []]
	# Jitter a grid to keep trees from stacking while preserving clusters and clearings.
	var tree_cells := 15100.0 if generator.profile == MapGenerator.Profile.WOODLAND else 11200.0
	var step := maxf(8.0, sqrt(grid_half.x * grid_half.y * 4.0 / tree_cells))
	var cells := Vector2i((grid_half * 2.0 / step).floor())
	for z in cells.y:
		for x in cells.x:
			var p := (Vector2(x, z) + Vector2(rng.randf_range(.16, .84), rng.randf_range(.16, .84))) * step - grid_half
			if not clear_for_scenery(p) or rng.randf() >= generator.tree_cover(p):
				continue
			var kind := rng.randi_range(0, 3)
			if (snow > .5 or generator.profile == MapGenerator.Profile.RIDGES) and rng.randf() < .55:
				kind = 2
			elif generator.profile == MapGenerator.Profile.SHORE and rng.randf() < .44:
				kind = 1
			var size := rng.randf_range(.86, 1.64)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
			groups[kind].append(Transform3D(basis, ground_point(p)))
	var woodland := TacticalWoodland.new()
	woodland.name = "TacticalWoodland"
	add_child(woodland)
	woodland.plant(groups, snow)

func make_reeds() -> void:
	if generator.coast < 0:
		return
	rng.seed = hash([generator.seed_value, "shore vegetation"])
	var transforms: Array[Transform3D] = []
	var along := field_half_size.y if generator.coast < 2 else field_half_size.x
	for i in 355:
		var offset := rng.randf_range(-along, along)
		var point := generator.shore_point(rng.randf_range(-3.0, 39.0), offset)
		if path_distance(point) < 3.3:
			continue
		var height := height_at(point)
		if height < -.68 or height > 1.5:
			continue
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(.62, 1.55))
		transforms.append(Transform3D(basis, ground_point(point)))
	if transforms.is_empty():
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 12:
		var angle := i * 2.39996
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var bottom := direction * rng.randf_range(.10, .48)
		var right := direction.cross(Vector3.UP) * rng.randf_range(.05, .10)
		var tip := bottom + direction * .24 + Vector3.UP * rng.randf_range(.65, 1.5)
		surface.add_vertex(bottom - right)
		surface.add_vertex(bottom + right)
		surface.add_vertex(tip)
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("88764e") if snow > .5 else Color("777b3d")
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := surface.commit()
	mesh.surface_set_material(0, material)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var reeds := MultiMeshInstance3D.new()
	reeds.name = "ShoreReeds"
	reeds.multimesh = multi
	reeds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(reeds)

func make_homesteads() -> void:
	if yards.is_empty():
		return
	var props := Node3D.new()
	props.name = "RoadsideProps"
	add_child(props)
	for i in yards.size():
		var point := yards[i]
		var smithy := i == 0
		var building := (SMITHY if smithy else CABIN).instantiate() as Node3D
		props.add_child(building)
		building.position = ground_point(point, -.1 if smithy else .04)
		building.scale = Vector3.ONE * (SMITHY_SCALE if smithy else .9)
		if not smithy:
			building.rotation.y = -signf(generator.road.x) * PI * .5
		obstacles.append(Vector3(point.x, point.y, 7.5))
		var fence := MeshInstance3D.new()
		fence.name = "WattleFence"
		fence.mesh = WATTLE
		fence.position = ground_point(point + Vector2(signf(generator.road.x) * 4.2, 3.9), -.04)
		fence.rotation.y = PI * .5
		props.add_child(fence)
	var site := well_point()
	var well := WELL.instantiate() as Node3D
	well.name = "TimberWell"
	props.add_child(well)
	well.position = ground_point(site)
	well.rotation.y = generator.road.w
	obstacles.append(Vector3(site.x, site.y, 1.55))

func make_landmarks() -> void:
	if generator.profile == MapGenerator.Profile.SETTLEMENT:
		return
	var meshes: Array[Mesh] = [DEADWOOD, OUTCROP, PEBBLES]
	var groups: Array[Dictionary] = [{}, {}, {}]
	var random := RandomNumberGenerator.new()
	random.seed = hash([generator.seed_value, generator.profile, "landmark props"])
	var margins := field_half_size + Vector2.ONE * 94.0
	if generator.profile in [MapGenerator.Profile.WOODLAND, MapGenerator.Profile.SHORE]:
		for i in 430:
			var point := Vector2(random.randf_range(-margins.x, margins.x), random.randf_range(-margins.y, margins.y))
			var cover := generator.tree_cover(point)
			var distance_outside := (point.abs() - field_half_size).maxf(0.0).length()
			if (distance_outside < 4.0 or cover < .27 or not clear_for_scenery(point)
					or grade_at(point, 2.0) > .34):
				continue
			add_landmark(groups[0], point, random.randf_range(.72, 1.35), random.randf() * TAU)
	if generator.profile == MapGenerator.Profile.RIDGES:
		for i in 110:
			var x := generator.flank * (field_half_size.x + random.randf_range(8.0, 72.0))
			var point := Vector2(x, random.randf_range(-margins.y, margins.y))
			if not clear_for_scenery(point) or grade_at(point, 3.0) > .46:
				continue
			add_landmark(groups[1], point, random.randf_range(.88, 2.5), random.randf() * TAU)
	if generator.coast >= 0:
		var along := field_half_size.y if generator.coast < 2 else field_half_size.x
		for cluster in 42:
			var offset := random.randf_range(-along, along)
			var depth := random.randf_range(-12.0, 26.0)
			for i in 8:
				var point := generator.shore_point(depth + random.randf_range(-3.0, 3.0), offset + random.randf_range(-9.0, 9.0))
				if height_at(point) < -.32 or path_distance(point) < 3.0:
					continue
				add_landmark(groups[2], point, random.randf_range(.75, 1.5), random.randf() * TAU)
	var scenery := Node3D.new()
	scenery.name = "LandscapeProps"
	add_child(scenery)
	for kind in groups.size():
		for cell: Vector2i in groups[kind]:
			var placements: Array[Transform3D] = groups[kind][cell]
			var data := MultiMesh.new()
			data.transform_format = MultiMesh.TRANSFORM_3D
			data.mesh = meshes[kind]
			data.instance_count = placements.size()
			for i in placements.size():
				data.set_instance_transform(i, placements[i])
			var chunk := MultiMeshInstance3D.new()
			chunk.position = Vector3(cell.x, 0, cell.y) * PROP_CHUNK_SIZE
			chunk.multimesh = data
			chunk.visibility_range_end = [185.0, 480.0, 125.0][kind]
			if kind == 2:
				chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			scenery.add_child(chunk)

func add_landmark(chunks: Dictionary, point: Vector2, size: float, yaw: float) -> void:
	var cell := Vector2i((point / PROP_CHUNK_SIZE).floor())
	if not chunks.has(cell):
		var placements: Array[Transform3D] = []
		chunks[cell] = placements
	var x := height_at(point + Vector2(1.0, 0)) - height_at(point - Vector2(1.0, 0))
	var z := height_at(point + Vector2(0, 1.0)) - height_at(point - Vector2(0, 1.0))
	var normal := Vector3(-x, 2.0, -z).normalized()
	var tilt := Basis(Quaternion(Vector3.UP, normal))
	var basis := (tilt * Basis(Vector3.UP, yaw)).scaled(Vector3.ONE * size)
	var position := ground_point(point, -.065) - Vector3(cell.x, 0, cell.y) * PROP_CHUNK_SIZE
	chunks[cell].append(Transform3D(basis, position))

func constrain(point: Vector3) -> Vector3:
	var p:=Vector2(point.x,point.z)
	for obstacle in obstacles:
		var center:=Vector2(obstacle.x,obstacle.y)
		var away:=p-center
		if away.length_squared()<obstacle.z*obstacle.z:
			p=center+(away.normalized() if away.length_squared()>.001 else Vector2.RIGHT)*obstacle.z
	return ground_point(p)

func waypoint(from: Vector3, to: Vector3) -> Vector3:
	var start:=Vector2(from.x,from.z)
	var goal:=Vector2(to.x,to.z)
	for obstacle in obstacles:
		var center:=Vector2(obstacle.x,obstacle.y)
		if start.distance_squared_to(center) >= 35.0 * 35.0: continue
		var near := Geometry2D.get_closest_point_to_segment(center,start,goal)
		if near.distance_squared_to(center) < (obstacle.z+1) * (obstacle.z+1):
			var side:=(goal-start).normalized().orthogonal()
			if (start-center).dot(side)<0: side=-side
			return ground_point(center+side*(obstacle.z+3))
	return to

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	if not heights.is_empty() and camera.global_position.y <= highest_ground + grass_range:
		update_grass(camera.global_position)

func update_grass(camera_position: Vector3) -> void:
	# A chunk outside this neighborhood cannot contain a blade within shader fade range.
	var cell := Vector2i((Vector2(camera_position.x,camera_position.z)/GRASS_CHUNK_SIZE).floor())
	if cell != grass_camera_cell:
		grass_camera_cell = cell
		grass_queue.clear()
		var radius := ceili(grass_range/GRASS_CHUNK_SIZE)
		var limits := Vector2i(((field_half_size + Vector2(12, 9)) / GRASS_CHUNK_SIZE).ceil())
		var low := (cell - Vector2i.ONE * radius).max(-limits)
		var high := (cell + Vector2i.ONE * (radius + 1)).min(limits)
		for z in range(low.y, high.y):
			for x in range(low.x, high.x):
				var key := Vector2i(x, z)
				if not grass_chunks.has(key):
					grass_queue.append(key)
		grass_queue.sort_custom(func(a: Vector2i, b: Vector2i):
			return (a - cell).length_squared() > (b - cell).length_squared())
	if grass_queue.is_empty(): return
	if grass_mesh == null:
		grass_rng.seed = rng.seed
		grass_mesh = make_grass_mesh()
	var chunk_budget := 2 if grass_instances_per_chunk < 320 else GRASS_CHUNKS_PER_FRAME
	for i in mini(chunk_budget,grass_queue.size()):
		var key: Vector2i = grass_queue.pop_back()
		make_grass_chunk(key)
		grass_chunks[key] = true

func make_grass_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in 7:
		var angle := grass_rng.randf_range(0,TAU)
		var center := Vector3(grass_rng.randf_range(-.12,.12),0,grass_rng.randf_range(-.12,.12))
		var side := Vector3(.009,0,0).rotated(Vector3.UP,angle)
		var bend := Vector3(.09,0,.02).rotated(Vector3.UP,angle)
		var height := grass_rng.randf_range(.13,.31)
		var a := center-side
		var b := center+side
		var c := center+Vector3.UP*height*.55+bend*.25-side*.55
		var d := center+Vector3.UP*height*.55+bend*.25+side*.55
		var tip := center+Vector3.UP*height+bend
		for vertex in [a,b,c,b,d,c,c,d,tip]:
			st.set_normal(Vector3(.2,.85,.15).normalized())
			st.set_color(Color(.75,.85,.55,vertex.y / height))
			st.add_vertex(vertex)
	var mesh := st.commit()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec2 field_half_size;
uniform float snow;
varying float height;
varying float variation;
void vertex(){
 vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 height=COLOR.a;
 variation=sin(world.x*.51+world.z*.26)*.5+.5;
 float wind=sin(world.x*.42+world.z*.25+TIME*1.6)*.035+sin(TIME*2.7+world.z)*.012;
 // Fade per blade in world space. Per-chunk distance cutoffs expose square borders.
 float fade=1.0-smoothstep(55.0,90.0,distance(CAMERA_POSITION_WORLD,world));
 float edge_x=1.0-smoothstep(field_half_size.x+1.0+sin(world.z*.43)*3.0,field_half_size.x+12.0,abs(world.x));
 float edge_z=1.0-smoothstep(field_half_size.y-2.0+sin(world.x*.37)*3.0,field_half_size.y+9.0,abs(world.z));
 fade*=edge_x*edge_z;
 VERTEX*=fade;
 VERTEX.x+=wind*height*height*fade;
 VERTEX.z+=wind*.55*height*height*fade;
}
void fragment(){
 ALBEDO=mix(vec3(.055,.075,.026),vec3(.27,.30,.105),height)*mix(.78,1.17,variation);
 ALBEDO=mix(ALBEDO,vec3(.62,.70,.73),snow*.8);
 ROUGHNESS=.95;
 BACKLIGHT=ALBEDO*.35;
}
"""
	material.shader = shader
	material.set_shader_parameter("field_half_size", field_half_size)
	material.set_shader_parameter("snow",snow)
	mesh.surface_set_material(0,material)
	return mesh

func make_grass_chunk(cell: Vector2i) -> void:
	grass_rng.seed = hash([generator.seed_value, cell])
	const HALF_CHUNK := GRASS_CHUNK_SIZE*.5
	var chunk_center := Vector3(cell.x*GRASS_CHUNK_SIZE+HALF_CHUNK,0,cell.y*GRASS_CHUNK_SIZE+HALF_CHUNK)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = grass_mesh
	multi.instance_count = grass_instances_per_chunk
	var buffer := PackedFloat32Array()
	buffer.resize(multi.instance_count*12)
	for i in multi.instance_count:
		var point := Vector3(grass_rng.randf_range(-HALF_CHUNK,HALF_CHUNK),0,grass_rng.randf_range(-HALF_CHUNK,HALF_CHUNK))
		var world := point+chunk_center
		point.y = height_at(Vector2(world.x,world.z))
		var at := Vector2(world.x, world.z)
		var path := path_distance(at)
		var cover := ground_cover_at(at)
		var growth := 1.0 - maxf(cover.r * .76, maxf(cover.g * .88, maxf(cover.b, cover.a)))
		var density := growth * smoothstep(2.0, 4.2, path) * smoothstep(MapGenerator.WATER_HEIGHT, .8, point.y)
		var scale_factor := grass_rng.randf_range(.55, 1.4) * maxf(.001, density)
		var basis := Basis(Vector3.UP,grass_rng.randf_range(0,TAU)).scaled(Vector3.ONE*scale_factor)
		for row in 3:
			var offset := i*12 + row*4
			buffer[offset] = basis.x[row]
			buffer[offset+1] = basis.y[row]
			buffer[offset+2] = basis.z[row]
			buffer[offset+3] = point[row]
	multi.buffer = buffer
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.position = chunk_center
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = grass_range
	add_child(instance)

func make_rocks() -> void:
	rng.seed = hash([generator.seed_value, "rocks"])
	var material := StandardMaterial3D.new()
	material.albedo_texture = ROCK_COLOR
	material.normal_enabled = true
	material.normal_texture = ROCK_NORMAL
	material.roughness = .95
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 1.2
	for variant in 4:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 12
		sphere.rings = 7
		var arrays := sphere.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			var p := vertices[i]
			var distortion := 1.0 + .13*sin(p.x*7+variant)+.11*cos(p.z*6+variant*2)+.06*sin(p.y*9)
			vertices[i] = p*Vector3(1,.65,1.2)*distortion
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var initial := ArrayMesh.new()
		initial.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var st := SurfaceTool.new()
		st.create_from(initial,0)
		st.generate_normals()
		st.generate_tangents()
		var mesh := st.commit()
		mesh.surface_set_material(0,material)
		var rocks := MultiMeshInstance3D.new()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		var transforms: Array[Transform3D] = []
		var margins := field_half_size + Vector2(35.0, 35.0)
		for i in 180:
			var p := Vector2(rng.randf_range(-margins.x, margins.x), rng.randf_range(-margins.y, margins.y))
			if height_at(p) < .2:
				continue
			var large := i < (12 if generator.profile == MapGenerator.Profile.RIDGES else 4)
			if large and (absf(p.x) < generator.opening_half_width + 3.0 or not clear_for_scenery(p)):
				continue
			var size := rng.randf_range(1.0, 2.4) if large else rng.randf_range(.06, .24)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
			transforms.append(Transform3D(basis, ground_point(p, -.19 * size)))
			if large and absf(p.x) < field_half_size.x - 8.0 and absf(p.y) < field_half_size.y - 8.0:
				obstacles.append(Vector3(p.x, p.y, size * 1.15))
		multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i, transforms[i])
		rocks.multimesh = multi
		add_child(rocks)
