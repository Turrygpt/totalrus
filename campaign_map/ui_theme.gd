extends RefCounted
## Shared campaign art direction. No tactical resources are referenced here.

const Geo = preload("res://campaign_map/geography.gd")
const PAPER := Color("e5cba0")
const PAPER_LIGHT := Color("f5e2bb")
const INK := Color("30251b")
const INK_FAINT := Color("695641")
const IRON := Color("292f31")
const IRON_DARK := Color("101619")
const BONE := Color("f6e5c5")
const BRASS := Color("d7ac69")
const GOLD := Color("f2ce8c")
const RED := Color("762c23")
const GREEN := Color("68785b")
const ARMY_COLORS := [RED,Color("42646c"),Color("8b623c")]
const FONT = preload("res://assets/ui/birch/fonts/RobotoCondensed.ttf")
const DISPLAY_FACE = preload("res://assets/ui/birch/fonts/CormorantGaramond.ttf")
const Experience = preload("res://scripts/unit_experience.gd")
const ART_ROOT := "res://assets/ui/birch/"
const RESEARCH_ATLAS := "research_icons.png"
const RESEARCH_ICON_CELLS := [
	"husbandry","trade","law","merchant_courts",
	"granaries","settlement","grain_reserves","",
	"drill","iron","siege","supply_trains",
	"camp","standards","retinue_schools","",
]
const SINGLE_ART := {
	"infantry":"spearman.png", "princely":"princely_cavalry.png", "khazar":"khazar_archer.png",
	"varangian":"varangian_axeman.png",
	"light_cavalry":"light_cavalry.png",
	"oleg_leader":"oleg_leader.png",
	"russa_leader":"russa_leader.png", "polotsk_voivode":"polotsk_voivode.png", "smolensk_leader":"smolensk_leader.png",
	"radimichi_leader":"radimichi_leader.png", "severians_leader":"severians_leader.png",
	"askold_leader":"askold_leader.png", "dir_leader":"dir_leader.png",
}
const PORTRAIT_ATLAS := "hired_leaders.png"
const CONSTRUCTION_ATLASES := {
	"construction/civic.webp": [
		"hall","hall_2","hall_3","farm","farm_2","farm_3","farm_2_1","farm_3_1","farm_2_2",
	],
	"construction/commerce.webp": [
		"farm_3_2","market","market_2","market_3","warehouse","warehouse_2","warehouse_3","forge","forge_2",
	],
	"construction/military.webp": [
		"forge_3","barracks","barracks_2","barracks_3","range","range_2","range_3","stables","stables_2",
	],
	"construction/defense.webp": [
		"stables_3","wall","wall_2","wall_3","shrine","shrine_2","shrine_3","fur_house","saltworks",
	],
	"construction/resources.webp": [
		"timber_yard","apiary","linen_yard","bloomery","pottery","threshing_yard","stone_yard",
	],
}
static var icons: Dictionary = {}
static var sheets: Dictionary = {}
static var loading_art: Dictionary = {}
static var button_textures: Dictionary = {}
static var DISPLAY := display_font()
const UNIT_ART_CELLS := {"militia":1, "archer":2, "cavalry":4}

static func display_font() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = DISPLAY_FACE
	font.variation_opentype = {"wght": 610}
	font.variation_embolden = .22
	return font

static func faction_flag(faction: int, city := "") -> Texture2D:
	var path := "res://assets/banners/factions/%s.svg" % Geo.faction_appearance(faction, city).banner
	if not sheets.has(path):
		sheets[path] = load(path)
	return sheets[path]

static func surface(key: String) -> Texture2D:
	if not sheets.has("materials.png"):
		if not ResourceLoader.exists(ART_ROOT+"materials.png"): return null
		sheets["materials.png"] = load(ART_ROOT+"materials.png")
	var texture: Texture2D = sheets["materials.png"]
	var height := texture.get_height()/3.0
	var index: int = {"paper":0,"wood":1,"cloth":2}.get(key,0)
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(1,index*height+2,texture.get_width()-2,height-4)
	atlas.filter_clip = true
	return atlas

static func paper_frame(inset := 24) -> StyleBoxTexture:
	var frame := StyleBoxTexture.new()
	var paper := surface("paper") as AtlasTexture
	if paper:
		# Keep the text field free of the dark bark markings at the atlas edges.
		var clean := paper.region
		clean.position.x += clean.size.x*.13
		clean.size.x *= .74
		paper.region = clean
	frame.texture = paper
	frame.texture_margin_left = 16
	frame.texture_margin_right = 16
	frame.texture_margin_top = 8
	frame.texture_margin_bottom = 8
	frame.set_content_margin_all(inset)
	return frame

