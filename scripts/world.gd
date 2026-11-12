extends Node3D
## Papatya Parki'ni kodla kurar: arazi, su, bitkiler, yapilar.
## Harita verisi park_map.gd icinde; burasi onu 3D sahneye cevirir.

const ParkMap = preload("res://scripts/park_map.gd")
const Kit = preload("res://scripts/kit.gd")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")
const WATER_SHADER = preload("res://shaders/water.gdshader")
const FOLIAGE_SHADER = preload("res://shaders/foliage.gdshader")

const FLOWER_COLORS := ["ffffff", "ffd84d", "b48be8", "ff9ec4", "ff6b5e", "ffb347"]

var circles: Array[Vector3] = []   # engel daireleri (x, z, yaricap)
var segments: Array = []           # engel dogrulari [Vector2, Vector2]

var _rng := RandomNumberGenerator.new()
var _splat: Texture2D
var _flower_xf: Array[Transform3D] = []
var _flower_col: Array[Color] = []
var _bush_xf: Array[Transform3D] = []
var _bush_col: Array[Color] = []
var _ducks: Array = []
var _clouds: Array[Node3D] = []
var _t := 0.0


func _ready() -> void:
	_rng.seed = 20261112
	_splat = load("res://assets/park_splat.png")
	_build_ground()
	_build_water()
	_build_house()
	_build_plaza()
	_build_bridge()
	_build_play_area()
	_build_kiosk()
	_build_garden()
	_build_picnic()
	_build_lookouts()
	_build_lamps()
	_build_trees()
	_build_pond_life()
	_scatter_plants()
	_build_clouds()


func gy(p: Vector2) -> float:
	return ParkMap.terrain_height(p)


func at(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, gy(p) + y, p.y)


