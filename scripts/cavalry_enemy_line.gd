extends Node3D

const Soldier = preload("res://scripts/soldier.gd")
const Rider = preload("res://scripts/horseman.gd")
const BracePose = preload("res://scripts/cavalry_brace_pose.gd")
const CHARGE = preload("res://scripts/cavalry_charge.gd")
const SpearCombat = preload("res://scripts/spear_combat.gd")
const COUNT := 30

var soldiers: Array[Soldier] = []
var waiting := PackedFloat32Array()
var windups := PackedFloat32Array()
var strike_clips: Array[String] = []
var strike_elapsed := PackedFloat32Array()
var next_contacts := PackedInt32Array()
var strike_contacts: Array = []
var targets: Array[Rider] = []
var search_wait := PackedFloat32Array()
var detour := PackedFloat32Array()
var walking_grace := PackedFloat32Array()
var impact_velocity := PackedVector3Array()
var charge_recovery := PackedFloat32Array()
var alive_count := COUNT
var bracing := false
var incoming := Vector3.BACK
var line_yaw := 0.0
var wanted_yaw := 0.0
var turn_delay := 0.0
var pivot := Vector3.ZERO
var line_slots := PackedVector3Array()

func _ready() -> void:
	var brace_animation: AnimationLibrary
	for index in COUNT:
		var soldier := Soldier.new()
		soldier.index = index
		soldier.team = 1
		soldier.appearance_index = index % Soldier.BODY_TEXTURES.size()
		soldier.position = Vector3((index % 10 - 4.5) * 1.31, 0, floorf(index / 10.0) * 1.39)
		soldier.position.x += .23 * sin(index * 2.23)
		soldier.position.z += .31 * cos(index * 1.56)
		soldier.rotation.y = .10 * sin(index * 1.73)
		add_child(soldier)
		soldier.set_physics_process(false)
		soldier.set_process(false)
		soldier.collision_mask = 0
		soldier.agent.avoidance_enabled = false
		if brace_animation == null:
			brace_animation = BracePose.make(soldier)
		soldier.player.add_animation_library(&"cavalry", brace_animation)
		soldier.animation_map["brace_spear"] = &"cavalry/brace_spear"
		soldier.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		soldier.play_clip("idle_spear", .1)
		soldiers.append(soldier)
		waiting.append(float(index % 5) * .075)
		windups.append(-1.0)
		strike_clips.append("")
		strike_elapsed.append(0.0)
		next_contacts.append(0)
		strike_contacts.append([])
		targets.append(null)
		search_wait.append(float(index % 7) * .043)
		detour.append(0.0)
		walking_grace.append(0.0)
		impact_velocity.append(Vector3.ZERO)
		charge_recovery.append(0.0)
		line_slots.append(Vector3.ZERO)

func brace(direction: Vector3) -> void:
	bracing = true
	incoming = direction
	wanted_yaw = atan2(direction.x, direction.z)
	var difference := absf(angle_difference(line_yaw, wanted_yaw))
	turn_delay = 4.10 if difference > 2.0 else (3.15 if difference > .66 else 0.0)
	pivot = living_center()
	for i in soldiers.size():
		var soldier := soldiers[i]
		if soldier.alive:
			line_slots[i] = (soldier.global_position - pivot).rotated(Vector3.UP, -line_yaw)
			if windups[i] < 0:
				targets[i] = null
				walking_grace[i] = 0.0
				soldier.play_clip("brace_spear", .28)

func relax_brace() -> void:
	bracing = false
	turn_delay = 0.0

func defense_direction() -> Vector3:
	return Vector3(sin(line_yaw), 0, cos(line_yaw))

func clicked(camera: Camera3D, cursor: Vector2, ground: Vector3) -> bool:
	if alive_count == 0:
		return false
	if absf(ground.x - position.x) <= 7.7 and absf(ground.z - position.z - 1.4) <= 2.9:
		return true
	for soldier in soldiers:
		var head := soldier.global_position + Vector3.UP * 1.15
		if soldier.alive and not camera.is_position_behind(head):
			if camera.unproject_position(head).distance_to(cursor) < 22.0:
				return true
	return false

func charge_target(from: Vector3, to: Vector3, forward: Vector3, contacted: int) -> Soldier:
	var best: Soldier
	var best_score := INF
	for soldier in soldiers:
		if not soldier.alive or charge_recovery[soldier.index] > 0.0 or (contacted & (1 << soldier.index)) != 0:
			continue
		var score := CHARGE.contact_score(soldier.global_position, from, to, forward)
		if score < best_score:
			best = soldier
			best_score = score
	return best

func charge_span(direction: Vector3) -> Vector2:
	var bounds := Vector2(INF, -INF)
	for soldier in soldiers:
		if soldier.alive:
			var distance := soldier.global_position.dot(direction)
			bounds.x = minf(bounds.x, distance)
			bounds.y = maxf(bounds.y, distance)
	return bounds