static func box(color: Color, border: Color = Color.TRANSPARENT, inset: int = 10, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_content_margin_all(inset)
	return style

static func campaign_frame(inset := 14) -> StyleBoxFlat:
	var style := box(IRON_DARK,Color("58402b"),inset,1)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0,0,0,.55)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0,5)
	return style

static func metal_button(state: String, inset := 8) -> StyleBoxTexture:
	if not button_textures.has(state):
		var palette: Array = {
			"normal": ["353b39","141b1d","c3995d"],
			"hover": ["77552d","2d2923","f9d58e"],
			"pressed": ["523a24","211a14","edbb67"],
			"primary": ["70291c","340e11","efc382"],
			"highlight": ["8a602c","3a2718","ffd899"],
			"disabled": ["31383b","1c2327","675843"],
			"focus": ["00000000","00000000","ffe0a1"],
			"tab": ["323839","17191a","a88249"],
			"hover_tab": ["695233","2d2822","f6cd8c"],
			"active_tab": ["792e20","3d1312","ffd095"],
			"plate": ["333832","151b19","b18854"],
		}[state]
		var top := Color(palette[0])
		var bottom := Color(palette[1])
		var rim := Color(palette[2])
		var tab := state in ["tab","hover_tab","active_tab"]
		var ceremonial := state == "primary" or state == "active_tab"
		var noise := FastNoiseLite.new()
		noise.frequency = .24
		var bitmap := Image.create_empty(48,36,false,Image.FORMAT_RGBA8)
		for y in bitmap.get_height():
			var vertical := mini(y,bitmap.get_height()-1-y)
			var shade := top.lerp(bottom,smoothstep(0.0,35.0,float(y)))
			for x in bitmap.get_width():
				var horizontal := mini(x,bitmap.get_width()-1-x)
				var cut := 7 if not tab or y<18 else 2
				var edge := mini(mini(vertical,horizontal),horizontal+vertical-cut)
				if edge < 0: continue
				var fleck := noise.get_noise_2d(x,y)
				var pixel := shade.lerp(Color("a99574") if fleck > 0 else Color.BLACK,absf(fleck)*(.18 if ceremonial else .10))
				match edge:
					0: pixel = rim.darkened(.48 if y>18 else .13)
					1: pixel = rim.lightened(maxf(0,fleck)*.28)
					2: pixel = rim.darkened(.78)
					3: pixel = rim.darkened(.35)
				if state == "focus" and edge > 1: continue
				bitmap.set_pixel(x,y,pixel)
		button_textures[state] = ImageTexture.create_from_image(bitmap)
	var style := StyleBoxTexture.new()
	style.texture = button_textures[state]
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,9)
	style.set_content_margin_all(inset)
	return style

static func accent_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal",metal_button("primary"))
	button.add_theme_stylebox_override("hover",metal_button("hover"))
	button.add_theme_stylebox_override("pressed",metal_button("pressed"))

static func theme(paper := false) -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = 18
	var fg := INK if paper else BONE
	result.set_color("font_color", "Label", fg)
	result.set_color("default_color", "RichTextLabel", fg)
	result.set_color("font_color", "Button", fg)
	result.set_color("font_hover_color", "Button", Color.WHITE if not paper else RED)
	result.set_color("font_pressed_color", "Button", BONE)
	result.set_color("font_disabled_color", "Button", Color("a49d8d"))
	for state in ["normal","hover","pressed","disabled","focus"]:
		result.set_stylebox(state,"Button",metal_button(state,0 if state == "focus" else 8))
		result.set_stylebox(state,"OptionButton",result.get_stylebox(state,"Button"))
	result.set_color("font_color","OptionButton",fg)
	result.set_color("font_color","PopupMenu",BONE)
	result.set_stylebox("panel","PopupMenu",campaign_frame(9))
	result.set_stylebox("hover","PopupMenu",metal_button("hover",4))
	if paper:
		result.set_stylebox("normal","Button",box(PAPER,BRASS,8))
		result.set_stylebox("hover","Button",box(PAPER_LIGHT,BRASS,8))
		result.set_stylebox("disabled","Button",box(PAPER.darkened(.14),BRASS.darkened(.2),8))
	result.set_stylebox("panel", "PanelContainer", box(PAPER,BRASS,20) if paper else campaign_frame(20))
	result.set_stylebox("panel", "TooltipPanel", campaign_frame(14))
	result.set_font("font", "TooltipLabel", FONT)
	result.set_font_size("font_size", "TooltipLabel", 18)
	result.set_color("font_color", "TooltipLabel", BONE)
	result.set_constant("separation", "HBoxContainer", 10)
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("h_separation", "HFlowContainer", 10)
	result.set_constant("v_separation", "HFlowContainer", 10)
	result.set_stylebox("scroll", "VScrollBar", box(Color("b9ae93"), Color.TRANSPARENT, 0))
	result.set_stylebox("grabber", "VScrollBar", box(Color("706c56"), Color.TRANSPARENT, 3))
	result.set_stylebox("grabber_highlight", "VScrollBar", box(RED, Color.TRANSPARENT, 3))
	result.set_stylebox("grabber_pressed", "VScrollBar", box(RED, Color.TRANSPARENT, 3))
	result.set_stylebox("scroll", "HScrollBar", box(IRON_DARK, Color.TRANSPARENT, 0))
	result.set_stylebox("grabber", "HScrollBar", box(BRASS, Color.TRANSPARENT, 2))
	return result

