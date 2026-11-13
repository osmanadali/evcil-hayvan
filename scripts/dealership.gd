extends Node
## Otokent Galeri: evin yakininda, ana yola bakan bos bir arsada camli bir oto galerisi. Icerde doner
## platformlarda iki araba, onde fiyat etiketli araclar. Yaninda F ile satis paneli acilir; alinan arac
## galerinin onune teslim edilir, m._rides'a eklenir ve state.d["garage"]'a yazilir (sonraki acilista
## evin yakinina park edilmis olarak gelir).

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const GasStation = preload("res://scripts/gas_station.gd")
const Car = preload("res://scripts/car.gd")

const BRAND := "OTOKENT"
## Katalog: id -> [ad, model, uzunluk, boya ("" = orijinal), fiyat, tur (m.RIDES anahtari), on-arka ters mi]
const CATALOG := {
	"scooter": ["Vızz 50 Scooter", "scooter", 1.8, "", 400, "scooter", false],
	"moto": ["Rüzgar 250 Motosiklet", "motosiklet", 2.05, "", 900, "motosiklet", false],
	"hb_mavi": ["Kent Hatchback · Mavi", "hatchback", 4.1, "2c6fd6", 1400, "araba", false],
	"hb_beyaz": ["Kent Hatchback · Beyaz", "hatchback", 4.1, "eeeeea", 1500, "araba", false],
	"sedan_siyah": ["Kent Hatchback GT · Gece Siyahı", "hatchback", 4.1, "26282c", 2200, "araba", false],
	"sedan_gumus": ["Kent Hatchback GT · Yarış Kırmızısı", "hatchback", 4.1, "c8322b", 2400, "araba", false],
	"minibus": ["Kervan Minibüs", "dolmus", 5.4, "", 3000, "araba", true],
}
const ORDER := ["scooter", "moto", "hb_mavi", "hb_beyaz", "sedan_siyah", "sedan_gumus", "minibus"]

var m: Node
var state: Node
var built := false
var center := Vector2.INF
var toward := Vector2.ZERO
var root: Node3D
var _spawned := false


## Galerinin yerel noktasi (+Z yola dogru) -> dunya
func local(x: float, z: float) -> Vector2:
	return GasStation._local(center, toward, x, z)


