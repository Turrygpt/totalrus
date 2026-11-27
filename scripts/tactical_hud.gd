extends Control

const UI = preload("res://campaign_map/ui_theme.gd")
const MapGenerator = preload("res://scripts/tactical_map_generator.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")
const Card = preload("res://scripts/tactical_unit_card.gd")
const Squad = preload("res://scripts/squad.gd")
const DOCK_HEIGHT := 288.0
const Medallion=preload("res://campaign_map/ui_medallion.gd")

var world: Node3D
var layout: Control
var dock: Control
var enemy_dock: Control
var roster_scroll: ScrollContainer
var cards: Dictionary = {}
var enemy_cards: Dictionary = {}
var name_label: Label
var kind_label: Label
var count_label: Label
var state_label: Label
var trait_label: Label
var command_hint: Label
var camera_hint: Label
var selected_behavior: OptionButton
var army_behavior: OptionButton
var ability_button: Button
var melee_button: Button
var fortify_button: Button
var friendly_count: Label
var enemy_count: Label
var battle_state: Label
var objective_panel: PanelContainer
var friendly_health: ProgressBar
var enemy_health: ProgressBar
var minimap: Control
var portrait: TextureRect
var morale_meter: ProgressBar
var stamina_meter: ProgressBar
var health_meter: ProgressBar
var command_buttons: Array[Button]=[]
var announcement: PanelContainer
var notice_title: Label
var notice_body: Label
var notice_portrait: TextureRect
var notices: Array[Dictionary]=[]
var notice_until := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	layout = Control.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	make_header()
	make_enemy_roster()
	make_dock()
	make_announcements()
	resized.connect(reflow)
	roster_scroll.resized.connect(resize_cards)
	reflow()

func make_map_controls() -> void:
	var controls := HBoxContainer.new()
	controls.position = Vector2(18, 65)
	controls.add_theme_constant_override("separation", 6)
	layout.add_child(controls)

	var profile := OptionButton.new()
	profile.focus_mode = Control.FOCUS_NONE
	for id in MapGenerator.PLAYABLE_PROFILES:
		profile.add_item(MapGenerator.TITLES[id], id)
	profile.select(profile.get_item_index(world.terrain.generator.profile))
	profile.tooltip_text = "Тип местности"
	controls.add_child(profile)

	var seed_input := LineEdit.new()
	seed_input.custom_minimum_size.x = 118
	seed_input.max_length = 10
	seed_input.text = str(world.terrain.generator.seed_value)
	seed_input.tooltip_text = "Номер карты. Один и тот же номер и тип местности дают ту же карту при том же масштабе боя."
	controls.add_child(seed_input)

	var apply := Button.new()
	apply.text = "Создать карту"
	apply.focus_mode = Control.FOCUS_NONE
	apply.tooltip_text = "Начать новый бой на выбранной карте"
	controls.add_child(apply)
	var generate := func() -> void:
		var tree := get_tree()
		tree.set_meta(&"tactical_map_profile", profile.get_selected_id())
		tree.set_meta(&"tactical_map_seed", seed_input.text.to_int())
		tree.reload_current_scene()
	apply.pressed.connect(generate)
	seed_input.text_submitted.connect(func(value: String):
		if value.is_valid_int():
			generate.call()
	)
	seed_input.text_changed.connect(func(value: String):
		apply.disabled = not value.is_valid_int()
	)

	var randomize_seed := Button.new()
	randomize_seed.text = "Случайный номер"
	randomize_seed.focus_mode = Control.FOCUS_NONE
	randomize_seed.pressed.connect(func():
		seed_input.text = str(randi_range(1, 2147483647))
		apply.disabled = false
	)
	controls.add_child(randomize_seed)

