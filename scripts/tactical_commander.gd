extends Node

const FIELD = preload("res://scripts/battlefield_bounds.gd")
const BOW_RANGE := preload("res://scripts/archer.gd").BOW_RANGE
const REPLAN_INTERVAL := 1.0
const INFANTRY_CONTACT := 22.0
const PURSUIT_RANGE := 42.0
const CAVALRY_CONTACT := 14.0
const REAR_DEPTH := 10.0
const REGROUP_DISTANCE := 24.0

var attacking := false
var clock := .35
var positions := {}
var cavalry_maneuvers := {}
var infantry_maneuvers := {}
var withdrawals := {}
var regrouped_at := {}
var recent_engagements := {}
var matchup_preferences := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	attacking = get_parent().campaign_request.get("enemy_attack",false)

func _physics_process(delta: float) -> void:
	clock -= delta
	if clock > 0.0:
		return
	clock = REPLAN_INTERVAL
	var battle := get_parent()
	if not battle.result_text.is_empty():
		return
	var troops := []
	var opponents := []
	var routed := []
	for group in battle.squads:
		if group.team == 1:
			if group.ai_enabled: learn_from_engagement(group)
			if group.ai_enabled and group.is_physics_processing() and group.combat_ready() and not group.reforming_after_rout:
				troops.append(group)
			else:
				group.arrow_threat = null
				positions.erase(group)
				cavalry_maneuvers.erase(group)
				infantry_maneuvers.erase(group)
				withdrawals.erase(group)
				regrouped_at.erase(group)
		elif group.combat_ready():
			opponents.append(group)
		elif group.routed and not group.surrendered and group.alive_count() > 0:
			routed.append(group)
	if troops.is_empty():
		return
	if opponents.is_empty():
		for group in withdrawals.keys():
			group.stop()
			positions.erase(group)
		withdrawals.clear()
		infantry_maneuvers.clear()
		var pursuers := troops.filter(func(group): return group.unit_kind == "light_cavalry")
		if pursuers.is_empty(): pursuers = troops
		for group in pursuers:
			if group.resume_after_reform: continue
			var fleeing_enemy := choose_target(group,routed,{})
			if fleeing_enemy: attack(group,fleeing_enemy,true)
		for group in troops:
			if group.is_melee_cavalry() and not pursuers.has(group) and (routed.has(group.attack_target) or cavalry_maneuvers.has(group)):
				positions.erase(group)
				cavalry_maneuvers.erase(group)
				group.stop()
		return
	var field_battle: bool = battle.siege_gates.is_empty()
	if field_battle:
		for group in troops:
			if not uses_bow(group):
				plan_withdrawal(group,opponents,troops,battle.battle_time)
	var line := troops.filter(func(group):
		return not uses_bow(group) and not group.is_melee_cavalry() and not withdrawals.has(group)
	)
	var screen := opponents.filter(func(group): return not uses_bow(group))
	if battle.campaign_request.is_empty():
		attacking = attacking or battle.auto_battle or battle.battle_time > 12.0
	var engaged := troops.any(func(group): return opponents.any(func(other): return group.center().distance_squared_to(other.center()) < 26.0 * 26.0))
	var press := attacking
	var front := troops.filter(func(group): return not group.commander_guard and not withdrawals.has(group))
	var assignments := {}
	var gate_load := {}
	var flank := pick_infantry_flanker(line,opponents) if field_battle and (press or engaged) else {}
	for group in troops:
		if withdrawals.has(group) or group.ranged_retreat_goal.is_finite():
			continue
		var arrow_threat: Node3D
		if field_battle and opponents.has(group.arrow_threat):
			arrow_threat = group.arrow_threat
		else:
			group.arrow_threat = null
		var field_cavalry: bool = field_battle and group.is_melee_cavalry()
		if group.resume_after_reform and not field_cavalry:
			continue
		if engaged and group.can_activate_inspiration() and troops.any(func(ally): return ally.morale < 75.0 and ally.center().distance_squared_to(group.center()) <= 2500.0):
			group.activate_inspiration()
		if group.commander_guard and not front.is_empty() and hold_commander(group,front,opponents,press and field_battle):
			continue
		if field_cavalry and (press or engaged or arrow_threat):
			plan_field_cavalry(group,opponents,routed,line,screen,assignments,press or engaged,arrow_threat)
			continue
		if not arrow_threat and group == flank.get("group") and plan_infantry_flank(group,flank,opponents):
			continue
		var target := choose_target(group,opponents,assignments)
		if group == flank.get("support"):
			target = flank.target
		elif arrow_threat and (not target or group.center().distance_squared_to(target.center()) > INFANTRY_CONTACT * INFANTRY_CONTACT):
			target = arrow_threat
		if not target:
			continue
		assignments[target] = assignments.get(target,0) + 1
		if group.can_activate_berserk() and group.morale < 55.0 and group.center().distance_squared_to(target.center()) < 225.0:
			group.activate_berserk()
		if press or arrow_threat or group == flank.get("support"):
			plan_attack(group,target,line,gate_load)
		else:
			plan_defense(group,target,gate_load)

