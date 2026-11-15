extends Node
## Kale Palas Otel ve kayit noktalari.
## - Ana yola bakan bos bir arsada 7 katli otel (isikli tabela, sacak, doner kapi, kapi gorevlisi).
## - Lobi ve oda ic mekanlari (scripts/hotel_interior.gd, gokyuzunde y = 300'de kurulur).
## - Kayit: evdeki yatak ve otel odasi. "OYUN KAYDEDİLDİ" afisi; oyuncunun konumu (state.d["pos"],
##   "pos_in", "pos_zone", "pos_ride") surekli izlenir ve oyun acilinca kalinan yerden devam edilir.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const GasStation = preload("res://scripts/gas_station.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const HotelInterior = preload("res://scripts/hotel_interior.gd")

const NAME := "Kale Palas Otel"
const ROOM_NO := "304"
const NIGHT_PRICE := 250
## Oda servisi: [ad, fiyat, tokluk, enerji, hayvan icin mi]
const SERVICE := [
	["Serpme Kahvaltı Tabağı", 60, 55, 5, false],
	["Mercimek Çorbası", 35, 30, 0, false],
	["Izgara Köfte ve Pilav", 90, 80, 5, false],
	["Türk Kahvesi", 25, 4, 22, false],
	["Dostuna Özel Mama Tabağı", 40, 70, 0, true],
]
const MINIBAR := [["Su", 15, 6, 4], ["Meyve Suyu", 22, 10, 8], ["Çikolata", 28, 14, 10]]

var m: Node
var state: Node
var built := false
var center := Vector2.INF
var toward := Vector2.ZERO
var root: Node3D
var lobby: Node3D
var room: Node3D
var restore_pending := true     # ilk "Devam Et"te son kayit noktasina don
var _doorman: Node3D
var _door_spin: Node3D
var _greet_t := 0.0
var _track_t := 0.0
var _banner_layer: CanvasLayer
var _banner: Control
var _banner_title: Label
var _banner_sub: Label


func local(x: float, z: float) -> Vector2:
	return GasStation._local(center, toward, x, z)


func info() -> Dictionary:
	if typeof(state.d.get("hotel")) != TYPE_DICTIONARY:
		state.d["hotel"] = {"room": false, "nights": 0}
	return state.d["hotel"]


func has_room() -> bool:
	return bool(info().get("room", false))


# ---------------------------------------------------------------- dis mekan

