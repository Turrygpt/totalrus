extends Control
var world: Node3D
var hovered: Node3D
var confirmed := 0.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _process(delta: float) -> void:
	confirmed = maxf(0,confirmed-delta/maxf(.01,Engine.time_scale))
	queue_redraw()
func _draw() -> void:
	var ours: Node3D = world.selected_squad
	if not is_instance_valid(ours) or not ours.selected or not ours.combat_ready(): return
	var target: Node3D = hovered if is_instance_valid(hovered) else ours.attack_target
	if not is_instance_valid(target) or target.team == ours.team or target.alive_count() == 0: return
	var a3: Vector3 = ours.center()+Vector3.UP*.15
	var b3: Vector3 = target.center()+Vector3.UP*.15
	if world.camera.is_position_behind(a3) or world.camera.is_position_behind(b3): return
	var a: Vector2 = world.camera.unproject_position(a3)
	var b: Vector2 = world.camera.unproject_position(b3)
	var direction: Vector2 = (b-a).normalized()
	var color := Color("edbd6b") if target == ours.attack_target else Color("75c6e2")
	var normal := Vector2(-direction.y,direction.x)
	var path := PackedVector2Array()
	for i in 25:
		var t := i/24.0
		path.append(a.lerp(b,t)+normal*sin(t*PI)*24)
	draw_polyline(path,Color(0,0,0,.6),8,true)
	draw_polyline(path,color,4,true)
	draw_colored_polygon(PackedVector2Array([b,b-direction*23+normal*10,b-direction*23-normal*10]),color)
	for group in [ours,target]:
		var center: Vector3 = group.center()+Vector3.UP*.06
		var ring := PackedVector2Array()
		for i in 41:
			var p := center+Vector3(cos(i*TAU/40)*maxf(3,group.formation_width*.58),0,sin(i*TAU/40)*3.3)
			ring.append(world.camera.unproject_position(p))
		draw_polyline(ring,Color("ee7862") if group == ours else color,2,true)
	var text: String = ours.display_name+"  →  "+target.display_name
	if target != ours.attack_target: text += "  ·  ПКМ — атаковать"
	var mid: Vector2 = a.lerp(b,.5)+Vector2(0,-38)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
	draw_style_box(panel_style(),Rect2(mid-Vector2(width*.5+12,24),Vector2(width+24,34)))
	draw_string(font,mid-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("fff0d0"))
func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.04,.05,.04,.90)
	style.set_corner_radius_all(5)
	return style
