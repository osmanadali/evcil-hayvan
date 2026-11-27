extends Node
## Mahalle esnafi ve sosyal yerler (uydurma adlar).
## - Firin: sicak ekmek, simit, pogaca, acma; kapidan buhar tuter. Ekmek tostta / koftede kullanilir.
## - Kasap: kiyma (kofte icin) ve kopege uygun iri cig kemik.
## - Manav: kaldirimda meyve-sebze kasalari; domates, biber, patates, salatalik, elma, muz.
## - Berber: ici yurunebilir (scripts/barber_interior.gd): koltuga otur, sac modeli / rengi / sakal sec, ode.
## - Spor salonu: ici yurunebilir (scripts/gym_interior.gd): kosu bandi, dambil, mekik; uyelik; guc / dayaniklilik.
## - Kahvehane: kaldirimdaki masada otur, kahveci cay getirir; rakiple tavla (zar yarisi) ya da okey oyna.
## - Cuma ogle: caminin onunde cemaat toplanir. Arada bir ana yoldan kornalarla dugun konvoyu gecer.
## Hepsi yan panelden kullanilir (F / dokunmatik dugme).

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const Npc = preload("res://scripts/npc.gd")

# [tur, ad, alt yazi, renk, duvar rengi, hedef]
const SHOPS := [
	["firin", "Altın Başak Fırını", "SICAK EKMEK · SİMİT · POĞAÇA", "c7802b", "eadcc0", "home"],
	["manav", "Bereket Manav", "MEYVE · SEBZE", "3f8f3a", "e3dccb", "home"],
	["kahvehane", "Dostlar Kıraathanesi", "ÇAY · TAVLA · OKEY", "7a4a2a", "d8cbb0", "park"],
	["kasap", "Kardeşler Kasabı", "ET · KIYMA · KEMİK", "b3262b", "f0ece4", "road"],
	["berber", "Makas Berber Salonu", "SAÇ · SAKAL · BAKIM", "2f5fa8", "e8e4dc", "road"],
	["spor", "Kondisyon Spor Salonu", "FİTNESS · AĞIRLIK · KOŞU", "d24a1f", "d9dcdf", "home"],
]
# Ici yurunebilen esnaf (otomatik kayar kapi, shop_spots'a eklenir): tur -> [ic mekan betigi, kapi yazisi]
const INTERIORS := {"berber": ["res://scripts/barber_interior.gd", "Berbere Gir"],
	"spor": ["res://scripts/gym_interior.gd", "Spor Salonuna Gir"]}
# kimlik -> [ad (canta), fiyat, yenebilir mi]
const GOODS := {
	"ekmek": ["Ekmek", 4, false], "simit": ["Simit", 5, true], "pogaca": ["Poğaça", 4, true], "acma": ["Açma", 5, true],
	"kiyma": ["Kıyma", 18, false], "kemik": ["Çiğ Kemik", 6, false],
	"domates": ["Domates", 3, false], "biber": ["Biber", 2, false], "patates": ["Patates", 3, false],
	"salatalik": ["Salatalık", 2, false], "elma": ["Elma", 3, true], "muz": ["Muz", 4, true],
}
const SELL := {"firin": ["ekmek", "simit", "pogaca", "acma"], "kasap": ["kiyma", "kemik"],
	"manav": ["domates", "biber", "patates", "salatalik", "elma", "muz"]}
const HAIR_COLORS := [["Doğal Kahve", "4a3324"], ["Simsiyah", "17120f"], ["Kumral", "8a5a35"], ["Sarı", "d9b56a"],
	["Kızıl", "a8452a"], ["Kır", "b9b6b0"], ["Pembe", "e07aa8"], ["Mavi", "3f6fd0"]]
const CUT_PRICE := 25
const DYE_PRICE := 30
const TEA_PRICE := 3
const TILE_COLORS := [["Kırmızı", "e0453a"], ["Sarı", "f2c230"], ["Mavi", "4f8fe0"], ["Siyah", "c9ccd2"]]
const TAVLA_PIPS := 167

var m: Node
var state: Node
var shops: Array = []           # {kind, name, accent, pos (kapi onu), root, tw, c}
var seats: Array = []           # kahvehane oyuncu sandalyeleri: {pos, yaw, table (Node3D), op (rakip model), dice}
var seat: Dictionary = {}       # oturuluyorsa {i, t, tea_t, glass}
var game: Dictionary = {}       # tavla / okey durumu
var _poles: Array = []          # berber diregi seritleri
var _smell := false
var _npcs: Array = []           # kahvehane musterileri (act icin)
# Cuma
var _mosques: Array = []        # [{c, gather}]
var _crowd: Array = []          # Npc
var _crowd_at := -1
var _crowd_t := 0.0
var _last_clock := -1.0
# Dugun konvoyu
var _convoy: Dictionary = {}    # {path: PackedVector2Array, cum: Array, s, cars: [Node3D], horn: AudioStreamPlayer3D, ht}
var _convoy_t := 240.0
var _horn: AudioStreamWAV


func is_seated() -> bool:
	return not seat.is_empty()


func shop_of(kind: String) -> Dictionary:
	for s in shops:
		if s["kind"] == kind:
			return s
	return {}


# ---------------------------------------------------------------- kurulum

func build() -> void:
	if not state.d.has("gun"):
		state.d["gun"] = int(Time.get_datetime_dict_from_system()["weekday"])
	var w: Node = m.world
	var targets := {}
	if ParkMap.zone == "":
		targets["home"] = m.HOME_DOOR + m.HOME_DOOR_OUT * 10.0 + Vector2(25.0, -20.0)
	if ParkMap.has_spot("baslangic"):
		targets["park"] = ParkMap.spot("baslangic") + Vector2(35.0, -30.0)
	var ref: Vector2 = targets.get("home", targets.get("park", Vector2.ZERO))
	var best := Vector2.INF
	for r in ParkMap.data["roads"]:
		var rk := String(r.get("k", ""))
		if not (rk.begins_with("secondary") or rk.begins_with("tertiary") or rk.begins_with("primary")):
			continue
		var ids: Array = r["n"]
		for i in ids.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(ref, ParkMap.nodes[int(ids[i])], ParkMap.nodes[int(ids[i + 1])])
			if q.distance_to(ref) > 50.0 and q.distance_to(ref) < ref.distance_to(best):
				best = q
	if best != Vector2.INF:
		targets["road"] = best
	var taken: Array = []
	for k in w.shop_spots:
		taken.append(k["pos"])
	for pl in SHOPS:
		var t: Vector2 = targets.get(pl[5], targets.get("park", targets.get("road", Vector2.INF)))
		if t == Vector2.INF:
			continue
		var lot: Array = m.eateries._find_lot(t, taken)
		if lot.is_empty():
			print("ESNAF yer bulunamadi: ", pl[1])
			continue
		taken.append(lot[0])
		var sp := _building(lot[0], lot[1], pl)
		shops.append(sp)
		if INTERIORS.has(pl[0]):
			var tw: Vector2 = (lot[1] as Vector2).normalized()
			var spot := {"name": pl[1], "kind": pl[0], "pos": sp["pos"], "accent": pl[3], "interior": INTERIORS[pl[0]][0],
				"enter": INTERIORS[pl[0]][1], "dir": tw, "center": lot[0], "tw": tw}
			w.auto_door(spot, (lot[0] as Vector2) + tw * 3.6, tw, 2.0)
			w.shop_spots.append(spot)
			sp["spot"] = spot
		print("ESNAF ", pl[1], " @ ", (sp["pos"] as Vector2).round())
	_find_mosques()
	_horn = _make_horn()


func _w2(r: Node3D, local: Vector2) -> Vector2:
	var g := r.global_transform * Vector3(local.x, 0, local.y)
	return Vector2(g.x, g.z)


func _ly(r: Node3D, local: Vector2) -> float:
	return ParkMap.walk_height(_w2(r, local)) - r.global_position.y


func _person(kind: String, shirt: Color, pants: Color) -> PersonModel:
	var v := PersonModel.new()
	v.kind = kind
	v.tint = shirt
	v.tint2 = shirt
	v.pants = pants
	return v


