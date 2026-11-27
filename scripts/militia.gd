extends "res://scripts/soldier.gd"

func _ready() -> void:
	has_sidearm = false
	super._ready()
	max_hp = rng.randf_range(74.0,86.0)
	hp = max_hp

func crowd_kind() -> String:
	return "militia"

func apply_appearance() -> void:
	apply_archer_tunic()

func keeps_shield_forward() -> bool:
	return has_shield()
