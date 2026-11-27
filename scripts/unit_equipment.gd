extends RefCounted

const MAX_LEVEL := 3
const WEAPON_BONUS := .06
const ARMOR_BONUS := .05
const WEAPON_NAMES := ["Обычное оружие", "Добротное оружие", "Отборное оружие", "Мастерское оружие"]
const ARMOR_NAMES := ["Обычные доспехи", "Добротные доспехи", "Отборные доспехи", "Мастерские доспехи"]
const MEDAL_NAMES := ["", "Бронзовая метка", "Серебряная метка", "Золотая метка"]

static func levels(unit: Dictionary) -> Vector2i:
	return Vector2i(
		clampi(int(unit.get("weapon_level",0)),0,MAX_LEVEL),
		clampi(int(unit.get("armor_level",0)),0,MAX_LEVEL)
	)

static func weapon_damage(level: int) -> float:
	return 1.0 + level * WEAPON_BONUS

static func armor_reduction(level: int) -> float:
	return level * ARMOR_BONUS

static func title(level: int, armor: bool) -> String:
	return ARMOR_NAMES[level] if armor else WEAPON_NAMES[level]

static func upgrade_description(level: int, armor: bool) -> String:
	var effect := "Урон по телу −%d%%" % roundi(armor_reduction(level)*100.0) if armor else "Урон +%d%%" % roundi((weapon_damage(level)-1.0)*100.0)
	return "%s · %s" % [MEDAL_NAMES[level],effect]

static func description(gear: Vector2i) -> String:
	var weapon := title(gear.x,false)
	var armor := title(gear.y,true)
	if gear.x > 0: weapon += " · " + upgrade_description(gear.x,false)
	if gear.y > 0: armor += " · " + upgrade_description(gear.y,true)
	return weapon + "\n" + armor
