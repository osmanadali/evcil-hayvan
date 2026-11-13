extends Node
## Evcil hayvan bakimi artilari:
## - Tasma (L ya da hayvan menusu): elden tasmaya sarkan ip cizilir, hayvan 2.5 m'den uzaklasamaz.
##   Tasmasizken sokakta ara sira guvercin surusunu ya da sokak kedisini kovalar; R ile geri cagrilir.
## - Guvercin suruleri: meydanlarda/parkta yemlenir, biri yaklasinca kanat cirpip havalanir, sonra geri doner.
## - Egitim (T ya da telefon): Otur, Pati ver, Yat, Don, Bekle numaralari sirayla, odul biskuvisiyle ogretilir.
##   Ogrenilenler state.pet(kind)["tricks"] icinde kalir ve istendiginde yaptirilir.
## - Pati Yuvasi barinagi: parkta citli bahce, kulubeler, sahiplendirilmeyi bekleyen kedi ve kopekler.
##   Kapida F: sahiplenme paneli.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PetModel = preload("res://scripts/pet_model.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const PetAgent = preload("res://scripts/pet_agent.gd")
const F_TITLE := preload("res://assets/fonts/Bangers-Regular.ttf")

const LEASH_LEN := 2.5
# [kimlik, ad, kac tekrar]
const TRICKS := [["otur", "Otur", 3], ["pati", "Pati ver", 4], ["yat", "Yat", 4], ["don", "Dön", 5], ["bekle", "Bekle", 5]]
# Barinaktaki hayvanlar: [kimlik, tur, ad, yas, renk, boy, huy]
const ADOPTABLES := [
	["karabas", "kopek", "Karabaş", "3 yaşında", "6b5a4c", 1.05, "Sakin, çok sadık"],
	["findik", "kopek", "Fındık", "6 aylık", "c99a68", 0.8, "Oyuncu bir yavru"],
	["pasa", "kopek", "Paşa", "5 yaşında", "efe3cc", 1.15, "Kocaman ve uysal"],
	["boncuk", "kedi", "Boncuk", "2 yaşında", "f2b27a", 1.0, "Kucak sever"],
	["duman", "kedi", "Duman", "4 yaşında", "9aa0aa", 1.05, "Biraz utangaç"],
	["tarcin", "kedi", "Tarçın", "8 aylık", "d98a50", 0.8, "Meraklı ve hızlı"],
]

var m: Node        # main
var state: Node

var shelter: Dictionary = {}     # {root, pos, yaw, gate, animals: [...], keeper}
var flocks: Array = []           # [{pos, birds, mode, t}]
var stray: Dictionary = {}       # sokak kedisi {node, home, pos, mode, t, target}
var chase: Dictionary = {}       # {kind, what: "flock"/"cat", i, t, phase}
var _chase_cd := 40.0
var _trick: Dictionary = {}      # {agent, id, t}
var _ropes := {}                 # kind -> MeshInstance3D
var _rope_mat: StandardMaterial3D
var _clips := {}                 # kind -> MeshInstance3D (tasma kancasi)
var _bird_mats: Array = []
var _rng := RandomNumberGenerator.new()


func leashed() -> bool:
	return bool(state.d.get("leash", false))


# ---------------------------------------------------------------- kurulum

func build() -> void:
	_rng.seed = 4242
	_rope_mat = StandardMaterial3D.new()
	_rope_mat.albedo_color = Color("c0392b")
	_rope_mat.roughness = 0.55
	_rope_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bird_mats = [Kit.mat("8a8f9a", 0.85), Kit.mat("6f7480", 0.85), Kit.mat("4d6b62", 0.4), Kit.mat("2a2c30", 0.6),
		Kit.mat("c9c3b8", 0.85), Kit.mat("e08a3a", 0.5)]
	if ParkMap.zone == "" and ParkMap.has_spot("baslangic"):
		_build_shelter()
	_build_flocks()
	_build_stray()
	print("EVCIL BAKIM barinak=%s suru=%d kedi=%s" % [shelter.get("pos", "yok"), flocks.size(), not stray.is_empty()])


func _ok(p: Vector2, r: float, road_gap: float) -> bool:
	var w: Node3D = m.world
	if not ParkMap.inside_bounds(p, 12.0) or not w.is_free(p, r) or w._inside_building(p):
		return false
	if ParkMap.water_sd(p) < r + 2.0:
		return false
	if road_gap > 0.0 and w._road_point(p).distance_to(p) < road_gap:
		return false
	for k in 12:
		if not w.is_free(p + Vector2.from_angle(k * TAU / 12.0) * r * 0.85, 0.3):
			return false
	return true


## Egimi az, bos bir yer.
func _flat_spot(p: Vector2, r: float, road_gap: float, max_rad := 40) -> Vector2:
	var best := Vector2.INF
	var best_s := 1e9
	for rad in range(0, max_rad, 3):
		for k in (1 if rad == 0 else 14):
			var q := p + Vector2.from_angle(k * TAU / 14.0 + rad * 0.37) * float(rad)
			if not _ok(q, r, road_gap):
				continue
			var lo := 1e9
			var hi := -1e9
			for j in 9:
				var h := ParkMap.terrain_height(q + (Vector2.ZERO if j == 8 else Vector2.from_angle(j * TAU / 8.0) * r))
				lo = minf(lo, h)
				hi = maxf(hi, h)
			var s := (hi - lo) + float(rad) * 0.02
			if s < best_s:
				best_s = s
				best = q
		if best_s < 0.35:
			break
	return best


func _yaw(face: Vector2) -> float:
	return atan2(face.x, face.y)


## Barinak yerel koordinati (x sag, y = +z on) -> dunya
func _sw(l: Vector2) -> Vector2:
	return shelter["pos"] + l.rotated(-shelter["yaw"])


# ---------------------------------------------------------------- barinak