func _root(p: Vector2, rot_y := 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = at(p)
	n.rotation.y = rot_y
	add_child(n)
	return n


## Hareketi engellere ve suya gore duzeltir.
func resolve(np: Vector2, r: float, old: Vector2) -> Vector2:
	if np.length() > ParkMap.PLAY_RADIUS:
		np = np.normalized() * ParkMap.PLAY_RADIUS
	for c in circles:
		var cp := Vector2(c.x, c.y)
		var d := np.distance_to(cp)
		if d < c.z + r and d > 0.001:
			np = cp + (np - cp) / d * (c.z + r)
	for s in segments:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ab := b - a
		var q := a + ab * clampf((np - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := np.distance_to(q)
		if d < r + 0.08 and d > 0.001:
			np = q + (np - q) / d * (r + 0.08)
	if ParkMap.water_blocked(np):
		if not ParkMap.water_blocked(Vector2(np.x, old.y)):
			return Vector2(np.x, old.y)
		if not ParkMap.water_blocked(Vector2(old.x, np.y)):
			return Vector2(old.x, np.y)
		return old
	return np


# ---------------------------------------------------------------- arazi

func _build_ground() -> void:
	# Ortada sik, kenarlarda seyrek izgara
	var n := 150
	var coords := PackedFloat32Array()
	coords.resize(n + 1)
	for i in n + 1:
		var u := float(i) / n * 2.0 - 1.0
		var a := absf(u)
		var c := a / 0.8 * 52.0 if a < 0.8 else 52.0 + (a - 0.8) / 0.2 * 58.0
		coords[i] = signf(u) * c
	var verts := PackedVector3Array()
	verts.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var p := Vector2(coords[i], coords[j])
			verts[j * (n + 1) + i] = Vector3(p.x, ParkMap.terrain_height(p), p.y)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var idx := PackedInt32Array()
	for j in n + 1:
		for i in n + 1:
			var dx := verts[j * (n + 1) + mini(i + 1, n)] - verts[j * (n + 1) + maxi(i - 1, 0)]
			var dz := verts[mini(j + 1, n) * (n + 1) + i] - verts[maxi(j - 1, 0) * (n + 1) + i]
			normals[j * (n + 1) + i] = dz.cross(dx).normalized()
			if i < n and j < n:
				var a := j * (n + 1) + i
				idx.append_array([a, a + 1, a + n + 2, a, a + n + 2, a + n + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("splat", _splat)
	m.set_shader_parameter("splat_extent", ParkMap.SPLAT_EXTENT)
	Kit.add(self, mesh, m)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(55, 76)
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("splat", _splat)
	m.set_shader_parameter("splat_extent", ParkMap.SPLAT_EXTENT)
	var w := Kit.add(self, plane, m, Vector3(-42.5, ParkMap.WATER_Y, 21))
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- yapilar

func _fence(a: Vector2, b: Vector2, hex: String, h := 0.9) -> void:
	segments.append([a, b])
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var m := Kit.mat(hex)
	var count := int(ceil(length / 1.6))
	for i in count + 1:
		var p := a + dir * (length * i / count)
		Kit.box(self, Vector3(0.14, h, 0.14), at(p, h * 0.5), m)
		Kit.box(self, Vector3(0.2, 0.06, 0.2), at(p, h + 0.03), m)
	var mid := (a + b) * 0.5
	var rot := Vector3(0, atan2(-dir.y, dir.x), 0)
	for k in [0.38, 0.78]:
		Kit.box(self, Vector3(length, 0.09, 0.06), at(mid, h * k), m, rot)


func _rect_fence(mn: Vector2, mx: Vector2, hex: String) -> void:
	_fence(Vector2(mn.x, mn.y), Vector2(mx.x, mn.y), hex)
	_fence(Vector2(mx.x, mn.y), Vector2(mx.x, mx.y), hex)


func _bench(p: Vector2, rot_y: float) -> void:
	var r := _root(p, rot_y)
	var wood := Kit.mat("b9824f")
	var dark := Kit.mat("5b5f66", 0.6)
	Kit.box(r, Vector3(1.7, 0.08, 0.5), Vector3(0, 0.46, 0), wood)
	Kit.box(r, Vector3(1.7, 0.42, 0.07), Vector3(0, 0.82, 0.25), wood, Vector3(-0.15, 0, 0))
	for sx in [-0.72, 0.72]:
		Kit.box(r, Vector3(0.08, 0.46, 0.46), Vector3(sx, 0.23, 0), dark)
		Kit.box(r, Vector3(0.08, 0.5, 0.07), Vector3(sx, 0.7, 0.24), dark, Vector3(-0.15, 0, 0))
	circles.append(Vector3(p.x, p.y, 0.75))


func _lamp(p: Vector2) -> void:
	var r := _root(p)
	var dark := Kit.mat("3f4750", 0.5)
	Kit.cyl(r, 0.05, 0.08, 2.7, Vector3(0, 1.35, 0), dark, 8)
	Kit.cyl(r, 0.14, 0.2, 0.12, Vector3(0, 0.06, 0), dark, 8)
	Kit.cyl(r, 0.24, 0.1, 0.1, Vector3(0, 2.98, 0), dark, 10)
	Kit.ball(r, 0.17, Vector3(0, 2.8, 0), Kit.glow("fff1c2", 1.2), Vector3.ONE, 10)
	circles.append(Vector3(p.x, p.y, 0.15))


func _build_house() -> void:
	var h := ParkMap.HOUSE
	var r := _root(h)
	var white := Kit.mat("ffffff")
	var wood := Kit.mat("8c5a3c")
	Kit.box(r, Vector3(8.2, 0.4, 6.2), Vector3(0, 0.2, 0), Kit.mat("b9a48c"))
	Kit.box(r, Vector3(8, 3.2, 6), Vector3(0, 1.8, 0), Kit.mat("f9eed8"))
	Kit.prism(r, Vector3(7.0, 2.2, 8.8), Vector3(0, 4.5, 0), Kit.mat("c9553a"), Vector3(0, PI / 2, 0))
	Kit.box(r, Vector3(0.75, 1.7, 0.75), Vector3(2.5, 5.0, -1.0), Kit.mat("b5654a"))
	Kit.box(r, Vector3(0.95, 0.15, 0.95), Vector3(2.5, 5.9, -1.0), Kit.mat("8f8f8f"))
	# Kapi
	Kit.box(r, Vector3(1.45, 2.3, 0.1), Vector3(0, 1.5, 3.0), white)
	Kit.box(r, Vector3(1.15, 2.05, 0.14), Vector3(0, 1.42, 3.0), wood)
	Kit.ball(r, 0.07, Vector3(0.4, 1.4, 3.1), Kit.mat("f2c14e", 0.3))
	Kit.box(r, Vector3(2.0, 0.2, 0.9), Vector3(0, 0.3, 3.4), Kit.mat("b9a48c"))
	Kit.prism(r, Vector3(2.2, 0.6, 1.0), Vector3(0, 3.0, 3.3), Kit.mat("d9694a"))
	# Pencereler ve cicek kasalari
	for sx in [-2.5, 2.5]:
		Kit.box(r, Vector3(1.5, 1.4, 0.1), Vector3(sx, 2.1, 3.0), white)
		Kit.box(r, Vector3(1.2, 1.1, 0.14), Vector3(sx, 2.1, 3.0), Kit.mat("9fd3e8", 0.2))
		Kit.box(r, Vector3(0.07, 1.1, 0.16), Vector3(sx, 2.1, 3.0), white)
		Kit.box(r, Vector3(1.2, 0.07, 0.16), Vector3(sx, 2.1, 3.0), white)
		Kit.box(r, Vector3(1.5, 0.22, 0.34), Vector3(sx, 1.28, 3.2), wood)
		for i in 7:
			_flower(Vector3(h.x + sx - 0.6 + i * 0.2, gy(h) + 1.3, h.y + 3.2), Color(FLOWER_COLORS[3 + i % 2]), 0.8)
		_bush(h + Vector2(sx * 1.5, 3.7), 0.8)
	for c in [Vector2(-4.1, -3.1), Vector2(4.1, 3.1)]:
		segments.append([h + c, h + Vector2(-c.x, c.y)])
		segments.append([h + c, h + Vector2(c.x, -c.y)])

	# Bahce citi (guneyde kapi boslugu)
	var mn := ParkMap.YARD_MIN
	var mx := ParkMap.YARD_MAX
	var hex := "fbf7ef"
	_fence(mn, Vector2(mx.x, mn.y), hex)
	_fence(mn, Vector2(mn.x, mx.y), hex)
	_fence(Vector2(mx.x, mn.y), mx, hex)
	_fence(Vector2(mn.x, mx.y), Vector2(-1.5, mx.y), hex)
	_fence(Vector2(1.5, mx.y), mx, hex)

	# Kopek kulubesi, mama kabi, posta kutusu
	var d := _root(Vector2(5.8, -30.6), -0.25)
	Kit.box(d, Vector3(1.3, 1.0, 1.5), Vector3(0, 0.5, 0), Kit.mat("f0d49a"))
	Kit.prism(d, Vector3(1.8, 0.75, 1.9), Vector3(0, 1.37, 0), Kit.mat("d94f4f"))
	Kit.box(d, Vector3(0.55, 0.62, 0.06), Vector3(0, 0.31, 0.74), Kit.mat("3a2a22"))
	Kit.cyl(d, 0.275, 0.275, 0.06, Vector3(0, 0.62, 0.74), Kit.mat("3a2a22"), 14, Vector3(PI / 2, 0, 0))
	Kit.cyl(d, 0.2, 0.26, 0.12, Vector3(-1.1, 0.06, 0.9), Kit.mat("4f8fd9", 0.4))
	circles.append(Vector3(5.8, -30.6, 1.05))
	var mb := _root(Vector2(2.2, -26.2))
	Kit.box(mb, Vector3(0.1, 1.0, 0.1), Vector3(0, 0.5, 0), wood)
	Kit.box(mb, Vector3(0.3, 0.26, 0.5), Vector3(0, 1.1, 0), Kit.mat("e2574c", 0.5))
	circles.append(Vector3(2.2, -26.2, 0.2))
	for i in 9:
		_bush(Vector2(-8.2 + i * 0.25, -41.8 + i * 1.5), _rng.randf_range(0.7, 1.0))
		_bush(Vector2(8.2 - i * 0.2, -41.8 + i * 1.5), _rng.randf_range(0.7, 1.0))
	for i in 40:
		_flower(at(Vector2(_rng.randf_range(-7.5, -1.6), _rng.randf_range(-32.4, -28.2))), Color(FLOWER_COLORS[_rng.randi() % 6]))


func _build_plaza() -> void:
	var r := _root(ParkMap.PLAZA)
	var stone := Kit.mat("d8d2c4")
	var water := Kit.mat("6fcfe0", 0.15)
	Kit.cyl(r, 2.3, 2.45, 0.55, Vector3(0, 0.27, 0), stone, 24)
	Kit.cyl(r, 2.0, 2.0, 0.06, Vector3(0, 0.55, 0), water, 24)
	Kit.cyl(r, 0.28, 0.4, 1.5, Vector3(0, 0.9, 0), stone, 12)
	Kit.cyl(r, 0.95, 0.35, 0.3, Vector3(0, 1.6, 0), stone, 18)
	Kit.cyl(r, 0.82, 0.82, 0.04, Vector3(0, 1.75, 0), water, 18)
	Kit.cyl(r, 0.1, 0.16, 0.5, Vector3(0, 2.0, 0), stone, 10)
	Kit.ball(r, 0.2, Vector3(0, 2.35, 0), Kit.mat("ffffff", 0.2))
	for i in 8:
		var a := i * TAU / 8.0
		Kit.cyl(r, 0.03, 0.05, 0.8, Vector3(cos(a) * 0.5, 1.5, sin(a) * 0.5), Kit.mat("d5f4fa", 0.1), 5,
				Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5))
	circles.append(Vector3(0, 0, 2.5))
	# Kaldirim halkasi
	for i in 28:
		var a := i * TAU / 28.0
		Kit.box(self, Vector3(1.2, 0.05, 0.5), Vector3(cos(a) * 6.9, 0.02, sin(a) * 6.9), Kit.mat("c9bfae"), Vector3(0, -a + PI / 2, 0))
	for deg in [135.0, 22.0, -158.0, 112.0]:
		var a := deg_to_rad(deg)
		var p := Vector2(cos(a), sin(a)) * 5.5
		_bench(p, atan2(p.x, p.y))
	for deg in [68.0, -112.0, -22.0, 158.0]:
		var a := deg_to_rad(deg)
		var p := Vector2(cos(a), sin(a)) * 6.1
		Kit.cyl(self, 0.75, 0.62, 0.55, at(p, 0.27), stone, 14)
		circles.append(Vector3(p.x, p.y, 0.8))
		_bush(p, 0.75, 0.45)
		for i in 9:
			var fa := i * TAU / 9.0
			_flower(at(p + Vector2(cos(fa), sin(fa)) * 0.55, 0.5), Color(FLOWER_COLORS[(i % 2) * 3 + 1]))


func _build_bridge() -> void:
	var b := ParkMap.BRIDGE
	var wood := Kit.mat("b9824f")
	var dark := Kit.mat("8c5a3c")
	var half := ParkMap.BRIDGE_LEN * 0.5
	var n := 12
	for i in n:
		var x := b.x - half + (i + 0.5) * ParkMap.BRIDGE_LEN / n
		var p := Vector2(x, b.y)
		var slope := (ParkMap.bridge_y(Vector2(x + 0.1, b.y)) - ParkMap.bridge_y(Vector2(x - 0.1, b.y))) / 0.2
		Kit.box(self, Vector3(ParkMap.BRIDGE_LEN / n * 0.94, 0.1, ParkMap.BRIDGE_W), Vector3(x, ParkMap.bridge_y(p) - 0.05, b.y),
				wood if i % 2 == 0 else dark, Vector3(0, 0, atan(slope)))
	for sz in [-1.0, 1.0]:
		var z: float = b.y + sz * (ParkMap.BRIDGE_W * 0.5 - 0.06)
		var prev := Vector3.ZERO
		for i in 5:
			var x := b.x - half + i * ParkMap.BRIDGE_LEN / 4.0
			var top := Vector3(x, ParkMap.bridge_y(Vector2(x, b.y)) + 0.85, z)
			Kit.box(self, Vector3(0.14, 1.3, 0.14), top - Vector3(0, 0.6, 0), dark)
			Kit.ball(self, 0.11, top + Vector3(0, 0.08, 0), dark, Vector3.ONE, 8)
			if i > 0:
				var d := top - prev
				Kit.box(self, Vector3(d.length(), 0.1, 0.08), (top + prev) * 0.5 - Vector3(0, 0.12, 0), wood, Vector3(0, 0, atan2(d.y, d.x)))
			prev = top


func _build_play_area() -> void:
	var mn := ParkMap.PLAY_MIN
	var mx := ParkMap.PLAY_MAX
	var hex := "c9a06a"
	_fence(mn, Vector2(mx.x, mn.y), hex)
	_fence(Vector2(mx.x, mn.y), mx, hex)
	_fence(mx, Vector2(mn.x, mx.y), hex)
	_fence(mn, Vector2(mn.x, 4.6), hex)
	_fence(Vector2(mn.x, 7.4), Vector2(mn.x, mx.y), hex)
	# Giris takisi
	for z in [4.6, 7.4]:
		Kit.box(self, Vector3(0.2, 2.6, 0.2), Vector3(mn.x, 1.3, z), Kit.mat("e2574c"))
	Kit.box(self, Vector3(0.24, 0.5, 3.4), Vector3(mn.x, 2.7, 6.0), Kit.mat("ffd15c"))
	Kit.ball(self, 0.28, Vector3(mn.x - 0.1, 2.7, 6.0), Kit.mat("ffffff"), Vector3(0.5, 1, 1))
	# Atlama cemberleri
	var cols := ["e2574c", "ffd15c", "4f8fd9"]
	for i in 3:
		var p := Vector2(28.5 + i * 2.6, 4.3)
		var r := _root(p)
		Kit.box(r, Vector3(0.1, 0.6, 0.1), Vector3(0, 0.3, 0), Kit.mat("ffffff"))
		Kit.torus(r, 0.5, 0.62, Vector3(0, 1.15 + i * 0.12, 0), Kit.mat(cols[i], 0.5), Vector3(0, 0, PI / 2))
		circles.append(Vector3(p.x, p.y, 0.12))
	# Rampa
	var ramp := _root(Vector2(35.5, 8.5), 0.4)
	Kit.box(ramp, Vector3(1.2, 0.1, 2.3), Vector3(0, 0.55, -0.98), Kit.mat("ffd15c"), Vector3(0.52, 0, 0))
	Kit.box(ramp, Vector3(1.2, 0.1, 2.3), Vector3(0, 0.55, 0.98), Kit.mat("4f8fd9"), Vector3(-0.52, 0, 0))
	circles.append(Vector3(35.5, 8.5, 1.2))
	# Tunel
	var tube := StandardMaterial3D.new()
	tube.albedo_color = Color("5fbf8f")
	tube.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tm := CylinderMesh.new()
	tm.top_radius = 0.6
	tm.bottom_radius = 0.6
	tm.height = 2.6
	tm.cap_top = false
	tm.cap_bottom = false
	Kit.add(self, tm, tube, Vector3(30.5, 0.58, 11.3), Vector3(0, 0.3, PI / 2))
	circles.append(Vector3(30.5, 11.3, 1.0))
	# Slalom cubuklari, toplar, su kabi
	for i in 6:
		var p := Vector2(34.0 + i * 0.9, 12.3)
		Kit.cyl(self, 0.05, 0.05, 1.1, Vector3(p.x, 0.55, p.y), Kit.mat(cols[i % 3], 0.5), 8)
		circles.append(Vector3(p.x, p.y, 0.08))
	Kit.ball(self, 0.22, Vector3(27.2, 0.22, 8.8), Kit.mat("e2574c", 0.5))
	Kit.ball(self, 0.16, Vector3(32.4, 0.16, 7.4), Kit.mat("ffd15c", 0.5))
	Kit.ball(self, 0.19, Vector3(37.6, 0.19, 4.6), Kit.mat("4f8fd9", 0.5))
	Kit.cyl(self, 0.3, 0.38, 0.16, Vector3(26.0, 0.08, 12.6), Kit.mat("4f8fd9", 0.4))
	_bench(Vector2(38.4, 11.0), -PI / 2)


func _build_kiosk() -> void:
	var k := ParkMap.KIOSK
	var r := _root(k)
	Kit.box(r, Vector3(3.2, 2.5, 2.4), Vector3(0, 1.25, 0), Kit.mat("fff3e0"))
	Kit.box(r, Vector3(3.7, 0.22, 2.9), Vector3(0, 2.6, 0), Kit.mat("e2574c"))
	Kit.box(r, Vector3(2.5, 1.0, 0.06), Vector3(0, 1.75, 1.2), Kit.mat("5a4636"))
	Kit.box(r, Vector3(2.9, 0.12, 0.6), Vector3(0, 1.15, 1.4), Kit.mat("b9824f"))
	Kit.box(r, Vector3(3.5, 0.06, 1.3), Vector3(0, 2.3, 1.75), Kit.checker(Color("e2574c"), Color("ffffff"), 8, 1), Vector3(0.35, 0, 0))
	# Tepedeki dev dondurma
	Kit.cyl(r, 0.42, 0.02, 0.95, Vector3(0, 3.2, 0), Kit.mat("e8b574"), 12)
	Kit.ball(r, 0.47, Vector3(0, 3.85, 0), Kit.mat("ff9ec4", 0.6))
	Kit.ball(r, 0.36, Vector3(0, 4.4, 0), Kit.mat("fff6d6", 0.6))
	Kit.ball(r, 0.1, Vector3(0, 4.8, 0), Kit.mat("e2574c", 0.3))
	circles.append(Vector3(k.x, k.y, 2.3))
	# Semsiyeli masalar
	var canopy := ["ffd15c", "6fcfe0"]
	for i in 2:
		var p: Vector2 = k + [Vector2(-3.6, 2.2), Vector2(3.4, 2.8)][i]
		var t := _root(p)
		Kit.cyl(t, 0.65, 0.65, 0.06, Vector3(0, 0.75, 0), Kit.mat("ffffff"), 16)
		Kit.cyl(t, 0.04, 0.04, 2.3, Vector3(0, 1.15, 0), Kit.mat("8f8f8f"), 6)
		Kit.cyl(t, 0.02, 1.35, 0.5, Vector3(0, 2.4, 0), Kit.mat(canopy[i]), 10)
		for j in 3:
			var a := j * TAU / 3.0 + i
			Kit.cyl(t, 0.22, 0.2, 0.45, Vector3(cos(a) * 1.0, 0.22, sin(a) * 1.0), Kit.mat("b9824f"), 10)
		circles.append(Vector3(p.x, p.y, 0.75))


func _build_garden() -> void:
	var g := ParkMap.GARDEN
	var r := _root(g)
	var white := Kit.mat("fbf7ef")
	Kit.cyl(r, 2.7, 2.8, 0.08, Vector3(0, 0.04, 0), Kit.mat("d8d2c4"), 6)
	for i in 6:
		var a := i * TAU / 6.0
		Kit.cyl(r, 0.1, 0.12, 2.5, Vector3(cos(a) * 2.4, 1.25, sin(a) * 2.4), white, 8)
		circles.append(Vector3(g.x + cos(a) * 2.4, g.y + sin(a) * 2.4, 0.14))
	Kit.cyl(r, 0.1, 3.3, 1.5, Vector3(0, 3.25, 0), Kit.mat("5fb3a8"), 6)
	Kit.ball(r, 0.2, Vector3(0, 4.1, 0), Kit.mat("f2c14e", 0.3))
	# Renk renk cicek yaylari (guneybati girisi acik)
	var bands := [[30.0, "ff6b5e"], [100.0, "ffd84d"], [240.0, "b48be8"], [310.0, "ff9ec4"]]
	for band in bands:
		for i in 85:
			var a := deg_to_rad(band[0] + _rng.randf_range(-28.0, 28.0))
			var p := g + Vector2(cos(a), sin(a)) * _rng.randf_range(4.6, 6.9)
			_flower(at(p), Color(band[1]), _rng.randf_range(0.9, 1.3))
		for i in 4:
			var a := deg_to_rad(band[0] - 27.0 + i * 18.0)
			_bush(g + Vector2(cos(a), sin(a)) * 7.5, 0.7)
	_bench(g + Vector2(3.9, 0.3), PI / 2)


func _build_picnic() -> void:
	var p := ParkMap.PICNIC
	var r := _root(p, 0.3)
	Kit.box(r, Vector3(2.8, 0.03, 2.1), Vector3(0, 0.03, 0), Kit.checker(Color("e2574c"), Color("ffffff"), 8, 6))
	Kit.box(r, Vector3(0.6, 0.34, 0.42), Vector3(-0.7, 0.2, -0.3), Kit.mat("c9a06a"))
	Kit.torus(r, 0.2, 0.24, Vector3(-0.7, 0.4, -0.3), Kit.mat("a8703a"), Vector3(PI / 2, 0, 0))
	Kit.ball(r, 0.09, Vector3(0.1, 0.12, 0.3), Kit.mat("e2574c", 0.4))
	Kit.ball(r, 0.09, Vector3(0.3, 0.12, 0.15), Kit.mat("8fce5a", 0.4))
	Kit.cyl(r, 0.22, 0.22, 0.03, Vector3(0.7, 0.06, -0.4), Kit.mat("ffffff", 0.3))
	Kit.ball(r, 0.2, Vector3(1.9, 0.2, 0.9), Kit.mat("ffd15c", 0.5))


func _build_lookouts() -> void:
	# Seyir tepesi
	var h := ParkMap.HILL
	_bench(h + Vector2(1.6, 1.3), 0.0)
	var t := _root(h + Vector2(-0.6, 2.4))
	Kit.cyl(t, 0.05, 0.07, 1.2, Vector3(0, 0.6, 0), Kit.mat("3f4750", 0.5), 8)
	Kit.cyl(t, 0.09, 0.12, 0.45, Vector3(0, 1.25, -0.05), Kit.mat("e2574c", 0.4), 10, Vector3(PI / 2 - 0.2, 0, 0))
	# Golet kiyisi
	_bench(ParkMap.LOOKOUT + Vector2(-0.9, 1.2), -PI / 2)


func _build_lamps() -> void:
	for p in [Vector2(2.2, -17), Vector2(-2.3, -9.5), Vector2(1.4, 13), Vector2(11, -2.4), Vector2(-10, 2.5),
			Vector2(-24.6, 8.6), Vector2(-31.4, 5.4), Vector2(7.3, 1.6), Vector2(-7.3, -1.6), Vector2(1.6, 7.3),
			Vector2(-1.6, -7.3), Vector2(19.5, 3.6), Vector2(9, 22.2), Vector2(-9, -9.5), Vector2(9.5, -7)]:
		_lamp(p)


# ---------------------------------------------------------------- bitkiler

func _foliage(y0: float, y1: float, sway: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("y0", y0)
	m.set_shader_parameter("y1", y1)
	m.set_shader_parameter("sway", sway)
	return m


func _blob_mesh(blobs: Array, segs := 10) -> SurfaceTool:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = segs
	s.rings = segs / 2
	var st := SurfaceTool.new()
	for b in blobs:
		var scl: Vector3 = b[1]
		st.append_from(s, 0, Transform3D(Basis().scaled(scl), b[0]))
	return st


func _trunk(mesh: ArrayMesh, r_top: float, r_bot: float, h: float) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 7
	c.rings = 1
	var st := SurfaceTool.new()
	st.append_from(c, 0, Transform3D(Basis(), Vector3(0, h * 0.5, 0)))
	st.commit(mesh)
	mesh.surface_set_material(0, Kit.mat("8a5a3c"))


func _round_tree_mesh(variant: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_trunk(mesh, 0.14, 0.26, 2.0)
	var one := Vector3.ONE
	var blobs := [
		[Vector3(0, 3.0, 0), one * 1.45], [Vector3(0.95, 2.5, 0.3), one * 1.0], [Vector3(-0.85, 2.6, -0.3), one * 1.05],
		[Vector3(0.1, 2.4, 0.95), one * 0.9], [Vector3(0, 3.8, -0.1), one * 0.95]]
	if variant == 1:
		blobs = [[Vector3(0, 3.1, 0), Vector3(1.15, 1.7, 1.15)], [Vector3(0.5, 2.4, 0.4), one * 0.8], [Vector3(-0.5, 2.6, -0.3), one * 0.85]]
	_blob_mesh(blobs).commit(mesh)
	mesh.surface_set_material(1, _foliage(1.5, 4.7, 0.04))
	return mesh


func _pine_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_trunk(mesh, 0.12, 0.2, 1.3)
	var st := SurfaceTool.new()
	for c in [[1.7, 1.35, 2.0], [2.7, 1.05, 1.8], [3.6, 0.75, 1.6]]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = c[1]
		cone.height = c[2]
		cone.radial_segments = 9
		cone.rings = 1
		st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, c[0], 0)))
	st.commit(mesh)
	mesh.surface_set_material(1, _foliage(0.7, 4.4, 0.02))
	return mesh


func _multimesh(mesh: Mesh, xf: Array[Transform3D], col: Array[Color], shadows := true) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, col[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _spot_free(p: Vector2, margin: float) -> bool:
	if ParkMap.path_sd(p) < margin or ParkMap.water_sd(p) < margin + 0.6:
		return false
	if ParkMap.rect_sd(p, ParkMap.YARD_MIN, ParkMap.YARD_MAX) < margin:
		return false
	if ParkMap.rect_sd(p, ParkMap.PLAY_MIN, ParkMap.PLAY_MAX) < margin:
		return false
	for c in ParkMap.CLEARINGS:
		if p.distance_to(Vector2(c.x, c.y)) < c.z + margin:
			return false
	return true


func _xf(p: Vector2, s: float, y := 0.0, squash := 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * squash, s)), at(p, y))


func _build_trees() -> void:
	var round_cols := ["5fae4a", "79bf52", "4c9a4a", "93c85a", "6bb86a"]
	var pine_cols := ["2f7d5a", "3a8a5c", "2b6e52"]
	var xf: Array = [[] as Array[Transform3D], [] as Array[Transform3D], [] as Array[Transform3D]]
	var col: Array = [[] as Array[Color], [] as Array[Color], [] as Array[Color]]
	var spots: Array[Vector2] = []

	# Elle yerlestirilenler: bahce, tepe mesesi, golet kiyisi, piknik golgesi
	var fixed := [[Vector2(-6, -31), 1.1, "f5b8cd"], [ParkMap.HILL + Vector2(-2.2, -0.8), 1.6, "79bf52"],
		[ParkMap.LOOKOUT + Vector2(-2.6, -2.2), 1.35, "93c85a"], [ParkMap.PICNIC + Vector2(-3.2, -1.6), 1.3, "f5b8cd"],
		[Vector2(6.5, -41), 1.2, "5fae4a"], [ParkMap.KIOSK + Vector2(0.5, -4.6), 1.2, "f5b8cd"]]
	for f in fixed:
		var p: Vector2 = f[0]
		spots.append(p)
		circles.append(Vector3(p.x, p.y, 0.45))
		xf[0].append(_xf(p, f[1], -0.05))
		col[0].append(Color(f[2]))

	for i in 1900:
		var inner := i < 700
		var p: Vector2
		if inner:
			p = Vector2(_rng.randf_range(-47, 47), _rng.randf_range(-47, 47))
			if p.length() > 46.5 or not _spot_free(p, 1.7):
				continue
			var dens := 0.5 + 0.5 * sin(p.x * 0.16 + 0.7) * cos(p.y * 0.14 - 0.3)
			if _rng.randf() > 0.15 + dens * 0.6:
				continue
		else:
			var a := _rng.randf() * TAU
			p = Vector2(cos(a), sin(a)) * _rng.randf_range(47.8, 70.0)
			if ParkMap.water_sd(p) < 2.0:
				continue
		var near := false
		for s in spots:
			if s.distance_to(p) < (3.4 if inner else 3.0):
				near = true
				break
		if near:
			continue
		spots.append(p)
		if inner:
			circles.append(Vector3(p.x, p.y, 0.4))
		var s := _rng.randf_range(0.85, 1.25) * (1.0 if inner else 1.3)
		if _rng.randf() < (0.22 if inner else 0.6):
			xf[2].append(_xf(p, s, -0.05, _rng.randf_range(0.9, 1.25)))
			col[2].append(Color(pine_cols[_rng.randi() % 3]))
		else:
			var v := _rng.randi() % 2
			xf[v].append(_xf(p, s, -0.05, _rng.randf_range(0.9, 1.1)))
			var c := Color(round_cols[_rng.randi() % 5])
			if inner and _rng.randf() < 0.1:
				c = Color("f5b8cd")   # cicek acmis agac
			col[v].append(c)
	_multimesh(_round_tree_mesh(0), xf[0], col[0])
	_multimesh(_round_tree_mesh(1), xf[1], col[1])
	_multimesh(_pine_mesh(), xf[2], col[2])


func _bush(p: Vector2, s := 1.0, y := 0.0) -> void:
	_bush_xf.append(_xf(p, s, y))
	_bush_col.append(Color(["4c9a4a", "5fae4a", "6bb86a"][_rng.randi() % 3]))


func _flower(pos: Vector3, c: Color, s := 1.0) -> void:
	_flower_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s * _rng.randf_range(0.85, 1.15)), pos))
	_flower_col.append(c)