func build() -> void:
	if built:
		return
	built = true
	var w: Node3D = m.world
	var start := ParkMap.spot("baslangic")
	var used: Array[Vector2] = [start]
	for st in w.fuel_stations:
		used.append(st["pos"] if st.has("pos") else Vector2(st["root"].position.x, st["root"].position.z))
	# Evin yakinindan baslayip giderek uzaklasan noktalarin cevresinde uygun arsa ara
	var lot: Array = []
	var tries: Array[Vector2] = [start + Vector2(40, 30)]
	for rad in [250.0, 480.0]:
		for k in 8:
			tries.append(start + Vector2.from_angle(k * TAU / 8.0) * rad)
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
	root.name = "Galeri"
	GasStation._pad(root, center, toward)
	var y := 0.08
	for q in [local(-9, -13), local(9, -13), local(-9, -3), local(9, -3)]:
		y = maxf(y, ParkMap.terrain_height(q) - root.position.y + 0.08)
	# Showroom: zemin, cam duvarlar, koyu dikmeler, beyaz cati
	var floor_m := Kit.mat("e9e7e2", 0.15)
	Kit.box(root, Vector3(18.4, 0.3, 10.4), Vector3(0, y - 0.1, -8), floor_m)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.62, 0.78, 0.86, 0.28)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.6
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame := Kit.mat("2b2e33", 0.4)
	frame.metallic = 0.7
	var hgt := 4.6
	Kit.box(root, Vector3(18, hgt, 0.08), Vector3(0, y + hgt * 0.5, -13), glass)
	Kit.box(root, Vector3(0.08, hgt, 10), Vector3(-9, y + hgt * 0.5, -8), glass)
	Kit.box(root, Vector3(0.08, hgt, 10), Vector3(9, y + hgt * 0.5, -8), glass)
	Kit.box(root, Vector3(7.4, hgt, 0.08), Vector3(-5.3, y + hgt * 0.5, -3), glass)
	Kit.box(root, Vector3(7.4, hgt, 0.08), Vector3(5.3, y + hgt * 0.5, -3), glass)
	Kit.box(root, Vector3(3.2, 1.0, 0.08), Vector3(0, y + hgt - 0.5, -3), glass)
	for x in [-9.0, -6.0, -3.0, -1.6, 1.6, 3.0, 6.0, 9.0]:
		Kit.box(root, Vector3(0.16, hgt, 0.16), Vector3(x, y + hgt * 0.5, -3), frame)
		Kit.box(root, Vector3(0.16, hgt, 0.16), Vector3(x, y + hgt * 0.5, -13), frame)
	for z in [-5.5, -8.0, -10.5]:
		Kit.box(root, Vector3(0.16, hgt, 0.16), Vector3(-9, y + hgt * 0.5, z), frame)
		Kit.box(root, Vector3(0.16, hgt, 0.16), Vector3(9, y + hgt * 0.5, z), frame)
	Kit.box(root, Vector3(19.0, 0.45, 11.0), Vector3(0, y + hgt + 0.2, -8), Kit.mat("f4f4f2", 0.5))
	Kit.box(root, Vector3(19.1, 0.5, 0.12), Vector3(0, y + hgt + 0.2, -2.45), Kit.mat("c8322b", 0.4))
	# Tabela
	var sign := GasStation._label(root, BRAND, Vector3(-1.2, y + hgt + 1.25, -3.2), Color("c8322b"), 1.6)
	sign.double_sided = true
	var sub := GasStation._label(root, "GALERİ", Vector3(4.2, y + hgt + 1.05, -3.2), Color("2b2e33"), 0.9)
	sub.double_sided = true
	Kit.box(root, Vector3(10.5, 1.5, 0.2), Vector3(0.8, y + hgt + 1.15, -3.35), Kit.mat("ffffff", 0.4))
	# Tavan isiklari
	for x in [-5.0, 0.0, 5.0]:
		Kit.box(root, Vector3(2.4, 0.06, 0.4), Vector3(x, y + hgt - 0.05, -8), Kit.glow("fff6e0", 2.0))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, y + hgt - 0.6, -8)
	lamp.omni_range = 12.0
	lamp.light_energy = 1.2
	lamp.light_color = Color("fff1d8")
	root.add_child(lamp)
	# Satis masasi
	Kit.box(root, Vector3(2.6, 0.95, 0.8), Vector3(0, y + 0.47, -11.6), Kit.mat("f2f2f0", 0.3))
	Kit.box(root, Vector3(2.7, 0.06, 0.9), Vector3(0, y + 0.97, -11.6), Kit.mat("c8322b", 0.4))
	Kit.box(root, Vector3(0.5, 0.35, 0.04), Vector3(0.6, y + 1.18, -11.7), Kit.mat("15171a", 0.2))
	# Bayraklar
	for x in [-10.0, 10.0]:
		Kit.cyl(root, 0.06, 0.06, 6.5, Vector3(x, 3.25 + y, 4.6), frame)
		Kit.box(root, Vector3(0.04, 2.2, 0.9), Vector3(x, 5.2 + y, 4.15), Kit.mat("c8322b" if x < 0 else "f2c230", 0.6))
	# Carpisma: cam kutu, kapi bosluklu
	var segs := [[local(-9, -13), local(9, -13)], [local(-9, -13), local(-9, -3)], [local(9, -13), local(9, -3)],
		[local(-9, -3), local(-1.6, -3)], [local(1.6, -3), local(9, -3)], [local(-1.3, -11.2), local(1.3, -11.2)]]
	for sg in segs:
		w._add_segment(sg[0], sg[1])
	# Sergi araclari: icerde doner platformlarda iki araba, onde uc arac
	var show := [["hb_mavi", -4.6, -8.2, 0.6], ["sedan_siyah", 4.6, -8.2, -0.6],
		["scooter", -6.5, 1.0, 0.0], ["moto", -2.8, 1.0, 0.0], ["minibus", 4.0, 0.4, 0.0]]
	for sv in show:
		var it: Array = CATALOG[sv[0]]
		var v := make_vehicle(sv[0])
		if v == null:
			continue
		var p := local(sv[1], sv[2])
		var floor_y: float = (root.position.y + y + 0.2) if sv[2] < -3.0 else ParkMap.terrain_height(p) + 0.04
		if sv[2] < -3.0:
			Kit.cyl(root, 2.6, 2.6, 0.12, Vector3(sv[1], y + 0.11, sv[2]), Kit.mat("3a3d42", 0.25), 32)
		v.position = Vector3(p.x, floor_y, p.y)
		v.rotation.y = root.rotation.y + float(sv[3])
		m.add_child(v)
		w._add_circle(Vector3(p.x, p.y, 1.2 if it[5] == "araba" else 0.6))
		# Fiyat etiketi
		var tag_z: float = sv[2] + (it[2] * 0.5 + 0.4) * (1.0 if sv[2] > -3.0 else 0.0)
		var tag_x: float = sv[1] + (0.0 if sv[2] > -3.0 else 2.8 * signf(sv[1]))
		var ty: float = (y + 0.2) if sv[2] < -3.0 else (ParkMap.terrain_height(local(tag_x, tag_z)) - root.position.y)
		Kit.cyl(root, 0.03, 0.03, 1.1, Vector3(tag_x, ty + 0.55, tag_z), frame)
		Kit.box(root, Vector3(1.5, 0.62, 0.04), Vector3(tag_x, ty + 1.35, tag_z), Kit.mat("ffffff", 0.4))
		var nm: String = it[0].split(" · ")[0]
		GasStation._label(root, nm, Vector3(tag_x, ty + 1.48, tag_z + 0.03), Color("2b2e33"), 0.16, 0.0, false)
		GasStation._label(root, "%d ₺" % it[4], Vector3(tag_x, ty + 1.24, tag_z + 0.03), Color("c8322b"), 0.24)