func uses_bow(group: Node3D) -> bool:
	return group.uses_bows()

func army_centre(troops: Array) -> Vector3:
	var point := Vector3.ZERO
	for group in troops: point += group.center()
	return point / troops.size()

func learn_from_engagement(group: Node3D) -> void:
	var target: Node3D = group.attack_target
	var previous: Dictionary = recent_engagements.get(group,{})
	if not is_instance_valid(target) and previous.is_empty(): return
	var kills: int = group.soldiers.reduce(func(total,soldier): return total + soldier.kills,0)
	var remaining: int = group.alive_count()
	if not previous.is_empty():
		var gain: float = (kills - previous.kills) * 2.0 - (previous.remaining - remaining) * 2.5
		if not is_zero_approx(gain):
			var key: String = previous.matchup
			matchup_preferences[key] = clampf(matchup_preferences.get(key,0.0) + gain,-14.0,14.0)
	if is_instance_valid(target) and not target.surrendered and remaining > 0:
		recent_engagements[group] = {"matchup":"%s/%s" % [group.unit_kind,target.unit_kind],"kills":kills,"remaining":remaining}
	else:
		recent_engagements.erase(group)

func choose_target(group: Node3D, opponents: Array, assignments: Dictionary) -> Node3D:
	var best: Node3D
	var strongest := INF
	var from: Vector3 = group.center()
	var horse: bool = group.is_melee_cavalry()
	var committed: Node3D = group.attack_target
	if is_instance_valid(committed) and committed in opponents and not horse and from.distance_squared_to(committed.center()) < 32.0 * 32.0:
		return committed
	for other in opponents:
		var distance: float = from.distance_to(other.center())
		var score := distance + float(assignments.get(other,0)) * 9.0
		if other == group.attack_target: score -= 8.0
		if horse and other.is_ranged(): score -= 16.0
		if horse and other.spear_count() * 2 >= other.alive_count(): score += 10.0
		score -= matchup_preferences.get("%s/%s" % [group.unit_kind,other.unit_kind],0.0)
		score -= maxf(0.0,50.0 - other.morale) * .15
		score -= (1.0 - float(other.alive_count()) / other.unit_count) * 8.0
		if distance < 12.0: score -= 16.0
		if score < strongest:
			strongest = score
			best = other
	return best

