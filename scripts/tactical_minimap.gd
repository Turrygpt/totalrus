extends Control
const UI = preload("res://campaign_map/ui_theme.gd")
var world: Node3D
var terrain_texture: ImageTexture

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	tooltip_text="ЛКМ / перетаскивание — камера. ПКМ — приказ выбранному отряду."
	var map := Image.create_empty(192,144,false,Image.FORMAT_RGB8)
	for y in 144:
		for x in 192:
			var p: Vector2 = (Vector2(x/191.0,y/143.0)*2-Vector2.ONE)*world.field_half_size
			var h: float=world.terrain.height_at(p)
			var forest: float=world.terrain.generator.tree_cover(p)
			var color:=Color("68704a").lerp(Color("b4a47c"),clampf(h/25,0,1))
			var cover: Color = world.terrain.ground_cover_at(p)
			color = color.lerp(Color("9a8260"), cover.r * .44)
			color = color.lerp(Color("6a6865"), cover.b * .66)
			color = color.lerp(Color("948168"), cover.a * .66)
			if forest > .16 and world.terrain.clear_for_scenery(p): color = color.darkened(forest * .42)
			if world.terrain.path_distance(p)<4: color=Color("c3b084")
			if world.terrain.snow>.5: color=color.lerp(Color("cad3d7"),.7)
			map.set_pixel(x,y,color)
	terrain_texture=ImageTexture.create_from_image(map)

func map_point(point: Vector3) -> Vector2:
	return (Vector2(point.x,point.z)/world.field_half_size*.5+Vector2.ONE*.5)*size

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if terrain_texture: draw_texture_rect(terrain_texture,Rect2(Vector2.ZERO,size),false)
	for obstacle: Vector3 in world.terrain.obstacles:
		draw_rect(Rect2(map_point(Vector3(obstacle.x,0,obstacle.y))-Vector2(3,2),Vector2(6,4)),Color("453629"))
	if not world.siege_gates.is_empty():
		var y:=map_point(Vector3(0,0,world.siege_line)).y
		draw_line(Vector2(0,y),Vector2(size.x,y),UI.BONE,2,true)
	for group in world.squads:
		if group.alive_count()==0: continue
		var p:=map_point(group.center()).clamp(Vector2.ONE*3,size-Vector2.ONE*3)
		var color:=Color("d9bd70") if group.team==0 else Color("b33f32")
		if group.routed or group.surrendered: color=color.darkened(.4)
		draw_circle(p,3.5,color)
		if group.selected: draw_arc(p,5.5,0,TAU,20,Color.WHITE,1.3,true)
	var camera_at:=map_point(world.focus)
	var radius:float=clampf(world.camera_distance/9.0,5,36)
	draw_arc(camera_at,radius,0,TAU,40,Color(1,1,1,.65),1,true)
	var facing:=Vector2(-sin(world.camera_yaw),-cos(world.camera_yaw))
	draw_line(camera_at,camera_at+facing*radius,Color.WHITE,1,true)
	draw_rect(Rect2(Vector2.ZERO,size),UI.BRASS,false,1)

func _gui_input(event: InputEvent) -> void:
	var at: Vector2
	var order:=false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: return
		at=event.position
		order=event.button_index==MOUSE_BUTTON_RIGHT
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): at=event.position
	else: return
	var p: Vector2=(at/size*2-Vector2.ONE)*world.field_half_size
	var point: Vector3=world.terrain.ground_point(p)
	if order:
		world.command_selected(1,point,true)
	else:
		world.camera_follow=false
		world.focus=point
		world.update_camera()
	accept_event()