func _build_shelter() -> void:
	var b: Vector2 = ParkMap.spot("baslangic")
	var p := _flat_spot(b + Vector2(58.0, 12.0), 7.6, 3.0)
	if p == Vector2.INF:
		return
	var face: Vector2 = (b - p).normalized()
	var yaw := _yaw(face)
	var w: Node3D = m.world
	var r: Node3D = w._root(p, yaw)
	shelter = {"root": r, "pos": p, "yaw": yaw, "animals": [], "base": w.gy(p)}
	var wall := Kit.mat("eadfc6", 0.9)
	var trim := Kit.mat("2f6f4f", 0.7)
	var wood := Kit.mat("8a5a34", 0.85)
	var dark := Kit.mat("2a2420", 0.9)
	var glass := Kit.mat("9cc4d6", 0.15)
	# Zemin: cakil bahce ve kaldirim
	Kit.box(r, Vector3(9.4, 0.3, 8.6), Vector3(0, -0.1, 0.9), Kit.mat("cbb48a", 0.95))
	Kit.box(r, Vector3(9.6, 0.32, 0.5), Vector3(0, -0.09, 5.3), Kit.mat("9b968c", 0.9))
	Kit.box(r, Vector3(2.0, 0.32, 1.6), Vector3(0, -0.09, 6.2), Kit.mat("9b968c", 0.9))
	# Bina (arka): tek katli, kiremit cati
	var bz := -5.2
	Kit.box(r, Vector3(9.0, 3.0, 4.0), Vector3(0, 1.5, bz), wall)
	Kit.box(r, Vector3(9.1, 0.35, 4.1), Vector3(0, 0.17, bz), Kit.mat("a59d8f", 0.9))
	Kit.prism(r, Vector3(4.8, 1.4, 9.8), Vector3(0, 3.7, bz), Kit.mat("b4532f", 0.8), Vector3(0, PI / 2, 0))
	Kit.box(r, Vector3(9.3, 0.18, 4.4), Vector3(0, 3.0, bz), trim)
	# Kapi ve pencereler (bahceye bakan yuz)
	var fz := bz + 2.02
	Kit.box(r, Vector3(1.3, 2.25, 0.08), Vector3(0, 1.13, fz), trim)
	Kit.box(r, Vector3(1.1, 2.1, 0.06), Vector3(0, 1.1, fz + 0.03), wood)
	Kit.box(r, Vector3(0.7, 0.9, 0.04), Vector3(0, 1.5, fz + 0.07), glass)
	for sx in [-3.0, 3.0]:
		Kit.box(r, Vector3(1.8, 1.25, 0.08), Vector3(sx, 1.65, fz), trim)
		Kit.box(r, Vector3(1.6, 1.08, 0.06), Vector3(sx, 1.65, fz + 0.03), glass)
		Kit.box(r, Vector3(0.06, 1.08, 0.08), Vector3(sx, 1.65, fz + 0.05), trim)
		Kit.box(r, Vector3(1.9, 0.08, 0.25), Vector3(sx, 1.0, fz + 0.1), trim)
	# Tabela
	var sign := Kit.pivot(r, Vector3(0, 2.6, fz + 0.06))
	Kit.box(sign, Vector3(3.6, 0.62, 0.08), Vector3.ZERO, Kit.mat("f6f1e4", 0.6))
	Kit.box(sign, Vector3(3.7, 0.08, 0.1), Vector3(0, 0.33, 0), trim)
	Kit.box(sign, Vector3(3.7, 0.08, 0.1), Vector3(0, -0.33, 0), trim)
	_sign_text(sign, "PATİ YUVASI", Vector3(0, 0.06, 0.05), 74, Color("2f6f4f"))
	_sign_text(sign, "HAYVAN BARINAĞI · SAHİPLENDİRME", Vector3(0, -0.2, 0.05), 26, Color("6b4a2a"))
	# Pati izi amblem
	var pm := Kit.mat("e07b3a", 0.6)
	Kit.cyl(sign, 0.12, 0.12, 0.03, Vector3(-1.55, -0.02, 0.05), pm, 14, Vector3(PI / 2, 0, 0))
	for k in 4:
		Kit.cyl(sign, 0.045, 0.045, 0.03, Vector3(-1.55 + (k - 1.5) * 0.085, 0.13 + (0.03 if k == 1 or k == 2 else 0.0), 0.05), pm, 10, Vector3(PI / 2, 0, 0))
	# Bina carpismasi
	_box_collider(Vector2(0, bz), Vector2(4.5, 2.0))
	# Cit: alcak tahta cit, onde kapi bosluğu
	var x0 := -4.6
	var x1 := 4.6
	var z0 := bz + 2.0
	var z1 := 5.0
	var pickets: Array = []
	var posts: Array = []
	var runs := [[Vector2(x0, z0), Vector2(x0, z1)], [Vector2(x1, z0), Vector2(x1, z1)],
		[Vector2(x0, z1), Vector2(-0.9, z1)], [Vector2(0.9, z1), Vector2(x1, z1)]]
	for run in runs:
		var a: Vector2 = run[0]
		var c: Vector2 = run[1]
		var n := int(a.distance_to(c) / 0.17)
		var along: Vector2 = (c - a).normalized()
		var ry := atan2(along.x, along.y)
		for i in n + 1:
			var q := a.lerp(c, float(i) / n)
			var h := 1.0 + (0.06 if i % 2 == 0 else 0.0)
			pickets.append(Transform3D(Basis(Vector3.UP, ry), Vector3(q.x, h * 0.5, q.y)).scaled_local(Vector3(1, h, 1)))
		var np := int(a.distance_to(c) / 1.8) + 1
		for i in np + 1:
			posts.append(a.lerp(c, float(i) / np))
		for hy in [0.3, 0.75]:
			var mid := (a + c) * 0.5
			Kit.box(r, Vector3(0.05, 0.07, a.distance_to(c)), Vector3(mid.x, hy, mid.y), wood, Vector3(0, ry, 0))
		w._add_segment(_sw(a), _sw(c))
	var pm2 := BoxMesh.new()
	pm2.size = Vector3(0.1, 1.0, 0.025)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pm2
	mm.instance_count = pickets.size()
	for i in pickets.size():
		mm.set_instance_transform(i, pickets[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Kit.mat("f1ead8", 0.8)
	r.add_child(mmi)
	for q in posts:
		Kit.box(r, Vector3(0.14, 1.25, 0.14), Vector3(q.x, 0.62, q.y), Kit.mat("2f6f4f", 0.7))
		Kit.box(r, Vector3(0.18, 0.06, 0.18), Vector3(q.x, 1.27, q.y), Kit.mat("2f6f4f", 0.7))
	# Kapi kemeri
	for sx in [-0.95, 0.95]:
		Kit.box(r, Vector3(0.16, 2.3, 0.16), Vector3(sx, 1.15, z1), trim)
	Kit.box(r, Vector3(2.2, 0.42, 0.1), Vector3(0, 2.4, z1), trim)
	_sign_text(Kit.pivot(r, Vector3(0, 2.4, z1 + 0.06)), "HOŞ GELDİN DOSTUM", Vector3.ZERO, 30, Color("fff4d6"))
	# Acik kapi kanatlari
	for sx in [-1.0, 1.0]:
		var gate := Kit.pivot(r, Vector3(sx * 0.9, 0, z1))
		gate.rotation.y = sx * 1.25
		for i in 5:
			Kit.box(gate, Vector3(0.1, 0.95, 0.025), Vector3(-sx * (0.1 + i * 0.17), 0.5, 0), Kit.mat("f1ead8", 0.8))
		Kit.box(gate, Vector3(0.82, 0.06, 0.04), Vector3(-sx * 0.44, 0.3, 0), wood)
		Kit.box(gate, Vector3(0.82, 0.06, 0.04), Vector3(-sx * 0.44, 0.75, 0), wood)
	# Kulubeler
	var kennels := [[Vector2(-3.5, -1.6), "3f6fa8", 0.0], [Vector2(-3.5, 1.2), "c94f4f", 0.0], [Vector2(3.5, 1.4), "4f8f5a", PI]]
	for i in kennels.size():
		var kp: Vector2 = kennels[i][0]
		_kennel(r, kp, Kit.mat(kennels[i][1], 0.75), kennels[i][2], ADOPTABLES[i][2])
		w._add_circle(Vector3(_sw(kp).x, _sw(kp).y, 0.75))
	# Kedi agaci
	var ct := Vector2(3.4, -1.6)
	var carpet := Kit.mat("d8c7a6", 1.0)
	Kit.cyl(r, 0.09, 0.09, 1.6, Vector3(ct.x, 0.8, ct.y), Kit.mat("c9b48a", 1.0))
	Kit.box(r, Vector3(0.8, 0.06, 0.8), Vector3(ct.x, 0.04, ct.y), carpet)
	Kit.box(r, Vector3(0.6, 0.06, 0.55), Vector3(ct.x - 0.15, 0.8, ct.y), carpet)
	Kit.box(r, Vector3(0.55, 0.06, 0.55), Vector3(ct.x + 0.1, 1.6, ct.y + 0.05), carpet)
	Kit.box(r, Vector3(0.45, 0.4, 0.45), Vector3(ct.x + 0.1, 0.27, ct.y + 0.05), Kit.mat("b8a07a", 1.0))
	Kit.ball(r, 0.06, Vector3(ct.x + 0.33, 0.62, ct.y + 0.2), Kit.mat("d95f76", 0.7))
	w._add_circle(Vector3(_sw(ct).x, _sw(ct).y, 0.5))
	# Su ve mama kaplari
	for q in [Vector2(-2.2, -2.6), Vector2(-1.7, -2.6), Vector2(1.8, 3.6)]:
		Kit.cyl(r, 0.17, 0.13, 0.08, Vector3(q.x, 0.04, q.y), Kit.mat("3f6fa8" if q.x < -2.0 else "e07b3a", 0.4))
		Kit.cyl(r, 0.14, 0.14, 0.01, Vector3(q.x, 0.075, q.y), Kit.mat("6fb1c9", 0.1) if q.x < -2.0 else Kit.mat("8a5a34", 0.9))
	# Bahcede toplar ve bir cicek saksisi
	Kit.ball(r, 0.11, Vector3(0.9, 0.11, 2.2), Kit.mat("c8452f", 0.5))
	Kit.ball(r, 0.08, Vector3(-1.2, 0.08, 0.4), Kit.mat("f2c230", 0.5))
	for sx in [-4.1, 4.1]:
		Kit.cyl(r, 0.28, 0.22, 0.45, Vector3(sx, 0.22, z1 + 0.7), Kit.mat("a8552f", 0.8))
		Kit.ball(r, 0.36, Vector3(sx, 0.62, z1 + 0.7), Kit.mat("4f8f3a", 0.95), Vector3(1, 0.8, 1))
		for k in 6:
			Kit.ball(r, 0.06, Vector3(sx + cos(k) * 0.25, 0.8, z1 + 0.7 + sin(k) * 0.25), Kit.mat(["e84a6f", "f2c230", "ffffff"][k % 3], 0.6))
	# Bilgi panosu: kapinin yaninda
	var board := Kit.pivot(r, Vector3(2.0, 0, z1 + 0.6))
	board.rotation.y = -0.25
	Kit.box(board, Vector3(0.08, 1.5, 0.08), Vector3(-0.5, 0.75, 0), wood)
	Kit.box(board, Vector3(0.08, 1.5, 0.08), Vector3(0.5, 0.75, 0), wood)
	Kit.box(board, Vector3(1.2, 0.8, 0.05), Vector3(0, 1.3, 0), Kit.mat("f6f1e4", 0.7))
	_sign_text(board, "SAHİPLEN,\nSATIN ALMA!", Vector3(0, 1.38, 0.04), 30, Color("c94f4f"))
	_sign_text(board, "Sahiplendirme ücretsiz", Vector3(0, 1.06, 0.04), 16, Color("3a3a3a"))
	w._add_circle(Vector3(_sw(Vector2(2.0, z1 + 0.6)).x, _sw(Vector2(2.0, z1 + 0.6)).y, 0.35))
	# Gorevli: kapida
	var keeper := PersonModel.new()
	keeper.kind = "kadin"
	keeper.tint = Color("4f8f5a")
	keeper.tint2 = Color("4f8f5a")
	keeper.pants = Color("2a3a4a")
	keeper.position = Vector3(-1.5, 0, z1 - 0.7)
	keeper.rotation.y = 0.3
	r.add_child(keeper)
	shelter["keeper"] = keeper
	shelter["gate"] = _sw(Vector2(0, z1 + 1.4))
	shelter["gate_in"] = _sw(Vector2(0, z1 - 0.6))
	shelter["yard"] = Rect2(x0 + 0.5, z0 + 0.6, (x1 - x0) - 1.0, (z1 - z0) - 1.3)
	# Hayvanlar
	var adopted: Array = state.d.get("shelter_adopted", [])
	for i in ADOPTABLES.size():
		var e: Array = ADOPTABLES[i]
		var v := PetModel.new()
		v.kind = e[1]
		v.tint = Color(e[4])
		v.size_mul = e[5]
		var lp := Vector2(_rng.randf_range(-2.4, 2.4), _rng.randf_range(-2.0, 3.4))
		if i < 3:
			lp = (kennels[i][0] as Vector2) + Vector2(0.9 if kennels[i][0].x < 0 else -0.9, 0.0)
		if e[0] == "duman":
			lp = Vector2(3.5, -1.55)
		v.position = Vector3(lp.x, 0.0, lp.y)
		v.rotation.y = _rng.randf() * TAU
		r.add_child(v)
		v.pose = ["sit", "stand", "lie"][i % 3]
		if e[0] == "duman":
			v.position.y = 1.63
			v.pose = "lie"
		var tag := Label3D.new()
		tag.text = e[2]
		tag.font = F_TITLE
		tag.font_size = 44
		tag.pixel_size = 0.0055
		tag.outline_size = 10
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position = Vector3(0, 1.25 if e[1] == "kopek" else 1.35, 0)
		tag.modulate = Color("fff4d6")
		v.add_child(tag)
		tag.visible = false
		v.visible = not adopted.has(e[0])
		shelter["animals"].append({"e": e, "node": v, "pos": lp, "target": lp, "t": _rng.randf_range(1.0, 6.0),
			"tag": tag, "perch": e[0] == "duman"})
	print("BARINAK ", p, " yon=", snappedf(yaw, 0.01))


func _sign_text(parent: Node3D, text: String, pos: Vector3, size: int, c: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = F_TITLE
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	l.double_sided = false
	parent.add_child(l)


func _box_collider(c: Vector2, half: Vector2) -> void:
	var w: Node3D = m.world
	var pts := [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	for i in 4:
		w._add_segment(_sw(c + pts[i]), _sw(c + pts[(i + 1) % 4]))


func _kennel(r: Node3D, p: Vector2, paint: Material, ry: float, pet_name: String) -> void:
	var k := Kit.pivot(r, Vector3(p.x, 0, p.y))
	k.rotation.y = ry + PI / 2.0     # kapisi bahcenin ortasina baksin
	Kit.box(k, Vector3(1.2, 0.9, 1.0), Vector3(0, 0.5, 0), paint)
	Kit.box(k, Vector3(1.3, 0.1, 1.1), Vector3(0, 0.05, 0), Kit.mat("6b4a2a", 0.9))
	Kit.prism(k, Vector3(1.5, 0.55, 1.2), Vector3(0, 1.22, 0), Kit.mat("5a3418", 0.8))
	Kit.box(k, Vector3(0.5, 0.6, 0.04), Vector3(0, 0.42, 0.5), Kit.mat("1a1612", 1.0))
	Kit.cyl(k, 0.25, 0.25, 0.04, Vector3(0, 0.72, 0.5), Kit.mat("1a1612", 1.0), 14, Vector3(PI / 2, 0, 0))
	# Isim levhasi
	var plate := Kit.pivot(k, Vector3(0, 0.88, 0.52))
	Kit.box(plate, Vector3(0.5, 0.14, 0.02), Vector3.ZERO, Kit.mat("f6f1e4", 0.6))
	_sign_text(plate, pet_name, Vector3(0, 0, 0.015), 26, Color("3a2a1a"))


# ---------------------------------------------------------------- guvercinler ve sokak kedisi

func _build_flocks() -> void:
	var spots: Array = []
	for nm in ["cesme", "kafe", "bahce", "piknik", "cardak"]:
		if ParkMap.has_spot(nm):
			spots.append(ParkMap.spot(nm) + Vector2(6.0, 5.0))
	for g in m.world.metro_gates:
		spots.append(g["pos"] - (g["toward"] as Vector2) * 9.0)
	for i in mini(3, m.world.stops.size()):
		spots.append((m.world.stops[i]["pos"] as Vector2) + Vector2(4.0, 3.0))
	for sp in spots:
		if flocks.size() >= 7:
			break
		var c := _free_near(sp, 1.6)
		if c == Vector2.INF:
			continue
		var f := {"pos": c, "birds": [], "mode": "ground", "t": 0.0, "root": Node3D.new()}
		m.world.add_child(f["root"])
		var n := _rng.randi_range(6, 10)
		for i in n:
			var b := _pigeon(f["root"], i)
			var off := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.3, 2.2)
			f["birds"].append({"n": b, "off": off, "goal": off, "phase": _rng.randf() * 10.0, "vel": Vector3.ZERO,
				"peck": 0.0, "wl": b.get_node("WL"), "wr": b.get_node("WR"), "head": b.get_node("Head")})
		_reset_flock(f)
		flocks.append(f)


func _free_near(p: Vector2, r: float) -> Vector2:
	var w: Node3D = m.world
	for rad in range(0, 20, 2):
		for k in (1 if rad == 0 else 10):
			var q := p + Vector2.from_angle(k * TAU / 10.0) * float(rad)
			if ParkMap.inside_bounds(q, 10.0) and w.is_free(q, r) and not w._inside_building(q) and ParkMap.water_sd(q) > 3.0:
				return q
	return Vector2.INF


func _pigeon(parent: Node3D, i: int) -> Node3D:
	var b := Node3D.new()
	parent.add_child(b)
	var body: Material = _bird_mats[0] if i % 4 != 3 else _bird_mats[4]
	var s := _rng.randf_range(0.9, 1.1)
	b.scale = Vector3.ONE * s
	Kit.ball(b, 0.075, Vector3(0, 0.12, 0.01), body, Vector3(0.85, 0.8, 1.35), 10)
	Kit.ball(b, 0.05, Vector3(0, 0.17, -0.07), _bird_mats[2], Vector3(1, 1.1, 1), 8)
	var head := Kit.pivot(b, Vector3(0, 0.2, -0.09))
	head.name = "Head"
	Kit.ball(head, 0.038, Vector3(0, 0.02, -0.02), _bird_mats[1], Vector3.ONE, 8)
	Kit.cyl(head, 0.004, 0.01, 0.03, Vector3(0, 0.015, -0.065), _bird_mats[3], 6, Vector3(-PI / 2, 0, 0))
	for sx in [-1.0, 1.0]:
		Kit.ball(head, 0.008, Vector3(sx * 0.028, 0.03, -0.04), _bird_mats[5], Vector3.ONE, 6)
	Kit.box(b, Vector3(0.07, 0.015, 0.1), Vector3(0, 0.12, 0.13), _bird_mats[1], Vector3(-0.3, 0, 0))
	for sx in [-1.0, 1.0]:
		var wing := Kit.pivot(b, Vector3(sx * 0.05, 0.15, 0.01))
		wing.name = "WL" if sx < 0 else "WR"
		Kit.box(wing, Vector3(0.16, 0.012, 0.11), Vector3(sx * 0.07, 0, 0.02), _bird_mats[1])
		wing.rotation.z = sx * -1.2
		Kit.cyl(b, 0.005, 0.005, 0.08, Vector3(sx * 0.025, 0.04, 0.02), _bird_mats[5], 4)
	return b


func _reset_flock(f: Dictionary) -> void:
	f["mode"] = "ground"
	f["t"] = 0.0
	(f["root"] as Node3D).visible = true
	var c: Vector2 = f["pos"]
	for bd in f["birds"]:
		var off: Vector2 = bd["off"]
		var q := c + off
		var n: Node3D = bd["n"]
		n.position = Vector3(q.x, ParkMap.walk_height(q), q.y)
		n.rotation = Vector3(0, _rng.randf() * TAU, 0)
		bd["goal"] = off
		(bd["wl"] as Node3D).rotation.z = 1.2
		(bd["wr"] as Node3D).rotation.z = -1.2


func _scare(f: Dictionary) -> void:
	if f["mode"] != "ground":
		return
	f["mode"] = "fly"
	f["t"] = 0.0
	var c: Vector2 = f["pos"]
	var away := Vector2.from_angle(_rng.randf() * TAU)
	for bd in f["birds"]:
		var out: Vector2 = ((bd["off"] as Vector2).normalized() * 0.6 + away).normalized()
		bd["vel"] = Vector3(out.x * _rng.randf_range(3.0, 5.0), _rng.randf_range(3.2, 5.0), out.y * _rng.randf_range(3.0, 5.0))
		bd["phase"] = _rng.randf() * 3.0


func _update_flocks(dt: float, o: Vector2) -> void:
	var pet_ps: Array = []
	for k in m.agents:
		var a: Node3D = m.agents[k]
		if a.visible:
			pet_ps.append([a.pos2(), a.model.speed])
	var owner_fast: bool = m.owner_model.speed > 3.0
	for f in flocks:
		var c: Vector2 = f["pos"]
		var dist := c.distance_to(o)
		if dist > 90.0 and f["mode"] == "ground":
			(f["root"] as Node3D).visible = false
			continue
		(f["root"] as Node3D).visible = f["mode"] != "gone"
		f["t"] += dt
		match f["mode"]:
			"ground":
				var scared := dist < (3.4 if owner_fast else 1.8)
				for pp in pet_ps:
					if (pp[0] as Vector2).distance_to(c) < 3.6 and float(pp[1]) > 0.6:
						scared = true
				if ParkMap.home != null:
					scared = false
				if scared:
					_scare(f)
					continue
				for bd in f["birds"]:
					var n: Node3D = bd["n"]
					bd["phase"] += dt
					var cur := Vector2(n.position.x, n.position.z) - c
					var goal: Vector2 = bd["goal"]
					var to := goal - cur
					if to.length() < 0.05:
						bd["peck"] = maxf(float(bd["peck"]) - dt, 0.0)
						if _rng.randf() < dt * 0.5:
							bd["goal"] = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.3, 2.3)
						elif _rng.randf() < dt * 1.2:
							bd["peck"] = 0.5
					else:
						var stepv := to.normalized() * minf(0.45 * dt, to.length())
						cur += stepv
						n.rotation.y = lerp_angle(n.rotation.y, atan2(-to.x, -to.y), minf(1.0, dt * 8.0))
					var q := c + cur
					n.position = Vector3(q.x, ParkMap.walk_height(q), q.y)
					var hd: Node3D = bd["head"]
					var walk_bob := sin(float(bd["phase"]) * 14.0) * 0.012 if to.length() > 0.05 else 0.0
					var pk := sin(float(bd["peck"]) * TAU * 2.0) * 0.6 if float(bd["peck"]) > 0.0 else 0.0
					hd.position.z = -0.09 + walk_bob
					hd.rotation.x = -absf(pk)
			"fly":
				for bd in f["birds"]:
					var n: Node3D = bd["n"]
					var v: Vector3 = bd["vel"]
					v.y = minf(v.y + dt * 0.8, 6.0)
					bd["vel"] = v
					n.position += v * dt
					n.rotation.y = lerp_angle(n.rotation.y, atan2(-v.x, -v.z), minf(1.0, dt * 6.0))
					n.rotation.x = 0.35
					bd["phase"] += dt
					var flap := sin(float(bd["phase"]) * 26.0) * 0.9
					(bd["wl"] as Node3D).rotation.z = flap
					(bd["wr"] as Node3D).rotation.z = -flap
				if f["t"] > 6.0:
					f["mode"] = "gone"
					f["t"] = 0.0
					(f["root"] as Node3D).visible = false
			"gone":
				var near_pet := false
				for pp in pet_ps:
					if (pp[0] as Vector2).distance_to(c) < 14.0:
						near_pet = true
				if f["t"] > 30.0 and dist > 16.0 and not near_pet:
					_reset_flock(f)


func _build_stray() -> void:
	var base := Vector2.INF
	if ParkMap.has_spot("kafe"):
		base = ParkMap.spot("kafe") + Vector2(-8.0, 8.0)
	elif not flocks.is_empty():
		base = (flocks[0]["pos"] as Vector2) + Vector2(7.0, -5.0)
	if base == Vector2.INF:
		return
	var p := _free_near(base, 0.6)
	if p == Vector2.INF:
		return
	var v := PetModel.new()
	v.kind = "kedi"
	v.tint = Color("e8a060")
	v.size_mul = 0.85
	m.world.add_child(v)
	v.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
	v.pose = "sit"
	stray = {"node": v, "home": p, "pos": p, "mode": "idle", "t": 0.0, "goal": p}


func _update_stray(dt: float, o: Vector2) -> void:
	if stray.is_empty():
		return
	var v: Node3D = stray["node"]
	var p: Vector2 = stray["pos"]
	if p.distance_to(o) > 90.0 and stray["mode"] != "flee":
		v.visible = false
		return
	stray["t"] += dt
	match stray["mode"]:
		"idle":
			v.visible = true
			v.speed = 0.0
			if stray["t"] > 6.0:
				stray["t"] = 0.0
				stray["goal"] = (stray["home"] as Vector2) + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.5, 3.0)
				stray["mode"] = "walk"
				v.pose = "stand"
		"walk":
			var goal: Vector2 = stray["goal"]
			if _step_node(v, goal, 0.9, dt) < 0.15 or stray["t"] > 8.0:
				stray["mode"] = "idle"
				stray["t"] = 0.0
				v.pose = ["sit", "lie", "stand"][_rng.randi() % 3]
		"flee":
			var a: Node3D = m.agents.get(chase.get("kind", ""), null)
			var away := Vector2.from_angle(v.rotation.y + PI / 2.0)
			if a:
				away = (p - a.pos2()).normalized()
			_step_node(v, p + away * 3.0, 5.0, dt)
			if stray["t"] > 6.5:
				stray["mode"] = "gone"
				stray["t"] = 0.0
				v.hop(0.9, 0.5)
		"gone":
			if stray["t"] > 0.4:
				v.visible = false
			if stray["t"] > 45.0 and (stray["home"] as Vector2).distance_to(o) > 18.0:
				stray["pos"] = stray["home"]
				var h: Vector2 = stray["home"]
				v.position = Vector3(h.x, ParkMap.walk_height(h), h.y)
				stray["mode"] = "idle"
				stray["t"] = 0.0
				v.visible = true


func _step_node(v: Node3D, goal: Vector2, sp: float, dt: float) -> float:
	var p := Vector2(v.position.x, v.position.z)
	var to := goal - p
	var d := to.length()
	if d < 0.05:
		v.speed = 0.0
		return d
	var np: Vector2 = m.world.resolve(p + to / d * minf(sp * dt, d), 0.25, p)
	v.speed = np.distance_to(p) / maxf(dt, 0.0001)
	v.position = Vector3(np.x, ParkMap.walk_height(np), np.y)
	v.rotation.y = lerp_angle(v.rotation.y, atan2(-to.x, -to.y), minf(1.0, dt * 10.0))
	if v == stray.get("node"):
		stray["pos"] = np
	return np.distance_to(goal)


# ---------------------------------------------------------------- kovalamaca

func _try_chase() -> void:
	if leashed() or not chase.is_empty() or ParkMap.home != null:
		return
	if m._ride != null or m._taxi != null or m._bus_ride != null:
		return
	var a: Node3D = m._active()
	if a == null or a.mode != PetAgent.Mode.FOLLOW or not a.visible:
		return
	var ap: Vector2 = a.pos2()
	var best := -1
	var bd := 26.0
	for i in flocks.size():
		var f: Dictionary = flocks[i]
		if f["mode"] == "ground":
			var d := ap.distance_to(f["pos"])
			if d < bd and d > 4.0:
				bd = d
				best = i
	if not stray.is_empty() and stray["mode"] in ["idle", "walk"]:
		var d2 := ap.distance_to(stray["pos"])
		if d2 < bd and d2 > 3.0:
			best = -2
	if best == -1:
		return
	start_chase(a, "cat" if best == -2 else "flock", best)


func start_chase(a: Node3D, what: String, i: int) -> void:
	a.command("come")
	a.external = true
	a.model.pose = "stand"
	chase = {"kind": a.kind, "what": what, "i": i, "t": 0.0, "phase": "run"}
	var nm: String = state.pet(a.kind)["name"]
	if what == "cat":
		stray["mode"] = "flee"
		stray["t"] = 0.0
		(stray["node"] as Node3D).pose = "stand"
		m.ui.toast("%s bir sokak kedisi gördü ve peşinden fırladı! Geri çağır: R" % nm)
	else:
		m.ui.toast("%s güvercinleri gördü ve peşlerinden koşuyor! Geri çağır: R" % nm)
	m._pet_voice(a.kind)


func _update_chase(dt: float) -> void:
	var a: Node3D = m.agents.get(chase["kind"], null)
	if a == null or not is_instance_valid(a):
		chase.clear()
		return
	if not a.external:
		# Geri cagrildi (R) ya da baska bir komut verildi
		var nm: String = state.pet(a.kind)["name"]
		m.ui.toast("Aferin %s! Çağırınca geldi." % nm)
		state.add_xp(a.kind, 1.0)
		a.model.happy_time = 1.5
		chase.clear()
		if not stray.is_empty() and stray["mode"] == "flee":
			stray["mode"] = "gone"
			stray["t"] = 0.0
		return
	chase["t"] += dt
	var ap: Vector2 = a.pos2()
	var o: Vector2 = m._owner_pos()
	match chase["phase"]:
		"run":
			var goal := ap
			if chase["what"] == "cat":
				goal = stray["pos"]
				if stray["mode"] == "gone":
					chase["phase"] = "lost"
					chase["t"] = 0.0
			else:
				var f: Dictionary = flocks[chase["i"]]
				goal = f["pos"]
				if f["mode"] != "ground":
					# Kuslar kalkti: havaya bakarak biraz daha kos, havla
					chase["phase"] = "bark"
					chase["t"] = 0.0
					chase["dir"] = (goal - ap).normalized() if goal.distance_to(ap) > 0.3 else Vector2.from_angle(a.rotation.y)
					m._pet_voice(a.kind)
			a._move(goal, 6.3, dt)
			if chase["t"] > 14.0:
				chase["phase"] = "lost"
				chase["t"] = 0.0
		"bark":
			var dir: Vector2 = chase["dir"]
			if chase["t"] < 1.6:
				a._move(ap + dir * 2.0, 4.5, dt)
			else:
				a.model.speed = 0.0
				a.model.look_at_point = a.position + Vector3(dir.x * 3.0, 5.0, dir.y * 3.0)
				if chase["t"] > 2.0 and int(chase["t"] * 2.0) % 3 == 0 and not a.model.is_hopping():
					a.model.hop(0.3, 0.4)
			if chase["t"] > 4.0:
				chase["phase"] = "lost"
				chase["t"] = 0.0
				m._pet_voice(a.kind)
		"lost":
			# Gezinip sahibini bekler: ya R ile cagrilir ya da sahibi yanina gelir
			a.model.speed = 0.0
			a.model.pose = "sit"
			a.model.look_at_point = Vector3(sin(chase["t"] * 0.7) * 5.0, 0.5, cos(chase["t"] * 0.7) * 5.0) + a.position
			if ap.distance_to(o) < 2.2:
				a.command("come")
			elif chase["t"] > 75.0:
				a.command("come")
			elif int(chase["t"]) % 9 == 0 and chase["t"] - floorf(chase["t"]) < dt:
				m._pet_voice(a.kind, true)


func recall() -> void:
	# main "come" komutu zaten a.command("come") ile external'i kapatir; burada sadece temizlik.
	pass


# ---------------------------------------------------------------- tasma

func toggle_leash() -> void:
	if m._ride != null or m._taxi != null:
		m.ui.toast("Araçtayken tasma takamazsın.")
		return
	var on := not leashed()
	state.d["leash"] = on
	var a: Node3D = m._active()
	var nm: String = state.pet(a.kind)["name"]
	if on:
		if not chase.is_empty():
			m.ui.toast("Önce %s'i geri çağır (R)." % nm)
			state.d["leash"] = false
			return
		for k in m.agents:
			var ag: Node3D = m.agents[k]
			if ag.pos2().distance_to(m._owner_pos()) > 4.0 and ag.mode == PetAgent.Mode.FOLLOW:
				ag.place(m._owner_pos() + ag.slot.rotated(-m.owner_node.rotation.y))
		m.ui.toast("Tasma takıldı · %s artık yanından ayrılmaz" % nm)
		m.owner_model.act("pet", 0.8)
	else:
		m.ui.toast("Tasma çıkarıldı · dikkat, güvercin görünce kaçabilir!")
	m._sfx("tik", -4.0, 0.8)
	state.save_game()


func _update_leash(dt: float) -> void:
	var on := leashed()
	var o: Vector2 = m._owner_pos()
	var show_any: bool = on and m._ride == null and m._taxi == null and m._bus_ride == null and m._mode in ["play", "debug"] \
			and m.owner_node.visible and m._play_ride.is_empty()
	for k in m.agents:
		var a: Node3D = m.agents[k]
		var rope: MeshInstance3D = _rope(k)
		var show: bool = show_any and a.visible and is_instance_valid(a.model.neck_socket)
		if show and on and (a.mode == PetAgent.Mode.FOLLOW or a.mode == PetAgent.Mode.STAY) and not a.external:
			var d: float = a.pos2().distance_to(o)
			if d > LEASH_LEN:
				if a.mode == PetAgent.Mode.STAY:
					a.command("come")
				var np: Vector2 = m.world.resolve(o + (a.pos2() - o).normalized() * LEASH_LEN, 0.3, a.pos2())
				a.place(np)
		if show and a.pos2().distance_to(o) > 7.0:
			show = false
		rope.visible = show
		(_clips[k] as Node3D).visible = show
		if show:
			_draw_rope(rope, m.owner_model.hand.global_position, a.model.neck_socket.global_position, k)


func _rope(kind: String) -> MeshInstance3D:
	if _ropes.has(kind) and is_instance_valid(_ropes[kind]):
		return _ropes[kind]
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _rope_mat
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.extra_cull_margin = 4.0
	m.add_child(mi)
	_ropes[kind] = mi
	var clip := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.018
	tm.outer_radius = 0.03
	tm.rings = 10
	tm.ring_segments = 6
	clip.mesh = tm
	clip.material_override = Kit.mat("c9ccd2", 0.25)
	clip.top_level = true
	m.add_child(clip)
	_clips[kind] = clip
	return mi


func _draw_rope(mi: MeshInstance3D, a: Vector3, b: Vector3, kind: String) -> void:
	var im: ImmediateMesh = mi.mesh
	im.clear_surfaces()
	const N := 16
	const SIDES := 5
	var rad := 0.012
	var d := a.distance_to(b)
	var length := maxf(LEASH_LEN + 0.35, d * 1.02)
	var sag := sqrt(maxf(length * length - d * d, 0.0)) * 0.5
	var low := minf(a.y, b.y)
	var ground := ParkMap.walk_height(Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)) + 0.03
	sag = minf(sag, maxf(low - ground, 0.0) + (absf(a.y - b.y) * 0.25))
	var pts: Array[Vector3] = []
	var sway := sin(Time.get_ticks_msec() * 0.003) * 0.02 * sag
	for i in N + 1:
		var t := float(i) / N
		var q := a.lerp(b, t)
		q.y -= sag * 4.0 * t * (1.0 - t)
		q.x += sway * 4.0 * t * (1.0 - t)
		pts.append(q)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in pts.size():
		var tan: Vector3 = (pts[mini(i + 1, N)] - pts[maxi(i - 1, 0)]).normalized()
		var side := tan.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(tan).normalized()
		var ring: Array[Vector3] = []
		for s in SIDES:
			var ang := s * TAU / SIDES
			ring.append(pts[i] + (side * cos(ang) + up * sin(ang)) * rad)
		rings.append(ring)
	for i in N:
		var r0: Array[Vector3] = rings[i]
		var r1: Array[Vector3] = rings[i + 1]
		for s in SIDES:
			var s2 := (s + 1) % SIDES
			var n0 := (r0[s] - pts[i]).normalized()
			var n1 := (r0[s2] - pts[i]).normalized()
			im.surface_set_normal(n0)
			im.surface_add_vertex(r0[s])
			im.surface_set_normal(n0)
			im.surface_add_vertex(r1[s])
			im.surface_set_normal(n1)
			im.surface_add_vertex(r1[s2])
			im.surface_set_normal(n0)
			im.surface_add_vertex(r0[s])
			im.surface_set_normal(n1)
			im.surface_add_vertex(r1[s2])
			im.surface_set_normal(n1)
			im.surface_add_vertex(r0[s2])
	im.surface_end()
	var clip: Node3D = _clips[kind]
	clip.global_position = b
	clip.look_at(b + (pts[N - 1] - b).normalized() + Vector3(0.001, 0, 0), Vector3.UP)


