extends RefCounted

const TacticalMapLayout = preload("res://scripts/tactical_map_layout.gd")

enum Profile { MEADOW, WOODLAND, RIDGES, SHORE, SETTLEMENT }
const PLAYABLE_PROFILES := [Profile.MEADOW, Profile.WOODLAND, Profile.RIDGES, Profile.SHORE]
const TITLES := {
	Profile.MEADOW: "Поля и дворы",
	Profile.WOODLAND: "Лесная опушка",
	Profile.RIDGES: "Холмистая гряда",
	Profile.SHORE: "Речной берег",
}
const DEFAULT_SEED := 882
const WATER_HEIGHT := -.5
const FOREST_DENSITY: Array[float] = [.25, .73, .37, .34, .25]
const RELIEF: Array[float] = [9.0, 13.0, 26.0, 12.0, 8.0]
const DRY_SOIL: Array[float] = [.60, .29, .62, .43, .62]
const ROCK_GRADE: Array[float] = [.26, .27, .105, .23, .29]
const MAX_TRACKS := 7
const YARD_COUNT: Array[int] = [2, 1, 1, 1, 3]

var seed_value: int
var profile: Profile
var coast: int
var bounds: Vector2
var opening_half_width: float
var road: Vector4
var heights: PackedFloat32Array
var forest: PackedFloat32Array
var relief := FastNoiseLite.new()
var vegetation := FastNoiseLite.new()
var hills: Array[Vector3] = []
var flank: float
var landmark_depth: float
var shoreline_phase: float
var authored_layout: TacticalMapLayout

func _init(half_size: Vector2, source: Dictionary) -> void:
	bounds = half_size
	authored_layout = source.get("layout")
	opening_half_width = source.get("opening_half_width", 132.0)
	seed_value = int(source.get("seed", DEFAULT_SEED))
	heights = source.get("heights", PackedFloat32Array())
	forest = source.get("forest", PackedFloat32Array())
	coast = clampi(int(source.get("water_side", -1)), -1, 3)
	profile = choose_profile(source)
	var layout := RandomNumberGenerator.new()
	layout.seed = hash([seed_value, profile, "features"])
	if profile == Profile.SHORE and coast < 0:
		coast = 1 if seed_value == DEFAULT_SEED else layout.randi_range(0, 3)
	flank = -1.0 if layout.randf() < .5 else 1.0
	landmark_depth = layout.randf_range(-.16, .16) * bounds.y
	shoreline_phase = layout.randf() * TAU
	var road_random := RandomNumberGenerator.new()
	road_random.seed = hash([seed_value, profile, "routes"])
	var road_side := -flank if profile == Profile.RIDGES else flank
	if coast in [0, 1]:
		road_side = -1.0 if coast == 0 else 1.0
	var setback := .60 if profile == Profile.SHORE else .50
	var road_offset := minf(maxf(opening_half_width + 34.0, bounds.x * setback), bounds.x * .72)
	road = Vector4(road_side * road_offset, road_random.randf_range(12, 24),
		road_random.randf_range(.006, .010), -landmark_depth * .008 + road_random.randf_range(-.5, .5))
	relief.seed = hash([seed_value, "relief"])
	relief.frequency = .007
	relief.fractal_octaves = 3
	vegetation.seed = hash([seed_value, "vegetation"])
	vegetation.frequency = .019
	vegetation.fractal_octaves = 2
	if authored_layout != null:
		road = authored_layout.road
		shoreline_phase = authored_layout.shoreline_phase
		landmark_depth = authored_layout.landmark_depth
		for crest in authored_layout.hills:
			hills.append(crest)
		return
	var hill_random := RandomNumberGenerator.new()
	hill_random.seed = hash([seed_value, profile, "hills"])
	for side in [-1.0, 1.0]:
		for i in 2:
			hills.append(Vector3(side * bounds.x * hill_random.randf_range(.45, .72),
				bounds.y * hill_random.randf_range(-.66, .66), hill_random.randf_range(.55, 1.0)))

