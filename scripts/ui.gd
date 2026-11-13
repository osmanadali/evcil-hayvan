extends CanvasLayer
## Oyun arayuzu: ana menu, kurulum, ust bilgi, komut dugmeleri, magaza, dolap, gorevler, fotograf modu.

signal command(name: String)
signal select_pet(kind: String)
signal start_game(owner_kind: String, pet_kind: String, pet_name: String)
signal continue_game
signal open_map
signal photo(action: String)
signal closet_toggled(open: bool)
signal worn_changed
signal adopted(kind: String)
signal back_to_menu

const K = preload("res://scripts/ui_kit.gd")
const Icon = preload("res://scripts/icon.gd")
const Accessories = preload("res://scripts/accessories.gd")
const NEED_ICONS := {"hunger": "bone", "energy": "bolt", "fun": "smile", "clean": "drop"}
const NEED_COLORS := {"hunger": "f29f4b", "energy": "e9b93a", "fun": "e0708f", "clean": "4f9fd9"}
const PET_COLORS := {"kopek": "e0a04a", "kedi": "e8843c"}

var state: Node

var hud: Control
var menu: Control
var setup: Control
var photo_hud: Control
var _cards := {}
var _coins: Label
var clock_label: Label
var weather_label: Label
var _clock_icon: Control
var _actions: GridContainer
var _context: Button
var _context_cmd := ""
var _toast: PanelContainer
var _toast_label: Label
var _toast_time := 0.0
var _toast_queue: Array[String] = []
var _modal: Control
var _food_pop: Control
var _closet: Control
var _closet_slot := "hat"
var _shop_tab := "food"
var _setup_owner := "kadin"
var _setup_pet := "kopek"
var _name_edit: LineEdit
var _refresh_t := 0.0
var _flash: ColorRect
const GLASS := Color(0.06, 0.07, 0.08, 0.5)
var _more := false          # tum komutlar acik mi
var stick := Vector2.ZERO       # hareket cubugu (-1..1)
var _stick_base: Panel
var _stick_knob: Panel
var _stick_id := -2


func _ready() -> void:
	_build_hud()
	_build_menu()
	_build_setup()
	_build_photo_hud()
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	state.changed.connect(refresh)
	state.toast.connect(toast)
	show_screen("menu")


func show_screen(which: String) -> void:
	hud.visible = which == "hud"
	menu.visible = which == "menu"
	setup.visible = which == "setup"
	photo_hud.visible = which == "photo"
	close_modal()
	if which == "menu":
		var cb: Button = menu.get_node("Box/Continue")
		cb.visible = state.d["started"]
		var first: Button = cb if cb.visible else menu.get_node("Box").get_child(1)
		first.call_deferred("grab_focus")
	if which == "hud":
		refresh()


func is_blocking() -> bool:
	return menu.visible or setup.visible or _modal != null


func _process(dt: float) -> void:
	if _hint:
		_hint.modulate.a = 0.0 if _modal != null else 1.0
	_refresh_t -= dt
	if _refresh_t <= 0.0 and hud.visible:
		_refresh_t = 0.3
		_update_cards()
	if _toast_time > 0.0:
		_toast_time -= dt
		_toast.modulate.a = clampf(_toast_time * 3.0, 0.0, 1.0)
		if _toast_time <= 0.0:
			_toast.visible = false
	elif not _toast_queue.is_empty():
		_toast_label.text = _toast_queue.pop_front()
		_toast.visible = true
		_toast.modulate.a = 1.0
		_toast_time = 2.4
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - dt * 2.5, 0.0)


func toast(text: String) -> void:
	if _toast_queue.size() < 4 and (_toast_queue.is_empty() or _toast_queue[-1] != text):
		_toast_queue.append(text)


func flash() -> void:
	_flash.color.a = 0.9


# ---------------------------------------------------------------- ust bilgi

func _build_hud() -> void:
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.full(hud)
	add_child(hud)

	var cards := VBoxContainer.new()
	cards.name = "Cards"
	# Centik / kamera deligi icin ustten bosluk
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var top := 24.0
	if win.y > 0 and safe.position.y > 0:
		top += safe.position.y * get_viewport().get_visible_rect().size.y / float(win.y)
	cards.position = Vector2(16, top)
	cards.add_theme_constant_override("separation", 6)
	hud.add_child(cards)

	var right := HBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -640
	right.offset_right = -16
	right.offset_top = top
	right.offset_bottom = top + 60
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 12)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(right)
	# Ust sag: saat ve menu (harita dugmesi yok: mini harita acar; para mini haritanin altinda)
	var pill := K.box(right, GLASS, 26, 8)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	pill.add_child(row)
	_clock_icon = Icon.new("sun", Color("ffd36b"), 24)
	row.add_child(_clock_icon)
	clock_label = K.label(row, "10:00", 26, Color.WHITE)
	clock_label.add_theme_font_override("font", load("res://assets/fonts/Anton-Regular.ttf"))
	# Hava durumu ve sicaklik (saatin yaninda, kucuk)
	var wsep := ColorRect.new()
	wsep.color = Color(1, 1, 1, 0.3)
	wsep.custom_minimum_size = Vector2(2, 26)
	row.add_child(wsep)
	weather_label = K.label(row, "", 20, Color(0.86, 0.93, 1.0))
	weather_label.add_theme_font_override("font", load("res://assets/fonts/Anton-Regular.ttf"))
	_coins = Label.new()      # para yazisi mini haritada; bu etiket yalniz eski kod icin
	var phone_btn := K.button(right, "", "phone", func(): command.emit("phone"), GLASS, Color.WHITE, Vector2(60, 60), 30, 30)
	_glass(phone_btn)
	var menu_btn := K.button(right, "", "list", func(): open_pause(), GLASS, Color.WHITE, Vector2(60, 60), 30, 30)
	_glass(menu_btn)
	# Bilgisayarda menu Esc ile acilir, hareket klavyeyle: dugme ve cubuk gizli
	var touch := DisplayServer.is_touchscreen_available()
	menu_btn.visible = touch

	_toast = K.box(hud, Color(0.25, 0.19, 0.14, 0.9), 26, 16)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 112
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	# GTA tarzi bildirim: koyu, kose yumusak, solda sari serit
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.04, 0.04, 0.06, 0.86)
	tsb.border_width_left = 8
	tsb.border_color = Color("f5c518")
	tsb.set_corner_radius_all(4)
	tsb.content_margin_left = 26
	tsb.content_margin_right = 22
	tsb.content_margin_top = 12
	tsb.content_margin_bottom = 12
	_toast.add_theme_stylebox_override("panel", tsb)
	_toast_label = K.label(_toast, "", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.custom_minimum_size = Vector2(520, 0)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom.offset_left = -700
	bottom.offset_right = -16
	bottom.offset_top = -300
	bottom.offset_bottom = -20
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 12)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bottom)
	_context = K.button(bottom, " ", "star", func(): command.emit(_context_cmd), K.ORANGE, Color.WHITE, Vector2(320, 70), 26, 35)
	_context.visible = false
	# Alt ortada (mini harita sagda oldugu icin)
	_context.reparent(hud)
	_context.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_context.offset_left = -170
	_context.offset_right = 170
	_context.offset_top = -110
	_context.offset_bottom = -40
	_actions = ActionGrid.new()
	_actions.columns = 4
	_actions.add_theme_constant_override("h_separation", 14)
	_actions.add_theme_constant_override("v_separation", 10)
	_actions.size_flags_horizontal = Control.SIZE_SHRINK_END
	bottom.add_child(_actions)

	# Hareket cubugu (sol alt)
	_stick_base = K.panel(hud, Color(0.05, 0.06, 0.07, 0.22), 89, 2, Color(1, 1, 1, 0.35))
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stick_base.offset_left = 50
	_stick_base.offset_right = 230
	_stick_base.offset_top = -230
	_stick_base.offset_bottom = -50
	_stick_knob = K.panel(_stick_base, Color(1, 1, 1, 0.55), 37, 0, Color.WHITE)
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.size = Vector2(76, 76)
	_stick_knob.position = Vector2(52, 52)
	_stick_base.visible = DisplayServer.is_touchscreen_available()


