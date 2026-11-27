extends Button
## A real button with an atlas illustration: roster, building or recruitment card.
const UI = preload("res://campaign_map/ui_theme.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")
var art_key := "infantry"
var caption := ""
var value := ""
var foot := ""
var foot_color := UI.INK_FAINT
var status_icon := ""
var availability := ""
var availability_color := UI.INK_FAINT
var fraction := 1.0
var selected := false
var empty := false
var artwork: Texture2D
var experience_rank := 0
var equipment := Vector2i.ZERO
var compact := false
var muted := false
var building := false
static var caption_paper: StyleBoxTexture

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(153,138) if compact and building else Vector2(112,106) if compact else Vector2(126,158) if building else Vector2(94,152)
	if not availability.is_empty() and not building: custom_minimum_size.y += 17
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not empty: artwork = UI.art(art_key)
	for state in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	resized.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	pressed.connect(queue_redraw)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO,size)
	var lit := selected or is_hovered() or has_focus()
	var border := Color("ffe3a2") if lit else Color("9b7244")
	var silhouette := Chrome.chamfer(rect,7)
	var status_height := 17 if not availability.is_empty() else 0
	if selected:
		draw_polyline(silhouette,Color(1,.51,.16,.19),11,true)
		draw_polyline(silhouette,Color(1,.64,.22,.44),6,true)
	draw_colored_polygon(silhouette,UI.PAPER if not empty else UI.IRON_DARK)
	if artwork and not empty:
		var photo := Rect2(Vector2(4,5),Vector2(size.x-8,size.y-43-status_height))
		var tint := Color(.78,.71,.60,.78) if disabled or muted else Color.WHITE
		if building:
			draw_rect(photo,Color("f3ddbb").lerp(UI.PAPER,1.0-tint.a))
		UI.draw_card_art(self,artwork,photo,tint,not building)
	if empty:
		draw_texture_rect(UI.icon("plus"),Rect2(Vector2(size.x*.5-17,size.y*.5-25),Vector2(34,34)),false,Color(.65,.65,.53,.45))
		UI.draw_card_caption(self,Vector2(5,size.y-18),caption,size.x-10,14,UI.BRASS)
	else:
		draw_caption_paper(status_height)
		var caption_baseline := size.y - (14 if foot.is_empty() else 20) - status_height
		UI.draw_card_caption(self,Vector2(5,caption_baseline),caption,size.x-10,19 if building else 13,UI.INK,UI.DISPLAY if building else UI.FONT)
		if not foot.is_empty():
			var foot_size := 15 if building else (12 if status_height>0 else 11)
			UI.draw_card_caption(self,Vector2(4,size.y-7-status_height),foot,size.x-8,foot_size,foot_color,UI.DISPLAY if building else UI.FONT)
		if status_height > 0:
			draw_rect(Rect2(4,size.y-21,size.x-8,17),Color(availability_color,.16))
			UI.draw_card_caption(self,Vector2(4,size.y-8),availability,size.x-11,12,availability_color)
		if not status_icon.is_empty():
			var marker := Rect2(size.x-28,4,24,24)
			draw_colored_polygon(Chrome.chamfer(marker,4),UI.IRON_DARK)
			draw_texture_rect(UI.icon(status_icon),marker.grow(-4),false,UI.PAPER_LIGHT)
		if not value.is_empty():
			var badge := Rect2(4,4,34,24)
			var points := Chrome.chamfer(badge,4)
			draw_colored_polygon(points,UI.IRON_DARK)
			draw_polyline(points,UI.BRASS,1.0,true)
			draw_string(UI.DISPLAY,Vector2(4,23),value,HORIZONTAL_ALIGNMENT_CENTER,34,21,UI.GOLD)
		UI.draw_experience(self,Vector2(size.x-28,3),experience_rank)
		UI.draw_equipment(self,Vector2(size.x-28,29),equipment)
		if fraction >= 0:
			draw_rect(Rect2(5,size.y-43,size.x-10,3),UI.IRON)
			draw_rect(Rect2(5,size.y-43,(size.x-10)*clampf(fraction,0,1),3),UI.GREEN)
	draw_polyline(Chrome.chamfer(rect.grow(-1),7),border,2.0 if lit else 1.0,true)
	draw_polyline(Chrome.chamfer(rect.grow(-3),5),UI.PAPER_LIGHT,1.0,true)

func draw_caption_paper(status_height: int) -> void:
	var top := size.y-38-status_height
	var bottom := size.y-4
	var points := PackedVector2Array([Vector2(4,top),Vector2(size.x-4,top),Vector2(size.x-4,bottom),Vector2(4,bottom)])
	draw_polygon(points,PackedColorArray([UI.PAPER_LIGHT,UI.PAPER_LIGHT,UI.PAPER,UI.PAPER]))
	if building:
		if caption_paper == null:
			caption_paper = UI.paper_frame(0)
			caption_paper.modulate_color = Color(1,.93,.79,.57)
		draw_style_box(caption_paper,Rect2(4,top,size.x-8,bottom-top))
