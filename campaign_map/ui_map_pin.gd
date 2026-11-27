extends Button
const UI = preload("res://campaign_map/ui_theme.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")
var army := false
var capital := false
var selected := false
var blocks_march := false
var tone := UI.RED
var flag: Texture2D
var info := ""
var lettering := 21
var construction_idle := false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)

func marker_size() -> Vector2:
	var width := UI.DISPLAY.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,lettering).x+44
	if not army: width = maxf(width,UI.FONT.get_string_size(info,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+40)
	return Vector2(ceilf(width)+(24 if construction_idle else 0),36 if army else 55 if capital else 49)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO,size)
	var bg := UI.IRON_DARK.lerp(tone,.51 if not selected else .75)
	if is_hovered(): bg = bg.lightened(.11)
	draw_colored_polygon(Chrome.chamfer(Rect2(Vector2(1,3),size),5),Color(0,0,0,.3))
	draw_colored_polygon(Chrome.chamfer(rect,5),bg)
	var border := Color("#ff795f") if blocks_march else UI.BONE if selected else UI.BRASS
	draw_polyline(Chrome.chamfer(rect.grow(-1),5),border,2 if selected or blocks_march else 1,true)
	draw_polyline(Chrome.chamfer(rect.grow(-3),4),border.darkened(.52),1.0,true)
	var fg := UI.BONE
	if flag:
		draw_texture_rect(flag,Rect2(7,5,19,25),false)
	draw_string(UI.DISPLAY,Vector2(32,24),text,HORIZONTAL_ALIGNMENT_LEFT,-1,lettering,fg)
	if not army:
		draw_string(UI.FONT,Vector2(32,size.y-7),info,HORIZONTAL_ALIGNMENT_LEFT,-1,12,fg.darkened(.10) if not selected else UI.BONE)
	if construction_idle:
		var badge := Rect2(size.x-28,8,19,20)
		draw_rect(badge,Color("795527"))
		draw_rect(badge,Color("e7be80"),false,1.0)
		draw_texture_rect(UI.icon("town"),badge.grow(-2),false)