func plan_withdrawal(group: Node3D, opponents: Array, troops: Array, now: float) -> void:
	var origin: Vector3 = group.center()
	var threat: Node3D
	var pressure_gap := INF
	for other in opponents:
		var gap: float = origin.distance_to(other.center()) - other.cohesion_radius
		if gap < pressure_gap:
			pressure_gap = gap
			threat = other
	var under_pressure: bool = pressure_gap < group.cohesion_radius + 8.0
	var active: Dictionary = withdrawals.get(group,{})
	if not active.is_empty():
		var arrived: bool = origin.distance_squared_to(active.point) < 25.0
		var recovered: bool = group.morale >= minf(60.0,group.morale_target() - 2.0) and group.stamina >= 35.0
		var pressed_again: bool = under_pressure and (arrived or now - active.started > 16.0)
		if pressed_again or (not under_pressure and recovered and (arrived or now - active.started > 16.0)):
			withdrawals.erase(group)
			regrouped_at[group] = now
			return
		var heading: Vector3 = ground_direction(origin,threat.center()) if arrived else active.heading
		position_group(group,active.point,heading,not arrived,false,arrived and not group.is_mounted())
		group.state_text = "Собираются за линией" if arrived else "Отходят за линию"
		return
	if not under_pressure or group.berserk_remaining > 0.0 or now - regrouped_at.get(group,-INF) < 12.0:
		return
	if group.morale >= 30.0 or group.alive_count() > group.unit_count * .36:
		return
	if group.recent_hit_time <= 0.0 and threat.attack_target != group and group.attack_target != threat:
		return
	var away := ground_direction(threat.center(),origin)
	if away.is_zero_approx(): away = Vector3.FORWARD
	var cover: Node3D
	var cover_gap := 48.0
	for ally in troops:
		if ally == group or ally.is_mounted() or uses_bow(ally) or ally.morale < 55.0 or withdrawals.has(ally):
			continue
		var gap: float = origin.distance_to(ally.center())
		if gap < cover_gap:
			cover_gap = gap
			cover = ally
	if not cover:
		return
	var best := Vector3.INF
	var best_score := -INF
	for angle: float in [0.0,PI / 4.0,-PI / 4.0,PI / 2.0,-PI / 2.0]:
		var point := FIELD.clamp_ground(origin + away.rotated(Vector3.UP,angle) * REGROUP_DISTANCE,get_parent().field_half_size,12.0)
		if origin.distance_squared_to(point) < 64.0 or not maneuver_path_clear(origin,point,opponents,threat):
			continue
		var clearance := INF
		for other in opponents:
			clearance = minf(clearance,point.distance_to(other.center()) - other.cohesion_radius)
		if clearance <= pressure_gap + 6.0:
			continue
		var score := clearance - .55 * point.distance_to(cover.center())
		if score > best_score:
			best_score = score
			best = point
	if not best.is_finite():
		return
	withdrawals[group] = {"point":best,"heading":ground_direction(origin,best),"started":now}
	infantry_maneuvers.erase(group)
	cavalry_maneuvers.erase(group)
	position_group(group,best,ground_direction(origin,best),true)
	group.state_text = "Отходят за линию"

func pick_infantry_flanker(line: Array, opponents: Array) -> Dictionary:
	for group in infantry_maneuvers.keys():
		var maneuver: Dictionary = infantry_maneuvers[group]
		if group in line and maneuver.support in line and maneuver.target in opponents and supporting_infantry(maneuver.target,[maneuver.support]):
			return maneuver
		infantry_maneuvers.erase(group)
	var flank := {}
	var best_score := INF
	for support in line:
		var target: Node3D = support.attack_target
		if not opponents.has(target) or not supporting_infantry(target,[support]):
			continue
		var point: Vector3 = target.center()
		var advance := ground_direction(support.center(),point)
		if advance.is_zero_approx():
			continue
		var lateral := advance.cross(Vector3.UP)
		for group in line:
			var offset: Vector3 = group.center() - point
			var distance := offset.length()
			if group == support or group.morale < 60.0 or group.stamina < 40.0 or group.resume_after_reform or distance < 16.0 or distance > 55.0:
				continue
			if opponents.any(func(other): return group.center().distance_to(other.center()) < other.cohesion_radius + 8.0):
				continue
			var score := distance - .6 * absf(offset.dot(lateral))
			if score < best_score:
				best_score = score
				flank = {"group":group,"support":support,"target":target,"advance":advance,
					"side":signf(offset.dot(lateral)),"deadline":get_parent().battle_time + 22.0}
	if not flank.is_empty():
		if is_zero_approx(flank.side): flank.side = 1.0
		infantry_maneuvers[flank.group] = flank
	return flank

func plan_infantry_flank(group: Node3D, maneuver: Dictionary, opponents: Array) -> bool:
	var target: Node3D = maneuver.target
	var origin: Vector3 = group.center()
	var point: Vector3 = target.center()
	if group.attack_target == target and maneuver.get("committed",false):
		return true
	var advance: Vector3 = maneuver.advance
	var from_flank := ground_direction(point,origin).dot(advance) > -.25
	if from_flank and maneuver_path_clear(origin,point,opponents,target):
		attack(group,target,true)
		maneuver.committed = true
		return true
	if get_parent().battle_time < maneuver.deadline:
		var waypoint := maneuver_bypass(origin,point,target,opponents,maneuver,4.0)
		if waypoint.is_finite():
			position_group(group,waypoint,ground_direction(origin,waypoint),true)
			group.state_text = "Заходят во фланг"
			return true
	infantry_maneuvers.erase(group)
	return false

