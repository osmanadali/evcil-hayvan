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
		menu.get_node("Box/Continue").visible = state.d["started"]
	if which == "hud":
		refresh()


func is_blocking() -> bool:
	return menu.visible or setup.visible or _modal != null


func _process(dt: float) -> void:
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
	clock_label = K.label(row, "10:00", 23, Color.WHITE)
	_coins = Label.new()      # para yazisi mini haritada; bu etiket yalniz eski kod icin
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
	_actions = GridContainer.new()
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


func set_context(text: String, cmd: String, icon := "star") -> void:
	if cmd == _context_cmd and _context.visible == (cmd != ""):
		return
	_context_cmd = cmd
	_context.visible = cmd != ""
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
		["Otur", "sit", "sit"], ["Yat", "minus", "lie"], ["Uyu", "moon", "sleep"]]
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
	for q in state.QUESTS:
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


func open_pause() -> void:
	var body := _open_modal("Menü", 90, 90)
	body.add_theme_constant_override("separation", 12)
	K.button(body, "Devam Et", "play", close_modal, K.GREEN, Color.WHITE, Vector2(0, 72), 26, 28)
	K.button(body, "Görevler", "list", func(): open_quests(), K.SOFT, K.BROWN, Vector2(0, 72), 26, 28)
	K.button(body, "Dolap", "shirt", func(): open_closet(), K.SOFT, K.BROWN, Vector2(0, 72), 26, 28)
	K.button(body, "Fotoğraf Çek", "camera", func():
		close_modal()
		photo.emit("enter"), K.SOFT, K.BROWN, Vector2(0, 72), 26, 28)
	K.button(body, "Ses: Açık" if state.d["sound"] else "Ses: Kapalı", "sound", func():
		state.d["sound"] = not state.d["sound"]
		open_pause(), K.SOFT, K.BROWN, Vector2(0, 72), 26, 28)
	K.button(body, "Ana Menü", "home", func(): back_to_menu.emit(), K.SOFT, K.BROWN, Vector2(0, 72), 26, 28)


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

func _build_menu() -> void:
	menu = Control.new()
	K.full(menu)
	add_child(menu)
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.09, 0.06, 0.28)
	K.full(shade)
	menu.add_child(shade)
	var title := K.outline(K.label(menu, "Patili\nGezinti", 96, Color("fff3d6"), HORIZONTAL_ALIGNMENT_CENTER), 22, Color("6b4a2f"))
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 70
	title.offset_bottom = 330
	title.add_theme_constant_override("line_spacing", -18)
	var sub := K.outline(K.label(menu, "Dostunla birlikte Keçiören'i keşfet", 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), 10, Color("6b4a2f"))
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 330
	sub.offset_bottom = 376
	var paw := Icon.new("paw", Color("fff3d6"), 70)
	paw.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	paw.offset_left = -35
	paw.offset_right = 35
	paw.offset_top = 14
	paw.offset_bottom = 78
	menu.add_child(paw)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -220
	box.offset_right = 220
	box.offset_top = -300
	box.offset_bottom = -50
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 18)
	menu.add_child(box)
	var cont := K.button(box, "Devam Et", "play", func(): continue_game.emit(), K.GREEN, Color.WHITE, Vector2(440, 88), 32, 40)
	cont.name = "Continue"
	K.button(box, "Yeni Oyun", "paw", func(): show_screen("setup"), K.CREAM, K.BROWN, Vector2(440, 88), 32, 40)


func _build_setup() -> void:
	setup = Control.new()
	K.full(setup)
	add_child(setup)
	var shade := ColorRect.new()
	shade.color = Color(0.12, 0.09, 0.06, 0.45)
	K.full(shade)
	setup.add_child(shade)
	var p := K.panel(setup, K.CREAM, 48, 0, Color.WHITE, 16)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.offset_left = -400
	p.offset_right = 400
	p.offset_top = -340
	p.offset_bottom = 340
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 10)
	K.full(col, 30, 20, 30, 22)
	p.add_child(col)
	_fill_setup()


func _fill_setup() -> void:
	var col: VBoxContainer = setup.find_child("Col", true, false)
	var old_name := _name_edit.text if _name_edit else ""
	for c in col.get_children():
		c.queue_free()
	K.label(col, "Yeni Oyun", 36, K.BROWN, HORIZONTAL_ALIGNMENT_CENTER)
	K.label(col, "Sen kimsin?", 24, K.MUTED)
	_choice(col, [["Kadın", "kadin", "walk"], ["Erkek", "erkek", "walk"]], _setup_owner, func(v): _setup_owner = v)
	K.label(col, "İlk dostun", 24, K.MUTED)
	_choice(col, [["Köpek", "kopek", "paw"], ["Kedi", "kedi", "paw"]], _setup_pet, func(v): _setup_pet = v)
	K.label(col, "Dostunun adı", 24, K.MUTED)
	_name_edit = LineEdit.new()
	_name_edit.text = old_name
	_name_edit.placeholder_text = "Pamuk" if _setup_pet == "kopek" else "Limon"
	_name_edit.max_length = 12
	_name_edit.custom_minimum_size = Vector2(0, 70)
	_name_edit.add_theme_font_size_override("font_size", 30)
	_name_edit.add_theme_color_override("font_color", K.BROWN)
	_name_edit.add_theme_color_override("font_placeholder_color", K.MUTED)
	var sb := K.style(K.SOFT, 24)
	sb.content_margin_left = 22
	for s in ["normal", "focus"]:
		_name_edit.add_theme_stylebox_override(s, sb)
	col.add_child(_name_edit)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	K.button(row, "Geri", "come", func(): show_screen("menu"), K.SOFT, K.BROWN, Vector2(180, 84), 28, 34)
	var go := K.button(row, "Başla", "play", func():
		var n := _name_edit.text.strip_edges()
		start_game.emit(_setup_owner, _setup_pet, n if n != "" else _name_edit.placeholder_text),
		K.GREEN, Color.WHITE, Vector2(0, 84), 32, 34)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _choice(parent: Node, options: Array, current: String, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	for o in options:
		var id: String = o[1]
		var on := id == current
		var b := K.button(row, o[0], o[2], func():
			cb.call(id)
			_fill_setup(), K.ORANGE if on else K.SOFT, Color.WHITE if on else K.BROWN, Vector2(0, 88), 30, 30)
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
