extends Control
## Telefon gorunumlu harita uygulamasi: kaydir, yakinlastir, bir yer sec, "Yuru" de.

signal place_chosen(p: Vector2)
signal nav_chosen(p: Vector2, name: String)    # yalnizca yol tarifi (yurumeden)

const ParkMap = preload("res://scripts/park_map.gd")
const K = preload("res://scripts/ui_kit.gd")
const Icon = preload("res://scripts/icon.gd")
const MAP_PX := 1024.0

const SPOT_PINS := [
	["Bahçe", "bahce", Vector2(11.5, 0), "6aa84f", "bone"], ["Pet Shop", "petshop", Vector2(0, 6.5), "f29f4b", "cart"],
	["Park Kafe", "kafe", Vector2(-7, 0), "8f5a3c", "smile"], ["Dondurmacı", "dondurmaci", Vector2(0, 3), "e88fb0", "star"],
	["Çardak", "cardak", Vector2(0, 4.5), "a78bd4", "heart"], ["Çeşme", "cesme", Vector2(0, 4), "4f8fd9", "drop"],
	["Köpek Oyun Alanı", "oyun_alani", Vector2(9.5, 0), "f29f4b", "ball"], ["Piknik Alanı", "piknik", Vector2(2.5, 2), "6aa84f", "smile"],
]
const KIND_STYLE := {"park": ["4c8a3f", "heart"], "saha": ["5fb3a8", "ball"], "cami": ["4f8fd9", "moon"], "okul": ["e0b23e", "star"]}

# ad, haritadaki yer, varis noktasi, renk, simge (harita verisinden doldurulur)
var PINS: Array = []
var STREETS: Array = []

var _view: Control
var _canvas: Control
var _me: Control
var _pins: Array[Control] = []
var _streets: Array[Label] = []
var _sheet: Control
var _sheet_title: Label
var _sheet_info: Label
var _zoom := 1.0
var _zoom_min := 0.6
var _touches := {}
var _moved := 0.0
var _selected := -1
var _me_world := Vector2.ZERO
var _static_pins := 0           # PINS'in sabit kismi; sonrakiler her acilista yenilenir
var _dyn_nodes: Array[Control] = []
var _custom := Vector2.INF       # haritada bos bir yere dokunulunca isaretlenen yer
var _custom_pin: Control
var dynamic: Array = []          # main doldurur: [ad, konum, renk, simge]


