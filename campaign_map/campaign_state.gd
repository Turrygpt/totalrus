extends RefCounted

const Geo = preload("res://campaign_map/geography.gd")
const Experience = preload("res://scripts/unit_experience.gd")
const Equipment = preload("res://scripts/unit_equipment.gd")
const HALL_SLOTS := [3, 5, 6, 7]
const HALL_MILITIA_LIMIT := [100, 150, 200, 250]
const SIEGE_TURNS := 5
const LEVEL_NAMES := ["I", "II", "III", "IV"]
const FISHING_BRANCH := 1
const HUNTING_BRANCH := 2
const REPAIR_COST := 35
const PROVINCE_UNIFICATION_REWARD := 250
const UNREST_ORDER := -25
const REBEL_BAND_ORDER := -60
const REBEL_DISPERSAL_ORDER := -50
const REVOLT_ORDER := -70
const REVOLT_TURNS := 2
const RELIEF_COST := 50
const RELIEF_ORDER := 8
const RELIEF_TURNS := 2
const RELIEF_COOLDOWN := 4
const GUARD_ORDER_STEP := 25
const GUARD_ORDER_LIMIT := 8
const RESOURCES := {
	"novgorod":"Меха", "russa":"Соль", "kholm":"Лес", "polotsk":"Мёд и воск",
	"vitebsk":"Лён", "smolensk":"Железо", "orsha":"Лён", "mogilev":"Керамика",
	"lyubech":"Мёд и воск", "chernigov":"Зерно", "kyiv":"Зерно", "ladoga":"Меха",
	"izborsk":"Камень", "pskov":"Лён", "north_pogost":"Меха", "upper_volok":"Лес",
	"toropets":"Мёд и воск", "west_pogost":"Мёд и воск", "berezina":"Лес",
	"desna":"Лён", "korosten":"Лес", "pereyaslavl":"Зерно", "sula":"Зерно",
}
# Bonus in silver and food for each level of an operating market.
const TRADE_GOODS := {
	"Меха":Vector2i(4,0), "Соль":Vector2i(4,0), "Лес":Vector2i(2,0),
	"Мёд и воск":Vector2i(3,1), "Лён":Vector2i(3,0), "Железо":Vector2i(4,0),
	"Керамика":Vector2i(3,0), "Зерно":Vector2i(2,2), "Камень":Vector2i(2,0),
}
const BUILDINGS := {
	"hall": ["Двор", 90, 2, 22, 0, 1],
	"farm": ["Хозяйство", 65, 1, 10, 8, 0],
	"market": ["Торг", 100, 2, 30, 2, 0],
	"warehouse": ["Товарный амбар", 80, 1, 14, 7, 0],
	"forge": ["Кузница", 110, 2, 10, 0, 0],
	"barracks": ["Казармы", 100, 2, 0, 0, 1],
	"range": ["Стрельбище", 75, 1, 0, 0, 1],
	"stables": ["Конюшни", 100, 2, 0, 0, 0],
	"wall": ["Укрепления", 110, 2, 0, 0, 2],
	"shrine": ["Святилище", 90, 2, 1, 0, 4],
	"fur_house": ["Меховой склад", 110, 2, 8, 0, 0],
	"saltworks": ["Солеварня", 130, 3, 7, 12, 0],
	"timber_yard": ["Лесной двор", 105, 2, 8, 0, 0],
	"apiary": ["Бортный двор", 90, 2, 9, 4, 2],
	"linen_yard": ["Льняная мастерская", 110, 2, 15, 0, 1],
	"bloomery": ["Сыродутный двор", 125, 3, 9, 0, 0],
	"pottery": ["Гончарный двор", 115, 2, 19, 0, 0],
	"threshing_yard": ["Гумно", 105, 2, 3, 16, 0],
	"stone_yard": ["Каменный двор", 115, 2, 7, 0, 0],
}
# Silver, food and order spent per operating level.
const BUILDING_UPKEEP := {
	"hall": Vector3i(0,1,0),
	"market": Vector3i(0,0,2),
	"forge": Vector3i(0,1,0),
	"barracks": Vector3i(0,1,0),
	"range": Vector3i(0,1,0),
	"stables": Vector3i(0,2,0),
	"wall": Vector3i(0,1,0),
	"shrine": Vector3i(0,2,0),
}
# Local resource and building required to start construction.
const SPECIAL_BUILDINGS := {
	"fur_house": ["Меха", "market"],
	"saltworks": ["Соль", "market"],
	"timber_yard": ["Лес", "farm"],
	"apiary": ["Мёд и воск", "farm"],
	"linen_yard": ["Лён", "farm"],
	"bloomery": ["Железо", "forge"],
	"pottery": ["Керамика", "market"],
	"threshing_yard": ["Зерно", "farm"],
	"stone_yard": ["Камень", "wall"],
}
const BUILDING_UPGRADES := {
	"hall": [["Двор наместника"],["Княжеский терем"]],
	"farm": [["Скотный двор","Рыболовный промысел","Изба охотника"],["Животноводческая усадьба","Рыбная пристань","Пушной двор"]],
	"market": [["Торговые ряды"],["Гостиный двор"]],
	"warehouse": [["Зернохранилище"],["Запасной двор"]],
	"forge": [["Оружейная мастерская"],["Оружейный двор"]],
	"barracks": [["Дружинный стан"],["Дружинный двор"]],
	"range": [["Лучный двор"],["Лучная школа"]],
	"stables": [["Конный двор"],["Конный завод"]],
	"wall": [["Деревянная крепость"],["Каменный детинец"]],
	"shrine": [["Капище"],["Храмовый двор"]],
}
const BUILDING_PURPOSE := {
	"hall":"Доход, порядок и прирост населения. Улучшение даёт место под здание и повышает предел населения.",
	"farm":"Даёт продовольствие, увеличивает прирост и вместимость населения.",
	"market":"Приносит серебро и продовольствие. Открывает товарный амбар.",
	"warehouse":"Торговля излишками зерна даёт продовольствие и серебро. Нужен действующий торг.",
	"forge":"Открывает платные улучшения оружия и доспехов в гарнизоне. Уровни I, II и III дают доступ к бронзовым, серебряным и золотым меткам. Открывает набор копейщиков, а с конюшнями — тяжёлой конницы.",
	"barracks":"Дают бронзовую лычку при наборе, усиливают гарнизон и увеличивают прирост населения.",
	"range":"Открывает набор лучников. Улучшения снижают цену найма лучников.",
	"stables":"Открывают лёгкую конницу. Кузница даёт снаряжение для тяжёлой. Со II уровня набор дешевле.",
	"wall":"Увеличивают ополчение. Исправные стены любого города требуют осады.",
	"shrine":"Поддерживает порядок и ускоряет приобщение города к культуре владельца.",
	"fur_house":"Сортирует и пакует меха для продажи. Действующий торг приносит дополнительно 5 серебра за уровень.",
	"saltworks":"Выпаривает соль и помогает сохранять продукты. Даёт серебро и продовольствие.",
	"timber_yard":"Заготавливает брёвна и тёс. Даёт серебро и снижает стоимость строительства и улучшения зданий в городе на 10%.",
	"apiary":"Собирает лесной мёд и воск. Даёт серебро, продовольствие и поддерживает порядок.",
	"linen_yard":"Перерабатывает местный лён в полотно. Даёт серебро и поддерживает порядок.",
	"bloomery":"Выплавляет железо для местной кузницы. Даёт серебро и снижает стоимость набора копейщиков и тяжёлой конницы на 8 серебра.",
	"pottery":"Обжигает посуду и тару для торговли. Даёт серебро.",
	"threshing_yard":"Обмолачивает зерно. Даёт продовольствие и немного серебра.",
	"stone_yard":"Готовит камень для городских стен. Даёт серебро и снижает стоимость улучшения укреплений на 25%.",
}
const MILITARY_BUILDINGS := ["forge","barracks","range","stables","wall"]
const UNITS := {
	"militia": ["Ополченцы",45,40,5,1],
	"infantry": ["Копейщики",60,70,8,1],
	"archer": ["Лучники",30,65,7,1],
	"light_cavalry": ["Лёгкая конница",30,95,10,1],
	"cavalry": ["Тяжёлая конница",30,145,15,2],
	"princely": ["Княжеская дружина",30,170,19,2],
	"varangian": ["Варяжские наёмники",40,155,24,0],
	"khazar": ["Хазарские наёмники",30,185,30,0],
}
const UNIT_FOOD := {"militia":1,"infantry":1,"archer":1,"cavalry":2,"light_cavalry":2,"princely":2,"varangian":1,"khazar":2}
const WEAPON_UPGRADE_BASE_COST := 30
const ARMOR_UPGRADE_BASE_COST := 40
const HERO_PREMIUM := 25
const HERO_NAMES := ["Добрыня","Ратибор","Мстислав","Ждан","Ярополк","Вышата","Гостомысл","Боривой",
	"Предслав","Рогволод","Владислав","Всеволод","Святополк","Владимир","Путята","Радогост",
	"Микула","Тугарин","Остромир","Судислав","Брячислав","Добромир","Радим","Станислав"]
