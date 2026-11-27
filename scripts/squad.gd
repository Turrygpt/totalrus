extends Node3D
const PROF = preload("res://scripts/profile_counters.gd")
const FIELD = preload("res://scripts/battlefield_bounds.gd")
const Experience = preload("res://scripts/unit_experience.gd")
const Charge = preload("res://scripts/cavalry_charge.gd")
const Equipment = preload("res://scripts/unit_equipment.gd")

const SOLDIER = preload("res://scripts/soldier.gd")
const SOLDIER_COUNT := 60
const CAVALRY_COLUMN_SPACING := 2.45
const CAVALRY_ROW_SPACING := 4.08
const MAX_FORMATION_WIDTH := 32.0

enum Behavior { PEACEFUL, HOLD, RETALIATE, AGGRESSIVE }
const BEHAVIOR_NAMES := ["Мирный", "Стоять ровно", "Режим ответа на атаку", "Режим агрессии"]

var soldiers: Array = []
var selected := true
var state_text := "Ожидание"
var order_heading := 0.0
var pending_order := {}
var team := 0
var uniform_color: Color:
	get:
		return uniform_dye if uniform_dye.a > 0.0 else SOLDIER.TroopColors.SKIRMISH_COLORS[team]
var uniform_dye := Color.TRANSPARENT
var spawn_center := Vector3(0, 0, 15)
var spawn_heading := 0.0
var opponent: Node3D
var attack_target: Node3D
var incoming_cavalry: Node3D
var running_attack := false
var combat_timer := 0.0
var ai_enabled := true
var behavior_controlled := false
var behavior := Behavior.RETALIATE
var retaliation_target: Node3D
var behavior_attack := false
var defending_order := false
var victory_started := false
var unit_count := 60
var unit_kind := "infantry"
var unit_script: Script = preload("res://scripts/spearman_video_fighter.gd")
var display_name := ""
var commander_portrait := ""
var commander_guard := false
var faction_standard: Texture2D
var experience_points := 0.0
var starting_experience_points := 0.0
var experience_rank := 0
var experience_capacity := 0
var equipment := Vector2i.ZERO
var morale_bonus := 0.0
var stamina_discount := 0.0
var armor_reduction := 0.0
var participated := false
const MIN_RUNNING_STAMINA := 30.0
var stamina := 100.0
var formation_columns := 10
var formation_width := 15.3
var formation_density := 2
var field_half_size := FIELD.DEFAULT_HALF_SIZE
const DENSITY_SPACING := [.76, 1.0, 1.30]
var members: Array = []
var native_logic_groups: Array[Array] = []
var cached_center := Vector3.ZERO
var cohesion_radius := 16.0
var siege_gate := INF
var siege_counterattack := false
var cache_timer := 0.0
var serial := 0
var reinforcement_pending := false
var reform_delay := -1.0
var reforming := false
var reforming_after_rout := false
var resume_after_reform := false
var ranged_ready := false
var ranged_area := false
var melee_mode := false
var bow_orders_active := true
var fortified := false
var ranged_point := Vector3.ZERO
var volley_timer := 0.0
var volley_assembly := 0.0
var volley_count := 0
var arrows_remaining := 0
var volley_archers: Array = []
var firing_goal := Vector3.INF
var attack_formation := {}
var attack_formation_goal := Vector3.INF
var ranged_retreat_cooldown := 0.0
var ranged_retreat_goal := Vector3.INF
var ranged_retreat_stall := 0.0
var ranged_retreat_remaining := INF
var selection_rings: MultiMeshInstance3D
var selection_ring_buffer := PackedFloat32Array()
var show_selection_rings := true
const ARCHER = preload("res://scripts/archer.gd")
const BOW_RANGE := ARCHER.BOW_RANGE
const WAVER_THRESHOLD := 43.0
const RALLY_THRESHOLD := 50.0
const ROUT_THRESHOLD := 24.0
const SURRENDER_THRESHOLD := 15.0
const ROUT_RECOVERY_DELAY := 4.0
const ROUT_RECOVERY_RADIUS := 12.0
const ROUT_LEG_DISTANCE := 30.0
const ROUT_PURSUIT_LIMIT := 12.0
const RETREAT_EXIT_INSET := 0.6
const RETREAT_EXIT_TOLERANCE := 0.8
const LEADERSHIP_RADIUS := 18.0
const MORALE_RESOLVE := {"militia":-14.0, "archer":-5.0, "light_cavalry":-5.0, "cavalry":5.0, "princely":10.0, "varangian":12.0}
const MORALE_MULTIPLIER := 2.0
const BERSERK_DURATION := 60.0
const INSPIRATION_DURATION := 60.0
const INSPIRATION_RADIUS := 50.0
const INSPIRATION_MORALE := 20.0
var morale := 100.0
var berserk_remaining := 0.0
var berserk_used := false
var inspiration_used := false
var inspired_remaining := 0.0
var routed := false
var surrendered := false
var withdrawn_count := 0
var rout_safe_time := 0.0
var rout_pursuit_time := 0.0
var rout_goal := Vector3.ZERO
var recovering_from_rout := false
var break_pressure_time := 0.0
var last_rally_losses := 0.0
var wavering := false
var morale_elapsed := 0.0
var casualty_shock := 0.0
var incoming_pressure := 0.0
var recent_hit_time := 0.0
var arrow_threat: Node3D
var flank_pressure := 0.0
var spear_pressure := 0.0

func _ready() -> void:
	const SPAWN_BUDGET_USEC := 2500
	starting_experience_points = experience_points
	if is_ranged():
		arrows_remaining = 14 if is_mounted() else 12
	field_half_size = FIELD.for_scene(get_tree().current_scene)
	if not reinforcement_pending:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		add_to_group("squads")
		serial = get_tree().get_nodes_in_group("squads").size()-1
	combat_timer = fmod(serial * .071,.45)
	morale = minf(100.0, (resolve_morale() + Experience.morale(Experience.rank(experience_points))) * MORALE_MULTIPLIER)
	order_heading = spawn_heading
	if is_mounted():
		formation_columns = 6
		formation_width = (formation_columns - 1) * CAVALRY_COLUMN_SPACING
	if unit_kind == "archer":
		formation_width = 18.0
	var initial_spacing: float = DENSITY_SPACING[formation_density]
	formation_width *= initial_spacing
	combat_timer = fmod(serial*.073,.45)
	var appearances: Array[int] = []
	for i in unit_count:
		appearances.append(i % SOLDIER.BODY_TEXTURES.size())
	appearances.shuffle()
	var sotnik_slot := -1
	var shields: Array[int] = []
	var axes: Array[int] = []
	var rows := ceili(float(unit_count) / formation_columns)
	if unit_kind == "infantry" and unit_count > 0:
		sotnik_slot = mini(unit_count - 1, (rows / 2) * formation_columns + formation_columns / 2)
		for i in unit_count:
			shields.append(i % SOLDIER.SHIELD_VARIANT_COUNT)
		shields.shuffle()
	if unit_kind == "militia":
		for i in unit_count:
			shields.append(i % SOLDIER.ROUND_SHIELD_COUNT)
		shields.shuffle()
	if unit_kind == "varangian":
		for i in unit_count:
			shields.append(i % unit_script.SHIELD_COUNT)
			axes.append(i % unit_script.AXE_COUNT)
		shields.shuffle()
		axes.shuffle()
	var spawn_deadline := Time.get_ticks_usec() + SPAWN_BUDGET_USEC
	for i in unit_count:
		var soldier := CharacterBody3D.new()
		soldier.set_script(unit_script)
		soldier.cohesion_group = self
		soldier.weapon_damage_multiplier = Equipment.weapon_damage(equipment.x)
		soldier.armor_reduction = 1.0 - (1.0-armor_reduction) * (1.0-Equipment.armor_reduction(equipment.y))
		soldier.index = i
		soldier.is_sotnik = i == sotnik_slot
		if not shields.is_empty():
			soldier.shield_variant = shields[i]
		if not axes.is_empty():
			soldier.axe_variant = axes[i]
		soldier.team = team
		soldier.appearance_index = appearances[i]
		soldier.hair_index = randi_range(0, SOLDIER.HAIR_TONES.size() - 1)
		var spacing := formation_width / maxi(1, formation_columns - 1)
		var depth := 2.1 if unit_kind == "archer" else 1.75
		if is_mounted():
			depth = CAVALRY_ROW_SPACING
		var offset := formation_offset(i, formation_columns, unit_count, spacing, depth*initial_spacing, true)
		soldier.position = FIELD.project(spawn_center + offset.rotated(Vector3.UP, spawn_heading))
		var heading := spawn_heading + sin((serial+1)*7.3+i*2.4)*.075
		soldier.rotation.y = heading
		soldier.final_heading = heading
		add_child(soldier)
		soldiers.append(soldier)
		if reinforcement_pending and Time.get_ticks_usec() >= spawn_deadline and i + 1 < unit_count:
			await get_tree().process_frame
			spawn_deadline = Time.get_ticks_usec() + SPAWN_BUDGET_USEC
	members = soldiers.duplicate()
	set_experience(experience_points)
	make_selection_rings()
	refresh_center()
	if display_name.is_empty(): display_name = "СОКОЛ" if team == 0 else "ВЕПРЬ"
	if team == 1:
		selected = false
		state_text = "Держат позицию"
		for soldier in soldiers:
			soldier.guarding = not is_ranged()
			soldier.front_rank = soldier.index < 20

