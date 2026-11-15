extends Node3D
## EvBul ilanlarinin ic mekani. Dort parametrik sablon (1+1, 2+1, 3+1, mustakil) tek bir plandan uretilir:
## solda salon, sagda ortadan gecen koridor; koridorun arkasinda (pencereli) odalar, onunde mutfak / banyo.
## Duvar rengi, zemin, mobilya takimi, perde, manzara ve balkon ilan tohumuna (seed_i) gore degisir; ayni ilan
## her zaman ayni gorunur. Arayuz ev.gd / shop_interior.gd ile ayni: w2, local2, has_point, resolve, is_free,
## update_view. Ev hayati (home_life.gd) icin: furn_slots, furn_rot, mess_spots, stove_stand, stove_pos, stove_yaw.

const Kit = preload("res://scripts/kit.gd")
const H := 2.7            # dis duvar / tavan yuksekligi
const PH := 2.45          # ara duvar yuksekligi (kamera ustten bakar)

var type := "1+1"
var seed_i := 1
var hour := 12.0
var lid := ""
var lived := false        # kiralanmis / satin alinmis: mobilya, yemek ve daginiklik calisir
var W := 9.6
var D := 7.0
var X0 := 0.0             # sol sinir: balkon (-1.5) ya da bahce (-6.5) varsa negatif
var SW := 5.4             # salon genisligi
var CZ0 := 3.7            # koridorun arka kenari
var CZ1 := 5.0            # koridorun on kenari
var pal := {}
var entrance_local := Vector2.ZERO
var bed_c := Vector2.ZERO
var bed_half := Vector2(0.8, 1.05)
var petbed_local := Vector2(1.7, 0.7)
var stove_stand := Vector2.ZERO
var stove_pos := Vector3.ZERO
var stove_yaw := 0.0
var furn_slots := {}
var furn_rot := {}
var mess_spots: Array = []
var colliders: Array = []        # [Vector2 a, Vector2 b] yerel
var lights: Array = []
var ceiling: Node3D
var _back: Node3D
var _front: Node3D
var _left: Node3D
var _right: Node3D
var _rng := RandomNumberGenerator.new()
var _wall_m: Material
var _wood: Material
var _white: Material


## Ilanin gorunumu (ic mekan ve telefon kucuk resmi ayni paleti kullanir).
static func palette(s: int, t: String) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = s * 7919 + 13
	var walls := ["efe6d6", "dfe8e2", "e8dccf", "e3e1ee", "f1e3d3", "d9e4ec", "ece4c9", "ead9d6"]
	var sofas := ["3f5f7a", "7a4a3a", "5c6b4a", "85858c", "a8553f", "3d3f55", "b08a4a"]
	var beds := ["c9d6e8", "e8c9c9", "d8e3c7", "e9dfc2", "b9b3d6", "f0d9b0"]
	var curtains := ["7a1f2b", "d9c9a8", "3f5f7a", "8a9a7a", "c98a5a", "ece6da"]
	var woods := ["5a3a26", "8a6a45", "d9c7a5", "2f2a28"]
	var floors := [["parke", "e2d6c4", "Parke"], ["parke", "8f705a", "Koyu Parke"], ["parke", "b4b0ac", "Gri Laminat"], ["karo", "cfc8bc", "Seramik"]]
	var f: Array = floors[r.randi() % floors.size()]
	return {
		"wall": walls[r.randi() % walls.size()], "wall2": walls[r.randi() % walls.size()],
		"sofa": sofas[r.randi() % sofas.size()], "bed": beds[r.randi() % beds.size()],
		"curtain": curtains[r.randi() % curtains.size()], "wood": woods[r.randi() % woods.size()],
		"floor": f[0], "floor_tint": f[1], "floor_name": f[2],
		"balcony": t != "müstakil" and r.randf() < 0.6,
		"view": "bahce" if t == "müstakil" else ["sehir", "park", "sehir"][r.randi() % 3],
		"style": r.randi() % 3,
	}


func _ready() -> void:
	pal = palette(seed_i, type)
	_rng.seed = seed_i * 131 + 7
	_wall_m = Kit.mat(Color(pal["wall"]).darkened(0.12).to_html(false), 0.95)
	_wood = Kit.mat(pal["wood"], 0.45)
	_white = Kit.mat("f6f3ec", 0.8)
	var back: Array = [["yatak", 4.2]]
	var front: Array = [["banyo", 4.2]]
	match type:
		"2+1":
			W = 12.8
			D = 8.0
			SW = 5.6
			back = [["yatak", 3.9], ["oda", 3.3]]
			front = [["mutfak", 4.2], ["banyo", 3.0]]
		"3+1":
			W = 16.4
			D = 8.6
			SW = 6.0
			back = [["yatak", 3.9], ["oda", 3.2], ["calisma", 3.3]]
			front = [["mutfak", 4.4], ["banyo", 2.8], ["kiler", 3.2]]
		"müstakil":
			W = 14.0
			D = 9.0
			SW = 6.4
			back = [["yatak", 4.2], ["oda", 3.4]]
			front = [["mutfak", 4.6], ["banyo", 3.0]]
			X0 = -6.5
	if pal["balcony"]:
		X0 = -1.5
	CZ0 = snappedf(D * 0.5 + 0.2, 0.1)
	CZ1 = CZ0 + 1.3
	entrance_local = Vector2(SW - 1.4, D - 0.75)
	_build_shell(back, front)
	_build_salon()
	var x := SW
	var first := true
	for c in back:
		var w: float = c[1]
		_build_back_room(String(c[0]), x, x + w, first)
		first = false
		x += w
	x = SW
	for c in front:
		var w: float = c[1]
		match String(c[0]):
			"mutfak":
				_build_kitchen(x, x + w)
			"banyo":
				_build_bath(x, x + w)
			_:
				_build_laundry(x, x + w)
		x += w
	# Koridor: yolluk, ayakkabilik
	var mid := (CZ0 + CZ1) * 0.5
	Kit.box(self, Vector3(W - SW - 1.2, 0.012, 0.75), Vector3((SW + W) * 0.5 - 0.3, 0.008, mid), Kit.mat(pal["curtain"], 0.95))
	Kit.box(self, Vector3(0.36, 0.8, 0.9), Vector3(W - 0.2, 0.4, mid), _wood)
	_solid(Vector2(W - 0.2, mid), Vector2(0.18, 0.45))
	furn_slots["tablo"] = Vector2(W - 0.03, mid)
	mess_spots.append(Vector2(SW + 1.6, mid))
	mess_spots.append(Vector2(W - 1.6, mid))
	if X0 < -2.0:
		_build_garden()
	elif X0 < 0.0:
		_build_balcony()
	_light(Vector3(SW * 0.5, 2.3, D * 0.45), 7.5, 0.7)
	_light(Vector3((SW + W) * 0.5, 2.3, CZ0 * 0.5), 7.0, 0.55)
	_light(Vector3((SW + W) * 0.5, 2.3, (CZ1 + D) * 0.5), 7.0, 0.5)
	if W - SW > 9.0:
		_light(Vector3(W - 2.0, 2.3, D * 0.5), 6.0, 0.45)