# ---------------------------------------------------------------- egitim

func tricks_of(kind: String) -> Dictionary:
	var p: Dictionary = state.pet(kind)
	if not p.has("tricks") or typeof(p["tricks"]) != TYPE_DICTIONARY:
		p["tricks"] = {}
	return p["tricks"]


func learned(kind: String, id: String) -> bool:
	for t in TRICKS:
		if t[0] == id:
			return int(tricks_of(kind).get(id, 0)) >= int(t[2])
	return false


func open_training() -> void:
	var a: Node3D = m._active()
	var kind: String = a.kind
	var nm: String = state.pet(kind)["name"]
	var treats := int(state.d["foods"].get("odul", 0))
	var body: VBoxContainer = m.ui._open_panel("EĞİTİM", "%s · Ödül Bisküvisi: %d" % [nm, treats])
	var tr := tricks_of(kind)
	var unlocked := true
	for t in TRICKS:
		var id: String = t[0]
		var need: int = t[2]
		var have := int(tr.get(id, 0))
		if have >= need:
			m.ui._panel_item(body, "%s  ·  Öğrendi — Yaptır" % t[1], func(): command("trick:" + id))
		elif unlocked:
			unlocked = false
			m.ui._panel_item(body, "Öğret: %s  ·  %d/%d  ·  1 ödül" % [t[1], have, need], func(): command("train:" + id))
		else:
			var b: Button = m.ui._panel_item(body, "%s  ·  Kilitli" % t[1], func(): m.ui.toast("Önce bir önceki numarayı öğret."))
			b.modulate = Color(1, 1, 1, 0.45)
	m.ui._panel_item(body, "Tasmayı " + ("Çıkar" if leashed() else "Tak") + "  (L)", func():
		toggle_leash()
		open_training())
	m.ui._focus_first(body)


