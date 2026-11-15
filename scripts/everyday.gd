extends Node
## Gundelik hayat: balik tutma, Sali pazari, Maras dondurmacisi.
## - Balik: gol kiyisindaki "Olta Bufesi"nden olta ve yem alinir. Kiyida F ile olta atilir, samandira
##   batinca (ünlem + "VUR!") F'ye zamaninda basilir. Balik cantaya girer; bufede satilir ya da evde pisirilir.
## - Sali Pazari: oyun icinde her Sali 08-18 arasi, secilen bir sokakta tezgahlar kurulur; saticilar bagirir,
##   taze sebze, meyve, peynir, yumurta alinir (yemek malzemesi). Diger gunler tezgahlar ortulu ve sessiz.
## - Maras dondurmacisi: parkta, hava uygunsa acik. Kornetı uzatip geri ceker; F'ye birkac kez basmak gerekir.
##   Hayvana da kucuk bir kase dondurma verilebilir (gunde en fazla iki).

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const F_TITLE := preload("res://assets/fonts/Bangers-Regular.ttf")

const DAYS := ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]
const TUESDAY := 2
const MARKET_FROM := 8.0
const MARKET_TO := 18.0

# ---- balik
const OLTA_PRICE := 90
const YEM_PRICE := 12
const YEM_PACK := 10
# kimlik: [ad (canta anahtari), en az kg, en cok kg, agirlik, satis fiyati, renk]
const FISH := {
	"gumus": ["Gümüş", 0.02, 0.06, 38.0, 4, "c9d6e0"],
	"kefal": ["Kefal", 0.25, 0.9, 22.0, 12, "9aa5ad"],
	"sazan": ["Sazan", 1.0, 6.5, 18.0, 28, "b88a3e"],
	"levrek": ["Levrek", 0.5, 2.6, 11.0, 32, "8fa7b5"],
	"alabalik": ["Alabalık", 0.3, 1.4, 7.0, 22, "d68a8a"],
	"yayin": ["Yayın", 6.0, 16.0, 2.5, 90, "5b5f55"],
}
const JUNK := ["Eski bir çizme", "Bir demet yosun", "Paslı bir kutu"]

# ---- pazar
const STALL_TYPES := ["manav", "peynir", "meyve", "giyim", "manav", "peynir", "giyim"]
const STALL_NAMES := {"manav": "Manav Tezgâhı", "peynir": "Peynir & Yumurta", "meyve": "Meyve Tezgâhı", "giyim": "Giyim Tezgâhı"}
# tur: [[urun, fiyat]]
const STALL_GOODS := {
	"manav": [["Domates", 3], ["Biber", 2], ["Elma", 3]],
	"peynir": [["Peynir", 10], ["Yumurta", 2]],
	"meyve": [["Elma", 3], ["Mandalina", 3], ["Domates", 3]],
}
const STALL_CALLS := {
	"manav": ["Taze domates, gel abla gel!", "Biber biber, bahçeden yeni geldi!", "Üç kilo biber beş lira, kaçırma!", "Bak ağzın tadı, buyur tadına bak!"],
	"peynir": ["Köy peyniri, tadına bak!", "Yumurtalar köy yumurtası!", "Beyaz peynir, tulum, kaşar!"],
	"meyve": ["Elma, armut, mandalina!", "Tatlı mandalina, gel teyze gel!", "Kilosu on lira, bitmeden gel!"],
	"giyim": ["Beşe beş, beşe beş!", "Çorap çorap! Üçü on lira!", "Hepsi beş lira, kaçırma abla!"],
}
const AWNING := ["c8342b", "2f7bb5", "2e9a5a", "d9962b", "8e44ad", "e07a2f", "1f8f9a"]

# ---- dondurma
const ICE_PRICE := 20
const ICE_PET_PRICE := 12
const ICE_CALLS := ["Maraş dondurması! Kesilir, uzar, kaçar!", "Gel abla gel, uzatayım, tutabilirsen!", "Dondurma mı, bıçakla yenir!", "Çanı çalıyorum, dondurma geldi!"]

var m: Node
var state: Node

# gun sayaci
var weekday := TUESDAY
var _prev_clock := -1.0
var force_pazar := false
var force_ice := false

# balik durumu
var kiosk: Dictionary = {}
var shore_stand := Vector2.INF
var _fs := ""                       # "", cast, wait, bite, reel
var _ft := 0.0
var _wait := 6.0
var _win := 1.2
var _nib := 0.0
var _fstand := Vector2.ZERO
var _ftarget := Vector2.ZERO
var _fcatch: Dictionary = {}
var _rod: Node3D
var _tip: Node3D
var _float: Node3D
var _line: MeshInstance3D
var _bang: Label3D
var _fish_node: Node3D
var _ripple: MeshInstance3D
var _shore_cache: Dictionary = {}
var _shore_t := 0.0

# pazar
var stalls: Array = []
var pazar_pos := Vector2.INF
var _pazar_open := false
var _sign_label: Label3D
var _pz_t := 0.0
var _call_t := 6.0

# dondurma
var cart: Dictionary = {}
var _ice_open := true
var _trick := {}                    # {pulls, state, t}
var _ice_call := 9.0
var _ice_t := 0.0


func weekday_name() -> String:
	return DAYS[weekday]


func pazar_is_open() -> bool:
	if force_pazar:
		return true
	return weekday == TUESDAY and m.clock >= MARKET_FROM and m.clock < MARKET_TO


# ---------------------------------------------------------------- kurulum

func build() -> void:
	if not state.d.has("gun_no"):
		state.d["gun_no"] = int(Time.get_date_dict_from_system()["weekday"])
	weekday = posmod(int(state.d["gun_no"]), 7)
	_build_kiosk()
	_build_pazar()
	_build_cart()
	print("GUNDELIK kiosk=%s pazar=%d dondurma=%s gun=%s" % [not kiosk.is_empty(), stalls.size(), not cart.is_empty(), weekday_name()])


func _ok(p: Vector2, r: float, road_gap: float) -> bool:
	var w: Node3D = m.world
	if not ParkMap.inside_bounds(p, 12.0) or not w.is_free(p, r) or w._inside_building(p):
		return false
	if road_gap > 0.0 and w._road_point(p).distance_to(p) < road_gap:
		return false
	return true


func _free_spot(p: Vector2, r: float, road_gap: float) -> Vector2:
	if _ok(p, r, road_gap) and ParkMap.water_sd(p) > r + 2.0:
		return p
	for rad in range(2, 30, 2):
		for k in 12:
			var q := p + Vector2.from_angle(k * TAU / 12.0 + rad * 0.3) * float(rad)
			if _ok(q, r, road_gap) and ParkMap.water_sd(q) > r + 2.0:
				return q
	return Vector2.INF


func _yaw(face: Vector2) -> float:
	return atan2(face.x, face.y)


func _w2(p: Vector2, yaw: float, local: Vector2) -> Vector2:
	return p + Vector2(local.x * cos(yaw) + local.y * sin(yaw), -local.x * sin(yaw) + local.y * cos(yaw))


func _person(kind: String, shirt: String, pants: String) -> Node3D:
	var v := PersonModel.new()
	v.kind = kind
	v.tint = Color(shirt)
	v.tint2 = Color(shirt)
	v.pants = Color(pants)
	return v