## Hareket cubugu: dokunmayi (ya da fareyi) dogrudan izler, boylece ikinci parmak kamerayi cevirebilir.
func _input(e: InputEvent) -> void:
	if not hud.visible or is_blocking():
		stick = Vector2.ZERO
		_stick_id = -2
		return
	var touch := DisplayServer.is_touchscreen_available()
	var pos := Vector2.ZERO
	var id := -1
	var down := false
	var up := false
	var move := false
	if e is InputEventScreenTouch and touch:
		pos = e.position
		id = e.index
		down = e.pressed
		up = not e.pressed
	elif e is InputEventScreenDrag and touch:
		pos = e.position
		id = e.index
		move = true
	elif e is InputEventMouseButton and not touch and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		down = e.pressed
		up = not e.pressed
	elif e is InputEventMouseMotion and not touch:
		pos = e.position
		move = true
	else:
		return
	var rect := _stick_base.get_global_rect()
	var center := rect.get_center()
	if down and _stick_id == -2 and pos.distance_to(center) < rect.size.x * 0.75:
		_stick_id = id
	if _stick_id == id and (down or move):
		var v := (pos - center) / (rect.size.x * 0.5)
		stick = v.limit_length(1.0)
		_stick_knob.position = Vector2(52, 52) + stick * 52.0
		get_viewport().set_input_as_handled()
	elif _stick_id == id and up:
		_stick_id = -2
		stick = Vector2.ZERO
		_stick_knob.position = Vector2(52, 52)
		get_viewport().set_input_as_handled()


var _hint: PanelContainer
var _hint_label: Label


## Etkilesim: bilgisayarda ekranda dugme yok, sol ustte "[F] ..." ipucu; tablette kucuk F dugmesi.
func set_context(text: String, cmd: String, icon := "star") -> void:
	if _hint == null:
		_hint = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.03, 0.05, 0.82)
		sb.border_width_left = 6
		sb.border_color = ACCENT
		sb.content_margin_left = 16
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		_hint.add_theme_stylebox_override("panel", sb)
		_hint.position = Vector2(24, 150)
		_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_hint)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_hint.add_child(row)
		var key := PanelContainer.new()
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color.WHITE
		ks.set_corner_radius_all(6)
		ks.content_margin_left = 10
		ks.content_margin_right = 10
		key.add_theme_stylebox_override("panel", ks)
		row.add_child(key)
		_fx_label(key, "F", F_BODY, 24, Color("111111"))
		_hint_label = _fx_label(row, "", F_BODY, 24, Color.WHITE)
	if cmd == _context_cmd and _hint.visible == (cmd != "" or text != ""):
		return
	_context_cmd = cmd
	var touch := DisplayServer.is_touchscreen_available()
	_hint.visible = text != "" and not touch
	(_hint.get_child(0).get_child(0) as Control).visible = cmd != ""
	_hint_label.text = text
	_context.visible = cmd != "" and touch
	K.set_text(_context, text)
	var ic := _context.find_children("*", "Control", true, false)
	for c in ic:
		if c is Icon:
			c.icon = icon


func refresh() -> void:
	if not hud:
		return
	_coins.text = str(state.d["coins"])
	# Hayvan kartlari
	var cards: VBoxContainer = hud.get_node("Cards")
	var pets: Array = state.owned_pets()
	if _cards.keys() != pets:
		for c in cards.get_children():
			c.queue_free()
		_cards.clear()
		for kind in pets:
			_cards[kind] = _make_card(cards, kind)
	_update_cards()
	# Komut dugmeleri: yalniz "Gel" (cagir); digerleri hayvana dokununca cevresinde acilir
	for c in _actions.get_children():
		c.queue_free()
	_actions.columns = 1
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_actions.add_child(col)
	if DisplayServer.is_touchscreen_available():
		var jb := K.button(col, "Zıpla", "", func(): command.emit("jump"), GLASS, Color.WHITE, Vector2(76, 56), 18, 28)
		jb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_glass(jb)
	var b := K.button(col, "", "come", func(): _on_action("come"), GLASS, Color.WHITE, Vector2(76, 76), 34, 38)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_glass(b)
	var cap := K.label(col, "Çağır", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	cap.add_theme_constant_override("outline_size", 5)
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))


## Hayvanin cevresinde halka menu: sev, mama, top/yumak, otur, yat, uyu, oynat.
var _radial: Control


func radial_open() -> bool:
	return _radial != null and _radial.visible


func close_radial() -> void:
	if _radial:
		_radial.queue_free()
		_radial = null


