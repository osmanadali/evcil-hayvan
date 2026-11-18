extends Node
## Ek meslekler: taksi soforlugu, Park Kafe'de garsonluk, komsunun hayvanina bakicilik.
## main._job sozlugunu kullanir (ust soldaki is satiri, "Isi birak", sure); burada her isin
## kurulumu, her kare mantigi, [F] etkilesimleri ve temizligi var. Ayrica gunluk kazanc ozeti ve kira hatirlatmasi.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const Npc = preload("res://scripts/npc.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const Car = preload("res://scripts/car.gd")

const TYPES := ["taxi", "garson", "bakici"]
const NAMES := {"dog": "Köpek gezdirme", "courier": "Kurye", "taxi": "Taksi", "garson": "Garsonluk", "bakici": "Hayvan bakıcılığı"}
const PAX := ["Selin Hanım", "Burak Bey", "Nermin Teyze", "Kaan", "Derya Hanım", "Orhan Amca", "Melis", "Cem Bey"]
const MENU := [["Çay", "b8322b"], ["Türk kahvesi", "4a2c1a"], ["Limonata", "f2d64b"], ["Simit", "c98a3a"], ["Tost", "e0b070"], ["Ayran", "f4f4f0"]]
const PET_NAMES := {"kopek": ["Pamuk", "Badem", "Şans", "Kömür"], "kedi": ["Minnoş", "Tekir", "Sarman", "Mırmır"]}
const GARSON_GOAL := 5
const WALK_GOAL := 150.0

var m: Node
var state: Node
var taxi_car: Node3D           # is icin verilen sari taksi (sonraki islerde yeniden kullanilir)
var _prev_v := 0.0
var _crash_cd := 0.0
var _prev_clock := -1.0
var _near := {}                # [F] baglami: {cmd, text, icon}


# ---------------------------------------------------------------- yardimcilar

func _j() -> Dictionary:
	return m._job


func _mine() -> bool:
	return not m._job.is_empty() and m._job["type"] in TYPES


func _person(kind: String, tint: Color) -> PersonModel:
	var v := PersonModel.new()
	v.kind = kind
	v.tint = tint
	v.tint2 = tint
	return v


func _npc_person(p: Vector2, face: Vector2) -> Node3D:
	var n := Npc.new()
	var v := _person("kadin" if randi() % 2 == 0 else "erkek", Color(["8a5a8a", "3f6fb5", "c94f4f", "4f8f5a", "d9a03a", "5a6b7a"][randi() % 6]))
	n.visual = v
	n.add_child(v)
	n.roam_center = p
	n.roam_radius = 0.1
	n.world = m.world
	m.add_child(n)
	n.place(p)
	n.hold = 1e6
	n.hold_face = face
	return n


## Yolun kenari: [kaldirim kenari (arac duracak yer), kaldirim (yaya), yon]
func _curb(p: Vector2) -> Array:
	var best := ParkMap.nearest_node(p)
	if best < 0 or ParkMap.road_next[best].size() == 0:
		var bd := 1e18
		for i in ParkMap.nodes.size():
			if ParkMap.road_next[i].size() > 0:
				var d := ParkMap.nodes[i].distance_squared_to(p)
				if d < bd:
					bd = d
					best = i
	if best < 0:
		return []
	var a: Vector2 = ParkMap.nodes[best]
	var nb: int = ParkMap.road_next[best][0]
	var b: Vector2 = ParkMap.nodes[nb]
	var dir := (b - a).normalized()
	var w := ParkMap.road_width(best, nb)
	var base := a + dir * minf(6.0, a.distance_to(b) * 0.4)
	var side := Vector2(-dir.y, dir.x)
	var walk: Vector2 = m.world.resolve(base + side * (w * 0.5 + 1.3), 0.4, base + side * (w * 0.5 + 1.3))
	return [base + side * maxf(w * 0.5 - 1.0, 0.0), walk, atan2(-dir.x, -dir.y)]


## Arac koymak icin bos bir yol kenari (baska araca 7 m'den yakin olmayan).
func _free_curb(p: Vector2) -> Array:
	var first := []
	for k in 13:
		var q := p if k == 0 else p + Vector2.from_angle(k * 1.9) * (8.0 + k * 3.0)
		var c := _curb(q)
		if c.is_empty():
			continue
		if first.is_empty():
			first = c
		var ok := true
		for r in m._rides + m._cars:
			if r != taxi_car and is_instance_valid(r) and Vector2(r.position.x, r.position.z).distance_to(c[0]) < 7.0:
				ok = false
				break
		if ok:
			return c
	return first


func _marker(parent: Node3D, hex: String, h := 2.6) -> Node3D:
	var mk := Node3D.new()
	mk.name = "IsIsaret"
	parent.add_child(mk)
	Kit.cyl(mk, 0.0, 0.22, 0.4, Vector3(0, h, 0), Kit.glow(hex, 2.0), 4, Vector3(PI, 0, 0))
	return mk


func _tag(parent: Node3D, text: String, col: Color, y := 1.9) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 44
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, y, 0)
	parent.add_child(l)
	return l


func _free(n) -> void:
	if n is Node and is_instance_valid(n):
		n.queue_free()


## Yonelme hali: Pamuk'a, Minnos'a, Tekir'e, Badem'e (son unluye gore).
func _dat(name: String) -> String:
	var last := ""
	for ch in name.to_lower():
		if ch in "aeıioöuü":
			last = ch
	var ends_vowel := name.to_lower().right(1) in ["a", "e", "ı", "i", "o", "ö", "u", "ü"]
	return name + "'" + ("y" if ends_vowel else "") + ("a" if last in ["a", "ı", "o", "u"] else "e")


func _tm(t: float) -> String:
	var left := int(maxf(t, 0.0))
	return "%d:%02d" % [left / 60, left % 60]


# ---------------------------------------------------------------- is menusu

