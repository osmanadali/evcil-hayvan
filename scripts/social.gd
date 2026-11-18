extends Node
## Sosyal hayat: arkadaslar, bulusmalar, sevgili, dogum gunleri, bayramlar.
## - Arkadaslar: komsular (scripts/neighbors.gd, ayni dostluk degeri state.d["friends"]) ve Cinaralti Cay
##   Ocagi'nin mudavimleri Selin ve Deniz. Mesajlar uygulamasina davet gelir ("Kafede bulusalim mi? 18:00
##   Cinaralti"); kabul edince o saatte oraya gidince arkadas gelir, ayni masaya oturulur, sohbet secenekleri
##   dostlugu arttirir.
## - Sevgili: Selin ya da Deniz ile yeterli dostluk + randevu (aksam yemegi, parkta yuruyus, gol turu)
##   sonrasi "Benimle cikar misin?"; daha sonra "Birlikte yasayalim mi?" -> evde birlikte yasarsiniz.
## - Dogum gunleri: oyun takviminde her arkadasin bir gunu var; bildirim -> marketten hediye / cicek
##   -> aksam partisi.
## - Bayram: oyun takvimi 30 gunluk dongu; Ramazan gunlerinde parkta komsularla uzun iftar sofrasi,
##   Ramazan (Seker) ve Kurban Bayrami'nda cocuklar seker toplamaya gelir, komsular bayramlasmaya gelir.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PersonModel = preload("res://scripts/person_model.gd")

const CYCLE := 30
const RAMAZAN := [7, 8, 9, 10]
const SEKER_BAYRAMI := [11, 12, 13]
const KURBAN_BAYRAMI := [24, 25, 26, 27]
# Yeni arkadaslar (Cinaralti mudavimleri): [ad, cinsiyet, tisort, pantolon, renk, saat bas, saat son, tabure]
const NEW_PEOPLE := {
	"selin": ["Selin", "kadin", "e86a8a", "2b2f38", "e86a8a", 10.0, 15.5, 4],
	"deniz": ["Deniz", "erkek", "2f9e8a", "3b3b46", "2f9e8a", 15.0, 21.0, 13],
}
const CANDIDATES := ["selin", "deniz"]
const BDAY := {"hasan": 5, "ayse": 17, "mert": 21, "fatma": 28, "selin": 14, "deniz": 3}
const GIFTS := ["Hediye Paketi", "Çiçek Buketi"]
const CANDY := "Bayram Şekeri"
const DATE_KINDS := ["dinner", "walk", "boat"]
# Sohbet: [arkadasin sozu, [[cevap, dostluk, arkadasin yaniti], ...]]
const TOPICS := [
	["Bu hafta çok yoğundu, işler bir türlü bitmedi.", [
		["Anlat bakalım, neler oldu?", 6, "Sağ ol, dinlediğin için. İçim rahatladı."],
		["Benimki daha kötüydü!", 1, "Hmm… herkesin derdi kendine."],
		["(Telefonuna bak)", -3, "Beni dinlemiyorsun galiba…"]]],
	["Hafta sonu ne yapsak?", [
		["Göle gidelim, tekne turu var!", 5, "Harika fikir! Martılara simit atarız."],
		["Evde film izleriz.", 3, "Olur, patlamısır benden."],
		["Bilmem, sen düşün.", 0, "Peki… yine ben düşüneyim."]]],
	["%s çok tatlı! Ne zamandır seninle?", [
		["Gel, sev istersen!", 6, "Ay, ne yumuşacık! Bayıldım."],
		["Epey oldu, en iyi dostum o.", 4, "Belli, sana nasıl bakıyor bir görsen."],
		["Bazen çok yaramaz ama.", 2, "Hepsi öyle, yaramazlık da ayrı tatlı."]]],
	["Çayı nasıl seversin?", [
		["Tavşan kanı, demli!", 4, "İşte bu! Tam Ankaralı."],
		["Açık, bol şekerli.", 3, "Şekerin tabakta, keyfine bak."],
		["Ben kahveciyim aslında.", 1, "Çınaraltı'nda bunu yüksek sesle söyleme!"]]],
	["Keçiören'de en sevdiğin yer neresi?", [
		["Altınpark'ın gölü.", 4, "Akşam üstü orada yürümek bir harika."],
		["Burası tabii, Çınaraltı!", 5, "Bence de, burası bizim yer."],
		["Evim, kapıdan çıkmam.", 1, "Arada bir çık, biz buradayız!"]]],
	["Son zamanlarda ne okuyorsun?", [
		["Bir polisiye roman, elimden bırakamıyorum.", 4, "Bitince bana ver, ben de okurum."],
		["Hayvan bakımı üzerine bir kitap.", 5, "Ne güzel, %s şanslı bir dost."],
		["Okumuyorum pek.", 0, "Sana güzel bir kitap önereyim o zaman."]]],
	["Çocukken ne olmak isterdin?", [
		["Veteriner! Hâlâ içimde.", 5, "Bence çok yakışırdı sana."],
		["Futbolcu, halı sahada hâlâ deniyorum.", 3, "Bir maç yapalım o zaman!"],
		["Hatırlamıyorum ki.", 0, "Hmm, ben astronot olmak isterdim."]]],
]
const ROMANCE_TOPICS := [
	["Seninle vakit geçirmek çok güzel.", [
		["Ben de çok mutluyum, iyi ki tanışmışız.", 7, "İyi ki…"],
		["Evet, çay da güzel.", 1, "Çay mı? Peki…"],
		["Hadi bir fotoğraf çekelim!", 5, "Gülümse! Ay, çok güzel çıktık."]]],
	["Gelecekte kendini nerede görüyorsun?", [
		["Güzel bir evde, sevdiklerimle.", 6, "Ne güzel bir hayal."],
		["Bir bahçede, bir sürü hayvanla!", 6, "%s de bir kardeş ister bence."],
		["Hiç düşünmedim.", 1, "Düşünmek lazım ama, değil mi?"]]],
]

var m: Node
var state: Node
var regulars := {}            # id -> PersonModel (Cinaralti'nda oturan mudavim)
var guest: Dictionary = {}    # etkin bulusma: {id, kind, model, stool, table, rounds, ...}
var kids: Array = []          # [{model, done, t, home}]
var iftar: Dictionary = {}    # {root, pos, yaw, seats:[{pos,yaw}], player_seat, people}
var home_people: Array = []   # evdeki misafirler / sevgili: [{id, model}]
var _seated: Dictionary = {}  # oyuncu iftar sofrasinda: {pos, yaw, t, ate}
var _tick := 0.0
var _last_clock := -1.0
var _near := ""               # baglam: yakin kisi / is
var _boat_seen := false
var _kids_cd := 0.0
var _reg_block := {}          # id -> bekleme (sn): bulusmadan sonra mudavim hemen geri oturmasin


# ---------------------------------------------------------------- durum

func s() -> Dictionary:
	if not state.d.has("soc") or typeof(state.d["soc"]) != TYPE_DICTIONARY:
		state.d["soc"] = {}
	var d: Dictionary = state.d["soc"]
	for k in ["met", "dates", "done", "msgd"]:
		if not d.has(k) or typeof(d[k]) != TYPE_DICTIONARY:
			d[k] = {}
	if not d.has("day"):
		d["day"] = 1
	if not d.has("partner"):
		d["partner"] = ""
		d["stage"] = ""
	if not d.has("appt") or typeof(d["appt"]) != TYPE_DICTIONARY:
		d["appt"] = {}
	if not d.has("invite") or typeof(d["invite"]) != TYPE_DICTIONARY:
		d["invite"] = {}
	if not d.has("inv_t"):
		d["inv_t"] = 90.0
	return d


func day() -> int:
	return int(s()["day"])


func cday(dd := -1) -> int:
	if dd < 0:
		dd = day()
	return ((dd - 1) % CYCLE) + 1


func is_ramazan(dd := -1) -> bool:
	return cday(dd) in RAMAZAN


func bayram_name(dd := -1) -> String:
	var c := cday(dd)
	if c in SEKER_BAYRAMI:
		return "Ramazan Bayramı"
	if c in KURBAN_BAYRAMI:
		return "Kurban Bayramı"
	return ""


func bayram_day_no(dd := -1) -> int:
	var c := cday(dd)
	if c in SEKER_BAYRAMI:
		return c - int(SEKER_BAYRAMI[0]) + 1
	if c in KURBAN_BAYRAMI:
		return c - int(KURBAN_BAYRAMI[0]) + 1
	return 0


func date_text() -> String:
	var t := "Gün %d" % day()
	var b := bayram_name()
	if b != "":
		return t + " · %s %d. gün" % [b, bayram_day_no()]
	if is_ramazan():
		return t + " · Ramazan"
	return t


func _done(key: String) -> bool:
	return int(s()["done"].get(key, -1)) == day()


func _mark(key: String) -> void:
	s()["done"][key] = day()


func pname(id: String) -> String:
	if NEW_PEOPLE.has(id):
		return NEW_PEOPLE[id][0]
	if m.neighbors.PEOPLE.has(id):
		return m.neighbors.PEOPLE[id][0]
	return id


func _short(id: String) -> String:
	return {"hasan": "Hasan Efendi", "ayse": "Ayşe Teyze", "mert": "Mert", "fatma": "Fatma Hanım"}.get(id, pname(id))


func friend(id: String) -> int:
	return m.neighbors.friend(id)


func add_friend(id: String, n: int, show := true) -> void:
	m.neighbors._add_friend(id, n)
	if show and n != 0:
		m.ui.toast("%s ile dostluk %s%d · %d / 100" % [_short(id), "+" if n > 0 else "", n, friend(id)])


func friends_list() -> Array:
	var out: Array = []
	for id in m.neighbors.PEOPLE:
		out.append(id)
	for id in NEW_PEOPLE:
		if s()["met"].has(id):
			out.append(id)
	return out


func partner() -> String:
	return String(s()["partner"])


func rel_text(id: String) -> String:
	if partner() == id:
		return "Sevgilin" if s()["stage"] != "ev" else "Sevgilin · Birlikte yaşıyorsunuz"
	var f := friend(id)
	return "Yabancı" if f < 20 else ("Tanıdık" if f < 45 else ("Dost" if f < 75 else "Can Dostu"))


