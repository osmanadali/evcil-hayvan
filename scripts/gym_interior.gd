extends "res://scripts/shop_interior.gd"
## Kondisyon Spor Salonu ici (dukkan kabugu shop_interior.gd: otomatik kayar kapi, kamera, carpisma).
## Girisin saginda resepsiyon (uyelik: gunluk giris ya da 30 gunluk), arkada uc kosu bandi, sol duvarda
## ayna ve dambil rafi, sagda mekik sehpalari, kum torbasi. Aletin onunde F -> kisa set (ilerleme cubugu):
##   Koşu Bandı -> dayaniklilik (kosarken enerji daha yavas biter, scripts/player_needs.gd)
##   Dambıl     -> guc (market sepeti daha cok urun tasir, main._put_in_basket)
##   Mekik      -> ikisi biraz
## Her set enerji ve tokluk harcar; yorgun / acken calisilamaz. Gunde 6 setten sonra kazanc yariya iner.
## Kayit: state.d["fit"] = {guc, dayan, uye_son (gecerli son gun), sets, set_gun, toplam}

const ActivityBar = preload("res://scripts/activity_bar.gd")
const DAY_PASS := 25
const MONTH_PASS := 250
const SET_SECS := 6.0
const DAILY_SETS := 6
# tur -> [ad, enerji, tokluk, dayaniklilik, guc]
const EX := {
	"kosu": ["Koşu Bandı", 12.0, 6.0, 4.0, 0.5],
	"agirlik": ["Dambıl", 10.0, 5.0, 0.5, 4.0],
	"mekik": ["Mekik", 8.0, 4.0, 2.0, 2.0],
}

var m: Node
## Aletler: [{kind, stand (oyuncunun durdugu yer), front (yaklasma noktasi), yaw, h, busy}]
var stations: Array = []
var receptionist: Node3D
var _ex := {}                 # suren set: {i, t, bar, items: [Node3D]}
var _belts: Array = []        # kosu bandi seritleri: [{node, x, z0}]
var _npcs: Array = []


static func fit(st: Dictionary) -> Dictionary:
	if not st.has("fit") or typeof(st["fit"]) != TYPE_DICTIONARY:
		st["fit"] = {"guc": 0.0, "dayan": 0.0, "uye_son": -1, "sets": 0, "set_gun": -1, "toplam": 0}
	return st["fit"]


## Market sepetinin alabilecegi urun sayisi (guc arttikca artar).
static func carry_cap(st: Dictionary) -> int:
	return 12 + int(float(fit(st).get("guc", 0.0)) * 0.18)


func _ready() -> void:
	m = get_parent()
	_rng.seed = 909
	lamp_hex = "f4f8ff"
	counter_local = Vector2(8.6, 7.65)
	_build_shell()
	_build_gym()


func _exit_tree() -> void:
	if m != null and not _ex.is_empty():
		_stop(false)


# ---------------------------------------------------------------- yapim

