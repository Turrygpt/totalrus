extends SceneTree
const State = preload("res://campaign_map/campaign_state.gd")
const Geo = preload("res://campaign_map/geography.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ",message)
	if not condition: failures += 1

func _init() -> void:
	var state := State.new()
	for province in Geo.PROVINCES.size():
		var towns := Geo.CITIES.keys().filter(func(id): return Geo.CITIES[id][1]==province)
		check(towns.size()>0 and towns.size()<=4,"province %d has at most four towns" % province)
	state.factions[0].silver = 10000
	state.cities.novgorod.manpower = 10
	state.cities.ladoga.manpower = 60
	state.cities.russa.manpower = 90
	check(state.province_manpower(0,0)==70,"population shared by owner, excludes rival towns")
	var roster := []
	check(state.recruit(0,"novgorod","militia",roster),"recruitment can use another controlled town's reserve")
	check(state.province_manpower(0,0)==25 and state.cities.russa.manpower==90,"recruitment spends only own provincial population")
	state.capture("russa",0,"occupy")
	check(state.province_manpower(0,0)==25 and state.cities.russa.unintegrated==90,"capture does not release the captured reserve immediately")
	check(not state.build(0,"russa","shrine") and not state.recruit(0,"russa","militia",roster),"occupation blocks building and recruitment")
	state.capture("polotsk",0,"occupy")
	state.cities.polotsk.occupation=0
	state.cities.polotsk.manpower=100
	check(state.province_manpower(0,0)==25 and state.province_manpower(0,1)==100,"different province has its own population")
	var guards := {}
	var armies: Array[Dictionary] = []
	state.advance(0,armies,1,[],guards)
	check(state.cities.russa.occupation==1 and state.cities.russa.manpower==0,"occupation lasts a complete first turn")
	state.advance(0,armies,2,[],guards)
	check(state.cities.russa.occupation==0 and state.cities.russa.manpower==0,"two turns restore order without instant population transfer")
	state.advance(0,armies,3,[],guards)
	check(state.cities.russa.unintegrated>0 and state.cities.russa.manpower>0,"captured population integrates gradually")
	state.cities.ladoga.buildings={"hall":1,"farm":1}
	check(state.build(0,"ladoga","wall"),"non-capital town can build walls in a separate slot")
	var building_test := State.new()
	building_test.factions[0].silver = 10000
	var town: Dictionary = building_test.cities.ladoga
	for level in range(1,5):
		town.buildings.hall = level
		check(building_test.building_slots("ladoga")==[3,5,6,7][level-1],"hall level %d sets the slot limit" % level)
	town.buildings.hall = 1
	check(not building_test.build(0,"ladoga","farm"),"farm II is blocked by hall I")
	town.buildings.hall = 2
	check(building_test.build(0,"ladoga","farm"),"hall II unlocks farm II")
	town.queue = {}
	town.buildings.farm = 2
	building_test.factions[0].tech.append("husbandry")
	check(not building_test.build(0,"ladoga","farm"),"farm III is blocked by hall II even with technology")
	town.buildings.hall = 3
	check(building_test.build(0,"ladoga","farm"),"hall III and technology unlock farm III")
	var militia_test := State.new()
	var local: Dictionary = militia_test.cities.ladoga
	var reserve_before: int = militia_test.cities.novgorod.manpower
	local.manpower = 91
	check(militia_test.militia_reserve("ladoga",[],1)==36,"militia uses 40% of the town's own population, rounded down")
	for level in range(1,5):
		local.buildings.hall = level
		local.manpower = 900
		var militia := []
		var maximum: int = [100,150,200,250][level-1]
		check(militia_test.muster_militia("ladoga",militia,level)==maximum and local.manpower==900-maximum,"militia cap at hall level %d" % level)
		check(militia_test.muster_militia("ladoga",militia,level)==0,"muster cannot be repeated in the same turn")
		check(militia_test.militia_reserve("ladoga",militia,level+1)==0,"already mobilized militia counts towards the limit")
	check(militia_test.cities.novgorod.manpower==reserve_before,"nearby towns do not pay for this muster")
	var north: Dictionary = state.province_account(0,0)
	var south_before: Dictionary = state.province_account(0,1)
	armies.append({"region":"polotsk","station":"polotsk","index":0,"roster":[{"kind":"cavalry","count":30}]})
	var south: Dictionary = state.province_account(0,1,armies)
	check(south.food==south_before.food-2 and state.province_account(0,0,armies).food==north.food,"food consumption stays in the army's province")
	state.cities.ladoga.occupation=0
	state.sieges.ladoga={}
	check(state.province_manpower(0,0)==state.cities.novgorod.manpower+state.cities.russa.manpower,"siege isolates the besieged reserve")
	check_unrest()
	check_ai_order()
	var restored := State.new()
	restored.restore(state.snapshot())
	check(restored.snapshot()==state.snapshot(),"new economy survives save/restore")
	var legacy := State.new().snapshot().duplicate(true)
	legacy.erase("schema")
	legacy.factions.resize(7)
	legacy.recruitment.resize(7)
	legacy.cities.russa.rebel=true
	for city in legacy.cities.values():
		for key in ["occupation","unintegrated","revolt_turns","relief_turns","relief_cooldown"]: city.erase(key)
		city.revolt_cooldown = 2
	restored.restore(legacy)
	check(restored.factions.size()==8 and restored.owner("russa")==Geo.REBELS,"legacy save gains rebel faction and occupation defaults")
	print("PROVINCE_QA failures=",failures)
	quit(failures)

