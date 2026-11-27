extends RefCounted
# Four botanical silhouettes assembled from textured boughs, with spatial batching.
const ATLAS = preload("res://assets/campaign/foliage/branches.png")
const LEAVES = preload("res://campaign_map/foliage.gdshader")
const CHUNK := 90.0

static func plant(terrain: Node3D, groups: Array) -> void:
	for kind in groups.size():
		var mesh := tree_mesh(kind)
		var chunks := {}
		for transform: Transform3D in groups[kind]:
			var key := Vector2i(floori(transform.origin.x/CHUNK), floori(transform.origin.z/CHUNK))
			if not chunks.has(key): chunks[key] = []
			chunks[key].append(transform)
		for key: Vector2i in chunks:
			var data := MultiMesh.new()
			data.transform_format = MultiMesh.TRANSFORM_3D
			data.use_colors = true
			data.mesh = mesh
			data.instance_count = chunks[key].size()
			var origin := Vector3(key.x*CHUNK,0,key.y*CHUNK)
			for i in data.instance_count:
				var transform: Transform3D = chunks[key][i]
				var tint := .83 + .22 * absf(sin(transform.origin.x*12.7 + transform.origin.z*3.1))
				transform.origin -= origin
				data.set_instance_transform(i,transform)
				data.set_instance_color(i,Color(tint,tint, tint*.92))
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = data
			instance.position = origin
			terrain.add_child(instance)

static func tree_mesh(kind: int) -> ArrayMesh:
	var random := RandomNumberGenerator.new()
	random.seed = 7103 + kind*723
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#a4a18a") if kind == 1 else Color("#605342")
	wood.roughness = .96
	wood.vertex_color_use_as_albedo = true
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	bark.set_material(wood)
	var height := 5.8 if kind == 2 else 4.8
	branch(bark, Vector3.ZERO, Vector3(.12,height,0), .17 if kind != 1 else .11, .025)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := ShaderMaterial.new()
	material.shader = LEAVES
	material.set_shader_parameter("branches", ATLAS)
	leaves.set_material(material)
	var count := 33 if kind == 2 else 28
	for i in count:
		var angle := i*2.39996 + random.randf_range(-.3,.3)
		var center: Vector3
		var size: float
		if kind == 2:
			var level := float(i)/float(count)
			var spread := lerpf(1.65,.16,level)
			center = Vector3(cos(angle)*spread*.55,1.2+level*4.5,sin(angle)*spread*.55)
			size = lerpf(2.2,.5,level)
		else:
			var level := random.randf_range(-.85,.95)
			var radius := sqrt(1.0-level*level) * (1.55 if kind != 1 else 1.12)
			center = Vector3(cos(angle)*radius,3.65+level*(1.3 if kind != 1 else 1.75),sin(angle)*radius)
			if kind == 3: center.y += .65
			size = random.randf_range(1.5,2.25) if kind != 1 else random.randf_range(1.2,1.85)
		if i%3 == 0:
			branch(bark,Vector3(0,center.y*.66,0),center,.045,.013)
		var tilt := random.randf_range(-.65,.65)
		var right := Vector3(cos(angle),0,sin(angle))
		var up := Vector3(-sin(angle)*sin(tilt),cos(tilt),cos(angle)*sin(tilt)).normalized()
		card(leaves,center,right,up,size,kind)
		# Horizontal branch fans keep the canopy full from the campaign's high camera.
		if i%2 == 0:
			card(leaves,center, right,Vector3(-sin(angle),.22,cos(angle)).normalized(),size*.9,kind)
	bark.generate_normals()
	var mesh := bark.commit()
	leaves.commit(mesh)
	return mesh

static func card(st: SurfaceTool, center: Vector3, right: Vector3, up: Vector3, size: float, kind: int) -> void:
	var origin := Vector2(kind%2,kind/2)*.5
	var corners := [Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5)]
	for i in [0,2,1,0,3,2]:
		var c: Vector2 = corners[i]
		var point := center+(right*c.x+up*c.y)*size
		var normal := (Vector3(point.x, (point.y-2.5)*.6+1.7, point.z)).normalized()
		st.set_normal(normal)
		st.set_color(Color(.84,.93,.79).lerp(Color(1.06,1.04,.94),clampf(point.y/6.0,0,1)))
		st.set_uv(origin + Vector2(c.x+.5,.5-c.y)*.5)
		st.add_vertex(point)

static func branch(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, tip: float) -> void:
	var direction := (b-a).normalized()
	var right := direction.cross(Vector3.FORWARD).normalized()
	if right.length_squared() < .1: right = Vector3.RIGHT
	var side := direction.cross(right).normalized()
	for i in 5:
		var v := right*cos(TAU*i/5.0)+side*sin(TAU*i/5.0)
		var w := right*cos(TAU*(i+1)/5.0)+side*sin(TAU*(i+1)/5.0)
		for point in [a+v*radius,b+v*tip,b+w*tip,a+v*radius,b+w*tip,a+w*radius]:
			st.set_color(Color(.8,.8,.8) if i%2 == 0 else Color.WHITE)
			st.add_vertex(point)
