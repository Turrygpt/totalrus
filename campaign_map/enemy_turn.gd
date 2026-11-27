extends RefCounted

const Geo = preload("res://campaign_map/geography.gd")
const Forces = preload("res://campaign_map/forces.gd")
const Landscape = preload("res://campaign_map/terrain.gd")
const MOVE := 116.0
const GUARD_RANGE := 25.0
const CONTACT_RANGE := 9.0
const THREAT_RANGE := 128.0
const ARMY_SUPPORT_RANGE := 96.0
const CITY_SUPPORT_RANGE := 140.0
const SIEGE_CAMP_RANGE := 31.0

var positions: Array[Vector2]
var forces: RefCounted
var navigation: RefCounted
var campaign: RefCounted
var turn: int
var operations: Dictionary
var player_orders: Dictionary

func _init(points: Array[Vector2], troops: RefCounted, graph: RefCounted, state: RefCounted, round_number: int, goals: Dictionary, orders: Dictionary) -> void:
	positions = points
	forces = troops
	navigation = graph
	campaign = state
	turn = round_number
	operations = goals
	player_orders = orders

func plan(index: int) -> Dictionary:
	var faction := Geo.army_faction(index)
	var previous: Dictionary = operations.get(index,{})
	var from := positions[index]
	var strength := Forces.roster_power(forces.armies[index])
	var budget := MOVE * Forces.march_multiplier(forces.armies[index])
	var towns: Array[String] = []
	var defense: Dictionary = {}
	var defense_score := -INF
	var siege_relief := {}
	var relief_distance := INF
	var offense: Dictionary = {}
	var offense_score := -INF
	var needs_reinforcements := false
	for city: String in Geo.CITIES:
		var point := Geo.position_of(city)
		var distance := from.distance_to(point)
		var owner: int = campaign.owner(city)
		if owner == faction:
			towns.append(city)
			var threat := city_threat(city)
			if threat.is_empty(): continue
			if threat.get("besieging",false):
				var attack := intercept(index,threat.army,strength)
				if not attack.is_empty():
					var travel := route_length(attack.get("path",PackedVector2Array()))
					if travel < relief_distance:
						siege_relief = attack
						relief_distance = travel
					continue
			var guard := city_order("defend",city,from,camp(city,index))
			if guard.is_empty(): continue
			var score: float = threat.urgency - route_length(guard.path)
			if higher_priority(threat.urgent,defense.get("urgent",false),score,defense_score):
				defense_score = score
				defense = guard
				defense["threat"] = threat.army
				defense["urgent"] = threat.urgent
		elif owner == 0 and not campaign.cities[city].rebel:
			var retake: bool = Geo.STARTING_OWNERS[city] == faction or campaign.cities[city].get("previous_owner",-1) == faction
			var kind := "retake" if retake else "attack_city"
			if (not retake and distance > budget*2.0*Landscape.ROAD_SPEED) or claimed(city,index,kind): continue
			var assault := city_order(kind,city,from,point)
			if assault.is_empty(): continue
			var travel := route_length(assault.path)
			if not retake and travel > budget*2.0: continue
			var allies := strength + support_power(faction,point,index,city)
			var defenders := town_power(city) + support_power(0,point,-1,city)
			if campaign.building_level(city,"wall") > 0: defenders *= 1.45
			if allies < defenders*(0.95 if retake else 1.15):
				needs_reinforcements = needs_reinforcements or retake
				continue
			var score := -travel - defenders*0.3
			if retake and city == Geo.army_home(index): score += MOVE
			if previous.get("kind") == kind and previous.get("city") == city: score += MOVE
			if higher_priority(retake,offense.get("kind") == "retake",score,offense_score):
				offense_score = score
				offense = assault

	if not siege_relief.is_empty(): return siege_relief
	if defense.get("urgent",false):
		var relief := intercept(index,defense.threat,strength)
		return defense if relief.is_empty() else relief
	if offense.get("kind") == "retake":
		return offense
	if not defense.is_empty():
		var relief := intercept(index,defense.threat,strength)
		return defense if relief.is_empty() else relief
	for target: int in player_orders:
		if from.distance_to(positions[target]) > 58.0: continue
		var attack := intercept(index,target,strength)
		if not attack.is_empty(): return attack
	if needs_reinforcements and forces.armies[index].size() < 6:
		var muster := muster_order(index,towns)
		if not muster.is_empty(): return muster
	if not offense.is_empty():
		return offense
	return patrol(index,towns,previous)

func higher_priority(priority: bool, current_priority: bool, score: float, current_score: float) -> bool:
	return priority if priority != current_priority else score > current_score