func living_center() -> Vector3:
	var total := Vector3.ZERO
	for soldier in soldiers:
		if soldier.alive:
			total += soldier.global_position
	return total / maxi(1, alive_count)

func hit(soldier: Soldier, damage: float, impulse: Vector3, charge_direction := Vector3.ZERO) -> void:
	if not soldier.alive:
		return
	var charge := not charge_direction.is_zero_approx()
	var direction := charge_direction if charge else impulse.normalized()
	var facing := soldier.basis.z.dot(direction)
	var shielded := facing > .45
	var exposed := charge and facing < .25
	var from_behind := clampf(-facing, 0.0, 1.0)
	var planted := shielded and bracing and soldier.animation_name == "brace_spear" and soldier.basis.z.dot(incoming) > .76
	if planted:
		var neighbors := 0
		for other in soldiers:
			if other != soldier and other.alive and other.animation_name == "brace_spear":
				neighbors += int(other.position.distance_squared_to(soldier.position) < 3.65)
		damage *= .56 if neighbors >= 2 else .76
		if charge:
			var axial := direction * impulse.dot(direction)
			impulse = axial * .39 + (impulse - axial) * (.64 if neighbors >= 2 else .81)
		else:
			impulse *= .4
	elif shielded and not soldier.animation_name.begins_with("attack_spear"):
		damage *= .72
	elif exposed:
		# A charge across the shield line scatters it. A hit squarely from behind lands harder.
		damage *= lerpf(.60, .87, from_behind)
	soldier.hp -= damage
	if soldier.hp <= 0:
		soldier.die()
		alive_count -= 1
	elif charge or not planted:
		soldier.play_clip("hit", .07)
	impact_velocity[soldier.index] = (impact_velocity[soldier.index] + impulse).limit_length(10.8 if charge else 7.0)
	if charge:
		charge_recovery[soldier.index] = 2.35 if exposed else .86
	if planted and soldier.alive and not charge:
		return
	_cancel_strike(soldier.index)
	waiting[soldier.index] = .74 if charge else .55

func _cancel_strike(index: int) -> void:
	windups[index] = -1.0
	strike_clips[index] = ""
	strike_elapsed[index] = 0.0
	next_contacts[index] = 0
	strike_contacts[index] = []

func _begin_strike(soldier: Soldier) -> void:
	var index := soldier.index
	var alias := soldier.next_spear_attack()
	var definition: Dictionary = SpearCombat.attack(alias)
	strike_clips[index] = alias
	strike_contacts[index] = SpearCombat.contacts(alias)
	# Compatibility while opening an older asset build; the integrated build
	# always uses one of the ten authored definitions above.
	if definition.is_empty():
		strike_contacts[index] = [{"time": .43}]
	windups[index] = float(definition.get("duration", 1.1))
	strike_elapsed[index] = 0.0
	next_contacts[index] = 0
	waiting[index] = .35 + float(index % 3) * .12
	soldier.animation_name = ""
	soldier.play_clip(alias, .085)

func _advance_strike(soldier: Soldier, delta: float) -> void:
	var index := soldier.index
	if not soldier.alive or soldier.animation_name != strike_clips[index]:
		_cancel_strike(index)
		return
	strike_elapsed[index] += delta
	windups[index] = maxf(0.0, windups[index] - delta)
	var contacts: Array = strike_contacts[index]
	# Consume every crossed contact once, even after a long frame. The double
	# jab has two contacts; the feint is absent from this damage-event list.
	while next_contacts[index] < contacts.size() and float(contacts[next_contacts[index]].time) <= strike_elapsed[index]:
		next_contacts[index] += 1
		var target := targets[index]
		if not is_instance_valid(target) or target.fallen: continue
		var reach := target.position - soldier.global_position
		if reach.length_squared() < 8.7 and (-soldier.basis.z).dot(reach.normalized()) > .43:
			# This scenario targets the exposed horse body below the rider's
			# shield. Infantry shield/open-zone tests live in Soldier combat.
			target.receive_cavalry_hit(32.0 if target.weapon_ready else 45.0)
	if windups[index] <= 0:
		_cancel_strike(index)
		soldier.play_clip("combat_spear", .18)

