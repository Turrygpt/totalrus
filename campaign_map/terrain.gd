extends Node3D

const Geo = preload("res://campaign_map/geography.gd")
const State = preload("res://campaign_map/campaign_state.gd")
const Countryside = preload("res://campaign_map/countryside.gd")
const ConstructionScenery = preload("res://campaign_map/construction_scenery.gd")
const Woodland = preload("res://campaign_map/woodland.gd")
const SiegeEffects = preload("res://campaign_map/siege_effects.gd")
const HALF := Vector2(385, 321)*Geo.MAP_SCALE
const WATER_LEVEL := 2.5
const BANK_CLEARANCE := 0.10
const COLS := 961
const ROWS := 805
const GROUND_MESH := "res://assets/campaign/terrain_mesh.res"
# Bump when changing relief, shoreline, or vertex shading. Rebuild with --bake-campaign-ground.
const GROUND_BAKE_VERSION := 3
const PITCH := HALF*2.0 / Vector2(COLS-1,ROWS-1)
const RIVER_BUCKET := 32.0
const RIVER_REACH := 53.0
const ROAD_BUCKET := 12.0
const ROAD_SPEED := 1.30
const ROAD_PAINT_PITCH := 0.5
const ROAD_PAINT_RADIUS := 1.4
const DISTRICT_CLEARANCE := 4.8
const FISHING_SHORE_REACH := 30
const IZBA_MODELS := "res://assets/cinematic_log_cabin.glb"
const IZBAS_PER_HALL_LEVEL := 2
const MAX_IZBAS := 6
const RIVERS := [
	[7.3, [Vector2(395,-5), Vector2(283,-22), Vector2(200,-17), Vector2(110,-30), Vector2(68,-2), Vector2(8,15), Vector2(-16,37), Vector2(-29,84), Vector2(-65,112), Vector2(-65,150), Vector2(-93,181), Vector2(-84,208), Vector2(-58,235), Vector2(-75,259), Vector2(-111,331)]],
	[4.4, [Vector2(178,-84), Vector2(114,-80), Vector2(81,-68), Vector2(29,-65), Vector2(5,-51), Vector2(-53,-59), Vector2(-99,-57), Vector2(-160,-91), Vector2(-230,-100), Vector2(-394,-114)]],
	[3.5, [Vector2(28,-334), Vector2(44,-246), Vector2(59,-225), Vector2(48,-200), Vector2(49,-178), Vector2(65,-153), Vector2(78,-126), Vector2(100,-103), Vector2(91,-85), Vector2(80,-68)]],
	[4.1, [Vector2(394,75), Vector2(229,117), Vector2(148,129), Vector2(122,157), Vector2(82,168), Vector2(44,176), Vector2(14,184), Vector2(-15,210), Vector2(-78,212)]],
	[3.6, [Vector2(-400,167), Vector2(-230,157), Vector2(-179,137), Vector2(-141,146), Vector2(-105,137), Vector2(-65,147)]],
]
const LAKES := [
	[Vector2(27,-179), Vector2(23,11)],
	[Vector2(-131,-169), Vector2(13,21)],
	[Vector2(151,-112), Vector2(17,8)],
]
const BORDERS := [
	[Vector2(-385,-124), Vector2(-156,-118), Vector2(-111,-104), Vector2(-55,-104), Vector2(8,-89), Vector2(56,-92), Vector2(105,-87), Vector2(161,-85), Vector2(385,-96)],
	[Vector2(-385,-4), Vector2(-171,-10), Vector2(-114,-4), Vector2(-60,4), Vector2(-6,1), Vector2(47,4), Vector2(102,10), Vector2(164,15), Vector2(385,13)],
	[Vector2(-385,134), Vector2(-159,148), Vector2(-113,151), Vector2(-61,158), Vector2(-5,146), Vector2(46,137), Vector2(99,131), Vector2(162,131), Vector2(385,120)],
]
# Radius, long axis, rotation, and roof color for each settlement.
const TOWN_LAYOUTS := {
	"novgorod": [10.8, 1.27, -0.32, "#594634"],
	"russa": [5.8, 1.35, -0.48, "#604e43"],
	"kholm": [4.9, 1.16, 0.51, "#5c5542"],
	"polotsk": [6.8, 1.42, 0.62, "#604333"],
	"vitebsk": [5.8, 1.10, -0.51, "#5e4938"],
	"smolensk": [9.9, 1.16, 0.41, "#4b5246"],
	"orsha": [5.5, 1.34, 0.92, "#5d4a3f"],
	"mogilev": [5.9, 1.31, 0.06, "#5f4d3d"],
	"lyubech": [8.8, 1.12, -0.76, "#6b4f40"],
	"chernigov": [7.2, 1.32, -0.52, "#6d4938"],
	"kyiv": [11.5, 1.29, 0.31, "#6b4533"],
	"ladoga": [5.3, 1.2, 0.3, "#66513a"],
	"izborsk": [5.3, 1.2, 0.3, "#66513a"],
	"pskov": [5.3, 1.2, 0.3, "#66513a"],
	"north_pogost": [5.3, 1.2, 0.3, "#66513a"],
	"upper_volok": [5.3, 1.2, 0.3, "#66513a"],
	"toropets": [5.3, 1.2, 0.3, "#66513a"],
	"west_pogost": [5.3, 1.2, 0.3, "#66513a"],
	"berezina": [5.3, 1.2, 0.3, "#66513a"],
	"desna": [5.3, 1.2, 0.3, "#66513a"],
	"korosten": [5.3, 1.2, 0.3, "#66513a"],
	"pereyaslavl": [5.3, 1.2, 0.3, "#66513a"],
	"sula": [5.3, 1.2, 0.3, "#66513a"],
}

var countryside := Countryside.new()
var construction := ConstructionScenery.new()
var material_cache := {}
var box_cache := {}
var rng := RandomNumberGenerator.new()
var relief := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var woodland := FastNoiseLite.new()
var river_buckets: Dictionary[Vector2i, PackedInt32Array] = {}
var river_starts := PackedVector2Array()
var river_vectors := PackedVector2Array()
var river_inverse_length := PackedFloat32Array()
var river_widths := PackedFloat32Array()
var road_buckets: Dictionary[Vector2i, PackedVector2Array] = {}
var road_routes: Array[PackedVector2Array] = []
var town_pads: Array[Vector3] = []
var town_heights := {}
var terrain_grid := PackedVector3Array()
var settlements := {}
var fishing_shores: Dictionary[String,Vector4] = {}
var district_layouts := {}
var izba_meshes: Array[Mesh] = []
var siege_palisades: Dictionary[String, Node3D] = {}
var stone: StandardMaterial3D
var timber: Material
var bridge_material: StandardMaterial3D
var ground_material: ShaderMaterial
var water_material: ShaderMaterial

func _ready() -> void:
	rng.seed = 45280
	relief.seed = 812
	relief.frequency = 0.0068
	relief.fractal_octaves = 3
	relief.fractal_gain = 0.42
	detail.seed = 911
	detail.frequency = 0.058
	detail.fractal_octaves = 3
	woodland.seed = 2718
	woodland.frequency = 0.012
	woodland.fractal_octaves = 3
	woodland.fractal_gain = 0.46
	stone = material(Color("#8e8a70"))
	timber = wood_material(Color("#6d5743"))
	bridge_material = material(Color("#9b774f"))
	bridge_material.albedo_texture = bridge_plank_texture()
	index_rivers()
	for city in Geo.CITIES.values():
		var point: Vector2 = city[2]*Geo.MAP_SCALE
		town_heights[point] = natural_height(point)
		town_pads.append(Vector3(point.x,point.y,9.5 if city[3] else 6.5))
	create_ground()
	index_fishing_shores()
	create_water()
	var roads: Array[PackedVector2Array] = []
	for road in Geo.ROADS:
		var points := Geo.road_points(road)
		roads.append(points)
		index_road(points)
	countryside.build(self,roads)
	paint_roads(roads)
	create_landscape()
	batch_static_scenery(self)