func _thread(id: String) -> void:
	var md: Dictionary = m.neighbors._md()
	if md.has(id):
		return
	var nm := pname(id)
	var col := "777777"
	if NEW_PEOPLE.has(id):
		col = NEW_PEOPLE[id][4]
	elif m.neighbors.MSG_SENDERS.has(id):
		col = m.neighbors.MSG_SENDERS[id][1]
	if id == "takvim":
		nm = "Takvim"
		col = "8e5cd9"
	md[id] = {"name": nm, "col": col, "items": [], "unread": 0, "order": 0}


func msg(id: String, text: String, act := "", replies: Array = [], quiet := false) -> void:
	_thread(id)
	m.neighbors.push_msg(id, text, act, replies, quiet)


func _person(kind: String, shirt: String, pants: String) -> PersonModel:
	var v := PersonModel.new()
	v.kind = kind
	v.tint = Color(shirt)
	v.tint2 = Color(shirt)
	v.pants = Color(pants)
	return v


func _person_for(id: String) -> PersonModel:
	if NEW_PEOPLE.has(id):
		var a: Array = NEW_PEOPLE[id]
		return _person(a[1], a[2], a[3])
	var p: Array = m.neighbors.PEOPLE[id]
	return _person(p[1], p[2], p[3])


func _face(n: Node3D, to: Vector2) -> void:
	var d := to - Vector2(n.global_position.x, n.global_position.z)
	if d.length() > 0.01:
		n.global_rotation.y = atan2(-d.x, -d.y)


func _bag() -> Dictionary:
	if not state.d.has("bag") or typeof(state.d["bag"]) != TYPE_DICTIONARY:
		state.d["bag"] = {}
	return state.d["bag"]


func _bag_n(item: String) -> int:
	return int(_bag().get(item, 0))


func _bag_take(item: String) -> bool:
	var b := _bag()
	if int(b.get(item, 0)) <= 0:
		return false
	b[item] = int(b[item]) - 1
	if int(b[item]) <= 0:
		b.erase(item)
	return true


func _pet_name() -> String:
	return state.pet(state.d["active"])["name"]


func _fmt(t: String) -> String:
	return t % _pet_name() if t.contains("%s") else t


# ---------------------------------------------------------------- yerler

func tea_ok() -> bool:
	return not m.street_food.tea.is_empty()


func place_of(kind: String, id := "") -> Vector2:
	match kind:
		"cafe", "dinner":
			if tea_ok():
				return m.street_food.tea["pos"]
		"walk":
			return _park_pos()
		"boat":
			if m.boat.built:
				return m.boat.booth_front
		"party":
			if NEW_PEOPLE.has(id):
				return _park_pos()
			var o2: Vector2 = m.HOME_DOOR_OUT
			return m.HOME_DOOR + o2 * 3.5 + Vector2(-o2.y, o2.x) * 3.0
		"iftar":
			return _iftar_pos()
	return m.HOME_DOOR + m.HOME_DOOR_OUT * 4.0


func place_label(kind: String, id := "") -> String:
	match kind:
		"cafe":
			return "Çınaraltı"
		"dinner":
			return "Çınaraltı'nda akşam yemeği"
		"walk":
			return "parkta yürüyüş"
		"boat":
			return "göl iskelesinde"
		"party":
			return "parkta doğum günü" if NEW_PEOPLE.has(id) else "apartmanın önünde doğum günü"
		"iftar":
			return "parkta iftar sofrası"
	return ""


var _park_cache := Vector2.INF


func _park_pos() -> Vector2:
	if _park_cache != Vector2.INF:
		return _park_cache
	if ParkMap.zone == "" and ParkMap.has_spot("bahce"):
		_park_cache = ParkMap.spot("bahce")
	else:
		_park_cache = _nearest_park(m._owner_pos())
	return _park_cache


func _nearest_park(from: Vector2) -> Vector2:
	var best := from
	var bd := 1e9
	for pk in ParkMap.data.get("parks", []):
		var pts: Array = pk["p"]
		if pts.size() < 3:
			continue
		var c := Vector2.ZERO
		for q in pts:
			c += Vector2(float(q[0]), float(q[1]))
		c /= float(pts.size())
		var dd := c.distance_to(from)
		if dd < bd:
			bd = dd
			best = c
	return best


var _iftar_cache := Vector2.INF
var _iftar_yaw := 0.0


func _iftar_pos() -> Vector2:
	if _iftar_cache != Vector2.INF:
		return _iftar_cache
	var c: Vector2 = _nearest_park(m.HOME_DOOR) if ParkMap.zone == "" else _park_pos()
	_iftar_cache = c
	var w: Node = m.world
	for r in range(0, 40, 3):
		var found := false
		for k in 12:
			var p := c + Vector2.from_angle(k * TAU / 12.0) * float(r)
			for a in [0.0, PI * 0.5, PI * 0.25, -PI * 0.25]:
				var ax := Vector2.from_angle(a)
				var sd := Vector2(-ax.y, ax.x)
				var ok: bool = not w._inside_building(p) and ParkMap.water_sd(p) > 3.0
				for t in [-3.2, -1.6, 0.0, 1.6, 3.2]:
					for sgn in [-1.0, 1.0]:
						if ok and (not w.is_free(p + ax * t + sd * 1.0 * sgn, 0.45) or w._inside_building(p + ax * t + sd * 3.0 * sgn)):
							ok = false
				if ok:
					_iftar_cache = p
					_iftar_yaw = a
					found = true
					break
			if found:
				break
		if found:
			break
	return _iftar_cache


# ---------------------------------------------------------------- kurulum / her kare

func build() -> void:
	s()
	_last_clock = m.clock


func busy() -> bool:
	return not _seated.is_empty()


func update(dt: float) -> void:
	if m.world == null:
		return
	# Gun sayaci: saat gece yarisini gecince bir gun ilerler
	if _last_clock >= 0.0 and m.clock < _last_clock - 12.0:
		s()["day"] = day() + 1
		_new_day()
	_last_clock = m.clock
	_update_guest(dt)
	_update_kids(dt)
	_update_seated(dt)
	_tick -= dt
	if _tick > 0.0:
		return
	_tick = 0.5
	_slow_update()


func _slow_update() -> void:
	var d := s()
	var outside: bool = ParkMap.home == null and m._ride == null
	_update_regulars(outside)
	_update_home_people()
	_check_appt()
	_daily_messages()
	if m._mode == "play":
		d["inv_t"] = float(d["inv_t"]) - 0.5
		if float(d["inv_t"]) <= 0.0:
			d["inv_t"] = randf_range(170.0, 300.0)
			_random_invite()
	# Bayram cocuklari: apartman onunde
	_kids_cd -= 0.5
	if outside and kids.is_empty() and _kids_cd <= 0.0 and bayram_name() != "" and m.clock >= 9.0 and m.clock < 19.5 \
			and ParkMap.zone == "" and m._owner_pos().distance_to(m.HOME_DOOR) < 28.0 and not _done("kids2"):
		spawn_kids()
	# Iftar sofrasi
	if is_ramazan() and m.clock >= 18.0 and m.clock < 22.0 and outside:
		if iftar.is_empty() and m._owner_pos().distance_to(_iftar_pos()) < 60.0:
			_build_iftar()
	elif not iftar.is_empty() and _seated.is_empty():
		_clear_iftar()


func _new_day() -> void:
	var d := s()
	d["done"].erase("kids_n")
	var c := cday()
	var b := bayram_name()
	if b != "" and bayram_day_no() == 1:
		msg("takvim", "%s başladı! Komşular bayramlaşmaya gelecek, çocuklar kapına şeker toplamaya gelir. Marketten %s almayı unutma." % [b, CANDY], "home")
	elif c == int(RAMAZAN[0]):
		msg("takvim", "Ramazan ayı başladı. Akşam 19:00 sularında iftar vakti; komşular parkta sofra kurabilir.")
	elif cday(day() + 1) == int(SEKER_BAYRAMI[0]) or cday(day() + 1) == int(KURBAN_BAYRAMI[0]):
		msg("takvim", "Yarın %s! Çocuklar için marketten %s al." % [bayram_name(day() + 1), CANDY])
	for id in BDAY:
		if int(BDAY[id]) == cday(day() + 1) and (not NEW_PEOPLE.has(id) or d["met"].has(id)):
			msg("takvim", "Yarın %s'in doğum günü! Marketten bir hediye ya da çiçek almak ister misin?" % _short(id))
	state.save_game()


func _daily_messages() -> void:
	if m._mode != "play" or ParkMap.zone != "":
		return
	var d := s()
	# Dogum gunu daveti (sabah)
	if m.clock >= 8.0 and m.clock < 18.0 and d["appt"].is_empty() and d["invite"].is_empty():
		for id in BDAY:
			if int(BDAY[id]) != cday() or _done("bday_" + id):
				continue
			if NEW_PEOPLE.has(id) and not d["met"].has(id):
				continue
			if friend(id) < 15:
				continue
			_mark("bday_" + id)
			_make_invite(id, "party", 19.0, day(),
				"Bugün benim doğum günüm! Akşam 19:00'da %s küçük bir parti veriyorum, gelir misin?" % ("parkta" if NEW_PEOPLE.has(id) else "apartmanın önünde"))
			return
	# Iftar daveti
	if is_ramazan() and m.clock >= 12.0 and m.clock < 18.5 and not _done("iftar_msg") and d["appt"].is_empty() and d["invite"].is_empty():
		_mark("iftar_msg")
		_make_invite("fatma", "iftar", 19.0, day(), "Kuzum, bu akşam komşularla parkta iftar sofrası kuruyoruz. 19:00'da gel, bir tabak da sana koyarız!")
		return
	# Bayram mesajlari
	if bayram_name() != "" and not _done("bayram_msg") and m.clock >= 8.0:
		_mark("bayram_msg")
		var lines := {"hasan": "Bayramın mübarek olsun evladım! Kapı önüne çocuklar şekere gelir, hazırlıklı ol.",
			"ayse": "Bayramın kutlu olsun yavrum, öp beni bir ara. Paşa da bayramlaşmak istiyor.",
			"mert": "İyi bayramlar komşu! Akşam bizde baklava var, gel.",
			"fatma": "Bayramınız mübarek olsun kuzum, sizi de bekleriz!"}
		var ids: Array = lines.keys()
		var id: String = ids[day() % ids.size()]
		msg(id, lines[id], "home", ["Bayramınız mübarek olsun!"])