const ADVISOR_STRATEGIES := {"off":"Выключен","economy":"Хозяйство","defense":"Оборона","population":"Население"}
const ADVISOR_PRIORITIES := {
	"economy":["farm","market","warehouse","hall"],
	"defense":["wall","barracks","forge","range","stables","hall"],
	"population":["hall","farm","barracks"],
}
const RECRUIT_BUILDINGS := {
	"militia": {}, "infantry": {"barracks":1,"forge":1},
	"archer": {"barracks":1,"range":1}, "light_cavalry": {"stables":1}, "cavalry": {"forge":1,"stables":1},
}
const MERCENARY_REGIONS := {"varangian":[0,1,4,5],"khazar":[2,3,6]}
const MERCENARY_RESTOCK := 4
const LIMIT := 20
const RECRUIT_GROWTH := {"hall":6,"farm":6,"barracks":6}
const TECH := {
	"husbandry": {"name":"Пашенное хозяйство","turns":2,"requires":"","cost":55,"bonus":2,"effect":"+%d еды в каждом городе. Открывает гражданские здания III уровня."},
	"trade": {"name":"Торговые пути","turns":3,"requires":"husbandry","cost":85,"bonus":3,"effect":"+%d серебра в каждом городе за ход до податей."},
	"law": {"name":"Княжеский суд","turns":4,"requires":"trade","cost":130,"bonus":2,"effect":"+%d к изменению порядка за ход в каждом городе."},
	"merchant_courts": {"name":"Купеческие дворы","turns":5,"requires":"law","cost":185,"bonus":5,"effect":"+%d серебра за уровень действующего торга до податей."},
	"granaries": {"name":"Хлебные запасы","turns":3,"requires":"husbandry","cost":80,"bonus":2,"effect":"+%d еды за уровень действующего хозяйства."},
	"settlement": {"name":"Новые слободы","turns":4,"requires":"granaries","cost":120,"bonus":6,"effect":"+%d к приросту населения на город за ход."},
	"grain_reserves": {"name":"Земские житницы","turns":4,"requires":"settlement","cost":155,"bonus":3,"effect":"+%d еды за уровень действующего товарного амбара."},
	"drill": {"name":"Дружинный строй","turns":2,"requires":"","cost":60,"bonus":5,"effect":"+%d к стойкости всех отрядов в бою. Открывает военные здания III уровня."},
	"iron": {"name":"Железное дело","turns":3,"requires":"drill","cost":95,"bonus":10,"effect":"На %d%% меньше урона по телу у копейщиков, тяжёлой конницы и княжеской дружины. Открывает улучшения кузницы."},
	"siege": {"name":"Осадное дело","turns":4,"requires":"iron","cost":140,"bonus":1,"effect":"Гарнизон сдаётся на %d ход раньше при осаде."},
	"supply_trains": {"name":"Полковые обозы","turns":4,"requires":"siege","cost":165,"bonus":5,"effect":"На своей территории полевые отряды за ход восполняют ещё %d%% штатной численности при достатке еды и людей."},
	"camp": {"name":"Походная выучка","turns":3,"requires":"drill","cost":85,"bonus":15,"effect":"Все отряды тратят на %d%% меньше выносливости в бою."},
	"standards": {"name":"Полковые стяги","turns":4,"requires":"camp","cost":125,"bonus":5,"effect":"Ещё +%d к стойкости всех отрядов в бою."},
	"retinue_schools": {"name":"Школы дружинников","turns":5,"requires":"standards","cost":200,"bonus":1,"effect":"Новые местные отряды из городов с казармами получают ещё %d ступень опыта."},
}
const TECH_BRANCHES := [
	{"name":"Земля и порядок","root":"husbandry","tiers":[["trade","granaries"],["law","settlement"],["merchant_courts","grain_reserves"]]},
	{"name":"Военное дело","root":"drill","tiers":[["iron","camp"],["siege","standards"],["supply_trains","retinue_schools"]]},
]
const AI_TECH_ORDER := ["husbandry","drill","trade","iron","granaries","camp","law","siege","settlement","standards","grain_reserves","supply_trains","merchant_courts","retinue_schools"]
const ARMORED_UNITS := ["infantry","cavalry","princely"]
const STANCES := {"march":"Поход","forced":"Форсированный марш","ambush":"Засада","raid":"Налёт","camp":"Укреплённый лагерь"}
const EDICTS := {
	"grain": ["Сбор зерна", 2, "%+d еды"],
	"trade": ["Торговый указ", 5, "%+d серебра"],
	"order": ["Охрана порядка", 3, "%+d порядка"],
}

var cities := {}
var fishing_shores := {}
var factions := []
var leaders := []
var recruitment := []
var stances := []
var sieges := {}
var rebellions := {}
var rewarded_provinces := {}
var serial := 0
var journal: Array[String] = []

func _init() -> void:
	for i in Geo.FACTIONS.size():
		factions.append({"silver":500,"tax":1,"tech":[],"research":{},"edicts":{},"influence":60,"loyalty":65,"rebel":false})
		recruitment.append([])
	for i in Geo.ARMIES.size():
		var army: Dictionary = Geo.ARMIES[i]
		leaders.append({"id":army.id,"name":army.name,"portrait":army.portrait,"xp":0,"skill":"","tradition":"","heir":army.get("heir",HERO_NAMES[i+8]),"age":35,"generation":0,"ancestors":[],"trait":"","retinue":""})
		stances.append("march")
	for id in Geo.CITIES:
		var initial_owner: int = Geo.STARTING_OWNERS[id]
		var buildings := {"hall":1,"farm":1}
		if Geo.CITIES[id][3]:
			buildings.hall = 2
			buildings.wall = 1
			buildings.barracks = 1
		cities[id] = {"owner":initial_owner,"culture":initial_owner,"assimilation":100,"buildings":buildings,"building_branches":{},"order":50,"queue":{},"damage":{},"slum":0,"rebel":false,"manpower":starting_manpower(id),"occupation":0,"unintegrated":0,"revolt_turns":0,"relief_turns":0,"relief_cooldown":0,"advisor":"off"}

func owner(city: String) -> int:
	return cities[city].owner

func update_faction_defeats() -> PackedStringArray:
	var notices := PackedStringArray()
	for faction in Geo.FACTIONS.size():
		if faction == Geo.REBELS or factions[faction].get("defeated",false):
			continue
		var oleg_fell: bool = faction == 0 and leaders[0].get("fallen",false)
		if not oleg_fell and cities.values().any(func(town): return town.owner == faction):
			continue
		var has_leader := false
		for index in leaders.size():
			if Geo.army_faction(index) == faction and not leaders[index].get("fallen",false):
				has_leader = true
				break
		if has_leader and not oleg_fell: continue
		factions[faction].defeated = true
		var notice := "Фракция «%s» потерпела поражение" % Geo.FACTIONS[faction].name
		note(notice)
		notices.append(notice)
	return notices

func region_at(point: Vector2, _province: int) -> String:
	return Geo.region_at(point)

func owns_province(faction: int, province: int) -> bool:
	for id in Geo.CITIES:
		if Geo.CITIES[id][1] == province and (owner(id) != faction or cities[id].rebel):
			return false
	return true

func edict(faction: int, province: int, key: String) -> bool:
	if not EDICTS.has(key) or not owns_province(faction,province) or factions[faction].edicts.get(province) == key:
		return false
	factions[faction].edicts[province] = key
	return true

func building_slots(id: String) -> int:
	return HALL_SLOTS[clampi(cities[id].buildings.get("hall",1),1,HALL_SLOTS.size())-1]

static func max_building_level(key: String) -> int:
	if SPECIAL_BUILDINGS.has(key): return 1
	return BUILDING_UPGRADES[key].size()+1

static func local_special_building(id: String) -> String:
	var resource: String = RESOURCES[id]
	for key: String in SPECIAL_BUILDINGS:
		if SPECIAL_BUILDINGS[key][0] == resource: return key
	return ""

