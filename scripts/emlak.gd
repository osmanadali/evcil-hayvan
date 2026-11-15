extends Node
## EvBul (emlak): haritadaki gercek apartmanlarda kiralik / satilik evler.
## - Telefon uygulamasi "EvBul": 8 ilan (1+1, 2+1, 3+1 daire, bahceli mustakil ev), adres, kat, fiyat, kucuk resim.
## - "Evi gez": ilanin ic mekanina isinlanir (scripts/emlak_interior.gd, ilan tohumuna gore degisen 4 sablon).
## - Kirala (haftalik kira, Faturalar'a "Kira" olarak duser) ya da satin al: binanin kapisi ek ev olur
##   (F · Eve Gir), icinde uyunur / kaydedilir, yemek pisirilir, mobilya yerlesir (home_life etkin eve gore calisir).
## - "Tasin": o evi ana ev yapar (Evim yol tarifi ve yeni oyun acilis noktasi). Eski ev her zaman durur.
## Kayit: state.d["emlak"] = {homes: {ilan no: {own: "kira" | "mulk", next: sonraki kira zamani}}, main: ilan no}

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const Interior = preload("res://scripts/emlak_interior.gd")

const BRAND := "EvBul"
const WEEK := 8400.0           # kira donemi: 7 oyun gunu (sn)
const EVICT := 2400.0          # son odemeden bu kadar sonra tahliye
## tur -> [haftalik kira, satis fiyati, ad, m2]
const TYPES := {
	"1+1": [350, 6000, "1+1 Daire", 55], "2+1": [550, 9500, "2+1 Daire", 90],
	"3+1": [800, 14000, "3+1 Daire", 130], "müstakil": [1100, 22000, "Müstakil Ev", 150],
}
const ORDER := ["1+1", "2+1", "müstakil", "3+1", "1+1", "2+1", "3+1", "müstakil"]

var m: Node
var state: Node
var listings: Array = []       # [{id, type, title, out, n, addr, street, floor, rent, price, m2, seed}]
var interior: Node3D
var cur := -1                  # icinde bulunulan ilan
var _ret := Vector2.INF        # gezmeden donulecek yer
var _near := -1
var _markers: Node3D
var _t := 0.0
var _rent_t := 0.0


# ---------------------------------------------------------------- durum

func _d() -> Dictionary:
	var e = state.d.get("emlak")
	if typeof(e) != TYPE_DICTIONARY:
		e = {"homes": {}, "main": ""}
		state.d["emlak"] = e
	if typeof(e.get("homes")) != TYPE_DICTIONARY:
		e["homes"] = {}
	return e


func own(id: String) -> String:
	var h = _d()["homes"].get(id)
	return str(h.get("own", "")) if typeof(h) == TYPE_DICTIONARY else ""


func find(id: String) -> int:
	for i in listings.size():
		if listings[i]["id"] == id:
			return i
	return -1


func owned() -> Array:
	var out: Array = []
	for L in listings:
		if own(L["id"]) != "":
			out.append(L)
	return out


func inside() -> bool:
	return interior != null and ParkMap.home == interior


func inside_owned() -> bool:
	return inside() and interior.lived


func cur_id() -> String:
	return str(listings[cur]["id"]) if cur >= 0 and cur < listings.size() else ""


## Ana ev tasinmissa onun kapisi, yoksa INF.
func spawn_point() -> Vector2:
	var i := find(str(_d().get("main", "")))
	if ParkMap.zone != "" or i < 0 or own(listings[i]["id"]) == "":
		return Vector2.INF
	return listings[i]["out"]


func main_door() -> Vector2:
	var p := spawn_point()
	return p if p != Vector2.INF else m.HOME_DOOR


# ---------------------------------------------------------------- ilanlar

