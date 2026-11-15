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
	"f_sazan": ["Fırın Sazan", {"Sazan": 1}, {"Domates": 1}, 55, true, "b88a3e"],
	"f_levrek": ["Izgara Levrek", {"Levrek": 1}, {"Biber": 1}, 55, true, "c9b48a"],
	"f_alabalik": ["Tava Alabalık", {"Alabalık": 1}, {"Domates": 1}, 50, true, "d68a6a"],
	"f_kefal": ["Kefal Tava", {"Kefal": 1}, {}, 40, true, "a8a89a"],
	"f_gumus": ["Çıtır Gümüş", {"Gümüş": 3}, {}, 30, true, "d8d2b0"],
	"f_yayin": ["Yayın Buğulama", {"Yayın": 1}, {"Domates": 1, "Biber": 1}, 75, true, "8a8a70"],
	"kofte": ["Izgara Köfte", {"Kıyma": 1}, {"Ekmek": 1}, 55, false, "7a3f24"],
	"patates": ["Fırında Patates", {"Patates": 2}, {"Biber": 1}, 40, true, "e0b04a"],
	"salata": ["Çoban Salata", {"Domates": 1, "Salatalık": 1}, {"Biber": 1}, 22, false, "d94a3a"],
}
const INGREDIENTS := ["Yumurta", "Domates", "Biber", "Makarna", "Peynir", "Sazan", "Levrek", "Alabalık", "Kefal", "Gümüş", "Yayın", "Kıyma", "Patates", "Salatalık"]

## Mobilya: kimlik -> [ad, fiyat, yer aciklamasi, yerel konum]
const FURNITURE := {
	"bitki": ["Saksı Bitkisi", 60, "salonun köşesine", Vector2(0.45, 11.1)],
	"lamba": ["Ayaklı Lamba", 90, "televizyonun yanına", Vector2(4.75, 11.2)],
	"hali": ["Desenli Halı", 120, "yatak odasına", Vector2(3.0, 6.3)],
	"tablo": ["Yağlı Boya Tablo", 150, "yatak odası duvarına", Vector2(5.93, 3.7)],
	"yatak": ["Evcil Hayvan Yatağı", 80, "salona", Vector2(1.25, 9.7)],
	"agac": ["Kedi Tırmalama Ağacı", 140, "küçük odaya", Vector2(11.5, 6.95)],
	"akvaryum": ["Akvaryum", 220, "salon duvarına", Vector2(4.2, 7.72)],
	"top_havuzu": ["Top Havuzu", 260, "oyun odasına", Vector2(10.2, 8.0)],
	"oyuncak": ["Oyuncak Sepeti", 70, "oyun odasına", Vector2(9.0, 8.7)],
	"tunel": ["Kedi Tüneli", 110, "oyun odasına", Vector2(11.2, 8.5)],
}
## Serbest yerlestirme: tablo duvara sabit, digerleri 0.25 m izgarada tasinip dondurulur.
const FIXED := ["tablo"]
const GRID := 0.25
## Carpisma yari boyutlari (yerel x, z)
const COL_HALF := {"bitki": Vector2(0.22, 0.22), "lamba": Vector2(0.16, 0.16), "agac": Vector2(0.3, 0.3), "akvaryum": Vector2(0.56, 0.22)}
## Oyun odasi esyalari: [oyun metni, eglence, bekleme]
const PLAY := {"agac": ["Kedi Ağacında Oyna", 22.0], "top_havuzu": ["Top Havuzunda Oyna", 32.0],
	"oyuncak": ["Oyuncaklarla Oyna", 18.0], "tunel": ["Tünelde Oyna", 20.0]}
const PLAY_COOLDOWN := 40.0

const WALL_COLORS := [["Beyaz", "ffffff"], ["Krem", "f1e2bd"], ["Nane", "bfe3cc"], ["Gökyüzü", "b9d6ee"],
	["Pudra Pembe", "f0c4cc"], ["Hardal", "e3bd55"], ["Lavanta", "cdbfe8"], ["Adaçayı", "a9c2a0"]]
const FLOOR_COLORS := [["Doğal Parke", "ffffff"], ["Koyu Ceviz", "8a6a58"], ["Küllü Meşe", "b9bcc2"],
	["Bal Rengi", "ffd9a0"], ["Abanoz", "5a5048"]]