# ---------------------------------------------------------------- davetler

func _pick_kind(id: String) -> String:
	var opts: Array = ["cafe"]
	if id in CANDIDATES and (partner() == id or (partner() == "" and friend(id) >= 45)):
		opts = ["dinner", "walk", "cafe"]
		if m.boat.built:
			opts.append("boat")
	elif id in ["mert", "selin", "deniz"]:
		opts.append("walk")
	return opts[randi() % opts.size()]


func _slot(kind: String) -> Array:
	var h := float(ceili(m.clock) + 1)
	var dd := day()
	if kind == "dinner":
		h = maxf(h, 20.0)
	if h > 21.0:
		dd += 1
		h = {"cafe": 11.0, "walk": 17.0, "boat": 15.0, "dinner": 20.0}.get(kind, 12.0)
	h = maxf(h, 9.0)
	return [h, dd]


func _invite_text(kind: String, h: float, dd: int) -> String:
	var when := ("%02d:00" % int(h)) if dd == day() else ("yarın %02d:00" % int(h))
	match kind:
		"cafe":
			return "Kafede buluşalım mı? %s Çınaraltı" % when
		"dinner":
			return "Akşam yemeğine çıkalım mı? %s Çınaraltı'nda, mangal ve çay benden!" % when
		"walk":
			return "Hava çok güzel, %s parkta yürüyüşe çıkalım mı? %s de gelsin!" % [when, _pet_name()]
		"boat":
			return "%s göl iskelesinde buluşup tekne turuna çıkalım mı?" % when.capitalize()
	return "Buluşalım mı? %s" % when


func _make_invite(id: String, kind: String, h: float, dd: int, text := "") -> void:
	if kind in ["cafe", "dinner"] and not tea_ok():
		kind = "walk"
	if kind == "boat" and not m.boat.built:
		kind = "walk"
	var p := place_of(kind, id)
	var inv := {"id": id, "kind": kind, "hour": h, "day": dd, "x": p.x, "z": p.y}
	s()["invite"] = inv
	msg(id, text if text != "" else _invite_text(kind, h, dd), "soc:accept", ["Bugün olmaz, kusura bakma."])


func _random_invite() -> void:
	var d := s()
	if not d["appt"].is_empty() or not d["invite"].is_empty() or not guest.is_empty() or ParkMap.zone != "":
		return
	var pool: Array = []
	for id in friends_list():
		if friend(id) >= 22:
			pool.append(id)
			if id == partner():
				pool.append(id)
				pool.append(id)
	if pool.is_empty():
		return
	var id: String = pool[randi() % pool.size()]
	var kind := _pick_kind(id)
	var sl := _slot(kind)
	_make_invite(id, kind, float(sl[0]), int(sl[1]))


## Oyuncu davet eder (Sosyal uygulamasi ya da sohbetten).
func invite_by_player(id: String, kind := "cafe") -> void:
	var d := s()
	m.ui.close_modal()
	if not d["appt"].is_empty():
		m.ui.toast("Zaten bir buluşman var: %s, %02d:00." % [_short(d["appt"]["id"]), int(d["appt"]["hour"])])
		return
	if friend(id) < 20 and id != partner():
		m.ui.toast("%s seni henüz pek tanımıyor. Önce biraz sohbet et." % _short(id))
		return
	var sl := _slot(kind)
	_make_invite(id, kind, float(sl[0]), int(sl[1]), "")
	accept()
	m.ui.toast("%s kabul etti: %s, %s %02d:00" % [_short(id), place_label(kind, id), "bugün" if int(sl[1]) == day() else "yarın", int(sl[0])])


func act_label(act: String) -> String:
	var inv: Dictionary = s()["invite"]
	if act == "soc:accept":
		if inv.is_empty():
			return "Davet geçerliliğini yitirdi"
		return "Daveti Kabul Et · %02d:00" % int(inv["hour"])
	return "Aç"


func do_act(act: String) -> void:
	if act == "soc:accept":
		if s()["invite"].is_empty():
			m.ui.toast("Bu davetin süresi geçti.")
			return
		accept()


func accept() -> void:
	var d := s()
	var inv: Dictionary = d["invite"]
	if inv.is_empty():
		return
	d["appt"] = inv.duplicate()
	d["invite"] = {}
	var id: String = inv["id"]
	var th: Dictionary = m.neighbors._md().get(id, {})
	if not th.is_empty():
		var clk: String = m.ui.clock_label.text if m.ui.clock_label else ""
		th["items"].append({"me": true, "t": "Gelirim, görüşürüz!", "c": clk, "act": "", "r": []})
	var p := Vector2(float(inv["x"]), float(inv["z"]))
	m._set_nav(p, _short(id))
	m.ui.toast("Buluşma: %s · %s %02d:00. Konum haritada işaretli." % [_short(id), place_label(inv["kind"], id), int(inv["hour"])])
	state.save_game()


func _check_appt() -> void:
	var d := s()
	# Kabul edilmeyen davet zamani gecince silinir
	var inv: Dictionary = d["invite"]
	if not inv.is_empty() and (day() > int(inv["day"]) or (day() == int(inv["day"]) and m.clock > float(inv["hour"]) + 1.0)):
		d["invite"] = {}
	var ap: Dictionary = d["appt"]
	if ap.is_empty() or not guest.is_empty():
		return
	var h := float(ap["hour"])
	var late: bool = day() > int(ap["day"]) or (day() == int(ap["day"]) and m.clock > h + 2.0)
	if late:
		var id: String = ap["id"]
		d["appt"] = {}
		if ap["kind"] != "iftar":
			msg(id, "Seni bekledim ama gelmedin… Bir dahaki sefere haber ver bari.", "", ["Çok özür dilerim!"])
			add_friend(id, -4, false)
		state.save_game()
		return
	if day() != int(ap["day"]) or m.clock < h - 0.5:
		return
	if ParkMap.home != null or m._ride != null:
		return
	var p := Vector2(float(ap["x"]), float(ap["z"]))
	if m._owner_pos().distance_to(p) < 45.0:
		_spawn_guest(ap)


# ---------------------------------------------------------------- bulusma

func _table_free(t: int, skip := -1) -> Array:
	var out: Array = []
	var sts: Array = m.street_food.tea["stools"]
	for i in sts.size():
		if int(sts[i]["table"]) == t and not sts[i]["busy"] and i != skip:
			out.append(i)
	return out


func _seat_model_at_stool(v: Node3D, i: int) -> void:
	var tea: Dictionary = m.street_food.tea
	var st: Dictionary = tea["stools"][i]
	if v.get_parent() != tea["root"]:
		if v.get_parent():
			v.get_parent().remove_child(v)
		tea["root"].add_child(v)
	v.seated = true
	v.position = Vector3(st["local"].x, float(st["h"]) + m.street_food._seat_y, st["local"].y)
	v.rotation = Vector3(0, float(st["yaw_l"]), 0)
	st["busy"] = true


func _spawn_guest(ap: Dictionary) -> void:
	var id: String = ap["id"]
	var kind: String = ap["kind"]
	if kind == "iftar":
		# Iftarda konuk yok: sofra kendisi kurulur (_slow_update)
		s()["appt"] = {}
		if iftar.is_empty():
			_build_iftar()
		m.ui.toast("İftar sofrası kuruldu! Boş yere otur. [F]")
		return
	guest = {"id": id, "kind": kind, "rounds": 0, "t": 0.0, "walked": 0.0, "started": false, "deco": null}
	var v: PersonModel = null
	if kind in ["cafe", "dinner"] and tea_ok():
		var tea: Dictionary = m.street_food.tea
		var stool := -1
		if regulars.has(id) and regulars[id].visible:
			v = regulars[id]
			regulars.erase(id)
			stool = int(NEW_PEOPLE[id][7])
		var table := -1
		if stool >= 0:
			table = int(tea["stools"][stool]["table"])
			tea["stools"][stool]["busy"] = false
			if _table_free(table, stool).is_empty():
				stool = -1
		if stool < 0:
			for t in tea["tables"].size():
				if _table_free(t).size() >= 2:
					table = t
					stool = int(_table_free(t)[0])
					break
		if stool < 0:
			table = 0
			stool = 0
		if v == null:
			v = _person_for(id)
		_seat_model_at_stool(v, stool)
		guest["stool"] = stool
		guest["table"] = table
		guest["model"] = v
		m._say(v, "Buradayım! Gel otur.")
		v.act("wave", 1.2)
		m.ui.toast("%s Çınaraltı'nda, masada seni bekliyor. Yanına git ve otur. [F]" % _short(id))
	else:
		var p := Vector2(float(ap["x"]), float(ap["z"]))
		var o: Vector2 = m._owner_pos()
		var at := p
		if o.distance_to(p) < 6.0:
			at = o + (p - o).normalized() * 2.5 if o.distance_to(p) > 0.5 else o + Vector2(1.8, 0.8)
		for k in 12:
			if m.world.is_free(at, 0.4):
				break
			at = p + Vector2.from_angle(k * 0.7) * (1.5 + k * 0.3)
		v = _person_for(id)
		m.add_child(v)
		v.position = Vector3(at.x, ParkMap.walk_height(at), at.y)
		_face(v, o)
		guest["model"] = v
		guest["pos"] = at
		if kind == "party":
			guest["deco"] = _party_table(at + (at - o).normalized() * 1.4, o)
			m._say(v, "Geldin! Pasta seni bekliyordu.")
			m.ui.toast("%s'in doğum günü partisi! Yanına git. [F]" % _short(id))
		else:
			m._say(v, "Selam! Hazır mısın?")
			m.ui.toast("%s geldi, seni bekliyor. Yanına git. [F]" % _short(id))
		v.act("wave", 1.2)
	m._sfx("tik", -4.0, 1.5)
	m._update_context()


