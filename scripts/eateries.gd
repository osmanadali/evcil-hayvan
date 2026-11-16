extends Node
## Lokantalar ve ek marketler (uydurma markalar).
## - Uc lokanta: parkin yaninda ocakbasi kebap & pide, evin yakininda ev yemekleri, ana caddede burger & doner.
##   Bos arsalarda, vitrini yola bakan binalar kurulur (tabela, cam vitrin, tente, kaldirimda menu panosu).
##   Ici yurunebilir (scripts/restaurant_interior.gd, y = 300): bos bir sandalyede F ile otur, garson gelir,
##   sag panelden yemek / icecek sec, birkac saniye sonra tepsiyle getirir; yemek yenir (tokluk + biraz enerji),
##   sonunda hesap odenir. Fast food'da siparis kasada verilir ve once odenir. Kasada paket siparis cantaya gider.
##   Hayvanlar masanin yaninda oturur; onlara su kabi / odul istenebilir.
## - Uc ek market: evin yakininda, metro girisinin yaninda ve parkin yaninda (market ic mekani, farkli marka rengi).
## - Telefon "Yakınımda": en yakin market, lokanta, eczane, ATM ve benzinlik; dokununca yol tarifi.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PersonModel = preload("res://scripts/person_model.gd")

# [tur/stil, ad, alt yazi, renk, duvar rengi, hedef]
const PLACES := [
	["kebap", "Ocakbaşı Usta Kebap & Pide", "KEBAP · PİDE · LAHMACUN", "b8401a", "d9c3a0", "park"],
	["ev", "Anneler Sofrası", "EV YEMEKLERİ · ÇORBA · TATLI", "3f7a4a", "e8dcc0", "home"],
	["fast", "Paşa Burger & Döner", "BURGER · DÖNER · PATATES", "d9302b", "f2efe8", "road"],
	["market", "Komşu Market", "", "2f62a8", "e6e1d6", "home"],
	["market", "Durak Market", "", "e07b1f", "dcd6cb", "metro"],
	["market", "Yeşil Yaprak Market", "", "3f8f4a", "e9e4da", "park"],
]
# kimlik, ad, fiyat, tokluk, enerji
const MENUS := {
	"kebap": [["adana", "Adana Kebap", 38, 55, 0], ["iskender", "İskender", 42, 60, 0], ["lahmacun", "Lahmacun", 15, 30, 0],
		["pide", "Kıymalı Pide", 28, 50, 0], ["kunefe", "Künefe", 20, 15, 6], ["ayran", "Ayran", 6, 8, 3]],
	"ev": [["mercimek", "Mercimek Çorbası", 12, 20, 4], ["fasulye", "Kuru Fasulye Pilav", 26, 55, 0],
		["karniyarik", "Karnıyarık", 30, 50, 0], ["tavuk", "Tavuk Sote", 28, 45, 0], ["sutlac", "Fırın Sütlaç", 14, 12, 5],
		["cay", "Çay", 3, 2, 12]],
	"fast": [["burger", "Paşa Burger", 32, 50, 0], ["doner", "Tavuk Döner Dürüm", 24, 45, 0],
		["menu", "Döner Menü + Patates + Ayran", 36, 65, 3], ["patates", "Patates Kızartması", 12, 20, 0],
		["gazoz", "Gazoz", 7, 3, 8], ["ayran", "Ayran", 6, 8, 3]],
}
# Paket: kimlik -> cantadaki ad (player_needs.ITEM_GAIN'de tokluk degeri var)
const TAKEAWAY := {"lahmacun": "Paket Lahmacun", "pide": "Paket Pide", "adana": "Paket Dürüm", "fasulye": "Paket Yemek",
	"karniyarik": "Paket Yemek", "tavuk": "Paket Yemek", "burger": "Paket Burger", "doner": "Paket Dürüm",
	"menu": "Paket Dürüm", "ayran": "Ayran", "cay": "Çay"}
const WAITER_SPEED := 1.5
const COOK_TIME := 4.5
const BITE_EVERY := 2.6

var m: Node                     # main
var state: Node
var places: Array = []          # dunyadaki yerler: {name, kind, style, pos, accent}
var seat: Dictionary = {}       # {ti, si, t}
var order: Array = []           # siparis edilen urunler (menu satirlari)
var bill := 0                   # odenmemis hesap (masada)
var phase := ""                 # "" | come | order | cook | ready | bring | eat | done
var _cook_t := 0.0
var _walk: Array = []           # garsonun yerel yolu
var _walk_then := ""
var _tray: Node3D
var _bites := 0
var _bite_n := 0
var _bite_t := 0.0
var _bowls: Array = []
var _meal_gain := Vector2.ZERO  # toplam (tokluk, enerji)


func shop() -> Node3D:
	if m._shop != null and ParkMap.home == m._shop and m._shop.kind == "lokanta":
		return m._shop
	return null


func is_seated() -> bool:
	return not seat.is_empty()


func menu_of(style: String) -> Array:
	return MENUS.get(style, MENUS["ev"])


# ---------------------------------------------------------------- kurulum (dunya)

func build() -> void:
	var w: Node = m.world
	var targets := {}
	if ParkMap.zone == "":
		targets["home"] = m.HOME_DOOR + m.HOME_DOOR_OUT * 10.0
	if ParkMap.has_spot("baslangic"):
		targets["park"] = ParkMap.spot("baslangic") + Vector2(-30.0, 25.0)
	if not w.metro_gates.is_empty():
		targets["metro"] = w.metro_gates[0]["pos"]
	# Ana cadde: eve (yoksa merkeze) en yakin birincil yol
	var ref: Vector2 = targets.get("home", Vector2.ZERO)
	var best := Vector2.INF
	for r in ParkMap.data["roads"]:
		if not String(r.get("k", "")).begins_with("primary"):
			continue
		var ids: Array = r["n"]
		for i in ids.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(ref + Vector2(60, 60), ParkMap.nodes[int(ids[i])], ParkMap.nodes[int(ids[i + 1])])
			if q.distance_to(ref) > 40.0 and q.distance_to(ref) < ref.distance_to(best):
				best = q
	if best != Vector2.INF:
		targets["road"] = best
	var taken: Array = []
	for k in w.shop_spots:
		taken.append(k["pos"])
	for pl in PLACES:
		var t: Vector2 = targets.get(pl[5], targets.get("park", targets.get("road", Vector2.INF)))
		if t == Vector2.INF:
			continue
		var lot := _find_lot(t, taken)
		if lot.is_empty():
			print("LOKANTA yer bulunamadi: ", pl[1])
			continue
		var door := _building(lot[0], lot[1], pl)
		taken.append(lot[0])
		var kind: String = "market" if pl[0] == "market" else "lokanta"
		var sp := {"name": pl[1], "kind": kind, "style": pl[0], "pos": door, "accent": pl[3], "dir": lot[1], "center": lot[0], "tw": lot[1]}
		w.shop_spots.append(sp)
		places.append(sp)
		print("LOKANTA ", pl[1], " @ ", door.round())