## Katalogdaki araci kurar (m.world.vehicle ile model, boya, sinyaller); bulunamazsa null.
func make_vehicle(id: String) -> Node3D:
	var it: Array = CATALOG[id]
	var v: Node3D = m.world.vehicle("res://assets/models/%s.glb" % it[1], float(it[2]), bool(it[6]))
	if v == null:
		if it[5] != "araba":
			return null
		v = m.world.make_car(Color(it[3] if it[3] != "" else "c23b32"))
	elif it[3] != "":
		m._paint(v, Color(it[3]))
	v.set_meta("kind", it[5])
	v.set_meta("garage", id)
	if it[5] == "araba":
		v.set_meta("blinkers", Car.add_blinkers(v))
	return v


func garage() -> Array:
	if not state.d.has("garage") or typeof(state.d["garage"]) != TYPE_ARRAY:
		state.d["garage"] = []
	return state.d["garage"]


## Acilista: garajdaki araclar evin yakinindaki kaldirimlara park edilir.
func spawn_garage() -> void:
	if _spawned:
		return
	_spawned = true
	var start := ParkMap.spot("baslangic")
	var i := 0
	for id in garage():
		if not CATALOG.has(id):
			continue
		var v := make_vehicle(id)
		if v == null:
			continue
		var ang := 0.9 + i * 1.7
		var c: Array = m._curb_near(start + Vector2(cos(ang), sin(ang)) * (16.0 + i * 7.0))
		var p: Vector2 = c[0] if not c.is_empty() else start + Vector2(6.0 + i * 3.0, 8.0)
		m._place_ride(v, p, float(c[1]) if not c.is_empty() else 0.0)
		i += 1


func context() -> Array:
	if center == Vector2.INF or m._ride != null or ParkMap.home != null:
		return []
	var o: Vector2 = m._owner_pos()
	if o.distance_to(local(0, -9.5)) < 3.2 or o.distance_to(local(0, -1.5)) < 2.4:
		return ["Otokent Galeri · Araç Satın Al", "dealer", "cart"]
	return []


func open_panel() -> void:
	var body: VBoxContainer = m.ui._open_panel("OTOKENT GALERİ", "Sıfır km, garantili · Cüzdan %d ₺" % int(state.d["coins"]))
	var owned := garage()
	for id in ORDER:
		var it: Array = CATALOG[id]
		var n := owned.count(id)
		var txt := "%s · %d ₺" % [it[0], it[4]] + ("  (garajında %d)" % n if n > 0 else "")
		m.ui._panel_item(body, txt, func(): buy(id))
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func buy(id: String) -> void:
	var it: Array = CATALOG[id]
	if int(state.d["coins"]) < int(it[4]):
		m.ui.toast("Bu araç için %d ₺ daha lazım." % (int(it[4]) - int(state.d["coins"])))
		return
	var v := make_vehicle(id)
	if v == null:
		m.ui.toast("Bu model şu an stokta yok.")
		return
	if not state.spend(int(it[4])):
		v.free()
		return
	m.ui.close_modal()
	# Teslim: galerinin onunde, yola bakan bos bir yer
	var p := local(-9.0, 3.6)
	for cand in [local(-9.0, 3.6), local(9.0, 3.6), local(0.5, 4.2), local(-9.0, -0.5), local(9.0, -0.5)]:
		if m.world.is_free(cand, 1.0 if it[5] == "araba" else 0.5):
			p = cand
			break
	m._place_ride(v, p, root.rotation.y + PI * 0.5)
	garage().append(id)
	state.count("dealer", 1)
	state.save_game()
	m._sfx("kasa", -4.0)
	m.ui.toast("Hayırlı olsun! %s galerinin önünde seni bekliyor." % it[0])


func phone_app() -> void:
	if center == Vector2.INF:
		m.ui.toast("Galeri bulunamadı.")
		return
	m._set_nav(local(0, -1.5), "Otokent Galeri")


## Test: galeriye yol tarafindan genis bakis ya da panel.
func debug(mode: String) -> void:
	if center == Vector2.INF:
		print("GALERI YOK")
		return
	print("GALERI ", center, " yon=", toward)
	m._place_owner(local(0.0, -1.0))
	if mode == "panel":
		state.d["coins"] = maxi(int(state.d["coins"]), 3000)
		await get_tree().process_frame
		m._update_context()
		open_panel()
		return
	m._mode = "debug"
	m.cam.global_position = root.to_global(Vector3(-13.0, 6.5, 17.0))
	m.cam.look_at(root.to_global(Vector3(0.0, 2.0, -6.0)))
	m.cam.fov = 62.0