func _build_gym() -> void:
	# Kaucuk zemin, agirlik bolgesinde daha koyu
	Kit.box(self, Vector3(W, 0.02, D), Vector3(W * 0.5, 0.006, D * 0.5), Kit.mat("3a3d44", 0.95))
	Kit.box(self, Vector3(3.2, 0.024, 4.6), Vector3(1.6, 0.008, 4.9), Kit.mat("24262b", 0.95))
	for z in [0.9, 2.9]:
		Kit.box(self, Vector3(6.6, 0.026, 0.05), Vector3(3.6, 0.009, z), Kit.mat("f2c230", 0.6))
	# Duvarlar: acik gri, turuncu serit
	var wall := Kit.mat("e4e6e9", 0.85)
	Kit.box(self, Vector3(W, H, 0.02), Vector3(W * 0.5, H * 0.5, 0.01), wall)
	for side in [0.01, W - 0.01]:
		Kit.box(self, Vector3(0.02, H, D), Vector3(side, H * 0.5, D * 0.5), wall)
		Kit.box(self, Vector3(0.03, 0.25, D), Vector3(side, 1.6, D * 0.5), Kit.mat(accent, 0.6))
	Kit.box(self, Vector3(W, 0.25, 0.03), Vector3(W * 0.5, 1.6, 0.02), Kit.mat(accent, 0.6))
	_sign("KONDİSYON", Vector3(3.6, 2.55, 0.05), accent, Color.WHITE)
	_poster(Vector3(8.4, 2.15, 0.04), 0.0, "BUGÜN DE\nGELDİN!")
	_poster(Vector3(W - 0.04, 2.1, 3.2), -PI * 0.5, "GÜÇ\nDAYANIKLILIK")
	# Uc kosu bandi (arka duvara donuk); ortadakinde bir uye kosuyor
	for i in 3:
		var x: float = [1.9, 3.6, 5.3][i]
		_treadmill(Vector2(x, 1.75))
		stations.append({"kind": "kosu", "stand": Vector2(x, 1.75), "front": Vector2(x, 3.15), "yaw": 0.0, "h": 0.19, "busy": i == 1})
	var runner := _person(Vector2(3.6, 1.75), 0.0, Color("2f62a8"), true)
	runner.position.y = 0.19
	(runner as PersonModel).force_speed = 3.2
	_npcs.append(runner)
	# Sol duvar: boydan ayna, dambil rafi
	var mirror := StandardMaterial3D.new()
	mirror.albedo_color = Color("a3b6c0")
	mirror.metallic = 1.0
	mirror.roughness = 0.05
	Kit.box(self, Vector3(0.03, 1.5, 4.4), Vector3(0.04, 1.5, 4.9), mirror)
	_rack(Vector2(0.45, 4.9))
	for i in 2:
		var z: float = [4.2, 5.6][i]
		stations.append({"kind": "agirlik", "stand": Vector2(1.55, z), "front": Vector2(2.2, z), "yaw": PI * 0.5, "h": 0.0, "busy": false})
		Kit.box(self, Vector3(0.9, 0.012, 0.9), Vector3(1.55, 0.02, z), Kit.mat("1a1b1f", 0.95))
	# Halter sehpasi (sus), arka sol kose
	var steel := Kit.mat("9aa0a8", 0.3)
	steel.metallic = 0.7
	Kit.box(self, Vector3(0.4, 0.42, 1.3), Vector3(1.5, 0.21, 7.2), Kit.mat("1d1f24", 0.5))
	for sx in [-1.0, 1.0]:
		Kit.box(self, Vector3(0.06, 1.2, 0.06), Vector3(1.5 + sx * 0.55, 0.6, 6.6), steel)
	Kit.cyl(self, 0.016, 0.016, 1.8, Vector3(1.5, 1.05, 6.6), steel, 8, Vector3(0, 0, PI * 0.5))
	for sx in [-1.0, 1.0]:
		Kit.cyl(self, 0.2, 0.2, 0.06, Vector3(1.5 + sx * 0.75, 1.05, 6.6), Kit.mat("1a1a1d", 0.5), 18, Vector3(0, 0, PI * 0.5))
	_solid(Vector2(1.5, 7.0), Vector2(0.7, 0.75))
	# Sag: iki mekik sehpasi (oyuncu odaya donuk oturur)
	for i in 2:
		var x2: float = [7.4, 9.2][i]
		_situp_bench(Vector2(x2, 2.1))
		stations.append({"kind": "mekik", "stand": Vector2(x2, 2.45), "front": Vector2(x2, 3.4), "yaw": PI, "h": 0.5, "busy": false})
	# Kum torbasi
	Kit.cyl(self, 0.02, 0.02, 0.8, Vector3(W - 1.0, H - 0.4, 5.2), steel, 6)
	Kit.cyl(self, 0.2, 0.2, 1.0, Vector3(W - 1.0, 1.5, 5.2), Kit.mat("8a1f1f", 0.5), 16)
	_solid(Vector2(W - 1.0, 5.2), Vector2(0.25, 0.25))
	# Resepsiyon (girisin sagi), su sebili, gorevli
	_counter(Vector2(8.6, 6.85), 2.2, "f4f4f0")
	Kit.box(self, Vector3(2.2, 0.3, 0.04), Vector3(8.6, 0.6, 7.21), Kit.mat(accent, 0.5))
	Kit.box(self, Vector3(0.34, 0.24, 0.04), Vector3(8.2, 1.2, 6.75), Kit.mat("2b2d31", 0.4), Vector3(-0.3, 0, 0))
	receptionist = _person(Vector2(8.6, 6.1), PI, Color(accent), true)
	Kit.box(self, Vector3(0.35, 1.0, 0.35), Vector3(W - 0.3, 0.5, 7.9), Kit.mat("d9dcdf", 0.4))
	Kit.cyl(self, 0.14, 0.14, 0.4, Vector3(W - 0.3, 1.22, 7.9), Kit.mat("8fc8f0", 0.1), 12)
	_solid(Vector2(W - 0.3, 7.9), Vector2(0.2, 0.2))
	# Uye: dambil calisiyor
	var lifter := _person(Vector2(1.55, 5.6), PI * 0.5, Color("3f8f4a"), false)
	(lifter as PersonModel).exercise = "curl"
	stations[4]["busy"] = true
	_dumbbells_in(lifter)
	_npcs.append(lifter)