func build() -> void:
	if built:
		return
	built = true
	var w: Node3D = m.world
	var start := ParkMap.spot("baslangic")
	var used: Array[Vector2] = [start]
	for st in w.fuel_stations:
		used.append(st["pos"] if st.has("pos") else Vector2(st["root"].position.x, st["root"].position.z))
	if m.dealer and m.dealer.center != Vector2.INF:
		used.append(m.dealer.center)
	var lot: Array = []
	var tries: Array[Vector2] = [start + Vector2(-90, -60)]
	for rad in [200.0, 380.0, 560.0]:
		for k in 8:
			tries.append(start + Vector2.from_angle((k + 0.5) * TAU / 8.0) * rad)
	for poi in tries:
		if not ParkMap.inside_bounds(poi, 30.0):
			continue
		lot = GasStation._find_lot(w, poi, used)
		if not lot.is_empty():
			break
	if lot.is_empty():
		return
	center = lot[0]
	toward = lot[1]
	root = w._root(center, atan2(toward.x, toward.y))
	root.name = "Otel"
	GasStation._pad(root, center, toward)
	var y := 0.08
	for q in [local(-8.5, -13), local(8.5, -13), local(-8.5, -3), local(8.5, -3)]:
		y = maxf(y, ParkMap.terrain_height(q) - root.position.y + 0.08)
	var stone := Kit.mat("e6dccb", 0.85)
	var base_m := Kit.mat("cdbfa6", 0.8)
	var gold := Kit.mat("c9a45c", 0.3)
	gold.metallic = 0.8
	var burgundy := Kit.mat("7a1f2b", 0.7)
	var dark := Kit.mat("2b2e33", 0.4)
	var win := Kit.mat("26384a", 0.08)
	win.metallic = 0.7
	var g0 := 4.2            # zemin kat yuksekligi
	var fh := 3.1            # kat yuksekligi
	var floors := 6
	var top := y + g0 + fh * floors
	# Govde
	Kit.box(root, Vector3(17.4, 2.4, 10.4), Vector3(0, y - 1.2, -8), base_m)
	Kit.box(root, Vector3(17, g0, 10), Vector3(0, y + g0 * 0.5, -8), base_m)
	Kit.box(root, Vector3(17, fh * floors, 10), Vector3(0, y + g0 + fh * floors * 0.5, -8), stone)
	Kit.box(root, Vector3(17.3, 0.35, 10.3), Vector3(0, y + g0, -8), gold)
	Kit.box(root, Vector3(17.7, 0.5, 10.7), Vector3(0, top + 0.25, -8), base_m)
	Kit.box(root, Vector3(3.0, 2.2, 3.0), Vector3(-5, top + 1.5, -9.5), base_m)
	# Pencere seritleri ve dikmeler
	for f in floors:
		var wy: float = y + g0 + fh * f + 1.65
		Kit.box(root, Vector3(15.6, 1.55, 0.08), Vector3(0, wy, -2.97), win)
		Kit.box(root, Vector3(15.6, 1.55, 0.08), Vector3(0, wy, -13.03), win)
		for sx in [-1.0, 1.0]:
			Kit.box(root, Vector3(0.08, 1.55, 8.4), Vector3(sx * 8.53, wy, -8), win)
		Kit.box(root, Vector3(15.9, 0.12, 0.3), Vector3(0, wy - 0.86, -2.9), base_m)
	for i in 8:
		Kit.box(root, Vector3(0.5, fh * floors, 0.16), Vector3(-7.7 + i * 2.2, y + g0 + fh * floors * 0.5, -2.92), stone)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var lit := Kit.glow("f2c477", 0.45)
	for f in floors:
		for i in 7:
			if rng.randf() < 0.36:
				Kit.box(root, Vector3(1.66, 1.5, 0.03), Vector3(-6.6 + i * 2.2, y + g0 + fh * f + 1.65, -2.91), lit)
	# Zemin kat cephesi: lobi camlari, doner kapi
	var lobby_glass := Kit.glow("ffdfae", 0.55)
	for sx in [-1.0, 1.0]:
		Kit.box(root, Vector3(5.6, 2.9, 0.06), Vector3(sx * 5.0, y + 1.75, -2.96), lobby_glass)
		for k in 3:
			Kit.box(root, Vector3(0.1, 2.9, 0.1), Vector3(sx * (2.2 + k * 2.8), y + 1.75, -2.93), dark)
		Kit.box(root, Vector3(5.8, 0.12, 0.12), Vector3(sx * 5.0, y + 3.25, -2.93), gold)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 0.92, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.5
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	Kit.box(root, Vector3(3.2, 3.0, 0.1), Vector3(0, y + 1.5, -2.9), Kit.glow("ffe6bd", 0.8))
	Kit.cyl(root, 1.3, 1.3, 2.7, Vector3(0, y + 1.35, -2.9), glass, 24)
	Kit.cyl(root, 1.4, 1.4, 0.3, Vector3(0, y + 2.85, -2.9), gold, 24)
	Kit.cyl(root, 1.4, 1.4, 0.06, Vector3(0, y + 0.03, -2.9), dark, 24)
	_door_spin = Node3D.new()
	_door_spin.position = Vector3(0, y + 1.35, -2.9)
	root.add_child(_door_spin)
	for k in 2:
		Kit.box(_door_spin, Vector3(2.5, 2.6, 0.04), Vector3.ZERO, glass, Vector3(0, k * PI * 0.5, 0))
	Kit.cyl(_door_spin, 0.05, 0.05, 2.7, Vector3.ZERO, gold, 8)
	# Sacak, kolonlar, kirmizi hali
	Kit.box(root, Vector3(6.6, 0.3, 4.6), Vector3(0, y + 3.55, -0.7), burgundy)
	Kit.box(root, Vector3(6.7, 0.5, 0.1), Vector3(0, y + 3.6, 1.62), gold)
	var cl := GasStation._label(root, "KALE PALAS", Vector3(0, y + 3.6, 1.69), Color("5a1420"), 0.36)
	cl.double_sided = false
	for sx in [-1.0, 1.0]:
		Kit.cyl(root, 0.13, 0.13, 5.4, Vector3(sx * 3.0, y + 0.85, 1.3), gold, 12)
		Kit.box(root, Vector3(0.08, 0.5, 4.6), Vector3(sx * 3.32, y + 3.6, -0.7), gold)
	for i in 3:
		Kit.box(root, Vector3(0.5, 0.04, 0.5), Vector3(-2.0 + i * 2.0, y + 3.38, -0.4), Kit.glow("fff0cf", 2.6))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, y + 2.9, -0.5)
	lamp.omni_range = 9.0
	lamp.light_energy = 1.1
	lamp.light_color = Color("ffe2b0")
	root.add_child(lamp)
	var cy: float = ParkMap.terrain_height(local(0, -0.3)) - root.position.y
	Kit.box(root, Vector3(2.4, 0.5, 4.8), Vector3(0, minf(cy, y) - 0.19, 0.0), Kit.mat("8c1f2c", 0.95))
	# Saksilar
	for sx in [-1.0, 1.0]:
		Kit.cyl(root, 0.38, 0.3, 1.6, Vector3(sx * 2.1, y - 0.2, -2.2), dark, 12)
		Kit.ball(root, 0.5, Vector3(sx * 2.1, y + 0.95, -2.2), Kit.mat("2f7a45", 0.85), Vector3(1, 1.25, 1))
		w._add_circle(Vector3(local(sx * 2.1, -2.2).x, local(sx * 2.1, -2.2).y, 0.4))
		w._add_circle(Vector3(local(sx * 3.0, 1.3).x, local(sx * 3.0, 1.3).y, 0.2))
	# Catidaki isikli tabela
	for sx in [-1.0, 1.0]:
		Kit.box(root, Vector3(0.12, 1.6, 0.12), Vector3(sx * 6.0, top + 1.3, -3.5), dark)
	Kit.box(root, Vector3(14.6, 0.1, 0.14), Vector3(0, top + 0.95, -3.5), Kit.glow("ffcf6b", 2.2))
	var sign := GasStation._label(root, "KALE PALAS OTEL", Vector3(0, top + 2.15, -3.45), Color("ffcf6b"), 2.1)
	sign.double_sided = true
	sign.visibility_range_end = 420.0
	var side := GasStation._label(root, "OTEL", Vector3(8.56, y + g0 + 1.2, -4.4), Color("ffcf6b"), 1.1, PI * 0.5)
	side.visibility_range_end = 200.0
	# Bayrak direkleri
	for sx in [-1.0, 1.0]:
		Kit.cyl(root, 0.06, 0.06, 7.5, Vector3(sx * 9.6, y + 2.7, 3.6), dark, 8)
		Kit.box(root, Vector3(0.04, 1.9, 0.85), Vector3(sx * 9.6, y + 5.4, 3.15), burgundy if sx < 0 else gold)
	# Kapi gorevlisi
	var dm := PersonModel.new()
	dm.kind = "erkek"
	dm.tint = Color("7a1f2b")
	dm.pants = Color("1d1e24")
	var dp := local(2.2, -1.4)
	dm.position = Vector3(2.2, ParkMap.walk_height(dp) - root.position.y, -1.4)
	root.add_child(dm)
	_doorman = dm
	w._add_circle(Vector3(dp.x, dp.y, 0.3))
	# Carpisma: bina govdesi
	for sg in [[local(-8.5, -13), local(8.5, -13)], [local(-8.5, -13), local(-8.5, -3)], [local(8.5, -13), local(8.5, -3)],
			[local(-8.5, -3), local(8.5, -3)], [local(-1.3, -1.9), local(1.3, -1.9)]]:
		w._add_segment(sg[0], sg[1])


