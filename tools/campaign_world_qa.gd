extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(condition: bool, label: String) -> void:
	if not condition: failures += 1
	print("PASS " if condition else "FAIL ",label)
func run() -> void:
	var world = load("res://campaign_map/main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await process_frame
	world.set_process(false)
	check(world.navigation != null,"march graph starts preparing when campaign opens")
	world.ensure_navigation()
	var geo = world.Geo
	var start: Vector2 = world.army_positions[0]
	var matching := 0
	var samples := 0
	for y in range(-610,611,37):
		for x in range(-740,741,37):
			var point := Vector2(x+.31,y+.17)
			var city: String = world.region_at(point)
			var inside := false
			for polygon in world.territory_borders.cells[city]:
				if Geometry2D.is_point_in_polygon(point,polygon): inside = true
			if inside: matching += 1
			samples += 1
	check(matching==samples,"drawn territories match playable regions: %d/%d" % [matching,samples])
	var mask: Image = world.territory_borders.mask.get_image()
	var texture_matches := true
	for id in geo.CITIES:
		var uv: Vector2 = geo.position_of(id)/(world.Landscape.HALF*2.0)+Vector2(.5,.5)
		var pixel := Vector2i(uv*Vector2(mask.get_size()))
		texture_matches = texture_matches and roundi(mask.get_pixelv(pixel).g*255.)==geo.CITIES.keys().find(id)+1
	check(texture_matches,"territory texture preserves every settlement ID")
	var hud = world.management.hud
	check(hud.portrait.texture==hud.UI.art(geo.ARMIES[0].portrait),"selected commander portrait")
	check(hud.panel.atlas.get_global_rect().position.x>hud.deck_scroll.get_global_rect().position.x,"minimap on the right")
	world.select_city("novgorod")
	check(world.terrain.ground_material.get_shader_parameter("selected_territory")==1,"selected territory painted into terrain material")
	var original_owner: int = world.campaign.owner("russa")
	world.campaign.cities.russa.owner = 0
	world.territory_borders.refresh()
	await process_frame
	var recolored: Color = world.territory_borders.palette_image.get_pixel(2,0)
	check(recolored.is_equal_approx(Color("d3b269")),"border changes with city ownership")
	world.campaign.cities.russa.owner = original_owner
	world.select_army(0)
	for id in geo.CITIES:
		var point: Vector2 = geo.position_of(id)
		check(world.navigation.is_land(point),"land "+id)
		check(world.navigation.route(start,point).size()>1,"route "+id)
		check(world.campaign.cities.has(id),"economy "+id)
	for point in [Vector2(-730,-600),Vector2(730,-600),Vector2(-730,600),Vector2(730,600)]:
		check(world.navigation.route(start,point).size()>1,"corner "+str(point))
	var graph: AStar2D = world.navigation.graph
	var queue := PackedInt64Array([world.navigation.connector(start)])
	var reached := {queue[0]:true}
	var cursor := 0
	while cursor<queue.size():
		for neighbor in graph.get_point_connections(queue[cursor]):
			if reached.has(neighbor): continue
			reached[neighbor] = true
			queue.append(neighbor)
		cursor += 1
	check(reached.size()==graph.get_point_count(),"entire march graph connected: %d/%d" % [reached.size(),graph.get_point_count()])
	for id in geo.CITIES:
		world.focus_at(geo.position_of(id))
		var target: Vector3 = world.terrain.surface(geo.position_of(id))
		var pixel: Vector2 = world.camera.unproject_position(target)
		var hit: Variant = world.pick_ground(pixel)
		if hit is Vector2 and hit.distance_to(geo.position_of(id))>=.2: print("PICK_DETAIL ",id," target=",target," hit=",hit," surface=",world.terrain.surface(hit))
		check(hit is Vector2 and hit.distance_to(geo.position_of(id))<.2,"perspective picking "+id)
	check(world.fog.visible_at(start),"player vision")
	check(not world.fog.visible_at(geo.position_of("kyiv")),"Kyiv concealed")
	check(not world.can_see_army(6),"enemy concealed")
	check(world.armies[6].visible,"hidden enemy remains active for AI")
	check(not world.riders[6].visible,"hidden enemy model concealed")
	var memory: PackedByteArray = world.fog.explored.duplicate()
	var sources: Array[Vector3] = [Vector3(geo.position_of("kyiv").x,geo.position_of("kyiv").y,140)]
	world.fog.update(sources,true)
	check(world.fog.explored_at(start) and not world.fog.visible_at(start),"exploration memory after departure")
	world.save_file = "res://build/rome_visual/test.save"
	world.save_campaign()
	var saved: PackedByteArray = world.fog.explored.duplicate()
	world.fog.restore(null)
	world.load_campaign()
	check(world.fog.explored_at(geo.position_of("kyiv")),"exploration save roundtrip")
	var old: Dictionary = world.campaign.snapshot().duplicate(true)
	old.cities.erase("izborsk")
	old.cities.novgorod.order = 39
	world.campaign.restore(old)
	check(world.campaign.cities.has("izborsk") and world.campaign.cities.novgorod.order==39,"old save adds towns and preserves state")
	world.update_fog(true)
	var enemy_before: Vector2 = world.army_positions[6]
	world.end_turn()
	for i in 5000:
		if world.enemy_actor==0 or not world.encounter.is_empty(): break
		world.advance_enemy_turn(.25)
	check(world.enemy_actor==0 or not world.encounter.is_empty(),"enemy phase terminates under fog")
	check(world.army_positions[6]!=enemy_before or not world.encounter.is_empty(),"hidden enemy simulation advances")
	print("RESULT failures=",failures)
	quit(failures)