static func building_name(key: String, level: int, branch := 0) -> String:
	if key == "farm" and level == 1 and branch == HUNTING_BRANCH: return "Изба охотника"
	if level <= 1: return BUILDINGS[key][0]
	if key == "hall" and level == 4: return "Великий княжеский двор"
	var names: Array = BUILDING_UPGRADES[key][level-2]
	return names[branch]

func building_branch(id: String, key: String) -> int:
	return cities[id].building_branches.get(key,0)

func upgrade_branches(id: String, key: String, include_locked := false) -> Array[int]:
	var town: Dictionary = cities[id]
	var level: int = town.buildings.get(key,0)
	if key == "farm":
		var can_hunt: bool = include_locked or RESOURCES.get(id) == "Меха"
		if level == 0:
			return [0,HUNTING_BRANCH] if can_hunt else [0]
		if (level == 1 and building_branch(id,key) == 0) or (level == 2 and not town.building_branches.has(key)):
			return [0,FISHING_BRANCH,HUNTING_BRANCH] if can_hunt else [0,FISHING_BRANCH]
	return [building_branch(id,key)]

func building_level(id: String, key: String) -> int:
	var town: Dictionary = cities[id]
	return 0 if town.damage.has(key) else town.buildings.get(key,0)

func build_cost(id: String, key: String) -> int:
	var level: int = cities[id].buildings.get(key,0)
	var cost: float = BUILDINGS[key][1] * (level+1)
	if id not in Geo.TRADE_CITIES and key in MILITARY_BUILDINGS: cost *= .8
	if building_level(id,"timber_yard") > 0: cost *= .9
	if key == "wall" and level > 0 and building_level(id,"stone_yard") > 0: cost *= .75
	return roundi(cost)

func build_turns(id: String, key: String) -> int:
	return BUILDINGS[key][2] + cities[id].buildings.get(key,0)

func build_issue(faction: int, id: String, key: String, action := "build", branch := -1) -> String:
	var issues := build_issues(faction,id,key,action,branch)
	return "" if issues.is_empty() else issues[0]

func build_issues(faction: int, id: String, key: String, action := "build", branch := -1) -> PackedStringArray:
	var town: Dictionary = cities[id]
	if town.owner != faction or town.rebel: return PackedStringArray(["Город должен быть под вашим управлением."])
	if not BUILDINGS.has(key): return PackedStringArray(["Неизвестная постройка."])
	var issues := PackedStringArray()
	var occupation := occupation_issue(id)
	if not occupation.is_empty(): issues.append(occupation)
	if sieges.has(id): issues.append("Строительство приостановлено из-за осады.")
	if not town.queue.is_empty():
		var queued := building_name(town.queue.key,town.queue.level,town.queue.get("branch",0))
		issues.append("Очередь занята: «%s», осталось %d ход." % [queued,town.queue.turns])
	var level: int = town.buildings.get(key,0)
	if action == "repair":
		if not town.damage.has(key): issues.append("Ремонт не требуется.")
		elif factions[faction].silver < REPAIR_COST:
			issues.append("Не хватает %d серебра на ремонт." % (REPAIR_COST-factions[faction].silver))
		return issues
	if action == "demolish":
		if key == "hall" or level == 0: issues.append("Эту постройку нельзя снести.")
		return issues
	if action != "build":
		issues.append("Неизвестное действие.")
		return issues
	if level >= max_building_level(key):
		issues.append("Достигнут высший уровень.")
		return issues
	if town.damage.has(key): issues.append("Сначала отремонтируйте постройку.")
	var target_branch := building_branch(id,key) if branch < 0 else branch
	if target_branch not in upgrade_branches(id,key,true):
		issues.append("Это направление недоступно для выбранной ветки.")
		return issues
	if key == "farm" and target_branch == HUNTING_BRANCH and target_branch not in upgrade_branches(id,key):
		issues.append("Охотничий промысел доступен в поселениях с ресурсом «Меха».")
	if key == "farm" and target_branch == FISHING_BRANCH and not fishing_shores.has(id):
		issues.append("Для рыболовства нужна река или озеро поблизости.")
	if key != "hall" and level >= 1 and level+1 > building_level(id,"hall"):
		issues.append("Нужен действующий «%s» (%s)." % [building_name("hall",level+1),LEVEL_NAMES[level]])
	if level == 0 and town.buildings.size() >= building_slots(id):
		issues.append("Заняты все места (%d из %d). Улучшите двор или освободите участок." % [town.buildings.size(),building_slots(id)])
	if key == "warehouse" and building_level(id,"market") == 0: issues.append("Нужен действующий торг.")
	if SPECIAL_BUILDINGS.has(key):
		var requirements: Array = SPECIAL_BUILDINGS[key]
		if RESOURCES[id] != requirements[0]:
			issues.append("Нужен местный ресурс «%s»." % requirements[0])
		if building_level(id,"hall") < 2:
			issues.append("Нужен действующий «%s» (II)." % building_name("hall",2))
		if building_level(id,requirements[1]) == 0:
			issues.append("Нужна действующая постройка «%s»." % building_name(requirements[1],1))
	var knowledge := ""
	if key == "forge" and level >= 1:
		knowledge = "iron"
	elif level == 2 and key != "hall":
		knowledge = "drill" if key in MILITARY_BUILDINGS else "husbandry"
	if not knowledge.is_empty() and knowledge not in factions[faction].tech:
		issues.append("Нужно изучить «%s»." % TECH[knowledge].name)
	var shortage: int = build_cost(id,key)-factions[faction].silver
	if shortage > 0: issues.append("Не хватает %d серебра." % shortage)
	return issues

func build(faction: int, id: String, key: String, action := "build", branch := -1) -> bool:
	if branch < 0 and BUILDINGS.has(key):
		branch = building_branch(id,key)
	if not build_issue(faction,id,key,action,branch).is_empty():
		return false
	var town: Dictionary = cities[id]
	if action == "repair":
		factions[faction].silver -= REPAIR_COST
		town.damage.erase(key)
		return true
	if action == "demolish":
		town.buildings.erase(key)
		town.damage.erase(key)
		town.building_branches.erase(key)
		return true
	var level: int = town.buildings.get(key,0)
	var cost := build_cost(id,key)
	var turns := build_turns(id,key)
	factions[faction].silver -= cost
	town.queue = {"key":key,"level":level+1,"branch":branch,"turns":turns,"paid":cost}
	return true

func available_construction(id: String) -> String:
	var town: Dictionary = cities[id]
	if town.owner != 0 or town.rebel or not town.queue.is_empty(): return ""
	for existing in [false,true]:
		for key in BUILDINGS:
			if town.buildings.has(key) != existing: continue
			for branch in upgrade_branches(id,key):
				if build_issue(0,id,key,"build",branch).is_empty(): return key
	return ""

func cancel_build(id: String) -> void:
	var town: Dictionary = cities[id]
	if not town.queue.is_empty():
		factions[town.owner].silver += town.queue.paid
		town.queue = {}

func recruit_cost(city: String, kind: String) -> int:
	var cost: int = UNITS[kind][2]
	if kind == "archer": cost -= 8*maxi(0,building_level(city,"range")-1)
	if kind in ["cavalry","light_cavalry"]: cost -= 10*maxi(0,building_level(city,"stables")-1)
	if kind in ["infantry","cavalry"] and building_level(city,"bloomery") > 0: cost -= 8
	return cost

func hero_cost(city: String) -> int:
	return recruit_cost(city,"cavalry")+HERO_PREMIUM

func hero_hire_issue(city: String, faction := 0) -> String:
	if not cities.has(city) or owner(city)!=faction or cities[city].rebel:
		return "Воеводу можно нанять в своём городе."
	var occupation := occupation_issue(city)
	if not occupation.is_empty(): return occupation
	if sieges.has(city): return "Наём приостановлен из-за осады."
	if factions[faction].silver < hero_cost(city): return "Не хватает серебра."
	if province_manpower(faction,Geo.CITIES[city][1]) < UNITS.princely[1]:
		return "Нужно %d доступного населения в провинции." % UNITS.princely[1]
	return ""

func hire_hero(city: String) -> Dictionary:
	if not hero_hire_issue(city).is_empty(): return {}
	if not spend_manpower(0,Geo.CITIES[city][1],UNITS.princely[1]): return {}
	factions[0].silver -= hero_cost(city)
	serial += 1
	var family := "hero_%d" % serial
	var number := leaders.size()-Geo.ARMIES.size()
	var name := available_leader_name(number)
	var leader := new_leader(family,name,"hired_leader_%d" % (number%6),available_leader_name(number+8,name),0,[])
	leaders.append(leader)
	stances.append("march")
	note("%s: нанят воевода %s" % [Geo.CITIES[city][0],name])
	return leader