func _guest_pos() -> Vector2:
	if guest.is_empty():
		return Vector2.INF
	var v: Node3D = guest["model"] if is_instance_valid(guest["model"]) else null      # silinmis dugum turlu degiskene atanamaz
	return Vector2(v.global_position.x, v.global_position.z)


func _player_at_guest_table() -> bool:
	if not guest.has("table") or not m.street_food.is_seated():
		return false
	var st: Dictionary = m.street_food.tea["stools"][m.street_food.seat["i"]]
	return int(st["table"]) == int(guest["table"])


func _update_guest(dt: float) -> void:
	if guest.is_empty():
		return
	var v: Node3D = guest["model"] if is_instance_valid(guest["model"]) else null      # silinmis dugum turlu degiskene atanamaz
	if not is_instance_valid(v):
		guest = {}
		return
	guest["t"] = float(guest["t"]) + dt
	var o: Vector2 = m._owner_pos()
	var gp := _guest_pos()
	if guest["kind"] == "boat" and guest.get("boarded", false):
		if m.boat.mode == "tour":
			_boat_seen = true
		elif _boat_seen:
			_boat_seen = false
			v.visible = true
			var off: Vector2 = o + Vector2(1.2, 0.6)
			v.global_position = Vector3(off.x, ParkMap.walk_height(off), off.y)
			_face(v, o)
			finish_meet(true, "Tekne turu harikaydı! Martılar, göl, gün batımı…")
		return
	# Oyuncu uzaklasirsa bulusma bozulur
	if ParkMap.home == null and o.distance_to(gp) > 70.0 and not (guest["kind"] == "walk" and guest["started"]):
		finish_meet(false, "")
		return
	if guest["kind"] == "walk" and guest["started"]:
		# Oyuncunun yaninda yurur
		var fw := Vector2(-sin(m.owner_node.rotation.y), -cos(m.owner_node.rotation.y))
		var want := o - fw * 0.6 + Vector2(-fw.y, fw.x) * 1.1
		var d := want - gp
		var spd := 0.0
		if d.length() > 0.25:
			spd = clampf(d.length() * 1.6, 0.0, 5.0)
			var np := gp + d.normalized() * minf(spd * dt, d.length())
			if d.length() > 25.0:
				np = want
			v.global_position = Vector3(np.x, ParkMap.walk_height(np), np.y)
			v.global_rotation.y = lerp_angle(v.global_rotation.y, atan2(-d.x, -d.y), minf(1.0, dt * 6.0))
			guest["walked"] = float(guest["walked"]) + minf(spd * dt, d.length())
		v.speed = spd
		var w: float = guest["walked"]
		var lines := ["Şu ağaçlara bak, ne güzel yeşermiş.", "%s çok mutlu görünüyor!", "Seninle yürümek iyi geliyor.", "Bir dahakine simit alalım."]
		var step := int(w / 45.0)
		if step > int(guest.get("said", 0)) and step <= lines.size():
			guest["said"] = step
			m._say(v, _fmt(lines[step - 1]))
		if w >= 180.0:
			v.speed = 0.0
			finish_meet(true, "Ne güzel bir yürüyüştü, kafam dinlendi!")
		return
	# Bekleyen konuk oyuncuya doner
	if not v.seated and o.distance_to(gp) < 10.0:
		var d2 := o - gp
		v.global_rotation.y = lerp_angle(v.global_rotation.y, atan2(-d2.x, -d2.y), minf(1.0, dt * 4.0))
	if v.seated and _player_at_guest_table() and not v.is_acting() and randf() < dt * 0.1:
		v.act("sip", 1.8)
	# Cok uzun beklerse gider
	if float(guest["t"]) > 300.0 and int(guest["rounds"]) == 0 and not _player_at_guest_table():
		finish_meet(false, "")


## Sohbet paneli: arkadas bir sey soyler, oyuncu cevap secer.
func open_chat() -> void:
	if guest.is_empty():
		return
	var id: String = guest["id"]
	var ui: Node = m.ui
	var pool: Array = TOPICS.duplicate()
	if id == partner() or (id in CANDIDATES and friend(id) >= 55 and partner() == ""):
		pool.append_array(ROMANCE_TOPICS)
	var used: Array = guest.get("used", [])
	var idx := randi() % pool.size()
	for k in pool.size():
		if not used.has((idx + k) % pool.size()):
			idx = (idx + k) % pool.size()
			break
	used.append(idx)
	guest["used"] = used
	var tp: Array = pool[idx]
	var body: VBoxContainer = ui._open_panel(pname(id).to_upper(), "\"%s\"\nDostluk: %d / 100 · %s" % [_fmt(tp[0]), friend(id), rel_text(id)])
	for ans in tp[1]:
		var a: Array = ans
		ui._panel_item(body, _fmt(a[0]), func(): _answer(a))
	_extra_options(body, id)
	ui._panel_item(body, "Buluşmayı Bitir", func():
		ui.close_modal()
		finish_meet(true, ""))
	ui._focus_first(body)


func _answer(a: Array) -> void:
	m.ui.close_modal()
	var v: Node3D = guest.get("model")
	if is_instance_valid(v):
		m._say(v, _fmt(a[2]).substr(0, 46))
		v.act("wave", 0.8)
	m.owner_model.act("wave", 0.6)
	guest["rounds"] = int(guest["rounds"]) + 1
	add_friend(guest["id"], int(a[1]))
	m.ui.toast("%s: \"%s\"" % [_short(guest["id"]), _fmt(a[2])])
	if int(a[1]) >= 5:
		m._sfx("mutlu", -12.0, 1.2)
	if int(guest["rounds"]) >= 3:
		get_tree().create_timer(1.6).timeout.connect(func(): if not guest.is_empty(): finish_meet(true, ""))
	m._update_context()


## Sevgililik ve davet secenekleri (sohbet panelinin altinda).
func _extra_options(body: VBoxContainer, id: String) -> void:
	var d := s()
	var ui: Node = m.ui
	if not id in CANDIDATES:
		return
	var dates := int(d["dates"].get(id, 0))
	if partner() == "" and friend(id) >= 75 and dates >= 3:
		ui._panel_item(body, "Benimle çıkar mısın?", func(): _ask_out(id))
	elif partner() == id and d["stage"] != "ev" and friend(id) >= 90 and dates >= 6:
		ui._panel_item(body, "Birlikte yaşayalım mı?", func(): _move_in(id))


func _ask_out(id: String) -> void:
	m.ui.close_modal()
	var d := s()
	d["partner"] = id
	d["stage"] = "sevgili"
	add_friend(id, 8, false)
	var v: Node3D = guest.get("model")
	if is_instance_valid(v):
		m._say(v, "Evet! Ben de çok istiyordum.")
		v.act("wave", 1.4)
	m._sfx("mutlu", -6.0, 1.0)
	m.ui.toast("%s artık sevgilin! Randevular devam etsin: akşam yemeği, park, göl turu." % _short(id))
	state.save_game()


func _move_in(id: String) -> void:
	m.ui.close_modal()
	s()["stage"] = "ev"
	var v: Node3D = guest.get("model")
	if is_instance_valid(v):
		m._say(v, "Evet! Valizimi hazırlıyorum!")
	m._sfx("mutlu", -6.0, 1.0)
	m.ui.toast("%s seninle birlikte yaşamaya başladı. Eve girince onu salonda bulacaksın." % _short(id))
	state.save_game()


func finish_meet(ok: bool, line: String) -> void:
	if guest.is_empty():
		return
	var id: String = guest["id"]
	var kind: String = guest["kind"]
	var v: Node3D = guest.get("model")
	var d := s()
	d["appt"] = {}
	if ok:
		var bonus := 4 + int(guest["rounds"])
		if kind in DATE_KINDS and id in CANDIDATES:
			d["dates"][id] = int(d["dates"].get(id, 0)) + 1
			bonus += 3
		add_friend(id, bonus, false)
		state.count("friend")
		var l: String = line if line != "" else ["Çok güzel vakit geçirdik, yine yapalım!", "İyi ki geldin, kendime geldim.", "Görüşürüz, kendine iyi bak!"][randi() % 3]
		if is_instance_valid(v):
			m._say(v, l.substr(0, 46))
		var extra := ""
		if kind in DATE_KINDS and id in CANDIDATES:
			extra = " · Randevu: %d" % int(d["dates"][id])
		m.ui.toast("%s: \"%s\" Dostluk +%d → %d%s" % [_short(id), l, bonus, friend(id), extra])
		m._sfx("mutlu", -10.0, 1.1)
		get_tree().create_timer(20.0).timeout.connect(func():
			if NEW_PEOPLE.has(id) or friend(id) >= 30:
				msg(id, ["Bugün çok güzeldi, teşekkürler!", "Yine buluşalım, haber ver!", "Eve vardım, iyi geceler!"][randi() % 3], "", ["Ben de çok eğlendim!"]))
	else:
		add_friend(id, -2, false)
		m.ui.toast("%s gitti. Buluşma yarım kaldı." % _short(id))
	# Konugu kaldir
	if guest.has("stool") and m.street_food.tea.size() > 0:
		m.street_food.tea["stools"][int(guest["stool"])]["busy"] = false
	var deco: Variant = guest.get("deco")
	if deco is Node3D and is_instance_valid(deco):
		var dn: Node3D = deco
		get_tree().create_timer(4.0).timeout.connect(func(): if is_instance_valid(dn): dn.queue_free())
	if is_instance_valid(v):
		get_tree().create_timer(3.0).timeout.connect(func(): if is_instance_valid(v): v.queue_free())
	_reg_block[id] = 90.0
	guest = {}
	state.save_game()
	m._update_context()