func _building(c: Vector2, tw: Vector2, pl: Array) -> Dictionary:
	var w: Node = m.world
	var kind: String = pl[0]
	var rot := atan2(tw.x, tw.y)
	var r: Node3D = w._root(c, rot)
	const HX := 4.2
	const HZ := 3.6
	var accent: String = pl[3]
	var body := Kit.mat(pl[4], 0.85)
	var dark := Kit.mat("2b2d31", 0.4)
	# Govde: on yuzu 0.7 m geride (vitrin girintisi), iki kat
	Kit.box(r, Vector3(HX * 2.0, 6.4, HZ * 2.0 - 0.7), Vector3(0, 1.8, -0.35), body)
	Kit.box(r, Vector3(HX * 2.0 + 0.3, 0.3, HZ * 2.0 + 0.3), Vector3(0, 5.1, 0), Kit.mat("5b5f66", 0.7))
	for sx in [-1.0, 1.0]:
		Kit.box(r, Vector3(0.4, 6.4, 0.75), Vector3(sx * (HX - 0.2), 1.8, HZ - 0.37), body)
	Kit.box(r, Vector3(HX * 2.0, 2.2, 0.75), Vector3(0, 3.9, HZ - 0.37), body)
	for x in [-2.4, 0.0, 2.4]:
		Kit.box(r, Vector3(1.2, 1.1, 0.06), Vector3(x, 4.15, HZ + 0.02), Kit.mat("3d4a55", 0.15))
		Kit.box(r, Vector3(1.35, 0.08, 0.15), Vector3(x, 3.55, HZ + 0.06), Kit.mat("d9d4c8", 0.6))
	# Arka ve yan cepheler (lokantalarla ayni: pencereler, silme, yan levha, cati ekipmani; duz kutu kalmasin)
	m.eateries._back_and_sides(r, HX, HZ, body, Kit.mat("3d4a55", 0.15), Kit.mat("d9d4c8", 0.6), accent, pl)
	# Tabela
	Kit.box(r, Vector3(HX * 2.0 - 0.6, 0.85, 0.14), Vector3(0, 3.05, HZ + 0.08), Kit.mat(accent, 0.45))
	var nl: Label3D = w._text(r, pl[1], Vector3(0, 3.13, HZ + 0.16), Color.WHITE, 0.32)
	nl.font = load("res://assets/fonts/Bangers-Regular.ttf")
	nl.visibility_range_end = 110.0
	var sub: Label3D = w._text(r, pl[2], Vector3(0, 2.8, HZ + 0.16), Color("fff3d6"), 0.14)
	sub.visibility_range_end = 60.0
	# Aydinlik ic duvar
	var warm := StandardMaterial3D.new()
	warm.albedo_color = Color("f6ead2") if kind != "kasap" else Color("f4f6f6")
	warm.emission_enabled = true
	warm.emission = Color("ffdcae") if kind != "kasap" else Color("eef6ff")
	warm.emission_energy_multiplier = 0.6
	Kit.box(r, Vector3(HX * 2.0 - 0.8, 2.4, 0.04), Vector3(0, 1.25, HZ - 0.68), warm)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.82, 0.9, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	var sp := {"kind": kind, "name": pl[1], "accent": accent, "root": r, "tw": tw, "c": c, "pos": c + tw * (HZ + 1.0)}
	match kind:
		"firin":
			_firin(r, HX, HZ, glass, dark)
		"kasap":
			_kasap(r, HX, HZ, glass, dark)
		"manav":
			_manav(r, HX, HZ)
		"berber":
			_berber(r, HX, HZ, glass, dark)
		"spor":
			_spor(r, HX, HZ, glass, dark)
		"kahvehane":
			_kahvehane(r, HX, HZ, glass, dark)
	# Tente (cizgili)
	var aw := Node3D.new()
	aw.position = Vector3(0, 2.72, HZ + 0.5)
	aw.rotation.x = 0.32
	r.add_child(aw)
	for k in 9:
		Kit.box(aw, Vector3((HX * 2.0 + 0.2) / 9.0, 0.05, 1.1), Vector3(-HX - 0.1 + (k + 0.5) * (HX * 2.0 + 0.2) / 9.0, 0, 0),
			Kit.mat(accent if k % 2 == 0 else "f4f1ea", 0.7))
	var o := OmniLight3D.new()
	o.position = Vector3(0, 2.4, HZ + 1.2)
	o.light_color = Color("ffd59a")
	o.omni_range = 6.0
	o.light_energy = 0.7
	o.distance_fade_enabled = true
	o.distance_fade_begin = 60.0
	o.distance_fade_length = 20.0
	r.add_child(o)
	# Carpisma: govdenin dort kenari
	var bs := Basis(Vector3.UP, rot)
	var corner := func(x: float, z: float) -> Vector2:
		var v := bs * Vector3(x, 0, z)
		return c + Vector2(v.x, v.z)
	var fz := HZ - 0.72
	for e in [[-HX, -HZ, HX, -HZ], [HX, -HZ, HX, fz], [HX, fz, -HX, fz], [-HX, fz, -HX, -HZ]]:
		w._add_segment(corner.call(e[0], e[1]), corner.call(e[2], e[3]))
	return sp


func _glass_front(r: Node3D, HX: float, HZ: float, glass: Material, dark: Material) -> void:
	Kit.box(r, Vector3(HX * 2.0 - 0.8, 2.5, 0.03), Vector3(0, 1.3, HZ - 0.05), glass)
	for x in [-HX + 0.4, -0.7, 0.7, HX - 0.4]:
		Kit.box(r, Vector3(0.09, 2.6, 0.1), Vector3(x, 1.3, HZ - 0.05), dark)
	Kit.box(r, Vector3(HX * 2.0 - 0.7, 0.1, 0.12), Vector3(0, 2.58, HZ - 0.05), dark)
	Kit.box(r, Vector3(HX * 2.0 - 0.7, 0.3, 0.14), Vector3(0, 0.15, HZ - 0.05), dark)
	Kit.box(r, Vector3(0.03, 0.45, 0.03), Vector3(0.5, 1.1, HZ + 0.02), Kit.mat("c9ccd0", 0.3))


func _staff(r: Node3D, local: Vector3, kind: String, shirt: String) -> PersonModel:
	var v := _person(kind, Color(shirt), Color("2d3138"))
	v.position = local
	v.rotation.y = PI          # model -Z'ye bakar; vitrine / kapiya (+Z) donsun
	r.add_child(v)
	return v


func _firin(r: Node3D, HX: float, HZ: float, glass: Material, dark: Material) -> void:
	# Arkada tas firin agzi (kor isigi), raflarda ekmekler, vitrinde simit sirigi
	var stone := Kit.mat("8a7a6a", 0.95)
	Kit.box(r, Vector3(2.4, 1.7, 0.3), Vector3(-1.6, 0.85, HZ - 0.55), stone)
	Kit.box(r, Vector3(0.9, 0.55, 0.05), Vector3(-1.6, 0.95, HZ - 0.39), Kit.glow("ff7a1a", 2.6))
	var bread := Kit.mat("c98a3e", 0.85)
	var crust := Kit.mat("a8692a", 0.8)
	for row in 3:
		var y := 0.6 + row * 0.5
		Kit.box(r, Vector3(2.6, 0.04, 0.3), Vector3(1.9, y, HZ - 0.5), Kit.mat("6b4526", 0.7))
		for k in 7:
			Kit.capsule(r, 0.07, 0.3, Vector3(0.85 + k * 0.33, y + 0.08, HZ - 0.5), bread if k % 2 == 0 else crust, Vector3(PI / 2, 0.3, 0))
	# Vitrin tezgahi: simit ve pogaca
	Kit.box(r, Vector3(2.6, 0.9, 0.35), Vector3(1.9, 0.45, HZ - 0.25), Kit.mat("e8e2d4", 0.5))
	for k in 6:
		Kit.torus(r, 0.03, 0.08, Vector3(1.0 + k * 0.36, 0.93, HZ - 0.25), Kit.mat("b8803a", 0.8))
	for k in 5:
		Kit.ball(r, 0.07, Vector3(1.1 + k * 0.38, 0.95, HZ - 0.12), Kit.mat("d9a04c", 0.6), Vector3(1.0, 0.6, 1.0), 8)
	_glass_front(r, HX, HZ, glass, dark)
	# Simit sirigi kapinin yaninda
	Kit.cyl(r, 0.02, 0.02, 1.4, Vector3(-HX + 0.9, 0.8, HZ + 0.4), Kit.mat("5b3a1f", 0.6), 6)
	for k in 6:
		Kit.torus(r, 0.03, 0.075, Vector3(-HX + 0.9, 0.35 + k * 0.17, HZ + 0.4), Kit.mat("b8803a", 0.8), Vector3(PI / 2, 0, 0))
	_staff(r, Vector3(1.9, 0, HZ - 1.0), "erkek", "f4f2ea")
	# Buhar: kapidan ve bacadan
	_steam(r, Vector3(0, 2.3, HZ + 0.3), 14, 0.5)
	Kit.box(r, Vector3(0.5, 1.4, 0.5), Vector3(-2.6, 5.9, -1.2), Kit.mat("9a8f84", 0.9))
	_steam(r, Vector3(-2.6, 6.7, -1.2), 10, 0.9)


func _kasap(r: Node3D, HX: float, HZ: float, glass: Material, dark: Material) -> void:
	# Beyaz fayans, cam buzdolabi tezgah, kancada asili etler
	Kit.box(r, Vector3(HX * 2.0 - 0.8, 0.9, 0.36), Vector3(0, 0.45, HZ - 0.3), Kit.mat("e9eef0", 0.3))
	Kit.box(r, Vector3(HX * 2.0 - 1.0, 0.04, 0.3), Vector3(0, 0.75, HZ - 0.3), Kit.glow("f4fbff", 0.6))
	var meat := Kit.mat("b0322e", 0.55)
	var fat := Kit.mat("f0d9c8", 0.6)
	for k in 7:
		var x := -2.6 + k * 0.85
		Kit.box(r, Vector3(0.5, 0.06, 0.2), Vector3(x, 0.8, HZ - 0.3), meat if k % 3 != 2 else fat)
	Kit.cyl(r, 0.015, 0.015, HX * 2.0 - 1.0, Vector3(0, 2.25, HZ - 0.5), Kit.mat("c9ccd0", 0.25), 6, Vector3(0, 0, PI / 2))
	for k in 5:
		var x := -2.4 + k * 1.2
		Kit.cyl(r, 0.006, 0.006, 0.18, Vector3(x, 2.15, HZ - 0.5), Kit.mat("c9ccd0", 0.25), 4)
		Kit.capsule(r, 0.11, 0.55, Vector3(x, 1.8, HZ - 0.5), meat, Vector3.ZERO)
		Kit.ball(r, 0.08, Vector3(x, 1.6, HZ - 0.45), fat, Vector3(1.0, 0.6, 0.6), 8)
	_glass_front(r, HX, HZ, glass, dark)
	_staff(r, Vector3(-1.0, 0, HZ - 1.0), "erkek", "f6f6f6")