func available_leader_name(offset: int, excluded := "") -> String:
	for i in HERO_NAMES.size():
		var candidate: String = HERO_NAMES[(offset+i)%HERO_NAMES.size()]
		if candidate != excluded and not leaders.any(func(leader): return candidate in [leader.name,leader.heir]):
			return candidate
	return HERO_NAMES[offset%HERO_NAMES.size()]

func new_leader(id: String, name: String, portrait: String, heir: String, generation: int, ancestors: Array) -> Dictionary:
	return {"id":id,"family_id":id,"name":name,"portrait":portrait,"xp":0,"skill":"","tradition":"",
		"heir":heir,"age":27,"generation":generation,"ancestors":ancestors,"trait":"","retinue":""}

func leader_portrait(index: int) -> String:
	return leaders[index].get("portrait",Geo.army_portrait(index))

func set_advisor(id: String, strategy: String) -> bool:
	if owner(id) != 0 or cities[id].rebel or not ADVISOR_STRATEGIES.has(strategy):
		return false
	cities[id].advisor = strategy
	return true

func run_advisors() -> void:
	for id: String in cities:
		var town: Dictionary = cities[id]
		var strategy: String = town.get("advisor","off")
		if town.owner != 0 or town.rebel or not ADVISOR_PRIORITIES.has(strategy) or not town.queue.is_empty():
			continue
		var priority: Array = ADVISOR_PRIORITIES[strategy]
		for key: String in priority:
			if town.damage.has(key) and build(0,id,key,"repair"):
				break
			if build(0,id,key):
				break

func recruit_duration(city: String, kind: String) -> int:
	if kind == "cavalry" and building_level(city,"stables") >= 2:
		return 1
	return UNITS[kind][4]

static func local_mercenary(city: String) -> String:
	if not Geo.CITIES.has(city):
		return ""
	for kind in MERCENARY_REGIONS:
		if Geo.CITIES[city][1] in MERCENARY_REGIONS[kind]:
			return kind
	return ""

static func starting_manpower(city: String) -> int:
	return 50 if Geo.CITIES[city][3] else 35

func manpower_limit(city: String) -> int:
	return (120 if Geo.CITIES[city][3] else 90) + 30 * maxi(0,building_level(city,"hall")-1) + 10 * building_level(city,"farm")

func manpower_growth(city: String, food: int) -> int:
	if cities[city].rebel or sieges.has(city) or cities[city].get("occupation",0) > 0:
		return 0
	var growth := 12
	for key in RECRUIT_GROWTH:
		growth += RECRUIT_GROWTH[key] * building_level(city,key)
	growth += tech_bonus(owner(city),"settlement")
	if food < 0 or cities[city].order < UNREST_ORDER:
		growth = maxi(1,growth/2)
	var space: int = maxi(0,manpower_limit(city)-cities[city].manpower)
	return mini(growth,space)

func pending_recruits(faction: int, garrison_city := "") -> Array:
	return recruitment[faction].filter(func(item):
		return not item.get("garrison",false) if garrison_city.is_empty() else item.get("garrison",false) and item.city == garrison_city)

func recruit_issue(faction: int, city: String, kind: String, roster: Array, garrison := false) -> String:
	for requirement in recruit_requirements(faction,city,kind,roster,garrison):
		if not requirement.issue.is_empty(): return requirement.issue
	return ""

func recruit_requirements(faction: int, city: String, kind: String, roster: Array, garrison := false) -> Array[Dictionary]:
	if kind == "princely": return [{"label":"","issue":"Отряд входит только в личную дружину воеводы."}]
	if not UNITS.has(kind) or not cities.has(city):
		return [{"label":"","issue":"Нет подходящего места для найма."}]
	var checks: Array[Dictionary] = []
	var town: Dictionary = cities[city]
	var occupation := occupation_issue(city)
	if town.owner == faction and not occupation.is_empty():
		checks.append({"label":"","issue":occupation})
	var local_recruitment := garrison or not MERCENARY_REGIONS.has(kind)
	if local_recruitment and (town.owner != faction or town.rebel):
		checks.append({"label":"","issue":"Набор доступен в своём регионе."})
	if local_recruitment and sieges.has(city):
		checks.append({"label":"","issue":"Набор приостановлен из-за осады."})
	var slots := maxi(0,LIMIT-roster.size()-pending_recruits(faction,city if garrison else "").size())
	checks.append({"label":"Свободных мест: %d" % slots,
		"issue":"" if slots>0 else ("Гарнизон заполнен." if garrison else "В дружине нет места.")})
	if MERCENARY_REGIONS.has(kind):
		var turns: int = cities[city].get("mercenary",0)
		if local_mercenary(city) != kind:
			checks.append({"label":"","issue":"В этих землях нет таких наёмников."})
		else:
			checks.append({"label":"Местные наёмники готовы к найму",
				"issue":"Новые наёмники появятся через %d ход." % turns if turns>0 else ""})
	else:
		var requirements: Dictionary = RECRUIT_BUILDINGS[kind]
		for building in requirements:
			var name := "%s %s" % [BUILDINGS[building][0],LEVEL_NAMES[requirements[building]-1]]
			var issue := ""
			if building_level(city,building) < requirements[building]:
				issue = "Почините «%s»." % name if town.damage.has(building) else "Нужна постройка «%s»." % name
			checks.append({"label":name,"issue":issue})
		var required: int = UNITS[kind][1]
		var available := province_manpower(faction,Geo.CITIES[city][1])
		checks.append({"label":"Люди: %d нужно, %d доступно" % [required,available],
			"issue":"Не хватает людей: %d нужно, %d доступно." % [required,available] if available<required else ""})
	var price := recruit_cost(city,kind)
	var balance: int = factions[faction].silver
	checks.append({"label":"Серебро: %d нужно, %d в казне" % [price,balance],
		"issue":"Не хватает %d серебра (%d нужно, %d в казне)." % [price-balance,price,balance] if balance<price else ""})
	return checks

func equipment_offer(faction: int, city: String, unit: Dictionary, armor: bool) -> Dictionary:
	var gear := Equipment.levels(unit)
	var level := (gear.y if armor else gear.x) + 1
	var price := (ARMOR_UPGRADE_BASE_COST if armor else WEAPON_UPGRADE_BASE_COST) * level
	var issue := ""
	if owner(city) != faction:
		issue = "Нужен свой город."
	elif cities[city].rebel:
		issue = "Сначала подавите мятеж."
	elif not occupation_issue(city).is_empty():
		issue = occupation_issue(city)
	elif level > Equipment.MAX_LEVEL:
		issue = "Достигнут высший уровень."
	elif level > building_level(city,"forge"):
		issue = "Нужна действующая кузница уровня %d." % level
	elif factions[faction].silver < price:
		issue = "Не хватает серебра."
	return {"level":level,"price":price,"issue":issue}

func improve_equipment(faction: int, city: String, unit: Dictionary, armor: bool) -> bool:
	var offer := equipment_offer(faction,city,unit,armor)
	if not offer.issue.is_empty():
		return false
	factions[faction].silver -= offer.price
	unit["armor_level" if armor else "weapon_level"] = offer.level
	return true

func recruit_experience(faction: int, city: String, kind: String) -> int:
	if MERCENARY_REGIONS.has(kind) or building_level(city,"barracks") == 0:
		return 0
	return Experience.POINTS_PER_STRIPE * (1 + tech_bonus(faction,"retinue_schools"))

func name_squad(unit: Dictionary, city: String) -> void:
	if unit.has("squad_name") or String(unit.id).ends_with("_garrison_militia"):
		return
	var town: Dictionary = cities[city]
	var number: int = int(town.get("last_squad_number",0)) + 1
	town.last_squad_number = number
	var formation := "отряд" if unit.kind == "militia" or unit.title == "Повстанцы" else "полк"
	unit["squad_name"] = "%d-й %s %s" % [number,Geo.CITY_ADJECTIVES[city],formation]

func recruit(faction: int, city: String, kind: String, roster: Array, garrison := false) -> bool:
	if not recruit_issue(faction,city,kind,roster,garrison).is_empty():
		return false
	var def: Array = UNITS[kind]
	var town: Dictionary = cities[city]
	factions[faction].silver -= recruit_cost(city,kind)
	serial += 1
	var mercenary := MERCENARY_REGIONS.has(kind)
	var experience := recruit_experience(faction,city,kind)
	var unit := {"id":"recruit_%d" % serial,"kind":kind,"title":def[0],"count":def[1],"max":def[1],"xp":experience}
	name_squad(unit,city)
	if mercenary:
		roster.append(unit)
		town.mercenary = MERCENARY_RESTOCK
	else:
		spend_manpower(faction,Geo.CITIES[city][1],unit.count)
		if garrison:
			recruitment[faction].append({"unit":unit,"turns":recruit_duration(city,kind),"city":city,"garrison":true})
		else:
			roster.append(unit)
	return true

