extends "res://scripts/shop_interior.gd"
## Makas Berber Salonu ici (dukkan kabugu shop_interior.gd: otomatik kayar kapi, kamera, carpisma).
## Arka duvarda boydan ayna ve tezgah, uc berber koltugu (birinde musteri tiras oluyor), bekleme banki,
## lavabo, kasa, fiyat panosu. Bos koltuga F ile otur -> panel: sac modeli, sac rengi, sakal.
## Secimler oyuncunun uzerinde hemen denenir (onizleme); "Onayla ve Öde" ile ucret odenir, berber keser,
## kayda yazilir (state.d["hair"] = [model, renk, sakal], banka hareketlerine de islenir).
## Vazgecince ya da panel kapaninca eski haline doner.

const ActivityBar = preload("res://scripts/activity_bar.gd")
const CUT_PRICE := 25
const DYE_PRICE := 30
const BEARD_PRICE := 20
const HAIR_COLORS := [["Doğal", ""], ["Simsiyah", "17120f"], ["Koyu Kahve", "4a3324"], ["Kumral", "8a5a35"], ["Sarı", "d9b56a"],
	["Kızıl", "a8452a"], ["Kır", "b9b6b0"], ["Pembe", "e07aa8"], ["Mavi", "3f6fd0"]]

var m: Node
## Koltuklar: [{local (oturma noktasi), front (onunde durulacak nokta), seat (seating.gd koltuk sozlugu), npc}]
var chairs: Array = []
var barber: Node3D
var _barber_home := Vector2.ZERO
var _orig: Array = []           # oturunca kaydedilen eski gorunum [model, renk, sakal]
var _pick: Array = []           # onizlenen secim
var _cut := {}                  # kesim suruyorsa {t, dur, bar, chair}
var _paid := false
var _snip_t := 0.0
var _npc_barber: Node3D
var _npc_t := 0.0


func _ready() -> void:
	m = get_parent()
	_rng.seed = 4242
	lamp_hex = "fff4e0"
	_build_shell()
	_build_barber()


func _exit_tree() -> void:
	if m == null:
		return
	if _cut.has("bar") and is_instance_valid(_cut["bar"]):
		(_cut["bar"] as Node).queue_free()
	if not _paid and not _orig.is_empty():
		_apply(_orig)
	var cur: Dictionary = m.seating.cur
	for c in chairs:
		if cur == c["seat"]:
			m.seating.release()
			m.owner_model.seated = false
			m.owner_model.sit_exit = false
			m.owner_model.position = Vector3.ZERO
			m.ui._actions.visible = true


# ---------------------------------------------------------------- yapim