func open_radial(at: Vector2, cat: bool, two: bool) -> void:
	close_radial()
	_radial = Control.new()
	_radial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_radial)
	var items := [["Sev", "heart", "pet"], ["Mama", "bone", "food"], ["Yumak" if cat else "Top At", "yarn" if cat else "ball", "yarn" if cat else "throw"],
		["Otur", "sit", "sit"], ["Yat", "minus", "lie"], ["Uyu", "moon", "sleep"], ["Tasma", "walk", "leash"], ["Eğitim", "star", "train"]]
	if two:
		items.append(["Oynat", "play", "play"])
	var vp := get_viewport().get_visible_rect().size
	at = at.clamp(Vector2(130, 130), vp - Vector2(130, 130))
	for i in items.size():
		var a := -PI / 2.0 + i * TAU / items.size()
		var cmd: String = items[i][2]
		var holder := VBoxContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_theme_constant_override("separation", 0)
		_radial.add_child(holder)
		var btn := K.button(holder, "", items[i][1], func():
			close_radial()
			_on_action(cmd), GLASS, Color.WHITE, Vector2(62, 62), 28, 30)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_glass(btn)
		var l := K.label(holder, items[i][0], 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		holder.position = at + Vector2.from_angle(a) * 105.0 - Vector2(40, 40)
		holder.custom_minimum_size = Vector2(80, 80)
	# Ortada kapat
	var x := K.button(_radial, "", "close", close_radial, Color(0, 0, 0, 0.35), Color.WHITE, Vector2(44, 44), 22, 20)
	x.position = at - Vector2(22, 22)


## Saydam koyu yuvarlak dugme gorunumu
func _glass(b: Button) -> void:
	var r := int(b.custom_minimum_size.y / 2.0) - 1
	b.add_theme_stylebox_override("normal", K.style(GLASS, r, 2, Color(1, 1, 1, 0.28)))
	b.add_theme_stylebox_override("hover", K.style(GLASS, r, 2, Color(1, 1, 1, 0.28)))
	b.add_theme_stylebox_override("pressed", K.style(Color(1, 1, 1, 0.35), r, 2, Color.WHITE))


func _on_action(cmd: String) -> void:
	if cmd == "more":
		_more = not _more
		refresh()
	elif cmd == "food":
		_open_food()
	else:
		command.emit(cmd)


func _make_card(parent: Node, kind: String) -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(270, 66)
	b.pressed.connect(func(): select_pet.emit(kind))
	parent.add_child(b)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	K.full(row, 8, 7, 16, 7)
	b.add_child(row)
	var face := K.panel(row, Color(PET_COLORS[kind]), 25, 2, Color.WHITE)
	face.custom_minimum_size = Vector2(52, 52)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paw := Icon.new("paw", Color.WHITE, 30)
	paw.position = Vector2(11, 11)
	paw.size = Vector2(30, 30)
	face.add_child(paw)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 5)
	row.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var name_l := K.label(top, "", 19, Color.WHITE)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	var lvl := K.label(top, "", 16, Color("ffd9a0"))
	var xp := K.bar(col, K.ORANGE, Vector2(100, 4))
	var bars := {}      # ihtiyaclar artik mini haritanin cevresinde
	var mood := K.label(col, "", 14, Color(1, 1, 1, 0.8))
	mood.name = "Mood"
	return {"button": b, "name": name_l, "level": lvl, "xp": xp, "bars": bars, "mood": mood}


func _update_cards() -> void:
	for kind in _cards:
		var c: Dictionary = _cards[kind]
		var p: Dictionary = state.pet(kind)
		var active: bool = state.d["active"] == kind
		var sb := K.style(GLASS if active else Color(0.06, 0.07, 0.08, 0.28), 32, 2 if active else 0, Color(1, 1, 1, 0.45))
		for s in ["normal", "hover", "pressed"]:
			c["button"].add_theme_stylebox_override(s, sb)
		c["name"].text = p["name"]
		c["level"].text = "Sv %d" % state.level(kind)
		c["xp"].value = state.level_progress(kind) * 100.0
		# Kartta en dusuk ihtiyac yazilir ("Acikti", "Yorgun"...), hepsi iyiyse "Mutlu"
		var low := ""
		var low_v := 40.0
		for n in state.NEEDS:
			if float(p[n]) < low_v:
				low_v = float(p[n])
				low = n
		(c["mood"] as Label).text = {"hunger": "Acıktı", "energy": "Yorgun", "fun": "Sıkıldı", "clean": "Kirli"}.get(low, "Mutlu") if low != "" else "Mutlu"
		(c["mood"] as Label).modulate = Color(1, 0.6, 0.55) if low != "" else Color(0.75, 1, 0.75)


# ---------------------------------------------------------------- pencereler

func close_modal() -> void:
	if _modal:
		_modal.queue_free()
		_modal = null
	if _food_pop:
		_food_pop.queue_free()
		_food_pop = null
	if _closet:
		_closet.queue_free()
		_closet = null
		closet_toggled.emit(false)