func finish_legacy_field_recruits(faction: int, roster: Array) -> void:
	for item in pending_recruits(faction):
		if owner(item.city) == faction and not roster.any(func(unit): return unit.id == item.unit.id):
			roster.append(item.unit)
		recruitment[faction].erase(item)

func militia_reserve(city: String, garrison: Array, turn: int) -> int:
	var town: Dictionary = cities[city]
	if town.rebel or town.get("occupation",0) > 0 or town.get("militia_turn",0) == turn:
		return 0
	var slots := LIMIT - garrison.size() - pending_recruits(town.owner,city).size()
	var hall := clampi(town.buildings.get("hall",1),1,HALL_MILITIA_LIMIT.size())
	var already_mustered := 0
	for unit in garrison:
		if String(unit.id).begins_with("muster_"): already_mustered += unit.count
	var remaining := maxi(0,HALL_MILITIA_LIMIT[hall-1]-already_mustered)
	var local := floori(town.manpower*.40)
	return mini(mini(local,remaining),maxi(0,slots)*UNITS.militia[1])

func muster_militia(city: String, garrison: Array, turn: int, limit := HALL_MILITIA_LIMIT[-1]) -> int:
	var town: Dictionary = cities[city]
	var strength: int = UNITS.militia[1]
	var called_up := 0
	var available := mini(militia_reserve(city,garrison,turn),limit)
	while available > 0:
		var count := mini(strength,available)
		serial += 1
		var unit := {"id":"muster_%d" % serial,"kind":"militia","title":"Ополченцы","count":count,"max":count,"xp":0}
		name_squad(unit,city)
		garrison.append(unit)
		available -= count
		called_up += count
	if called_up > 0:
		town.manpower -= called_up
		town.militia_turn = turn
		note("%s: собрано ополчение, %d человек" % [Geo.CITIES[city][0],called_up])
	return called_up

func research_issue(faction: int, key: String) -> String:
	var state: Dictionary = factions[faction]
	if not TECH.has(key): return "Неизвестное исследование."
	if key in state.tech: return "Уже изучено."
	var item: Dictionary = TECH[key]
	if not item.requires.is_empty() and item.requires not in state.tech:
		return "Нужно изучить «%s»." % TECH[item.requires].name
	if not state.research.is_empty(): return "Сейчас изучается другое знание."
	if state.silver < item.cost: return "Не хватает %d серебра." % (item.cost-state.silver)
	return ""

func research_idle(faction: int) -> bool:
	var state: Dictionary = factions[faction]
	return state.research.is_empty() and state.tech.size() < TECH.size()

func research_turns_remaining(faction: int) -> int:
	var state: Dictionary = factions[faction]
	var active_key: String = state.research.get("key","")
	var remaining := 0
	for key in TECH:
		if key in state.tech: continue
		remaining += state.research.turns if key == active_key else TECH[key].turns
	return remaining

func research(faction: int, key: String) -> bool:
	if not research_issue(faction,key).is_empty(): return false
	var state: Dictionary = factions[faction]
	var item: Dictionary = TECH[key]
	state.silver -= item.cost
	state.research = {"key":key,"turns":item.turns}
	return true

func tech_bonus(faction: int, key: String) -> int:
	return TECH[key].bonus if key in factions[faction].tech else 0

func battle_research(faction: int) -> Dictionary:
	return {
		"morale":tech_bonus(faction,"drill")+tech_bonus(faction,"standards"),
		"armor":tech_bonus(faction,"iron")*.01,
		"armored_units":ARMORED_UNITS,
		"stamina":tech_bonus(faction,"camp")*.01,
	}

func finances(faction: int, roster: Array) -> Dictionary:
	var wealth := 0
	var food := 0
	var troop_cost := Vector2.ZERO
	var building_upkeep_silver := 0
	var food_used := 0
	var tax: int = factions[faction].tax
	var regions := 0
	for id in cities:
		var town: Dictionary = cities[id]
		if town.owner != faction or town.rebel: continue
		regions += 1
		var stats := town_yield(id)
		wealth += stats.silver
		food += stats.food_produced
		food_used += stats.food_used
		building_upkeep_silver += stats.silver_upkeep
	for unit in roster:
		troop_cost += unit_upkeep(unit)
	var upkeep := ceili(troop_cost.x)
	food_used += ceili(troop_cost.y)
	var net := roundi(wealth*[0.7,1.0,1.3][tax])-upkeep-building_upkeep_silver-maxi(0,regions-6)*2
	return {"wealth":wealth,"food":food-food_used,"food_produced":food,"food_used":food_used,"upkeep":upkeep,"building_upkeep":building_upkeep_silver,"net":net}

func has_fish_trade(id: String) -> bool:
	return building_level(id,"farm") >= 2 and building_branch(id,"farm") == FISHING_BRANCH

func trade_goods_text(id: String) -> String:
	var goods: String = RESOURCES[id]
	return goods+", рыба" if has_fish_trade(id) else goods

func local_trade_bonus(id: String) -> Vector2i:
	var bonus: Vector2i = TRADE_GOODS[RESOURCES[id]]
	if building_level(id,"fur_house") > 0: bonus.x += 5
	return bonus+Vector2i(2,0) if has_fish_trade(id) else bonus

static func building_upkeep(key: String, level: int) -> Vector3i:
	var per_level: Vector3i = BUILDING_UPKEEP.get(key,Vector3i.ZERO)
	var costs := per_level * level
	if key == "wall": costs.x = 2 * maxi(0,level-1)
	return costs

func building_yield(id: String, key: String, level: int, branch := -1) -> Vector3i:
	var def: Array = BUILDINGS[key]
	var yield_per_level := Vector3i(def[3],def[4],def[5])
	if key == "market":
		var bonus := local_trade_bonus(id)
		yield_per_level += Vector3i(bonus.x,bonus.y,0)
		yield_per_level.x += tech_bonus(owner(id),"merchant_courts")
	if key == "warehouse":
		yield_per_level.y += tech_bonus(owner(id),"grain_reserves")
	if id in Geo.TRADE_CITIES:
		if key == "market": yield_per_level += Vector3i(6,2,0)
		if key == "warehouse": yield_per_level += Vector3i(2,3,0)
	var result := yield_per_level * level
	if key == "farm":
		result.y += tech_bonus(owner(id),"granaries") * level
		var form := building_branch(id,key) if branch < 0 else branch
		if form == FISHING_BRANCH: result += Vector3i(-5,8,0)*maxi(0,level-1)
		if form == HUNTING_BRANCH: result += Vector3i(10,-4,0)*level
	return result

func town_yield(id: String) -> Dictionary:
	var town: Dictionary = cities[id]
	var silver := 7
	var food_produced := 1
	var food_used := 0
	var silver_upkeep := 0
	var order_sources := {}
	for key in town.buildings:
		if town.damage.has(key): continue
		if key == "warehouse" and building_level(id,"market") == 0: continue
		var contribution := building_yield(id,key,town.buildings[key])
		var costs := building_upkeep(key,town.buildings[key])
		silver += contribution.x
		silver_upkeep += costs.x
		food_produced += contribution.y
		food_used += costs.y
		var building_order := contribution.z-costs.z
		if building_order != 0:
			var source: String = "Беспорядки от торга" if key == "market" else BUILDINGS[key][0]
			order_sources[source] = building_order
	var faction: Dictionary = factions[town.owner]
	var p: int = Geo.CITIES[id][1]
	match faction.edicts.get(p,""):
		"grain": food_produced += EDICTS.grain[1]
		"trade": silver += EDICTS.trade[1]
		"order": order_sources["Охрана порядка"] = EDICTS.order[1]
	food_produced += tech_bonus(town.owner,"husbandry")
	silver += tech_bonus(town.owner,"trade")
	var law := tech_bonus(town.owner,"law")
	if law != 0: order_sources["Закон"] = law
	if town.slum >= 3: order_sources["Трущобы"] = -2
	if rebellions.has(id) or town.get("occupation",0) > 0:
		silver = roundi(silver*.5)
	elif not town.rebel and town.order <= UNREST_ORDER:
		silver = roundi(silver*.75)
	var order := 0
	for value: int in order_sources.values(): order += value
	return {"silver":silver,"silver_upkeep":silver_upkeep,"food":food_produced-food_used,"food_produced":food_produced,"food_used":food_used,"order":order,"order_sources":order_sources}

