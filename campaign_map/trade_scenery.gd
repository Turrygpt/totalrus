extends RefCounted

static func build(land: Node3D, yard: Node3D, good: String) -> void:
	var wood: Material = land.timber
	match good:
		"Меха":
			for x in [-2.05,0.0,2.05]:
				land.box(Vector3(.18,1.95,.18),wood,Vector3(x,.98,-.48),yard)
			land.box(Vector3(4.35,.16,.18),wood,Vector3(0,1.88,-.48),yard)
			for i in 4:
				var x := (i-1.5)*.95
				var fur: Material = land.material(Color("#ad906a") if i%2 == 0 else Color("#664b38"))
				land.box(Vector3(.46,1.16,.09),fur,Vector3(x,1.32,-.37),yard)
				land.box(Vector3(.71,.63,.09),fur,Vector3(x,1.43,-.37),yard)
			land.box(Vector3(2.2,.40,.88),wood,Vector3(.3,.20,.87),yard)
		"Соль":
			var salt: Material = land.material(Color("#e1d7bc"))
			for x in [-1.42,0.0,1.42]:
				cylinder(land,yard,Vector3(x,.38,.24),.54,.43,.76,wood)
				cylinder(land,yard,Vector3(x,.75,.24),.43,.49,.16,salt)
			var basin: Material = land.material(Color("#625b4d"))
			cylinder(land,yard,Vector3(-.4,.32,-1.2),.88,.72,.35,basin)
			cylinder(land,yard,Vector3(-.4,.51,-1.2),.71,.79,.10,salt)
		"Лес":
			for row in 3:
				var count := 4-row
				for i in count:
					var x := (i-(count-1)*.5)*.77
					var trunk := cylinder(land,yard,Vector3(x,.39+row*.63,.0),.39,.38,3.0,wood)
					trunk.rotation.x = PI*.5
					var cut: Material = land.material(Color("#b68d5e"))
					var end := cylinder(land,yard,Vector3(x,.39+row*.63,1.51),.33,.33,.045,cut)
					end.rotation.x = PI*.5
		"Мёд и воск":
			var clay: Material = land.material(Color("#96603d"))
			var wax: Material = land.material(Color("#c99c4f"))
			land.box(Vector3(4.2,.53,1.68),wood,Vector3(0,.27,0),yard)
			for x in [-1.4,-.45,.55]:
				pot(land,yard,Vector3(x,.54,-.21),.36,clay,wood)
			for i in 3:
				var x := .77+i*.39
				land.box(Vector3(.32,.19,.48),wax,Vector3(x,.64,.46),yard)
		"Лён":
			var linen: Material = land.material(Color("#d0c29e"))
			var dyed: Material = land.material(Color("#74878a"))
			for x in [-1.95,1.95]:
				land.box(Vector3(.16,1.92,.19),wood,Vector3(x,.96,-.51),yard)
			land.box(Vector3(4.14,.14,.13),wood,Vector3(0,1.81,-.51),yard)
			land.box(Vector3(1.42,1.19,.10),linen,Vector3(-.98,1.15,-.41),yard)
			land.box(Vector3(1.30,1.34,.10),dyed,Vector3(.84,1.08,-.41),yard)
			for x in [-1.05,.0,1.05]:
				var roll := cylinder(land,yard,Vector3(x,.22,.76),.22,.22,1.45,linen)
				roll.rotation.x = PI*.5
		"Железо":
			var clay: Material = land.material(Color("#9a6646"))
			var dark: Material = land.material(Color("#292725"))
			cylinder(land,yard,Vector3(-.79,.31,-.3),1.03,1.12,.62,land.stone)
			cylinder(land,yard,Vector3(-.79,1.19,-.3),.62,.92,1.80,clay)
			cylinder(land,yard,Vector3(-.79,2.10,-.3),.44,.44,.035,dark)
			land.box(Vector3(.47,.45,.09),dark,Vector3(-.79,.58,.63),yard)
			land.box(Vector3(1.61,.32,1.03),wood,Vector3(1.28,.16,.49),yard)
			for i in 4:
				var iron: Material = land.material(Color("#777372"))
				land.box(Vector3(.21,.13,.65),iron,Vector3(.77+i*.32,.38,.49),yard)
		"Керамика":
			var dark: Material = land.material(Color("#783f2c"))
			var light: Material = land.material(Color("#bc7452"))
			land.box(Vector3(4.08,.57,1.46),wood,Vector3(0,.29,-.13),yard)
			for i in 5:
				var radius := .22+.055*(i%3)
				pot(land,yard,Vector3((i-2)*.78,.58,-.18),radius,light if i%2 == 0 else dark,wood)
			pot(land,yard,Vector3(1.29,0,1.14),.41,dark,wood)
		"Зерно":
			var sack: Material = land.material(Color("#aa9364"))
			var grain: Material = land.material(Color("#c8a15a"))
			land.box(Vector3(3.28,.17,2.31),wood,Vector3(0,.09,0),yard)
			for x in [-1.03,0.0,1.03]:
				cylinder(land,yard,Vector3(x,.56,-.43),.36,.43,.79,sack)
				cylinder(land,yard,Vector3(x,.98,-.43),.18,.28,.17,sack)
			cylinder(land,yard,Vector3(0,.43,.56),.58,.47,.52,wood)
			cylinder(land,yard,Vector3(0,.71,.56),.48,.49,.12,grain)
		"Камень":
			var rock: Material = land.material(Color("#9e9b8c"))
			for z in [-.65,.64]:
				for i in 4:
					var x := (i-1.5)*1.0
					var block: Node3D = land.box(Vector3(.89,.43,1.08),rock,Vector3(x,.22,z),yard)
					block.rotation.y = .06*(i-2)
			for x in [-.95,0.0,.95]:
				land.box(Vector3(.77,.41,1.02),land.stone,Vector3(x,.64,-.65),yard)

static func pot(land: Node3D, yard: Node3D, at: Vector3, radius: float, clay: Material, inside: Material) -> void:
	cylinder(land,yard,at+Vector3.UP*radius*.77,radius,radius*.72,radius*1.54,clay)
	cylinder(land,yard,at+Vector3.UP*radius*1.68,radius*.70,radius,radius*.29,clay)
	cylinder(land,yard,at+Vector3.UP*radius*1.83,radius*.46,radius*.46,.025,inside)

static func cylinder(land: Node3D, yard: Node3D, at: Vector3, top: float, bottom: float, height: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 9
	mesh.rings = 0
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.material = material
	return land.place_mesh(mesh,at,yard)