func add_menu(body: VBoxContainer) -> void:
	m.ui._menu_item(body, "TAKSİ ŞOFÖRÜ  ·  30–110 ₺ + bahşiş", func():
		m.ui.close_modal()
		start("taxi"))
	m.ui._menu_item(body, "GARSON (PARK KAFE)  ·  40 ₺ + bahşiş", func():
		m.ui.close_modal()
		start("garson"))
	m.ui._menu_item(body, "HAYVAN BAKICISI  ·  55–85 ₺", func():
		m.ui.close_modal()
		start("bakici"))
	m.ui._menu_item(body, "GÜNLÜK KAZANÇ  ·  bugün %d ₺" % _today_total(), func():
		m.ui.close_modal()
		open_summary())


func start(kind: String) -> void:
	if not m._job.is_empty():
		m.ui.toast("Önce elindeki işi bitir (J · İşi bırak).")
		return
	if ParkMap.home != null:
		m.ui.toast("Önce dışarı çık.")
		return
	match kind:
		"taxi":
			_start_taxi()
		"garson":
			_start_garson()
		"bakici":
			_start_bakici()


func text() -> String:
	var j := _j()
	match j["type"]:
		"taxi":
			match j["stage"]:
				"car":
					return "Taksine bin" + "  ·  " + _tm(j["t"])
				"pickup":
					return "Yolcuyu al: %s" % j["pax_name"] + "  ·  " + _tm(j["t"])
				_:
					return "%s → %s%s" % [j["pax_name"], j["addr"], ("  ·  %d çarpma" % j["crash"] if j["crash"] > 0 else "")] + "  ·  " + _tm(j["t"])
		"garson":
			if j["stage"] == "go":
				return "Park Kafe'ye git" + "  ·  " + _tm(j["t"])
			var tray: Array = j["tray"]
			return "Garson: %d/%d servis%s  ·  bahşiş %d ₺" % [j["served"], GARSON_GOAL, ("  ·  tepside: " + ", ".join(tray)) if not tray.is_empty() else "", j["tips"]] + "  ·  " + _tm(j["t"])
		"bakici":
			if j["stage"] == "go":
				return "%s: %s" % [j["owner_name"], j["addr"]] + "  ·  " + _tm(j["t"])
			if j["stage"] == "back":
				return "%s sahibine teslim et" % m._acc(j["name"]) + "  ·  " + _tm(j["t"])
			return "%s: besle %s · gezdir %d/%d m" % [j["name"], "✓" if j["fed"] else "✗", int(minf(j["walked"], WALK_GOAL)), int(WALK_GOAL)] + "  ·  " + _tm(j["t"])
	return ""


# ---------------------------------------------------------------- taksi

func _start_taxi() -> void:
	var me: Vector2 = m._owner_pos()
	var c := _free_curb(me)
	if c.is_empty():
		m.ui.toast("Yakında yol yok.")
		return
	if taxi_car == null or not is_instance_valid(taxi_car) or not taxi_car in m._rides:
		taxi_car = m.world.vehicle("res://assets/models/taksi.glb", 4.5, true)
		if taxi_car == null:
			taxi_car = m.world.make_car(Color("f2c230"))
		taxi_car.set_meta("kind", "araba")
		taxi_car.set_meta("blinkers", Car.add_blinkers(taxi_car))
		# Tepe lambasi: "TAKSİ"
		var sign := Node3D.new()
		taxi_car.add_child(sign)
		# Tabela tavanin gercek yuksekligine oturur (modele gore olculur)
		var roof_y := Car.top_y(Car.body_points(taxi_car), 0.0, 0.3, -0.12, 0.32)
		if is_nan(roof_y):
			roof_y = 1.47
		sign.position.y = roof_y + 0.07 - 1.55
		Kit.box(sign, Vector3(0.62, 0.16, 0.24), Vector3(0, 1.55, 0.1), Kit.glow("ffd23a", 1.6))
		var l := Label3D.new()
		l.text = "TAKSİ"
		l.font_size = 30
		l.pixel_size = 0.004
		l.modulate = Color("1d1e21")
		l.position = Vector3(0, 1.55, -0.025)
		l.rotation.y = 0.0
		sign.add_child(l)
		var l2 := l.duplicate()
		l2.position = Vector3(0, 1.55, 0.225)
		l2.rotation.y = PI
		sign.add_child(l2)
		m._place_ride(taxi_car, c[0], c[2])
	elif m._ride != taxi_car:
		taxi_car.position = Vector3(c[0].x, ParkMap.walk_height(c[0]), c[0].y)
		taxi_car.rotation = Vector3(0, c[2], 0)
	var dd: Array = m._random_door(120.0, 320.0)
	if dd.is_empty():
		m.ui.toast("Şu an taksi bekleyen yok.")
		return
	var pc := _curb(dd[0])
	if pc.is_empty():
		return
	var pax := _npc_person(pc[1], pc[0])
	_marker(pax, "ffd23a")
	m._job = {"type": "taxi", "stage": "car", "t": 150.0, "pay": 0, "crash": 0, "pax": pax,
		"pax_name": PAX[randi() % PAX.size()], "pick": pc[0], "pick_walk": pc[1], "addr": ""}
	_prev_v = 0.0
	if m._ride == taxi_car:
		_taxi_to_pickup()
	else:
		m._set_nav(Vector2(taxi_car.position.x, taxi_car.position.z), "Taksin")
		m.ui.toast("Taksi şoförlüğü: sarı taksin yol kenarında. Bin (F), yolcuyu al, hızlı ve kazasız götür!")


func _taxi_to_pickup() -> void:
	var j := _j()
	j["stage"] = "pickup"
	j["t"] = maxf(float(j["t"]), 120.0)
	m._set_nav(j["pick"], "Yolcu: " + j["pax_name"])
	m.ui.toast("Yolcu seni bekliyor: %s. Yanına yanaş ve dur." % j["pax_name"])