func _build_barber() -> void:
	# Siyah-beyaz dama zemin
	var chk := Kit.checker(Color("ece8e0"), Color("1d1d21"), 22, 18)
	chk.roughness = 0.3
	Kit.box(self, Vector3(W, 0.02, D), Vector3(W * 0.5, 0.006, D * 0.5), chk)
	# Duvarlar: ust kisim krem, alt kisim lacivert lambri
	var wall := Kit.mat("efe7d6", 0.85)
	var wains := Kit.mat("24365a", 0.55)
	Kit.box(self, Vector3(W, H, 0.02), Vector3(W * 0.5, H * 0.5, 0.01), wall)
	for side in [0.01, W - 0.01]:
		Kit.box(self, Vector3(0.02, H, D), Vector3(side, H * 0.5, D * 0.5), wall)
		Kit.box(self, Vector3(0.04, 1.0, D), Vector3(side, 0.5, D * 0.5), wains)
	Kit.box(self, Vector3(W, 1.0, 0.04), Vector3(W * 0.5, 0.5, 0.03), wains)
	Kit.box(self, Vector3(W, 0.05, 0.06), Vector3(W * 0.5, 1.02, 0.04), Kit.mat("c9a45a", 0.4))
	# Arka duvar: boydan ayna, altinda tezgah, uzerinde sise / tarak / makas
	var mirror := StandardMaterial3D.new()
	mirror.albedo_color = Color("9fb3bd")
	mirror.metallic = 1.0
	mirror.roughness = 0.04
	Kit.box(self, Vector3(8.4, 1.25, 0.03), Vector3(W * 0.5, 1.75, 0.06), mirror)
	Kit.box(self, Vector3(8.6, 0.07, 0.08), Vector3(W * 0.5, 2.41, 0.07), Kit.mat("c9a45a", 0.35))
	Kit.box(self, Vector3(8.6, 0.07, 0.08), Vector3(W * 0.5, 1.1, 0.07), Kit.mat("c9a45a", 0.35))
	Kit.box(self, Vector3(8.6, 0.06, 0.42), Vector3(W * 0.5, 0.95, 0.24), Kit.mat("f4f1ea", 0.3))
	Kit.box(self, Vector3(8.6, 0.9, 0.38), Vector3(W * 0.5, 0.46, 0.22), Kit.mat("3a2a22", 0.6))
	colliders.append([Vector2(0.0, 0.5), Vector2(W, 0.5)])
	var bottles := ["2f62a8", "3f8f4a", "e07b1f", "c8322b", "f2c230", "6b3d8a", "1e9a8a"]
	for k in 22:
		var x := 1.4 + k * 0.38 + _rng.randf_range(-0.05, 0.05)
		if absf(x - 3.0) < 0.5 or absf(x - 5.5) < 0.5 or absf(x - 8.0) < 0.5:
			# Koltuk hizasinda tarak, makas, firca
			Kit.box(self, Vector3(0.16, 0.01, 0.03), Vector3(x, 0.99, 0.3), Kit.mat("1a1a1a", 0.4))
			continue
		var hgt := _rng.randf_range(0.12, 0.24)
		Kit.cyl(self, 0.035, 0.035, hgt, Vector3(x, 0.98 + hgt * 0.5, 0.2), Kit.mat(bottles[k % bottles.size()], 0.3), 10)
		Kit.cyl(self, 0.015, 0.015, 0.04, Vector3(x, 0.98 + hgt + 0.02, 0.2), Kit.mat("f4f4f4", 0.4), 8)
	# Uc berber koltugu, aynaya donuk
	for i in 3:
		var x: float = [3.0, 5.5, 8.0][i]
		_chair(Vector2(x, 1.55))
		var wp := w2(Vector2(x, 1.55))
		var seat := {"pos": wp, "yaw": 0.0, "h": global_position.y + 0.5, "kind": "berber", "busy": false}
		chairs.append({"local": Vector2(x, 1.55), "front": Vector2(x, 2.45), "seat": seat, "npc": null})
		# Yerde kesilmis sac kirintilari
		for k in 14:
			var a := _rng.randf() * TAU
			var r := _rng.randf_range(0.2, 0.75)
			Kit.box(self, Vector3(0.05, 0.004, 0.012), Vector3(x + cos(a) * r, 0.018, 1.6 + sin(a) * r * 0.8),
				Kit.mat(["2a1d15", "4a3324", "6b5040", "17120f"][k % 4], 0.9), Vector3(0, a, 0))
	# Soldaki koltukta tiras olan musteri ve onun berberi
	var cust := PersonModel.new()
	cust.kind = "erkek"
	cust.tint = Color("d9d4c8")
	cust.seated = true
	cust.position = Vector3(3.0, 0.45, 1.55)
	add_child(cust)
	chairs[0]["npc"] = cust
	chairs[0]["seat"]["busy"] = true
	_cape(cust, Vector3(3.0, 0.45, 1.55))
	_npc_barber = _person(Vector2(3.0, 2.25), PI * 0.0, Color("2a2d33"), false)
	# Oyuncunun berberi: orta koltugun yaninda bekler
	_barber_home = Vector2(6.35, 2.3)
	barber = _person(_barber_home, -PI * 0.25, Color("1f2a44"), false)
	# Sag duvar: bekleme banki, sehpa, dergiler
	var wood := Kit.mat("6b3d22", 0.6)
	Kit.box(self, Vector3(0.55, 0.08, 3.0), Vector3(W - 0.45, 0.45, 4.6), Kit.mat("a32a2a", 0.45))
	Kit.box(self, Vector3(0.1, 0.5, 3.0), Vector3(W - 0.18, 0.75, 4.6), Kit.mat("a32a2a", 0.45))
	for z in [3.25, 5.95]:
		Kit.box(self, Vector3(0.5, 0.42, 0.06), Vector3(W - 0.45, 0.21, z), wood)
	_solid(Vector2(W - 0.45, 4.6), Vector2(0.3, 1.5))
	Kit.box(self, Vector3(0.6, 0.04, 0.8), Vector3(W - 1.3, 0.42, 4.6), wood)
	Kit.box(self, Vector3(0.06, 0.4, 0.06), Vector3(W - 1.3, 0.2, 4.6), wood)
	for k in 3:
		Kit.box(self, Vector3(0.22, 0.012, 0.3), Vector3(W - 1.3 + (k - 1) * 0.12, 0.45 + k * 0.012, 4.5 + k * 0.08),
			Kit.mat(["c8322b", "2f62a8", "f2c230"][k], 0.6), Vector3(0, k * 0.4, 0))
	_solid(Vector2(W - 1.3, 4.6), Vector2(0.3, 0.4))
	var waiting := PersonModel.new()
	waiting.kind = "kadin"
	waiting.tint = Color("6b8f5a")
	waiting.seated = true
	waiting.position = Vector3(W - 0.5, 0.4, 5.3)
	waiting.rotation.y = PI * 0.5
	add_child(waiting)
	# Sol duvar: lavabo ve kasa
	Kit.box(self, Vector3(0.6, 0.85, 0.9), Vector3(0.35, 0.43, 3.4), Kit.mat("f4f4f0", 0.3))
	Kit.cyl(self, 0.24, 0.18, 0.12, Vector3(0.38, 0.86, 3.4), Kit.mat("d9dcdf", 0.15), 16)
	Kit.box(self, Vector3(0.04, 0.3, 0.04), Vector3(0.12, 1.05, 3.4), Kit.mat("b8bcc2", 0.2))
	_solid(Vector2(0.35, 3.4), Vector2(0.32, 0.45))
	_counter(Vector2(1.0, 6.3), 1.6, "c9a45a")
	Kit.box(self, Vector3(0.35, 0.22, 0.3), Vector3(1.0, 1.15, 6.3), Kit.mat("2b2d31", 0.4))
	Kit.box(self, Vector3(0.3, 0.12, 0.02), Vector3(1.0, 1.25, 6.46), Kit.glow("6fe3a0", 0.8))
	# Fiyat panosu (sol duvar)
	var board := Node3D.new()
	board.position = Vector3(0.05, 1.95, 4.9)
	board.rotation.y = PI * 0.5
	add_child(board)
	Kit.box(board, Vector3(2.0, 1.0, 0.04), Vector3.ZERO, Kit.mat("1e1e22", 0.5))
	Kit.box(board, Vector3(2.1, 0.07, 0.06), Vector3(0, 0.52, 0), Kit.mat(accent, 0.5))
	var l := Label3D.new()
	l.text = "FİYATLAR\nSaç Kesimi  %d ₺\nSakal / Tıraş  %d ₺\nSaç Boyası  %d ₺" % [CUT_PRICE, BEARD_PRICE, DYE_PRICE]
	l.font_size = 64
	l.pixel_size = 0.0032
	l.modulate = Color("f4ead2")
	l.position = Vector3(0, 0, 0.03)
	board.add_child(l)
	# Arka duvarin ustunde tabela
	_sign("MAKAS BERBER", Vector3(W * 0.5, 2.85, 0.06), accent, Color.WHITE)
	# Kapi yaninda kucuk berber diregi
	var pole := Node3D.new()
	pole.position = Vector3(W * 0.5 + 1.6, 1.6, D - 0.25)
	add_child(pole)
	Kit.cyl(pole, 0.09, 0.09, 0.9, Vector3.ZERO, Kit.glow("f4f4f4", 0.4), 12)
	for k in 6:
		var colh := "d22a2a" if k % 2 == 0 else "2a4fd2"
		Kit.box(pole, Vector3(0.025, 0.9, 0.025), Vector3(cos(k * TAU / 6.0) * 0.08, 0, sin(k * TAU / 6.0) * 0.08), Kit.glow(colh, 0.7), Vector3(0.0, -k * TAU / 6.0, 0.45))
	# Sicak isik koltuklarin ustunde
	for x in [3.0, 5.5, 8.0]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(x, H - 0.1, 2.0)
		sl.rotation.x = -PI * 0.5
		sl.spot_range = 4.0
		sl.spot_angle = 35.0
		sl.light_energy = 1.2
		sl.light_color = Color("fff0d8")
		add_child(sl)