## Balkon: saksilar korkuluk boyunca (yerel). Tohum: [ad, fiyat, cicek rengi, cicek acma gunu, govde boyu]
const POT_Z := [3.0, 3.6, 4.2, 4.8, 6.2, 6.9]
const POT_X := 0.32
const SEEDS := {
	"lale": ["Lale Tohumu", 6, "e0322b", 4, 0.42], "papatya": ["Papatya Tohumu", 5, "f7f3e6", 3, 0.4],
	"sumbul": ["Sümbül Tohumu", 8, "8a4ad9", 4, 0.38], "aycicegi": ["Ayçiçeği Tohumu", 10, "f2c21a", 5, 0.75],
}
const STAGES := ["Tohum", "Filiz", "Büyüyor", "Tomurcuk", "Çiçek açtı"]

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
var _balc_root: Node3D
var _pot_nodes: Array = []
var _play_cd := 0.0
var _balls: Array = []          # top havuzu patlamasi: [Node3D, hiz, omur]
var _edit := false
var _sel := ""
var _marker: MeshInstance3D
var _sel_btn: Button
var _anim_t := 0.0
var _cols: Array = []           # serbest esyalarin carpisma kenarlari


## Etkin evin kayit anahtari eki: asil ev "", EvBul evleri "_<ilan no>" (her evin esyasi ve daginikligi ayri).
func _key() -> String:
	var h := _home()
	return "_" + str(h.get("lid")) if h != null and h != m._home else ""


func items() -> Array:
	var k := "home_items" + _key()
	if not state.d.has(k) or typeof(state.d[k]) != TYPE_ARRAY:
		state.d[k] = []
	return state.d[k]


func mess() -> Array:
	var k := "home_mess" + _key()
	if not state.d.has(k) or typeof(state.d[k]) != TYPE_ARRAY:
		state.d[k] = [[7.0, 4.4, "tuy"], [3.0, 8.9, "top"], [5.0, 8.2, "tuy"]] if k == "home_mess" else []
	return state.d[k]


## Mobilyanin etkin evdeki yeri (EvBul evleri kendi yerlerini verir).
func _slot(id: String) -> Vector2:
	var h := _home()
	if h != null and h.get("furn_slots") != null and h.furn_slots.has(id):
		return h.furn_slots[id]
	return FURNITURE[id][3]


func _stove_stand() -> Vector2:
	var h := _home()
	return h.stove_stand if h != null and h.get("stove_stand") != null else STOVE_STAND


func _bag() -> Dictionary:
	var bag: Dictionary = state.d.get("bag", {})
	state.d["bag"] = bag
	return bag


## Etkin ev: icinde bulunulan EvBul evi (kiralik / satin alinmis) ya da asil ev.
func _home() -> Node3D:
	var h: Node3D = ParkMap.home
	if h != null and h != m._home and h.get("lived") == true:
		return h
	return m._home


func at_home() -> bool:
	return ParkMap.home != null and ParkMap.home == _home()


## Ic mekan silinmeden once (EvBul evinden cikarken) dugum baglantilarini birak.
func forget(home: Node3D) -> void:
	if _built_for != home:
		return
	cooking = false
	_built_for = null
	_root = null
	_furn_root = null
	_mess_root = null
	_cook_root = null
	_mess_nodes.clear()
	_fish.clear()


func busy() -> bool:
	return cooking


# ---------------------------------------------------------------- kurulum

## main._enter_home cagirir: evin icine esyalari, daginikligi ve pisirme sahnesini kur.
func on_home(home: Node3D) -> void:
	if _built_for == home:
		_rebuild_mess()
		_apply_paint()
		_rebuild_pots()
		return
	_built_for = home
	var old := home.get_node_or_null("EvHayati")
	if old != null:
		home.remove_child(old)
		old.queue_free()
	_mess_nodes.clear()
	_fish.clear()
	_root = Node3D.new()
	_root.name = "EvHayati"
	home.add_child(_root)
	_furn_root = Node3D.new()
	_root.add_child(_furn_root)
	_mess_root = Node3D.new()
	_root.add_child(_mess_root)
	_cook_root = Node3D.new()
	_root.add_child(_cook_root)
	if home.get("stove_pos") != null:
		_cook_root.position = home.stove_pos - Vector3(4.45, 0.93, 0.5)
	_balc_root = Node3D.new()
	_root.add_child(_balc_root)
	_build_cooking()
	_rebuild_furniture()
	_rebuild_mess()
	_apply_paint()
	_rebuild_pots()


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
		_furn_root.remove_child(c)
		c.queue_free()
	var home := _home()
	for seg in _cols:
		home.colliders.erase(seg)
	_cols.clear()
	_fish.clear()
	for id in items():
		if FURNITURE.has(id):
			_build_item(String(id))
	_update_marker()


## Esyanin yeri: [x, z, donus]  (kayitli ya da varsayilan)
func item_pr(id: String) -> Array:
	var hp: Dictionary = state.d.get("home_pos" + _key(), {})
	if hp.has(id) and hp[id] is Array and hp[id].size() >= 3:
		return [float(hp[id][0]), float(hp[id][1]), float(hp[id][2])]
	var d: Vector2 = _slot(id)
	var h := _home()
	var rot := float(h.furn_rot.get(id, 0.0)) if h != null and h.get("furn_rot") != null else 0.0
	return [d.x, d.y, rot]


