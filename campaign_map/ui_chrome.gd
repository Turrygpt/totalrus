extends Control
## Shared engraved frame and landscape inlays for the campaign and battle HUD.
const UI = preload("res://campaign_map/ui_theme.gd")
const PANORAMA := "res://assets/ui/birch/novgorod_panorama.jpg"
const BIRD := "res://assets/ui/birch/knotwork_bird.png"
const GILDED_FRAME := "res://assets/ui/birch/gilded_frame.png"
const FRAME_SLICE := 68.0
const CORNER_KNOT := [
	Vector2(0,20),Vector2(5,13),Vector2(12,10),Vector2(17,3),
	Vector2(14,0),Vector2(9,4),Vector2(10,10),Vector2(5,15),Vector2(1,12),
	Vector2(2,7),Vector2(8,6),Vector2(14,7),Vector2(20,0)
]

static var grain: Texture2D
static var panorama: Texture2D
static var bird: Texture2D
static var gilding: StyleBoxTexture
var panoramic := false
var beveled := false
var ornament_depth := 22.0
var separators := PackedFloat32Array()
var frame := UI.campaign_frame(0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var area := Rect2(Vector2.ZERO,size)
	draw_style_box(frame,area)
	if beveled:
		draw_colored_polygon(chamfer(area,14),UI.IRON_DARK)
	draw_material(self,area)
	if panoramic:
		draw_landscape(self,Rect2(size.x*.31,44,size.x*.68,size.y-108),.64)
		draw_bird(self,Rect2(size.x-174,57,160,size.y-133),.27)
	for y in separators:
		draw_line(Vector2(10,y+1),Vector2(size.x-10,y+1),UI.IRON,1.0)
		draw_line(Vector2(10,y),Vector2(size.x-10,y),UI.BRASS.darkened(.42),1.0)
	draw_trim(self,area,ornament_depth,beveled)

static func decorate(panel: Control, depth := 22.0) -> void:
	panel.draw.connect(func():
		var area := Rect2(Vector2.ZERO,panel.size)
		draw_material(panel,area)
		draw_trim(panel,area,depth))

static func draw_material(canvas: CanvasItem, area: Rect2) -> void:
	if area.size.x < 18 or area.size.y < 18: return
	if grain == null:
		var noise := FastNoiseLite.new()
		noise.frequency = .19
		var material := noise.get_seamless_image(96,96)
		material.convert(Image.FORMAT_RGBA8)
		for y in material.get_height():
			for x in material.get_width():
				var tone := material.get_pixel(x,y).r
				material.set_pixel(x,y,Color(.60,.62,.64,tone*tone*.155))
		grain = ImageTexture.create_from_image(material)
	canvas.draw_texture_rect(grain,area.grow(-5),true)
	var inset := area.grow(-6)
	var points := PackedVector2Array([inset.position,Vector2(inset.end.x,inset.position.y),inset.end,Vector2(inset.position.x,inset.end.y)])
	var light := Color(.35,.41,.44,.12)
	var shade := Color(.02,.03,.04,.30)
	canvas.draw_polygon(points,PackedColorArray([light,light,shade,shade]))

static func draw_landscape(canvas: CanvasItem, area: Rect2, opacity := .52) -> void:
	if area.size.x < 4 or area.size.y < 4: return
	if panorama == null and ResourceLoader.exists(PANORAMA):
		panorama = load(PANORAMA)
	if panorama == null: return
	var source := panorama.get_size()
	var crop := area.size / maxf(area.size.x/source.x,area.size.y/source.y)
	var region := Rect2((source-crop)*Vector2(.5,.50),crop)
	var stops_x := [0.0,.28,.80,1.0]
	var stops_y := [0.0,.19,.81,1.0]
	var strength := [0.0,.78,1.0,0.0]
	for row in range(stops_y.size()-1):
		for column in range(stops_x.size()-1):
			var points := PackedVector2Array()
			var coords := PackedVector2Array()
			var colors := PackedColorArray()
			for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.ONE,Vector2i.DOWN]:
				var x := column+offset.x
				var y := row+offset.y
				var unit := Vector2(stops_x[x],stops_y[y])
				points.append(area.position+area.size*unit)
				coords.append((region.position+region.size*unit)/source)
				var vertical := 0.0 if y == 0 or y == stops_y.size()-1 else 1.0
				colors.append(Color(1,.91,.77,strength[x]*vertical*opacity))
			canvas.draw_polygon(points,colors,coords,panorama)

static func draw_bird(canvas: CanvasItem, area: Rect2, opacity: float) -> void:
	if area.size.x < 18 or area.size.y < 18: return
	if bird == null and ResourceLoader.exists(BIRD):
		bird = load(BIRD)
	if bird == null: return
	var extent := bird.get_size() * minf(area.size.x/bird.get_width(),area.size.y/bird.get_height())
	canvas.draw_texture_rect(bird,Rect2(area.end-extent,extent),false,Color(.77,.79,.83,opacity))

