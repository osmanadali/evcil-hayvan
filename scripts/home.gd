extends Node3D
## Oyuncunun evi (kullanicinin fotograflarindan): koridor, mutfak, WC, banyo, iki yatak odasi, salon ve balkon.
## Yerel koordinatlar metre: x 0..12 (bati -> dogu), z 0..11.6 (kuzey -> guney), zemin y = 0.
## Duvarlar tek yuzlu ve iceri bakar: kamera yukaridan bakinca araya giren duvarlar ve tavan gorunmez (bebek evi).

const Kit = preload("res://scripts/kit.gd")
const H := 2.75          # tavan yuksekligi
const HALF_T := 0.06     # duvar kalinliginin yarisi

# [ad, x0, z0, x1, z1, zemin, duvar alt, acik kenarlar]
const ROOMS := [
	["koridor", 6.0, 0.0, 8.4, 7.4, "koridor", "", ""],
	["mutfak", 1.4, 0.0, 6.0, 2.4, "beyaz", "", ""],
	["yatak", 1.4, 2.4, 6.0, 7.4, "parke", "", ""],
	["wc", 8.4, 2.6, 9.9, 4.2, "desen", "mint", ""],
	["banyo", 8.4, 4.2, 10.8, 6.5, "desen", "mint", ""],
	["kucuk", 8.4, 6.6, 12.0, 10.2, "parke", "", ""],
	["salon", 0.0, 7.4, 8.4, 11.6, "parke", "", ""],
	["balkon", 0.0, 2.4, 1.4, 7.4, "balkon", "", "w"],
]
# [eksen ('x' = x sabit duvar, 'z' = z sabit), cizgi, bas, son, alt, ust, tur]
const OPENINGS := [
	["z", 0.0, 6.8, 7.7, 0.0, 2.1, "giris"],
	["x", 6.0, 0.2, 1.0, 0.0, 2.05, "kapi"],       # mutfak
	["x", 6.0, 5.4, 6.3, 0.0, 2.05, "kapi"],       # yatak odasi
	["x", 8.4, 3.0, 3.7, 0.0, 2.05, "kapi"],       # wc
	["x", 8.4, 4.6, 5.3, 0.0, 2.05, "kapi"],       # banyo
	["x", 8.4, 6.65, 7.35, 0.0, 2.05, "kapi"],     # kucuk oda
	["z", 7.4, 6.2, 8.2, 0.0, 2.3, "kemer"],       # salona acik gecis
	["x", 1.4, 5.2, 6.0, 0.0, 2.2, "balkon"],      # balkon kapisi
	["z", 0.0, 2.6, 3.8, 0.95, 2.2, "pencere"],    # mutfak
	["x", 1.4, 3.0, 4.6, 0.9, 2.2, "pencere"],     # yatak odasi
	["z", 11.6, 0.8, 5.0, 0.7, 2.4, "pencere"],    # salon
	["x", 12.0, 7.6, 8.8, 0.9, 2.2, "pencere"],    # kucuk oda
	["x", 10.8, 5.0, 5.6, 1.6, 2.2, "pencere"],    # banyo
]

var floor_y := 0.0
var colliders: Array = []        # [Vector2 a, Vector2 b] dunya 2B
var lights: Array[OmniLight3D] = []
var ceiling: MeshInstance3D
var entrance_local := Vector2(7.25, 0.9)
var _surf := {}                  # malzeme -> SurfaceTool
var _mats := {}


func _ready() -> void:
	_build_shell()
	_build_furniture()
	_commit()


# ---------------------------------------------------------------- yardimcilar

func w2(p: Vector2) -> Vector2:
	var g := global_transform * Vector3(p.x, 0, p.y)
	return Vector2(g.x, g.z)


func local2(p: Vector2) -> Vector2:
	var l := global_transform.affine_inverse() * Vector3(p.x, floor_y, p.y)
	return Vector2(l.x, l.z)


func has_point(p: Vector2) -> bool:
	var l := local2(p)
	for r in ROOMS:
		if l.x > r[1] and l.x < r[3] and l.y > r[2] and l.y < r[4]:
			return true
	return false


func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.roughness = 0.85
	if key == "tavan":
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match key:
		"siva":
			m.albedo_texture = load("res://assets/home/siva.jpg")
			m.uv1_scale = Vector3(0.5, 0.5, 1)
		"tavan":
			m.albedo_color = Color("f3f1ec")
		"parke":
			m.albedo_texture = load("res://assets/home/parke.jpg")
			m.normal_enabled = true
			m.normal_texture = load("res://assets/home/parke_n.jpg")
			m.uv1_scale = Vector3(0.45, 0.45, 1)
			m.roughness = 0.55
		"koridor":
			m.albedo_texture = load("res://assets/home/karo_koridor.jpg")
			m.uv1_scale = Vector3(0.55, 0.55, 1)
			m.roughness = 0.4
		"desen":
			m.albedo_texture = load("res://assets/home/karo_desen.jpg")
			m.uv1_scale = Vector3(1.25, 1.25, 1)
			m.roughness = 0.35
		"beyaz":
			m.albedo_texture = load("res://assets/home/karo_beyaz.jpg")
			m.uv1_scale = Vector3(1.2, 1.2, 1)
			m.roughness = 0.3
		"balkon":
			m.albedo_color = Color("c9bba6")
			m.albedo_texture = load("res://assets/home/karo_beyaz.jpg")
			m.uv1_scale = Vector3(0.8, 0.8, 1)
		"mint":
			m.albedo_texture = load("res://assets/home/karo_mint.jpg")
			m.uv1_scale = Vector3(1.25, 1.25, 1)
			m.roughness = 0.25
		"karo_ust":
			m.albedo_texture = load("res://assets/home/karo_beyaz.jpg")
			m.uv1_scale = Vector3(1.25, 1.25, 1)
			m.roughness = 0.3
	_mats[key] = m
	return m