func _near_pet(a: Node3D) -> bool:
	if a.pos2().distance_to(m._owner_pos()) > 6.0 or not a.visible:
		m.ui.toast("%s yanında değil. Önce çağır (R)." % state.pet(a.kind)["name"])
		return false
	if not chase.is_empty():
		m.ui.toast("%s şu an kuş kovalıyor! Önce geri çağır (R)." % state.pet(a.kind)["name"])
		return false
	return true


func train(id: String) -> void:
	var a: Node3D = m._active()
	if not _near_pet(a):
		return
	var treats := int(state.d["foods"].get("odul", 0))
	if treats <= 0:
		m.ui.toast("Ödül bisküvin kalmadı. Pet Shop'tan ya da marketten alabilirsin.")
		return
	var t: Array = []
	for x in TRICKS:
		if x[0] == id:
			t = x
	if t.is_empty():
		return
	state.d["foods"]["odul"] = treats - 1
	var tr := tricks_of(a.kind)
	tr[id] = int(tr.get(id, 0)) + 1
	state.add_need(a.kind, "hunger", 2.0)
	state.add_need(a.kind, "fun", 4.0)
	state.add_xp(a.kind, 1.0)
	state.count("train", 1)
	m._say(m.owner_node, t[1] + "!")
	m.owner_model.act("feed", 0.9)
	perform(a, id, int(tr[id]) < int(t[2]))
	var nm: String = state.pet(a.kind)["name"]
	if int(tr[id]) >= int(t[2]):
		m.ui.toast("Harika! %s artık \"%s\" komutunu biliyor!" % [nm, t[1]])
		m._sfx("mutlu", -4.0)
		state.add_xp(a.kind, 5.0)
		m._hearts(a.position)
	else:
		m.ui.toast("Ödülü kaptı! %s · %s %d/%d" % [nm, t[1], tr[id], t[2]])
	state.save_game()
	open_training()