func _multi(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	parent.add_child(mi)


func _label(parent: Node3D, text: String, pos: Vector3, size: float, color: Color, rot_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = F_TITLE
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.modulate = color
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = pos
	l.rotation.y = rot_y
	parent.add_child(l)
	return l


func _spheres(parent: Node3D, center: Vector3, half: Vector2, n: int, r: float, col: String, rough := 0.5) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	var xf: Array = []
	for k in n:
		var q := Vector3(randf_range(-half.x, half.x), randf() * r * 1.6, randf_range(-half.y, half.y))
		xf.append(Transform3D(Basis().scaled(Vector3.ONE * randf_range(0.85, 1.1)), center + q))
	_multi(parent, sm, Kit.mat(col, rough), xf)


# ---------------------------------------------------------------- olta bufesi

func _build_kiosk() -> void:
	var b: Node = m.boat
	if b.dock_pos == Vector2.ZERO:
		return
	var c: Vector2 = b.center
	var base: float = (b.dock_pos - c).angle()
	for step in range(35, 150, 11):
		for sgn in [1.0, -1.0]:
			var dir := Vector2.from_angle(base + deg_to_rad(float(step)) * sgn)
			var rr := 4.0
			while rr < 300.0 and ParkMap.water_sd(c + dir * rr) < 0.0:
				rr += 1.5
			var shore := c + dir * rr
			var stand := shore + dir * 1.6
			if rr >= 300.0 or ParkMap.water_sd(stand) < 0.5 or not _ok(stand, 0.8, 3.5):
				continue
			if b.booth_pos != Vector2.ZERO and stand.distance_to(b.booth_pos) < 14.0:
				continue
			var tang := Vector2(-dir.y, dir.x)
			var kp := stand + tang * 4.0 + dir * 1.2
			if not _ok(kp, 1.5, 3.0) or ParkMap.water_sd(kp) < 1.0:
				continue
			shore_stand = stand
			_add_kiosk(kp, -dir)
			return


func _add_kiosk(p: Vector2, face: Vector2) -> void:
	var w: Node3D = m.world
	var yaw := _yaw(face)
	var r: Node3D = w._root(p, yaw)
	var wood := Kit.mat("8a5a33", 0.85)
	var light := Kit.mat("d8b78a", 0.85)
	var blue := Kit.mat("2a6fa8", 0.6)
	var white := Kit.mat("f4f1ea", 0.6)
	Kit.box(r, Vector3(2.5, 2.0, 1.9), Vector3(0, 1.0, -0.2), wood)
	Kit.box(r, Vector3(2.6, 0.08, 0.5), Vector3(0, 1.06, 1.0), light)          # tezgah
	Kit.box(r, Vector3(2.6, 0.9, 0.4), Vector3(0, 0.45, 1.05), wood)
	Kit.box(r, Vector3(2.7, 0.1, 2.3), Vector3(0, 2.05, 0.05), Kit.mat("3a3a3e", 0.7))
	# Cizgili tente
	var tent := Kit.checker(Color("2a6fa8"), Color("f4f1ea"), 8, 1)
	Kit.box(r, Vector3(2.9, 0.06, 1.3), Vector3(0, 1.95, 1.2), tent, Vector3(0.28, 0, 0))
	Kit.box(r, Vector3(2.9, 0.2, 0.04), Vector3(0, 1.65, 1.82), blue)
	# Tabela
	Kit.box(r, Vector3(2.2, 0.42, 0.05), Vector3(0, 2.38, 0.95), white)
	Kit.box(r, Vector3(2.3, 0.05, 0.07), Vector3(0, 2.62, 0.95), blue)
	_label(r, "OLTA & YEM", Vector3(0, 2.38, 0.99), 0.3, Color("2a6fa8"))
	# Arka duvara dayali oltalar
	for k in 5:
		var tilt := 0.16 + k * 0.03
		Kit.cyl(r, 0.006, 0.013, 2.3, Vector3(-0.95 + k * 0.17, 1.5, 0.72), Kit.mat(["222222", "a02a2a", "2a5a9a", "222222", "6a4a2a"][k], 0.5), 6, Vector3(tilt, 0, 0.05))
	# Yem kutulari, kova, balik
	for k in 3:
		Kit.cyl(r, 0.1, 0.09, 0.14, Vector3(0.55 + k * 0.24, 1.17, 1.05), Kit.mat(["d9d9d9", "c0392b", "e0a030"][k], 0.5), 10)
	Kit.cyl(r, 0.2, 0.16, 0.34, Vector3(1.55, 0.17, 1.2), Kit.mat("2a6fa8", 0.6), 12)
	for k in 3:
		Kit.capsule(r, 0.03, 0.22, Vector3(1.5 + k * 0.05, 0.37, 1.18), Kit.mat("b8c4cc", 0.3), Vector3(0.3 * k, 0.4 * k, PI / 2))
	# Agirlik terazisi ve ag
	Kit.torus(r, 0.01, 0.17, Vector3(-1.4, 1.3, 1.2), Kit.mat("3a6a8a", 0.8), Vector3(PI / 2, 0, 0))
	var v := _person("erkek", "3b6f8f", "2b2f38")
	v.position = Vector3(0, 0, -0.35)
	r.add_child(v)
	w._add_circle(Vector3(p.x, p.y, 1.55))
	var front := p + face * 2.0
	kiosk = {"root": r, "pos": p, "front": front, "vendor": v, "yaw": yaw}


# ---------------------------------------------------------------- sali pazari

func _find_pazar_street() -> Array:
	var ref := Vector2.ZERO
	if ParkMap.has_spot("baslangic"):
		ref = ParkMap.spot("baslangic")
	var cands: Array = []
	for rw in ParkMap.data["roads"]:
		var ids: Array = rw["n"]
		for i in ids.size() - 1:
			var a: Vector2 = ParkMap.nodes[int(ids[i])]
			var b: Vector2 = ParkMap.nodes[int(ids[i + 1])]
			var len := a.distance_to(b)
			if len < 40.0:
				continue
			var d := ((a + b) * 0.5).distance_to(ref)
			if d < 30.0 or d > 320.0:
				continue
			if absf(ParkMap.terrain_height(a) - ParkMap.terrain_height(b)) > 2.5:
				continue
			cands.append([d, a, b, float(ParkMap.link_w.get(int(ids[i]) * 65536 + int(ids[i + 1]), 7.0))])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	return cands


func _build_pazar() -> void:
	var cands := _find_pazar_street()
	for ci in mini(cands.size(), 14):
		var c: Array = cands[ci]
		var a: Vector2 = c[1]
		var b: Vector2 = c[2]
		var hw: float = float(c[3]) * 0.5
		var dir := (b - a).normalized()
		var len := a.distance_to(b)
		var best_side := 1.0
		var best: Array = []
		for side in [1.0, -1.0]:
			var n: Vector2 = Vector2(-dir.y, dir.x) * side
			var got: Array = []
			var t := 4.0
			while t < len - 3.5 and got.size() < 7:
				for off in [hw + 2.4, hw + 3.4, hw + 4.6]:
					var q: Vector2 = a + dir * t + n * off
					if _ok(q, 1.3, hw + 1.0) and ParkMap.water_sd(q) > 3.0:
						got.append([q, -n])
						break
				t += 5.0
			if got.size() > best.size():
				best = got
				best_side = side
		if best.size() >= 4:
			for i in best.size():
				_add_stall(best[i][0], best[i][1], i)
			pazar_pos = a + dir * (len * 0.5)
			_build_pazar_sign(best[0][0] - best[0][1] * 0.0 - dir * 3.0, best[0][1], hw)
			return


func _build_pazar_sign(p: Vector2, face: Vector2, hw: float) -> void:
	if not _ok(p, 0.5, 0.0):
		return
	var r: Node3D = m.world._root(p, _yaw(face))
	var white := Kit.mat("f4f1ea", 0.6)
	var blue := Kit.mat("2a6fa8", 0.6)
	Kit.cyl(r, 0.04, 0.04, 2.6, Vector3(-0.7, 1.3, 0), Kit.mat("3a3a3e", 0.5), 8)
	Kit.cyl(r, 0.04, 0.04, 2.6, Vector3(0.7, 1.3, 0), Kit.mat("3a3a3e", 0.5), 8)
	Kit.box(r, Vector3(1.8, 0.7, 0.06), Vector3(0, 2.3, 0), blue)
	_label(r, "SALI PAZARI", Vector3(0, 2.42, 0.04), 0.22, Color.WHITE)
	_sign_label = _label(r, "Salı 08.00 - 18.00", Vector3(0, 2.16, 0.04), 0.15, Color("ffd27a"))
	Kit.box(r, Vector3(1.8, 0.7, 0.04), Vector3(0, 2.3, -0.02), white)
	m.world._add_circle(Vector3(p.x, p.y, 0.3))


func _add_stall(p: Vector2, face: Vector2, idx: int) -> void:
	var w: Node3D = m.world
	var yaw := _yaw(face)
	var r: Node3D = w._root(p, yaw)
	var typ: String = STALL_TYPES[idx % STALL_TYPES.size()]
	var col: String = AWNING[(idx * 3 + 1) % AWNING.size()]
	var steel := Kit.mat("8c9299", 0.35)
	var wood := Kit.mat("8a5a33", 0.85)
	# Kalici iskelet: direkler ve tezgah
	for sx in [-1.45, 1.45]:
		for sz in [-0.9, 1.15]:
			Kit.cyl(r, 0.03, 0.03, 2.35, Vector3(sx, 1.17, sz), steel, 8)
	Kit.box(r, Vector3(2.9, 0.08, 0.95), Vector3(0, 0.82, 0.55), Kit.mat("b79b6d", 0.8))
	Kit.box(r, Vector3(2.8, 0.78, 0.85), Vector3(0, 0.39, 0.55), Kit.mat("6b4a2f", 0.85))
	# Kapali hal: ortu
	var closed := Kit.pivot(r)
	Kit.box(closed, Vector3(3.0, 0.5, 1.0), Vector3(0, 1.0, 0.55), Kit.mat("4d6a78", 0.9))
	Kit.box(closed, Vector3(3.0, 0.1, 0.1), Vector3(0, 2.3, 0.2), Kit.mat("4d6a78", 0.9))
	# Acik hal: tente, mal, satici
	var open := Kit.pivot(r)
	var tent := Kit.checker(Color(col), Color("f6f3ee"), 8, 1)
	tent.cull_mode = BaseMaterial3D.CULL_DISABLED
	Kit.box(open, Vector3(3.3, 0.05, 2.6), Vector3(0, 2.36, 0.12), tent, Vector3(0.12, 0, 0))
	Kit.box(open, Vector3(3.3, 0.26, 0.04), Vector3(0, 2.2, 1.4), Kit.mat(col, 0.7))
	Kit.box(open, Vector3(3.0, 1.1, 0.04), Vector3(0, 1.8, -0.92), Kit.mat(col, 0.8))
	_stall_goods(open, typ, idx)
	var vend := _person("kadin" if idx % 3 == 1 else "erkek", ["f0efe8", "e8c77a", "a8c4e0", "d9a0a0"][idx % 4], "2b2f38")
	vend.position = Vector3(0.0, 0, -0.45)
	open.add_child(vend)
	var vp := p
	# Muşteriler (acikken)
	var fronts: Array = []
	for k in 2:
		if idx % 2 == 0 or k == 0:
			var cv := _person("kadin" if (idx + k) % 2 == 0 else "erkek", ["c8342b", "3b6fa8", "2e9a5a", "8e44ad"][(idx + k) % 4], "3a3a40")
			var lx := -0.8 + k * 1.7 + randf_range(-0.2, 0.2)
			cv.position = Vector3(lx, 0, 1.75)
			cv.rotation.y = PI
			open.add_child(cv)
			fronts.append(cv)
	_w2(p, yaw, Vector2.ZERO)
	w._add_circle(Vector3(_w2(p, yaw, Vector2(-0.8, 0.5)).x, _w2(p, yaw, Vector2(-0.8, 0.5)).y, 0.8))
	w._add_circle(Vector3(_w2(p, yaw, Vector2(0.8, 0.5)).x, _w2(p, yaw, Vector2(0.8, 0.5)).y, 0.8))
	stalls.append({"root": r, "pos": p, "front": _w2(p, yaw, Vector2(0, 2.0)), "yaw": yaw, "type": typ,
		"open": open, "closed": closed, "vendor": vend, "name": STALL_NAMES[typ]})
	open.visible = false


func _stall_goods(open: Node3D, typ: String, idx: int) -> void:
	var white := Kit.mat("f4f1ea", 0.7)
	var crate := Kit.mat("a8793f", 0.85)
	match typ:
		"manav", "meyve":
			var cols: Array = ["d0302a", "3f9a3a", "e8b82a"] if typ == "manav" else ["c8342b", "f08a24", "9fcb3a"]
			for k in 3:
				var cx := -0.95 + k * 0.95
				Kit.box(open, Vector3(0.8, 0.2, 0.5), Vector3(cx, 1.0, 0.55), crate)
				_spheres(open, Vector3(cx, 1.1, 0.55), Vector2(0.3, 0.17), 14, 0.065, cols[k], 0.4)
			# Arka siradan yukseltilmis kasalar
			for k in 2:
				var cx := -0.5 + k * 1.0
				Kit.box(open, Vector3(0.7, 0.2, 0.4), Vector3(cx, 1.28, 0.22), crate, Vector3(-0.3, 0, 0))
				_spheres(open, Vector3(cx, 1.4, 0.2), Vector2(0.25, 0.12), 10, 0.06, cols[(k + 1) % 3], 0.4)
			_label(open, "TAZE %s" % ("SEBZE" if typ == "manav" else "MEYVE"), Vector3(0, 2.1, 1.43), 0.16, Color.WHITE)
		"peynir":
			for k in 4:
				Kit.cyl(open, 0.2, 0.2, 0.11, Vector3(-1.0 + k * 0.4, 0.92 + (k % 2) * 0.1, 0.45), Kit.mat("f1e9cf", 0.6), 14)
			Kit.box(open, Vector3(0.5, 0.28, 0.38), Vector3(0.72, 1.0, 0.55), Kit.mat("f4f4f0", 0.7))
			# Yumurta tepsileri
			for k in 2:
				Kit.box(open, Vector3(0.45, 0.05, 0.3), Vector3(0.55 + k * 0.55, 1.2, 0.3), Kit.mat("b9a98a", 0.9))
				_spheres(open, Vector3(0.55 + k * 0.55, 1.27, 0.3), Vector2(0.17, 0.1), 8, 0.035, "efe0c0", 0.6)
			_label(open, "KÖY ÜRÜNLERİ", Vector3(0, 2.1, 1.43), 0.16, Color.WHITE)
		"giyim":
			Kit.cyl(open, 0.015, 0.015, 3.0, Vector3(0, 1.95, 0.2), Kit.mat("8c9299", 0.35), 6, Vector3(0, 0, PI / 2))
			var cs := ["c8342b", "3b6fa8", "e8b82a", "2e9a5a", "f4f1ea", "8e44ad", "e07a2f", "2b2f38"]
			for k in 8:
				Kit.box(open, Vector3(0.28, 0.5, 0.05), Vector3(-1.26 + k * 0.36, 1.68, 0.2), Kit.mat(cs[(k + idx) % cs.size()], 0.9))
			for k in 4:
				Kit.box(open, Vector3(0.5, 0.12, 0.36), Vector3(-1.0 + k * 0.62, 0.96, 0.55), Kit.mat(cs[(k * 2 + idx) % cs.size()], 0.95))
			_label(open, "BEŞE BEŞ", Vector3(0, 2.1, 1.43), 0.18, Color("ffe08a"))


func _update_pazar(dt: float) -> void:
	_pz_t -= dt
	if _pz_t > 0.0 or stalls.is_empty():
		return
	_pz_t = 1.0
	var open := pazar_is_open()
	if open != _pazar_open:
		_pazar_open = open
		for s in stalls:
			(s["open"] as Node3D).visible = open
			(s["closed"] as Node3D).visible = not open
		if open and m._mode == "play" and m._owner_pos().distance_to(pazar_pos) < 120.0:
			m.ui.toast("Salı Pazarı kuruldu! Taze sebze, meyve, peynir.")
		if _sign_label:
			_sign_label.text = "Bugün AÇIK!" if open else "Salı 08.00 - 18.00"


func _pazar_calls(dt: float) -> void:
	if not _pazar_open or m._mode != "play":
		return
	_call_t -= dt
	if _call_t > 0.0:
		return
	_call_t = randf_range(4.0, 8.0)
	var o: Vector2 = m._owner_pos()
	var near: Array = []
	for s in stalls:
		if o.distance_to(s["pos"]) < 26.0:
			near.append(s)
	if near.is_empty():
		return
	var s: Dictionary = near[randi() % near.size()]
	var lines: Array = STALL_CALLS[s["type"]]
	m._say(s["vendor"], lines[randi() % lines.size()])


func open_stall(i: int) -> void:
	var s: Dictionary = stalls[i]
	var typ: String = s["type"]
	if typ == "giyim":
		m._say(s["vendor"], "Beşe beş abla, bak kumaşı pamuk!")
		m.ui.toast("Giyim tezgâhı: bu hafta sadece bakıyoruz.")
		return
	var body: VBoxContainer = m.ui._open_panel(String(s["name"]).to_upper(), "Salı Pazarı · Cüzdan %d ₺" % int(state.d["coins"]))
	for g in STALL_GOODS[typ]:
		var nm: String = g[0]
		var pr: int = g[1]
		m.ui._panel_item(body, "%s · %d ₺" % [nm, pr], func(): _buy_stall(i, nm, 1, pr))
		m.ui._panel_item(body, "%s ×3 · %d ₺ (pazar fiyatı)" % [nm, pr * 3 - 1], func(): _buy_stall(i, nm, 3, pr * 3 - 1))
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _buy_stall(i: int, nm: String, n: int, price: int) -> void:
	if not state.spend(price):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % price)
		return
	m._sfx("kasa", -8.0)
	state.count("shop")
	var bag: Dictionary = state.d.get("bag", {})
	bag[nm] = int(bag.get(nm, 0)) + n
	state.d["bag"] = bag
	m._say(stalls[i]["vendor"], ["Afiyet olsun abla!", "Hayırlı olsun!", "Bereketli olsun!"][randi() % 3])
	m.ui.toast("%s ×%d çantana kondu · Çanta: %d" % [nm, n, int(bag[nm])])
	state.save_game()
	open_stall(i)


# ---------------------------------------------------------------- maras dondurmacisi

func _build_cart() -> void:
	if not ParkMap.has_spot("baslangic"):
		return
	var b: Vector2 = ParkMap.spot("baslangic")
	var cp := _free_spot(b + Vector2(-17.0, 12.0), 1.5, 5.0)
	if cp == Vector2.INF:
		return
	var face := (b - cp).normalized()
	var w: Node3D = m.world
	var yaw := _yaw(face)
	var r: Node3D = w._root(cp, yaw)
	var red := Kit.mat("b3262c", 0.45)
	var gold := Kit.mat("d4a32e", 0.3)
	gold.metallic = 0.7
	var cream := Kit.mat("f6efe0", 0.5)
	var chrome := Kit.mat("d9dde2", 0.18)
	chrome.metallic = 0.85
	var dark := Kit.mat("1d1d1f", 0.8)
	for sz in [-1.0, 1.0]:
		var wh := Kit.pivot(r, Vector3(0.55, 0.38, sz * 0.52))
		Kit.torus(wh, 0.3, 0.38, Vector3.ZERO, dark, Vector3(PI / 2, 0, 0))
		Kit.torus(wh, 0.28, 0.32, Vector3.ZERO, gold, Vector3(PI / 2, 0, 0))
		for k in 8:
			Kit.box(wh, Vector3(0.012, 0.6, 0.012), Vector3.ZERO, gold, Vector3(0, 0, k * PI / 8.0))
	Kit.box(r, Vector3(1.8, 0.78, 1.0), Vector3(0, 0.85, 0), red)
	Kit.box(r, Vector3(1.86, 0.06, 1.06), Vector3(0, 1.26, 0), gold)
	Kit.box(r, Vector3(1.86, 0.05, 1.06), Vector3(0, 0.5, 0), gold)
	for sz in [-1.0, 1.0]:
		for k in 5:
			Kit.ball(r, 0.05, Vector3(-0.7 + k * 0.35, 0.88, sz * 0.51), gold, Vector3(1, 1, 0.4), 8)
		_label(r, "MARAŞ DONDURMA", Vector3(0, 0.9, sz * 0.512), 0.2, Color("fff2c9"), 0.0 if sz > 0 else PI)
	# Ustte iki kazan (biri acik: beyaz dondurma), kapaklar
	Kit.cyl(r, 0.3, 0.27, 0.34, Vector3(-0.42, 1.46, 0.1), chrome, 16)
	Kit.cyl(r, 0.3, 0.27, 0.34, Vector3(0.28, 1.46, 0.1), chrome, 16)
	Kit.cyl(r, 0.27, 0.27, 0.03, Vector3(-0.42, 1.64, 0.1), cream, 16)
	var lid := Kit.cyl(r, 0.31, 0.31, 0.04, Vector3(0.28, 1.65, 0.1), chrome, 16)
	var lid_pos := lid.position
	# Konik: kornet yigini
	for k in 5:
		Kit.cyl(r, 0.04, 0.012, 0.2, Vector3(0.72 + (k % 2) * 0.09, 1.4, -0.28 + k * 0.1), Kit.mat("d9a45a", 0.8), 8)
	# Cati ve tabela
	for sx in [-0.85, 0.85]:
		Kit.cyl(r, 0.02, 0.02, 1.0, Vector3(sx, 1.76, -0.42), gold, 8)
	Kit.box(r, Vector3(1.9, 0.06, 0.95), Vector3(0, 2.27, -0.05), red)
	Kit.box(r, Vector3(1.94, 0.04, 1.0), Vector3(0, 2.24, -0.05), gold)
	Kit.box(r, Vector3(1.5, 0.26, 0.04), Vector3(0, 2.5, -0.3), cream)
	for sz in [-1.0, 1.0]:
		_label(r, "KAHRAMANIN YERİ", Vector3(0, 2.5, -0.3 + sz * 0.03), 0.12, Color("b3262c"), 0.0 if sz > 0 else PI)
	# Cani: kolda asili
	Kit.cyl(r, 0.04, 0.07, 0.11, Vector3(-0.85, 1.1, 0.5), gold, 10)
	# Ortu (kapaliyken)
	var tarp := Kit.box(r, Vector3(1.9, 0.5, 1.1), Vector3(0, 1.45, 0), Kit.mat("4d6a78", 0.9))
	tarp.visible = false
	# Satici: fes benzeri kirmizi sapka ve yelek
	var v := _person("erkek", "b3262c", "2b2f38")
	v.position = Vector3(-0.05, 0, -1.0)
	r.add_child(v)
	# Kornet (hile icin): saticinin elinden onune uzanir
	var cone := Kit.pivot(r, Vector3(0.0, 1.35, -0.4))
	Kit.cyl(cone, 0.045, 0.008, 0.16, Vector3.ZERO, Kit.mat("d9a45a", 0.8), 10, Vector3(PI, 0, 0))
	Kit.ball(cone, 0.05, Vector3(0, 0.1, 0), Kit.mat("f6efe0", 0.4), Vector3(1, 1.1, 1), 10)
	Kit.ball(cone, 0.036, Vector3(0, 0.17, 0), Kit.mat("e9a8bd", 0.4), Vector3.ONE, 8)
	cone.visible = false
	var side := Vector2(face.y, -face.x)
	w._add_circle(Vector3(cp.x + side.x * 0.5, cp.y + side.y * 0.5, 0.65))
	w._add_circle(Vector3(cp.x - side.x * 0.5, cp.y - side.y * 0.5, 0.65))
	cart = {"root": r, "pos": cp, "front": cp + face * 1.6, "yaw": yaw, "vendor": v, "cone": cone, "tarp": tarp, "lid": lid, "lid_pos": lid_pos}


func ice_ok() -> bool:
	if force_ice:
		return true
	return m.clock >= 10.0 and m.clock < 22.0 and m.weather.rain < 0.3 and m.weather.snow < 0.1 and m.weather.temp > 2.0


func _update_cart(dt: float) -> void:
	if cart.is_empty():
		return
	_ice_t -= dt
	if _ice_t <= 0.0:
		_ice_t = 1.0
		var ok := ice_ok()
		if ok != _ice_open:
			_ice_open = ok
			(cart["vendor"] as Node3D).visible = ok
			(cart["tarp"] as Node3D).visible = not ok
			if not ok:
				_trick.clear()
				(cart["cone"] as Node3D).visible = false
	if not _ice_open or m._mode != "play":
		return
	var o: Vector2 = m._owner_pos()
	# Hile: oyuncu uzaklasirsa vazgec
	if not _trick.is_empty():
		_trick["t"] = float(_trick["t"]) + dt
		if o.distance_to(cart["front"]) > 4.5 or float(_trick["t"]) > 14.0:
			_cancel_trick("Gitti mi bu? Dondurma erimeden gel!")
	_ice_call -= dt
	if _ice_call <= 0.0 and _trick.is_empty():
		_ice_call = randf_range(8.0, 15.0)
		if o.distance_to(cart["pos"]) < 28.0:
			m._say(cart["vendor"], ICE_CALLS[randi() % ICE_CALLS.size()])
			if o.distance_to(cart["pos"]) < 16.0:
				m._sfx("dukkan_zil", -14.0, 1.3)


func open_ice_menu() -> void:
	if not _ice_open:
		return
	var warm: bool = m.weather.temp >= 20.0
	var body: VBoxContainer = m.ui._open_panel("MARAŞ DONDURMA", ("Sıcak günün ferahı! " if warm else "Soğukta da yenir! ") + "Cüzdan %d ₺" % int(state.d["coins"]))
	m.ui._panel_item(body, "Dondurma Al · %d ₺" % ICE_PRICE, func(): start_trick())
	var pet_name := ""
	var a: Node3D = m._active()
	if a != null:
		pet_name = state.pet(a.kind)["name"]
	m.ui._panel_item(body, "%s'e Kase Dondurma · %d ₺" % [pet_name, ICE_PET_PRICE], func(): pet_ice())
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func start_trick() -> void:
	m.ui.close_modal()
	if int(state.d["coins"]) < ICE_PRICE:
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % ICE_PRICE)
		return
	_face_cart()
	_trick = {"pulls": 2 if randf() < 0.65 else 3, "state": "out", "t": 0.0}
	m._say(cart["vendor"], "Buyur abla, al bakalım!")
	_cone_to(true)


