extends Control
## Telefon gorunumlu harita: kaydir, yakinlastir, bir yere dokun ve kopek oraya yurusun.

signal place_chosen(p: Vector2)

const MAP_WORLD := 100.0   # harita gorselinin kapladigi alan (metre)
const MAP_PX := 1024.0
const BROWN := Color("5a4636")

# ad, haritadaki yer, varis noktasi, renk
const PINS := [
	["Ev", Vector2(0, -36), Vector2(0, -30), "e2574c"],
	["Çeşme Meydanı", Vector2(0, 0), Vector2(0, 4.5), "4f8fd9"],
	["Gölet", Vector2(-29, -7), Vector2(-39.5, -6), "38b6c9"],
	["Ahşap Köprü", Vector2(-28, 7), Vector2(-24.5, 7), "b9824f"],
	["Köpek Oyun Alanı", Vector2(32, 8), Vector2(27, 6), "ffb347"],
	["Dondurmacı", Vector2(18, 16), Vector2(15.4, 14.2), "ff7fb0"],
	["Çiçek Bahçesi", Vector2(22, -16), Vector2(18.6, -14.2), "b48be8"],
	["Piknik Alanı", Vector2(-16, -20), Vector2(-14, -18), "8fce5a"],
	["Seyir Tepesi", Vector2(6, 32), Vector2(7, 33.2), "5fb3a8"],
	["Kır Çiçekleri", Vector2(-14, 20), Vector2(-12, 18), "ffd84d"],
]

var _view: Control
var _canvas: Control
var _me: Control
var _pins: Array[Control] = []
var _zoom := 1.0
var _zoom_min := 0.6
var _touches := {}
var _moved := 0.0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.06, 0.5)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)

	var phone := _panel(Color("2d2a33"), 60, self)
	phone.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	phone.offset_left = 34
	phone.offset_right = -34
	phone.offset_top = 100
	phone.offset_bottom = -100
	var screen := _panel(Color("fff8ec"), 46, phone)
	screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_inset(screen, 16, 16, 16, 16)
	var notch := _panel(Color("2d2a33"), 12, screen)
	notch.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	notch.offset_left = -60
	notch.offset_right = 60
	notch.offset_top = 0
	notch.offset_bottom = 22

	var title := _label("Papatya Parkı", 34, screen)
	title.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	title.offset_top = 34
	title.offset_bottom = 84
	var close := _round_button("×", Color("e2574c"), screen, func(): visible = false)
	close.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	close.offset_left = -84
	close.offset_right = -20
	close.offset_top = 26
	close.offset_bottom = 90

	_view = _panel(Color("7cc3d8"), 30, screen)
	_view.clip_contents = true
	_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_inset(_view, 18, 104, 18, 84)
	_view.gui_input.connect(_on_view_input)
	_canvas = Control.new()
	_canvas.mouse_filter = MOUSE_FILTER_IGNORE
	_view.add_child(_canvas)
	var tex := TextureRect.new()
	tex.mouse_filter = MOUSE_FILTER_IGNORE
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.size = Vector2(MAP_PX, MAP_PX)
	if ResourceLoader.exists("res://assets/park_map.png"):
		tex.texture = load("res://assets/park_map.png")
	_canvas.add_child(tex)

	for p in PINS:
		var pin := Control.new()
		pin.mouse_filter = MOUSE_FILTER_IGNORE
		pin.position = _to_px(p[1])
		var dot := _panel(Color(p[3]), 19, pin, 5)
		dot.position = Vector2(-19, -19)
		dot.size = Vector2(38, 38)
		var l := _label(p[0], 22, pin)
		l.position = Vector2(-150, 20)
		l.size = Vector2(300, 30)
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_color_override("font_outline_color", Color.WHITE)
		_canvas.add_child(pin)
		_pins.append(pin)
	_me = Control.new()
	_me.mouse_filter = MOUSE_FILTER_IGNORE
	var paw := _panel(Color("ff8a3c"), 15, _me, 5)
	paw.position = Vector2(-15, -15)
	paw.size = Vector2(30, 30)
	var ml := _label("Buradasın", 20, _me)
	ml.position = Vector2(-150, -48)
	ml.size = Vector2(300, 28)
	ml.add_theme_constant_override("outline_size", 8)
	ml.add_theme_color_override("font_outline_color", Color.WHITE)
	_canvas.add_child(_me)

	var plus := _round_button("+", Color("5a4636"), _view, func(): _zoom_at(1.3, _view.size * 0.5))
	var minus := _round_button("−", Color("5a4636"), _view, func(): _zoom_at(1.0 / 1.3, _view.size * 0.5))
	for i in 2:
		var b: Button = [plus, minus][i]
		b.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
		b.offset_left = -78
		b.offset_right = -14
		b.offset_top = -150 + i * 70
		b.offset_bottom = -86 + i * 70

	var hint := _label("Bir yere dokun, köpeğin oraya yürüsün", 22, screen)
	hint.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	hint.offset_top = -66
	hint.offset_bottom = -26