func activate_reinforcement() -> void:
	reinforcement_pending = false
	add_to_group("squads")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	show()
	var battlefield := get_tree().current_scene
	for soldier in soldiers:
		soldier.add_to_group("combatants")
		if soldier.crowd_visual and soldier.crowd_visual.distant:
			soldier.crowd_visual.last_tick = battlefield.battle_time
			if battlefield.crowd_movement.native != null:
				battlefield.crowd_renderer.sleeping_visuals.append(soldier.crowd_visual)
			soldier.crowd_visual.advance(0.0)

func living() -> Array:
	return members

func is_ranged() -> bool:
	return unit_kind in ["archer", "khazar"]

func uses_bows() -> bool:
	return arrows_remaining > 0 and not melee_mode and not members.is_empty()

func can_bombard() -> bool:
	return uses_bows() or (can_throw_spears() and spear_count() > 0)

func set_melee_mode(enabled: bool) -> void:
	if not is_ranged() or melee_mode == enabled: return
	melee_mode = enabled
	refresh_combat_mode()
	for soldier in members:
		soldier.update_weapon_mode()

func refresh_combat_mode() -> void:
	if not is_ranged(): return
	var bows := uses_bows()
	if bows == bow_orders_active: return
	bow_orders_active = bows
	var cancel_ranged_order := ranged_area or ranged_retreat_goal.is_finite()
	ranged_area = false
	ranged_ready = false
	volley_assembly = 0.0
	volley_archers.clear()
	ranged_retreat_goal = Vector3.INF
	firing_goal = Vector3.INF
	for soldier in members:
		if melee_mode: soldier.cancel_shot()
		if is_instance_valid(attack_target):
			soldier.combat_target = null
		elif cancel_ranged_order:
			soldier.stop()
	if is_instance_valid(attack_target):
		state_text = attack_state()
		attack_formation.clear()
		if not can_advance_in_formation() or not start_attack_formation():
			assign_combat_targets()
	elif cancel_ranged_order:
		state_text = "Ожидание"

func is_melee_cavalry() -> bool:
	return unit_kind in Charge.UNIT_KINDS

func is_heavy_cavalry() -> bool:
	return unit_kind in Charge.HEAVY_KINDS

func can_wedge_charge() -> bool:
	return is_heavy_cavalry() and running_attack and not defending_order and stamina >= Charge.WEDGE_MIN_STAMINA

func is_mounted() -> bool:
	return is_melee_cavalry() or unit_kind == "khazar"

func can_throw_spears() -> bool:
	return unit_kind == "infantry"

func record_experience_kill(routed_target: bool) -> void:
	var capacity := experience_capacity if experience_capacity > 0 else unit_count
	set_experience(Experience.earn_kills(experience_points,.5 if routed_target else 1.0,capacity))

func set_experience(points: float) -> void:
	experience_points = clampf(points,0.0,Experience.MAX_POINTS)
	var next_rank := Experience.rank(experience_points)
	if next_rank == experience_rank:
		return
	experience_rank = next_rank
	for soldier in members:
		soldier.experience_rank = next_rank

func make_selection_rings() -> void:
	selection_rings = MultiMeshInstance3D.new()
	selection_rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := TorusMesh.new()
	ring.inner_radius = .26
	ring.outer_radius = .29
	ring.rings = 16
	ring.ring_segments = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("cf6651") if team == 0 else Color("88c1df")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material = material
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = ring
	batch.instance_count = unit_count
	selection_ring_buffer.resize(unit_count * 12)
	for i in unit_count:
		var offset := i * 12
		selection_ring_buffer[offset] = 1.0
		selection_ring_buffer[offset+5] = 1.0
		selection_ring_buffer[offset+10] = 1.0
	selection_rings.multimesh = batch
	add_child(selection_rings)

func _process(_delta: float) -> void:
	update_selection_rings()

func update_selection_rings() -> void:
	selection_rings.visible = show_selection_rings and selected and combat_ready()
	if not selection_rings.visible: return
	selection_rings.multimesh.visible_instance_count = members.size()
	for i in members.size():
		var at: Vector3 = members[i].render_position()
		var offset := i * 12
		selection_ring_buffer[offset+3] = at.x
		selection_ring_buffer[offset+7] = at.y + .025
		selection_ring_buffer[offset+11] = at.z
	selection_rings.multimesh.buffer = selection_ring_buffer

func alive_count() -> int:
	return members.size()

func survivor_count() -> int:
	return alive_count() + withdrawn_count

func combat_ready() -> bool:
	return not routed and not members.is_empty()

func soldier_died(soldier: CharacterBody3D) -> void:
	members.erase(soldier)
	casualty_shock = minf(10.0, casualty_shock + 65.0 / unit_count)
	refresh_center()

func record_morale_hit(damage_fraction: float, charge_impact: bool) -> void:
	if surrendered or damage_fraction <= 0.0:
		return
	recent_hit_time = 2.5
	var impact := 140.0 if charge_impact else 72.0
	incoming_pressure = minf(19.0, incoming_pressure + damage_fraction * impact / unit_count)

func record_flank_hit(facing: float, damage: float) -> void:
	if not surrendered and facing < .35:
		var pressure := .18 if facing < -.35 else .09
		flank_pressure = minf(12.0, flank_pressure + damage * pressure * 60.0 / unit_count)

func record_spear_pressure(damage: float) -> void:
	if not routed:
		spear_pressure = minf(5.0, spear_pressure + damage * .10 * 60.0 / unit_count)

func resolve_morale() -> float:
	return 100.0 + MORALE_RESOLVE.get(unit_kind, 0.0) + morale_bonus

func morale_target() -> float:
	var losses := 1.0 - float(alive_count()) / unit_count
	var loss_morale := resolve_morale() - 100.0 * losses + Experience.morale(experience_rank)
	var desired := loss_morale - casualty_shock - incoming_pressure - flank_pressure - spear_pressure
	desired -= maxf(0.0,40.0-stamina) * .15
	var leadership := 0.0
	if unit_kind != "princely":
		for group in get_tree().get_nodes_in_group("squads"):
			if group.team == team and group.unit_kind == "princely" and group.combat_ready() and center().distance_squared_to(group.center()) <= LEADERSHIP_RADIUS * LEADERSHIP_RADIUS:
				leadership = 10.0
				break
	var inspiration := INSPIRATION_MORALE if inspired_remaining > 0 else 0.0
	return clampf((desired + leadership + inspiration) * MORALE_MULTIPLIER, 0.0, 100.0)

func can_activate_berserk() -> bool:
	return unit_kind == "varangian" and not berserk_used and not victory_started and combat_ready()

func activate_berserk() -> bool:
	if not can_activate_berserk():
		return false
	berserk_used = true
	berserk_remaining = BERSERK_DURATION
	wavering = false
	return true

func can_activate_inspiration() -> bool:
	return unit_kind == "princely" and not inspiration_used and not victory_started and combat_ready() and soldiers[0].alive and not soldiers[0].withdrawn

func activate_inspiration() -> bool:
	if not can_activate_inspiration():
		return false
	inspiration_used = true
	var leader: CharacterBody3D = soldiers[0]
	var origin := leader.global_position
	leader.raise_horn()
	var battlefield := get_tree().current_scene
	battlefield.show_inspiration(origin,INSPIRATION_RADIUS)
	for ally in battlefield.squads:
		if ally.team == team and not ally.surrendered and ally.alive_count() > 0 and origin.distance_squared_to(ally.center()) <= INSPIRATION_RADIUS * INSPIRATION_RADIUS:
			ally.receive_inspiration()
	return true

func receive_inspiration() -> void:
	if inspired_remaining <= 0:
		for soldier in members: soldier.set_inspired(true)
	inspired_remaining = INSPIRATION_DURATION
	morale = minf(100.0,morale+INSPIRATION_MORALE)
	if routed and morale >= RALLY_THRESHOLD:
		rally_from_rout()
	if not routed: wavering = morale < WAVER_THRESHOLD and berserk_remaining <= 0