## Dortgen: noktalar iceriden bakinca saat yonunun tersine; uv metre cinsinden.
func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	if not _surf.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surf[key] = st
	var st: SurfaceTool = _surf[key]
	var n := (b - a).cross(c - a).normalized()
	for t in [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]:   # Godot: on yuz saat yonunde
		st.set_normal(n)
		st.set_uv(t[1])
		st.add_vertex(t[0])


func _commit() -> void:
	for key in _surf:
		var st: SurfaceTool = _surf[key]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		mi.name = "Yuzey_" + key
		add_child(mi)
		if key == "tavan":
			ceiling = mi


# ---------------------------------------------------------------- kabuk

func _build_shell() -> void:
	for r in ROOMS:
		var x0: float = r[1]
		var z0: float = r[2]
		var x1: float = r[3]
		var z1: float = r[4]
		var fk: String = r[5]
		# Zemin (yukari bakar) ve tavan (asagi bakar)
		_quad(fk, Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, 0, z0),
			Vector2(x0, z0), Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0))
		# Tavan asagi bakar (zeminin ters sirasi)
		_quad("tavan", Vector3(x0, H, z0), Vector3(x1, H, z0), Vector3(x1, H, z1), Vector3(x0, H, z1),
			Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1))
		var open: String = r[7]
		var lower: String = r[6]
		# Dort kenar: [ad, eksen, cizgi, bas, son, ice dogru normal]
		for side in [["n", "z", z0, x0, x1, Vector3(0, 0, 1)], ["s", "z", z1, x0, x1, Vector3(0, 0, -1)],
				["w", "x", x0, z0, z1, Vector3(1, 0, 0)], ["e", "x", x1, z0, z1, Vector3(-1, 0, 0)]]:
			if open.contains(side[0]):
				continue
			_wall(side[1], side[2], side[3], side[4], side[5], lower, r[5] == "parke")


## Bir kenar boyunca duvar: aciklik olmayan kisimlar tam, aciklik olan yerde altta ve ustte parca kalir.
func _wall(axis: String, line: float, s0: float, s1: float, inward: Vector3, lower: String, skirting: bool) -> void:
	var holes: Array = []
	for o in OPENINGS:
		if o[0] == axis and absf(float(o[1]) - line) < 0.01 and o[3] > s0 and o[2] < s1:
			holes.append([maxf(o[2], s0), minf(o[3], s1), float(o[4]), float(o[5]), o[6]])
	holes.sort_custom(func(a, b): return a[0] < b[0])
	var cuts: Array = []          # [bas, son, alt, ust] dolu parcalar
	var at := s0
	for h in holes:
		if h[0] > at:
			cuts.append([at, h[0], 0.0, H])
		if h[2] > 0.0:
			cuts.append([h[0], h[1], 0.0, h[2]])
		cuts.append([h[0], h[1], h[3], H])
		at = h[1]
	if at < s1:
		cuts.append([at, s1, 0.0, H])
	var off := inward * HALF_T
	for c in cuts:
		var a0: float = c[0]
		var a1: float = c[1]
		for band in ([[0.0, 1.15, lower], [1.15, H, "karo_ust"]] if lower != "" else [[0.0, H, "siva"]]):
			var y0 := maxf(float(c[2]), band[0])
			var y1 := minf(float(c[3]), band[1])
			if y1 - y0 < 0.001:
				continue
			_wall_quad(band[2], axis, line, a0, a1, y0, y1, off, inward)
		# Carpisma (kapi acikliklari haric, alt kismi dolu olanlar)
		if c[2] < 0.5:
			var pa := Vector2(line, a0) if axis == "x" else Vector2(a0, line)
			var pb := Vector2(line, a1) if axis == "x" else Vector2(a1, line)
			colliders.append([pa, pb])
	if lower != "":
		# Mint karonun ustunde siyah serit
		for c in cuts:
			if c[2] < 1.1 and c[3] > 1.2:
				var p := Vector3(line, 1.15, (c[0] + c[1]) * 0.5) if axis == "x" else Vector3((c[0] + c[1]) * 0.5, 1.15, line)
				var size := Vector3(0.02, 0.06, c[1] - c[0]) if axis == "x" else Vector3(c[1] - c[0], 0.06, 0.02)
				Kit.box(self, size, p + inward * (HALF_T + 0.01), Kit.mat("151517", 0.3))
	if skirting:
		for c in cuts:
			if c[2] < 0.05:
				var p := Vector3(line, 0.04, (c[0] + c[1]) * 0.5) if axis == "x" else Vector3((c[0] + c[1]) * 0.5, 0.04, line)
				var size := Vector3(0.02, 0.08, c[1] - c[0]) if axis == "x" else Vector3(c[1] - c[0], 0.08, 0.02)
				Kit.box(self, size, p + inward * (HALF_T + 0.01), Kit.mat("6b4128", 0.6))
	for h in holes:
		_opening_trim(axis, line, h, inward)


