extends "res://scripts/cavalry.gd"

func begin_strike() -> void:
	if not has_spear or combat_target.bracing_charge:
		super.begin_strike()
		return
	charge_impact = clampf(motion_speed / attack_run_speed(), 0.0, 1.0)
	start_strike("attack_spear", 1.0)