func update_morale(delta := .45) -> void:
	if members.is_empty() or surrendered or victory_started or berserk_remaining > 0: return
	if routed:
		update_rout(delta)
		return
	var desired := morale_target()
	morale = move_toward(morale,desired,(6.0 if desired < morale else 9.0) * delta)
	var losses := 1.0 - float(alive_count()) / unit_count
	var breaking := morale <= ROUT_THRESHOLD and recent_hit_time > 0.0 and losses >= .42 and losses - last_rally_losses >= .12
	break_pressure_time = maxf(0.0,break_pressure_time + (delta if breaking else -2.0 * delta))
	if break_pressure_time >= 2.5:
		begin_rout()
		return
	wavering = morale < WAVER_THRESHOLD

func can_run() -> bool:
	return stamina >= MIN_RUNNING_STAMINA

func update_stamina(delta: float) -> void:
	var exertion := 0.0
	var walking := 0
	for soldier in members:
		if soldier.motion_speed > 2.5:
			exertion += 1.10
		elif soldier.motion_speed > .5:
			walking += 1
		if soldier.active_action.begins_with("attack") or (soldier.attack_order and is_instance_valid(soldier.combat_target) and soldier.position.distance_squared_to(soldier.combat_target.position) < 12.25):
			exertion += 1.35
		elif soldier.active_action in ["bow_draw","bow_release","throw_spear"]:
			exertion += .40
	var spent := exertion / members.size()
	var recovery := lerpf(.46,.44,float(walking) / members.size())
	var cost_multiplier := (1.5 if wavering else 1.0) * (1.0-stamina_discount) * Experience.stamina_cost(experience_rank)
	if unit_kind == "light_cavalry":
		cost_multiplier *= Charge.LIGHT_STAMINA_COST
	elif is_heavy_cavalry() and members.any(func(s): return s.wedge_charge and s.penetrating_charge()):
		spent += Charge.WEDGE_STAMINA_DRAIN
	var stamina_change := recovery if spent < .08 else -spent * cost_multiplier
	stamina = clampf(stamina + stamina_change * delta,0.0,100.0)
	if not can_run() and not routed:
		var running_move := state_text in ["Бег","Галоп"]
		if running_move: state_text = "Шаг"
		if running_attack:
			running_attack = false
			if not attack_formation.is_empty(): attack_formation_goal = Vector3.INF
			if is_instance_valid(attack_target) and state_text in ["Натиск","Выход на дистанцию бегом","Прорыв строя","Натиск клином","Удар клином"]:
				state_text = attack_state()
		var ranged := is_ranged()
		for soldier in members:
			if running_move or reforming or soldier.attack_order or (ranged and soldier.manual_move):
				soldier.charge = false
				if soldier.speed_limit > 2.5:
					soldier.speed_limit = 1.8
	var multiplier := lerpf(.72,1.0,minf(stamina / 70.0,1.0))
	for soldier in members:
		if not is_equal_approx(soldier.stamina_multiplier,multiplier):
			soldier.set_stamina_multiplier(multiplier)

func morale_state() -> String:
	if surrendered: return "Сдались"
	if routed: return "Собираются" if recovering_from_rout else "Отступают"
	if wavering: return "Дрогнули"
	return "Стойкие"

func begin_rout() -> void:
	if not combat_ready():
		return
	stop()
	routed = true
	rout_safe_time = 0.0
	rout_pursuit_time = 0.0
	recovering_from_rout = false
	wavering = false
	refresh_center()
	var index: Node = get_tree().current_scene.combat_index
	order_rout_leg(index.nearest(center(), team, cohesion_radius + ROUT_RECOVERY_RADIUS))
	state_text = "Отряд отступает"

func order_rout_leg(threat: CharacterBody3D) -> void:
	var rear := Vector3.BACK if team == 0 else Vector3.FORWARD
	var direction := rear
	if is_instance_valid(threat):
		var away := center() - threat.position
		away.y = 0.0
		direction = (rear + away.normalized() * .75).normalized()
	rout_goal = FIELD.clamp_ground(center() + direction * ROUT_LEG_DISTANCE, field_half_size, 2.0)
	var heading := atan2(-direction.x, -direction.z)
	if rout_goal.z * rear.z >= field_half_size.y - 2.0:
		order_retreat_to_edge()
		return
	var slots := make_formation_slots(rout_goal, heading, formation_columns, minf(formation_width, 15.0))
	var assignment := assign_slots(slots, members)
	rout_goal = Vector3.ZERO
	for i in members.size():
		var soldier: CharacterBody3D = members[i]
		soldier.flee(slots[assignment[i]], heading)
		rout_goal += soldier.target
	rout_goal /= members.size()

func surrender() -> void:
	if surrendered or members.is_empty():
		return
	if not routed:
		stop()
	routed = true
	surrendered = true
	recovering_from_rout = false
	wavering = false
	morale = minf(morale,SURRENDER_THRESHOLD)
	order_retreat_to_edge()
	for soldier in members:
		soldier.disarm_for_surrender()
	state_text = "Отряд сдался"

func order_retreat_to_edge() -> void:
	var direction := 1.0 if team == 0 else -1.0
	var heading := PI if team == 0 else 0.0
	var edge := direction * (field_half_size.y - RETREAT_EXIT_INSET)
	rout_goal = FIELD.project(Vector3(center().x, 0.0, edge))
	for soldier in members:
		var exit: Vector3 = soldier.position
		exit.z = edge
		soldier.flee(FIELD.project(exit), heading)

func withdraw_fleeing_soldiers(battle_finished := false) -> void:
	var direction := 1.0 if team == 0 else -1.0
	var edge := field_half_size.y - RETREAT_EXIT_INSET - RETREAT_EXIT_TOLERANCE
	for index in range(members.size() - 1, -1, -1):
		var soldier: CharacterBody3D = members[index]
		if not soldier.fleeing or (not battle_finished and soldier.position.z * direction < edge):
			continue
		soldier.leave_battlefield()
		members.remove_at(index)
		withdrawn_count += 1

func withdraw_surrendered_soldiers() -> void:
	withdraw_fleeing_soldiers()

func update_rout(delta: float) -> void:
	var battlefield := get_tree().current_scene
	var threat: CharacterBody3D = battlefield.combat_index.nearest(center(), team, ROUT_RECOVERY_RADIUS)
	if threat or recent_hit_time > 0.0:
		rout_safe_time = 0.0
		rout_pursuit_time += delta
		recovering_from_rout = false
		state_text = "Отряд отступает"
		morale = maxf(0.0, morale - (2.0 + incoming_pressure * .12) * delta)
		if rout_pursuit_time >= ROUT_PURSUIT_LIMIT and morale <= SURRENDER_THRESHOLD:
			surrender()
		elif center().distance_squared_to(rout_goal) < 16.0 and absf(rout_goal.z) < field_half_size.y - 2.0:
			order_rout_leg(threat)
		return
	rout_pursuit_time = 0.0
	rout_safe_time += delta
	if rout_safe_time < ROUT_RECOVERY_DELAY:
		return
	recovering_from_rout = true
	state_text = "Восстанавливают мораль"
	if morale < RALLY_THRESHOLD:
		morale = minf(RALLY_THRESHOLD, morale + 4.0 * delta)
	if morale < RALLY_THRESHOLD:
		return
	rally_from_rout()

func rally_from_rout() -> void:
	routed = false
	recovering_from_rout = false
	last_rally_losses = 1.0 - float(alive_count()) / unit_count
	break_pressure_time = 0.0
	for soldier in members:
		soldier.fleeing = false
	refresh_center()
	var battlefield := get_tree().current_scene
	var nearest_distance := INF
	for enemy in battlefield.squads:
		if enemy.team == team or not enemy.combat_ready():
			continue
		var direction: Vector3 = enemy.center() - center()
		direction.y = 0.0
		var distance := direction.length_squared()
		if distance > .01 and distance < nearest_distance:
			nearest_distance = distance
			order_heading = atan2(-direction.x, -direction.z)
	reform_after_battle()
	reforming_after_rout = true
	resume_after_reform = team == 0 and not behavior_controlled and battlefield.auto_battle

func refresh_center() -> void:
	if members.is_empty(): return
	cached_center = Vector3.ZERO
	for soldier in members: cached_center += soldier.position
	cached_center /= members.size()
	var columns := clampi(formation_columns,1,members.size())
	var width := formation_width * (columns - 1) / maxi(1,formation_columns - 1)
	var depth := (ceili(float(members.size()) / columns) - 1) * formation_row_spacing()
	cohesion_radius = clampf(Vector2(width,depth).length() * .5 + (4.5 if is_mounted() else 3.0),5.0,24.0)