func _wall_quad(key: String, axis: String, line: float, a0: float, a1: float, y0: float, y1: float, off: Vector3, inward: Vector3) -> void:
	var p := func(s: float, y: float) -> Vector3:
		return (Vector3(line, y, s) if axis == "x" else Vector3(s, y, line)) + off
	var A: Vector3 = p.call(a0, y0)
	var B: Vector3 = p.call(a1, y0)
	var C: Vector3 = p.call(a1, y1)
	var D: Vector3 = p.call(a0, y1)
	# Normal iceri baksin
	if (B - A).cross(C - A).dot(inward) < 0.0:
		_quad(key, B, A, D, C, Vector2(a1, y0), Vector2(a0, y0), Vector2(a0, y1), Vector2(a1, y1))
	else:
		_quad(key, A, B, C, D, Vector2(a0, y0), Vector2(a1, y0), Vector2(a1, y1), Vector2(a0, y1))


## Kapi pervazi, kapi kanadi, pencere cercevesi ve cami. Her aciklik iki odada da gorulur; kanat yalniz bir kez.
func _opening_trim(axis: String, line: float, h: Array, inward: Vector3) -> void:
	var kind: String = h[4]
	var s0: float = h[0]
	var s1: float = h[1]
	var y0: float = h[2]
	var y1: float = h[3]
	var mid := (s0 + s1) * 0.5
	var w := s1 - s0
	var at := func(s: float, y: float, depth := 0.0) -> Vector3:
		return (Vector3(line, y, s) if axis == "x" else Vector3(s, y, line)) + inward * (HALF_T + depth)
	var along := Vector3(0, 0, 1) if axis == "x" else Vector3(1, 0, 0)
	var brown := Kit.mat("6e3a26", 0.55)
	var frame_col := brown if kind != "kemer" else Kit.mat("ece6d8", 0.8)
	# Pervaz (her iki yuzde)
	var thick := Vector3(0.03, 0.0, 0.0) if axis == "x" else Vector3(0.0, 0.0, 0.03)
	var bar := func(size_along: float, size_y: float) -> Vector3:
		return (Vector3(0.03, size_y, size_along) if axis == "x" else Vector3(size_along, size_y, 0.03))
	Kit.box(self, bar.call(0.07, y1 - y0 + 0.07), at.call(s0 - 0.035, (y0 + y1) * 0.5 + 0.035, 0.012), frame_col)
	Kit.box(self, bar.call(0.07, y1 - y0 + 0.07), at.call(s1 + 0.035, (y0 + y1) * 0.5 + 0.035, 0.012), frame_col)
	Kit.box(self, bar.call(w + 0.14, 0.07), at.call(mid, y1 + 0.035, 0.012), frame_col)
	if y0 > 0.0:
		Kit.box(self, bar.call(w + 0.14, 0.05), at.call(mid, y0 - 0.02, 0.03), Kit.mat("e9e4da", 0.5))   # denizlik
	# Iki yuzden birini sec (kanat/cam bir kez)
	var first := inward.x + inward.z > 0.0
	if not first:
		return
	if kind == "pencere" or kind == "balkon":
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.75, 0.85, 0.9, 0.18)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.05
		glass.metallic_specular = 1.0
		glass.cull_mode = BaseMaterial3D.CULL_DISABLED
		var g := Kit.box(self, bar.call(w - 0.04, y1 - y0 - 0.04), at.call(mid, (y0 + y1) * 0.5, -HALF_T), glass)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Kahve PVC kayit ve orta kayit
		Kit.box(self, bar.call(0.06, y1 - y0), at.call(mid, (y0 + y1) * 0.5, -HALF_T), brown)
		if kind == "balkon":
			Kit.box(self, bar.call(w, 0.06), at.call(mid, 1.0, -HALF_T), brown)
	elif kind == "kapi":
		# Acik ic kapi: kahve panel, ustte buzlu cam
		var leaf := Node3D.new()
		var hinge: Vector3 = at.call(s0, 0.0, -HALF_T)
		leaf.position = hinge
		leaf.rotation.y = (PI / 2.0 if axis == "x" else 0.0) - 1.35
		add_child(leaf)
		Kit.box(leaf, Vector3(w - 0.04, 1.45, 0.04), Vector3((w - 0.04) * 0.5, 0.72, 0), brown)
		var frosted := StandardMaterial3D.new()
		frosted.albedo_color = Color(0.88, 0.9, 0.92, 0.7)
		frosted.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		frosted.roughness = 0.6
		Kit.box(leaf, Vector3(w - 0.24, 0.42, 0.03), Vector3((w - 0.04) * 0.5, 1.72, 0), frosted)
		Kit.box(leaf, Vector3(w - 0.04, 0.1, 0.045), Vector3((w - 0.04) * 0.5, 1.47, 0), brown)
		Kit.box(leaf, Vector3(w - 0.04, 0.08, 0.045), Vector3((w - 0.04) * 0.5, 1.98, 0), brown)
		Kit.box(leaf, Vector3(0.14, 0.03, 0.09), Vector3(w - 0.14, 1.0, 0), Kit.mat("c9cdd1", 0.25))   # kol
	elif kind == "giris":
		# Celik daire kapisi (kapali)
		var d := Kit.box(self, bar.call(w - 0.02, y1 - 0.02), at.call(mid, y1 * 0.5, -HALF_T), Kit.mat("5a3a2a", 0.5))
		d.name = "GirisKapisi"
		Kit.box(self, Vector3(0.12, 0.03, 0.08) if axis != "x" else Vector3(0.08, 0.03, 0.12), at.call(s1 - 0.12, 1.0, -HALF_T + 0.05), Kit.mat("c9cdd1", 0.25))


