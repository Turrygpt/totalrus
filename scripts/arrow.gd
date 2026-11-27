extends Node3D
const FIELD = preload("res://scripts/battlefield_bounds.gd")

const MODEL = preload("res://assets/arrow.glb")
const BODY_WOUNDS = preload("res://scripts/body_wounds.gd")
const MODEL_SCALE := .65
const TIP_OFFSET := .83 * MODEL_SCALE
const BODY_STAY := 1.0
const BODY_VIEW_DISTANCE := 42.0
var shooter: CharacterBody3D
var source_team := -1
var bow_damage_scale := 1.0
var velocity := Vector3.ZERO
var age := 0.0
var flight_query := PhysicsRayQueryParameters3D.new()
var mesh: Node3D
var flight_sound_played := false
var first_step := true
var body_bone := -1
var body_offset := Transform3D.IDENTITY

func launch(origin: Vector3, destination: Vector3) -> void:
	set_process(false)
	global_position = origin
	mesh = MODEL.instantiate()
	mesh.scale *= MODEL_SCALE
	add_child(mesh)
	velocity = launch_velocity(origin, destination)
	flight_query.collision_mask = 3
	flight_query.hit_from_inside = true
	if is_instance_valid(shooter): flight_query.exclude = [shooter.get_rid()]
	orient()

static func launch_velocity(origin: Vector3, destination: Vector3) -> Vector3:
	var flight := maxf(.35, origin.distance_to(destination) / 27.0)
	return (destination - origin) / flight + Vector3.UP * 4.905 * flight

static func ally_blocks_launch(archer: CharacterBody3D, origin: Vector3, destination: Vector3) -> bool:
	var launch_speed := launch_velocity(origin, destination)
	var space := archer.get_world_3d().direct_space_state
	var exclude: Array[RID] = [archer.get_rid()]
	var from := origin
	# Check the initial shaft and the first metres of actual flight. A shot
	# blocked by the front rank can wait; distant friendly fire still applies.
	for time: float in [0.0, .08, .16, .24]:
		var speed_at_time := launch_speed + Vector3.DOWN * 9.81 * time
		var to := origin + launch_speed * time + Vector3.DOWN * 4.905 * time * time
		to += speed_at_time.normalized() * TIP_OFFSET
		var query := PhysicsRayQueryParameters3D.create(from, to, 2, exclude)
		query.hit_from_inside = true
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit.collider is CharacterBody3D and hit.collider.get("team") == archer.team
		from = to
	return false

func orient() -> void:
	var axis := velocity.normalized()
	var side := axis.cross(Vector3.UP).normalized()
	if side.length_squared() < .1: side = Vector3.RIGHT
	global_basis = Basis(side,axis,side.cross(axis)).orthonormalized()

func _physics_process(delta: float) -> void:
	age += delta
	if age > 7:
		queue_free()
		return
	var old_tip := global_position if first_step else global_position + global_basis.y * TIP_OFFSET
	first_step = false
	global_position += velocity*delta+Vector3.DOWN*4.905*delta*delta
	velocity.y -= 9.81*delta
	orient()
	var tip := global_position + global_basis.y * TIP_OFFSET
	if not flight_sound_played and age >= .15:
		flight_sound_played = true
		var effects := get_tree().current_scene.get_node_or_null("BattleEffects")
		if effects: effects.sound("arrow_fly",global_position,-20.0)
	flight_query.from = old_tip
	flight_query.to = tip
	var hit := get_world_3d().direct_space_state.intersect_ray(flight_query)
	if not hit.is_empty() and hit.collider.has_method("receive_hit"):
		var friendly: bool = hit.collider.team == source_team
		var damage := randf_range(58.0, 72.0) * bow_damage_scale * (.25 if friendly else 1.0)
		if is_instance_valid(shooter): damage *= shooter.attack_damage_scale()
		var victim: CharacterBody3D = hit.collider
		if victim.receive_hit(damage,shooter,true,friendly,true,hit.position):
			embed_in_body(victim, hit.position)
		else:
			queue_free()
	elif not hit.is_empty() or (tip.y <= FIELD.project(Vector3(tip.x,0,tip.z)).y+.025 and velocity.y < 0):
		var contact: Vector3 = hit.position if not hit.is_empty() else FIELD.project(Vector3(tip.x,0,tip.z))
		var effects := get_tree().current_scene.get_node_or_null("BattleEffects")
		if effects: effects.sound("arrow_body",contact,-15.0)
		queue_free()

func embed_in_body(victim: CharacterBody3D, point: Vector3) -> void:
	if not victim.body_wounds: victim.body_wounds = BODY_WOUNDS.new()
	var anchor: Dictionary = victim.body_wounds.arrow_anchor(victim, point)
	if anchor.is_empty():
		queue_free()
		return
	global_position = anchor.tip - global_basis.y * TIP_OFFSET
	body_bone = anchor.index
	var pose: Transform3D = anchor.pose
	body_offset = pose.orthonormalized().affine_inverse() * global_transform
	set_physics_process(false)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reparent(victim)
	var lifetime := create_tween()
	lifetime.tween_interval(BODY_STAY)
	lifetime.tween_callback(queue_free)
	set_process(true)
	update_embedded_pose()

func _process(_delta: float) -> void:
	if body_bone >= 0: update_embedded_pose()

func update_embedded_pose() -> void:
	var victim: CharacterBody3D = get_parent()
	var camera := get_viewport().get_camera_3d()
	mesh.visible = camera == null or camera.global_position.distance_squared_to(victim.global_position) < BODY_VIEW_DISTANCE * BODY_VIEW_DISTANCE
	if mesh.visible:
		var pose: Transform3D = victim.body_wounds.world_bone(victim, body_bone, true)
		global_transform = pose.orthonormalized() * body_offset