func _poster(at: Vector3, yaw: float, text: String) -> void:
	var p := Node3D.new()
	p.position = at
	p.rotation.y = yaw
	add_child(p)
	Kit.box(p, Vector3(1.3, 1.0, 0.02), Vector3.ZERO, Kit.mat("1d1f24", 0.5))
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/Bangers-Regular.ttf")
	l.font_size = 96
	l.pixel_size = 0.0035
	l.modulate = Color(accent).lightened(0.2)
	l.position = Vector3(0, 0, 0.02)
	p.add_child(l)


func _treadmill(c: Vector2) -> void:
	var blk := Kit.mat("1d1f24", 0.5)
	var grey := Kit.mat("6a6f78", 0.4)
	Kit.box(self, Vector3(0.82, 0.14, 1.9), Vector3(c.x, 0.07, c.y), blk)
	Kit.box(self, Vector3(0.56, 0.03, 1.7), Vector3(c.x, 0.155, c.y), Kit.mat("101114", 0.85))
	for sx in [-1.0, 1.0]:
		Kit.box(self, Vector3(0.12, 0.05, 1.8), Vector3(c.x + sx * 0.35, 0.165, c.y), grey)
		Kit.box(self, Vector3(0.05, 1.1, 0.05), Vector3(c.x + sx * 0.36, 0.7, c.y - 0.82), grey, Vector3(-0.15, 0, 0))
		Kit.box(self, Vector3(0.04, 0.04, 0.55), Vector3(c.x + sx * 0.36, 1.1, c.y - 0.6), grey)
	Kit.box(self, Vector3(0.78, 0.3, 0.1), Vector3(c.x, 1.3, c.y - 0.9), blk, Vector3(0.5, 0, 0))
	Kit.box(self, Vector3(0.5, 0.16, 0.02), Vector3(c.x, 1.31, c.y - 0.84), Kit.glow("3ad0ff", 0.9), Vector3(0.5, 0, 0))
	# Bant uzerinde kayan seritler (kosarken hareket eder)
	for k in 5:
		var s := Kit.box(self, Vector3(0.54, 0.004, 0.04), Vector3(c.x, 0.173, c.y - 0.8 + k * 0.32), Kit.mat("2c2e34", 0.8))
		_belts.append({"node": s, "c": c, "o": k * 0.32})
	_solid(Vector2(c.x, c.y - 0.85), Vector2(0.42, 0.12))
	colliders.append([Vector2(c.x - 0.42, c.y - 0.95), Vector2(c.x - 0.42, c.y + 0.6)])
	colliders.append([Vector2(c.x + 0.42, c.y - 0.95), Vector2(c.x + 0.42, c.y + 0.6)])