func check_unrest() -> void:
	var state := State.new()
	var city := "russa"
	var town: Dictionary = state.cities[city]
	var armies: Array[Dictionary] = []
	var guards := {}
	state.capture(city,0,"occupy")
	town.occupation = 0
	var base := state.town_yield(city)
	town.order = -24
	var normal := state.town_yield(city)
	check(base.silver==roundi(normal.silver*.75) and base.food==normal.food,"at -25 unrest cuts only silver")
	town.order = -59
	state.resolve_unrest(city,state.order_forecast(city,0,armies,guards),guards)
	check(not state.rebellions.has(city),"no rebel band above -60")
	town.order = -60
	state.factions[0].tax = 0
	town.culture = 0
	town.buildings = {}
	state.resolve_unrest(city,state.order_forecast(city,0,armies,guards),guards)
	check(not state.rebellions.has(city),"a town recovering above -60 avoids the rebel band")
	town.order = -62
	state.resolve_unrest(city,state.order_forecast(city,0,armies,guards),guards)
	check(town.order==-60 and state.rebellions.has(city) and state.owner(city)==0,"at -60 a rebel band spawns without taking the town")
	var band_yield := state.town_yield(city)
	town.occupation = 1
	check(state.town_yield(city)==band_yield and band_yield.silver==4 and band_yield.food==1,"the rebel band and occupation penalties do not stack or cut food")
	town.occupation = 0
	town.order = -53
	state.resolve_unrest(city,state.order_forecast(city,0,armies,guards),guards)
	check(town.order==-51 and state.rebellions.has(city),"an existing band stays until order reaches -50")
	state.resolve_unrest(city,state.order_forecast(city,0,armies,guards),guards)
	check(town.order==-49 and not state.rebellions.has(city),"the band disperses peacefully above -50")
	town.order = -100
	state.resolve_unrest(city,state.order_forecast(city,-1,armies,guards),guards)
	check(town.order==-100 and town.revolt_turns==2 and state.owner(city)==0,"even at -100 the first warning gives two turns")

	state = State.new()
	state.capture(city,0,"loot")
	state.factions[0].tax = 2
	state.factions[0].silver = 5000
	town = state.cities[city]
	guards.novgorod = []
	for i in 32: guards.novgorod.append({"kind":"cavalry","count":1})
	# A field army consumes local food without contributing to order inside the city.
	var cavalry := []
	for i in 32: cavalry.append({"kind":"cavalry","count":State.UNITS.cavalry[1]})
	armies.append({"index":0,"roster":cavalry,"region":city,"station":""})
	state.advance(0,armies,1,[],guards)
	check(town.order==-70 and town.revolt_turns==2 and state.rebellions.has(city),"at -70 the first warning gives two full turns")
	state.advance(0,armies,2,[],guards)
	check(town.order==-75 and town.revolt_turns==1 and state.owner(city)==0,"the city is still controlled after one critical turn")
	var food: int = state.province_account(0,0,armies,guards).food
	var forecast := state.order_forecast(city,food,armies,guards)
	check(forecast.next==-100 and forecast.revolt,"forecast predicts loss on the second critical turn")
	var rescued := State.new()
	rescued.restore(state.snapshot().duplicate(true))
	check(rescued.cities[city].revolt_turns==1 and rescued.rebellions==state.rebellions,"save preserves countdown and rebel roster")
	state.advance(0,armies,3,[],guards)
	check(state.owner(city)==Geo.REBELS and guards[city].size()==3,"missing the deadline transfers the city and rebel roster")

	var rescue_guards := {"novgorod":guards.novgorod}
	rescued.factions[0].tax = 0
	var treasury: int = rescued.factions[0].silver
	check(rescued.distribute_relief(0,city) and rescued.factions[0].silver==treasury-50,"relief is available during occupation and costs 50 silver")
	check(not rescued.distribute_relief(0,city) and rescued.factions[0].silver==treasury-50,"repeat relief is blocked without charging again")
	forecast = rescued.order_forecast(city,food,armies,rescue_guards)
	check(forecast.next==-68 and forecast.revolt_turns==0 and not forecast.revolt,"lower taxes and relief forecast a last-turn rescue")
	rescued.advance(0,armies,3,[],rescue_guards)
	town = rescued.cities[city]
	check(town.order==forecast.next and town.revolt_turns==0 and rescued.owner(city)==0,"relief saves the city on the last available turn")
	var saved_relief := State.new()
	saved_relief.restore(rescued.snapshot().duplicate(true))
	check(saved_relief.cities[city].relief_turns==1 and saved_relief.cities[city].relief_cooldown==3,"save preserves relief duration and cooldown")
	rescued.advance(0,armies,4,[],rescue_guards)
	check(town.order==-61 and town.relief_turns==0 and town.relief_cooldown==2,"relief applies exactly twice")

