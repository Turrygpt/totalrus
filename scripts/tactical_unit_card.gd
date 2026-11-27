extends Button

signal focus_requested

const UI = preload("res://campaign_map/ui_theme.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")
const Experience = preload("res://scripts/unit_experience.gd")
const Equipment = preload("res://scripts/unit_equipment.gd")
const Squad = preload("res://scripts/squad.gd")
const NAMES := {
	"militia":"Ополченцы", "infantry":"Копейщики", "archer":"Лучники",
	"cavalry":"Тяж. конница", "light_cavalry":"Лёгк. конница", "princely":"Княжеская дружина", "varangian":"Варяги", "khazar":"Хазары",
}
const STRENGTH := Color("9aab78")
const WARNING := Color("e7be75")
const RETREAT := Color("eda087")
const OUT := Color("c0bcaf")

var squad: Node3D
var compact := false
var artwork: Texture2D
var caption := ""
var in_focus := false
var living := -1
var order := ""
var mood := ""
var state_color := UI.BONE
var rank := 0
var stamina := 100

func _ready() -> void:
	name = "SquadCard%d" % squad.serial
	custom_minimum_size = Vector2(77,96) if compact else Vector2(114,148)
	caption = NAMES.get(squad.unit_kind,squad.display_name)
	artwork = UI.art(squad.unit_kind)
	if not squad.commander_portrait.is_empty():
		artwork = UI.art(squad.commander_portrait)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_ARROW if compact else Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	tooltip_text = caption
	refresh(squad.selected)

static func order_text(group: Node3D) -> String:
	if group.surrendered:
		return "Сдались"
	if group.alive_count() == 0:
		return "Уничтожен"
	if group.routed:
		return group.morale_state()
	if not group.pending_order.is_empty():
		return "Приказ принят"
	return group.state_text

static func morale_text(group: Node3D) -> String:
	if group.alive_count() > 0 and group.berserk_remaining > 0:
		return "Берсерк · %d с" % ceili(group.berserk_remaining)
	if group.routed and not group.surrendered and group.alive_count() > 0:
		return "Мораль %d%% · Приказы недоступны" % floori(group.morale)
	if group.alive_count() == 0 or group.morale >= group.WAVER_THRESHOLD:
		return "Воодушевлены" if group.alive_count() > 0 and not group.routed and group.inspired_remaining > 0 else ""
	var amount := floori(group.morale)
	if group.routed:
		return "Мораль %d%%" % amount
	return "Дрогнули · %d%%" % amount

static func condition_color(group: Node3D) -> Color:
	if group.alive_count() == 0 or group.surrendered:
		return OUT
	if group.routed:
		return RETREAT
	if group.berserk_remaining > 0 or group.inspired_remaining > 0:
		return WARNING
	if group.morale < group.WAVER_THRESHOLD:
		return WARNING
	return UI.BONE

func refresh(selected: bool) -> void:
	var current_living: int = squad.alive_count()
	var current_order := order_text(squad)
	var current_mood := morale_text(squad)
	var current_color := condition_color(squad)
	var current_stamina := ceili(squad.stamina)
	if living == current_living and current_order == order and current_mood == mood and state_color == current_color and in_focus == selected and rank == squad.experience_rank and stamina == current_stamina:
		return
	living = current_living
	order = current_order
	mood = current_mood
	state_color = current_color
	in_focus = selected
	rank = squad.experience_rank
	stamina = current_stamina
	queue_redraw()

func _get_tooltip(_at_position: Vector2) -> String:
	var title: String = squad.display_name
	if not squad.commander_portrait.is_empty(): title += " · " + caption
	var hint := "%s · %d / %d\n%s" % [title,living,squad.unit_count,order]
	if squad.behavior_controlled:
		hint += "\n" + Squad.BEHAVIOR_NAMES[squad.behavior]
	hint += "\n" + Experience.description(squad.experience_points,squad.unit_kind)
	hint += "\n" + Equipment.description(squad.equipment)
	if not mood.is_empty():
		hint += "\n" + mood
	if living > 0 and not squad.surrendered:
		hint += "\nВыносливость %d%%" % stamina
		if squad.morale_bonus > 0.0:
			hint += "\nСтойкость от исследований +%d" % squad.morale_bonus
		if squad.armor_reduction > 0.0:
			hint += "\nУрон по телу от исследований −%d%%" % roundi(squad.armor_reduction * 100.0)
		if squad.stamina_discount > 0.0:
			hint += "\nРасход выносливости от исследований −%d%%" % roundi(squad.stamina_discount * 100.0)
	if living > 0 and (squad.is_ranged() or squad.can_throw_spears()):
		var ammunition := "Стрелы" if squad.is_ranged() else "Метательные копья"
		hint += "\n%s: %d" % [ammunition,squad.ammo_count()]
	if living > 0 and not compact:
		hint += "\nДвойной щелчок — к отряду"
	return hint

