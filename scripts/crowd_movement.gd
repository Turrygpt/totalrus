extends Node
const PROF = preload("res://scripts/profile_counters.gd")
const FIELD = preload("res://scripts/battlefield_bounds.gd")
const Soldier = preload("res://scripts/soldier.gd")
# The arena is one convex navigation polygon; only the local crowd needs avoidance.
const CELL := 1.25
var cells := {}
var clock := 0.0
var native: RefCounted
var field_half_size := FIELD.DEFAULT_HALF_SIZE
var native_clock := 0.0
var high_load := false
var actors: Array[Soldier] = []
var state := PackedFloat32Array()
var previous_state := PackedFloat32Array()
var render_heights := PackedFloat32Array()
var needs_script_grid := true
var render_clock := 0.0
var step_duration := .1
var solve_task := -1
var pending_solve: NativeSolve
var ground_config := PackedFloat32Array()
var ground_heights := PackedFloat32Array()
var waypoint_bounds := Rect2()
var physics_time := 0.0
var physics_delta := 0.0
var heavy_physics_frame := -1

class NativeSolve extends RefCounted:
	# The native solver reuses its contact grid across calls.
	static var lock := Mutex.new()
	var input: PackedFloat32Array
	var output: PackedFloat32Array
	var projected := PackedFloat32Array()
	var delta: float

	func run(solver: RefCounted, half_size: Vector2, heights: PackedFloat32Array, config: PackedFloat32Array) -> void:
		lock.lock()
		if half_size == FIELD.DEFAULT_HALF_SIZE:
			output = solver.call("step", input, delta)
		else:
			output = solver.call("step_bounded", input, delta, half_size.x - .6, half_size.y - .6)
		lock.unlock()
		if not config.is_empty():
			projected = solver.call("project_terrain", output, heights, config)

func _process(delta: float) -> void:
	render_clock += delta
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -90
	field_half_size = FIELD.for_scene(get_parent())
	if ClassDB.class_exists("CrowdNative") and "--no-native" not in OS.get_cmdline_user_args(): native=ClassDB.instantiate("CrowdNative")
	if native and field_half_size != FIELD.DEFAULT_HALF_SIZE and not native.has_method("step_bounded"):
		native = null
func _physics_process(delta: float) -> void:
	physics_time += delta
	physics_delta = delta
	if native:
		var applying := solve_task != -1
		if applying:
			heavy_physics_frame = Engine.get_physics_frames()
			finish_native_step()
		native_clock+=delta
		var interval := .075 if high_load else .05
		if native_clock >= interval * Engine.time_scale:
			heavy_physics_frame = Engine.get_physics_frames()
			step_native(native_clock)
			native_clock=0.0
	if native and not needs_script_grid: return
	clock -= delta
	if clock > 0: return
	clock = .1
	cells.clear()
	for group in get_tree().current_scene.squads:
		for s in group.members:
			var key := Vector2i(floori(s.position.x/CELL),floori(s.position.z/CELL))
			if not cells.has(key): cells[key] = []
			cells[key].append(s)

func _exit_tree() -> void:
	if solve_task != -1:
		WorkerThreadPool.wait_for_task_completion(solve_task)
		solve_task = -1

func avoidance(s: CharacterBody3D, desired: Vector3) -> Vector3:
	var point := s.position
	var cell := Vector2i(floori(point.x/CELL),floori(point.z/CELL))
	var push := Vector3.ZERO
	var checked := 0
	for z in range(cell.y-1,cell.y+2):
		for x in range(cell.x-1,cell.x+2):
			for other in cells.get(Vector2i(x,z),[]):
				if other == s or not other.alive or other.withdrawn: continue
				if s.mounted and s.has_method("penetrating_charge") and s.penetrating_charge() and not other.mounted and s.team != other.team and not other.bracing_charge:
					continue
				checked += 1
				if checked > 24: return (desired+push.limit_length(2.0)).limit_length(s.speed_limit*s.speed_variation)
				var away: Vector3 = point-other.position
				var d2 := away.length_squared()
				if d2 < .000001:
					away = Vector3.RIGHT if s.get_instance_id() > other.get_instance_id() else Vector3.LEFT
					d2 = .0001
				if d2 < .64:
					var distance := sqrt(d2)
					var normal := away/distance
					var closing := desired.dot(normal)
					if closing < 0:
						desired -= normal*closing*clampf((.8-distance)/.25,0,1)
					push += normal*(.8-distance)*2.5
	return (desired+push.limit_length(2.0)).limit_length(s.speed_limit*s.speed_variation)