func open(player_pos: Vector2) -> void:
	visible = true
	_me.position = _to_px(player_pos)
	await get_tree().process_frame
	_zoom_min = maxf(_view.size.x, _view.size.y) / MAP_PX
	_zoom = _zoom_min * 1.45
	_canvas.position = _view.size * 0.5 - _me.position * _zoom
	_apply()


func _to_px(w: Vector2) -> Vector2:
	return (w / MAP_WORLD + Vector2(0.5, 0.5)) * MAP_PX


func _apply() -> void:
	_zoom = clampf(_zoom, _zoom_min, _zoom_min * 4.0)
	_canvas.scale = Vector2.ONE * _zoom
	var lo := _view.size - Vector2(MAP_PX, MAP_PX) * _zoom
	_canvas.position = _canvas.position.clamp(lo, Vector2.ZERO)
	# Simgeler ekranda ayni boyda kalir; isimler yakinlastirinca gorunur
	var names := _zoom > _zoom_min * 1.25
	for pin in _pins:
		pin.scale = Vector2.ONE / _zoom
		pin.get_child(1).visible = names
	_me.scale = Vector2.ONE / _zoom


func _zoom_at(factor: float, pivot: Vector2) -> void:
	var before := (pivot - _canvas.position) / _zoom
	_zoom = clampf(_zoom * factor, _zoom_min, _zoom_min * 4.0)
	_canvas.position = pivot - before * _zoom
	_apply()


func _on_view_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_moved = 0.0
		else:
			_touches.erase(e.index)
			if _touches.is_empty() and _moved < 14.0:
				_tap(e.position)
	elif e is InputEventScreenDrag and _touches.has(e.index):
		if _touches.size() >= 2:
			var other: Vector2 = _touches[1 - e.index] if _touches.has(1 - e.index) else e.position
			var before: float = maxf(other.distance_to(_touches[e.index]), 1.0)
			_zoom_at(maxf(other.distance_to(e.position), 1.0) / before, (other + e.position) * 0.5)
			_moved = 100.0
		else:
			_canvas.position += e.relative
			_moved += e.relative.length()
			_apply()
		_touches[e.index] = e.position
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_at(1.15, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_at(1.0 / 1.15, e.position)
		elif e.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
			if e.pressed:
				_moved = 0.0
			elif _moved < 14.0:
				_tap(e.position)
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT and not DisplayServer.is_touchscreen_available():
		_canvas.position += e.relative
		_moved += e.relative.length()
		_apply()


func _tap(pos: Vector2) -> void:
	var best := -1
	var best_d := 60.0
	for i in PINS.size():
		var d: float = (_canvas.position + _to_px(PINS[i][1]) * _zoom).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		visible = false
		place_chosen.emit(PINS[best][2])


# ---------------------------------------------------------------- parcalar

func _panel(c: Color, radius: int, parent: Control, border := 0) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(border)
		sb.border_color = Color.WHITE
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 4
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = MOUSE_FILTER_IGNORE if border > 0 else MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


func _inset(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.offset_left = l
	c.offset_top = t
	c.offset_right = -r
	c.offset_bottom = -b


func _label(text: String, size: int, parent: Control) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", BROWN)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _round_button(text: String, c: Color, parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.add_theme_font_size_override("font_size", 38)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c if state != "pressed" else c.darkened(0.2)
		sb.set_corner_radius_all(32)
		b.add_theme_stylebox_override(state, sb)
	for col in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(col, Color.WHITE)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