func door_pos() -> Vector2:
	return local(0.0, -0.6)


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	_track_t -= dt
	if _track_t <= 0.0:
		_track_t = 1.0
		_track()
	if center == Vector2.INF or ParkMap.home != null or m._mode != "play":
		return
	var o: Vector2 = m._owner_pos()
	var dd := o.distance_to(door_pos())
	if dd < 60.0 and _door_spin:
		_door_spin.rotation.y += dt * (1.6 if dd < 7.0 else 0.35)
	_greet_t -= dt
	if dd < 5.5 and _greet_t <= 0.0 and m._ride == null:
		_greet_t = 40.0
		m._say(_doorman, "Kale Palas'a hoş geldiniz!" if not has_room() else "Tekrar hoş geldiniz efendim!")


## Oyuncunun konumunu duzenli olarak kayda yazar (otomatik kayit da buradan devam eder).
func _track() -> void:
	if m._mode != "play" or m.needs.busy():
		return
	var d: Dictionary = state.d
	if ParkMap.home == null:
		if m._bus_ride != null or m._taxi != null:
			return
		var o: Vector2 = m._owner_pos()
		d["pos"] = [snappedf(o.x, 0.1), snappedf(o.y, 0.1)]
		d["pos_in"] = ""
		d["pos_zone"] = ParkMap.zone
		if m._ride != null and m._ride in m._rides:
			d["pos_ride"] = {"kind": str(m._ride.get_meta("kind", "")), "garage": str(m._ride.get_meta("garage", "")),
				"p": [snappedf(m._ride.position.x, 0.1), snappedf(m._ride.position.z, 0.1)], "yaw": snappedf(m._ride.rotation.y, 0.01)}
	elif ParkMap.home == m._home:
		d["pos_in"] = "home"
		d["pos_zone"] = ParkMap.zone
	elif m.emlak != null and m.emlak.inside_owned():
		d["pos_in"] = "emlak:" + m.emlak.cur_id()
		d["pos_zone"] = ParkMap.zone
	elif lobby != null and ParkMap.home == lobby:
		d["pos_in"] = "hotel"
		d["pos_zone"] = ParkMap.zone
	elif room != null and ParkMap.home == room:
		d["pos_in"] = "hotelroom"
		d["pos_zone"] = ParkMap.zone