func _flower_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var stem := CylinderMesh.new()
	stem.top_radius = 0.012
	stem.bottom_radius = 0.016
	stem.height = 0.34
	stem.radial_segments = 4
	stem.rings = 1
	var st := SurfaceTool.new()
	st.append_from(stem, 0, Transform3D(Basis(), Vector3(0, 0.17, 0)))
	st.commit(mesh)
	_blob_mesh([[Vector3(0, 0.36, 0), Vector3(0.13, 0.06, 0.13)]], 6).commit(mesh)
	_blob_mesh([[Vector3(0, 0.39, 0), Vector3(0.05, 0.045, 0.05)]], 5).commit(mesh)
	var petal := StandardMaterial3D.new()
	petal.vertex_color_use_as_albedo = true
	petal.vertex_color_is_srgb = true
	petal.roughness = 0.9
	mesh.surface_set_material(0, Kit.mat("4c9a4a"))
	mesh.surface_set_material(1, petal)
	mesh.surface_set_material(2, Kit.mat("ffc93c"))
	return mesh


func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in 3:
		var a := k * PI / 3.0 + 0.3
		var d := Vector3(cos(a), 0, sin(a))
		var o := d.cross(Vector3.UP) * 0.12 * (k - 1)
		var tip := o + Vector3(d.z * 0.1, 0.34 + k * 0.06, -d.x * 0.1)
		for tri in [[-1.0, 1.0], [1.0, -1.0]]:   # iki yuz
			st.add_vertex(o + d * 0.045 * tri[0])
			st.add_vertex(tip)
			st.add_vertex(o + d * 0.045 * tri[1])
	var mesh := st.commit()
	mesh.surface_set_material(0, _foliage(0.0, 0.4, 0.25))
	return mesh