func _dinner_food(t: int) -> Node3D:
	var tea: Dictionary = m.street_food.tea
	var tl: Vector2 = tea["tables"][t]
	var r := Kit.pivot(tea["root"], Vector3(tl.x, m.street_food._hl(tea["root"], tl) + 0.545, tl.y))
	var plate := Kit.mat("f4f1ea", 0.3)
	for k in 2:
		var o := Vector3(-0.14 + k * 0.28, 0, 0.0)
		Kit.cyl(r, 0.1, 0.09, 0.015, o, plate, 18)
		for j in 4:
			Kit.capsule(r, 0.018, 0.08, o + Vector3(-0.04 + j * 0.027, 0.02, 0), Kit.mat("6b3a22", 0.7), Vector3(PI / 2, 0, 0))
		Kit.ball(r, 0.025, o + Vector3(0.05, 0.02, 0.04), Kit.mat("e0322b", 0.5))
	Kit.cyl(r, 0.04, 0.035, 0.08, Vector3(0, 0.04, 0.18), Kit.mat("f6e7b0", 0.4), 10)
	var flame := Kit.ball(r, 0.012, Vector3(0, 0.09, 0.18), Kit.glow("ffb347", 3.0))
	flame.scale = Vector3(1, 1.6, 1)
	return r


func _party_table(p: Vector2, face: Vector2) -> Node3D:
	var r := Node3D.new()
	m.add_child(r)
	r.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
	var d := face - p
	r.rotation.y = atan2(-d.x, -d.y)
	Kit.box(r, Vector3(1.2, 0.04, 0.7), Vector3(0, 0.74, 0), Kit.mat("f4f4f0", 0.7))
	for sx in [-0.55, 0.55]:
		for sz in [-0.3, 0.3]:
			Kit.box(r, Vector3(0.04, 0.74, 0.04), Vector3(sx, 0.37, sz), Kit.mat("8a5a32", 0.7))
	# Pasta ve mumlar
	Kit.cyl(r, 0.18, 0.18, 0.12, Vector3(0, 0.82, 0), Kit.mat("f7d6e0", 0.6), 20)
	Kit.cyl(r, 0.185, 0.185, 0.02, Vector3(0, 0.885, 0), Kit.mat("e86a8a", 0.5), 20)
	for k in 5:
		var a := k * TAU / 5.0
		Kit.cyl(r, 0.008, 0.008, 0.07, Vector3(cos(a) * 0.1, 0.93, sin(a) * 0.1), Kit.mat(["2f80ff", "f2c230", "34a853", "e8453c", "8e5cd9"][k], 0.5), 6)
		Kit.ball(r, 0.01, Vector3(cos(a) * 0.1, 0.975, sin(a) * 0.1), Kit.glow("ffb347", 3.0), Vector3(1, 1.6, 1), 6)
	# Bardaklar ve balonlar
	for k in 4:
		Kit.cyl(r, 0.03, 0.025, 0.1, Vector3(-0.45 + k * 0.3, 0.81, 0.22), Kit.mat(["f2c230", "2f80ff", "e8453c", "34a853"][k], 0.4), 10)
	for k in 3:
		var bx := -0.7 + k * 0.7
		Kit.cyl(r, 0.004, 0.004, 1.2, Vector3(bx, 1.35, -0.34), Kit.mat("dddddd", 0.5), 4)
		Kit.ball(r, 0.16, Vector3(bx, 2.0, -0.34), Kit.mat(["e8453c", "f2c230", "2f80ff"][k], 0.25), Vector3(1, 1.2, 1), 12)
	return r


## Dogum gunu: hediye ver / kutla
func give_gift() -> void:
	if guest.is_empty():
		return
	var id: String = guest["id"]
	var v: Node3D = guest["model"] if is_instance_valid(guest["model"]) else null      # silinmis dugum turlu degiskene atanamaz
	var item := ""
	for g in GIFTS:
		if _bag_n(g) > 0:
			item = g
			break
	var bonus := 4
	if item != "":
		_bag_take(item)
		bonus = 14 if item == "Hediye Paketi" else 11
		m.owner_model.act("feed", 1.0)
		m._say(v, "Ay, ne güzel! Çok teşekkür ederim!")
		m.ui.toast("%s'e %s verdin. Çok sevindi!" % [_short(id), item])
	else:
		m.owner_model.act("wave", 1.0)
		m._say(v, "Geldin ya, en güzel hediye bu!")
		m.ui.toast("Hediye almadın ama geldiğine sevindi. (Marketten Hediye Paketi ya da Çiçek Buketi alabilirsin.)")
	guest["rounds"] = 3
	add_friend(id, bonus, false)
	var deco: Variant = guest.get("deco")
	get_tree().create_timer(2.0).timeout.connect(func():
		m.owner_model.act("eat", 2.0)
		if deco is Node3D and is_instance_valid(deco):
			m._say(deco, "İyi ki doğdun!")
		m.needs.add("hunger", 15.0)
		m.ui.toast("Pastadan bir dilim yedin. İyi ki doğdun %s!" % _short(id)))
	get_tree().create_timer(5.0).timeout.connect(func(): finish_meet(true, "Bu doğum gününü hiç unutmayacağım!"))


func start_walk() -> void:
	guest["started"] = true
	var v: Node3D = guest["model"] if is_instance_valid(guest["model"]) else null      # silinmis dugum turlu degiskene atanamaz
	m._say(v, "Hadi yürüyelim! Sen önden git.")
	m.ui.toast("%s ile parkta yürü: 180 metre birlikte yürüyün." % _short(guest["id"]))
	for kind in m.agents:
		m.agents[kind].command("come")


func start_boat() -> void:
	if not m.boat.built:
		return
	var v: Node3D = guest["model"] if is_instance_valid(guest["model"]) else null      # silinmis dugum turlu degiskene atanamaz
	guest["boarded"] = true
	_boat_seen = false
	v.visible = false
	m.boat.start_tour(true)
	m.ui.toast("%s ile birlikte tekneye bindiniz. İyi seyirler!" % _short(guest["id"]))


func sit_with_guest() -> void:
	if guest.is_empty() or not guest.has("table"):
		return
	var free := _table_free(int(guest["table"]))
	if free.is_empty():
		m.ui.toast("Masada boş tabure yok.")
		return
	var o: Vector2 = m._owner_pos()
	var sts: Array = m.street_food.tea["stools"]
	var best: int = free[0]
	for i in free:
		if o.distance_to(sts[i]["pos"]) < o.distance_to(sts[best]["pos"]):
			best = i
	if m.street_food.is_seated():
		m.street_food.stand_up()
	m._place_owner(sts[best]["pos"])
	m.street_food.sit(best, guest["kind"] == "cafe")
	if guest["kind"] == "dinner" and guest.get("deco") == null:
		guest["deco"] = _dinner_food(int(guest["table"]))
		if state.spend(40):
			m.ui.toast("Akşam yemeği geldi: ızgara köfte ve salata · 40 ₺. Afiyet olsun!")
		else:
			m.ui.toast("Paran yetmedi, %s bu sefer ısmarladı. Afiyet olsun!" % _short(guest["id"]))
		m.needs.add("hunger", 35.0)
	m._say(guest["model"], "Ne iyi ettin de geldin!")


# ---------------------------------------------------------------- mudavimler (Selin, Deniz)

func _update_regulars(outside: bool) -> void:
	if not tea_ok() or ParkMap.zone != "":
		return
	var tea: Dictionary = m.street_food.tea
	var near: bool = outside and m._owner_pos().distance_to(tea["pos"]) < 120.0
	for id in NEW_PEOPLE:
		var a: Array = NEW_PEOPLE[id]
		_reg_block[id] = maxf(float(_reg_block.get(id, 0.0)) - 0.5, 0.0)
		var want: bool = near and m.clock >= float(a[5]) and m.clock < float(a[6]) and guest.get("id", "") != id and float(_reg_block[id]) <= 0.0
		if m.weather and m.weather.kind in ["saganak", "kar"]:
			want = false
		var stool := int(a[7])
		var st: Dictionary = tea["stools"][stool]
		if regulars.has(id):
			var v: Node3D = regulars[id]
			if not want:
				v.queue_free()
				regulars.erase(id)
				st["busy"] = false
		elif want and not st["busy"]:
			var v2 := _person_for(id)
			_seat_model_at_stool(v2, stool)
			regulars[id] = v2


func talk_regular(id: String) -> void:
	var d := s()
	var ui: Node = m.ui
	var first: bool = not d["met"].has(id)
	if first:
		d["met"][id] = day()
		m.ui.toast("%s ile tanıştın! Artık Sosyal uygulamasında arkadaş listende." % pname(id))
	var v: Node3D = regulars.get(id)
	if is_instance_valid(v):
		m._say(v, "Merhaba!" if first else "Aa, sen! Gel otur.")
		v.act("wave", 1.0)
	var greet: String = "Merhaba, ben %s. Buraya her gün çay içmeye gelirim. Sen de mi buralısın?" % pname(id) if first \
		else ["Ne var ne yok?", "Yine mi sen, ne güzel!", "Çaylar benden mi senden mi?"][day() % 3]
	var body: VBoxContainer = ui._open_panel(pname(id).to_upper(), "\"%s\"\nDostluk: %d / 100 · %s" % [greet, friend(id), rel_text(id)])
	var tp: Array = TOPICS[(day() + friend(id)) % TOPICS.size()]
	ui._panel_item(body, "Sohbet et: \"%s\"" % _fmt(tp[1][0][0]), func():
		ui.close_modal()
		if is_instance_valid(v):
			m._say(v, _fmt(tp[1][0][2]).substr(0, 46))
		if not _done("chat_" + id):
			_mark("chat_" + id)
			add_friend(id, 5)
		else:
			m.ui.toast("%s: \"%s\"" % [pname(id), _fmt(tp[1][0][2])])
		state.save_game())
	if friend(id) >= 20:
		ui._panel_item(body, "Buluşalım mı? (Çınaraltı)", func(): invite_by_player(id, "cafe"))
	if id in CANDIDATES and (partner() == id or (partner() == "" and friend(id) >= 45)):
		ui._panel_item(body, "Akşam yemeğine çıkalım mı?", func(): invite_by_player(id, "dinner"))
	ui._panel_item(body, "Hoşça kal", func(): ui.close_modal())
	ui._focus_first(body)
	state.save_game()