## Ortasinda baslikli pencere acar; icerik VBox'ini dondurur.
func _open_modal(title: String, top := 150.0, bottom := 150.0) -> VBoxContainer:
	close_modal()
	_modal = Control.new()
	K.full(_modal)
	add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.06, 0.5)
	K.full(dim)
	_modal.add_child(dim)
	var p := K.panel(_modal, K.CREAM, 44, 0, Color.WHITE, 16)
	var vs := get_viewport().get_visible_rect().size
	var side := maxf((vs.x - 820.0) * 0.5, 28.0)
	K.full(p, side, minf(top, 36.0) if top < 200.0 else 150.0, side, minf(bottom, 36.0) if bottom < 200.0 else 150.0)
	var head := HBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 30
	head.offset_right = -22
	head.offset_top = 20
	head.offset_bottom = 88
	p.add_child(head)
	var t := K.label(head, title, 36, K.BROWN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(Icon.new("coin", Color.WHITE, 30))
	var cl := K.label(head, str(state.d["coins"]) + "  ", 26, K.BROWN)
	cl.name = "Coins"
	K.button(head, "", "close", close_modal, K.RED, Color.WHITE, Vector2(64, 64), 22, 32)
	var scroll := ScrollContainer.new()
	K.full(scroll, 24, 104, 24, 24)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	return body


func _row(parent: Node, icon: String, icon_color: Color, title: String, sub: String) -> HBoxContainer:
	var pc := K.box(parent, K.SOFT, 26, 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pc.add_child(row)
	var badge := K.panel(row, icon_color, 30)
	badge.custom_minimum_size = Vector2(60, 60)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ic := Icon.new(icon, Color.WHITE, 34)
	ic.position = Vector2(13, 13)
	ic.size = Vector2(34, 34)
	badge.add_child(ic)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	K.label(col, title, 25, K.BROWN)
	if sub != "":
		var s := K.label(col, sub, 19, K.MUTED)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return row


func _tabs(parent: Node, tabs: Array, current: String, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	for t in tabs:
		var id: String = t[1]
		var on := id == current
		var b := K.button(row, t[0], "", func(): cb.call(id), K.ORANGE if on else K.SOFT, Color.WHITE if on else K.BROWN, Vector2(0, 58), 21, 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func open_shop(tab := "") -> void:
	if tab != "":
		_shop_tab = tab
	var body := _open_modal("Pet Shop")
	_tabs(body, [["Mama", "food"], ["Aksesuar", "acc"], ["Dostlar", "pets"]], _shop_tab, open_shop)
	if _shop_tab == "food":
		for id in state.FOODS:
			var f: Array = state.FOODS[id]
			var sub := "Tokluk +%d" % f[2] + ("  ·  Neşe +%d" % f[3] if f[3] > 0 else "") + "  ·  Sende: %d" % int(state.d["foods"].get(id, 0))
			var row := _row(body, "bone", K.ORANGE, f[0], sub)
			_price_button(row, f[1], func():
				if state.spend(f[1]):
					state.d["foods"][id] = int(state.d["foods"].get(id, 0)) + 1
					open_shop())
	elif _shop_tab == "acc":
		for id in Accessories.ITEMS:
			var it: Array = Accessories.ITEMS[id]
			var row := _row(body, "shirt", K.BLUE, it[0], Accessories.SLOTS[it[1]])
			if state.d["owned"].has(id):
				K.label(row, "Sende var  ", 21, K.GREEN)
			else:
				_price_button(row, it[2], func():
					if state.spend(it[2]):
						state.d["owned"].append(id)
						toast("%s dolabına eklendi" % it[0])
						open_shop())
	else:
		for kind in ["kopek", "kedi"]:
			var p: Dictionary = state.pet(kind)
			var row := _row(body, "paw", Color(PET_COLORS[kind]), state.PET_NAMES[kind],
				"Ailenin üyesi: %s" % p["name"] if p["owned"] else "Yeni bir dost sahiplen. İkisi birlikte oynar.")
			if p["owned"]:
				K.label(row, "Seninle  ", 21, K.GREEN)
			else:
				_price_button(row, state.ADOPT_PRICE, func():
					if state.spend(state.ADOPT_PRICE):
						p["owned"] = true
						adopted.emit(kind)
						toast("%s artık ailenin bir üyesi!" % p["name"])
						open_shop())


func _price_button(row: Node, price: int, cb: Callable) -> void:
	var can: bool = state.d["coins"] >= price
	var b := K.button(row, str(price), "coin", cb, K.GREEN if can else Color("bdb5a8"), Color.WHITE, Vector2(124, 62), 24, 24)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func open_quests() -> void:
	var body := _open_modal("Görevler")
	K.label(body, "Bugünün görevleri", 24, K.MUTED)
	for q in state.daily_quests():
		var done: bool = state.d["quest_done"].has(q[0])
		var prog: float = minf(state.quest_progress(q[0]), q[2])
		var row := _row(body, "check" if done else "star", K.GREEN if done else K.ORANGE, q[1], "%d / %d   ·   Ödül: %d altın" % [int(prog), q[2], q[3]])
		var pb := K.bar(row, K.GREEN, Vector2(110, 14))
		pb.value = prog / q[2] * 100.0
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	K.label(body, "Keşif: %d / %d yer" % [state.d["places"].size(), state.places.size()], 24, K.MUTED)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	body.add_child(flow)
	for pl in state.places:
		var found: bool = state.d["places"].has(pl[0])
		var chip := K.box(flow, K.GREEN if found else K.SOFT, 18, 10)
		K.label(chip, pl[0] if found else "? ? ?", 19, Color.WHITE if found else K.MUTED)


## GTA tarzi tam ekran sayfa (duraklatma / ayarlar): solda koyu gecis, egik baslik, buyuk maddeler.
func _open_page(title: String, subtitle := "") -> VBoxContainer:
	close_modal()
	_context.modulate.a = 0.0
	_modal = Control.new()
	_modal.tree_exiting.connect(func(): if is_instance_valid(_context): _context.modulate.a = 1.0)
	K.full(_modal)
	add_child(_modal)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.45)
	K.full(dim)
	_modal.add_child(dim)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.gradient = Gradient.new()
	gt.gradient.set_color(0, Color(0.02, 0.02, 0.05, 0.92))
	gt.gradient.set_color(1, Color(0.02, 0.02, 0.05, 0.0))
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 980
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(grad)
	var head := Control.new()
	head.position = Vector2(60, 40)
	head.rotation = -0.04
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(head)
	_fx_label(head, title, F_TITLE, 96, ACCENT, 16)
	var stripe := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT2
	sb.skew = Vector2(0.35, 0)
	stripe.add_theme_stylebox_override("panel", sb)
	stripe.position = Vector2(8, 104)
	stripe.size = Vector2(70 + title.length() * 46, 14)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(stripe)
	if subtitle != "":
		_fx_label(head, subtitle, F_BODY, 26, Color.WHITE, 6).position = Vector2(14, 126)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 40
	scroll.offset_right = 760
	scroll.offset_top = 210
	scroll.offset_bottom = -70
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_modal.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.55)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -54
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(bar)
	var hint := _fx_label(bar, "ESC  GERİ      ENTER  SEÇ" if not DisplayServer.is_touchscreen_available() else "BİR SEÇENEĞE DOKUN", F_BODY, 22, Color(1, 1, 1, 0.8))
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.offset_left = 60
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var accent := ColorRect.new()
	accent.color = ACCENT2
	accent.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	accent.offset_top = -58
	accent.offset_bottom = -54
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal.add_child(accent)
	return body


## Kucuk yan panel (dukkan, veteriner): oyun gorunur kalir, sagda koyu kart.
func _open_panel(title: String, subtitle := "") -> VBoxContainer:
	close_modal()
	_context.modulate.a = 0.0
	_modal = Control.new()
	K.full(_modal)
	_modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal)
	_modal.tree_exiting.connect(func(): if is_instance_valid(_context): _context.modulate.a = 1.0)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.88)
	sb.border_width_top = 6
	sb.border_color = ACCENT
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", sb)
	card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	card.offset_left = -470
	card.offset_right = -36
	card.offset_top = -120
	card.offset_bottom = 120
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_modal.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	_fx_label(col, title, F_TITLE, 52, ACCENT, 8)
	if subtitle != "":
		var st := _fx_label(col, subtitle, F_BODY, 20, Color(1, 1, 1, 0.8))
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.custom_minimum_size = Vector2(400, 0)
	var sep := ColorRect.new()
	sep.color = ACCENT2
	sep.custom_minimum_size = Vector2(0, 3)
	col.add_child(sep)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	col.add_child(body)
	var hint := _fx_label(col, "ESC  KAPAT", F_BODY, 18, Color(1, 1, 1, 0.5))
	hint.custom_minimum_size = Vector2(0, 30)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return body