## "Devam Et": son kayit noktasina / kalinan yere don (oyun acilisinda bir kez).
func on_enter_play() -> void:
	if not restore_pending:
		return
	restore_pending = false
	var d: Dictionary = state.d
	if typeof(d.get("pos")) != TYPE_ARRAY or d["pos"].size() < 2 or str(d.get("pos_zone", "")) != ParkMap.zone:
		return
	var pos := Vector2(float(d["pos"][0]), float(d["pos"][1]))
	if not ParkMap.inside_bounds(pos, 2.0):
		return
	# Son kullanilan arac birakildigi yerde dursun
	var pr = d.get("pos_ride")
	if typeof(pr) == TYPE_DICTIONARY and typeof(pr.get("p")) == TYPE_ARRAY:
		var rp := Vector2(float(pr["p"][0]), float(pr["p"][1]))
		for r in m._rides:
			if str(r.get_meta("kind", "")) == str(pr.get("kind", "")) and str(r.get_meta("garage", "")) == str(pr.get("garage", "")):
				r.position = Vector3(rp.x, ParkMap.walk_height(rp), rp.y)
				r.rotation.y = float(pr.get("yaw", 0.0))
				if pos.distance_to(rp) < 1.6:
					pos = rp + Vector2(cos(r.rotation.y), -sin(r.rotation.y)) * 2.0
				break
	if str(d.get("pos_in", "")).begins_with("emlak:") and m.emlak.restore(str(d["pos_in"]).substr(6)):
		return
	match str(d.get("pos_in", "")):
		"home":
			if ParkMap.zone == "":
				m._enter_home()
				m._place_owner(m._home.w2(Vector2(4.55, 3.9)))
				m._focus = m.owner_node.position
				return
		"hotel":
			if center != Vector2.INF:
				enter_lobby(false, true)
				return
		"hotelroom":
			if center != Vector2.INF:
				if has_room():
					enter_room(true)
				else:
					enter_lobby(false, true)
				return
	m._place_owner(pos)
	var i := 0
	for k in m.agents:
		m.agents[k].place(m._owner_pos() + Vector2(0.9 + 0.6 * i, 0.5).rotated(i * 2.0))
		i += 1
	m._focus = m.owner_node.position


# ---------------------------------------------------------------- baglam ve komutlar

func context() -> Array:
	if m.needs.busy():
		return []
	var o: Vector2 = m._owner_pos()
	if lobby != null and ParkMap.home == lobby:
		var lo: Vector2 = lobby.local2(o)
		if lo.distance_to(lobby.entrance_local) < 1.2:
			return ["Otelden Çık", "htl_out", "come"]
		if lo.distance_to(lobby.desk_local) < 1.7:
			return ["Resepsiyon · Oda kirala" if not has_room() else "Resepsiyon", "htl_desk", "bag"]
		if lo.distance_to(lobby.lift_local) < 1.6:
			return ["Asansör · Odana çık" if has_room() else "Asansör", "htl_lift", "home"]
		return ["", "", ""]
	if room != null and ParkMap.home == room:
		var lo: Vector2 = room.local2(o)
		if lo.distance_to(room.entrance_local) < 1.0:
			return ["Lobiye İn", "htl_down", "come"]
		if lo.distance_to(room.service_local) < 1.0:
			return ["Oda Servisi", "htl_service", "cart"]
		if lo.distance_to(room.bar_local) < 0.9:
			return ["Mini Bar", "htl_bar", "drop"]
		if lo.distance_to(room.tv_local) < 0.9:
			return ["Televizyonu Kapat" if room.tv_on else "Televizyonu Aç", "htl_tv", "play"]
		if room.near_bed(lo):
			return ["Yatak · Uyu / Kaydet", "htl_bed", "moon"]
		return ["", "", ""]
	if center == Vector2.INF or ParkMap.home != null or m._ride != null:
		return []
	if o.distance_to(door_pos()) < 2.6:
		return ["Kale Palas Otel'e Gir", "htl_in", "home"]
	return []