## Numarayi yaptirir. clumsy: henuz ogrenmedi, biraz sasirir.
func perform(a: Node3D, id: String, clumsy := false) -> void:
	var o: Vector2 = m._owner_pos()
	var dir: Vector2 = o - a.pos2()
	if dir.length() > 0.1:
		a.rotation.y = atan2(-dir.x, -dir.y)
	_trick.clear()
	match id:
		"otur":
			a.command("sit")
		"yat":
			a.command("lie")
		"pati":
			a.command("sit")
			a.model.give_paw(1.0 if clumsy else 2.2)
		"don":
			a.command("come")
			a.external = true
			a.model.hop(0.15, 0.3)
			_trick = {"agent": a, "id": id, "t": 0.0, "dur": 1.6 if clumsy else 1.1, "turns": 0.6 if clumsy else 1.0, "y0": a.rotation.y}
		"bekle":
			a.command("sit")
			a.stay_far = 140.0
			if not clumsy:
				m.ui.toast("%s sen çağırana kadar bekleyecek (R)." % state.pet(a.kind)["name"])
	a.model.happy_time = 1.0
	m._pet_voice(a.kind, true)


func do_trick(id: String) -> void:
	var a: Node3D = m._active()
	if not _near_pet(a):
		return
	if not learned(a.kind, id):
		m.ui.toast("Bu numarayı henüz öğrenmedi.")
		return
	for t in TRICKS:
		if t[0] == id:
			m._say(m.owner_node, t[1] + "!")
	m.owner_model.act("wave", 0.7)
	perform(a, id, false)
	state.add_xp(a.kind, 0.5)
	m.ui.close_modal()