func _rack(c: Vector2) -> void:
	var steel := Kit.mat("9aa0a8", 0.3)
	steel.metallic = 0.7
	Kit.box(self, Vector3(0.6, 0.06, 2.6), Vector3(c.x, 0.5, c.y), steel)
	Kit.box(self, Vector3(0.6, 0.06, 2.6), Vector3(c.x, 0.85, c.y), steel)
	for z in [-1.2, 1.2]:
		Kit.box(self, Vector3(0.5, 0.9, 0.06), Vector3(c.x, 0.45, c.y + z), steel)
	var cols := ["c8322b", "2f62a8", "3f8f4a", "f2c230", "1d1f24"]
	for k in 7:
		for row in 2:
			var z2: float = c.y - 1.05 + k * 0.35
			var y: float = 0.6 + row * 0.35
			var r: float = 0.045 + (k % 4) * 0.01
			for sx in [-1.0, 1.0]:
				Kit.cyl(self, r, r, 0.06, Vector3(c.x + sx * 0.09, y, z2), Kit.mat(cols[k % cols.size()], 0.5), 10, Vector3(0, 0, PI * 0.5))
			Kit.cyl(self, 0.012, 0.012, 0.14, Vector3(c.x, y, z2), steel, 6, Vector3(0, 0, PI * 0.5))
	_solid(c, Vector2(0.32, 1.32))


func _situp_bench(c: Vector2) -> void:
	var pad := Kit.mat("1d1f24", 0.45)
	var steel := Kit.mat("9aa0a8", 0.3)
	Kit.box(self, Vector3(0.42, 0.1, 1.5), Vector3(c.x, 0.45, c.y), pad, Vector3(-0.12, 0, 0))
	Kit.box(self, Vector3(0.06, 0.45, 0.06), Vector3(c.x, 0.22, c.y - 0.5), steel)
	Kit.box(self, Vector3(0.06, 0.38, 0.06), Vector3(c.x, 0.19, c.y + 0.5), steel)
	Kit.box(self, Vector3(0.5, 0.04, 0.5), Vector3(c.x, 0.02, c.y), steel)
	# Ayak kilidi
	Kit.cyl(self, 0.05, 0.05, 0.4, Vector3(c.x, 0.2, c.y + 0.85), pad, 10, Vector3(0, 0, PI * 0.5))
	_solid(Vector2(c.x, c.y - 0.15), Vector2(0.24, 0.65))


func _person(at: Vector2, face_y: float, shirt: Color, female: bool) -> Node3D:
	var v := PersonModel.new()
	v.kind = "kadin" if female else "erkek"
	v.tint = shirt
	v.tint2 = shirt
	v.position = Vector3(at.x, 0, at.y)
	v.rotation.y = face_y
	add_child(v)
	return v


func _dumbbell() -> Node3D:
	var d := Node3D.new()
	var steel := Kit.mat("9aa0a8", 0.3)
	Kit.cyl(d, 0.014, 0.014, 0.2, Vector3.ZERO, steel, 8, Vector3(0, 0, PI * 0.5))
	for sx in [-1.0, 1.0]:
		Kit.cyl(d, 0.05, 0.05, 0.05, Vector3(sx * 0.08, 0, 0), Kit.mat("1d1f24", 0.5), 12, Vector3(0, 0, PI * 0.5))
	return d