func _find_lot(target: Vector2, taken: Array) -> Array:
	var w: Node = m.world
	for ring in [0.0, 12.0, 24.0, 36.0, 50.0, 65.0, 80.0, 100.0, 125.0]:
		var n := 1 if ring == 0.0 else 10
		for k in n:
			var s: Vector2 = target + Vector2.from_angle(k * TAU / n + ring * 0.1) * ring
			if not ParkMap.inside_bounds(s, 20.0):
				continue
			var rp: Vector2 = w._road_point(s)
			var tw := rp - s
			if tw.length() < 1.0 or tw.length() > 40.0:
				continue
			tw = tw.normalized()
			for back in [10.0, 11.5, 13.0, 14.5]:
				var c: Vector2 = rp - tw * float(back)
				if _lot_ok(c, tw, taken):
					return [c, tw]
	return []


func _lot_ok(c: Vector2, tw: Vector2, taken: Array) -> bool:
	var w: Node = m.world
	if not ParkMap.inside_bounds(c, 12.0):
		return false
	for t in taken:
		if c.distance_to(t) < 20.0:
			return false
	if ParkMap.zone == "" and c.distance_to(m.HOME_DOOR) < 14.0:
		return false
	if not w._clear_lot(c, 5.0):
		return false
	var side := Vector2(-tw.y, tw.x)
	for dx in [-1.0, 0.0, 1.0]:
		for dz in [-1.0, 0.0, 1.0]:
			if w._mask(c + side * dx * 5.0 + tw * dz * 4.5)[2] > 0.4:
				return false
	var door := c + tw * 4.8
	if w._mask(door)[2] > 0.45 or not w.is_free(door, 0.5):
		return false
	# Zemin cok egimli olmasin
	if absf(ParkMap.terrain_height(c + tw * 4.0) - ParkMap.terrain_height(c - tw * 4.0)) > 2.5:
		return false
	return true


## Bina: govde, yola bakan girintili vitrin, tabela, tente. Kapinin onundeki noktayi dondurur.
func _building(c: Vector2, tw: Vector2, pl: Array) -> Vector2:
	var w: Node = m.world
	var rot := atan2(tw.x, tw.y)
	var r: Node3D = w._root(c, rot)
	const HX := 4.5
	const HZ := 3.8
	var accent: String = pl[3]
	var body := Kit.mat(pl[4], 0.85)
	var dark := Kit.mat("2b2d31", 0.4)
	# Govde (on yuzu 0.7 m geride: vitrin girintisi)
	Kit.box(r, Vector3(HX * 2.0, 6.4, HZ * 2.0 - 0.7), Vector3(0, 1.8, -0.35), body)
	Kit.box(r, Vector3(HX * 2.0 + 0.3, 0.3, HZ * 2.0 + 0.3), Vector3(0, 5.1, 0), Kit.mat("5b5f66", 0.7))
	Kit.box(r, Vector3(0.4, 6.4, 0.75), Vector3(-HX + 0.2, 1.8, HZ - 0.37), body)
	Kit.box(r, Vector3(0.4, 6.4, 0.75), Vector3(HX - 0.2, 1.8, HZ - 0.37), body)
	Kit.box(r, Vector3(HX * 2.0, 2.2, 0.75), Vector3(0, 3.9, HZ - 0.37), body)
	# Ust kat pencereleri
	var win := Kit.mat("3d4a55", 0.15)
	var sill := Kit.mat("d9d4c8", 0.6)
	for x in [-2.6, 0.0, 2.6]:
		Kit.box(r, Vector3(1.3, 1.1, 0.06), Vector3(x, 4.15, HZ + 0.02), win)
		Kit.box(r, Vector3(1.45, 0.08, 0.15), Vector3(x, 3.55, HZ + 0.06), sill)
	_back_and_sides(r, HX, HZ, body, win, sill, accent, pl)
	# Tabela (fasya): marka renginde, isikli yazi
	Kit.box(r, Vector3(HX * 2.0 - 0.6, 0.85, 0.14), Vector3(0, 3.05, HZ + 0.08), Kit.mat(accent, 0.45))
	var name_l: Label3D = w._text(r, pl[1], Vector3(0, 3.12 if pl[2] != "" else 3.05, HZ + 0.16), Color.WHITE, 0.34)
	name_l.font = load("res://assets/fonts/Bangers-Regular.ttf")
	name_l.visibility_range_end = 110.0
	if pl[2] != "":
		var sub: Label3D = w._text(r, pl[2], Vector3(0, 2.8, HZ + 0.16), Color("fff3d6"), 0.15)
		sub.visibility_range_end = 60.0
	# Carpisma: govdenin dort kenari (arac ve yaya binanin icine giremez; vitrin girintisi acik)
	var bs := Basis(Vector3.UP, rot)
	var fz := HZ - 0.72
	for e in [[-HX, -HZ, HX, -HZ], [HX, -HZ, HX, fz], [HX, fz, -HX, fz], [-HX, fz, -HX, -HZ]]:
		var va := bs * Vector3(e[0], 0, e[1])
		var vb := bs * Vector3(e[2], 0, e[3])
		w._add_segment(c + Vector2(va.x, va.z), c + Vector2(vb.x, vb.z))
	if pl[0] == "market":
		w._shopfront(c + tw * (HZ - 0.12), tw, accent, "market")
		return c + tw * (HZ + 1.0)
	# Lokanta vitrini: loş sicak ic (arka duvar, lambri, raf), masa siluetleri, cam, cerceve, kapi.
	# Arka duvar eskiden acik krem + guclu isimaydi: disaridan cam bembeyaz parliyordu.
	var warm := StandardMaterial3D.new()
	warm.albedo_color = Color("8a6448")
	warm.emission_enabled = true
	warm.emission = Color("7a4e2c")
	warm.emission_energy_multiplier = 0.35
	Kit.box(r, Vector3(HX * 2.0 - 0.8, 2.4, 0.04), Vector3(0, 1.25, HZ - 0.66), warm)
	var wood := Kit.mat("6b3d22", 0.6)
	Kit.box(r, Vector3(HX * 2.0 - 0.8, 0.9, 0.05), Vector3(0, 0.45, HZ - 0.63), Kit.mat("4a2a18", 0.7))
	Kit.box(r, Vector3(HX * 2.0 - 0.8, 0.04, 0.6), Vector3(0, 0.03, HZ - 0.35), Kit.mat("5a3a24", 0.8))
	for x in [-3.0, -1.8, 1.8, 3.0]:
		Kit.box(r, Vector3(0.7, 0.5, 0.03), Vector3(x, 1.75, HZ - 0.62), Kit.mat("3a2414", 0.6))
		Kit.box(r, Vector3(0.6, 0.4, 0.035), Vector3(x, 1.75, HZ - 0.615), Kit.mat(["c9962e", "b8401a", "3f6f78", "8a9a3a"][int(x + 3.0) % 4], 0.8))
	for x in [-2.8, -1.6, 1.6, 2.8]:
		Kit.box(r, Vector3(0.7, 0.05, 0.5), Vector3(x, 0.75, HZ - 0.4), wood)
		Kit.box(r, Vector3(0.06, 0.72, 0.06), Vector3(x, 0.37, HZ - 0.4), wood)
		Kit.cyl(r, 0.1, 0.1, 0.03, Vector3(x + 0.15, 0.79, HZ - 0.4), Kit.mat("f4f4f0", 0.3), 10)
	for x in [-2.2, 2.2]:
		Kit.ball(r, 0.14, Vector3(x, 2.25, HZ - 0.4), Kit.glow("ffd08a", 2.0), Vector3.ONE, 8)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.45, 0.55, 0.6, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.12
	glass.metallic_specular = 0.4
	Kit.box(r, Vector3(HX * 2.0 - 0.8, 2.5, 0.03), Vector3(0, 1.3, HZ - 0.05), glass)
	for x in [-HX + 0.4, -0.7, 0.7, HX - 0.4]:
		Kit.box(r, Vector3(0.09, 2.6, 0.1), Vector3(x, 1.3, HZ - 0.05), dark)
	Kit.box(r, Vector3(HX * 2.0 - 0.7, 0.1, 0.12), Vector3(0, 2.58, HZ - 0.05), dark)
	Kit.box(r, Vector3(HX * 2.0 - 0.7, 0.3, 0.14), Vector3(0, 0.15, HZ - 0.05), dark)
	Kit.box(r, Vector3(0.03, 0.45, 0.03), Vector3(0.5, 1.1, HZ + 0.02), Kit.mat("c9ccd0", 0.3))
	# Kapi ustunde "ACIK" levhasi
	Kit.box(r, Vector3(0.6, 0.2, 0.03), Vector3(0, 2.3, HZ - 0.02), Kit.glow("ff3a3a", 1.6))
	w._text(r, "AÇIK", Vector3(0, 2.3, HZ + 0.0), Color.WHITE, 0.12)
	# Tente: cizgili
	var aw := Node3D.new()
	aw.position = Vector3(0, 2.72, HZ + 0.5)
	aw.rotation.x = 0.32
	r.add_child(aw)
	for k in 9:
		Kit.box(aw, Vector3((HX * 2.0 + 0.2) / 9.0, 0.05, 1.1), Vector3(-HX - 0.1 + (k + 0.5) * (HX * 2.0 + 0.2) / 9.0, 0, 0),
			Kit.mat(accent if k % 2 == 0 else "f4f1ea", 0.7))
	# Kaldirimda menu panosu (A tipi)
	var ab := Node3D.new()
	ab.position = Vector3(HX - 0.9, 0, HZ + 1.1)
	r.add_child(ab)
	Kit.box(ab, Vector3(0.6, 0.9, 0.04), Vector3(0, 0.5, 0.12), Kit.mat("1e1e22", 0.5), Vector3(-0.2, 0, 0))
	Kit.box(ab, Vector3(0.6, 0.9, 0.04), Vector3(0, 0.5, -0.12), Kit.mat("1e1e22", 0.5), Vector3(0.2, 0, 0))
	var txt := "MENÜ\n"
	var mm: Array = menu_of(pl[0])
	for i in 4:
		txt += "%s %d₺\n" % [mm[i][1], int(mm[i][2])]
	var ml: Label3D = w._text(ab, txt.strip_edges(), Vector3(0, 0.55, 0.16), Color("fff3d6"), 0.05)
	ml.rotation.x = -0.2
	# Lokanta onunde sicak isik (gece)
	var o := OmniLight3D.new()
	o.position = Vector3(0, 2.4, HZ + 1.2)
	o.light_color = Color("ffcf8a")
	o.omni_range = 7.0
	o.light_energy = 0.8
	o.distance_fade_enabled = true
	o.distance_fade_begin = 70.0
	o.distance_fade_length = 20.0
	r.add_child(o)
	return c + tw * (HZ + 1.0)


