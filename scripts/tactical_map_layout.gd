extends Resource

@export var title: String
@export var half_size: Vector2
@export var seed_value: int
@export var profile: int
@export var water_side: int = -1
@export var opening_half_width: float
@export var road: Vector4
@export var shoreline_phase: float
@export var landmark_depth: float
@export var yards: PackedVector2Array
@export var shore_approach: PackedVector2Array
@export var hills: PackedVector3Array

func landscape(season: int) -> Dictionary:
	return {
		"seed": seed_value,
		"profile": profile,
		"season": season,
		"water_side": water_side,
		"opening_half_width": opening_half_width,
		"layout": self,
	}