## Iki ele birer dambil (sol el PersonModel.hand, sag ele yeni kemik eklentisi).
func _dumbbells_in(p: Node3D) -> Array:
	var pm := p as PersonModel
	var out: Array = []
	if pm._skel == null:
		await get_tree().process_frame
		if not is_instance_valid(pm) or pm._skel == null:
			return out
	for side in ["LeftHand", "RightHand"]:
		var att := BoneAttachment3D.new()
		att.bone_name = side
		pm._skel.add_child(att)
		var d := _dumbbell()
		d.position = Vector3(0, 0.09, 0.02)
		att.add_child(d)
		out.append(att)
	return out


# ---------------------------------------------------------------- her kare

func _process(dt: float) -> void:
	if m == null:
		return
	# Bant seritleri: bant uzerinde biri kosuyorsa kayar
	var t := Time.get_ticks_msec() / 1000.0
	for b in _belts:
		var c: Vector2 = b["c"]
		var running := (c.distance_to(Vector2(3.6, 1.75)) < 0.1) or (not _ex.is_empty() and (stations[int(_ex["i"])]["stand"] as Vector2).distance_to(c) < 0.1)
		if running:
			var z := fposmod(float(b["o"]) + t * 2.2, 1.6) - 0.8
			(b["node"] as Node3D).position.z = c.y + z
	if _ex.is_empty():
		return
	var st: Dictionary = stations[int(_ex["i"])]
	_ex["t"] = float(_ex["t"]) + dt
	var wp: Vector2 = w2(st["stand"])
	m.owner_node.position = Vector3(wp.x, global_position.y + float(st["h"]), wp.y)
	m.owner_node.rotation = Vector3(0, float(st["yaw"]), 0)
	m._target = wp
	var u: float = float(_ex["t"]) / SET_SECS
	var bar: Node = _ex["bar"]
	if is_instance_valid(bar):
		bar.set_value(u)
	if float(_ex["t"]) > 0.6 and _move_key():
		m.ui.toast("Seti yarıda bıraktın.")
		_stop(false)
		return
	if u >= 1.0:
		_stop(true)


func _move_key() -> bool:
	return Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back") \
		or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right") or m.ui.stick.length() > 0.5


# ---------------------------------------------------------------- baglam ve komutlar

func busy() -> bool:
	return not _ex.is_empty()


func member() -> bool:
	var f := fit(m.state.d)
	return int(f.get("uye_son", -1)) >= int(m.state.d.get("gun", 0))


func context() -> Array:
	if not _ex.is_empty():
		return ["%s · bırakmak için yürü" % EX[stations[int(_ex["i"])]["kind"]][0], "", "star"]
	var lo: Vector2 = local2(m._owner_pos())
	if lo.distance_to(counter_local) < 1.4:
		return ["Resepsiyon · Üyelik", "in_gym_desk", "cart"]
	for i in stations.size():
		var st: Dictionary = stations[i]
		if not st["busy"] and lo.distance_to(st["front"]) < 0.9:
			return ["%s · Çalış" % EX[st["kind"]][0], "in_gym_ex:%d" % i, "star"]
	return []


func command(cmd: String) -> void:
	if cmd == "in_gym_desk":
		open_desk()
	elif cmd.begins_with("in_gym_ex:"):
		start(int(cmd.substr(10)))


func _stats_text() -> String:
	var f := fit(m.state.d)
	var d := float(f["dayan"])
	var g := float(f["guc"])
	return "Dayanıklılık %d/100 (koşarken enerji %%%d daha yavaş biter) · Güç %d/100 (sepet %d ürün)" % [
		int(d), int(60.0 * d / 100.0), int(g), carry_cap(m.state.d)]