func order_forecast(id: String, provincial_food: int, armies: Array, garrisons: Dictionary, building_order_change := 0, include_relief := true) -> Dictionary:
	var town: Dictionary = cities[id]
	var reasons: Dictionary = town_yield(id).order_sources
	if building_order_change != 0: reasons["Изменение от новой постройки"] = building_order_change
	var tax: int = factions[town.owner].tax
	if tax != 0: reasons["Подати"] = -2*tax
	if town.culture != town.owner: reasons["Чужая культура"] = -3
	if provincial_food >= 0:
		reasons["Снабжение провинции"] = 2
	else:
		reasons["Нехватка еды в провинции"] = -6
	var guard := garrison_order(id,armies,garrisons)
	if guard > 0: reasons["Гарнизон и дружины в городе"] = guard
	if town.get("occupation",0) > 0: reasons["Восстановление города"] = 8
	if include_relief and town.relief_turns > 0: reasons["Раздача припасов"] = RELIEF_ORDER
	var projected: int = town.order
	for value: int in reasons.values(): projected += value
	var next := clampi(projected,-100,100)
	var limit_adjustment := next-projected
	if limit_adjustment != 0: reasons["Предел порядка"] = limit_adjustment
	var turns := 0
	if next <= REVOLT_ORDER:
		turns = REVOLT_TURNS if town.revolt_turns == 0 else town.revolt_turns-1
	var revolt: bool = next <= REVOLT_ORDER and turns == 0
	if revolt and next > -100:
		reasons["Мятеж"] = -100-next
		next = -100
	var band := next <= REBEL_BAND_ORDER or (rebellions.has(id) and next < REBEL_DISPERSAL_ORDER)
	return {"next":next,"reasons":reasons,"revolt_turns":turns,"revolt":revolt,"band":band}

func ai_market_viable(id: String, food: int, armies: Array, garrisons: Dictionary) -> bool:
	var level := building_level(id,"market")
	var yield_change := building_yield(id,"market",level+1)-building_yield(id,"market",level)
	var cost_change := building_upkeep("market",level+1)-building_upkeep("market",level)
	# The relief bonus expires while the market is under construction.
	var forecast := order_forecast(id,food+yield_change.y-cost_change.y,armies,garrisons,yield_change.z-cost_change.z,false)
	return forecast.next > UNREST_ORDER and forecast.next >= cities[id].order

func ai_shrine_viable(id: String, food: int) -> bool:
	var remaining := food-queued_building_upkeep(owner(id),Geo.CITIES[id][1],"shrine").y
	var level := building_level(id,"shrine")
	return remaining >= building_upkeep("shrine",level+1).y-building_upkeep("shrine",level).y

func ai_wall_upgrade_viable(id: String, net_income: int) -> bool:
	var level := building_level(id,"wall")
	if level == 0 or level >= max_building_level("wall"): return false
	var remaining := net_income-queued_building_upkeep(owner(id),-1,"wall").x
	return remaining >= building_upkeep("wall",level+1).x-building_upkeep("wall",level).x

func queued_building_upkeep(faction: int, province := -1, building := "") -> Vector3i:
	var costs := Vector3i.ZERO
	for city in cities:
		var town: Dictionary = cities[city]
		if town.owner != faction or town.rebel: continue
		if province >= 0 and Geo.CITIES[city][1] != province: continue
		var queue: Dictionary = town.queue
		if queue.is_empty() or (not building.is_empty() and queue.key != building): continue
		var key: String = queue.key
		costs += building_upkeep(key,queue.level)-building_upkeep(key,building_level(city,key))
	return costs

func recruitment_upkeep_budget(faction: int, province: int, net_income: int, food: int) -> Vector2i:
	var silver := net_income-queued_building_upkeep(faction).x
	var provisions := food-queued_building_upkeep(faction,province).y
	for item in recruitment[faction]:
		if not item.get("garrison",false) or owner(item.city) != faction or cities[item.city].rebel: continue
		var upkeep := unit_upkeep(item.unit)
		silver -= ceili(upkeep.x)
		if Geo.CITIES[item.city][1] == province: provisions -= ceili(upkeep.y)
	return Vector2i(silver,provisions)

static func unit_upkeep(unit: Dictionary) -> Vector2:
	var kind: String = unit.kind
	var strength := float(unit.count) / int(UNITS[kind][1])
	return Vector2(UNITS[kind][3],UNIT_FOOD[kind]) * strength

static func unit_fits_upkeep(kind: String, budget: Vector2i) -> bool:
	return budget.x >= int(UNITS[kind][3]) and budget.y >= int(UNIT_FOOD[kind])

func relief_issue(faction: int, id: String) -> String:
	var town: Dictionary = cities[id]
	if town.owner != faction or town.rebel: return "Город должен быть под вашим управлением."
	if town.relief_cooldown > 0: return "Повторная раздача через %d ход." % town.relief_cooldown
	if factions[faction].silver < RELIEF_COST: return "Недостаточно серебра."
	return ""

func distribute_relief(faction: int, id: String) -> bool:
	if not relief_issue(faction,id).is_empty(): return false
	factions[faction].silver -= RELIEF_COST
	cities[id].relief_turns = RELIEF_TURNS
	cities[id].relief_cooldown = RELIEF_COOLDOWN
	note("%s: начата раздача припасов." % Geo.CITIES[id][0])
	return true

func prepare_ai_order(faction: int, armies: Array, turn: int, garrisons: Dictionary, detached_units: Array = []) -> bool:
	if faction == 0 or faction == Geo.REBELS: return false
	var state: Dictionary = factions[faction]
	var candidates: Array[Dictionary] = []
	var lower_tax := false
	var stable := true
	var prioritize_order := false
	for id in cities:
		var town: Dictionary = cities[id]
		if town.owner != faction or town.rebel: continue
		var food: int = province_account(faction,Geo.CITIES[id][1],armies,garrisons).food
		var forecast := order_forecast(id,food,armies,garrisons)
		if forecast.revolt or town.revolt_turns > 0: prioritize_order = true
		if town.order < 0 or forecast.next < 2: stable = false
		if forecast.next <= REBEL_BAND_ORDER or (forecast.next <= UNREST_ORDER and forecast.next < town.order):
			lower_tax = true
		if forecast.next <= REBEL_BAND_ORDER:
			candidates.append({"city":id,"order":forecast.next,"imminent":forecast.revolt})
	if lower_tax and state.tax > 0:
		state.tax = 0
		note("%s: подати снижены из-за беспорядков." % Geo.FACTIONS[faction].name)
	elif stable and state.tax == 0:
		state.tax = 1
	if candidates.is_empty(): return prioritize_order
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.imminent if a.imminent != b.imminent else a.order < b.order)
	var troops := detached_units.duplicate()
	for army in armies: troops.append_array(army.roster)
	var net_income: int = finances(faction,troops).net
	for candidate in candidates:
		var id: String = candidate.city
		var province: int = Geo.CITIES[id][1]
		var food: int = province_account(faction,province,armies,garrisons).food
		if order_forecast(id,food,armies,garrisons).next > REBEL_BAND_ORDER: continue
		var budget := recruitment_upkeep_budget(faction,province,net_income,food)
		# Mustered local militia cost provisions, with no silver upkeep.
		if budget.x >= 0 and muster_order_guard(id,budget.y,armies,turn,garrisons):
			prioritize_order = true
			food = province_account(faction,province,armies,garrisons).food
		if order_forecast(id,food,armies,garrisons).next <= REBEL_BAND_ORDER and distribute_relief(faction,id):
			prioritize_order = true
	return prioritize_order

func muster_order_guard(city: String, food: int, armies: Array, turn: int, garrisons: Dictionary) -> bool:
	var garrison: Array = garrisons.get(city,[])
	var strength := order_guard_strength(city,armies,garrisons)
	var useful := GUARD_ORDER_LIMIT*GUARD_ORDER_STEP-strength
	var food_limit: int = maxi(0,food)/int(UNIT_FOOD.militia)*int(UNITS.militia[1])
	var available := mini(militia_reserve(city,garrison,turn),mini(useful,food_limit))
	if available <= 0 or (strength+available)/GUARD_ORDER_STEP <= strength/GUARD_ORDER_STEP:
		return false
	garrisons[city] = garrison
	return muster_militia(city,garrison,turn,available) > 0

