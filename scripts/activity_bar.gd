extends CanvasLayer
## Kisa sureli islerde (berberde kesim, spor salonunda set) ekranin altinda baslik + ilerleme cubugu.
## Kullanim: var b := ActivityBar.new(); add_child(b); b.setup("KOŞU BANDI", "Koşuyorsun…"); b.set_value(0.4)

const F_TITLE := preload("res://assets/fonts/Bangers-Regular.ttf")
const F_UI := preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const ACCENT := Color("f5c518")

var _title: Label
var _sub: Label
var _fill: ColorRect
var _back: ColorRect


func setup(title: String, sub: String) -> void:
	layer = 30
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.075, 0.095, 0.9)
	sb.border_width_top = 5
	sb.border_color = ACCENT
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 8
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = -260
	card.offset_right = 260
	card.offset_top = -150
	card.offset_bottom = -60
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	_title = _label(col, title, F_TITLE, 34, ACCENT)
	_sub = _label(col, sub, F_UI, 22, Color(1, 1, 1, 0.85))
	_back = ColorRect.new()
	_back.color = Color(1, 1, 1, 0.15)
	_back.custom_minimum_size = Vector2(480, 16)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_back)
	_fill = ColorRect.new()
	_fill.color = ACCENT
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.size = Vector2(0, 16)
	_back.add_child(_fill)


func _label(parent: Node, text: String, font: Font, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func set_value(v: float) -> void:
	if _fill:
		_fill.size = Vector2(480.0 * clampf(v, 0.0, 1.0), 16)


func set_sub(text: String) -> void:
	if _sub:
		_sub.text = text