func _ready() -> void:
	ParkMap.load_data()
	for sp in SPOT_PINS:
		if not ParkMap.has_spot(sp[1]):
			continue
		var c: Vector2 = ParkMap.spot(sp[1])
		PINS.append([sp[0], c, c + sp[2], sp[3], sp[4]])
	for pl in ParkMap.data["places"]:
		var c := Vector2(pl["pos"][0], pl["pos"][1])
		var st: Array = KIND_STYLE.get(pl["kind"], ["8d8f92", "pin"])
		PINS.append([pl["name"], c, ParkMap.nodes[ParkMap.nearest_node(c)], st[0], st[1]])
	# Dukkanlar, eczaneler, kafeler, bankalar, benzinlikler (OpenStreetMap)
	const POI_STYLE := {"market": ["e0743a", "cart"], "eczane": ["d9523f", "plus"], "yemek": ["b8743a", "star"],
		"banka": ["4a6fa5", "coin"], "akaryakit": ["6b6f75", "drop"], "metro": ["c8322b", "pin"], "durak": ["1a4fa0", "pin"]}
	for po in ParkMap.data["pois"]:
		if POI_STYLE.has(po["k"]) and po["k"] != "durak" and po["k"] != "akaryakit":     # benzinlikler: main dinamik pin
			var c := Vector2(po["pos"][0], po["pos"][1])
			if ParkMap.inside_bounds(c, 2.0):
				PINS.append([po["name"], c, c, POI_STYLE[po["k"]][0], POI_STYLE[po["k"]][1]])
	_static_pins = PINS.size()
	for sdata in ParkMap.data["streets"]:
		STREETS.append([sdata["name"], Vector2(sdata["pos"][0], sdata["pos"][1]), float(sdata["rot"])])
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.06, 0.55)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(dim)

	# Telefon govdesi
	var phone := K.panel(self, Color("26242b"), 64, 3, Color("4a4753"), 18)
	K.full(phone, 150, 24, 150, 24)   # yatay ekranda tablet gorunumu
	var screen := K.panel(phone, Color("f4f1ea"), 50)
	K.full(screen, 14, 14, 14, 14)
	screen.clip_contents = true

	# Harita
	_view = Control.new()
	_view.clip_contents = true
	K.full(_view, 0, 0, 0, 0)
	_view.gui_input.connect(_on_view_input)
	screen.add_child(_view)
	_canvas = Control.new()
	_canvas.mouse_filter = MOUSE_FILTER_IGNORE
	_view.add_child(_canvas)
	var tex := TextureRect.new()
	tex.mouse_filter = MOUSE_FILTER_IGNORE
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tex.size = Vector2(MAP_PX, MAP_PX)
	tex.texture = load(ParkMap.asset("park_map.png"))
	_canvas.add_child(tex)
	for s in STREETS:
		var sl := K.label(_canvas, s[0], 15, Color("8d8f92"), HORIZONTAL_ALIGNMENT_CENTER)
		sl.size = Vector2(220, 20)
		sl.scale = Vector2(0.45, 0.45)
		sl.pivot_offset = Vector2(110, 10)
		sl.position = _to_px(s[1]) - Vector2(110, 10)
		sl.rotation = s[2]
		_streets.append(sl)
	for p in PINS:
		var pin := Control.new()
		pin.mouse_filter = MOUSE_FILTER_IGNORE
		pin.position = _to_px(p[1])
		var dot := K.panel(pin, Color(p[3]), 21, 4, Color.WHITE, 5)
		dot.mouse_filter = MOUSE_FILTER_IGNORE
		dot.position = Vector2(-21, -21)
		dot.size = Vector2(42, 42)
		var ic := Icon.new(p[4], Color.WHITE, 22)
		ic.position = Vector2(-11, -11)
		ic.size = Vector2(22, 22)
		pin.add_child(ic)
		var l := K.outline(K.label(pin, p[0], 20, K.BROWN, HORIZONTAL_ALIGNMENT_CENTER), 8)
		l.position = Vector2(-150, 22)
		l.size = Vector2(300, 28)
		_canvas.add_child(pin)
		_pins.append(pin)
	_me = Control.new()
	_me.mouse_filter = MOUSE_FILTER_IGNORE
	var halo := K.panel(_me, Color(0.31, 0.56, 0.85, 0.25), 30)
	halo.mouse_filter = MOUSE_FILTER_IGNORE
	halo.position = Vector2(-30, -30)
	halo.size = Vector2(60, 60)
	var me_dot := K.panel(_me, K.BLUE, 13, 4, Color.WHITE, 4)
	me_dot.mouse_filter = MOUSE_FILTER_IGNORE
	me_dot.position = Vector2(-13, -13)
	me_dot.size = Vector2(26, 26)
	_canvas.add_child(_me)

	# Ust: durum cubugu ve arama kutusu
	var status := K.label(screen, "09:41", 20, K.BROWN)
	status.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	status.position = Vector2(34, 14)
	var notch := K.panel(screen, Color("26242b"), 14)
	notch.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	notch.offset_left = -62
	notch.offset_right = 62
	notch.offset_top = 10
	notch.offset_bottom = 38
	var search := K.panel(screen, Color.WHITE, 30, 0, Color.WHITE, 8)
	search.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	search.offset_left = 20
	search.offset_right = -96
	search.offset_top = 54
	search.offset_bottom = 114
	var sic := Icon.new("pin", K.RED, 30)
	sic.position = Vector2(16, 15)
	sic.size = Vector2(30, 30)
	search.add_child(sic)
	var st := K.label(search, "Subayevleri, Keçiören", 24, K.BROWN)
	st.position = Vector2(58, 0)
	st.size = Vector2(400, 60)
	var close := K.button(screen, "", "close", func(): visible = false, K.RED, Color.WHITE, Vector2(60, 60), 22, 30)
	close.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	close.offset_left = -84
	close.offset_right = -24
	close.offset_top = 54
	close.offset_bottom = 114

	# Sag: yakinlastirma ve konumum
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side.set_anchors_and_offsets_preset(PRESET_CENTER_RIGHT)
	side.offset_left = -84
	side.offset_right = -24
	side.offset_top = -110
	side.offset_bottom = 110
	screen.add_child(side)
	K.button(side, "", "plus", func(): _zoom_at(1.35, _view.size * 0.5), Color.WHITE, K.BROWN, Vector2(60, 60), 22, 18)
	K.button(side, "", "minus", func(): _zoom_at(1.0 / 1.35, _view.size * 0.5), Color.WHITE, K.BROWN, Vector2(60, 60), 22, 18)
	K.button(side, "", "walk", func(): _center_on(_me.position), Color.WHITE, K.BLUE, Vector2(60, 60), 22, 18)

	# Alt: secilen yer karti
	_sheet = K.panel(screen, Color.WHITE, 34, 0, Color.WHITE, 12)
	_sheet.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_sheet.offset_left = 16
	_sheet.offset_right = -16
	_sheet.offset_top = -176
	_sheet.offset_bottom = -22
	_sheet_title = K.label(_sheet, "", 30, K.BROWN)
	_sheet_title.position = Vector2(28, 16)
	_sheet_title.size = Vector2(380, 44)
	_sheet_info = K.label(_sheet, "", 21, K.MUTED)
	_sheet_info.position = Vector2(28, 62)
	_sheet_info.size = Vector2(380, 70)
	_sheet_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sheet_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var go := K.button(_sheet, "Yürü", "walk", _go, K.SOFT, K.BROWN, Vector2(150, 70), 24, 26)
	go.set_anchors_and_offsets_preset(PRESET_CENTER_RIGHT)
	go.offset_left = -176
	go.offset_right = -26
	go.offset_top = -35
	go.offset_bottom = 35
	go.name = "Go"
	var nav := K.button(_sheet, "Yol Tarifi", "come", _nav, K.BLUE, Color.WHITE, Vector2(210, 70), 24, 26)
	nav.set_anchors_and_offsets_preset(PRESET_CENTER_RIGHT)
	nav.offset_left = -400
	nav.offset_right = -190
	nav.offset_top = -35
	nav.offset_bottom = 35
	nav.name = "Nav"
	_custom_pin = Control.new()
	_custom_pin.mouse_filter = MOUSE_FILTER_IGNORE
	var cdot := K.panel(_custom_pin, K.RED, 16, 4, Color.WHITE, 5)
	cdot.mouse_filter = MOUSE_FILTER_IGNORE
	cdot.position = Vector2(-16, -40)
	cdot.size = Vector2(32, 32)
	var cstem := ColorRect.new()
	cstem.color = K.RED
	cstem.position = Vector2(-2, -10)
	cstem.size = Vector2(4, 12)
	_custom_pin.add_child(cstem)
	_custom_pin.visible = false
	_canvas.add_child(_custom_pin)
	var credit := K.outline(K.label(_view, "© OpenStreetMap katkıcıları", 15, K.MUTED), 4)
	credit.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	credit.offset_left = 26
	credit.offset_top = -206
	credit.offset_bottom = -184
	credit.offset_right = 300
	_select(-1)