func _manav(r: Node3D, HX: float, HZ: float) -> void:
	# Acik on: kaldirimda egimli kasalar
	var crate := Kit.mat("b98a52", 0.9)
	var fruit := [["d63a2a", 0.05], ["f08a1e", 0.05], ["3f8f2a", 0.04], ["7a2a6a", 0.06], ["f2d23a", 0.05], ["a8c43a", 0.05],
		["c22a3a", 0.045], ["e8c890", 0.05]]
	var mm: Dictionary = {}
	for row in 2:
		for k in 4:
			var x := -2.7 + k * 1.8 - (0.0 if row == 0 else 0.0)
			var z := HZ + 0.25 + row * 0.55
			var y := 0.35 + (1 - row) * 0.35
			var cr := Node3D.new()
			cr.position = Vector3(x, y, z)
			cr.rotation.x = 0.28
			r.add_child(cr)
			Kit.box(cr, Vector3(1.0, 0.2, 0.5), Vector3.ZERO, crate)
			var f: Array = fruit[(row * 4 + k) % fruit.size()]
			var fm: StandardMaterial3D = mm.get(f[0], null)
			if fm == null:
				fm = Kit.mat(f[0], 0.45)
				mm[f[0]] = fm
			var rad: float = f[1]
			for i in 5:
				for j in 3:
					Kit.ball(cr, rad, Vector3(-0.38 + i * 0.19, 0.12, -0.15 + j * 0.15), fm, Vector3.ONE, 6)
			# Kasa ayaklari
			Kit.box(r, Vector3(0.9, y - 0.05, 0.08), Vector3(x, (y - 0.05) * 0.5, z + 0.2), crate)
	# Fiyat levhalari
	m.world._text(r, "Domates 3₺  ·  Biber 2₺  ·  Patates 3₺  ·  Elma 3₺", Vector3(0, 1.6, HZ - 0.6), Color("2b2d31"), 0.11)
	Kit.box(r, Vector3(HX * 2.0 - 1.0, 0.05, 0.6), Vector3(0, 0.9, HZ - 0.5), Kit.mat("6b4526", 0.7))
	_staff(r, Vector3(2.8, 0, HZ - 0.9), "erkek", "3f8f3a")


func _berber(r: Node3D, HX: float, HZ: float, glass: Material, dark: Material) -> void:
	# Ayna, koltuk, ve kapida donen berber diregi
	Kit.box(r, Vector3(3.6, 1.2, 0.03), Vector3(0, 1.5, HZ - 0.64), Kit.mat("cfe0ea", 0.05))
	for x in [-1.0, 1.0]:
		Kit.cyl(r, 0.25, 0.3, 0.5, Vector3(x, 0.25, HZ - 0.3), Kit.mat("2b2d31", 0.4), 12)
		Kit.box(r, Vector3(0.55, 0.12, 0.5), Vector3(x, 0.55, HZ - 0.3), Kit.mat("a32a2a", 0.4))
		Kit.box(r, Vector3(0.55, 0.7, 0.1), Vector3(x, 0.95, HZ - 0.52), Kit.mat("a32a2a", 0.4))
	_glass_front(r, HX, HZ, glass, dark)
	var pole := Node3D.new()
	pole.position = Vector3(-HX + 0.7, 1.4, HZ + 0.15)
	r.add_child(pole)
	Kit.cyl(pole, 0.11, 0.11, 0.05, Vector3(0, 0.62, 0), Kit.mat("d9d4c8", 0.3), 12)
	Kit.cyl(pole, 0.11, 0.11, 0.05, Vector3(0, -0.62, 0), Kit.mat("d9d4c8", 0.3), 12)
	Kit.cyl(pole, 0.09, 0.09, 1.2, Vector3.ZERO, Kit.glow("f4f4f4", 0.5), 12)
	var spin := Node3D.new()
	pole.add_child(spin)
	for k in 6:
		var col := "d22a2a" if k % 2 == 0 else "2a4fd2"
		Kit.box(spin, Vector3(0.03, 1.2, 0.03), Vector3(cos(k * TAU / 6.0) * 0.092, 0, sin(k * TAU / 6.0) * 0.092), Kit.glow(col, 0.8), Vector3(0.0, -k * TAU / 6.0, 0.45))
	_poles.append(spin)
	_staff(r, Vector3(0.0, 0, HZ - 0.9), "erkek", "2a2d33")


func _spor(r: Node3D, HX: float, HZ: float, glass: Material, dark: Material) -> void:
	# Vitrinden gorunen kosu bantlari ve dambil rafi; camda buyuk yazi
	var blk := Kit.mat("1d1f24", 0.5)
	for x in [-2.2, 2.2]:
		Kit.box(r, Vector3(0.7, 0.12, 1.4), Vector3(x, 0.16, HZ - 1.3), blk)
		Kit.box(r, Vector3(0.06, 1.1, 0.06), Vector3(x - 0.3, 0.7, HZ - 1.9), blk)
		Kit.box(r, Vector3(0.06, 1.1, 0.06), Vector3(x + 0.3, 0.7, HZ - 1.9), blk)
		Kit.box(r, Vector3(0.7, 0.25, 0.12), Vector3(x, 1.25, HZ - 1.9), blk, Vector3(0.5, 0, 0))
	Kit.box(r, Vector3(1.4, 0.06, 0.4), Vector3(0, 0.6, HZ - 1.6), Kit.mat("8a8f96", 0.3))
	for k in 5:
		Kit.cyl(r, 0.06, 0.06, 0.26, Vector3(-0.5 + k * 0.25, 0.7, HZ - 1.6), blk, 10, Vector3(0, 0, PI * 0.5))
	_glass_front(r, HX, HZ, glass, dark)
	m.world._text(r, "AÇIK 07:00 - 23:00", Vector3(0, 2.3, HZ + 0.02), Color("ffd8c8"), 0.12)
	_staff(r, Vector3(-1.0, 0, HZ - 1.2), "kadin", "d24a1f")


func _kahvehane(r: Node3D, HX: float, HZ: float, glass: Material, dark: Material) -> void:
	_glass_front(r, HX, HZ, glass, dark)
	# Icerde eski bir duvar saati ve televizyon
	Kit.box(r, Vector3(1.2, 0.7, 0.06), Vector3(2.2, 2.0, HZ - 0.64), Kit.mat("1a1c20", 0.3))
	Kit.cyl(r, 0.25, 0.25, 0.04, Vector3(-2.2, 2.05, HZ - 0.64), Kit.mat("f2efe4", 0.4), 16, Vector3(PI / 2, 0, 0))
	var wood := Kit.mat("6b3d22", 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# Kaldirimda iki masa; masa basina iki sandalye (karsilikli, yan yana yonde)
	for ti in 2:
		var tx := -2.5 if ti == 0 else 2.5
		var tz := HZ + 1.25
		var tl := Vector2(tx, tz)
		var ty := _ly(r, tl)
		var table := Node3D.new()
		table.position = Vector3(tx, ty, tz)
		r.add_child(table)
		Kit.box(table, Vector3(0.7, 0.04, 0.7), Vector3(0, 0.7, 0), Kit.mat("d9cdb5", 0.5))
		Kit.box(table, Vector3(0.06, 0.68, 0.06), Vector3(0, 0.34, 0), wood)
		Kit.box(table, Vector3(0.4, 0.02, 0.4), Vector3(0, 0.01, 0), wood)
		# Tavla kutusu (acik)
		var board := Node3D.new()
		board.position = Vector3(0, 0.73, 0)
		table.add_child(board)
		Kit.box(board, Vector3(0.5, 0.03, 0.36), Vector3.ZERO, Kit.mat("5a3218", 0.5))
		Kit.box(board, Vector3(0.46, 0.005, 0.32), Vector3(0, 0.017, 0), Kit.mat("e6d2a8", 0.7))
		for k in 12:
			var px := -0.21 + (k % 6) * 0.034 + (0.25 if k >= 6 else 0.0)
			Kit.box(board, Vector3(0.022, 0.003, 0.13), Vector3(px - 0.04, 0.021, 0.08), Kit.mat("a8402a" if k % 2 == 0 else "2a2a2a", 0.6))
			Kit.box(board, Vector3(0.022, 0.003, 0.13), Vector3(px - 0.04, 0.021, -0.08), Kit.mat("2a2a2a" if k % 2 == 0 else "a8402a", 0.6))
		for k in 8:
			Kit.cyl(board, 0.016, 0.016, 0.008, Vector3(-0.18 + (k % 4) * 0.035, 0.026, (0.12 if k < 4 else -0.12)), Kit.mat("f4f0e4" if k < 4 else "3a2418", 0.4), 10)
		var dice: Array = []
		for k in 2:
			var d := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE * 0.022
			d.mesh = bm
			d.material_override = Kit.mat("fbfaf6", 0.3)
			d.position = Vector3(0.05 + k * 0.04, 0.035, 0.0)
			board.add_child(d)
			Kit.ball(d, 0.004, Vector3(0, 0.0115, 0), Kit.mat("1a1a1a", 0.5), Vector3(1, 0.3, 1), 4)
			dice.append(d)
		# Masada cay bardagi (rakibin)
		m.street_food.tea_glass(table, Vector3(-0.22, 0.72, 0.2), true, true)
		# Sandalyeler: masa merkezinin solunda ve saginda
		for si in 2:
			var sx := -0.62 if si == 0 else 0.62
			var cl := Vector2(tx + sx, tz)
			var cy := _ly(r, cl)
			var ch := Node3D.new()
			ch.position = Vector3(cl.x, cy, cl.y)
			ch.rotation.y = PI * 0.5 if si == 0 else -PI * 0.5   # masaya bakar
			r.add_child(ch)
			for lx in [-0.17, 0.17]:
				for lz in [-0.17, 0.17]:
					Kit.box(ch, Vector3(0.03, 0.44, 0.03), Vector3(lx, 0.22, lz), wood)
			Kit.box(ch, Vector3(0.4, 0.04, 0.4), Vector3(0, 0.44, 0), Kit.mat("8a5a35", 0.7))
			Kit.box(ch, Vector3(0.4, 0.45, 0.03), Vector3(0, 0.68, 0.19), wood)
			# Yerel yonden "masaya bak" acisi (person modeli -Z'ye bakar)
			var face := Vector2(tx, tz) - cl
			var yaw_l := atan2(-face.x, -face.y)
			var player_seat := ti == 0 and si == 1
			if player_seat:
				seats.append({"local": cl, "y": cy, "yaw_l": yaw_l, "table": table, "dice": dice, "op": null, "board": board})
			else:
				var v := _person("erkek", Color.from_hsv(rng.randf(), 0.35, rng.randf_range(0.35, 0.7)), Color.from_hsv(rng.randf(), 0.2, 0.25))
				v.seated = true
				v.position = Vector3(cl.x, cy - 0.05, cl.y)
				v.rotation.y = yaw_l
				r.add_child(v)
				_npcs.append(v)
				if ti == 0:
					set_meta("op0", v)
	if seats.size() > 0 and has_meta("op0"):
		seats[0]["op"] = get_meta("op0")
	# Kahveci kapida
	var kv := _staff(r, Vector3(0.9, _ly(r, Vector2(0.9, HZ + 0.6)), HZ + 0.6), "erkek", "f2efe8")
	kv.rotation.y = PI
	set_meta("kahveci", kv)


func _steam(parent: Node3D, at: Vector3, amount: int, size: float) -> CPUParticles3D:
	var pt := CPUParticles3D.new()
	pt.position = at
	pt.amount = amount
	pt.lifetime = 3.0
	pt.local_coords = false
	pt.direction = Vector3.UP
	pt.spread = 18.0
	pt.gravity = Vector3(0.1, 0.25, 0)
	pt.initial_velocity_min = 0.15
	pt.initial_velocity_max = 0.35
	pt.scale_amount_min = 0.6
	pt.scale_amount_max = 1.3
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.8))
	pt.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.3))
	g.set_color(1, Color(1, 1, 1, 0.0))
	pt.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var gt := GradientTexture2D.new()
	var rg := Gradient.new()
	rg.set_color(0, Color(1, 1, 1, 1))
	rg.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = rg
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = gt
	q.material = mat
	pt.mesh = q
	parent.add_child(pt)
	return pt


