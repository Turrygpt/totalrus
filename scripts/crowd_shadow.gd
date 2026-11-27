extends RefCounted
const FOOT_PLACEMENT = preload("res://scripts/infantry_foot_placement.gd")
# A separate animated silhouette casts real directional shadows at distance.
# It never replaces the visible body and uses no textures or full skinning.
static var cache := {}
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var indices := PackedInt32Array()
var bindings := PackedVector2Array()
var actor: Node3D
var names: Array
var rests := {}
var cape_to_bone:=Transform3D.IDENTITY
func build(owner_actor: Node3D, bank: Resource, sockets: Array[BoneAttachment3D]) -> ArrayMesh:
	actor=owner_actor
	var key:=str(bank.get_instance_id())+str(actor.get_script().resource_path)+str(actor.has_kite_shield())+str(sockets.is_empty())
	if cache.has(key): return cache[key]
	names=bank.get_meta("bone_names")
	for i in actor.skeleton.get_bone_count():
		rests[actor.skeleton.get_bone_name(i)]=actor.global_transform.affine_inverse()*actor.skeleton.global_transform*actor.skeleton.get_bone_global_rest(i)
	if actor.mounted:
		mounted_body()
	else:segment("Hips","Neck",.36,.23)
	for side in ["Left","Right"]:
		segment(side+"Arm",side+"ForeArm",.13,.13)
		segment(side+"ForeArm",side+"Hand",.105,.105)
		segment(side+"UpLeg",side+"Leg",.17,.18)
		segment(side+"Leg",side+"Foot",.125,.14)
		segment(side+"Foot",side+"ToeBase",.13,.12)
	var head:=bone("Head")
	if not head.is_empty():
		var sphere:=SphereMesh.new();sphere.radius=.12;sphere.height=.30;sphere.radial_segments=8;sphere.rings=3
		var center:Vector3=rests[head].origin+Vector3.UP*.08
		append_shape(sphere,rests[head].affine_inverse()*Transform3D(Basis.IDENTITY,center),names.find(head),0)
	for socket in sockets:
		var bone_index:int=names.find(socket.bone_name)
		if bone_index<0:continue
		for part:MeshInstance3D in socket.find_children("*","MeshInstance3D",true,false):
			if part.mesh is PrimitiveMesh:continue
			var tag:=0
			var parent:Node=part
			while parent!=socket:
				if parent==actor.spear:tag=1
				if parent==actor.sword:tag=2
				parent=parent.get_parent()
			var material:Material=part.get_active_material(0)
			if material is ShaderMaterial and "wool_color" in material.shader.code:
				tag=5;cape_to_bone=socket.global_transform.affine_inverse()*part.global_transform
			if tag == 2:
				if actor.get("axe_variant") != null:
					tag = -1
				else:
					bone_index = names.find("GripRight")
			if actor.get("bow") != null and actor.bow.is_ancestor_of(part):
				tag=3
			if actor.get("held_arrow") != null and actor.held_arrow.is_ancestor_of(part):
				tag=4
			var box:AABB=(socket.global_transform.affine_inverse()*part.global_transform)*part.get_aabb()
			var proxy:=BoxMesh.new();proxy.size=box.size.max(Vector3.ONE*.012)
			var center:=box.get_center()
			# Belt-space sword is approximated in the right-hand grip after drawing.
			if tag==2: center=Vector3(0,box.size.y*.45,0)
			append_shape(proxy,Transform3D(Basis.IDENTITY,center),bone_index,tag)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV2]=bindings;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=ShaderMaterial.new();material.shader=preload("res://assets/crowd_shadow.gdshader")
	material.set_shader_parameter("pose_bones",bank.get_meta("pose_bones"))
	material.set_shader_parameter("cape_to_bone",cape_to_bone)
	material.set_shader_parameter("corpse_hips", names.find(bone("Hips")))
	material.set_shader_parameter("corpse_neck", names.find(bone("Neck")))
	FOOT_PLACEMENT.configure_material(material, bank)
	mesh.surface_set_material(0,material)
	cache[key]=mesh
	print("SHADOW_PROXY ",actor.get_script().resource_path," triangles ",indices.size()/3)
	return mesh
func bone(suffix:String) -> String:
	for name:String in names:
		if name.ends_with(":"+suffix) or name.ends_with("_"+suffix) or name==suffix:return name
	return ""

func mounted_body() -> void:
	segment("Body","Torso",.72,.76)
	segment("Torso","Neck2",.42,.46)
	segment("Neck2","Head",.30,.38)
	segment("Tail1","Tail5",.11,.12)
	segment("RiderRoot","RiderChest",.36,.23)
	for side in [".L",".R"]:
		segment("FrontUpperLeg"+side,"FrontLowerLeg"+side,.15,.15)
		segment("FrontLowerLeg"+side,"FF"+side,.11,.13)
		segment("BackUpperLeg"+side,"BackLowerLeg"+side,.19,.18)
		segment("BackLowerLeg"+side,"FFB"+side,.11,.13)
		segment("RiderUpperArm"+side,"RiderForearm"+side,.13,.13)
		segment("RiderForearm"+side,"RiderHand"+side,.11,.11)
		segment("RiderThigh"+side,"RiderShin"+side,.16,.18)
		segment("RiderShin"+side,"RiderBoot"+side,.13,.14)
	var name:=bone("RiderHead")
	var sphere:=SphereMesh.new();sphere.radius=.13;sphere.height=.3;sphere.radial_segments=8;sphere.rings=3
	append_shape(sphere,Transform3D(Basis.IDENTITY,Vector3(0,.08,0)),names.find(name),0)
func segment(first:String,last:String,width:float,depth:float) -> void:
	var a:=bone(first);var b:=bone(last)
	if a.is_empty() or b.is_empty():return
	var start:Vector3=rests[a].origin;var end:Vector3=rests[b].origin
	var y:Vector3=(end-start).normalized();var x:=y.cross(Vector3.FORWARD).normalized()
	if x.length_squared()<.01:x=Vector3.RIGHT
	var z:=x.cross(y).normalized()
	var shape:=BoxMesh.new();shape.size=Vector3(width,start.distance_to(end)+.04,depth)
	append_shape(shape,rests[a].affine_inverse()*Transform3D(Basis(x,y,z),(start+end)*.5),names.find(a),0)
func append_shape(mesh:PrimitiveMesh,transform:Transform3D,bone_index:int,tag:int) -> void:
	var arrays:=mesh.get_mesh_arrays()
	var start:=vertices.size()
	for point:Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		vertices.append(transform*point);normals.append(Vector3.UP);bindings.append(Vector2(bone_index,tag))
	for index:int in arrays[Mesh.ARRAY_INDEX]:indices.append(start+index)