## Komsu diyalogunun altina eklenen secenekler (neighbors.talk cagirir).
func neighbor_options(id: String, body: VBoxContainer) -> void:
	var ui: Node = m.ui
	if bayram_name() != "" and not _done("bayramlas_" + id):
		ui._panel_item(body, "Bayramlaş (elini öp)", func():
			ui.close_modal()
			_mark("bayramlas_" + id)
			m.owner_model.act("feed", 1.0)
			add_friend(id, 6)
			var pd: Dictionary = m.neighbors.people.get(id, {})
			if not pd.is_empty():
				m._say(pd["node"], "Bayramın mübarek olsun, nice bayramlara!")
			if id in ["ayse", "fatma", "hasan"]:
				state.d["coins"] = int(state.d["coins"]) + 10
				state.changed.emit()
				m.ui.toast("%s sana bayram harçlığı verdi: +10 ₺" % _short(id))
			state.save_game())
	if friend(id) >= 20 and s()["appt"].is_empty():
		ui._panel_item(body, "Çınaraltı'nda çay içelim mi?", func(): invite_by_player(id, "cafe"))


# ---------------------------------------------------------------- bayram cocuklari

func spawn_kids() -> void:
	var o: Vector2 = m._owner_pos()
	var out: Vector2 = m.HOME_DOOR_OUT
	var base: Vector2 = o + out * 9.0
	if not m.world.is_free(base, 0.5):
		base = o + Vector2(-out.y, out.x) * 9.0
	for i in 3:
		var kind: String = ["kiz", "erkek", "kiz"][i]
		var v := _person("kadin" if kind == "kiz" else "erkek", ["f26fa0", "2f80ff", "f2c230"][i], ["3b4a7a", "2b2f38", "5a3a6a"][i])
		v.scale = Vector3.ONE * 0.6
		m.add_child(v)
		var p: Vector2 = base + Vector2(i * 0.9 - 0.9, (i % 2) * 0.8)
		v.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
		kids.append({"model": v, "done": false, "t": 0.0, "slot": i})
	var dn := int(s()["done"].get("kids_n", 0)) + 1
	s()["done"]["kids_n"] = dn
	if dn >= 2:
		_mark("kids2")
	_kids_cd = 60.0
	m._say(kids[0]["model"], "Şeker toplamaya geldik!")
	m.ui.toast("Bayram! Mahallenin çocukları şeker toplamaya geldi. Çantanda %d %s var. [F]" % [_bag_n(CANDY), CANDY])


func _update_kids(dt: float) -> void:
	if kids.is_empty():
		return
	var o: Vector2 = m._owner_pos()
	var all_gone := true
	for k in kids:
		var v: Node3D = k["model"] if is_instance_valid(k["model"]) else null      # silinmis dugum turlu degiskene atanamaz
		if not is_instance_valid(v):
			continue
		all_gone = false
		k["t"] = float(k["t"]) + dt
		var p := Vector2(v.position.x, v.position.z)
		var want: Vector2
		if k["done"]:
			want = p + (p - o).normalized() * 5.0
		else:
			want = o + Vector2.from_angle(float(k["slot"]) * 1.1 + 0.6) * 1.3
		var d := want - p
		var spd := 0.0
		if d.length() > 0.3:
			spd = 3.0 if k["done"] else minf(2.6, d.length() * 1.5)
			var np := p + d.normalized() * minf(spd * dt, d.length())
			v.position = Vector3(np.x, ParkMap.walk_height(np), np.y)
			v.rotation.y = lerp_angle(v.rotation.y, atan2(-d.x, -d.y), minf(1.0, dt * 6.0))
		elif not k["done"]:
			var fo := o - p
			v.rotation.y = lerp_angle(v.rotation.y, atan2(-fo.x, -fo.y), minf(1.0, dt * 6.0))
		v.speed = spd
		if k["done"] and float(k["t"]) > 4.0:
			v.queue_free()
		elif not k["done"] and (float(k["t"]) > 150.0 or o.distance_to(p) > 40.0):
			k["done"] = true
			k["t"] = 0.0
	if all_gone:
		kids.clear()
		m._update_context()


func _waiting_kid() -> Dictionary:
	var o: Vector2 = m._owner_pos()
	for k in kids:
		var v: Node3D = k["model"] if is_instance_valid(k["model"]) else null      # silinmis dugum turlu degiskene atanamaz
		if is_instance_valid(v) and not k["done"] and o.distance_to(Vector2(v.position.x, v.position.z)) < 3.0:
			return k
	return {}


func give_candy() -> void:
	var k := _waiting_kid()
	if k.is_empty():
		return
	var v: Node3D = k["model"]
	if not _bag_take(CANDY):
		m._say(v, "Şeker yok mu? Olsun, iyi bayramlar!")
		m.ui.toast("Çantanda %s yok. Marketten alabilirsin (4 ₺)." % CANDY)
		k["done"] = true
		k["t"] = 0.0
		m._update_context()
		return
	m.owner_model.act("feed", 1.0)
	v.act("wave", 1.2)
	m._say(v, ["Bayramınız mübarek olsun!", "Teşekkürler abla, abi!", "Yaşasın, şeker!"][randi() % 3])
	m._sfx("mutlu", -10.0, 1.6)
	k["done"] = true
	k["t"] = 0.0
	state.count("bayram")
	for id in m.neighbors.PEOPLE:
		m.neighbors._add_friend(id, 1)
	var left := 0
	for q in kids:
		if not q["done"]:
			left += 1
	m.ui.toast("Çocuğa %s verdin. Komşular seni takdir etti. (Kalan çocuk: %d · Çanta: %d)" % [CANDY, left, _bag_n(CANDY)])
	state.save_game()
	m._update_context()


# ---------------------------------------------------------------- iftar

func _build_iftar() -> void:
	if not iftar.is_empty():
		return
	var p := _iftar_pos()
	var r := Node3D.new()
	r.name = "IftarSofrasi"
	m.add_child(r)
	var gy := ParkMap.walk_height(p)
	r.position = Vector3(p.x, gy, p.y)
	r.rotation.y = -_iftar_yaw
	var ax := Vector2.from_angle(_iftar_yaw)
	var sd := Vector2(-ax.y, ax.x)
	var cloth := Kit.mat("f6f3ea", 0.8)
	var wood := Kit.mat("8a5a32", 0.75)
	# Uzun masa (yerel x ekseni boyunca)
	Kit.box(r, Vector3(6.4, 0.05, 0.95), Vector3(0, 0.56, 0), wood)
	Kit.box(r, Vector3(6.5, 0.01, 1.05), Vector3(0, 0.59, 0), cloth)
	Kit.box(r, Vector3(6.3, 0.012, 0.22), Vector3(0, 0.6, 0), Kit.mat("b8433a", 0.8))
	for x in [-3.0, -1.0, 1.0, 3.0]:
		Kit.box(r, Vector3(0.06, 0.56, 0.7), Vector3(x, 0.28, 0), wood)
	for sz in [-0.85, 0.85]:
		Kit.box(r, Vector3(6.2, 0.05, 0.32), Vector3(0, 0.42, sz), wood)
		for x in [-2.8, 0.0, 2.8]:
			Kit.box(r, Vector3(0.05, 0.42, 0.26), Vector3(x, 0.21, sz), wood)
	var plate := Kit.mat("ffffff", 0.3)
	var soup := Kit.mat("d9822b", 0.5)
	var seats: Array = []
	for i in 10:
		var lx := -2.6 + (i % 5) * 1.3
		var lz := -0.85 if i < 5 else 0.85
		var pz := -0.28 if i < 5 else 0.28
		Kit.cyl(r, 0.13, 0.11, 0.02, Vector3(lx, 0.61, pz), plate, 18)
		Kit.cyl(r, 0.07, 0.05, 0.05, Vector3(lx, 0.645, pz), Kit.mat("f4f1ea", 0.3), 14)
		Kit.cyl(r, 0.06, 0.06, 0.005, Vector3(lx, 0.668, pz), soup, 14)
		Kit.cyl(r, 0.028, 0.024, 0.09, Vector3(lx + 0.18, 0.645, pz), Kit.mat("e8f2f8", 0.15), 10)
		var wp := p + ax * lx + sd * lz
		seats.append({"pos": wp, "yaw": atan2(-(-sd.x * signf(lz)), -(-sd.y * signf(lz))), "lx": lx, "lz": lz})
	# Ortada pide, hurma, salata
	for x in [-1.95, 0.65]:
		Kit.box(r, Vector3(0.5, 0.04, 0.22), Vector3(x, 0.62, 0), Kit.mat("c98a3a", 0.85))
		for k in 5:
			Kit.ball(r, 0.012, Vector3(x - 0.18 + k * 0.09, 0.645, 0.02), Kit.mat("2a1a10", 0.7), Vector3.ONE, 4)
	for x in [-0.65, 1.95]:
		Kit.cyl(r, 0.12, 0.08, 0.06, Vector3(x, 0.63, 0), Kit.mat("3f7a3a", 0.6), 14)
		for k in 6:
			Kit.ball(r, 0.022, Vector3(x - 0.06 + (k % 3) * 0.06, 0.67, -0.03 + (k / 3) * 0.06), Kit.mat("e0322b" if k % 2 else "5a3418", 0.5), Vector3(1.0, 0.7, 1.4), 6)
	# Fenerler ve isik
	var lamp_m := Kit.glow("ffcf7a", 2.5)
	for x in [-3.3, 3.3]:
		Kit.cyl(r, 0.03, 0.03, 2.2, Vector3(x, 1.1, -0.65), Kit.mat("2b2b2b", 0.5), 6)
	Kit.cyl(r, 0.006, 0.006, 6.6, Vector3(0, 2.15, -0.65), Kit.mat("333333", 0.5), 4, Vector3(0, 0, PI / 2))
	for k in 9:
		Kit.ball(r, 0.07, Vector3(-3.0 + k * 0.75, 2.05, -0.65), lamp_m, Vector3(1, 1.3, 1), 8)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.0, 0)
	light.omni_range = 9.0
	light.light_color = Color("ffd59a")
	light.light_energy = 1.6
	r.add_child(light)
	# Komsular sofrada
	var people: Array = []
	var who: Array = ["hasan", "ayse", "mert", "fatma"]
	var seat_ix := [0, 6, 2, 8]
	for k in who.size():
		var st: Dictionary = seats[seat_ix[k]]
		var v := _person_for(who[k])
		r.add_child(v)
		v.seated = true
		v.position = Vector3(st["lx"], 0.01 + m.street_food._seat_y, st["lz"])
		v.rotation.y = 0.0 if st["lz"] > 0 else PI
		st["busy"] = true
		people.append(v)
	# Iki misafir daha
	for k in 2:
		var st2: Dictionary = seats[[4, 9][k]]
		var v2 := _person(["kadin", "erkek"][k], ["c98a3a", "5a6b8a"][k], ["3a3a46", "2b2f38"][k])
		r.add_child(v2)
		v2.seated = true
		v2.position = Vector3(st2["lx"], 0.01 + m.street_food._seat_y, st2["lz"])
		v2.rotation.y = 0.0 if st2["lz"] > 0 else PI
		st2["busy"] = true
		people.append(v2)
	iftar = {"root": r, "pos": p, "seats": seats, "people": people, "light": light, "ezan": false}
	print("IFTAR sofra ", p)


