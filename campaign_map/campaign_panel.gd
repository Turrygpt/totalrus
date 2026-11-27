extends Control
## Campaign windows and actions. CampaignHUD owns the persistent command deck.
const Data = preload("res://campaign_map/campaign_state.gd")
const Geo = preload("res://campaign_map/geography.gd")
const UI = preload("res://campaign_map/ui_theme.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")
const Card = preload("res://campaign_map/ui_card.gd")
const Medallion = preload("res://campaign_map/ui_medallion.gd")
const HUD = preload("res://campaign_map/campaign_hud.gd")
const Experience = preload("res://scripts/unit_experience.gd")
const Equipment = preload("res://scripts/unit_equipment.gd")
const CONSTRUCTION_SOUND := "res://assets/audio/construction_start.wav"
const STANCE_NAMES := {"march":"Поход", "forced":"Форсированный марш", "ambush":"Засада", "raid":"Налёт", "camp":"Лагерь"}
var world
var hud: Control
var details: PanelContainer
var veil: ColorRect
var body: VBoxContainer
var header_icon: TextureRect
var header: Label
var subtitle: Label
var feedback: Label
var town_tabs: HFlowContainer
var screen := ""
var settlement_view := ""
var military_buildings := false
var selected_building := "hall"
var selected_recruit := "militia"
var atlas: Control
var construction_audio: AudioStreamPlayer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud = HUD.new()
	hud.world = world
	hud.panel = self
	add_child(hud)
	veil = ColorRect.new()
	veil.color = Color(.015,.032,.050,.16)
	hud.canvas.add_child(veil)
	hud.canvas.move_child(veil,0)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			if world.encounter.is_empty() and world.pending_capture.is_empty(): close_details()
			veil.accept_event())
	veil.hide()
	details = PanelContainer.new()
	details.theme = UI.theme()
	hud.canvas.add_child(details)
	details.add_theme_stylebox_override("panel",UI.campaign_frame(18))
	Chrome.decorate(details,32)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",5)
	details.add_child(layout)
	var title_inset := MarginContainer.new()
	title_inset.add_theme_constant_override("margin_left",18)
	title_inset.add_theme_constant_override("margin_right",12)
	layout.add_child(title_inset)
	var title_row := HBoxContainer.new()
	title_row.custom_minimum_size.y = 61
	title_row.add_theme_constant_override("separation",14)
	title_row.draw.connect(func():
		Chrome.draw_landscape(title_row,Rect2(title_row.size.x*.38,-13,title_row.size.x*.61,135),.96))
	title_inset.add_child(title_row)
	header_icon = add_icon(title_row,"knot",50)
	header_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation",0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(titles)
	header = UI.label(titles,"",42,UI.GOLD,true)
	subtitle = UI.label(titles,"",18,UI.BONE,true)
	var close := make_button(title_row,"",close_details)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.icon = UI.icon("close")
	close.expand_icon = true
	close.add_theme_constant_override("icon_max_width",25)
	close.add_theme_color_override("icon_normal_color",UI.BONE)
	close.custom_minimum_size = Vector2(42,42)
	close.tooltip_text = "Закрыть · Esc"
	town_tabs = flow(layout)
	town_tabs.add_theme_constant_override("h_separation",7)
	town_tabs.hide()
	divider(layout)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	scroll.add_child(body)
	feedback = UI.label(layout,"",16,Color("e2b38a"))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.hide()
	construction_audio = AudioStreamPlayer.new()
	construction_audio.name = "ConstructionAudio"
	construction_audio.volume_db = -12.0
	add_child(construction_audio)
	layout_details()
	details.hide()

func layout_details() -> void:
	var available: Vector2 = hud.canvas.size
	var width := minf(1390,available.x-64)
	var tall := screen in ["province","army","garrison_recruit","research"]
	var preferred_height := 820 if screen == "research" else (642 if tall else 598)
	var height := minf(preferred_height,available.y-372)
	details.position = Vector2((available.x-width)*.5,available.y-350-height)
	details.size = Vector2(width,height)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:
		if details.visible: close_details()
		elif hud.menu.visible: hud.menu.hide()
		else: hud.menu.show()
		get_viewport().set_input_as_handled()

func make_button(parent: Node, title: String, action: Callable, allowed := true) -> Button:
	var item := Button.new()
	item.text = title
	item.add_theme_font_size_override("font_size",16)
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.pressed.connect(action)
	item.disabled = not allowed
	parent.add_child(item)
	return item

func close_details() -> void:
	screen = ""
	details.hide()
	veil.hide()
	hud.refresh()

func open(tab: String) -> void:
	if world.campaign_defeated or not world.encounter.is_empty() or not world.pending_capture.is_empty(): return
	if screen==tab and details.visible:
		close_details()
		return
	screen = tab
	if screen == "army":
		world.selected_city = ""
		world.selected_army = world.commanded_army
	if screen in ["province","garrison"]:
		settlement_view = world.selected_city
		if screen == "garrison" and settlement_view.is_empty(): settlement_view = world.stationed_city(world.commanded_army)
		if settlement_view.is_empty(): settlement_view = world.current_city
		if settlement_view.is_empty(): settlement_view = world.region_at(world.army_positions[world.commanded_army])
	hud.menu.hide()
	if not hud.enemy_turn_notice: hud.turn_notice.hide()
	veil.show()
	details.show()
	if screen == "army": world.refresh_ui()
	else: refresh()

func open_building(key: String) -> void:
	military_buildings = key in Data.MILITARY_BUILDINGS
	selected_building = key
	if screen=="province": refresh()
	else: open("province")

func show_building_group(military: bool) -> void:
	military_buildings = military
	selected_building = "barracks" if military else "hall"
	refresh()

func line(value: String, font_size := 18, parent: Node = null) -> Label:
	var item := UI.label(body if parent==null else parent,value,font_size,UI.BONE)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return item

func row(parent: Node = null) -> HBoxContainer:
	var result := HBoxContainer.new()
	(body if parent==null else parent).add_child(result)
	return result

func flow(parent: Node = null) -> HFlowContainer:
	var result := HFlowContainer.new()
	(body if parent==null else parent).add_child(result)
	return result

func tile(parent: Node, width := 210) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",UI.box(Color("152128"),UI.BRASS.darkened(.35),13))
	Chrome.decorate(panel,14)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",7)
	panel.add_child(column)
	return column

func picture(parent: Node, key: String, width: float, height: float) -> TextureRect:
	return texture_picture(parent,UI.art(key),width,height)

func texture_picture(parent: Node, texture: Texture2D, width: float, height: float) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(width,height)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func metric(parent: Node, title: String, value: String, key: String) -> void:
	var column := tile(parent,150)
	var heading := row(column)
	var image := TextureRect.new()
	image.texture = UI.icon(key)
	image.custom_minimum_size = Vector2(20,20)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.modulate = UI.BRASS
	heading.add_child(image)
	UI.label(heading,title.to_upper(),13,UI.BRASS)
	UI.label(column,value,32,UI.BONE,true)