func open(player_pos: Vector2) -> void:
	visible = true
	_me_world = player_pos
	_me.position = _to_px(player_pos)
	_rebuild_dynamic()
	_custom = Vector2.INF
	_custom_pin.visible = false
	_select(-1)
	await get_tree().process_frame
	_zoom_min = maxf(_view.size.x, _view.size.y) / MAP_PX
	_zoom = _zoom_min * 2.6
	_center_on(_me.position)


func _center_on(px: Vector2) -> void:
	_canvas.position = _view.size * 0.5 - px * _zoom
	_apply()


func _to_px(w: Vector2) -> Vector2:
	return ((w - ParkMap.SPLAT_CENTER) / ParkMap.SPLAT_EXTENT + Vector2(0.5, 0.5)) * MAP_PX


func _apply() -> void:
	_zoom = clampf(_zoom, _zoom_min, _zoom_min * 9.0)
	_canvas.scale = Vector2.ONE * _zoom
	var lo := _view.size - Vector2(MAP_PX, MAP_PX) * _zoom
	_canvas.position = _canvas.position.clamp(lo, Vector2.ZERO)
	# Simgeler ekranda ayni boyda kalir; isimler yakinlastirinca gorunur
	var names := _zoom > _zoom_min * 2.4
	for i in _pins.size():
		_pins[i].scale = Vector2.ONE / _zoom * (1.25 if i == _selected else 1.0)
		_pins[i].get_child(2).visible = names or i == _selected
	for s in _streets:
		s.visible = _zoom > _zoom_min * 2.2
	_me.scale = Vector2.ONE / _zoom


