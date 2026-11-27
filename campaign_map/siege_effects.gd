extends Node3D

var sources: Array[Node3D] = []
var sites: PackedVector3Array
var smoke_mesh: QuadMesh
var fire_mesh: QuadMesh

func set_turns(turns: int) -> void:
	var count := clampi(turns,0,sites.size())
	if count == sources.size(): return
	while sources.size() > count:
		var source: Node3D = sources.pop_back()
		remove_child(source)
		source.queue_free()
	while sources.size() < count:
		if smoke_mesh == null:
			smoke_mesh = plume_mesh(Vector2(2.35,2.35),BaseMaterial3D.BLEND_MODE_MIX)
			fire_mesh = plume_mesh(Vector2(1.65,2.8),BaseMaterial3D.BLEND_MODE_ADD)
		var source := Node3D.new()
		source.position = sites[sources.size()]
		add_child(source)
		sources.append(source)
		add_plume(source,false)
	for i in sources.size():
		var fire := sources[i].get_node_or_null("Fire") as CPUParticles3D
		if i < count-1:
			if fire == null:
				add_plume(sources[i],true)
		elif fire != null:
			sources[i].remove_child(fire)
			fire.queue_free()

func plume_mesh(size: Vector2, blend_mode: BaseMaterial3D.BlendMode) -> QuadMesh:
	var gradient := Gradient.new()
	gradient.set_color(0,Color.WHITE)
	gradient.set_color(1,Color(1,1,1,0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(.5,.5)
	texture.fill_to = Vector2(1,.5)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = blend_mode
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.material = material
	return mesh

func add_plume(parent: Node3D, fire: bool) -> void:
	var plume := CPUParticles3D.new()
	plume.name = "Fire" if fire else "Smoke"
	plume.mesh = fire_mesh if fire else smoke_mesh
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.amount = 18 if fire else 24
	plume.lifetime = 1.08 if fire else 4.7
	plume.preprocess = .45 if fire else 1.3
	plume.randomness = .3
	plume.position.y = 0.3 if fire else 2.2
	plume.direction = Vector3.UP if fire else Vector3(.18,1,.08)
	plume.spread = 23.0 if fire else 19.0
	plume.gravity = Vector3.ZERO if fire else Vector3(.25,.14,.1)
	plume.initial_velocity_min = 1.3 if fire else 1.4
	plume.initial_velocity_max = 2.9 if fire else 2.4
	plume.scale_amount_min = .65
	plume.scale_amount_max = 1.25
	var size := Curve.new()
	size.max_value = 2
	size.add_point(Vector2(0,.65 if fire else .52))
	size.add_point(Vector2(1,.12 if fire else 1.65))
	plume.scale_amount_curve = size
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0,.25,1])
	colors.colors = PackedColorArray([
		Color(1,.87,.30,.65) if fire else Color(.21,.19,.17,.1),
		Color(1,.32,.055,.63) if fire else Color(.16,.14,.13,.48),
		Color(.6,.07,.02,0) if fire else Color(.38,.35,.31,0),
	])
	plume.color_ramp = colors
	parent.add_child(plume)