func register_actors(groups: Array[Node3D]) -> void:
	if solve_task != -1: finish_native_step()
	var first := actors.size()
	for group in groups: actors.append_array(group.soldiers)
	var load_changed := not high_load and actors.size() > 600
	high_load = actors.size() > 600
	if load_changed and native and native.has_method("project_terrain"):
		var terrain: Node3D = get_parent().get("terrain")
		if terrain: prepare_ground(terrain)
	var cadence := 7 if high_load else 5
	for i in range(0 if load_changed else first,actors.size()):
		actors[i].native_logic_cadence = cadence
	state.resize(actors.size()*12)
	render_heights.resize(actors.size()*2)
	needs_script_grid = true
	# Keep the render interpolation buffers compatible until the next solver step.
	if not previous_state.is_empty(): previous_state.resize(state.size())
	for i in range(first,actors.size()): actors[i].native_index = i

func prepare_ground(terrain: Node3D) -> void:
	var size: Vector2i = terrain.grid_size
	if size.x < 2 or size.y < 2 or terrain.heights.size() != size.x * size.y: return
	var half: Vector2 = terrain.grid_half
	var step: Vector2 = terrain.grid_step
	ground_heights = terrain.heights
	ground_config = PackedFloat32Array([size.x,size.y,half.x,half.y,step.x,step.y])
	for obstacle: Vector3 in terrain.obstacles:
		ground_config.append_array(PackedFloat32Array([obstacle.x,obstacle.y,obstacle.z]))
		var center := Vector2(obstacle.x,obstacle.y)
		if waypoint_bounds.size == Vector2.ZERO:
			waypoint_bounds = Rect2(center,Vector2.ONE)
		else:
			waypoint_bounds = waypoint_bounds.expand(center)
	if waypoint_bounds.has_area(): waypoint_bounds = waypoint_bounds.grow(35.0)

func step_native(delta: float) -> void:
	var started := Time.get_ticks_usec() if PROF.enabled else 0
	var field := get_tree().current_scene
	var fortified: bool = field.has_method("siege_waypoint") and not field.siege_gates.is_empty()
	var battle_now: float = field.battle_time
	var terrain: Node3D = field.terrain
	var renderer: Node3D = field.crowd_renderer
	if actors.is_empty(): register_actors(field.squads)
	needs_script_grid = false
	var can_skip_far_waypoints := not ground_config.is_empty()
	for i in actors.size():
		var s := actors[i]
		var offset := i * 12
		var active := s.managed_native_logic or s.is_physics_processing()
		var controlled := s.alive and not s.withdrawn and active and s.crowd_visual != null
		if controlled != s.native_controlled:
			s.native_controlled = controlled
			renderer.update_actor_rendering(s)
		# Native movement already resolves body contacts. Keep the capsule in
		# the ray queries for melee, arrows and picking without a second solver.
		if high_load and controlled != s.native_query_body:
			s.set_native_query_body(controlled)
		if not s.alive or s.withdrawn:
			state[offset+9] = -1.0
			state[offset+10] = 0.0
			continue
		if high_load and controlled and not s.managed_native_logic and s.can_batch_native_logic():
			var group := s.get_parent()
			if group.has_method("register_native_logic"):
				s.native_logic_time = physics_time - physics_delta - s.native_logic_elapsed
				s.native_logic_elapsed = 0.0
				s.managed_native_logic = true
				s.set_physics_process(false)
				group.register_native_logic(s)
		elif s.managed_native_logic and not controlled:
			s.managed_native_logic = false
			s.native_logic_elapsed = maxf(0,physics_time - physics_delta - s.native_logic_time)
			s.set_physics_process(true)
		if not controlled and active: needs_script_grid = true
		var p := s.position
		var v := s.velocity
		var advancing: bool = controlled and (not s.busy or s.moving_strike()) and s.reaction <= 0.0
		var t := p
		if advancing:
			t = s.movement_goal(false)
			if fortified: t = field.siege_waypoint(p,t,s.cohesion_group)
			if terrain and (p.x != t.x or p.z != t.z):
				if not can_skip_far_waypoints or waypoint_bounds.has_point(Vector2(p.x,p.z)):
					t = terrain.waypoint(p,t)
		state[offset]=p.x; state[offset+1]=p.z; state[offset+2]=v.x; state[offset+3]=v.z
		state[offset+4]=t.x; state[offset+5]=t.z; state[offset+6]=s.rotation.y; state[offset+7]=s.final_heading
		state[offset+8]=s.speed_limit*s.speed_variation
		state[offset+9]=float(advancing) if controlled else -1.0
		state[offset+10]=1.0 # Only living, visible fighters enter the contact grid.
		var face: bool = s.busy or s.faces_combat_target()
		var passing := s.mounted and s.penetrating_charge()
		state[offset+11]=float(int(face)+int(s.has_spear)*2+s.team*4+int(s.mounted)*8+int(s.attack_order)*16+int(s.attack_order and s.flank_until>battle_now)*32+int(passing)*64+int(s.bracing_charge)*128)
	if PROF.enabled: PROF.add("native_pack",started)
	var work := NativeSolve.new()
	work.input = state
	work.delta = delta
	if high_load:
		pending_solve = work
		var config := PackedFloat32Array() if fortified else ground_config
		solve_task = WorkerThreadPool.add_task(work.run.bind(native,field_half_size,ground_heights,config),true,"Battle crowd movement")
		return
	started = Time.get_ticks_usec() if PROF.enabled else 0
	work.run(native,field_half_size,PackedFloat32Array(),PackedFloat32Array())
	if PROF.enabled: PROF.add("native_solve",started)
	apply_native_step(work)