func _face_cart() -> void:
	var d: Vector2 = cart["pos"] - m._owner_pos()
	m.owner_node.rotation.y = atan2(-d.x, -d.y)


func _cone_to(out: bool, fast := false) -> void:
	var cone: Node3D = cart["cone"]
	cone.visible = true
	var target := Vector3(0.0, 1.35, 0.95) if out else Vector3(0.0, 1.35, -0.4)
	var tw := create_tween()
	tw.tween_property(cone, "position", target, 0.22 if fast else 0.55).set_trans(Tween.TRANS_QUAD)
	if not out:
		tw.tween_callback(func(): if _trick.is_empty() and is_instance_valid(cone): cone.visible = false)


func _cancel_trick(line: String) -> void:
	_trick.clear()
	_cone_to(false)
	m._say(cart["vendor"], line)


func trick_press() -> void:
	if _trick.is_empty() or _trick["state"] != "out":
		return
	_face_cart()
	if int(_trick["pulls"]) > 0:
		_trick["pulls"] = int(_trick["pulls"]) - 1
		_trick["state"] = "teasing"
		m.owner_model.act("wave", 0.8)
		_cone_to(false, true)
		var lines := ["Hop! Yok yok, bu sefer değil!", "Haha, kaçtı kaçtı!", "Dur dur, bir daha dene!"]
		m._say(cart["vendor"], lines[randi() % lines.size()])
		m._sfx("dukkan_zil", -12.0, 1.5)
		await get_tree().create_timer(1.5).timeout
		if _trick.is_empty():
			return
		_trick["state"] = "out"
		m._say(cart["vendor"], "Hadi, bu sefer uzatıyorum!")
		_cone_to(true)
	else:
		if not state.spend(ICE_PRICE):
			_cancel_trick("Para yoksa dondurma da yok!")
			return
		_trick.clear()
		(cart["cone"] as Node3D).visible = false
		m._sfx("kasa", -8.0)
		state.count("shop")
		state.count("icecream")
		m._say(cart["vendor"], ["Afiyet olsun!", "Oh be, yakaladın!", "Güle güle ye!"][randi() % 3])
		m._use_item("Dondurma")
		state.save_game()