func _update_trick(dt: float) -> void:
	if _trick.is_empty():
		return
	var a: Node3D = _trick["agent"]
	if not is_instance_valid(a) or not a.external:
		_trick.clear()
		return
	_trick["t"] += dt
	var k := clampf(_trick["t"] / _trick["dur"], 0.0, 1.0)
	a.rotation.y = float(_trick["y0"]) + TAU * float(_trick["turns"]) * smoothstep(0.0, 1.0, k)
	a.model.speed = 1.4 * sin(k * PI)
	if k >= 1.0:
		a.external = false
		a.model.speed = 0.0
		a.model.happy_time = 1.5
		_trick.clear()


# ---------------------------------------------------------------- barinak paneli

func open_shelter() -> void:
	var adopted: Array = state.d.get("shelter_adopted", [])
	var body: VBoxContainer = m.ui._open_panel("PATİ YUVASI", "Hayvan Barınağı · Sahiplendirme ücretsiz")
	var any := false
	for e in ADOPTABLES:
		if adopted.has(e[0]):
			continue
		any = true
		var kind_name: String = "Köpek" if e[1] == "kopek" else "Kedi"
		var id: String = e[0]
		m.ui._panel_item(body, "%s · %s · %s · %s" % [e[2], kind_name, e[3], e[6]], func(): adopt(id))
	if not any:
		m.ui._panel_item(body, "Bütün dostlar yuvasını buldu!", func(): m.ui.close_modal())
	m.ui._panel_item(body, "Mama Bağışla (1 Kuru Mama)", func(): donate())
	m.ui._focus_first(body)