func _chair(c: Vector2) -> void:
	var chrome := Kit.mat("c9ccd2", 0.15)
	chrome.metallic = 0.9
	var leather := Kit.mat("7a1f22", 0.35)
	Kit.cyl(self, 0.32, 0.36, 0.05, Vector3(c.x, 0.025, c.y), chrome, 18)
	Kit.cyl(self, 0.07, 0.07, 0.32, Vector3(c.x, 0.2, c.y), chrome, 10)
	Kit.box(self, Vector3(0.56, 0.12, 0.52), Vector3(c.x, 0.42, c.y), leather)
	Kit.box(self, Vector3(0.56, 0.75, 0.1), Vector3(c.x, 0.85, c.y + 0.3), leather, Vector3(-0.12, 0, 0))
	Kit.box(self, Vector3(0.3, 0.16, 0.08), Vector3(c.x, 1.34, c.y + 0.37), leather)
	Kit.box(self, Vector3(0.04, 0.2, 0.04), Vector3(c.x, 1.2, c.y + 0.36), chrome)
	for sx in [-1.0, 1.0]:
		Kit.box(self, Vector3(0.08, 0.06, 0.48), Vector3(c.x + sx * 0.32, 0.64, c.y + 0.02), leather)
		Kit.box(self, Vector3(0.03, 0.2, 0.03), Vector3(c.x + sx * 0.32, 0.52, c.y + 0.2), chrome)
	# Ayak dayama
	Kit.box(self, Vector3(0.42, 0.03, 0.18), Vector3(c.x, 0.16, c.y - 0.5), chrome, Vector3(0.3, 0, 0))
	Kit.box(self, Vector3(0.03, 0.28, 0.03), Vector3(c.x, 0.2, c.y - 0.34), chrome, Vector3(0.9, 0, 0))
	_solid(c + Vector2(0, 0.1), Vector2(0.32, 0.32))