func advance(faction: int, armies: Array[Dictionary], turn: int, garrison_units: Array, garrisons: Dictionary) -> void:
	var state: Dictionary = factions[faction]
	var troops := garrison_units.duplicate()
	for entry in armies: troops.append_array(entry.roster)
	var account := finances(faction,troops)
	state.silver = maxi(0,state.silver+account.net)
	var unpaid: bool = state.silver==0 and account.net<0
	var supplies := {}
	for province in Geo.PROVINCES.size():
		supplies[province] = province_account(faction,province,armies,garrisons).food
	for id in cities:
		var town: Dictionary = cities[id]
		if town.owner != faction or town.rebel: continue
		var recovering: bool = town.get("occupation",0) > 0
		var forecast := order_forecast(id,supplies[Geo.CITIES[id][1]],armies,garrisons)
		if recovering: town.occupation -= 1
		town.relief_turns = maxi(0,town.relief_turns-1)
		town.relief_cooldown = maxi(0,town.relief_cooldown-1)
		town.mercenary = maxi(0,town.get("mercenary",0)-1)
		if town.culture != faction:
			town.assimilation += 8+building_level(id,"shrine")*3
			if town.assimilation >= 100: town.culture = faction
		resolve_unrest(id,forecast,garrisons)
		if town.rebel or recovering: continue
		town.slum = town.slum+1 if town.buildings.size()<building_slots(id) and town.queue.is_empty() else 0
		if not town.queue.is_empty() and not sieges.has(id):
			town.queue.turns -= 1
			if town.queue.turns <= 0:
				var key: String = town.queue.key
				var level: int = town.queue.level
				var branch: int = town.queue.get("branch",0)
				town.buildings[key] = level
				if key == "farm" and town.queue.has("branch") and (level >= 2 or branch != 0):
					town.building_branches[key] = branch
				note("%s: %s «%s»" % [Geo.CITIES[id][0],"построено" if level == 1 else "завершена перестройка в",building_name(key,level,branch)])
				town.queue = {}
		if turn%4 == 0 and not sieges.has(id) and not town.damage.is_empty():
			town.damage.erase(town.damage.keys()[0])
		if sieges.has(id): continue
		var growth := manpower_growth(id,supplies[Geo.CITIES[id][1]])
		var space := maxi(0,manpower_limit(id)-town.manpower-growth)
		var integrated := mini(space,mini(town.get("unintegrated",0),maxi(6,ceili(manpower_limit(id)*.15))))
		town.unintegrated = town.get("unintegrated",0)-integrated
		town.manpower = mini(town.manpower + growth + integrated,manpower_limit(id))
	if not state.research.is_empty():
		state.research.turns -= 1
		if state.research.turns <= 0:
			state.tech.append(state.research.key)
			note("%s: изучено «%s»" % [Geo.FACTIONS[faction].name,TECH[state.research.key].name])
			state.research = {}
	for item in recruitment[faction].duplicate():
		if owner(item.city) != faction:
			recruitment[faction].erase(item)
			continue
		if cities[item.city].rebel or sieges.has(item.city) or cities[item.city].get("occupation",0) > 0:
			continue
		item.turns -= 1
		if item.turns <= 0:
			var destination: Array = garrisons.get_or_add(item.city,[])
			destination.append(item.unit)
			recruitment[faction].erase(item)
	for entry in armies:
		advance_army(entry,faction,turn,unpaid,province_account(faction,Geo.CITIES[entry.region][1],armies,garrisons).food)
	state.loyalty = maxi(0,state.loyalty-(1 if state.influence>72 else 0))
	if state.loyalty <= 10 and not state.rebel:
		state.rebel = true
		for id in cities:
			if owner(id) == faction and id != Geo.FACTIONS[faction].capital:
				city_revolt(id,garrisons)
				note("%s: раскол, мятеж в городе %s" % [Geo.FACTIONS[faction].name,Geo.CITIES[id][0]])
				break

func advance_army(entry: Dictionary, faction: int, turn: int, unpaid: bool, food: int) -> void:
	var index: int = entry.index
	var roster: Array = entry.roster
	if roster.is_empty(): return
	var friendly: bool = owner(entry.region) == faction and not cities[entry.region].rebel
	var province: int = Geo.CITIES[entry.region][1]
	var can_replenish := friendly and food > 0
	var leader: Dictionary = leaders[index]
	var replenishment := 0.17 if leader.skill == "Наставник" or stances[index] == "camp" else 0.12
	replenishment += tech_bonus(faction,"supply_trains") * .01
	var losses := 0
	for unit in roster.duplicate():
		if unpaid or food < 0:
			var lost := maxi(1,ceili(unit.count*.06))
			unit.count = maxi(0,unit.count-lost)
			losses += lost
		elif can_replenish:
			replenish_from_reserve(unit,faction,province,replenishment)
		if unit.count == 0: roster.erase(unit)
	if losses > 0 and faction == 0:
		var cause := "нехватка еды и невыплата жалованья" if unpaid and food < 0 else ("нехватка еды" if food < 0 else "невыплата жалованья")
		note("%s, %s: выбыло %d чел. (%s)." % [leader.name,Geo.CITIES[entry.region][0],losses,cause])
	if stances[index] == "raid" and not friendly: factions[faction].silver += 24
	if not roster.is_empty() and turn%4 == 0:
		leader.age += 1
		if leader.age >= 62 and index != 0: succession(index)

static func replenish_unit(unit: Dictionary, fraction: float) -> void:
	var capacity: int = unit.get("max",UNITS[unit.kind][1])
	var strength := mini(capacity,unit.count+maxi(1,ceili(capacity*fraction)))
	unit.count = strength

func succession(index: int) -> void:
	var leader: Dictionary = leaders[index]
	if not leader.has("ancestors"): leader.ancestors = []
	var ancestors: Array = leader.ancestors.duplicate()
	ancestors.append({"id":leader.id,"name":leader.name,"age":leader.age,
		"portrait":leader_portrait(index),"fallen":leader.get("fallen",false)})
	var generation: int = leader.generation+1
	var family: String = Geo.ARMIES[index].id if index < Geo.ARMIES.size() else leader.family_id
	var name: String = available_leader_name(index+generation) if leader.get("fallen",false) else leader.heir
	var portrait_number := (index+generation+1)%6
	if "hired_leader_%d" % portrait_number == leader_portrait(index):
		portrait_number = (portrait_number+1)%6
	var replacement := new_leader("%s_leader_%d" % [family,generation],name,
		"hired_leader_%d" % portrait_number,available_leader_name(index+generation+8,name),generation,ancestors)
	replacement.family_id = family
	leaders[index] = replacement
	note("%s: новый воевода — %s" % [Geo.FACTIONS[Geo.army_faction(index)].name,name])

func award_leader_victory(index: int, city_battle: bool) -> void:
	var leader: Dictionary = leaders[index]
	leader.xp += 100
	leader.trait = "Осадный воевода" if city_battle else "Испытанный полководец"
	if leader.xp >= 200:
		leader.retinue = "Бывалые дружинники"

func patronage(faction: int) -> bool:
	var state: Dictionary = factions[faction]
	if state.silver < 80: return false
	state.silver -= 80
	state.loyalty = mini(100,state.loyalty+20)
	state.influence = maxi(0,state.influence-5)
	return true

func capture(id: String, faction: int, choice: String) -> String:
	var town: Dictionary = cities[id]
	var p: int = Geo.CITIES[id][1]
	if town.owner != faction:
		town.advisor = "off"
		factions[town.owner].edicts.erase(p)
	for queue in recruitment:
		for item in queue.duplicate():
			if item.city == id: queue.erase(item)
	rebellions.erase(id)
	town.unintegrated = roundi((town.manpower+town.get("unintegrated",0))*({"occupy":1.0,"loot":.5,"raze":.2}.get(choice,1.0)))
	town.manpower = 0
	town.occupation = {"occupy":2,"loot":4,"raze":5}.get(choice,2)
	town.revolt_turns = 0
	town.relief_turns = 0
	town.relief_cooldown = 0
	if town.owner != faction:
		town.previous_owner = town.owner
	town.owner = faction
	town.assimilation = 0
	town.rebel = false
	town.order = -25 if choice == "occupy" else -65
	town.queue = {}
	sieges.erase(id)
	if choice != "occupy":
		factions[faction].silver += 180 if choice == "loot" else 0
		for key in town.buildings:
			town.damage[key] = true
		if choice == "raze":
			town.buildings = {"hall":1}
			town.building_branches.clear()
			town.damage = {"hall":true}
	note("Взят город %s" % Geo.CITIES[id][0])
	return reward_province(p) if faction == 0 else ""

func reward_province(province: int) -> String:
	if rewarded_provinces.has(province) or not owns_province(0,province):
		return ""
	rewarded_provinces[province] = true
	factions[0].silver += PROVINCE_UNIFICATION_REWARD
	var message := "Объединение области «%s» · +%d серебра" % [Geo.PROVINCES[province][0],PROVINCE_UNIFICATION_REWARD]
	note(message)
	return message