func add_icon(parent: Node, key: String, width := 18) -> TextureRect:
	var image := TextureRect.new()
	image.texture = UI.icon(key)
	image.custom_minimum_size = Vector2(width,width)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.modulate = UI.GOLD
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func stat(parent: Node, icon: String, value: String) -> void:
	var entry := row(parent)
	entry.add_theme_constant_override("separation",7)
	add_icon(entry,icon)
	var caption := UI.label(entry,value,17,UI.BONE,true)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func divider(parent: Node, ornament := false) -> void:
	var rule := Control.new()
	rule.custom_minimum_size.y = 7 if ornament else 3
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.draw.connect(func(): Chrome.draw_rule(rule,Rect2(Vector2.ZERO,rule.size),ornament))
	parent.add_child(rule)

func serif_button(button: Button, font_size := 20) -> void:
	button.add_theme_font_override("font",UI.DISPLAY)
	button.add_theme_font_size_override("font_size",font_size)

func section(title: String, parent: Node = null) -> void:
	UI.label(body if parent==null else parent,title,25,UI.BONE,true)

func refresh() -> void:
	hud.refresh()
	if screen.is_empty():
		veil.visible = world.campaign_defeated or not world.encounter.is_empty() or not world.pending_capture.is_empty()
		return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for child in town_tabs.get_children():
		town_tabs.remove_child(child)
		child.queue_free()
	town_tabs.visible = screen == "province"
	feedback.hide()
	var screen_icons := {"province":"knot","garrison":"shield","garrison_recruit":"plus","army":"sword","finance":"coin","research":"book","politics":"crown","goals":"scroll"}
	header_icon.texture = UI.icon(screen_icons.get(screen,"town"))
	var active: bool = world.player_orders_allowed()
	var campaign = world.campaign
	match screen:
		"province": province(campaign,active)
		"garrison": show_garrison()
		"garrison_recruit": garrison_recruit(campaign)
		"army": army(campaign,active)
		"finance": finance(campaign,active)
		"research": knowledge(campaign,active)
		"politics": dynasty(campaign,active)
		"goals": chronicle(campaign)
	call_deferred("layout_details")

func select_building(key: String) -> void:
	selected_building = key
	refresh()