func make_header() -> void:
	var field_controls := HBoxContainer.new()
	field_controls.position=Vector2(18,14)
	field_controls.add_theme_constant_override("separation",6)
	layout.add_child(field_controls)
	medallion(field_controls,"menu","Показать / скрыть карточки противника",func(): enemy_dock.visible=not enemy_dock.visible)
	medallion(field_controls,"focus","К выбранному отряду · F",func(): focus_group(world.selected_squad))
	medallion(field_controls,"book","Музыка · F8",world.toggle_battle_music)
	if world.campaign_request.is_empty():
		world.add_battle_size_control(field_controls)
		if world.standalone_layout == null:
			make_map_controls()
		else:
			var title_panel := PanelContainer.new()
			title_panel.position = Vector2(18, 65)
			title_panel.add_theme_stylebox_override("panel", UI.campaign_frame(8))
			layout.add_child(title_panel)
			UI.label(title_panel, world.standalone_layout.title, 23, UI.BONE, true)
	else:
		world.campaign_action=make_button(field_controls,"Отступить",world.campaign_action_pressed)
		world.campaign_action.disabled = not world.campaign_request.get("retreat_allowed",true)
		if world.campaign_action.disabled:
			world.campaign_action.tooltip_text = "При обороне города отступить нельзя." if world.campaign_request.get("defending_city",false) else "Этот воевода уже отступал в текущем ходу."
	var score_panel:=frame(layout,Rect2(0,0,552,69))
	score_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	score_panel.offset_left=-276
	score_panel.offset_right=276
	score_panel.offset_top=12
	score_panel.offset_bottom=90
	var score:=VBoxContainer.new()
	score.add_theme_constant_override("separation",2)
	place(score,score_panel,Rect2(22,11,508,64))
	var sides:=HBoxContainer.new()
	score.add_child(sides)
	friendly_count=UI.label(sides,"",18,UI.BONE)
	friendly_count.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	enemy_count=UI.label(sides,"",18,UI.BONE)
	enemy_count.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var bars:=HBoxContainer.new()
	score.add_child(bars)
	friendly_health=add_health_bar(bars,Color("a8b47a"))
	enemy_health=add_health_bar(bars,Color("ad5547"))
	battle_state=UI.label(score,"",14,UI.BRASS)
	battle_state.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	objective_panel=PanelContainer.new()
	objective_panel.add_theme_stylebox_override("panel",UI.campaign_frame(12))
	Chrome.decorate(objective_panel,14)
	layout.add_child(objective_panel)
	objective_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	objective_panel.offset_left=-292
	objective_panel.offset_right=-18
	objective_panel.offset_top=12
	objective_panel.offset_bottom=77
	var lines:=VBoxContainer.new()
	objective_panel.add_child(lines)
	UI.label(lines,"ЗАДАЧА СРАЖЕНИЯ",12,UI.BRASS)
	UI.label(lines,"Разбить врага до конца времени" if world.attacking_team()==0 else "Удержаться до конца времени",17,UI.BONE,true)

func place(control: Control, parent: Control, rect: Rect2) -> void:
	parent.add_child(control)
	control.position=rect.position
	control.size=rect.size

func frame(parent: Control, rect: Rect2) -> Control:
	var control:=Control.new()
	control.mouse_filter=Control.MOUSE_FILTER_STOP
	place(control,parent,rect)
	var trim:=Chrome.new()
	trim.ornament_depth = 14
	control.add_child(trim)
	trim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	trim.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return control

func medallion(parent: Node, key: String, hint: String, callback: Callable) -> Button:
	var button:=Medallion.new()
	button.key=key
	button.tooltip_text=hint
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

var enemy_deck: HBoxContainer
var friendly_deck: HBoxContainer

func make_enemy_roster() -> void:
	var enemies: Array = world.squads.filter(func(group): return group.team == 1)
	var width := clampf(enemies.size()*82+24,220,944)
	enemy_dock = PanelContainer.new()
	enemy_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	enemy_dock.add_theme_stylebox_override("panel",UI.campaign_frame(10))
	Chrome.decorate(enemy_dock,13)
	layout.add_child(enemy_dock)
	enemy_dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	enemy_dock.offset_left = -width*.5
	enemy_dock.offset_right = width*.5
	enemy_dock.offset_top = 94.0
	enemy_dock.hide()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 105.0
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_force_pass_scroll_events = false
	enemy_dock.add_child(scroll)
	enemy_deck = HBoxContainer.new()
	enemy_deck.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_deck.add_theme_constant_override("separation",5)
	scroll.add_child(enemy_deck)
	for group in enemies:
		add_unit_card(group)