func check_ai_order() -> void:
	var state := State.new()
	var city := "polotsk"
	var faction := state.owner(city)
	var town: Dictionary = state.cities[city]
	for other in state.cities:
		if other != city and state.owner(other) == faction:
			state.cities[other].owner = 0
	town.buildings = {}
	town.order = -80
	town.revolt_turns = 1
	town.manpower = 150
	state.factions[faction].tax = 2
	state.factions[faction].silver = 50
	var guards := {}
	var armies: Array[Dictionary] = []
	var province: int = Geo.CITIES[city][1]
	check(state.order_forecast(city,1,armies,guards).revolt,"AI city was due to revolt without intervention")
	check(state.prepare_ai_order(faction,armies,1,guards),"AI prioritizes the city before routine spending")
	check(state.factions[faction].tax==0 and state.factions[faction].silver==0 and town.relief_turns==2,"AI reduces taxes and pays for relief")
	check(guards.has(city) and guards[city].size()==1 and town.manpower==150-State.UNITS.militia[1],"AI spends local manpower on as much militia as provincial food allows")
	check(state.province_account(faction,province,armies,guards).food==0,"AI reinforcements keep provincial food nonnegative")
	state.advance(faction,armies,1,[],guards)
	check(state.owner(city)==faction and town.order==-69 and town.revolt_turns==0,"AI saves the city on the last turn")
	state.prepare_ai_order(faction,armies,2,guards)
	check(guards[city].size()==1 and state.factions[faction].tax==0,"AI avoids over-mustering when supplies are tight and keeps taxes low")
	town.order = 10
	state.prepare_ai_order(faction,armies,3,guards)
	check(state.factions[faction].tax==1,"AI restores moderate taxes when all its towns stabilize")
	state.factions[0].tax = 2
	state.cities.novgorod.order = -90
	state.cities.novgorod.revolt_turns = 1
	check(not state.prepare_ai_order(0,armies,3,guards) and state.factions[0].tax==2,"AI order handling leaves the player alone")