func _clear_iftar() -> void:
	if iftar.is_empty():
		return
	if is_instance_valid(iftar["root"]):
		iftar["root"].queue_free()
	iftar = {}


func _iftar_free_seat() -> int:
	if iftar.is_empty():
		return -1
	var o: Vector2 = m._owner_pos()
	var best := -1
	var bd := 3.5
	for i in iftar["seats"].size():
		var st: Dictionary = iftar["seats"][i]
		if st.get("busy", false):
			continue
		var dd := o.distance_to(st["pos"])
		if dd < bd:
			bd = dd
			best = i
	return best


func sit_iftar(i: int) -> void:
	if iftar.is_empty() or i < 0:
		return
	var st: Dictionary = iftar["seats"][i]
	st["busy"] = true
	m._moving = false
	m._queue.clear()
	m._steering = false
	m.owner_model.speed = 0.0
	m.owner_model.seated = true
	var r: Node3D = iftar["root"]
	_seated = {"i": i, "t": 0.0, "ate": false}
	_place_seated()
	var k := 0
	for kind in m.agents:
		var a: Node3D = m.agents[kind]
		a.command("lie")
		var ap: Vector2 = st["pos"] + (st["pos"] - Vector2(r.position.x, r.position.z)).normalized() * (1.0 + 0.6 * k)
		a.place(ap)
		k += 1
	m.ui._actions.visible = false
	var ezan: bool = m.clock >= 18.9
	if ezan:
		m.ui.toast("Ezan okundu, hayırlı iftarlar! Komşularla oruç açıyorsun.")
	else:
		m.ui.toast("Sofraya oturdun. Ezana az kaldı, birlikte bekliyorsunuz…")
	for v in iftar["people"]:
		if is_instance_valid(v):
			m._say(v, ["Hoş geldin!", "Buyur, otur evladım.", "Hayırlı iftarlar!"][randi() % 3])
			break
	m._update_context()


func _place_seated() -> void:
	var st: Dictionary = iftar["seats"][_seated["i"]]
	var r: Node3D = iftar["root"]
	var g: Vector3 = r.global_transform * Vector3(st["lx"], 0.01, st["lz"])
	m.owner_node.position = g
	m.owner_node.rotation = Vector3(0, r.rotation.y + (0.0 if st["lz"] > 0 else PI), 0)
	m.owner_model.position = Vector3(0, m.street_food._seat_y, 0)
	m._target = Vector2(g.x, g.z)


func _update_seated(dt: float) -> void:
	if _seated.is_empty():
		return
	if iftar.is_empty():
		_seated = {}
		m.owner_model.seated = false
		return
	_seated["t"] = float(_seated["t"]) + dt
	if (m._mode != "play" and m._mode != "debug") or (float(_seated["t"]) > 0.8 and (m.ui.stick.length() > 0.5 or m._moving)):
		stand_iftar()
		return
	_place_seated()
	# Ezan vakti gelince yemek
	if not _seated["ate"] and (m.clock >= 18.9 or float(_seated["t"]) > 25.0) and float(_seated["t"]) > 1.5:
		_seated["ate"] = true
		m.owner_model.act("eat", 2.4)
		m.needs.add("hunger", 60.0)
		m.needs.add("energy", 10.0)
		for v in iftar["people"]:
			if is_instance_valid(v):
				v.act("eat", 2.4)
		m._sfx("mutlu", -10.0, 1.0)
		m.ui.toast("Mercimek çorbası, pide, hurma… Afiyet olsun! Komşularla sohbet ettin.")
		for id in m.neighbors.PEOPLE:
			if not _done("iftar_" + id):
				_mark("iftar_" + id)
				m.neighbors._add_friend(id, 5)
		state.count("friend")
		state.save_game()
		m._update_context()
	elif _seated["ate"] and randf() < dt * 0.2:
		var v2: Node3D = iftar["people"][randi() % iftar["people"].size()]
		if is_instance_valid(v2):
			m._say(v2, ["Çorba çok güzel olmuş!", "Bir pide daha alır mısın?", "Allah kabul etsin.", "Hurma da var, buyur."][randi() % 4])


func stand_iftar() -> void:
	if _seated.is_empty():
		return
	var st: Dictionary = iftar["seats"][_seated["i"]] if not iftar.is_empty() else {}
	if not st.is_empty():
		st["busy"] = false
	var ate: bool = _seated["ate"]
	_seated = {}
	m.owner_model.seated = false
	m.owner_model.position = Vector3.ZERO
	if not st.is_empty():
		var r: Node3D = iftar["root"]
		var out: Vector2 = st["pos"] + (st["pos"] - Vector2(r.position.x, r.position.z)).normalized() * 0.6
		m.owner_node.position = Vector3(out.x, ParkMap.walk_height(out), out.y)
		m._target = out
	for kind in m.agents:
		m.agents[kind].command("come")
	m.ui._actions.visible = true
	if ate:
		m.ui.toast("Sofradan kalktın. Komşular: \"Yine bekleriz, hayırlı Ramazanlar!\" (Dostluk +5)")
	m._update_context()


# ---------------------------------------------------------------- ev: sevgili ve bayram misafirleri

func _update_home_people() -> void:
	var at_home: bool = m._home != null and ParkMap.home == m._home
	if not at_home:
		if not home_people.is_empty():
			for hp in home_people:
				if is_instance_valid(hp["model"]):
					hp["model"].queue_free()
			home_people.clear()
		return
	if not home_people.is_empty():
		return
	var want: Array = []
	if s()["stage"] == "ev" and partner() != "":
		want.append(partner())
	if bayram_name() != "" and not _done("home_guests") and m.clock >= 10.0 and m.clock < 21.0:
		want.append("ayse")
		want.append("fatma")
	if want.is_empty():
		return
	var h: Node3D = m._home
	var cands := [Vector2(5.4, 2.2), Vector2(4.6, 3.4), Vector2(5.8, 4.2), Vector2(3.6, 2.4), Vector2(4.2, 5.0), Vector2(6.2, 1.6), Vector2(3.0, 4.0)]
	var y: float = m.owner_node.position.y
	var used := 0
	for id in want:
		var v := _person_for(id)
		m.add_child(v)
		var wp: Vector2 = h.w2(cands[0])
		while used < cands.size():
			var c: Vector2 = h.w2(cands[used])
			used += 1
			if h.is_free(c, 0.35):
				wp = c
				break
		v.position = Vector3(wp.x, y, wp.y)
		_face(v, m._owner_pos())
		home_people.append({"id": id, "model": v})
	if want.has("ayse"):
		m.ui.toast("Bayram ziyareti! Ayşe Teyze ve Fatma Hanım bayramlaşmaya geldi. [F]")
		m._say(home_people[-1]["model"], "Bayramınız mübarek olsun!")
	elif not home_people.is_empty():
		m._say(home_people[0]["model"], ["Hoş geldin!", "Neredeydin? Seni özledim.", "Çay demledim!"][randi() % 3])


func _near_home_person() -> Dictionary:
	var o: Vector2 = m._owner_pos()
	for hp in home_people:
		var v: Node3D = hp["model"]
		if is_instance_valid(v) and o.distance_to(Vector2(v.position.x, v.position.z)) < 1.8:
			return hp
	return {}


func home_talk() -> void:
	var hp := _near_home_person()
	if hp.is_empty():
		return
	var id: String = hp["id"]
	var v: Node3D = hp["model"]
	_face(v, m._owner_pos())
	if id != partner():
		# Bayram misafirleri: ikram
		_mark("home_guests")
		m.owner_model.act("feed", 1.2)
		var gave := ""
		if _bag_take(CANDY):
			gave = " ve bayram şekeri"
		for g in home_people:
			if g["id"] != partner():
				add_friend(g["id"], 6, false)
				m._say(g["model"], "Eline sağlık, bayramın mübarek olsun!")
		m.ui.toast("Misafirlere çay%s ikram ettin. Ayşe Teyze ve Fatma Hanım çok memnun kaldı! (Dostluk +6)" % gave)
		var keep: Array = []
		for g in home_people:
			if g["id"] == partner():
				keep.append(g)
			else:
				var gm: Node3D = g["model"]
				get_tree().create_timer(4.0).timeout.connect(func(): if is_instance_valid(gm): gm.queue_free())
		home_people = keep if not keep.is_empty() else [{"id": "_gone", "model": null}]
		state.save_game()
		return
	var ui: Node = m.ui
	var body: VBoxContainer = ui._open_panel(pname(id).to_upper(), "Sevgilin · Birlikte yaşıyorsunuz\nDostluk: %d / 100" % friend(id))
	ui._panel_item(body, "Sarıl", func():
		ui.close_modal()
		m.owner_model.act("pet", 1.0)
		m._say(v, "İyi ki varsın.")
		m.needs.add("energy", 8.0)
		if not _done("hug"):
			_mark("hug")
			add_friend(id, 3))
	ui._panel_item(body, "Günün nasıl geçti?", func():
		ui.close_modal()
		var l: String = ["Yoğundu ama seni görünce geçti.", "%s ile parka gittik, çok eğlendi!", "Markette eski bir arkadaşa rastladım."][randi() % 3]
		m._say(v, _fmt(l).substr(0, 46))
		m.ui.toast("%s: \"%s\"" % [pname(id), _fmt(l)])
		if not _done("homechat"):
			_mark("homechat")
			add_friend(id, 3))
	ui._panel_item(body, "Dışarıda buluşalım (akşam yemeği)", func(): invite_by_player(id, "dinner"))
	ui._panel_item(body, "Kapat", func(): ui.close_modal())
	ui._focus_first(body)