static func label(parent: Node, value: String, size := 18, color: Color = BONE, display := false) -> Label:
	var item := Label.new()
	item.text = value
	item.add_theme_font_override("font", DISPLAY if display else FONT)
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	return item

static func draw_card_art(canvas: CanvasItem, texture: Texture2D, frame: Rect2, tint: Color, crop_portrait: bool) -> void:
	var source := texture.get_size()
	if crop_portrait:
		var crop := frame.size / maxf(frame.size.x / source.x, frame.size.y / source.y)
		canvas.draw_texture_rect_region(texture, frame, Rect2((source-crop)*Vector2(.5,.24),crop), tint)
	else:
		var fitted := source * minf(frame.size.x / source.x, frame.size.y / source.y)
		canvas.draw_texture_rect(texture, Rect2(frame.get_center()-fitted*.5,fitted), false, tint)

static func draw_card_caption(canvas: CanvasItem, baseline: Vector2, value: String, width: float, font_size: int, color: Color, font: Font = FONT) -> void:
	var measured := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	if measured > width:
		font_size = maxi(1,floori(font_size*width/measured))
	canvas.draw_string(font,baseline,value,HORIZONTAL_ALIGNMENT_CENTER,width,font_size,color)

static func building_art_key(key: String, level: int, branch: int) -> String:
	if key == "farm" and branch > 0:
		return "farm_%d_%d" % [maxi(2,level),branch]
	if level <= 1: return key
	return "%s_%d" % [key,mini(level,3)]

static func art_file(key: String) -> String:
	if key.begins_with("hired_leader_"): return PORTRAIT_ATLAS
	for file: String in CONSTRUCTION_ATLASES:
		if key in CONSTRUCTION_ATLASES[file]: return file
	return SINGLE_ART.get(key,"warriors.png" if UNIT_ART_CELLS.has(key) else "buildings.png")

static func request_art(key: String) -> void:
	var file := art_file(key)
	if sheets.has(file) or loading_art.has(file): return
	var path := ART_ROOT + file
	if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path)==OK:
		loading_art[file] = path

static func art_ready(key: String) -> bool:
	var file := art_file(key)
	return not loading_art.has(file) or ResourceLoader.load_threaded_get_status(loading_art[file]) != ResourceLoader.THREAD_LOAD_IN_PROGRESS

static func art(key: String) -> Texture2D:
	if key == "town":
		var atlas_path := ART_ROOT+"town_and_fort.jpg"
		if not sheets.has(atlas_path) and ResourceLoader.exists(atlas_path):
			sheets[atlas_path] = load(atlas_path)
		if sheets.has(atlas_path):
			var tile := AtlasTexture.new()
			tile.atlas = sheets[atlas_path]
			var side := tile.atlas.get_height()
			tile.region = Rect2(0,0,side,side)
			tile.filter_clip = true
			return tile
	var file := art_file(key)
	if not sheets.has(file):
		if loading_art.has(file):
			sheets[file] = ResourceLoader.load_threaded_get(loading_art[file])
			loading_art.erase(file)
		elif ResourceLoader.exists(ART_ROOT+file):
			sheets[file] = load(ART_ROOT+file)
	var sheet: Texture2D = sheets.get(file)
	if sheet == null and file == PORTRAIT_ATLAS: return art("princely")
	if sheet == null or SINGLE_ART.has(key): return sheet
	var buildings := {"hall":0, "farm":1, "market":2, "forge":3, "barracks":4, "wall":5, "shrine":6, "town":7, "birch":8}
	var is_unit := UNIT_ART_CELLS.has(key)
	var index: int = UNIT_ART_CELLS[key] if is_unit else buildings.get(key,0)
	if CONSTRUCTION_ATLASES.has(file):
		index = CONSTRUCTION_ATLASES[file].find(key)
	if file == PORTRAIT_ATLAS:
		index = clampi(key.trim_prefix("hired_leader_").to_int(),0,5)
	var cell := sheet.get_size()/Vector2(3, 2 if is_unit or file == PORTRAIT_ATLAS else 3)
	var crop := AtlasTexture.new()
	crop.atlas = sheet
	crop.region = Rect2(Vector2(index%3, floori(index/3.0))*cell, cell)
	crop.filter_clip = true
	return crop