func _taxi_tick(dt: float) -> void:
	var j := _j()
	if taxi_car == null or not is_instance_valid(taxi_car):
		m._end_job(false, "Taksi kayboldu, iş iptal.")
		return
	var in_taxi: bool = m._ride == taxi_car
	var tp := Vector2(taxi_car.position.x, taxi_car.position.z)
	var slow: bool = absf(m._drive_speed) < 2.5
	match j["stage"]:
		"car":
			if in_taxi:
				_taxi_to_pickup()
		"pickup":
			if is_instance_valid(j["pax"]):
				(j["pax"] as Node3D).set("hold_face", tp)
			if in_taxi and slow and tp.distance_to(j["pick"]) < 9.0:
				var dd: Array = m._random_door(260.0, 700.0)
				if dd.is_empty():
					dd = m._random_door(120.0, 900.0)
				if dd.is_empty():
					m._end_job(false, "Yolcu fikrini değiştirdi.")
					return
				var dc := _curb(dd[0])
				_free(j["pax"])
				j["pax"] = null
				j["stage"] = "drive"
				j["drop"] = dc[0]
				j["drop_walk"] = dc[1]
				j["addr"] = dd[1]
				var dist: float = tp.distance_to(dc[0])
				j["dist"] = dist
				j["allow"] = dist / 6.0 + 45.0
				j["t"] = j["allow"]
				j["crash"] = 0
				m._sfx("araba_kapi", -6.0, 1.1)
				m._set_nav(dc[0], j["addr"])
				m.ui.toast("%s: \"%s lütfen, acelem var!\"" % [j["pax_name"], dd[1]])
		"drive":
			if in_taxi:
				_crash_check(dt)
			if in_taxi and slow and tp.distance_to(j["drop"]) < 10.0:
				var fare := clampi(25 + int(float(j["dist"]) / 12.0), 30, 110)
				var frac := clampf(float(j["t"]) / float(j["allow"]), 0.0, 1.0)
				var tip := maxi(0, int(round(fare * 0.4 * frac)) - 6 * int(j["crash"]))
				if int(j["crash"]) >= 3:
					fare = int(fare * 0.7)
				j["pay"] = fare + tip
				var out := _npc_person(j["drop_walk"], j["drop_walk"])
				out.hold = 1.5
				out.graph_node = ParkMap.nearest_node(j["drop_walk"])
				get_tree().create_timer(25.0).timeout.connect(func(): _free(out))
				m._sfx("araba_kapi", -6.0, 1.05)
				var line := "Harika yolculuktu!" if tip >= fare * 0.25 else ("Ucu ucuna yetiştik." if int(j["crash"]) < 3 else "Bir daha seninle binmem!")
				m._end_job(true, "%s: \"%s\"  Ücret %d ₺ · bahşiş %d ₺ ·" % [j["pax_name"], line, fare, tip])


## Ani yavaslama = carpma (fren en fazla ~9 m/sn2; carpmada ~6x hiz kaybi/sn).
func _crash_check(dt: float) -> void:
	var j := _j()
	_crash_cd -= dt
	var v: float = absf(m._drive_speed)
	if _prev_v > 4.5 and (_prev_v - v) / maxf(dt, 0.001) > 16.0 and _crash_cd <= 0.0:
		_crash_cd = 1.5
		j["crash"] = int(j["crash"]) + 1
		m._sfx("tik", -2.0, 0.6)
		m.ui.toast("%s: \"%s\"" % [j["pax_name"], ["Dikkat et!", "Ay, yavaş!", "Ehliyeti nereden aldın?"][mini(int(j["crash"]) - 1, 2)]])
	_prev_v = v


# ---------------------------------------------------------------- garsonluk

func _cafe_center() -> Vector2:
	if ParkMap.has_spot("kafe"):
		return ParkMap.spot("kafe")
	for po in ParkMap.data["pois"]:
		if po["k"] == "yemek":
			return Vector2(po["pos"][0], po["pos"][1])
	return m._owner_pos() + Vector2(8, 0)


## Kafenin onunde masalarin sigacagi bos bir duzluk arar.
func _terrace_spot(cf: Vector2) -> Vector2:
	var w: Node = m.world
	for r: float in [13.0, 16.0, 19.0, 23.0, 28.0]:
		for k in 16:
			var c := cf + Vector2.from_angle(k * TAU / 16.0 + 0.3) * r
			var ok := true
			for off in [Vector2.ZERO, Vector2(4.5, 3.5), Vector2(-4.5, 3.5), Vector2(4.5, -3.5), Vector2(-4.5, -3.5), Vector2(0, 3.5), Vector2(0, -3.5)]:
				if not w.is_free(c + off, 0.6) or w._inside_building(c + off):
					ok = false
					break
			if ok:
				return c
	return cf + Vector2(0, 14)