func _scatter_plants() -> void:
	# Kir cicegi cayiri
	for i in 380:
		var a := _rng.randf() * TAU
		var p := ParkMap.MEADOW + Vector2(cos(a), sin(a)) * sqrt(_rng.randf()) * 8.5
		_flower(at(p), Color(FLOWER_COLORS[_rng.randi() % 6]))
	# Yol kenarlari ve serpistirme papatyalar
	var placed := 0
	while placed < 750:
		var p := Vector2(_rng.randf_range(-46, 46), _rng.randf_range(-46, 46))
		var d := ParkMap.path_sd(p)
		if p.length() > 46 or d < 0.5 or ParkMap.water_sd(p) < 1.0 or ParkMap.rect_sd(p, ParkMap.PLAY_MIN, ParkMap.PLAY_MAX) < 0.3:
			continue
		if d < 2.2:
			_flower(at(p), Color(FLOWER_COLORS[_rng.randi() % 6]))
		elif _rng.randf() < 0.3:
			_flower(at(p), Color(FLOWER_COLORS[_rng.randi() % 2]))
		else:
			continue
		placed += 1
	_multimesh(_flower_mesh(), _flower_xf, _flower_col, false)

	# Calilar
	var n := 0
	while n < 70:
		var p := Vector2(_rng.randf_range(-46, 46), _rng.randf_range(-46, 46))
		if p.length() < 46 and _spot_free(p, 0.8):
			_bush(p, _rng.randf_range(0.6, 1.2))
			n += 1
	var bush := ArrayMesh.new()
	_blob_mesh([[Vector3(0, 0.42, 0), Vector3.ONE * 0.62], [Vector3(0.5, 0.33, 0.1), Vector3.ONE * 0.45],
		[Vector3(-0.45, 0.36, -0.12), Vector3.ONE * 0.5]], 8).commit(bush)
	bush.surface_set_material(0, _foliage(0.0, 1.0, 0.03))
	_multimesh(bush, _bush_xf, _bush_col)

	# Cim tutamlari
	var gxf: Array[Transform3D] = []
	var gcol: Array[Color] = []
	var gcols := ["6fb84a", "8fce5a", "5aa544"]
	while gxf.size() < 5000:
		var p := Vector2(_rng.randf_range(-47, 47), _rng.randf_range(-47, 47))
		if ParkMap.path_sd(p) < 0.3 or ParkMap.water_sd(p) < 0.9 or ParkMap.rect_sd(p, ParkMap.PLAY_MIN, ParkMap.PLAY_MAX) < 0.2:
			continue
		gxf.append(_xf(p, _rng.randf_range(0.45, 0.85)))
		gcol.append(Color(gcols[_rng.randi() % 3]))
	_multimesh(_grass_mesh(), gxf, gcol, false)

	# Kayalar
	var rxf: Array[Transform3D] = []
	var rcol: Array[Color] = []
	while rxf.size() < 46:
		var p := Vector2(_rng.randf_range(-46, 46), _rng.randf_range(-46, 46))
		var shore := ParkMap.water_sd(p)
		var ok := (shore > 0.7 and shore < 1.8) if rxf.size() < 26 else _spot_free(p, 1.0)
		if not ok or ParkMap.path_sd(p) < 0.8 or p.length() > 46:
			continue
		var s := _rng.randf_range(0.25, 0.75)
		rxf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.65, s * 0.8)), at(p, s * 0.15)))
		rcol.append(Color(["a9abae", "9a9c9e", "b8b4aa"][_rng.randi() % 3]))
		if s > 0.5:
			circles.append(Vector3(p.x, p.y, s * 0.8))
	var rock := ArrayMesh.new()
	_blob_mesh([[Vector3.ZERO, Vector3.ONE]], 7).commit(rock)
	var rm := StandardMaterial3D.new()
	rm.vertex_color_use_as_albedo = true
	rm.vertex_color_is_srgb = true
	rm.roughness = 1.0
	rock.surface_set_material(0, rm)
	_multimesh(rock, rxf, rcol)