func plan_field_cavalry(group: Node3D, opponents: Array, routed: Array, line: Array, screen: Array, assignments: Dictionary, advance_order: bool, arrow_threat: Node3D) -> void:
	var light: bool = group.unit_kind == "light_cavalry"
	var origin: Vector3 = group.center()
	var threats := opponents.filter(func(other):
		if uses_bow(other): return false
		var threat_range := CAVALRY_CONTACT
		if other.attack_target == group: threat_range = group.cohesion_radius + other.cohesion_radius + 10.0
		return origin.distance_squared_to(other.center()) < threat_range * threat_range
	)
	var independent := line.is_empty()
	if group.resume_after_reform:
		if threats.is_empty() and not independent and not arrow_threat: return
		group.resume_after_reform = false
	if not light and opponents.has(group.attack_target) and (threats.is_empty() or threats.has(group.attack_target)):
		attack(group,group.attack_target,true)
		return
	var targets := opponents
	if not threats.is_empty():
		targets = threats
	elif arrow_threat:
		targets = [arrow_threat]
	elif light:
		var pursuit := routed.filter(func(other): return origin.distance_squared_to(other.center()) <= PURSUIT_RANGE * PURSUIT_RANGE or group.attack_target == other)
		var archers := opponents.filter(func(other): return other.unit_kind == "archer")
		if not pursuit.is_empty(): targets = pursuit
		elif not archers.is_empty(): targets = archers
	else:
		var pinned := opponents.filter(func(other): return supporting_infantry(other,line) != null)
		if not pinned.is_empty(): targets = pinned
	var maneuver: Dictionary = cavalry_maneuvers.get(group,{})
	var target: Node3D = maneuver.get("target")
	if not targets.has(target): target = choose_target(group,targets,assignments)
	assignments[target] = assignments.get(target,0) + 1
	var point: Vector3 = target.center()
	var gap := origin.distance_to(point)
	if not threats.is_empty() and gap < CAVALRY_CONTACT:
		attack(group,target,true)
		return
	var support := supporting_infantry(target,line)
	var line_center: Vector3 = group.spawn_center if line.is_empty() else army_centre(line)
	var advance := ground_direction(line_center,point)
	if support: advance = ground_direction(support.center(),point)
	if advance.is_zero_approx(): advance = Vector3.BACK
	var lateral := advance.cross(Vector3.UP)
	var preferred_side := -1.0 if (group.spawn_center - line_center).dot(lateral) < 0.0 else 1.0
	var countering_fire := target == arrow_threat
	var can_leave := advance_order or countering_fire or independent or gap < 55.0
	var can_charge := light or countering_fire or support != null or independent or not threats.is_empty()
	if not can_leave or not can_charge:
		cavalry_maneuvers.erase(group)
		var reserve: Vector3 = group.spawn_center if line.is_empty() else line_center - advance * 12.0 + lateral * preferred_side * 18.0
		position_group(group,reserve,advance,true)
		group.state_text = "В резерве"
		return
	if group.attack_target == target:
		attack(group,target,true)
		return
	var now: float = get_parent().battle_time
	if maneuver.get("target") != target:
		maneuver = {"target":target,"advance":advance,"side":preferred_side,"deadline":now + 10.0 + gap / 5.0}
		cavalry_maneuvers[group] = maneuver
	advance = maneuver.advance
	var blockers := screen.duplicate()
	if not target.routed and not blockers.has(target) and not light:
		blockers.append(target)
	var clear := maneuver_path_clear(origin,point,blockers,target)
	var from_flank := ground_direction(point,origin).dot(advance) > -.4
	var try_rear := not light and support != null
	var from_rear: bool = (origin - point).dot(advance) >= REAR_DEPTH and ground_direction(point,origin).dot(advance) > .28
	if clear and (from_rear or (not try_rear and from_flank) or (light and (target.is_ranged() or target.routed)) or (countering_fire and support == null)):
		attack(group,target,true)
		return
	var waypoint := maneuver_bypass(origin,point,target,blockers,maneuver,18.0 if try_rear else 5.0)
	if waypoint.is_finite() and now < maneuver.deadline:
		position_group(group,waypoint,ground_direction(origin,waypoint),true)
		group.state_text = "Заходят в тыл" if try_rear else "Обходят строй"
	elif clear and from_flank:
		attack(group,target,true)
	elif independent or not threats.is_empty() or (not light and support != null):
		# The cavalry must commit if the infantry is gone or the enemy closes the route.
		attack(group,target,true)
	elif positions.has(group) or is_instance_valid(group.attack_target):
		positions.erase(group)
		group.stop()

