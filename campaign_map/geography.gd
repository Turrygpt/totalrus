extends RefCounted
const MAP_SCALE := 2.0

# Provinces contain at most four settlements; faction ownership is independent.
const REBELS := 7
const PROVINCES := [
	["Новгородская земля", "novgorod", Color("#a8be80")],
	["Полоцкая земля", "polotsk", Color("#d0b37d")],
	["Верхнее Поднепровье", "mogilev", Color("#9eb9bc")],
	["Киевская земля", "kyiv", Color("#cb947d")],
	["Псковская земля", "pskov", Color("#a6b69c")],
	["Смоленская земля", "smolensk", Color("#b1a1bd")],
	["Северская земля", "chernigov", Color("#96adc2")],
]

# Name, province, east/north map position, faction capital.
const CITIES := {
	"novgorod": ["Новгород", 0, Vector2(63, -198), true],
	"russa": ["Старая Русса", 0, Vector2(15, -153), true],
	"kholm": ["Холм", 0, Vector2(78, -104), false],
	"polotsk": ["Полоцк", 1, Vector2(-114, -46), true],
	"vitebsk": ["Витебск", 1, Vector2(-44, -46), false],
	"smolensk": ["Смоленск", 5, Vector2(105, -15), true],
	"orsha": ["Орша", 2, Vector2(17, 32), false],
	"mogilev": ["Могилёв", 2, Vector2(-51, 71), true],
	"lyubech": ["Любеч", 3, Vector2(-45, 132), false],
	"chernigov": ["Чернигов", 6, Vector2(56, 164), true],
	"kyiv": ["Киев", 3, Vector2(-104, 204), true],
	"ladoga": ["Ладога", 0, Vector2(95, -286), false],
	"izborsk": ["Изборск", 4, Vector2(-315, -245), false],
	"pskov": ["Псков", 4, Vector2(-235, -175), false],
	"north_pogost": ["Северный погост", 4, Vector2(-110, -280), false],
	"upper_volok": ["Верхний волок", 5, Vector2(310, -240), false],
	"toropets": ["Торопец", 5, Vector2(280, -68), false],
	"west_pogost": ["Западный погост", 1, Vector2(-310, -50), false],
	"berezina": ["Березинский погост", 2, Vector2(-305, 82), false],
	"desna": ["Деснинский погост", 6, Vector2(310, 75), false],
	"korosten": ["Искоростень", 3, Vector2(-285, 253), false],
	"pereyaslavl": ["Переяславль", 6, Vector2(205, 250), false],
	"sula": ["Посульский погост", 6, Vector2(320, 280), false],
}

const CITY_ADJECTIVES := {
	"novgorod":"Новгородский", "russa":"Старорусский", "kholm":"Холмский",
	"polotsk":"Полоцкий", "vitebsk":"Витебский", "smolensk":"Смоленский",
	"orsha":"Оршанский", "mogilev":"Могилёвский", "lyubech":"Любечский",
	"chernigov":"Черниговский", "kyiv":"Киевский", "ladoga":"Ладожский",
	"izborsk":"Изборский", "pskov":"Псковский", "north_pogost":"Северный",
	"upper_volok":"Верхневолокский", "toropets":"Торопецкий", "west_pogost":"Западный",
	"berezina":"Березинский", "desna":"Деснинский", "korosten":"Искоростенский",
	"pereyaslavl":"Переяславский", "sula":"Посульский",
}

const STARTING_OWNERS := {
	"novgorod": 0,
	"russa": 1, "kholm": 1,
	"polotsk": 2, "vitebsk": 2,
	"smolensk": 3, "orsha": 3,
	"mogilev": 4,
	"lyubech": 5, "chernigov": 5,
	"kyiv": 6,
	"ladoga": 0,
	"izborsk": 1,
	"pskov": 1,
	"north_pogost": 1,
	"upper_volok": 1,
	"toropets": 3,
	"west_pogost": 2,
	"berezina": 4,
	"desna": 5,
	"korosten": 6,
	"pereyaslavl": 5,
	"sula": 5,
}
const TRADE_CITIES := ["novgorod","russa","polotsk","orsha","mogilev","kyiv"]

const FACTIONS := [
	{"name":"Новгородцы","capital":"novgorod","color":Color("#8c373d"),"banner":"novgorod"},
	{"name":"Приильменские общины","capital":"russa","color":Color("#8b6b22"),"banner":"ilmen"},
	{"name":"Полоцкие кривичи","capital":"polotsk","color":Color("#a4542d"),"banner":"polotsk"},
	{"name":"Смоленские кривичи","capital":"smolensk","color":Color("#685181"),"banner":"smolensk"},
	{"name":"Радимичи","capital":"mogilev","color":Color("#694833"),"banner":"radimichi"},
	{"name":"Северяне","capital":"chernigov","color":Color("#365f90"),"banner":"severians"},
	{"name":"Киевляне","capital":"kyiv","color":Color("#3e7351"),"banner":"kyiv"},
	{"name":"Повстанцы","capital":"","color":Color("#783d36"),"banner":"rebels"},
]

const LADOGA_REBEL_APPEARANCE := {"name":"Повстанцы","color":Color("#557d32"),"banner":"ladoga"}

