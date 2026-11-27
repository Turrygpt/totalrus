extends RefCounted

const MODEL_LIBRARY := "res://assets/campaign/construction_models.glb"
const CITY_BUILDINGS := ["market","farm","forge","warehouse","stables","range","shrine","barracks"]
var meshes: Dictionary[String,Mesh] = {}

static func city_offset(key: String, radius: float, stretch: float) -> Vector2:
	var slot := CITY_BUILDINGS.find(key)
	if slot < 0: return Vector2.ZERO
	var angle := TAU*(slot+.5)/CITY_BUILDINGS.size()
	return Vector2(sin(angle)*stretch,cos(angle))*radius*.68

func mesh_for(key: String, level: int) -> Mesh:
	if meshes.is_empty() and ResourceLoader.exists(MODEL_LIBRARY,"PackedScene"):
		var library: PackedScene = load(MODEL_LIBRARY)
		var models := library.instantiate()
		for child in models.get_children():
			if child is MeshInstance3D:
				meshes[child.name] = child.mesh
		models.free()
	return meshes.get("%s_%d" % [key,clampi(level,1,3)])

func place(parent: Node3D, key: String, level: int, size := 1.0, offset := Vector3.ZERO) -> MeshInstance3D:
	var mesh := mesh_for(key,level)
	if mesh == null: return null
	var building := MeshInstance3D.new()
	building.name = "BlenderModel"
	building.mesh = mesh
	building.scale = Vector3.ONE*size
	building.position = offset
	parent.add_child(building)
	return building