func _build_item(id: String) -> void:
	var pr := item_pr(id)
	var p := Vector2(pr[0], pr[1])
	var r := Kit.pivot(_furn_root, Vector3(p.x, 0, p.y))
	if not FIXED.has(id):
		r.rotation.y = pr[2]
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
		"top_havuzu":
			var rim := Kit.mat("3f8fd9", 0.6)
			Kit.cyl(r, 0.62, 0.62, 0.05, Vector3(0, 0.03, 0), Kit.mat("2a5f9a", 0.8), 24)
			Kit.torus(r, 0.54, 0.68, Vector3(0, 0.22, 0), rim)
			var cols := ["e0322b", "f2c21a", "3fb5e0", "58a24c", "e07bb4", "f28a1a"]
			for k in 26:
				var a := k * 2.399
				var rr := 0.5 * sqrt(fmod(k * 0.173 + 0.1, 1.0))
				Kit.ball(r, 0.075, Vector3(cos(a) * rr, 0.12 + 0.05 * (k % 3), sin(a) * rr), Kit.mat(cols[k % 6], 0.4), Vector3.ONE, 8)
		"oyuncak":
			Kit.cyl(r, 0.24, 0.2, 0.3, Vector3(0, 0.15, 0), Kit.mat("b98a4a", 1.0), 14)
			Kit.torus(r, 0.21, 0.25, Vector3(0, 0.3, 0), Kit.mat("8a5f2a", 1.0))
			Kit.ball(r, 0.07, Vector3(-0.08, 0.36, 0.05), Kit.mat("e0322b", 0.5), Vector3.ONE, 10)
			Kit.ball(r, 0.06, Vector3(0.1, 0.35, -0.04), Kit.mat("3fb5e0", 0.5), Vector3.ONE, 10)
			Kit.capsule(r, 0.022, 0.2, Vector3(0.02, 0.4, 0.1), Kit.mat("f1e8d0", 0.7), Vector3(0.5, 0, 1.2))
		"tunel":
			var tm := Kit.mat("e0a63a", 0.9)
			Kit.cyl(r, 0.22, 0.22, 0.9, Vector3(0, 0.22, 0), tm, 16, Vector3(0, 0, PI / 2))
			for k in 4:
				Kit.torus(r, 0.2, 0.24, Vector3(-0.33 + k * 0.22, 0.22, 0), Kit.mat("a8741f", 0.9), Vector3(0, 0, PI / 2))
			Kit.ball(r, 0.03, Vector3(0.0, 0.46, 0.0), Kit.mat("e0322b", 0.6))
	var half: Vector2 = COL_HALF.get(id, Vector2.ZERO)
	if half != Vector2.ZERO:
		var seg := _square(p, half.x, half.y, pr[2])
		_cols.append_array(seg)
		_home().colliders.append_array(seg)


func _square(c: Vector2, hx: float, hz := -1.0, rot := 0.0) -> Array:
	var h := Vector2(hx, hz if hz > 0.0 else hx)
	var pts := []
	for q in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
		pts.append(c + q.rotated(-rot))
	var out: Array = []
	for i in 4:
		out.append([pts[i], pts[(i + 1) % 4]])
	return out


## Telefon uygulamasi: Mobilya magazasi.
func open_shop() -> void:
	var body: VBoxContainer = m.ui._open_page("YUVAM MOBİLYA", "Cüzdan: %d ₺  ·  Aldığın eşya evindeki yerine yerleşir; sonra taşıyıp döndürebilirsin." % int(state.d["coins"]))
	m.ui._menu_item(body, "YERLEŞTİRME MODU (TAŞI · DÖNDÜR)", func(): start_edit())
	m.ui._menu_item(body, "DUVAR RENGİ  ·  %s" % String(WALL_COLORS[_wall_i()][0]).to_upper(), func(): open_paint("wall"))
	m.ui._menu_item(body, "ZEMİN RENGİ  ·  %s" % String(FLOOR_COLORS[_floor_i()][0]).to_upper(), func(): open_paint("floor"))
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
	m.ui.toast("%s alındı! Evinde %s yerleştirildi." % [f[0], f[2]] if _key() == "" else "%s alındı ve bu evdeki yerine yerleştirildi." % f[0])
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
	var h := _home()
	var spots: Array = h.mess_spots if h != null and h.get("mess_spots") != null else MESS_SPOTS
	for s in spots:
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
	return lo.distance_to(_stove_stand()) < 0.9


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
		if key.begins_with("f_") and not ok:
			continue
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
	m._place_owner(home.w2(_stove_stand()))
	m.owner_node.rotation.y = home.rotation.y + (float(home.stove_yaw) if home.get("stove_yaw") != null else 0.0)
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
	if not at_home() or cooking or _edit:
		return []
	var lo: Vector2 = _home().local2(m._owner_pos())
	if _near_stove(lo):
		if _dish != "":
			return ["Yemeği Al: %s" % RECIPES[_dish][0], "hl_cook", "heart"]
		return ["Yemek Pişir", "hl_cook", "drop"]
	var pi := _nearest_pot(lo)
	if pi >= 0:
		var pc := _pot_context(pi)
		if not pc.is_empty():
			return pc
	var pl := _nearest_play(lo)
	if pl != "" and _play_cd <= 0.0:
		return [PLAY[pl][0], "hl_play", "paw"]
	var i := _nearest_mess(lo)
	if i >= 0:
		return ["Topla: %s" % MESS_KINDS.get(String(mess()[i][2]), "Eşya"), "hl_clean", "hand"]
	return []


