extends "res://scripts/battlefield.gd"
func make_armies() -> void:
	for t in 2:
		var g:=Node3D.new()
		g.set_script(SQUAD)
		g.team=t
		g.unit_count=30 if t==1 and "--unequal" in OS.get_cmdline_user_args() else 60
		g.spawn_center=Vector3(0,0,12 if t==0 else -12)
		g.spawn_heading=0 if t==0 else PI
		g.display_name="BLUE" if t==0 else "RED"
		g.ai_enabled=false
		add_child(g)
		squads.append(g)
		if t==0: squad=g
		else: enemy=g
	for g in squads: g.opponent=enemy if g.team==0 else squad