func add_unit_card(group: Node3D) -> void:
	var card := Card.new()
	card.squad = group
	if group.team == 1:
		card.compact = true
		enemy_deck.add_child(card)
		enemy_cards[group] = card
	else:
		card.pressed.connect(func(): world.select_squad(group,Input.is_key_pressed(KEY_SHIFT)))
		card.focus_requested.connect(focus_group.bind(group))
		friendly_deck.add_child(card)
		cards[group] = card
		resize_cards()

func add_health_bar(parent: Node,color: Color) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.custom_minimum_size.y = 4
	meter.show_percentage = false
	meter.max_value = 1.0
	meter.add_theme_stylebox_override("background",UI.box(Color("393d32"),Color.TRANSPARENT,0))
	meter.add_theme_stylebox_override("fill",UI.box(color,Color.TRANSPARENT,0))
	parent.add_child(meter)
	return meter

func make_dock() -> void:
	dock=Control.new()
	dock.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layout.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_top=-DOCK_HEIGHT
	var unit:=frame(dock,Rect2(18,0,252,278))
	name_label=UI.label(unit,"",26,UI.BONE,true)
	name_label.position=Vector2(16,10)
	name_label.size=Vector2(224,29)
	name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	kind_label=UI.label(unit,"",13,UI.BRASS)
	kind_label.position=Vector2(12,37)
	portrait=TextureRect.new()
	portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	place(portrait,unit,Rect2(12,60,95,116))
	var meters:=VBoxContainer.new()
	meters.add_theme_constant_override("separation",4)
	place(meters,unit,Rect2(120,62,118,110))
	for caption in ["Здоровье","Боевой дух","Выносливость"]:
		UI.label(meters,caption,13,UI.BRASS)
		var meter:=add_health_bar(meters,Color("9cac73"))
		meter.custom_minimum_size.y=6
		match caption:
			"Здоровье": health_meter=meter
			"Боевой дух":
				morale_meter = meter
				morale_meter.mouse_filter = Control.MOUSE_FILTER_PASS
				morale_meter.tooltip_text = "Потери, натиск и усталость снижают мораль. Опыт и поддержка дружины помогают держать строй.\nПри %d%% отряд отступает. После передышки при %d%% он снова выполняет приказы." % [world.SQUAD.ROUT_THRESHOLD, world.SQUAD.RALLY_THRESHOLD]
			_: stamina_meter=meter
	count_label=UI.label(unit,"",16,UI.BONE)
	count_label.position=Vector2(12,184)
	count_label.size=Vector2(228,24)
	count_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	state_label=UI.label(unit,"",16,UI.BONE)
	state_label.position=Vector2(12,210)
	state_label.size=Vector2(228,24)
	state_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	trait_label=UI.label(unit,"",14,UI.BRASS)
	trait_label.position=Vector2(12,237)
	trait_label.size=Vector2(228,26)
	trait_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var center:=frame(dock,Rect2())
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_left=296
	center.offset_right=-312
	center.offset_top=24
	center.offset_bottom=278
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 5)
	center.add_child(rows)
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 12
	rows.offset_right = -12
	rows.offset_top = 4
	rows.offset_bottom = -3
	var behavior_controls := HBoxContainer.new()
	behavior_controls.add_theme_constant_override("separation", 8)
	rows.add_child(behavior_controls)
	var title := UI.label(behavior_controls, "ДРУЖИНА", 13, UI.BRASS)
	title.custom_minimum_size.x = 118
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selected_behavior = make_behavior_menu(behavior_controls, false)
	army_behavior = make_behavior_menu(behavior_controls, true)
	roster_scroll=ScrollContainer.new()
	roster_scroll.custom_minimum_size.y = 156
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(roster_scroll)
	roster_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	roster_scroll.mouse_force_pass_scroll_events=false
	friendly_deck=HBoxContainer.new()
	friendly_deck.alignment=BoxContainer.ALIGNMENT_CENTER
	friendly_deck.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	friendly_deck.add_theme_constant_override("separation",5)
	roster_scroll.add_child(friendly_deck)
	for group in world.squads:
		if group.team==0: add_unit_card(group)
	var commands:=HBoxContainer.new()
	commands.add_theme_constant_override("separation",5)
	commands.custom_minimum_size.y = 44
	rows.add_child(commands)
	for spec in [["sword","Общая атака · B · Включить агрессию всей армии",world.start_battle],["close","Остановиться · X",stop_selected],["shield","Держать позицию / стена щитов · G",defend_selected],["plus","Область обстрела · Shift+4",aim_selected]]:
		command_buttons.append(medallion(commands,spec[0],spec[1],spec[2]))
	world.density_button=OptionButton.new()
	world.density_button.focus_mode=Control.FOCUS_NONE
	for caption in ["Плотный строй · 4","Средний строй · 5","Рыхлый строй · 6"]: world.density_button.add_item(caption)
	world.density_button.item_selected.connect(world.change_formation_density)
	commands.add_child(world.density_button)
	ability_button=make_button(commands,"",use_ability)
	ability_button.hide()
	melee_button = make_button(commands, "", world.toggle_selected_melee)
	melee_button.hide()
	fortify_button = make_button(commands, "Укрепиться", world.fortify_selected)
	fortify_button.tooltip_text = "Первые два ряда выставят копья вперёд и будут держать позицию."
	fortify_button.hide()
	camera_hint=UI.label(commands,"WASD · камера    F · к отряду",13,UI.BRASS)
	camera_hint.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	command_hint=UI.label(dock,"",13,UI.BONE)
	command_hint.add_theme_color_override("font_shadow_color",Color(0,0,0,.95))
	command_hint.add_theme_constant_override("shadow_offset_x",1)
	command_hint.add_theme_constant_override("shadow_offset_y",1)
	command_hint.position=Vector2(298,0)
	command_hint.size=Vector2(1120,22)
	command_hint.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	var right:=frame(dock,Rect2())
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left=-288
	right.offset_right=-18
	right.offset_top=0
	right.offset_bottom=278
	minimap=preload("res://scripts/tactical_minimap.gd").new()
	minimap.world=world
	place(minimap,right,Rect2(12,12,246,181))
	world.pause_button=make_button(right,"",world.toggle_pause)
	world.pause_button.position=Vector2(12,199)
	world.pause_button.size=Vector2(246,32)
	var speeds:=HBoxContainer.new()
	place(speeds,right,Rect2(12,237,246,30))
	for rate in [1,2,3]:
		var button:=make_button(speeds,"%d×" % rate,world.set_speed.bind(rate))
		button.toggle_mode=true
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		world.speed_buttons.append(button)