func adopt(id: String) -> void:
	var e: Array = []
	for x in ADOPTABLES:
		if x[0] == id:
			e = x
	if e.is_empty():
		return
	var kind: String = e[1]
	var p: Dictionary = state.pet(kind)
	if p["owned"]:
		m.ui.close_modal()
		var mine: String = p["name"]
		m.ui.toast("Zaten bir %s var: %s. %s seni kıskanabilir; ama %s'yi istediğin zaman ziyaret edebilirsin!" % [
			"köpeğin" if kind == "kopek" else "kedin", mine, mine, e[2]])
		if shelter.has("keeper"):
			m._say(shelter["keeper"], "%s seni çok sevdi!" % e[2])
		return
	p["owned"] = true
	p["name"] = e[2]
	p["tint"] = e[4]
	p["size"] = e[5]
	p["hunger"] = 70.0
	p["fun"] = 80.0
	var adopted: Array = state.d.get("shelter_adopted", [])
	adopted.append(id)
	state.d["shelter_adopted"] = adopted
	for an in shelter.get("animals", []):
		if an["e"][0] == id:
			(an["node"] as Node3D).visible = false
	m._on_adopted(kind)
	if m.agents.has(kind):
		m.agents[kind].place(shelter.get("gate", m._owner_pos() + Vector2(1, 1)))
	m.ui.close_modal()
	m.ui.toast("%s artık ailenin bir üyesi! Ona iyi bak." % e[2])
	if shelter.has("keeper"):
		m._say(shelter["keeper"], "Güle güle %s!" % e[2])
	m._sfx("mutlu", -3.0)
	state.save_game()
	m.ui.refresh()