const ROADS := [
	["novgorod", "russa", Vector2(92, -169)],
	["novgorod", "kholm", Vector2(112, -151)],
	["russa", "kholm", Vector2(45, -123)],
	["russa", "polotsk", Vector2(-48, -117)],
	["kholm", "vitebsk", Vector2(36, -79)],
	["kholm", "smolensk", Vector2(113, -62)],
	["polotsk", "vitebsk", Vector2(-76, -73)],
	["vitebsk", "smolensk", Vector2(37, -28)],
	["vitebsk", "orsha", Vector2(-22, -2)],
	["smolensk", "orsha", Vector2(64, 10)],
	["orsha", "mogilev", Vector2(-14, 59)],
	["mogilev", "lyubech", Vector2(-57, 103)],
	["lyubech", "chernigov", Vector2(-1, 147)],
	["lyubech", "kyiv", Vector2(-84, 166)],
	["chernigov", "kyiv", Vector2(-11, 195)],
	["kholm", "orsha", Vector2(71, -64)],
	["polotsk", "mogilev", Vector2(-107, 18)],
	["smolensk", "mogilev", Vector2(37, 48)],
	["mogilev", "chernigov", Vector2(15, 112)],
	["novgorod", "ladoga", Vector2(115, -247)],
	["ladoga", "upper_volok", Vector2(215, -277)],
	["ladoga", "north_pogost", Vector2(-12, -269)],
	["north_pogost", "izborsk", Vector2(-220, -285)],
	["izborsk", "pskov", Vector2(-290, -200)],
	["pskov", "russa", Vector2(-116, -140)],
	["pskov", "west_pogost", Vector2(-283, -113)],
	["west_pogost", "polotsk", Vector2(-219, -67)],
	["upper_volok", "toropets", Vector2(294, -158)],
	["toropets", "smolensk", Vector2(206, -49)],
	["toropets", "desna", Vector2(337, 22)],
	["west_pogost", "berezina", Vector2(-331, 15)],
	["berezina", "mogilev", Vector2(-181, 60)],
	["berezina", "korosten", Vector2(-324, 185)],
	["korosten", "kyiv", Vector2(-198, 238)],
	["desna", "chernigov", Vector2(199, 132)],
	["desna", "sula", Vector2(337, 191)],
	["chernigov", "pereyaslavl", Vector2(135, 223)],
	["pereyaslavl", "sula", Vector2(269, 263)],
	["kyiv", "pereyaslavl", Vector2(55, 274)],
]

const ARMIES := [
	{"id":"oleg","faction":0,"name":"Олег","portrait":"oleg_leader","heir":"Игорь"},
	{"id":"ilmen","faction":1,"name":"Милогост","portrait":"russa_leader"},
	{"id":"polotsk","faction":2,"name":"Велемир","portrait":"polotsk_voivode"},
	{"id":"smolensk","faction":3,"name":"Твердислав","portrait":"smolensk_leader"},
	{"id":"radimichi","faction":4,"name":"Радослав","portrait":"radimichi_leader"},
	{"id":"severians","faction":5,"name":"Бранибор","portrait":"severians_leader"},
	{"id":"askold","faction":6,"name":"Аскольд","portrait":"askold_leader"},
	{"id":"dir","faction":6,"name":"Дир","portrait":"dir_leader","camp_offset":Vector2(0,-24)},
]

const WATER_NAMES := [
	["Волхов",Vector2(53,-221),Vector2(.17,1),false],
	["Западная Двина",Vector2(-70,-59),Vector2(1,-.05),false],
	["Днепр",Vector2(-50,101),Vector2(-1,1),false],
	["Днепр",Vector2(165,-23),Vector2(1,.09),false],
	["Десна",Vector2(105,162),Vector2(1,-.42),false],
	["Припять",Vector2(-180,140),Vector2(1,.05),false],
	["оз. Ильмень",Vector2(27,-179),Vector2.RIGHT,true],
	["Чудское озеро",Vector2(-131,-169),Vector2.RIGHT,true],
	["оз. Селигер",Vector2(151,-112),Vector2.RIGHT,true],
]

static func faction_appearance(faction: int, city := "") -> Dictionary:
	if faction == REBELS and city == "ladoga":
		return LADOGA_REBEL_APPEARANCE
	return FACTIONS[faction]

static func army_faction(index: int) -> int:
	return ARMIES[index].faction if index < ARMIES.size() else 0

static func army_portrait(index: int) -> String:
	return ARMIES[index].portrait if index < ARMIES.size() else "princely"

static func army_home(index: int) -> String:
	return FACTIONS[army_faction(index)].capital

static func army_camp(index: int, city: String) -> Vector2:
	if index < ARMIES.size():
		return camp_position(city)+ARMIES[index].get("camp_offset",Vector2.ZERO)
	var angle := (index-ARMIES.size())*2.4
	return position_of(city)+Vector2.from_angle(angle)*(21.0+fmod(index-ARMIES.size(),3.0)*3.0)

static func position_of(city: String) -> Vector2:
	return CITIES[city][2]*MAP_SCALE

static func province_capital(province: int) -> String:
	return PROVINCES[province][1]

static func is_province_capital(city: String) -> bool:
	return city == province_capital(CITIES[city][1])

static func camp_position(city: String) -> Vector2:
	match city:
		"novgorod":
			return position_of(city)+Vector2(23,8)
		"kyiv", "polotsk":
			return position_of(city)+Vector2(-17,9)
	return position_of(city)+Vector2(13,7)

static func road_points(road: Array) -> PackedVector2Array:
	var a := position_of(road[0])
	var b := position_of(road[1])
	var middle: Vector2 = road[2]*MAP_SCALE
	# A quadratic through the authored bend, rather than a straight connection.
	var control := middle * 2.0 - (a + b) * 0.5
	var points := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		points.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return points

static func region_at(point: Vector2) -> String:
	var closest := "novgorod"
	var distance := INF
	for id in CITIES:
		var candidate := point.distance_squared_to(position_of(id))
		if candidate < distance:
			closest = id
			distance = candidate
	return closest

static func province_center(index: int) -> Vector2:
	var center := Vector2.ZERO
	var count := 0
	for id in CITIES:
		if CITIES[id][1] == index:
			center += position_of(id)
			count += 1
	return center / maxf(1,count)