func _start_garson() -> void:
	var cf := _cafe_center()
	var c := _terrace_spot(cf)
	var root := Node3D.new()
	root.name = "KafeTeras"
	m.add_child(root)
	root.position = Vector3(c.x, ParkMap.walk_height(c), c.y)
	var face := (cf - c).normalized()
	root.rotation.y = atan2(face.x, face.y)       # +Z kafeye bakar
	var xf := func(lp: Vector2) -> Vector2: return c + lp.rotated(-root.rotation.y)
	# Tezgah (kafe tarafinda) + tente
	var wood := Kit.mat("7a4a2a", 0.7)
	Kit.box(root, Vector3(3.2, 1.0, 0.7), Vector3(0, 0.5, 3.4), wood)
	Kit.box(root, Vector3(3.3, 0.06, 0.8), Vector3(0, 1.03, 3.4), Kit.mat("e8e2d4", 0.4))
	Kit.box(root, Vector3(3.6, 0.08, 1.8), Vector3(0, 2.55, 3.4), Kit.mat("c0392b", 0.8), Vector3(-0.12, 0, 0))
	for sx in [-1.7, 1.7]:
		Kit.cyl(root, 0.04, 0.04, 2.5, Vector3(sx, 1.25, 2.7), Kit.mat("2a2a2a", 0.5), 8)
	# Semaver ve bardaklar
	Kit.cyl(root, 0.16, 0.18, 0.42, Vector3(-1.0, 1.27, 3.4), Kit.mat("c9cdd2", 0.25), 14)
	Kit.ball(root, 0.07, Vector3(-1.0, 1.52, 3.4), Kit.mat("c9a04a", 0.3))
	for i in 4:
		Kit.cyl(root, 0.03, 0.025, 0.08, Vector3(0.1 + i * 0.18, 1.1, 3.3), Kit.mat("b8322b", 0.2), 8)
	var sign := Label3D.new()
	sign.text = "PARK KAFE · TEZGÂH"
	sign.font_size = 54
	sign.pixel_size = 0.006
	sign.outline_size = 10
	sign.modulate = Color("ffe08a")
	sign.position = Vector3(0, 2.85, 2.5)
	sign.rotation.y = PI
	root.add_child(sign)
	# Masalar: 2x2, her birinde iki sandalye
	var tables: Array = []
	var top := Kit.mat("f4f1ea", 0.5)
	var leg := Kit.mat("3a3d42", 0.5)
	var chair := Kit.mat("2f6f8f", 0.6)
	for ti in 4:
		var lp := Vector2(-2.4 + (ti % 2) * 4.8, -2.6 + (ti / 2) * 3.4)
		Kit.cyl(root, 0.45, 0.45, 0.04, Vector3(lp.x, 0.74, lp.y), top, 18)
		Kit.cyl(root, 0.04, 0.04, 0.72, Vector3(lp.x, 0.36, lp.y), leg, 8)
		Kit.cyl(root, 0.22, 0.22, 0.03, Vector3(lp.x, 0.015, lp.y), leg, 12)
		for sxs in [-1.0, 1.0]:
			var cp := lp + Vector2(sxs * 0.78, 0)
			Kit.box(root, Vector3(0.42, 0.05, 0.42), Vector3(cp.x, 0.45, cp.y), chair)
			Kit.box(root, Vector3(0.05, 0.45, 0.42), Vector3(cp.x + sxs * 0.2, 0.7, cp.y), chair)
			for lx in [-0.17, 0.17]:
				for lz in [-0.17, 0.17]:
					Kit.cyl(root, 0.018, 0.018, 0.45, Vector3(cp.x + lx, 0.225, cp.y + lz), leg, 6)
		# Saksi
		tables.append({"lp": lp, "seat": lp + Vector2(0.78, 0), "pos": xf.call(lp), "cust": null, "st": "empty", "item": "", "wait": 0.0, "tag": null})
	for sp in [Vector2(-4.6, 1.2), Vector2(4.6, 1.2)]:
		Kit.cyl(root, 0.25, 0.2, 0.45, Vector3(sp.x, 0.22, sp.y), Kit.mat("b5651d", 0.8), 12)
		Kit.ball(root, 0.38, Vector3(sp.x, 0.75, sp.y), Kit.mat("3f8f4a", 0.9))
	var me: Vector2 = m._owner_pos()
	m._job = {"type": "garson", "stage": "go", "t": 360.0, "pay": 0, "root": root, "tables": tables,
		"counter": xf.call(Vector2(0, 2.7)), "center": c, "tray": [], "tray_node": null, "served": 0, "missed": 0,
		"tips": 0, "spawn_t": 0.0}
	if me.distance_to(c) < 25.0:
		_garson_begin()
	else:
		m._set_nav(c, "Park Kafe")
		m.ui.toast("Garsonluk: Park Kafe'de garson aranıyor. Kafeye git!")


func _garson_begin() -> void:
	var j := _j()
	j["stage"] = "work"
	j["t"] = maxf(float(j["t"]), 300.0)
	m._nav = Vector2.INF
	m.minimap.route = []
	for i in 2:
		_garson_seat(i * 3)
	m.ui.toast("Masalara git, siparişi al (F), tezgâhtan tepsiyi doldur, servis et. %d servis!" % GARSON_GOAL)


func _garson_seat(pref := -1) -> void:
	var j := _j()
	var free: Array = []
	for t in j["tables"]:
		if t["st"] == "empty":
			free.append(t)
	if free.is_empty():
		return
	var t: Dictionary = free[pref % free.size()] if pref >= 0 else free[randi() % free.size()]
	var root: Node3D = j["root"]
	var holder := Node3D.new()
	root.add_child(holder)
	var lp: Vector2 = t["seat"]
	holder.position = Vector3(lp.x, 0.0, lp.y)
	holder.rotation.y = -PI * 0.5           # masaya (-X) bakar
	var v := _person("kadin" if randi() % 2 == 0 else "erkek", Color(["d95f76", "3f9d63", "e07b39", "5a6bb5", "8a5a8a"][randi() % 5]))
	v.seated = true
	holder.add_child(v)
	t["cust"] = holder
	t["st"] = "wait"
	t["wait"] = 0.0
	t["item"] = MENU[randi() % MENU.size()][0]
	t["tag"] = _tag(holder, "SİPARİŞ!", Color("ffd23a"), 1.75)


func _garson_leave(t: Dictionary) -> void:
	var c = t["cust"]
	t["cust"] = null
	t["tag"] = null
	t["st"] = "empty"
	if c is Node3D and is_instance_valid(c):
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_callback(c.queue_free)