## Arka ve yan cepheler: eskiden duz, dokusuz kutuydu (parktan / yoldan bakinca ne oldugu anlasilmiyordu).
## Kat silmesi, subasman, ust kat pencereleri, yanda marka levhasi, arkada servis kapisi, catida klima / depo.
func _back_and_sides(r: Node3D, hx: float, hz: float, body: Material, win: Material, sill: Material, accent: String, pl: Array) -> void:
	var w: Node = m.world
	var band := Kit.mat("8f8577", 0.8)
	var base := Kit.mat("6f6a62", 0.9)
	var zb := -hz                     # arka yuz
	var depth := hz * 2.0 - 0.7       # govde derinligi
	var zc := -0.35                   # govde merkezi (z)
	# Kat silmesi ve subasman (dort yanda)
	Kit.box(r, Vector3(hx * 2.0 + 0.12, 0.16, 0.12), Vector3(0, 3.45, zb - 0.04), band)
	Kit.box(r, Vector3(hx * 2.0 + 0.1, 0.55, 0.08), Vector3(0, 0.2, zb - 0.03), base)
	for sx in [-1.0, 1.0]:
		Kit.box(r, Vector3(0.12, 0.16, depth + 0.12), Vector3(sx * (hx + 0.04), 3.45, zc), band)
		Kit.box(r, Vector3(0.08, 0.55, depth + 0.1), Vector3(sx * (hx + 0.03), 0.2, zc), base)
	# Arka: ust kat pencereleri, servis kapisi, kucuk mutfak penceresi, havalandirma
	for x in [-2.6, 0.0, 2.6]:
		Kit.box(r, Vector3(1.2, 1.1, 0.06), Vector3(x, 4.15, zb - 0.02), win)
		Kit.box(r, Vector3(1.35, 0.08, 0.15), Vector3(x, 3.55, zb - 0.06), sill)
	Kit.box(r, Vector3(1.0, 2.1, 0.06), Vector3(2.4, 1.05, zb - 0.03), Kit.mat("4a4f55", 0.5))
	Kit.box(r, Vector3(0.05, 0.05, 0.12), Vector3(2.75, 1.05, zb - 0.08), Kit.mat("c9ccd0", 0.3))
	Kit.box(r, Vector3(1.3, 0.12, 0.6), Vector3(2.4, 2.25, zb - 0.3), Kit.mat(accent, 0.6))
	Kit.box(r, Vector3(1.1, 0.7, 0.06), Vector3(-2.0, 1.9, zb - 0.02), win)
	Kit.box(r, Vector3(0.6, 0.6, 0.25), Vector3(-0.3, 2.1, zb - 0.12), Kit.mat("b9bcc0", 0.4))
	for k in 4:
		Kit.box(r, Vector3(0.5, 0.04, 0.02), Vector3(-0.3, 1.9 + k * 0.13, zb - 0.25), Kit.mat("6f7378", 0.4))
	# Yanlar: ust katta iki pencere, zemin katta marka levhasi (adi yazili, isikli)
	for sx in [-1.0, 1.0]:
		var xf: float = sx * (hx + 0.02)
		for z in [zc - 1.6, zc + 1.6]:
			Kit.box(r, Vector3(0.06, 1.1, 1.2), Vector3(xf, 4.15, z), win)
			Kit.box(r, Vector3(0.15, 0.08, 1.35), Vector3(sx * (hx + 0.06), 3.55, z), sill)
		Kit.box(r, Vector3(0.08, 0.9, depth - 1.6), Vector3(sx * (hx + 0.05), 2.45, zc), Kit.mat(accent, 0.45))
		var t: Label3D = w._text(r, pl[1], Vector3(sx * (hx + 0.1), 2.45, zc), Color.WHITE, 0.22)
		t.rotation.y = sx * PI * 0.5
		t.visibility_range_end = 90.0
	# Cati: klima dis uniteleri, su deposu, baca
	var roof_y := 5.25
	Kit.box(r, Vector3(0.9, 0.6, 0.45), Vector3(-2.6, roof_y + 0.3, zb + 1.0), Kit.mat("e4e4e0", 0.5))
	Kit.cyl(r, 0.22, 0.22, 0.04, Vector3(-2.6, roof_y + 0.3, zb + 1.23), Kit.mat("55585e", 0.5), 14, Vector3(PI * 0.5, 0, 0))
	Kit.box(r, Vector3(0.9, 0.6, 0.45), Vector3(-1.4, roof_y + 0.3, zb + 1.0), Kit.mat("e4e4e0", 0.5))
	Kit.cyl(r, 0.55, 0.55, 1.1, Vector3(2.4, roof_y + 0.55, zb + 1.6), Kit.mat("d0d3d6", 0.35), 16)
	Kit.cyl(r, 0.18, 0.18, 1.6, Vector3(3.6, roof_y + 0.8, zb + 0.6), Kit.mat("7a7f86", 0.4), 10)
	Kit.cyl(r, 0.26, 0.26, 0.12, Vector3(3.6, roof_y + 1.6, zb + 0.6), Kit.mat("55585e", 0.5), 10)