func province(campaign, active: bool) -> void:
	var id := settlement_view
	var town: Dictionary = campaign.cities[id]
	var province_id: int = Geo.CITIES[id][1]
	header.text = Geo.PROVINCES[province_id][0]
	subtitle.text = "%s  ·  %s  ·  %s" % [Geo.CITIES[id][0],Geo.FACTIONS[town.owner].name,campaign.trade_goods_text(id)]
	for key in Geo.CITIES:
		if Geo.CITIES[key][1] != province_id: continue
		var known: bool = world.fog.visible_at(Geo.position_of(key)) or campaign.owner(key)==0
		var tab := make_button(town_tabs,Geo.CITIES[key][0] if known else "Неизвестное поселение",select_town.bind(key),known and key!=id)
		tab.custom_minimum_size = Vector2(126 if key != id else 154,43)
		serif_button(tab,22 if key == id else 20)
		for state in ["normal","hover","pressed","disabled"]:
			var variant: String = {"normal":"tab","hover":"hover_tab","pressed":"active_tab","disabled":"active_tab" if key == id else "tab"}[state]
			var style := UI.metal_button(variant,13)
			style.content_margin_top = 7
			style.content_margin_bottom = 7
			tab.add_theme_stylebox_override(state,style)
		tab.add_theme_color_override("font_disabled_color",UI.BONE)
	var content := row()
	content.add_theme_constant_override("separation",14)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stats_column := tile(content,244)
	stats_column.get_parent().size_flags_horizontal = Control.SIZE_FILL
	stats_column.add_theme_constant_override("separation",2)
	var city_picture := picture(stats_column,"town",207,111)
	city_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	city_picture.draw.connect(func(): Chrome.draw_trim(city_picture,Rect2(Vector2.ZERO,city_picture.size),11))
	var stats: Dictionary = campaign.town_yield(id)
	var city_title := UI.label(stats_column,Geo.CITIES[id][0],28,UI.GOLD,true)
	city_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider(stats_column)
	stat(stats_column,"coin","Доход  %d серебра" % stats.silver)
	if stats.silver_upkeep > 0:
		stat(stats_column,"coin","Содержание  −%d сер." % stats.silver_upkeep)
	stat(stats_column,"grain","Еда города  %+d" % stats.food)
	if town.rebel:
		stat(stats_column,"scales","Порядок  %d" % town.order)
	else:
		var forecast: Dictionary = world.city_order_forecast(id)
		stat(stats_column,"scales","Порядок  %d → %d" % [town.order,forecast.next])
		if forecast.revolt:
			line("Мятеж на следующем ходу",15,stats_column)
		elif town.revolt_turns > 0 and forecast.revolt_turns == 0:
			line("На следующем ходу угроза мятежа спадёт",14,stats_column)
		elif town.revolt_turns > 0:
			line("До мятежа: %d ход." % town.revolt_turns,15,stats_column)
		elif forecast.revolt_turns > 0:
			line("На следующем ходу начнётся отсчёт до мятежа",14,stats_column)
		elif forecast.band and not campaign.rebellions.has(id):
			line("На следующем ходу появятся повстанцы",14,stats_column)
		elif town.order <= Data.UNREST_ORDER and not campaign.rebellions.has(id) and town.occupation == 0:
			line("Беспорядки · штраф к доходу 25%",14,stats_column)
		line("Изменения за следующий ход",14,stats_column)
		for reason in order_forecast_lines(forecast):
			line(reason,14,stats_column)
		divider(stats_column)
	var is_ours: bool = town.owner == 0
	if is_ours:
		var local: Dictionary = world.province_finances(0,province_id)
		stat(stats_column,"town","Ваши города в крае  %d" % local.cities)
		stat(stats_column,"people","Население  %d / %d" % [local.manpower,local.limit])
		stat(stats_column,"arrow","Прирост края  +%d / ход" % local.growth)
		line("Прирост города +%d / ход" % campaign.manpower_growth(id,local.food),14,stats_column)
		stat(stats_column,"grain","Еда провинции  %+d" % local.food)
		if local.locked>0: line("Недоступно населения: %d" % local.locked,13,stats_column)
		if town.get("occupation",0)>0: line("Восстановление: %d ход." % town.occupation,14,stats_column)
		var relief_issue: String = campaign.relief_issue(0,id)
		var relief := make_button(stats_column,"Раздать припасы · %d сер." % Data.RELIEF_COST,distribute_relief.bind(id),active and relief_issue.is_empty())
		relief.tooltip_text = "+%d порядка за ход в течение %d ходов." % [Data.RELIEF_ORDER,Data.RELIEF_TURNS]
		if not relief_issue.is_empty(): relief.tooltip_text += "\n"+relief_issue
		if town.relief_turns > 0: line("Раздача припасов: ещё %d ход." % town.relief_turns,14,stats_column)
		stat(stats_column,"pin","Места  %d / %d" % [town.buildings.size(),campaign.building_slots(id)])
		var hire_issue: String = campaign.hero_hire_issue(id)
		var hire := make_button(stats_column,"Нанять воеводу",hire_hero.bind(id),active and hire_issue.is_empty())
		serif_button(hire)
		hire.icon = UI.icon("people")
		hire.add_theme_constant_override("icon_max_width",20)
		hire.tooltip_text = "%d серебра · личная дружина из %d всадников" % [campaign.hero_cost(id),Data.UNITS.princely[1]]
		if not hire_issue.is_empty(): hire.tooltip_text += "\n"+hire_issue
		line("%d серебра · %d населения" % [campaign.hero_cost(id),Data.UNITS.princely[1]],13,stats_column)
	else: line("Гарнизон  %d" % world.forces.headcount(world.forces.garrisons.get(id,[])),16,stats_column)
	var catalog := VBoxContainer.new()
	catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog.add_theme_constant_override("separation",8)
	content.add_child(catalog)
	catalog.draw.connect(func():
		Chrome.draw_bird(catalog,Rect2(catalog.size.x-335,catalog.size.y-268,329,220),.22)
		catalog.draw_line(Vector2(catalog.size.x+6,1),Vector2(catalog.size.x+6,catalog.size.y-8),Color(UI.BRASS,.23)))
	if is_ours:
		var advisor_row := row(catalog)
		UI.label(advisor_row,"Советник по строительству",19,UI.GOLD,true)
		var strategies := OptionButton.new()
		for key in Data.ADVISOR_STRATEGIES:
			strategies.add_item(Data.ADVISOR_STRATEGIES[key])
			strategies.set_item_metadata(strategies.item_count-1,key)
			if town.get("advisor","off") == key:
				strategies.select(strategies.item_count-1)
		strategies.disabled = not active
		strategies.tooltip_text = "На каждом ходу выбирает стройку или ремонт по стратегии и расходует серебро из казны."
		strategies.item_selected.connect(func(index): choose_advisor(id,strategies.get_item_metadata(index)))
		advisor_row.add_child(strategies)
	var filters := row(catalog)
	for military in [false,true]:
		var tab := make_button(filters,"Военное дело" if military else "Хозяйство",show_building_group.bind(military),military != military_buildings)
		serif_button(tab)
		tab.icon = UI.icon("sword" if military else "grain")
		tab.add_theme_constant_override("icon_max_width",20)
		if military == military_buildings:
			tab.add_theme_stylebox_override("disabled",UI.metal_button("highlight"))
			tab.add_theme_color_override("font_disabled_color",UI.BONE)
	var buildings := GridContainer.new()
	buildings.columns = 4
	buildings.add_theme_constant_override("h_separation",8)
	buildings.add_theme_constant_override("v_separation",8)
	catalog.add_child(buildings)
	var shown := []
	var local_special := Data.local_special_building(id)
	for key in Data.BUILDINGS:
		if key != "wall" and (key in Data.MILITARY_BUILDINGS) != military_buildings: continue
		if Data.SPECIAL_BUILDINGS.has(key) and key != local_special: continue
		if not is_ours and not town.buildings.has(key): continue
		shown.append(key)
	if selected_building not in shown: selected_building = "" if shown.is_empty() else shown[0]
	for key in shown:
		var level: int = town.buildings.get(key,0)
		var branch: int = campaign.building_branch(id,key)
		var card := Card.new()
		card.compact = true
		card.building = true
		card.art_key = UI.building_art_key(key,level,branch)
		card.caption = Data.building_name(key,level,branch)
		card.value = Data.LEVEL_NAMES[level-1] if level>0 else ""
		card.fraction = -1
		card.selected = selected_building==key
		describe_building_card(card,campaign,id,key,active)
		card.pressed.connect(select_building.bind(key))
		buildings.add_child(card)
	var profile := "Торговый город: дополнительный доход от торговли" if id in Geo.TRADE_CITIES else "Военный город: военные постройки на 20% дешевле"
	divider(catalog)
	stat(catalog,"scales",profile)
	var detail_frame := tile(content,401)
	detail_frame.get_parent().size_flags_horizontal = Control.SIZE_FILL
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size.y = 402
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_frame.add_child(detail_scroll)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",7)
	detail_scroll.add_child(detail)
	if selected_building.is_empty():
		line("Нет известных построек этой категории",17,detail)
	else:
		building_details(campaign,id,selected_building,detail,active)
	if is_ours and not town.queue.is_empty():
		var queue_row := row(catalog)
		add_icon(queue_row,"hourglass",22)
		var target := Data.building_name(town.queue.key,town.queue.level,town.queue.get("branch",0))
		line("В работе · %s · осталось %d ход." % [target,town.queue.turns],16,queue_row).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		make_button(queue_row,"Отменить",cancel.bind(id),active)
	if town.rebel: line("Город захвачен повстанцами. Разгромите гарнизон, чтобы вернуть управление.")
	if campaign.rebellions.has(id):
		line("Повстанцы в окрестностях. Доход города снижен вдвое.")
		make_button(body,"Разгромить повстанцев",world.attack_rebels.bind(id),active)
	if is_ours and not campaign.occupation_issue(id).is_empty(): line(campaign.occupation_issue(id),16)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog.add_child(spacer)
	var decrees := flow(catalog)
	decrees.add_theme_constant_override("h_separation",5)
	if is_ours:
		var plate := PanelContainer.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_theme_stylebox_override("panel",UI.metal_button("plate",7))
		decrees.add_child(plate)
		var title := row(plate)
		title.add_theme_constant_override("separation",5)
		add_icon(title,"scroll",17)
		UI.label(title,"Указ провинции",17,UI.GOLD,true)
		var decree_icons := {"grain":"grain","trade":"scales","order":"shield"}
		var full_control: bool = campaign.owns_province(0,province_id)
		var active_edict: String = campaign.factions[0].edicts.get(province_id,"")
		for key in Data.EDICTS:
			var definition: Array = Data.EDICTS[key]
			var effect: String = definition[2] % definition[1]
			var selected: bool = key == active_edict
			var decree := make_button(decrees,"%s · %s" % [definition[0],effect],edict.bind(province_id,key),active and full_control and not selected)
			serif_button(decree,17)
			decree.icon = UI.icon(decree_icons[key])
			decree.add_theme_constant_override("icon_max_width",17)
			decree.tooltip_text = "%s за ход в каждом городе провинции." % effect
			if selected:
				decree.add_theme_stylebox_override("disabled",UI.metal_button("active_tab"))
				decree.add_theme_color_override("font_disabled_color",UI.BONE)
				decree.add_theme_color_override("icon_disabled_color",UI.GOLD)
				decree.tooltip_text += "\nДействующий указ."
			elif not full_control:
				decree.tooltip_text += "\nДля указа нужно владеть всеми городами провинции."
			elif not active_edict.is_empty():
				decree.tooltip_text += "\nЗаменяет действующий указ."
	if world.current_city!=id and not world.forces.armies[world.commanded_army].is_empty():
		make_button(decrees,"Атаковать город" if world.can_attack_city(id) else "Двинуть дружину к городу",world.order_to.bind(id),active)