func command(cmd: String) -> void:
	match cmd:
		"hl_pot":
			if at_home():
				_pot_action(_nearest_pot(_home().local2(m._owner_pos())))
		"hl_play":
			if at_home():
				_play(_nearest_play(_home().local2(m._owner_pos())))
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
	if _play_cd > 0.0:
		_play_cd -= dt
	if not at_home():
		return
	_anim_t += dt
	if _edit and m.ui._modal == null:
		_end_edit()
	_update_balls(dt)
	if _marker != null and _marker.visible:
		_marker.scale = Vector3.ONE * (1.0 + 0.06 * sin(_anim_t * 6.0))
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
			if it.has("top_havuzu") or it.has("oyuncak") or it.has("tunel"):
				state.add_need(k, "fun", 0.6)
			if mess().size() >= 6:
				state.add_need(k, "clean", -0.6)


# ---------------------------------------------------------------- duvar ve zemin rengi

func _wall_i() -> int:
	return clampi(int(state.d.get("home_wall", 0)), 0, WALL_COLORS.size() - 1)


func _floor_i() -> int:
	return clampi(int(state.d.get("home_floor", 0)), 0, FLOOR_COLORS.size() - 1)


func _apply_paint() -> void:
	var home := _home()
	if home == null or not home.has_method("_mat"):
		return
	home._mat("siva").albedo_color = Color(String(WALL_COLORS[_wall_i()][1]))
	home._mat("parke").albedo_color = Color(String(FLOOR_COLORS[_floor_i()][1]))


func open_paint(what: String) -> void:
	var wall := what == "wall"
	var list: Array = WALL_COLORS if wall else FLOOR_COLORS
	var cur := _wall_i() if wall else _floor_i()
	var body: VBoxContainer = m.ui._open_page("DUVAR RENGİ" if wall else "ZEMİN RENGİ", "Seçtiğin renk evindeki odalara hemen uygulanır. Boya ücretsiz.")
	for i in list.size():
		var idx := i
		m.ui._menu_item(body, "%s%s" % [String(list[i][0]).to_upper(), "  ✓" if i == cur else ""], func():
			state.d["home_wall" if wall else "home_floor"] = idx
			_apply_paint()
			state.save_game()
			m._sfx("tik", -6.0, 1.0)
			m.ui.toast("%s: %s" % ["Duvarlar" if wall else "Zemin", list[idx][0]])
			open_paint(what))
	m.ui._menu_item(body, "GERİ", func(): open_shop())
	m.ui._focus_first(body)


# ---------------------------------------------------------------- serbest yerlestirme

func _movable() -> Array:
	var out: Array = []
	for id in items():
		if FURNITURE.has(id) and not FIXED.has(id):
			out.append(String(id))
	return out


func start_edit() -> void:
	if not at_home():
		m.ui.toast("Eşyaları yerleştirmek için evinde olmalısın.")
		return
	var mv := _movable()
	if mv.is_empty():
		m.ui.toast("Henüz taşıyacak eşyan yok. Önce mobilya al.")
		return
	_edit = true
	if _sel == "" or not mv.has(_sel):
		_sel = mv[0]
	_open_edit_panel()
	_update_marker()


func _open_edit_panel() -> void:
	var sub := "I J K L taşı · U O döndür · Enter bitir · zemine tıkla: oraya koy." if not DisplayServer.is_touchscreen_available() else "Okları kullan ya da zemine dokun: eşya oraya gider."
	var body: VBoxContainer = m.ui._open_panel("YERLEŞTİRME", sub)
	_sel_btn = m.ui._panel_item(body, "", func(): _cycle(1))
	_sel_btn.text = _sel_text()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	body.add_child(row)
	for d in [["◀", Vector2(-1, 0)], ["▲", Vector2(0, -1)], ["▼", Vector2(0, 1)], ["▶", Vector2(1, 0)]]:
		var dv: Vector2 = d[1]
		_small_btn(row, d[0], func(): _nudge(dv))
	_small_btn(row, "⟲", func(): _rotate(-PI / 4.0))
	_small_btn(row, "⟳", func(): _rotate(PI / 4.0))
	m.ui._panel_item(body, "İlk Yerine Koy", func(): _reset_sel())
	m.ui._panel_item(body, "Bitti", func(): m.ui.close_modal())