func _tray_refresh() -> void:
	var j := _j()
	_free(j.get("tray_node"))
	j["tray_node"] = null
	var tray: Array = j["tray"]
	if tray.is_empty():
		return
	var n := Node3D.new()
	m.owner_node.add_child(n)
	var s: float = m.owner_node.global_transform.basis.get_scale().x
	n.scale = Vector3.ONE / maxf(s, 0.001)
	n.position = Vector3(0.0, 1.08, -0.42) / maxf(s, 0.001)
	Kit.cyl(n, 0.26, 0.24, 0.025, Vector3.ZERO, Kit.mat("c9cdd2", 0.3), 18)
	for i in tray.size():
		var col := "ffffff"
		for it in MENU:
			if it[0] == tray[i]:
				col = it[1]
		var pp := Vector3(-0.14 + (i % 3) * 0.14, 0.06, -0.05 + (i / 3) * 0.12)
		if tray[i] in ["Simit", "Tost"]:
			Kit.cyl(n, 0.06, 0.06, 0.01, pp + Vector3(0, -0.04, 0), Kit.mat("ffffff", 0.4), 12)
			Kit.box(n, Vector3(0.1, 0.03, 0.08), pp + Vector3(0, -0.02, 0), Kit.mat(col, 0.7))
		else:
			Kit.cyl(n, 0.032, 0.026, 0.1, pp, Kit.mat(col, 0.2), 10)
	j["tray_node"] = n


func _garson_tick(dt: float) -> void:
	var j := _j()
	var me: Vector2 = m._owner_pos()
	if j["stage"] == "go":
		if me.distance_to(j["center"]) < 20.0:
			_garson_begin()
		return
	j["spawn_t"] = float(j["spawn_t"]) - dt
	var active := 0
	for t in j["tables"]:
		if t["st"] != "empty":
			active += 1
			if t["st"] != "eat":
				t["wait"] = float(t["wait"]) + dt
			if t["st"] == "eat":
				t["wait"] = float(t["wait"]) - dt
				if float(t["wait"]) <= 0.0:
					_garson_leave(t)
			elif float(t["wait"]) > 100.0:
				m._say(t["cust"], "Çok bekledim, gidiyorum!")
				j["missed"] = int(j["missed"]) + 1
				_garson_leave(t)
				m.ui.toast("Bir müşteri beklemekten sıkılıp gitti.")
			elif t["tag"] != null and is_instance_valid(t["tag"]):
				(t["tag"] as Label3D).modulate = Color("ff6b6b") if float(t["wait"]) > 60.0 else (Color("ffd23a") if t["st"] == "wait" else Color.WHITE)
	var done := int(j["served"]) + int(j["missed"])
	if active < 3 and done + active < GARSON_GOAL and float(j["spawn_t"]) <= 0.0:
		j["spawn_t"] = 9.0
		_garson_seat()
	if done >= GARSON_GOAL and active == 0 or done >= GARSON_GOAL and _all_eating():
		var base := 8 * int(j["served"])
		j["pay"] = base + int(j["tips"])
		if int(j["served"]) == 0:
			m._end_job(false, "Hiç servis yapamadın, kafe seni gönderdi.")
		else:
			m._end_job(true, "Park Kafe: \"Eline sağlık!\" %d servis · bahşiş %d ₺ ·" % [j["served"], j["tips"]])


func _all_eating() -> bool:
	for t in _j()["tables"]:
		if t["st"] != "empty" and t["st"] != "eat":
			return false
	return true


func _garson_context(me: Vector2) -> Dictionary:
	var j := _j()
	if j["stage"] != "work":
		return {}
	var best := {}
	var bd := 2.4
	for i in j["tables"].size():
		var t: Dictionary = j["tables"][i]
		var d: float = me.distance_to(t["pos"])
		if d >= bd:
			continue
		if t["st"] == "wait":
			best = {"text": "Sipariş al", "cmd": "mj_g_order_%d" % i, "icon": "list"}
			bd = d
		elif t["st"] == "order" and t["item"] in j["tray"]:
			best = {"text": "Servis et: %s" % t["item"], "cmd": "mj_g_serve_%d" % i, "icon": "hand"}
			bd = d
	if best.is_empty() and me.distance_to(j["counter"]) < 2.6:
		var need := _pending_items()
		if not need.is_empty():
			best = {"text": "Tepsiye koy: %s" % ", ".join(need), "cmd": "mj_g_tray", "icon": "cart"}
	return best


func _pending_items() -> Array:
	var j := _j()
	var need: Array = []
	var tray: Array = (j["tray"] as Array).duplicate()
	for t in j["tables"]:
		if t["st"] == "order":
			if t["item"] in tray:
				tray.erase(t["item"])
			else:
				need.append(t["item"])
	return need


func _garson_cmd(cmd: String) -> void:
	var j := _j()
	if cmd == "mj_g_tray":
		var need := _pending_items()
		(j["tray"] as Array).append_array(need)
		_tray_refresh()
		m.owner_model.act("feed", 0.6)
		m._sfx("tik", -4.0, 1.3)
		m.ui.toast("Tepside: %s" % ", ".join(j["tray"]))
		return
	var i := int(cmd.get_slice("_", 3))
	if i < 0 or i >= j["tables"].size():
		return
	var t: Dictionary = j["tables"][i]
	if cmd.begins_with("mj_g_order") and t["st"] == "wait":
		t["st"] = "order"
		m._say(t["cust"], "Bir %s lütfen!" % t["item"].to_lower())
		if t["tag"] != null and is_instance_valid(t["tag"]):
			(t["tag"] as Label3D).text = t["item"].to_upper()
		m.owner_model.act("wave", 0.6)
		m.ui.toast("Sipariş: %s · tezgâhtan al." % t["item"])
	elif cmd.begins_with("mj_g_serve") and t["st"] == "order" and t["item"] in j["tray"]:
		(j["tray"] as Array).erase(t["item"])
		_tray_refresh()
		var tip := clampi(12 - int(float(t["wait"]) / 8.0), 1, 12)
		j["tips"] = int(j["tips"]) + tip
		j["served"] = int(j["served"]) + 1
		t["st"] = "eat"
		t["wait"] = 8.0
		_free(t["tag"])
		t["tag"] = null
		# Masaya bardak / tabak
		var root: Node3D = j["root"]
		var lp: Vector2 = t["lp"]
		var cup := Kit.cyl(root, 0.032, 0.026, 0.1, Vector3(lp.x + 0.25, 0.81, lp.y), Kit.mat("b8322b", 0.2), 10)
		get_tree().create_timer(9.0).timeout.connect(func(): _free(cup))
		m._say(t["cust"], "Teşekkürler! (+%d ₺ bahşiş)" % tip)
		m.owner_model.act("feed", 0.6)
		m._sfx("para", -10.0, 1.3)