func command(cmd: String) -> void:
	match cmd:
		"htl_in":
			enter_lobby()
		"htl_out":
			exit_lobby()
		"htl_desk":
			open_desk()
		"htl_lift":
			if has_room():
				enter_room()
			else:
				m.ui.toast("Önce resepsiyondan bir oda kiralamalısın.")
		"htl_down":
			enter_lobby(true)
		"htl_service":
			open_service()
		"htl_bar":
			open_minibar()
		"htl_tv":
			room.set_tv(not room.tv_on)
			m._sfx("tik", -6.0)
			m.ui.toast("Televizyon açıldı: Patili Haberler başlıyor." if room.tv_on else "Televizyon kapandı.")
			m._update_context()
		"htl_bed":
			open_room_bed()
		"htl_homebed":
			open_home_bed()


# ---------------------------------------------------------------- ic mekanlara giris cikis

func _drop_interiors() -> void:
	if lobby:
		lobby.queue_free()
		lobby = null
	if room:
		room.queue_free()
		room = null


func _enter(it: Node3D, at: Vector2, pets_at: Vector2) -> void:
	ParkMap.home = it
	m._moving = false
	m._queue.clear()
	m._place_owner(it.w2(at))
	m.owner_node.rotation.y = 0.0
	var i := 0
	for k in m.agents:
		m.agents[k].place(it.w2(pets_at + Vector2(0.6 * i, 0.0)))
		i += 1
	m._cam_pitch = 0.6
	m._cam_yaw = 0.0
	m._zoom = 0.6
	m._focus = m.owner_node.position


func enter_lobby(from_lift := false, quiet := false) -> void:
	_drop_interiors()
	lobby = HotelInterior.new()
	lobby.kind = "lobby"
	lobby.hour = m.clock
	lobby.position = Vector3(60, 300, 0)
	m.add_child(lobby)
	_enter(lobby, lobby.lift_local + Vector2(0, 0.5) if from_lift else lobby.entrance_local,
		(lobby.lift_local + Vector2(-1.0, 0.9)) if from_lift else (lobby.entrance_local + Vector2(0.8, 0.2)))
	if quiet:
		return
	if from_lift:
		m._sfx("dukkan_zil", -10.0, 1.4)
	else:
		m.ui.toast("%s · Evcil dostu otel" % NAME)
		m._sfx("dukkan_zil", -8.0)
		get_tree().create_timer(0.8).timeout.connect(func():
			if lobby and is_instance_valid(lobby.staff) and ParkMap.home == lobby:
				m._say(lobby.staff, "Hoş geldiniz!" if not has_room() else "Tekrar hoş geldiniz!"))


func exit_lobby() -> void:
	ParkMap.home = null
	_drop_interiors()
	var out := local(0.0, 1.2)
	m._place_owner(out)
	m.owner_node.rotation.y = root.rotation.y
	var i := 0
	for k in m.agents:
		m.agents[k].place(out + (local(1.0 + 0.6 * i, 0.6) - local(0, 0)))
		i += 1
	m._cam_pitch = 0.27
	m._focus = m.owner_node.position


func enter_room(quiet := false) -> void:
	_drop_interiors()
	room = HotelInterior.new()
	room.kind = "room"
	room.hour = m.clock
	room.position = Vector3(120, 300, 0)
	m.add_child(room)
	_enter(room, room.entrance_local, room.petbed_local)
	if not quiet:
		m._sfx("dukkan_zil", -10.0, 1.4)
		m.ui.toast("3. kat · Oda %s. İyi dinlenmeler!" % ROOM_NO)


