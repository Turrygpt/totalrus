extends RefCounted

const Geo = preload("res://campaign_map/geography.gd")
const State = preload("res://campaign_map/campaign_state.gd")
const Forces = preload("res://campaign_map/forces.gd")
const VERSION := 4
enum Slot { MANUAL, END_TURN, BATTLE_START, BATTLE_END }

const AUTOSAVE_SUFFIXES := {
	Slot.END_TURN: "end_turn",
	Slot.BATTLE_START: "battle_start",
	Slot.BATTLE_END: "battle_end",
}

static func slot_path(manual_path: String, slot: Slot) -> String:
	if slot == Slot.MANUAL: return manual_path
	return "%s.%s.save" % [manual_path.get_basename(),AUTOSAVE_SUFFIXES[slot]]

static func write(path: String, data: Dictionary) -> Error:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	var error := file.get_error() if file.store_var(data) else ERR_FILE_CANT_WRITE
	file.flush()
	if error == OK: error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary,path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error

# The first save format used one index for both an army and its faction.
const LEGACY_INDEX := [0,2,6]

static func upgrade(data: Dictionary) -> Dictionary:
	if data.get("version") == VERSION:
		return data
	if data.get("version") in [2,3]:
		return data
	if data.get("version") != 1 or data.get("armies",[]).size() != LEGACY_INDEX.size():
		return {}
	var old: Dictionary = data.campaign
	var state := State.new().snapshot()
	state.erase("rewarded_provinces")
	var new_forces := Forces.new()
	var positions: Array[Vector2] = []
	for index in Geo.ARMIES.size(): positions.append(Geo.army_camp(index,Geo.army_home(index)))
	for city in old.cities:
		var town: Dictionary = old.cities[city]
		var original := 0 if city == "novgorod" else (1 if city in ["russa","kholm","polotsk","vitebsk","smolensk"] else 2)
		town.owner = Geo.STARTING_OWNERS[city] if town.owner == original else LEGACY_INDEX[town.owner]
		town.culture = Geo.STARTING_OWNERS[city] if town.culture == original else LEGACY_INDEX[town.culture]
		state.cities[city] = town
	for prior in LEGACY_INDEX.size():
		var index: int = LEGACY_INDEX[prior]
		state.factions[index] = old.factions[prior]
		state.recruitment[index] = old.recruitment[prior]
		state.stances[index] = old.stances[prior]
		state.leaders[index] = old.leaders[prior]
		if state.leaders[index].generation == 0:
			state.leaders[index].name = Geo.ARMIES[index].name
		var roster: Array = data.armies[prior]
		if not roster.is_empty() and not roster.any(func(unit): return unit.kind == "princely"):
			roster.push_front(new_forces.armies[index][0])
		new_forces.armies[index] = roster
		new_forces.stations[index] = data.stations[prior]
		positions[index] = data.positions[prior]
	for index in Geo.ARMIES.size():
		if index in LEGACY_INDEX: continue
		var faction := Geo.army_faction(index)
		var capital := Geo.army_home(index)
		if state.cities[capital].owner == faction: continue
		var towns := Geo.CITIES.keys().filter(func(city): return state.cities[city].owner == faction)
		if towns.is_empty():
			new_forces.armies[index] = []
			new_forces.stations[index] = ""
		else:
			new_forces.stations[index] = towns[0]
			positions[index] = Geo.army_camp(index,towns[0])
	for key in ["serial","journal","sieges"]: state[key] = old[key]
	var patrols: Dictionary[int,String] = {}
	for index in data.patrols:
		patrols[LEGACY_INDEX[index]] = data.patrols[index]
	data.patrols = patrols
	data.destination_army = remap_index(data.destination_army)
	data.enemy_actor = remap_index(data.enemy_actor) if data.enemy_actor < LEGACY_INDEX.size() else Geo.ARMIES.size()
	if not data.encounter.is_empty():
		var encounter: Dictionary = data.encounter
		encounter.army = remap_index(encounter.army)
		if encounter.army > 0:
			var guard: Array = new_forces.armies[encounter.army].filter(func(unit): return unit.kind == "princely")
			for unit in guard:
				if not encounter.defenders.any(func(defender): return defender.id == unit.id):
					encounter.defenders.append(unit)
			if not encounter.city_battle:
				encounter.target = state.leaders[encounter.army].name
				encounter.title = ("Оборона дружины · " if encounter.enemy_attack else "Полевое сражение · ") + encounter.target
	data.version = 3
	data.campaign = state
	data.armies = new_forces.armies
	data.stations = new_forces.stations
	data.positions = positions
	return data

static func remap_index(index: int) -> int:
	return LEGACY_INDEX[index] if index >= 0 and index < LEGACY_INDEX.size() else -1
