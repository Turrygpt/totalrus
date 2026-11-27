extends "res://scripts/battlefield.gd"
func make_armies() -> void:
	squad=make_unit(0,Vector3(0,0,15),"КОННИЦА","cavalry")
	enemy=make_unit(1,Vector3(0,0,-8),"КОПЕЙЩИКИ","infantry")
	for g in squads:g.ai_enabled=false;g.opponent=enemy if g.team==0 else squad