static func research_icon(key: String) -> Texture2D:
	var index := RESEARCH_ICON_CELLS.find(key)
	if index < 0 or key.is_empty(): return null
	if not sheets.has(RESEARCH_ATLAS):
		sheets[RESEARCH_ATLAS] = load(ART_ROOT+RESEARCH_ATLAS)
	var sheet: Texture2D = sheets[RESEARCH_ATLAS]
	if sheet == null: return null
	var cell := sheet.get_size()/4.0
	var origin := Vector2(index%4,floori(index/4.0))*cell
	var crop := AtlasTexture.new()
	crop.atlas = sheet
	crop.region = Rect2(origin.floor(),(origin+cell).floor()-origin.floor())
	crop.filter_clip = true
	return crop

static func draw_experience(canvas: CanvasItem, point: Vector2, rank: int) -> void:
	if rank == 0:
		return
	canvas.draw_rect(Rect2(point,Vector2(25,25)),IRON_DARK)
	var metal := Experience.color(rank)
	for stripe in Experience.stripes(rank):
		var y := 7.0+stripe*5.0
		var chevron := PackedVector2Array([point+Vector2(5,y+4),point+Vector2(12.5,y),point+Vector2(20,y+4)])
		canvas.draw_polyline(chevron,metal,2,true)

static func draw_equipment(canvas: CanvasItem, point: Vector2, gear: Vector2i) -> void:
	if gear.x > 0:
		draw_equipment_badge(canvas,point,"sword",gear.x)
	if gear.y > 0:
		draw_equipment_badge(canvas,point+Vector2(13,0),"shield",gear.y)

static func draw_equipment_badge(canvas: CanvasItem, point: Vector2, symbol: String, level: int) -> void:
	var badge := Rect2(point,Vector2(12,15))
	canvas.draw_rect(badge,IRON_DARK)
	canvas.draw_texture_rect(icon(symbol),badge.grow(-.5),false,Experience.COLORS[level-1])

