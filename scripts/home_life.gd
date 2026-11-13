extends Node
## Ev hayati (scripts/home.gd dairesi icinde):
## 1) Yemek: mutfakta ocagin onunde F "Yemek Pişir" -> tarif paneli. Malzemeler cantadan (marketten alinir).
##    Pisirme: oyuncu ocaga doner, tavada yemek belirir, buhar cikar, cizirti sesi; bitince "Ye" ya da
##    hayvana uygun olanlari "Hayvanına Ver" ya da "Çantaya Koy".
## 2) Mobilya: telefonda "Mobilya" uygulamasi; esyalar evdeki sabit bos yerlere konur (state.d["home_items"]).
## 3) Temizlik: zamanla ev daginiklasir (tuy yumaklari, oyuncaklar; state.d["home_mess"]); F ile toplanir.
##    Ev tamamen toplaninca hayvanlar temizlik ve mutluluk kazanir.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")

const STOVE_STAND := Vector2(4.6, 1.0)      # ocagin onu (yerel)
const COOK_TIME := 5.0
const MESS_EVERY := 70.0                     # saniyede bir yeni daginiklik
const MESS_MAX := 8

## Tarifler: kimlik -> [ad, {malzeme: adet}, {istege bagli: adet}, tokluk, hayvana uygun mu, renk]
const RECIPES := {
	"menemen": ["Menemen", {"Yumurta": 2, "Domates": 1}, {"Biber": 1}, 45, false, "e0612b"],
	"makarna": ["Makarna", {"Makarna": 1}, {"Peynir": 1}, 40, true, "f0d27a"],
	"tost": ["Kaşarlı Tost", {"Ekmek": 1, "Peynir": 1}, {"Domates": 1}, 35, false, "d9a05a"],
	"yumurta": ["Haşlanmış Yumurta", {"Yumurta": 1}, {}, 20, true, "f7f3e6"],
}
const INGREDIENTS := ["Yumurta", "Domates", "Biber", "Makarna", "Peynir"]

## Mobilya: kimlik -> [ad, fiyat, yer aciklamasi, yerel konum]
const FURNITURE := {
	"bitki": ["Saksı Bitkisi", 60, "salonun köşesine", Vector2(0.45, 11.1)],
	"lamba": ["Ayaklı Lamba", 90, "televizyonun yanına", Vector2(4.75, 11.2)],
	"hali": ["Desenli Halı", 120, "yatak odasına", Vector2(3.0, 6.3)],
	"tablo": ["Yağlı Boya Tablo", 150, "yatak odası duvarına", Vector2(5.93, 3.7)],
	"yatak": ["Evcil Hayvan Yatağı", 80, "salona", Vector2(1.25, 9.7)],
	"agac": ["Kedi Tırmalama Ağacı", 140, "küçük odaya", Vector2(11.5, 6.95)],
	"akvaryum": ["Akvaryum", 220, "salon duvarına", Vector2(4.2, 7.72)],
}

## Daginiklik icin uygun bos zemin noktalari (yerel)
const MESS_SPOTS := [Vector2(7.3, 1.6), Vector2(7.0, 4.4), Vector2(7.7, 5.6), Vector2(3.0, 8.9), Vector2(5.0, 8.2),
	Vector2(6.2, 10.6), Vector2(2.0, 8.7), Vector2(4.0, 10.3), Vector2(2.5, 5.6), Vector2(4.6, 6.4),
	Vector2(5.2, 3.4), Vector2(2.6, 1.1), Vector2(5.2, 1.6), Vector2(10.0, 7.6), Vector2(11.0, 8.5), Vector2(1.6, 9.3)]
const MESS_KINDS := {"tuy": "Tüy Yumağı", "top": "Oyuncak Top", "kemik": "Oyuncak Kemik", "ip": "Yün Yumağı", "kirinti": "Mama Kırıntısı"}