func _process(_delta: float) -> void:
	load_visible_settlement()

func load_visible_settlement() -> void:
	if settlements.size() == Geo.CITIES.size(): return
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var bounds := get_viewport().get_visible_rect().grow(80)
	var closest := ""
	var distance := INF
	for id in Geo.CITIES:
		if settlements.has(id): continue
		var sites := PackedVector2Array([Geo.position_of(id)])
		if district_layouts.has(id):
			var layout: Array = district_layouts[id]
			if layout[0].has("farm"):
				if layout[2].get("farm",0) == State.FISHING_BRANCH and fishing_shores.has(id):
					var shore := fishing_shores[id]
					sites.append(Vector2(shore.x,shore.y))
				elif layout[0].farm == 1 and layout[2].get("farm",0) == 0 and countryside.farm_sites.has(id):
					sites.append(countryside.farm_sites[id])
		for site in sites:
			var at := surface(site,4.0)
			if camera.is_position_behind(at) or not bounds.has_point(camera.unproject_position(at)): continue
			var squared := camera.global_position.distance_squared_to(at)
			if squared < distance:
				distance = squared
				closest = id
	if closest.is_empty(): return
	create_city(closest)
	if district_layouts.has(closest):
		var layout: Array = district_layouts[closest]
		sync_district(closest,layout[0],layout[1],layout[2],layout[3])