func _build_pond_life() -> void:
	var reed := Kit.mat("6f9a4a")
	var head := Kit.mat("7a4e2e")
	var n := 0
	while n < 34:
		var p := Vector2(_rng.randf_range(-40, -18), _rng.randf_range(-16, 3))
		var sd := ParkMap.water_sd(p)
		if sd < 0.15 or sd > 0.6:
			continue
		var h := _rng.randf_range(0.8, 1.3)
		Kit.cyl(self, 0.015, 0.02, h, at(p, h * 0.5 - 0.1), reed, 4)
		Kit.capsule(self, 0.04, 0.22, at(p, h - 0.1), head)
		n += 1
	n = 0
	while n < 9:
		var p := Vector2(_rng.randf_range(-37, -20), _rng.randf_range(-14, 0))
		if ParkMap.water_sd(p) > -1.6:
			continue
		Kit.cyl(self, 0.38, 0.38, 0.02, Vector3(p.x, ParkMap.WATER_Y + 0.02, p.y), Kit.mat("5aa544"), 10)
		if n % 2 == 0:
			Kit.ball(self, 0.12, Vector3(p.x + 0.1, ParkMap.WATER_Y + 0.1, p.y), Kit.mat("ff9ec4"), Vector3(1, 0.7, 1), 8)
		n += 1
	for i in 3:
		var d := Node3D.new()
		add_child(d)
		var white := Kit.mat("ffffff" if i < 2 else "f6dd7a")
		Kit.ball(d, 1.0, Vector3(0, 0.08, 0), white, Vector3(0.17, 0.14, 0.26), 10)
		Kit.ball(d, 0.09, Vector3(0, 0.25, -0.17), white, Vector3.ONE, 10)
		Kit.box(d, Vector3(0.07, 0.03, 0.1), Vector3(0, 0.23, -0.28), Kit.mat("ff9a3c"))
		Kit.ball(d, 0.018, Vector3(0.05, 0.28, -0.23), Kit.mat("2a2320"), Vector3.ONE, 6)
		Kit.ball(d, 0.018, Vector3(-0.05, 0.28, -0.23), Kit.mat("2a2320"), Vector3.ONE, 6)
		_ducks.append([d, Vector2(-28.5 + i * 0.8, -6.5 - i * 0.5), 2.2 + i * 0.9, i * 2.1])