var m: Node
var state: Node
var cooking := false
var _cook_t := 0.0
var _recipe := ""
var _dish := ""                 # pisen ve henuz yenmemis yemek
var _root: Node3D               # ev icindeki tum dinamik nesneler
var _furn_root: Node3D
var _mess_root: Node3D
var _cook_root: Node3D
var _mess_nodes: Array = []     # [Node3D, index]
var _mess_t := 30.0
var _fish: Array = []
var _bonus_t := 0.0
var _food: Node3D
var _steam: CPUParticles3D
var _flame: MeshInstance3D
var _sizzle: AudioStreamPlayer
var _built_for: Node3D = null
var _anim_t := 0.0


func items() -> Array:
	if not state.d.has("home_items") or typeof(state.d["home_items"]) != TYPE_ARRAY:
		state.d["home_items"] = []
	return state.d["home_items"]


func mess() -> Array:
	if not state.d.has("home_mess") or typeof(state.d["home_mess"]) != TYPE_ARRAY:
		state.d["home_mess"] = [[7.0, 4.4, "tuy"], [3.0, 8.9, "top"], [5.0, 8.2, "tuy"]]
	return state.d["home_mess"]


func _bag() -> Dictionary:
	var bag: Dictionary = state.d.get("bag", {})
	state.d["bag"] = bag
	return bag


func _home() -> Node3D:
	return m._home


func at_home() -> bool:
	return m._home != null and ParkMap.home == m._home


func busy() -> bool:
	return cooking


# ---------------------------------------------------------------- kurulum

## main._enter_home cagirir: evin icine esyalari, daginikligi ve pisirme sahnesini kur.
func on_home(home: Node3D) -> void:
	if _built_for == home:
		_rebuild_mess()
		return
	_built_for = home
	_root = Node3D.new()
	_root.name = "EvHayati"
	home.add_child(_root)
	_furn_root = Node3D.new()
	_root.add_child(_furn_root)
	_mess_root = Node3D.new()
	_root.add_child(_mess_root)
	_cook_root = Node3D.new()
	_root.add_child(_cook_root)
	_build_cooking()
	_rebuild_furniture()
	_rebuild_mess()


func _build_cooking() -> void:
	# Ocak alevi (pisirirken yanar), tava ve buhar
	_flame = Kit.torus(_cook_root, 0.035, 0.075, Vector3(4.45, 0.93, 0.5), Kit.glow("ff7a1a", 3.0))
	_flame.visible = false
	var pan := Kit.pivot(_cook_root, Vector3(4.45, 0.95, 0.5))
	Kit.cyl(pan, 0.15, 0.13, 0.05, Vector3(0, 0.025, 0), Kit.mat("2a2a2c", 0.35), 18)
	Kit.cyl(pan, 0.135, 0.135, 0.01, Vector3(0, 0.048, 0), Kit.mat("3b3b3e", 0.25), 18)
	Kit.box(pan, Vector3(0.24, 0.02, 0.035), Vector3(0.0, 0.04, 0.26), Kit.mat("1a1a1a", 0.5), Vector3(0, PI / 2, 0))
	_food = Node3D.new()
	_food.position = Vector3(0, 0.055, 0)
	pan.add_child(_food)
	_steam = CPUParticles3D.new()
	_steam.position = Vector3(4.45, 1.05, 0.5)
	_steam.emitting = false
	_steam.amount = 26
	_steam.lifetime = 1.6
	_steam.direction = Vector3.UP
	_steam.spread = 18.0
	_steam.gravity = Vector3(0, 0.25, 0)
	_steam.initial_velocity_min = 0.25
	_steam.initial_velocity_max = 0.5
	_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_steam.emission_sphere_radius = 0.09
	_steam.scale_amount_min = 0.6
	_steam.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.0))
	_steam.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.55))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	_steam.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = _soft_dot()
	q.material = sm
	_steam.mesh = q
	_cook_root.add_child(_steam)
	_sizzle = AudioStreamPlayer.new()
	_sizzle.stream = _sizzle_stream()
	_sizzle.volume_db = -14.0
	_cook_root.add_child(_sizzle)


func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t


## Cizirti: yumusatilmis gurultu + rastgele citirtilar (dongu).
func _sizzle_stream() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - lp
		lp = lp * 0.6 + w * 0.4
		var s := hp * 0.25
		if rng.randf() < 0.004:
			s += rng.randf_range(-0.8, 0.8)
		var v := int(clampf(s, -1.0, 1.0) * 30000.0)
		data.encode_s16(i * 2, v)
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = n
	return st


