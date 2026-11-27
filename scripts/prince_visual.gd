extends Node3D
## Reusable prince model. The heraldry surface keeps its own 0..1 UV island.
@export var mounted := false
@export var faction_crest: Texture2D = preload("res://assets/banners/factions/novgorod.svg")
var cloth: Node3D
var embroidery: ShaderMaterial

func _ready() -> void:
	embroidery = ShaderMaterial.new()
	embroidery.shader = preload("res://assets/prince/embroidery.gdshader")
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.lod_bias = 100.0
	for mesh: MeshInstance3D in find_children("PrinceBody*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface)
			if original and original.resource_name.begins_with("FactionEmbroidery"):
				mesh.set_surface_override_material(surface, embroidery)
	set_faction_crest(faction_crest)
	cloth = preload("res://scripts/prince_cloth.gd").new()
	cloth.name = "SimulatedCloak"
	add_child(cloth)
	cloth.configure(self, mounted)

func set_faction_crest(texture: Texture2D) -> void:
	faction_crest = texture
	if embroidery:
		embroidery.set_shader_parameter("has_crest", texture != null)
		if texture:
			embroidery.set_shader_parameter("crest_texture", texture)

func set_cloak_color(color: Color) -> void:
	cloth.set_color(color)

func use_skinned_cape() -> void:
	cloth.use_skinned_mesh()
