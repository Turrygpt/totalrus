extends RefCounted

const Charge = preload("res://scripts/cavalry_charge.gd")

const POINTS_PER_STRIPE := 10
const MAX_RANK := 9
const MAX_POINTS := float(MAX_RANK * POINTS_PER_STRIPE)
const STAT_MULTIPLIER := 1.5
const GAIN_MULTIPLIER := 0.8
const PARTICIPATION_POINTS := 2.0
const VICTORY_POINTS := 3.0
const METALS := ["Бронза", "Серебро", "Золото"]
const COLORS := [Color("c38a5c"), Color("c2c9ca"), Color("ebc675")]
const NUMERALS := ["I", "II", "III"]

static func rank(points: float) -> int:
	return clampi(floori((points + .000001) / POINTS_PER_STRIPE),0,MAX_RANK)

static func stripes(value: int) -> int:
	return posmod(value-1,3)+1 if value > 0 else 0

static func color(value: int) -> Color:
	return COLORS[floori((value-1)/3.0)] if value > 0 else Color.TRANSPARENT

static func title(value: int) -> String:
	if value == 0:
		return ""
	return "%s %s" % [METALS[floori((value-1)/3.0)],NUMERALS[stripes(value)-1]]

static func attack_tempo(value: int) -> float:
	return 1.0 + value * .04 * STAT_MULTIPLIER

static func melee_attack(value: int) -> float:
	return 1.0 + value * .02 * STAT_MULTIPLIER

static func melee_defense(value: int) -> float:
	return value * .02 * STAT_MULTIPLIER

static func projectile_spread(value: int) -> float:
	return 1.0 - value * .04 * STAT_MULTIPLIER

static func charge_impact(value: int) -> float:
	return 1.0 + value * .03 * STAT_MULTIPLIER

static func stamina_cost(value: int) -> float:
	return 1.0 - value * .03 * STAT_MULTIPLIER

static func earn_kills(points: float, kills: float, capacity: int) -> float:
	var credit := kills * POINTS_PER_STRIPE * GAIN_MULTIPLIER / maxi(1,capacity)
	var level := rank(points)
	while credit > 0.0 and level < MAX_RANK:
		var next_threshold := float((level+1) * POINTS_PER_STRIPE)
		var difficulty := 1.0 + .08 * level
		var needed := maxf(0.0,next_threshold-points) * difficulty
		if credit < needed:
			return points + credit / difficulty
		credit -= needed
		points = next_threshold
		level += 1
	return minf(points,MAX_POINTS)

static func after_battle(points: float, victory: bool) -> float:
	var reward := PARTICIPATION_POINTS + (VICTORY_POINTS if victory else 0.0)
	return minf(points + reward * GAIN_MULTIPLIER,MAX_POINTS)

static func description(points: float, unit_kind := "") -> String:
	var level := rank(points)
	var standing := title(level) if level > 0 else "Без лычек"
	if level == MAX_RANK:
		standing += " · высшее звание"
	else:
		standing += " · %.1f / %d очк." % [points,(level+1)*POINTS_PER_STRIPE]
	var hint := "Опыт — %s\nПодготовка атак +%d%% · Мораль +%d\nБлижний бой · урон +%d%% · получаемый урон −%d%%" % [
		standing,roundi((attack_tempo(level)-1.0)*100.0),morale(level),
		roundi((melee_attack(level)-1.0)*100.0),roundi(melee_defense(level)*100.0),
	]
	hint += "\nРасход выносливости от опыта −%d%%" % roundi((1.0-stamina_cost(level))*100.0)
	if unit_kind in ["infantry","archer","khazar"]:
		var projectile := "копий" if unit_kind == "infantry" else "стрел"
		hint += "\nРазброс %s −%d%%" % [projectile,roundi((1.0-projectile_spread(level))*100.0)]
	if unit_kind in Charge.UNIT_KINDS:
		hint += "\nНатиск · урон и отбрасывание +%d%%" % roundi((charge_impact(level)-1.0)*100.0)
	return hint

static func morale(value: int) -> float:
	return value * 2.0 * STAT_MULTIPLIER