func construction_issues(campaign, id: String, key: String, active: bool, action := "build", branch := -1) -> PackedStringArray:
	var reasons: PackedStringArray = campaign.build_issues(0,id,key,action,branch)
	if not active:
		reasons.insert(0,"Дождитесь своего хода." if world.enemy_actor > 0 else "Дождитесь завершения текущего действия на карте.")
	return reasons

func describe_building_card(card: Button, campaign, id: String, key: String, active: bool) -> void:
	var town: Dictionary = campaign.cities[id]
	var level: int = town.buildings.get(key,0)
	var reasons := PackedStringArray()
	if town.queue.get("key","") == key:
		card.foot = "В работе · %d ход." % town.queue.turns
		card.status_icon = "hourglass"
		card.foot_color = Color("775019")
	elif town.damage.has(key):
		card.foot = "Нужен ремонт"
		card.status_icon = "hammer"
		card.foot_color = Color("8b3027")
		reasons = construction_issues(campaign,id,key,active,"repair")
	elif level >= Data.max_building_level(key):
		card.foot = "Построено" if Data.SPECIAL_BUILDINGS.has(key) else "Построено · предел"
		card.status_icon = "check"
	elif town.owner != 0:
		card.foot = "Построено"
		card.status_icon = "check"
	else:
		var available := false
		for option: int in campaign.upgrade_branches(id,key,true):
			var branch_issues := construction_issues(campaign,id,key,active,"build",option)
			if branch_issues.is_empty():
				available = true
				break
			for issue in branch_issues:
				if issue not in reasons: reasons.append(issue)
		if available:
			card.foot = "Можно строить" if level == 0 else "Можно улучшить"
			card.status_icon = "plus" if level == 0 else "upgrade"
			card.foot_color = Color("3c602e")
			reasons.clear()
		else:
			card.foot = "Нельзя строить" if level == 0 else "Улучшение закрыто"
			card.status_icon = "lock"
			card.foot_color = Color("8b3027")
	card.tooltip_text = "%s · %s\n%s" % [card.caption,card.foot,Data.BUILDING_PURPOSE[key]]
	var preview_level := level
	if level == 0: preview_level = town.queue.get("level",1) if town.queue.get("key","") == key else 1
	var starts := " после ремонта" if town.damage.has(key) else (" после строительства" if level == 0 else "")
	decorate_building_upkeep(card,key,preview_level,starts)
	if not reasons.is_empty(): card.tooltip_text += "\n"+"\n".join(reasons)