# ---------------------------------------------------------------- baglam ve komutlar

func context() -> Array:
	_near = ""
	if busy():
		if _seated["ate"]:
			return ["Sofradan Kalk", "soc_iftar_up", "come"]
		return ["İftarı bekliyorsun…", "soc_iftar_up", "moon"]
	if m._ride != null:
		return []
	var o: Vector2 = m._owner_pos()
	if ParkMap.home != null:
		var hp := _near_home_person()
		if not hp.is_empty() and hp["model"] != null:
			return ["Sevgilinle Sohbet Et" if hp["id"] == partner() else "Misafirlere İkram Et", "soc_home", "smile"]
		return []
	if not guest.is_empty():
		var id: String = guest["id"]
		var gp := _guest_pos()
		match String(guest["kind"]):
			"cafe", "dinner":
				if _player_at_guest_table():
					return ["%s ile Sohbet Et" % _short(id), "soc_chat", "smile"]
				if o.distance_to(gp) < 6.0 and not m.street_food.is_seated():
					return ["%s'in Masasına Otur" % _short(id), "soc_sit", "sit"]
			"walk":
				if not guest["started"] and o.distance_to(gp) < 3.0:
					return ["%s ile Yürüyüşe Başla" % _short(id), "soc_walk", "walk"]
				if guest["started"] and o.distance_to(gp) < 3.0 and m._moving == false and m.owner_model.speed < 0.2:
					return ["%s ile Sohbet Et" % _short(id), "soc_chat", "smile"]
			"boat":
				if not guest.get("boarded", false) and o.distance_to(gp) < 3.5:
					return ["%s ile Tekne Turuna Çık · %d ₺" % [_short(id), int(m.boat.TOUR_PRICE)], "soc_boat", "drop"]
			"party":
				if o.distance_to(gp) < 3.5 and int(guest["rounds"]) < 3:
					var has := _bag_n(GIFTS[0]) > 0 or _bag_n(GIFTS[1]) > 0
					return ["%s'e Hediyeni Ver" % _short(id) if has else "%s'in Doğum Gününü Kutla" % _short(id), "soc_gift", "star"]
	if not kids.is_empty() and not _waiting_kid().is_empty():
		return ["Çocuğa Bayram Şekeri Ver (%d)" % _bag_n(CANDY), "soc_candy", "heart"]
	if not iftar.is_empty() and o.distance_to(iftar["pos"]) < 6.0:
		var i := _iftar_free_seat()
		if i >= 0:
			return ["İftar Sofrasına Otur", "soc_iftar:%d" % i, "sit"]
	if not regulars.is_empty() and not m.street_food.is_seated():
		for id in regulars:
			var v: Node3D = regulars[id]
			if o.distance_to(Vector2(v.global_position.x, v.global_position.z)) < 1.7:
				_near = id
				return [("%s ile Tanış" if not s()["met"].has(id) else "%s ile Konuş") % pname(id), "soc_reg", "smile"]
	return []


func command(cmd: String) -> void:
	if cmd.begins_with("soc_iftar:"):
		sit_iftar(int(cmd.substr(10)))
		return
	match cmd:
		"soc_chat":
			open_chat()
		"soc_sit":
			sit_with_guest()
		"soc_walk":
			start_walk()
		"soc_boat":
			start_boat()
		"soc_gift":
			give_gift()
		"soc_candy":
			give_candy()
		"soc_iftar_up":
			if not _seated.is_empty() and _seated["ate"]:
				stand_iftar()
		"soc_home":
			home_talk()
		"soc_reg":
			if _near != "":
				talk_regular(_near)
		"soc_app":
			phone_app()
	m._update_context()


## Cantadan kullanilan esya (main._use_item): hediyeler yenmez.
func use_item(name: String) -> bool:
	if name in GIFTS:
		_bag()[name] = _bag_n(name) + 1
		if not guest.is_empty() and guest["kind"] == "party":
			give_gift()
		else:
			m.ui.toast("%s bir arkadaşa hediye. Doğum günü partisinde ver." % name)
		return true
	if name == CANDY and not _waiting_kid().is_empty():
		_bag()[name] = _bag_n(name) + 1
		give_candy()
		return true
	return false


# ---------------------------------------------------------------- telefon: Sosyal

func phone_app() -> void:
	var ui: Node = m.ui
	var d := s()
	var sub := date_text()
	var ap: Dictionary = d["appt"]
	if not ap.is_empty():
		sub += "\nBuluşma: %s · %s · %s%02d:00" % [_short(ap["id"]), place_label(ap["kind"], ap["id"]), "yarın " if int(ap["day"]) > day() else "", int(ap["hour"])]
	var body: VBoxContainer = ui._open_panel("SOSYAL", sub)
	if not ap.is_empty():
		ui._panel_item(body, "Buluşma Yerine Git", func():
			ui.close_modal()
			m._set_nav(Vector2(float(ap["x"]), float(ap["z"])), _short(ap["id"])))
	if not d["invite"].is_empty():
		var inv: Dictionary = d["invite"]
		ui._panel_item(body, "Davet: %s · %02d:00 · Kabul Et" % [_short(inv["id"]), int(inv["hour"])], func():
			ui.close_modal()
			accept())
	for id in friends_list():
		var line := "%s · %d · %s" % [_short(id), friend(id), rel_text(id)]
		var fid: String = id
		ui._panel_item(body, line, func(): invite_by_player(fid, "cafe" if fid != partner() else "dinner"))
	if s()["met"].size() < NEW_PEOPLE.size():
		ui._fx_label(body, "Çınaraltı Çay Ocağı'nın müdavimleriyle tanışabilirsin.", ui.F_BODY, 18, Color(1, 1, 1, 0.7))
	ui._panel_item(body, "Takvim", func(): _open_calendar())
	ui._panel_item(body, "Kapat", func(): ui.close_modal())
	ui._focus_first(body)


func _days_until(pred: Callable) -> int:
	for k in CYCLE + 1:
		if pred.call(day() + k):
			return k
	return -1


func _open_calendar() -> void:
	var ui: Node = m.ui
	var body: VBoxContainer = ui._open_panel("TAKVİM", date_text())
	var lines: Array = []
	var rb := _days_until(func(dd: int) -> bool: return cday(dd) == int(SEKER_BAYRAMI[0]))
	var kb := _days_until(func(dd: int) -> bool: return cday(dd) == int(KURBAN_BAYRAMI[0]))
	var rz := _days_until(func(dd: int) -> bool: return cday(dd) == int(RAMAZAN[0]))
	lines.append("Ramazan Bayramı: " + ("bugün!" if bayram_name() == "Ramazan Bayramı" else "%d gün sonra" % rb))
	lines.append("Kurban Bayramı: " + ("bugün!" if bayram_name() == "Kurban Bayramı" else "%d gün sonra" % kb))
	lines.append("Ramazan (iftar sofraları): " + ("şu an Ramazan" if is_ramazan() else "%d gün sonra" % rz))
	for id in friends_list():
		var bid: int = BDAY.get(id, 1)
		var k := _days_until(func(dd: int) -> bool: return cday(dd) == bid)
		lines.append("%s doğum günü: %s" % [_short(id), "bugün!" if k == 0 else "%d gün sonra" % k])
	for l in lines:
		ui._fx_label(body, l, ui.F_BODY, 20, Color.WHITE)
	ui._panel_item(body, "Geri", func(): phone_app())
	ui._focus_first(body)


# ---------------------------------------------------------------- test

func debug_friendmeet() -> void:
	if not tea_ok():
		print("SOSYAL cay ocagi yok")
		return
	var d := s()
	d["met"]["selin"] = 1
	m.neighbors._friends()["selin"] = maxi(friend("selin"), 50)
	var p: Vector2 = m.street_food.tea["pos"]
	m.clock = 18.0
	d["appt"] = {"id": "selin", "kind": "cafe", "hour": 18.0, "day": day(), "x": p.x, "z": p.y}
	m._place_owner(p + Vector2(2.0, 2.0))
	_spawn_guest(d["appt"])
	sit_with_guest()
	open_chat()
	print("SOSYAL bulusma masa=", guest.get("table"), " tabure=", guest.get("stool"), " oturdu=", m.street_food.is_seated())


func debug_bayram() -> void:
	var d := s()
	d["day"] = int(SEKER_BAYRAMI[0])
	_last_clock = 11.0
	m.clock = 11.0
	_bag()[CANDY] = 3
	var out: Vector2 = m.HOME_DOOR_OUT
	m._place_owner(m.HOME_DOOR + out * 4.0)
	spawn_kids()
	for k in kids:
		var v: Node3D = k["model"] if is_instance_valid(k["model"]) else null      # silinmis dugum turlu degiskene atanamaz
		var q: Vector2 = m._owner_pos() + Vector2.from_angle(float(k["slot"]) * 1.1 + 0.6) * 1.3
		v.position = Vector3(q.x, ParkMap.walk_height(q), q.y)
	print("SOSYAL bayram ", date_text(), " cocuk=", kids.size())


func debug_iftar() -> void:
	var d := s()
	d["day"] = int(RAMAZAN[1])
	m.clock = 19.0
	_last_clock = 19.0
	_build_iftar()
	m._place_owner(iftar["seats"][3]["pos"])
	sit_iftar(3)
	print("SOSYAL iftar ", date_text(), " sofra=", iftar["pos"])
