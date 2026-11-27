extends Control

const UI = preload("res://campaign_map/ui_theme.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")
const Medallion = preload("res://campaign_map/ui_medallion.gd")
const Card = preload("res://campaign_map/ui_card.gd")
const Atlas = preload("res://campaign_map/campaign_atlas.gd")
const Data = preload("res://campaign_map/campaign_state.gd")
const Geo = preload("res://campaign_map/geography.gd")
const Forces = preload("res://campaign_map/forces.gd")
const CampaignSave = preload("res://campaign_map/campaign_save.gd")
const Experience = preload("res://scripts/unit_experience.gd")
const Equipment = preload("res://scripts/unit_equipment.gd")
const SETTLEMENT_ROLES := ["Небольшое поселение", "Маленький город", "Город", "Большой город"]
const SHORT_NAMES := {"militia":"Ополченцы", "infantry":"Копейщики", "archer":"Лучники", "cavalry":"Тяж. конница", "light_cavalry":"Лёгк. конница", "varangian":"Варяги", "khazar":"Хазары"}
var world
var panel
var canvas: Control
var dock: Control
var deck_title: Label
var deck_icon: TextureRect
var deck: HBoxContainer
var deck_scroll: ScrollContainer
var city_portrait_frame: Panel
var portrait: TextureRect
var city_name: Label
var city_role: Label
var role_icon: TextureRect
var city_owner: Label
var tabs: HBoxContainer
var context_name: Label
var context_icon: TextureRect
var context_summary: Label
var city_summary: HBoxContainer
var city_indicators: Array[Label] = []
var inspection: Label
var stance: Label
var money: Label
var income: Label
var food: Label
var population: Label
var province_caption: Label
var action: Button
var movement: ProgressBar
var unit_id := ""
var menu: PanelContainer
var menu_actions: VBoxContainer
var load_actions: VBoxContainer
var save_button: Button
var load_buttons: Dictionary[CampaignSave.Slot,Button] = {}
var load_feedback: Label
var nav_buttons := {}
var research_badge: Label
var army_tab: Button
var town_tab: Button
var recruit_tab: Button
var garrison_tab: Button
var help_label: Label
var story_objective: Button
var turn_notice: PanelContainer
var turn_notice_title: Label
var turn_notice_date: Label
var turn_notice_tween: Tween
var enemy_turn_notice := false
var player_turn_frame := UI.campaign_frame(12)
var enemy_turn_frame := UI.campaign_frame(12)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.theme()
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	resized.connect(relayout)
	make_top_bar()
	make_dock()
	make_menu()
	make_turn_notice()
	relayout()

func make_turn_notice() -> void:
	turn_notice = PanelContainer.new()
	Chrome.decorate(turn_notice,15)
	turn_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_notice.add_theme_stylebox_override("panel",player_turn_frame)
	enemy_turn_frame.bg_color = Color("3d211df5")
	enemy_turn_frame.border_color = Color("d39476")
	canvas.add_child(turn_notice)
	turn_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	turn_notice.offset_left = -217
	turn_notice.offset_right = 217
	turn_notice.offset_top = 73
	var lines := VBoxContainer.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation",3)
	turn_notice.add_child(lines)
	turn_notice_title = UI.label(lines,"Ваш ход",35,UI.BONE,true)
	turn_notice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_notice_date = UI.label(lines,"",19,UI.BRASS)
	turn_notice_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_notice_date.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	turn_notice.hide()

func update_turn_notice() -> void:
	var enemy_turn: bool = world.enemy_actor > 0 and not world.campaign_defeated
	if enemy_turn:
		if not enemy_turn_notice:
			if turn_notice_tween: turn_notice_tween.kill()
			turn_notice.add_theme_stylebox_override("panel",enemy_turn_frame)
			turn_notice_title.text = "Ход противника"
			turn_notice_date.add_theme_color_override("font_color",Color("e5b899"))
			turn_notice.modulate.a = 1.0
			turn_notice.show()
		turn_notice_date.text = world.enemy_turn_status()
	elif enemy_turn_notice:
		turn_notice.hide()
	enemy_turn_notice = enemy_turn

