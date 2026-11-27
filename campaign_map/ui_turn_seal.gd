extends Button
const UI = preload("res://campaign_map/ui_theme.gd")

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var center := size*.5
	var radius := minf(size.x,size.y)*.5-3
	var accent: Color = UI.BRASS if disabled else UI.RED.lightened(.12) if is_hovered() else UI.RED
	draw_circle(center+Vector2(0,3),radius+2,Color(0,0,0,.45))
	draw_circle(center,radius,UI.IRON)
	draw_arc(center,radius,0,TAU,64,UI.BRASS,2,true)
	draw_circle(center,radius-6,accent.darkened(.3) if disabled else accent)
	draw_arc(center,radius-6,0,TAU,64,UI.BRASS,1,true)
	for i in 12:
		var axis := Vector2.from_angle(i*TAU/12.0)
		draw_line(center+axis*(radius-3),center+axis*(radius-1),UI.BONE,1,true)
	draw_texture_rect(UI.icon("hourglass"),Rect2(center-Vector2(18,22),Vector2(36,44)),false,Color(.7,.7,.65) if disabled else UI.BONE)
	if has_focus(): draw_arc(center,radius+2,0,TAU,64,UI.BONE,1,true)