# ---------------------------------------------------------------- hayvan bakiciligi

func _start_bakici() -> void:
	var dd: Array = m._random_door(50.0, 220.0)
	if dd.is_empty():
		m.ui.toast("Şu an bakıcı arayan komşu yok.")
		return
	var door: Vector2 = dd[0]
	var me: Vector2 = m._owner_pos()
	var owner_p: Vector2 = m.world.resolve(door, 0.4, door)
	var owner := _npc_person(owner_p, me)
	_marker(owner, "7bd88f")
	var kind: String = "kedi" if randi() % 2 == 0 else "kopek"
	var pet: Node3D = m._npc_pet(kind, Color(["f2e2c4", "3a3330", "f4f4f4", "c9a070", "8a8a8a"][randi() % 5]), randf_range(0.85, 1.1))
	var pp: Vector2 = m.world.resolve(owner_p + Vector2(0.9, 0.5), 0.3, owner_p)
	pet.roam_center = pp
	pet.roam_radius = 0.1
	pet.place(pp)
	pet.hold = 1e6
	pet.hold_face = owner_p
	var names: Array = PET_NAMES[kind]
	var cn: String = m.CLIENTS[randi() % m.CLIENTS.size()]
	m._job = {"type": "bakici", "stage": "go", "t": 420.0, "pay": 0, "owner": owner, "owner_name": cn, "owner_pos": owner_p,
		"pet": pet, "kind": kind, "name": names[randi() % names.size()], "addr": dd[1], "fed": false, "walked": 0.0,
		"love": 0, "love_t": 0.0, "last": me, "bowl": null}
	m._set_nav(owner_p, "Bakıcılık: " + cn)
	m.ui.toast("Hayvan bakıcılığı: %s işe gidiyor, %s sana emanet. Kapısına git." % [cn, m._acc(m._job["name"])])


func _bakici_tick(dt: float) -> void:
	var j := _j()
	var me: Vector2 = m._owner_pos()
	j["love_t"] = float(j["love_t"]) - dt
	if j["stage"] == "care":
		var pet: Node3D = j["pet"] if is_instance_valid(j["pet"]) else null      # silinmis dugum turlu degiskene atanamaz
		var moved: float = me.distance_to(j["last"])
		if moved < 8.0 and is_instance_valid(pet) and Vector2(pet.position.x, pet.position.z).distance_to(me) < 7.0 and m._ride == null:
			j["walked"] = float(j["walked"]) + moved
		if j["fed"] and float(j["walked"]) >= WALK_GOAL:
			j["stage"] = "back"
			var ow: Node3D = j["owner"]
			if is_instance_valid(ow):
				ow.visible = true
			m._set_nav(j["owner_pos"], j["owner_name"])
			m._pet_voice(j["kind"])
			m.ui.toast("%s karnı tok, yorgun ve mutlu. Sahibine teslim et!" % j["name"])
	j["last"] = me


func _bakici_context(me: Vector2) -> Dictionary:
	var j := _j()
	var pet: Node3D = j["pet"] if is_instance_valid(j["pet"]) else null      # silinmis dugum turlu degiskene atanamaz
	if not is_instance_valid(pet):
		return {}
	var pp := Vector2(pet.position.x, pet.position.z)
	match j["stage"]:
		"go":
			if me.distance_to(j["owner_pos"]) < 3.6:
				return {"text": "%s teslim al" % m._acc(j["name"]), "cmd": "mj_b_al", "icon": "paw"}
		"care", "back":
			if j["stage"] == "back" and me.distance_to(j["owner_pos"]) < 3.6:
				return {"text": "%s sahibine ver" % m._acc(j["name"]), "cmd": "mj_b_ver", "icon": "check"}
			if me.distance_to(pp) < 2.6 and j["bowl"] == null:
				if not j["fed"]:
					return {"text": "%s mama ver" % _dat(j["name"]), "cmd": "mj_b_mama", "icon": "bone"}
				if float(j["love_t"]) <= 0.0 and int(j["love"]) < 3:
					return {"text": "%s sev" % m._acc(j["name"]), "cmd": "mj_b_sev", "icon": "heart"}
	return {}