func pet_ice() -> void:
	m.ui.close_modal()
	var a: Node3D = m._active()
	if a == null:
		return
	var pn: String = state.pet(a.kind)["name"]
	var today: String = String(state.d.get("day", ""))
	var rec: Dictionary = state.d.get("pet_ice", {})
	if rec.get("day", "") != today:
		rec = {"day": today, "n": 0}
	if int(rec["n"]) >= 2:
		m._say(cart["vendor"], "Bugünlük yeter, midesi bozulur!")
		m.ui.toast("%s bugün yeterince dondurma yedi, fazlası midesine dokunur." % pn)
		return
	if not state.spend(ICE_PET_PRICE):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % ICE_PET_PRICE)
		return
	rec["n"] = int(rec["n"]) + 1
	state.d["pet_ice"] = rec
	m._sfx("kasa", -8.0)
	_face_cart()
	m._say(cart["vendor"], "Minik dostumuza kaşıkla, soğuk olmasın!")
	var ap := Vector2(a.position.x, a.position.z)
	var o: Vector2 = m._owner_pos()
	var cp := ap + (o - ap).normalized() * 0.5
	var cup: Node3D = m.world._root(cp)
	Kit.cyl(cup, 0.07, 0.05, 0.08, Vector3(0, 0.04, 0), Kit.mat("f4f1ea", 0.6), 12)
	Kit.ball(cup, 0.065, Vector3(0, 0.1, 0), Kit.mat("f6efe0", 0.4), Vector3(1, 0.7, 1), 10)
	Kit.ball(cup, 0.03, Vector3(0, 0.15, 0), Kit.mat("d94a63", 0.4), Vector3.ONE, 8)
	get_tree().create_timer(3.8).timeout.connect(func(): if is_instance_valid(cup): cup.queue_free())
	state.add_need(a.kind, "fun", 14.0)
	state.add_need(a.kind, "hunger", 4.0)
	m._pet_voice(a.kind, true)
	state.count("icecream")
	m.ui.toast("%s dondurmayı lıkır lıkır yaladı! (Gün içinde en fazla iki kez.)" % pn)
	state.save_game()