# ---------------------------------------------------------------- giris / cikis

func on_enter(sp: Dictionary) -> void:
	var s := shop()
	if s == null:
		return
	seat = {}
	phase = ""
	order.clear()
	bill = 0
	# Birkac masada baska musteriler otursun
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sp["name"]) + int(m.clock)
	for k in 3:
		var ti: int = rng.randi() % s.tables.size()
		var si: int = rng.randi() % 2
		var st: Dictionary = s.tables[ti]["seats"][si]
		if st["busy"]:
			continue
		st["busy"] = true
		var v := PersonModel.new()
		v.kind = "kadin" if rng.randf() < 0.5 else "erkek"
		v.tint = Color.from_hsv(rng.randf(), 0.45, 0.7)
		v.pants = Color.from_hsv(rng.randf(), 0.3, 0.3)
		v.seated = true
		var lp: Vector2 = st["local"]
		v.position = Vector3(lp.x, 0.41, lp.y)
		v.rotation.y = float(st["yaw"])
		s.add_child(v)
		var it: Array = menu_of(s.style)[rng.randi() % 4]
		_dish(s.tables[ti]["food"], it[0], _plate_pos(s, ti, si, 0))
	get_tree().create_timer(1.4).timeout.connect(func():
		var s2 := shop()
		if s2:
			m._say(s2.waiter, ["Hoş geldiniz, buyurun!", "Hoş geldiniz, istediğiniz masaya oturun!", "Buyurun, şöyle geçin!"][randi() % 3])
			s2.waiter.act("wave", 1.2))
	m.ui.toast("Boş bir sandalyeye gelip F ile otur%s." % (" · Sipariş kasada verilir" if s.style == "fast" else ", garson gelsin"))


func leave() -> void:
	if is_seated():
		stand_up()
	var s := shop()
	if s and s.style == "fast" and (phase == "cook" or phase == "ready") and not order.is_empty():
		# Odenmis siparis: paket yapilip cantaya konur
		var bag: Dictionary = state.d.get("bag", {})
		for it in order:
			var nm: String = TAKEAWAY.get(it[0], it[1])
			bag[nm] = int(bag.get(nm, 0)) + 1
		state.d["bag"] = bag
		m.ui.toast("Siparişini paket yaptılar, çantana kondu.")
	phase = ""
	order.clear()
	bill = 0
	_walk.clear()
	m._exit_shop()


# ---------------------------------------------------------------- baglam ve komutlar

func context() -> Array:
	var s := shop()
	if s == null:
		return []
	if is_seated():
		match phase:
			"come":
				return ["Garson geliyor…", "", "sit"]
			"order":
				return ["Menüye Bak · Sipariş Ver", "eat_menu", "list"]
			"cook", "bring":
				return ["Yemeğin hazırlanıyor…" if phase == "cook" else "Garson yemeği getiriyor…", "eat_pet" if not m.agents.is_empty() else "", "sit"]
			"eat":
				return ["Afiyet olsun! · Hayvanına bir şey iste", "eat_pet", "paw"]
			"done":
				if bill > 0:
					return ["Hesabı Öde · %d ₺" % bill, "eat_pay", "coin"]
				return ["Bir Şey Daha İste · Kalkmak için yürü", "eat_menu" if s.style != "fast" else "", "sit"]
			"ready":
				return ["Siparişin geliyor…", "", "sit"]
		if s.style == "fast":
			return ["Sipariş kasada verilir · Kalkmak için yürü", "", "sit"]
		return ["Garsonu Çağır", "eat_call", "hand"]
	var lo: Vector2 = s.local2(m._owner_pos())
	if lo.distance_to(s.entrance_local) < 1.1:
		return ["Dışarı Çık", "eat_out", "come"]
	if lo.distance_to(s.counter_local) < 1.3:
		if s.style == "fast":
			if phase == "cook" or phase == "ready":
				return ["Siparişin hazırlanıyor · Bir masaya otur", "", "sit"]
			return ["Kasa · Sipariş Ver", "eat_counter", "cart"]
		return ["Kasa · Paket Sipariş", "eat_counter", "bag"]
	var best := []
	var bd := 0.8
	for ti in s.tables.size():
		for si in 2:
			var st: Dictionary = s.tables[ti]["seats"][si]
			var d: float = lo.distance_to(st["local"])
			if not st["busy"] and d < bd:
				bd = d
				best = [ti, si]
	if not best.is_empty():
		return ["Masaya Otur", "eat_sit:%d:%d" % [best[0], best[1]], "sit"]
	return ["", "", ""]


func command(cmd: String) -> void:
	if cmd.begins_with("eat_sit:"):
		var p := cmd.split(":")
		sit(int(p[1]), int(p[2]))
	elif cmd == "eat_menu":
		if phase == "done" or phase == "":
			_call_waiter()
		else:
			open_menu()
	elif cmd == "eat_call":
		_call_waiter()
	elif cmd == "eat_counter":
		open_menu()
	elif cmd == "eat_pay":
		pay()
	elif cmd == "eat_pet":
		_pet_menu()
	elif cmd == "eat_out":
		leave()
	elif cmd == "eat_near":
		nearby_app()