func _find_mosques() -> void:
	var w: Node = m.world
	for b in ParkMap.data["buildings"]:
		if String(b.get("t", "")) != "cami":
			continue
		var poly := ParkMap.to_poly(b["p"])
		if poly.size() < 3:
			continue
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= poly.size()
		var rp: Vector2 = w._road_point(c)
		var dir := (rp - c).normalized() if rp.distance_to(c) > 0.5 else Vector2(0, 1)
		var g := c
		for k in 40:
			g = c + dir * (2.0 + k * 1.0)
			if not w._inside_building(g) and w.is_free(g, 1.0):
				g += dir * 3.0
				break
		_mosques.append({"c": c, "gather": g, "dir": dir})


# ---------------------------------------------------------------- baglam ve komutlar

func context() -> Array:
	if m._ride != null or m._taxi != null or ParkMap.home != null:
		return []
	if is_seated():
		if game.is_empty():
			return ["Oyun Seç · Tavla / Okey", "esn_games", "play"]
		return ["Oyuna Dön", "esn_resume", "play"]
	var o: Vector2 = m._owner_pos()
	for i in shops.size():
		var s: Dictionary = shops[i]
		if o.distance_to(s["c"]) > 14.0 or s.has("spot"):
			continue
		if s["kind"] == "kahvehane":
			for j in seats.size():
				if o.distance_to(_w2(s["root"], seats[j]["local"])) < 1.0:
					return ["Otur · Tavla / Okey Oyna", "esn_sit:%d" % j, "sit"]
		if o.distance_to(s["pos"]) < 2.4:
			var lbl: String = {"firin": "Fırın · Sıcak Ekmek", "kasap": "Kasap · Et ve Kemik", "manav": "Manav · Meyve Sebze",
				"berber": "Berber · Saç Kesimi", "kahvehane": "Kahvehane · Çay ve Oyun"}.get(s["kind"], s["name"])
			var ic: String = {"firin": "bag", "kasap": "bone", "manav": "cart", "berber": "star", "kahvehane": "drop"}.get(s["kind"], "cart")
			return [lbl, "esn_shop:%d" % i, ic]
	return []


func command(cmd: String) -> void:
	if cmd.begins_with("esn_shop:"):
		open_shop(int(cmd.substr(9)))
	elif cmd.begins_with("esn_sit:"):
		sit(int(cmd.substr(8)))
	elif cmd == "esn_games":
		open_games()
	elif cmd == "esn_resume":
		_show_game()
	elif cmd == "esn_up":
		stand_up()
	elif cmd == "esn_app":
		phone_app()


func open_shop(i: int) -> void:
	if i < 0 or i >= shops.size():
		return
	var s: Dictionary = shops[i]
	_face(s["c"])
	match s["kind"]:
		"firin", "kasap", "manav":
			_goods_panel(s)
		"berber", "spor":
			if s.has("spot"):
				m._enter_shop(s["spot"])
			else:
				_barber_panel()
		"kahvehane":
			var body: VBoxContainer = m.ui._open_panel("DOSTLAR KIRAATHANESİ", "Demli çay, tavla, okey · Cüzdan %d ₺" % int(state.d["coins"]))
			m.ui._panel_item(body, "Çay İç · %d ₺" % TEA_PRICE, func():
				if not state.spend(TEA_PRICE):
					m.ui.toast("Çay için %d ₺ gerekli." % TEA_PRICE)
					return
				m.ui.close_modal()
				m._use_item("Çay")
				_say_staff(s, ["Afiyet olsun!", "Taze demlendi!", "Buyur, tavşan kanı!"][randi() % 3]))
			m.ui._panel_item(body, "Masaya Otur, Oyun Oyna", func():
				m.ui.close_modal()
				sit(0))
			m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
			m.ui._focus_first(body)


func _goods_panel(s: Dictionary) -> void:
	var kind: String = s["kind"]
	var sub: String = {"firin": "Taş fırından yeni çıktı · Cüzdan %d ₺", "kasap": "Taze et, köpeğine iri çiğ kemik · Cüzdan %d ₺",
		"manav": "Tarladan bugün geldi · Cüzdan %d ₺"}[kind] % int(state.d["coins"])
	var body: VBoxContainer = m.ui._open_panel(String(s["name"]).to_upper(), sub)
	for id in SELL[kind]:
		var g: Array = GOODS[id]
		var key: String = id
		if bool(g[2]):
			m.ui._panel_item(body, "%s Ye · %d ₺" % [g[0], int(g[1])], func(): buy(s, key, "eat"))
		if key == "kemik":
			m.ui._panel_item(body, "Köpeğine Kemik Ver · %d ₺" % int(g[1]), func(): buy(s, key, "pet"))
		m.ui._panel_item(body, "%s Al (Çantaya) · %d ₺" % [g[0], int(g[1])], func(): buy(s, key, "bag"))
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func buy(s: Dictionary, id: String, how: String) -> void:
	var g: Array = GOODS[id]
	if how == "pet" and not m.agents.has("kopek"):
		m.ui.toast("Yanında köpek yok. Kemiği çantana alabilirsin.")
		return
	if not state.spend(int(g[1])):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % int(g[1]))
		return
	m.ui.close_modal()
	m._sfx("kasa", -8.0)
	state.count("shop")
	state.count("esnaf")
	var nm: String = g[0]
	match how:
		"bag":
			var bag: Dictionary = state.d.get("bag", {})
			bag[nm] = int(bag.get(nm, 0)) + 1
			state.d["bag"] = bag
			var hint := ""
			if nm in ["Ekmek", "Kıyma", "Domates", "Biber", "Patates", "Salatalık"]:
				hint = " Evde mutfakta pişirebilirsin."
			m.ui.toast("%s çantana kondu · Çanta: %d.%s" % [nm, int(bag[nm]), hint])
		"eat":
			m._use_item(nm)
		"pet":
			_give_bone()
	_say_staff(s, ["Afiyet olsun!", "Yine bekleriz!", "Hayırlı işler!", "Bereketli olsun!"][randi() % 4])
	state.save_game()


func _give_bone() -> void:
	var a: Node3D = m.agents.get("kopek", null)
	if a == null:
		return
	state.add_need("kopek", "hunger", 18.0)
	state.add_need("kopek", "fun", 25.0)
	m._pet_voice("kopek", true)
	var pn: String = state.pet("kopek")["name"]
	m.ui.toast("%s iri çiğ kemiği kaptı, mutlu mutlu kemiriyor! (Pişmiş kemik kıymık yapar, hep çiğ ver.)" % pn)