# ---------------------------------------------------------------- mobilya

func _rebuild_furniture() -> void:
	if _furn_root == null:
		return
	for c in _furn_root.get_children():
		c.queue_free()
	_fish.clear()
	for id in items():
		if FURNITURE.has(id):
			_build_item(String(id))


func _build_item(id: String) -> void:
	var home := _home()
	var p: Vector2 = FURNITURE[id][3]
	var r := Kit.pivot(_furn_root, Vector3(p.x, 0, p.y))
	match id:
		"bitki":
			Kit.cyl(r, 0.2, 0.15, 0.38, Vector3(0, 0.19, 0), Kit.mat("b5553a", 0.8), 14)
			Kit.cyl(r, 0.18, 0.18, 0.02, Vector3(0, 0.37, 0), Kit.mat("3b2a1d", 1.0), 14)
			var leaf := Kit.mat("3f8a3c", 0.7)
			var leaf2 := Kit.mat("2f6e2e", 0.7)
			for k in 9:
				var a := k * TAU / 9.0
				var tilt := 0.35 + 0.25 * (k % 3)
				var l := Kit.pivot(r, Vector3(0, 0.38, 0))
				l.rotation = Vector3(0, a, 0)
				Kit.ball(l, 0.16, Vector3(0, 0.45, 0.0), leaf if k % 2 == 0 else leaf2, Vector3(0.45, 1.6, 0.12), 8).rotation.x = tilt
			Kit.cyl(r, 0.012, 0.012, 0.6, Vector3(0, 0.65, 0), Kit.mat("4a6b2a"), 6)
			home.colliders.append_array(_square(p, 0.22))
		"lamba":
			Kit.cyl(r, 0.16, 0.18, 0.03, Vector3(0, 0.015, 0), Kit.mat("1a1a1a", 0.4), 16)
			Kit.cyl(r, 0.012, 0.012, 1.5, Vector3(0, 0.76, 0), Kit.mat("b39060", 0.3), 8)
			var shade := StandardMaterial3D.new()
			shade.albedo_color = Color("f4e7cc")
			shade.emission_enabled = true
			shade.emission = Color("ffd99a")
			shade.emission_energy_multiplier = 1.2
			shade.cull_mode = BaseMaterial3D.CULL_DISABLED
			Kit.cyl(r, 0.13, 0.22, 0.28, Vector3(0, 1.58, 0), shade, 18)
			var l := OmniLight3D.new()
			l.position = Vector3(0, 1.45, 0)
			l.light_color = Color("ffd9a0")
			l.light_energy = 0.9
			l.omni_range = 3.5
			r.add_child(l)
			home.colliders.append_array(_square(p, 0.16))
		"hali":
			var hm := Kit.checker(Color("8c2f39"), Color("d9a441"), 8, 5)
			Kit.box(r, Vector3(1.7, 0.012, 1.05), Vector3(0, 0.02, 0), hm)
			Kit.box(r, Vector3(1.82, 0.01, 1.17), Vector3(0, 0.013, 0), Kit.mat("3d1f24", 1.0))
		"tablo":
			# Bati duvari icin dondurulmus (x sabit duvar, iceri -x)
			Kit.box(r, Vector3(0.04, 0.78, 1.08), Vector3(0, 1.62, 0), Kit.mat("8a6a2a", 0.35))
			Kit.box(r, Vector3(0.02, 0.66, 0.96), Vector3(-0.02, 1.62, 0), Kit.mat("e9dcc0", 0.9))
			Kit.box(r, Vector3(0.02, 0.3, 0.96), Vector3(-0.03, 1.45, 0), Kit.mat("3e6e8e", 0.9))     # deniz
			Kit.box(r, Vector3(0.02, 0.2, 0.5), Vector3(-0.035, 1.66, -0.18), Kit.mat("6a8a4a", 0.9))   # tepe
			Kit.ball(r, 0.08, Vector3(-0.035, 1.8, 0.25), Kit.mat("f2b33a", 0.9), Vector3(0.2, 1, 1))  # gunes
			Kit.box(r, Vector3(0.02, 0.06, 0.25), Vector3(-0.04, 1.52, 0.1), Kit.mat("f4f4f0", 0.9))    # yelken
		"yatak":
			var fab := Kit.mat("7a5a9a", 0.95)
			Kit.cyl(r, 0.42, 0.42, 0.06, Vector3(0, 0.03, 0), Kit.mat("4a3a5a", 0.9), 20)
			Kit.torus(r, 0.26, 0.44, Vector3(0, 0.12, 0), fab)
			Kit.cyl(r, 0.3, 0.3, 0.06, Vector3(0, 0.08, 0), Kit.mat("e8dcc8", 1.0), 20)
		"agac":
			var sisal := Kit.mat("c9a875", 1.0)
			var plush := Kit.mat("8d7a6a", 1.0)
			Kit.box(r, Vector3(0.6, 0.05, 0.6), Vector3(0, 0.025, 0), plush)
			Kit.cyl(r, 0.06, 0.06, 1.4, Vector3(-0.12, 0.72, 0), sisal, 10)
			Kit.cyl(r, 0.06, 0.06, 0.8, Vector3(0.15, 0.42, 0.1), sisal, 10)
			Kit.box(r, Vector3(0.42, 0.05, 0.42), Vector3(0.1, 0.82, 0.05), plush)
			Kit.box(r, Vector3(0.38, 0.05, 0.38), Vector3(-0.12, 1.43, 0), plush)
			Kit.cyl(r, 0.14, 0.14, 0.2, Vector3(-0.12, 1.55, 0), plush, 14)
			Kit.ball(r, 0.04, Vector3(0.25, 0.7, 0.2), Kit.mat("e0322b", 0.6))
			home.colliders.append_array(_square(p, 0.3))
		"akvaryum":
			var wood := Kit.mat("2a2421", 0.5)
			Kit.box(r, Vector3(1.1, 0.72, 0.42), Vector3(0, 0.36, 0), wood)
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.7, 0.9, 1.0, 0.18)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.05
			glass.cull_mode = BaseMaterial3D.CULL_DISABLED
			Kit.box(r, Vector3(1.02, 0.5, 0.36), Vector3(0, 0.98, 0), glass)
			var water := StandardMaterial3D.new()
			water.albedo_color = Color(0.2, 0.55, 0.75, 0.45)
			water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water.emission_enabled = true
			water.emission = Color("1f6f9a")
			water.emission_energy_multiplier = 0.6
			Kit.box(r, Vector3(0.98, 0.42, 0.32), Vector3(0, 0.95, 0), water)
			Kit.box(r, Vector3(0.98, 0.04, 0.32), Vector3(0, 0.75, 0), Kit.mat("d9c79a", 1.0))       # kum
			for k in 4:
				Kit.capsule(r, 0.012, 0.18 + k * 0.05, Vector3(-0.35 + k * 0.22, 0.86 + k * 0.02, 0.05 - (k % 2) * 0.1), Kit.mat("3f9a4a", 0.7))
			Kit.box(r, Vector3(1.1, 0.04, 0.42), Vector3(0, 1.25, 0), wood)
			for k in 4:
				var f := Kit.pivot(r, Vector3(0, 0.95, 0))
				Kit.ball(f, 0.03, Vector3(0, 0, 0), Kit.mat(["f28a1a", "f2d21a", "e0322b", "3fb5e0"][k], 0.4), Vector3(1.6, 0.9, 0.6), 8)
				Kit.prism(f, Vector3(0.04, 0.04, 0.01), Vector3(-0.055, 0, 0), Kit.mat(["f28a1a", "f2d21a", "e0322b", "3fb5e0"][k], 0.4), Vector3(0, 0, PI / 2))
				_fish.append([f, k * 1.7, 0.3 + k * 0.07])
			var l := OmniLight3D.new()
			l.position = Vector3(0, 1.1, 0.3)
			l.light_color = Color("7fd0ff")
			l.light_energy = 0.5
			l.omni_range = 2.0
			r.add_child(l)
			home.colliders.append_array(_square(p, 0.56, 0.22))