func material(color: Color, unlit := false) -> StandardMaterial3D:
	var key := str(color)+str(unlit)
	if material_cache.has(key): return material_cache[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.93
	if unlit:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_cache[key] = result
	return result

func wood_material(color: Color, roof := false) -> ShaderMaterial:
	var key := "wood"+str(color)+str(roof)
	if material_cache.has(key): return material_cache[key]
	var result := ShaderMaterial.new()
	result.shader = preload("res://campaign_map/timber.gdshader")
	result.set_shader_parameter("tint",color)
	result.set_shader_parameter("roof",roof)
	material_cache[key] = result
	return result

func smooth_points(points: Array, steps: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		for j in steps:
			result.append(a.cubic_interpolate(points[i+1], points[maxi(0,i-1)], points[mini(points.size()-1,i+2)], float(j) / steps))
	result.append(points[-1])
	return result

func signed_water_distance(p: Vector2) -> float:
	p /= Geo.MAP_SCALE
	var closest := 40.0
	var variation := detail.get_noise_2dv(p * .55)
	var cell := Vector2i((p/RIVER_BUCKET).floor())
	if river_buckets.has(cell):
		var width_factor := .94 + .15 * variation
		var candidates: PackedInt32Array = river_buckets[cell]
		for i in candidates:
			var a := river_starts[i]
			var direction := river_vectors[i]
			if absf(a.x-p.x) > 41.0 or absf(a.y-p.y) > 41.0:
				continue
			var t := clampf((p-a).dot(direction)*river_inverse_length[i],0,1)
			closest = minf(closest,p.distance_to(a+direction*t)-river_widths[i]*width_factor)
	for lake in LAKES:
		var v: Vector2 = (p - lake[0]) / lake[1]
		var shore := (v.length()-1.0) * float(lake[1].y)
		closest = minf(closest, shore + variation*2.2)
	return closest*Geo.MAP_SCALE

func index_fishing_shores() -> void:
	for id in Geo.CITIES:
		var center := Geo.position_of(id)
		if signed_water_distance(center) > FISHING_SHORE_REACH+4: continue
		var shore := find_fishing_shore(id,center)
		if shore != Vector4.ZERO:
			fishing_shores[id] = shore

func find_fishing_shore(id: String, center: Vector2) -> Vector4:
	for distance in range(4,FISHING_SHORE_REACH+1,2):
		for i in 24:
			var direction := Vector2.from_angle(i*TAU/24.0)
			var bank := center+direction*distance
			if signed_water_distance(bank) > 5.0: continue
			var water := bank+direction*4.5
			var bank_height := surface(bank).y
			if bank_height > WATER_LEVEL+.25 and bank_height < WATER_LEVEL+2.6 and surface(water).y < WATER_LEVEL-.15:
				if Geo.region_at(bank-direction*2.0)==id and Geo.region_at(water)==id:
					return Vector4(bank.x,bank.y,direction.x,direction.y)
	return Vector4.ZERO

func index_rivers() -> void:
	for river in RIVERS:
		var points := smooth_points(river[1],9)
		for i in range(1,points.size()):
			var start := points[i-1]
			var direction := points[i]-start
			var index := river_starts.size()
			river_starts.append(start)
			river_vectors.append(direction)
			river_inverse_length.append(1.0/direction.length_squared())
			river_widths.append(river[0])
			var extent := Vector2.ONE*RIVER_REACH
			var low := Vector2i(((start-extent)/RIVER_BUCKET).floor())
			var high := Vector2i(((start+extent)/RIVER_BUCKET).floor())
			for y in range(low.y,high.y+1):
				for x in range(low.x,high.x+1):
					var cell := Vector2i(x,y)
					var candidates: PackedInt32Array = river_buckets.get(cell,PackedInt32Array())
					candidates.append(index)
					river_buckets[cell] = candidates

func relief_height(p: Vector2) -> float:
	var upland := smoothstep(94.0,348.0,absf(p.x+27.0*sin(p.y/85.0)))
	var hills := smoothstep(-.48,.65,relief.get_noise_2dv(p))*(8.0+25.0*upland)
	var drumlins := relief.get_noise_2d(p.x*1.95+419.0,p.y*1.15)*(2.7+upland*5.5)
	return 5.2+hills+drumlins+detail.get_noise_2dv(p)*(1.0+1.5*upland)

func natural_height(p: Vector2) -> float:
	var bank := signed_water_distance(p)
	var small := detail.get_noise_2dv(p)
	var upland := smoothstep(94.0,348.0,absf(p.x+27.0*sin(p.y/85.0)))
	var base := relief_height(p)
	var floodplain := 3.15+.55*small
	var slope := lerpf(floodplain,maxf(4.0,base),smoothstep(0.0,26.0+upland*16.0,bank))
	return lerpf(-1.15,slope,smoothstep(-8.0,2.4,bank))

func height_at(p: Vector2) -> float:
	var height := natural_height(p)
	for pad in town_pads:
		var center := Vector2(pad.x,pad.y)
		var distance_squared := p.distance_squared_to(center)
		var outer := pad.z+16.0
		if distance_squared < outer*outer:
			var blend := (1.0-smoothstep(pad.z,outer,sqrt(distance_squared)))*smoothstep(.2,3.0,signed_water_distance(p))
			height = lerpf(height,town_heights[center],blend)
	return height

func forest_cover(p: Vector2) -> float:
	var mass := woodland.get_noise_2dv(p)
	var edge := detail.get_noise_2dv(p) * 0.19
	return smoothstep(-0.20, 0.29, mass + edge)

func surface(p: Vector2, lift := 0.0) -> Vector3:
	var height := height_at(p) if terrain_grid.is_empty() else sample_surface_height(terrain_grid,p)
	return Vector3(p.x,height+lift,p.y)

static func sample_surface_height(grid: PackedVector3Array, p: Vector2) -> float:
	var cell := (p+HALF)/PITCH
	var x := clampi(floori(cell.x),0,COLS-2)
	var z := clampi(floori(cell.y),0,ROWS-2)
	var u := clampf(cell.x-x,0,1)
	var v := clampf(cell.y-z,0,1)
	var i := z*COLS+x
	var a := grid[i].y
	var b := grid[i+1].y
	var c := grid[i+COLS].y
	var d := grid[i+COLS+1].y
	return a+(b-a)*u+(c-a)*v if u+v <= 1.0 else d+(c-d)*(1.0-u)+(b-d)*(1.0-v)

func province_at(p: Vector2) -> int:
	return Geo.CITIES[Geo.region_at(p)][1]

func ground_signature() -> int:
	var towns := []
	for city in Geo.CITIES.values():
		towns.append([city[1],city[2],city[3]])
	var province_colors := []
	for province in Geo.PROVINCES:
		province_colors.append(province[2])
	return hash([
		GROUND_BAKE_VERSION, COLS, ROWS, HALF, WATER_LEVEL,
		RIVER_BUCKET, RIVER_REACH, RIVERS, LAKES, towns, province_colors,
	])

func create_ground() -> void:
	var signature := ground_signature()
	var bake_requested := "--bake-campaign-ground" in OS.get_cmdline_user_args()
	var mesh: ArrayMesh
	if not bake_requested and ResourceLoader.exists(GROUND_MESH):
		mesh = load(GROUND_MESH) as ArrayMesh
		if mesh and mesh.get_surface_count() == 1 and mesh.get_meta("geometry_signature",0) == signature:
			terrain_grid = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		if terrain_grid.size() != COLS*ROWS:
			mesh = null
			terrain_grid.clear()
	if mesh == null:
		mesh = bake_ground_mesh()
		mesh.set_meta("geometry_signature",signature)
		if bake_requested:
			var result := ResourceSaver.save(mesh,GROUND_MESH,ResourceSaver.FLAG_COMPRESS)
			if result != OK: push_error("Could not save campaign ground mesh: %s" % error_string(result))
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://campaign_map/ground.gdshader")
	ground_material = mat
	mat.set_shader_parameter("grass", preload("res://assets/terrain/grass_color.jpg"))
	mat.set_shader_parameter("rock", preload("res://assets/terrain/rock_color.jpg"))
	mat.set_shader_parameter("grass_normal", preload("res://assets/terrain/grass_normalgl.jpg"))
	mat.set_shader_parameter("rock_normal", preload("res://assets/terrain/rock_normalgl.jpg"))
	mat.set_shader_parameter("grass_roughness", preload("res://assets/terrain/grass_roughness.jpg"))
	mat.set_shader_parameter("rock_roughness", preload("res://assets/terrain/rock_roughness.jpg"))
	place_mesh(mesh, Vector3.ZERO).material_override = mat

func bake_ground_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(COLS*ROWS)
	normals.resize(COLS*ROWS)
	colors.resize(COLS*ROWS)
	for z in ROWS:
		for x in COLS:
			var p := Vector2(x,z)*PITCH-HALF
			var i := z*COLS+x
			vertices[i] = surface(p)
			var coverage := forest_cover(p)
			var heath := smoothstep(-0.31,0.51,detail.get_noise_2dv(p))
			var shade := Color("#69764b").lerp(Color("#a29663"),heath)
			shade = shade.lerp(Color("#39472d"),pow(coverage,.85)*0.86)
			shade = shade.lerp(Geo.PROVINCES[province_at(p)][2],0.077)
			var shore := 1.0-smoothstep(WATER_LEVEL+0.25,WATER_LEVEL+1.9,vertices[i].y)
			shade = shade.lerp(Color("#777454"),shore*0.72)
			shade.a = 0.0
			for pad in town_pads:
				var distance := p.distance_to(Vector2(pad.x,pad.y))
				if distance < pad.z+4.0: shade.a = maxf(shade.a,1.0-smoothstep(pad.z-1.0,pad.z+4.0,distance))
			colors[i] = shade
			if x < COLS-1 and z < ROWS-1:
				indices.append_array(PackedInt32Array([i, i+1, i+COLS, i+1, i+COLS+1, i+COLS]))
	for z in ROWS:
		for x in COLS:
			var east := vertices[z*COLS+mini(COLS-1,x+1)] - vertices[z*COLS+maxi(0,x-1)]
			var south := vertices[mini(ROWS-1,z+1)*COLS+x] - vertices[maxi(0,z-1)*COLS+x]
			normals[z*COLS+x] = south.cross(east).normalized()
	var arrays := []
	terrain_grid = vertices
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func create_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = HALF*2.0
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://campaign_map/water.gdshader")
	water_material = mat
	plane.material = mat
	place_mesh(plane, Vector3(0,WATER_LEVEL,0))

func place_mesh(mesh: Mesh, p: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)
	instance.position = p
	return instance

func paint_roads(roads: Array[PackedVector2Array]) -> void:
	var size := Vector2i(HALF*2.0/ROAD_PAINT_PITCH)
	var paint := PackedByteArray()
	paint.resize(size.x*size.y)
	for points in roads:
		for i in range(1,points.size()):
			paint_road_segment(paint,size,points[i-1],points[i],ROAD_PAINT_RADIUS)
	for lane in countryside.lanes:
		paint_road_segment(paint,size,lane[0],lane[1],.65)
	var image := Image.create_from_data(size.x,size.y,false,Image.FORMAT_L8,paint)
	image.generate_mipmaps()
	ground_material.set_shader_parameter("road_paint",ImageTexture.create_from_image(image))

func paint_road_segment(paint: PackedByteArray, size: Vector2i, a: Vector2, b: Vector2, radius: float) -> void:
	var extent := Vector2.ONE*radius
	var low := Vector2i(((a.min(b)-extent+HALF)/ROAD_PAINT_PITCH).floor()).max(Vector2i.ZERO)
	var high := Vector2i(((a.max(b)+extent+HALF)/ROAD_PAINT_PITCH).ceil()).min(size-Vector2i.ONE)
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var p := (Vector2(x,y)+Vector2(0.5,0.5))*ROAD_PAINT_PITCH-HALF
			var nearest := Geometry2D.get_closest_point_to_segment(p,a,b)
			var coverage := 1.0-smoothstep(0.45,radius,p.distance_to(nearest))
			var pixel := y*size.x+x
			paint[pixel] = maxi(paint[pixel],roundi(coverage*255.0))

func index_road(points: PackedVector2Array) -> void:
	var samples := PackedVector2Array([points[0]])
	for i in range(1,points.size()):
		var divisions := ceili(points[i-1].distance_to(points[i])/0.85)
		for j in range(1,divisions+1):
			samples.append(points[i-1].lerp(points[i],float(j)/divisions))
	road_routes.append(samples)
	for point in samples:
		var extent := Vector2.ONE*5.2
		var low := Vector2i(((point-extent)/ROAD_BUCKET).floor())
		var high := Vector2i(((point+extent)/ROAD_BUCKET).floor())
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var cell := Vector2i(x,y)
				var candidates: PackedVector2Array = road_buckets.get(cell,PackedVector2Array())
				candidates.append(point)
				road_buckets[cell] = candidates
	var bank := -1
	for i in samples.size():
		if surface(samples[i]).y <= WATER_LEVEL+BANK_CLEARANCE:
			continue
		if bank >= 0 and i-bank > 1:
			create_bridge(samples.slice(bank,i+1))
		bank = i

func bridge_plank_texture() -> ImageTexture:
	var strip := Image.create(32,128,true,Image.FORMAT_RGB8)
	for y in 128:
		var board := y / 16
		for x in 32:
			var grain := sin(x*.4 + y*.8) * .026
			var joint := .55 if y % 16 == 0 else 1.0
			var edge := .64 if x < 2 or x >= 30 else 1.0
			var tone := (.82 + sin(board*5.7)*.12 + grain) * joint * edge
			strip.set_pixel(x,y,Color(tone,tone,tone))
	strip.generate_mipmaps()
	return ImageTexture.create_from_image(strip)

func create_bridge(points: PackedVector2Array) -> void:
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	deck.set_material(bridge_material)
	var distance := 0.0
	for i in points.size():
		if i > 0: distance += points[i].distance_to(points[i-1])
		var tangent := points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]
		var side := Vector2(-tangent.y,tangent.x).normalized()*1.25
		var height := maxf(surface(points[i]).y+0.06,WATER_LEVEL+0.55)
		for side_index in 2:
			var edge: Vector2 = points[i]+side if side_index == 0 else points[i]-side
			deck.set_normal(Vector3.UP)
			deck.set_uv(Vector2(side_index,distance/5.6))
			deck.add_vertex(Vector3(edge.x,height,edge.y))
	place_mesh(deck.commit(),Vector3.ZERO)

func movement_cost(point: Vector2, road_radius := 5.0) -> float:
	var cell := Vector2i((point/ROAD_BUCKET).floor())
	if road_buckets.has(cell):
		for sample in road_buckets[cell]:
			if point.distance_squared_to(sample) <= road_radius*road_radius:
				return 1.0/ROAD_SPEED
	return 1.0

func box(size: Vector3, mat: Material, p: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var key := mat.get_instance_id()
	if not box_cache.has(key):
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = mat
		box_cache[key] = mesh
	var instance := place_mesh(box_cache[key],p,parent)
	instance.scale = size
	return instance

func batch_static_scenery(parent: Node3D) -> void:
	var groups := {}
	for node in parent.find_children("*","MeshInstance3D",true,false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or mesh_node.material_override != null: continue
		var cell := Vector2i(floori(mesh_node.global_position.x/90.0),floori(mesh_node.global_position.z/90.0))
		var key := str(mesh_node.mesh.get_rid())+str(cell)
		if not groups.has(key): groups[key] = []
		groups[key].append(mesh_node)
	for nodes: Array in groups.values():
		if nodes.size()<2: continue
		var first := nodes[0] as MeshInstance3D
		var data := MultiMesh.new()
		data.transform_format = MultiMesh.TRANSFORM_3D
		data.mesh = first.mesh
		data.instance_count = nodes.size()
		for i in nodes.size():
			data.set_instance_transform(i,parent.global_transform.affine_inverse()*nodes[i].global_transform)
			nodes[i].hide()
			nodes[i].queue_free()
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = data
		parent.add_child(instance)

func create_city(id: String) -> void:
	var p := Geo.position_of(id)
	var layout: Array = TOWN_LAYOUTS[id]
	var radius: float = layout[0]
	var settlement := Node3D.new()
	settlements[id] = settlement
	add_child(settlement)
	settlement.position = surface(p)
	settlement.rotation.y = layout[2]
	# Timber boardwalks lead through the settlement to the gate site.
	for step in range(-int(radius*.7),int(radius*.87)):
		var at := settlement.to_global(Vector3(0,0,step*.9))
		if surface(Vector2(at.x,at.z)).y <= WATER_LEVEL+.12: continue
		var plank := settlement.to_local(surface(Vector2(at.x,at.z),.01))
		box(Vector3(1.35,.09,.28),wood_material(Color("#827459")),plank,settlement)
	batch_static_scenery(settlement)

func tower(parent: Node3D, at: Vector3, width: float, height: float, tiles: Material) -> void:
	box(Vector3(width,height,width), timber, at+Vector3.UP*(height*0.5+0.2),parent)
	var trim := wood_material(Color("#514233"))
	for side in [-1.0,1.0]:
		for axis in [-1.0,1.0]:
			box(Vector3(.19,height+.15,.19),trim,at+Vector3(side*width*.48,height*.5+.2,axis*width*.48),parent)
		for slit in [-.24,.24]:
			box(Vector3(width*.13,.55,.04),material(Color("#25271e")),at+Vector3(slit*width,height-.8,side*(width*.5+.02)),parent)
	box(Vector3(width*1.12,.18,width*1.12),trim,at+Vector3.UP*(height+.13),parent)
	var pyramid := CylinderMesh.new()
	pyramid.radial_segments = 4
	pyramid.top_radius = 0.04
	pyramid.bottom_radius = width*0.89
	pyramid.height = width*0.82
	pyramid.material = tiles
	var covering := place_mesh(pyramid,at+Vector3.UP*(height+pyramid.height*0.5+0.2),parent)
	covering.rotation_degrees.y = 45.0

func hall(parent: Node3D, roof_color: Color, size: float, level: int, damaged: bool) -> void:
	var tiles := wood_material(roof_color.darkened(.55) if damaged else roof_color,true)
	box(Vector3(5.7,3.3,3.5)*size, timber,Vector3.UP*1.9*size,parent)
	if level >= 3:
		box(Vector3(5.9,.75,3.7)*size,stone,Vector3.UP*.4*size,parent)
	var trim := wood_material(Color("#493d2e"))
	for side in [-1.0,1.0]:
		for post in [-2.75,0.,2.75]:
			box(Vector3(.17,3.4,.18)*size,trim,Vector3(post,1.9,side*1.76)*size,parent)
		for window in [-1.8,1.8]:
			box(Vector3(.63,.80,.10)*size,trim,Vector3(window,2.25,side*1.79)*size,parent)
			box(Vector3(.42,.59,.12)*size,material(Color("#282b22")),Vector3(window,2.25,side*1.81)*size,parent)
	for side in [-1,1]:
		if damaged and side == 1: continue
		var slope := box(Vector3(6.05,0.24,2.54)*size,tiles,Vector3(0,4.16,side*1.06)*size,parent)
		slope.rotation.x = side*0.61
	if level >= 3:
		tower(parent,Vector3(0,3.2,-.5)*size,1.45*size,1.55*size,tiles)
	box(Vector3(2.2,1.8,0.75)*size,timber,Vector3(0,1.23,2.07)*size,parent)
	box(Vector3(.82,1.47,.10)*size,trim,Vector3(0,1.05,2.5)*size,parent)
	if level >= 2:
		for side in [-1,1]:
			box(Vector3(.22,2.15,.22)*size,trim,Vector3(side*1.17,1.12,2.87)*size,parent)
		if not damaged:
			box(Vector3(2.75,.19,1.57)*size,tiles,Vector3(0,2.23,2.55)*size,parent)
	for step in 3:
		box(Vector3(1.5,.18,.35)*size,wood_material(Color("#8b7959")),Vector3(0,.12+step*.13,3.2-step*.31)*size,parent)

func city_wall_corners(layout: Array, capital: bool) -> PackedVector2Array:
	var sides := 10 if capital else 8
	var corners := PackedVector2Array()
	var radius: float = layout[0]*.92
	for i in sides:
		var angle := TAU*(i-.5)/sides
		corners.append(Vector2(sin(angle)*float(layout[1]),cos(angle))*radius)
	return corners

func build_city_walls(parent: Node3D, layout: Array, level: int, damaged: bool, capital: bool) -> void:
	var perimeter := city_wall_corners(layout,capital)
	var sides := perimeter.size()
	var corners := PackedVector3Array()
	var tiles := wood_material(Color(layout[3]),true)
	var posts: Array[Transform3D] = []
	for corner in perimeter:
		var at := Vector3(corner.x,0,corner.y)
		var world_at := parent.to_global(at)
		at.y += surface(Vector2(world_at.x,world_at.z)).y-world_at.y
		corners.append(at)
	var gate_a := corners[0].lerp(corners[1],.18)
	var gate_b := corners[0].lerp(corners[1],.82)
	var gate_width := 1.35+level*.35
	for at in [gate_a,gate_b]:
		tower(parent,at,gate_width,2.3+level*.8,tiles)
	wall_section(parent,corners[0],gate_a,level,posts)
	wall_section(parent,gate_b,corners[1],level,posts)
	var lintel := box(Vector3(.9,.45,gate_a.distance_to(gate_b)),timber,(gate_a+gate_b)*.5+Vector3.UP*(1.55+level*.45),parent)
	lintel.rotation.y = atan2(gate_b.x-gate_a.x,gate_b.z-gate_a.z)
	for i in range(1,sides):
		if damaged and (i == sides/2 or i == sides/2+1): continue
		wall_section(parent,corners[i],corners[(i+1)%sides],level,posts)
		if level >= 2 and i%2 == 0:
			tower(parent,corners[i],gate_width*.9,2.0+level*.85,tiles)
	var post := CylinderMesh.new()
	post.top_radius = 0.13
	post.bottom_radius = 0.30
	post.height = 1.0
	post.radial_segments = 6
	post.material = timber
	batch(post,posts,false,parent)

func wall_section(parent: Node3D, a: Vector3, b: Vector3, level: int, posts: Array[Transform3D]) -> void:
	var center := (a+b)*.5
	var length := a.distance_to(b)
	var yaw := atan2(b.x-a.x,b.z-a.z)
	var height := 1.4+level*.65
	if level >= 2:
		var masonry_height := height if level == 3 else .65
		var masonry := box(Vector3(1.05,masonry_height+.35,length+.15),stone,center+Vector3.UP*(masonry_height*.5-.12),parent)
		masonry.rotation.y = yaw
		masonry.rotation.x = -atan2(b.y-a.y,Vector2(b.x-a.x,b.z-a.z).length())
	if level == 3:
		var count := maxi(1,floori(length/1.1))
		for i in count:
			var merlon := box(Vector3(1.05,.55,.66),stone,a.lerp(b,(i+.5)/count)+Vector3.UP*(height+.28),parent)
			merlon.rotation.y = yaw
		return
	var count := ceili(length/.43)
	for i in count:
		var post_height := height+.14*sin(i*2.1)
		var point := a.lerp(b,(i+.5)/count)+Vector3.UP*(post_height*.5-.1)
		posts.append(Transform3D(Basis.from_scale(Vector3(1,post_height,1)),point))

func sync_sieges(cities: Dictionary) -> void:
	for id in siege_palisades.keys():
		if id in cities: continue
		var palisade := siege_palisades[id]
		palisade.hide()
		palisade.queue_free()
		siege_palisades.erase(id)
	for id in cities:
		if not siege_palisades.has(id):
			siege_palisades[id] = create_siege_palisade(id)
		var effects := siege_palisades[id].get_node("Effects") as SiegeEffects
		effects.set_turns(cities[id])

func create_siege_palisade(id: String) -> Node3D:
	var layout: Array = TOWN_LAYOUTS[id]
	var center := Geo.position_of(id)
	var axes := Vector2(layout[0]*layout[1]+8.5,layout[0]+8.5)
	var count := ceili(TAU*(axes.x+axes.y)*.5/2.3)
	var shafts: Array[Transform3D] = []
	var points: Array[Transform3D] = []
	var bindings: Array[Transform3D] = []
	for i in count:
		var angle := TAU*i/count
		var offset := (Vector2.from_angle(angle)*axes).rotated(-float(layout[2]))
		var ground := surface(center+offset)
		if ground.y <= WATER_LEVEL: continue
		var inward := Vector3(-offset.x,0,-offset.y).normalized()
		var up := (Vector3.UP+inward*.14).normalized()
		var right := up.cross(inward).normalized()
		var basis := Basis(right,up,right.cross(up))
		var height := 4.7+.44*sin(i*2.4)
		shafts.append(Transform3D(basis.scaled_local(Vector3(1,height,1)),ground+up*(height*.5-.15)))
		var shoulder := ground+up*(height+.37)
		points.append(Transform3D(basis.scaled_local(Vector3(1,1.15,.52)),shoulder+up*.575))
		var reversed := basis.rotated(right,PI)
		points.append(Transform3D(reversed.scaled_local(Vector3(1,.58,.52)),shoulder-up*.29))
		if i%4 == 0:
			bindings.append(Transform3D(basis,ground+up*(height-.54)))
	var palisade := Node3D.new()
	palisade.name = "SiegePalisade_"+id
	add_child(palisade)
	var effects := SiegeEffects.new()
	effects.name = "Effects"
	for offset: Vector2 in [Vector2(.1,-.12),Vector2(-.43,.28),Vector2(.44,.33),Vector2(.41,-.44)]:
		var point := center+(offset*float(layout[0])).rotated(-float(layout[2]))
		effects.sites.append(surface(point,2.15 if effects.sites.is_empty() else 1.7))
	palisade.add_child(effects)
	var shaft := CylinderMesh.new()
	shaft.top_radius = .21
	shaft.bottom_radius = .28
	shaft.height = 1.0
	shaft.radial_segments = 6
	shaft.material = wood_material(Color("78523a"))
	batch(shaft,shafts,false,palisade)
	var point := CylinderMesh.new()
	point.top_radius = 0.0
	point.bottom_radius = .62
	point.height = 1.0
	point.radial_segments = 4
	point.material = material(Color("c2c5bb"))
	batch(point,points,false,palisade)
	var binding := CylinderMesh.new()
	binding.top_radius = .28
	binding.bottom_radius = .28
	binding.height = .64
	binding.radial_segments = 6
	binding.material = material(Color("a14637"))
	batch(binding,bindings,false,palisade)
	return palisade

func create_landscape() -> void:
	var trees := [[],[],[],[]]
	var boulder := SphereMesh.new()
	boulder.radial_segments = 6
	boulder.rings = 3
	boulder.material = stone
	var rocks: Array[Transform3D] = []
	var settlement_buffers: Array[Vector4] = []
	var camps := PackedVector2Array()
	for id in Geo.CITIES:
		var position := Geo.position_of(id)
		var buffer: float = TOWN_LAYOUTS[id][0]*TOWN_LAYOUTS[id][1]+DISTRICT_CLEARANCE+4.0
		settlement_buffers.append(Vector4(position.x,position.y,buffer*buffer,0.0))
		camps.append(Geo.camp_position(id))
	const SPACING := 3.8
	var cols := floori((HALF.x*2.0-8.0)/SPACING)
	var rows := floori((HALF.y*2.0-8.0)/SPACING)
	for i in cols*rows:
		var cell := Vector2(i%cols,floori(float(i)/cols))
		var jitter := Vector2(rng.randf_range(0.04,0.96),rng.randf_range(0.04,0.96))
		var p := (cell+jitter)*SPACING-HALF+Vector2(4,4)
		if countryside.is_clearing(p): continue
		var canopy := forest_cover(p)
		if rng.randf() > lerpf(0.006,0.96,smoothstep(.10,.75,canopy)):
			continue
		var at := surface(p)
		if at.y < WATER_LEVEL+0.64 or signed_water_distance(p) < 2.6:
			continue
		var clear := true
		for j in settlement_buffers.size():
			var buffer := settlement_buffers[j]
			if p.distance_squared_to(Vector2(buffer.x,buffer.y)) < buffer.z or p.distance_squared_to(camps[j]) < 53.0:
				clear = false
				break
		if not clear:
			continue
		var road_cell := Vector2i((p/ROAD_BUCKET).floor())
		if road_buckets.has(road_cell):
			for point in road_buckets[road_cell]:
				if p.distance_squared_to(point) < 10.5:
					clear = false
					break
		if not clear:
			continue
		var s := rng.randf_range(0.78,1.48)
		var spin := Basis(Vector3.UP,rng.randf_range(0,TAU))
		if rng.randf() < 0.012:
			rocks.append(Transform3D(spin.scaled(Vector3(2.4,1.25,1.7)*s),at+Vector3.UP*s*0.25))
			continue
		var conifers := lerpf(.65,.19,smoothstep(-300.0,300.0,p.y))
		var kind := (2 if rng.randf() < .7 else 3) if rng.randf() < conifers else (1 if rng.randf() < .42 else 0)
		trees[kind].append(Transform3D(spin.scaled(Vector3(s,s*rng.randf_range(.9,1.2),s)),at))
	Woodland.plant(self,trees)
	batch(boulder,rocks)

func batch(mesh: Mesh, transforms: Array[Transform3D], colored := false, parent: Node3D = self) -> void:
	if transforms.is_empty(): return
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.use_colors = colored
	data.mesh = mesh
	data.instance_count = transforms.size()
	for i in transforms.size():
		data.set_instance_transform(i,transforms[i])
		if colored:
			var tint := rng.randf_range(0.68,1.18)
			data.set_instance_color(i,Color(tint,tint,rng.randf_range(0.76,1.10)))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = data
	parent.add_child(instance)


var district_nodes := {}
var district_keys := {}
var props := {}

func district_prop(id: String, parent: Node3D, level: int, base_scale := 1.0) -> Node3D:
	if not props.has(id):
		var path := "res://assets/campaign/%s.glb" % id
		props[id] = load(path) if ResourceLoader.exists(path,"PackedScene") else null
	if props[id] == null: return null
	var prop: Node3D = props[id].instantiate()
	parent.add_child(prop)
	prop.scale *= base_scale*(1.0+.2*(level-2))
	return prop

func building_location(id: String, key: String, branch := 0) -> Vector2:
	var center := Geo.position_of(id)
	var layout: Array = TOWN_LAYOUTS[id]
	if key == "farm" and branch == State.FISHING_BRANCH and fishing_shores.has(id):
		var shore := fishing_shores[id]
		return Vector2(shore.x,shore.y)
	if State.SPECIAL_BUILDINGS.has(key):
		# Site the local workshop just outside the walls, on the dry side.
		for direction: Vector2 in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
			var offset := (direction*Vector2(layout[1],1.0)*float(layout[0])*1.35).rotated(-float(layout[2]))
			var site := center+offset
			if signed_water_distance(site) > 3.0:
				return site
		return center+Vector2(0,float(layout[0])*.43).rotated(-float(layout[2]))
	var offset := ConstructionScenery.city_offset(key,layout[0],layout[1])
	return center+offset.rotated(-float(layout[2]))

func sync_district(id: String, buildings: Dictionary, damage: Dictionary, branches: Dictionary, owner_color: Color) -> void:
	var signature := hash([buildings,damage,branches,owner_color])
	if district_keys.get(id,-1) == signature:
		return
	if not settlements.has(id):
		district_layouts[id] = [buildings,damage,branches,owner_color]
		return
	district_layouts.erase(id)
	district_keys[id] = signature
	if district_nodes.has(id):
		var previous: Node3D = district_nodes[id]
		previous.get_parent().remove_child(previous)
		previous.queue_free()
	var settlement: Node3D = settlements[id]
	var district := Node3D.new()
	district.name = "Buildings"
	settlement.add_child(district)
	district_nodes[id] = district
	var center := Geo.position_of(id)
	var layout: Array = TOWN_LAYOUTS[id]
	var radius: float = layout[0]
	var capital: bool = Geo.CITIES[id][3]
	var hall_level: int = buildings.get("hall",0)
	if hall_level > 0:
		var hall_size := (.88 if capital else .58)+.12*(hall_level-1)
		var court := Node3D.new()
		court.name = "Hall"
		district.add_child(court)
		if not damage.has("hall") and construction.place(court,"hall",hall_level,hall_size):
			ground_building(court,Vector2(4.5,3.6)*hall_size,stone)
		else:
			hall(court,Color(layout[3]),hall_size,hall_level,damage.has("hall"))
			batch_static_scenery(court)
		place_city_izbas(district,layout,mini(hall_level*IZBAS_PER_HALL_LEVEL,MAX_IZBAS),hash(id))
	var wall_level: int = buildings.get("wall",0)
	if wall_level > 0:
		var walls := Node3D.new()
		walls.name = "Wall"
		district.add_child(walls)
		build_city_walls(walls,layout,wall_level,damage.has("wall"),capital)
		batch_static_scenery(walls)
	var flag := district.to_local(surface(center+Vector2(radius*float(layout[1])+1,-2),0.25))
	box(Vector3(0.16,7.8,0.16),timber,flag+Vector3.UP*3.9,district)
	box(Vector3(3.45,2.45,.12),material(owner_color),flag+Vector3(-1.65,6.31,0),district)
	var names := ["farm","market","warehouse","forge","barracks","range","stables","shrine"]
	var colors := ["b49052","9f664f","916842","51545a","614735","b19b69","745940","b2a58b"]
	names.append(State.local_special_building(id))
	colors.append("9d7955")
	for i in names.size():
		var kind: String = names[i]
		var level: int = buildings.get(kind,0)
		if level == 0:
			continue
		var building := Node3D.new()
		building.name = kind.capitalize()
		district.add_child(building)
		var tint := Color(colors[i])
		var damaged := damage.has(kind)
		var prop := material(tint.darkened(.68) if damaged else tint)
		var branch: int = branches.get(kind,0)
		if kind == "farm" and branch == State.FISHING_BRANCH and fishing_shores.has(id):
			build_fishery(building,fishing_shores[id],level,prop,damaged)
			batch_static_scenery(building)
			if not damaged: launch_fishing_boat(building,fishing_shores[id])
			continue
		if kind == "farm" and level == 1 and branch == 0:
			add_crop_field(district,id,damaged)
		var site := building_location(id,kind,branch)
		var facing := center-site
		building.global_position = surface(site)
		building.global_rotation.y = atan2(facing.x,facing.y)
		building.scale = Vector3.ONE*clampf(radius*.073,.35,.82)
		var model_key := kind
		if kind == "farm" and branch == State.HUNTING_BRANCH:
			model_key = "lodge"
		elif State.SPECIAL_BUILDINGS.has(kind):
			model_key = "warehouse"
			if kind in ["saltworks","bloomery","pottery"]: model_key = "forge"
			if kind in ["apiary","threshing_yard"]: model_key = "farm"
		if not damaged:
			var model := construction.place(building,model_key,level)
			if model:
				var bounds := model.mesh.get_aabb().size
				ground_building(building,Vector2(bounds.x,bounds.z)*.84,stone)
				continue
		build_district_prop(building,model_key if State.SPECIAL_BUILDINGS.has(kind) else kind,level,prop,damaged)
		batch_static_scenery(building)

func place_city_izbas(district: Node3D, layout: Array, count: int, variant_seed: int) -> void:
	if izba_meshes.is_empty():
		var models := (load(IZBA_MODELS) as PackedScene).instantiate()
		for child in models.get_children():
			if child is MeshInstance3D: izba_meshes.append(child.mesh)
		models.free()
	var houses := Node3D.new()
	houses.name = "Izbas"
	district.add_child(houses)
	var radius: float = layout[0]
	var stretch: float = layout[1]
	const ROWS := [0.0, -0.38, 0.38]
	for i in count:
		var side := -1.0 if i%2 == 0 else 1.0
		var offset := Vector3(side*radius*stretch*.43,0,radius*ROWS[i >> 1])
		var house := MeshInstance3D.new()
		house.name = "Izba%d" % (i+1)
		house.mesh = izba_meshes[posmod(i+variant_seed,izba_meshes.size())]
		house.position = offset
		house.rotation.y = side*PI*.5
		house.scale = Vector3.ONE*clampf(radius*.05,.24,.52)
		houses.add_child(house)
		var size := house.mesh.get_aabb().size
		ground_building(house,Vector2(size.x,size.z)*.78,stone)

func build_district_prop(parent: Node3D, kind: String, level: int, roof_material: Material, damaged: bool) -> void:
	match kind:
		"range":
			var targets := 2+level
			box(Vector3(targets*1.5,1.1,.23),timber,Vector3(0,.55,-.9),parent)
			if level >= 2:
				box(Vector3(targets*1.35,.18,1.05),timber,Vector3(0,.11,2.25),parent)
			if level == 3:
				for side in [-1,1]:
					box(Vector3(.14,.68,2.85),timber,Vector3(side*targets*.69,.36,1.45),parent)
			for target in targets:
				var stand := Vector3((target-(targets-1)*.5)*1.5,0,.2)
				box(Vector3(.17,1.15,.17),timber,stand+Vector3.UP*.57,parent)
				box(Vector3(.82,.85,.18),roof_material,stand+Vector3.UP*1.05,parent)
			return
		"market":
			var stalls := level+1
			for stall in stalls:
				var x := (stall-(stalls-1)*.5)*1.55
				market_stall(parent,Vector3(x,0,0),roof_material,-1)
				if level == 3:
					market_stall(parent,Vector3(x,0,2.9),roof_material,1)
			if level >= 2:
				box(Vector3(stalls*1.53,.12,1.55),timber,Vector3(0,.08,1.35),parent)
			return
		"shrine":
			tower(parent,Vector3.ZERO,1.6+level*.23,1.6+level*.7,roof_material)
			if level >= 2:
				box(Vector3(2.4,.25,2.4),stone,Vector3(0,.13,0),parent)
			if level == 3:
				for side in [-1,1]:
					tower(parent,Vector3(side*1.8,0,0),.95,1.7,roof_material)
			return
	var height := 1.45+level*.48
	var width := (4.35 if kind in ["stables","barracks"] else 2.7)+level*.3
	box(Vector3(width,height,2.5),timber,Vector3.UP*height*.5,parent)
	for side in [-1,1]:
		if damaged and side == 1: continue
		var roof := box(Vector3(width+.38,.19,1.58),roof_material,Vector3(0,height+.35,side*.66),parent)
		roof.rotation.x = side*.46
	match kind:
		"forge":
			box(Vector3(.78,height+1.3,.78),stone,Vector3(-width*.37,(height+1.3)*.5,-.65),parent)
			box(Vector3(.88,.17,.88),material(Color("#383431")),Vector3(-width*.37,height+1.3,-.65),parent)
			box(Vector3(.78,.65,.58),material(Color("#51545a")),Vector3(.58,.33,1.8),parent)
			if level >= 2:
				box(Vector3(.63,height+.85,.65),stone,Vector3(width*.27,(height+.85)*.5,-.5),parent)
			if level == 3:
				box(Vector3(2.3,.23,1.9),roof_material,Vector3(-.5,height*.8,1.95),parent)
				for x in [-1.5,.5]:
					box(Vector3(.17,height*.8,.17),timber,Vector3(x,height*.4,2.75),parent)
		"stables":
			for rail in 2:
				box(Vector3(width,.13,.13),timber,Vector3(0,.44+rail*.44,3.1),parent)
			for post in 3:
				box(Vector3(.16,1.16,.16),timber,Vector3((post-1)*width*.5,.58,3.1),parent)
			if level >= 2:
				for side in [-1,1]:
					box(Vector3(.14,.46,1.8),timber,Vector3(side*width*.5,.65,2.2),parent)
			if level == 3:
				box(Vector3(.15,.52,1.8),timber,Vector3(0,.61,2.2),parent)
		"warehouse":
			for crate in level+1:
				box(Vector3(.56,.57,.57),roof_material,Vector3((crate-level*.5)*.74,.29,1.65),parent)
			if level >= 2:
				box(Vector3(width+.3,.33,2.8),stone,Vector3(0,.17,0),parent)
			if level == 3:
				box(Vector3(2.0,1.36,1.8),timber,Vector3(0,.68,-1.82),parent)
				box(Vector3(2.28,.21,2.05),roof_material,Vector3(0,1.43,-1.82),parent)
		"barracks":
			var trim := wood_material(Color("#483729"))
			box(Vector3(.77,1.32,.12),trim,Vector3(0,.68,1.29),parent)
			var shield_face := CylinderMesh.new()
			shield_face.top_radius = .34
			shield_face.bottom_radius = .34
			shield_face.height = .13
			shield_face.radial_segments = 12
			shield_face.material = material(Color("#874838"))
			for shield in [-1,1]:
				var emblem := place_mesh(shield_face,Vector3(shield*(width*.5+.05),height*.64,0),parent)
				emblem.rotation.z = PI*.5
				box(Vector3(.48,.39,.09),trim,Vector3(shield*width*.26,height*.57,-1.27),parent)
				box(Vector3(.13,1.1,.14),trim,Vector3(shield*1.04,.55,1.75),parent)
			box(Vector3(2.35,.16,1.18),roof_material,Vector3(0,1.18,1.53),parent)
			if level >= 2:
				box(Vector3(2.4,.15,1.75),timber,Vector3(0,.10,1.87),parent)
			if level == 3:
				for side in [-1,1]:
					tower(parent,Vector3(side*width*.54,0,-.86),1.11,2.55,roof_material)

func market_stall(parent: Node3D, at: Vector3, roof: Material, side: int) -> void:
	box(Vector3(1.2,.68,1.05),timber,at+Vector3.UP*.34,parent)
	for post in [-.49,.49]:
		box(Vector3(.13,1.65,.13),timber,at+Vector3(post,.83,side*.36),parent)
	var canopy := box(Vector3(1.4,.15,1.47),roof,at+Vector3(0,1.69,side*.12),parent)
	canopy.rotation.x = side*.20

func ground_building(parent: Node3D, footprint: Vector2, footing_material: Material) -> void:
	var position := parent.global_position
	var bottom := surface(Vector2(position.x,position.z)).y
	var top := bottom
	for edge in [-footprint.x*.5,footprint.x*.5]:
		for depth in [-footprint.y*.5,footprint.y*.5]:
			var point := parent.to_global(Vector3(edge,0,depth))
			var height := surface(Vector2(point.x,point.z)).y
			bottom = minf(bottom,height)
			top = maxf(top,height)
	parent.global_position.y = top
	var footing := (top-bottom+.14)/parent.scale.y
	box(Vector3(footprint.x,footing,footprint.y),footing_material,Vector3(0,-footing*.5,0),parent)

func add_crop_field(parent: Node3D, id: String, damaged: bool) -> void:
	if not countryside.farm_sites.has(id): return
	var site: Vector2 = countryside.farm_sites[id]
	var facing := (Geo.position_of(id)-site).normalized()
	var across := Vector2(facing.y,-facing.x)
	var crop := Color("#94703c") if damaged else Color("#a78848")
	countryside.field(self,site,across,facing,Vector2(14,10),parent,crop)

func build_fishery(parent: Node3D, shore: Vector4, level: int, roof: Material, damaged: bool) -> void:
	var bank := Vector2(shore.x,shore.y)
	parent.global_position = surface(bank)
	parent.global_rotation.y = atan2(shore.z,shore.w)
	if not damaged:
		var prop := district_prop("fishery",parent,level,6.4)
		if prop != null:
			var towards_water := Vector2(shore.z,shore.w)
			var dry := 0.0
			var wet := 4.5
			for i in 6:
				var middle := (dry+wet)*.5
				if surface(bank+towards_water*middle).y > WATER_LEVEL:
					dry = middle
				else:
					wet = middle
			# The model's jetty points along +X; its yard ends just behind the shore.
			var center := bank+towards_water*(dry-prop.scale.x*.39)
			prop.position = parent.to_local(surface(center,-.08))
			prop.rotation.y = -PI*.5
			return
	var deck_width := 1.65 if level == 2 else 2.6
	var length := 4.5
	for i in 8:
		if damaged and i in [4,5]: continue
		box(Vector3(deck_width,.15,.60),timber,Vector3(0,.12,i*length/8.0),parent)
	for side in [-1,1]:
		for z in [1.0,3.9]:
			box(Vector3(.21,2.5,.21),timber,Vector3(side*deck_width*.44,-.84,z),parent)
	var hut_base := .14
	var supports: Array[Vector3] = []
	for x in [-1.15,1.15]:
		for z in [-1.95,-.35]:
			var world_at := parent.to_global(Vector3(x,0,z))
			var ground := surface(Vector2(world_at.x,world_at.z)).y-world_at.y
			supports.append(Vector3(x,ground,z))
			hut_base = maxf(hut_base,ground+.1)
	for support in supports:
		var height := hut_base-support.y+.12
		box(Vector3(.21,height,.24),timber,support+Vector3.UP*(height*.5-.08),parent)
	box(Vector3(2.6,1.5,1.8),timber,Vector3(0,hut_base+.75,-1.15),parent)
	box(Vector3(.64,1.12,.08),wood_material(Color("#493a2c")),Vector3(0,hut_base+.58,-.22),parent)
	var cover := box(Vector3(2.9,.18,2.1),roof,Vector3(0,hut_base+1.57,-1.15),parent)
	cover.rotation.x = -.19
	for i in 3:
		var height := lerpf(.19,hut_base,(i+1)/3.0)
		box(Vector3(.95,.15,.32),timber,Vector3(0,height,.32-i*.29),parent)

func launch_fishing_boat(parent: Node3D, shore: Vector4) -> void:
	var route := fishing_boat_route(shore)
	if route.is_empty(): return
	var boat := Node3D.new()
	boat.name = "FishingBoat"
	parent.add_child(boat)
	var start := parent.to_local(Vector3(route[0].x,WATER_LEVEL+.07,route[0].y))
	var end := parent.to_local(Vector3(route[1].x,WATER_LEVEL+.07,route[1].y))
	var heading := atan2(end.x-start.x,end.z-start.z)
	boat.position = start
	boat.rotation.y = heading
	var hull := CylinderMesh.new()
	hull.radial_segments = 8
	hull.top_radius = .43
	hull.bottom_radius = .27
	hull.height = .24
	hull.material = timber
	place_mesh(hull,Vector3.ZERO,boat).scale.z = 2.35
	var planks := material(Color("#a4865b"))
	for seat in [-.37,.37]:
		box(Vector3(.63,.06,.20),planks,Vector3(0,.14,seat),boat)
	var travel_time := start.distance_to(end)/1.1
	var voyage := boat.create_tween().set_loops()
	voyage.tween_property(boat,"position",end,travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	voyage.tween_property(boat,"rotation:y",heading+PI,1.4)
	voyage.tween_property(boat,"position",start,travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	voyage.tween_property(boat,"rotation:y",heading+TAU,1.4)
	voyage.tween_callback(func(): boat.rotation.y = heading)

func fishing_boat_route(shore: Vector4) -> PackedVector2Array:
	var bank := Vector2(shore.x,shore.y)
	var towards_water := Vector2(shore.z,shore.w)
	var tangent := towards_water.orthogonal()
	var route := PackedVector2Array()
	var longest := 2.0
	for depth: float in [4.5,6.0,7.5,9.0,10.5]:
		var center := bank+towards_water*depth
		if not clear_for_fishing_boat(center): continue
		for angle: float in [0.0,.35,-.35,.70,-.70,1.05,-1.05]:
			var direction := tangent.rotated(angle)
			var ends := PackedVector2Array()
			for sign: float in [-1.0,1.0]:
				var last := center
				for i in range(1,17):
					var point := center+direction*sign*i*.65
					if not clear_for_fishing_boat(point): break
					last = point
				ends.append(last)
			var length := ends[0].distance_to(ends[1])
			if length > longest:
				route = ends
				longest = length
	return route

func clear_for_fishing_boat(point: Vector2) -> bool:
	if surface(point).y > WATER_LEVEL-.18 or movement_cost(point,2.55) < 1.0: return false
	# Test the turning radius as well as the center of the hull.
	for i in 8:
		if surface(point+Vector2.from_angle(i*TAU/8.0)*1.25).y > WATER_LEVEL-.14:
			return false
	return true

var visual_season := -1
func set_season(season: int) -> void:
	if season == visual_season: return
	visual_season = season
	ground_material.set_shader_parameter("snow",1.0 if season==3 else 0.0)
	var visited := {}
	for node in find_children("*","GeometryInstance3D",true,false):
		var mesh: Mesh = null
		if node is MeshInstance3D: mesh = node.mesh
		elif node is MultiMeshInstance3D: mesh = node.multimesh.mesh
		if mesh == null: continue
		for surface_id in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface_id)
			if not mat is ShaderMaterial or visited.has(mat.get_instance_id()): continue
			visited[mat.get_instance_id()] = true
			for parameter in mat.shader.get_shader_uniform_list():
				if parameter.name == "snow": mat.set_shader_parameter("snow",1.0 if season==3 else 0.0)