func show_turn_start() -> void:
	if turn_notice_tween: turn_notice_tween.kill()
	turn_notice.add_theme_stylebox_override("panel",player_turn_frame)
	turn_notice_title.text = "Ваш ход"
	turn_notice_date.add_theme_color_override("font_color",UI.BRASS)
	turn_notice_date.text = world.turn_label.text
	turn_notice.modulate.a = 1.0
	turn_notice.show()
	turn_notice_tween = create_tween()
	turn_notice_tween.tween_interval(3.2)
	turn_notice_tween.tween_property(turn_notice,"modulate:a",0.0,.4)
	turn_notice_tween.tween_callback(turn_notice.hide)

func at(control: Control, parent: Control, rect: Rect2) -> void:
	parent.add_child(control)
	control.position = rect.position
	control.size = rect.size

func button(parent: Node, text: String, icon_key: String, action_fn: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.icon = UI.icon(icon_key) if not icon_key.is_empty() else null
	result.expand_icon = false
	result.add_theme_constant_override("icon_max_width",22)
	result.add_theme_font_size_override("font_size",16)
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.pressed.connect(action_fn)
	parent.add_child(result)
	for state in ["normal","hover","pressed","disabled"]:
		var style: StyleBox = result.get_theme_stylebox(state).duplicate()
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		result.add_theme_stylebox_override(state,style)
	return result

func medallion(parent: Node, key: String, hint: String, callback: Callable) -> Button:
	var item := Medallion.new()
	item.key = key
	item.tooltip_text = hint
	item.pressed.connect(callback)
	parent.add_child(item)
	return item

func frame(parent: Control, rect: Rect2, beveled := false) -> Control:
	var surface := Control.new()
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	at(surface,parent,rect)
	var chrome := Chrome.new()
	chrome.beveled = beveled
	if beveled:
		chrome.frame.set_corner_radius_all(13)
		chrome.ornament_depth = 25
	surface.add_child(chrome)
	chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return surface

func make_top_bar() -> void:
	var council := HBoxContainer.new()
	at(council,canvas,Rect2(19,6,320,54))
	council.add_theme_constant_override("separation",11)
	medallion(council,"menu","Меню кампании · Esc",func(): menu.visible = not menu.visible)
	for item in [["Княжеский род","politics","crown"],["Казна","finance","coin"],["Знания и ремёсла","research","book"],["Цели и летопись","goals","scroll"]]:
		nav_buttons[item[1]] = medallion(council,item[2],item[0],panel.open.bind(item[1]))
	for item: Button in council.get_children():
		item.custom_minimum_size = Vector2(54,54)
	research_badge = UI.label(nav_buttons.research,"!",20,UI.GOLD,true)
	research_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	research_badge.position = Vector2(40,0)
	research_badge.add_theme_color_override("font_outline_color",UI.IRON_DARK)
	research_badge.add_theme_constant_override("outline_size",5)
	var emblem := TextureRect.new()
	emblem.texture = UI.faction_flag(0)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(emblem,canvas,Rect2(357,3,62,72))
	var title := UI.label(canvas,"РУСЬ",37,UI.GOLD,true)
	title.position = Vector2(442,-2)
	title.add_theme_color_override("font_shadow_color",UI.IRON_DARK)
	title.add_theme_constant_override("shadow_offset_y",2)
	var motto := UI.label(canvas," ".join(Geo.FACTIONS[0].name.to_upper().split("")),15,UI.BONE,true)
	motto.position = Vector2(443,41)
	var rule := Control.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(rule,canvas,Rect2(574,44,52,10))
	rule.draw.connect(func(): Chrome.draw_rule(rule,Rect2(Vector2.ZERO,rule.size),true))
	var date_frame := frame(canvas,Rect2(0,12,291,44))
	date_frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	date_frame.offset_left = -359
	date_frame.offset_right = -12
	date_frame.offset_top = 8
	date_frame.offset_bottom = 58
	var season := TextureRect.new()
	season.texture = UI.icon("sun")
	season.modulate = UI.GOLD
	season.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	season.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(season,date_frame,Rect2(22,11,28,28))
	world.turn_label.reparent(date_frame,false)
	world.turn_label.position = Vector2(53,8)
	world.turn_label.size = Vector2(272,34)
	world.turn_label.add_theme_font_override("font",UI.DISPLAY)
	world.turn_label.add_theme_font_size_override("font_size",25)
	world.turn_label.add_theme_color_override("font_color",UI.GOLD)
	world.turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story_objective = button(canvas,"","scroll",func():
		var order: Dictionary = world.story_order()
		if not order.is_empty():
			world.focus_at(Geo.position_of(order.city))
			world.update_fog()
			world.project_markers())
	story_objective.position = Vector2(22,72)
	help_label = UI.label(canvas,"ПКМ — маршрут, повторный ПКМ — марш   ·   СКМ / WASD — обзор   ·   Колесо — масштаб",12,UI.BONE)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help_label.offset_left = 22
	help_label.offset_top = -351
	help_label.offset_bottom = -329
	help_label.add_theme_color_override("font_shadow_color",UI.IRON_DARK)
	help_label.add_theme_constant_override("shadow_offset_y",1)

func pictogram(parent: Node, icon_key: String, dimension := 18.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = UI.icon(icon_key)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2.ONE*dimension
	icon.modulate = UI.GOLD
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon

func resource(parent: Node, icon_key: String, hint: String, font_size := 19) -> Label:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation",5)
	parent.add_child(group)
	pictogram(group,icon_key)
	var value := UI.label(group,"",font_size,UI.BONE,true)
	value.tooltip_text = hint
	value.mouse_filter = Control.MOUSE_FILTER_STOP
	return value

func make_dock() -> void:
	dock = Control.new()
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_top = -321
	var leader_panel := frame(dock,Rect2(10,0,294,313),true)
	city_name = UI.label(leader_panel,"",32,UI.GOLD,true)
	city_name.position = Vector2(10,4)
	city_name.size.x = 269
	city_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	city_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	city_portrait_frame = Panel.new()
	city_portrait_frame.add_theme_stylebox_override("panel",UI.box(UI.PAPER,UI.BRASS,2))
	at(city_portrait_frame,leader_panel,Rect2(14,50,161,183))
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	at(portrait,city_portrait_frame,Rect2(3,3,155,177))
	portrait.draw.connect(func(): Chrome.draw_trim(portrait,Rect2(Vector2.ZERO,portrait.size),13))
	var owner_plate := Panel.new()
	owner_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner_plate.add_theme_stylebox_override("panel",UI.metal_button("plate",0))
	at(owner_plate,city_portrait_frame,Rect2(24,155,113,22))
	city_owner = UI.label(owner_plate,"",14,UI.BONE,true)
	city_owner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	city_owner.offset_left = 5
	city_owner.offset_right = -5
	city_owner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	city_owner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	city_owner.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	role_icon = pictogram(leader_panel,"crown",23)
	role_icon.position = Vector2(184,61)
	city_role = UI.label(leader_panel,"",15,UI.BONE,true)
	city_role.position = Vector2(209,58)
	city_role.size = Vector2(78,49)
	city_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_icon = pictogram(leader_panel,"scales",22)
	context_icon.position = Vector2(184,116)
	context_name = UI.label(leader_panel,"",16,UI.BONE,true)
	context_name.position = Vector2(211,115)
	context_name.size = Vector2(75,50)
	context_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stance = UI.label(leader_panel,"",12,UI.BRASS)
	stance.position = Vector2(14,231)
	movement = ProgressBar.new()
	movement.show_percentage = false
	movement.add_theme_stylebox_override("background",UI.box(UI.IRON,UI.BRASS,0))
	movement.add_theme_stylebox_override("fill",UI.box(UI.GREEN.lightened(.2),Color.TRANSPARENT,0))
	at(movement,leader_panel,Rect2(14,245,158,4))
	var focus_button := medallion(leader_panel,"focus","Показать выбранный объект",focus_selection)
	focus_button.position = Vector2(206,177)
	focus_button.size = Vector2(46,46)
	action = button(leader_panel,"Управление войском","helm",context_action)
	action.position = Vector2(14,251)
	action.size = Vector2(266,47)
	action.add_theme_font_override("font",UI.DISPLAY)
	action.add_theme_font_size_override("font_size",20)
	var center := frame(dock,Rect2(0,0,1120,313),true)
	var deck_chrome = center.get_child(0)
	deck_chrome.panoramic = true
	deck_chrome.separators = PackedFloat32Array([47,236])
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_left = 322
	center.offset_right = -336
	center.offset_top = 0
	center.offset_bottom = 313
	deck_icon = pictogram(center,"town",30)
	deck_icon.position = Vector2(52,12)
	deck_title = UI.label(center,"",30,UI.GOLD,true)
	deck_title.position = Vector2(100,7)
	deck_title.size.x = 448
	deck_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	context_summary = UI.label(center,"",17,UI.BONE,true)
	context_summary.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	context_summary.offset_left = -470
	context_summary.offset_right = -14
	context_summary.offset_top = 16
	context_summary.offset_bottom = 37
	context_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	context_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	city_summary = HBoxContainer.new()
	center.add_child(city_summary)
	city_summary.alignment = BoxContainer.ALIGNMENT_END
	city_summary.add_theme_constant_override("separation",16)
	city_summary.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	city_summary.offset_left = -441
	city_summary.offset_right = -24
	city_summary.offset_top = 14
	city_summary.offset_bottom = 37
	city_indicators.append(resource(city_summary,"coin","Доход города",17))
	city_indicators.append(resource(city_summary,"scales","Порядок в городе",17))
	city_indicators.append(resource(city_summary,"shield","Гарнизон",17))
	deck_scroll = ScrollContainer.new()
	center.add_child(deck_scroll)
	deck_scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	deck_scroll.offset_left = 37
	deck_scroll.offset_right = -13
	deck_scroll.offset_top = 59
	deck_scroll.offset_bottom = 229
	deck_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	deck = HBoxContainer.new()
	deck.add_theme_constant_override("separation",7)
	deck_scroll.add_child(deck)
	inspection = UI.label(center,"",15,UI.BONE,true)
	inspection.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	inspection.offset_left = 344
	inspection.offset_right = -350
	inspection.offset_top = 255
	inspection.offset_bottom = 285
	inspection.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inspection.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inspection.mouse_filter = Control.MOUSE_FILTER_PASS
	tabs = HBoxContainer.new()
	at(tabs,center,Rect2(32,246,240,50))
	tabs.add_theme_constant_override("separation",5)
	army_tab = medallion(tabs,"sword","Выбрать дружину",func(): world.select_army(world.commanded_army))
	town_tab = medallion(tabs,"town","Провинция и строительство",panel.open.bind("province"))
	recruit_tab = medallion(tabs,"plus","Набор войск",panel.open.bind("army"))
	garrison_tab = medallion(tabs,"shield","Гарнизон и перевод отрядов",panel.open.bind("garrison"))
	medallion(tabs,"camp","Походная стойка",panel.open.bind("army"))
	var tip := HBoxContainer.new()
	center.add_child(tip)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tip.offset_left = -380
	tip.offset_right = -27
	tip.offset_top = 255
	tip.offset_bottom = 285
	tip.alignment = BoxContainer.ALIGNMENT_END
	tip.add_theme_constant_override("separation",10)
	pictogram(tip,"info",26)
	var hint := UI.label(tip,"Выберите карточку, чтобы узнать подробности",14,UI.BONE,true)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var commands := frame(dock,Rect2(0,0,304,313),true)
	commands.get_child(0).separators = PackedFloat32Array([160])
	commands.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	commands.offset_left = -314
	commands.offset_right = -10
	commands.offset_top = 0
	commands.offset_bottom = 313
	panel.atlas = Atlas.new()
	panel.atlas.world = world
	at(panel.atlas,commands,Rect2(10,9,284,151))
	var resources := HBoxContainer.new()
	resources.add_theme_constant_override("separation",14)
	at(resources,commands,Rect2(13,168,252,24))
	money = resource(resources,"coin","Казна · серебро")
	income = resource(resources,"arrow","Доход за следующий ход")
	province_caption = UI.label(commands,"",15,UI.BONE,true)
	province_caption.position = Vector2(13,192)
	province_caption.size = Vector2(252,17)
	province_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var local_resources := HBoxContainer.new()
	at(local_resources,commands,Rect2(13,210,252,20))
	local_resources.add_theme_constant_override("separation",18)
	food = resource(local_resources,"grain","Еда текущей провинции")
	population = resource(local_resources,"people","Доступное население вашей части провинции")
	world.turn_button.reparent(commands,false)
	world.turn_button.text = ""
	world.turn_button.position = Vector2(11,243)
	world.turn_button.size = Vector2(54,54)
	world.turn_button.tooltip_text = "Завершить ход"
	var end_turn := button(commands,"Конец хода","",world.request_end_turn)
	end_turn.position = Vector2(49,248)
	end_turn.size = Vector2(189,44)
	end_turn.name = "EndTurnCaption"
	end_turn.add_theme_font_override("font",UI.DISPLAY)
	end_turn.add_theme_font_size_override("font_size",23)
	UI.accent_button(end_turn)
	var map_button := medallion(commands,"map","Вся карта · Home",world.overview)
	map_button.position = Vector2(245,246)
	commands.move_child(world.turn_button,-1)
	map_button.size = Vector2(43,43)
	world.status.reparent(canvas,false)
	world.status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	world.status.offset_left = -600
	world.status.offset_right = -22
	world.status.offset_top = -351
	world.status.offset_bottom = -329
	world.status.add_theme_font_size_override("font_size",13)
	world.status.add_theme_color_override("font_color",UI.BONE)
	world.status.add_theme_color_override("font_shadow_color",UI.IRON_DARK)
	world.status.add_theme_constant_override("shadow_offset_y",1)
	world.status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	world.status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func make_menu() -> void:
	menu = PanelContainer.new()
	Chrome.decorate(menu)
	at(menu,canvas,Rect2(17,76,310,0))
	menu_actions = VBoxContainer.new()
	menu.add_child(menu_actions)
	UI.label(menu_actions,"Кампания",28,UI.BONE,true)
	save_button = button(menu_actions,"Сохранить","save",func():
		world.save_campaign()
		menu.hide())
	button(menu_actions,"Загрузить","load",show_load_slots)
	button(menu_actions,"Вся карта","map",func(): world.overview(); menu.hide())
	button(menu_actions,"Продолжить","close",menu.hide)
	load_actions = VBoxContainer.new()
	menu.add_child(load_actions)
	UI.label(load_actions,"Загрузка кампании",26,UI.BONE,true)
	add_load_slot(CampaignSave.Slot.MANUAL,"Ручное сохранение")
	UI.label(load_actions,"Автосохранения",16,UI.BRASS)
	add_load_slot(CampaignSave.Slot.END_TURN,"Конец хода")
	add_load_slot(CampaignSave.Slot.BATTLE_START,"Начало боя")
	add_load_slot(CampaignSave.Slot.BATTLE_END,"Конец боя")
	load_feedback = UI.label(load_actions,"",16,UI.BRASS)
	load_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(load_actions,"Назад","close",show_menu_actions)
	menu.visibility_changed.connect(func():
		if menu.visible: show_menu_actions())
	show_menu_actions()
	menu.hide()

func show_menu_actions() -> void:
	load_actions.hide()
	menu_actions.show()
	menu.reset_size()

func add_load_slot(slot: CampaignSave.Slot, title: String) -> void:
	load_buttons[slot] = button(load_actions,title,"load",func():
		if world.load_campaign(slot):
			menu.hide()
		else:
			load_feedback.text = world.march_notice
			load_feedback.show())

func show_load_slots() -> void:
	for slot in load_buttons:
		var path: String = world.campaign_slot_path(slot)
		var entry: Button = load_buttons[slot]
		entry.disabled = not FileAccess.file_exists(path)
		entry.tooltip_text = "Сохранение ещё не создано" if entry.disabled else Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(path) + int(Time.get_time_zone_from_system().bias)*60,true)
	load_feedback.hide()
	menu_actions.hide()
	load_actions.show()
	menu.reset_size()

func relayout() -> void:
	if not canvas: return
	var factor := maxf(.001,minf(size.x/1920.0,size.y/1080.0))
	canvas.scale = Vector2.ONE*factor
	canvas.size = size/factor
	if is_instance_valid(panel.details): panel.layout_details()

func refresh() -> void:
	update_turn_notice()
	var order: Dictionary = world.story_order()
	story_objective.visible = not order.is_empty() and not world.campaign_defeated
	if story_objective.visible:
		story_objective.text = "Сюжетная цель · " + order.title
		story_objective.tooltip_text = order.speech + "\n\nПоказать город на карте"
	var finances: Dictionary = world.faction_finances(0)
	money.text = str(world.campaign.factions[0].silver)
	income.text = "%+d" % finances.net
	income.add_theme_color_override("font_color",Color("b8c7a3") if finances.net>=0 else Color("d9a08c"))
	var region: String = world.selected_city if not world.selected_city.is_empty() else world.region_at(world.army_positions[world.selected_army])
	var province: int = Geo.CITIES[region][1]
	var local: Dictionary = world.province_finances(0,province)
	province_caption.text = Geo.PROVINCES[province][0]+" · ваши города: %d" % local.cities
	food.text = "%+d" % local.food
	food.tooltip_text = "Еда провинции: производится %d, потребляется %d. Другие провинции не снабжают эту." % [local.food_produced,local.food_used]
	food.add_theme_color_override("font_color",UI.BONE if local.food>=0 else Color("d9a08c"))
	population.text = str(local.manpower)
	population.tooltip_text = "Население провинции: %d / %d; прирост +%d/ход. Пока недоступно: %d." % [local.manpower,local.limit,local.growth,local.locked]
	research_badge.visible = world.campaign.research_idle(0)
	nav_buttons.research.tooltip_text = "Знания и ремёсла · исследование свободно" if research_badge.visible else "Знания и ремёсла"
	for tab in nav_buttons:
		nav_buttons[tab].selected = panel.screen == tab
		nav_buttons[tab].queue_redraw()
	for child in deck.get_children():
		deck.remove_child(child)
		child.queue_free()
	var town: String = world.selected_city
	var army: int = world.selected_army
	var commander_portrait: String = world.campaign.leader_portrait(army) if army >= 0 else "town"
	var friendly: bool = world.is_player_army(army)
	var faction: Dictionary = Geo.FACTIONS[Geo.army_faction(army)]
	var active: bool = world.player_orders_allowed()
	save_button.disabled = not active or not world.can_load_campaign()
	var city_view := not town.is_empty()
	deck_icon.texture = UI.icon("town" if city_view else "sword")
	context_icon.texture = UI.icon("scales" if city_view else "camp")
	city_summary.visible = city_view
	context_summary.visible = not city_view
	portrait.texture = UI.art("town" if city_view else commander_portrait)
	army_tab.selected = town.is_empty()
	army_tab.queue_redraw()
	town_tab.selected = not town.is_empty()
	town_tab.queue_redraw()
	recruit_tab.disabled = not active
	garrison_tab.visible = (town.is_empty() and friendly and not world.stationed_city(army).is_empty()) or (not town.is_empty() and world.campaign.owner(town) == 0)
	garrison_tab.selected = panel.screen == "garrison"
	garrison_tab.queue_redraw()
	inspection.text = ""
	if town.is_empty():
		var leader: Dictionary = world.campaign.leaders[army]
		city_name.text = leader.name
		deck_title.text = "Дружина · "+leader.name
		role_icon.texture = UI.icon("helm")
		city_role.text = "%s\nРанг %d" % ["Князь" if army in [6,7] else "Воевода",1+floori(leader.xp/100.0)]
		city_owner.text = faction.name
		var roster: Array = world.forces.armies[army]
		var queue: Array = world.campaign.pending_recruits(army) if army == 0 else []
		if not roster.is_empty() and not roster.any(func(unit): return unit.id==unit_id): unit_id = roster[0].id
		context_summary.text = "%s   ·   %d воинов   ·   %d / %d отрядов" % [faction.name,world.forces.headcount(roster),roster.size()+queue.size(),Data.LIMIT]
		if not queue.is_empty(): context_summary.text += "  ·  В наборе %d" % queue.size()
		for unit in roster:
			var guard: bool = unit.kind == "princely"
			var card := Card.new()
			card.art_key = commander_portrait if guard else unit.kind
			card.caption = leader.name if guard else SHORT_NAMES.get(unit.kind,unit.title)
			if guard: card.foot = unit.title
			card.value = str(unit.count)
			card.experience_rank = Experience.rank(unit.get("xp",0))
			card.equipment = Equipment.levels(unit)
			card.selected = unit.id==unit_id
			card.fraction = float(unit.count)/float(unit.get("max",Data.UNITS[unit.kind][1]))
			var squad_name := Forces.squad_name(unit)
			var role: String = "%s · %s" % [leader.name,unit.title] if guard else unit.title
			var title := "%s\n%s" % [squad_name,role]
			if guard: title += "\nРанг %d" % (1+floori(leader.xp/100.0))
			card.tooltip_text = "%s\n%d воинов\n%s\n%s\nНажмите, чтобы выбрать отряд" % [
				title,unit.count,Experience.description(unit.get("xp",0),unit.kind),Equipment.description(card.equipment),
			]
			card.pressed.connect(select_unit.bind(unit.id))
			deck.add_child(card)
			card.custom_minimum_size.x = 94
			if card.selected:
				inspection.text = "%s · %s   ·   %d / %d воинов   ·   Опыт %d   ·   %s   ·   %s   ·   Содержание %d серебра, %d пищи" % [
					squad_name,unit.title,unit.count,unit.get("max",Data.UNITS[unit.kind][1]),card.experience_rank,
					Equipment.title(card.equipment.x,false),Equipment.title(card.equipment.y,true),Data.UNITS[unit.kind][3],Data.UNIT_FOOD[unit.kind],
				]
		if roster.is_empty(): inspection.text = "Войско не собрано"
		for enlistment in queue:
			var unit: Dictionary = enlistment.unit
			var card := Card.new()
			card.art_key = unit.kind
			card.caption = SHORT_NAMES.get(unit.kind,unit.title)
			card.value = str(unit.count)
			card.fraction = -1
			card.experience_rank = Experience.rank(unit.get("xp",0))
			card.foot = "В наборе · %d ход." % enlistment.turns
			card.tooltip_text = "%s\n%s · %d воинов\n%s\nНабор в регионе %s" % [Forces.squad_name(unit),unit.title,unit.count,card.foot,Geo.CITIES[enlistment.city][0]]
			card.disabled = true
			deck.add_child(card)
			card.custom_minimum_size.x = 94
		if friendly and roster.size()+queue.size()<Data.LIMIT:
			var card := Card.new()
			card.empty = true
			card.caption = "Набрать отряд"
			card.tooltip_text = "Открыть набор и наём войск"
			card.pressed.connect(panel.open.bind("army"))
			card.disabled = not active
			deck.add_child(card)
			card.custom_minimum_size.x = 94
		context_name.text = Data.STANCES[world.campaign.stances[army]].to_upper()
		action.text = "Управление войском" if friendly else "Атаковать войско"
		action.icon = UI.icon("helm" if friendly else "sword")
		action.disabled = not active
	else:
		var city: Dictionary = world.campaign.cities[town]
		var is_ours: bool = city.owner == 0
		var income_stats: Dictionary = world.campaign.town_yield(town)
		city_name.text = Geo.CITIES[town][0]
		deck_title.text = Geo.CITIES[town][0]+" · Постройки"
		var owner_faction: Dictionary = Geo.FACTIONS[city.owner]
		var is_faction_capital: bool = owner_faction.capital == town
		var is_province_capital := Geo.is_province_capital(town)
		role_icon.texture = UI.icon("crown" if is_faction_capital or is_province_capital else "town")
		if is_faction_capital:
			city_role.text = "Столица фракции"
		elif is_province_capital:
			city_role.text = "Столица области"
		else:
			var hall_level := clampi(city.buildings.get("hall",1),1,SETTLEMENT_ROLES.size())
			city_role.text = SETTLEMENT_ROLES[hall_level-1]
		city_owner.text = owner_faction.name
		city_indicators[0].text = "Доход %d" % income_stats.silver
		city_indicators[1].text = "Порядок %d" % city.order
		city_indicators[1].tooltip_text = "Порядок в городе"
		if not city.rebel:
			var forecast: Dictionary = world.city_order_forecast(town)
			city_indicators[1].text = "Порядок %d → %d" % [city.order,forecast.next]
			city_indicators[1].tooltip_text = "Изменения за следующий ход\n"+"\n".join(panel.order_forecast_lines(forecast))
		city_indicators[2].text = "Гарнизон %d" % world.forces.headcount(world.forces.garrisons.get(town,[]))
		var profile := "Торговый город" if town in Geo.TRADE_CITIES else "Военный город"
		inspection.text = "%s   ·   %s   ·   %s" % [Geo.PROVINCES[Geo.CITIES[town][1]][0],world.campaign.trade_goods_text(town),profile]
		if is_ours:
			inspection.text += "   ·   Население провинции: %d (+%d/ход)" % [local.manpower,local.growth]
			if city.get("occupation",0)>0: inspection.text += "   ·   Восстановление: %d ход." % city.occupation
		for key in Data.BUILDINGS:
			var level: int = city.buildings.get(key,0)
			if level == 0:
				continue
			var branch: int = world.campaign.building_branch(town,key)
			var card := Card.new()
			card.art_key = UI.building_art_key(key,level,branch)
			card.building = true
			card.caption = Data.building_name(key,level,branch)
			card.foot = "Уровень %s" % Data.LEVEL_NAMES[level-1]
			if city.damage.has(key): card.foot = "Повреждено"
			card.value = Data.LEVEL_NAMES[level-1]
			card.fraction = -1
			card.tooltip_text = card.caption
			if not card.foot.is_empty(): card.tooltip_text += " · " + card.foot
			panel.decorate_building_upkeep(card,key,level," после ремонта" if city.damage.has(key) else "")
			card.tooltip_text += "\nОткрыть строительство провинции" if is_ours else "\nОткрыть сведения о городе"
			card.pressed.connect(panel.open_building.bind(key))
			deck.add_child(card)
		context_name.text = Data.RESOURCES[town]
		var hostile: bool = world.can_attack_city(town)
		action.text = "Атаковать город" if hostile else ("Управление городом" if is_ours else "Сведения о городе")
		action.icon = UI.icon("sword" if hostile else "town")
		action.disabled = not active
	inspection.tooltip_text = inspection.text
	stance.visible = town.is_empty() and friendly
	movement.visible = stance.visible
	stance.text = "Ход  %d / %d" % [roundi(world.movement),roundi(world.MOVE_PER_TURN*world.stance_movement())]
	movement.max_value = world.MOVE_PER_TURN*world.stance_movement()
	movement.value = world.movement
	world.status.tooltip_text = world.status.text
	if not world.battle_summary.is_empty():
		var summary: Dictionary = world.battle_summary
		world.status.tooltip_text += "\n%s · %s\nПотери Руси: %d · осталось %d\nПотери противника: %d" % [summary.title,summary.target,summary.own_losses,summary.remaining,summary.enemy_losses]
	world.turn_button.get_parent().get_node("EndTurnCaption").disabled = world.turn_button.disabled
	panel.atlas.queue_redraw()

func select_unit(id: String) -> void:
	unit_id = id
	refresh()

func focus_selection() -> void:
	if not world.selected_city.is_empty(): world.focus_at(Geo.position_of(world.selected_city))
	elif world.can_see_army(world.selected_army): world.focus_at(world.army_positions[world.selected_army])

func context_action() -> void:
	if not world.selected_city.is_empty():
		if world.can_attack_city(world.selected_city): world.order_to(world.selected_city,-1,true)
		else: panel.open("province")
	elif not world.is_player_army(world.selected_army): world.attack_army(world.selected_army,true)
	else: panel.open("army")