func city_threat(city: String) -> Dictionary:
	var point := Geo.position_of(city)
	var siege: Dictionary = campaign.sieges.get(city,{})
	var besieger: int = siege.get("army",0)
	if not siege.is_empty() and player_orders.has(besieger) and positions[besieger].distance_to(point) <= SIEGE_CAMP_RANGE:
		return {"army":besieger,"urgency":MOVE*4.0,"urgent":true,"besieging":true}
	var threat: Dictionary = {}
	var best := 0.0
	for index: int in player_orders:
		var distance := positions[index].distance_to(point)
		if distance > THREAT_RANGE: continue
		var ordered: bool = player_orders[index] == city
		var urgency := THREAT_RANGE-distance+(MOVE*2.0 if ordered else 0.0)
		if urgency > best:
			best = urgency
			threat = {"army":index,"urgency":urgency,"urgent":ordered}
	return threat

func intercept(index: int, target: int, strength: float) -> Dictionary:
	var from := positions[index]
	var point := positions[target]
	var distance := from.distance_to(point)
	var budget := MOVE * Forces.march_multiplier(forces.armies[index])
	if distance > budget*Landscape.ROAD_SPEED+CONTACT_RANGE: return {}
	if strength + support_power(Geo.army_faction(index),point,index) < (Forces.roster_power(forces.armies[target])+support_power(0,point,target))*0.85:
		return {}
	if distance <= CONTACT_RANGE and (from.is_equal_approx(point) or (navigation.is_land(from) and navigation.land_segment(from,point))):
		return {"kind":"intercept","player_army":target}
	var path: PackedVector2Array = navigation.route(from,point)
	if path.is_empty() or route_length(path) > budget+CONTACT_RANGE: return {}
	return {"kind":"intercept","player_army":target,"path":path}

func support_power(faction: int, point: Vector2, excluded_army: int, excluded_city := "") -> float:
	var power := 0.0
	for index in positions.size():
		if index != excluded_army and Geo.army_faction(index) == faction and not forces.armies[index].is_empty() and within_support_range(navigation,positions[index],point,ARMY_SUPPORT_RANGE):
			power += Forces.roster_power(forces.armies[index])
	for city: String in Geo.CITIES:
		if city == excluded_city or campaign.owner(city) != faction or campaign.cities[city].rebel or campaign.sieges.has(city):
			continue
		if within_support_range(navigation,Geo.position_of(city),point,CITY_SUPPORT_RANGE):
			power += town_power(city)
	return power

static func within_support_range(graph: RefCounted, from: Vector2, battle: Vector2, limit: float) -> bool:
	if from.distance_squared_to(battle) > limit * limit: return false
	if from.is_equal_approx(battle): return true
	if graph.is_land(from) and graph.land_segment(from,battle): return true
	# A river or lake can make a nearby source too far away by the available crossings.
	var path: PackedVector2Array = graph.route(from,battle) if graph.is_land(battle) else graph.route(battle,from)
	if path.is_empty(): return false
	var distance := 0.0
	for i in range(1,path.size()):
		distance += path[i-1].distance_to(path[i])
	return distance <= limit

func town_power(city: String) -> float:
	var roster: Array = forces.garrisons.get(city,[])
	return Forces.roster_power(roster) + float(campaign.militia_reserve(city,roster,turn))*0.8

func claimed(city: String, index: int, kind: String) -> bool:
	for ally: int in operations:
		if ally == index or Geo.army_faction(ally) != Geo.army_faction(index) or forces.armies[ally].is_empty():
			continue
		var order: Dictionary = operations[ally]
		if order.get("city") == city and order.get("kind") == kind:
			return true
	return false

func patrol(index: int, towns: Array[String], previous: Dictionary) -> Dictionary:
	var from := positions[index]
	var city: String = previous.get("city","")
	if previous.get("kind") == "patrol" and city in towns and not claimed(city,index,"patrol"):
		var continuation := city_order("patrol",city,from,camp(city,index))
		if continuation.get("path",PackedVector2Array()).size() >= 2: return continuation
	for offset in towns.size():
		city = towns[(turn+index+offset-1)%towns.size()]
		if from.distance_to(Geo.position_of(city)) <= GUARD_RANGE or claimed(city,index,"patrol"): continue
		var route := city_order("patrol",city,from,camp(city,index))
		if not route.is_empty(): return route
	return {}

func muster_order(index: int, towns: Array[String]) -> Dictionary:
	var best := INF
	var order: Dictionary = {}
	for city in towns:
		if campaign.sieges.has(city) or not campaign.occupation_issue(city).is_empty(): continue
		var candidate := city_order("muster",city,positions[index],camp(city,index))
		if candidate.is_empty(): continue
		var distance := route_length(candidate.path)
		if distance < best:
			best = distance
			order = candidate
	return order

func camp(city: String, index: int) -> Vector2:
	var point := Geo.army_camp(index,city)
	return point if navigation.is_land(point) else Geo.position_of(city)

func city_order(kind: String, city: String, from: Vector2, target: Vector2) -> Dictionary:
	var path: PackedVector2Array = navigation.route(from,target)
	if path.is_empty() and not from.is_equal_approx(target): return {}
	return {"kind":kind,"city":city,"path":path}

func route_length(points: PackedVector2Array) -> float:
	return navigation.route_cost(points)