func note(message: String) -> void:
	journal.push_front(message)
	if journal.size() > 40: journal.pop_back()

func snapshot() -> Dictionary:
	return {"schema":7,"rewarded_provinces":rewarded_provinces,"rebellions":rebellions,"cities":cities,"factions":factions,"leaders":leaders,
		"recruitment":recruitment,"stances":stances,"sieges":sieges,"serial":serial,"journal":journal}

func restore(data: Dictionary) -> Array[String]:
	var defaults: Dictionary = get_script().new().cities
	cities = data.cities.duplicate(true)
	for id in defaults:
		if not cities.has(id): cities[id] = defaults[id]
	for id in cities:
		cities[id].erase("slots")
		cities[id].erase("revolt_cooldown")
		cities[id].get_or_add("building_branches",{})
		cities[id].get_or_add("advisor","off")
		cities[id].get_or_add("manpower",starting_manpower(id))
		for key in ["occupation","unintegrated","revolt_turns","relief_turns","relief_cooldown"]: cities[id].get_or_add(key,0)
		if cities[id].rebel: cities[id].owner = Geo.REBELS
	factions = data.factions
	while factions.size() < Geo.FACTIONS.size():
		factions.append({"silver":0,"tax":1,"tech":[],"research":{},"edicts":{},"influence":0,"loyalty":100,"rebel":false})
	if data.get("schema",0) < 3:
		for faction in factions: faction.edicts = {}
	rebellions = data.get("rebellions",{}).duplicate(true)
	leaders = data.leaders
	for i in leaders.size():
		var leader: Dictionary = leaders[i]
		if not leader.has("portrait"):
			leader.portrait = Geo.army_portrait(i) if i < Geo.ARMIES.size() and leader.generation == 0 else "hired_leader_%d" % posmod(i+leader.generation-Geo.ARMIES.size(),6)
		if leader.heir.begins_with("Наследник рода") or leader.heir.begins_with("Сын воеводы"):
			leader.heir = available_leader_name(i+8+leader.generation)
		if leader.name.begins_with("Наследник рода") or leader.name.begins_with("Сын воеводы"):
			leader.name = available_leader_name(i+leader.generation)
	recruitment = data.recruitment
	while recruitment.size() < Geo.FACTIONS.size(): recruitment.append([])
	stances = data.stances
	sieges = data.sieges
	serial = data.serial
	journal.assign(data.journal)
	rewarded_provinces = data.get("rewarded_provinces",{}).duplicate()
	var rewards: Array[String] = []
	if not data.has("rewarded_provinces"):
		for province in Geo.PROVINCES.size():
			var message := reward_province(province)
			if not message.is_empty():
				rewards.append(message)
	return rewards

# City reserves form a single spendable pool for each owner/province pair.
# Keeping contributions per city makes capture and loss transfer only that city's share.
func province_cities(faction: int, province: int) -> Array:
	return cities.keys().filter(func(id): return Geo.CITIES[id][1] == province and owner(id) == faction and not cities[id].rebel)

func population_available(id: String) -> bool:
	return not cities[id].rebel and cities[id].get("occupation",0) == 0 and not sieges.has(id)

func province_manpower(faction: int, province: int) -> int:
	var total := 0
	for id in province_cities(faction,province):
		if population_available(id): total += cities[id].manpower
	return total

func spend_manpower(faction: int, province: int, amount: int) -> bool:
	if amount < 0 or province_manpower(faction,province) < amount: return false
	var contributors := province_cities(faction,province).filter(population_available)
	# Draw evenly, so recruiting in one town does not empty another town first.
	while amount > 0:
		for id in contributors:
			if cities[id].manpower > 0 and amount > 0:
				cities[id].manpower -= 1
				amount -= 1
	return true

func province_account(faction: int, province: int, armies: Array = [], garrisons: Dictionary = {}) -> Dictionary:
	var result := {"food":0,"food_produced":0,"food_used":0,"manpower":province_manpower(faction,province),"limit":0,"growth":0,"locked":0,"cities":0}
	var troop_food := 0.0
	for id in province_cities(faction,province):
		result.cities += 1
		result.limit += manpower_limit(id)
		result.locked += cities[id].get("unintegrated",0)
		if not population_available(id): result.locked += cities[id].manpower
		if not sieges.has(id):
			var stats := town_yield(id)
			result.food_produced += stats.food_produced
			result.food_used += stats.food_used
		for unit in garrisons.get(id,[]):
			troop_food += unit_upkeep(unit).y
	for army in armies:
		if cities.has(army.region) and Geo.CITIES[army.region][1] == province:
			for unit in army.roster:
				troop_food += unit_upkeep(unit).y
	result.food_used += ceili(troop_food)
	result.food = result.food_produced-result.food_used
	for id in province_cities(faction,province):
		result.growth += manpower_growth(id,result.food)
	return result

func occupation_issue(id: String) -> String:
	var turns: int = cities[id].get("occupation",0)
	return "Восстановление порядка: ещё %d ход. Стройка и наём приостановлены." % turns if turns > 0 else ""

func replenish_from_province(unit: Dictionary, city: String, fraction: float) -> void:
	if not population_available(city): return
	replenish_from_reserve(unit,owner(city),Geo.CITIES[city][1],fraction)

func replenish_from_reserve(unit: Dictionary, faction: int, province: int, fraction: float) -> void:
	var capacity: int = unit.get("max",UNITS[unit.kind][1])
	if unit.count >= capacity: return
	var amount := mini(capacity-unit.count,maxi(1,ceili(capacity*fraction)))
	amount = mini(amount,province_manpower(faction,province))
	if amount > 0 and spend_manpower(faction,province,amount):
		unit.count += amount

func garrison_order(city: String, armies: Array, garrisons: Dictionary) -> int:
	return mini(GUARD_ORDER_LIMIT,order_guard_strength(city,armies,garrisons)/GUARD_ORDER_STEP)

func order_guard_strength(city: String, armies: Array, garrisons: Dictionary) -> int:
	var strength := 0
	for unit in garrisons.get(city,[]): strength += unit.count
	for army in armies:
		if army.station == city:
			for unit in army.roster: strength += unit.count
	return strength

func rebel_roster(city: String) -> Array:
	var troops := []
	for kind in ["militia","militia","archer"]:
		serial += 1
		var count: int = UNITS[kind][1]
		var unit := {"id":"rebel_%s_%d" % [city,serial],"kind":kind,"title":"Повстанцы","count":count,"max":count,"xp":0}
		name_squad(unit,city)
		troops.append(unit)
	return troops

func resolve_unrest(city: String, forecast: Dictionary, garrisons: Dictionary) -> void:
	var town: Dictionary = cities[city]
	var previous_turns: int = town.revolt_turns
	var name: String = Geo.CITIES[city][0]
	town.order = forecast.next
	town.revolt_turns = forecast.revolt_turns
	if forecast.revolt:
		city_revolt(city,garrisons)
		return
	if forecast.band and not rebellions.has(city):
		rebellions[city] = {"roster":rebel_roster(city)}
		note("%s: появился отряд повстанцев. Доход снижен вдвое." % name)
	elif not forecast.band and rebellions.erase(city):
		note("%s: отряд повстанцев разошёлся." % name)
	if town.revolt_turns > 0:
		note("%s: до мятежа %d ход." % [name,town.revolt_turns])
	elif previous_turns > 0:
		note("%s: мятеж предотвращён." % name)

func defeat_rebel_band(city: String) -> void:
	rebellions.erase(city)
	var town: Dictionary = cities[city]
	town.order = mini(100,town.order+25)
	if town.order > REVOLT_ORDER: town.revolt_turns = 0
	note("%s: отряд повстанцев разгромлен. Порядок +25." % Geo.CITIES[city][0])

func city_revolt(city: String, garrisons: Dictionary) -> void:
	var town: Dictionary = cities[city]
	factions[town.owner].edicts.erase(Geo.CITIES[city][1])
	town.owner = Geo.REBELS
	town.advisor = "off"
	town.rebel = true
	town.order = -100
	town.revolt_turns = 0
	town.relief_turns = 0
	town.relief_cooldown = 0
	town.queue = {}
	town.occupation = 0
	sieges.erase(city)
	garrisons[city] = rebellions[city].roster if rebellions.has(city) else rebel_roster(city)
	rebellions.erase(city)
	for queue in recruitment:
		for item in queue.duplicate():
			if item.city == city: queue.erase(item)
	note("Восстание: %s перешёл под контроль повстанцев!" % Geo.CITIES[city][0])