## Cantadan kullanim (main._use_item once buraya sorar).
func use_item(name: String) -> bool:
	if name != "Çiğ Kemik":
		return false
	if m.agents.has("kopek"):
		_give_bone()
	else:
		var bag: Dictionary = state.d.get("bag", {})
		bag[name] = int(bag.get(name, 0)) + 1
		state.d["bag"] = bag
		m.ui.toast("Kemik köpekler için. Kedi kemik kemirmez.")
	return true


func _say_staff(s: Dictionary, text: String) -> void:
	var r: Node3D = s["root"]
	for ch in r.get_children():
		if ch is PersonModel and not (ch as PersonModel).seated:
			m._say(ch, text)
			return


func _face(p: Vector2) -> void:
	var d: Vector2 = p - m._owner_pos()
	if d.length() > 0.1:
		m.owner_node.rotation.y = atan2(-d.x, -d.y)


# ---------------------------------------------------------------- berber

func _barber_panel() -> void:
	var hr: Array = state.d.get("hair", [0, ""])
	var body: VBoxContainer = m.ui._open_panel("MAKAS BERBER SALONU", "Şu an: %s · Kesim %d ₺ · Boya %d ₺ · Cüzdan %d ₺" % [PersonModel.HAIR_STYLES[int(hr[0])], CUT_PRICE, DYE_PRICE, int(state.d["coins"])])
	for i in PersonModel.HAIR_STYLES.size():
		var k: int = i
		m.ui._panel_item(body, "Kesim: %s · %d ₺" % [PersonModel.HAIR_STYLES[i], CUT_PRICE], func(): _haircut(k, ""))
	m.ui._panel_item(body, "Saç Boyası Seç…", func(): _dye_panel())
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _dye_panel() -> void:
	var body: VBoxContainer = m.ui._open_panel("SAÇ BOYASI", "Renk seç · %d ₺" % DYE_PRICE)
	for c in HAIR_COLORS:
		var hex: String = c[1]
		var b: Button = m.ui._panel_item(body, c[0], func(): _haircut(-1, hex))
		b.add_theme_color_override("font_color", Color(hex).lightened(0.25))
	m.ui._panel_item(body, "Geri", func(): _barber_panel())
	m.ui._focus_first(body)


func _haircut(style: int, hex: String) -> void:
	var price := CUT_PRICE if style >= 0 else DYE_PRICE
	if not state.spend(price):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % price)
		return
	m.ui.close_modal()
	m._sfx("kasa", -8.0)
	var hr: Array = state.d.get("hair", [0, ""]).duplicate()
	if style >= 0:
		hr[0] = style
	if hex != "":
		hr[1] = hex
	state.d["hair"] = hr
	var s := shop_of("berber")
	if not s.is_empty():
		_say_staff(s, "Şöyle buyur, koltuğa geç!" if style >= 0 else "Rengi çok yakışacak!")
	m.ui.toast("Berber makasını şakırdatıyor… çıt çıt çıt…" if style >= 0 else "Boya sürülüyor, biraz bekle…")
	m.owner_model.act("wave", 1.2)
	get_tree().create_timer(1.6).timeout.connect(func():
		apply_hair()
		m._sfx("mutlu", -8.0)
		if not s.is_empty():
			_say_staff(s, "Sıhhatler olsun!")
		m.ui.toast("Sıhhatler olsun! Yeni saçın: %s." % (PersonModel.HAIR_STYLES[int(hr[0])] if style >= 0 else "boyalı"))
		state.save_game())


func apply_hair() -> void:
	var hr: Array = state.d.get("hair", [])
	if hr.size() < 2 or m.owner_model == null:
		return
	m.owner_model.set_hair(int(hr[0]), Color(hr[1]) if String(hr[1]) != "" else Color(0, 0, 0, 0))


# ---------------------------------------------------------------- kahvehane: oturma

func sit(i: int) -> void:
	var s := shop_of("kahvehane")
	if s.is_empty() or is_seated() or i < 0 or i >= seats.size():
		return
	m._moving = false
	m._queue.clear()
	m._steering = false
	m.owner_model.speed = 0.0
	seat = {"i": i, "t": 0.0, "tea_t": 3.0, "glass": null}
	_place_seated()
	m.owner_model.seated = true
	var st: Dictionary = seats[i]
	var r: Node3D = s["root"]
	var k := 0
	for kind in m.agents:
		var a: Node3D = m.agents[kind]
		a.command("lie")
		var ap: Vector2 = _w2(r, st["local"] + Vector2(0.3 + 0.6 * k, -0.7))
		a.place(ap)
		k += 1
	m.ui._actions.visible = false
	m.ui.toast("Masaya oturdun. Kahveci çayını getiriyor. Kalkmak için yürü.")
	if st["op"] != null:
		m._say(st["op"], ["Hoş geldin! Bir el atalım mı?", "Gel bakalım, zar sende!", "Tavla mı okey mi?"][randi() % 3])
	open_games()
	m._update_context()


func _place_seated() -> void:
	var s := shop_of("kahvehane")
	var st: Dictionary = seats[seat["i"]]
	var r: Node3D = s["root"]
	var wp: Vector2 = _w2(r, st["local"])
	m.owner_node.position = Vector3(wp.x, r.global_position.y + float(st["y"]), wp.y)
	m.owner_node.rotation = Vector3(0, r.rotation.y + float(st["yaw_l"]), 0)
	m.owner_model.position = Vector3(0, -0.05, 0)
	m._target = wp


func stand_up() -> void:
	if not is_seated():
		return
	var s := shop_of("kahvehane")
	var st: Dictionary = seats[seat["i"]]
	if is_instance_valid(seat["glass"]):
		seat["glass"].queue_free()
	seat = {}
	game = {}
	m.ui.close_modal()
	m.owner_model.seated = false
	m.owner_model.position = Vector3.ZERO
	var out: Vector2 = _w2(s["root"], st["local"] + Vector2(0.0, 0.7))
	m.owner_node.position = Vector3(out.x, ParkMap.walk_height(out), out.y)
	m._target = out
	for kind in m.agents:
		m.agents[kind].command("come")
	m.ui._actions.visible = true
	m._update_context()


func open_games() -> void:
	var body: VBoxContainer = m.ui._open_panel("KAHVEHANE", "Rakibin hazır. Kazanana bir çay benden!")
	m.ui._panel_item(body, "Tavla Oyna (Zar Yarışı)", func(): start_tavla())
	m.ui._panel_item(body, "Okey Oyna (Hızlı El)", func(): start_okey())
	m.ui._panel_item(body, "Bir Çay Daha · %d ₺" % TEA_PRICE, func():
		m.ui.close_modal()
		_order_tea())
	m.ui._panel_item(body, "Kalk", func(): stand_up())
	m.ui._focus_first(body)


func _order_tea() -> void:
	if not is_seated():
		return
	if not state.spend(TEA_PRICE):
		m.ui.toast("Çay için %d ₺ gerekli." % TEA_PRICE)
		return
	seat["tea_t"] = 2.5
	var kv: Node3D = get_meta("kahveci", null)
	if kv:
		m._say(kv, "Hemen geliyor!")


func _tea_arrives() -> void:
	var st: Dictionary = seats[seat["i"]]
	if is_instance_valid(seat["glass"]):
		seat["glass"].queue_free()
	var t: Node3D = st["table"]
	var tl: Vector3 = t.to_local(m.owner_node.global_position)
	var dir := Vector3(tl.x, 0, tl.z).normalized()
	seat["glass"] = m.street_food.tea_glass(t, Vector3(0, 0.72, 0) + dir * 0.25 + Vector3(-dir.z, 0, dir.x) * 0.12, true, true)
	var kv: Node3D = get_meta("kahveci", null)
	if kv:
		m._say(kv, ["Çayın geldi, afiyet olsun!", "Tavşan kanı, buyur!"][randi() % 2])
	if state.d.has("me"):
		m.needs.add("energy", 12.0)
	m.owner_model.act("sip", 1.8)


# ---------------------------------------------------------------- tavla (zar yarisi)

func start_tavla() -> void:
	game = {"type": "tavla", "me": TAVLA_PIPS, "op": TAVLA_PIPS, "log": "Pullarını önce sen toplarsan kazanırsın. Çift atarsan dört kez oynarsın!", "over": false}
	_show_game()


func _dice_name(a: int, b: int) -> String:
	if a == b:
		return {1: "Hep yek!", 2: "Dubara!", 3: "Dü se!", 4: "Dört cihar!", 5: "Penç!", 6: "Düşeş!"}[a]
	return "%d-%d" % [maxi(a, b), mini(a, b)]


func _roll_visual(a: int, b: int) -> void:
	if not is_seated():
		return
	var dice: Array = seats[seat["i"]]["dice"]
	var vals := [a, b]
	for k in 2:
		var d: MeshInstance3D = dice[k]
		d.rotation = Vector3(0, randf() * TAU, 0)
		d.position = Vector3(randf_range(-0.05, 0.12), 0.035, randf_range(-0.07, 0.07))
		d.scale = Vector3.ONE * (1.0 + 0.04 * vals[k])
	m._sfx("tik", -4.0, randf_range(0.8, 1.2))


