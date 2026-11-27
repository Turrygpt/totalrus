extends RefCounted

const Geo = preload("res://campaign_map/geography.gd")
const Data = preload("res://campaign_map/campaign_state.gd")
const Experience = preload("res://scripts/unit_experience.gd")
const Charge = preload("res://scripts/cavalry_charge.gd")
const Equipment = preload("res://scripts/unit_equipment.gd")
const LADOGA_COMMANDER_ID := "ladoga_rebels_0"
const LADOGA_COMMANDER_TITLE := "Ладожский воевода"

var armies := []
var stations: Array[String] = []
var garrisons := {}
var holdings: Array[String] = []

func _init() -> void:
	var companions := [
		[["varangian",40]], [["militia",45]], [["infantry",46],["archer",24],["cavalry",21]],
		[["infantry",44],["archer",20]], [["militia",45]], [["infantry",45],["archer",25]],
		[["infantry",60]], [["archer",30]],
	]
	for i in Geo.ARMIES.size():
		stations.append(Geo.army_home(i))
		armies.append(roster(Geo.ARMIES[i].id,[["princely",Data.UNITS.princely[1]]]+companions[i]))
	for id in Geo.CITIES:
		if Geo.STARTING_OWNERS[id] == 0:
			holdings.append(id)

func roster(prefix: String, units: Array) -> Array:
	var result := []
	for i in units.size():
		var kind: String = units[i][0]
		var spec: Array = Data.UNITS[kind]
		result.append({"id": "%s_%d" % [prefix,i], "kind": kind, "title": "Личная дружина" if kind == "princely" and prefix == "oleg" else spec[0], "count": units[i][1], "max": spec[1]})
	return result

static func normalize_units(units: Array) -> void:
	var maximum: int = Data.UNITS.princely[1]
	for unit in units:
		if unit.id == LADOGA_COMMANDER_ID:
			var solo_commander: bool = unit.get("max",0) == 1
			unit.kind = "light_cavalry"
			unit.title = LADOGA_COMMANDER_TITLE
			unit.commander = true
			unit.max = Data.UNITS.light_cavalry[1]
			unit.count = unit.max if solo_commander and unit.count == 1 else mini(unit.count,unit.max)
		if unit.kind == "cavalry":
			unit.title = Data.UNITS.cavalry[0]
		if unit.kind != "princely":
			continue
		unit.title = "Личная дружина" if unit.id == "oleg_0" else Data.UNITS.princely[0]
		unit.max = maximum
		unit.count = mini(unit.count,maximum)

func headcount(units: Array) -> int:
	var total := 0
	for unit in units:
		total += unit.count
	return total

static func squad_name(unit: Dictionary) -> String:
	var id := String(unit.id)
	if id.ends_with("_garrison_militia"):
		var city := id.trim_suffix("_garrison_militia")
		return "%s гарнизон" % Geo.CITY_ADJECTIVES[city]
	return unit.get("squad_name",unit.title)

static func squad_tooltip(roster: Array) -> String:
	var lines := PackedStringArray()
	for unit in roster:
		if unit.count > 0:
			lines.append("%s · %s · %d" % [squad_name(unit),unit.title,unit.count])
	return "\n".join(lines)

static func march_multiplier(units: Array) -> float:
	if not units.is_empty() and units.all(func(unit): return unit.kind in Charge.UNIT_KINDS or unit.kind == "khazar"):
		return 1.35
	return 1.0

static func roster_power(roster: Array, research := {}) -> float:
	var power := 0.0
	var morale_readiness := 1.0 + float(research.get("morale",0))*.005
	var research_stamina_cost := 1.0 - float(research.get("stamina",0))
	var armored: Array = research.get("armored_units",[])
	for unit in roster:
		var rank := Experience.rank(unit.get("xp",0))
		var base: float = {"militia":0.8,"infantry":1.0,"archer":1.25,"light_cavalry":1.12,"cavalry":1.4,"princely":1.8,"varangian":1.5,"khazar":1.55}.get(unit.kind,1.0)
		var research_protection := 1.0 - float(research.get("armor",0)) if unit.kind in armored else 1.0
		var gear := Equipment.levels(unit)
		var protection := research_protection * (1.0-Equipment.armor_reduction(gear.y))
		var veteran_bonus := 1.0 + (Experience.attack_tempo(rank)-1.0)*.5 + Experience.morale(rank)*.005
		# Autoresolve estimates a mix of melee and ranged damage.
		var melee_share := .5 if unit.kind in ["archer","khazar"] else 1.0
		var ranged_attack := 1.0 + (1.0-Experience.projectile_spread(rank))*.5
		var attack := lerpf(ranged_attack,Experience.melee_attack(rank),melee_share) * Equipment.weapon_damage(gear.x)
		if unit.kind in Charge.UNIT_KINDS:
			attack *= lerpf(1.0,Experience.charge_impact(rank),.25)
		protection *= 1.0 - Experience.melee_defense(rank)*.5
		var stamina_saving := 1.0 - research_stamina_cost * Experience.stamina_cost(rank)
		var readiness := morale_readiness + stamina_saving*.2
		power += unit.count * base * veteran_bonus * readiness * attack / protection
	return power