func defend(riders: Array[Rider], speeds: PackedFloat32Array, delta: float, pursuit := false) -> void:
	if bracing:
		if turn_delay > 0:
			turn_delay = maxf(0.0, turn_delay - delta)
		else:
			line_yaw = rotate_toward(line_yaw, wanted_yaw, .92 * delta)
	for index in soldiers.size():
		var soldier := soldiers[index]
		charge_recovery[index] = maxf(0.0, charge_recovery[index] - delta)
		if not impact_velocity[index].is_zero_approx():
			soldier.position += impact_velocity[index] * delta
			impact_velocity[index] = impact_velocity[index].move_toward(Vector3.ZERO, delta * 14.0)
		if not soldier.alive:
			_cancel_strike(index)
			continue
		walking_grace[index] = maxf(0.0, walking_grace[index] - delta)
		var point := soldier.global_position
		if windups[index] >= 0:
			_advance_strike(soldier, delta)
			continue
		waiting[index] = maxf(0.0, waiting[index] - delta)
		if waiting[index] > 0:
			continue
		if bracing and _counter_charge(soldier, riders, speeds):
			continue
		if bracing and turn_delay > 0:
			_hold_line(soldier, delta)
			continue
		var target := _find_target(soldier, riders, delta, pursuit)
		if target:
			var offset := target.position - point
			if offset.length_squared() <= 8.4:
				var heading := atan2(-offset.x, -offset.z)
				soldier.rotation.y = rotate_toward(soldier.rotation.y, heading, 1.85 * delta)
				if absf(angle_difference(soldier.rotation.y, heading)) < .19:
					_begin_strike(soldier)
				else:
					soldier.play_clip("combat_spear", .18)
			elif pursuit and _press(soldier, target.position, delta):
				walking_grace[index] = .18
				soldier.play_clip("advance_spear", .17)
			elif pursuit and walking_grace[index] <= 0.0:
				soldier.play_clip("combat_spear", .20)
		elif bracing:
			_hold_line(soldier, delta)
		else:
			soldier.play_clip("idle_spear", .23)

func _find_target(soldier: Soldier, riders: Array[Rider], delta: float, pursuit: bool) -> Rider:
	var index := soldier.index
	var target := targets[index]
	var limit := 225.0 if pursuit else 8.4
	var point := soldier.global_position
	if target and not target.fallen and point.distance_squared_to(target.position) < limit * 1.24:
		return target
	targets[index] = null
	search_wait[index] -= delta
	if search_wait[index] > 0.0:
		return null
	search_wait[index] = .27 + float(index % 7) * .032
	for rider in riders:
		if rider.fallen:
			continue
		var offset := rider.position - point
		var score := offset.length_squared()
		if bracing and soldier.animation_name == "brace_spear" and soldier.basis.z.dot(incoming) > .76:
			if offset.dot(-incoming) > .65 and rider.gait == &"Gallop":
				continue
		if score < limit:
			targets[index] = rider
			limit = score
	return targets[index]

func _hold_line(soldier: Soldier, delta: float) -> void:
	soldier.rotation.y = rotate_toward(soldier.rotation.y, line_yaw, 1.42 * delta)
	var station := pivot + line_slots[soldier.index].rotated(Vector3.UP, line_yaw)
	if turn_delay <= 0.0 and soldier.global_position.distance_squared_to(station) > .24:
		var step := soldier.global_position.move_toward(station, 1.42 * delta)
		if _room(soldier, to_local(step)):
			soldier.global_position = step
			walking_grace[soldier.index] = .18
			soldier.play_clip("advance_spear", .21)
			return
	if walking_grace[soldier.index] <= 0.0:
		soldier.play_clip("brace_spear", .18)

func _counter_charge(soldier: Soldier, riders: Array[Rider], speeds: PackedFloat32Array) -> bool:
	if soldier.animation_name != "brace_spear" or soldier.basis.z.dot(incoming) < .76:
		return false
	var point := soldier.global_position
	var target := -1
	var closest := 3.5
	for i in riders.size():
		var rider := riders[i]
		if rider.fallen or rider.spear_immunity > 0.0 or speeds[i] < 2.5:
			continue
		if rider.basis.z.dot(incoming) < .4:
			continue
		var offset := point - rider.position
		var front := offset.dot(incoming)
		var lateral := (offset - incoming * front).length()
		if lateral < 1.05 and front > .4 and front < closest:
			closest = front
			target = i
	if target < 0:
		return false
	if riders[target].receive_braced_spear(speeds[target], soldier.rng.randf()):
		waiting[soldier.index] = .68
		soldier.play_clip("brace_spear", .12)
		return true
	return false

func _press(soldier: Soldier, target: Vector3, delta: float) -> bool:
	var direction := soldier.global_position.direction_to(target)
	var preferred: float = detour[soldier.index]
	for turn: float in [preferred, 0.0, .77, -.77]:
		var walk := direction.rotated(Vector3.UP, turn)
		var heading := atan2(-walk.x, -walk.z)
		if _room(soldier, soldier.position + walk * .28):
			soldier.rotation.y = rotate_toward(soldier.rotation.y, heading, 1.72 * delta)
			var forward := -soldier.basis.z
			if forward.dot(walk) < .62:
				return false
			var next := soldier.position + forward * 1.15 * delta
			if not _room(soldier, next):
				return false
			soldier.position = next
			detour[soldier.index] = turn
			return true
	return false

func _room(soldier: Soldier, point: Vector3) -> bool:
	for other in soldiers:
		if other != soldier and other.alive and point.distance_squared_to(other.position) < .73:
			if point.distance_squared_to(other.position) <= soldier.position.distance_squared_to(other.position):
				return false
	return true
