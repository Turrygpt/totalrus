extends Button
const UI = preload("res://campaign_map/ui_theme.gd")
var key := "helm"
var selected := false

func _ready() -> void:
	custom_minimum_size = Vector2(44,44)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var center := size*.5
	var radius := minf(size.x,size.y)*.5-2.
	var light := UI.GOLD.darkened(.36) if disabled else UI.GOLD
	draw_circle(center+Vector2(0,3),radius+1,Color(0,0,0,.63))
	draw_circle(center,radius,Color("443022"),true,-1,true)
	draw_arc(center,radius-1.,0,TAU,48,Color("a16a3c"),2.0,true)
	draw_arc(center,radius-1.,PI*1.06,PI*1.99,24,light,2.0,true)
	draw_arc(center,radius-3.,0,TAU,48,Color("825631"),2.0,true)
	draw_circle(center,radius-5.,UI.RED if selected else UI.IRON.lightened(.15) if is_hovered() else UI.IRON_DARK)
	draw_arc(center,radius-5.,0,TAU,48,UI.BRASS,1.0,true)
	draw_arc(center,radius-6.,.09,PI*.88,22,Color("5d3927"),1.0,true)
	var icon_size := Vector2.ONE*(radius*1.21)
	draw_texture_rect(UI.icon(key),Rect2(center-icon_size*.5,icon_size),false,light)
	if selected or has_focus(): draw_arc(center,radius,0,TAU,48,Color("dfc077"),2.,true)