# ---------------------------------------------------------------- esyalar

func _box(size: Vector3, pos: Vector3, m: Material, rot_y := 0.0, solid := false) -> MeshInstance3D:
	var mi := Kit.box(self, size, pos, m, Vector3(0, rot_y, 0))
	if solid:
		_solid(Vector2(pos.x, pos.z), Vector2(size.x, size.z) * 0.5, rot_y)
	return mi


func _solid(c: Vector2, half: Vector2, rot := 0.0) -> void:
	var pts: Array = []
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		pts.append(c + (k * half).rotated(-rot))
	for i in 4:
		colliders.append([pts[i], pts[(i + 1) % 4]])


func _rug(tex: String, c: Vector2, size: Vector2, rot := 0.0, uv := Vector2.ONE) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/home/%s" % tex)
	m.uv1_scale = Vector3(uv.x, uv.y, 1)
	m.roughness = 1.0
	Kit.box(self, Vector3(size.x, 0.015, size.y), Vector3(c.x, 0.008, c.y), m, Vector3(0, rot, 0))


func _lamp(c: Vector2, kind := "kafes") -> void:
	var drop := 0.55 if kind != "plafon" else 0.0
	Kit.cyl(self, 0.006, 0.006, drop + 0.01, Vector3(c.x, H - drop * 0.5, c.y), Kit.mat("111111"), 4)
	var bulb := StandardMaterial3D.new()
	bulb.albedo_color = Color("fff3d6")
	bulb.emission_enabled = true
	bulb.emission = Color("ffe6b0")
	bulb.emission_energy_multiplier = 3.0
	if kind == "plafon":
		Kit.ball(self, 0.22, Vector3(c.x, H - 0.05, c.y), bulb, Vector3(1, 0.3, 1))
	else:
		Kit.ball(self, 0.06, Vector3(c.x, H - drop - 0.05, c.y), bulb)
		if kind == "kafes":
			var wire := Kit.mat("1a1a1a", 0.5)
			for k in 4:
				var a := k * PI / 2.0 + PI / 4.0
				Kit.box(self, Vector3(0.008, 0.32, 0.008), Vector3(c.x + cos(a) * 0.14, H - drop - 0.08, c.y + sin(a) * 0.14), wire, Vector3(0, -a, 0.45))
	var l := OmniLight3D.new()
	l.position = Vector3(c.x, H - drop - 0.25, c.y)
	l.light_color = Color("ffe9c8")
	l.light_energy = 1.4
	l.omni_range = 6.5
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	add_child(l)
	lights.append(l)


func _curtain(x0: float, x1: float, z: float, toward: float) -> void:
	# Kivrimli beyaz tul perde (iki yuzlu)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int((x1 - x0) / 0.06)
	for i in n:
		var xa := x0 + (x1 - x0) * i / n
		var xb := x0 + (x1 - x0) * (i + 1) / n
		var za := z + toward * (0.08 + 0.05 * sin(i * 0.9))
		var zb := z + toward * (0.08 + 0.05 * sin((i + 1) * 0.9))
		for v in [[xa, 0.05, za], [xb, 0.05, zb], [xb, 2.55, zb], [xa, 0.05, za], [xb, 2.55, zb], [xa, 2.55, za]]:
			st.set_normal(Vector3(0, 0, -toward))
			st.add_vertex(Vector3(v[0], v[1], v[2]))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.96, 0.92, 0.93)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	add_child(mi)
	Kit.box(self, Vector3(x1 - x0 + 0.2, 0.03, 0.03), Vector3((x0 + x1) * 0.5, 2.6, z + toward * 0.08), Kit.mat("dcd6ca"))


func _armchair(c: Vector2, rot: float) -> void:
	var r := Kit.pivot(self, Vector3(c.x, 0, c.y))
	r.rotation.y = rot
	var fab := StandardMaterial3D.new()
	fab.albedo_texture = load("res://assets/home/berjer.jpg")
	fab.uv1_scale = Vector3(2, 2, 1)
	fab.roughness = 0.95
	var navy := Kit.mat("1d2142", 0.9)
	var gold := Kit.mat("a8844f", 0.5)
	Kit.box(r, Vector3(0.82, 0.22, 0.78), Vector3(0, 0.14, 0), navy)
	Kit.box(r, Vector3(0.62, 0.16, 0.62), Vector3(0, 0.32, 0.04), fab)
	Kit.box(r, Vector3(0.82, 0.62, 0.18), Vector3(0, 0.55, -0.32), fab, Vector3(-0.12, 0, 0))
	for sx in [-1.0, 1.0]:
		Kit.box(r, Vector3(0.14, 0.46, 0.74), Vector3(sx * 0.36, 0.45, 0.0), fab)
		Kit.cyl(r, 0.075, 0.075, 0.74, Vector3(sx * 0.36, 0.68, 0.0), fab, 10, Vector3(PI / 2, 0, 0))
		Kit.box(r, Vector3(0.02, 0.02, 0.74), Vector3(sx * 0.43, 0.68, 0.0), gold)
	Kit.box(r, Vector3(0.4, 0.3, 0.12), Vector3(0, 0.52, -0.18), Kit.mat("7a7a48", 1.0), Vector3(-0.2, 0, 0))   # yastik
	_solid(c, Vector2(0.42, 0.4), rot)