# ---------------------------------------------------------------- balik tutma

func _forward() -> Vector2:
	var r: float = m.owner_node.rotation.y
	return Vector2(-sin(r), -cos(r))


## Kiyida mi: yakin su yonu {dir, dist} ya da bos.
func _shore(o: Vector2) -> Dictionary:
	var sd := ParkMap.water_sd(o)
	if sd < 0.3 or sd > 7.0:
		return {}
	var f := _forward()
	var best := {}
	var bd := -2.0
	for k in 16:
		var d := Vector2.from_angle(k * TAU / 16.0)
		var dot := d.dot(f)
		if dot < -0.3 or dot < bd:
			continue
		var dist := 0.0
		for tr in [7.0, 5.5, 4.2]:
			if ParkMap.water_sd(o + d * tr) < -1.5:
				dist = tr
				break
		if dist > 0.0:
			bd = dot
			best = {"dir": d, "dist": dist}
	return best


func _water_y() -> float:
	var b: Node = m.boat
	if b.center != Vector2.ZERO and b.wy != 0.0:
		return b.wy
	return ParkMap.terrain_height(_ftarget) + ParkMap.WATER_LIFT


func _fish_ready() -> bool:
	return bool(state.d.get("olta", false)) and m._ride == null and m._taxi == null and ParkMap.home == null