func building_details(campaign, id: String, key: String, column: VBoxContainer, active: bool) -> void:
	var town: Dictionary = campaign.cities[id]
	var level: int = town.buildings.get(key,0)
	var branch: int = campaign.building_branch(id,key)
	var heading := row(column)
	var art := Control.new()
	art.custom_minimum_size = Vector2(150,106)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(art)
	var illustration := UI.art(UI.building_art_key(key,level,branch))
	art.draw.connect(func():
		if illustration:
			UI.draw_card_art(art,illustration,Rect2(Vector2.ZERO,art.size),Color.WHITE,false))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(titles)
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	var name := UI.label(titles,Data.building_name(key,level,branch),32,UI.GOLD,true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var level_label := UI.label(titles,"Построено · уровень %s" % Data.LEVEL_NAMES[level-1] if level>0 else "Ещё не построено",17,UI.GOLD,true)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	divider(titles,true)
	if Data.SPECIAL_BUILDINGS.has(key):
		stat(column,"pin","Местный промысел · %s" % Data.RESOURCES[id])
	var purpose: String = Data.BUILDING_PURPOSE[key]
	if key == "farm" and branch == Data.HUNTING_BRANCH:
		purpose = "Местный пушной промысел даёт больше серебра и меньше продовольствия."
	var description := UI.label(column,purpose,19,UI.BONE,true)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if key == "market":
		var trade: Vector2i = campaign.local_trade_bonus(id)
		var bonus := "+%d серебра" % trade.x
		if trade.y > 0: bonus += " · +%d еды" % trade.y
		line("%s · %s за уровень торга" % [campaign.trade_goods_text(id),bonus],14,column)
	if level > 0:
		var yields: Vector3i = campaign.building_yield(id,key,level,branch)
		divider(column)
		building_yields(column,yields)
		show_building_upkeep(column,key,level,"После ремонта" if town.damage.has(key) else "Содержание")
		if key == "hall": line("Места под постройки: %d" % campaign.building_slots(id),14,column)
	if key in Data.RECRUIT_GROWTH: line("Прирост населения: +%d / ход за уровень" % Data.RECRUIT_GROWTH[key],14,column)
	if key == "hall" or key == "farm":
		line("Вместимость населения за улучшение  +%d" % (30 if key == "hall" else 10),14,column)
	if town.owner!=0: return
	if level > 0:
		var locate := make_button(column,"Показать на карте",show_built_building.bind(id,key,branch))
		locate.icon = UI.icon("pin")
		locate.add_theme_constant_override("icon_max_width",18)
	if town.queue.get("key","") == key:
		divider(column)
		var queued := Data.building_name(key,town.queue.level,town.queue.get("branch",0))
		stat(column,"hourglass","В работе · %s (%s)" % [queued,Data.LEVEL_NAMES[town.queue.level-1]])
		line("До завершения: %d ход." % town.queue.turns,16,column)
		show_building_upkeep(column,key,town.queue.level,"После завершения")
	elif town.damage.has(key):
		var issues := construction_issues(campaign,id,key,active,"repair",branch)
		building_action(id,key,column,"Починить · %d серебра" % Data.REPAIR_COST,"repair",branch,issues)
		show_construction_issues(column,issues)
	elif level>=Data.max_building_level(key) and not Data.SPECIAL_BUILDINGS.has(key):
		stat(column,"check","Достигнут высший уровень")
	elif level<Data.max_building_level(key):
		divider(column)
		var title := "Строительство" if level == 0 else "Следующий уровень"
		UI.label(column,title,23,UI.GOLD,true)
		stat(column,"hammer","%d серебра · %d ход." % [campaign.build_cost(id,key),campaign.build_turns(id,key)])
		for option: int in campaign.upgrade_branches(id,key,true):
			var target := Data.building_name(key,level+1,option)
			var yields: Vector3i = campaign.building_yield(id,key,level+1,option)
			var issues := construction_issues(campaign,id,key,active,"build",option)
			var target_row := row(column)
			target_row.add_theme_constant_override("separation",6)
			picture(target_row,UI.building_art_key(key,level+1,option),64,64)
			if not issues.is_empty():
				add_icon(target_row,"lock",18)
			var target_label := UI.label(target_row,"%s · %s" % [Data.LEVEL_NAMES[level],target],21,UI.BONE,true)
			target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if issues.is_empty():
				building_action(id,key,column,"Построить" if level == 0 else "Улучшить","build",option,issues)
			else:
				show_construction_issues(column,issues)
			building_yields(column,yields)
			show_building_upkeep(column,key,level+1,"Содержание")
			if key == "hall": line("Места %d" % (Data.HALL_SLOTS[level]-1),14,column)
			if level >= 1 and level+2 <= Data.max_building_level(key):
				line("Дальше · %s · %s" % [Data.LEVEL_NAMES[level+1],Data.building_name(key,level+2,option)],15,column)
	if key == "warehouse" and level>0 and campaign.building_level(id,"market")==0: line("Торг приостановлен",14,column)
	if level>0 and key!="hall":
		var blockers := construction_issues(campaign,id,key,active,"demolish")
		var remove := make_button(column,"Снести постройку",build.bind(id,key,"demolish"),blockers.is_empty())
		remove.tooltip_text = "\n".join(blockers)
		remove.icon = UI.icon("hammer")
		remove.add_theme_constant_override("icon_max_width",22)
		serif_button(remove,22)

func building_yields(parent: Node, yields: Vector3i) -> void:
	var values := row(parent)
	values.alignment = BoxContainer.ALIGNMENT_CENTER
	values.add_theme_constant_override("separation",5)
	for index in 3:
		if yields[index] == 0: continue
		add_icon(values,["coin","grain","scales"][index],16)
		UI.label(values,"%s %+d" % [["Серебро","Еда","Порядок"][index],yields[index]],17,UI.BONE,true)

func order_forecast_lines(forecast: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for reason: String in forecast.reasons:
		lines.append("%+d  %s" % [forecast.reasons[reason],reason])
	return lines

func decorate_building_upkeep(card: Button, key: String, level: int, starts := "") -> void:
	var upkeep := building_upkeep_text(key,level,true)
	if upkeep.is_empty(): return
	card.availability = upkeep
	card.availability_color = Color("8b3027")
	card.tooltip_text += "\nСодержание%s · %s" % [starts,building_upkeep_text(key,level)]

func building_upkeep_text(key: String, level: int, compact := false) -> String:
	var costs := Data.building_upkeep(key,level)
	var parts := PackedStringArray()
	if costs.x > 0: parts.append("−%d %s" % [costs.x,"сер." if compact else "серебра"])
	if costs.y > 0: parts.append("−%d еды" % costs.y)
	if costs.z > 0: parts.append("−%d порядка" % costs.z)
	return " · ".join(parts)+" / ход" if not parts.is_empty() else ""

func show_building_upkeep(parent: Node, key: String, level: int, label: String) -> void:
	var upkeep := building_upkeep_text(key,level)
	if not upkeep.is_empty(): line("%s · %s" % [label,upkeep],16,parent)

func show_construction_issues(column: Node, issues: PackedStringArray) -> void:
	for issue in issues:
		var reason := line("• "+issue,16,column)
		reason.add_theme_color_override("font_color",Color("edba9d"))

func show_built_building(id: String, key: String, branch: int) -> void:
	world.selected_city = id
	close_details()
	world.focus_at(world.terrain.building_location(id,key,branch),95.0)

func building_action(id: String, key: String, column: VBoxContainer, label: String, action: String, branch: int, issues: PackedStringArray) -> void:
	var button := make_button(column,label,build.bind(id,key,action,branch),issues.is_empty())
	button.set_meta("action","build_"+key)
	UI.accent_button(button)
	button.icon = UI.icon("town")
	button.add_theme_constant_override("icon_max_width",24)
	serif_button(button,24)
	button.tooltip_text = "\n".join(issues)

func show_garrison() -> void:
	var id := settlement_view
	header.text = "Гарнизон · "+str(Geo.CITIES[id][0])
	var available: bool = world.stationed_city(world.commanded_army) == id and world.player_orders_allowed()
	subtitle.text = "Перевод отрядов между дружиной и гарнизоном" if available else "Приведите дружину в этот город, чтобы обменяться отрядами"
	if world.campaign.owner(id) == 0:
		line("Кузница I, II и III уровня открывает бронзовые, серебряные и золотые метки снаряжения. Цена за отряд фиксирована.",16)
	var exchange := row()
	var army := tile(exchange,460)
	var garrison := tile(exchange,460)
	var field: Array = world.forces.armies[world.commanded_army]
	var reserve: Array = world.forces.garrisons.get(id,[])
	var field_queue: Array = world.campaign.pending_recruits(0)
	var reserve_queue: Array = world.campaign.pending_recruits(0,id)
	section("Дружина · %d / %d" % [field.size()+field_queue.size(),Data.LIMIT],army)
	section("Гарнизон · %d / %d" % [reserve.size()+reserve_queue.size(),Data.LIMIT],garrison)
	for unit in field:
		transfer_row(army,id,unit,true)
	for unit in reserve:
		transfer_row(garrison,id,unit,false)
	for item in field_queue:
		line("%s · %d воинов · В наборе" % [item.unit.title,item.unit.count],16,army)
	for item in reserve_queue:
		line("%s · %d воинов · В наборе" % [item.unit.title,item.unit.count],16,garrison)
	if field.is_empty(): line("Нет полевых отрядов",17,army)
	if reserve.is_empty(): line("Нет отрядов в гарнизоне",17,garrison)
	if world.campaign.owner(id) == 0:
		make_button(garrison,"Набрать в гарнизон",open.bind("garrison_recruit"),world.player_orders_allowed())
	line("Переведённый отряд сохраняет численность и опыт. Полевые отряды в гарнизоне по-прежнему требуют содержания.",16)

func transfer_row(parent: Node, id: String, unit: Dictionary, to_garrison: bool) -> void:
	var unit_panel := VBoxContainer.new()
	parent.add_child(unit_panel)
	var entry := row(unit_panel)
	picture(entry,world.campaign.leader_portrait(world.commanded_army) if unit.kind == "princely" else unit.kind,52,52)
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_theme_constant_override("separation",1)
	entry.add_child(stats)
	var local_militia: bool = world.Forces.is_city_militia(id,unit)
	var title: String = "Городское ополчение" if local_militia else HUD.SHORT_NAMES.get(unit.kind,unit.title)
	UI.label(stats,title,22,UI.BONE,true)
	var rank := Experience.rank(unit.get("xp",0))
	var strength := "%d воинов" % unit.count
	if rank > 0: strength += " · " + Experience.title(rank)
	var detail := UI.label(stats,strength,14,UI.BRASS)
	var gear := Equipment.levels(unit)
	detail.mouse_filter = Control.MOUSE_FILTER_STOP
	detail.tooltip_text = Experience.description(unit.get("xp",0),unit.kind) + "\n" + Equipment.description(gear)
	if gear != Vector2i.ZERO:
		UI.label(stats,"%s · %s" % [Equipment.title(gear.x,false),Equipment.title(gear.y,true)],14,UI.BRASS)
	if local_militia:
		UI.label(entry,"Только оборона города",16,UI.BRASS)
		return
	var issue: String = world.transfer_issue(id,unit,to_garrison)
	var action := make_button(entry,"В гарнизон →" if to_garrison else "← В дружину",transfer.bind(id,unit.id,to_garrison),issue.is_empty())
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action.tooltip_text = issue
	if not to_garrison and world.can_disband_unit(id,unit):
		make_button(unit_panel,"Распустить отряд",confirm_disband.bind(id,unit),true)
	if world.campaign.owner(id) != 0 or world.campaign.building_level(id,"forge") == 0:
		return
	if to_garrison and world.stationed_city(world.commanded_army) != id:
		return
	var upgrades := flow(unit_panel)
	for armor in [false,true]:
		var offer: Dictionary = world.campaign.equipment_offer(0,id,unit,armor)
		if offer.level > Equipment.MAX_LEVEL:
			continue
		var label := "%s · %d сер." % [Equipment.title(offer.level,armor),offer.price]
		var upgrade := make_button(upgrades,label,upgrade_equipment.bind(id,unit.id,to_garrison,armor),offer.issue.is_empty() and world.player_orders_allowed())
		upgrade.icon = UI.icon("shield" if armor else "sword")
		upgrade.add_theme_constant_override("icon_max_width",16)
		var effect := Equipment.upgrade_description(offer.level,armor)
		upgrade.tooltip_text = effect if offer.issue.is_empty() else effect + "\n" + offer.issue

func upgrade_equipment(id: String, unit_id: String, field: bool, armor: bool) -> void:
	report(world.upgrade_unit_equipment(id,unit_id,field,armor))

func transfer(id: String, unit_id: String, to_garrison: bool) -> void:
	if not world.transfer_unit(id,unit_id,to_garrison):
		report(false)

func army(campaign, active: bool) -> void:
	var index: int = world.commanded_army
	header.text = "Дружина воеводы"
	var id: String = world.region_at(world.army_positions[index])
	subtitle.text = campaign.leaders[index].name.to_upper()+"  ·  "+Geo.CITIES[id][0]+"  ·  %d / 20 отрядов" % world.forces.armies[index].size()
	if world.forces.armies[index].is_empty(): make_button(body,"Собрать новое войско · 110 серебра",raise_player_army,active)
	var stances := flow()
	for key in STANCE_NAMES:
		var button := make_button(stances,STANCE_NAMES[key],choose_stance.bind(key),active and campaign.stances[index]!=key)
		if campaign.stances[index]==key:
			button.add_theme_stylebox_override("disabled",UI.box(UI.RED,UI.BRASS,10))
			button.add_theme_color_override("font_disabled_color",UI.BONE)
	var dismissible: Array = world.forces.armies[index].filter(func(unit): return unit.kind != "princely")
	if not dismissible.is_empty():
		section("Отряды дружины",body)
		var rows := flow()
		for unit in dismissible:
			var entry := row(rows)
			UI.label(entry,"%s · %d" % [world.Forces.squad_name(unit),unit.count],17)
			make_button(entry,"Распустить отряд",confirm_disband.bind("",unit),world.can_disband_unit("",unit))
	recruit_cards(campaign,id,false)
	line("Полевые отряды пополняются на своей земле при избытке еды и наличии людей в провинции.",17)

func garrison_recruit(campaign) -> void:
	var id := settlement_view
	header.text = "Набор в гарнизон"
	subtitle.text = Geo.CITIES[id][0]
	make_button(body,"К гарнизону",return_to_garrison)
	recruit_cards(campaign,id,true)

func return_to_garrison() -> void:
	screen = "garrison"
	refresh()

func select_recruit(key: String) -> void:
	selected_recruit = key
	refresh()

func recruit_cards(campaign, id: String, garrison: bool) -> void:
	if campaign.owner(id) == 0:
		var local: Dictionary = world.province_finances(0,Geo.CITIES[id][1])
		line("%s · ваши города: %d" % [Geo.PROVINCES[Geo.CITIES[id][1]][0],local.cities],18)
		line("Население  %d / %d   ·   Прирост +%d / ход   ·   Еда %+d" % [local.manpower,local.limit,local.growth,local.food],18)
		if local.locked>0: line("Население захваченных и осаждённых городов пока недоступно: %d" % local.locked,14)
	var content := row()
	content.add_theme_constant_override("separation",18)
	var catalog := VBoxContainer.new()
	catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(catalog)
	section("Найм отрядов",catalog)
	var cards := GridContainer.new()
	cards.columns = 6
	cards.add_theme_constant_override("h_separation",8)
	catalog.add_child(cards)
	var recruitable := Data.RECRUIT_BUILDINGS.keys()
	var local_mercenary := Data.local_mercenary(id)
	if not local_mercenary.is_empty(): recruitable.append(local_mercenary)
	if selected_recruit not in recruitable: selected_recruit = recruitable[0]
	var selected_requirements: Array[Dictionary] = []
	for key in recruitable:
		var spec: Array = Data.UNITS[key]
		var requirements: Array[Dictionary] = recruitment_checks(id,key,garrison)
		var blockers := recruit_blockers(requirements)
		var available := blockers.is_empty()
		if key == selected_recruit: selected_requirements = requirements
		var card := Card.new()
		card.art_key = key
		card.caption = HUD.SHORT_NAMES.get(key,spec[0])
		card.value = str(spec[1])
		card.foot = "%d серебра" % campaign.recruit_cost(id,key)
		card.availability = "Можно нанять" if available else "Недоступно"
		card.availability_color = Color("36552d") if available else Color("842d26")
		card.status_icon = "check" if available else "lock"
		card.fraction = -1
		card.selected = selected_recruit==key
		card.muted = not available
		card.tooltip_text = "%s · %s" % [spec[0],card.availability]
		if not available: card.tooltip_text += "\n"+"\n".join(blockers)
		card.pressed.connect(select_recruit.bind(key))
		cards.add_child(card)
	var detail := tile(content,350)
	detail.get_parent().size_flags_horizontal = Control.SIZE_FILL
	var key := selected_recruit
	var spec: Array = Data.UNITS[key]
	section(spec[0],detail)
	var blockers := recruit_blockers(selected_requirements)
	var available := blockers.is_empty()
	var status := line("Можно нанять" if available else "Найм недоступен",18,detail)
	status.add_theme_color_override("font_color",Color("cce2af") if available else Color("ffc2aa"))
	line("%d воинов в отряде" % spec[1],20,detail)
	line("Содержание: %d серебра · %d пищи" % [spec[3],Data.UNIT_FOOD[key]],15,detail)
	var duration: int = campaign.recruit_duration(id,key) if garrison else 0
	var hint := ("Сразу в гарнизон" if garrison else "Сразу в дружину") if duration==0 else "%d ход. на набор" % duration
	var rank := Experience.rank(campaign.recruit_experience(0,id,key))
	if rank > 0: hint += " · " + Experience.title(rank)
	line(hint,14,detail)
	divider(detail)
	UI.label(detail,"Условия найма",22,UI.GOLD,true)
	for requirement in selected_requirements:
		var met: bool = requirement.issue.is_empty()
		var check := row(detail)
		check.add_theme_constant_override("separation",7)
		add_icon(check,"check" if met else "lock",16)
		var label := line(requirement.label if met else requirement.issue,16,check)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not met: label.add_theme_color_override("font_color",Color("edba9d"))
	var hire := make_button(detail,"Нанять · %d серебра" % campaign.recruit_cost(id,key),recruit.bind(id,key,garrison),available)
	hire.set_meta("action","recruit_"+key)
	UI.accent_button(hire)
	hire.tooltip_text = hint if available else "\n".join(blockers)
	var queue: Array = campaign.pending_recruits(0,id if garrison else "")
	section("Очередь набора",catalog)
	if queue.is_empty(): line("Очередь пуста",14,catalog)
	for item in queue: line("%s  ·  %d воинов  ·  %d ход.  ·  %s" % [item.unit.title,item.unit.count,item.turns,Geo.CITIES[item.city][0]],15,catalog)

func recruitment_checks(id: String, key: String, garrison: bool) -> Array[Dictionary]:
	var requirements: Array[Dictionary] = world.recruitment_requirements(id,key,garrison)
	if not world.player_orders_allowed():
		var issue := "Дождитесь своего хода." if world.enemy_actor > 0 else "Дождитесь завершения действия на карте."
		requirements.push_front({"label":"","issue":issue})
	return requirements

func recruit_blockers(requirements: Array[Dictionary]) -> PackedStringArray:
	var blockers := PackedStringArray()
	for requirement in requirements:
		if not requirement.issue.is_empty(): blockers.append(requirement.issue)
	return blockers

func finance(campaign, active: bool) -> void:
	header.text = "Казна"
	subtitle.text = "ДОХОДЫ И СОДЕРЖАНИЕ  ·  РУСЬ"
	var summary: Dictionary = world.faction_finances(0)
	var metrics := row()
	metric(metrics,"Серебро",str(campaign.factions[0].silver),"coin")
	metric(metrics,"За следующий ход","%+d" % summary.net,"scroll")
	metric(metrics,"Содержание войск",str(summary.upkeep),"helm")
	metric(metrics,"Содержание зданий",str(summary.building_upkeep),"hammer")
	section("Ресурсы провинций")
	for province_id in Geo.PROVINCES.size():
		var local: Dictionary=world.province_finances(0,province_id)
		if local.cities==0: continue
		line("%s · города: %d · население %d · еда %+d (%d − %d)" % [Geo.PROVINCES[province_id][0],local.cities,local.manpower,local.food,local.food_produced,local.food_used],17)
	section("Подати с земель")
	for id in Geo.CITIES:
		if campaign.owner(id)!=0: continue
		var stats: Dictionary = campaign.town_yield(id)
		var entry := row()
		UI.label(entry,Geo.CITIES[id][0],23,UI.BONE,true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(entry,"%d серебра      %+d пищи" % [stats.silver,stats.food],18,UI.BRASS)
	var taxes := flow()
	for i in 3: make_button(taxes,["Низкие подати","Умеренные подати","Высокие подати"][i],tax_rate.bind(i),active and campaign.factions[0].tax!=i)
	line("Высокие подати увеличивают доход и снижают общественный порядок.",16)

func knowledge(campaign, active: bool) -> void:
	header.text = "Знания и ремёсла"
	var state: Dictionary = campaign.factions[0]
	var status := "ИССЛЕДОВАНИЕ СВОБОДНО" if campaign.research_idle(0) else "ВСЕ ЗНАНИЯ ИЗУЧЕНЫ"
	if not state.research.is_empty():
		status = "%s  ·  ОСТАЛОСЬ %d ХОД." % [Data.TECH[state.research.key].name.to_upper(),state.research.turns]
	subtitle.text = "%s  ·  В КАЗНЕ %d СЕРЕБРА" % [status,state.silver]
	line("Изучено %d из %d  ·  До полного дерева %d ход. исследований" % [state.tech.size(),Data.TECH.size(),campaign.research_turns_remaining(0)],17)
	var branches := row()
	for branch in Data.TECH_BRANCHES:
		var column := tile(branches,470)
		section(branch.name,column)
		knowledge_card(column,campaign,branch.root,active)
		var paths := GridContainer.new()
		paths.columns = 2
		paths.add_theme_constant_override("h_separation",8)
		column.add_child(paths)
		for tier in branch.tiers:
			for key in tier:
				var arrow := UI.label(paths,"↓",17,UI.BRASS)
				arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			for key in tier:
				knowledge_card(paths,campaign,key,active)

func knowledge_card(parent: Node, campaign, key: String, active: bool) -> void:
	var state: Dictionary = campaign.factions[0]
	var item: Dictionary = Data.TECH[key]
	var card := tile(parent,0)
	var heading := row(card)
	var icon := texture_picture(heading,UI.research_icon(key),38,38)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var title := line(item.name,21,heading)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var effect := line(item.effect % item.bonus,16,card)
	if not item.requires.is_empty():
		effect.custom_minimum_size.y = 57
		var requirement := line("После «%s»" % Data.TECH[item.requires].name,14,card)
		requirement.add_theme_color_override("font_color",UI.BRASS)
	var issue: String = campaign.research_issue(0,key)
	var caption := "Изучить за %d серебра" % item.cost
	if key in state.tech:
		caption = "Изучено"
	elif state.research.get("key","") == key:
		caption = "Изучается  ·  %d ход." % state.research.turns
	else:
		var duration := line("Срок · %d ход." % item.turns,14,card)
		duration.add_theme_color_override("font_color",UI.BRASS)
	var button := make_button(card,caption,research.bind(key),active and issue.is_empty())
	button.tooltip_text = ("Исследовать «%s»" % item.name) if issue.is_empty() else issue

func dynasty(campaign, active: bool) -> void:
	var leader: Dictionary = campaign.leaders[0]
	var faction: Dictionary = campaign.factions[0]
	header.text = "Княжеский род"
	subtitle.text = "ВЛАСТЬ  ·  НАСЛЕДОВАНИЕ  ·  СВИТА"
	var lineage := row()
	picture(lineage,campaign.leader_portrait(0),185,199)
	var history := VBoxContainer.new()
	history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lineage.add_child(history)
	UI.label(history,leader.name,37,UI.BONE,true)
	line("%d лет  ·  Ранг %d  ·  Опыт %d" % [leader.age,1+floori(leader.xp/100.0),leader.xp],19,history)
	line("Наследник: "+leader.heir,21,history)
	line("Черта: "+(leader.trait if not leader.trait.is_empty() else "Ещё не проявилась"),17,history)
	line("Свита: "+(leader.retinue if not leader.retinue.is_empty() else "Не назначена"),17,history)
	var influence := row()
	metric(influence,"Влияние рода","%d%%" % faction.influence,"tree")
	metric(influence,"Лояльность знати","%d%%" % faction.loyalty,"shield")
	var actions := flow()
	make_button(actions,"Назначить советника · 80 серебра",patronage,active and faction.silver>=80)
	make_button(actions,"Наставник · 100 опыта",perk.bind("skill","Наставник"),active and leader.xp>=100 and leader.skill.is_empty())
	make_button(actions,"Ветераны · 200 опыта",perk.bind("tradition","Ветераны"),active and leader.xp>=200 and leader.tradition.is_empty())
	if not leader.skill.is_empty() or not leader.tradition.is_empty(): line("Навык: %s  ·  Традиция: %s" % [leader.skill,leader.tradition])
	for former in leader.get("ancestors",[]): line("Предшественник: %s · %d лет" % [former.name,former.age],17)

func chronicle(campaign) -> void:
	header.text = "Повесть наших лет"
	subtitle.text = "ЦЕЛИ КАМПАНИИ И ЛЕТОПИСЬ СОБЫТИЙ"
	for stage in world.STORY_ORDERS:
		if stage > world.story_stage: continue
		if stage == world.StoryStage.CAPTURE_LADOGA:
			section("Глава I · Новгородская земля")
		elif stage == world.StoryStage.CAPTURE_SMOLENSK:
			line("Олег · «Холм взят. Оставьте дозоры на дорогах, а остальным дайте отдохнуть».")
			section("Глава II · " + world.SMOLENSK_CHAPTER)
		var order: Dictionary = world.STORY_ORDERS[stage]
		var status := "Выполнено" if stage < world.story_stage else "Сюжетная цель"
		section("%s · %s" % [status,order.title])
		line(order.speech)
	var owned: int = world.forces.holdings.size()
	var funds: Dictionary = world.faction_finances(0)
	var assimilated := 0
	for id in world.forces.holdings:
		if campaign.cities[id].culture==0: assimilated += 1
	var goals := row()
	for goal in [["Собрать русские земли","Киев и все %d регионов" % Geo.CITIES.size(),"%d / %d" % [owned,Geo.CITIES.size()]],["Богатая держава","1800 серебра · +80 дохода · +25 пищи","Достигнуто" if campaign.factions[0].silver>=1800 and funds.net>=80 and funds.food>=25 else "В процессе"],["Единая культура","9 регионов культуры Руси","%d / 9" % assimilated]]:
		var column := tile(goals,320)
		UI.label(column,goal[0],26,UI.BONE,true)
		line(goal[1],16,column)
		UI.label(column,goal[2],31,UI.RED,true)
	section("Летопись")
	if campaign.journal.is_empty():
		line("%s %d года. Дружина Олега стоит у Новгорода. Путь на юг открыт." % [
			world.MONTH_NAMES[world.START_MONTH_INDEX],world.START_YEAR],18)
	for event in campaign.journal: line(event,18)

func report(ok: bool) -> void:
	if ok: world.refresh_ui()
	else:
		feedback.text = "Действие недоступно. Проверьте средства, свободные места и требования."
		feedback.show()

func select_town(id: String) -> void:
	if not world.fog.visible_at(Geo.position_of(id)) and world.campaign.owner(id)!=0: return
	settlement_view = id
	world.selected_city = id
	world.refresh_ui()

func build(id: String, key: String, action: String, branch := -1) -> void:
	var reasons := construction_issues(world.campaign,id,key,world.player_orders_allowed(),action,branch)
	if not reasons.is_empty():
		feedback.text = "\n".join(reasons)
		feedback.show()
		return
	var ok: bool = world.campaign.build(0,id,key,action,branch)
	if ok:
		if action == "build":
			if construction_audio.stream == null: construction_audio.stream = load(CONSTRUCTION_SOUND)
			construction_audio.play()
		world.refresh_garrison(id)
		world.sync_settlement_models()
	report(ok)

func cancel(id: String) -> void:
	if world.player_orders_allowed() and world.campaign.owner(id)==0:
		world.campaign.cancel_build(id)
		world.sync_settlement_models()
		report(true)

func recruit(id: String, key: String, garrison: bool) -> void:
	var blockers := recruit_blockers(recruitment_checks(id,key,garrison))
	if not blockers.is_empty():
		feedback.text = "\n".join(blockers)
		feedback.show()
		return
	var index: int = world.commanded_army
	var roster: Array = world.forces.garrisons[id] if garrison else world.forces.armies[index]
	var ok: bool = world.campaign.recruit(0,id,key,roster,garrison)
	if ok and not garrison:
		world.movement = minf(world.movement,world.MOVE_PER_TURN*world.stance_movement())
	report(ok)
	world.armies[index].visible = not world.forces.armies[index].is_empty()

func hire_hero(id: String) -> void:
	if not world.recruit_hero(id): report(false)

func raise_player_army() -> void:
	report(world.player_orders_allowed() and world.raise_army(world.commanded_army))

func choose_stance(value: String) -> void:
	if world.player_orders_allowed():
		world.campaign.stances[world.commanded_army] = value
		world.movement = minf(world.movement,world.MOVE_PER_TURN*world.stance_movement())
		report(true)

func tax_rate(rate: int) -> void:
	if world.player_orders_allowed():
		world.campaign.factions[0].tax = rate
		report(true)

func choose_advisor(id: String, strategy: String) -> void:
	report(world.player_orders_allowed() and world.campaign.set_advisor(id,strategy))

func confirm_disband(city: String, unit: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Распустить отряд"
	dialog.dialog_text = "Распустить «%s» (%d воинов)?" % [world.Forces.squad_name(unit),unit.count]
	dialog.ok_button_text = "Распустить"
	dialog.cancel_button_text = "Отмена"
	var unit_id: String = unit.id
	dialog.confirmed.connect(func():
		if not world.disband_unit(city,unit_id): report(false)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func distribute_relief(id: String) -> void:
	report(world.player_orders_allowed() and world.campaign.distribute_relief(0,id))

func research(key: String) -> void:
	report(world.player_orders_allowed() and world.campaign.research(0,key))

func edict(p: int, key: String) -> void:
	report(world.player_orders_allowed() and world.campaign.edict(0,p,key))

func patronage() -> void:
	report(world.player_orders_allowed() and world.campaign.patronage(0))

func perk(key: String, value: String) -> void:
	if world.player_orders_allowed():
		world.campaign.leaders[0][key] = value
		report(true)