func tavla_roll() -> void:
	if game.get("type", "") != "tavla" or game["over"]:
		return
	var a := randi_range(1, 6)
	var b := randi_range(1, 6)
	var mv := (a + b) * (2 if a == b else 1)
	game["me"] = maxi(0, int(game["me"]) - mv)
	_roll_visual(a, b)
	var txt := "Sen: %s → %d ilerledin." % [_dice_name(a, b), mv]
	if int(game["me"]) <= 0:
		game["over"] = true
		game["log"] = txt + "\nBütün pulları topladın, KAZANDIN!"
		_win("tavla")
		_show_game()
		return
	var c := randi_range(1, 6)
	var d := randi_range(1, 6)
	var mv2 := (c + d) * (2 if c == d else 1)
	game["op"] = maxi(0, int(game["op"]) - mv2)
	txt += "\nRakip: %s → %d ilerledi." % [_dice_name(c, d), mv2]
	var op: Node3D = seats[seat["i"]]["op"]
	if c == d and op:
		m._say(op, ["Oh be, %s" % _dice_name(c, d), "Gördün mü zarı?"][randi() % 2])
	elif a == b and op:
		m._say(op, ["Yok artık, yine çift!", "Şansına tüküreyim!"][randi() % 2])
	if int(game["op"]) <= 0:
		game["over"] = true
		txt += "\nRakip pullarını topladı. Kaybettin, bir dahakine!"
		_lose()
	game["log"] = txt
	_show_game()


# ---------------------------------------------------------------- okey (hizli el)
# Taslar: [renk 0..3, sayi 1..13] ya da [-1, 0] = okey (joker). Elde 3 tas tutulur; sira gelince desteden ya da yerden
# bir tas cekilir, biri atilir. Kalan 3 tas bir "per" olursa (ayni sayi farkli renk ya da ayni renk ardisik) el biter.

func start_okey() -> void:
	var pile: Array = []
	for rep in 2:
		for col in 4:
			for n in range(1, 14):
				pile.append([col, n])
	pile.append([-1, 0])
	pile.append([-1, 0])
	pile.shuffle()
	var me: Array = [pile.pop_back(), pile.pop_back(), pile.pop_back()]
	var op: Array = [pile.pop_back(), pile.pop_back(), pile.pop_back()]
	game = {"type": "okey", "pile": pile, "me": me, "op": op, "floor": [], "drawn": false, "over": false,
		"log": "Desteden ya da yerden bir taş çek, sonra birini at. Elindeki 3 taş per olursa bitirirsin!"}
	_show_game()


func _tile_name(t: Array) -> String:
	if int(t[0]) < 0:
		return "OKEY ★"
	return "%s %d" % [TILE_COLORS[int(t[0])][0], int(t[1])]


func _tile_color(t: Array) -> Color:
	return Color("ffd23a") if int(t[0]) < 0 else Color(TILE_COLORS[int(t[0])][1])


static func is_per(h: Array) -> bool:
	if h.size() != 3:
		return false
	var real: Array = []
	for t in h:
		if int(t[0]) >= 0:
			real.append(t)
	if real.size() <= 1:
		return true
	# Ayni sayi, farkli renkler
	var same_n := true
	var cols := {}
	for t in real:
		if int(t[1]) != int(real[0][1]):
			same_n = false
		cols[int(t[0])] = true
	if same_n and cols.size() == real.size():
		return true
	# Ayni renk, ardisik (okey bosluklari doldurur)
	var same_c := true
	var ns: Array = []
	for t in real:
		if int(t[0]) != int(real[0][0]):
			same_c = false
		ns.append(int(t[1]))
	if not same_c:
		return false
	ns.sort()
	for i in range(1, ns.size()):
		if ns[i] == ns[i - 1]:
			return false
	return ns[ns.size() - 1] - ns[0] <= 2


static func _pair_score(h: Array) -> float:
	var sc := 0.0
	for i in h.size():
		if int(h[i][0]) < 0:
			sc += 2.0
			continue
		for j in range(i + 1, h.size()):
			if int(h[j][0]) < 0:
				continue
			if int(h[i][1]) == int(h[j][1]) and int(h[i][0]) != int(h[j][0]):
				sc += 1.0
			elif int(h[i][0]) == int(h[j][0]) and absi(int(h[i][1]) - int(h[j][1])) <= 2 and int(h[i][1]) != int(h[j][1]):
				sc += 1.0
	return sc


## Rakip: 4 tastan birini atar; en iyi kalan eli secer. Atilan tasi dondurur.
static func _best_discard(h4: Array) -> int:
	var best := 0
	var bs := -1.0
	for i in h4.size():
		var rest := h4.duplicate()
		rest.remove_at(i)
		var sc := 100.0 if is_per(rest) else _pair_score(rest)
		sc += randf() * 0.3
		if sc > bs:
			bs = sc
			best = i
	return best


func okey_draw(from_floor: bool) -> void:
	if game.get("type", "") != "okey" or game["over"] or game["drawn"]:
		return
	var t: Array
	if from_floor:
		if (game["floor"] as Array).is_empty():
			return
		t = (game["floor"] as Array).pop_back()
	else:
		if (game["pile"] as Array).is_empty():
			game["over"] = true
			game["log"] = "Deste bitti, el berabere!"
			_show_game()
			return
		t = (game["pile"] as Array).pop_back()
	(game["me"] as Array).append(t)
	game["drawn"] = true
	game["log"] = "Çektiğin taş: %s. Şimdi atacağın taşı seç." % _tile_name(t)
	m._sfx("tik", -6.0, 1.3)
	_show_game()


func okey_discard(i: int) -> void:
	if game.get("type", "") != "okey" or game["over"] or not game["drawn"]:
		return
	var me: Array = game["me"]
	var t: Array = me[i]
	me.remove_at(i)
	(game["floor"] as Array).append(t)
	game["drawn"] = false
	m._sfx("tik", -6.0, 0.9)
	var txt := "Attın: %s." % _tile_name(t)
	if is_per(me):
		game["over"] = true
		game["log"] = txt + "\nPer tamam! Elini açtın, KAZANDIN!"
		_win("okey")
		_show_game()
		return
	# Rakibin sirasi: yerdeki tas isine yararsa onu alir
	var op: Array = game["op"]
	var fl: Array = game["floor"]
	var took := ""
	var with_floor := op.duplicate()
	with_floor.append(fl[fl.size() - 1])
	var di := _best_discard(with_floor)
	var keep := with_floor.duplicate()
	keep.remove_at(di)
	if di != with_floor.size() - 1 and (is_per(keep) or _pair_score(keep) > _pair_score(op) + 0.5):
		op.append(fl.pop_back())
		took = "yerden %s aldı" % _tile_name(op[op.size() - 1])
	else:
		if (game["pile"] as Array).is_empty():
			game["over"] = true
			game["log"] = txt + "\nDeste bitti, el berabere!"
			_show_game()
			return
		op.append((game["pile"] as Array).pop_back())
		took = "desteden çekti"
	var d2 := _best_discard(op)
	var thrown: Array = op[d2]
	op.remove_at(d2)
	fl.append(thrown)
	txt += "\nRakip %s, %s attı." % [took, _tile_name(thrown)]
	if is_per(op):
		game["over"] = true
		var shown: Array = []
		for x in op:
			shown.append(_tile_name(x))
		txt += "\nRakip elini açtı: %s. Kaybettin!" % ", ".join(shown)
		_lose()
	game["log"] = txt
	_show_game()


# ---------------------------------------------------------------- oyun paneli