func choose_profile(source: Dictionary) -> Profile:
	if source.get("city", false):
		return Profile.SETTLEMENT
	if source.get("profile", -1) in PLAYABLE_PROFILES:
		return int(source.profile) as Profile
	if coast >= 0:
		return Profile.SHORE
	if heights.size() == 289:
		var low := INF
		var high := -INF
		for value in heights:
			low = minf(low, value)
			high = maxf(high, value)
		if high - low >= 15.0:
			return Profile.RIDGES
	if forest.size() == 289:
		var total := 0.0
		for cover in forest:
			total += cover
		if total / forest.size() >= .53:
			return Profile.WOODLAND
	return Profile.MEADOW

func road_x(z: float) -> float:
	return road.x + road.y * sin(z * road.z + road.w)

func sample(data: PackedFloat32Array, point: Vector2, fallback: float) -> float:
	if data.size() != 289:
		return fallback
	var uv := ((point / bounds + Vector2.ONE) * 8.0).clamp(Vector2.ZERO, Vector2.ONE * 15.9999)
	var cell := Vector2i(uv.floor())
	var weight := uv - Vector2(cell)
	var i := cell.y * 17 + cell.x
	return lerpf(lerpf(data[i], data[i + 1], weight.x),
		lerpf(data[i + 17], data[i + 18], weight.x), weight.y)

func elevation(point: Vector2) -> float:
	var base := maxf(1.7, .84 * sample(heights, point, 12.0))
	var clearing := smoothstep(opening_half_width - 6.0, maxf(opening_half_width + 43.0, bounds.x * .57), absf(point.x))
	var micro_relief := .10 if heights.size() == 289 else .29
	var local := relief.get_noise_2dv(point) * RELIEF[profile] * lerpf(micro_relief, 1.0, clearing)
	if profile == Profile.RIDGES:
		var axis := flank * bounds.x * .59 + 28.0 * sin((point.y - landmark_depth) * .008)
		var crest := 1.0 - smoothstep(12.0, bounds.x * .44, absf(point.x - axis))
		var saddle := lerpf(.38, 1.0, smoothstep(18.0, 118.0, absf(point.y - landmark_depth)))
		return base + local + clearing * crest * saddle * RELIEF[profile]
	var hill := 0.0
	for crest in hills:
		var delta := (point - Vector2(crest.x, crest.y)) / Vector2(82.0, 118.0)
		hill = maxf(hill, exp(-delta.length_squared() * 1.9) * crest.z)
	return base + local + hill * clearing * RELIEF[profile]

func height_at(point: Vector2) -> float:
	var value := elevation(point)
	var road_center := road_x(point.y)
	var road_blend := 1.0 - smoothstep(3.0, 12.0, absf(point.x - road_center))
	if road_blend > 0.0:
		value = lerpf(value, elevation(Vector2(road_center, point.y)), road_blend)
	if profile == Profile.SETTLEMENT:
		var center := maxf(1.7, .84 * sample(heights, Vector2.ZERO, 12.0))
		value = lerpf(center, value, smoothstep(28.0, 76.0, absf(point.y)))
	if coast >= 0:
		var distance := shore_distance(point)
		var terrace := smoothstep(-92.0, -29.0, distance)
		var floodplain := 1.45 + relief.get_noise_2dv(point) * .7
		value = lerpf(maxf(value, 1.2), floodplain, terrace)
		value = lerpf(value, -3.5, smoothstep(-16.0, 18.0, distance))
		if profile == Profile.SHORE:
			var opposite_bank := 9.5 + relief.get_noise_2dv(point) * 4.5
			value = lerpf(value, opposite_bank, smoothstep(61.0, 108.0, distance))
	return value

func shore_distance(point: Vector2) -> float:
	var across := point.x if coast < 2 else point.y
	var along := point.y if coast < 2 else point.x
	var edge := bounds.x if coast < 2 else bounds.y
	var outward := across if coast % 2 == 1 else -across
	var meander := 6.5 * sin(along * .017 + shoreline_phase) + 2.5 * sin(along * .044 - shoreline_phase)
	return outward - edge - 24.0 + meander