static func icon(key: String) -> Texture2D:
	if icons.has(key): return icons[key]
	var paths := {
		"coin": '<ellipse cx="12" cy="8" rx="8" ry="3" fill="#fff5dd"/><path d="M4 11v3c0 4 16 4 16 0v-3M4 16v3c0 4 16 4 16 0v-2M4 21v3c0 4 16 4 16 0v-2"/><ellipse cx="25" cy="17" rx="4" ry="2" fill="#fff5dd"/><path d="M22 21q3 2 7 0v3q-4 2-7 0"/>',
		"grain": '<path d="M16 28V6M16 19C6 19 6 13 6 11c5 0 9 4 10 8zm0-7C8 12 8 6 9 4c4 1 7 4 7 8zm0 13c10 0 10-6 10-8-5 0-9 4-10 8zm0-10c8 0 8-6 7-8-4 1-7 4-7 8z"/>',
		"sword": '<path d="M9 29l5-7m-6-3 10 7M13 21 24 4l3-1v4L16 23M6 28l4 3"/>',
		"shield": '<path d="M6 5h20v13c0 6-10 11-10 11S6 24 6 18zM16 8v15M10 14l6 4 6-4"/>',
		"town": '<path fill="#fff5dd" fill-rule="evenodd" stroke="none" d="M2 27V11h3v4h3v-4h3v5h3V6h3v3h3V6h3v10h3v-5h4v16H2zm12 0h5v-5a2.5 2.5 0 0 0-5 0zm3-13v4h3v-4z"/>',
		"knot": '<path d="M16 1l4 4-4 4-4-4zm0 22 4 4-4 4-4-4zM1 16l4-4 4 4-4 4zm22 0 4-4 4 4-4 4zM9 8q-5-5-6-1-1 2 2 5l13 13q4 4 7 1t-1-7L11 6m12 2q5-5 6-1 1 2-2 5L14 25q-4 4-7 1t1-7L21 6"/>',
		"scroll": '<path d="M7 5h18v20H10M7 5c-7 0-7 8 0 8h2V5M10 25c-8 0-8 5-2 5h17v-5M12 12h9M12 16h9M12 20h6"/>',
		"book": '<path d="M16 8v21M3 5c5-2 10 0 13 3 4-3 8-5 13-3v21c-6-2-10 0-13 3-4-3-8-5-13-3zM7 11l5 1m-5 5 5 1m8-6 5-1m-5 7 5-1"/>',
		"tree": '<path d="M16 28V5m0 8-7-5m7 11 8-6m-8 10-6-5M12 28h8M9 8C2 9 4 2 4 2s8-2 5 6zm15 5c-2-8 5-7 5-7s3 7-5 7zM10 18c-7 1-6-6-6-6s7-1 6 6zM16 5c-5-4 0-5 0-5s5 2 0 5z"/>',
		"hourglass": '<path d="M8 3h16M8 29h16M10 3v7l12 12v7M22 3v7L10 22v7M12 7h8m-8 18h8"/>',
		"map": '<path d="m3 7 9-4 8 4 9-4v22l-9 4-8-4-9 4zm9-4v22m8-18v22"/>',
		"focus": '<circle cx="16" cy="16" r="8"/><path d="M16 1v9m0 12v9M1 16h9m12 0h9"/>',
		"helm": '<path d="M6 24V14C6 1 26 1 26 14v10M16 4v23m-7-9 5 2m9-2-5 2M4 27h24M6 16l-2 8m22-8 2 8"/>',
		"plus": '<path d="M16 6v20M6 16h20"/>',
		"close": '<path d="m8 8 16 16M24 8 8 24"/>',
		"menu": '<path d="M5 8h22M5 16h22M5 24h22"/>',
		"save": '<path d="M6 3h19l3 4v22H4V3zm3 0v10h14V3M9 29V18h14v11"/>',
		"load": '<path d="M3 12h26l-3 16H6zm2 0V5h9l4 4h9v3M16 12v11m-5-4 5 5 5-5"/>',
		"chevron": '<path d="m12 6 10 10-10 10"/>',
		"sun": '<circle cx="16" cy="16" r="6"/><path d="M16 1v6m0 18v6M1 16h6m18 0h6M5 5l4 4m14 14 4 4M5 27l4-4M23 9l4-4"/>',
		"crown": '<path d="m3 8 5 15h16l5-15-8 7-5-10-5 10zM8 27h16"/><circle cx="16" cy="4" r="1"/>',
		"hammer": '<path d="m5 9 6-6 12 6-3 6-6-3L6 28l-4-3 8-15z"/>',
		"scales": '<path d="M16 3v24M8 28h16M4 9h24M6 9 2 20h8L6 9zm20 0-4 11h8z"/>',
		"people": '<circle cx="16" cy="9" r="3"/><path d="M10 26v-6a6 6 0 0 1 12 0v6zM8 12a3 3 0 1 0-3 3m19-3a3 3 0 1 1 3 3M7 18c-3 0-5 2-5 6h5m18-6c3 0 5 2 5 6h-5"/>',
		"pin": '<path d="M16 29S6 17 6 12a10 10 0 0 1 20 0c0 5-10 17-10 17z"/><circle cx="16" cy="12" r="4"/>',
		"info": '<circle cx="16" cy="16" r="13"/><path d="M16 14v9m-3 1h6"/><circle cx="16" cy="9" r="1" fill="#fff5dd"/>',
		"lock": '<rect x="7" y="13" width="18" height="14" rx="2"/><path d="M11 13V8a5 5 0 0 1 10 0v5m-5 6v3"/>',
		"upgrade": '<path d="M16 28V5M7 14l9-9 9 9"/>',
		"camp": '<path d="m3 28 13-23 13 23zm8 0 5-12 5 12M13 2l6 7M19 2l-6 7"/>',
		"march": '<path d="M10 3v10l-5 9 6 5 6-10M20 7v10l-5 9 6 5 7-12"/>',
		"check": '<path d="m5 17 7 7L27 7"/>',
		"arrow": '<path d="M3 16h24m-8-8 8 8-8 8"/>',
	}
	var path: String = paths.get(key, paths.shield)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><g fill="none" stroke="#fff5dd" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">'+path+'</g></svg>'
	var image := Image.new()
	image.load_svg_from_string(svg, 2.0)
	var texture := ImageTexture.create_from_image(image)
	icons[key] = texture
	return texture
