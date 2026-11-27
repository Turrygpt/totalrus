extends Node
# Rear-rank congestion, not a geometric formation, triggers flank movement.
# Fighters already in contact are never moved by this coordinator.
var clock := 0.0
var cursor := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -95

func _physics_process(delta:float) -> void:
	clock-=delta
	if clock>0:return
	clock=.12
	var groups:Array=get_tree().current_scene.squads
	for attempt in groups.size():
		cursor=(cursor+1)%groups.size()
		var g=groups[cursor]
		if g.is_ranged() or g.defending_order or not g.combat_ready():continue
		if not is_instance_valid(g.attack_target) or not g.attack_target.combat_ready():continue
		plan_rear_ranks(g)
		break

func blocked_by_ally(s:CharacterBody3D) -> bool:
	if not is_instance_valid(s.combat_target):return false
	var direction:Vector3=s.combat_target.position-s.position
	var ray:=PhysicsRayQueryParameters3D.create(s.position+Vector3.UP,s.position+Vector3.UP+direction.limit_length(3.0),2,[s.get_rid()])
	var hit:=s.get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.collider.team==s.team and hit.collider.alive

func plan_rear_ranks(group:Node3D) -> void:
	var enemies:Array=group.attack_target.members
	if enemies.is_empty():return
	var forward:Vector3=(group.attack_target.center()-group.center()).normalized()
	if forward.length_squared()<.1:return
	var right:=Vector3(forward.z,0,-forward.x)
	var enemy_left:=INF;var enemy_right:=-INF;var enemy_front:=INF
	for foe in enemies:
		var lateral:float=foe.position.dot(right)
		enemy_left=minf(enemy_left,lateral);enemy_right=maxf(enemy_right,lateral)
		enemy_front=minf(enemy_front,foe.position.dot(forward))
	var candidates:=[]
	var traffic:=[0,0]
	for s in group.members:
		if s.has_flank_plan():
			traffic[0 if s.flank_side<0 else 1]+=1
			continue
		if not s.attack_order or s.busy or s.animation_clock>0 or s.combat_stall<.75:continue
		if not is_instance_valid(s.combat_target) or not s.combat_target.alive or s.combat_target.fleeing:continue
		if s.position.distance_to(s.combat_target.position)<=s.weapon_reach() and s.clear_strike(s.combat_target):continue
		if blocked_by_ally(s):candidates.append(s)
	if candidates.is_empty():return
	# Release small groups from the nearest blocked edge, not every rear rank at once.
	candidates.sort_custom(func(a,b):
		var ax:float=a.position.dot(right);var bx:float=b.position.dot(right)
		return minf(absf(ax-enemy_left),absf(ax-enemy_right))<minf(absf(bx-enemy_left),absf(bx-enemy_right)))
	var sent:=0
	var service:Node=get_tree().current_scene.combat_index
	for s in candidates:
		if sent>=6:break
		var lateral:float=s.position.dot(right)
		var side:float=-1 if absf(lateral-enemy_left)+traffic[0]*.65<absf(lateral-enemy_right)+traffic[1]*.65 else 1
		var lane:=0 if side<0 else 1
		if traffic[lane]>=8:continue
		var edge:float=(enemy_left if side<0 else enemy_right)+side*(1.25+(traffic[lane]%2)*.75)
		for ally in group.members:
			if ally==s or ally.has_flank_plan() or absf((ally.position-s.position).dot(forward))>2:continue
			if side<0:edge=minf(edge,ally.position.dot(right)-.85)
			else:edge=maxf(edge,ally.position.dot(right)+.85)
		var waypoint:Vector3=s.position+right*(edge-lateral)+forward*clampf(enemy_front-s.position.dot(forward)-2.0,0,1.2)
		if absf(waypoint.x) > group.field_half_size.x - 1.4 or absf(waypoint.z) > group.field_half_size.y - 1.4:
			continue
		var victim:CharacterBody3D
		var score:=INF
		for foe in enemies:
			var value:float=absf(foe.position.dot(right)-edge)*3+maxf(0,foe.position.dot(forward)-enemy_front)*.3+waypoint.distance_to(foe.position)*.2+service.attackers(foe)*1.2
			if value<score:score=value;victim=foe
		if not victim:continue
		s.combat_target=victim
		s.flank_waypoint=waypoint
		s.flank_until=get_tree().current_scene.battle_time+12.0
		s.flank_side=side
		s.combat_detour=Vector3.INF
		s.combat_stall=0
		traffic[lane]+=1
		sent+=1