func open_desk() -> void:
	var f := fit(m.state.d)
	var gun := int(m.state.d.get("gun", 0))
	var left := int(f.get("uye_son", -1)) - gun + 1
	var sub := ("Üyeliğin geçerli · %d gün kaldı" % left) if left > 0 else "Üyeliğin yok"
	sub += "\n" + _stats_text() + "\nCüzdan %d ₺" % int(m.state.d["coins"])
	var body: VBoxContainer = m.ui._open_panel("KONDİSYON SPOR", sub)
	m.ui._panel_item(body, "Günlük Giriş · %d ₺" % DAY_PASS, func(): buy(1, DAY_PASS))
	m.ui._panel_item(body, "Aylık Üyelik (30 gün) · %d ₺" % MONTH_PASS, func(): buy(30, MONTH_PASS))
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func buy(days: int, price: int) -> void:
	if not m.state.spend(price):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % price)
		return
	var f := fit(m.state.d)
	var gun := int(m.state.d.get("gun", 0))
	f["uye_son"] = maxi(int(f.get("uye_son", -1)), gun - 1) + days
	if m.get("bank") and m.bank.has_method("_log"):
		m.bank._log("Kondisyon Spor · " + ("günlük giriş" if days == 1 else "aylık üyelik"), -price)
	m.ui.close_modal()
	m._sfx("kasa", -8.0)
	m._say(receptionist, "İyi antrenmanlar!" if days == 1 else "Aramıza hoş geldin! Kartın hazır.")
	m.ui.toast("%s alındı. Aletlerin önünde F ile çalış." % ("Günlük giriş" if days == 1 else "30 günlük üyelik"))
	m.state.save_game()


func start(i: int) -> void:
	if i < 0 or i >= stations.size() or not _ex.is_empty():
		return
	var st: Dictionary = stations[i]
	if st["busy"]:
		return
	if not member():
		m.ui.toast("Önce resepsiyondan giriş ya da üyelik almalısın.")
		m._say(receptionist, "Buyurun, önce kayıt!")
		return
	var ex: Array = EX[st["kind"]]
	if m.needs.value("energy") < float(ex[1]) + 5.0:
		m.ui.toast("Çok yorgunsun, çalışamazsın. Biraz dinlen ya da uyu.")
		return
	if m.needs.value("hunger") < float(ex[2]) + 5.0:
		m.ui.toast("Karnın çok aç! Önce bir şeyler ye.")
		return
	m.ui.close_modal()
	m._moving = false
	m._queue.clear()
	m._steering = false
	m.ui.stick = Vector2.ZERO
	var om: Node = m.owner_model
	om.speed = 0.0
	var bar := ActivityBar.new()
	m.add_child(bar)
	var items: Array = []
	match st["kind"]:
		"kosu":
			om.force_speed = 3.2
			bar.setup("KOŞU BANDI", "Tempolu koşu… (dayanıklılık)")
			m._cam_yaw = 0.7
		"agirlik":
			om.exercise = "curl"
			om._ex_t = 0.0
			items = await _dumbbells_in(om)
			bar.setup("DAMBIL", "Biseps, sırayla iki kol… (güç)")
			m._cam_yaw = PI * 0.5 + 0.6
		"mekik":
			om.seated = true
			om._seat_t = 1.0
			om.exercise = "situp"
			om._ex_t = 0.0
			om.position = Vector3(0, -0.05, 0)
			bar.setup("MEKİK", "Karın kasları… (güç + dayanıklılık)")
			m._cam_yaw = 0.35
	m._cam_pitch = 0.32
	_ex = {"i": i, "t": 0.0, "bar": bar, "items": items}
	st["busy"] = true
	m.ui._actions.visible = false
	for k in m.agents:
		m.agents[k].command("sit")
	m._update_context()


func _stop(done: bool) -> void:
	var e := _ex
	_ex = {}
	var st: Dictionary = stations[int(e["i"])]
	st["busy"] = false
	if is_instance_valid(e.get("bar")):
		(e["bar"] as Node).queue_free()
	for it in e.get("items", []):
		if is_instance_valid(it):
			(it as Node).queue_free()
	var om: Node = m.owner_model
	om.force_speed = -1.0
	om.exercise = ""
	om.seated = false
	om.position = Vector3.ZERO
	var out: Vector2 = w2(st["front"])
	m.owner_node.position = Vector3(out.x, global_position.y, out.y)
	m._target = out
	m.ui._actions.visible = true
	for k in m.agents:
		m.agents[k].command("come")
	if done:
		_reward(st["kind"])
	m._update_context()