## Paneldeki kucuk madde.
func _panel_item(parent: Node, text: String, cb: Callable) -> Button:
	var b := _menu_item(parent, text, cb)
	b.custom_minimum_size = Vector2(400, 46)
	b.add_theme_font_size_override("font_size", 28)
	return b


## Telefon: sag altta gercek bir telefon, uygulama simgeleri. apps: [[ad, renk, simge, Callable]]
func open_phone(apps: Array, owner_name: String) -> void:
	close_modal()
	_context.modulate.a = 0.0
	_modal = Control.new()
	K.full(_modal)
	add_child(_modal)
	_modal.tree_exiting.connect(func(): if is_instance_valid(_context): _context.modulate.a = 1.0)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.25)
	K.full(dim)
	dim.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close_modal())
	_modal.add_child(dim)
	var phone := Panel.new()
	var body_sb := StyleBoxFlat.new()
	body_sb.bg_color = Color("111214")
	body_sb.set_corner_radius_all(46)
	body_sb.border_color = Color("3a3d42")
	body_sb.set_border_width_all(4)
	body_sb.shadow_color = Color(0, 0, 0, 0.5)
	body_sb.shadow_size = 24
	phone.add_theme_stylebox_override("panel", body_sb)
	phone.size = Vector2(330, 640)
	var vs := get_viewport().get_visible_rect().size
	var sc := minf(1.0, (vs.y - 50.0) / 640.0)
	phone.scale = Vector2.ONE * sc
	phone.position = Vector2(vs.x - 330.0 * sc - 40.0, vs.y)
	_modal.add_child(phone)
	var screen := Panel.new()
	var scr_sb := StyleBoxFlat.new()
	var grad := Gradient.new()
	scr_sb.bg_color = Color("1d3b5a")
	scr_sb.set_corner_radius_all(36)
	screen.add_theme_stylebox_override("panel", scr_sb)
	screen.position = Vector2(12, 12)
	screen.size = Vector2(306, 616)
	screen.clip_contents = true
	phone.add_child(screen)
	# Duvar kagidi: yumusak gecis
	var wp := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.gradient = Gradient.new()
	gt.gradient.set_color(0, Color("2b5876"))
	gt.gradient.set_color(1, Color("4e4376"))
	gt.fill_to = Vector2(0.4, 1)
	wp.texture = gt
	wp.stretch_mode = TextureRect.STRETCH_SCALE
	wp.position = Vector2.ZERO
	wp.size = screen.size
	wp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(wp)
	# Centik ve durum cubugu
	var notch := Panel.new()
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color("050505")
	nsb.set_corner_radius_all(14)
	notch.add_theme_stylebox_override("panel", nsb)
	notch.position = Vector2(108, 10)
	notch.size = Vector2(90, 26)
	screen.add_child(notch)
	var tl := _fx_label(screen, clock_label.text, F_BODY, 20, Color.WHITE)
	tl.position = Vector2(26, 10)
	var bat := _fx_label(screen, "4G  ▮▮▮  %86", F_BODY, 16, Color.WHITE)
	bat.position = Vector2(200, 13)
	var big := _fx_label(screen, clock_label.text, F_BODY, 68, Color.WHITE)
	big.position = Vector2(0, 52)
	big.size = Vector2(306, 80)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var who := _fx_label(screen, "%s  ·  %d ₺" % [owner_name, state.d["coins"]], F_BODY, 18, Color(1, 1, 1, 0.8))
	who.position = Vector2(0, 136)
	who.size = Vector2(306, 26)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	grid.position = Vector2(22, 184)
	screen.add_child(grid)
	var first: Button = null
	for a in apps:
		var app: Array = a
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		grid.add_child(cell)
		var b := Button.new()
		b.custom_minimum_size = Vector2(76, 76)
		b.focus_mode = Control.FOCUS_ALL
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(app[1])
		bs.set_corner_radius_all(20)
		var hs := bs.duplicate()
		hs.bg_color = Color(app[1]).lightened(0.2)
		hs.border_color = Color.WHITE
		hs.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", bs)
		b.add_theme_stylebox_override("hover", hs)
		b.add_theme_stylebox_override("focus", hs)
		b.add_theme_stylebox_override("pressed", hs)
		var ic := Icon.new(app[2], Color.WHITE, 40)
		ic.position = Vector2(18, 18)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		var cb: Callable = app[3]
		b.pressed.connect(func():
			if K.on_click.is_valid():
				K.on_click.call()
			close_modal()
			cb.call())
		cell.add_child(b)
		var nl := _fx_label(cell, app[0], F_BODY, 15, Color.WHITE)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.custom_minimum_size = Vector2(76, 0)
		if first == null:
			first = b
	# Ana ekran cubugu
	var home := ColorRect.new()
	home.color = Color(1, 1, 1, 0.7)
	home.position = Vector2(103, 596)
	home.size = Vector2(100, 5)
	screen.add_child(home)
	var tw := create_tween()
	tw.tween_property(phone, "position:y", vs.y - 640.0 * sc - 25.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if first:
		first.call_deferred("grab_focus")


func _focus_first(body: Node) -> void:
	for c in body.get_children():
		if c is Button:
			c.call_deferred("grab_focus")
			return


func open_pause() -> void:
	if menu.visible:
		open_settings()
		return
	var body := _open_page("DURAKLATILDI", "%d altın  ·  %s" % [state.d["coins"], clock_label.text])
	_menu_item(body, "DEVAM ET", close_modal)
	_menu_item(body, "GÖREVLER", func(): open_quests())
	_menu_item(body, "DOLAP", func(): open_closet())
	_menu_item(body, "ÇANTAM", func(): open_bag())
	_menu_item(body, "FOTOĞRAF ÇEK", func():
		close_modal()
		photo.emit("enter"))
	_menu_item(body, "AYARLAR", func(): open_settings())
	_menu_item(body, "ANA MENÜ", func(): back_to_menu.emit())
	_focus_first(body)


## Dukkan urunleri: [kimlik, ad, fiyat, tur]  tur: "food" (hayvan mamasi), "bag" (cantaya), "pet:<ihtiyac>:<miktar>" (hemen etki)
const SHOP_ITEMS := {
	"market": [["mama", "Kuru Mama", 8, "food"], ["konserve", "Konserve", 14, "food"], ["odul", "Ödül Bisküvisi", 6, "food"],
		["su", "Su", 3, "bag"], ["simit", "Simit", 5, "bag"], ["ayran", "Ayran", 6, "bag"], ["ekmek", "Ekmek", 4, "bag"],
		["cikolata", "Çikolata", 8, "bag"], ["dondurma", "Dondurma", 10, "bag"], ["meyve", "Meyve Suyu", 7, "bag"],
		["yumurta", "Yumurta", 3, "bag"], ["domates", "Domates", 4, "bag"], ["biber", "Biber", 3, "bag"],
		["makarna", "Makarna", 9, "bag"], ["peynir", "Peynir", 14, "bag"],
		["top", "Oyuncak Top", 12, "pet:fun:30"], ["sampuan", "Pati Şampuanı", 15, "pet:clean:40"]],
	"eczane": [["vitamin", "Vitamin Macunu", 15, "pet:energy:35"], ["damla", "Pire-Kene Damlası", 20, "pet:clean:45"],
		["kulak", "Kulak Solüsyonu", 10, "pet:clean:20"], ["sakin", "Sakinleştirici Ödül", 12, "pet:fun:25"],
		["yara", "Yara Bandı", 4, "bag"], ["kolonya", "Kolonya", 9, "bag"], ["agri", "Ağrı Kesici", 12, "bag"]],
}
var _basket := {}
signal bought(items: Dictionary, total: int)


## Alisveris: urunlere dokunup sepete ekle, sonra ODE. GTA tarzi tam ekran sayfa.
func open_store(kind: String, title: String) -> void:
	var total := 0
	var count := 0
	for id in _basket:
		count += int(_basket[id])
		for it in SHOP_ITEMS[kind]:
			if it[0] == id:
				total += int(it[2]) * int(_basket[id])
	var body := _open_page(title.to_upper(), "Cüzdan: %d ₺   ·   Sepet: %d ürün, %d ₺" % [state.d["coins"], count, total])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for it in SHOP_ITEMS[kind]:
		var item: Array = it
		var n := int(_basket.get(item[0], 0))
		var label := "%s  %d ₺%s" % [item[1].to_upper(), item[2], ("   ×%d" % n) if n > 0 else ""]
		var b := _tile(grid, label, n > 0, func():
			_basket[item[0]] = int(_basket.get(item[0], 0)) + 1
			open_store(kind, title), ACCENT, Vector2(340, 50), 22)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var pay := _tile(row, "ÖDE  %d ₺" % total, true, func():
		if total == 0:
			toast("Sepetin boş. Ürünlere dokunarak ekle.")
		elif state.d["coins"] < total:
			toast("Paran yetmiyor! %d ₺ eksik." % (total - state.d["coins"]))
		else:
			state.d["coins"] -= total
			for id in _basket:
				for it2 in SHOP_ITEMS[kind]:
					if it2[0] != id:
						continue
					var kind2: String = it2[3]
					if kind2 == "food":
						state.d["foods"][id] = int(state.d["foods"].get(id, 0)) + int(_basket[id])
					elif kind2 == "bag":
						var bag: Dictionary = state.d.get("bag", {})
						bag[it2[1]] = int(bag.get(it2[1], 0)) + int(_basket[id])
						state.d["bag"] = bag
			bought.emit(_basket.duplicate(), total)
			_basket.clear()
			state.changed.emit()
			state.save_game()
			close_modal(), ACCENT2, Vector2(300, 58), 32)
	pay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile(row, "BOŞALT", false, func():
		_basket.clear()
		open_store(kind, title), Color.WHITE, Vector2(170, 58), 28)
	_tile(row, "ÇIK", false, func():
		_basket.clear()
		close_modal(), Color.WHITE, Vector2(120, 58), 28)


## Canta: aldiklarini kullan (ye, ic).
func open_bag() -> void:
	var body := _open_page("ÇANTAM")
	var bag: Dictionary = state.d.get("bag", {})
	var any := false
	for name in bag.keys():
		var n := int(bag[name])
		if n <= 0:
			continue
		any = true
		var nm: String = name
		_menu_item(body, "%s  ×%d" % [nm.to_upper(), n], func():
			bag[nm] = int(bag[nm]) - 1
			if bag[nm] <= 0:
				bag.erase(nm)
			command.emit("use:" + nm)
			open_bag())
	if not any:
		_fx_label(body, "Çantan boş. Marketten bir şeyler al.", F_BODY, 28, Color.WHITE, 6)
	_menu_item(body, "GERİ", func(): open_pause())
	_focus_first(body)


## Ayarlar: ses, tam ekran, kontroller.
func open_settings() -> void:
	var body := _open_page("AYARLAR")
	var snd := "SES:  AÇIK" if state.d["sound"] else "SES:  KAPALI"
	_menu_item(body, snd, func():
		state.d["sound"] = not state.d["sound"]
		state.save_game()
		open_settings())
	if not DisplayServer.is_touchscreen_available():
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		_menu_item(body, "TAM EKRAN:  " + ("AÇIK" if full else "KAPALI"), func():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			open_settings())
	var info := _fx_label(body, "KONTROLLER", F_BODY, 30, ACCENT, 6)
	info.custom_minimum_size = Vector2(0, 56)
	info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var keys := "W A S D  yürü / sür     SHIFT  koş     BOŞLUK  zıpla, el freni\nE  etkileşim     V  araç içi kamera     M  harita\nP  telefon     G  görevler     C  fotoğraf     ESC  menü" \
		if not DisplayServer.is_touchscreen_available() else "Sol alttaki çubukla yürü, ekranı sürükleyerek etrafına bak.\nHayvanına dokun: sev, besle, oyna."
	var kl := _fx_label(body, keys, F_BODY, 22, Color(1, 1, 1, 0.85))
	kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kl.add_theme_constant_override("line_spacing", 6)
	_menu_item(body, "GERİ", func():
		if menu.visible:
			close_modal()
		else:
			open_pause())
	_focus_first(body)


func _open_food() -> void:
	if _food_pop:
		_food_pop.queue_free()
		_food_pop = null
		return
	_food_pop = K.box(hud, K.CREAM, 30, 14, 10)
	_food_pop.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_food_pop.offset_left = -540
	_food_pop.offset_right = -20
	_food_pop.offset_bottom = -190
	_food_pop.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_food_pop.add_child(col)
	var any := false
	for id in state.FOODS:
		var n := int(state.d["foods"].get(id, 0))
		if n <= 0:
			continue
		any = true
		var f: Array = state.FOODS[id]
		K.button(col, "%s  ×%d" % [f[0], n], "bone", func():
			_food_pop.queue_free()
			_food_pop = null
			command.emit("feed:" + id), K.SOFT, K.BROWN, Vector2(480, 66), 24, 22)
	if not any:
		K.label(col, "Mama kalmadı. Çarşıdaki Pet Shop'tan alabilirsin.", 22, K.MUTED, HORIZONTAL_ALIGNMENT_CENTER).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.get_child(0).custom_minimum_size = Vector2(480, 0)


## Dolap: ekranin altinda acilir, hayvan ustte gorunur.
func open_closet(slot := "") -> void:
	if slot != "":
		_closet_slot = slot
	var was_open := _closet != null
	if _closet:
		_closet.queue_free()
	elif _modal or _food_pop:
		close_modal()
	_closet = K.panel(self, K.CREAM, 44, 0, Color.WHITE, 16)
	_closet.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_closet.offset_left = -560
	_closet.offset_right = -16
	_closet.offset_top = 16
	_closet.offset_bottom = -16
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	K.full(col, 22, 18, 22, 18)
	_closet.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var kind: String = state.d["active"]
	var t := K.label(head, "Dolap  ·  %s" % state.pet(kind)["name"], 30, K.BROWN)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	K.button(head, "", "close", close_modal, K.RED, Color.WHITE, Vector2(60, 60), 22, 30)
	var tabs := []
	for s in Accessories.SLOTS:
		tabs.append([Accessories.SLOTS[s], s])
	_tabs(col, tabs, _closet_slot, open_closet)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var worn: Dictionary = state.pet(kind)["worn"]
	var none := not worn.has(_closet_slot)
	var nb := K.button(grid, "Hiçbiri", "close", func():
		worn.erase(_closet_slot)
		worn_changed.emit()
		open_closet(), K.ORANGE if none else K.SOFT, Color.WHITE if none else K.BROWN, Vector2(0, 74), 22, 22)
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in Accessories.ITEMS:
		var it: Array = Accessories.ITEMS[id]
		if it[1] != _closet_slot:
			continue
		var have: bool = state.d["owned"].has(id)
		var on: bool = worn.get(_closet_slot, "") == id
		var b := K.button(grid, it[0] if have else "%s  (%d)" % [it[0], it[2]], "check" if on else ("shirt" if have else "lock"), func():
			if have:
				worn[_closet_slot] = id
				worn_changed.emit()
				open_closet()
			else:
				toast("Bunu çarşıdaki Pet Shop'tan alabilirsin"),
			K.ORANGE if on else K.SOFT, Color.WHITE if on else (K.BROWN if have else K.MUTED), Vector2(0, 74), 22, 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not was_open:
		closet_toggled.emit(true)


# ---------------------------------------------------------------- ana menu ve kurulum

const F_TITLE := preload("res://assets/fonts/Bangers-Regular.ttf")
const F_BODY := preload("res://assets/fonts/Anton-Regular.ttf")
const ACCENT := Color("f5c518")     # sari
const ACCENT2 := Color("ff5f8f")    # pembe


func _fx_label(parent: Node, text: String, font: Font, size: int, color: Color, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.05))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 4)
	l.add_theme_constant_override("shadow_offset_y", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## GTA tarzi menu maddesi: buyuk egik yazi; ustune gelince / secilince sari egik serit.
func _menu_item(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(470, 66)
	b.add_theme_font_override("font", F_BODY)
	b.add_theme_font_size_override("font_size", 46)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	b.add_theme_color_override("font_hover_color", Color("111111"))
	b.add_theme_color_override("font_focus_color", Color("111111"))
	b.add_theme_color_override("font_pressed_color", Color("111111"))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("outline_size", 6)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.content_margin_left = 28
	var hi := StyleBoxFlat.new()
	hi.bg_color = ACCENT
	hi.skew = Vector2(0.3, 0)
	hi.content_margin_left = 28
	hi.shadow_color = Color(0, 0, 0, 0.35)
	hi.shadow_size = 8
	hi.shadow_offset = Vector2(6, 6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hi)
	b.add_theme_stylebox_override("focus", hi)
	b.add_theme_stylebox_override("pressed", hi)
	b.pressed.connect(cb)
	b.pressed.connect(func():
		if K.on_click.is_valid():
			K.on_click.call())
	b.mouse_entered.connect(func(): b.grab_focus())
	parent.add_child(b)
	return b


func _build_menu() -> void:
	menu = Control.new()
	K.full(menu)
	add_child(menu)
	# Solda koyu gecis (sehir arkada akarken yazilar okunsun)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.gradient = Gradient.new()
	gt.gradient.set_color(0, Color(0.02, 0.02, 0.05, 0.88))
	gt.gradient.set_color(1, Color(0.02, 0.02, 0.05, 0.0))
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 900
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(grad)
	# Logo: iki renkli, egik
	var logo := Control.new()
	logo.position = Vector2(60, 40)
	logo.rotation = -0.05
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(logo)
	var paw := Icon.new("paw", ACCENT2, 64)
	paw.position = Vector2(4, 8)
	logo.add_child(paw)
	_fx_label(logo, "PATİLİ", F_TITLE, 128, ACCENT, 18).position = Vector2(76, -18)
	_fx_label(logo, "GEZİNTİ", F_TITLE, 104, ACCENT2, 16).position = Vector2(40, 96)
	var tag := _fx_label(logo, "KEÇİÖREN · ANKARA", F_BODY, 26, Color.WHITE, 6)
	tag.position = Vector2(46, 218)
	# Menu maddeleri (eski kodla uyum icin Box/Continue adlari korunur)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.position = Vector2(40, 330)
	box.add_theme_constant_override("separation", 6)
	menu.add_child(box)
	var cont := _menu_item(box, "DEVAM ET", func(): continue_game.emit())
	cont.name = "Continue"
	_menu_item(box, "YENİ OYUN", func(): show_screen("setup"))
	_menu_item(box, "AYARLAR", func(): open_settings())
	if not DisplayServer.is_touchscreen_available():
		_menu_item(box, "ÇIKIŞ", func(): get_tree().quit())
	# Alt serit: ipucu
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.55)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -54
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(bar)
	var hint := _fx_label(bar, "↑ ↓  SEÇ      ENTER  ONAYLA" if not DisplayServer.is_touchscreen_available() else "BİR SEÇENEĞE DOKUN",
		F_BODY, 22, Color(1, 1, 1, 0.8))
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.offset_left = 60
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ver := _fx_label(bar, "v0.9", F_BODY, 20, Color(1, 1, 1, 0.5))
	ver.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ver.offset_right = -40
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var accent := ColorRect.new()
	accent.color = ACCENT2
	accent.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	accent.offset_top = -58
	accent.offset_bottom = -54
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(accent)


func _build_setup() -> void:
	setup = Control.new()
	K.full(setup)
	add_child(setup)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.gradient = Gradient.new()
	gt.gradient.set_color(0, Color(0.02, 0.02, 0.05, 0.92))
	gt.gradient.set_color(1, Color(0.02, 0.02, 0.05, 0.05))
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	K.full(grad)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	setup.add_child(grad)
	var head := Control.new()
	head.position = Vector2(60, 36)
	head.rotation = -0.04
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	setup.add_child(head)
	_fx_label(head, "YENİ OYUN", F_TITLE, 96, ACCENT, 16)
	var stripe := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT2
	sb.skew = Vector2(0.35, 0)
	stripe.add_theme_stylebox_override("panel", sb)
	stripe.position = Vector2(8, 104)
	stripe.size = Vector2(430, 14)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(stripe)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 8)
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 64
	col.offset_right = 720
	col.offset_top = 160
	col.offset_bottom = -20
	setup.add_child(col)
	_fill_setup()