func _show_game() -> void:
	if game.is_empty():
		open_games()
		return
	if game["type"] == "tavla":
		var body: VBoxContainer = m.ui._open_panel("TAVLA", "Kalan yol · Sen %d  —  Rakip %d" % [int(game["me"]), int(game["op"])])
		var l: Label = m.ui._fx_label(body, game["log"], m.ui.F_BODY, 22, Color.WHITE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(400, 0)
		if not game["over"]:
			m.ui._panel_item(body, "Zar At", func(): tavla_roll())
		else:
			m.ui._panel_item(body, "Bir El Daha", func(): start_tavla())
			m.ui._panel_item(body, "Okey'e Geç", func(): start_okey())
		m.ui._panel_item(body, "Masadan Kalk", func(): stand_up())
		m.ui._focus_first(body)
		return
	var fl: Array = game["floor"]
	var body2: VBoxContainer = m.ui._open_panel("OKEY", "Destede %d taş%s" % [(game["pile"] as Array).size(), (" · Yerde: %s" % _tile_name(fl[fl.size() - 1])) if not fl.is_empty() else ""])
	var l2: Label = m.ui._fx_label(body2, game["log"], m.ui.F_BODY, 22, Color.WHITE)
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.custom_minimum_size = Vector2(400, 0)
	var me: Array = game["me"]
	if game["over"]:
		m.ui._panel_item(body2, "Yeni El", func(): start_okey())
		m.ui._panel_item(body2, "Tavla'ya Geç", func(): start_tavla())
	elif not game["drawn"]:
		var hand: Array = []
		for t in me:
			hand.append(_tile_name(t))
		var hl: Label = m.ui._fx_label(body2, "Elin: " + "  ·  ".join(hand), m.ui.F_BODY, 22, m.ui.ACCENT)
		hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hl.custom_minimum_size = Vector2(400, 0)
		m.ui._panel_item(body2, "Desteden Çek", func(): okey_draw(false))
		if not fl.is_empty():
			var fb: Button = m.ui._panel_item(body2, "Yerden Al: %s" % _tile_name(fl[fl.size() - 1]), func(): okey_draw(true))
			fb.add_theme_color_override("font_color", _tile_color(fl[fl.size() - 1]))
	else:
		for i in me.size():
			var k: int = i
			var b: Button = m.ui._panel_item(body2, "At: %s" % _tile_name(me[i]), func(): okey_discard(k))
			b.add_theme_color_override("font_color", _tile_color(me[i]))
	m.ui._panel_item(body2, "Masadan Kalk", func(): stand_up())
	m.ui._focus_first(body2)


func _win(what: String) -> void:
	state.count("kahvehane")
	state.add_coins(5)
	m._sfx("mutlu", -6.0)
	for kind in m.agents:
		state.add_need(kind, "fun", 10.0)
	var op: Node3D = seats[seat["i"]]["op"] if is_seated() else null
	if op:
		m._say(op, ["Helal olsun, çaylar benden!", "Bu sefer sen kazandın…", "Rövanş isterim!"][randi() % 3])
	m.ui.toast("%s kazandın! Rakibin çay ısmarladı." % ("Tavlayı" if what == "tavla" else "Okeyi"))
	if is_seated():
		seat["tea_t"] = 2.0
	state.save_game()


func _lose() -> void:
	state.count("kahvehane")
	var op: Node3D = seats[seat["i"]]["op"] if is_seated() else null
	if op:
		m._say(op, ["Ustana saygı!", "Hadi bir el daha!", "Zar bende bugün!"][randi() % 3])
	state.save_game()


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	for p in _poles:
		(p as Node3D).rotation.y += dt * 1.6
	_update_day()
	if m._mode != "play" and m._mode != "debug":
		return
	var o: Vector2 = m._owner_pos()
	# Firin kokusu
	var f := shop_of("firin")
	if not f.is_empty() and ParkMap.home == null:
		var d: float = o.distance_to(f["pos"])
		if d < 10.0 and not _smell:
			_smell = true
			m.ui.toast("Mis gibi taze ekmek kokusu geliyor! Fırından sıcak simit al.")
		elif d > 30.0:
			_smell = false
	# Kahvehane musterileri arada zar atar / cay icer
	for v in _npcs:
		if not (v as PersonModel).is_acting() and randf() < dt * 0.08:
			(v as PersonModel).act("throw" if randf() < 0.5 else "sip", 1.4)
	_update_seat(dt)
	_update_crowd(dt, o)
	_update_convoy(dt, o)


func _update_seat(dt: float) -> void:
	if not is_seated():
		return
	seat["t"] += dt
	if (m._mode != "play" and m._mode != "debug") or m._ride != null or (seat["t"] > 0.6 and (m.ui.stick.length() > 0.5 or m._moving)):
		stand_up()
		return
	_place_seated()
	if seat["tea_t"] > 0.0:
		seat["tea_t"] -= dt
		if seat["tea_t"] <= 0.0:
			_tea_arrives()


# ---------------------------------------------------------------- cuma: camide cemaat

func _update_day() -> void:
	if _last_clock >= 0.0 and m.clock < _last_clock - 12.0:
		state.d["gun"] = int(state.d.get("gun", 0)) + 1
		if is_friday():
			m.ui.toast("Bugün cuma. Öğle vakti camilerin önü kalabalık olur.")
	_last_clock = m.clock


func is_friday() -> bool:
	return int(state.d.get("gun", 0)) % 7 == 5


func _update_crowd(dt: float, o: Vector2) -> void:
	_crowd_t -= dt
	if _crowd_t > 0.0:
		return
	_crowd_t = 1.5
	var want := -1
	if is_friday() and m.clock >= 11.8 and m.clock <= 13.6 and ParkMap.home == null:
		var bd := 230.0
		for i in _mosques.size():
			var d: float = o.distance_to(_mosques[i]["gather"])
			if d < bd:
				bd = d
				want = i
	if want != _crowd_at:
		_clear_crowd()
		if want >= 0:
			_spawn_crowd(want)
	# Yakindan gecene "Hayirli cumalar"
	if _crowd_at >= 0 and randf() < 0.35:
		for n in _crowd:
			if o.distance_to(Vector2(n.position.x, n.position.z)) < 4.0:
				m._say(n, ["Hayırlı cumalar!", "Cumanız mübarek olsun!", "Allah kabul etsin."][randi() % 3])
				break


func _spawn_crowd(i: int) -> void:
	_crowd_at = i
	var g: Vector2 = _mosques[i]["gather"]
	var rng := RandomNumberGenerator.new()
	rng.seed = i * 31 + int(state.d.get("gun", 0))
	var shirts := ["f2f2ee", "e6e1d4", "3a3d42", "5a6a7a", "8a7a5a", "2f4f6a", "d9d2c0"]
	for k in 18:
		var n := Npc.new()
		var v := _person("erkek" if k % 5 != 4 else "kadin", Color(shirts[k % shirts.size()]).darkened(rng.randf() * 0.2), Color.from_hsv(0.6, 0.15, rng.randf_range(0.15, 0.35)))
		n.visual = v
		n.roam_center = g + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		n.roam_radius = 6.0
		n.walk_speed = rng.randf_range(0.6, 1.0)
		n.world = m.world
		n.short_pause = true
		n.add_child(v)
		m.add_child(n)
		_crowd.append(n)
	print("CUMA kalabalik @ ", g.round())


func _clear_crowd() -> void:
	for n in _crowd:
		if is_instance_valid(n):
			n.queue_free()
	_crowd.clear()
	_crowd_at = -1


# ---------------------------------------------------------------- dugun konvoyu

func _make_horn() -> AudioStreamWAV:
	var rate := 22050
	var pattern := [[0.16, true], [0.09, false], [0.16, true], [0.09, false], [0.55, true], [0.5, false]]
	var data := PackedByteArray()
	var t := 0.0
	for seg in pattern:
		var n := int(float(seg[0]) * rate)
		for i in n:
			var v := 0.0
			if seg[1]:
				var env := minf(1.0, minf(i, n - i) / 200.0)
				v = (signf(sin(TAU * 415.0 * t)) * 0.5 + signf(sin(TAU * 523.0 * t)) * 0.5) * 0.28 * env
				v = v * 0.7 + sin(TAU * 830.0 * t) * 0.08 * env
			var s := int(clampf(v, -1.0, 1.0) * 32000.0)
			data.append(s & 0xff)
			data.append((s >> 8) & 0xff)
			t += 1.0 / rate
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## Oyuncunun yakinindan gecen uzun bir yol rotasi (dugum dizisi) secer.
func _convoy_path(o: Vector2, tries := 40) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_d := 1e9
	for attempt in tries:
		var k := randi() % ParkMap.nodes.size()
		var p0: Vector2 = ParkMap.nodes[k]
		var d0 := p0.distance_to(o)
		if ParkMap.road_next[k].is_empty() or d0 < 60.0 or d0 > (320.0 if tries > 40 else 180.0) or not ParkMap.inside_bounds(p0, 30.0):
			continue
		var path := PackedVector2Array([p0])
		var prev := -1
		var cur := k
		var L := 0.0
		var near := d0
		for step in 400:
			var opts: Array = []
			for nb in ParkMap.road_next[cur]:
				if nb != prev and ParkMap.inside_bounds(ParkMap.nodes[nb], 10.0):
					opts.append(nb)
			if opts.is_empty():
				break
			# Duz devam etmeyi ve oyuncuya yaklasmayi tercih et
			var bn: int = opts[0]
			var bsc := -1e9
			for nb in opts:
				var sc := 0.0
				if prev >= 0:
					sc += (ParkMap.nodes[cur] - ParkMap.nodes[prev]).normalized().dot((ParkMap.nodes[nb] - ParkMap.nodes[cur]).normalized()) * 2.0
				if near > 25.0:
					sc -= ParkMap.nodes[nb].distance_to(o) / 60.0
				sc += randf() * 0.3
				if sc > bsc:
					bsc = sc
					bn = nb
			L += ParkMap.nodes[cur].distance_to(ParkMap.nodes[bn])
			prev = cur
			cur = bn
			path.append(ParkMap.nodes[cur])
			near = minf(near, ParkMap.nodes[cur].distance_to(o))
			if L > 520.0:
				break
		if L < 200.0:
			continue
		var sc2 := near + (0.0 if L > 350.0 else 30.0)
		if sc2 < best_d:
			best_d = sc2
			best = path
	return best if best_d < (70.0 if tries > 40 else 40.0) else PackedVector2Array()


func start_convoy(force := false) -> bool:
	if not _convoy.is_empty() or m.world.car_mesh == null:
		return false
	var o: Vector2 = m._owner_pos()
	var path := _convoy_path(o, 400 if force else 40)
	if path.size() < 3:
		if force:
			print("DUGUN rota bulunamadi")
		return false
	# Serit: yolun sagindan
	var lane := PackedVector2Array()
	for i in path.size():
		var a: Vector2 = path[maxi(i - 1, 0)]
		var b: Vector2 = path[mini(i + 1, path.size() - 1)]
		var dir := (b - a).normalized()
		lane.append(path[i] + Vector2(-dir.y, dir.x) * 1.8)
	var cum: Array = [0.0]
	for i in range(1, lane.size()):
		cum.append(float(cum[i - 1]) + lane[i - 1].distance_to(lane[i]))
	var cars: Array = []
	var paints := [Color("f6f6f2"), Color("2b2d33"), Color("b23a34"), Color("9a9da3"), Color("2f4f8a")]
	for i in 5:
		var holder := Node3D.new()
		var car: Node3D = m.world.traffic_car(0, paints[i])
		holder.add_child(car)
		_decorate(holder, i == 0)
		m.add_child(holder)
		cars.append(holder)
	var hp := AudioStreamPlayer3D.new()
	hp.stream = _horn
	hp.unit_size = 18.0
	hp.max_distance = 220.0
	hp.volume_db = 2.0
	cars[0].add_child(hp)
	var hp2 := AudioStreamPlayer3D.new()
	hp2.stream = _horn
	hp2.unit_size = 14.0
	hp2.max_distance = 200.0
	hp2.pitch_scale = 0.85
	cars[2].add_child(hp2)
	_convoy = {"lane": lane, "cum": cum, "s": 0.0, "cars": cars, "horn": hp, "horn2": hp2, "ht": 0.5, "told": false}
	print("DUGUN konvoyu basladi, rota %.0f m" % float(cum[cum.size() - 1]))
	return true


func _decorate(h: Node3D, bride: bool) -> void:
	var pink := Kit.mat("f27aa8", 0.6)
	var white := Kit.mat("fbf7f2", 0.5)
	var red := Kit.mat("d6283a", 0.5)
	# Kaput uzerinde capraz kurdeleler ve ortada fiyonk; anten bayraklari
	Kit.box(h, Vector3(0.06, 0.02, 1.6), Vector3(-0.35, 1.02, -1.3), pink, Vector3(0, 0.35, 0))
	Kit.box(h, Vector3(0.06, 0.02, 1.6), Vector3(0.35, 1.02, -1.3), pink, Vector3(0, -0.35, 0))
	Kit.ball(h, 0.16, Vector3(0, 1.08, -1.3), white if bride else red, Vector3(1.6, 0.6, 0.9), 8)
	Kit.ball(h, 0.07, Vector3(0, 1.1, -1.3), pink, Vector3.ONE, 6)
	if bride:
		for k in 5:
			Kit.ball(h, 0.07, Vector3(-0.3 + k * 0.15, 1.12, -1.65), [red, white, pink][k % 3], Vector3.ONE, 6)
		var l: Label3D = m.world._text(h, "GELİN ARABASI", Vector3(0, 0.75, 2.33), Color("d6283a"), 0.16)
		l.rotation.y = 0.0
	Kit.cyl(h, 0.008, 0.008, 0.6, Vector3(0.7, 1.75, 0.6), Kit.mat("2b2d31", 0.4), 4)
	Kit.box(h, Vector3(0.02, 0.22, 0.34), Vector3(0.7, 1.95, 0.78), red)
	Kit.box(h, Vector3(0.015, 0.05, 0.6), Vector3(-0.6, 1.55, 0.9), white, Vector3(0.3, 0, 0))


func _at(s: float) -> Vector2:
	var lane: PackedVector2Array = _convoy["lane"]
	var cum: Array = _convoy["cum"]
	if s <= 0.0:
		return lane[0] + (lane[0] - lane[1]).normalized() * -s
	for i in range(1, lane.size()):
		if float(cum[i]) >= s:
			var t := (s - float(cum[i - 1])) / maxf(float(cum[i]) - float(cum[i - 1]), 0.01)
			return lane[i - 1].lerp(lane[i], t)
	return lane[lane.size() - 1]


func _update_convoy(dt: float, o: Vector2) -> void:
	if _convoy.is_empty():
		_convoy_t -= dt
		if _convoy_t <= 0.0:
			_convoy_t = randf_range(300.0, 600.0)
			if ParkMap.home == null and m.clock > 10.0 and m.clock < 21.0 and randf() < 0.6:
				start_convoy()
		return
	var total: float = _convoy["cum"][(_convoy["cum"] as Array).size() - 1]
	_convoy["s"] = float(_convoy["s"]) + dt * 7.5
	var s: float = _convoy["s"]
	var cars: Array = _convoy["cars"]
	for i in cars.size():
		var si: float = s - i * 9.5
		var h: Node3D = cars[i]
		var p := _at(clampf(si, -60.0, total))
		var ahead := _at(clampf(si + 2.5, -60.0, total + 3.0))
		var face := (ahead - p)
		if face.length() < 0.01:
			face = Vector2(0, -1)
		face = face.normalized()
		var y := ParkMap.terrain_height(p)
		h.position = Vector3(p.x, y, p.y)
		h.rotation.y = lerp_angle(h.rotation.y, atan2(-face.x, -face.y), minf(1.0, dt * 5.0)) if si > 0.5 else atan2(-face.x, -face.y)
		h.visible = si > -40.0 and si < total + 5.0
		if h.get_child_count() > 0:
			m.world.spin_wheels(h.get_child(0), dt * 7.5)
	var near: float = o.distance_to(_at(s))
	if near < 60.0 and not _convoy["told"]:
		_convoy["told"] = true
		m.ui.toast("Düğün konvoyu geçiyor! Kornalar çalıyor, gelin arabası süslenmiş.")
	_convoy["ht"] = float(_convoy["ht"]) - dt
	if float(_convoy["ht"]) <= 0.0 and state.d.get("sound", true):
		_convoy["ht"] = randf_range(2.2, 4.0)
		if near < 200.0:
			var hp: AudioStreamPlayer3D = _convoy["horn2"] if randf() < 0.4 else _convoy["horn"]
			hp.play()
	if s - (cars.size() - 1) * 9.5 > total + 5.0:
		for c in cars:
			c.queue_free()
		_convoy = {}


# ---------------------------------------------------------------- telefon ve test

func phone_app() -> void:
	if shops.is_empty():
		m.ui.toast("Bu bölgede mahalle esnafı yok.")
		return
	var o: Vector2 = m._owner_pos()
	var body: VBoxContainer = m.ui._open_panel("MAHALLE ESNAFI", "Fırın, kasap, manav, berber, kahvehane · dokun, yol tarifi al")
	var list := shops.duplicate()
	list.sort_custom(func(a, b): return o.distance_to(a["pos"]) < o.distance_to(b["pos"]))
	for s in list:
		var sp: Dictionary = s
		m.ui._panel_item(body, "%s · %d m" % [sp["name"], int(o.distance_to(sp["pos"]))], func():
			m.ui.close_modal()
			m._set_nav(sp["pos"], sp["name"]))
	if is_friday():
		m.ui._fx_label(body, "Bugün cuma: öğle vakti camiler kalabalık.", m.ui.F_BODY, 20, m.ui.ACCENT)
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func debug(what: String, arg: String) -> void:
	match what:
		"shop":
			var s := shop_of(arg)
			if s.is_empty():
				print("ESNAF yok: ", arg)
				return
			var tw: Vector2 = s["tw"]
			var side := Vector2(-tw.y, tw.x)
			m._place_owner(s["pos"] + tw * 4.5 + side * 1.5)
			_face(s["c"])
		"panel":
			var i := shops.find(shop_of(arg))
			if i >= 0:
				m._place_owner(shops[i]["pos"])
				open_shop(i)
		"berber" when arg.begins_with("ic"):
			# --berber=ic[:model:renk:sakal] (or. ic:1:17120f:4)
			var pp := arg.split(":")
			var s3 := shop_of("berber")
			if s3.is_empty() or not s3.has("spot"):
				print("BERBER yok")
				return
			state.d["coins"] = maxi(int(state.d["coins"]), 200)
			m._place_owner(s3["pos"])
			m._enter_shop(s3["spot"])
			if pp.size() > 1 and pp[1] == "dizi":
				m._shop.debug_lineup()
				return
			m._shop.debug_cut(int(pp[1]) if pp.size() > 1 else 1, pp[2] if pp.size() > 2 else "-", int(pp[3]) if pp.size() > 3 else 4)
		"gym":
			var s4 := shop_of("spor")
			if s4.is_empty() or not s4.has("spot"):
				print("SPOR yok")
				return
			state.d["coins"] = maxi(int(state.d["coins"]), 300)
			if arg == "dis":
				var tw4: Vector2 = s4["tw"]
				m._place_owner(s4["pos"] + tw4 * 6.0 + Vector2(-tw4.y, tw4.x) * 2.0)
				_face(s4["c"])
				print("SPOR disarida @ ", (s4["pos"] as Vector2).round())
				return
			m._place_owner(s4["pos"])
			m._enter_shop(s4["spot"])
			m._shop.debug(arg)
		"berber":
			state.d["coins"] = maxi(int(state.d["coins"]), 100)
			var hr: Array = [int(arg) if arg.is_valid_int() else 1, "3f6fd0" if arg == "mavi" else "17120f"]
			state.d["hair"] = hr
			apply_hair()
			debug("shop", "berber")
		"kahvehane":
			if seats.is_empty():
				print("KAHVEHANE yok")
				return
			var s2 := shop_of("kahvehane")
			m._place_owner(_w2(s2["root"], seats[0]["local"] + Vector2(0, 0.8)))
			sit(0)
			if arg == "okey":
				start_okey()
				okey_draw(false)
			else:
				start_tavla()
				tavla_roll()
				tavla_roll()
		"dugun":
			start_convoy(true)
			if not _convoy.is_empty():
				_convoy["s"] = maxf(0.0, _nearest_s(m._owner_pos()) - 40.0)
		"cuma":
			state.d["gun"] = 5
			m.clock = 12.4
			if not _mosques.is_empty():
				var best: Dictionary = _mosques[0]
				for q in _mosques:
					if (q["gather"] as Vector2).distance_to(m._owner_pos()) < (best["gather"] as Vector2).distance_to(m._owner_pos()):
						best = q
				m._place_owner(best["gather"] + (best["dir"] as Vector2) * 12.0)
				_face(best["c"])
				_crowd_t = 0.0


func _nearest_s(o: Vector2) -> float:
	var lane: PackedVector2Array = _convoy["lane"]
	var cum: Array = _convoy["cum"]
	var bs := 0.0
	var bd := 1e9
	for i in lane.size():
		var d := lane[i].distance_to(o)
		if d < bd:
			bd = d
			bs = float(cum[i])
	return bs
