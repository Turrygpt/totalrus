extends Control
const UI=preload("res://campaign_map/ui_theme.gd")
const Chrome=preload("res://campaign_map/ui_chrome.gd")
const Experience=preload("res://scripts/unit_experience.gd")
var world: Node3D
var outcome := "win"
var panel: PanelContainer

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	theme=UI.theme()
	var veil:=ColorRect.new()
	veil.color=Color(0.025,.03,.035,.7)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	panel=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",UI.campaign_frame(24))
	Chrome.decorate(panel,26)
	add_child(panel)
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",12)
	panel.add_child(body)
	var title:=UI.label(body,{"win":"Победа","loss":"Поражение","draw":"Ничья","retreat":"Отступление"}[outcome],48,UI.GOLD,true)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var caption:=UI.label(body,world.campaign_request.get("title","Итоги сражения"),20,UI.BRASS)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var elapsed:=floori(world.battle_time)
	var clock:=UI.label(body,"Длительность: %02d:%02d" % [elapsed/60,elapsed%60],16,UI.BONE)
	clock.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	if world.time_expired:
		var reason := UI.label(body,"Время вышло. Победила обороняющаяся сторона.",19,UI.BRASS)
		reason.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var columns:=HBoxContainer.new()
	columns.add_theme_constant_override("separation",22)
	body.add_child(columns)
	for team in 2:
		var side:=VBoxContainer.new()
		side.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		columns.add_child(side)
		var name: String="Ваше войско" if team==0 else "Противник"
		UI.label(side,name,28,UI.BONE,true)
		var initial:=0
		var remaining:=0
		for group in world.squads:
			if group.team==team:
				initial+=group.unit_count
				remaining+=group.survivor_count()
		UI.label(side,"Вступили в бой: %d\nПотери: %d\nУцелели: %d" % [initial,initial-remaining,remaining],20,UI.BONE)
		var leader: CharacterBody3D=world.campaign_leader if team==0 else world.rival_leader
		UI.label(side,"Полководец погиб" if is_instance_valid(leader) and not leader.alive else ("Полководец жив" if is_instance_valid(leader) else "Без полководца"),17,UI.BRASS)
		var scroll:=ScrollContainer.new()
		scroll.custom_minimum_size=Vector2(360,210)
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		side.add_child(scroll)
		var units:=VBoxContainer.new()
		units.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		scroll.add_child(units)
		for group in world.squads:
			if group.team!=team: continue
			var row:=HBoxContainer.new()
			units.add_child(row)
			var unit:=UI.label(row,group.display_name,16,UI.BONE)
			unit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			unit.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			var survivors: int = group.survivor_count()
			if survivors > 0 and (group.participated or (not world.campaign_request.is_empty() and outcome != "retreat")):
				var winner := (team == 0 and outcome == "win") or (team == 1 and outcome == "loss")
				var points := Experience.after_battle(group.experience_points,winner)
				var gained: float = points - group.starting_experience_points
				var promotion := Experience.rank(points) > Experience.rank(group.starting_experience_points)
				if gained > .001:
					var result := "+%.1f опыта" % gained
					if promotion: result += " · " + Experience.title(Experience.rank(points))
					UI.label(row,result,16,UI.GOLD if promotion else UI.BRASS)
			UI.label(row,"%d / %d" % [survivors,group.unit_count],16,UI.BRASS)
	var button:=Button.new()
	button.text="Вернуться на карту" if not world.campaign_request.is_empty() else "Новое сражение"
	button.custom_minimum_size.y=46
	button.pressed.connect(world.campaign_action_pressed if not world.campaign_request.is_empty() else world.restart_battle)
	body.add_child(button)
	resized.connect(fit)
	fit.call_deferred()

func fit() -> void:
	var factor:=minf(size.x/1920.0,size.y/1080.0)
	panel.scale=Vector2.ONE*factor
	panel.size=Vector2(900,600)
	panel.position=(size-panel.size*factor)*.5