func finish_native_step() -> void:
	var started := Time.get_ticks_usec() if PROF.enabled else 0
	WorkerThreadPool.wait_for_task_completion(solve_task)
	if PROF.enabled: PROF.add("native_wait",started)
	solve_task = -1
	var work := pending_solve
	pending_solve = null
	apply_native_step(work)

func apply_native_step(work: NativeSolve) -> void:
	var field := get_tree().current_scene
	var terrain: Node3D = field.terrain
	var fortified: bool = field.has_method("siege_waypoint") and not field.siege_gates.is_empty()
	var result := work.output
	var delta := work.delta
	previous_state = work.input
	render_clock = 0.0
	step_duration = delta
	var started := Time.get_ticks_usec() if PROF.enabled else 0
	for i in actors.size():
		var s := actors[i]
		if not s.native_controlled or not s.alive or s.withdrawn: continue
		var offset:=i*12
		var origin := s.position
		var yaw := work.input[offset+6]
		s.visual_position_from = origin
		s.visual_yaw_from = yaw
		s.movement_duration = delta
		s.visual_elapsed = 0.0
		var point := Vector3(result[offset],origin.y,result[offset+1])
		var pushed := not s.charge_push.is_zero_approx()
		if pushed:
			point = FIELD.clamp_ground(point + s.step_charge_push(delta), field_half_size, .6)
			result[offset] = point.x
			result[offset+1] = point.z
		if fortified:
			point = field.constrain_siege_crossing(s.position,point)
			result[offset] = point.x
			result[offset+1] = point.z
		if point.x != origin.x or point.z != origin.z:
			if not work.projected.is_empty() and not pushed and not fortified:
				point = Vector3(work.projected[i*3],work.projected[i*3+1],work.projected[i*3+2])
			else:
				point = terrain.constrain(point) if terrain else FIELD.project(point)
			result[offset] = point.x
			result[offset+1] = point.z
		var heading := result[offset+6]
		if not is_equal_approx(yaw,heading):
			s.transform = Transform3D(Basis(Vector3.UP,heading),point)
		elif point != origin:
			s.position = point
		if s.native_query_body and point != origin:
			s.sync_native_query_position()
		render_heights[i*2] = origin.y
		render_heights[i*2+1] = point.y
		var velocity := Vector3(result[offset+2],0,result[offset+3])
		s.velocity = velocity
		s.motion_speed = velocity.length()
		if s.motion_speed > .18: s.update_footsteps(delta)
	state = result
	if PROF.enabled: PROF.add("native_apply",started)