func donate() -> void:
	var n := int(state.d["foods"].get("mama", 0))
	if n <= 0:
		m.ui.toast("Kuru maman yok. Pet Shop'tan alabilirsin.")
		return
	state.d["foods"]["mama"] = n - 1
	m.ui.close_modal()
	m.ui.toast("Teşekkürler! Barınaktaki dostlar bu akşam karnını doyuracak.")
	if shelter.has("keeper"):
		m._say(shelter["keeper"], "Çok teşekkürler!")
	state.add_xp(m._active().kind, 2.0)
	state.save_game()


func _update_shelter(dt: float, o: Vector2) -> void:
	if shelter.is_empty():
		return
	var r: Node3D = shelter["root"]
	var near: bool = o.distance_to(shelter["pos"]) < 70.0
	r.visible = o.distance_to(shelter["pos"]) < 400.0
	if not near:
		for an in shelter["animals"]:
			var pv: Node3D = an["node"]
			pv.speed = 0.0
		return
	var yard: Rect2 = shelter["yard"]
	var ol: Vector2 = (o - shelter["pos"]).rotated(shelter["yaw"])
	for an in shelter["animals"]:
		var v: Node3D = an["node"]
		if not v.visible:
			continue
		var tag: Label3D = an["tag"]
		tag.visible = ol.distance_to(an["pos"]) < 7.0
		if an["perch"]:
			v.look_at_point = m.owner_node.position + Vector3(0, 1.2, 0) if ol.distance_to(an["pos"]) < 6.0 else null
			continue
		an["t"] -= dt
		var cur: Vector2 = an["pos"]
		var goal: Vector2 = an["target"]
		var to := goal - cur
		if to.length() > 0.08:
			var sp := 1.0
			var st := to.normalized() * minf(sp * dt, to.length())
			cur += st
			an["pos"] = cur
			v.position = Vector3(cur.x, 0.0, cur.y)
			v.rotation.y = lerp_angle(v.rotation.y, atan2(-to.x, -to.y), minf(1.0, dt * 8.0))
			v.speed = sp
			v.look_at_point = null
		else:
			v.speed = 0.0
			# Ziyaretci yakinsa ona bakar, kuyruk sallar
			if ol.distance_to(cur) < 6.0:
				v.look_at_point = m.owner_node.position + Vector3(0, 1.2, 0)
				v.excited = true
			else:
				v.look_at_point = null
				v.excited = false
			if an["t"] <= 0.0:
				an["t"] = _rng.randf_range(3.0, 8.0)
				if _rng.randf() < 0.55:
					if ol.distance_to(cur) < 9.0 and _rng.randf() < 0.6:
						# Ziyaretciye dogru citin yanina gel
						var tgt := Vector2(clampf(ol.x, yard.position.x, yard.end.x), yard.end.y - _rng.randf_range(0.0, 0.8))
						an["target"] = tgt
					else:
						an["target"] = Vector2(_rng.randf_range(yard.position.x, yard.end.x), _rng.randf_range(yard.position.y, yard.end.y))
					v.pose = "stand"
				else:
					v.pose = ["sit", "lie", "stand"][_rng.randi() % 3]
					if _rng.randf() < 0.3:
						v.hop(0.2, 0.35)


# ---------------------------------------------------------------- dongu, baglam, komutlar

func update(dt: float) -> void:
	if m.owner_node == null or not is_instance_valid(m.owner_node):
		return
	var o: Vector2 = m._owner_pos()
	_update_shelter(dt, o)
	_update_flocks(dt, o)
	_update_stray(dt, o)
	_update_trick(dt)
	if not chase.is_empty():
		_update_chase(dt)
	elif m._mode == "play":
		_chase_cd -= dt
		if _chase_cd <= 0.0:
			_chase_cd = _rng.randf_range(25.0, 55.0)
			_try_chase()
	_update_leash(dt)


func context() -> Array:
	if not chase.is_empty():
		return ["Geri Çağır: %s" % state.pet(chase["kind"])["name"], "come", "come"]
	if shelter.is_empty() or m._ride != null or m._taxi != null or ParkMap.home != null:
		return []
	var o: Vector2 = m._owner_pos()
	if o.distance_to(shelter["gate"]) < 2.6 or o.distance_to(shelter["gate_in"]) < 2.0:
		return ["Pati Yuvası · Sahiplen", "shelter", "paw"]
	return []


func command(cmd: String) -> void:
	if cmd == "leash":
		toggle_leash()
	elif cmd == "train":
		open_training()
	elif cmd == "shelter":
		open_shelter()
	elif cmd.begins_with("train:"):
		train(cmd.substr(6))
	elif cmd.begins_with("trick:"):
		do_trick(cmd.substr(6))
	elif cmd == "shelter_nav":
		if shelter.is_empty():
			m.ui.toast("Bu bölgede barınak yok.")
		else:
			m.ui.close_modal()
			m._set_nav(shelter["gate"], "Pati Yuvası")


# ---------------------------------------------------------------- test

func debug_leash() -> void:
	state.d["leash"] = true
	var a: Node3D = m._active()
	var o: Vector2 = m._owner_pos()
	a.place(o + Vector2(1.6, 1.0).rotated(-m.owner_node.rotation.y))
	print("TASMA ", leashed(), " mesafe=", snappedf(a.pos2().distance_to(o), 0.01))


func debug_shelter() -> void:
	if shelter.is_empty():
		print("BARINAK YOK")
		return
	var g: Vector2 = shelter["gate"]
	m._place_owner(g + (g - shelter["pos"]).normalized() * 1.2)
	var d: Vector2 = shelter["pos"] - m._owner_pos()
	m.owner_node.rotation.y = atan2(-d.x, -d.y)
	m._cam_yaw = m.owner_node.rotation.y + 0.35
	for k in m.agents:
		m.agents[k].place(m._owner_pos() + Vector2(1.0, 0.8).rotated(-m.owner_node.rotation.y))
	print("BARINAK gate=", g)


func debug_chase() -> void:
	var a: Node3D = m._active()
	state.d["leash"] = false
	var best := -1
	var bd := 1e9
	for i in flocks.size():
		var d: float = (flocks[i]["pos"] as Vector2).distance_to(m._owner_pos())
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return
	var fp: Vector2 = flocks[best]["pos"]
	m._place_owner(fp + Vector2(9.0, 4.0))
	a.place(m._owner_pos() + Vector2(1.0, 0.5))
	start_chase(a, "flock", best)
	print("KOVALA suru=", fp)
