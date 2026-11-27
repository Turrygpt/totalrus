extends RefCounted
## Exact settlement cells clipped by province borders. The same nearest-city
## rule is used by CampaignState.region_at, so the drawn frontier is playable.
const Geo = preload("res://campaign_map/geography.gd")
var cells := {}
var palette: ImageTexture
var palette_image: Image
var mask: Texture2D
var world

func build(map) -> void:
	world = map
	for id in Geo.CITIES:
		var polygon := rectangle(world.Landscape.HALF)
		var origin := Geo.position_of(id)
		for other in Geo.CITIES:
			if other == id: continue
			var target := Geo.position_of(other)
			polygon = clip_half_plane(polygon,(origin+target)*.5,target-origin)
		var pieces := [polygon]
		cells[id] = pieces
	mask = load_mask()
	palette = ImageTexture.create_from_image(Image.create_empty(32,1,false,Image.FORMAT_RGBA8))
	for material in [world.terrain.ground_material,world.terrain.water_material]:
		material.set_shader_parameter("territory_distance",mask)
		material.set_shader_parameter("territory_ids",mask)
		material.set_shader_parameter("territory_palette",palette)
		material.set_shader_parameter("map_half",world.Landscape.HALF)
	refresh()

func rectangle(half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)])

func clip_half_plane(points: PackedVector2Array, middle: Vector2, normal: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points.size():
		var a := points[i]
		var b := points[(i+1)%points.size()]
		var da := (a-middle).dot(normal)
		var db := (b-middle).dot(normal)
		if da <= 0.0: result.append(a)
		if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
			result.append(a.lerp(b,da/(da-db)))
	return result

func load_mask() -> Texture2D:
	var signature := hash(cells)
	for path in ["res://assets/campaign/territory_mask.res","user://territory_mask.res"]:
		if not ResourceLoader.exists(path): continue
		var cached := load(path) as Texture2D
		if cached and cached.get_meta("geometry_signature",0) == signature: return cached
	var texture := bake_mask()
	texture.set_meta("geometry_signature",signature)
	ResourceSaver.save(texture,"user://territory_mask.res",ResourceSaver.FLAG_COMPRESS)
	return texture

func bake_mask() -> ImageTexture:
	# Rasterize IDs, then the narrow distance band around each exact frontier.
	# It is cached; no border meshes, physics, depth offsets or shadow casters.
	const WIDTH := 1536
	const HEIGHT := 1280
	const REACH := 8.0
	var half: Vector2 = world.Landscape.HALF
	var pitch := half*2.0/Vector2(WIDTH,HEIGHT)
	var bytes := PackedByteArray()
	bytes.resize(WIDTH*HEIGHT*4)
	bytes.fill(255)
	var index := 0
	for id in cells:
		index += 1
		for polygon in cells[id]:
			var low_y := half.y
			var high_y := -half.y
			for point in polygon:
				low_y = minf(low_y,point.y)
				high_y = maxf(high_y,point.y)
			for y in range(maxi(0,floori((low_y+half.y)/pitch.y)),mini(HEIGHT,ceili((high_y+half.y)/pitch.y))):
				var py := (y+.5)*pitch.y-half.y
				var hits := PackedFloat32Array()
				for i in polygon.size():
					var a: Vector2 = polygon[i]
					var b: Vector2 = polygon[(i+1)%polygon.size()]
					if (a.y <= py and b.y > py) or (b.y <= py and a.y > py): hits.append(lerpf(a.x,b.x,(py-a.y)/(b.y-a.y)))
				hits.sort()
				for hit in range(0,hits.size()-1,2):
					for x in range(maxi(0,ceili((hits[hit]+half.x)/pitch.x-.5)),mini(WIDTH,ceili((hits[hit+1]+half.x)/pitch.x-.5))):
						var pixel := (y*WIDTH+x)*4
						bytes[pixel+1] = index
						bytes[pixel+2] = Geo.CITIES[id][1]
			for i in polygon.size():
				var a: Vector2 = polygon[i]
				var b: Vector2 = polygon[(i+1)%polygon.size()]
				var midpoint := (a+b)*.5
				if absf(midpoint.x)>half.x-.1 or absf(midpoint.y)>half.y-.1: continue
				var delta := b-a
				var square := delta.length_squared()
				if square < .001: continue
				for y in range(maxi(0,floori((minf(a.y,b.y)-REACH+half.y)/pitch.y)),mini(HEIGHT,ceili((maxf(a.y,b.y)+REACH+half.y)/pitch.y))):
					var py := (y+.5)*pitch.y-half.y
					var lo := minf(a.x,b.x)-REACH
					var hi := maxf(a.x,b.x)+REACH
					if absf(delta.y)>.01:
						var x0 := a.x+delta.x*clampf((py-REACH-a.y)/delta.y,0.,1.)
						var x1 := a.x+delta.x*clampf((py+REACH-a.y)/delta.y,0.,1.)
						lo = minf(x0,x1)-REACH
						hi = maxf(x0,x1)+REACH
					for x in range(maxi(0,floori((lo+half.x)/pitch.x)),mini(WIDTH,ceili((hi+half.x)/pitch.x))):
						var point := Vector2((x+.5)*pitch.x-half.x,py)
						var nearest := a+delta*clampf((point-a).dot(delta)/square,0.,1.)
						var pixel := (y*WIDTH+x)*4
						bytes[pixel] = mini(bytes[pixel],mini(255,roundi(point.distance_to(nearest)/REACH*255.)))
	return ImageTexture.create_from_image(Image.create_from_data(WIDTH,HEIGHT,false,Image.FORMAT_RGBA8,bytes))

func refresh() -> void:
	if not is_instance_valid(world): return
	var selected: String = world.selected_city
	if selected.is_empty(): selected = world.region_at(world.army_positions[world.selected_army])
	palette_image = Image.create_empty(32,1,false,Image.FORMAT_RGBA8)
	var index := 0
	for id in cells:
		index += 1
		var owner: int = world.campaign.owner(id)
		var color: Color = Geo.faction_appearance(owner, id).color.lightened(.24)
		if owner == 0: color = Color("d3b269")
		palette_image.set_pixel(index,0,color)
	palette.update(palette_image)
	for material in [world.terrain.ground_material,world.terrain.water_material]:
		material.set_shader_parameter("selected_territory",Geo.CITIES.keys().find(selected)+1)
		material.set_shader_parameter("selected_province",Geo.CITIES[selected][1])