## Egik secim karosu: secili = sari zemin siyah yazi, degil = koyu yari saydam.
func _tile(parent: Node, text: String, on: bool, cb: Callable, color := ACCENT, size := Vector2(0, 66), font_size := 38) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_override("font", F_BODY)
	b.add_theme_font_size_override("font_size", font_size)
	var fg := Color("111111") if on else Color.WHITE
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, fg)
	var st := StyleBoxFlat.new()
	st.bg_color = color if on else Color(1, 1, 1, 0.08)
	st.border_color = color
	st.set_border_width_all(0 if on else 3)
	st.skew = Vector2(0.25, 0)
	st.content_margin_left = 18
	st.content_margin_right = 18
	var hv := st.duplicate()
	hv.bg_color = color.lerp(Color.WHITE, 0.15) if on else Color(1, 1, 1, 0.2)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("focus", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.pressed.connect(cb)
	b.pressed.connect(func():
		if K.on_click.is_valid():
			K.on_click.call())
	parent.add_child(b)
	return b


func _fill_setup() -> void:
	var col: VBoxContainer = setup.find_child("Col", true, false)
	var old_name := _name_edit.text if _name_edit else ""
	for c in col.get_children():
		c.queue_free()
	_fx_label(col, "SEN KİMSİN?", F_BODY, 30, Color.WHITE, 6)
	_choice(col, [["KADIN", "kadin", "walk"], ["ERKEK", "erkek", "walk"]], _setup_owner, func(v): _setup_owner = v)
	_fx_label(col, "İLK DOSTUN", F_BODY, 30, Color.WHITE, 6)
	_choice(col, [["KÖPEK", "kopek", "paw"], ["KEDİ", "kedi", "paw"]], _setup_pet, func(v): _setup_pet = v)
	_fx_label(col, "DOSTUNUN ADI", F_BODY, 30, Color.WHITE, 6)
	_name_edit = LineEdit.new()
	_name_edit.text = old_name
	_name_edit.placeholder_text = "Pamuk" if _setup_pet == "kopek" else "Limon"
	_name_edit.max_length = 12
	_name_edit.custom_minimum_size = Vector2(0, 64)
	_name_edit.add_theme_font_override("font", F_BODY)
	_name_edit.add_theme_font_size_override("font_size", 38)
	_name_edit.add_theme_color_override("font_color", Color.WHITE)
	_name_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.4))
	_name_edit.add_theme_color_override("caret_color", ACCENT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.border_width_bottom = 5
	sb.border_color = ACCENT
	sb.content_margin_left = 22
	for s2 in ["normal", "focus"]:
		_name_edit.add_theme_stylebox_override(s2, sb)
	col.add_child(_name_edit)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	col.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	_tile(row, "GERİ", false, func(): show_screen("menu"), Color.WHITE, Vector2(200, 74), 38)
	var go := _tile(row, "BAŞLA", true, func():
		var n := _name_edit.text.strip_edges()
		start_game.emit(_setup_owner, _setup_pet, n if n != "" else _name_edit.placeholder_text), ACCENT2, Vector2(0, 74), 42)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _choice(parent: Node, options: Array, current: String, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	for o in options:
		var id: String = o[1]
		var b := _tile(row, o[0], id == current, func():
			cb.call(id)
			_fill_setup())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


# ---------------------------------------------------------------- fotograf modu

func _build_photo_hud() -> void:
	photo_hud = Control.new()
	photo_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	K.full(photo_hud)
	add_child(photo_hud)
	var back := K.button(photo_hud, "", "close", func(): photo.emit("exit"), K.CREAM, K.BROWN, Vector2(76, 76), 28, 38)
	back.position = Vector2(20, 28)
	var hint := K.outline(K.label(photo_hud, "Sürükle: kamerayı çevir  ·  İki parmak: yakınlaştır", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), 8, Color("3a2a22"))
	hint.name = "Hint"
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 46
	hint.offset_bottom = 86
	hint.offset_left = 110
	var bottom := VBoxContainer.new()
	bottom.name = "Bottom"
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -230
	bottom.offset_bottom = -24
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 16)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo_hud.add_child(bottom)
	var poses := HBoxContainer.new()
	poses.alignment = BoxContainer.ALIGNMENT_CENTER
	poses.add_theme_constant_override("separation", 10)
	bottom.add_child(poses)
	for p in [["Dur", "stand"], ["Otur", "sit"], ["Yat", "lie"], ["Zıpla", "hop"], ["Bana Bak", "look"]]:
		var id: String = p[1]
		K.button(poses, p[0], "", func(): photo.emit("pose:" + id), K.CREAM, K.BROWN, Vector2(124, 66), 21, 24)
	var shutter := K.button(bottom, "", "camera", func(): photo.emit("take"), Color.WHITE, K.BROWN, Vector2(104, 104), 38, 52)
	shutter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func set_photo_chrome(on: bool) -> void:
	for c in photo_hud.get_children():
		c.visible = on


## Komut dugmeleri yalniz dokunmatik ekranda gorunur (bilgisayarda klavye: R cagir, Bosluk zipla).
class ActionGrid extends GridContainer:
	func _process(_dt: float) -> void:
		if visible and not DisplayServer.is_touchscreen_available():
			modulate.a = 0.0
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			for c in find_children("*", "Button", true, false):
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE
