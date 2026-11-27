extends Node
# Rebuilt once for the whole army; queries never scan every soldier in the battle.
const CELL := 4.0
const EMPTY_BUCKET := []
var cells: Array[Dictionary] = [{},{}]
var combatants: Array = []
var clock := 0.0
var engagements := {}
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -100
func _physics_process(delta: float) -> void:
	clock -= delta
	if clock <= 0:
		clock = .18
		rebuild()
func rebuild() -> void:
	cells = [{},{}]
	engagements.clear()
	combatants = get_tree().get_nodes_in_group("combatants")
	for s in combatants:
		if not s.alive or s.disarmed: continue
		var point: Vector3 = s.position
		var key := Vector2i(floori(point.x/CELL),floori(point.z/CELL))
		var grid := cells[s.team]
		if not grid.has(key): grid[key] = []
		grid[key].append(s)
		if s.attack_order and is_instance_valid(s.combat_target) and s.combat_target.alive and not s.combat_target.fleeing and point.distance_squared_to(s.combat_target.position)<100 and (not s.has_method("start_shot") or s.sword_drawn):
			if not engagements.has(s.combat_target):engagements[s.combat_target]=[]
			engagements[s.combat_target].append(s)

func claim_angle(attacker: CharacterBody3D, victim: CharacterBody3D) -> float:
	var offset:Vector3=attacker.position-victim.position
	var base:=atan2(offset.x,offset.z)
	var others:Array=engagements.get(victim,[])
	var best:=base;var best_score:=INF
	for turn in [0.0,PI/3,-PI/3,PI*2/3,-PI*2/3,PI]:
		var angle:float=base+turn
		var score:float=absf(turn)*1.5
		for other in others:
			if other==attacker or not other.alive or other.combat_target!=victim:continue
			var gap:=absf(angle_difference(angle,other.combat_slot_angle))
			if gap<.85:score+=(.85-gap)*100
		if score<best_score:best_score=score;best=angle
	if attacker not in others:others.append(attacker)
	engagements[victim]=others
	return best

func attackers(victim: CharacterBody3D) -> int:
	return engagements.get(victim,[]).size()

func immediate_threat(s:CharacterBody3D, current:CharacterBody3D, radius := 3.5) -> CharacterBody3D:
	var best:CharacterBody3D
	var second:CharacterBody3D
	var third:CharacterBody3D
	var first_score:=INF;var second_score:=INF;var third_score:=INF
	var point := s.position
	for enemy in nearby(point,s.team,radius, is_instance_valid(current) and current.fleeing):
		var distance:float=point.distance_squared_to(enemy.position)
		var score:float=distance
		if enemy==current: score-=.6
		if enemy.combat_target==s and distance<5: score-=.9
		if score<first_score:
			third=second;third_score=second_score;second=best;second_score=first_score;best=enemy;first_score=score
		elif score<second_score:
			third=second;third_score=second_score;second=enemy;second_score=score
		elif score<third_score:third=enemy;third_score=score
	# Spatial ranking is cheap; only the three immediate candidates need body rays.
	var reach:float=s.weapon_reach()+.25
	for candidate in [best,second,third]:
		if not candidate:continue
		if point.distance_squared_to(candidate.position)>reach*reach or s.clear_strike(candidate):return candidate
	return best
func nearby(point: Vector3, team: int, radius: float, include_fleeing := false) -> Array:
	var found := []
	var grid: Dictionary = cells[1-team]
	var limit := radius*radius
	for z in range(floori((point.z-radius)/CELL),floori((point.z+radius)/CELL)+1):
		for x in range(floori((point.x-radius)/CELL),floori((point.x+radius)/CELL)+1):
			for s in grid.get(Vector2i(x,z),EMPTY_BUCKET):
				if s.alive and not s.withdrawn and not s.disarmed and (include_fleeing or not s.fleeing) and point.distance_squared_to(s.position) <= limit: found.append(s)
	return found
func nearest(point: Vector3, team: int, radius := 40.0) -> CharacterBody3D:
	var best: CharacterBody3D
	var distance := radius*radius
	var grid: Dictionary = cells[1-team]
	for z in range(floori((point.z-radius)/CELL),floori((point.z+radius)/CELL)+1):
		for x in range(floori((point.x-radius)/CELL),floori((point.x+radius)/CELL)+1):
			for s in grid.get(Vector2i(x,z),EMPTY_BUCKET):
				if not s.alive or s.fleeing: continue
				var d: float = point.distance_squared_to(s.position)
				if d < distance: distance = d; best = s
	return best