# ---------------------------------------------------------------- resepsiyon

func open_desk() -> void:
	var h := info()
	var sub := "Evcil dostu otel · Cüzdan %d ₺" % int(state.d["coins"])
	if has_room():
		sub = "Oda %s · Kalan gece: %d · Cüzdan %d ₺" % [ROOM_NO, int(h["nights"]), int(state.d["coins"])]
	var body: VBoxContainer = m.ui._open_panel("KALE PALAS", sub)
	if not has_room():
		m.ui._panel_item(body, "Oda kirala — 1 gece %d ₺" % NIGHT_PRICE, func(): rent())
		m.ui._panel_item(body, "Evcil dostum da kalabilir mi?", func():
			m.ui.close_modal()
			if lobby and is_instance_valid(lobby.staff):
				m._say(lobby.staff, "Elbette! Odada minderi ve mama kabı hazır."))
	else:
		m.ui._panel_item(body, "Odana çık · Oda %s" % ROOM_NO, func():
			m.ui.close_modal()
			enter_room())
		m.ui._panel_item(body, "Bir gece daha ekle · %d ₺" % NIGHT_PRICE, func(): rent())
		m.ui._panel_item(body, "Odadan ayrıl (çıkış yap)", func(): check_out())
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func rent() -> void:
	if int(state.d["coins"]) < NIGHT_PRICE:
		m.ui.toast("Bir gece için %d ₺ daha lazım." % (NIGHT_PRICE - int(state.d["coins"])))
		return
	if not state.spend(NIGHT_PRICE):
		return
	var h := info()
	var first := not has_room()
	h["room"] = true
	h["nights"] = int(h.get("nights", 0)) + 1
	state.count("hotel", 1)
	state.save_game()
	m._sfx("kasa", -4.0)
	if first:
		m.ui.toast("Oda %s senin! Anahtarın hazır, asansörle çıkabilirsin." % ROOM_NO)
		if lobby and is_instance_valid(lobby.staff):
			m._say(lobby.staff, "İyi konaklamalar! Oda %s, 3. kat." % ROOM_NO)
	else:
		m.ui.toast("Konaklaman bir gece uzatıldı. Kalan gece: %d" % int(h["nights"]))
	if room != null and ParkMap.home == room:
		open_room_bed()
	else:
		open_desk()


func check_out() -> void:
	var h := info()
	h["room"] = false
	h["nights"] = 0
	state.save_game()
	m.ui.close_modal()
	if room != null and ParkMap.home == room:
		enter_lobby(true, true)
	m.ui.toast("Çıkış yapıldı. Kale Palas'ı tercih ettiğin için teşekkürler!")
	if lobby and is_instance_valid(lobby.staff):
		m._say(lobby.staff, "Yine bekleriz!")
	m._update_context()


# ---------------------------------------------------------------- oda

func open_room_bed() -> void:
	var h := info()
	var nights := int(h.get("nights", 0))
	var body: VBoxContainer = m.ui._open_panel("ODA %s" % ROOM_NO, "Kayıt noktası · Kalan gece: %d · Cüzdan %d ₺" % [nights, int(state.d["coins"])])
	if nights > 0:
		m.ui._panel_item(body, "Kaydet ve uyu · sabah 08:00'e kadar", func():
			m.ui.close_modal()
			sleep_in_room())
	else:
		m.ui._panel_item(body, "Bir gece daha kal · %d ₺" % NIGHT_PRICE, func(): rent())
	m.ui._panel_item(body, "Oyunu Kaydet", func():
		m.ui.close_modal()
		save_now("%s · Oda %s" % [NAME, ROOM_NO]))
	m.ui._panel_item(body, "Oda servisi çağır", func(): open_service())
	m.ui._panel_item(body, "Odadan ayrıl (çıkış yap)", func(): check_out())
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func open_service() -> void:
	var body: VBoxContainer = m.ui._open_panel("ODA SERVİSİ", "Kapına kadar gelir · Cüzdan %d ₺" % int(state.d["coins"]))
	for it in SERVICE:
		m.ui._panel_item(body, "%s · %d ₺" % [it[0], it[1]], func(): order(it))
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func order(it: Array) -> void:
	if not state.spend(int(it[1])):
		return
	m._sfx("kasa", -6.0)
	if bool(it[4]):
		for k in m.agents:
			state.add_need(k, "hunger", float(it[2]))
			m.agents[k].model.happy_time = 2.5
		m._pet_voice(m._active().kind)
		m.ui.toast("%s afiyetle yedi. (+%d tokluk)" % [state.pet(m._active().kind)["name"], int(it[2])])
	else:
		m.needs.add("hunger", float(it[2]))
		m.needs.add("energy", float(it[3]))
		m.owner_model.act("eat", 1.6)
		m.ui.toast("%s geldi, afiyet olsun! (+%d tokluk)" % [it[0], int(it[2])])
	state.save_game()
	open_service()