func stop_selected() -> void:
	world.stop_selected()

func defend_selected() -> void:
	world.command_mode=3

func aim_selected() -> void:
	world.command_mode=4

func column(parent: Node,width: float) -> VBoxContainer:
	var item := VBoxContainer.new()
	item.custom_minimum_size.x = width
	item.add_theme_constant_override("separation",5)
	parent.add_child(item)
	return item

func make_button(parent: Node,caption: String,callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	var normal := UI.metal_button("normal",6)
	button.add_theme_stylebox_override("normal",normal)
	parent.add_child(button)
	return button

func focus_group(group: Node3D) -> void:
	world.select_squad(group)
	world.focus = group.center()
	world.update_camera()

func reflow() -> void:
	var scale_factor := maxf(.35,minf(size.x/1920.0,size.y/1080.0))
	layout.scale = Vector2.ONE*scale_factor
	layout.size = size/scale_factor

func resize_cards() -> void:
	if cards.is_empty():
		return
	var ideal := floorf((roster_scroll.size.x-5*(cards.size()-1))/cards.size())
	var width := clampf(ideal,62,110)
	for card in cards.values():
		card.custom_minimum_size.x = width

func map_bottom_y() -> float:
	return dock.get_global_rect().position.y

func map_top_y() -> float:
	return enemy_dock.get_global_rect().end.y if enemy_dock.visible else 92.0*layout.scale.y

func update_pause(paused: bool) -> void:
	var button: Button = world.pause_button
	button.text = "▶ Начать бой · Пробел" if world.deploying else ("▶ Продолжить · Пробел" if paused else "Ⅱ Пауза · Пробел")
	button.add_theme_stylebox_override("normal",UI.metal_button("primary" if paused else "normal"))
	update_battle_state()

func update_battle_state() -> void:
	var remaining := maxi(0,ceili(world.BATTLE_TIME_LIMIT-world.battle_time))
	var clock := "Осталось %02d:%02d" % [remaining/60,remaining%60]
	var message: String = world.result_text
	if message.is_empty() and get_tree().paused:
		message = "РАССТАНОВКА" if world.deploying else "ПАУЗА"
	if message.is_empty() and not world.campaign_support.is_empty():
		var reinforcements_in := maxi(0,ceili(world.REINFORCEMENT_TIME-world.battle_time))
		message = "Подмога через %02d:%02d" % [reinforcements_in/60,reinforcements_in%60]
	battle_state.text = clock if message.is_empty() else "%s    ·    %s" % [message,clock]
	battle_state.add_theme_color_override("font_color",Color("eda089") if remaining<=60 else (UI.BRASS if message.is_empty() else Color("eac380")))

func refresh(ours: int,theirs: int) -> void:
	var factions: Array = world.campaign_request.get("banner_factions",[])
	var side := "РУСЬ"
	var rival := "ПРОТИВНИК"
	if not factions.is_empty():
		side = UI.Geo.FACTIONS[factions[0]].name.to_upper()
		rival = UI.Geo.FACTIONS[factions[1]].name.to_upper()
	friendly_count.text = "%s    %d" % [side,ours]
	enemy_count.text = "%d    %s" % [theirs,rival]
	friendly_health.value = world.team_health(0)
	enemy_health.value = world.team_health(1)
	update_battle_state()
	refresh_selection()

func make_behavior_menu(parent: Control, all_groups: bool) -> OptionButton:
	var menu := OptionButton.new()
	menu.focus_mode = Control.FOCUS_NONE
	menu.allow_reselect = true
	menu.fit_to_longest_item = false
	menu.tooltip_text = "Изменить поведение всей армии" if all_groups else "Изменить поведение выбранных отрядов"
	var descriptions := [
		"Вступает в бой только по прямому приказу.",
		"Держит строй и бьёт врагов на дистанции своего оружия.",
		"Вступает в бой после вражеского попадания.",
		"Сам находит ближайшего врага и атакует."
	]
	for i in Squad.BEHAVIOR_NAMES.size():
		menu.add_item(Squad.BEHAVIOR_NAMES[i])
		menu.set_item_tooltip(i, descriptions[i])
	menu.item_selected.connect(world.set_squad_behavior.bind(all_groups))
	parent.add_child(menu)
	return menu

func refresh_behavior_menu(menu: OptionButton, label: String, groups: Array) -> void:
	menu.disabled = groups.is_empty() or not world.result_text.is_empty()
	var mode: int = -1 if groups.is_empty() else groups[0].behavior
	if groups.any(func(group): return group.behavior != mode):
		mode = -1
	if menu.selected != mode:
		menu.select(mode)
	var description: String = "Разные режимы" if mode < 0 else Squad.BEHAVIOR_NAMES[mode]
	menu.text = label if groups.is_empty() else "%s · %s" % [label, description]

func refresh_selection(scroll_to_selected := false) -> void:
	var group: Node3D = world.selected_squad
	var selection: Array = world.selected_groups()
	refresh_behavior_menu(selected_behavior, "Выбранные", selection)
	refresh_behavior_menu(army_behavior, "Вся армия", world.friendly_groups())
	portrait.texture=UI.art(group.commander_portrait if not group.commander_portrait.is_empty() else group.unit_kind)
	health_meter.value=group.total_health()
	morale_meter.value=group.morale/100.0
	stamina_meter.value=group.stamina/100.0
	for button in command_buttons: button.disabled=not world.result_text.is_empty() or selection.is_empty()
	command_buttons[0].disabled = not world.result_text.is_empty() or world.team_in_battle(0)==0
	for button in command_buttons: button.disabled = button.disabled or world.deploying
	command_buttons[3].disabled = command_buttons[3].disabled or not selection.any(func(unit): return unit.can_bombard())
	var bow_units := selection.filter(func(unit): return unit.is_ranged())
	melee_button.visible = not world.deploying and not bow_units.is_empty()
	melee_button.disabled = not world.result_text.is_empty() or not bow_units.any(func(unit): return unit.ammo_count() > 0)
	melee_button.text = "В ближний бой · V" if bow_units.any(func(unit): return unit.uses_bows()) else "Вернуть луки · V"
	fortify_button.visible = not world.deploying and selection.any(func(unit): return unit.uses_spear_formation())
	fortify_button.disabled = not world.result_text.is_empty()
	for card in cards.values():
		card.refresh(card.squad.selected and card.squad.combat_ready())
	for card in enemy_cards.values():
		card.refresh(false)
	if scroll_to_selected and cards.has(group):
		roster_scroll.ensure_control_visible(cards[group])
	name_label.text = group.display_name
	kind_label.text = Card.NAMES.get(group.unit_kind,group.display_name)
	kind_label.visible = kind_label.text.to_lower() != name_label.text.to_lower() and group.unit_kind not in ["light_cavalry","cavalry"]
	count_label.text = "%d / %d воинов" % [group.alive_count(),group.unit_count]
	if group.is_ranged() or group.can_throw_spears():
		count_label.text += "  ·  %s %d" % ["стрелы" if group.is_ranged() else "копья",group.ammo_count()]
	if selection.size()>1: count_label.text = "Выбрано отрядов · %d" % selection.size()
	elif selection.is_empty() and not group.routed: count_label.text = "Нет выбранных отрядов"
	state_label.text = Card.order_text(group)
	state_label.add_theme_color_override("font_color",Card.condition_color(group))
	trait_label.text = Card.morale_text(group)
	if group.stamina < 98.0 and group.alive_count() > 0 and not group.surrendered:
		var fatigue := "Выносливость %d%%" % ceili(group.stamina)
		trait_label.text = fatigue if trait_label.text.is_empty() else "%s   ·   %s" % [fatigue,trait_label.text]
	trait_label.add_theme_color_override("font_color",Card.condition_color(group))
	world.density_button.disabled = world.deploying or selection.is_empty() or not world.result_text.is_empty()
	world.density_button.select(group.formation_density)
	ability_button.visible = not world.deploying and group in selection and group.unit_kind in ["varangian","princely"]
	camera_hint.visible = not ability_button.visible and not melee_button.visible and not fortify_button.visible
	if group.unit_kind == "varangian":
		ability_button.disabled = not world.result_text.is_empty() or not group.can_activate_berserk()
		ability_button.text = "Берсерк · %d с" % ceili(group.berserk_remaining) if group.berserk_remaining > 0 else ("Берсерк использован" if group.berserk_used else "Берсерк")
		ability_button.tooltip_text = "Мораль не влияет на отряд 60 секунд. Одно применение за бой."
	elif group.unit_kind == "princely":
		ability_button.disabled = not world.result_text.is_empty() or not group.can_activate_inspiration()
		ability_button.text = "Воодушевление · %d с" % ceili(group.inspired_remaining) if group.inspiration_used and group.inspired_remaining > 0 else ("Воодушевление использовано" if group.inspiration_used else "Воодушевление")
		ability_button.tooltip_text = "Союзники в 50 м сразу получают +20 к морали и на минуту +20% к урону, здоровью и скорости. Отступающие собираются при 50% морали. Одно применение за бой."
	command_hint.text = order_hint(group)

func use_ability() -> void:
	if not world.result_text.is_empty(): return
	var group: Node3D = world.selected_squad
	var used: bool = group.activate_berserk() if group.unit_kind == "varangian" else group.activate_inspiration()
	if used: refresh_selection()

func order_hint(group: Node3D) -> String:
	if not world.result_text.is_empty():
		return "R — новый бой" if world.campaign_request.is_empty() else "Вернуться на карту — закончить сражение"
	if world.formation_preview.visible:
		if world.drag_layout.size() > 1:
			return "Отряды в строю: %d   ·   Отпустите ПКМ" % world.drag_layout.size()
		var layout: Dictionary = world.drag_layout.values()[0]
		return "Фронт: %d воинов   ·   %.1f м   ·   Отпустите ПКМ" % [layout.columns,layout.width]
	if Time.get_ticks_msec()<world.order_expires: return world.order_notice
	if world.deploying:
		return "Shift / рамка — выбрать отряды · Потяните ПКМ в зоне расстановки, чтобы задать строй"
	if world.selected_groups().is_empty():
		return "ЛКМ — выбрать отряд · Рамка — выбрать несколько"
	var defense := "Держать позицию" if group.is_mounted() or group.is_ranged() else "Стена щитов"
	if world.command_mode == 3:
		return "%s   ·   ЛКМ — направление фронта" % defense
	if world.command_mode == 4:
		return "ЛКМ — область обстрела" if group.uses_bows() else "ЛКМ — область броска копий"
	var hint := "ПКМ — шаг / атака    ·    Двойной ПКМ — %s    ·    G — %s" % ["галоп" if group.is_mounted() else "бег",defense.to_lower()]
	if group.uses_bows():
		hint += "    ·    Shift+4 — обстрел"
	elif group.can_throw_spears():
		hint += "    ·    Shift+4 — копья"
	return hint+"    ·    Shift / рамка — несколько отрядов"

func make_announcements() -> void:
	announcement=PanelContainer.new()
	announcement.add_theme_stylebox_override("panel",UI.campaign_frame(12))
	Chrome.decorate(announcement,15)
	place(announcement,layout,Rect2(18,83,358,142))
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	announcement.add_child(row)
	notice_portrait=TextureRect.new()
	notice_portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	notice_portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	notice_portrait.custom_minimum_size=Vector2(78,108)
	row.add_child(notice_portrait)
	var text:=VBoxContainer.new()
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(text)
	notice_title=UI.label(text,"",25,UI.BONE,true)
	notice_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	notice_body=UI.label(text,"",16,UI.BRASS)
	notice_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	announcement.hide()

func announce_commander(team: int, commander: String) -> void:
	notices.append({"team":team,"commander":commander})
	show_next_notice()

func show_next_notice() -> void:
	if announcement.visible or notices.is_empty(): return
	var item: Dictionary=notices.pop_front()
	notice_title.text="Наш полководец погиб" if item.team==0 else "Вражеский полководец погиб"
	notice_body.text=item.commander+"\nБоевой дух его войска −20"
	var portraits: Array=world.campaign_request.get("commander_portraits",["infantry","infantry"])
	notice_portrait.texture=UI.art(portraits[item.team])
	notice_until=Time.get_ticks_msec()+9000
	announcement.show()

func _process(_delta: float) -> void:
	if is_instance_valid(announcement) and announcement.visible and Time.get_ticks_msec()>notice_until:
		announcement.hide()
		show_next_notice()
