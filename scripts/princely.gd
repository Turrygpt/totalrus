extends "res://scripts/cavalry.gd"

const PRINCE_MODEL = preload("res://scenes/prince_mounted.tscn")
const COMMANDER_HEALTH_MULTIPLIER := 3.0

static var horn_mesh: ArrayMesh
var horn: MeshInstance3D

func warrior_scene() -> PackedScene:
	return PRINCE_MODEL if is_sotnik else super.warrior_scene()

func crowd_kind() -> String:
	# The commander's own rig stays visible; the cavalry pose bank has a different body.
	return "prince" if is_sotnik else super.crowd_kind()

func apply_appearance() -> void:
	if not is_sotnik:
		super.apply_appearance()
		return
	var rider := model.find_child("PrinceBody", true, false) as MeshInstance3D
	rider.set_surface_override_material(0, TroopColors.dye(rider.get_active_material(0),
		uniform_color(), TroopColors.Fabric.PRINCE))
	TroopColors.dye_saddle(model, uniform_color())

func braced_fall_damage() -> float:
	return max_hp / COMMANDER_HEALTH_MULTIPLIER + 1.0 if is_sotnik else super.braced_fall_damage()

func set_faction_crest(standard: Texture2D) -> void:
	model.set_faction_crest(standard)

func _ready() -> void:
	is_sotnik = index == 0
	super._ready()
	max_hp *= 1.3
	damage_multiplier = 1.18
	if is_sotnik:
		model.set_cloak_color(uniform_color())
		max_hp *= COMMANDER_HEALTH_MULTIPLIER
		if warrior_lods_enabled:
			for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
				mesh.lod_bias = 1.2
	hp = max_hp

func raise_horn() -> void:
	if horn_mesh == null:
		horn_mesh = make_horn()
	horn = MeshInstance3D.new()
	horn.mesh = horn_mesh
	add_child(horn)
	horn.position = Vector3(-.27,2.55,-.10)
	var mouth := Vector3(-.04,2.91,-.21)
	var head_index := skeleton.find_bone("RiderHead")
	if head_index >= 0:
		var head: Vector3 = to_local(skeleton.to_global(skeleton.get_bone_global_pose(head_index).origin))
		if head.y > 2.2:
			mouth = head + Vector3(-.04,-.07,-.15)
	var lift := create_tween()
	lift.tween_property(horn,"position",mouth,.22)
	lift.tween_interval(1.45)
	lift.tween_property(horn,"position",horn.position,.20)
	lift.tween_callback(horn.queue_free)

static func make_horn() -> ArrayMesh:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c9a468")
	material.metallic = .5
	material.roughness = .43
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for ring in 10:
		for edge in 10:
			for point in [[ring,edge],[ring+1,edge],[ring+1,edge+1],[ring,edge],[ring+1,edge+1],[ring,edge+1]]:
				var depth: float = float(point[0])/10.0
				var angle: float = TAU*point[1]/10.0
				var radius := .025+.13*depth*depth
				surface.add_vertex(Vector3(.20*depth*depth+cos(angle)*radius,-.14*depth*depth+sin(angle)*radius,-.64*depth))
	surface.generate_normals()
	return surface.commit()