func _build_furniture() -> void:
	var wood := Kit.mat("7a4a2a", 0.5)
	var light_wood := Kit.mat("c8b18c", 0.6)
	var white := Kit.mat("f2f0ea", 0.4)
	var black := Kit.mat("17181a", 0.5)

	# --- Koridor: gomme dolap, yolluk, giris halisi, petek, ayakkabilik
	for z in [1.2, 1.9, 2.6, 3.3]:
		_box(Vector3(0.55, 2.0, 0.68), Vector3(6.34, 1.0, z + 0.35), white)
		_box(Vector3(0.02, 1.8, 0.56), Vector3(6.62, 1.0, z + 0.35), Kit.mat("e6e3db", 0.4))
		_box(Vector3(0.03, 0.4, 0.03), Vector3(6.64, 1.05, z + 0.62), black)
		_box(Vector3(0.55, 0.6, 0.68), Vector3(6.34, 2.38, z + 0.35), white)
		_box(Vector3(0.03, 0.18, 0.03), Vector3(6.64, 2.25, z + 0.62), black)
	_solid(Vector2(6.34, 2.6), Vector2(0.3, 1.42))
	_rug("yolluk.jpg", Vector2(7.25, 3.0), Vector2(0.75, 3.4))
	_rug("hali_giris.jpg", Vector2(7.2, 6.4), Vector2(1.6, 1.6))
	_radiator(Vector3(8.32, 0, 5.95), PI / 2, 0.8)
	_box(Vector3(0.38, 0.4, 0.9), Vector3(8.14, 0.2, 0.75), black, 0.0, true)      # ayakkabilik
	_lamp(Vector2(7.2, 2.6), "plafon")
	_lamp(Vector2(7.2, 6.0), "plafon")

	# --- WC: klozet, raf, koku cubuklari
	_toilet(Vector3(9.55, 0, 3.4), -PI / 2)
	_box(Vector3(0.12, 0.02, 0.5), Vector3(9.8, 1.55, 3.4), black)
	_box(Vector3(0.06, 0.08, 0.06), Vector3(9.8, 1.6, 3.4), Kit.mat("d8a35a", 0.2))
	_lamp(Vector2(9.15, 3.4), "plafon")

	# --- Banyo: kose dus kabini, ayakli lavabo, camasir sepeti, havlu
	_shower(Vector3(10.8, 0, 6.5))
	_sink(Vector3(9.3, 0, 4.42))
	_box(Vector3(0.45, 0.6, 0.35), Vector3(8.8, 0.3, 6.2), Kit.mat("f7f7f4", 0.6), 0.0, true)
	_box(Vector3(0.04, 0.9, 0.4), Vector3(8.5, 1.15, 5.9), Kit.mat("cfd96a", 1.0))
	_lamp(Vector2(9.6, 5.3), "plafon")

	# --- Mutfak: tezgah, dolaplar, ocak, buzdolabi, masa
	_box(Vector3(0.7, 1.85, 0.66), Vector3(1.8, 0.93, 0.4), Kit.mat("e9e9e6", 0.3), 0.0, true)       # buzdolabi
	_box(Vector3(3.2, 0.86, 0.6), Vector3(3.7, 0.43, 0.36), white, 0.0, true)
	_box(Vector3(3.24, 0.04, 0.64), Vector3(3.7, 0.88, 0.36), Kit.mat("9b7b5a", 0.4))
	_box(Vector3(0.5, 0.02, 0.4), Vector3(3.2, 0.905, 0.36), Kit.mat("c9cdd1", 0.15))               # evye
	_box(Vector3(0.6, 0.02, 0.55), Vector3(4.6, 0.91, 0.36), black)                                  # ocak
	for k in 4:
		Kit.torus(self, 0.05, 0.08, Vector3(4.45 + (k % 2) * 0.3, 0.925, 0.22 + (k / 2) * 0.28), Kit.mat("333333"))
	_box(Vector3(1.9, 0.6, 0.35), Vector3(4.2, 2.0, 0.2), white)                                     # ust dolaplar
	_box(Vector3(0.8, 0.04, 0.6), Vector3(2.9, 0.75, 1.75), light_wood, 0.0, true)
	for dx in [-0.25, 0.25]:
		_box(Vector3(0.4, 0.45, 0.4), Vector3(2.9 + dx * 2.4, 0.45, 1.75), Kit.mat("3a3a3a", 0.6))
	_lamp(Vector2(3.7, 1.3), "plafon")

	# --- Buyuk yatak odasi
	var circle := StandardMaterial3D.new()
	circle.albedo_color = Color("7a5345")
	circle.roughness = 0.9
	Kit.cyl(self, 0.95, 0.95, 0.01, Vector3(3.4, 1.55, 2.47), circle, 40, Vector3(PI / 2, 0, 0))
	_box(Vector3(1.75, 1.15, 0.12), Vector3(3.4, 0.6, 2.52), Kit.mat("d8cdb8", 0.95))                # baslik
	for k in 12:
		Kit.ball(self, 0.012, Vector3(2.75 + (k % 6) * 0.26, 0.85 + (k / 6) * 0.22, 2.59), Kit.mat("bfb39b"))
	_box(Vector3(1.6, 0.42, 2.0), Vector3(3.4, 0.21, 3.58), Kit.mat("cbbd9d", 0.9), 0.0, true)       # baza
	_box(Vector3(1.58, 0.22, 1.96), Vector3(3.4, 0.53, 3.58), Kit.mat("ece4d4", 0.95))               # yatak
	_box(Vector3(1.2, 0.14, 1.1), Vector3(3.55, 0.7, 3.9), Kit.mat("a7c94f", 0.95), 0.25)            # yorgan
	_box(Vector3(0.6, 0.14, 0.4), Vector3(3.0, 0.72, 2.85), Kit.mat("f0e3b3", 1.0), 0.3)              # yastiklar
	_box(Vector3(0.55, 0.16, 0.38), Vector3(3.75, 0.74, 2.8), Kit.mat("eadfc8", 1.0))
	_box(Vector3(0.42, 0.55, 0.38), Vector3(4.55, 0.28, 2.65), white, 0.0, true)                      # komodin
	_box(Vector3(1.25, 0.04, 0.62), Vector3(1.85, 0.76, 3.8), Kit.mat("8a5a35", 0.5), 0.0, true)      # calisma masasi
	for x in [1.3, 2.4]:
		for z in [3.55, 4.05]:
			_box(Vector3(0.04, 0.74, 0.04), Vector3(x + (0.08 if x < 2.0 else -0.08), 0.37, z), wood)
	_box(Vector3(0.36, 0.02, 0.25), Vector3(1.9, 0.79, 3.75), Kit.mat("222428", 0.3))                # tablet
	_office_chair(Vector3(2.55, 0, 3.85))
	_rug("kilim.jpg", Vector2(4.75, 4.8), Vector2(0.85, 3.0))
	_mirror(Vector3(2.1, 0, 7.18))
	_curtain(1.42, 2.0, 2.95, 1.0)
	_curtain(1.42, 2.0, 6.15, 1.0)
	_lamp(Vector2(3.6, 4.8), "ampul")

	# --- Kucuk oda: tek kisilik yatak, koyu sehpa, monitor
	_box(Vector3(2.0, 0.48, 1.0), Vector3(10.85, 0.24, 9.6), Kit.mat("b9b9b9", 0.9), 0.0, true)
	_box(Vector3(1.96, 0.16, 0.96), Vector3(10.85, 0.56, 9.6), Kit.mat("f1ebc7", 0.95))
	_box(Vector3(0.1, 0.95, 1.05), Vector3(9.8, 0.48, 9.6), Kit.mat("a9a9a9", 0.9))
	_box(Vector3(0.8, 0.14, 0.7), Vector3(11.1, 0.7, 9.55), Kit.mat("a8682f", 0.95), 0.4)
	_box(Vector3(0.6, 0.72, 0.5), Vector3(9.3, 0.36, 9.85), Kit.mat("2a2421", 0.6), 0.0, true)
	_box(Vector3(0.55, 0.36, 0.04), Vector3(9.3, 0.95, 9.95), black)
	_rug("hali_giris.jpg", Vector2(10.0, 8.0), Vector2(1.4, 1.0))
	_lamp(Vector2(10.2, 8.4), "ampul")

	# --- Salon
	_curtain(0.6, 5.2, 11.6, -1.0)
	_rug("hali_salon.jpg", Vector2(4.7, 9.6), Vector2(3.8, 2.7))
	_armchair(Vector2(2.5, 10.65), PI + 0.5)
	_armchair(Vector2(3.65, 10.85), PI + 0.15)
	# Kose koltuk: mor govde, gri ortu, mor yastiklar
	var purple := Kit.mat("5a2b5a", 0.9)
	var cover := Kit.mat("bdbab4", 1.0)
	_box(Vector3(0.9, 0.42, 3.1), Vector3(7.95, 0.21, 9.95), purple, 0.0, true)
	_box(Vector3(0.88, 0.14, 3.05), Vector3(7.95, 0.49, 9.95), cover)
	_box(Vector3(0.22, 0.48, 3.1), Vector3(8.3, 0.66, 9.95), purple)
	_box(Vector3(1.2, 0.42, 0.9), Vector3(7.1, 0.21, 11.15), purple, 0.0, true)
	_box(Vector3(1.2, 0.14, 0.88), Vector3(7.1, 0.49, 11.15), cover)
	_box(Vector3(1.2, 0.48, 0.22), Vector3(7.1, 0.66, 11.5), purple)
	_box(Vector3(0.9, 0.55, 0.22), Vector3(7.95, 0.55, 8.45), purple)                                # kol
	for z in [8.9, 9.6, 10.6]:
		_box(Vector3(0.14, 0.38, 0.42), Vector3(8.12, 0.72, z), Kit.mat("6b2f69", 1.0), 0.0)
	_box(Vector3(0.14, 0.34, 0.46), Vector3(8.1, 0.7, 9.25), Kit.mat("e8e3d5", 1.0))                  # zikzak yastik
	_box(Vector3(1.25, 0.04, 0.68), Vector3(6.45, 0.48, 9.7), Kit.mat("8a5a35", 0.5), 0.0, true)     # sehpa
	for dx in [-0.55, 0.55]:
		for dz in [-0.28, 0.28]:
			_box(Vector3(0.05, 0.46, 0.05), Vector3(6.45 + dx, 0.23, 9.7 + dz), wood)
	_box(Vector3(0.38, 0.02, 0.26), Vector3(6.3, 0.51, 9.6), Kit.mat("1d1e22", 0.3), 0.3)            # laptop
	_box(Vector3(0.36, 0.22, 0.01), Vector3(6.3, 0.62, 9.47), Kit.glow("36c2a8", 0.4), 0.3)
	_box(Vector3(1.0, 0.62, 0.46), Vector3(5.75, 0.31, 11.3), wood, 0.0, true)                       # TV unitesi
	_box(Vector3(1.08, 0.64, 0.05), Vector3(5.75, 0.97, 11.3), black)
	_box(Vector3(1.0, 0.56, 0.01), Vector3(5.75, 0.97, 11.27), Kit.glow("5f86a8", 0.35))
	_guitar(Vector3(6.55, 0, 11.45))
	var poster := StandardMaterial3D.new()
	poster.albedo_texture = load("res://assets/home/tablo.jpg")
	_box(Vector3(0.02, 0.62, 1.6), Vector3(8.33, 1.6, 9.6), poster)
	_box(Vector3(0.7, 0.04, 0.45), Vector3(0.35, 0.8, 8.4), light_wood, 0.0, true)                    # konsol
	_box(Vector3(0.12, 0.25, 0.12), Vector3(0.3, 0.95, 8.15), white)                                 # kagit havlu
	_drying_rack(Vector3(1.6, 0, 8.4))
	_lamp(Vector2(4.5, 9.5), "kafes")

	# --- Balkon: korkuluk, mavi kanepe, sandik, supurge
	var rail := Kit.mat("6a4231", 0.5)
	_box(Vector3(0.05, 0.05, 5.0), Vector3(0.05, 1.02, 4.9), rail)
	_box(Vector3(0.04, 0.04, 5.0), Vector3(0.05, 0.12, 4.9), rail)
	for k in 42:
		_box(Vector3(0.02, 0.9, 0.02), Vector3(0.05, 0.57, 2.5 + k * 0.12), rail)
	colliders.append([Vector2(0.05, 2.4), Vector2(0.05, 7.4)])
	_box(Vector3(0.62, 0.42, 1.7), Vector3(1.05, 0.21, 3.8), Kit.mat("2f3e78", 0.9), 0.0, true)
	_box(Vector3(0.2, 0.42, 1.7), Vector3(1.28, 0.6, 3.8), Kit.mat("2f3e78", 0.9))
	_box(Vector3(0.48, 0.42, 0.42), Vector3(0.5, 0.21, 5.5), Kit.mat("a77a4a", 0.8), 0.2, true)
	Kit.cyl(self, 0.05, 0.05, 0.1, Vector3(0.5, 0.47, 5.5), Kit.mat("58a24c", 0.6))
	_box(Vector3(0.03, 1.3, 0.03), Vector3(1.25, 0.65, 7.0), Kit.mat("b18a55"), 0.0)
	_lamp(Vector2(0.7, 4.9), "ampul")


