extends Node
## Oynanis test botu: --shot=x.png --playtest[=grup,grup] [--ptlog]
## Ozellikleri sirayla gercek fonksiyon cagrilari / tus ve fare olaylariyla tetikler; her adimi
## "ADIM ad OK" ya da "ADIM ad HATA sebep" diye yazar. Bir adim bitmezse (betik hatasi coroutine'i keser ya da
## takilma) zaman asimiyla HATA sayilir. Gruplar: telefon, harita, arac, ulasim, mekan, yasam.

const ParkMap = preload("res://scripts/park_map.gd")

var m: Node
var fails: Array = []
var steps := 0
var _done := false
var _bad := ""
var _start := Vector2.ZERO
var _verbose := false
var _token := 0


func run(main: Node, args: Dictionary) -> void:
	m = main
	main.add_child(self)
	_verbose = args.has("ptlog")
	_start = m._owner_pos()
	m.state.d["coins"] = 50000
	m.life.instant = true
	# Oyuncunun gercek kaydi testten etkilenmesin: basta yedekle, sonda geri yaz
	var save_path: String = m.state.SAVE_PATH
	var had_save := FileAccess.file_exists(save_path)
	var save_txt := FileAccess.get_file_as_string(save_path) if had_save else ""
	var want: Array = Array(String(args.get("playtest", "1")).split(",", false))
	if want.has("1"):
		want = ["telefon", "harita", "arac", "ulasim", "mekan", "yasam"]
	for fr in 20:
		await get_tree().process_frame
	for g in want:
		print("GRUP ", g)
		match g:
			"telefon": await _g_phone()
			"harita": await _g_map()
			"fare": await _g_mouse()
			"arac": await _g_vehicles()
			"ulasim": await _g_transit()
			"mekan": await _g_places()
			"yasam": await _g_life()
	if had_save:
		var sf := FileAccess.open(save_path, FileAccess.WRITE)
		if sf:
			sf.store_string(save_txt)
	elif FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("PLAYTEST BITTI adim=", steps, " hata=", fails.size(), " ", fails)


# ---------------------------------------------------------------- yardimcilar

