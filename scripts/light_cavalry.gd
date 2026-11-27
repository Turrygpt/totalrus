extends "res://scripts/cavalry.gd"

func _ready() -> void:
	has_sidearm = false
	super._ready()
	max_hp = 120.0
	hp = max_hp
	damage_multiplier = .82

func rider_material(source: StandardMaterial3D) -> ShaderMaterial:
	return TroopColors.dye(source, uniform_color(), TroopColors.Fabric.ARCHER, ARCHER_ALBEDO)

func attack_run_speed() -> float:
	return CHARGE.LIGHT_RUN_SPEED