# ---------------------------------------------------------------- arayuz

func w2(p: Vector2) -> Vector2:
	return Vector2(global_position.x + p.x, global_position.z + p.y)


func local2(p: Vector2) -> Vector2:
	return Vector2(p.x - global_position.x, p.y - global_position.z)


func has_point(p: Vector2) -> bool:
	var l := local2(p)
	return l.x > X0 - 0.2 and l.x < W + 0.2 and l.y > -0.2 and l.y < D + 0.2


func resolve(np: Vector2, r: float, old: Vector2) -> Vector2:
	var p := local2(np)
	var o := local2(old)
	p.x = clampf(p.x, X0 + r, W - r)
	p.y = clampf(p.y, r, D - r)
	for pass_i in 3:
		for s in colliders:
			var q := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
			var d := p.distance_to(q)
			if d < r:
				var n := (p - q).normalized() if d > 0.0001 else (o - q).normalized()
				p = q + n * r
	for s in colliders:
		if Geometry2D.segment_intersects_segment(o, p, s[0], s[1]) != null:
			p = o
			break
	return w2(p)


func is_free(p: Vector2, r := 0.4) -> bool:
	return has_point(p) and resolve(p, r, p).distance_to(p) < 0.05


## Kamera hangi dis duvarin arkasindaysa o duvar (ve tavan) gizlenir.
func update_view(cam_pos: Vector3) -> void:
	var l := cam_pos - global_position
	ceiling.visible = l.y < H - 0.05
	_back.visible = l.z > 0.0
	_front.visible = l.z < D
	_left.visible = l.x > 0.0
	_right.visible = l.x < W


func near_bed(lo: Vector2) -> bool:
	var q := (lo - bed_c).abs() - bed_half
	return maxf(q.x, q.y) < 0.75


## Yatagin oturulan kenari (uyurken).
func bed_edge() -> Vector2:
	return Vector2(bed_c.x + bed_half.x - 0.18, bed_c.y + 0.1)


# ---------------------------------------------------------------- yardimcilar

func _solid(c: Vector2, half: Vector2) -> void:
	var a := c - half
	var b := c + half
	colliders.append([a, Vector2(b.x, a.y)])
	colliders.append([Vector2(b.x, a.y), b])
	colliders.append([b, Vector2(a.x, b.y)])
	colliders.append([Vector2(a.x, b.y), a])


func _light(at: Vector3, rng: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = at
	l.light_color = Color("ffe9c8")
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.shadow_enabled = false
	add_child(l)
	lights.append(l)
	Kit.cyl(self, 0.16, 0.2, 0.08, Vector3(at.x, H - 0.3, at.z), Kit.glow("fff0d0", 1.4), 14)


func _floor(x0: float, z0: float, x1: float, z1: float, kind: String, tint: String) -> void:
	var m := StandardMaterial3D.new()
	var tex := {"parke": "parke.jpg", "karo": "karo_beyaz.jpg", "mint": "karo_mint.jpg", "desen": "karo_desen.jpg"}.get(kind, "") as String
	var path := "res://assets/home/" + tex
	if tex != "" and ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		var s := 2.4 if kind == "parke" else 0.9
		m.uv1_scale = Vector3((x1 - x0) / s, (z1 - z0) / s, 1)
	m.albedo_color = Color(tint)
	m.roughness = 0.35 if kind == "parke" else 0.15
	Kit.box(self, Vector3(x1 - x0, 0.1, z1 - z0), Vector3((x0 + x1) * 0.5, -0.05, (z0 + z1) * 0.5), m)


## Ara duvar: x ekseni boyunca (z sabit). gaps: [x0, x1] kapi bosluklari.
func _pwall_x(z: float, x0: float, x1: float, gaps: Array = []) -> void:
	var x := x0
	for g in gaps:
		_pseg(Vector2(x, z), Vector2(float(g[0]), z))
		Kit.box(self, Vector3(float(g[1]) - float(g[0]), PH - 2.05, 0.1), Vector3((float(g[0]) + float(g[1])) * 0.5, (PH + 2.05) * 0.5, z), _wall_m)
		for gx in g:
			Kit.box(self, Vector3(0.06, 2.05, 0.14), Vector3(float(gx), 1.025, z), _wood)
		x = float(g[1])
	_pseg(Vector2(x, z), Vector2(x1, z))


func _pwall_z(x: float, z0: float, z1: float) -> void:
	_pseg(Vector2(x, z0), Vector2(x, z1))


func _pseg(a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) < 0.02:
		return
	var size := Vector3(absf(b.x - a.x) + 0.1, PH, 0.1) if absf(b.y - a.y) < 0.01 else Vector3(0.1, PH, absf(b.y - a.y) + 0.1)
	Kit.box(self, size, Vector3((a.x + b.x) * 0.5, PH * 0.5, (a.y + b.y) * 0.5), _wall_m)
	colliders.append([a, b])


func _glass() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.8, 0.9, 0.96, 0.16)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.roughness = 0.03
	return g