func supporting_infantry(target: Node3D, line: Array) -> Node3D:
	var nearest: Node3D
	var limit := INFANTRY_CONTACT * INFANTRY_CONTACT
	for ally in line:
		if infantry_maneuvers.has(ally): continue
		var distance: float = ally.center().distance_squared_to(target.center())
		if distance < limit and (ally.attack_target == target or target.attack_target == ally or distance < 14.0 * 14.0):
			limit = distance
			nearest = ally
	return nearest

func ground_direction(from: Vector3, to: Vector3) -> Vector3:
	return Vector3(to.x - from.x,0.0,to.z - from.z).normalized()

func maneuver_path_clear(from: Vector3, to: Vector3, blockers: Array, target: Node3D = null) -> bool:
	from.y = 0.0
	to.y = 0.0
	for obstacle in blockers:
		if obstacle == target: continue
		var centre: Vector3 = obstacle.center()
		centre.y = 0.0
		var nearest := Geometry3D.get_closest_point_to_segment(centre,from,to)
		var clearance: float = obstacle.cohesion_radius + 5.0
		if nearest.distance_squared_to(centre) < minf(clearance * clearance,from.distance_squared_to(centre)) - .1:
			return false
	return true

func maneuver_bypass(origin: Vector3, point: Vector3, target: Node3D, blockers: Array, maneuver: Dictionary, exit_depth: float) -> Vector3:
	var advance: Vector3 = maneuver.advance
	var bounds: Vector2 = get_parent().field_half_size
	var best := Vector3.INF
	var best_score := INF
	var best_side: float = maneuver.side
	var starting_depth := minf(0.0,(origin - point).dot(advance))
	for side: float in [maneuver.side,-maneuver.side]:
		var outward := advance.cross(Vector3.UP) * side
		var edge: float = maxf(17.0,target.cohesion_radius + 6.0)
		for obstacle in blockers:
			var offset: Vector3 = obstacle.center() - point
			var clearance: float = obstacle.cohesion_radius + 7.0
			var depth := offset.dot(advance)
			if depth >= starting_depth - clearance and depth <= exit_depth + clearance:
				edge = maxf(edge,offset.dot(outward) + clearance)
		var exit := FIELD.clamp_ground(point + outward * edge + advance * exit_depth,bounds,12.0)
		if (exit - point).dot(advance) < exit_depth - 2.0: continue
		if ground_direction(point,exit).dot(advance) <= -.4: continue
		var entry := FIELD.clamp_ground(exit + advance * minf(0.0,(origin - exit).dot(advance)),bounds,12.0)
		var direct := maneuver_path_clear(origin,exit,blockers)
		if not direct and (origin.distance_squared_to(entry) < 3.0 or not maneuver_path_clear(origin,entry,blockers) or not maneuver_path_clear(entry,exit,blockers)):
			continue
		if not maneuver_path_clear(exit,point,blockers,target): continue
		var cost := origin.distance_to(exit) if direct else origin.distance_to(entry) + entry.distance_to(exit)
		cost += exit.distance_to(point) + (0.0 if side == maneuver.side else 8.0)
		if cost < best_score:
			best_score = cost
			best = exit if direct else entry
			best_side = side
	maneuver.side = best_side
	return best

func plan_attack(group: Node3D, target: Node3D, line: Array, gate_load: Dictionary) -> void:
	var battle := get_parent()
	var origin: Vector3 = group.center()
	var point: Vector3 = target.center()
	var gap := origin.distance_to(point)
	var bow := uses_bow(group)
	if not battle.siege_gates.is_empty() and group.members.any(func(s): return s.position.z < battle.siege_line + 2.0):
		var gate := choose_gate(group,point.x,gate_load)
		group.siege_gate = gate
		if bow and gap < BOW_RANGE - 8.0 and not line.is_empty():
			attack(group,target,false)
		else:
			position_group(group,Vector3(gate,0,battle.siege_line+22.0),Vector3.BACK,true,true)
		return
	attack(group,target,group.is_melee_cavalry() or (not bow and gap < 24.0))