func celebrate() -> void:
	if victory_started or not combat_ready():
		return
	victory_started = true
	wavering = false
	attack_target = null
	pending_order.clear()
	state_text = "Победа"
	reform_delay = 3.3
	for soldier in living():
		soldier.celebrate_victory()

func total_health() -> float:
	var health := 0.0
	for soldier in members:
		health += soldier.hp / soldier.max_hp
	return health / unit_count

func ammo_count() -> int:
	if can_throw_spears():
		return spear_count()
	return arrows_remaining

func center() -> Vector3:
	return cached_center

func spear_count() -> int:
	var count := 0
	for soldier in soldiers:
		count += int(soldier.has_spear and soldier.alive)
	return count

func is_busy() -> bool:
	return soldiers.any(func(s): return s.alive and s.busy and s.active_action in ["aim", "throw_spear", "draw_sword"])

func command(action: int, point: Vector3) -> void:
	if action == 4 and not can_bombard():
		return
	if action == 5 and not uses_spear_formation(): return
	if not combat_ready():
		return
	if is_busy():
		if action != 4:
			pending_order = {"action": action, "point": point}
		return
	if action == 2 and not can_run():
		action = 1
	attack_target = null
	attack_formation.clear()
	running_attack = false
	behavior_attack = false
	retaliation_target = null
	reforming = false
	reforming_after_rout = false
	reform_delay = -1.0
	resume_after_reform = false
	ranged_retreat_goal = Vector3.INF
	firing_goal = Vector3.INF
	ranged_area = action == 4 and is_ranged()
	ranged_ready = false
	fortified = action == 5
	defending_order = action in [3, 5]
	if action == 4:
		if is_ranged():
			point = center() + (point - center()).limit_length(BOW_RANGE)
			point = FIELD.project(point)
			ranged_point = point
			firing_goal = Vector3.INF
			for soldier in living(): soldier.order_fire_area(point)
			state_text = "Обстрел области"
			return
		if spear_count() == 0:
			return
		var origin := center()
		var offset := point - origin
		offset.y = 0.0
		point = origin + offset.limit_length(20.0)
		var spread_radius := 1.7 * Experience.projectile_spread(experience_rank)
		for soldier in soldiers:
			var spread := Vector3(sin(soldier.index * 13.7), 0, cos(soldier.index * 7.3)) * spread_radius
			var destination := point + spread
			destination = FIELD.project(destination)
			soldier.order_throw(destination, fmod(soldier.index * 0.113, 0.55))
		state_text = "Метание копий"
		return
	var defending := defending_order
	var origin := center()
	var direction := point - origin
	if direction.length() > 0.1:
		order_heading = atan2(-direction.x, -direction.z)
	var destination := origin if defending else point
	# A rotation-independent inset keeps the entire formation within the field.
	destination = FIELD.clamp_ground(destination, field_half_size, 8.5)
	var shield_wall := defending and not is_ranged() and not is_mounted()
	var spacing_x := maxf(.68, .72 * DENSITY_SPACING[formation_density]) if shield_wall else formation_width/maxi(1,formation_columns-1)
	var spacing_z := 1.15 * float(DENSITY_SPACING[formation_density]) if shield_wall else formation_row_spacing()
	var active := living()
	var columns := mini(formation_columns, active.size())
	var slots := make_formation_slots(destination,order_heading,columns,(columns-1)*spacing_x,spacing_z,not shield_wall)
	var assignment := assign_slots(slots, active)
	for i in active.size():
		var slot: int = assignment[i]
		active[i].order_move(slots[slot], order_heading, 4.2 if action == 2 else 1.8, defending, slot < columns * 2)
	var fast_move := "Галоп" if is_mounted() else "Бег"
	state_text = "Укрепились" if fortified else (("Стена щитов" if shield_wall else "Держат позицию") if defending else (fast_move if action == 2 else "Шаг"))

func assign_slots(slots: Array[Vector3], units: Array) -> PackedInt32Array:
	var started:=Time.get_ticks_usec() if PROF.enabled else 0
	var result:=assign_slots_impl(slots,units)
	for i in units.size():
		if not units[i].is_sotnik:
			continue
		var center_slot := 0
		var best_distance := INF
		var center := Vector3.ZERO
		for slot in slots: center += slot
		center /= slots.size()
		for j in slots.size():
			var distance := slots[j].distance_squared_to(center)
			if distance < best_distance:
				best_distance = distance
				center_slot = j
		var displaced := result.find(center_slot)
		if displaced >= 0:
			result[displaced] = result[i]
			result[i] = center_slot
		break
	if PROF.enabled:PROF.add("formation_assignment",started)
	return result

func assign_slots_impl(slots: Array[Vector3], units: Array) -> PackedInt32Array:
	var movement:Node=get_tree().current_scene.get("crowd_movement")
	if movement and movement.native and movement.native.has_method("assign_slots") and units.size()<=256:
		var points:=PackedFloat32Array()
		points.resize(units.size()*4)
		for i in units.size():
			points[i*4]=units[i].position.x;points[i*4+1]=units[i].position.z
			points[i*4+2]=slots[i].x;points[i*4+3]=slots[i].z
		var result:PackedFloat32Array=movement.native.call("assign_slots",points)
		result.resize(units.size())
		return PackedInt32Array(Array(result))
	return assign_slots_gd(slots,units)

func assign_slots_gd(slots: Array[Vector3], units: Array) -> PackedInt32Array:
	# Hungarian assignment, evaluated only when a new order changes the destinations.
	var count := units.size()
	var u := PackedFloat64Array()
	var v := PackedFloat64Array()
	var p := PackedInt32Array()
	var way := PackedInt32Array()
	u.resize(count + 1)
	v.resize(count + 1)
	p.resize(count + 1)
	way.resize(count + 1)
	for i in range(1, count + 1):
		p[0] = i
		var j0 := 0
		var minimum := PackedFloat64Array()
		minimum.resize(count + 1)
		minimum.fill(INF)
		var used := PackedByteArray()
		used.resize(count + 1)
		while true:
			used[j0] = 1
			var i0 := p[j0]
			var delta := INF
			var j1 := 0
			for j in range(1, count + 1):
				if used[j]:
					continue
				var cost: float = units[i0 - 1].global_position.distance_squared_to(slots[j - 1]) - u[i0] - v[j]
				if cost < minimum[j]:
					minimum[j] = cost
					way[j] = j0
				if minimum[j] < delta:
					delta = minimum[j]
					j1 = j
			for j in range(count + 1):
				if used[j]:
					u[p[j]] += delta
					v[j] -= delta
				else:
					minimum[j] -= delta
			j0 = j1
			if p[j0] == 0:
				break
		while true:
			var j1 := way[j0]
			p[j0] = p[j1]
			j0 = j1
			if j0 == 0:
				break
	var result := PackedInt32Array()
	result.resize(count)
	for j in range(1, count + 1):
		result[p[j] - 1] = j - 1
	return result

func stop() -> void:
	if routed: return
	pending_order.clear()
	attack_target = null
	attack_formation.clear()
	running_attack = false
	behavior_attack = false
	retaliation_target = null
	defending_order = false
	fortified = false
	ranged_area = false
	ranged_ready = false
	volley_assembly = 0.0
	volley_archers.clear()
	ranged_retreat_goal = Vector3.INF
	firing_goal = Vector3.INF
	reforming = false
	reforming_after_rout = false
	reform_delay = -1.0
	resume_after_reform = false
	for soldier in soldiers:
		soldier.stop()
	state_text = "Остановка"

func set_behavior(mode: Behavior) -> void:
	if mode == behavior:
		return
	behavior = mode
	retaliation_target = null
	if combat_ready() and (is_instance_valid(attack_target) or ranged_area or pending_order.has("enemy")):
		stop()
		for soldier in members:
			soldier.strike_target = null

func allows_local_contact() -> bool:
	return not behavior_controlled or behavior != Behavior.PEACEFUL

