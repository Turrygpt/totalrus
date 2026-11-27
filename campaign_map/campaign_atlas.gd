extends Control
const UI = preload("res://campaign_map/ui_theme.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")
const Geo = preload("res://campaign_map/geography.gd")
var world
var territory: ImageTexture
var coastline: ImageTexture
var relief: ImageTexture
var owners_hash := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "ЛКМ — переместить камеру\nСветлая рамка — видимая часть карты"

func map_rect() -> Rect2:
	return Rect2(Vector2(6,6),size-Vector2(12,12))

func map_point(point: Vector2) -> Vector2:
	var rect := map_rect()
	return rect.position+(point/(world.Landscape.HALF*2.0)+Vector2(0.5,0.5))*rect.size

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),UI.IRON)
	draw_rect(Rect2(Vector2.ZERO,size),UI.BRASS,false,1)
	var owners := []
	for id in Geo.CITIES: owners.append(world.campaign.owner(id))
	var signature := hash(owners)
	if territory == null or owners_hash != signature:
		owners_hash = signature
		var image := Image.create_empty(160,128,false,Image.FORMAT_RGBA8)
		var relief_pixels: Image
		if relief == null:
			relief_pixels = Image.create_empty(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				var point: Vector2 = (Vector2(x+.5,y+.5)/Vector2(160,128)-Vector2(.5,.5))*world.Landscape.HALF*2.0
				var city: String = world.region_at(point)
				var color: Color = Geo.faction_appearance(world.campaign.owner(city), city).color.lerp(Color("394946"),.65)
				var height: float = world.terrain.surface(point).y
				color = color.lightened(clampf(height/100.0,0,.12))
				var sea: bool = height < world.Landscape.WATER_LEVEL
				if sea: color = Color("254352")
				image.set_pixel(x,y,color)
				if relief_pixels:
					var neutral := Color(.36,.37,.24,.25).lightened(clampf(height/200.0,0,.11))
					relief_pixels.set_pixel(x,y,Color(.03,.20,.32,.31) if sea else neutral)
		territory = ImageTexture.create_from_image(image)
		if relief_pixels: relief = ImageTexture.create_from_image(relief_pixels)
		if coastline == null:
			var edges := Image.create_empty(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8)
			var water := Color("254352")
			for y in range(1,image.get_height()-1):
				for x in range(1,image.get_width()-1):
					if not image.get_pixel(x,y).is_equal_approx(water): continue
					for offset: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
						if not image.get_pixel(x+offset.x,y+offset.y).is_equal_approx(water):
							edges.set_pixel(x,y,Color(.83,.72,.49,.53))
							break
			coastline = ImageTexture.create_from_image(edges)
	draw_texture_rect(territory,map_rect(),false)
	for road in Geo.ROADS:
		var points := PackedVector2Array()
		for p in Geo.road_points(road): points.append(map_point(p))
		draw_polyline(points,Color(.9,.79,.55,.50),.8,true)
	draw_texture_rect(world.fog.atlas_texture,map_rect(),false)
	draw_texture_rect(relief,map_rect(),false)
	draw_texture_rect(coastline,map_rect(),false)
	for id in Geo.CITIES:
		if not world.fog.visible_at(Geo.position_of(id)): continue
		var p := map_point(Geo.position_of(id))
		if world.campaign.sieges.has(id): draw_arc(p,5.5,0,TAU,18,Color("de8260"),1.5,true)
		var is_capital := Geo.is_province_capital(id)
		draw_circle(p,3.3 if is_capital else 2.2,UI.IRON)
		draw_circle(p,2.1 if is_capital else 1.4,Geo.faction_appearance(world.campaign.owner(id), id).color.lightened(.35))
	for i in world.army_positions.size():
		if not world.armies[i].visible or not world.can_see_army(i): continue
		var p := map_point(world.army_positions[i])
		draw_circle(p,4.5,UI.PAPER_LIGHT if i==0 else UI.IRON)
		draw_circle(p,2.7,Geo.FACTIONS[Geo.army_faction(i)].color.lightened(.24))
	var view_size: Vector2 = world.get_viewport().get_visible_rect().size
	var bounds := PackedVector2Array()
	for screen_point in [Vector2(view_size.x*.05,view_size.y*.08),Vector2(view_size.x*.95,view_size.y*.08),Vector2(view_size.x*.95,view_size.y*.76),Vector2(view_size.x*.05,view_size.y*.76)]:
		var origin: Vector3 = world.camera.project_ray_origin(screen_point)
		var direction: Vector3 = world.camera.project_ray_normal(screen_point)
		var point: Vector3 = origin+direction*(-origin.y/direction.y)
		bounds.append(map_point(Vector2(point.x,point.z)).clamp(Vector2(7,7),size-Vector2(7,7)))
	bounds.append(bounds[0])
	draw_polyline(bounds,Color(.98,.93,.78,.8),1.0,true)
	draw_string(UI.DISPLAY,Vector2(size.x-24,24),"С",HORIZONTAL_ALIGNMENT_LEFT,-1,15,UI.BONE)
	draw_line(Vector2(size.x-20,27),Vector2(size.x-20,39),UI.BONE,1)
	Chrome.draw_trim(self,Rect2(Vector2.ZERO,size),17)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var rect := map_rect()
		var unit: Vector2 = ((event.position-rect.position)/rect.size).clamp(Vector2.ZERO,Vector2.ONE)
		world.focus_at((unit-Vector2(.5,.5))*world.Landscape.HALF*2.0)
		accept_event()