## Dunya kurulunca: kapisi yola yakin apartmanlardan haritaya yayilmis ilanlari sec (her seferinde ayni).
func build() -> void:
	listings.clear()
	_near = -1
	if _markers != null:
		_markers.queue_free()
		_markers = null
	if ParkMap.zone != "":
		return
	var apts: Array = []
	var low: Array = []
	var blds: Array = ParkMap.data["buildings"]
	for i in blds.size():
		var b: Dictionary = blds[i]
		var dr = b.get("door")
		if str(b.get("t", "")) != "apartman" or str(b.get("name", "")) != "" or not (dr is Array) or dr.size() < 4:
			continue
		var n := Vector2(dr[2], dr[3])
		var out := Vector2(dr[0], dr[1]) + n * 1.7
		if not ParkMap.inside_bounds(out, 40.0) or out.distance_to(m.HOME_DOOR) < 70.0:
			continue
		var nn := ParkMap.nearest_node(out)
		if nn < 0 or ParkMap.nodes[nn].distance_to(out) > 24.0:
			continue
		(low if float(b["h"]) <= 7.0 else apts).append([out, i, n])
	var picked: Array = [m.HOME_DOOR]
	for t in ORDER:
		var pool: Array = apts
		var best := -1
		for try_pool in ([low, apts] if t == "müstakil" else [apts]):
			pool = try_pool
			best = -1
			var bs := -1e9
			var best_md := 0.0
			for k in pool.size():
				var p: Vector2 = pool[k][0]
				var md := 1e9
				for q in picked:
					md = minf(md, p.distance_to(q))
				var s := minf(md, 240.0) - 0.05 * p.distance_to(m.HOME_DOOR)
				if s > bs and not m.world._inside_building(p) and m.world.is_free(p, 0.5):
					bs = s
					best = k
					best_md = md
			if best >= 0 and best_md >= 90.0:
				break          # yeterince uzak bir aday bulundu (ilanlar ust uste binmesin)
		if best < 0:
			continue
		var c: Array = pool.pop_at(best)
		picked.append(c[0])
		var bi: int = c[1]
		var b: Dictionary = blds[bi]
		var seed_i := bi * 31 + 17
		var info: Array = TYPES[t]
		var floors := maxi(1, int(round((float(b["h"]) - 0.8) / 3.0)))
		var fl := 0 if t == "müstakil" else 1 + seed_i % floors
		var kf := 0.9 + float(seed_i % 21) / 100.0 + (0.03 * fl if t != "müstakil" else 0.0)
		var street: String = m._street_name(c[0])
		var no: String = str(b["no"]) if str(b.get("no", "")) != "" else str(seed_i % 58 + 2)
		listings.append({
			"id": str(bi), "type": t, "title": info[2], "out": c[0], "n": c[2], "street": street,
			"addr": "%s No: %s" % [street, no], "floor": fl, "floors": floors,
			"rent": int(round(float(info[0]) * kf / 10.0)) * 10, "price": int(round(float(info[1]) * kf / 100.0)) * 100,
			"m2": int(info[3]) + seed_i % 9 - 4, "seed": seed_i,
		})
	_rebuild_markers()


func _floor_text(L: Dictionary) -> String:
	return "Bahçeli, müstakil" if L["type"] == "müstakil" else "%d. kat (%d katlı bina)" % [int(L["floor"]), int(L["floors"])]


## Kapi onundeki tabela: ilan (KIRALIK · SATILIK) ya da kendi evin (EVİN) + yerde halka.
func _rebuild_markers() -> void:
	if _markers != null:
		_markers.queue_free()
	_markers = Node3D.new()
	m.add_child(_markers)
	for L in listings:
		var mine := own(L["id"]) != ""
		var n: Vector2 = L["n"]
		var p: Vector2 = L["out"] + Vector2(-n.y, n.x) * 1.3 - n * 0.9
		var r := Kit.pivot(_markers, Vector3(p.x, ParkMap.walk_height(p), p.y))
		r.rotation.y = atan2(n.x, n.y)
		var col := "2f9e4a" if mine else "e8375f"
		Kit.cyl(r, 0.03, 0.03, 1.5, Vector3(0, 0.75, 0), Kit.mat("d8d8d8", 0.4), 8)
		Kit.box(r, Vector3(0.95, 0.6, 0.04), Vector3(0, 1.6, 0), Kit.mat(col, 0.6))
		Kit.box(r, Vector3(0.95, 0.16, 0.045), Vector3(0, 1.82, 0), Kit.mat("ffd23a", 0.6))
		for side in [1.0, -1.0]:
			_label(r, BRAND, Vector3(0, 1.82, 0.027 * side), 0.11, Color("1a1a1a"), 0.0 if side > 0 else PI)
			_label(r, "EVİN" if mine else "KİRALIK", Vector3(0, 1.66, 0.027 * side), 0.17, Color.WHITE, 0.0 if side > 0 else PI)
			_label(r, str(L["type"]).to_upper() if mine else "SATILIK · " + str(L["type"]).to_upper(), Vector3(0, 1.45, 0.027 * side), 0.1, Color.WHITE, 0.0 if side > 0 else PI)
		if mine:
			var o: Vector2 = L["out"]
			Kit.torus(_markers, 0.5, 0.6, Vector3(o.x, ParkMap.walk_height(o) + 0.05, o.y), Kit.glow("3fe07a", 1.2))