func _zoom_at(factor: float, pivot: Vector2) -> void:
	var before := (pivot - _canvas.position) / _zoom
	_zoom = clampf(_zoom * factor, _zoom_min, _zoom_min * 9.0)
	_canvas.position = pivot - before * _zoom
	_apply()


func _on_view_input(e: InputEvent) -> void:
	var touch := DisplayServer.is_touchscreen_available()
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
			var other: Vector2 = e.position
			for k in _touches:
				if k != e.index:
					other = _touches[k]
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
		elif e.button_index == MOUSE_BUTTON_LEFT and not touch:
			if e.pressed:
				_moved = 0.0
			elif _moved < 14.0:
				_tap(e.position)
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT and not touch:
		_canvas.position += e.relative
		_moved += e.relative.length()
		_apply()


func _tap(pos: Vector2) -> void:
	var best := -1
	var best_d := 56.0
	for i in PINS.size():
		var d: float = (_canvas.position + _to_px(PINS[i][1]) * _zoom).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		# Bos bir yere dokunuldu: orayi hedef olarak isaretle
		var local := (pos - _canvas.position) / _zoom
		_custom = (local / MAP_PX - Vector2(0.5, 0.5)) * ParkMap.SPLAT_EXTENT + ParkMap.SPLAT_CENTER
		_custom_pin.position = local
		_custom_pin.visible = true
	else:
		_custom_pin.visible = false
		_custom = Vector2.INF
	_select(best)


## Harita her acildiginda: evim, araclarim, duraklar gibi degisen isaretler.
func _rebuild_dynamic() -> void:
	PINS.resize(_static_pins)
	for n in _dyn_nodes:
		n.queue_free()
	_dyn_nodes.clear()
	for p in dynamic:
		PINS.append([p[0], p[1], p[1], p[2], p[3]])
		var pin := Control.new()
		pin.mouse_filter = MOUSE_FILTER_IGNORE
		pin.position = _to_px(p[1])
		var dot := K.panel(pin, Color(p[2]), 17, 3, Color.WHITE, 4)
		dot.mouse_filter = MOUSE_FILTER_IGNORE
		dot.position = Vector2(-17, -17)
		dot.size = Vector2(34, 34)
		var ic := Icon.new(p[3], Color.WHITE, 18)
		ic.position = Vector2(-9, -9)
		ic.size = Vector2(18, 18)
		pin.add_child(ic)
		var l := K.outline(K.label(pin, p[0], 17, K.BROWN, HORIZONTAL_ALIGNMENT_CENTER), 7)
		l.position = Vector2(-150, 18)
		l.size = Vector2(300, 24)
		_canvas.add_child(pin)
		_pins.append(pin)
		_dyn_nodes.append(pin)


func _nav() -> void:
	var t := _target()
	if t[0] != Vector2.INF:
		visible = false
		nav_chosen.emit(t[0], t[1])


func _target() -> Array:
	if _selected >= 0:
		return [PINS[_selected][2], PINS[_selected][0]]
	if _custom != Vector2.INF:
		return [_custom, "İşaretli yer"]
	return [Vector2.INF, ""]


func _select(i: int) -> void:
	_selected = i
	var go: Button = _sheet.get_node("Go")
	var nav: Button = _sheet.get_node("Nav")
	var t := _target()
	if t[0] == Vector2.INF:
		_sheet_title.text = "Nereye gidelim?"
		_sheet_info.text = "Bir yere ya da işarete dokun, sonra Yol Tarifi."
		go.visible = false
		nav.visible = false
	else:
		_sheet_title.text = t[1]
		nav.visible = true
		var route := ParkMap.find_route(_me_world, t[0])
		var dist := 0.0
		var prev := _me_world
		for p in route:
			dist += prev.distance_to(p)
			prev = p
		_sheet_info.text = "%d metre  ·  yaklaşık %d dk yürüyüş" % [int(dist), maxi(1, int(dist / 3.4 / 60.0 + 0.5))]
		go.visible = true
	if is_inside_tree() and _view.size.x > 0:
		_apply()


func select_by_name(pin_name: String) -> void:
	for i in PINS.size():
		if PINS[i][0] == pin_name:
			_select(i)
			_zoom = _zoom_min * 4.0
			_center_on(_to_px(PINS[i][1]))


func _go() -> void:
	var t := _target()
	if t[0] != Vector2.INF:
		visible = false
		nav_chosen.emit(t[0], t[1])
		place_chosen.emit(t[0])
