extends SceneTree
func _initialize() -> void:
	for method in RenderingServer.get_method_list():
		if "time" in method.name or "profile" in method.name: print(method)
	for method in ClassDB.class_get_method_list("MeshInstance3D"):
		if "bake" in method.name: print(method)
	quit()