# ---------------------------------------------------------------- oturma

func sit(ti: int, si: int) -> void:
	var s := shop()
	if s == null or is_seated():
		return
	var st: Dictionary = s.tables[ti]["seats"][si]
	if st["busy"]:
		return
	st["busy"] = true
	seat = {"ti": ti, "si": si, "t": 0.0}
	m._moving = false
	m._queue.clear()
	m._steering = false
	m.owner_model.speed = 0.0
	m.owner_model.seated = true
	_place_seated()
	# Hayvanlar masanin yaninda oturur
	var tc: Vector2 = s.tables[ti]["c"]
	var k := 0
	for kind in m.agents:
		var a: Node3D = m.agents[kind]
		a.command("sit")
		var lp: Vector2 = tc + Vector2(-0.95, (-0.35 if si == 0 else 0.35) + 0.0 * k) + Vector2(0, 0.55 * k * (1 if si == 0 else -1))
		a.place(s.w2(lp))
		a.rotation.y = PI * 0.5
		k += 1
	m.ui._actions.visible = false
	if s.style == "fast":
		if phase == "ready":
			_bring()
		elif phase == "cook":
			m.ui.toast("Oturdun. Siparişin hazırlanınca masana getirecekler.")
		else:
			m.ui.toast("Oturdun. Fast food'da sipariş kasadan verilir.")
	elif phase == "":
		_call_waiter()
	m._update_context()


func _place_seated() -> void:
	var s := shop()
	if s == null:
		return
	var st: Dictionary = s.tables[seat["ti"]]["seats"][seat["si"]]
	var wp: Vector2 = s.w2(st["local"])
	m.owner_node.position = Vector3(wp.x, s.global_position.y + 0.46, wp.y)
	m.owner_node.rotation = Vector3(0, float(st["yaw"]), 0)
	m.owner_model.position = Vector3(0, -0.05, 0)
	m._target = wp


func stand_up() -> void:
	var s := shop()
	if not is_seated():
		return
	if s:
		var st: Dictionary = s.tables[seat["ti"]]["seats"][seat["si"]]
		st["busy"] = false
		if bill > 0 and (phase == "eat" or phase == "done"):
			pay()
		elif bill > 0:
			m.ui.toast("Siparişini iptal ettin.")
			bill = 0
			order.clear()
			phase = ""
			_walk_home()
		var food: Node3D = s.tables[seat["ti"]]["food"]
		if phase == "eat" or phase == "done":
			for ch in food.get_children():
				ch.queue_free()
			phase = ""
			order.clear()
		var tc: Vector2 = s.tables[seat["ti"]]["c"]
		var lp: Vector2 = st["local"]
		var out: Vector2 = s.w2(lp + (lp - tc).normalized() * 0.5 + Vector2(-0.5, 0))
		m.owner_node.position = Vector3(out.x, s.global_position.y, out.y)
		m._target = out
	for b in _bowls:
		if is_instance_valid(b):
			b.queue_free()
	_bowls.clear()
	seat = {}
	m.owner_model.seated = false
	m.owner_model.position = Vector3.ZERO
	for kind in m.agents:
		m.agents[kind].command("come")
	m.ui._actions.visible = true
	m._update_context()


# ---------------------------------------------------------------- siparis

func _call_waiter() -> void:
	var s := shop()
	if s == null or not is_seated() or s.style == "fast":
		return
	if phase != "" and phase != "done":
		return
	if phase == "done":
		order.clear()
	phase = "come"
	var tl: Vector2 = _table_side(s)
	_walk = [Vector2(tl.x, s.waiter_home.y), tl]
	_walk_then = "take"
	m._update_context()


func _table_side(s: Node3D) -> Vector2:
	var tc: Vector2 = s.tables[seat["ti"]]["c"]
	return Vector2(tc.x + 1.05, tc.y)


func _walk_home() -> void:
	var s := shop()
	if s == null:
		return
	var wp: Vector2 = Vector2(s.waiter.position.x, s.waiter.position.z)
	_walk = [Vector2(wp.x, s.waiter_home.y), s.waiter_home]
	_walk_then = "home"