func _reward(kind: String) -> void:
	var ex: Array = EX[kind]
	var f := fit(m.state.d)
	var gun := int(m.state.d.get("gun", 0))
	if int(f.get("set_gun", -1)) != gun:
		f["set_gun"] = gun
		f["sets"] = 0
	f["sets"] = int(f["sets"]) + 1
	f["toplam"] = int(f.get("toplam", 0)) + 1
	var tired_k := 1.0 if int(f["sets"]) <= DAILY_SETS else 0.5
	var dd := float(ex[3]) * (1.0 - float(f["dayan"]) / 125.0) * tired_k
	var dg := float(ex[4]) * (1.0 - float(f["guc"]) / 125.0) * tired_k
	f["dayan"] = clampf(float(f["dayan"]) + dd, 0.0, 100.0)
	f["guc"] = clampf(float(f["guc"]) + dg, 0.0, 100.0)
	m.needs.add("energy", -float(ex[1]))
	m.needs.add("hunger", -float(ex[2]))
	m.state.count("spor")
	m.state.save_game()
	if m.owner_model.has_method("set_build"):
		m.owner_model.set_build(float(f["guc"]))
	var msg := "%s seti bitti! Dayanıklılık %d (+%.1f) · Güç %d (+%.1f) · −%d enerji, −%d tokluk" % [
		ex[0], int(f["dayan"]), dd, int(f["guc"]), dg, int(ex[1]), int(ex[2])]
	if int(f["sets"]) == DAILY_SETS:
		msg += " · Bugünlük yeter, kasların dinlenmeli."
	m.ui.toast(msg)
	m._sfx("mutlu", -10.0)
	print("SPOR set ", kind, " dayan=", snappedf(float(f["dayan"]), 0.1), " guc=", snappedf(float(f["guc"]), 0.1),
		" enerji=", snappedf(m.needs.value("energy"), 0.1), " tokluk=", snappedf(m.needs.value("hunger"), 0.1))


# ---------------------------------------------------------------- test

## --gym=uyelik|kosu|agirlik|mekik|hepsi : resepsiyonda uyelik alir, aleti calistirir (goruntu icin set ortasinda bekler).
func debug(what: String) -> void:
	await get_tree().create_timer(0.6).timeout
	m._place_owner(w2(counter_local))
	await get_tree().create_timer(0.3).timeout
	print("SPOR baglam(resepsiyon)=", context(), " uye=", member())
	if what == "uyelik":
		open_desk()
		return
	buy(30, MONTH_PASS)
	print("SPOR uye=", member(), " uye_son=", fit(m.state.d)["uye_son"], " gun=", m.state.d.get("gun"))
	var kinds: Array = ["kosu", "agirlik", "mekik"] if what == "hepsi" else [what]
	for k in kinds:
		for i in stations.size():
			if stations[i]["kind"] == k and not stations[i]["busy"]:
				m._place_owner(w2(stations[i]["front"]))
				await get_tree().create_timer(0.3).timeout
				print("SPOR baglam=", context())
				await start(i)
				if what != "hepsi":
					_ex["t"] = -60.0        # goruntu icin set bitmesin
				await get_tree().create_timer(2.5).timeout
				if DisplayServer.get_name() != "headless" and m._args.has("shot"):
					m.get_viewport().get_texture().get_image().save_png(String(m._args["shot"]).replace(".png", "_%s.png" % k))
					print("SPOR goruntu ", k)
				await get_tree().create_timer(SET_SECS - 2.0 if what == "hepsi" else 0.5).timeout
				break
