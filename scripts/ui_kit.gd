extends RefCounted
## Arayuz parcalari icin ortak yardimcilar ve renkler.

const Icon = preload("res://scripts/icon.gd")

const CREAM := Color("fff8ec")
const SOFT := Color("efe4cf")
const BROWN := Color("5a4636")
const MUTED := Color("9a8672")
const ORANGE := Color("f29f4b")
const GREEN := Color("6aa84f")
const RED := Color("d9523f")
const BLUE := Color("4f8fd9")
const GOLD := Color("e9b93a")


static func style(bg: Color, radius := 24, border := 0, border_color := Color.WHITE, shadow := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = border_color
	if shadow > 0:
		sb.shadow_color = Color(0.2, 0.12, 0.05, 0.22)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, shadow * 0.5)
	return sb


static func panel(parent: Node, bg := CREAM, radius := 24, border := 0, border_color := Color.WHITE, shadow := 0) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", style(bg, radius, border, border_color, shadow))
	parent.add_child(p)
	return p


static func box(parent: Node, bg := CREAM, radius := 24, pad := 16, shadow := 0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := style(bg, radius, 0, Color.WHITE, shadow)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


static func label(parent: Node, text: String, size := 24, color := BROWN, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func outline(l: Label, size := 8, c := Color.WHITE) -> Label:
	l.add_theme_constant_override("outline_size", size)
	l.add_theme_color_override("font_outline_color", c)
	return l


## Simgeli ve/veya yazili dugme.
static func button(parent: Node, text: String, icon: String, cb: Callable, bg := CREAM, fg := BROWN,
		min_size := Vector2(120, 72), font := 24, radius := 26, vertical := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.add_theme_stylebox_override("normal", style(bg, radius, 0, Color.WHITE, 6))
	b.add_theme_stylebox_override("hover", style(bg.lightened(0.05), radius, 0, Color.WHITE, 6))
	b.add_theme_stylebox_override("pressed", style(bg.darkened(0.12), radius, 0, Color.WHITE, 2))
	b.add_theme_stylebox_override("disabled", style(bg.lerp(Color("bdb5a8"), 0.7), radius))
	b.pressed.connect(cb)
	var row: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4 if vertical else 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(row)
	if icon != "":
		var ic := Icon.new(icon, fg, font * (1.5 if vertical else 1.25))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.set_meta("bg", bg)
		row.add_child(ic)
	if text != "":
		var l := label(row, text, font if not vertical else int(font * 0.8), fg, HORIZONTAL_ALIGNMENT_CENTER)
		l.name = "Text"
	parent.add_child(b)
	return b


static func set_text(b: Button, text: String) -> void:
	var l := b.find_child("Text", true, false)
	if l:
		(l as Label).text = text


static func bar(parent: Node, color: Color, min_size := Vector2(80, 12)) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = min_size
	pb.add_theme_stylebox_override("background", style(Color(0.35, 0.27, 0.2, 0.18), 6))
	pb.add_theme_stylebox_override("fill", style(color, 6))
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pb)
	return pb


static func full(c: Control, l := 0.0, t := 0.0, r := 0.0, b := 0.0) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = -r
	c.offset_bottom = -b