func _bakici_cmd(cmd: String) -> void:
	var j := _j()
	var pet: Node3D = j["pet"] if is_instance_valid(j["pet"]) else null      # silinmis dugum turlu degiskene atanamaz
	match cmd:
		"mj_b_al":
			j["stage"] = "care"
			pet.hold = 0.0
			pet.follow = m.owner_node
			var ow: Node3D = j["owner"]
			m._say(ow, "%s sana emanet, iyi bak!" % j["name"])
			var mk := ow.get_node_or_null("IsIsaret")
			if mk:
				mk.queue_free()
			get_tree().create_timer(2.5).timeout.connect(func():
				if is_instance_valid(ow) and _mine() and _j().get("stage", "") == "care":
					ow.visible = false)
			m._nav = Vector2.INF
			m.minimap.route = []
			m._pet_voice(j["kind"])
			m.ui.toast("Önce %s mama ver (F), sonra %d m gezdir." % [_dat(j["name"]), int(WALK_GOAL)])
		"mj_b_mama":
			var pp := Vector2(pet.position.x, pet.position.z)
			var me: Vector2 = m._owner_pos()
			var bp := pp + (me - pp).normalized() * 0.35
			var bowl := Node3D.new()
			m.add_child(bowl)
			bowl.position = Vector3(bp.x, ParkMap.walk_height(bp), bp.y)
			Kit.cyl(bowl, 0.16, 0.12, 0.08, Vector3(0, 0.04, 0), Kit.mat("d94a4a", 0.4), 16)
			Kit.cyl(bowl, 0.13, 0.13, 0.02, Vector3(0, 0.075, 0), Kit.mat("8a5a2a", 0.9), 16)
			j["bowl"] = bowl
			m.owner_model.act("feed", 0.9)
			pet.follow = null
			pet.hold = 5.0
			pet.hold_face = bp
			pet.visual.pose = "eat"
			m._sfx("tik", -6.0, 0.8)
			get_tree().create_timer(5.0).timeout.connect(func():
				_free(bowl)
				if is_instance_valid(pet):
					pet.visual.pose = "stand"
				if _mine() and _j().get("pet") == pet:
					_j()["bowl"] = null
					_j()["fed"] = true
					pet.follow = m.owner_node
					m.ui.toast("%s doydu! Şimdi gezdirme zamanı." % _j()["name"]))
		"mj_b_sev":
			j["love"] = int(j["love"]) + 1
			j["love_t"] = 15.0
			m.owner_model.act("pet", 0.9)
			pet.visual.happy_time = 2.0
			m._pet_voice(j["kind"], true)
			m.ui.toast("%s seni sevdi! (+5 ₺ bahşiş)" % j["name"])
		"mj_b_ver":
			var bonus := int(15.0 * clampf(float(j["t"]) / 300.0, 0.0, 1.0))
			j["pay"] = 55 + int(j["love"]) * 5 + bonus
			m._end_job(true, "%s: \"%s çok mutlu görünüyor, sağ ol!\"" % [j["owner_name"], j["name"]])


# ---------------------------------------------------------------- main'den cagrilanlar

func job_tick(dt: float) -> void:
	match _j()["type"]:
		"taxi":
			_taxi_tick(dt)
		"garson":
			_garson_tick(dt)
		"bakici":
			_bakici_tick(dt)


## Her kare: gun donumu ozeti (is olmasa da).
func update(_dt: float) -> void:
	if m._mode != "play":
		return
	var c: float = m.clock
	if _prev_clock >= 0.0 and c < _prev_clock - 12.0:
		_day_end()
	_prev_clock = c


func context() -> Array:
	if not _mine() or m._ride != null:
		return []
	var me: Vector2 = m._owner_pos()
	var r := {}
	match _j()["type"]:
		"garson":
			r = _garson_context(me)
		"bakici":
			r = _bakici_context(me)
	return [] if r.is_empty() else [r["text"], r["cmd"], r["icon"]]


func command(cmd: String) -> void:
	if cmd == "mj_ozet":
		open_summary()
		return
	if not _mine():
		return
	if cmd.begins_with("mj_g_"):
		_garson_cmd(cmd)
	elif cmd.begins_with("mj_b_"):
		_bakici_cmd(cmd)


## Is biterken (basarili ya da degil) sahneyi toplar.
func cleanup(job: Dictionary) -> void:
	match job["type"]:
		"taxi":
			_free(job.get("pax"))
		"garson":
			_free(job.get("tray_node"))
			var root = job.get("root")
			if root is Node3D and is_instance_valid(root):
				var tw := create_tween()
				tw.tween_interval(4.0)
				tw.tween_callback(root.queue_free)
		"bakici":
			_free(job.get("bowl"))
			var pet = job.get("pet")
			var ow = job.get("owner")
			if pet is Node3D and is_instance_valid(pet):
				m._npc_pets.erase(pet)
				pet.visual.pose = "stand"
				if ow is Node3D and is_instance_valid(ow):
					pet.follow = ow
			if ow is Node3D and is_instance_valid(ow):
				ow.visible = true
				var mk: Node = ow.get_node_or_null("IsIsaret")
				if mk:
					mk.queue_free()
			get_tree().create_timer(6.0).timeout.connect(func():
				_free(pet)
				_free(ow))


# ---------------------------------------------------------------- gunluk kazanc ve kira

func _ld() -> Dictionary:
	var e = state.d.get("meslek")
	if typeof(e) != TYPE_DICTIONARY:
		e = {"earn": {}, "n": 0, "dun": {}, "dun_n": 0}
		state.d["meslek"] = e
	return e


func record(kind: String, amount: int) -> void:
	var e := _ld()
	var earn: Dictionary = e["earn"]
	earn[kind] = int(earn.get(kind, 0)) + amount
	e["n"] = int(e["n"]) + 1
	if kind in TYPES:
		state.count("meslek")


func _today_total() -> int:
	var s := 0
	for k in _ld()["earn"]:
		s += int(_ld()["earn"][k])
	return s


## Kiralik ev(ler): [toplam haftalik kira, sonraki kira gunune kalan oyun gunu]; kira yoksa [].
func rent_info() -> Array:
	var em: Node = m.emlak
	if em == null or not em.has_method("owned") or not em.has_method("_d") or m.bank == null:
		return []
	var homes: Dictionary = em._d().get("homes", {})
	var total := 0
	var soon := 1e9
	for id in homes:
		var h = homes[id]
		if typeof(h) != TYPE_DICTIONARY or str(h.get("own", "")) != "kira":
			continue
		var i: int = em.find(str(id))
		total += int(em.listings[i]["rent"]) if i >= 0 else int(h.get("rent", 400))
		soon = minf(soon, (float(h.get("next", 0.0)) - float(m.bank._now())) / float(m.DAY_SECONDS))
	if total == 0:
		return []
	return [total, maxf(soon, 0.0)]


func _day_end() -> void:
	var e := _ld()
	var total := _today_total()
	e["dun"] = (e["earn"] as Dictionary).duplicate()
	e["dun_n"] = int(e["n"])
	e["earn"] = {}
	e["n"] = 0
	var msg := "Gün bitti · Bugünkü kazancın: %d ₺ (%d iş)" % [total, int(e["dun_n"])] if total > 0 else "Gün bitti · Bugün iş yapmadın. J · İş Bul"
	var ri := rent_info()
	if not ri.is_empty():
		if float(ri[1]) <= 1.0:
			msg += "  ·  Yarın kira günü: %d ₺!" % int(ri[0])
		else:
			msg += "  ·  Kiraya %d gün var (%d ₺)" % [ceili(float(ri[1])), int(ri[0])]
	m.ui.toast(msg)
	state.save_game()