func _square(c: Vector2, hx: float, hz := -1.0) -> Array:
	var h := Vector2(hx, hz if hz > 0.0 else hx)
	var pts := [c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y), c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)]
	var out: Array = []
	for i in 4:
		out.append([pts[i], pts[(i + 1) % 4]])
	return out


## Telefon uygulamasi: Mobilya magazasi.
func open_shop() -> void:
	var body: VBoxContainer = m.ui._open_page("YUVAM MOBİLYA", "Cüzdan: %d ₺  ·  Aldığın eşya evindeki yerine hemen yerleşir." % int(state.d["coins"]))
	for id in FURNITURE:
		var f: Array = FURNITURE[id]
		var key: String = id
		if items().has(key):
			m.ui._menu_item(body, "%s  ·  EVİNDE ✓" % String(f[0]).to_upper(), func(): m.ui.toast("%s zaten evinde." % f[0]))
		else:
			m.ui._menu_item(body, "%s  ·  %d ₺" % [String(f[0]).to_upper(), int(f[1])], func(): buy(key))
	m.ui._menu_item(body, "KAPAT", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func buy(id: String) -> void:
	if items().has(id) or not FURNITURE.has(id):
		return
	var f: Array = FURNITURE[id]
	if not state.spend(int(f[1])):
		m.ui.toast("Paran yetmiyor: %s %d ₺." % [f[0], int(f[1])])
		return
	items().append(id)
	state.count("furniture")
	state.save_game()
	m._sfx("kasa", -6.0)
	if _furn_root != null:
		_build_item(id)
	m.ui.toast("%s alındı! Evinde %s yerleştirildi." % [f[0], f[2]])
	open_shop()


# ---------------------------------------------------------------- daginiklik

func _rebuild_mess() -> void:
	if _mess_root == null:
		return
	for c in _mess_root.get_children():
		c.queue_free()
	_mess_nodes.clear()
	var list := mess()
	for i in list.size():
		var e: Array = list[i]
		_mess_nodes.append(_mess_mesh(Vector2(float(e[0]), float(e[1])), String(e[2]), i))


func _mess_mesh(p: Vector2, kind: String, seed_i: int) -> Node3D:
	var r := Kit.pivot(_mess_root, Vector3(p.x, 0, p.y))
	r.rotation.y = seed_i * 1.3
	match kind:
		"tuy":
			var c := Kit.mat("d8c3a0" if seed_i % 2 == 0 else "6a5a4a", 1.0)
			for k in 5:
				Kit.ball(r, 0.05 + 0.015 * (k % 2), Vector3(cos(k * 1.3) * 0.06, 0.03, sin(k * 1.3) * 0.05), c, Vector3(1.2, 0.5, 1.0), 6)
		"top":
			Kit.ball(r, 0.08, Vector3(0, 0.08, 0), Kit.mat("e0322b", 0.5), Vector3.ONE, 12)
			Kit.torus(r, 0.078, 0.084, Vector3(0, 0.08, 0), Kit.mat("f4f4f0", 0.5), Vector3(PI / 2, 0, 0))
		"kemik":
			var b := Kit.mat("f1e8d0", 0.7)
			Kit.capsule(r, 0.022, 0.2, Vector3(0, 0.025, 0), b, Vector3(0, 0, PI / 2))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					Kit.ball(r, 0.03, Vector3(sx * 0.1, 0.03, sz * 0.022), b, Vector3.ONE, 8)
		"ip":
			Kit.ball(r, 0.07, Vector3(0, 0.07, 0), Kit.mat("4a7ad9", 1.0), Vector3.ONE, 10)
			Kit.capsule(r, 0.008, 0.35, Vector3(0.18, 0.01, 0.02), Kit.mat("4a7ad9", 1.0), Vector3(0, 0.4, PI / 2))
		_:
			for k in 7:
				Kit.ball(r, 0.018, Vector3(cos(k * 2.1) * 0.1, 0.012, sin(k * 1.7) * 0.1), Kit.mat("8a5a2b", 0.8), Vector3(1, 0.6, 1), 5)
	return r


func _spawn_mess() -> void:
	var list := mess()
	if list.size() >= MESS_MAX or state.owned_pets().is_empty():
		return
	var free: Array = []
	for s in MESS_SPOTS:
		var used := false
		for e in list:
			if Vector2(float(e[0]), float(e[1])).distance_to(s) < 0.6:
				used = true
		if not used:
			free.append(s)
	if free.is_empty():
		return
	var p: Vector2 = free[randi() % free.size()] + Vector2(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
	var kinds := MESS_KINDS.keys()
	var kind: String = kinds[randi() % kinds.size()]
	list.append([p.x, p.y, kind])
	if at_home() and _mess_root != null:
		_mess_nodes.append(_mess_mesh(p, kind, list.size() - 1))


func _nearest_mess(lo: Vector2) -> int:
	var best := -1
	var bd := 0.85
	var list := mess()
	for i in list.size():
		var d := Vector2(float(list[i][0]), float(list[i][1])).distance_to(lo)
		if d < bd:
			bd = d
			best = i
	return best


func _clean(i: int) -> void:
	var list := mess()
	if i < 0 or i >= list.size():
		return
	var kind: String = list[i][2]
	list.remove_at(i)
	m.owner_model.act("pet", 1.0)
	m._sfx("tik", -6.0, 1.2)
	_rebuild_mess()
	state.count("tidy")
	for k in m.agents:
		state.add_need(k, "clean", 3.0)
	if list.is_empty():
		for k in m.agents:
			state.add_need(k, "clean", 15.0)
			state.add_need(k, "fun", 10.0)
		m._pet_voice(m._active().kind, true)
		m.ui.toast("Ev tertemiz oldu! Hayvanların çok mutlu. (+temizlik, +mutluluk)")
	else:
		m.ui.toast("%s toplandı · %d dağınıklık kaldı" % [MESS_KINDS.get(kind, "Eşya"), list.size()])
	state.save_game()


# ---------------------------------------------------------------- yemek

func _near_stove(lo: Vector2) -> bool:
	return lo.distance_to(STOVE_STAND) < 0.9


func _has(recipe: String) -> bool:
	var bag := _bag()
	var need: Dictionary = RECIPES[recipe][1]
	for k in need:
		if int(bag.get(k, 0)) < int(need[k]):
			return false
	return true


func _need_text(recipe: String) -> String:
	var r: Array = RECIPES[recipe]
	var parts: Array = []
	for k in r[1]:
		parts.append("%s×%d" % [k, int(r[1][k])])
	var opt: Array = []
	for k in r[2]:
		opt.append(k)
	return ", ".join(parts) + ((" (+" + ", ".join(opt) + ")") if not opt.is_empty() else "")


func open_cook_panel() -> void:
	if _dish != "":
		_open_dish_panel()
		return
	var body: VBoxContainer = m.ui._open_panel("MUTFAK", "Malzemeler çantandan kullanılır. Eksikse marketten al.")
	for id in RECIPES:
		var r: Array = RECIPES[id]
		var key: String = id
		var ok := _has(key)
		var b: Button = m.ui._panel_item(body, ("%s · %s" % [r[0], _need_text(key)]) if ok else ("%s · eksik: %s" % [r[0], _need_text(key)]), func():
			if _has(key):
				m.ui.close_modal()
				start_cook(key)
			else:
				m.ui.toast("Malzeme eksik: %s. Marketten alabilirsin." % _need_text(key)))
		b.add_theme_font_size_override("font_size", 22)
		if not ok:
			b.modulate = Color(1, 1, 1, 0.55)
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func start_cook(recipe: String) -> void:
	if cooking or not RECIPES.has(recipe):
		return
	var r: Array = RECIPES[recipe]
	var bag := _bag()
	for k in r[1]:
		bag[k] = int(bag[k]) - int(r[1][k])
		if int(bag[k]) <= 0:
			bag.erase(k)
	var extra := false
	for k in r[2]:
		if int(bag.get(k, 0)) >= int(r[2][k]):
			bag[k] = int(bag[k]) - int(r[2][k])
			if int(bag[k]) <= 0:
				bag.erase(k)
			extra = true
	_recipe = recipe
	cooking = true
	_cook_t = 0.0
	m._moving = false
	m._queue.clear()
	var home := _home()
	m._place_owner(home.w2(STOVE_STAND))
	m.owner_node.rotation.y = home.rotation.y
	m.owner_model.speed = 0.0
	m.owner_model.act("cook", COOK_TIME)
	_build_food(recipe)
	_food.scale = Vector3.ONE * 0.05
	_flame.visible = true
	_steam.emitting = true
	if state.d.get("sound", true):
		_sizzle.play()
	m.ui.toast("%s pişiyor...%s" % [r[0], " (ekstra malzemeyle daha lezzetli!)" if extra else ""])
	state.d["cook_extra"] = extra


func _build_food(recipe: String) -> void:
	for c in _food.get_children():
		c.queue_free()
	var col: String = RECIPES[recipe][5]
	match recipe:
		"menemen":
			Kit.cyl(_food, 0.125, 0.125, 0.02, Vector3.ZERO, Kit.mat("d9472b", 0.5), 18)
			for k in 6:
				Kit.ball(_food, 0.035, Vector3(cos(k * 1.1) * 0.07, 0.012, sin(k * 1.1) * 0.07), Kit.mat("f2c94a", 0.5), Vector3(1.2, 0.4, 1.0), 8)
			for k in 4:
				Kit.box(_food, Vector3(0.04, 0.01, 0.015), Vector3(cos(k * 1.6 + 0.4) * 0.05, 0.016, sin(k * 1.6 + 0.4) * 0.05), Kit.mat("3f8a2c", 0.5), Vector3(0, k, 0))
		"makarna":
			var pm := Kit.mat(col, 0.5)
			for k in 18:
				Kit.capsule(_food, 0.008, 0.07, Vector3(cos(k * 2.4) * 0.07 * fmod(k * 0.37, 1.0), 0.01 + (k % 3) * 0.008, sin(k * 2.4) * 0.07 * fmod(k * 0.37, 1.0)), pm, Vector3(PI / 2, k * 0.7, 0))
		"tost":
			Kit.box(_food, Vector3(0.16, 0.04, 0.16), Vector3(0, 0.02, 0), Kit.mat(col, 0.7))
			Kit.box(_food, Vector3(0.165, 0.01, 0.165), Vector3(0, 0.02, 0), Kit.mat("f2d24a", 0.4))
		_:
			for k in 2:
				Kit.ball(_food, 0.035, Vector3(-0.04 + k * 0.08, 0.03, 0), Kit.mat(col, 0.4), Vector3(1, 1.25, 1), 10)


func _finish_cook() -> void:
	cooking = false
	_flame.visible = false
	_steam.emitting = false
	_sizzle.stop()
	_food.scale = Vector3.ONE
	_dish = _recipe
	state.count("cook")
	m._sfx("mutlu", -8.0)
	_open_dish_panel()


func _open_dish_panel() -> void:
	var r: Array = RECIPES[_dish]
	var pn: String = state.pet(m._active().kind)["name"]
	var body: VBoxContainer = m.ui._open_panel(String(r[0]).to_upper(), "Afiyet olsun! Ne yapmak istersin?")
	m.ui._panel_item(body, "Ye", func():
		m.ui.close_modal()
		eat_dish(_dish))
	if bool(r[4]):
		m.ui._panel_item(body, "%s'e Ver" % pn, func():
			m.ui.close_modal()
			_give_pet())
	m.ui._panel_item(body, "Çantaya Koy", func():
		var bag := _bag()
		bag[r[0]] = int(bag.get(r[0], 0)) + 1
		_clear_dish()
		m.ui.close_modal()
		m.ui.toast("%s çantana kondu, sonra yiyebilirsin." % r[0]))
	m.ui._focus_first(body)


func _clear_dish() -> void:
	_dish = ""
	for c in _food.get_children():
		c.queue_free()


func eat_dish(recipe: String) -> void:
	var r: Array = RECIPES[recipe]
	var gain := float(r[3]) + (10.0 if bool(state.d.get("cook_extra", false)) else 0.0)
	if _dish == recipe:
		_clear_dish()
	m.owner_model.act("eat", 2.4)
	if state.d.has("me"):
		m.needs.add("hunger", gain)
		m.needs.add("energy", 5.0)
		m.ui.toast("%s çok lezzetli oldu! Karnın doydu. (+%d tokluk)" % [r[0], int(gain)])
	else:
		m.ui.toast("%s çok lezzetli oldu! Ellerine sağlık." % r[0])
	state.save_game()


func _give_pet() -> void:
	var r: Array = RECIPES[_dish]
	var a: Node3D = m._active()
	var pn: String = state.pet(a.kind)["name"]
	state.add_need(a.kind, "hunger", 30.0)
	state.add_need(a.kind, "fun", 12.0)
	_clear_dish()
	m._pet_voice(a.kind, true)
	m.ui.toast("%s ev yapımı %s yedi, kuyruğunu sallıyor! (Baharatsız, ona uygun.)" % [pn, String(r[0]).to_lower()])
	state.save_game()


## Cantadan kullanim: cig malzemeyi geri koy, pismis yemegi ye. true donerse main baska bir sey yapmaz.
func use_item(name: String) -> bool:
	if INGREDIENTS.has(name):
		var bag := _bag()
		bag[name] = int(bag.get(name, 0)) + 1
		m.ui.toast("%s çiğ yenmez. Evde mutfakta ocağın önünde F ile yemek pişir." % name)
		return true
	for id in RECIPES:
		if RECIPES[id][0] == name:
			state.d["cook_extra"] = false
			eat_dish(id)
			return true
	return false


# ---------------------------------------------------------------- baglam ve komutlar

func context() -> Array:
	if not at_home() or cooking:
		return []
	var lo: Vector2 = _home().local2(m._owner_pos())
	if _near_stove(lo):
		if _dish != "":
			return ["Yemeği Al: %s" % RECIPES[_dish][0], "hl_cook", "heart"]
		return ["Yemek Pişir", "hl_cook", "drop"]
	var i := _nearest_mess(lo)
	if i >= 0:
		return ["Topla: %s" % MESS_KINDS.get(String(mess()[i][2]), "Eşya"), "hl_clean", "hand"]
	return []


func command(cmd: String) -> void:
	match cmd:
		"hl_cook":
			open_cook_panel()
		"hl_clean":
			if at_home():
				_clean(_nearest_mess(_home().local2(m._owner_pos())))
		"hl_shop":
			open_shop()


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	if m._mode != "play":
		return
	_mess_t -= dt
	if _mess_t <= 0.0:
		_mess_t = MESS_EVERY
		_spawn_mess()
	if not at_home():
		return
	_anim_t += dt
	if cooking:
		_cook_t += dt
		_food.scale = Vector3.ONE * clampf(_cook_t / (COOK_TIME * 0.7), 0.05, 1.0)
		_flame.scale = Vector3.ONE * (1.0 + 0.08 * sin(_anim_t * 23.0))
		if not m.owner_model.is_acting():
			m.owner_model.act("cook", COOK_TIME - _cook_t + 0.2)
		if _cook_t >= COOK_TIME:
			_finish_cook()
	for f in _fish:
		var n: Node3D = f[0]
		var ph: float = _anim_t * float(f[2]) + float(f[1])
		n.position = Vector3(sin(ph) * 0.38, 0.95 + 0.08 * sin(ph * 2.3), cos(ph * 0.7) * 0.08)
		n.rotation.y = PI if cos(ph) < 0.0 else 0.0
	# Evdeki esyalarin kucuk faydalari, daginik evin zarari (10 sn'de bir)
	_bonus_t += dt
	if _bonus_t >= 10.0:
		_bonus_t = 0.0
		var it := items()
		for k in m.agents:
			if it.has("yatak"):
				state.add_need(k, "energy", 1.0)
			if it.has("agac") or it.has("akvaryum"):
				state.add_need(k, "fun", 0.8)
			if mess().size() >= 6:
				state.add_need(k, "clean", -0.6)
