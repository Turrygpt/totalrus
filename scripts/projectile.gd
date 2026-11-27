extends Node3D
const FIELD = preload("res://scripts/battlefield_bounds.gd")

const GROUND_LIFETIME := 5.0
const FADE_DURATION := 1.5

var velocity := Vector3.ZERO
var landed := false
var source_team := -1
var shooter: CharacterBody3D
var previous_tip := Vector3.ZERO
var ignore_bodies: Array[RID] = []

func launch(origin: Transform3D, target: Vector3) -> void:
	global_transform = origin
	var distance := Vector2(target.x - position.x, target.z - position.z).length()
	var flight_time := maxf(0.8, distance / 11.0)
	# Aim at chest height; the swept tip, rather than the shaft origin, deals damage.
	var aim := target + Vector3.UP * .9
	velocity = (aim - global_position) / flight_time
	velocity.y += 0.5 * 9.81 * flight_time
	previous_tip = global_position + global_basis.y * 1.31
	for soldier in get_tree().get_nodes_in_group("combatants"):
		if soldier.team == source_team:
			ignore_bodies.append(soldier.get_rid())

func _physics_process(delta: float) -> void:
	if landed:
		return
	velocity.y -= 9.81 * delta
	global_position += velocity * delta
	# The shaft is authored along local +Y, with its tip 1.31 m above the grip.
	var shaft := velocity.normalized()
	var side := shaft.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.1:
		side = Vector3.RIGHT
	global_basis = Basis(side, shaft, side.cross(shaft)).orthonormalized()
	var tip := global_position + shaft * 1.31
	var query := PhysicsRayQueryParameters3D.create(previous_tip, tip, 3, ignore_bodies)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	previous_tip = tip
	if not hit.is_empty() and hit.collider.has_method("receive_hit"):
		var damage := randf_range(58.0,78.0)
		if is_instance_valid(shooter): damage *= shooter.attack_damage_scale()
		hit.collider.receive_hit(damage,shooter,true,false,false,hit.position)
		landed = true
		set_physics_process(false)
		# A hit spear drops rather than hovering at chest height after the victim falls.
		var drop := create_tween()
		drop.tween_property(self, "position:y", FIELD.project(Vector3(position.x,0,position.z)).y+.07, .3)
		drop.parallel().tween_property(self, "rotation:x", PI / 2.0, .3)
		fade_and_remove()
		return
	if not hit.is_empty() or (tip.y <= FIELD.project(Vector3(tip.x,0,tip.z)).y+.03 and velocity.y < 0.0):
		var ground: Vector3 = hit.position if not hit.is_empty() else FIELD.project(Vector3(tip.x,0,tip.z))
		global_position += ground+Vector3.UP*.03-tip
		landed = true
		set_physics_process(false)
		fade_and_remove()

func fade_and_remove() -> void:
	var meshes := find_children("*", "MeshInstance3D", true, false)
	var fade := create_tween()
	fade.tween_interval(GROUND_LIFETIME)
	fade.tween_callback(func():
		for mesh: MeshInstance3D in meshes:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	fade.tween_method(func(transparency: float):
		for mesh: MeshInstance3D in meshes:
			mesh.transparency = transparency
	, 0.0, 1.0, FADE_DURATION)
	fade.tween_callback(queue_free)