func hold_commander(group: Node3D, front: Array, opponents: Array, follow: bool) -> bool:
	var origin: Vector3 = group.center()
	if opponents.any(func(other): return origin.distance_squared_to(other.center()) < 14.0 * 14.0):
		return false
	var guard: Vector3 = group.spawn_center
	if not follow and not is_instance_valid(group.attack_target):
		return true
	if follow:
		var middle := army_centre(front)
		var nearest := choose_target(group,opponents,{})
		var forward := ground_direction(middle,nearest.center()) if nearest else Vector3.BACK
		guard = middle - forward * (group.cohesion_radius + 20.0)
		guard = FIELD.clamp_ground(guard,get_parent().field_half_size,4.0)
	if group.attack_target or origin.distance_squared_to(guard) > 16.0 * 16.0:
		position_group(group,guard,Vector3.BACK,false)
	return true

func plan_defense(group: Node3D, target: Node3D, gate_load: Dictionary) -> void:
	var battle := get_parent()
	var origin: Vector3 = group.center()
	var point: Vector3 = target.center()
	var bow := uses_bow(group)
	var horse: bool = group.is_melee_cavalry()
	var gap := origin.distance_to(point)
	var fortified: bool = not battle.siege_gates.is_empty()
	var guard: Vector3 = group.spawn_center
	var direction := Vector3.BACK
	var closing: bool = not fortified and group.attack_target == target and gap < 30.0
	if fortified:
		var gate := choose_gate(group,point.x,gate_load)
		guard = Vector3(gate,0,battle.siege_line - (16.0 if bow or horse else 7.0))
		group.siege_gate = gate
	var bow_range := BOW_RANGE + 8.0 if group.defending_order and group.attack_target == target else BOW_RANGE - 8.0
	if bow and gap < bow_range:
		attack(group,target,false,true)
	elif horse and gap < 20.0 and (not fortified or point.z < battle.siege_line or (point.z-battle.siege_line < 4.0 and absf(point.x-guard.x) < 7.0)):
		attack(group,target,true)
	elif not bow and (closing or gap < group.cohesion_radius * .65 + 8.0) and (not fortified or point.z < battle.siege_line + 1.0):
		var brace: bool = group.defending_order and group.spear_count() * 2 >= group.alive_count() and group.members.any(func(s): return s.position.distance_squared_to(point) < 20.0)
		attack(group,target,false,brace)
	else:
		if not fortified and not positions.has(group) and not is_instance_valid(group.attack_target):
			return
		position_group(group,guard,direction,fortified,fortified,not bow and not horse)

func choose_gate(group: Node3D, enemy_x: float, loads: Dictionary) -> float:
	var gate := INF
	var lowest := INF
	for candidate: float in get_parent().siege_gates:
		var score: float = absf(enemy_x-candidate) + absf(group.center().x-candidate) * .6 + loads.get(candidate,0) * 10.0
		if group.siege_gate == candidate: score -= 9.0
		if score < lowest:
			lowest = score
			gate = candidate
	loads[gate] = loads.get(gate,0) + 1
	return gate

func attack(group: Node3D, target: Node3D, running: bool, hold := false) -> void:
	if group.stamina < 30.0 and not target.routed:
		running = false
	if group.attack_target == target and group.defending_order == hold:
		# Retargeting a charge inside its run-up resets riders' individual passes.
		var slow_down: bool = group.stamina < 30.0 and not running and group.running_attack
		if slow_down and group.is_melee_cavalry():
			slow_down = not group.members.any(func(soldier): return soldier.penetrating_charge())
		if (running and not group.running_attack) or slow_down:
			group.command_attack(target,running,hold)
		return
	positions.erase(group)
	group.command_attack(target,running,hold)

func position_group(group: Node3D, point: Vector3, direction: Vector3, running: bool, narrow := false, hold := false) -> void:
	running = running and group.stamina >= 35.0
	var heading := atan2(-direction.x,-direction.z)
	var old: Dictionary = positions.get(group,{})
	if old.has("point") and old.running == running and old.hold == hold and old.narrow == narrow and old.point.distance_squared_to(point) < 20.0 and absf(angle_difference(old.heading,heading)) < .5 and not is_instance_valid(group.attack_target):
		return
	positions[group] = {"point":point,"heading":heading,"running":running,"hold":hold,"narrow":narrow}
	var columns: int = group.formation_columns
	var width: float = group.formation_width
	var spacing := 0.0
	if narrow:
		columns = 4 if group.is_mounted() else 5
		width = 7.2
		spacing = 3.35 if group.is_mounted() else 1.55
	var slots: Array[Vector3] = group.make_formation_slots(point,heading,columns,width,spacing)
	group.command_formation({"slots":slots,"columns":columns,"width":width,"heading":heading,"hold":hold},running)