func open_minibar() -> void:
	var body: VBoxContainer = m.ui._open_panel("MİNİ BAR", "Ücretler hesabına yazılır · Cüzdan %d ₺" % int(state.d["coins"]))
	for it in MINIBAR:
		m.ui._panel_item(body, "%s · %d ₺" % [it[0], it[1]], func():
			if not state.spend(int(it[1])):
				return
			m.needs.add("hunger", float(it[2]))
			m.needs.add("energy", float(it[3]))
			m._sfx("kasa", -8.0)
			m.ui.toast("%s · afiyet olsun!" % it[0])
			open_minibar())
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


## Otel odasinda uyu: evdeki uykuyla ayni etki (enerji dolar, saat 08:00), bir gece duser, oyun kaydedilir.
func sleep_in_room() -> void:
	var n: Node = m.needs
	if n.sleeping or room == null or ParkMap.home != room:
		return
	n.sleeping = true
	n._stop_owner()
	m.ui.set_context("", "")
	m.ui._actions.visible = false
	var edge_l := Vector2(room.bed_c.x + room.bed_half.x - 0.2, room.bed_c.y)
	var edge: Vector2 = room.w2(edge_l)
	var out: Vector2 = room.w2(edge_l + Vector2(0.8, 0.0))
	var face := out - edge
	n._sit_at(edge, atan2(-face.x, -face.y), room.global_position.y + 0.55)
	var i := 0
	for k in m.agents:
		m.agents[k].place(room.w2(room.petbed_local + Vector2(0.25 * i, 0.0)))
		m.agents[k].command("lie")
		i += 1
	var hours := fposmod(8.0 - float(m.clock), 24.0)
	if hours < 1.0:
		hours += 24.0
	await get_tree().create_timer(0.8).timeout
	n._build_fade()
	n._fade_title.text = "Zzz..."
	n._fade_sub.text = "İyi uykular · Oda %s" % ROOM_NO
	await n._fade_to(1.0, 1.4)
	var steps := 24
	var start: float = m.clock
	for s in steps:
		m.clock = fposmod(start + hours * float(s + 1) / steps, 24.0)
		n._fade_sub.text = "%02d:%02d" % [int(m.clock), int(fmod(m.clock, 1.0) * 60.0)]
		await get_tree().create_timer(0.06).timeout
	m.clock = 8.0
	n._fade_sub.text = "08:00"
	var d: Dictionary = n.me()
	d["energy"] = 100.0
	d["hunger"] = maxf(float(d["hunger"]) - minf(hours, 10.0) * 2.0, 5.0)
	for k in m.agents:
		state.add_need(k, "energy", 100.0)
	var h := info()
	h["nights"] = maxi(int(h.get("nights", 0)) - 1, 0)
	state.count("sleep")
	n._fade_title.text = "Günaydın!"
	n._fade_title.add_theme_color_override("font_color", Color("ffd36b"))
	await get_tree().create_timer(1.1).timeout
	# Sabah manzarasi icin odayi yenile
	if room != null and ParkMap.home == room:
		enter_room(true)
		n._stand(room.w2(edge_l + Vector2(0.8, 0.0)))
	await n._fade_to(0.0, 1.2)
	n._fade_title.add_theme_color_override("font_color", Color("9fb4ff"))
	n.sleeping = false
	m.ui._actions.visible = true
	m._pet_voice(m._active().kind)
	save_now("%s · Oda %s" % [NAME, ROOM_NO])
	m.ui.toast("Günaydın! Dinlenmiş uyandın, enerjin doldu." + ("" if int(h["nights"]) > 0 else " Konaklaman bugün bitiyor."))
	m._update_context()


# ---------------------------------------------------------------- evdeki yatak