func _small_btn(row: HBoxContainer, t: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(62, 52)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	row.add_child(b)


func _sel_text() -> String:
	return "Seçili: %s  (değiştir)" % String(FURNITURE[_sel][0])


func _cycle(dir: int) -> void:
	var mv := _movable()
	if mv.is_empty():
		return
	var i := mv.find(_sel)
	_sel = mv[posmod(i + dir, mv.size())]
	if _sel_btn != null:
		_sel_btn.text = _sel_text()
	_update_marker()
	m._sfx("tik", -8.0, 1.1)


func _end_edit() -> void:
	_edit = false
	_sel_btn = null
	if _marker != null:
		_marker.visible = false
	state.save_game()
	m.ui.toast("Yerleşim kaydedildi.")


## Ekran yonunu (sag=+x, yukari=-y) evin yerel eksenine cevirir (kamera yonune gore, en yakin eksen).
func _screen_dir(sd: Vector2) -> Vector2:
	var cam: Camera3D = m.cam
	if cam == null:
		return sd
	var b := cam.global_transform.basis
	var fwd := Vector3(-b.z.x, 0, -b.z.z)
	if fwd.length() < 0.2:
		fwd = Vector3(b.y.x, 0, b.y.z)
	fwd = fwd.normalized()
	var right := Vector3(b.x.x, 0, b.x.z).normalized()
	var w := right * sd.x + fwd * (-sd.y)
	var l := Basis(Vector3.UP, _home().rotation.y).inverse() * w
	var v := Vector2(l.x, l.z)
	if absf(v.x) >= absf(v.y):
		return Vector2(signf(v.x), 0)
	return Vector2(0, signf(v.y))


func _nudge(sd: Vector2) -> void:
	if not _edit or _sel == "":
		return
	var pr := item_pr(_sel)
	_place_sel(Vector2(pr[0], pr[1]) + _screen_dir(sd) * GRID, pr[2])


func _place_sel(np: Vector2, rot: float) -> void:
	np = np.snapped(Vector2(GRID, GRID))
	if not _home().has_point(_home().w2(np)):
		m.ui.toast("Buraya konmaz, oda dışında.")
		return
	var hp: Dictionary = state.d.get("home_pos" + _key(), {})
	hp[_sel] = [np.x, np.y, rot]
	state.d["home_pos" + _key()] = hp
	_rebuild_furniture()
	m._sfx("tik", -9.0, 0.9)


func _rotate(a: float) -> void:
	if not _edit or _sel == "":
		return
	var pr := item_pr(_sel)
	_place_sel(Vector2(pr[0], pr[1]), wrapf(pr[2] + a, -PI, PI))


func _reset_sel() -> void:
	var hp: Dictionary = state.d.get("home_pos" + _key(), {})
	hp.erase(_sel)
	state.d["home_pos" + _key()] = hp
	_rebuild_furniture()
	m.ui.toast("%s ilk yerine kondu." % FURNITURE[_sel][0])


func _update_marker() -> void:
	if not _edit or _sel == "" or _root == null:
		if _marker != null:
			_marker.visible = false
		return
	if _marker == null:
		_marker = Kit.torus(_root, 0.42, 0.5, Vector3.ZERO, Kit.glow("ffd23a", 2.5))
	var pr := item_pr(_sel)
	_marker.position = Vector3(pr[0], 0.04, pr[1])
	_marker.visible = true


func _input(e: InputEvent) -> void:
	if not _edit or not (e is InputEventKey) or not e.pressed:
		return
	var k: InputEventKey = e
	var handled := true
	match k.keycode:
		KEY_I: _nudge(Vector2(0, -1))
		KEY_K: _nudge(Vector2(0, 1))
		KEY_J: _nudge(Vector2(-1, 0))
		KEY_L: _nudge(Vector2(1, 0))
		KEY_U: _rotate(-PI / 4.0)
		KEY_O: _rotate(PI / 4.0)
		KEY_TAB: _cycle(1)
		KEY_ENTER, KEY_KP_ENTER: m.ui.close_modal()
		KEY_DELETE, KEY_BACKSPACE: _reset_sel()
		_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _unhandled_input(e: InputEvent) -> void:
	if not _edit or not (e is InputEventMouseButton) or not e.pressed or e.button_index != MOUSE_BUTTON_LEFT:
		return
	var cam: Camera3D = m.cam
	if cam == null or _sel == "":
		return
	var o := cam.project_ray_origin(e.position)
	var d := cam.project_ray_normal(e.position)
	if absf(d.y) < 0.001:
		return
	var t := (_home().global_position.y - o.y) / d.y
	if t <= 0.0:
		return
	var hit := o + d * t
	var pr := item_pr(_sel)
	_place_sel(_home().local2(Vector2(hit.x, hit.z)), pr[2])


# ---------------------------------------------------------------- oyun odasi

func _nearest_play(lo: Vector2) -> String:
	var best := ""
	var bd := 1.2
	for id in items():
		if not PLAY.has(id):
			continue
		var pr := item_pr(String(id))
		var d := Vector2(pr[0], pr[1]).distance_to(lo)
		if d < bd:
			bd = d
			best = String(id)
	return best


func _play(id: String) -> void:
	if id == "" or _play_cd > 0.0 or state.owned_pets().is_empty():
		return
	_play_cd = PLAY_COOLDOWN
	var pr := item_pr(id)
	var c := Vector2(pr[0], pr[1])
	var home := _home()
	var i := 0
	for k in m.agents:
		m.agents[k].place(home.w2(c + Vector2(0.75 - 0.5 * i, 0.55).rotated(-pr[2])))
		state.add_need(k, "fun", float(PLAY[id][1]))
		state.add_need(k, "energy", -4.0)
		i += 1
	m.owner_model.act("pet", 1.4)
	m._pet_voice(m._active().kind, true)
	m._sfx("mutlu", -8.0)
	state.count("playroom")
	if id == "top_havuzu":
		_burst(c)
	m.ui.toast("%s! Hayvanların çok eğleniyor. (+eğlence)" % PLAY[id][0])
	state.save_game()


func _burst(c: Vector2) -> void:
	var cols := ["e0322b", "f2c21a", "3fb5e0", "58a24c", "e07bb4"]
	for k in 12:
		var b := Kit.ball(_root, 0.07, Vector3(c.x, 0.3, c.y), Kit.mat(cols[k % 5], 0.4), Vector3.ONE, 8)
		var a := k * 0.52
		_balls.append([b, Vector3(cos(a) * 0.9, 2.2 + (k % 3) * 0.5, sin(a) * 0.9), 2.4])


func _update_balls(dt: float) -> void:
	for i in range(_balls.size() - 1, -1, -1):
		var e: Array = _balls[i]
		var n: Node3D = e[0]
		var v: Vector3 = e[1]
		v.y -= 9.0 * dt
		n.position += v * dt
		if n.position.y < 0.08:
			n.position.y = 0.08
			v.y = absf(v.y) * 0.45
			v.x *= 0.7
			v.z *= 0.7
		e[1] = v
		e[2] = float(e[2]) - dt
		if e[2] <= 0.0:
			n.queue_free()
			_balls.remove_at(i)


# ---------------------------------------------------------------- balkon cicekleri

func pots() -> Array:
	var b = state.d.get("balcony", null)
	if typeof(b) != TYPE_ARRAY or b.size() != POT_Z.size():
		b = []
		for k in POT_Z.size():
			b.append({})
		state.d["balcony"] = b
	return b


func _today() -> String:
	return Time.get_date_string_from_system()


## Gelisim evresi 0..4 (sulanan gun sayisina gore); 4 = cicek acti; -1 = bos saksi
func pot_stage(pot: Dictionary) -> int:
	if pot.is_empty():
		return -1
	var need: int = int(SEEDS[pot["seed"]][3])
	var days := int(pot.get("days", 0))
	if days >= need:
		return 4
	if days <= 0:
		return 0
	return mini(3, 1 + int(float(days) * 3.0 / float(need)))


## Uc gunden uzun suz kalan bitki solar (sulaninca toparlanir).
func pot_wilted(pot: Dictionary) -> bool:
	if pot.is_empty() or pot_stage(pot) == 4:
		return false
	var t := float(pot.get("t", 0.0))
	return Time.get_unix_time_from_system() - t > 3.0 * 86400.0


func _rebuild_pots() -> void:
	if _balc_root == null:
		return
	if _key() != "":     # balkon cicekleri yalnizca asil evde
		return
	for c in _balc_root.get_children():
		_balc_root.remove_child(c)
		c.queue_free()
	_pot_nodes.clear()
	var list := pots()
	for i in POT_Z.size():
		var r := Kit.pivot(_balc_root, Vector3(POT_X, 0.0, POT_Z[i]))
		_pot_nodes.append(r)
		Kit.cyl(r, 0.17, 0.12, 0.3, Vector3(0, 0.15, 0), Kit.mat("b5553a", 0.8), 14)
		Kit.torus(r, 0.15, 0.19, Vector3(0, 0.3, 0), Kit.mat("a24a31", 0.8))
		Kit.cyl(r, 0.15, 0.15, 0.02, Vector3(0, 0.31, 0), Kit.mat("3b2a1d", 1.0), 14)
		_build_plant(r, list[i])


func _build_plant(r: Node3D, pot: Dictionary) -> void:
	var stage := pot_stage(pot)
	if stage < 0:
		return
	var seed_d: Array = SEEDS[pot["seed"]]
	var wilt := pot_wilted(pot)
	var green := Kit.mat("8a7a3a" if wilt else "3f8a3c", 0.7)
	var green2 := Kit.mat("7a6a32" if wilt else "2f6e2e", 0.7)
	var base := 0.32
	var full: float = float(seed_d[4])
	var h: float = [0.0, 0.25, 0.5, 0.75, 1.0][stage] * full
	if stage == 0:
		Kit.ball(r, 0.05, Vector3(0, base + 0.01, 0), Kit.mat("5a4030", 1.0), Vector3(1.3, 0.5, 1.3), 8)
		return
	var top := Kit.pivot(r, Vector3(0, base, 0))
	top.rotation.z = 0.35 if wilt else 0.0
	Kit.cyl(top, 0.012, 0.016, h, Vector3(0, h * 0.5, 0), green, 6)
	var nl := 2 + stage
	for k in nl:
		var ly := h * (0.25 + 0.5 * float(k) / float(nl))
		var lf := Kit.pivot(top, Vector3(0, ly, 0))
		lf.rotation.y = k * 2.4
		var leaf := Kit.ball(lf, 0.06 + 0.012 * stage, Vector3(0.07, 0, 0), green if k % 2 == 0 else green2, Vector3(1.5, 0.25, 0.7), 8)
		leaf.rotation.z = -1.1 if wilt else -0.5
	if stage == 3:
		Kit.ball(top, 0.045, Vector3(0, h + 0.02, 0), Kit.mat(String(seed_d[2]), 0.6), Vector3(0.9, 1.3, 0.9), 8)
	elif stage == 4:
		var fh := Kit.pivot(top, Vector3(0, h, 0))
		var sun: bool = pot["seed"] == "aycicegi"
		var pm := Kit.mat(String(seed_d[2]), 0.55)
		var n := 12 if sun else 8
		var rad := 0.1 if sun else 0.065
		for k in n:
			var a := k * TAU / float(n)
			Kit.ball(fh, rad * 0.55, Vector3(cos(a) * rad, sin(a) * rad, 0), pm, Vector3(1.0, 1.0, 0.35), 8)
		Kit.ball(fh, rad * (0.8 if sun else 0.5), Vector3(0, 0, 0.01), Kit.mat("5a3a1c" if sun else "f2b21a", 0.7), Vector3(1, 1, 0.5), 10)
		fh.rotation.x = 0.9 if sun else 0.0


func _nearest_pot(lo: Vector2) -> int:
	if _key() != "" or lo.x > 1.5 or lo.y < 2.5 or lo.y > 7.4:
		return -1
	var best := -1
	var bd := 0.95
	for i in POT_Z.size():
		var d := Vector2(POT_X, POT_Z[i]).distance_to(lo)
		if d < bd:
			bd = d
			best = i
	return best


func _seed_name(pot: Dictionary) -> String:
	return String(SEEDS[pot["seed"]][0]).replace(" Tohumu", "")


func _pot_context(i: int) -> Array:
	var pot: Dictionary = pots()[i]
	var st := pot_stage(pot)
	if st < 0:
		return ["Tohum Ek", "hl_pot", "plus"]
	if st == 4:
		return ["Çiçeği Kopar: %s" % _seed_name(pot), "hl_pot", "hand"]
	if pot.get("last", "") != _today():
		return ["Sula: %s (%s)" % [_seed_name(pot), STAGES[st]], "hl_pot", "drop"]
	return []


func _pot_action(i: int) -> void:
	if i < 0:
		return
	var pot: Dictionary = pots()[i]
	var st := pot_stage(pot)
	if st < 0:
		_open_plant_panel(i)
	elif st == 4:
		_harvest(i)
	elif pot.get("last", "") != _today():
		_water(i)


func _open_plant_panel(i: int) -> void:
	var body: VBoxContainer = m.ui._open_panel("SAKSI", "Ne ekmek istersin? Tohumları telefondaki Çiçekçi'den alırsın.")
	var bag := _bag()
	var any := false
	for id in SEEDS:
		var key: String = id
		var nm: String = SEEDS[id][0]
		var cnt := int(bag.get(nm, 0))
		if cnt > 0:
			any = true
			m.ui._panel_item(body, "%s ×%d  ·  %d günde açar" % [nm, cnt, int(SEEDS[id][3])], func(): _plant(i, key))
	if not any:
		m.ui._panel_item(body, "Tohumun yok · Çiçekçi'ye bak", func():
			m.ui.close_modal()
			open_flower_shop())
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _plant(i: int, seed_id: String) -> void:
	var bag := _bag()
	var nm: String = SEEDS[seed_id][0]
	if int(bag.get(nm, 0)) <= 0:
		return
	bag[nm] = int(bag[nm]) - 1
	if int(bag[nm]) <= 0:
		bag.erase(nm)
	pots()[i] = {"seed": seed_id, "days": 0, "last": "", "t": Time.get_unix_time_from_system()}
	m.ui.close_modal()
	m.owner_model.act("pet", 1.2)
	m._sfx("tik", -6.0, 0.8)
	_rebuild_pots()
	m.ui.toast("%s ekildi. Her gün sulamayı unutma!" % nm.replace(" Tohumu", ""))
	state.save_game()


func _water(i: int) -> void:
	var pot: Dictionary = pots()[i]
	var was_wilted := pot_wilted(pot)
	pot["days"] = int(pot.get("days", 0)) + 1
	pot["last"] = _today()
	pot["t"] = Time.get_unix_time_from_system()
	m.owner_model.act("pet", 1.4)
	m._sfx("tik", -8.0, 0.7)
	state.count("plant")
	_rebuild_pots()
	var st := pot_stage(pot)
	var nm := _seed_name(pot)
	if was_wilted:
		m.ui.toast("%s toparlandı, su iyi geldi." % nm)
	elif st == 4:
		m.ui.toast("%s çiçek açtı! Kopar ya da bırak, süs olsun." % nm)
	else:
		m.ui.toast("%s sulandı · evre: %s. Yarın yine su ver." % [nm, STAGES[st]])
	state.save_game()


func _harvest(i: int) -> void:
	var pot: Dictionary = pots()[i]
	var nm := _seed_name(pot)
	var gain := 12 + int(SEEDS[pot["seed"]][1]) * 2
	state.d["coins"] += gain
	pots()[i] = {}
	m.owner_model.act("pet", 1.2)
	m._sfx("kasa", -8.0)
	for k in m.agents:
		state.add_need(k, "fun", 6.0)
	_rebuild_pots()
	state.changed.emit()
	m.ui.toast("%s demeti çiçekçiye gitti: +%d ₺. Saksı yeniden boş." % [nm, gain])
	state.save_game()


## Telefon uygulamasi: Cicekci (tohum satisi)
func open_flower_shop() -> void:
	var body: VBoxContainer = m.ui._open_page("YEŞİL PARMAK ÇİÇEKÇİ", "Cüzdan: %d ₺  ·  Tohumlar çantana gelir. Evin balkonundaki saksılara F ile ek, her gün sula." % int(state.d["coins"]))
	var bag := _bag()
	for id in SEEDS:
		var key: String = id
		var f: Array = SEEDS[id]
		m.ui._menu_item(body, "%s  ·  %d ₺  ·  %d günde açar  (çantada: %d)" % [String(f[0]).to_upper(), int(f[1]), int(f[3]), int(bag.get(f[0], 0))], func(): _buy_seed(key))
	m.ui._menu_item(body, "KAPAT", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _buy_seed(id: String) -> void:
	var f: Array = SEEDS[id]
	if not state.spend(int(f[1])):
		m.ui.toast("Paran yetmiyor: %s %d ₺." % [f[0], int(f[1])])
		return
	var bag := _bag()
	bag[f[0]] = int(bag.get(f[0], 0)) + 1
	m._sfx("kasa", -6.0)
	state.save_game()
	m.ui.toast("%s çantana kondu." % f[0])
	open_flower_shop()


## Hata ayiklama: --decor / --balcony
func debug_setup(what: String) -> void:
	for fid in FURNITURE:
		if not items().has(fid):
			items().append(fid)
	state.d["home_wall"] = 2
	state.d["home_floor"] = 2
	state.d["home_pos"] = {"top_havuzu": [10.0, 8.25, 0.4], "agac": [9.5, 7.0, 0.8], "bitki": [3.0, 9.0, 0.0], "oyuncak": [9.25, 8.75, 0.5]}
	var l := pots()
	var today := _today()
	var now := Time.get_unix_time_from_system()
	l[0] = {"seed": "lale", "days": 0, "last": "", "t": now}
	l[1] = {"seed": "papatya", "days": 1, "last": today, "t": now}
	l[2] = {"seed": "sumbul", "days": 3, "last": today, "t": now}
	l[3] = {"seed": "lale", "days": 4, "last": today, "t": now}
	l[4] = {"seed": "aycicegi", "days": 5, "last": today, "t": now}
	l[5] = {"seed": "papatya", "days": 1, "last": "2020-01-01", "t": now - 5.0 * 86400.0}
	_apply_paint()
	_rebuild_furniture()
	_rebuild_pots()
	if what == "decor":
		_sel = "top_havuzu"
		start_edit()
	print("DEKOR ", WALL_COLORS[_wall_i()][0], "/", FLOOR_COLORS[_floor_i()][0], " saksi=", pots().map(func(p): return pot_stage(p)))