func _build_clouds() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.emission_enabled = true
	m.emission = Color("dfe9f5")
	m.emission_energy_multiplier = 0.45
	var mesh := ArrayMesh.new()
	_blob_mesh([[Vector3(0, 0, 0), Vector3(5, 2.4, 3.4)], [Vector3(4, -0.4, 0.5), Vector3(3.6, 1.8, 2.6)],
		[Vector3(-4.2, -0.5, -0.4), Vector3(3.8, 1.7, 2.8)], [Vector3(1.4, 1.4, -0.3), Vector3(3, 1.8, 2.4)]]).commit(mesh)
	for i in 10:
		var c := Kit.add(self, mesh, m, Vector3(_rng.randf_range(-130, 130), _rng.randf_range(34, 48), _rng.randf_range(-150, 30)))
		c.scale = Vector3.ONE * _rng.randf_range(0.8, 1.8)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_clouds.append(c)


func hide_clouds() -> void:
	for c in _clouds:
		c.visible = false


func _process(dt: float) -> void:
	_t += dt
	for d in _ducks:
		var node: Node3D = d[0]
		var c: Vector2 = d[1]
		var a: float = _t * 0.22 + d[3]
		node.position = Vector3(c.x + cos(a) * d[2], ParkMap.WATER_Y + sin(_t * 2.0 + d[3]) * 0.015, c.y + sin(a) * d[2] * 0.7)
		node.rotation.y = -a + PI
	for c in _clouds:
		c.position.x += dt * 0.8
		if c.position.x > 140.0:
			c.position.x = -140.0