func _gui_input(event: InputEvent) -> void:
	if not compact and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click and living > 0:
		focus_requested.emit()

func _draw() -> void:
	var accent := UI.BRASS
	if in_focus:
		accent = Color("e3c07c")
	elif is_hovered():
		accent = UI.BONE
	var frame := Rect2(Vector2.ZERO,size)
	draw_colored_polygon(Chrome.chamfer(frame,5),UI.IRON_DARK)
	var wrap_caption: bool = compact and squad.unit_kind == "princely"
	var caption_height := 25 if wrap_caption else 19
	var art_height := size.y - (19 if compact else 25) - caption_height
	var image_rect := Rect2(3,3,size.x-6,art_height)
	if artwork:
		var tint := Color(.45,.42,.38) if living == 0 else Color(.74,.71,.67) if squad.surrendered else Color.WHITE
		UI.draw_card_art(self,artwork,image_rect,tint,true)
	else:
		draw_rect(image_rect,UI.PAPER)
	var badge := Rect2(3,3,30,20) if compact else Rect2(3,3,39,25)
	draw_rect(badge,UI.IRON_DARK if not in_focus else UI.RED)
	draw_string(UI.FONT,Vector2(3,18 if compact else 22),str(living),HORIZONTAL_ALIGNMENT_CENTER,badge.size.x,15 if compact else 18,UI.BONE)
	UI.draw_experience(self,Vector2(size.x-28,3),rank)
	UI.draw_equipment(self,Vector2(size.x-28,29),squad.equipment)
	var strength_width := size.x - 6
	draw_rect(Rect2(3,art_height,strength_width,4),Color("43463b"))
	var strength := clampf(float(living) / maxf(1,squad.unit_count),0,1)
	var bar_color := STRENGTH if strength >= .5 else Color("c19b62")
	draw_rect(Rect2(3,art_height,strength_width*strength,4),bar_color)
	if living > 0 and not squad.surrendered and stamina < 98:
		draw_rect(Rect2(3,art_height-3,strength_width,2),UI.IRON_DARK)
		draw_rect(Rect2(3,art_height-3,strength_width*stamina*.01,2),Color("d1ae72"))
	draw_rect(Rect2(3,art_height+4,strength_width,caption_height),UI.PAPER if living > 0 else Color("a29a83"))
	if wrap_caption:
		draw_string(UI.FONT,Vector2(4,art_height+14),caption.get_slice(" ",0),HORIZONTAL_ALIGNMENT_CENTER,size.x-8,11,UI.INK)
		draw_string(UI.FONT,Vector2(4,art_height+25),caption.get_slice(" ",1),HORIZONTAL_ALIGNMENT_CENTER,size.x-8,11,UI.INK)
	else:
		var caption_size := 12 if squad.unit_kind == "princely" else 14
		draw_string(UI.FONT,Vector2(4,art_height+18),caption,HORIZONTAL_ALIGNMENT_CENTER,size.x-8,caption_size,UI.INK)
	var shown_status := order if mood.is_empty() or squad.routed else mood
	var font_size := 13 if size.x >= 100 else 12
	if UI.FONT.get_string_size(shown_status,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > size.x-8:
		shown_status = shown_status.get_slice(" ",0)
	draw_string(UI.FONT,Vector2(4,size.y-7),shown_status,HORIZONTAL_ALIGNMENT_CENTER,size.x-8,font_size,state_color)
	draw_polyline(Chrome.chamfer(frame.grow(-1),5),accent,2 if in_focus else 1,true)
	draw_polyline(Chrome.chamfer(frame.grow(-3),4),accent.darkened(.50),1.0,true)