# ---------------------------------------------------------------- kabuk

func _build_shell(back: Array, front: Array) -> void:
	_floor(0, 0, W, D, pal["floor"], pal["floor_tint"])
	ceiling = Node3D.new()
	add_child(ceiling)
	Kit.box(ceiling, Vector3(W, 0.1, D), Vector3(W * 0.5, H + 0.05, D * 0.5), Kit.mat("e4dfd6", 0.9))
	_back = Node3D.new()
	_front = Node3D.new()
	_left = Node3D.new()
	_right = Node3D.new()
	for n in [_back, _front, _left, _right]:
		add_child(n)
	# Arka duvar: salon penceresi + her arka odada bir pencere
	var wins: Array = [[1.2, SW - 1.3, 0.55, 2.35]]
	var x := SW
	for c in back:
		var w: float = c[1]
		var cx := x + w * 0.5 if String(c[0]) != "oda" else x + 1.2
		wins.append([cx - 0.8, cx + 0.8, 1.0, 2.3])
		x += w
	var px := 0.0
	var cur := Kit.mat(pal["curtain"], 0.95)
	for wn in wins:
		var a: float = wn[0]
		var b: float = wn[1]
		var y0: float = wn[2]
		var y1: float = wn[3]
		Kit.box(_back, Vector3(a - px, H, 0.12), Vector3((px + a) * 0.5, H * 0.5, -0.06), _wall_m)
		Kit.box(_back, Vector3(b - a, y0, 0.12), Vector3((a + b) * 0.5, y0 * 0.5, -0.06), _wall_m)
		Kit.box(_back, Vector3(b - a, H - y1, 0.12), Vector3((a + b) * 0.5, (H + y1) * 0.5, -0.06), _wall_m)
		Kit.box(_back, Vector3(b - a, y1 - y0, 0.03), Vector3((a + b) * 0.5, (y0 + y1) * 0.5, -0.06), _glass())
		for fx in [a, (a + b) * 0.5, b]:
			Kit.box(_back, Vector3(0.06, y1 - y0, 0.08), Vector3(fx, (y0 + y1) * 0.5, -0.05), _white)
		Kit.box(_back, Vector3(b - a + 0.1, 0.06, 0.2), Vector3((a + b) * 0.5, y0, 0.02), _white)
		for cx2 in [a - 0.18, b + 0.18]:
			Kit.box(_back, Vector3(0.42, y1 - y0 + 0.35, 0.08), Vector3(cx2, (y0 + y1) * 0.5 - 0.05, 0.1), cur)
		Kit.cyl(_back, 0.02, 0.02, b - a + 1.0, Vector3((a + b) * 0.5, y1 + 0.15, 0.1), _wood, 8, Vector3(0, 0, PI * 0.5))
		px = b
	Kit.box(_back, Vector3(W - px, H, 0.12), Vector3((px + W) * 0.5, H * 0.5, -0.06), _wall_m)
	_build_view()
	# Sag ve on duvar
	Kit.box(_right, Vector3(0.12, H, D + 0.24), Vector3(W + 0.06, H * 0.5, D * 0.5), _wall_m)
	Kit.box(_front, Vector3(W + 0.24, H, 0.12), Vector3(W * 0.5, H * 0.5, D + 0.06), _wall_m)
	Kit.box(_front, Vector3(0.95, 2.1, 0.06), Vector3(entrance_local.x, 1.05, D - 0.01), _wood)
	Kit.ball(_front, 0.035, Vector3(entrance_local.x + 0.35, 1.0, D - 0.06), Kit.mat("c9a45c", 0.3))
	Kit.box(self, Vector3(0.9, 0.012, 0.55), Vector3(entrance_local.x, 0.008, D - 0.4), Kit.mat("4a4038", 1.0))
	# Sol duvar: balkon / bahce kapisi varsa bosluklu
	if X0 < 0.0:
		var g0 := 3.45
		var g1 := 4.35
		Kit.box(_left, Vector3(0.12, H, g0), Vector3(-0.06, H * 0.5, g0 * 0.5), _wall_m)
		Kit.box(_left, Vector3(0.12, H, D - g1), Vector3(-0.06, H * 0.5, (g1 + D) * 0.5), _wall_m)
		Kit.box(_left, Vector3(0.12, H - 2.1, g1 - g0), Vector3(-0.06, (H + 2.1) * 0.5, (g0 + g1) * 0.5), _wall_m)
		for gz in [g0, g1]:
			Kit.box(_left, Vector3(0.16, 2.1, 0.06), Vector3(-0.06, 1.05, gz), _white)
		colliders.append([Vector2(-0.02, 0), Vector2(-0.02, g0)])
		colliders.append([Vector2(-0.02, g1), Vector2(-0.02, D)])
	else:
		Kit.box(_left, Vector3(0.12, H, D + 0.24), Vector3(-0.06, H * 0.5, D * 0.5), _wall_m)
	# Ara duvarlar: salon | sag blok, koridorun iki yani, odalar arasi
	_pwall_z(SW, 0, CZ0)
	_pwall_z(SW, CZ1, D)
	var gaps: Array = []
	x = SW
	for c in back:
		gaps.append([x + 0.35, x + 1.25])
		x += float(c[1])
		if x < W - 0.05:
			_pwall_z(x, 0, CZ0)
	_pwall_x(CZ0, SW, W, gaps)
	gaps = []
	x = SW
	for c in front:
		gaps.append([x + 0.35, x + 1.25])
		x += float(c[1])
		if x < W - 0.05:
			_pwall_z(x, CZ1, D)
	_pwall_x(CZ1, SW, W, gaps)


