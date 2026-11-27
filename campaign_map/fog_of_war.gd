extends RefCounted
const SIZE := Vector2i(256,224)
var half := Vector2(770,642)
var explored := PackedByteArray()
var sight := Image.create_empty(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
var texture: ImageTexture
var atlas_texture: ImageTexture
var revision := 0
var last_signature := 0

func _init() -> void:
	explored.resize(SIZE.x*SIZE.y)
	explored.fill(0)
	texture = ImageTexture.create_from_image(sight)
	atlas_texture = ImageTexture.create_from_image(sight)

func cell(p: Vector2) -> Vector2i:
	return Vector2i(((p/half+Vector2.ONE)*.5*Vector2(SIZE)).floor()).clamp(Vector2i.ZERO,SIZE-Vector2i.ONE)

func visible_at(p: Vector2) -> bool:
	var c := cell(p)
	return sight.get_pixel(c.x,c.y).r > .4

func explored_at(p: Vector2) -> bool:
	var c := cell(p)
	return explored[c.y*SIZE.x+c.x] > 100

func update(sources: Array[Vector3], force := false) -> bool:
	var signature := hash(sources)
	if not force and signature == last_signature: return false
	last_signature = signature
	sight.fill(Color(0,0,0,1))
	for source in sources:
		var center := Vector2(source.x,source.y)
		var lo := cell(center-Vector2.ONE*source.z)
		var hi := cell(center+Vector2.ONE*source.z)
		for y in range(lo.y,hi.y+1):
			for x in range(lo.x,hi.x+1):
				var point := ((Vector2(x+.5,y+.5)/Vector2(SIZE))*2.0-Vector2.ONE)*half
				var amount := 1.0-smoothstep(source.z*.72,source.z,point.distance_to(center))
				amount = maxf(amount,sight.get_pixel(x,y).r)
				sight.set_pixel(x,y,Color(amount,0,0,1))
				explored[y*SIZE.x+x] = maxi(explored[y*SIZE.x+x],roundi(amount*255))
	var atlas := Image.create_empty(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
	for y in SIZE.y:
		for x in SIZE.x:
			var value := sight.get_pixel(x,y)
			value.g = explored[y*SIZE.x+x]/255.0
			sight.set_pixel(x,y,value)
			atlas.set_pixel(x,y,Color(.16,.19,.20,(1.0-value.r)*lerpf(.96,.6,value.g)))
	texture.update(sight)
	atlas_texture.update(atlas)
	revision += 1
	return true

func restore(data: Variant) -> void:
	explored.fill(0)
	if data is PackedByteArray and data.size()==explored.size(): explored = data.duplicate()
	last_signature = 0

func attach(land: Node3D, camera: Camera3D) -> void:
	half = land.HALF
	var material := ShaderMaterial.new()
	material.shader = preload("res://campaign_map/fog_of_war.gdshader")
	material.set_shader_parameter("sight",texture)
	material.set_shader_parameter("map_half",half)
	var noise := FastNoiseLite.new()
	noise.seed = 882
	noise.frequency = .022
	noise.fractal_octaves = 4
	var clouds := NoiseTexture2D.new()
	clouds.width = 512
	clouds.height = 512
	clouds.seamless = true
	clouds.noise = noise
	material.set_shader_parameter("cloud_noise",clouds)
	material.render_priority = 120
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	quad.material = material
	var cloud := MeshInstance3D.new()
	cloud.mesh = quad
	cloud.extra_cull_margin = 16384.0
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(cloud)
	cloud.position.z = -1.1
	cloud.name = "FogOfWar"