func surface_weights(point: Vector2, grade: float) -> Color:
	var broad := relief.get_noise_2d(point.x * 3.1 + 196.0, point.y * 3.1 - 307.0)
	var detail := relief.get_noise_2d(point.x * 9.0 - 477.0, point.y * 9.0 + 138.0)
	var dry := smoothstep(-.15, .35, broad + detail * .31) * DRY_SOIL[profile]
	var litter := smoothstep(.25, .68, tree_cover(point) + detail * .09)
	var grade_limit := ROCK_GRADE[profile]
	var exposed := smoothstep(grade_limit, grade_limit + .22, grade + detail * .065)
	var bank := 0.0
	if coast >= 0:
		var shore := shore_distance(point)
		var riparian := 1.0 - smoothstep(91.0, 108.0, shore) if profile == Profile.SHORE else 1.0
		bank = smoothstep(-48.0, -7.0, shore + detail * 6.0) * riparian
	return Color(dry, litter, exposed, bank)

func tree_cover(point: Vector2) -> float:
	var density := FOREST_DENSITY[profile]
	var strategic := sample(forest, point, density)
	var patch := vegetation.get_noise_2dv(point)
	var edge := smoothstep(opening_half_width, opening_half_width + 42.0, absf(point.x))
	var composition := smoothstep(-.35, .40, patch)
	match profile:
		Profile.WOODLAND:
			var treeline := bounds.x * .53 + 27.0 * sin(point.y * .016) + patch * 29.0
			var gap := 1.0 - smoothstep(25.0, 99.0, absf(point.y - landmark_depth))
			var forest_core := smoothstep(treeline - 20.0, treeline + 52.0, absf(point.x))
			composition = lerpf(composition, maxf(composition, .61), forest_core) * forest_core
			composition *= 1.0 - .82 * gap * (1.0 - smoothstep(treeline + 15.0, treeline + 88.0, absf(point.x)))
		Profile.RIDGES:
			composition *= lerpf(1.0, .43, smoothstep(.36, .83, point.x * flank / bounds.x))
		Profile.SHORE:
			var shore := shore_distance(point)
			var near_bank := 1.0 - smoothstep(-112.0, -37.0, shore)
			var far_bank := smoothstep(81.0, 111.0, shore)
			composition = composition * near_bank + far_bank * (.45 + composition * .65)
	var base := lerpf(density, strategic, .75)
	if profile == Profile.SHORE and shore_distance(point) > 80.0:
		edge = 1.0
	return clampf(base * (composition * 1.65 + .12), 0.0, 1.0) * edge

func yard_candidates() -> Array[Vector2]:
	if authored_layout != null:
		var plots: Array[Vector2] = []
		plots.assign(authored_layout.yards)
		return plots
	var random := RandomNumberGenerator.new()
	random.seed = hash([seed_value, profile, "yards"])
	var plots: Array[Vector2] = []
	for i in 8:
		var step := floori((i + 1) * .5) * bounds.y * .16
		var depth := landmark_depth + step * (-1.0 if i % 2 == 0 else 1.0) + random.randf_range(-22, 22)
		if profile == Profile.SETTLEMENT or (profile == Profile.MEADOW and i > 0):
			depth = (90.0 + floori(i * .5) * bounds.y * .16 + random.randf_range(0, 33)) * (-1.0 if i % 2 == 0 else 1.0)
		plots.append(Vector2(road_x(depth) + signf(road.x) * random.randf_range(18, 27), depth))
	return plots

func shore_point(distance_from_edge: float, along: float) -> Vector2:
	var edge := bounds.x if coast < 2 else bounds.y
	var across := (edge + distance_from_edge) * (-1.0 if coast % 2 == 0 else 1.0)
	return Vector2(across, along) if coast < 2 else Vector2(along, across)

func shore_approach() -> PackedVector2Array:
	if authored_layout != null:
		return authored_layout.shore_approach
	if coast < 0 or profile == Profile.SETTLEMENT:
		return PackedVector2Array()
	var along := landmark_depth if coast < 2 else road.x
	var inside := shore_point(-63.0, along)
	var start := Vector2(road_x(inside.y - 35.0), inside.y - 35.0)
	if coast == 2:
		start = Vector2(road_x(inside.y + 35.0), inside.y + 35.0)
	if coast >= 2:
		along += signf(road.x) * 36.0
	var bend := shore_point(-22.0, along + 24.0)
	return PackedVector2Array([start, shore_point(-63.0, along), bend, shore_point(18.0, along + 34.0)])