func _label(parent: Node3D, text: String, pos: Vector3, size: float, col: Color, yrot: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.outline_size = 0
	l.modulate = col
	l.position = pos
	l.rotation.y = yrot
	l.double_sided = false
	if ResourceLoader.exists("res://assets/fonts/Anton-Regular.ttf"):
		l.font = load("res://assets/fonts/Anton-Regular.ttf")
	parent.add_child(l)


# ---------------------------------------------------------------- her kare, baglam, komut

func update(dt: float) -> void:
	if m._mode != "play":
		return
	_t -= dt
	if _t <= 0.0:
		_t = 0.25
		_near = -1
		if ParkMap.home == null and m._ride == null:
			var o: Vector2 = m._owner_pos()
			for i in listings.size():
				if o.distance_to(listings[i]["out"]) < 2.6:
					_near = i
	_rent_t -= dt
	if _rent_t <= 0.0:
		_rent_t = 1.0
		_check_rent()


func _check_rent() -> void:
	var homes: Dictionary = _d()["homes"]
	if homes.is_empty():
		return
	var bank: Node = m.bank
	var now: float = bank._now()
	for id in homes.keys():
		var h: Dictionary = homes[id]
		if str(h.get("own", "")) != "kira" or now < float(h.get("next", 0.0)):
			continue
		h["next"] = maxf(float(h.get("next", 0.0)) + WEEK, now + WEEK * 0.5)
		var i := find(str(id))
		var rent := int(listings[i]["rent"]) if i >= 0 else int(h.get("rent", 400))
		bank.unpaid().append({"k": "kira", "home": str(id), "amount": rent, "base": rent, "due": now + bank.DUE, "late": 0})
		m.ui.toast("Telefon · %s: Haftalık kiran kesildi · %d ₺ (P · Faturalar)" % [BRAND, rent])
		m._sfx("tik", -2.0, 1.4)
		state.save_game()
	var bills: Array = bank.unpaid()
	for bi in range(bills.size() - 1, -1, -1):
		var b: Dictionary = bills[bi]
		if str(b.get("k", "")) != "kira":
			continue
		var id := str(b.get("home", ""))
		if own(id) != "kira":
			if own(id) == "mulk":
				bills.remove_at(bi)       # ev satin alindi: kira borcu silinir
			continue
		if now - float(b["due"]) > EVICT:
			bills.remove_at(bi)
			_lose(id)
			m.ui.toast("%s: Kira çok gecikti, kiraladığın evden çıkarıldın!" % BRAND)


func context() -> Array:
	if m.needs.busy():
		return []
	if inside():
		var lo: Vector2 = interior.local2(m._owner_pos())
		if lo.distance_to(interior.entrance_local) < 1.0:
			return ["Dışarı Çık", "em_out", "come"]
		if interior.lived:
			if interior.near_bed(lo):
				return ["Yatak · Uyu / Kaydet", "em_bed", "moon"]
			return []
		return ["İlanı Aç · Kirala / Satın Al", "em_offer", "home"]
	if _near >= 0 and _near < listings.size() and ParkMap.home == null and m._ride == null:
		var L: Dictionary = listings[_near]
		if own(L["id"]) != "":
			return ["Eve Gir", "em_in", "home"]
		return ["Evi Gez · %s" % L["title"], "em_in", "home"]
	return []


func command(cmd: String) -> void:
	match cmd:
		"em_in":
			enter(_near)
		"em_out":
			leave()
		"em_bed":
			open_bed()
		"em_offer":
			open_listing(cur)
		"em_app":
			open_app()


# ---------------------------------------------------------------- ic mekan

func _drop() -> void:
	if interior != null:
		m.home_life.forget(interior)
		interior.queue_free()
		interior = null
	cur = -1


func enter(i: int, quiet := false) -> void:
	if i < 0 or i >= listings.size():
		return
	var was_in := inside()
	if ParkMap.home != null and not was_in:
		m.ui.toast("Önce bulunduğun yerden çık, sonra evi gezebilirsin.")
		return
	if m._ride != null or m._bus_ride != null or m._taxi != null:
		m.ui.toast("Önce araçtan in.")
		return
	if not was_in:
		_ret = m._owner_pos()
	_drop()
	var L: Dictionary = listings[i]
	interior = Interior.new()
	interior.type = L["type"]
	interior.seed_i = int(L["seed"])
	interior.hour = m.clock
	interior.lid = L["id"]
	interior.lived = own(L["id"]) != ""
	interior.position = Vector3(ParkMap.BOUNDS_MAX.x + 300.0, 300.0, 0.0)   # haritanin disinda, gokyuzunde
	m.add_child(interior)
	cur = i
	ParkMap.home = interior
	if interior.lived:
		m.home_life.on_home(interior)
	m._moving = false
	m._queue.clear()
	m._place_owner(interior.w2(interior.entrance_local))
	m.owner_node.rotation.y = 0.0
	var k := 0
	for a in m.agents:
		m.agents[a].place(interior.w2(interior.entrance_local + Vector2(-0.9 - 0.6 * k, -0.4)))
		k += 1
	m._cam_pitch = 0.9
	m._cam_yaw = 0.0
	m._focus = m.owner_node.position
	state.count("emlak")
	if quiet:
		return
	m._sfx("dukkan_zil", -10.0, 1.3)
	if interior.lived:
		m.ui.toast("Evindesin · %s" % L["addr"])
	else:
		m.ui.toast("%s · %s · Gez, beğenirsen kirala ya da satın al." % [L["title"], L["addr"]])


func leave() -> void:
	if not inside():
		return
	var L: Dictionary = listings[cur]
	var out: Vector2 = L["out"] if (interior.lived or _ret == Vector2.INF) else _ret
	ParkMap.home = null
	_drop()
	_ret = Vector2.INF
	m._place_owner(out)
	var k := 0
	for a in m.agents:
		m.agents[a].place(m._owner_pos() + Vector2(1.0 + 0.6 * k, 0.5).rotated(k * 2.0))
		k += 1
	m._cam_pitch = 0.27
	m._focus = m.owner_node.position


## "Devam Et": son kayit bu evlerden birindeyse iceride basla.
func restore(id: String) -> bool:
	var i := find(id)
	if i < 0 or own(id) == "" or ParkMap.zone != "":
		return false
	enter(i, true)
	if not inside():
		return false
	_ret = Vector2.INF
	m._place_owner(interior.w2(interior.bed_edge() + Vector2(0.8, 0.3)))
	m._focus = m.owner_node.position
	return true


func open_bed() -> void:
	if not inside_owned():
		return
	var L: Dictionary = listings[cur]
	var place := "Evim · %s" % L["addr"]
	var body: VBoxContainer = m.ui._open_panel("YATAK", "Kayıt noktası · %s" % L["addr"])
	m.ui._panel_item(body, "Kaydet ve uyu · sabah 08:00'e kadar", func():
		m.ui.close_modal()
		if inside():
			await m.needs.sleep(interior, interior.bed_edge())
			m.hotel.save_now(place))
	m.ui._panel_item(body, "Oyunu Kaydet", func():
		m.ui.close_modal()
		m.hotel.save_now(place))
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


# ---------------------------------------------------------------- kiralama, satin alma, tasinma

## Once cuzdandan, yetmezse banka hesabindan oder.
func _pay(n: int) -> bool:
	var cash := int(state.d["coins"])
	var bal: int = m.bank.balance()
	if cash + bal < n:
		m.ui.toast("Paran yetmiyor: %d ₺ gerekli (cüzdan %d ₺ + hesap %d ₺)." % [n, cash, bal])
		return false
	var from_cash := mini(cash, n)
	state.d["coins"] = cash - from_cash
	if n > from_cash:
		m.bank._d()["bank"] = bal - (n - from_cash)
		m.bank._log(BRAND + " ödemesi", -(n - from_cash))
	state.changed.emit()
	return true


func _became_home(i: int) -> void:
	_rebuild_markers()
	if inside() and cur == i and not interior.lived:
		interior.lived = true
		m.home_life.on_home(interior)
	state.count("emlak_own")
	state.save_game()
	m._sfx("kasa", -4.0)
	m._update_context()


func rent(i: int) -> void:
	var L: Dictionary = listings[i]
	if own(L["id"]) != "" or not _pay(int(L["rent"])):
		return
	_d()["homes"][L["id"]] = {"own": "kira", "next": float(m.bank._now()) + WEEK, "rent": int(L["rent"])}
	_became_home(i)
	m.ui.toast("Kiraladın! %s · İlk hafta ödendi, kira her hafta Faturalar'a düşer." % L["addr"])


func buy(i: int) -> void:
	var L: Dictionary = listings[i]
	if own(L["id"]) == "mulk" or not _pay(int(L["price"])):
		return
	_d()["homes"][L["id"]] = {"own": "mulk"}
	_became_home(i)
	m.ui.toast("Tapu senin! %s artık kendi evin, kira yok." % L["addr"])


func _lose(id: String) -> void:
	_d()["homes"].erase(id)
	if str(_d().get("main", "")) == id:
		_d()["main"] = ""
	if inside() and cur_id() == id:
		leave()
	_rebuild_markers()
	state.save_game()


func move_in(i: int) -> void:
	var L: Dictionary = listings[i]
	if own(L["id"]) == "":
		return
	_d()["main"] = L["id"]
	state.save_game()
	m._sfx("mutlu", -8.0)
	m.ui.toast("Taşındın! Ana evin artık %s. (Telefon · Evim buraya götürür)" % L["addr"])


# ---------------------------------------------------------------- telefon uygulamasi

## Ilanin "fotografi": ilanin paletinden cizilen kucuk resim.
class Thumb extends Control:
	var P := {}
	var type := "1+1"
	var badge := ""
	var font: Font

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var wall := Color(str(P["wall"]))
		var sky := Color("a9d3f2")
		if type == "müstakil":
			draw_rect(Rect2(0, 0, w, h), sky)
			draw_rect(Rect2(0, h * 0.68, w, h * 0.32), Color("5f9f55"))
			draw_rect(Rect2(w * 0.3, h * 0.36, w * 0.5, h * 0.36), wall)
			draw_colored_polygon(PackedVector2Array([Vector2(w * 0.25, h * 0.38), Vector2(w * 0.55, h * 0.1), Vector2(w * 0.85, h * 0.38)]), Color("a8402f"))
			draw_rect(Rect2(w * 0.51, h * 0.48, w * 0.08, h * 0.24), Color(str(P["wood"])))
			for x in [0.36, 0.66]:
				draw_rect(Rect2(w * x, h * 0.46, w * 0.09, h * 0.12), Color("dff0fa"))
			draw_rect(Rect2(w * 0.12, h * 0.42, w * 0.03, h * 0.3), Color("5b4630"))
			draw_circle(Vector2(w * 0.135, h * 0.36), h * 0.17, Color("3b8f42"))
			for i in 12:
				draw_rect(Rect2(w * i / 12.0 + 2, h * 0.74, w / 12.0 - 4, h * 0.14), Color("efe8da"))
		else:
			var fl := Color("b9895a") * Color(str(P["floor_tint"])) if P["floor"] == "parke" else Color("e6dfd2")
			draw_rect(Rect2(0, 0, w, h), wall)
			draw_rect(Rect2(0, h * 0.66, w, h * 0.34), fl)
			draw_rect(Rect2(0, h * 0.66, w, 2), Color(str(P["wood"])))
			# Pencere + manzara
			var wr := Rect2(w * 0.42, h * 0.12, w * 0.4, h * 0.4)
			draw_rect(wr, sky)
			if P["view"] == "sehir":
				for i in 5:
					var bh := wr.size.y * (0.25 + 0.12 * ((i * 7) % 4))
					draw_rect(Rect2(wr.position.x + wr.size.x * i / 5.0, wr.end.y - bh, wr.size.x / 5.0 - 1, bh), Color("8d9aa8").lightened(0.1 * (i % 3)))
			else:
				for i in 4:
					draw_circle(Vector2(wr.position.x + wr.size.x * (0.15 + 0.23 * i), wr.end.y - wr.size.y * 0.2), wr.size.y * 0.3, Color("3f8a4a").lightened(0.08 * (i % 2)))
				draw_rect(Rect2(wr.position.x, wr.end.y - wr.size.y * 0.16, wr.size.x, wr.size.y * 0.16), Color("5f9f55"))
			draw_rect(wr, Color.WHITE, false, 2.0)
			draw_line(Vector2(wr.get_center().x, wr.position.y), Vector2(wr.get_center().x, wr.end.y), Color.WHITE, 2.0)
			var cur := Color(str(P["curtain"]))
			draw_rect(Rect2(wr.position.x - w * 0.05, wr.position.y - 3, w * 0.06, wr.size.y + h * 0.1), cur)
			draw_rect(Rect2(wr.end.x - w * 0.01, wr.position.y - 3, w * 0.06, wr.size.y + h * 0.1), cur)
			# Hali, kanepe, bitki
			var sofa := Color(str(P["sofa"]))
			draw_rect(Rect2(w * 0.3, h * 0.8, w * 0.5, h * 0.12), sofa.lightened(0.45))
			draw_rect(Rect2(w * 0.05, h * 0.46, w * 0.32, h * 0.2), sofa.darkened(0.12))
			draw_rect(Rect2(w * 0.04, h * 0.6, w * 0.34, h * 0.16), sofa)
			draw_rect(Rect2(w * 0.88, h * 0.58, w * 0.06, h * 0.14), Color("e9e2d2"))
			draw_circle(Vector2(w * 0.91, h * 0.48), h * 0.13, Color("2f7a45"))
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.85), false, 3.0)
		if badge != "" and font != null:
			var fs := int(clampf(h * 0.2, 13, 30))
			var tw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(0, 0, tw + 14, fs + 8), Color("e8375f"))
			draw_string(font, Vector2(7, fs + 1), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _thumb(L: Dictionary, sz: Vector2, badge: String) -> Thumb:
	var t := Thumb.new()
	t.P = Interior.palette(int(L["seed"]), L["type"])
	t.type = L["type"]
	t.badge = badge
	t.font = m.ui.F_BODY
	t.custom_minimum_size = sz
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _status(L: Dictionary) -> String:
	var o := own(L["id"])
	if o == "":
		return ""
	return ("EVİN" if o == "mulk" else "KİRACISIN") + (" · ANA EV" if str(_d().get("main", "")) == L["id"] else "")


func open_app() -> void:
	var ui: Node = m.ui
	var sub := "Cüzdan: %d ₺  ·  Hesap: %d ₺  ·  %d ilan  ·  Kira haftalık, ilk hafta peşin" % [int(state.d["coins"]), m.bank.balance(), listings.size()]
	if listings.is_empty():
		sub = "Bu bölgede ilan yok. İlanlar Subayevleri tarafında."
	var body: VBoxContainer = ui._open_page(BRAND.to_upper(), sub)
	for i in listings.size():
		var L: Dictionary = listings[i]
		var idx: int = i
		var st := _status(L)
		var tail: String = st if st != "" else "%d ₺/HAFTA" % int(L["rent"])
		var b: Button = ui._menu_item(body, "%s · %s · %s" % [str(L["type"]).to_upper(), str(L["street"]).to_upper(), tail], func(): open_listing(idx))
		b.custom_minimum_size.x = 1010
		var t := _thumb(L, Vector2(104, 58), "")
		b.add_child(t)
		t.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		t.offset_left = -112
		t.offset_right = -8
		t.offset_top = -29
		t.offset_bottom = 29
	ui._menu_item(body, "KAPAT", func(): ui.close_modal())
	ui._focus_first(body)


func open_listing(i: int) -> void:
	if i < 0 or i >= listings.size():
		return
	var ui: Node = m.ui
	var L: Dictionary = listings[i]
	var P: Dictionary = Interior.palette(int(L["seed"]), L["type"])
	var o := own(L["id"])
	var extra := "Bahçe" if L["type"] == "müstakil" else ("Balkonlu" if P["balcony"] else "Balkonsuz")
	var sub := "%s  ·  %s  ·  %d m²" % [L["addr"], _floor_text(L), int(L["m2"])]
	var body: VBoxContainer = ui._open_page(str(L["title"]).to_upper(), sub)
	var ph := _thumb(L, Vector2(400, 210), _status(L) if o != "" else "KİRALIK · SATILIK")
	ph.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(ph)
	var info: Label = ui._fx_label(body, "%s zemin  ·  %s  ·  Kira %d ₺/hafta  ·  Satış %d ₺  ·  Cüzdan + hesap: %d ₺" % [P["floor_name"], extra, int(L["rent"]), int(L["price"]), int(state.d["coins"]) + int(m.bank.balance())], ui.F_BODY, 26, Color(1, 1, 1, 0.92), 4)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not (inside() and cur == i):
		ui._menu_item(body, "EVE GİR" if o != "" else "EVİ GEZ", func():
			ui.close_modal()
			enter(i))
	if o == "":
		ui._menu_item(body, "KİRALA · %d ₺ / HAFTA" % int(L["rent"]), func():
			rent(i)
			open_listing(i))
	if o != "mulk":
		ui._menu_item(body, "SATIN AL · %d ₺" % int(L["price"]), func():
			buy(i)
			open_listing(i))
	if o != "":
		if str(_d().get("main", "")) == L["id"]:
			ui._menu_item(body, "ANA EVİN ✓ · ESKİ EVE GERİ TAŞIN", func():
				_d()["main"] = ""
				state.save_game()
				ui.toast("Ana evin yine Subayevleri'ndeki daire.")
				open_listing(i))
		else:
			ui._menu_item(body, "TAŞIN · ANA EVİM OLSUN", func():
				move_in(i)
				open_listing(i))
	if o == "kira":
		ui._menu_item(body, "KİRADAN ÇIK", func():
			_lose(L["id"])
			ui.toast("Kira sözleşmen bitti: %s" % L["addr"])
			open_app())
	if not inside():
		ui._menu_item(body, "YOL TARİFİ", func():
			ui.close_modal()
			m._set_nav(L["out"], "%s · %s" % [L["title"], L["street"]]))
	ui._menu_item(body, "GERİ", func(): open_app())
	ui._focus_first(body)


# ---------------------------------------------------------------- test

## Test: --emlak (uygulama), --emlak=ilan (ilk ilanin sayfasi), --emlak=dis (ilk ilanin kapisi),
## --view=listingN (N. ilanin ici), --view=listingN --emlak=kira (kiralanmis: ev hayati acik).
func debug(mode: String, view: String) -> void:
	print("EMLAK ilan=", listings.size())
	for L in listings:
		print("  ", L["id"], " ", L["type"], " ", L["addr"], " kat=", L["floor"], " kira=", L["rent"], " satis=", L["price"], " kapi=", L["out"])
	if listings.is_empty():
		return
	if view.begins_with("listing"):
		var i := clampi(int(view.substr(7)), 0, listings.size() - 1)
		if mode == "kira":
			state.d["coins"] = maxi(int(state.d["coins"]), 3000)
			rent(i)
		enter(i)
		for f in 3:
			await get_tree().process_frame
		m.ui.visible = true
		m._place_owner(interior.w2(Vector2(interior.SW * 0.55, interior.D * 0.5)))
		m._focus = m.owner_node.position
		m._zoom = 1.0
		for f in 3:
			await get_tree().process_frame
		m._update_context()
		print("EMLAK IC tur=", interior.type, " W=", interior.W, " D=", interior.D, " baglam=", m.ui._context_cmd, " yasanan=", interior.lived)
		return
	if mode == "dis":
		var L: Dictionary = listings[0]
		m._place_owner(L["out"])
		m._focus = m.owner_node.position
		return
	if mode == "ilan":
		open_listing(0)
	else:
		open_app()