func update_behavior() -> void:
	if victory_started or not ai_enabled or not pending_order.is_empty() or reforming or reform_delay >= 0.0 or is_busy():
		return
	if behavior_attack and (not is_instance_valid(attack_target) or (behavior != Behavior.AGGRESSIVE and not attack_target.combat_ready())):
		if defending_order:
			finish_holding_attack()
		else:
			stop()
			reform_after_battle()
		return
	if behavior == Behavior.HOLD and behavior_attack:
		var enemy := enemy_in_hold_range()
		if enemy == null:
			finish_holding_attack()
		elif enemy != attack_target:
			command_attack(enemy, false, true, true)
		return
	if is_instance_valid(attack_target) or ranged_area or members.any(func(s): return s.position.distance_squared_to(s.target) > 0.49):
		return
	match behavior:
		Behavior.HOLD:
			var enemy := enemy_in_hold_range()
			if enemy:
				command_attack(enemy, false, true, true)
		Behavior.RETALIATE:
			if is_instance_valid(retaliation_target) and retaliation_target.combat_ready():
				command_attack(retaliation_target, false, defending_order, true)
		Behavior.AGGRESSIVE:
			get_tree().current_scene.send_to_nearest(self)

func enemy_in_hold_range() -> Node3D:
	var bows := uses_bows()
	var radius := BOW_RANGE if bows else 3.0
	var index: Node = get_tree().current_scene.combat_index
	var closest := INF
	var enemy_group: Node3D
	for foe in index.nearby(center(), team, cohesion_radius + radius):
		for soldier in members:
			var distance: float = soldier.position.distance_squared_to(foe.position)
			var reach: float = BOW_RANGE if bows else soldier.weapon_reach()
			if distance < closest and distance <= reach * reach:
				closest = distance
				enemy_group = foe.get_parent()
	return enemy_group

func finish_holding_attack() -> void:
	attack_target = null
	behavior_attack = false
	retaliation_target = null
	ranged_ready = false
	state_text = "Укрепились" if fortified else "Держат позицию"
	for soldier in members:
		soldier.order_move(soldier.guard_anchor, order_heading, 1.8, true, soldier.front_rank)

func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec() if PROF.enabled else 0
	physics_step(delta)
	if PROF.enabled: PROF.add("squad_physics",started)
	if not native_logic_groups.is_empty():
		var clock: float = get_tree().current_scene.crowd_movement.physics_time
		for soldier in native_logic_groups[Engine.get_physics_frames()%native_logic_groups.size()]:
			if is_instance_valid(soldier): soldier.run_managed_native_logic(clock)

func register_native_logic(soldier: CharacterBody3D) -> void:
	if native_logic_groups.is_empty():
		for i in soldier.native_logic_cadence: native_logic_groups.append([])
	var group := native_logic_groups[posmod(-soldier.native_logic_phase,native_logic_groups.size())]
	if soldier not in group: group.append(soldier)

func physics_step(delta: float) -> void:
	cache_timer -= delta
	if cache_timer <= 0: refresh_center(); cache_timer = .12
	if routed: withdraw_fleeing_soldiers()
	if members.is_empty() or surrendered: return
	berserk_remaining = maxf(0.0,berserk_remaining-delta)
	if inspired_remaining > 0:
		inspired_remaining = maxf(0.0,inspired_remaining-delta)
		if inspired_remaining <= 0:
			for soldier in members: soldier.set_inspired(false)
	casualty_shock = move_toward(casualty_shock, 0.0, 2.0 * delta)
	incoming_pressure = move_toward(incoming_pressure, 0.0, 3.0 * delta)
	recent_hit_time = maxf(0.0, recent_hit_time - delta)
	flank_pressure = move_toward(flank_pressure, 0.0, 3.0 * delta)
	spear_pressure = move_toward(spear_pressure, 0.0, 2.0 * delta)
	ranged_retreat_cooldown = maxf(0.0,ranged_retreat_cooldown-delta)
	morale_elapsed += delta
	if routed:
		if morale_elapsed >= .45:
			update_stamina(morale_elapsed)
			update_morale(morale_elapsed)
			morale_elapsed = 0.0
		return
	if reform_delay >= 0:
		reform_delay -= delta
		if reform_delay < 0: reform_after_battle()
	if reforming and members.all(func(s):
		return s.position.distance_to(s.target) < .7 and (not reforming_after_rout or absf(angle_difference(s.rotation.y, order_heading)) < .25)
	):
		reforming = false
		reforming_after_rout = false
		state_text = "Победа" if victory_started else ("Держат позицию" if defending_order else "Строй восстановлен")
		if resume_after_reform:
			resume_after_reform = false
			get_tree().current_scene.send_to_nearest(self)
	if not pending_order.is_empty() and not is_busy():
		var order := pending_order.duplicate()
		pending_order.clear()
		if order.has("layout"):
			command_formation(order.layout,order.running)
		elif order.has("enemy"):
			command_attack(order.enemy, order.running, order.get("hold",false), order.get("behavior_attack",false))
		else:
			command(order.action, order.point)
	combat_timer -= delta
	if combat_timer <= 0.0:
		combat_timer = .45
		if not victory_started:
			update_stamina(morale_elapsed)
			update_morale(morale_elapsed)
			morale_elapsed = 0.0
			if routed: return
		refresh_combat_mode()
		if is_ranged() and bow_orders_active and update_ranged_retreat():
			ranged_ready = false
			state_text = "Отходят галопом" if unit_kind == "khazar" else "Отходят"
			return
		if behavior_controlled:
			update_behavior()
		elif fortified and not is_instance_valid(attack_target):
			engage_fortified_front()
		if is_instance_valid(attack_target) and not ranged_retreat_goal.is_finite():
			if attack_target.routed and not defending_order and can_run():
				running_attack = true
			if not advance_attack_formation():
				assign_combat_targets()
		if bow_orders_active and is_ranged(): update_ranged_position()
	if bow_orders_active and is_ranged():
		update_volley(delta)
	if is_ranged() and alive_count() > 0 and not victory_started:
		if ranged_retreat_goal.is_finite(): state_text = "Отходят галопом" if unit_kind == "khazar" else "Отходят"
		elif living().any(func(s): return s.sword_drawn): state_text = "Сабли — ближний бой" if unit_kind == "khazar" else "Ножи — ближний бой"
		elif living().any(func(s): return s.active_action.begins_with("bow_")): state_text = "Стреляют"
	if is_instance_valid(attack_target) and attack_target.routed and not attack_target.surrendered and not defending_order and not ranged_retreat_goal.is_finite():
		state_text = "Преследуют отступающих"
	if state_text in ["Шаг", "Бег", "Галоп", "Остановка", "Метание копий"] and not is_busy():
		if soldiers.all(func(s): return not s.alive or s.global_position.distance_to(s.target) < 0.22):
			state_text = "Ожидание"

func alert_enemy(enemy_squad: Node3D, arrow_hit := false) -> void:
	if not ai_enabled or not combat_ready() or victory_started:
		return
	if team == 1 and not arrow_hit:
		return
	if not is_instance_valid(enemy_squad) or not enemy_squad.has_method("combat_ready") or not enemy_squad.combat_ready():
		return
	if team == 1:
		arrow_threat = enemy_squad
		return
	if is_instance_valid(attack_target):
		return
	if behavior_controlled:
		if behavior == Behavior.RETALIATE:
			retaliation_target = enemy_squad
		return
	if fortified:
		return
	if state_text in ["Ожидание", "Стена щитов", "Держат позицию", "Остановка"]:
		if defending_order:
			attack_target = enemy_squad
			running_attack = false
			assign_combat_targets()
		else:
			command_attack(enemy_squad, false)

func command_attack(enemy_squad: Node3D, running: bool, hold := false, automatic := false) -> void:
	if not is_instance_valid(enemy_squad) or enemy_squad.team == team or not combat_ready() or enemy_squad.surrendered or enemy_squad.alive_count() == 0:
		return
	running = running or (enemy_squad.routed and not hold)
	if not running and is_busy():
		pending_order = {"enemy": enemy_squad, "running": running, "hold":hold, "behavior_attack": automatic}
		return
	behavior_attack = automatic
	retaliation_target = null
	if attack_target == enemy_squad and defending_order == hold:
		if running and can_run() and not hold and not running_attack:
			running_attack = true
			if is_melee_cavalry(): enemy_squad.incoming_cavalry = self
			state_text = attack_state()
			if not attack_formation.is_empty():
				if can_wedge_charge():
					if not start_attack_formation(): assign_combat_targets()
					return
				attack_formation_goal = Vector3.INF
			if not advance_attack_formation(): assign_combat_targets()
		return
	pending_order.clear()
	attack_formation.clear()
	attack_target = enemy_squad
	reform_delay = -1.0
	reforming = false
	reforming_after_rout = false
	resume_after_reform = false
	ranged_area = false
	if not hold: fortified = false
	if hold and automatic and not defending_order:
		for soldier in members:
			soldier.guard_anchor = soldier.position
	defending_order = hold
	ranged_retreat_goal = Vector3.INF
	firing_goal = Vector3.INF
	running_attack = can_run() and not hold and running
	if is_melee_cavalry() and running_attack:
		enemy_squad.incoming_cavalry = self
	state_text = attack_state()
	if can_advance_in_formation():
		if start_attack_formation(): return
	assign_combat_targets()