func cast() -> void:
	if not bool(state.d.get("olta", false)):
		m.ui.toast("Oltan yok. Gölün kıyısındaki Olta Büfesi'nden alabilirsin.")
		return
	if int(state.d.get("yem", 0)) <= 0:
		m.ui.toast("Yemin bitti. Olta Büfesi'nden yem al.")
		return
	var o: Vector2 = m._owner_pos()
	var sh := _shore(o)
	if sh.is_empty():
		m.ui.toast("Oltayı atmak için gölün kıyısında, suya dönük dur.")
		return
	state.d["yem"] = int(state.d["yem"]) - 1
	_fstand = o
	var dir: Vector2 = sh["dir"]
	_ftarget = o + dir * float(sh["dist"])
	m._moving = false
	m._queue.clear()
	m.owner_node.rotation.y = atan2(-dir.x, -dir.y)
	m.owner_model.speed = 0.0
	m.owner_model.act("throw", 0.9)
	_make_rig()
	_fs = "cast"
	_ft = 0.0
	m._sfx("firlat", -6.0, 1.2)


func _make_rig() -> void:
	_free_rig()
	_rod = Kit.pivot(m.owner_node, Vector3(0.3, 1.0, -0.25))
	_rod.rotation = Vector3(deg_to_rad(40.0), 0, 0)
	var cork := Kit.mat("d9b27a", 0.8)
	Kit.cyl(_rod, 0.03, 0.03, 0.28, Vector3(0, 0, 0.0), Kit.mat("3a2a1a", 0.7), 8, Vector3(PI / 2, 0, 0))
	Kit.cyl(_rod, 0.004, 0.016, 2.4, Vector3(0, 0, -1.2), Kit.mat("1d1d1f", 0.5), 6, Vector3(PI / 2, 0, 0))
	Kit.cyl(_rod, 0.03, 0.03, 0.05, Vector3(0.05, 0.0, -0.1), Kit.mat("c0a050", 0.3), 8, Vector3(0, 0, PI / 2))
	_tip = Kit.pivot(_rod, Vector3(0, 0, -2.4))
	_float = Node3D.new()
	m.world.add_child(_float)
	Kit.ball(_float, 0.032, Vector3(0, 0.0, 0), Kit.mat("f4f1ea", 0.4), Vector3(1, 1.3, 1), 10)
	Kit.ball(_float, 0.03, Vector3(0, 0.045, 0), Kit.mat("d0302a", 0.4), Vector3(1, 0.9, 1), 10)
	Kit.cyl(_float, 0.004, 0.004, 0.09, Vector3(0, 0.11, 0), Kit.mat("e8a020", 0.4), 6)
	_float.position = _tip.global_position
	_line = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.004
	cm.bottom_radius = 0.004
	cm.height = 1.0
	cm.radial_segments = 4
	cm.rings = 1
	_line.mesh = cm
	_line.material_override = Kit.mat("e8ecef", 0.5)
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.world.add_child(_line)
	_bang = Label3D.new()
	_bang.text = "!"
	_bang.font = F_TITLE
	_bang.font_size = 96
	_bang.pixel_size = 0.006
	_bang.modulate = Color("ffd23a")
	_bang.outline_size = 12
	_bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bang.no_depth_test = true
	_bang.position = Vector3(0, 0.55, 0)
	_bang.visible = false
	_float.add_child(_bang)


func _free_rig() -> void:
	for n in [_rod, _float, _line, _ripple]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_rod = null
	_tip = null
	_float = null
	_line = null
	_ripple = null
	_bang = null


func stop_fishing(msg := "") -> void:
	if _fs == "":
		return
	_fs = ""
	_free_rig()
	if _fish_node != null and is_instance_valid(_fish_node):
		_fish_node.queue_free()
	_fish_node = null
	if msg != "":
		m.ui.toast(msg)


func _pick_fish() -> Dictionary:
	if randf() < 0.07:
		return {"junk": JUNK[randi() % JUNK.size()]}
	var tot := 0.0
	for id in FISH:
		tot += float(FISH[id][3])
	var x := randf() * tot
	var pick := "gumus"
	for id in FISH:
		x -= float(FISH[id][3])
		if x <= 0.0:
			pick = id
			break
	var f: Array = FISH[pick]
	# kucuk balik daha sik: kare dagilim
	var u := pow(randf(), 1.7)
	var kg := snappedf(lerpf(float(f[1]), float(f[2]), u), 0.01)
	return {"id": pick, "kg": kg, "frac": u}


func _splash(at: Vector3, big := false) -> void:
	m._sfx("su_sicrama", -10.0 if not big else -6.0, 1.3 if not big else 1.0)
	if _ripple != null and is_instance_valid(_ripple):
		_ripple.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rp := Kit.torus(m.world, 0.14, 0.17, at + Vector3(0, 0.02, 0), mat)
	_ripple = rp
	rp.scale = Vector3(0.3, 0.3, 0.3)
	rp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(rp, "scale", Vector3(3.2, 1.0, 3.2) if big else Vector3(2.0, 1.0, 2.0), 1.4)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.4)
	tw.chain().tween_callback(rp.queue_free)


func _update_fishing(dt: float) -> void:
	if _fs == "":
		return
	var o: Vector2 = m._owner_pos()
	if o.distance_to(_fstand) > 0.9 or m._ride != null or m._taxi != null or ParkMap.home != null:
		stop_fishing("Oltayı topladın.")
		return
	_ft += dt
	var wy := _water_y()
	var tip := _tip.global_position
	match _fs:
		"cast":
			var k := clampf(_ft / 0.8, 0.0, 1.0)
			var end := Vector3(_ftarget.x, wy, _ftarget.y)
			var p := tip.lerp(end, k)
			p.y += sin(k * PI) * 1.8
			_float.position = p
			if k >= 1.0:
				_splash(end)
				_fs = "wait"
				_ft = 0.0
				var hr: float = m.clock
				var good := (hr >= 5.0 and hr < 9.5) or (hr >= 17.0 and hr < 21.5)
				_wait = randf_range(3.5, 8.5) * (0.65 if good else 1.0)
		"wait":
			var y := wy + 0.01 + sin(_ft * 2.0) * 0.012
			_nib = maxf(_nib - dt, 0.0)
			if _nib <= 0.0 and randf() < dt * 0.3:
				_nib = 0.6
			y -= sin(_nib * 10.0) * 0.025 * minf(_nib * 3.0, 1.0)
			_float.position = Vector3(_ftarget.x, y, _ftarget.y)
			if _ft >= _wait:
				_bite()
		"bite":
			var y := wy - 0.07 + sin(_ft * 34.0) * 0.025
			_float.position = Vector3(_ftarget.x + sin(_ft * 9.0) * 0.03, y, _ftarget.y)
			_bang.visible = true
			if _ft >= _win:
				_bang.visible = false
				_miss()
		"reel":
			var k := clampf(_ft / 1.0, 0.0, 1.0)
			var from := Vector3(_ftarget.x, wy, _ftarget.y)
			var to := tip
			var p := from.lerp(to, k * k)
			p.y += sin(k * PI) * 1.2
			_float.position = p
			if _fish_node != null:
				_fish_node.position = p + Vector3(0, -0.35, 0)
				_fish_node.rotation.z = sin(_ft * 24.0) * 0.5
			if k >= 1.0:
				_catch_done()
	# Misina: kamis ucundan samandiraya
	if _line != null and _float != null:
		var a := tip
		var b := _float.position + Vector3(0, 0.05, 0)
		var dv := b - a
		var ln := dv.length()
		if ln > 0.05:
			var q := Quaternion(Vector3.UP, dv / ln)
			_line.transform = Transform3D(Basis(q).scaled(Vector3(1, ln, 1)), (a + b) * 0.5)