## Pencerelerin arkasindaki manzara: gokyuzu + sehir silueti / park agaclari / bahce citi.
func _build_view() -> void:
	var night := hour < 6.5 or hour > 19.0
	var sky := StandardMaterial3D.new()
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky.albedo_color = Color("141b33") if night else (Color("f0b98a") if hour > 17.5 or hour < 7.5 else Color("a9d3f2"))
	Kit.box(_back, Vector3(W + 6.0, 9.0, 0.05), Vector3(W * 0.5, 1.0, -2.6), sky)
	var bx := -2.0
	while bx < W + 2.0:
		var bw := _rng.randf_range(0.9, 1.7)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var shade := _rng.randf_range(0.0, 0.25)
		if pal["view"] == "sehir":
			var top := _rng.randf_range(-0.4, 2.0)
			m.albedo_color = Color("1d2440").lightened(shade * 0.4) if night else Color("8d9aa8").lightened(shade)
			var bz := _rng.randf_range(-2.3, -1.5)
			Kit.box(_back, Vector3(bw, 6.0, 0.3), Vector3(bx + bw * 0.5, top - 3.0, bz), m)
			if night:
				for k in 3:
					Kit.box(_back, Vector3(0.14, 0.12, 0.02), Vector3(bx + _rng.randf_range(0.2, bw - 0.2), top - _rng.randf_range(0.3, 1.4), bz + 0.17), Kit.glow("ffd98a", 1.6))
		else:
			m.albedo_color = (Color("12301c") if night else Color("3f8a4a")).lightened(shade)
			var r := _rng.randf_range(0.7, 1.3)
			Kit.ball(_back, r, Vector3(bx + bw * 0.5, _rng.randf_range(0.6, 1.5) + (0.6 if pal["view"] == "park" else 0.0), _rng.randf_range(-2.3, -1.6)), m, Vector3(1, 1.2, 0.4), 10)
		bx += bw + _rng.randf_range(-0.2, 0.3)
	if pal["view"] != "sehir":
		var g := StandardMaterial3D.new()
		g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		g.albedo_color = Color("16351f") if night else Color("5f9f55")
		Kit.box(_back, Vector3(W + 6.0, 2.0, 0.1), Vector3(W * 0.5, -0.2, -2.4), g)


# ---------------------------------------------------------------- mobilya parcalari

func _sofa(c: Vector2, length: float, rot: float, hex: String) -> void:
	var m := Kit.mat(hex, 0.95)
	var r := Kit.pivot(self, Vector3(c.x, 0, c.y))
	r.rotation.y = rot
	Kit.box(r, Vector3(length, 0.42, 0.9), Vector3(0, 0.23, 0), m)
	Kit.box(r, Vector3(length, 0.55, 0.22), Vector3(0, 0.66, -0.36), m)
	for sx in [-1.0, 1.0]:
		Kit.box(r, Vector3(0.2, 0.62, 0.9), Vector3(sx * (length * 0.5 - 0.1), 0.33, 0), m)
	var cu := Kit.mat(Color(hex).lightened(0.12).to_html(false), 0.95)
	Kit.box(r, Vector3(length - 0.5, 0.1, 0.6), Vector3(0, 0.47, 0.08), cu)
	Kit.box(r, Vector3(0.4, 0.36, 0.14), Vector3(-length * 0.5 + 0.5, 0.68, -0.18), Kit.mat(pal["curtain"], 0.95), Vector3(-0.3, 0, 0))
	var side := absf(sin(rot)) > 0.5
	_solid(c, Vector2(0.45, length * 0.5) if side else Vector2(length * 0.5, 0.45))


func _bed(c: Vector2, half: Vector2, cover: String) -> void:
	Kit.box(self, Vector3(half.x * 2, 0.3, half.y * 2), Vector3(c.x, 0.15, c.y), _wood)
	Kit.box(self, Vector3(half.x * 2 - 0.06, 0.2, half.y * 2 - 0.06), Vector3(c.x, 0.4, c.y), _white)
	Kit.box(self, Vector3(half.x * 2 + 0.02, 0.07, half.y * 1.3), Vector3(c.x, 0.52, c.y + half.y * 0.33), Kit.mat(cover, 0.95))
	Kit.box(self, Vector3(half.x * 2, 0.95, 0.08), Vector3(c.x, 0.55, c.y - half.y + 0.04), _wood)
	var n := 2 if half.x > 0.6 else 1
	for i in n:
		var px := c.x + (float(i) - (n - 1) * 0.5) * 0.75
		Kit.box(self, Vector3(0.6, 0.12, 0.38), Vector3(px, 0.56, c.y - half.y + 0.36), _white, Vector3(0.12, 0, 0))
	_solid(c, half)


func _chair(c: Vector2, rot: float, hex: String) -> void:
	var m := Kit.mat(hex, 0.6)
	var r := Kit.pivot(self, Vector3(c.x, 0, c.y))
	r.rotation.y = rot
	Kit.box(r, Vector3(0.42, 0.05, 0.42), Vector3(0, 0.46, 0), m)
	Kit.box(r, Vector3(0.42, 0.5, 0.04), Vector3(0, 0.72, -0.19), m)
	for sx in [-0.18, 0.18]:
		for sz in [-0.18, 0.18]:
			Kit.box(r, Vector3(0.04, 0.45, 0.04), Vector3(sx, 0.225, sz), m)