func uses_spear_formation() -> bool:
	return not is_mounted() and not is_ranged() and spear_count() * 2 >= members.size()

func can_advance_in_formation() -> bool:
	return not defending_order and not attack_target.routed and not uses_bows()

func start_attack_formation() -> bool:
	var origin := center()
	var direction: Vector3 = (attack_target.center() - origin).slide(Vector3.UP)
	if direction.is_zero_approx(): return false
	attack_formation_goal = Vector3.INF
	order_heading = atan2(-direction.x, -direction.z)
	var offsets := wedge_offsets(order_heading) if can_wedge_charge() else make_formation_slots(Vector3.ZERO, order_heading, formation_columns, formation_width)
	var slots: Array[Vector3] = []
	for offset in offsets: slots.append(FIELD.project(origin + offset.slide(Vector3.UP)))
	var assignment := assign_slots(slots, members)
	for i in members.size():
		var soldier: CharacterBody3D = members[i]
		attack_formation[soldier] = offsets[assignment[i]].slide(Vector3.UP)
		soldier.commit_formation_advance()
	return advance_attack_formation()

func wedge_offsets(heading: float) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var row := 0
	var depth_sum := 0.0
	while slots.size() < members.size():
		var count := mini(mini(2 * row + 1, 7), members.size() - slots.size())
		var depth := row * 3.2
		for column in count:
			slots.append(Vector3((column - (count - 1) * .5) * CAVALRY_COLUMN_SPACING, 0, depth))
		depth_sum += depth * count
		row += 1
	var centre := Vector3.BACK * (depth_sum / slots.size())
	for i in slots.size():
		slots[i] = (slots[i] - centre).rotated(Vector3.UP, heading)
	return slots

func advance_attack_formation() -> bool:
	if attack_formation.is_empty(): return false
	if attack_target.surrendered or attack_target.alive_count() == 0 or attack_target.routed:
		attack_formation.clear()
		return false
	var origin := center()
	var enemy_center: Vector3 = attack_target.center()
	var direction := (enemy_center - origin).slide(Vector3.UP).normalized()
	var heading := Vector3.FORWARD.rotated(Vector3.UP, order_heading)
	if members.any(func(s): return is_instance_valid(s.nearby_attack_contact())):
		attack_formation.clear()
		return false
	if direction.dot(heading) < .35:
		attack_formation.clear()
		return start_attack_formation()
	var own_front := 0.0
	var extent := Vector2.ZERO
	var rank_center := 0.0
	for soldier in members:
		var offset: Vector3 = attack_formation[soldier]
		own_front = maxf(own_front, offset.dot(direction))
		extent = extent.max(Vector2(absf(offset.x), absf(offset.z)))
		rank_center += heading.dot(soldier.position - offset)
	rank_center /= members.size()
	var enemy_front := 0.0
	for enemy in attack_target.members:
		enemy_front = maxf(enemy_front, (enemy_center - enemy.position).dot(direction))
	if can_wedge_charge() and (enemy_center - origin).dot(direction) - own_front - enemy_front <= Charge.WEDGE_RUN_UP:
		attack_formation.clear()
		return false
	# Running cavalry needs room to carry its momentum into the enemy line.
	var contact_gap := 1.75 if uses_spear_formation() else 1.0
	if is_mounted() and running_attack: contact_gap = 0.0
	var gap := own_front + enemy_front + contact_gap
	var goal := FIELD.clamp_ground(enemy_center - direction * gap, field_half_size - extent, 1.0)
	var remaining := (goal - origin).slide(Vector3.UP)
	var goal_changed := attack_formation_goal.distance_squared_to(goal) > .3025
	var in_slots := not goal_changed and members.all(func(s): return (s.target - s.position).slide(Vector3.UP).length_squared() < .49)
	if remaining.length_squared() < .36 or remaining.dot(direction) < 0.0 or in_slots:
		attack_formation.clear()
		return false
	var first_step := not attack_formation_goal.is_finite()
	if goal_changed: attack_formation_goal = goal
	for soldier in members:
		var offset: Vector3 = attack_formation[soldier]
		var destination := FIELD.project(attack_formation_goal + offset)
		var pace := 1.8
		if running_attack:
			pace = soldier.attack_run_speed() if soldier.mounted else 4.0
		if first_step:
			soldier.order_move(destination, order_heading, pace, false, false)
			soldier.reaction = 0.0
		elif goal_changed:
			soldier.target = destination
		# Match each fighter's pace to their assigned offset in the formation.
		var ahead := heading.dot(soldier.position - offset) - rank_center
		var rank_pace := clampf(pace - ahead * 2.5, pace * .55, pace * 1.08)
		soldier.speed_limit = rank_pace * soldier.stamina_multiplier / soldier.speed_variation
		if soldier.mounted:
			var distance_to_line := direction.dot(enemy_center - soldier.position) - enemy_front
			soldier.weapon_ready = distance_to_line <= pace * soldier.ready_lead
		else:
			soldier.shield_raised = soldier.has_shield() and not running_attack
	return true

func attack_state() -> String:
	if attack_target.routed: return "Преследуют отступающих"
	if can_wedge_charge(): return "Натиск клином"
	if running_attack: return "Выход на дистанцию бегом" if uses_bows() else "Натиск"
	if is_melee_cavalry(): return "Конная атака"
	if is_ranged(): return "Выход на дистанцию" if uses_bows() else "Атака в ближнем бою"
	return "Атака под щитами"

func assign_combat_targets() -> void:
	if fortified and not attack_target.combat_ready():
		attack_target = null
		state_text = "Укрепились"
		for soldier in members:
			soldier.order_move(soldier.guard_anchor, order_heading, 1.8, true, soldier.front_rank)
		return
	if attack_target.surrendered or attack_target.alive_count() == 0:
		var next_group: Node3D
		var closest := INF
		if not behavior_controlled and not (team == 1 and ai_enabled and is_melee_cavalry()):
			for group in get_tree().get_nodes_in_group("squads"):
				if group.team == team or group.surrendered or group.alive_count() == 0: continue
				var distance: float = center().distance_squared_to(group.center())
				if distance < closest:
					closest = distance
					next_group = group
		if next_group and closest < 196.0:
			attack_target = next_group
			if can_advance_in_formation() and start_attack_formation(): return
			assign_combat_targets()
			return
		stop()
		reform_after_battle()
		resume_after_reform = team == 0 and not behavior_controlled and get_tree().current_scene.auto_battle
		return
	var enemies: Array = attack_target.living()
	var pursuit_limit := INF
	if siege_counterattack:
		pursuit_limit = get_tree().current_scene.siege_line - .7
		enemies = enemies.filter(func(enemy): return enemy.position.z < pursuit_limit)
		if enemies.is_empty(): return
	if uses_bows():
		assign_ranged_targets(enemies)
		return
	var spread_targets := can_advance_in_formation()
	var forward: Vector3 = (attack_target.center() - center()).slide(Vector3.UP).normalized()
	if forward.is_zero_approx(): forward = Vector3.FORWARD.rotated(Vector3.UP, order_heading)
	var side := forward.cross(Vector3.UP)
	var claimed := {}
	var unassigned := []
	for soldier in members:
		var current = soldier.combat_target
		var valid_target: bool = is_instance_valid(current) and current.alive and not current.withdrawn and not current.disarmed and current.position.z < pursuit_limit
		var local_contact: bool = valid_target and not soldier.mounted and soldier.position.distance_squared_to(current.position) <= soldier.LOCAL_CONTACT_RADIUS ** 2
		var target_matches: bool = valid_target and (current.get_parent() == attack_target or local_contact
			or (soldier.mounted and not attack_target.routed and soldier.position.distance_squared_to(current.position) < 8.0))
		if target_matches and soldier.attack_order and (soldier.busy or soldier.combat_stall < 2.8 or soldier.position.distance_squared_to(current.position) < 8.0):
			claimed[current] = claimed.get(current, 0) + 1
			if soldier.charge != running_attack:
				soldier.order_attack(current,running_attack,defending_order)
			soldier.hold_position = defending_order
		else:
			unassigned.append(soldier)
	if spread_targets:
		unassigned.sort_custom(func(a, b): return a.position.dot(forward) > b.position.dot(forward))
	for soldier in unassigned:
		var best: CharacterBody3D
		var best_score := INF
		for enemy in enemies:
			var offset: Vector3 = enemy.position - soldier.position
			var distance := offset.length_squared()
			var users: int = claimed.get(enemy, 0)
			var score: float = distance + users * 13.0 + (55.0 if users >= 2 else 0.0)
			if spread_targets:
				var lateral := offset.dot(side)
				score += lateral * lateral * 2.5 + users * 16.0
			if distance<9:score-=12.0 # Prefer immediate contact over enemies deep in the formation.
			if score < best_score:
				best_score = score
				best = enemy
		claimed[best] = claimed.get(best, 0) + 1
		soldier.order_attack(best, running_attack, defending_order)
	if members.any(func(s): return s.busy and s.active_action.begins_with("attack")):
		state_text = "Рукопашная"
	if members.any(func(s): return s.bracing_charge):
		state_text = "Копья против конницы"
	elif is_melee_cavalry() and members.any(func(s): return s.penetrating_charge()):
		state_text = "Удар клином" if is_heavy_cavalry() else "Прорыв строя"
	elif fortified:
		state_text = "Укрепились"

