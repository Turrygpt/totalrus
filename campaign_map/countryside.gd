extends RefCounted
const Geo = preload("res://campaign_map/geography.gd")
const FIELD = preload("res://campaign_map/field.gdshader")
const CLEARING_RADIUS := 11.0
const CLEARING_CELL_SIZE := 32.0
var clearings: Dictionary[Vector2i, PackedVector2Array] = {}
var lanes: Array[PackedVector2Array] = []
var farm_sites: Dictionary[String,Vector2] = {}
var random := RandomNumberGenerator.new()

func build(land: Node3D, roads: Array[PackedVector2Array]) -> void:
	random.seed = 88216
	# Roadside clearings keep their own deterministic seed, independent of tree density.
	for samples in roads:
		for fraction in [.23,.66]:
			var i := int((samples.size()-2)*fraction)
			var point := samples[i]
			var along := (samples[i+1]-samples[i]).normalized()
			var side := along.orthogonal() * (-1.0 if random.randf()<.5 else 1.0)
			var center := point+side*8.0
			if not dry(land,center,6.0): continue
			var close := false
			for city in Geo.CITIES:
				if center.distance_to(Geo.position_of(city)) < 24.0: close = true
			if close: continue
			add_clearing(center)
			lanes.append(PackedVector2Array([point,center]))
			fence(land,center+along*7.0-side*2.5,center+along*7.0+side*5.0)
			fence(land,center-along*7.0-side*2.5,center-along*7.0+side*5.0)
			var plot := center+side*12.0
			if dry(land,plot,9.0):
				field(land,plot,along,side,Vector2(12,15))
				add_clearing(plot)
	for city in Geo.CITIES:
		var site := find_farm_site(land,city)
		if site != Vector2.INF:
			farm_sites[city] = site
			add_clearing(site)

func find_farm_site(land: Node3D, city: String) -> Vector2:
	var center := Geo.position_of(city)
	var camp := Geo.camp_position(city)
	var best := Vector2.INF
	var score := INF
	for distance: float in [27.0,34.0,43.0,55.0,73.0,95.0,120.0]:
		for i in 16:
			var direction := Vector2.from_angle(i*TAU/16.0+.7)
			var plot := center+direction*distance
			if plot.distance_squared_to(camp)<256.0 or is_clearing(plot,10.0): continue
			if Geo.region_at(plot+direction*10.0)!=city or Geo.region_at(plot+direction.orthogonal()*10.0)!=city or Geo.region_at(plot-direction.orthogonal()*10.0)!=city:
				continue
			if land.movement_cost(plot)<1.0 or not dry(land,plot,9.5): continue
			var cost: float = distance+land.forest_cover(plot)*16.0
			if cost < score:
				score = cost
				best = plot
		if score <= distance+5.0: break
	return best

func add_clearing(center: Vector2) -> void:
	var cell := Vector2i((center/CLEARING_CELL_SIZE).floor())
	var sites: PackedVector2Array = clearings.get(cell,PackedVector2Array())
	sites.append(center)
	clearings[cell] = sites

func is_clearing(p: Vector2, padding := 0.0) -> bool:
	var radius := CLEARING_RADIUS+padding
	var extent := Vector2.ONE*radius
	var low := Vector2i(((p-extent)/CLEARING_CELL_SIZE).floor())
	var high := Vector2i(((p+extent)/CLEARING_CELL_SIZE).floor())
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			var cell := Vector2i(x,y)
			if not clearings.has(cell): continue
			for center in clearings[cell]:
				if p.distance_squared_to(center) < radius*radius: return true
	return false

func dry(land: Node3D, p: Vector2, radius: float, max_slope := 2.5) -> bool:
	var h: float = land.surface(p).y
	for n in 8:
		var q := p+Vector2.from_angle(n*TAU/8.0)*radius
		if land.signed_water_distance(q)<2.5 or absf(land.surface(q).y-h)>max_slope: return false
	return true

func field(land: Node3D, center: Vector2, across: Vector2, along: Vector2, size: Vector2, parent: Node3D = null, crop := Color.TRANSPARENT) -> void:
	var destination := land if parent == null else parent
	var mat := ShaderMaterial.new()
	mat.shader = FIELD
	mat.set_shader_parameter("soil",preload("res://assets/terrain/grass_color.jpg"))
	if crop == Color.TRANSPARENT:
		crop = [Color("#7c7543"),Color("#9b884c"),Color("#675336"),Color("#778048")][random.randi_range(0,3)]
	mat.set_shader_parameter("crop",crop)
	mat.set_shader_parameter("snow",1.0 if land.visual_season == 3 else 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	for y in 10:
		for x in 10:
			for corner in [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				var uv: Vector2 = (Vector2(x,y)+corner)/10.0
				var p := center+across*(uv.x-.5)*size.x+along*(uv.y-.5)*size.y
				st.set_uv(uv)
				st.add_vertex(destination.to_local(land.surface(p,.12)))
	st.generate_normals()
	land.place_mesh(st.commit(),Vector3.ZERO,destination)

func fence(land: Node3D, a: Vector2, b: Vector2) -> void:
	var count := ceili(a.distance_to(b)/1.8)
	for n in range(count+1):
		var at: Vector3 = land.surface(a.lerp(b,float(n)/count))
		land.box(Vector3(.13,.95,.13),land.timber,at+Vector3.UP*.47)
		if n == count: continue
		var end: Vector3 = land.surface(a.lerp(b,float(n+1)/count))
		for height in [.37,.76]:
			var rail: MeshInstance3D = land.box(Vector3(.10,.10,at.distance_to(end)),land.timber,(at+end)*.5+Vector3.UP*height)
			rail.look_at(end+Vector3.UP*height)
