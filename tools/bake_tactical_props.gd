extends SceneTree
## Bakes the original tactical props into Godot meshes. Run with --headless --script.

const DESTINATION := "res://assets/props/"

func _initialize() -> void:
	var wood := StandardMaterial3D.new()
	wood.vertex_color_use_as_albedo = true
	wood.roughness = .93
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.albedo_texture = preload("res://assets/terrain/rock_color.jpg")
	stone.normal_texture = preload("res://assets/terrain/rock_normalgl.jpg")
	stone.normal_enabled = true
	stone.normal_scale = .59
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3.ONE * 1.8
	stone.roughness = .94

	var fence := start_mesh()
	var posts := [-1.36, -.45, .48, 1.37]
	for i in posts.size():
		var x: float = posts[i]
		branch(fence, Vector3(x, -.18, 0), Vector3(x + .027, 1.22 - .055 * i, .03), .071, .042, Color("654a35"), 7)
	for row in 8:
		var last := Vector3(-1.55, .23 + row * .106, -.02)
		for step in 16:
			var x := -1.55 + (step + 1) * .194
			var y := .23 + row * .106 + sin(x * 4.2 + row) * .018
			var z := cos((x + 1.36) * 3.45 + row * PI) * .106
			var point := Vector3(x, y, z)
			var thickness := .037 - step * .00085
			branch(fence, last, point, thickness, thickness - .00085, Color("957b56").darkened((row % 3) * .095), 5, false)
			last = point
	var failed := save_mesh(fence, wood, "msta_wattle")

	var deadwood := start_mesh()
	branch(deadwood, Vector3(-.48, -.14, .26), Vector3(-.53, .78, .22), .42, .28, Color("67503b"), 10)
	for i in 5:
		var direction := Vector3(cos(i * TAU / 5), 0, sin(i * TAU / 5))
		branch(deadwood, Vector3(-.48, .23, .26), Vector3(-.48, -.1, .26) + direction * .66, .18, .04, Color("5d4a36"), 5)
	branch(deadwood, Vector3(-.28, .24, -.40), Vector3(2.24, .15, -.17), .26, .11, Color("775e45"), 9)
	branch(deadwood, Vector3(.56, .25, -.31), Vector3(.24, .51, -.94), .11, .026, Color("705640"), 6)
	branch(deadwood, Vector3(1.37, .24, -.21), Vector3(1.15, .65, .38), .095, .017, Color("705640"), 6)
	failed = save_mesh(deadwood, wood, "msta_deadwood") or failed

	var outcrop := start_mesh()
	boulder(outcrop, Vector3(0, -.22, .0), Vector3(2.45, 2.25, 1.14), .51, Color("c1bbab"), 9)
	boulder(outcrop, Vector3(-1.74, -.17, .5), Vector3(1.25, 1.27, 1.00), 1.8, Color("a5a398"), 7)
	boulder(outcrop, Vector3(1.69, -.21, .61), Vector3(1.24, .88, .87), -.24, Color("ada89b"), 7)
	boulder(outcrop, Vector3(.12, -.19, -1.1), Vector3(1.19, 1.46, .84), 2.8, Color("a99e8d"), 7)
	failed = save_mesh(outcrop, stone, "msta_outcrop") or failed

	var pebbles := start_mesh()
	var random := RandomNumberGenerator.new()
	random.seed = 4178
	for i in 14:
		var angle := i * 2.39996
		var radius := sqrt(float(i) / 14.0)
		var point := Vector3(cos(angle) * radius * .83, -.044, sin(angle) * radius * .63)
		var size := random.randf_range(.065, .22)
		var tint := Color("c4b6a1").lerp(Color("8c9290"), random.randf())
		boulder(pebbles, point, Vector3(size, size * .56 + .045, size * .79), angle, tint, 6)
	failed = save_mesh(pebbles, stone, "msta_pebbles") or failed
	quit(1 if failed else 0)

func start_mesh() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	return surface

func save_mesh(surface: SurfaceTool, material: Material, name: String) -> bool:
	surface.generate_normals()
	surface.index()
	surface.set_material(material)
	var mesh := surface.commit()
	mesh.resource_name = name
	var result := ResourceSaver.save(mesh, DESTINATION + name + ".res")
	if result != OK:
		push_error("Could not save %s (%s)" % [name, error_string(result)])
	return result != OK

func triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)

func branch(surface: SurfaceTool, start: Vector3, end: Vector3, base: float, tip: float,
		color: Color, sides: int, caps := true) -> void:
	var axis := (end - start).normalized()
	var tangent := axis.cross(Vector3.FORWARD).normalized() if absf(axis.z) < .9 else axis.cross(Vector3.UP).normalized()
	var bitangent := tangent.cross(axis)
	for i in sides:
		var first := i * TAU / sides
		var second := (i + 1) * TAU / sides
		var left := tangent * cos(first) + bitangent * sin(first)
		var right := tangent * cos(second) + bitangent * sin(second)
		var a := start + left * base * (1.0 + sin(i * 4.7) * .11)
		var b := start + right * base * (1.0 + sin((i + 1) % sides * 4.7) * .11)
		var c := end + left * tip
		var d := end + right * tip
		var bark := color.lightened(.065 * sin(i * 3.2))
		triangle(surface, a, b, c, bark)
		triangle(surface, b, d, c, bark)
		if caps:
			triangle(surface, start, b, a, color.darkened(.12))
			triangle(surface, end, c, d, color.lerp(Color("b39b73"), .64))

func boulder(surface: SurfaceTool, center: Vector3, size: Vector3, twist: float,
		color: Color, sides: int) -> void:
	var rings: Array[PackedVector3Array] = []
	for ring in 3:
		var vertices := PackedVector3Array()
		for i in sides:
			var angle := i * TAU / sides + twist + ring * .10
			var spread: float = [.77, 1.0, .54][ring] * (1.0 + .17 * sin(i * 6.24 + ring * 2.8 + twist * 8.0))
			var height: float = [0.0, .43, .85][ring] + .095 * sin(i * 2.65 + twist + ring)
			vertices.append(center + size * Vector3(cos(angle) * spread + ring * .07, height, sin(angle) * spread))
		rings.append(vertices)
	for i in sides:
		var next := (i + 1) % sides
		for ring in 2:
			var shade := color.lightened(.09 * sin(i * 3.6 + ring))
			triangle(surface, rings[ring][i], rings[ring][next], rings[ring + 1][i], shade)
			triangle(surface, rings[ring][next], rings[ring + 1][next], rings[ring + 1][i], shade)
		triangle(surface, rings[2][i], rings[2][next], center + size * Vector3(.13, .94, -.04), color.lightened(.12))