func engage_fortified_front() -> void:
	var index: Node = get_tree().current_scene.combat_index
	var nearby: Array = index.nearby(center(), team, cohesion_radius + 3.0)
	for enemy in nearby:
		for soldier in members:
			if soldier.position.distance_squared_to(enemy.position) <= pow(soldier.weapon_reach() + .5, 2):
				command_attack(enemy.get_parent(), false, true)
				return

func assign_ranged_targets(enemies: Array) -> void:
	var claimed := {}
	var unassigned := []
	var range_squared := BOW_RANGE * BOW_RANGE
	for soldier in members:
		var current: CharacterBody3D = soldier.combat_target
		var valid: bool = is_instance_valid(current) and current.alive and not current.withdrawn and current.get_parent() == attack_target
		if soldier.sword_drawn:
			if not valid:
				var nearest := INF
				for enemy in enemies:
					var distance: float = soldier.position.distance_squared_to(enemy.position)
					if distance < nearest:
						nearest = distance
						current = enemy
			if not soldier.attack_order or soldier.combat_target != current or soldier.hold_position != defending_order or soldier.charge != running_attack:
				soldier.order_attack(current, running_attack, defending_order)
			continue
		if soldier.active_action.begins_with("bow_"):
			if valid: claimed[current] = claimed.get(current, 0) + 1
			continue
		if valid and soldier.attack_order and (not defending_order or soldier.position.distance_squared_to(current.position) <= range_squared):
			claimed[current] = claimed.get(current, 0) + 1
			if soldier.hold_position != defending_order or soldier.charge != running_attack:
				soldier.order_attack(current, running_attack, defending_order)
		else:
			unassigned.append(soldier)
	if unassigned.is_empty(): return
	# Fill gaps across the target formation before doubling up. A holding unit
	# must prioritize targets it can reach from its current position.
	var coverage := {}
	for enemy in enemies:
		var gap := INF
		for target in claimed:
			gap = minf(gap, enemy.position.distance_squared_to(target.position))
		coverage[enemy] = gap
	for soldier in unassigned:
		var best: CharacterBody3D
		var best_distance := INF
		var best_gap := -INF
		var best_priority := INF
		for enemy in enemies:
			var distance: float = soldier.position.distance_squared_to(enemy.position)
			var gap: float = coverage[enemy]
			var priority: int = claimed.get(enemy, 0)
			if defending_order and distance > range_squared: priority += members.size()
			if priority < best_priority or (priority == best_priority and (gap > best_gap or (gap == best_gap and distance < best_distance))):
				best = enemy
				best_priority = priority
				best_gap = gap
				best_distance = distance
		if not claimed.has(best):
			for enemy in enemies:
				coverage[enemy] = minf(coverage[enemy], enemy.position.distance_squared_to(best.position))
		claimed[best] = claimed.get(best, 0) + 1
		if not soldier.attack_order or soldier.combat_target != best or soldier.hold_position != defending_order or soldier.charge != running_attack:
			soldier.order_attack(best, running_attack, defending_order)

func formation_row_spacing() -> float:
	var base := 1.75 if spear_count() * 2 >= alive_count() else 1.4
	if unit_kind == "archer": base = 2.1
	if is_mounted(): base = CAVALRY_ROW_SPACING
	return base * DENSITY_SPACING[formation_density]

func set_formation_density(level: int) -> void:
	if level == formation_density or not combat_ready():
		return
	formation_width = clampf(formation_width / DENSITY_SPACING[formation_density] * DENSITY_SPACING[level], 1.2, MAX_FORMATION_WIDTH)
	formation_density = level
	if is_instance_valid(attack_target) and not defending_order:
		firing_goal = Vector3.INF
		if not attack_formation.is_empty() and not start_attack_formation():
			assign_combat_targets()
		return
	var point := center()
	if defending_order:
		command(5 if fortified else 3, point + Vector3.FORWARD.rotated(Vector3.UP, order_heading))
		return
	var slots := make_formation_slots(point, order_heading, formation_columns, formation_width)
	command_formation({"slots": slots, "heading": order_heading, "columns": formation_columns, "width": formation_width})

func formation_offset(slot: int, columns: int, count: int, spacing: float, depth: float, irregular: bool) -> Vector3:
	var row := slot / columns
	var rows := ceili(float(count)/columns)
	var row_count := mini(columns,count-row*columns)
	var offset := Vector3((slot%columns-(row_count-1)*.5)*spacing,0,(row-(rows-1)*.5)*depth)
	if irregular and formation_density == 2:
		var seed := float(slot+1+(serial+1)*67)
		offset.x += (fposmod(sin(seed*12.9898)*43758.5453,1.0)-.5)*spacing*.38
		offset.z += (fposmod(sin(seed*78.233)*12345.6789,1.0)-.5)*depth*.55
	return offset

func make_formation_slots(point: Vector3, heading: float, columns: int, width: float, row_spacing := 0.0, irregular := true) -> Array[Vector3]:
	if row_spacing <= 0.0:
		row_spacing = formation_row_spacing()
	var slots: Array[Vector3] = []
	if is_mounted():
		row_spacing = maxf(row_spacing,3.2)
		width = maxf(width,(mini(columns,members.size())-1)*2.3)
	if members.is_empty(): return slots
	width *= float(mini(columns,members.size())-1)/maxi(1,columns-1)
	columns = clampi(columns,1,members.size())
	var rows := ceili(float(members.size())/columns)
	var half := Vector3(width*.5,0,(rows-1)*row_spacing*.5)
	var extent := Vector3(absf(cos(heading))*half.x+absf(sin(heading))*half.z,0,absf(sin(heading))*half.x+absf(cos(heading))*half.z)
	var usable := field_half_size - Vector2(extent.x, extent.z)
	point = FIELD.clamp_ground(point, usable, 1.0)
	for i in members.size():
		var offset := formation_offset(i, columns, members.size(), width/maxi(1,columns-1), row_spacing, irregular)
		slots.append(FIELD.project(point+offset.rotated(Vector3.UP,heading)))
	return slots

func formation_from_drag(first: Vector3, last: Vector3) -> Dictionary:
	var line := last-first
	line.y = 0
	var spacing := CAVALRY_COLUMN_SPACING if is_mounted() else (1.8 if is_ranged() else (1.55 if spear_count() * 2 >= alive_count() else 1.15))
	spacing *= DENSITY_SPACING[formation_density]
	var minimum_columns := ceili(members.size() / (6.0 if is_mounted() else 8.0))
	var width := clampf(line.length(),maxf(1.2,(minimum_columns-1)*spacing),MAX_FORMATION_WIDTH)
	var columns := clampi(roundi(width / spacing)+1,2,maxi(2,members.size()))
	var heading := atan2(-line.z,line.x)
	var rows := ceili(float(members.size())/columns)
	var point := (first+last)*.5+Vector3.BACK.rotated(Vector3.UP,heading)*(rows-1)*formation_row_spacing()*.5
	return {"slots":make_formation_slots(point,heading,columns,width),"heading":heading,"columns":columns,"width":width}

func command_formation(layout: Dictionary, running := false) -> void:
	if not combat_ready(): return
	if is_busy(): pending_order = {"layout":layout,"running":running}; return
	running = running and can_run()
	stop()
	formation_columns = layout.columns
	formation_width = layout.width
	order_heading = layout.heading
	defending_order = layout.get("hold",false)
	var slots: Array[Vector3] = layout.slots
	if slots.size() != members.size(): slots = make_formation_slots(center(),order_heading,formation_columns,formation_width)
	var assignment := assign_slots(slots,members)
	for i in members.size(): members[i].order_move(slots[assignment[i]],order_heading,4.2 if running else 1.8,defending_order,assignment[i] < formation_columns * 2)
	state_text = "Перестроение"
	reforming = true

