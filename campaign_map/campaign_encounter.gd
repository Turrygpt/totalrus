extends RefCounted
const UI = preload("res://campaign_map/ui_theme.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")
const HEADER_ART := "res://assets/ui/birch/battle_council_header.png"

static func frame() -> StyleBoxFlat:
	return UI.campaign_frame(18)

static func render(world, column: VBoxContainer) -> void:
	if world.campaign_defeated:
		UI.label(column,"Кампания проиграна",40,UI.BONE,true)
		UI.label(column,"Все города потеряны, все воеводы пали",22,UI.BONE)
		var summary: Dictionary = world.battle_summary
		if summary.get("title","") == "Кампания проиграна" and summary.has("own_losses"):
			UI.label(column,"Потери Руси: %d · противника: %d" % [summary.own_losses,summary.enemy_losses],18,UI.BRASS)
		world.button(column,"Новая кампания",world.restart_campaign)
		return
	if not world.pending_capture.is_empty():
		UI.label(column,"Город взят",15,UI.BRASS)
		UI.label(column,world.Geo.CITIES[world.pending_capture][0],40,UI.BONE,true)
		var town := TextureRect.new()
		town.texture = UI.art("town")
		town.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		town.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		town.custom_minimum_size.y = 160
		column.add_child(town)
		UI.label(column,"После захвата наём и стройка ждут восстановления порядка.",17,UI.BRASS)
		UI.label(column,"Население присоединяется к запасу провинции постепенно.",17,UI.BRASS)
		world.button(column,"Занять   ·   здания целы   ·   восстановление 2 хода",world.settle_capture.bind("occupy"))
		world.button(column,"Взять добычу   ·   +180 серебра   ·   восстановление 4 хода",world.settle_capture.bind("loot"))
		world.button(column,"Разорить   ·   уничтожить постройки   ·   восстановление 5 ходов",world.settle_capture.bind("raze"))
		return
	if world.encounter.is_empty() and not world.battle_summary.is_empty():
		var summary: Dictionary = world.battle_summary
		UI.label(column,summary.title,40,UI.BONE,true)
		UI.label(column,summary.target,22,UI.BONE)
		UI.label(column,"Потери Руси: %d · противника: %d" % [summary.own_losses,summary.enemy_losses],18,UI.BRASS)
		if summary.get("time_expired",false): UI.label(column,"Время вышло. Победила оборона.",18,UI.BONE)
		if summary.has("siege_lifted"):
			UI.label(column,"Осада снята · "+summary.siege_lifted,18,UI.BONE)
		for notice in summary.get("faction_defeats",[]):
			UI.label(column,notice,18,UI.BRASS)
		world.button(column,"Продолжить",func():
			world.battle_summary.clear()
			world.show_battle_menu())
		return
	var encounter: Dictionary = world.encounter
	add_heading(column,encounter.title)
	var order: Dictionary = world.story_order()
	if (encounter.city_battle and not encounter.enemy_attack and not order.is_empty()
			and encounter.city == order.city and encounter.banner_factions[1] == order.defender_faction):
		var reply := UI.label(column,order.reply,17,UI.BRASS)
		reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var besieged_city: String = encounter.get("besieged_city","")
	if not besieged_city.is_empty():
		var siege := UI.label(column,"Нападение на осаждающую дружину · "+world.Geo.CITIES[besieged_city][0],17,UI.BRASS)
		siege.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation",10)
	column.add_child(sides)
	var own: int = world.forces.headcount(encounter.attackers)
	var enemy: int = world.forces.headcount(encounter.defenders)
	var factions: Array = encounter.banner_factions
	var names: Array = encounter.commander_names
	var portraits: Array = encounter.commander_portraits
	var own_faction: Dictionary = world.Geo.FACTIONS[factions[0]]
	var enemy_faction: Dictionary = world.Geo.faction_appearance(factions[1], encounter.city)
	army_side(sides,own_faction,names[0],own,portraits[0],UI.faction_flag(factions[0]),false)
	var versus := UI.label(sides,"×",38,UI.BRASS,true)
	versus.custom_minimum_size.x = 28
	versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	versus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	army_side(sides,enemy_faction,names[1],enemy,portraits[1],UI.faction_flag(factions[1], encounter.city),true)
	var comparison := VBoxContainer.new()
	comparison.add_theme_constant_override("separation",5)
	column.add_child(comparison)
	var support: Array = encounter.get("support",[])
	var initial := [own,enemy]
	for source in support:
		if not source.get("opening",false):
			initial[source.team] -= world.forces.headcount(source.roster)
	var comparison_text := "Численность сторон"
	if initial != [own,enemy]:
		comparison_text = "Всего с подмогой · на поле в начале %d × %d" % initial
	var caption := UI.label(comparison,comparison_text,13,UI.BRASS)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var strength := ProgressBar.new()
	strength.show_percentage = false
	strength.max_value = own+enemy
	strength.value = own
	strength.custom_minimum_size.y = 9
	strength.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strength.add_theme_stylebox_override("background",UI.box(enemy_faction.color.lightened(.12),Color.TRANSPARENT,0))
	strength.add_theme_stylebox_override("fill",UI.box(own_faction.color.lightened(.12),Color.TRANSPARENT,0))
	comparison.add_child(strength)
	if encounter.city_battle and not encounter.enemy_attack:
		var siege_status := UI.label(column,"До сдачи при осаде · %d ход." % world.siege_turns_remaining(encounter.city),17,UI.BONE)
		siege_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if encounter.city_battle:
		show_garrison_roster(column,encounter.garrison,"Гарнизон · "+world.Geo.CITIES[encounter.city][0])
	show_nearby_sources(world,column,support)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",9)
	column.add_child(actions)
	var fight := action_button(world,actions,"Атаковать" if not encounter.enemy_attack else "Сражаться",world.begin_manual_battle,true)
	fight.icon = UI.icon("sword")
	fight.expand_icon = true
	fight.add_theme_constant_override("icon_max_width",21)
	var resolve := action_button(world,actions,"Авторасчёт",world.resolve_automatically)
	resolve.tooltip_text = "Рассчитать исход и потери на карте"
	if encounter.city_battle and not encounter.enemy_attack:
		action_button(world,actions,"Продолжить осаду" if world.campaign.sieges.has(encounter.city) else "Взять в осаду",world.maintain_siege)
	var retreat := action_button(world,actions,"Отступить",world.withdraw_encounter)
	retreat.size_flags_stretch_ratio = .68
	retreat.disabled = not encounter.get("retreat_allowed",true)
	if retreat.disabled:
		retreat.tooltip_text = "При обороне города отступить нельзя." if encounter.get("defending_city",false) else "Этот воевода уже отступал в текущем ходу."