func fr(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func bad(why: String) -> void:
	if _bad == "":
		_bad = why


func step(name: String, c: Callable, timeout := 25.0) -> void:
	steps += 1
	_done = false
	_bad = ""
	_token += 1
	var tk := _token
	print("ADIM ", name, " BASLA")
	_wrap(c, tk)
	var t0 := Time.get_ticks_msec()
	while not _done and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await get_tree().process_frame
	if not _done:
		_bad = "bitmedi (betik hatasi ya da takilma, %d sn)" % int(timeout)
		_token += 1
	if _bad != "":
		fails.append(name + ": " + _bad)
		print("ADIM ", name, " HATA ", _bad)
	else:
		print("ADIM ", name, " OK")
	await norm()


func _wrap(c: Callable, tk: int) -> void:
	await c.call()
	if tk == _token:
		_done = true


## Tus olayi: eylem adindan (Keybinds) gercek InputEventKey uretir.
func key(action: String) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k: InputEventKey = e.duplicate()
			k.pressed = true
			k.echo = false
			Input.parse_input_event(k)
			await fr(2)
			var u: InputEventKey = k.duplicate()
			u.pressed = false
			Input.parse_input_event(u)
			await fr(2)
			return
	bad("tus yok: " + action)


func keycode(code: Key) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = down
		Input.parse_input_event(k)
		await fr(2)


func click_at(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await fr(1)
	for down in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		mb.position = pos
		mb.global_position = pos
		Input.parse_input_event(mb)
		await fr(2)


## Dugmeye bas: ekranda gorunuyorsa gercek fare tiklamasi, degilse sinyal.
func press(b: Button, real := false) -> void:
	if b == null or not is_instance_valid(b):
		return
	if _verbose:
		print("    tik: ", b.text.replace("\n", " / ").left(60))
	var vr: Rect2 = get_viewport().get_visible_rect()
	if real and vr.has_point(b.get_global_rect().get_center()) and b.is_visible_in_tree():
		await click_at(b.get_global_rect().get_center())
	else:
		b.pressed.emit()
	await fr(3)


func _collect(n: Node, out: Array) -> void:
	if n is Button and (n as Button).is_visible_in_tree() and not (n as Button).disabled:
		out.append(n)
	for ch in n.get_children():
		_collect(ch, out)


## Acik pencere / telefon uygulamasindaki basilabilir dugmeler.
func buttons() -> Array:
	var out: Array = []
	var ui = m.ui
	if ui._modal == null or not is_instance_valid(ui._modal):
		return out
	if ui.phone_open():
		if ui.phone_in_app():
			_collect(ui._phone_layer, out)
		return out
	_collect(ui._modal, out)
	return out


func close_ui() -> void:
	var ui = m.ui
	if ui.radial_open():
		ui.close_radial()
	if ui._modal != null or ui._food_pop != null or ui._closet != null:
		ui.close_modal()
	m.map_screen.visible = false
	if m._mode == "photo":
		m._on_photo("exit")
	if m._mode == "closet":
		m._mode = "play"
		m.ui.show_screen("hud")
	await fr(2)


## Her adimdan sonra: pencereleri kapat, arac / mekan / oturmadan cik, baslangic noktasina don.
func norm() -> void:
	await close_ui()
	if m._mode == "metro":
		if m._metro:
			m._metro.fast = true
		var t0 := Time.get_ticks_msec()
		while m._mode == "metro" and Time.get_ticks_msec() - t0 < 30000:
			await fr(5)
	if not m._job.is_empty():
		m._end_job(false, "Test: iş bırakıldı.")
	if m._taxi != null:
		m._leave_taxi(false)
	if m._bus_ride != null:
		m._exit_bus()
	if m._ride != null:
		m._drive_speed = 0.0
		m._exit_ride_now()
	if not m._play_ride.is_empty():
		m._end_play_ride()
	if m.boat.riding():
		m.boat.phase = "docked"        # tur ortasinda: iskeleye varmis say, in
		m.boat.disembark()
	if m.seating.busy():
		m.seating.release()
	if m.eateries.is_seated():
		m.eateries.stand_up()
	if m.esnaf.is_seated():
		m.esnaf.stand_up()
	if m.street_food.is_seated():
		m.street_food.stand_up()
	if m.everyday.has_method("stop_fishing"):
		m.everyday.stop_fishing()
	var t1 := Time.get_ticks_msec()
	while (m.needs.busy() or m.life.busy() or m.fuel.busy()) and Time.get_ticks_msec() - t1 < 15000:
		await fr(5)
	if m.emlak.inside():
		m.emlak.leave()
	if m.hotel.lobby != null or m.hotel.room != null:
		m.hotel.exit_lobby()
	if m._shop != null:
		m._exit_shop()
	if m._home != null and ParkMap.home != null:
		m._exit_home()
	await close_ui()
	if m._mode != "play":
		m._mode = "play"
		m.ui.show_screen("hud")
	if m._nav != Vector2.INF:
		m._cancel_nav()
	m._moving = false
	m._queue.clear()
	m.owner_model.visible = true
	m._place_owner(_start)
	var i := 0
	for k in m.agents:
		m.agents[k].place(_start + Vector2(0.9 + 0.5 * i, 0.6))
		i += 1
	m.state.d["coins"] = maxi(int(m.state.d["coins"]), 50000)
	await fr(4)


## Bir pencereyi acan cagriyi verir; icindeki her dugmeye (en cok max_n) tek tek basar, sonra iki adim daha derine iner.
func monkey(open: Callable, max_n := 14, deep := 2) -> int:
	await open.call()
	await fr(4)
	var n: int = buttons().size()
	for i in mini(n, max_n):
		await close_ui()
		await open.call()
		await fr(4)
		var bs: Array = buttons()
		if i >= bs.size():
			break
		await press(bs[i])
		for d in deep:
			var b2: Array = buttons()
			if b2.is_empty():
				break
			await press(b2[mini(d + (i % 3), b2.size() - 1)])
		if m._mode == "metro":
			await norm()
	await close_ui()
	return n


func goto(p: Vector2) -> void:
	m._place_owner(p)
	var i := 0
	for k in m.agents:
		m.agents[k].place(p + Vector2(0.9 + 0.5 * i, 0.6))
		i += 1
	await fr(6)
	m._update_context()


func ctx() -> String:
	return m.ui._context_cmd


# ---------------------------------------------------------------- telefon

func _phone_names() -> Array:
	m._open_phone()
	var names: Array = m.ui._phone_buttons.keys()
	m.ui.close_modal()
	return names


func _g_phone() -> void:
	await step("telefon: P tusuyla ac / Esc ile kapat", func():
		await key("phone")
		await fr(8)
		if not m.ui.phone_open():
			bad("P tusu telefonu acmadi")
		await keycode(KEY_ESCAPE)
		await fr(4)
		if m.ui.phone_open():
			bad("Esc telefonu kapatmadi"))
	var names: Array = _phone_names()
	await fr(3)
	print("TELEFON uygulamalar=", names.size(), " ", names)
	for nm in names:
		var app: String = String(nm)
		await step("telefon: " + app, func():
			# 1) gercek fare tiklamasiyla ac
			m._open_phone()
			await wait(0.7)
			var b: Button = m.ui.phone_app_button(app)
			if b == null:
				bad("simge yok")
				return
			var vis: bool = get_viewport().get_visible_rect().has_point(b.get_global_rect().get_center())
			await press(b, true)
			await wait(0.3)
			print("    fareyle: ekranda=", vis, " uygulama=", m.ui.phone_in_app(), " telefon=", m.ui.phone_open(), " mod=", m._mode)
			await close_ui()
			# 2) uygulamanin icindeki her dugme
			var cnt: int = await monkey(func():
				m._open_phone()
				await fr(3)
				var bb: Button = m.ui.phone_app_button(app)
				if bb != null:
					bb.pressed.emit()
				await fr(3))
			print("    dugme=", cnt), 90.0)


# ---------------------------------------------------------------- buyuk harita

func _g_map() -> void:
	var ms = m.map_screen
	await step("harita: M tusu, ac-kapa 3 kez", func():
		for i in 3:
			await key("map")
			await fr(6)
			if not ms.visible:
				bad("M haritayi acmadi (%d)" % i)
			await keycode(KEY_ESCAPE)
			await fr(4)
			if ms.visible:
				bad("Esc haritayi kapatmadi"))
	await step("harita: telefondan Tam Ekran, tiklama, yakinlastirma, surukleme", func():
		m._open_phone()
		await wait(0.8)
		await press(m.ui.phone_app_button("Harita"), true)
		await wait(0.5)
		if not m.ui.phone_in_app():
			bad("fare tiklamasi Harita uygulamasini acmadi")
			return
		var tb: Button = m._find_button(m.ui, "Tam Ekran")
		if tb == null:
			bad("Tam Ekran Harita dugmesi yok")
			return
		await press(tb, true)
		await fr(8)
		if not ms.visible:
			bad("tam ekran harita acilmadi")
			return
		var vr: Rect2 = ms._view.get_global_rect()
		for f in [Vector2(0.5, 0.5), Vector2(0.3, 0.4), Vector2(0.7, 0.6), Vector2(0.2, 0.8), Vector2(0.85, 0.2), Vector2(0.5, 0.3)]:
			await click_at(vr.position + vr.size * f)
			await fr(3)
		for wheel in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_DOWN]:
			var mb := InputEventMouseButton.new()
			mb.button_index = wheel
			mb.pressed = true
			mb.position = vr.get_center()
			mb.global_position = vr.get_center()
			Input.parse_input_event(mb)
			await fr(2)
		# surukleme
		var p0: Vector2 = vr.get_center()
		var d := InputEventMouseButton.new()
		d.button_index = MOUSE_BUTTON_LEFT
		d.pressed = true
		d.position = p0
		d.global_position = p0
		Input.parse_input_event(d)
		await fr(1)
		for i in 8:
			var mm := InputEventMouseMotion.new()
			mm.position = p0 + Vector2(12 * i, 7 * i)
			mm.global_position = mm.position
			mm.relative = Vector2(12, 7)
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(mm)
			await fr(1)
		var u: InputEventMouseButton = d.duplicate()
		u.pressed = false
		u.position = p0 + Vector2(96, 56)
		u.global_position = u.position
		Input.parse_input_event(u)
		await fr(3))
	await step("harita: her isarete yol tarifi (rota), iptal", func():
		m._open_map()
		await fr(6)
		var n: int = ms.PINS.size()
		var empty := 0
		for i in n:
			if not ms.visible:
				m._open_map()
				await fr(3)
			if i >= ms.PINS.size():
				break
			ms.select_by_name(ms.PINS[i][0])
			await fr(1)
			ms._nav()
			await fr(2)
			if m._nav == Vector2.INF and (ms.PINS[i][2] as Vector2).distance_to(m._owner_pos()) > 40.0:
				bad("rota kurulmadi: " + str(ms.PINS[i][0]))
			if i % 6 == 0:
				await fr(20)       # mini harita rotasi hesaplansin
				m._open_map()
				await fr(3)
				if ms.route.is_empty():
					empty += 1
				ms._cancel_route()
				await fr(2)
		print("    isaret=", n, " bos rota=", empty)
		if not ms.visible:
			m._open_map()
			await fr(3)
		var nb: Button = ms._sheet.get_node("Nav")
		ms._select(0)
		await fr(2)
		await press(nb, true)
		await fr(4)
		if ms.visible:
			bad("Yol Tarifi dugmesi haritayi kapatmadi")
		if m._nav == Vector2.INF:
			bad("Yol Tarifi dugmesi rota kurmadi"), 120.0)
	await step("harita: rota varken ac, rotayi goster / iptal dugmeleri", func():
		m._set_nav(ms.PINS[mini(5, ms.PINS.size() - 1)][2], "Test")
		await fr(30)
		m._open_map()
		await fr(6)
		var bs: Array = []
		_collect(ms, bs)
		print("    harita dugmeleri=", bs.size())
		for i in bs.size():
			if not ms.visible:
				m._set_nav(ms.PINS[mini(5, ms.PINS.size() - 1)][2], "Test")
				m._open_map()
				await fr(4)
			var b2: Array = []
			_collect(ms, b2)
			if i < b2.size():
				await press(b2[i])
		await fr(3))
	await step("harita: mini haritaya tikla", func():
		m.minimap.tapped.emit()
		await fr(5)
		if not ms.visible:
			bad("mini harita tiklamasi haritayi acmadi"))


## Gercek fare tiklamalari (yalnizca pencereli calismada, or. xvfb; headless fare olayi iletmez):
## telefon simgesi -> Harita -> Tam Ekran Harita -> haritaya tikla -> Yol Tarifi; sonra ikinci kez ac.
func _g_mouse() -> void:
	var ms = m.map_screen
	await step("fare: telefon > Harita > Tam Ekran > isarete tikla > Yol Tarifi (2 tur)", func():
		for turn in 2:
			m._open_phone()
			await wait(1.0)
			await press(m.ui.phone_app_button("Harita"), true)
			await wait(0.6)
			if not m.ui.phone_in_app():
				bad("fare tiklamasi Harita uygulamasini acmadi (tur %d)" % turn)
				return
			var tb: Button = m._find_button(m.ui, "Tam Ekran")
			if tb == null:
				bad("Tam Ekran Harita dugmesi yok")
				return
			await press(tb, true)
			await wait(0.6)
			if not ms.visible:
				bad("tam ekran harita acilmadi (tur %d)" % turn)
				return
			var vr: Rect2 = ms._view.get_global_rect()
			for f in [Vector2(0.3, 0.4), Vector2(0.7, 0.6), Vector2(0.5, 0.3), Vector2(0.45, 0.55)]:
				await click_at(vr.position + vr.size * f)
				await fr(2)
			print("    secili=", ms._selected, " isaretli=", ms._custom != Vector2.INF, " baslik=", ms._sheet_title.text)
			if ms._selected < 0 and ms._custom == Vector2.INF:
				bad("haritaya tiklama hedef secmedi (tur %d)" % turn)
			var nb: Button = ms._sheet.get_node("Nav")
			await press(nb, true)
			await wait(0.5)
			if ms.visible or m._nav == Vector2.INF:
				bad("Yol Tarifi dugmesi rota kurmadi (tur %d): harita=%s" % [turn, ms.visible])
			await wait(1.0)
			print("    rota dugum=", m.minimap.route.size(), " hedef=", m.minimap.dest_name), 400.0)
	await step("fare: telefon simgeleri (ilk 6) tiklaninca acilir", func():
		for app in ["Mesajlar", "İş Bul", "Sosyal", "Banka", "EvBul", "Otel"]:
			m._open_phone()
			await wait(0.9)
			var b: Button = m.ui.phone_app_button(app)
			if b == null:
				continue
			var vis: bool = get_viewport().get_visible_rect().has_point(b.get_global_rect().get_center())
			await press(b, true)
			await wait(0.5)
			print("    ", app, " ekranda=", vis, " uygulama=", m.ui.phone_in_app())
			if vis and not m.ui.phone_in_app():
				bad(app + " fareyle acilmadi")
			await close_ui(), 400.0)


# ---------------------------------------------------------------- araclar

func _g_vehicles() -> void:
	var kinds := {}
	for r in m._rides:
		kinds[r.get_meta("kind", "?")] = true
	print("ARAC turleri=", kinds.keys(), " adet=", m._rides.size())
	for kind in kinds.keys():
		await step("arac: %s bin (F), sur, ic kamera (V), far, radyo, in (F)" % kind, func():
			var target: Node3D = null
			for r in m._rides:
				if r.get_meta("kind", "") == kind and not r.has_meta("garage"):
					target = r
					break
			if target == null:
				bad("arac yok")
				return
			m.life.instant = false          # gercek binme hareketi
			var side: Vector2 = Vector2(target.position.x, target.position.z) + Vector2(1.7, 0.3).rotated(-target.rotation.y)
			await goto(side)
			await fr(10)
			m._update_context()
			await key("interact")
			var t0 := Time.get_ticks_msec()
			while (m._ride == null or m.life.busy()) and Time.get_ticks_msec() - t0 < 8000:
				await fr(3)
			if m._ride == null:
				bad("F ile binilmedi (baglam=%s)" % ctx())
				m.life.instant = true
				return
			await key("fps_view")
			await fr(10)
			await key("headlights")
			await key("radio")
			await key("radio")
			# gaz: 2.5 sn ileri, 1 sn sola, fren
			_hold_key(KEY_W, true)
			await wait(2.5)
			_hold_key(KEY_A, true)
			await wait(1.0)
			_hold_key(KEY_A, false)
			_hold_key(KEY_W, false)
			print("    hiz=%.1f konum=%s" % [m._drive_speed, m._owner_pos().round()])
			_hold_key(KEY_S, true)
			await wait(1.2)
			_hold_key(KEY_S, false)
			await key("fps_view")
			await fr(6)
			m._drive_speed = 0.0
			await fr(3)
			await key("interact")
			var t1 := Time.get_ticks_msec()
			while (m._ride != null or m.life.busy()) and Time.get_ticks_msec() - t1 < 8000:
				await fr(3)
			m.life.instant = true
			if m._ride != null:
				bad("F ile inilmedi")
			if not m.owner_model.visible:
				bad("inince karakter gorunmuyor"), 40.0)
	await step("arac: trafik arabasina bin / in", func():
		var c: Node3D = null
		var o: Vector2 = m._owner_pos()
		for x in m._cars:
			if is_instance_valid(x) and x.visible and not (m._car_model(x) in ["taksi", "dolmus"]):
				if c == null or o.distance_to(Vector2(x.position.x, x.position.z)) < o.distance_to(Vector2(c.position.x, c.position.z)):
					c = x
		if c == null:
			print("    trafik arabasi yok (atlandi)")
			return
		await goto(Vector2(c.position.x, c.position.z) + Vector2(1.8, 0.0).rotated(-c.rotation.y))
		m._enter_ride()
		await fr(20)
		print("    binildi=", m._ride != null)
		if m._ride != null:
			await wait(1.0)
			m._drive_speed = 0.0
			m._exit_ride()
			await fr(20))
	await step("arac: Arabam cagir (telefon) ve bin", func():
		m._summon_my_car()
		await wait(2.0)
		await close_ui())
	await step("arac: galeri paneli", func():
		if m.dealer.center == Vector2.INF:
			print("    galeri yok (atlandi)")
			return
		await monkey(func():
			m.dealer.open_panel()
			await fr(2)), 60.0)
	await step("arac: benzinlik", func():
		if m.world.fuel_stations.is_empty():
			print("    benzinlik yok (atlandi)")
			return
		m.fuel.debug_at_pump("panel")
		await fr(10)
		for b in buttons().slice(0, 6):
			if is_instance_valid(b):
				await press(b)
		await wait(1.0), 40.0)


func _hold_key(code: Key, down: bool) -> bool:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = down
	Input.parse_input_event(k)
	return down


# ---------------------------------------------------------------- toplu tasima

func _far_pin(dmin: float, dmax: float) -> int:
	var o: Vector2 = m._owner_pos()
	for i in m.map_screen.PINS.size():
		var d: float = (m.map_screen.PINS[i][2] as Vector2).distance_to(o)
		if d > dmin and d < dmax:
			return i
	return 0


func _g_transit() -> void:
	for model in ["taksi", "dolmus"]:
		await step("ulasim: %s cagir, bin, yolcu kamerasi, in" % model, func():
			if m.map_screen.PINS.is_empty():
				m._open_map()
				await fr(3)
				m.map_screen.visible = false
			var pi: int = _far_pin(250.0, 700.0)
			m._set_nav(m.map_screen.PINS[pi][2], m.map_screen.PINS[pi][0])
			await fr(10)
			m._call_taxi(model)
			await close_ui()
			var tx: Node3D = null
			var stop_at: Vector2 = m._nav
			Engine.time_scale = 3.0
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 25000 and tx == null:
				await fr(10)
				for c in m._cars:
					if is_instance_valid(c) and m._car_model(c) == model and c.hold > 0.0 and stop_at.distance_to(Vector2(c.position.x, c.position.z)) < 14.0:
						tx = c
			Engine.time_scale = 1.0
			print("    cagrilan arac geldi=", tx != null, " (%.0f sn)" % ((Time.get_ticks_msec() - t0) / 1000.0 * 3.0))
			if tx == null:
				bad("cagrilan %s 75 sn'de kaldirima gelmedi" % model)
				for c in m._cars:
					if is_instance_valid(c) and m._car_model(c) == model:
						tx = c
						break
			m._set_nav(m.map_screen.PINS[pi][2], m.map_screen.PINS[pi][0])
			if tx == null:
				bad(model + " bulunamadi")
				return
			await goto(Vector2(tx.position.x, tx.position.z) + Vector2(1.6, 0.0).rotated(-tx.rotation.y))
			await fr(6)
			m._update_context()
			print("    baglam=", ctx())
			if ctx() != "":
				await key("interact")
			else:
				m._board_taxi(tx)
			await fr(10)
			if m.map_screen.visible:
				m.map_screen.visible = false
				m._set_nav(m.map_screen.PINS[pi][2], m.map_screen.PINS[pi][0])
				m._board_taxi(tx)
				await fr(5)
			if m._taxi == null:
				bad("binilemedi")
				return
			print("    yol=", m._taxi_path.size(), " ucret=", m._taxi_fare)
			m.pview.set_on(true)
			await wait(4.0)
			m.pview.set_on(false)
			await wait(2.0)
			await key("interact")      # taksi: in / dolmus: inecek var
			var t1 := Time.get_ticks_msec()
			while m._taxi != null and Time.get_ticks_msec() - t1 < 15000:
				await fr(5)
			if m._taxi != null:
				bad("inilemedi (F)")
			if not m.owner_model.visible:
				bad("inince karakter gorunmuyor"), 60.0)
	await step("ulasim: taksiyle hedefe kadar git (hizli)", func():
		var pi: int = _far_pin(120.0, 260.0)
		var tx: Node3D = null
		for c in m._cars:
			if is_instance_valid(c) and m._car_model(c) == "taksi":
				tx = c
				break
		if tx == null:
			print("    taksi yok (atlandi)")
			return
		m._set_nav(m.map_screen.PINS[pi][2], m.map_screen.PINS[pi][0])
		await goto(Vector2(tx.position.x, tx.position.z) + Vector2(1.6, 0.0).rotated(-tx.rotation.y))
		m._board_taxi(tx)
		await fr(4)
		if m._taxi == null:
			bad("binilemedi")
			return
		Engine.time_scale = 4.0
		var t0 := Time.get_ticks_msec()
		while m._taxi != null and Time.get_ticks_msec() - t0 < 60000:
			await fr(10)
		Engine.time_scale = 1.0
		if m._taxi != null:
			bad("60 sn'de (4x) varilamadi; kalan dugum=%d/%d" % [m._taxi_i, m._taxi_path.size()])
		else:
			print("    varildi, hedefe uzaklik=%.0f" % m._owner_pos().distance_to(m.map_screen.PINS[pi][2])), 80.0)
	await step("ulasim: otobuse bin, yolcu kamerasi, in", func():
		if m._buses.is_empty():
			print("    otobus yok (atlandi)")
			return
		var got := false
		Engine.time_scale = 3.0
		for i in 240:
			for b in m._buses:
				if b.at_stop != "" and b.visible and ParkMap.inside_bounds(Vector2(b.position.x, b.position.z), 20.0):
					await goto(Vector2(b.position.x, b.position.z) + Vector2(3, 0))
					m._update_context()
					print("    durak=", b.at_stop, " baglam=", ctx())
					if ctx() == "bus":
						await key("interact")
					else:
						m._enter_bus()
					await fr(4)
					break
			if m._bus_ride != null:
				got = true
				break
			await fr(15)
		Engine.time_scale = 1.0
		if not got:
			bad("durakta otobus yakalanamadi")
			return
		m.pview.set_on(true)
		await wait(3.0)
		m.pview.set_on(false)
		Engine.time_scale = 4.0
		var t0 := Time.get_ticks_msec()
		var left := false
		while Time.get_ticks_msec() - t0 < 40000:
			await fr(10)
			m._update_context()
			if ctx() == "busexit":
				await key("interact")
				await fr(6)
				left = m._bus_ride == null
				break
		Engine.time_scale = 1.0
		if not left:
			print("    40 sn'de (4x) inilecek durak gelmedi; zorla iniliyor")
			m._exit_bus()
		if m._bus_ride != null:
			bad("otobusten inilemedi"), 150.0)
	await step("ulasim: metro penceresi ve ayni bolgede yolculuk", func():
		if m.world.metro_gates.is_empty():
			print("    metro girisi yok (atlandi)")
			return
		var g: Dictionary = m.world.metro_gates[0]
		await goto(g["pos"] + Vector2(1.5, 0))
		m._update_context()
		print("    baglam=", ctx(), " giris=", g["name"], " adet=", m.world.metro_gates.size())
		if ctx() != "":
			await key("interact")
		else:
			m._open_metro()
		await fr(6)
		var bs: Array = buttons()
		print("    durak dugmesi=", bs.size())
		await close_ui()
		# bolge degistirmeyen yolculuk (sahne yeniden yuklenmesin): ayni bolgedeki baska giris
		var dest := ""
		for g2 in m.world.metro_gates:
			if g2["name"] != g["name"]:
				dest = g2["name"]
		if dest == "":
			dest = g["name"]
		m._travel(dest, ParkMap.zone)
		await fr(10)
		if m._mode != "metro":
			bad("metro yolculugu baslamadi")
			return
		m._metro.auto = true       # perondan trene kendi yurur (oyuncu WASD ile yurur)
		await wait(3.0)
		await key("jump")          # hizlandir
		var t0 := Time.get_ticks_msec()
		while m._mode == "metro" and Time.get_ticks_msec() - t0 < 60000:
			await fr(10)
		if m._mode == "metro":
			bad("metro 60 sn'de bitmedi")
		elif not m.owner_model.visible:
			bad("metrodan cikinca karakter gorunmuyor"), 90.0)
	await step("ulasim: bisiklet kiralama / taksi duragi (tplus)", func():
		for a in ["bikerent", "taxirank"]:
			m.tplus.debug(a)
			await wait(1.5)
			m._update_context()
			print("    ", a, " baglam=", ctx())
			if ctx() != "":
				await key("interact")
				await fr(10)
				for b in buttons().slice(0, 4):
					if is_instance_valid(b):
						await press(b)
			await wait(1.0)
			await norm(), 60.0)
	await step("ulasim: gol turu / pedalli bot", func():
		if not m.boat.built:
			print("    gol turu yok (atlandi)")
			return
		await monkey(func():
			m.boat.open_menu()
			await fr(2), 6, 0)
		await norm()
		await m.boat.debug_board("tour", 2.0)
		await wait(2.0)
		await norm()
		await m.boat.debug_board("pedal", 2.0)
		await wait(2.0), 90.0)


# ---------------------------------------------------------------- mekanlar

## Bir noktaya git; [F] baglami cikarsa bas, acilan pencerenin dugmelerini dene.
func visit(p: Vector2, label: String, tries := 2) -> void:
	await goto(p)
	var c := ctx()
	print("    ", label, " baglam=", c)
	for i in tries:
		m._update_context()
		if ctx() == "":
			break
		await key("interact")
		await fr(10)
		var bs: Array = buttons()
		for j in mini(bs.size(), 5):
			var b2: Array = buttons()
			if j < b2.size():
				await press(b2[j])
		await close_ui()
		await wait(0.4)


func _g_places() -> void:
	var kinds := {}
	for sp in m.world.shop_spots:
		kinds[sp.get("kind", "")] = sp
	print("DUKKAN turleri=", kinds.keys())
	for kd in kinds.keys():
		await step("mekan: dukkan '%s' gir, gez, sepet, kasa, cik" % kd, func():
			var sp: Dictionary = kinds[kd]
			m._enter_shop(sp)
			await fr(15)
			if m._shop == null:
				bad("girilemedi")
				return
			m._update_context()
			print("    icerde baglam=", ctx())
			if kd == "market" or "shelves" in m._shop:
				m._take_basket()
				for id in ["simit", "mama", "su"]:
					m._put_in_basket(id)
				await fr(4)
				m._pay_cart()
				await fr(6)
				await close_ui()
			# ic mekanda birkac noktaya yuru, F'ye bas
			for l in [Vector2(0, 0), Vector2(2.0, 2.0), Vector2(-2.0, 1.5), Vector2(3.0, 3.15), Vector2(0, -2.0)]:
				if m._shop == null:
					break
				if m._shop.has_method("w2"):
					m._place_owner(m._shop.w2(l))
					await fr(5)
					m._update_context()
					if ctx() != "":
						if _verbose:
							print("    F: ", ctx())
						await key("interact")
						await fr(8)
						for b in buttons().slice(0, 4):
							if is_instance_valid(b):
								await press(b)
						await close_ui()
			if m._shop != null:
				m._exit_shop()
			await fr(8)
			if m._shop != null:
				bad("cikilamadi"), 60.0)
	# Lokantalar / ek marketler
	var styles := {}
	for pl in m.eateries.places:
		styles[str(pl.get("kind", "")) + ":" + str(pl.get("style", ""))] = pl
	print("LOKANTA turleri=", styles.keys(), " adet=", m.eateries.places.size())
	for mode in ["order", "sit", "1"]:
		await step("mekan: lokanta (%s): otur, menu, siparis, ode" % mode, func():
			m.eateries.debug_enter(mode == "order", mode, "")
			await wait(2.0)
			m._update_context()
			print("    baglam=", ctx(), " oturuyor=", m.eateries.is_seated(), " dukkan=", m._shop != null)
			await monkey(func():
				m.eateries.open_menu()
				await fr(2), 8, 1)
			if m._shop != null:
				m._update_context()
				if ctx() != "":
					await key("interact")
					await fr(10)
					await close_ui()
				if m.eateries.is_seated():
					m.eateries.pay()
					await fr(6)
					await close_ui(), 60.0)
	await step("mekan: her lokanta / ek market kapisi (F ile gir-cik)", func():
		for pl in m.eateries.places:
			await visit(pl["pos"], str(pl["name"]), 1)
			if m._shop != null:
				await wait(0.5)
				m._exit_shop()
				await fr(6)
			await close_ui(), 120.0)
	await step("mekan: Yakinimda uygulamasi", func():
		await monkey(func():
			m.eateries.nearby_app()
			await fr(2), 10, 1), 60.0)
	# Esnaf
	for i in m.esnaf.shops.size():
		var es: Dictionary = m.esnaf.shops[i]
		await step("mekan: esnaf %s (%s)" % [es.get("name", "?"), es.get("kind", "?")], func():
			await visit(es["pos"], str(es.get("name", "")), 2)
			await monkey(func():
				m.esnaf.open_shop(i)
				await fr(2), 8, 1), 60.0)
	for what in [["berber", "panel"], ["kahvehane", "sit"], ["kahvehane", "tavla"], ["kahvehane", "okey"], ["cuma", "1"], ["dugun", "1"]]:
		await step("mekan: esnaf ozel %s=%s" % what, func():
			m.esnaf.debug(what[0], what[1])
			await wait(1.5)
			for r in 6:
				var bs: Array = buttons()
				if bs.is_empty():
					break
				await press(bs[mini(r % 3, bs.size() - 1)])
			await wait(0.5), 40.0)
	# Sokak lezzetleri
	await step("mekan: simitci arabasi ve cay ocagi", func():
		for c in m.street_food.carts:
			await visit(c["pos"] if c is Dictionary and c.has("pos") else _start, "simitci", 1)
			break
		m.street_food.debug_cart()
		await fr(10)
		await monkey(func():
			m.street_food.open_menu("cart")
			await fr(2), 6, 0)
		m.street_food.debug_sit()
		await wait(2.0)
		m._update_context()
		print("    cay baglam=", ctx(), " oturuyor=", m.street_food.is_seated())
		if ctx() != "":
			await key("interact")
		await wait(1.0), 60.0)
	await step("mekan: pazar, dondurmaci, balik tutma", func():
		for kv in [["pazar", "1"], ["dondurma", "1"], ["dondurma", "trick"], ["fish", "1"], ["fish", "cast"]]:
			m.everyday.debug(kv[0], kv[1])
			await wait(1.2)
			for b in buttons().slice(0, 3):
				if is_instance_valid(b):
					await press(b)
			await close_ui()
			m._update_context()
			if ctx() != "":
				await key("interact")
				await fr(8)
			await close_ui()
			m.everyday.stop_fishing(), 60.0)
	# Oturma
	await step("mekan: oturma (bank / sandalye) otur-kalk", func():
		m.seating.debug_sit()
		await wait(1.5)
		if not m.seating.busy():
			bad("oturulamadi")
			return
		await key("interact")
		await wait(2.0)
		if m.seating.busy():
			# hareket tusuyla kalk
			_hold_key(KEY_W, true)
			await wait(0.4)
			_hold_key(KEY_W, false)
			await wait(1.5)
		if m.seating.busy():
			bad("kalkilamadi (F / W)")
		# en yakin 4 koltuk
		var o: Vector2 = _start
		var ss: Array = m.seating.seats.duplicate()
		ss.sort_custom(func(a, b): return o.distance_to(a["pos"]) < o.distance_to(b["pos"]))
		for s in ss.slice(0, 4):
			m.seating.sit(s)
			await wait(0.6)
			m.seating.stand_up()
			await wait(1.2)
		print("    koltuk=", ss.size()), 60.0)
	await step("mekan: bankta kestirme", func():
		if m.world.benches.is_empty():
			return
		m.needs.me()["energy"] = 20.0
		var bb: Array = m.world.benches[0]
		for b in m.world.benches:
			if _start.distance_to(b[0]) < _start.distance_to(bb[0]):
				bb = b
		await goto(bb[0] + Vector2(-sin(bb[1]), -cos(bb[1])) * 1.0)
		print("    baglam=", ctx())
		m.needs.nap(bb)
		var t0 := Time.get_ticks_msec()
		while m.needs.busy() and Time.get_ticks_msec() - t0 < 30000:
			await fr(5)
		if m.needs.busy():
			bad("kestirme 30 sn'de bitmedi"), 45.0)
	# Otel + kayit / yukleme
	await step("mekan: otel lobisi, resepsiyon, oda kirala", func():
		if m.hotel.center == Vector2.INF:
			print("    otel yok (atlandi)")
			return
		await visit(m.hotel.door_pos(), "otel kapisi", 1)
		await norm()
		await m.hotel.debug("panel", false)
		await fr(6)
		await monkey(func():
			if m.hotel.lobby == null:
				m.hotel.enter_lobby(false, true)
			m.hotel.open_desk()
			await fr(2), 8, 1), 60.0)
	await step("mekan: otel odasi: yatak, oda servisi, minibar, kayit, uyku", func():
		if m.hotel.center == Vector2.INF:
			return
		await m.hotel.debug("panel", true)
		await fr(6)
		await close_ui()
		for opener in ["open_room_bed", "open_service", "open_minibar"]:
			await monkey(func():
				if m.hotel.room == null:
					m.hotel.info()["room"] = true
					m.hotel.info()["nights"] = 1
					m.hotel.enter_room(true)
				m.hotel.call(opener)
				await fr(2), 6, 1)
			var t0 := Time.get_ticks_msec()
			while m.needs.busy() and Time.get_ticks_msec() - t0 < 20000:
				await fr(5)
		if m.hotel.room == null:
			m.hotel.info()["room"] = true
			m.hotel.info()["nights"] = 1
			m.hotel.enter_room(true)
		m.hotel.save_now("Test · Oda")
		await wait(0.6)
		print("    kayit yer=", m.state.d.get("save_place"), " pos_in=", m.state.d.get("pos_in"))
		if str(m.state.d.get("save_place", "")) == "":
			bad("kayit noktasi yazilmadi"), 120.0)
	await step("mekan: kayit / yukleme (diske yaz, oku, kayit noktasina don)", func():
		var coins: int = int(m.state.d["coins"])
		m.state.save_game()
		m.state.d["coins"] = 1
		m.state.load_game()
		if int(m.state.d["coins"]) != coins:
			bad("yukleme parayi geri getirmedi: %s != %s" % [m.state.d["coins"], coins])
		m.hotel.restore_pending = true
		m.hotel.on_enter_play()
		await fr(10)
		print("    geri donus: otel odasi=", m.hotel.room != null, " lobi=", m.hotel.lobby != null, " emlak=", m.emlak.inside()))
	await step("mekan: ev (gir, yatak, mutfak, dolap, cik)", func():
		if ParkMap.zone != "":
			print("    bu bolgede ev yok (atlandi)")
			return
		await goto(m.HOME_DOOR + m.HOME_DOOR_OUT * 1.2)
		print("    kapi baglam=", ctx())
		if ctx() != "":
			await key("interact")
		else:
			m._enter_home()
		await fr(15)
		if ParkMap.home == null:
			bad("eve girilemedi")
			return
		for what in ["cook", "furnish", "decor", "plants", "mess"]:
			m.home_life.debug_setup(what)
			await fr(6)
			for b in buttons().slice(0, 4):
				if is_instance_valid(b):
					await press(b)
			await close_ui()
			var t0 := Time.get_ticks_msec()
			while m.home_life.busy() and Time.get_ticks_msec() - t0 < 15000:
				await fr(5)
			m._update_context()
			if ctx() != "":
				await key("interact")
				await fr(8)
				await close_ui()
		await monkey(func():
			m.home_life.open_cook_panel()
			await fr(2), 6, 0)
		await monkey(func():
			m.hotel.open_home_bed()
			await fr(2), 4, 0)
		var t1 := Time.get_ticks_msec()
		while m.needs.busy() and Time.get_ticks_msec() - t1 < 25000:
			await fr(5)
		m._open_closet()
		await fr(10)
		await close_ui()
		if ParkMap.home != null:
			m._exit_home()
		await fr(8), 120.0)
	await step("mekan: ATM, banka, faturalar", func():
		m.bank.debug_atm()
		await fr(8)
		await close_ui()
		await monkey(func():
			m.bank.open_atm()
			await fr(2), 8, 1)
		m.bank.debug_bills()
		await fr(6)
		await monkey(func():
			m.bank.open_bills(true)
			await fr(2), 6, 1), 60.0)
	await step("mekan: veteriner muayene", func():
		for sp in m.world.shop_spots:
			if sp.get("kind", "") == "vet" or sp.get("kind", "") == "veteriner":
				m.state.pet(m.state.d["active"])["sick"] = "Öksürük"
				m._enter_shop(sp)
				await fr(10)
				if m._shop != null and "exam_local" in m._shop:
					m._place_owner(m._shop.w2(m._shop.exam_local))
				await monkey(func():
					m._open_vet()
					await fr(2), 8, 1)
				return
		print("    veteriner dukkani yok (atlandi)"), 60.0)


# ---------------------------------------------------------------- yasam

func _g_life() -> void:
	for jk in ["taxi", "garson", "bakici"]:
		await step("yasam: meslek %s (basla, calistir, bitir)" % jk, func():
			await m.meslek.debug(jk, true)
			await wait(1.0)
			m._update_context()
			print("    baglam=", ctx(), " is=", m._job.get("type", "-"))
			if ctx() != "":
				await key("interact")
				await fr(8), 90.0)
	for jk in ["dog", "courier"]:
		await step("yasam: is %s" % jk, func():
			if jk == "dog":
				m._start_dog_walk()
			else:
				m._start_courier()
			await fr(10)
			for st in 3:
				if m._job.is_empty():
					break
				m._place_owner(m._job["client_pos"] if m._job["type"] == "dog" and m._job["stage"] == "back" else m._job["target"])
				await wait(0.8)
			print("    is bitti=", m._job.is_empty()), 40.0)
	await step("yasam: Is Bul penceresi ve gun sonu ozeti (J)", func():
		await key("jobs")
		await fr(8)
		if buttons().is_empty():
			bad("J is penceresini acmadi")
		await close_ui()
		await monkey(func():
			m._open_jobs()
			await fr(2), 10, 1)
		await norm()
		m.meslek.open_summary()
		await fr(6), 90.0)
	await step("yasam: EvBul (ilanlar, gez, kirala, satin al, tasin)", func():
		await monkey(func():
			m.emlak.open_app()
			await fr(2), 8, 2)
		await norm()
		var n: int = m.emlak.listings.size()
		print("    ilan=", n)
		for i in mini(n, 6):
			m.emlak.open_listing(i)
			await fr(4)
			for b in buttons().slice(0, 3):
				if is_instance_valid(b):
					await press(b)
			await close_ui()
			m.emlak.enter(i, true)
			await fr(10)
			m._update_context()
			if ctx() != "":
				await key("interact")
				await fr(6)
				await close_ui()
			if m.emlak.inside():
				m.emlak.leave()
			await fr(6)
		if n > 0:
			m.emlak.rent(0)
			await fr(4)
			await close_ui()
			m.emlak.buy(mini(1, n - 1))
			await fr(4)
			await close_ui()
			m.emlak.move_in(0)
			await fr(4)
			await close_ui()
			m._open_map()
			await fr(4), 120.0)
	await step("yasam: Patigram (fotograf cek, gonderi, uygulama)", func():
		await key("photo")
		await fr(8)
		if m._mode != "photo":
			bad("C fotograf modunu acmadi")
			return
		var acts: Array = ["pose:sit", "pose:hop", "pose:look"]
		if DisplayServer.get_name() != "headless":
			acts.append("take")          # headless'ta ekran goruntusu yok
		for a in acts:
			m._on_photo(a)
			await wait(0.5)
		await wait(1.0)
		m._on_photo("exit")
		await fr(5)
		m.patigram.add_post("test_yok.png")
		await monkey(func():
			m._open_phone()
			await fr(3)
			m.ui.phone_app_button("Patigram").pressed.emit()
			await fr(3), 8, 1), 60.0)
	await step("yasam: sosyal (arkadas bulusmasi, bayram, iftar, mesajlar, sohbet)", func():
		m.social.debug_friendmeet()
		await wait(1.5)
		m._update_context()
		print("    bulusma baglam=", ctx())
		if ctx() != "":
			await key("interact")
			await fr(8)
		for r in 4:
			var bs: Array = buttons()
			if bs.is_empty():
				break
			await press(bs[0])
		await norm()
		m.social.debug_bayram()
		await wait(1.0)
		m._update_context()
		if ctx() != "":
			await key("interact")
			await fr(8)
		await norm()
		m.social.debug_iftar()
		await wait(1.0)
		m._update_context()
		print("    iftar baglam=", ctx())
		if ctx() != "":
			await key("interact")
			await wait(1.0)
		await norm()
		await key("messages")
		await fr(8)
		await monkey(func():
			m.neighbors.open_messages()
			await fr(2), 8, 2)
		await norm()
		m.neighbors.debug_msgs()
		await fr(6)
		await close_ui()
		m.neighbors.debug_msgroute()
		await fr(6)
		await close_ui()
		m.neighbors.debug_neighbors()
		await wait(1.0)
		m._update_context()
		if ctx() != "":
			await key("interact")
			await fr(8)
			for r in 3:
				var bs2: Array = buttons()
				if bs2.is_empty():
					break
				await press(bs2[0]), 120.0)
	await step("yasam: mevsim (kis, yaz, yilbasi, konvoy)", func():
		for a in [{"snowman": "1"}, {"mangal": "1"}, {"yilbasi": "1"}, {"konvoy": "1"}]:
			m.seasons.debug(a)
			await wait(0.8)
			m._update_context()
			if ctx() != "":
				await key("interact")
				await fr(8)
			for b in buttons().slice(0, 3):
				if is_instance_valid(b):
					await press(b)
			await close_ui()
		await key("snowball")
		await fr(10)
		m.seasons.start_fireworks(2.0)
		await wait(2.5)
		m.seasons.start_convoy()
		await wait(1.5)
		await monkey(func():
			m.seasons.phone_app()
			await fr(2), 6, 1), 90.0)
	for w in ["yagmur", "kar", "sis", "gunes"]:
		await step("yasam: hava " + w, func():
			m.weather.force(w)
			await wait(1.0)
			await key("umbrella")
			await fr(6)
			m._open_weather()
			await fr(6), 30.0)
	await step("yasam: ev dekoru (mobilya, boya, duzenleme, cicek)", func():
		await monkey(func():
			m.home_life.open_shop()
			await fr(2), 10, 1)
		await monkey(func():
			m.home_life.open_flower_shop()
			await fr(2), 8, 1)
		if ParkMap.zone == "":
			m._enter_home()
			await fr(12)
			for what in ["wall", "floor"]:
				await monkey(func():
					m.home_life.open_paint(what)
					await fr(2), 6, 0)
			m.home_life.start_edit()
			await fr(6)
			for b in buttons().slice(0, 8):
				if is_instance_valid(b):
					await press(b)
			for kc in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_Q, KEY_E, KEY_ENTER]:
				await keycode(kc)
			m.home_life._end_edit()
			await fr(4)
			m._exit_home(), 120.0)
	await step("yasam: ogretici ipuclari", func():
		for id in ["move", "phone", "map", "car", "pet", "shop", "taxi", "bus", "metro", "home", "job", "photo", "leash", "train"]:
			m.tutorial.show_once(id, true)
			await wait(0.3)
			await keycode(KEY_ENTER)
		m.tutorial._hide(), 40.0)
	await step("yasam: hayvan (sev, mama, top, komutlar, tasma, egitim, degistir, karne)", func():
		for a in ["pet_love", "pet_feed", "pet_play", "call_pet", "leash", "leash", "train", "switch_pet", "commands", "quests"]:
			await key(a)
			await fr(8)
			for b in buttons().slice(0, 2):
				if is_instance_valid(b):
					await press(b)
			await close_ui()
		for c in ["sit", "lie", "come", "pet", "throw", "yarn", "petmenu", "weather", "umbrella", "jump"]:
			m._on_command(c)
			await fr(8)
			await close_ui()
		await monkey(func():
			m.pet_care.open_training()
			await fr(2), 8, 1)
		await monkey(func():
			m.pet_health.phone_app()
			await fr(2), 6, 1)
		for d in ["debug_leash", "debug_shelter", "debug_chase"]:
			m.pet_care.call(d)
			await wait(1.0)
			for b in buttons().slice(0, 3):
				if is_instance_valid(b):
					await press(b)
			await close_ui(), 120.0)
	await step("yasam: spor (hali saha, basket)", func():
		if m.sports.root == null:
			print("    spor alani yok (atlandi)")
			return
		for kv in [["football", "1"], ["basket", "1"]]:
			m.sports.debug(kv[0], kv[1])
			await wait(1.5)
			m._update_context()
			print("    ", kv[0], " baglam=", ctx())
			if ctx() != "":
				await key("interact")
				await wait(1.0)
				await key("interact")
			await wait(1.0), 60.0)
	await step("yasam: trafik cezasi (polis, kirmizi isik, park)", func():
		m.traffic.debug_parkfine()
		await wait(1.0)
		await close_ui()
		m.traffic.debug_redlight()
		await wait(1.0)
		await close_ui()
		m.traffic.debug_police()
		await wait(1.5)
		await close_ui(), 60.0)
	await step("yasam: Esc menusu, ayarlar, tuslar, canta, gorevler, magaza", func():
		await keycode(KEY_ESCAPE)
		await fr(6)
		if buttons().is_empty():
			bad("Esc duraklatma menusunu acmadi")
		await close_ui()
		for opener in ["open_settings", "open_keys", "open_bag", "open_quests", "open_shop", "open_credits"]:
			m.ui.call(opener)
			await fr(5)
			var bs: Array = buttons()
			for j in mini(bs.size(), 10):
				m.ui.close_modal()
				m.ui.call(opener)
				await fr(3)
				var b2: Array = buttons()
				if j < b2.size() and not String(b2[j].text).contains("Ana Menü") and not String(b2[j].text).contains("Sıfırla"):
					await press(b2[j])
			await close_ui()
		m.ui.open_closet()
		await fr(8)
		await close_ui(), 90.0)
