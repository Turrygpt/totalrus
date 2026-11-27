extends CanvasLayer

const UI = preload("res://campaign_map/ui_theme.gd")
const Chrome = preload("res://campaign_map/ui_chrome.gd")

signal retry_requested
signal cancel_requested

var heading: Label
var message: Label
var progress: ProgressBar
var actions: HBoxContainer

func _ready() -> void:
	name = "TacticalLoading"
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cover := ColorRect.new()
	cover.color = UI.IRON_DARK
	cover.theme = UI.theme()
	add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grain := Chrome.new()
	cover.add_child(grain)
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	cover.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 760
	content.add_theme_constant_override("separation",15)
	center.add_child(content)
	var title := make_label(content,22,UI.BRASS)
	title.text = "Р У С Ь   ·   В О Е Н Н Ы Й   П О Х О Д"
	var landscape := TextureRect.new()
	landscape.texture = UI.art("birch")
	landscape.custom_minimum_size.y = 270
	landscape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	landscape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(landscape)
	heading = make_label(content,39,UI.BONE)
	heading.add_theme_font_override("font",UI.DISPLAY)
	message = make_label(content,22,UI.BRASS)
	progress = ProgressBar.new()
	progress.max_value = 1.0
	progress.custom_minimum_size.y = 16
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background",UI.box(UI.IRON,UI.BRASS,0))
	progress.add_theme_stylebox_override("fill",UI.box(UI.RED,Color.TRANSPARENT,0))
	content.add_child(progress)
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation",14)
	content.add_child(actions)
	make_button("Повторить",func(): retry_requested.emit())
	make_button("Назад к карте",func(): cancel_requested.emit())

func begin(title: String) -> void:
	heading.text = title
	message.text = "Загрузка тактической сцены…"
	actions.hide()
	progress.show()
	progress.value = 0

func set_progress(value: float) -> void:
	progress.value = maxf(progress.value,value)

func preparing() -> void:
	message.text = "Развёртывание войск…"
	set_progress(0.93)

func failed() -> void:
	message.text = "Не удалось загрузить тактическую сцену"
	progress.hide()
	actions.show()

func make_label(parent: Control, size: int, color: Color) -> Label:
	var item := Label.new()
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.add_theme_font_override("font",UI.FONT)
	item.add_theme_font_size_override("font_size",size)
	item.add_theme_color_override("font_color",color)
	parent.add_child(item)
	return item

func make_button(text: String, action: Callable) -> void:
	var item := Button.new()
	item.text = text
	item.add_theme_font_size_override("font_size",22)
	item.pressed.connect(action)
	actions.add_child(item)