static func auto_casualties(roster: Array, research: Dictionary, fraction: float, survivors: Dictionary) -> int:
	var exposure := {"militia":1.35,"infantry":1.15,"varangian":1.18,"princely":.62,
		"cavalry":.93,"light_cavalry":.77,"archer":.58,"khazar":.52}
	var risks: Array[float] = []
	var casualties: Array[int] = []
	var strength := 0
	for unit in roster:
		strength += unit.count
		casualties.append(0)
		var armor := Equipment.armor_reduction(Equipment.levels(unit).y)
		if unit.kind in research.get("armored_units",[]):
			armor = 1.0 - (1.0 - armor) * (1.0 - float(research.get("armor",0)))
		var veteran_defense := Experience.melee_defense(Experience.rank(unit.get("xp",0)))
		# Stable variation distinguishes otherwise identical units when the battle is reloaded.
		var exposure_variation := lerpf(.60,1.40,float(posmod(String(unit.id).sha256_text().substr(0,4).hex_to_int(),101)) / 100.0)
		risks.append(float(exposure.get(unit.kind,1.0)) * exposure_variation * (1.0 - armor) * (1.0 - veteran_defense))
	var budget := clampi(roundi(strength * fraction),0,strength)
	# Allocate the side's casualty budget by exposure, with diminishing risk as a unit loses men.
	for _loss in budget:
		var highest := -1.0
		var chosen := -1
		for i in roster.size():
			if casualties[i] >= roster[i].count: continue
			var remaining_share: float = 1.0 - float(casualties[i]) / roster[i].count
			var score: float = risks[i] * remaining_share * remaining_share
			if score > highest:
				highest = score
				chosen = i
		casualties[chosen] += 1
	for i in roster.size():
		survivors[roster[i].id] = roster[i].count - casualties[i]
	return budget

static func auto_leader_lost(roster: Array, counts: Dictionary, turn: int) -> bool:
	for unit in roster:
		if unit.kind != "princely" or not counts.has(unit.id): continue
		var losses: int = unit.count - counts[unit.id]
		var risk := .5 * float(losses) / maxi(1,unit.count)
		var roll := float(posmod(("%s/%d" % [unit.id,turn]).sha256_text().substr(0,4).hex_to_int(),1000)) / 1000.0
		return counts[unit.id] == 0 or roll < risk
	return false

static func auto_experience(roster: Array, opposing_losses: int, research: Dictionary, power: float) -> Dictionary:
	var experience := {}
	for unit in roster:
		var share := roster_power([unit],research) / maxf(.001,power)
		var capacity: int = unit.get("max",Data.UNITS[unit.kind][1])
		experience[unit.id] = Experience.earn_kills(unit.get("xp",0),opposing_losses*share,capacity)
	return experience

static func is_local_garrison(city: String, unit: Dictionary) -> bool:
	return String(unit.id).begins_with(city+"_garrison_")

static func is_city_militia(city: String, unit: Dictionary) -> bool:
	return is_local_garrison(city,unit) or String(unit.id).begins_with("muster_")

func survivors(units: Array, counts: Dictionary, combat_experience: Dictionary = {}, victory := false) -> Array:
	var remaining := []
	for unit in units:
		var count: int = clampi(counts.get(unit.id,0),0,unit.count)
		if count > 0:
			var updated: Dictionary = unit.duplicate()
			updated.count = count
			if combat_experience.has(unit.id):
				var earned := maxf(unit.get("xp",0),combat_experience[unit.id])
				updated.xp = Experience.after_battle(earned,victory)
			remaining.append(updated)
	return remaining

func retreat_army(index: int, avoid: String, campaign: RefCounted) -> void:
	var place := ""
	var best := INF
	for id in Geo.CITIES:
		if campaign.owner(id) != Geo.army_faction(index) or campaign.cities[id].rebel:
			continue
		var distance := Geo.position_of(avoid).distance_squared_to(Geo.position_of(id))
		if id == avoid or id in stations:
			distance += 1000000.0
		if distance < best:
			best = distance
			place = id
	stations[index] = place