func _cape(p: Node3D, at: Vector3) -> void:
	# Musterinin uzerinde berber onlugu (cizgili)
	var cape := Kit.cyl(self, 0.16, 0.36, 0.62, at + Vector3(0, 0.82, -0.02), Kit.mat("e8eef4", 0.7), 16)
	cape.scale = Vector3(1.0, 1.0, 0.75)


func _person(at: Vector2, face_y: float, shirt: Color, female: bool) -> Node3D:
	var v := PersonModel.new()
	v.kind = "kadin" if female else "erkek"
	v.tint = shirt
	v.tint2 = shirt
	v.position = Vector3(at.x, 0, at.y)
	v.rotation.y = face_y
	add_child(v)
	return v


# ---------------------------------------------------------------- her kare

func _process(dt: float) -> void:
	if m == null:
		return
	# Komsu koltuktaki berber arada makas sallar
	_npc_t -= dt
	if _npc_t <= 0.0 and is_instance_valid(_npc_barber):
		_npc_t = randf_range(1.5, 3.5)
		(_npc_barber as PersonModel).act("wave", 1.2)
	if _cut.is_empty():
		return
	_cut["t"] = float(_cut["t"]) + dt
	var u: float = float(_cut["t"]) / float(_cut["dur"])
	var ch: Dictionary = chairs[int(_cut["chair"])]
	var behind: Vector2 = ch["local"] + Vector2(0.15 * sin(float(_cut["t"]) * 1.3), 0.62)
	barber.position = barber.position.lerp(Vector3(behind.x, 0, behind.y), minf(1.0, dt * 3.0))
	barber.rotation.y = 0.0
	(barber as PersonModel).speed = 0.0
	_snip_t -= dt
	if _snip_t <= 0.0:
		_snip_t = 0.33
		m._sfx("tik", -12.0, randf_range(1.6, 2.1))
		if not (barber as PersonModel).is_acting():
			(barber as PersonModel).act("wave", 0.9)
	var bar: Node = _cut["bar"]
	if is_instance_valid(bar):
		bar.set_value(u)
	if u >= 1.0:
		_finish_cut()