func _bite() -> void:
	_fcatch = _pick_fish()
	_fs = "bite"
	_ft = 0.0
	var big := false
	if _fcatch.has("id"):
		big = float(_fcatch["frac"]) > 0.6
	_win = 0.95 if big else 1.3
	_splash(Vector3(_ftarget.x, _water_y(), _ftarget.y))
	m.ui.toast("Vur!")


func hook() -> void:
	if _fs != "bite":
		return
	_bang.visible = false
	_fs = "reel"
	_ft = 0.0
	m.owner_model.act("pet", 1.0)
	_splash(Vector3(_ftarget.x, _water_y(), _ftarget.y), true)
	if _fcatch.has("id"):
		var f: Array = FISH[_fcatch["id"]]
		_fish_node = _fish_mesh(String(f[5]), float(_fcatch["kg"]), float(f[2]))
	else:
		_fish_node = Node3D.new()
		Kit.box(_fish_node, Vector3(0.18, 0.2, 0.1), Vector3.ZERO, Kit.mat("5a4a3a", 0.9))
	m.world.add_child(_fish_node)


func _miss() -> void:
	_fs = "wait"
	_ft = 0.0
	_wait = randf_range(3.0, 7.0)
	m.ui.toast("Kaçırdın! Balık yemi alıp gitti.")
	state.d["yem"] = maxi(int(state.d.get("yem", 0)), 0)
	# yeni bekleme: yemi tekrar atmadan devam
	_fcatch = {}


func _fish_mesh(col: String, kg: float, max_kg: float) -> Node3D:
	var n := Node3D.new()
	var sc := clampf(0.55 + 1.0 * sqrt(kg / maxf(max_kg, 0.1)), 0.5, 1.7)
	var c := Kit.mat(col, 0.35)
	var belly := Kit.mat("e8e6dc", 0.4)
	Kit.ball(n, 0.1, Vector3.ZERO, c, Vector3(2.2, 0.85, 0.5), 12)
	Kit.ball(n, 0.08, Vector3(0, -0.04, 0), belly, Vector3(2.0, 0.55, 0.45), 10)
	var tail := Kit.prism(n, Vector3(0.14, 0.13, 0.03), Vector3(-0.26, 0, 0), c, Vector3(0, 0, -PI / 2))
	tail.scale = Vector3(1, 1, 1)
	Kit.ball(n, 0.015, Vector3(0.18, 0.03, 0.04), Kit.mat("111111", 0.2), Vector3.ONE, 6)
	Kit.ball(n, 0.015, Vector3(0.18, 0.03, -0.04), Kit.mat("111111", 0.2), Vector3.ONE, 6)
	n.scale = Vector3.ONE * sc
	n.rotation.y = randf() * TAU
	return n


func _catch_done() -> void:
	var o3: Vector3 = m.owner_node.position
	var tip := _float.position
	_free_rig()
	var fn: Node3D = _fish_node
	_fish_node = null
	_fs = ""
	var rec: Dictionary = state.d.get("balik", {"say": 0, "tur": {}})
	if not _fcatch.has("id"):
		var junk: String = _fcatch["junk"]
		m.ui.toast("%s çıktı! Balık değil ama… geri atıyorsun." % junk)
		if fn:
			fn.queue_free()
		return
	var id: String = _fcatch["id"]
	var f: Array = FISH[id]
	var kg: float = _fcatch["kg"]
	var bag: Dictionary = state.d.get("bag", {})
	bag[f[0]] = int(bag.get(f[0], 0)) + 1
	state.d["bag"] = bag
	var tur: Dictionary = rec["tur"]
	var tr: Dictionary = tur.get(id, {"n": 0, "en": 0.0})
	var new_rec := kg > float(tr["en"])
	tr["n"] = int(tr["n"]) + 1
	tr["en"] = maxf(kg, float(tr["en"]))
	tur[id] = tr
	rec["tur"] = tur
	rec["say"] = int(rec["say"]) + 1
	state.d["balik"] = rec
	state.count("fish")
	m._sfx("mutlu", -8.0)
	var big_text := " Rekor!" if (new_rec and int(tr["n"]) > 1) else ""
	m.ui.toast("%s tuttun! %s kg.%s · Çanta: %d" % [f[0], str(snappedf(kg, 0.01)).replace(".", ","), big_text, int(bag[f[0]])])
	# Balik basin ustunde kisaca gorunur
	if fn != null:
		fn.position = o3 + Vector3(0, 2.35, 0)
		fn.rotation = Vector3(0, 0, 0.0)
		var lab := Label3D.new()
		lab.text = "%s · %s kg" % [f[0], str(snappedf(kg, 0.01)).replace(".", ",")]
		lab.font = F_TITLE
		lab.font_size = 64
		lab.pixel_size = 0.006
		lab.outline_size = 10
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.position = Vector3(0, 0.4, 0)
		fn.add_child(lab)
		get_tree().create_timer(2.4).timeout.connect(func(): if is_instance_valid(fn): fn.queue_free())
	state.save_game()


# ---- bufe paneli

func open_kiosk() -> void:
	var rec: Dictionary = state.d.get("balik", {"say": 0, "tur": {}})
	var body: VBoxContainer = m.ui._open_panel("OLTA BÜFESİ", "Gölün balıkçısı · Cüzdan %d ₺ · Yem: %d" % [int(state.d["coins"]), int(state.d.get("yem", 0))])
	if bool(state.d.get("olta", false)):
		m.ui._panel_item(body, "Olta ✓ (var)", func(): m.ui.toast("Oltan çantanda. Kıyıda suya dönüp F'ye bas."))
	else:
		m.ui._panel_item(body, "Olta Al · %d ₺" % OLTA_PRICE, func(): _buy_olta())
	m.ui._panel_item(body, "Yem (%d adet) · %d ₺" % [YEM_PACK, YEM_PRICE], func(): _buy_yem())
	var any := false
	var bag: Dictionary = state.d.get("bag", {})
	var total := 0
	for id in FISH:
		var f: Array = FISH[id]
		var n := int(bag.get(f[0], 0))
		if n > 0:
			any = true
			total += n * int(f[4])
			var key: String = id
			m.ui._panel_item(body, "Sat: %s ×%d · %d ₺" % [f[0], n, n * int(f[4])], func(): _sell(key))
	if any:
		m.ui._panel_item(body, "Hepsini Sat · %d ₺" % total, func(): _sell(""))
	m.ui._panel_item(body, "Balık Defteri (%d balık)" % int(rec["say"]), func(): _open_log())
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _buy_olta() -> void:
	if not state.spend(OLTA_PRICE):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % OLTA_PRICE)
		return
	state.d["olta"] = true
	state.d["yem"] = int(state.d.get("yem", 0)) + 5
	m._sfx("kasa", -8.0)
	m._say(kiosk["vendor"], "Hayırlı olsun! Beş yem de hediye.")
	m.ui.toast("Olta alındı, 5 yem hediye! Kıyıda suya dönüp F ile olta at.")
	state.save_game()
	open_kiosk()


func _buy_yem() -> void:
	if not state.spend(YEM_PRICE):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % YEM_PRICE)
		return
	state.d["yem"] = int(state.d.get("yem", 0)) + YEM_PACK
	m._sfx("kasa", -8.0)
	state.save_game()
	open_kiosk()