func _table(c: Vector2, size: Vector2, h := 0.74) -> void:
	Kit.box(self, Vector3(size.x, 0.05, size.y), Vector3(c.x, h, c.y), _wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Kit.box(self, Vector3(0.06, h, 0.06), Vector3(c.x + sx * (size.x * 0.5 - 0.07), h * 0.5, c.y + sz * (size.y * 0.5 - 0.07)), _wood)
	_solid(c, size * 0.5)


func _plant(at: Vector2, s := 1.0) -> void:
	Kit.cyl(self, 0.22 * s, 0.17 * s, 0.42 * s, Vector3(at.x, 0.21 * s, at.y), Kit.mat("e9e2d2", 0.5), 14)
	Kit.ball(self, 0.36 * s, Vector3(at.x, 1.0 * s, at.y), Kit.mat("2f7a45", 0.8), Vector3(1, 1.25, 1))
	Kit.ball(self, 0.25 * s, Vector3(at.x + 0.16 * s, 0.7 * s, at.y + 0.1 * s), Kit.mat("3b8f52", 0.8))
	_solid(at, Vector2(0.2, 0.2) * s)


func _shelf(c: Vector2, size: Vector2, h: float) -> void:
	Kit.box(self, Vector3(size.x, h, size.y), Vector3(c.x, h * 0.5, c.y), _wood)
	var cols := ["a8553f", "3f5f7a", "d9a441", "5c6b4a", "ece6da"]
	var along_z := size.y > size.x
	var n := int(maxf(size.x, size.y) / 0.16)
	for row in int(h / 0.42):
		for i in n:
			if _rng.randf() < 0.25:
				continue
			var t := (float(i) + 0.5) / n - 0.5
			var bh := _rng.randf_range(0.2, 0.3)
			var pos := Vector3(c.x - size.x * 0.5 - 0.01, 0.2 + row * 0.42 + bh * 0.5, c.y + t * size.y) if along_z else Vector3(c.x + t * size.x, 0.2 + row * 0.42 + bh * 0.5, c.y + size.y * 0.5 + 0.01)
			Kit.box(self, Vector3(0.03, bh, 0.1) if along_z else Vector3(0.1, bh, 0.03), pos, Kit.mat(cols[_rng.randi() % cols.size()], 0.8))
	_solid(c, size * 0.5)


# ---------------------------------------------------------------- odalar

func _build_salon() -> void:
	var cz := 2.3
	_sofa(Vector2(0.55, cz), 2.0, PI * 0.5, pal["sofa"])
	if int(pal["style"]) != 1 and SW > 5.9:
		# Tekli koltuk (pencere onu)
		_sofa(Vector2(SW * 0.5 + 0.9, 0.8), 1.0, 0.0, Color(pal["sofa"]).darkened(0.15).to_html(false))
	# Hali, sehpa
	Kit.box(self, Vector3(2.3, 0.014, 1.7), Vector3(SW * 0.47, 0.009, cz), Kit.mat(Color(pal["curtain"]).darkened(0.1).to_html(false), 1.0))
	Kit.box(self, Vector3(2.1, 0.016, 1.5), Vector3(SW * 0.47, 0.01, cz), Kit.mat(Color(pal["sofa"]).lightened(0.45).to_html(false), 1.0))
	_table(Vector2(SW * 0.47, cz), Vector2(0.6, 1.0), 0.4)
	Kit.cyl(self, 0.07, 0.05, 0.1, Vector3(SW * 0.47, 0.48, cz - 0.2), Kit.mat("d9a441", 0.4), 10)
	# TV unitesi (salon | yatak odasi duvari)
	Kit.box(self, Vector3(0.4, 0.5, 1.7), Vector3(SW - 0.26, 0.25, cz), _wood)
	Kit.box(self, Vector3(0.05, 0.64, 1.15), Vector3(SW - 0.3, 0.95, cz), Kit.mat("0c0e12", 0.15))
	_solid(Vector2(SW - 0.26, cz), Vector2(0.2, 0.85))
	if int(pal["style"]) == 2:
		_shelf(Vector2(SW - 0.22, CZ0 - 0.6), Vector2(0.3, 0.9), 1.7)
	# Tablo (sol duvar, kanepenin ustu)
	Kit.box(self, Vector3(0.03, 0.6, 0.9), Vector3(0.02, 1.65, cz), _wood)
	Kit.box(self, Vector3(0.03, 0.5, 0.8), Vector3(0.03, 1.65, cz), Kit.mat(["3e6e8e", "c98a5a", "6a8a4a"][int(pal["style"])], 0.9))
	# Yemek masasi / acik mutfak
	if type == "1+1":
		_counter_z(0.35, 4.7, 6.1)
		stove_pos = Vector3(0.35, 0.93, 5.3)
		stove_stand = Vector2(1.0, 5.3)
		stove_yaw = PI * 0.5
		_stove(Vector2(0.35, 5.3))
		_fridge(Vector2(0.4, 6.45))
		_table(Vector2(2.6, 5.6), Vector2(0.8, 0.8))
		_chair(Vector2(2.6, 4.95), 0.0, pal["wood"])
		_chair(Vector2(2.6, 6.25), PI, pal["wood"])
		mess_spots.append(Vector2(1.6, 6.0))
	else:
		var tc := Vector2(SW * 0.5 - 0.5, D - 1.9)
		_table(tc, Vector2(1.5, 0.85))
		for sx in [-0.38, 0.38]:
			_chair(tc + Vector2(sx, -0.68), 0.0, pal["wood"])
			_chair(tc + Vector2(sx, 0.68), PI, pal["wood"])
		Kit.cyl(self, 0.09, 0.06, 0.2, Vector3(tc.x, 0.87, tc.y), Kit.mat("3f8a9a", 0.3), 12)
		if type == "müstakil":
			# Somine (salonun on duvari)
			var fx := 0.95
			Kit.box(self, Vector3(1.3, 1.3, 0.4), Vector3(fx, 0.65, D - 0.2), Kit.mat("8a4a3a", 0.9))
			Kit.box(self, Vector3(0.7, 0.6, 0.1), Vector3(fx, 0.35, D - 0.42), Kit.mat("15100e", 1.0))
			Kit.box(self, Vector3(0.5, 0.25, 0.05), Vector3(fx, 0.2, D - 0.45), Kit.glow("ff7a1a", 2.2))
			Kit.box(self, Vector3(1.5, 0.06, 0.5), Vector3(fx, 1.33, D - 0.25), _wood)
			_solid(Vector2(fx, D - 0.2), Vector2(0.65, 0.22))
	furn_slots["bitki"] = Vector2(0.4, 0.45)
	furn_slots["lamba"] = Vector2(0.32, 1.0)
	furn_slots["yatak"] = petbed_local
	furn_slots["akvaryum"] = Vector2(SW - 0.68, 0.3)
	furn_slots["agac"] = Vector2(SW - 0.45, CZ1 + 0.55)
	mess_spots.append_array([Vector2(2.6, 3.7), Vector2(SW - 1.3, 3.9), Vector2(1.5, 1.4), Vector2(SW - 1.4, 1.0), Vector2(SW - 2.0, D - 2.9)])


func _counter_z(x: float, z0: float, z1: float) -> void:
	Kit.box(self, Vector3(0.6, 0.86, z1 - z0), Vector3(x, 0.43, (z0 + z1) * 0.5), _white)
	Kit.box(self, Vector3(0.64, 0.05, z1 - z0 + 0.02), Vector3(x, 0.885, (z0 + z1) * 0.5), Kit.mat("3a3632", 0.25))
	Kit.box(self, Vector3(0.34, 0.6, z1 - z0), Vector3(x - 0.13, 1.85, (z0 + z1) * 0.5), _wood)
	_solid(Vector2(x, (z0 + z1) * 0.5), Vector2(0.3, (z1 - z0) * 0.5))


func _stove(c: Vector2) -> void:
	Kit.box(self, Vector3(0.5, 0.02, 0.5), Vector3(c.x, 0.915, c.y), Kit.mat("15171a", 0.2))
	for sx in [-0.12, 0.12]:
		for sz in [-0.12, 0.12]:
			Kit.torus(self, 0.03, 0.07, Vector3(c.x + sx, 0.93, c.y + sz), Kit.mat("2a2a2c", 0.4))


func _fridge(c: Vector2) -> void:
	var m := Kit.mat("d8dce0", 0.3)
	m.metallic = 0.5
	Kit.box(self, Vector3(0.68, 1.85, 0.68), Vector3(c.x, 0.925, c.y), m)
	_solid(c, Vector2(0.34, 0.34))


## Arka (pencereli) odalar: yatak odasi, cocuk/misafir odasi, calisma odasi.
func _build_back_room(kind: String, x0: float, x1: float, master: bool) -> void:
	var cx := (x0 + x1) * 0.5
	if kind != "yatak" or int(pal["style"]) == 1:
		# Farkli renkte duvar boyasi hissi: zeminde hali
		Kit.box(self, Vector3(x1 - x0 - 1.0, 0.012, 1.2), Vector3(cx, 0.008, CZ0 - 0.9), Kit.mat(pal["wall2"], 1.0))
	match kind:
		"yatak":
			var c := Vector2(cx, 1.2)
			_bed(c, Vector2(0.8, 1.05), pal["bed"])
			for sx in [-1.06, 1.06]:
				Kit.box(self, Vector3(0.42, 0.45, 0.4), Vector3(cx + sx, 0.225, 0.3), _wood)
				_solid(Vector2(cx + sx, 0.3), Vector2(0.21, 0.2))
			Kit.cyl(self, 0.09, 0.13, 0.22, Vector3(cx + 1.06, 0.62, 0.3), Kit.glow("ffe2b0", 0.9), 12)
			# Gardirop (sag duvar)
			Kit.box(self, Vector3(0.6, 2.05, 1.2), Vector3(x1 - 0.38, 1.025, CZ0 - 0.85), _wood)
			Kit.box(self, Vector3(0.02, 1.9, 0.02), Vector3(x1 - 0.69, 1.0, CZ0 - 0.85), Kit.mat("15100e", 0.5))
			_solid(Vector2(x1 - 0.38, CZ0 - 0.85), Vector2(0.3, 0.6))
			if master:
				bed_c = c
				bed_half = Vector2(0.8, 1.05)
				furn_slots["hali"] = Vector2(cx - 0.2, 2.95)
			mess_spots.append(Vector2(cx - 1.3, 2.7))
		"oda":
			_bed(Vector2(x1 - 0.62, 1.15), Vector2(0.5, 1.0), pal["wall2"] if pal["wall2"] != pal["wall"] else "f0d9b0")
			_table(Vector2(x0 + 1.2, 0.4), Vector2(1.2, 0.55))
			_chair(Vector2(x0 + 1.2, 1.0), PI, "d9673a")
			_shelf(Vector2(x0 + 0.24, 2.6), Vector2(0.32, 1.0), 1.3)
			Kit.ball(self, 0.14, Vector3(cx, 0.14, CZ0 - 1.0), Kit.mat("e0322b", 0.5))
			mess_spots.append(Vector2(cx, 2.6))
		_:
			_table(Vector2(cx, 0.45), Vector2(1.5, 0.62))
			Kit.box(self, Vector3(0.5, 0.32, 0.04), Vector3(cx, 0.95, 0.35), Kit.mat("0c0e12", 0.2))
			_chair(Vector2(cx, 1.1), PI, "2a2a2e")
			_shelf(Vector2(x1 - 0.24, 2.4), Vector2(0.32, 1.4), 1.9)
			_sofa(Vector2(x0 + 0.6, 2.5), 1.0, PI * 0.5, Color(pal["sofa"]).lightened(0.15).to_html(false))
			mess_spots.append(Vector2(cx, 2.6))


func _build_kitchen(x0: float, x1: float) -> void:
	_floor(x0 + 0.05, CZ1 + 0.05, x1 - 0.05, D, "desen" if int(pal["style"]) == 0 else "karo", "d6d2ca")
	var a := x0 + 1.55
	var b := x1 - 0.85
	var z := CZ1 + 0.36
	Kit.box(self, Vector3(b - a, 0.86, 0.6), Vector3((a + b) * 0.5, 0.43, z), _white)
	Kit.box(self, Vector3(b - a + 0.02, 0.05, 0.64), Vector3((a + b) * 0.5, 0.885, z), Kit.mat("3a3632", 0.25))
	Kit.box(self, Vector3(b - a, 0.55, 0.34), Vector3((a + b) * 0.5, 1.8, z - 0.12), _wood)
	_solid(Vector2((a + b) * 0.5, z), Vector2((b - a) * 0.5, 0.3))
	var sx := a + 0.75
	_stove(Vector2(sx, z))
	stove_pos = Vector3(sx, 0.93, z)
	stove_stand = Vector2(sx, z + 0.68)
	stove_yaw = 0.0
	# Evye
	Kit.box(self, Vector3(0.5, 0.03, 0.4), Vector3(b - 0.45, 0.905, z), Kit.mat("b8bcc0", 0.2))
	Kit.cyl(self, 0.015, 0.015, 0.25, Vector3(b - 0.45, 1.03, z - 0.2), Kit.mat("d0d4d8", 0.2), 8)
	_fridge(Vector2(x1 - 0.42, CZ1 + 0.42))
	if D - CZ1 > 2.4:
		var tc := Vector2((x0 + x1) * 0.5 + 0.4, D - 0.6)
		_table(tc, Vector2(1.0, 0.6))
		_chair(tc + Vector2(-0.25, -0.55), 0.0, pal["wood"])
		_chair(tc + Vector2(0.25, -0.55), 0.0, pal["wood"])
	mess_spots.append(Vector2(x0 + 0.9, CZ1 + 1.3))


func _build_bath(x0: float, x1: float) -> void:
	_floor(x0 + 0.05, CZ1 + 0.05, x1 - 0.05, D, "mint" if int(pal["style"]) != 2 else "karo", "d6d2ca")
	var cer := Kit.mat("f8f8f6", 0.15)
	# Lavabo + ayna (koridor duvari)
	var sx := x0 + 1.9
	Kit.box(self, Vector3(0.7, 0.8, 0.45), Vector3(sx, 0.4, CZ1 + 0.28), _wood)
	Kit.box(self, Vector3(0.74, 0.06, 0.48), Vector3(sx, 0.83, CZ1 + 0.29), cer)
	Kit.box(self, Vector3(0.6, 0.7, 0.02), Vector3(sx, 1.5, CZ1 + 0.07), Kit.mat("bcd4e0", 0.05))
	_solid(Vector2(sx, CZ1 + 0.28), Vector2(0.35, 0.23))
	# Dus kabini (arka sag kose)
	var sc := Vector2(x1 - 0.5, CZ1 + 0.52)
	Kit.box(self, Vector3(0.9, 0.08, 0.9), Vector3(sc.x, 0.04, sc.y), cer)
	Kit.box(self, Vector3(0.03, 1.9, 0.9), Vector3(sc.x - 0.45, 0.99, sc.y), _glass())
	Kit.box(self, Vector3(0.9, 1.9, 0.03), Vector3(sc.x, 0.99, sc.y + 0.45), _glass())
	Kit.cyl(self, 0.08, 0.08, 0.02, Vector3(sc.x + 0.2, 2.0, sc.y - 0.2), Kit.mat("c0c4c8", 0.2), 12)
	_solid(sc, Vector2(0.45, 0.45))
	# Klozet (sag duvar, onde)
	var tc := Vector2(x1 - 0.4, D - 0.5)
	Kit.box(self, Vector3(0.2, 0.75, 0.42), Vector3(tc.x + 0.25, 0.38, tc.y), cer)
	Kit.cyl(self, 0.2, 0.16, 0.4, Vector3(tc.x - 0.05, 0.2, tc.y), cer, 14)
	Kit.cyl(self, 0.21, 0.21, 0.03, Vector3(tc.x - 0.05, 0.42, tc.y), cer, 14)
	_solid(tc, Vector2(0.35, 0.22))
	Kit.box(self, Vector3(0.8, 0.012, 0.5), Vector3(x0 + 0.9, 0.06, CZ1 + 0.9), Kit.mat(pal["curtain"], 1.0))


func _build_laundry(x0: float, x1: float) -> void:
	var c := Vector2(x1 - 0.4, CZ1 + 0.45)
	Kit.box(self, Vector3(0.62, 0.86, 0.62), Vector3(c.x, 0.43, c.y), _white)
	Kit.cyl(self, 0.2, 0.2, 0.03, Vector3(c.x - 0.32, 0.45, c.y), Kit.mat("2a3a4a", 0.1), 16, Vector3(0, 0, PI * 0.5))
	_solid(c, Vector2(0.31, 0.31))
	_shelf(Vector2(x1 - 0.24, D - 0.8), Vector2(0.32, 1.2), 1.7)
	# Utu masasi
	Kit.box(self, Vector3(1.1, 0.04, 0.34), Vector3(x0 + 2.0, 0.85, D - 0.5), Kit.mat(pal["bed"], 0.9))
	Kit.box(self, Vector3(0.04, 0.85, 0.04), Vector3(x0 + 2.0, 0.42, D - 0.5), Kit.mat("b0b0b0", 0.3))
	_solid(Vector2(x0 + 2.0, D - 0.5), Vector2(0.55, 0.17))


# ---------------------------------------------------------------- balkon ve bahce

func _build_balcony() -> void:
	var z0 := 2.2
	var z1 := 5.6
	Kit.box(self, Vector3(1.5, 0.1, z1 - z0), Vector3(-0.75, -0.05, (z0 + z1) * 0.5), Kit.mat("b8b0a4", 0.6))
	var rail := Kit.mat("2a2c30", 0.4)
	Kit.box(self, Vector3(0.05, 0.05, z1 - z0), Vector3(-1.47, 1.0, (z0 + z1) * 0.5), rail)
	for z in [z0, z1]:
		Kit.box(self, Vector3(1.5, 0.05, 0.05), Vector3(-0.75, 1.0, z), rail)
		colliders.append([Vector2(-1.5, z), Vector2(0, z)])
	var n := 12
	for i in n + 1:
		Kit.box(self, Vector3(0.025, 1.0, 0.025), Vector3(-1.47, 0.5, lerpf(z0, z1, float(i) / n)), rail)
	for i in 5:
		for z in [z0, z1]:
			Kit.box(self, Vector3(0.025, 1.0, 0.025), Vector3(-1.5 + 0.3 * i, 0.5, z), rail)
	_chair(Vector2(-0.8, z0 + 0.5), PI, "d9c7a5")
	_plant(Vector2(-1.1, z1 - 0.4), 0.8)
	Kit.box(self, Vector3(0.9, 0.2, 0.22), Vector3(-1.3, 1.05, 3.9), Kit.mat("8a5a3a", 0.8), Vector3(0, PI * 0.5, 0))
	for i in 4:
		Kit.ball(self, 0.1, Vector3(-1.3, 1.22, 3.55 + i * 0.23), Kit.mat(["e0322b", "f2b33a", "e86aa0", "f4f4f0"][i], 0.7))


func _build_garden() -> void:
	var grass := Kit.mat("4f8f3f", 1.0)
	Kit.box(self, Vector3(6.5, 0.1, D), Vector3(-3.25, -0.05, D * 0.5), grass)
	# Tas yol
	for i in 6:
		Kit.cyl(self, 0.28, 0.28, 0.03, Vector3(-0.5 - i * 0.75, 0.012, 3.9 + 0.12 * sin(i * 1.7)), Kit.mat("b8b0a4", 0.9), 10)
	# Cit
	var fence := Kit.mat("e8e0d0", 0.7)
	for z in [0.03, D - 0.03]:
		Kit.box(self, Vector3(6.5, 0.06, 0.04), Vector3(-3.25, 0.75, z), fence)
		for i in 22:
			Kit.box(self, Vector3(0.1, 0.95, 0.03), Vector3(-6.45 + i * 0.3, 0.47, z), fence)
	Kit.box(self, Vector3(0.04, 0.06, D), Vector3(-6.47, 0.75, D * 0.5), fence)
	for i in int(D / 0.3) + 1:
		Kit.box(self, Vector3(0.03, 0.95, 0.1), Vector3(-6.47, 0.47, i * 0.3), fence)
	# Agac
	var tp := Vector2(-4.7, 2.0)
	Kit.cyl(self, 0.14, 0.2, 2.2, Vector3(tp.x, 1.1, tp.y), Kit.mat("5b4630", 0.9), 10)
	Kit.ball(self, 1.3, Vector3(tp.x, 3.0, tp.y), Kit.mat("3b8f42", 0.9), Vector3(1, 0.9, 1))
	Kit.ball(self, 0.9, Vector3(tp.x + 0.7, 2.6, tp.y + 0.4), Kit.mat("2f7a3a", 0.9))
	_solid(tp, Vector2(0.2, 0.2))
	# Bahce masasi, sandalyeler
	var tc := Vector2(-3.2, D - 2.4)
	Kit.cyl(self, 0.55, 0.55, 0.04, Vector3(tc.x, 0.72, tc.y), Kit.mat("f4f4f0", 0.5), 18)
	Kit.cyl(self, 0.05, 0.05, 0.72, Vector3(tc.x, 0.36, tc.y), Kit.mat("d0d0d0", 0.4), 8)
	_solid(tc, Vector2(0.4, 0.4))
	_chair(tc + Vector2(-0.85, 0), -PI * 0.5, "f4f4f0")
	_chair(tc + Vector2(0.85, 0), PI * 0.5, "f4f4f0")
	# Cicek tarhi, kulube
	Kit.box(self, Vector3(3.6, 0.16, 0.5), Vector3(-2.2, 0.08, 0.45), Kit.mat("5a4030", 1.0))
	for i in 9:
		Kit.ball(self, 0.13, Vector3(-3.8 + i * 0.4, 0.27, 0.45 + 0.08 * sin(i * 2.3)), Kit.mat(["e0322b", "f2b33a", "e86aa0", "f4f4f0", "8a5ac8"][i % 5], 0.7))
	var kc := Vector2(-5.5, D - 1.1)
	Kit.box(self, Vector3(0.9, 0.6, 0.9), Vector3(kc.x, 0.3, kc.y), Kit.mat("c98a5a", 0.8))
	Kit.prism(self, Vector3(1.05, 0.45, 1.0), Vector3(kc.x, 0.82, kc.y), Kit.mat("8a2f2a", 0.8))
	Kit.box(self, Vector3(0.02, 0.36, 0.34), Vector3(kc.x + 0.45, 0.2, kc.y), Kit.mat("1a1410", 1.0))
	_solid(kc, Vector2(0.45, 0.45))
	mess_spots.append(Vector2(-2.0, 5.2))