# ---------------------------------------------------------------- baglam ve komutlar

func busy() -> bool:
	return not _cut.is_empty()


func _my_chair() -> int:
	var cur: Dictionary = m.seating.cur
	for i in chairs.size():
		if cur == chairs[i]["seat"]:
			return i
	return -1


func context() -> Array:
	if not _cut.is_empty():
		return ["Berber kesiyor…", "", "star"]
	if _my_chair() >= 0:
		return ["Berber · Saç / Sakal Seç", "in_brb_menu", "star"]
	if m.seating.busy():
		return []
	var lo: Vector2 = local2(m._owner_pos())
	for i in chairs.size():
		if not chairs[i]["seat"]["busy"] and lo.distance_to(chairs[i]["front"]) < 1.0:
			return ["Berber Koltuğuna Otur", "in_brb_sit:%d" % i, "sit"]
	return []


func command(cmd: String) -> void:
	if cmd.begins_with("in_brb_sit:"):
		sit(int(cmd.substr(11)))
	elif cmd == "in_brb_menu":
		open_menu()


func sit(i: int) -> void:
	if i < 0 or i >= chairs.size() or chairs[i]["seat"]["busy"] or m.seating.busy():
		return
	m.seating.sit(chairs[i]["seat"])
	m.ui.toast("Koltuğa oturdun. Berber geliyor…")
	m._say(barber, ["Hoş geldin! Nasıl yapalım?", "Buyur abi, ne yapıyoruz bugün?", "Hoş geldin, saç mı sakal mı?"][randi() % 3])
	# Kamera aynanin onunden yuze baksin
	m._cam_yaw = PI - 0.45
	m._cam_pitch = 0.3
	m._zoom = 0.45
	var hr: Array = m.state.d.get("hair", [0, ""])
	_orig = [int(hr[0]) if hr.size() > 0 else 0, String(hr[1]) if hr.size() > 1 else "", int(hr[2]) if hr.size() > 2 else 0]
	_pick = _orig.duplicate()
	_paid = false
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_inside_tree() and _my_chair() == i and _cut.is_empty():
			open_menu())


func _price() -> int:
	if _orig.is_empty():
		return 0
	var p := 0
	if int(_pick[0]) != int(_orig[0]):
		p += CUT_PRICE
	if String(_pick[1]) != String(_orig[1]):
		p += DYE_PRICE
	if int(_pick[2]) != int(_orig[2]):
		p += BEARD_PRICE
	return p


func _color_name(hex: String) -> String:
	for c in HAIR_COLORS:
		if c[1] == hex:
			return c[0]
	return "Boyalı"