func open_home_bed() -> void:
	var body: VBoxContainer = m.ui._open_panel("YATAK", "Kayıt noktası · Evim")
	m.ui._panel_item(body, "Kaydet ve uyu · sabah 08:00'e kadar", func():
		m.ui.close_modal()
		await m.needs.sleep()
		save_now("Evim · Daire 29"))
	m.ui._panel_item(body, "Oyunu Kaydet", func():
		m.ui.close_modal()
		save_now("Evim · Daire 29"))
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


# ---------------------------------------------------------------- kayit

## Oyunu kaydeder ve GTA tarzi "OYUN KAYDEDİLDİ" afisini gosterir.
func save_now(place: String) -> void:
	_track()
	state.d["save_place"] = place
	state.d["save_clock"] = snappedf(float(m.clock), 0.01)
	state.save_game()
	state.count("save", 1)
	m._sfx("mutlu", -8.0)
	_show_banner(place)


func _show_banner(place: String) -> void:
	if _banner_layer == null:
		_banner_layer = CanvasLayer.new()
		_banner_layer.layer = 45
		add_child(_banner_layer)
		_banner = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.02, 0.04, 0.82)
		sb.border_width_top = 5
		sb.border_width_bottom = 5
		sb.border_color = m.ui.ACCENT
		sb.content_margin_left = 60
		sb.content_margin_right = 60
		sb.content_margin_top = 12
		sb.content_margin_bottom = 16
		_banner.add_theme_stylebox_override("panel", sb)
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var holder := CenterContainer.new()
		holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
		holder.offset_top = 120
		holder.offset_bottom = 320
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner_layer.add_child(holder)
		holder.add_child(_banner)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.add_child(col)
		_banner_title = m.ui._fx_label(col, "OYUN KAYDEDİLDİ", m.ui.F_TITLE, 84, m.ui.ACCENT, 10)
		_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner_sub = m.ui._fx_label(col, "", m.ui.F_BODY, 26, Color(1, 1, 1, 0.9), 0)
		_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var c: float = m.clock
	_banner_sub.text = "%s  ·  Saat %02d:%02d  ·  %d ₺" % [place, int(c), int(fmod(c, 1.0) * 60.0), int(state.d["coins"])]
	_banner.visible = true
	_banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): _banner.visible = false)


# ---------------------------------------------------------------- telefon ve test

func phone_app() -> void:
	if center == Vector2.INF:
		m.ui.toast("Bu bölgede Kale Palas Otel yok.")
		return
	if ParkMap.home != null:
		m.ui.toast("Kale Palas Otel · Geceliği %d ₺, evcil dostlar kabul edilir." % NIGHT_PRICE)
		return
	m._set_nav(door_pos(), NAME)
	m.ui.toast("%s · Geceliği %d ₺, evcil dostlar kabul edilir." % [NAME, NIGHT_PRICE])


## Test: --hotel (lobi), --hotel=dis (dis cephe), --hotel=panel (resepsiyon paneli),
## --hotelroom (oda), --hotelroom=kayit (kayit afisi), --hotelroom=uyu (uyku).
func debug(mode: String, in_room: bool) -> void:
	if center == Vector2.INF:
		print("OTEL YOK")
		return
	print("OTEL ", center, " yon=", toward, " kapi=", door_pos())
	state.d["coins"] = maxi(int(state.d["coins"]), 900)
	if in_room:
		info()["room"] = true
		info()["nights"] = 1
		enter_room()
		m._place_owner(room.w2(Vector2(3.0, 3.3)))
		for f in 3:
			await get_tree().process_frame
		m._update_context()
		print("OTEL ODA baglam=", m.ui._context_cmd)
		if mode == "kayit":
			save_now("%s · Oda %s" % [NAME, ROOM_NO])
			await get_tree().create_timer(0.5).timeout
			print("OTEL KAYIT pos_in=", state.d.get("pos_in"), " yer=", state.d.get("save_place"))
		elif mode == "uyu":
			sleep_in_room()
		elif mode == "panel":
			open_room_bed()
		return
	if mode == "dis":
		m._place_owner(local(0.0, 3.0))
		m._mode = "debug"
		m.cam.global_position = root.to_global(Vector3(-15.0, 5.0, 24.0))
		m.cam.look_at(root.to_global(Vector3(0.0, 11.0, -6.0)))
		m.cam.fov = 66.0
		return
	enter_lobby()
	m._place_owner(lobby.w2(lobby.desk_local))
	for f in 3:
		await get_tree().process_frame
	m._update_context()
	print("OTEL LOBI baglam=", m.ui._context_cmd)
	if mode == "panel":
		open_desk()