func _radiator(at: Vector3, rot: float, width: float) -> void:
	var r := Kit.pivot(self, at)
	r.rotation.y = rot
	for k in int(width / 0.06):
		Kit.box(r, Vector3(0.045, 0.55, 0.08), Vector3(-width * 0.5 + k * 0.06, 0.45, 0), Kit.mat("f1efe6", 0.35))


func _toilet(at: Vector3, rot: float) -> void:
	var r := Kit.pivot(self, at)
	r.rotation.y = rot
	var por := Kit.mat("f7f7f5", 0.15)
	Kit.cyl(r, 0.16, 0.13, 0.38, Vector3(0, 0.19, 0.08), por, 18)
	Kit.ball(r, 0.2, Vector3(0, 0.38, 0.15), por, Vector3(0.9, 0.18, 1.2), 18)
	Kit.box(r, Vector3(0.36, 0.06, 0.08), Vector3(0, 0.75, -0.18), por, Vector3(-1.3, 0, 0))           # kapak acik
	Kit.box(r, Vector3(0.38, 0.32, 0.16), Vector3(0, 0.6, -0.22), por)                                 # rezervuar
	_solid(Vector2(at.x, at.z), Vector2(0.3, 0.25), rot)


func _sink(at: Vector3) -> void:
	var por := Kit.mat("f7f7f5", 0.15)
	Kit.cyl(self, 0.1, 0.14, 0.75, at + Vector3(0, 0.37, 0.1), por, 16)
	Kit.ball(self, 0.28, at + Vector3(0, 0.82, 0.18), por, Vector3(1.0, 0.25, 0.8), 18)
	Kit.cyl(self, 0.015, 0.015, 0.18, at + Vector3(0, 0.95, 0.02), Kit.mat("c9cdd1", 0.15), 8)
	_solid(Vector2(at.x, at.z + 0.18), Vector2(0.28, 0.22))