func _apply(look: Array) -> void:
	var om: Node = m.owner_model
	om.set_hair(int(look[0]), Color(look[1]) if String(look[1]) != "" else Color(0, 0, 0, 0))
	om.set_beard(int(look[2]))


func _watch_close() -> void:
	# Panel ESC ile kapanirsa (yeni panel acilmadiysa) onizleme geri alinir
	var md: Node = m.ui._modal
	if md:
		md.tree_exiting.connect(func(): _check_closed.call_deferred())


func _check_closed() -> void:
	if not is_inside_tree() or not _cut.is_empty() or _paid:
		return
	if m.ui._modal == null and not _orig.is_empty():
		_pick = _orig.duplicate()
		_apply(_orig)


func open_menu() -> void:
	if _my_chair() < 0 or not _cut.is_empty():
		return
	if _orig.is_empty():
		var hr: Array = m.state.d.get("hair", [0, ""])
		_orig = [int(hr[0]) if hr.size() > 0 else 0, String(hr[1]) if hr.size() > 1 else "", int(hr[2]) if hr.size() > 2 else 0]
		_pick = _orig.duplicate()
	var PM := PersonModel
	var male: bool = m.owner_model.kind == "erkek"
	var sub := "Saç: %s · Renk: %s%s\nAynada dene, beğenirsen öde · Cüzdan %d ₺" % [PM.HAIR_STYLES[int(_pick[0])], _color_name(String(_pick[1])),
		(" · Sakal: %s" % PM.BEARD_STYLES[int(_pick[2])]) if male else "", int(m.state.d["coins"])]
	var body: VBoxContainer = m.ui._open_panel("BERBER KOLTUĞU", sub)
	m.ui._panel_item(body, "Saç Modeli · %d ₺" % CUT_PRICE, func(): _list("model"))
	m.ui._panel_item(body, "Saç Rengi · %d ₺" % DYE_PRICE, func(): _list("renk"))
	if male:
		m.ui._panel_item(body, "Sakal / Bıyık · %d ₺" % BEARD_PRICE, func(): _list("sakal"))
	var p := _price()
	if p > 0:
		var b: Button = m.ui._panel_item(body, "Onayla ve Öde · %d ₺" % p, func(): pay())
		b.add_theme_color_override("font_color", Color("f5c518"))
	m.ui._panel_item(body, "Vazgeç (eski hâline dön)" if p > 0 else "Kalk", func(): cancel())
	m.ui._focus_first(body)
	_watch_close()


func _list(what: String) -> void:
	var PM := PersonModel
	var body: VBoxContainer
	match what:
		"model":
			body = m.ui._open_panel("SAÇ MODELİ", "Seç, aynada dene · %d ₺" % CUT_PRICE)
			for i in PM.HAIR_STYLES.size():
				var k: int = i
				m.ui._panel_item(body, ("▸ " if int(_pick[0]) == i else "") + PM.HAIR_STYLES[i], func(): _try(0, k))
		"renk":
			body = m.ui._open_panel("SAÇ RENGİ", "Saç ve sakal aynı renk boyanır · %d ₺" % DYE_PRICE)
			for c in HAIR_COLORS:
				var hex: String = c[1]
				var b: Button = m.ui._panel_item(body, ("▸ " if String(_pick[1]) == hex else "") + c[0], func(): _try(1, hex))
				if hex != "":
					b.add_theme_color_override("font_color", Color(hex).lightened(0.3))
		_:
			body = m.ui._open_panel("SAKAL / BIYIK", "Seç, aynada dene · %d ₺" % BEARD_PRICE)
			for i in PM.BEARD_STYLES.size():
				var k2: int = i
				m.ui._panel_item(body, ("▸ " if int(_pick[2]) == i else "") + PM.BEARD_STYLES[i], func(): _try(2, k2))
	m.ui._panel_item(body, "Geri", func(): open_menu())
	m.ui._focus_first(body)
	_watch_close()


