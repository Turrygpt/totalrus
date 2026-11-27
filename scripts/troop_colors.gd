extends RefCounted

enum Fabric { WARRIOR, ARCHER, VARANGIAN, KHAZAR, PRINCE, SHIELD, VARANGIAN_SHIELD }

const DYE := preload("res://assets/troop_dye.gdshader")
const SHIRT_MASK := preload("res://assets/warrior_shirt_mask.png")
const SHIELD_PAINT_MASK := preload("res://assets/shield_paint_mask.png")
const SKIRMISH_COLORS := [Color("be473a"), Color("3984c3")]

static var dyed_materials := {}
static var saddle_materials := {}

static func uniform_color(banner: Color) -> Color:
	return Color.from_hsv(banner.h, maxf(banner.s, .52), maxf(banner.v, .75))

static func dye(source: StandardMaterial3D, color: Color, fabric: Fabric, texture: Texture2D = null) -> ShaderMaterial:
	var key := [source, color, fabric, texture]
	if not dyed_materials.has(key):
		var material := ShaderMaterial.new()
		material.shader = DYE
		material.set_shader_parameter("base_texture", texture if texture else source.albedo_texture)
		material.set_shader_parameter("team_color", color)
		material.set_shader_parameter("fabric", fabric)
		match fabric:
			Fabric.WARRIOR:
				material.set_shader_parameter("dye_texture", SHIRT_MASK)
			Fabric.SHIELD:
				material.set_shader_parameter("dye_texture", SHIELD_PAINT_MASK)
		material.set_shader_parameter("surface_roughness", source.roughness)
		material.set_shader_parameter("surface_metallic", source.metallic)
		material.set_shader_parameter("roughness_texture", source.roughness_texture)
		material.set_shader_parameter("metallic_texture", source.metallic_texture)
		material.set_shader_parameter("use_roughness_texture", source.roughness_texture != null)
		material.set_shader_parameter("use_metallic_texture", source.metallic_texture != null)
		material.set_shader_parameter("normal_texture", source.normal_texture)
		material.set_shader_parameter("use_normal_texture", source.normal_enabled)
		material.set_shader_parameter("normal_strength", source.normal_scale)
		dyed_materials[key] = material
	return dyed_materials[key]

static func dye_saddle(model: Node3D, color: Color) -> void:
	var saddle := model.find_child("Saddlecloth", true, false) as MeshInstance3D
	var source := saddle.get_active_material(0) as StandardMaterial3D
	var key := [source, color]
	if not saddle_materials.has(key):
		var wool := source.duplicate() as StandardMaterial3D
		wool.albedo_color = color
		saddle_materials[key] = wool
	saddle.set_surface_override_material(0, saddle_materials[key])