static func draw_card_inlay(canvas: CanvasItem, texture: Texture2D, area: Rect2) -> void:
	if texture == null or not area.has_area(): return
	var source := Rect2(Vector2.ZERO,texture.get_size())
	if texture is AtlasTexture:
		source = texture.region
		texture = texture.atlas
	var cropped := area.size/maxf(area.size.x/source.size.x,area.size.y/source.size.y)
	source = Rect2(source.position+(source.size-cropped)*Vector2(.5,.22),cropped)
	var plain := area
	plain.size.x *= .68
	var region := source
	region.size.x *= .68
	canvas.draw_texture_rect_region(texture,plain,region)
	var edge := Rect2(plain.end.x,area.position.y,area.size.x-plain.size.x,area.size.y)
	var edge_source := Rect2(region.end.x,source.position.y,source.size.x-region.size.x,source.size.y)
	var vertices := rect_corners(edge)
	var uv := rect_corners(Rect2(edge_source.position/texture.get_size(),edge_source.size/texture.get_size()))
	canvas.draw_polygon(vertices,PackedColorArray([Color.WHITE,Color.TRANSPARENT,Color.TRANSPARENT,Color.WHITE]),uv,texture)

static func rect_corners(area: Rect2) -> PackedVector2Array:
	return PackedVector2Array([area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)])

static func draw_rule(canvas: CanvasItem, area: Rect2, ornament: bool) -> void:
	var mid := area.get_center()
	var fade := Color(UI.BRASS,.08)
	var gold := Color(UI.BRASS,.72 if ornament else .53)
	var offset := Vector2(0,1)
	var start := Vector2(area.position.x,mid.y)
	var stop := Vector2(area.end.x,mid.y)
	var bar := PackedVector2Array([start,mid,mid+offset,start+offset])
	canvas.draw_polygon(bar,PackedColorArray([fade,gold,gold,fade]))
	bar = PackedVector2Array([mid,stop,stop+offset,mid+offset])
	canvas.draw_polygon(bar,PackedColorArray([gold,fade,fade,gold]))
	if ornament:
		var diamond := PackedVector2Array([mid+Vector2(-6,0),mid+Vector2(0,-3),mid+Vector2(6,0),mid+Vector2(0,3),mid+Vector2(-6,0)])
		canvas.draw_polyline(diamond,UI.GOLD,1.0,true)

static func draw_trim(canvas: CanvasItem, area: Rect2, depth := 22.0, beveled := false) -> void:
	if minf(area.size.x,area.size.y) < 18: return
	if gilding == null and ResourceLoader.exists(GILDED_FRAME):
		gilding = StyleBoxTexture.new()
		gilding.texture = load(GILDED_FRAME)
		gilding.draw_center = false
		gilding.modulate_color = Color(.94,.90,.85)
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
			gilding.set_texture_margin(side,FRAME_SLICE)
	if gilding:
		var corner := minf(depth,minf(area.size.x,area.size.y)*.34)
		var factor := corner/FRAME_SLICE
		var metal := area.grow(-4) if beveled else area
		if beveled:
			canvas.draw_polyline(chamfer(area.grow(-1),13),Color("5e3a22"),3.0,true)
			canvas.draw_polyline(chamfer(area.grow(-2),12),Color("dfac67"),1.2,true)
		canvas.draw_set_transform(metal.position,0,Vector2.ONE*factor)
		canvas.draw_style_box(gilding,Rect2(Vector2.ZERO,metal.size/factor))
		canvas.draw_set_transform(Vector2.ZERO)
		if depth >= 21.0:
			canvas.draw_polyline(chamfer(metal.grow(-5),8),Color(UI.BRASS,.54),1.0,true)
		return
	var metal := UI.GOLD if beveled else UI.BRASS
	canvas.draw_polyline(chamfer(area.grow(-2),7),metal.darkened(.35),1.0,true)
	canvas.draw_polyline(chamfer(area.grow(-4),5),metal,1.0,true)
	canvas.draw_polyline(chamfer(area.grow(-7),4),metal.darkened(.57),1.0,true)
	var scale := minf(depth,minf(area.size.x,area.size.y)*.34)/20.0
	for flip: Vector2 in [Vector2(1,1),Vector2(-1,1),Vector2(1,-1),Vector2(-1,-1)]:
		var origin := area.get_center()-(area.size*.5-Vector2(5,5))*flip
		var points := PackedVector2Array()
		for point: Vector2 in CORNER_KNOT:
			points.append(origin+point*scale*flip)
		canvas.draw_polyline(points,metal.darkened(.28),maxf(1.0,scale*1.5),true)
		canvas.draw_polyline(points,metal.lightened(.14),1.0,true)
		canvas.draw_circle(origin+Vector2(4,4)*scale*flip,maxf(.8,scale),metal)

static func chamfer(area: Rect2, cut: float) -> PackedVector2Array:
	var a := area.position
	var b := area.end
	return PackedVector2Array([
		a+Vector2(cut,0),Vector2(b.x-cut,a.y),Vector2(b.x,a.y+cut),
		b-Vector2(0,cut),b-Vector2(cut,0),Vector2(a.x+cut,b.y),
		Vector2(a.x,b.y-cut),a+Vector2(0,cut),a+Vector2(cut,0)
	])