func open_menu() -> void:
	var s := shop()
	if s == null:
		return
	var fast: bool = s.style == "fast"
	var at_table := is_seated() and not fast
	var total := 0
	for it in order:
		total += int(it[2])
	var sub := "Cüzdan %d ₺" % int(state.d["coins"])
	if at_table and not order.is_empty():
		sub = "Siparişin: %d ürün · %d ₺ · Cüzdan %d ₺" % [order.size(), total, int(state.d["coins"])]
	elif fast and not order.is_empty():
		sub = "Sepet: %d ürün · %d ₺ · Cüzdan %d ₺" % [order.size(), total, int(state.d["coins"])]
	var body: VBoxContainer = m.ui._open_panel(s.title.to_upper(), sub)
	if at_table or fast:
		for row in menu_of(s.style):
			var it: Array = row
			var n := 0
			for o in order:
				if o[0] == it[0]:
					n += 1
			m.ui._panel_item(body, "%s  ·  %d ₺%s" % [String(it[1]).to_upper(), int(it[2]), ("   ×%d" % n) if n > 0 else ""], func():
				if total + int(it[2]) > int(state.d["coins"]):
					m.ui.toast("Cüzdanın bu siparişe yetmiyor.")
					return
				order.append(it)
				m._sfx("tik", -6.0, 1.1)
				open_menu())
		if not order.is_empty():
			if fast:
				m.ui._panel_item(body, "ÖDE · BURADA YE · %d ₺" % total, func(): _fast_pay(false))
				m.ui._panel_item(body, "ÖDE · PAKET AL · %d ₺" % total, func(): _fast_pay(true))
			else:
				m.ui._panel_item(body, "SİPARİŞİ VER · %d ₺" % total, func(): _place_order())
			m.ui._panel_item(body, "SON ÜRÜNÜ ÇIKAR", func():
				order.pop_back()
				open_menu())
	else:
		# Kasada paket siparis (oturmadan)
		for row in menu_of(s.style):
			var it: Array = row
			if not TAKEAWAY.has(it[0]):
				continue
			var nm: String = TAKEAWAY[it[0]]
			m.ui._panel_item(body, "PAKET: %s  ·  %d ₺" % [String(it[1]).to_upper(), int(it[2])], func():
				if not state.spend(int(it[2])):
					m.ui.toast("Paran yetmiyor.")
					return
				_to_bag(nm)
				m._sfx("kasa", -6.0)
				m._say(s.cashier, "Buyurun, afiyet olsun!")
				open_menu())
	m.ui._panel_item(body, "KAPAT", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _to_bag(nm: String) -> void:
	var bag: Dictionary = state.d.get("bag", {})
	bag[nm] = int(bag.get(nm, 0)) + 1
	state.d["bag"] = bag
	state.count("shop")
	state.changed.emit()
	state.save_game()
	m.ui.toast("%s çantana kondu · Çanta: %d" % [nm, int(bag[nm])])


func _place_order() -> void:
	var s := shop()
	if s == null or order.is_empty():
		return
	m.ui.close_modal()
	bill = 0
	for it in order:
		bill += int(it[2])
	phase = "cook"
	_cook_t = COOK_TIME
	m._say(s.waiter, ["Hemen geliyor!", "Mutfağa söylüyorum, az sonra masanızda!", "Çok güzel seçim, hemen!"][randi() % 3])
	m._sfx("tik", -6.0)
	_walk_home()
	m._update_context()


func _fast_pay(take_away: bool) -> void:
	var s := shop()
	var total := 0
	for it in order:
		total += int(it[2])
	if not state.spend(total):
		m.ui.toast("Paran yetmiyor.")
		return
	m.ui.close_modal()
	m._sfx("kasa", -6.0)
	if take_away:
		for it in order:
			_to_bag(TAKEAWAY.get(it[0], it[1]))
		order.clear()
		m._say(s.cashier, "Paketiniz hazır, afiyet olsun!")
		m.ui.toast("Paket siparişin çantana kondu. Çantadan (I) yiyebilirsin.")
		return
	bill = 0
	phase = "cook"
	_cook_t = COOK_TIME
	m._say(s.cashier, "Siparişiniz hazırlanıyor, masanıza getireceğiz!")
	m.ui.toast("Ödendi · %d ₺. Bir masaya otur, siparişin gelecek." % total)
	m._update_context()


func _bring() -> void:
	var s := shop()
	if s == null:
		return
	phase = "bring"
	_tray = Kit.pivot(s.waiter, Vector3(0.0, 1.05, -0.35))
	Kit.cyl(_tray, 0.24, 0.24, 0.015, Vector3.ZERO, Kit.mat("b8b8b8" if s.style != "fast" else "d9302b", 0.3), 18)
	for i in mini(order.size(), 3):
		Kit.cyl(_tray, 0.08, 0.08, 0.02, Vector3(-0.1 + i * 0.1, 0.02, 0), Kit.mat("f4f4f0", 0.3), 10)
	var tl: Vector2 = _table_side(s)
	var wp: Vector2 = Vector2(s.waiter.position.x, s.waiter.position.z)
	_walk = [Vector2(wp.x, s.waiter_home.y), Vector2(tl.x, s.waiter_home.y), tl]
	_walk_then = "serve"
	m._update_context()


func _serve() -> void:
	var s := shop()
	if s == null:
		return
	if is_instance_valid(_tray):
		_tray.queue_free()
	s.waiter.act("feed", 1.0)
	m._say(s.waiter, ["Afiyet olsun!", "Buyurun, sıcacık!", "Afiyet bal şeker olsun!"][randi() % 3])
	var food: Node3D = s.tables[seat["ti"]]["food"]
	for ch in food.get_children():
		ch.queue_free()
	_meal_gain = Vector2.ZERO
	for i in order.size():
		_dish(food, order[i][0], _plate_pos(s, seat["ti"], seat["si"], i))
		_meal_gain += Vector2(float(order[i][3]), float(order[i][4]))
	_bites = clampi(2 + order.size(), 3, 7)
	_bite_n = 0
	_bite_t = 1.2
	phase = "eat"
	m._sfx("mutlu", -12.0, 1.2)
	m.ui.toast("Yemeğin geldi! Afiyet olsun.")
	print("LOKANTA YEMEK GELDI ", order.size())
	_walk_home()
	m._update_context()


func pay() -> void:
	var s := shop()
	if bill <= 0:
		return
	var paid: int = mini(bill, int(state.d["coins"]))
	state.d["coins"] = int(state.d["coins"]) - paid
	m._sfx("kasa", -4.0)
	m.ui.toast("Hesap: %d ₺ ödendi · Teşekkürler, yine bekleriz!" % paid)
	if s:
		m._say(s.waiter, "Yine bekleriz, afiyet olsun!")
	bill = 0
	state.changed.emit()
	state.save_game()
	m._update_context()


func _finish_meal() -> void:
	var s := shop()
	phase = "done"
	state.count("eat_out")
	var pn: String = state.pet(m._active().kind)["name"]
	m.ui.toast("Karnın doydu! (+%d tokluk) %s" % [int(_meal_gain.x), ("Hesabı öde, sonra kalk." if bill > 0 else "%s da keyiflendi." % pn)])
	for kind in m.agents:
		state.add_need(kind, "fun", 6.0)
	if s:
		var food: Node3D = s.tables[seat["ti"]]["food"]
		for ch in food.get_children():
			var f: Node = ch.get_node_or_null("Ic")
			if f:
				f.visible = false
	m._update_context()


## Hayvana: su kabi (ucretsiz) ya da odul (5 TL).
func _pet_menu() -> void:
	var s := shop()
	if s == null or m.agents.is_empty():
		return
	var pn: String = state.pet(m._active().kind)["name"]
	var body: VBoxContainer = m.ui._open_panel("%s İÇİN" % pn.to_upper(), "Masanın yanında bekliyor")
	m.ui._panel_item(body, "SU KABI İSTE  ·  ÜCRETSİZ", func(): _pet_give(false))
	m.ui._panel_item(body, "ÖDÜL MAMASI  ·  5 ₺", func(): _pet_give(true))
	m.ui._panel_item(body, "KAPAT", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _pet_give(treat: bool) -> void:
	var s := shop()
	if s == null:
		return
	if treat and not state.spend(5):
		m.ui.toast("Paran yetmiyor.")
		return
	m.ui.close_modal()
	for kind in m.agents:
		var a: Node3D = m.agents[kind]
		var lp: Vector2 = s.local2(Vector2(a.position.x, a.position.z)) + Vector2(0.3, 0)
		var b := Node3D.new()
		b.position = Vector3(lp.x, 0.0, lp.y)
		s.add_child(b)
		Kit.cyl(b, 0.13, 0.1, 0.07, Vector3(0, 0.035, 0), Kit.mat("2f62a8" if not treat else "c8322b", 0.3), 14)
		Kit.cyl(b, 0.11, 0.11, 0.01, Vector3(0, 0.06, 0), Kit.mat("bfe3f2", 0.1) if not treat else Kit.mat("8a5a2b", 0.8), 14)
		_bowls.append(b)
		if treat:
			state.add_need(kind, "hunger", 20.0)
			state.add_need(kind, "fun", 8.0)
		else:
			state.add_need(kind, "hunger", 6.0)
			state.add_need(kind, "fun", 4.0)
	m._say(s.waiter, "Minik dostumuza da ikramımız!" if not treat else "Afiyet olsun pati!")
	m._pet_voice(m._active().kind, true)
	m.ui.toast("%s önüne konan kaptan yiyor." % state.pet(m._active().kind)["name"] if treat else "%s suyunu içiyor." % state.pet(m._active().kind)["name"])


# ---------------------------------------------------------------- yemek modelleri

func _plate_pos(s: Node3D, ti: int, si: int, i: int) -> Vector3:
	var tc: Vector2 = s.tables[ti]["c"]
	var lp: Vector2 = s.tables[ti]["seats"][si]["local"]
	var dz: float = signf(lp.y - tc.y) * 0.2
	var xs := [0.0, -0.27, 0.27, -0.13, 0.13, 0.0]
	return Vector3(xs[i % xs.size()], 0.78, dz + (0.0 if i < 3 else -dz * 0.9))


func _dish(parent: Node3D, id: String, pos: Vector3) -> void:
	var d := Node3D.new()
	d.position = pos
	parent.add_child(d)
	var ic := Node3D.new()
	ic.name = "Ic"
	match id:
		"ayran", "gazoz", "cay":
			if id == "cay":
				m.street_food.tea_glass(d, Vector3.ZERO, true, true)
				return
			var col := "f4f4f0" if id == "ayran" else "d9302b"
			Kit.cyl(d, 0.035, 0.03, 0.13, Vector3(0, 0.065, 0), Kit.mat(col, 0.3), 12)
			return
	var plate := Kit.mat("f6f6f2", 0.25)
	Kit.cyl(d, 0.13, 0.1, 0.02, Vector3(0, 0.01, 0), plate, 18)
	d.add_child(ic)
	match id:
		"adana":
			for k in 2:
				Kit.capsule(ic, 0.022, 0.2, Vector3(-0.02 + k * 0.045, 0.035, 0), Kit.mat("7a3a1e", 0.7), Vector3(0, 0, PI * 0.5))
			Kit.box(ic, Vector3(0.16, 0.01, 0.05), Vector3(0, 0.024, 0.06), Kit.mat("d9a85a", 0.8))
			Kit.ball(ic, 0.025, Vector3(0.07, 0.035, -0.05), Kit.mat("c8322b", 0.5), Vector3.ONE, 8)
			Kit.capsule(ic, 0.012, 0.1, Vector3(-0.06, 0.03, -0.06), Kit.mat("3f8f3a", 0.6), Vector3(0, 0, PI * 0.5))
		"iskender":
			for k in 5:
				Kit.box(ic, Vector3(0.05, 0.012, 0.08), Vector3(-0.08 + k * 0.04, 0.03, 0), Kit.mat("8a4a22", 0.7), Vector3(0, 0, 0.2))
			Kit.ball(ic, 0.06, Vector3(0, 0.022, 0.0), Kit.mat("b8401a", 0.4), Vector3(1.6, 0.25, 1.3), 10)
			Kit.ball(ic, 0.035, Vector3(0.07, 0.03, 0.05), Kit.mat("f4f4f0", 0.4), Vector3(1, 0.5, 1), 8)
		"lahmacun", "pide":
			if id == "lahmacun":
				Kit.cyl(ic, 0.12, 0.12, 0.012, Vector3(0, 0.026, 0), Kit.mat("d9a05a", 0.8), 18)
				Kit.cyl(ic, 0.105, 0.105, 0.006, Vector3(0, 0.034, 0), Kit.mat("a8401e", 0.7), 18)
			else:
				Kit.capsule(ic, 0.045, 0.26, Vector3(0, 0.035, 0), Kit.mat("d9a05a", 0.8), Vector3(0, 0, PI * 0.5))
				Kit.box(ic, Vector3(0.17, 0.02, 0.05), Vector3(0, 0.06, 0), Kit.mat("7a3a1e", 0.7))
		"kunefe", "sutlac":
			Kit.cyl(ic, 0.06, 0.07, 0.03, Vector3(0, 0.035, 0), Kit.mat("e0902a" if id == "kunefe" else "f2e6c8", 0.6), 14)
			Kit.cyl(ic, 0.05, 0.05, 0.005, Vector3(0, 0.052, 0), Kit.mat("3f8f3a" if id == "kunefe" else "a8682e", 0.6), 12)
		"mercimek":
			Kit.cyl(d, 0.075, 0.055, 0.06, Vector3(0, 0.05, 0), plate, 14)
			Kit.cyl(ic, 0.068, 0.068, 0.005, Vector3(0, 0.078, 0), Kit.mat("e08a2a", 0.5), 14)
		"fasulye", "karniyarik", "tavuk":
			var main_c: String = {"fasulye": "b8401a", "karniyarik": "4a2a4a", "tavuk": "d9a05a"}[id]
			Kit.ball(ic, 0.055, Vector3(-0.04, 0.025, 0), Kit.mat(main_c, 0.5), Vector3(1.2, 0.4, 1.0), 10)
			Kit.ball(ic, 0.045, Vector3(0.05, 0.025, 0), Kit.mat("f6f2e6", 0.8), Vector3(1.0, 0.5, 1.0), 10)
		"burger":
			Kit.ball(ic, 0.055, Vector3(0, 0.07, 0), Kit.mat("d08a3a", 0.6), Vector3(1, 0.5, 1), 12)
			Kit.cyl(ic, 0.058, 0.058, 0.018, Vector3(0, 0.05, 0), Kit.mat("5a2a14", 0.7), 12)
			Kit.cyl(ic, 0.062, 0.062, 0.006, Vector3(0, 0.062, 0), Kit.mat("3f8f3a", 0.6), 12)
			Kit.cyl(ic, 0.055, 0.055, 0.02, Vector3(0, 0.032, 0), Kit.mat("d08a3a", 0.6), 12)
		"doner", "menu":
			Kit.capsule(ic, 0.035, 0.2, Vector3(0, 0.04, 0), Kit.mat("e8d0a0", 0.8), Vector3(0, 0.4, PI * 0.5))
			if id == "menu":
				for k in 6:
					Kit.box(ic, Vector3(0.012, 0.012, 0.07), Vector3(0.05 + k * 0.012, 0.03, 0.05), Kit.mat("f2c230", 0.6), Vector3(0, k * 0.4, 0))
				Kit.cyl(d, 0.03, 0.026, 0.11, Vector3(0.16, 0.055, 0), Kit.mat("f4f4f0", 0.3), 10)
		"patates":
			Kit.box(ic, Vector3(0.07, 0.08, 0.04), Vector3(0, 0.05, 0), Kit.mat("d9302b", 0.5))
			for k in 6:
				Kit.box(ic, Vector3(0.01, 0.06, 0.01), Vector3(-0.025 + k * 0.01, 0.11, 0), Kit.mat("f2c230", 0.6))
		_:
			Kit.ball(ic, 0.05, Vector3(0, 0.03, 0), Kit.mat("b8743a", 0.6), Vector3(1.2, 0.5, 1), 10)


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	var s := shop()
	if s == null:
		if is_seated():
			seat = {}
			m.owner_model.seated = false
			m.owner_model.position = Vector3.ZERO
		return
	_update_waiter(s, dt)
	if phase == "cook":
		_cook_t -= dt
		if fmod(_cook_t, 1.6) < dt:
			s.cook.act("cook", 1.0)
		if _cook_t <= 0.0:
			if is_seated():
				_bring()
			else:
				phase = "ready"
				m._say(s.cashier, "Siparişiniz hazır! Bir masaya oturun, getirelim.")
				m._update_context()
	if not is_seated():
		return
	seat["t"] += dt
	if (m._mode != "play" and m._mode != "debug") or (seat["t"] > 0.6 and (m.ui.stick.length() > 0.5 or m._moving)):
		stand_up()
		return
	_place_seated()
	if phase == "eat":
		_bite_t -= dt
		if _bite_t <= 0.0:
			_bite_t = BITE_EVERY
			_bite_n += 1
			m.owner_model.act("eat", 2.2)
			m.needs.add("hunger", _meal_gain.x / float(_bites))
			m.needs.add("energy", (_meal_gain.y + 4.0) / float(_bites))
			# Tabaklar azalsin
			var food: Node3D = s.tables[seat["ti"]]["food"]
			for ch in food.get_children():
				var f: Node3D = ch.get_node_or_null("Ic")
				if f:
					f.scale = Vector3.ONE * clampf(1.0 - float(_bite_n) / float(_bites) * 0.7, 0.3, 1.0)
			if _bite_n >= _bites:
				_finish_meal()


func _update_waiter(s: Node3D, dt: float) -> void:
	var w: Node3D = s.waiter
	if _walk.is_empty():
		w.speed = 0.0
		return
	var cp := Vector2(w.position.x, w.position.z)
	var tgt: Vector2 = _walk[0]
	var d := tgt - cp
	var step := WAITER_SPEED * dt
	if d.length() <= step:
		w.position = Vector3(tgt.x, 0, tgt.y)
		_walk.pop_front()
		if _walk.is_empty():
			w.speed = 0.0
			var then := _walk_then
			_walk_then = ""
			match then:
				"take":
					if is_seated():
						var o: Vector3 = s.to_local(m.owner_node.global_position)
						w.rotation.y = atan2(-(o.x - w.position.x), -(o.z - w.position.z))
						phase = "order"
						m._say(w, ["Hoş geldiniz, ne alırdınız?", "Buyurun, menümüz burada.", "Bugün %s çok güzel!" % menu_of(s.style)[1][1]][randi() % 3])
						open_menu()
						m._update_context()
					else:
						phase = ""
						_walk_home()
				"serve":
					if is_seated():
						_serve()
					else:
						phase = "ready"
						_walk_home()
				"home":
					w.rotation.y = PI
		return
	cp += d / d.length() * step
	w.position = Vector3(cp.x, 0, cp.y)
	w.rotation.y = lerp_angle(w.rotation.y, atan2(-d.x, -d.y), minf(1.0, dt * 8.0))
	w.speed = WAITER_SPEED


# ---------------------------------------------------------------- telefon: Yakinimda

func _me() -> Vector2:
	if ParkMap.home != null:
		if m._shop != null and ParkMap.home == m._shop:
			return m._shop_spot["pos"]
		return m.HOME_DOOR + m.HOME_DOOR_OUT * 1.5
	return m._owner_pos()


func nearby_app() -> void:
	var me := _me()
	var cats := [["MARKET", "market"], ["LOKANTA", "lokanta"], ["ECZANE", "eczane"], ["VETERİNER", "veteriner"]]
	var rows: Array = []
	for c in cats:
		var best := {}
		var bd := 1e9
		for sp in m.world.shop_spots:
			if sp.get("kind", "") != c[1]:
				continue
			var d: float = me.distance_to(sp["pos"])
			if d < bd:
				bd = d
				best = sp
		if not best.is_empty():
			rows.append([c[0], best["name"], best["pos"], bd])
	var bd2 := 1e9
	var atm := {}
	for a in m.bank.atms:
		var d: float = me.distance_to(a["pos"])
		if d < bd2:
			bd2 = d
			atm = a
	if not atm.is_empty():
		rows.append(["ATM", String(atm.get("name", "ATM")), atm["pos"], bd2])
	var bd3 := 1e9
	var fs := {}
	for f in m.world.fuel_stations:
		var d: float = me.distance_to(f["entry"])
		if d < bd3:
			bd3 = d
			fs = f
	if not fs.is_empty():
		rows.append(["BENZİNLİK", String(fs["name"]), fs["entry"], bd3])
	var body: VBoxContainer = m.ui._open_panel("YAKINIMDA", "En yakın yerler · dokun, yol tarifi başlasın")
	for r in rows:
		var row: Array = r
		var dist: float = row[3]
		var dtxt := ("%d m" % int(dist)) if dist < 1000.0 else ("%.1f km" % (dist / 1000.0))
		m.ui._panel_item(body, "%s · %s · %s" % [row[0], row[1], dtxt], func():
			m.ui.close_modal()
			m._set_nav(row[2], row[1])
			m.ui.toast("Yol tarifi: %s (%s)" % [row[1], dtxt]))
	m.ui._panel_item(body, "KAPAT", func(): m.ui.close_modal())
	m.ui._focus_first(body)


# ---------------------------------------------------------------- test

## Test: --lokanta=1|order|sit [--lokstyle=kebap|ev|fast|market]. "sit": oturur, garson masaya yurur.
func debug_enter(order_too: bool, mode := "", want_style := "") -> void:
	var sp: Dictionary = {}
	for p in places:
		if (p["kind"] == "lokanta" and want_style == "") or (want_style != "" and p["style"] == want_style):
			sp = p
			break
	if sp.is_empty():
		print("LOKANTA yok")
		return
	if mode == "out" or mode == "back" or mode == "side":
		# Binayi disaridan goster: on cephe (vitrin), arka ya da yan
		var tw: Vector2 = sp.get("dir", Vector2(0, 1))
		var door: Vector2 = sp["pos"]
		var c: Vector2 = door - tw * 4.8
		var eye: Vector2 = door + tw * 9.0 + Vector2(-tw.y, tw.x) * 3.0
		if mode == "back":
			eye = c - tw * 14.0 + Vector2(-tw.y, tw.x) * 6.0
		elif mode == "side":
			eye = c + Vector2(-tw.y, tw.x) * 14.0 - tw * 4.0
		m._place_owner(door + tw * 3.0)
		m._mode = "debug"
		var gy := ParkMap.terrain_height(c)
		m.cam.global_position = Vector3(eye.x, ParkMap.terrain_height(eye) + 2.2, eye.y)
		m.cam.look_at(Vector3(c.x, gy + 2.6, c.y))
		return
	m._enter_shop(sp)
	if mode == "sit":
		sit(0, 1)
		return
	if not order_too:
		return
	var s := shop()
	sit(0, 1)
	_walk.clear()
	s.waiter.position = Vector3(_table_side(s).x, 0, _table_side(s).y)
	for row in menu_of(s.style).slice(0, 3):
		order.append(row)
	m.ui.close_modal()
	bill = 0
	for it in order:
		bill += int(it[2])
	_serve()
	_walk.clear()
	s.waiter.position = Vector3(_table_side(s).x, 0, _table_side(s).y)