func deploy_formation(slots: Array[Vector3], heading: float, columns: int, width: float) -> void:
	formation_columns = columns
	formation_width = width
	order_heading = heading
	for i in members.size():
		members[i].place_for_deployment(slots[i],heading)
	refresh_center()
	update_selection_rings()

func reform_after_battle() -> void:
	if not combat_ready(): return
	if is_busy(): reform_delay = .5; return
	refresh_center()
	var layout := {"slots":make_formation_slots(center(),order_heading,formation_columns,formation_width),"heading":order_heading,"columns":formation_columns,"width":formation_width}
	command_formation(layout,false)
	state_text = "Собираются в строй"

func available_bowmen() -> Array:
	return members.filter(func(s): return s.auto_fire and not s.sword_drawn and not s.retreating and not s.manual_move)

func update_volley(delta: float) -> void:
	volley_timer -= delta
	if not volley_archers.is_empty():
		release_volley()
		return
	if not ranged_ready or not uses_bows():
		volley_assembly = 0.0
		return
	if volley_timer > 0.0:
		return
	var ready := available_bowmen().filter(func(s): return s.ready_to_loose())
	if ready.is_empty() or ready.size() < minimum_volley_size():
		volley_assembly = 0.0
		return
	volley_assembly += delta
	# Give the rest of the squad time to take aim before firing with fewer archers.
	if ready.size() < members.size() and volley_assembly < 1.6:
		return
	volley_assembly = 0.0
	volley_timer = 4.05
	volley_archers = ready
	for soldier in ready:
		soldier.start_shot()

func minimum_volley_size() -> int:
	return ceili(members.size() * .66)

func release_volley() -> void:
	volley_archers = volley_archers.filter(func(s): return s.alive and s.active_action.begins_with("bow_"))
	if volley_archers.any(func(s): return not s.arrow_ready):
		return
	# Check for interrupted shots and blocked trajectories before launching any arrows.
	var shots := {}
	for soldier in volley_archers:
		var trajectory: PackedVector3Array = soldier.prepare_arrow()
		if not trajectory.is_empty():
			shots[soldier] = trajectory
	if not shots.is_empty() and shots.size() >= minimum_volley_size():
		arrows_remaining -= 1
		volley_count += 1
		for soldier in shots:
			var trajectory: PackedVector3Array = shots[soldier]
			soldier.launch_arrow(trajectory[0], trajectory[1])
	volley_archers.clear()

func nearby_ranged_threat(limit: float) -> CharacterBody3D:
	var index: Node = get_tree().current_scene.combat_index
	var closest: CharacterBody3D
	var distance := limit * limit
	for foe in index.nearby(center(),team,cohesion_radius + limit):
		var enemy_group: Node3D = foe.get_parent()
		if enemy_group.is_ranged() and enemy_group.bow_orders_active: continue
		for soldier in members:
			var gap: float = soldier.position.distance_squared_to(foe.position)
			if gap < distance:
				closest = foe
				distance = gap
	return closest

func plan_ranged_retreat(threat: CharacterBody3D) -> bool:
	var world := get_tree().current_scene
	var origin := center()
	var away := (origin - threat.position).normalized()
	if away.is_zero_approx():
		away = Vector3.BACK if team == 0 else Vector3.FORWARD
	var distance := 30.0 if is_mounted() else 23.0
	var lower := origin
	var upper := origin
	for soldier in members:
		lower = lower.min(soldier.position)
		upper = upper.max(soldier.position)
	var margin := Vector3(field_half_size.x - 2.0,0.0,field_half_size.y - 2.0)
	var min_travel := -margin - lower
	var max_travel := margin - upper
	if not world.siege_gates.is_empty():
		if lower.z >= world.siege_line:
			min_travel.z = maxf(min_travel.z,world.siege_line+.8-lower.z)
		elif upper.z <= world.siege_line:
			max_travel.z = minf(max_travel.z,world.siege_line-.8-upper.z)
	var best_score := -INF
	var best_travel := Vector3.ZERO
	for angle in [0.0, PI/4, -PI/4, PI/2, -PI/2]:
		var direction := away.rotated(Vector3.UP,angle)
		var travel := (direction * distance).clamp(min_travel,max_travel)
		if travel.length_squared() < 16.0 or travel.dot(away) < -2.0:
			continue
		var goal := origin + travel
		var danger: CharacterBody3D = world.combat_index.nearest(goal,team,ARCHER.KEEP_DISTANCE)
		var clearance := goal.distance_to(danger.position) if danger else ARCHER.KEEP_DISTANCE
		var score := 1.3 * clearance + travel.dot(away) + travel.length() * .4
		if score > best_score:
			best_score = score
			best_travel = travel
	if best_travel.is_zero_approx():
		return false
	ranged_area = false
	ranged_ready = false
	firing_goal = Vector3.INF
	ranged_retreat_goal = origin + best_travel
	ranged_retreat_remaining = best_travel.length()
	ranged_retreat_stall = 0.0
	if not is_instance_valid(attack_target):
		attack_target = threat.get_parent()
	var heading := atan2(-best_travel.x,-best_travel.z)
	for soldier in members:
		soldier.order_skirmish_retreat(soldier.position + best_travel,heading)
	return true

func update_ranged_retreat() -> bool:
	if reforming or ranged_retreat_cooldown > 0.0:
		return false
	if not ranged_retreat_goal.is_finite():
		if behavior_controlled and behavior == Behavior.PEACEFUL and not is_instance_valid(attack_target):
			return false
		if members.any(func(s): return (s.manual_move and s.position.distance_squared_to(s.target) > .49) or not s.auto_fire):
			return false
		var initial := nearby_ranged_threat(ARCHER.RETREAT_DISTANCE if is_mounted() else 8.0)
		return initial != null and plan_ranged_retreat(initial)
	var remaining := center().distance_to(ranged_retreat_goal)
	if ranged_retreat_remaining - remaining > .65:
		ranged_retreat_remaining = remaining
		ranged_retreat_stall = 0.0
	else:
		ranged_retreat_stall += .45
	if ranged_retreat_stall < 2.25 and not members.all(func(s): return s.position.distance_squared_to(s.target) < 2.25):
		return true
	ranged_retreat_goal = Vector3.INF
	ranged_retreat_cooldown = 1.5
	for soldier in members:
		soldier.order_move(soldier.position,soldier.final_heading,1.8,false,false)
		soldier.manual_move = false
	if is_instance_valid(attack_target):
		assign_combat_targets()
	return false

func update_ranged_position() -> void:
	if members.is_empty() or victory_started: ranged_ready = false; return
	# Commit a volley as a unit. A changing range cannot cancel only its later ranks.
	if members.any(func(s): return s.active_action.begins_with("bow_")):
		ranged_ready = true
		return
	if not ranged_area and not is_instance_valid(attack_target):
		if behavior_controlled or (team == 1 and ai_enabled):
			ranged_ready = false
			return
		if reforming or members.any(func(s): return s.manual_move or not s.auto_fire): return
		var nearest: Node3D
		var distance := BOW_RANGE+7
		for group in get_tree().get_nodes_in_group("squads"):
			if group.team == team or not group.combat_ready(): continue
			var d: float = center().distance_to(group.center())
			if d < distance: distance = d; nearest = group
		if nearest: command_attack(nearest,false)
		else: ranged_ready = false; return
	var point: Vector3 = ranged_point if ranged_area else attack_target.center()
	var bowmen := available_bowmen()
	if bowmen.is_empty():
		ranged_ready = false
		return
	var in_range := 0
	for s in bowmen:
		var aim: Vector3 = ranged_point if ranged_area else (s.combat_target.position if is_instance_valid(s.combat_target) else point)
		if s.position.distance_squared_to(aim) <= BOW_RANGE * BOW_RANGE: in_range += 1
	ranged_ready = in_range > 0
	if in_range < bowmen.size() and not defending_order:
		var direction := (center()-point).normalized()
		var goal := point+direction*(BOW_RANGE-12)
		if firing_goal == Vector3.INF or goal.distance_to(firing_goal) > 2.0:
			firing_goal = goal
			var heading := atan2(direction.x,direction.z)
			var firing_slots := make_formation_slots(goal,heading,formation_columns,formation_width)
			var assignment := assign_slots(firing_slots,members)
			for i in members.size(): members[i].firing_slot = firing_slots[assignment[i]]
		if not members.any(func(s): return s.sword_drawn): state_text = "Выходят на дистанцию"
	else: state_text = "Готовят общий залп"