func _sell(only: String) -> void:
	var bag: Dictionary = state.d.get("bag", {})
	var gain := 0
	var cnt := 0
	for id in FISH:
		if only != "" and only != id:
			continue
		var f: Array = FISH[id]
		var n := int(bag.get(f[0], 0))
		if n > 0:
			gain += n * int(f[4])
			cnt += n
			bag.erase(f[0])
	state.d["bag"] = bag
	if cnt > 0:
		state.d["coins"] = int(state.d["coins"]) + gain
		m._sfx("kasa", -6.0)
		m._say(kiosk["vendor"], "Eline sağlık, taze balık!")
		m.ui.toast("%d balık satıldı · +%d ₺" % [cnt, gain])
		state.save_game()
	open_kiosk()


func _open_log() -> void:
	var rec: Dictionary = state.d.get("balik", {"say": 0, "tur": {}})
	var body: VBoxContainer = m.ui._open_panel("BALIK DEFTERİ", "Toplam %d balık tuttun" % int(rec["say"]))
	for id in FISH:
		var f: Array = FISH[id]
		var tr: Dictionary = rec["tur"].get(id, {})
		if tr.is_empty():
			m.ui._panel_item(body, "%s · henüz tutmadın" % f[0], func(): pass)
		else:
			m.ui._panel_item(body, "%s · en büyük %s kg · %d adet" % [f[0], str(snappedf(float(tr["en"]), 0.01)).replace(".", ","), int(tr["n"])], func(): pass)
	m.ui._panel_item(body, "Geri", func(): open_kiosk())
	m.ui._focus_first(body)


# ---------------------------------------------------------------- ortak: baglam, komut, kare

func context() -> Array:
	if m._ride != null or m._taxi != null or ParkMap.home != null:
		return []
	match _fs:
		"cast":
			return ["Olta atılıyor…", "", "hand"]
		"wait":
			return ["Balık Bekleniyor · Oltayı Topla", "ed_stop", "hand"]
		"bite":
			return ["VUR!", "ed_hook", "bolt"]
		"reel":
			return ["Balık çekiliyor…", "", "hand"]
	if not _trick.is_empty():
		if _trick["state"] == "out":
			return ["Dondurmayı Al!", "ed_cone", "hand"]
		return ["Dondurma kaçıyor…", "", "hand"]
	var o: Vector2 = m._owner_pos()
	if not kiosk.is_empty() and o.distance_to(kiosk["front"]) < 2.3:
		return ["Olta Büfesi · Olta, Yem, Balık Sat", "ed_kiosk", "bag"]
	if _pazar_open:
		for i in stalls.size():
			if stalls[i]["type"] != "giyim" and o.distance_to(stalls[i]["front"]) < 2.4:
				return ["%s · Taze Ürün" % stalls[i]["name"], "ed_stall:%d" % i, "cart"]
	if not cart.is_empty() and _ice_open and o.distance_to(cart["front"]) < 2.4:
		return ["Maraş Dondurma · %d ₺" % ICE_PRICE, "ed_ice", "smile"]
	if _fish_ready() and not _shore_cache.is_empty():
		return ["Olta At", "ed_cast", "hand"]
	return []


func command(cmd: String) -> void:
	if cmd == "ed_cast":
		cast()
	elif cmd == "ed_hook":
		hook()
	elif cmd == "ed_stop":
		stop_fishing("Oltayı topladın.")
	elif cmd == "ed_kiosk":
		open_kiosk()
	elif cmd.begins_with("ed_stall:"):
		open_stall(int(cmd.substr(9)))
	elif cmd == "ed_ice":
		open_ice_menu()
	elif cmd == "ed_cone":
		trick_press()
	elif cmd == "ed_app":
		phone_app()


func update(dt: float) -> void:
	# gun sayaci
	var ck: float = m.clock
	if _prev_clock >= 0.0 and ck < _prev_clock - 12.0:
		state.d["gun_no"] = int(state.d.get("gun_no", 0)) + 1
		weekday = posmod(int(state.d["gun_no"]), 7)
	_prev_clock = ck
	if m._mode != "play":
		return
	_update_pazar(dt)
	_pazar_calls(dt)
	_update_cart(dt)
	_update_fishing(dt)
	# kiyi kontrolu (sik degil)
	_shore_t -= dt
	if _shore_t <= 0.0:
		_shore_t = 0.3
		_shore_cache = _shore(m._owner_pos()) if (_fs == "" and _fish_ready()) else {}


func phone_app() -> void:
	var o: Vector2 = m._owner_pos()
	var body: VBoxContainer = m.ui._open_panel("MAHALLE", "Bugün %s · %s" % [weekday_name(), "Salı Pazarı AÇIK" if pazar_is_open() else "Pazar yalnızca Salı 08-18"])
	if pazar_pos != Vector2.INF:
		m.ui._panel_item(body, "Salı Pazarı · %d m" % int(o.distance_to(pazar_pos)), func():
			m.ui.close_modal()
			m._set_nav(pazar_pos, "Salı Pazarı"))
	if not kiosk.is_empty():
		m.ui._panel_item(body, "Olta Büfesi · %d m" % int(o.distance_to(kiosk["pos"])), func():
			m.ui.close_modal()
			m._set_nav(kiosk["front"], "Olta Büfesi"))
	if not cart.is_empty():
		m.ui._panel_item(body, "Maraş Dondurmacısı · %d m" % int(o.distance_to(cart["pos"])), func():
			m.ui.close_modal()
			m._set_nav(cart["front"], "Dondurmacı"))
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func has_content() -> bool:
	return not kiosk.is_empty() or not stalls.is_empty() or not cart.is_empty()


# ---------------------------------------------------------------- test

func debug(kind: String, arg: String) -> void:
	match kind:
		"fish":
			state.d["olta"] = true
			state.d["yem"] = 8
			var sp := shore_stand
			if sp == Vector2.INF:
				print("OLTA: kiyi yok")
				return
			m._place_owner(sp)
			var dirs := _shore(sp)
			# suya dogru don
			var best := Vector2.ZERO
			for k in 16:
				var d := Vector2.from_angle(k * TAU / 16.0)
				if ParkMap.water_sd(sp + d * 5.5) < -1.5:
					best = d
					break
			m.owner_node.rotation.y = atan2(-best.x, -best.y)
			m._cam_yaw = m.owner_node.rotation.y + 0.6
			for k in m.agents:
				m.agents[k].place(m._owner_pos() + Vector2(1.0, 0.6))
			cast()
			print("OLTA kiyi=", sp, " yon=", best, " ", dirs)
			await get_tree().create_timer(1.2).timeout
			if arg == "bite" and _fs == "wait":
				_wait = 0.0
				await get_tree().create_timer(0.6).timeout
				_win = 99.0
		"pazar":
			force_pazar = true
			if stalls.is_empty():
				print("PAZAR YOK")
				return
			var s: Dictionary = stalls[mini(2, stalls.size() - 1)]
			var fp: Vector2 = s["front"]
			m._place_owner(fp + (fp - s["pos"]).normalized() * 3.5)
			var d2: Vector2 = s["pos"] - m._owner_pos()
			m.owner_node.rotation.y = atan2(-d2.x, -d2.y)
			m._cam_yaw = m.owner_node.rotation.y + 0.45
			for k in m.agents:
				m.agents[k].place(m._owner_pos() + Vector2(1.0, 0.6))
			print("PAZAR tezgah=", stalls.size(), " yer=", pazar_pos)
		"dondurma":
			force_ice = true
			if cart.is_empty():
				print("DONDURMA YOK")
				return
			var fp2: Vector2 = cart["front"]
			m._place_owner(fp2 + (fp2 - cart["pos"]).normalized() * 0.5)
			_face_cart()
			m._cam_yaw = m.owner_node.rotation.y + 0.5
			for k in m.agents:
				m.agents[k].place(m._owner_pos() + Vector2(1.0, 0.6))
			state.d["coins"] = maxi(int(state.d["coins"]), 100)
			if arg == "trick":
				start_trick()
			print("DONDURMA ", cart["pos"])