func _shower(corner: Vector3) -> void:
	# Ceyrek daire dus teknesi ve kavisli cam
	var r := 0.95
	var tray := Kit.mat("f4f4f1", 0.2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.85, 0.92, 0.95, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.05
	var seg := 10
	for k in seg:
		var a0 := PI + PI / 2.0 * k / seg
		var a1 := PI + PI / 2.0 * (k + 1) / seg
		var p0 := Vector2(corner.x + cos(a0) * r, corner.z + sin(a0) * r)
		var p1 := Vector2(corner.x + cos(a1) * r, corner.z + sin(a1) * r)
		var m := (p0 + p1) * 0.5
		var L := p0.distance_to(p1)
		var ang := atan2(p1.y - p0.y, p1.x - p0.x)
		Kit.box(self, Vector3(L + 0.01, 0.18, 0.06), Vector3(m.x, 0.09, m.y), tray, Vector3(0, -ang, 0))
		var g := Kit.box(self, Vector3(L + 0.01, 1.85, 0.01), Vector3(m.x, 1.12, m.y), glass, Vector3(0, -ang, 0))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		colliders.append([p0, p1])
	Kit.box(self, Vector3(r * 0.7, 0.16, r * 0.7), corner + Vector3(-r * 0.36, 0.08, -r * 0.36), tray)
	Kit.cyl(self, 0.012, 0.012, 1.1, corner + Vector3(-0.08, 1.4, -0.5), Kit.mat("c9cdd1", 0.15), 6)


func _office_chair(at: Vector3) -> void:
	var m := Kit.mat("1d1e22", 0.7)
	Kit.box(self, Vector3(0.46, 0.08, 0.46), at + Vector3(0, 0.48, 0), m)
	Kit.box(self, Vector3(0.42, 0.5, 0.06), at + Vector3(0.22, 0.8, 0), m, Vector3(0, PI / 2, 0))
	Kit.cyl(self, 0.03, 0.03, 0.4, at + Vector3(0, 0.25, 0), Kit.mat("8a8a8a", 0.3), 8)
	for k in 5:
		var a := k * TAU / 5.0
		Kit.box(self, Vector3(0.3, 0.03, 0.04), at + Vector3(cos(a) * 0.15, 0.06, sin(a) * 0.15), m, Vector3(0, -a, 0))
	_solid(Vector2(at.x, at.z), Vector2(0.25, 0.25))


func _mirror(at: Vector3) -> void:
	var frame := Kit.mat("d8c39b", 0.6)
	var r := Kit.pivot(self, at)
	r.rotation.x = 0.12
	Kit.box(r, Vector3(0.5, 1.6, 0.04), Vector3(0, 0.8, 0), frame)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.84, 0.86)
	glass.metallic = 1.0
	glass.roughness = 0.04
	Kit.box(r, Vector3(0.42, 1.45, 0.01), Vector3(0, 0.82, -0.025), glass)