static func show_nearby_sources(world, column: VBoxContainer, support: Array) -> void:
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",4)
	var participating := {}
	for team in 2:
		var sources := support.filter(func(source): return source.team == team)
		if sources.is_empty(): continue
		UI.label(rows,"Наша подмога" if team == 0 else "Вражеская подмога",16,UI.BRASS,true)
		for source in sources:
			var id: Variant = source.city if source.has("city") else source.army
			participating[id] = true
			var timing := "на поле с начала боя" if source.get("opening",false) else "прибытие через 2 мин."
			var detail := "%d воинов · %s" % [world.forces.headcount(source.roster),timing]
			add_nearby_source(world,rows,source,detail)
	for source in world.nearby_battle_sources():
		var is_city: bool = source.has("city")
		var id: Variant = source.city if is_city else source.army
		if participating.has(id): continue
		if is_city and not world.fog.visible_at(world.Geo.position_of(id)): continue
		if not is_city and not world.can_see_army(id): continue
		var detail: String = world.Geo.FACTIONS[source.faction].name + " · вне боя"
		if is_city and world.campaign.sieges.has(id):
			detail = "в осаде · вне боя"
		add_nearby_source(world,rows,source,detail)
	if rows.get_child_count() == 0:
		rows.free()
		return
	UI.label(column,"Рядом с полем боя",17,UI.BONE,true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	scroll.add_child(rows)
	scroll.custom_minimum_size.y = minf(230.0,rows.get_combined_minimum_size().y)

static func add_nearby_source(world, rows: VBoxContainer, source: Dictionary, detail: String) -> void:
	var name: String = "Город %s" % world.Geo.CITIES[source.city][0] if source.has("city") else "Воевода %s" % source.name
	var entry := UI.label(rows,"%s · %s" % [name,detail],16,UI.BONE)
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

static func show_garrison_roster(column: VBoxContainer, roster: Array, title: String) -> void:
	var total := 0
	for unit in roster: total += unit.count
	UI.label(column,"%s · %d воинов" % [title,total],18,UI.BRASS)
	var detail := UI.label(column,roster_composition(roster),16,UI.BONE)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

static func roster_composition(roster: Array) -> String:
	var kinds := {}
	for unit in roster:
		if unit.count <= 0: continue
		kinds[unit.title] = kinds.get(unit.title,0)+unit.count
	var entries := PackedStringArray()
	for unit_name in kinds:
		entries.append("%s — %d" % [unit_name,kinds[unit_name]])
	return " · ".join(entries) if not entries.is_empty() else "Гарнизон пуст"

static func add_heading(parent: Node, value: String) -> void:
	var trim := PanelContainer.new()
	trim.add_theme_stylebox_override("panel",UI.box(Color("e9dcc2"),Color("9b8051"),1))
	parent.add_child(trim)
	var header := Control.new()
	header.custom_minimum_size.y = 125
	header.clip_contents = true
	trim.add_child(header)
	if ResourceLoader.exists(HEADER_ART):
		var landscape := TextureRect.new()
		var art := AtlasTexture.new()
		art.atlas = load(HEADER_ART)
		var source := art.atlas.get_size()
		art.region = Rect2(0,source.y * .38,source.x,source.y * .62)
		art.filter_clip = true
		landscape.texture = art
		landscape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		landscape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		landscape.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(landscape)
		landscape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation",2)
	header.add_child(words)
	words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := UI.label(words,"ВОЕННЫЙ СОВЕТ",13,Color("665133"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := UI.label(words,value,35,Color("302720"),true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = value

static func army_side(parent: Node, faction: Dictionary, commander: String, count: int, art_key: String, flag: Texture2D, mirrored: bool) -> void:
	var tone: Color = faction.color
	var side := PanelContainer.new()
	var style := UI.box(UI.IRON_DARK.lerp(tone,.20),UI.BRASS.darkened(.25),10)
	side.add_theme_stylebox_override("panel",style)
	Chrome.decorate(side,15)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.custom_minimum_size.x = 290
	parent.add_child(side)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	side.add_child(row)
	var photo_frame := PanelContainer.new()
	photo_frame.add_theme_stylebox_override("panel",UI.box(Color("bb9d70"),Color("bdab80"),2))
	photo_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(photo_frame)
	var portrait := TextureRect.new()
	portrait.texture = UI.art(art_key)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.custom_minimum_size = Vector2(108,112)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_frame.add_child(portrait)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation",1)
	row.add_child(text)
	if mirrored: row.move_child(photo_frame,-1)
	var alignment := HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	var name := UI.label(text,commander if not commander.is_empty() else "Гарнизон",35,UI.BONE,true)
	name.horizontal_alignment = alignment
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var realm := UI.label(text,faction.name,16,Color("c0b191"))
	realm.horizontal_alignment = alignment
	realm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var numbers := HBoxContainer.new()
	numbers.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	numbers.add_theme_constant_override("separation",6)
	text.add_child(numbers)
	var heraldry := TextureRect.new()
	heraldry.texture = flag
	heraldry.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heraldry.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heraldry.custom_minimum_size = Vector2(19,25)
	numbers.add_child(heraldry)
	UI.label(numbers,"%d воинов" % count,21,UI.BONE,true)
	if mirrored: numbers.move_child(heraldry,-1)

static func action_button(world, parent: Node, title: String, action: Callable, primary := false) -> Button:
	var button: Button = world.button(parent,title,action)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_stretch_ratio = 1.35 if primary else 1.0
	button.custom_minimum_size.y = 45
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size",20 if primary else 17)
	if primary: UI.accent_button(button)
	return button