func open_summary() -> void:
	var e := _ld()
	var body: VBoxContainer = m.ui._open_panel("GÜNLÜK KAZANÇ", "Bugün %d ₺ · %d iş" % [_today_total(), int(e["n"])])
	var earn: Dictionary = e["earn"]
	if earn.is_empty():
		m.ui._panel_item(body, "Bugün henüz iş yapmadın", func(): pass)
	for k in earn:
		m.ui._panel_item(body, "%s  ·  %d ₺" % [NAMES.get(k, k), int(earn[k])], func(): pass)
	var dun: Dictionary = e["dun"]
	if not dun.is_empty():
		var s := 0
		for k in dun:
			s += int(dun[k])
		m.ui._panel_item(body, "Dün: %d ₺ · %d iş" % [s, int(e["dun_n"])], func(): pass)
	var ri := rent_info()
	if not ri.is_empty():
		var left := float(ri[1])
		m.ui._panel_item(body, "Haftalık kira %d ₺ · %s" % [int(ri[0]), "bugün/yarın!" if left <= 1.0 else "%d gün sonra" % ceili(left)], func(): pass)
	m.ui._panel_item(body, "İŞ BUL", func():
		m.ui.close_modal()
		m._open_jobs())
	m.ui._panel_item(body, "KAPAT", func(): m.ui.close_modal())
	m.ui._focus_first(body)


# ---------------------------------------------------------------- test

func debug(kind: String, run: bool) -> void:
	if m._ride != null:
		m._drive_speed = 0.0
		m._exit_ride()
		await get_tree().create_timer(0.3).timeout
	if not m._job.is_empty():
		m._end_job(false, "Test: iş bırakıldı.")
	start(kind)
	if _j().is_empty():
		print("MESLEK baslamadi ", kind)
		return
	await get_tree().create_timer(0.5).timeout
	print("MESLEK ", kind, " : ", text())
	match kind:
		"taxi":
			var tp := Vector2(taxi_car.position.x, taxi_car.position.z)
			var side := tp + Vector2(1.6, 0.0).rotated(-taxi_car.rotation.y)
			m.owner_node.position = Vector3(side.x, ParkMap.walk_height(side), side.y)
			await get_tree().process_frame
			if m._nearest_rideable() == taxi_car:
				m._enter_ride()
			else:
				print("MESLEK yakin arac taksi degil: ", m._nearest_rideable())
			await get_tree().create_timer(0.4).timeout
			print("MESLEK taksi binildi=", m._ride == taxi_car, " : ", text())
			if run:
				for step in 2:
					if m._ride != taxi_car:
						break
					var tgt: Vector2 = _j()["pick"] if step == 0 else _j()["drop"]
					taxi_car.position = Vector3(tgt.x, ParkMap.walk_height(tgt), tgt.y)
					m._drive_speed = 0.0
					await get_tree().create_timer(0.6).timeout
					print("MESLEK adim ", step, " : ", text() if _mine() else "bitti", " para=", state.d["coins"])
					if not _mine():
						break
		"garson":
			m._place_owner(_j()["center"] + Vector2(0.5, 0.5))
			await get_tree().create_timer(0.5).timeout
			print("MESLEK garson basladi: ", text(), " sahip=", m._owner_pos().distance_to(_j()["center"]))
			if run:
				for k in 40:
					if not _mine():
						break
					var j := _j()
					for i in j["tables"].size():
						var t: Dictionary = j["tables"][i]
						if t["st"] == "wait":
							_garson_cmd("mj_g_order_%d" % i)
					if not _pending_items().is_empty():
						m._place_owner(j["counter"])
						await get_tree().create_timer(0.2).timeout
						print("MESLEK baglam tezgah: ", context())
						_garson_cmd("mj_g_tray")
					for i in j["tables"].size():
						var t: Dictionary = j["tables"][i]
						if t["st"] == "order" and t["item"] in j["tray"]:
							_garson_cmd("mj_g_serve_%d" % i)
					j["spawn_t"] = 0.0
					for t in j["tables"]:
						if t["st"] == "eat":
							t["wait"] = 0.01
					await get_tree().create_timer(0.25).timeout
				print("MESLEK garson : ", text() if _mine() else "bitti", " para=", state.d["coins"])
			else:
				var j := _j()
				if j["tables"][0]["st"] == "wait":
					_garson_cmd("mj_g_order_0")
				m._place_owner(j["counter"])
				await get_tree().create_timer(0.3).timeout
				_garson_cmd("mj_g_tray")
				m._place_owner(j["center"] + Vector2(0.0, -4.5).rotated(-(j["root"] as Node3D).rotation.y))
				m.owner_node.rotation.y = (j["root"] as Node3D).rotation.y
		"bakici":
			m._place_owner(_j()["owner_pos"] + Vector2(1.2, 1.2))
			await get_tree().create_timer(0.4).timeout
			print("MESLEK baglam: ", context())
			command("mj_b_al")
			command("mj_b_mama")
			if run:
				await get_tree().create_timer(5.5).timeout
				_j()["walked"] = WALK_GOAL
				await get_tree().create_timer(0.3).timeout
				m._place_owner(_j()["owner_pos"] + Vector2(1.0, 1.0))
				await get_tree().create_timer(0.4).timeout
				print("MESLEK baglam: ", context(), " : ", text())
				command("mj_b_sev")
				command("mj_b_ver")
				print("MESLEK bakici : ", text() if _mine() else "bitti", " para=", state.d["coins"])
	print("MESLEK ozet bugun=", _today_total(), " kira=", rent_info())