func _guitar(at: Vector3) -> void:
	var r := Kit.pivot(self, at)
	r.rotation.x = -0.2
	var body := Kit.mat("b8823f", 0.35)
	Kit.ball(r, 0.2, Vector3(0, 0.25, 0), body, Vector3(1, 1.1, 0.25), 16)
	Kit.ball(r, 0.15, Vector3(0, 0.55, 0), body, Vector3(1, 1, 0.25), 16)
	Kit.cyl(r, 0.045, 0.045, 0.01, Vector3(0, 0.48, -0.05), Kit.mat("221a12"), 12, Vector3(PI / 2, 0, 0))
	Kit.box(r, Vector3(0.05, 0.55, 0.03), Vector3(0, 0.95, 0), Kit.mat("3a2414", 0.5))
	Kit.box(r, Vector3(0.08, 0.16, 0.03), Vector3(0, 1.28, 0), Kit.mat("3a2414", 0.5))


func _drying_rack(at: Vector3) -> void:
	var metal := Kit.mat("b9bcbf", 0.3)
	for dx in [-0.45, 0.45]:
		Kit.box(self, Vector3(0.02, 1.0, 0.02), at + Vector3(dx, 0.5, 0.25), metal, Vector3(0.35, 0, 0))
		Kit.box(self, Vector3(0.02, 1.0, 0.02), at + Vector3(dx, 0.5, -0.25), metal, Vector3(-0.35, 0, 0))
	for k in 7:
		Kit.box(self, Vector3(0.9, 0.01, 0.01), at + Vector3(0, 0.95, -0.3 + k * 0.1), metal)
	Kit.box(self, Vector3(0.55, 0.5, 0.02), at + Vector3(0.1, 0.72, 0.0), Kit.mat("f2f2ee", 1.0))
	Kit.box(self, Vector3(0.4, 0.7, 0.02), at + Vector3(-0.2, 0.62, 0.1), Kit.mat("9fb3bf", 1.0))
	_solid(Vector2(at.x, at.z), Vector2(0.48, 0.3))


# ---------------------------------------------------------------- carpisma (dunya 2B)

func resolve(np: Vector2, r: float, old: Vector2) -> Vector2:
	var p := local2(np)
	var o := local2(old)
	for pass_i in 3:
		for s in colliders:
			var a: Vector2 = s[0]
			var b: Vector2 = s[1]
			var q := Geometry2D.get_closest_point_to_segment(p, a, b)
			var d := p.distance_to(q)
			if d < r:
				var n := (p - q).normalized() if d > 0.0001 else (o - q).normalized()
				p = q + n * r
	# Duvari asmak yok
	for s in colliders:
		if Geometry2D.segment_intersects_segment(o, p, s[0], s[1]) != null:
			p = o
			break
	return w2(p)


func is_free(p: Vector2, r := 0.4) -> bool:
	return has_point(p) and resolve(p, r, p).distance_to(p) < 0.05


## Kamera tavanin ustundeyse tavani gizle (yukaridan bakinca odalar gorunsun).
func update_view(cam_pos: Vector3) -> void:
	if ceiling:
		ceiling.visible = cam_pos.y < global_position.y + H - 0.05