func _try(slot: int, v) -> void:
	_pick[slot] = v
	_apply(_pick)
	m._sfx("tik", -8.0)
	open_menu()


func cancel() -> void:
	if not _orig.is_empty():
		_apply(_orig)
		_pick = _orig.duplicate()
	m.ui.close_modal()
	m.seating.stand_up()
	m._say(barber, "Yine bekleriz!")


func pay() -> void:
	var p := _price()
	if p <= 0:
		return
	if not m.state.spend(p):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % p)
		return
	_paid = true
	m.ui.close_modal()
	m._sfx("kasa", -8.0)
	# Kesim suresince eski gorunum, sonunda yenisi
	_apply(_orig)
	var bar := ActivityBar.new()
	m.add_child(bar)
	var what: Array = []
	if int(_pick[0]) != int(_orig[0]):
		what.append("saç kesimi")
	if String(_pick[1]) != String(_orig[1]):
		what.append("boya")
	if int(_pick[2]) != int(_orig[2]):
		what.append("sakal")
	bar.setup("BERBER", "Makas şakırdıyor… (%s)" % ", ".join(what))
	_cut = {"t": 0.0, "dur": 4.0, "bar": bar, "chair": _my_chair(), "what": what, "price": p}
	m._say(barber, "Şöyle bir başlayalım…")


func _finish_cut() -> void:
	var c := _cut
	_cut = {}
	if is_instance_valid(c["bar"]):
		(c["bar"] as Node).queue_free()
	_apply(_pick)
	var st: Dictionary = m.state.d
	st["hair"] = [int(_pick[0]), String(_pick[1]), int(_pick[2])]
	var rec: Array = st.get("berber_log", [])
	rec.push_front({"gun": int(st.get("gun", 0)), "is": ", ".join(c["what"]), "ucret": int(c["price"]),
		"sac": PersonModel.HAIR_STYLES[int(_pick[0])], "sakal": PersonModel.BEARD_STYLES[int(_pick[2])]})
	while rec.size() > 10:
		rec.pop_back()
	st["berber_log"] = rec
	if m.get("bank") and m.bank.has_method("_log"):
		m.bank._log("Makas Berber · " + ", ".join(c["what"]), -int(c["price"]))
	m.state.count("shop")
	m.state.save_game()
	_orig = _pick.duplicate()
	m._sfx("mutlu", -8.0)
	m._say(barber, ["Sıhhatler olsun!", "Çok yakıştı!", "Bak bakalım aynaya, nasıl?"][randi() % 3])
	m.ui.toast("Sıhhatler olsun! Yeni görünümün kaydedildi. Kalkmak için yürü.")
	barber.position = Vector3(_barber_home.x, 0, _barber_home.y)
	barber.rotation.y = -PI * 0.25
	_paid = false


# ---------------------------------------------------------------- test

## --berber=ic[:model:renk:sakal] : berbere girer, koltuga oturur, secimi dener, oder; kamera yuze bakar.
func debug_cut(style: int, hex: String, beard: int) -> void:
	await get_tree().create_timer(0.5).timeout
	var fr: Vector2 = chairs[1]["front"]
	m._place_owner(w2(fr))
	await get_tree().create_timer(0.3).timeout
	sit(1)
	await get_tree().create_timer(1.4).timeout
	print("BERBER oturdu koltuk=", _my_chair(), " baglam=", context())
	if style >= 0:
		_try(0, style)
	if hex != "-":
		_try(1, hex)
	if beard >= 0:
		_try(2, beard)
	print("BERBER onizleme=", _pick, " ucret=", _price())
	await get_tree().create_timer(1.0).timeout
	pay()
	await get_tree().create_timer(4.6).timeout
	print("BERBER kayit hair=", m.state.d.get("hair"), " log=", m.state.d.get("berber_log", []).slice(0, 1), " para=", m.state.d["coins"])
