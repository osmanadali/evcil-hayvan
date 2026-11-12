extends Node3D
## Dunyayi kodla kurar: arazi, su, bitkiler, yapilar. Harita verisi park_map.gd icinde.
## Yapilar ve agaclar Tripo modelleri (assets/models); kucuk esyalar basit sekillerden.

const ParkMap = preload("res://scripts/park_map.gd")
const Kit = preload("res://scripts/kit.gd")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")
const WATER_SHADER = preload("res://shaders/water.gdshader")
const FOLIAGE_SHADER = preload("res://shaders/foliage.gdshader")
const TREE_SHADER = preload("res://shaders/tree.gdshader")

const FLOWER_COLORS := ["f4f1e4", "f2c94c", "a78bd4", "e88fb0", "e0624f", "f0a04b"]
const HOUSE_TINTS := ["ffffff", "ffe9d6", "dfeeff", "eaffdf", "ffe0e0", "fff6c9", "e6e0ff"]

var circles: Array[Vector3] = []   # engel daireleri (x, z, yaricap)
var segments: Array = []           # engel dogrulari [Vector2, Vector2]
var toys: Array[Node3D] = []       # arka bahcedeki oyuncaklar
var bowl_pos := Vector2(-2.2, -41.6)
var bed_pos := Vector2(-7.0, -44.2)
var yarn_pos := Vector2(7.2, -44.0)

var _rng := RandomNumberGenerator.new()
var _splat_a: Texture2D
var _splat_b: Texture2D
var _scenes := {}
var _flower_xf: Array[Transform3D] = []
var _flower_col: Array[Color] = []
var _bush_xf: Array[Transform3D] = []
var _bush_col: Array[Color] = []
var _tree_fixed: Array = []        # [konum, boy, tur]
var _ducks: Array = []
var _clouds: Array[Node3D] = []
var _fire: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	_rng.seed = 20261112
	_splat_a = load("res://assets/splat_a.png")
	_splat_b = load("res://assets/splat_b.png")
	_build_ground()
	_build_water()
	_build_home()
	_build_street()
	_build_plaza()
	_build_bridge_and_pier()
	_build_play_area()
	_build_kiosk()
	_build_garden()
	_build_picnic()
	_build_lookouts()
	_build_square()
	_build_orchard()
	_build_beach()
	_build_camp()
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
	np = ParkMap.clamp_bounds(np)
	for c in circles:
		if absf(c.x - np.x) > 4.0 or absf(c.y - np.y) > 4.0:
			continue
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


func is_free(p: Vector2, r := 0.4) -> bool:
	return ParkMap.inside_bounds(p, 3.0) and not ParkMap.water_blocked(p) and resolve(p, r, p).distance_to(p) < 0.05


# ---------------------------------------------------------------- modeller

func _scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		_scenes[name] = load("res://assets/models/%s.glb" % name)
	return _scenes[name]


func _merged_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var local := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D:
		out = local * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var a := _merged_aabb(c, local)
		if a.size != Vector3.ZERO:
			out = a if first else out.merge(a)
			first = false
	return out


## Modeli yere oturtur. size: en genis yatay olcu (by_height ise yukseklik). rot_y = 0 guneye bakar.
func _model(name: String, p: Vector2, size: float, rot_y := 0.0, by_height := false, tint := "") -> Node3D:
	var inst: Node3D = _scene(name).instantiate()
	var holder := Node3D.new()
	holder.add_child(inst)
	inst.rotation.y = -PI / 2.0   # Tripo modelleri +X'e bakar
	var box := _merged_aabb(inst, Transform3D())
	var k := size / (box.size.y if by_height else maxf(box.size.x, box.size.z))
	inst.scale = Vector3.ONE * k
	var c := box.get_center() * k
	inst.position = Vector3(-c.x, -box.position.y * k, -c.z)
	holder.position = at(p)
	holder.rotation.y = rot_y
	holder.set_meta("half", Vector2(box.size.x, box.size.z) * k * 0.5)
	add_child(holder)
	if tint != "" and tint != "ffffff":
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m: BaseMaterial3D = mi.get_active_material(0).duplicate()
			m.albedo_color = Color(tint)
			mi.set_surface_override_material(0, m)
	return holder


## Dikdortgen engel (eksenlere hizali).
func _block(c: Vector2, half: Vector2) -> void:
	var a := c - half
	var b := c + half
	segments.append([a, Vector2(b.x, a.y)])
	segments.append([Vector2(b.x, a.y), b])
	segments.append([b, Vector2(a.x, b.y)])
	segments.append([Vector2(a.x, b.y), a])


func _block_model(holder: Node3D, p: Vector2, shrink := 0.82) -> void:
	var h: Vector2 = holder.get_meta("half")
	var quarter := absf(fmod(absf(holder.rotation.y), PI) - PI / 2.0) < 0.1
	_block(p, (Vector2(h.y, h.x) if quarter else h) * shrink)


# ---------------------------------------------------------------- arazi

func _build_ground() -> void:
	# Oyun alaninda sik, disinda seyrek izgara
	var mn := ParkMap.BOUNDS_MIN
	var mx := ParkMap.BOUNDS_MAX
	var xs := _axis(mn.x, mx.x)
	var zs := _axis(mn.y, mx.y)
	var nx := xs.size()
	var nz := zs.size()
	var verts := PackedVector3Array()
	verts.resize(nx * nz)
	for j in nz:
		for i in nx:
			var p := Vector2(xs[i], zs[j])
			verts[j * nx + i] = Vector3(p.x, ParkMap.terrain_height(p), p.y)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	var idx := PackedInt32Array()
	for j in nz:
		for i in nx:
			var dx := verts[j * nx + mini(i + 1, nx - 1)] - verts[j * nx + maxi(i - 1, 0)]
			var dz := verts[mini(j + 1, nz - 1) * nx + i] - verts[maxi(j - 1, 0) * nx + i]
			normals[j * nx + i] = dz.cross(dx).normalized()
			if i < nx - 1 and j < nz - 1:
				var a := j * nx + i
				idx.append_array([a, a + 1, a + nx + 1, a, a + nx + 1, a + nx])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	m.set_shader_parameter("splat_a", _splat_a)
	m.set_shader_parameter("splat_b", _splat_b)
	m.set_shader_parameter("splat_center", ParkMap.SPLAT_CENTER)
	m.set_shader_parameter("splat_extent", ParkMap.SPLAT_EXTENT)
	Kit.add(self, mesh, m)


func _axis(lo: float, hi: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var v := lo - 70.0
	while v < hi + 70.0:
		out.append(v)
		v += 1.0 if v >= lo - 4.0 and v <= hi + 4.0 else 6.0
	out.append(hi + 70.0)
	return out


func _water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("splat", _splat_a)
	m.set_shader_parameter("splat_center", ParkMap.SPLAT_CENTER)
	m.set_shader_parameter("splat_extent", ParkMap.SPLAT_EXTENT)
	return m


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(70, 130)
	var w := Kit.add(self, plane, _water_material(), Vector3(-46, ParkMap.WATER_Y, 38))
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- parcalar

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


func _hedge(a: Vector2, b: Vector2) -> void:
	segments.append([a, b])
	var n := int(a.distance_to(b) / 0.85)
	for i in n + 1:
		_bush(a.lerp(b, float(i) / n), _rng.randf_range(0.75, 0.9))


func _bench(p: Vector2, rot_y: float) -> void:
	_model("bank_lod", p, 1.9, rot_y)
	circles.append(Vector3(p.x, p.y, 0.8))


func _lamp(p: Vector2) -> void:
	_model("lamba_lod", p, 3.4, 0.0, true)
	circles.append(Vector3(p.x, p.y, 0.18))


func _umbrella_table(p: Vector2, hex: String, stools := 3) -> void:
	var t := _root(p)
	Kit.cyl(t, 0.65, 0.65, 0.06, Vector3(0, 0.75, 0), Kit.mat("ece7dc"), 16)
	Kit.cyl(t, 0.04, 0.04, 2.3, Vector3(0, 1.15, 0), Kit.mat("7d7f84"), 6)
	Kit.cyl(t, 0.02, 1.35, 0.5, Vector3(0, 2.4, 0), Kit.mat(hex), 10)
	for j in stools:
		var a := j * TAU / stools + p.x
		Kit.cyl(t, 0.22, 0.2, 0.45, Vector3(cos(a) * 1.0, 0.22, sin(a) * 1.0), Kit.mat("9a6b43"), 10)
	circles.append(Vector3(p.x, p.y, 0.75))


func _toy(node: Node3D, p: Vector2, y: float) -> void:
	node.position = at(p, y)
	node.set_meta("home", node.position)
	add_child(node)
	toys.append(node)


# ---------------------------------------------------------------- ev ve arka bahce

func _build_home() -> void:
	var h := ParkMap.HOUSE
	var house := _model("ev", h, 9.5, 0.0)
	_block_model(house, h)
	var mn := ParkMap.YARD_MIN
	var mx := ParkMap.YARD_MAX
	var hex := "ece6d8"
	_fence(mn, Vector2(-1.5, mn.y), hex)
	_fence(Vector2(1.5, mn.y), Vector2(mx.x, mn.y), hex)
	_fence(mn, Vector2(mn.x, mx.y), hex)
	_fence(Vector2(mx.x, mn.y), mx, hex)
	_fence(Vector2(mn.x, mx.y), Vector2(-1.5, mx.y), hex)
	_fence(Vector2(1.5, mx.y), mx, hex)
	var wood := Kit.mat("7d5236")

	# On bahce: posta kutusu, cicekler
	var mb := _root(Vector2(2.2, -26.2))
	Kit.box(mb, Vector3(0.1, 1.0, 0.1), Vector3(0, 0.5, 0), wood)
	Kit.box(mb, Vector3(0.3, 0.26, 0.5), Vector3(0, 1.1, 0), Kit.mat("b8433a", 0.5))
	circles.append(Vector3(2.2, -26.2, 0.2))
	for i in 60:
		var p := Vector2(_rng.randf_range(-10, 10), _rng.randf_range(-30.5, -27.8))
		if absf(p.x) > 1.6:
			_flower(at(p), Color(FLOWER_COLORS[_rng.randi() % 6]))

	# Arka bahce: kulube, mama kaplari, havuz, kedi agaci, sebze tarhi, oyuncaklar
	var kennel := _model("kulube", Vector2(-7.2, -46.2), 2.3, 0.5)
	circles.append(Vector3(-7.2, -46.2, 1.25))
	kennel.name = "Kulube"
	for i in 2:
		var b := _root(bowl_pos + Vector2(i * 0.75, 0))
		Kit.cyl(b, 0.24, 0.3, 0.13, Vector3(0, 0.065, 0), Kit.mat(["b8433a", "3f6fa8"][i], 0.4))
		Kit.cyl(b, 0.2, 0.2, 0.02, Vector3(0, 0.125, 0), Kit.mat(["8a5a35", "7fb9d6"][i], 0.3))
	var pool := _root(Vector2(6.0, -51.0))
	Kit.cyl(pool, 1.7, 1.7, 0.42, Vector3(0, 0.21, 0), Kit.mat("3f6fa8", 0.5), 22)
	Kit.cyl(pool, 1.55, 1.55, 0.04, Vector3(0, 0.41, 0), Kit.mat("7fc4d9", 0.1), 22)
	Kit.ball(pool, 0.16, Vector3(0.5, 0.5, 0.3), Kit.mat("f2c94c", 0.4))
	circles.append(Vector3(6.0, -51.0, 1.75))
	# Kedi tirmalama agaci
	var ct := _root(Vector2(8.3, -45.4))
	var rope := Kit.mat("c9ab7a")
	var felt := Kit.mat("8f7f9e")
	Kit.box(ct, Vector3(1.1, 0.1, 1.1), Vector3(0, 0.05, 0), felt)
	Kit.cyl(ct, 0.09, 0.09, 1.5, Vector3(-0.3, 0.8, 0), rope, 8)
	Kit.cyl(ct, 0.09, 0.09, 0.8, Vector3(0.3, 0.45, 0.1), rope, 8)
	Kit.box(ct, Vector3(0.7, 0.08, 0.7), Vector3(0.3, 0.88, 0.1), felt)
	Kit.box(ct, Vector3(0.6, 0.08, 0.6), Vector3(-0.3, 1.58, 0), felt)
	Kit.cyl(ct, 0.01, 0.01, 0.4, Vector3(-0.55, 1.36, 0.2), Kit.mat("eeeeee"), 4)
	Kit.ball(ct, 0.07, Vector3(-0.55, 1.14, 0.2), Kit.mat("d95f76"))
	circles.append(Vector3(8.3, -45.4, 0.7))
	# Sebze tarhi
	var bed := _root(Vector2(-3.5, -53.6))
	Kit.box(bed, Vector3(4.6, 0.22, 2.0), Vector3(0, 0.11, 0), wood)
	Kit.box(bed, Vector3(4.4, 0.06, 1.8), Vector3(0, 0.22, 0), Kit.mat("4d3a2a"))
	for i in 14:
		var px := -1.9 + (i % 7) * 0.63
		var pz := -0.45 + (i / 7) * 0.9
		Kit.ball(bed, 0.16, Vector3(px, 0.33, pz), Kit.mat(["4c8a3f", "6aa84f"][i % 2]), Vector3(1, 0.8, 1), 8)
		if i % 3 == 0:
			Kit.ball(bed, 0.07, Vector3(px + 0.08, 0.42, pz), Kit.mat("d2452f", 0.4), Vector3.ONE, 6)
	_block(Vector2(-3.5, -53.6), Vector2(2.3, 1.0))
	# Salincakli agac
	_tree_fixed.append([Vector2(-8.0, -52.5), 7.5, 0])
	var sw := _root(Vector2(-6.3, -51.6))
	Kit.cyl(sw, 0.015, 0.015, 2.2, Vector3(0, 2.3, 0), Kit.mat("d8cfb8"), 4)
	Kit.torus(sw, 0.3, 0.46, Vector3(0, 1.0, 0), Kit.mat("2b2b2e", 0.7), Vector3(PI / 2, 0.4, 0))
	_tree_fixed.append([Vector2(7.5, -31.0), 6.0, 0])
	# Oyuncaklar (kopek bunlari alip getirebilir)
	var cols := ["c8452f", "e9b93a", "3f6fa8", "5d9e6b"]
	for i in 3:
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.26
		ball.mesh = sm
		ball.material_override = Kit.mat(cols[i], 0.5)
		_toy(ball, Vector2(-2.5 + i * 2.3, -47.5 + (i % 2) * 1.6), 0.13)
	var bone := Node3D.new()
	Kit.capsule(bone, 0.05, 0.36, Vector3.ZERO, Kit.mat("efe6d2"), Vector3(0, 0, PI / 2))
	for sx in [-0.17, 0.17]:
		Kit.ball(bone, 0.075, Vector3(sx, 0, 0.045), Kit.mat("efe6d2"))
		Kit.ball(bone, 0.075, Vector3(sx, 0, -0.045), Kit.mat("efe6d2"))
	_toy(bone, Vector2(1.5, -44.0), 0.08)
	var frisbee := Node3D.new()
	Kit.cyl(frisbee, 0.22, 0.24, 0.04, Vector3.ZERO, Kit.mat("d95f76", 0.4), 16)
	_toy(frisbee, Vector2(-4.5, -44.5), 0.03)
	# Kedi yumagi sepeti
	var basket := _root(yarn_pos + Vector2(1.0, 0.4))
	Kit.cyl(basket, 0.42, 0.34, 0.3, Vector3(0, 0.15, 0), Kit.mat("b48a55"), 12)
	for i in 3:
		Kit.ball(basket, 0.14, Vector3(cos(i * 2.1) * 0.18, 0.34, sin(i * 2.1) * 0.18), Kit.mat(["d95f76", "6b8fd6", "f2c94c"][i], 0.9), Vector3.ONE, 10)
	# Tarhlar
	for i in 80:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_flower(at(Vector2(side * _rng.randf_range(9.6, 10.5), _rng.randf_range(-55, -41))), Color(FLOWER_COLORS[_rng.randi() % 6]))
	for i in 7:
		_bush(Vector2(-10.2, -40.0 + i * 1.1), 0.7)


# ---------------------------------------------------------------- mahalle

func _build_street() -> void:
	var z := ParkMap.STREET_Z
	var i := 0
	for lot in ParkMap.LOTS:
		var c: Vector2 = lot[0]
		var face: float = lot[1]
		var fwd := Vector2(0, 1).rotated(-face)   # sokaga bakan yon
		var hp := c - fwd * 2.5
		var house := _model("ev_lod", hp, 8.4, face, false, HOUSE_TINTS[(i + 1) % HOUSE_TINTS.size()])
		_block_model(house, hp)
		var hl := ParkMap.LOT_HALF
		var back := c - fwd * hl.y
		var front := c + fwd * hl.y
		_hedge(back + Vector2(-hl.x, 0), back + Vector2(hl.x, 0))
		_hedge(back + Vector2(-hl.x, 0), front + Vector2(-hl.x, 0))
		_hedge(back + Vector2(hl.x, 0), front + Vector2(hl.x, 0))
		_fence(front + Vector2(-hl.x, 0), front + Vector2(-1.4, 0), ["ece6d8", "b48a55"][i % 2], 0.8)
		_fence(front + Vector2(1.4, 0), front + Vector2(hl.x, 0), ["ece6d8", "b48a55"][i % 2], 0.8)
		# Kapiya giden tas basamaklar
		for s in 6:
			var sp := front - fwd * (0.6 + s * 1.05)
			Kit.cyl(self, 0.42, 0.42, 0.05, at(sp + Vector2(_rng.randf_range(-0.1, 0.1), 0), 0.02), Kit.mat("a9a59c"), 9)
		# Bahce susu
		var side := 1.0 if i % 2 == 0 else -1.0
		_tree_fixed.append([c + Vector2(side * 5.5, 0) + fwd * 6.5, _rng.randf_range(4.5, 6.0), 1 if i % 3 == 0 else 0])
		for k in 26:
			var fp := c + fwd * _rng.randf_range(4.5, 10.5) + Vector2(_rng.randf_range(-7.5, 7.5), 0)
			if absf(fp.x - c.x) > 1.2:
				_flower(at(fp), Color(FLOWER_COLORS[(i + k % 2) % 6]))
		var mb := _root(front + Vector2(2.0, 0) + fwd * 0.5)
		Kit.box(mb, Vector3(0.1, 1.0, 0.1), Vector3(0, 0.5, 0), Kit.mat("7d5236"))
		Kit.box(mb, Vector3(0.3, 0.26, 0.5), Vector3(0, 1.1, 0), Kit.mat(["3f6fa8", "5d9e6b", "b8433a"][i % 3], 0.5))
		i += 1
	# Sokak lambalari ve kaldirim agaclari
	var x := -52.0
	var k := 0
	while x < 60.0:
		var sz := z + (5.6 if k % 2 == 0 else -5.6)
		if absf(x) > 3.0:
			_lamp(Vector2(x, sz))
		_tree_fixed.append([Vector2(x + 8.0, z - 5.9 if k % 2 == 0 else z + 5.9), _rng.randf_range(5.0, 6.5), 0])
		x += 16.0
		k += 1
	var az := -52.0
	while az < 38.0:
		if absf(az + 12.5) > 5.0:
			_lamp(Vector2(ParkMap.AVENUE_X + (5.6 if k % 2 == 0 else -5.6), az))
			_tree_fixed.append([Vector2(ParkMap.AVENUE_X + (-5.9 if k % 2 == 0 else 5.9), az + 7.0), _rng.randf_range(5.0, 6.5), 0])
		az += 14.0
		k += 1
	# Sokak sonu banklari
	_bench(Vector2(-20, z + 5.9), PI)
	_bench(Vector2(20, z - 5.9), 0.0)


# ---------------------------------------------------------------- park

func _build_plaza() -> void:
	_model("cesme", ParkMap.PLAZA, 5.4, 0.0)
	circles.append(Vector3(0, 0, 2.75))
	var stone := Kit.mat("b9b3a6")
	for i in 28:
		var a := i * TAU / 28.0
		Kit.box(self, Vector3(1.2, 0.05, 0.5), Vector3(cos(a) * 6.9, 0.02, sin(a) * 6.9), Kit.mat("a8a297"), Vector3(0, -a + PI / 2, 0))
	for deg in [135.0, 22.0, -158.0, 112.0]:
		var a := deg_to_rad(deg)
		var p := Vector2(cos(a), sin(a)) * 5.6
		_bench(p, atan2(-p.x, -p.y) + PI)
	for deg in [68.0, -112.0, -22.0, 158.0]:
		var a := deg_to_rad(deg)
		var p := Vector2(cos(a), sin(a)) * 6.1
		Kit.cyl(self, 0.75, 0.62, 0.55, at(p, 0.27), stone, 14)
		circles.append(Vector3(p.x, p.y, 0.8))
		_bush(p, 0.75, 0.45)
		for i in 9:
			var fa := i * TAU / 9.0
			_flower(at(p + Vector2(cos(fa), sin(fa)) * 0.55, 0.5), Color(FLOWER_COLORS[(i % 2) * 3 + 1]))


func _plank_deck(c: Vector2, half: Vector2, base: float, rails: bool) -> void:
	var wood := Kit.mat("a8774a")
	var dark := Kit.mat("7d5236")
	var n := int(half.x * 2.0 / 0.48)
	var lo := c.x - half.x + 0.01
	var hi := c.x + half.x - 0.01
	for i in n:
		var x := c.x - half.x + (i + 0.5) * half.x * 2.0 / n
		var y := ParkMap.deck_y(Vector2(x, c.y))
		var slope := (ParkMap.deck_y(Vector2(minf(x + 0.1, hi), c.y)) - ParkMap.deck_y(Vector2(maxf(x - 0.1, lo), c.y))) / 0.2
		Kit.box(self, Vector3(half.x * 2.0 / n * 0.92, 0.1, half.y * 2.0), Vector3(x, y - 0.05, c.y), wood if i % 2 == 0 else dark, Vector3(0, 0, atan(slope)))
	var posts := int(half.x / 0.75) + 1
	for sz in [-1.0, 1.0]:
		var z: float = c.y + sz * (half.y - 0.06)
		var prev := Vector3.ZERO
		for i in posts:
			var x := c.x - half.x + 0.05 + i * (half.x * 2.0 - 0.1) / (posts - 1)
			var top := Vector3(x, ParkMap.deck_y(Vector2(clampf(x, lo, hi), c.y)) + 0.85, z)
			if rails:
				Kit.box(self, Vector3(0.14, 1.3, 0.14), top - Vector3(0, 0.6, 0), dark)
				Kit.ball(self, 0.11, top + Vector3(0, 0.08, 0), dark, Vector3.ONE, 8)
				if i > 0:
					var d := top - prev
					Kit.box(self, Vector3(d.length(), 0.1, 0.08), (top + prev) * 0.5 - Vector3(0, 0.12, 0), wood, Vector3(0, 0, atan2(d.y, d.x)))
			else:
				Kit.cyl(self, 0.1, 0.1, 1.6, Vector3(x, base - 0.5, z), dark, 8)
			prev = top


func _build_bridge_and_pier() -> void:
	for d in ParkMap.DECKS:
		_plank_deck(d[0], d[1], d[3], d[2] > 0.0)
	# Iskele ucunda kayik
	var boat := Node3D.new()
	boat.position = Vector3(-41.0, ParkMap.WATER_Y + 0.12, 70.6)
	boat.rotation.y = 0.3
	add_child(boat)
	var hull := Kit.mat("8a4b32")
	Kit.box(boat, Vector3(2.6, 0.12, 1.0), Vector3(0, 0, 0), hull)
	Kit.box(boat, Vector3(2.6, 0.4, 0.08), Vector3(0, 0.2, 0.5), hull, Vector3(-0.25, 0, 0))
	Kit.box(boat, Vector3(2.6, 0.4, 0.08), Vector3(0, 0.2, -0.5), hull, Vector3(0.25, 0, 0))
	Kit.box(boat, Vector3(0.08, 0.4, 1.0), Vector3(1.3, 0.2, 0), hull)
	Kit.box(boat, Vector3(0.08, 0.4, 1.0), Vector3(-1.3, 0.2, 0), hull)
	Kit.box(boat, Vector3(0.3, 0.06, 1.0), Vector3(0.3, 0.3, 0), Kit.mat("c9ab7a"))
	_ducks.append([boat, Vector2(-41.0, 70.6), 0.0, 0.0])


func _build_play_area() -> void:
	var mn := ParkMap.PLAY_MIN
	var mx := ParkMap.PLAY_MAX
	var hex := "a8774a"
	_fence(mn, Vector2(mx.x, mn.y), hex)
	_fence(Vector2(mx.x, mn.y), mx, hex)
	_fence(mx, Vector2(mn.x, mx.y), hex)
	_fence(mn, Vector2(mn.x, 4.6), hex)
	_fence(Vector2(mn.x, 7.4), Vector2(mn.x, mx.y), hex)
	for z in [4.6, 7.4]:
		Kit.box(self, Vector3(0.2, 2.6, 0.2), Vector3(mn.x, 1.3, z), Kit.mat("b8433a"))
	Kit.box(self, Vector3(0.24, 0.5, 3.4), Vector3(mn.x, 2.7, 6.0), Kit.mat("e0b23e"))
	var cols := ["b8433a", "e0b23e", "3f6fa8"]
	for i in 3:
		var p := Vector2(28.5 + i * 2.6, 4.3)
		var r := _root(p)
		Kit.box(r, Vector3(0.1, 0.6, 0.1), Vector3(0, 0.3, 0), Kit.mat("ece6d8"))
		Kit.torus(r, 0.5, 0.62, Vector3(0, 1.15 + i * 0.12, 0), Kit.mat(cols[i], 0.5), Vector3(0, 0, PI / 2))
		circles.append(Vector3(p.x, p.y, 0.12))
	var ramp := _root(Vector2(35.5, 8.5), 0.4)
	Kit.box(ramp, Vector3(1.2, 0.1, 2.3), Vector3(0, 0.55, -0.98), Kit.mat("e0b23e"), Vector3(0.52, 0, 0))
	Kit.box(ramp, Vector3(1.2, 0.1, 2.3), Vector3(0, 0.55, 0.98), Kit.mat("3f6fa8"), Vector3(-0.52, 0, 0))
	circles.append(Vector3(35.5, 8.5, 1.2))
	var tube := StandardMaterial3D.new()
	tube.albedo_color = Color("4f9a76")
	tube.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tm := CylinderMesh.new()
	tm.top_radius = 0.6
	tm.bottom_radius = 0.6
	tm.height = 2.6
	tm.cap_top = false
	tm.cap_bottom = false
	Kit.add(self, tm, tube, Vector3(30.5, 0.58, 11.3), Vector3(0, 0.3, PI / 2))
	circles.append(Vector3(30.5, 11.3, 1.0))
	for i in 6:
		var p := Vector2(34.0 + i * 0.9, 12.3)
		Kit.cyl(self, 0.05, 0.05, 1.1, Vector3(p.x, 0.55, p.y), Kit.mat(cols[i % 3], 0.5), 8)
		circles.append(Vector3(p.x, p.y, 0.08))
	Kit.cyl(self, 0.3, 0.38, 0.16, Vector3(26.0, 0.08, 12.6), Kit.mat("3f6fa8", 0.4))
	_bench(Vector2(38.4, 11.0), PI / 2)


func _build_kiosk() -> void:
	var k := ParkMap.KIOSK
	_model("dondurmaci", k, 4.6, 0.0)
	circles.append(Vector3(k.x, k.y, 2.3))
	_umbrella_table(k + Vector2(-3.8, 2.4), "d9a441")
	_umbrella_table(k + Vector2(3.8, 2.8), "5a9bb5")


func _build_garden() -> void:
	var g := ParkMap.GARDEN
	_model("cardak", g, 6.4, 0.0)
	for i in 6:
		var a := i * TAU / 6.0 + PI / 6.0
		circles.append(Vector3(g.x + cos(a) * 2.7, g.y + sin(a) * 2.7, 0.25))
	var bands := [[30.0, "d9523f"], [100.0, "f2c94c"], [240.0, "a78bd4"], [310.0, "e88fb0"]]
	for band in bands:
		for i in 85:
			var a := deg_to_rad(band[0] + _rng.randf_range(-28.0, 28.0))
			var p := g + Vector2(cos(a), sin(a)) * _rng.randf_range(4.6, 6.9)
			_flower(at(p), Color(band[1]), _rng.randf_range(0.9, 1.3))
		for i in 4:
			var a := deg_to_rad(band[0] - 27.0 + i * 18.0)
			_bush(g + Vector2(cos(a), sin(a)) * 7.5, 0.7)
	_bench(g + Vector2(4.6, 0.3), -PI / 2)


func _build_picnic() -> void:
	var p := ParkMap.PICNIC
	var r := _root(p, 0.3)
	Kit.box(r, Vector3(2.8, 0.03, 2.1), Vector3(0, 0.03, 0), Kit.checker(Color("b8433a"), Color("ece6d8"), 8, 6))
	Kit.box(r, Vector3(0.6, 0.34, 0.42), Vector3(-0.7, 0.2, -0.3), Kit.mat("b48a55"))
	Kit.torus(r, 0.2, 0.24, Vector3(-0.7, 0.4, -0.3), Kit.mat("8a5a35"), Vector3(PI / 2, 0, 0))
	Kit.ball(r, 0.09, Vector3(0.1, 0.12, 0.3), Kit.mat("c8452f", 0.4))
	Kit.ball(r, 0.09, Vector3(0.3, 0.12, 0.15), Kit.mat("7fae4f", 0.4))
	Kit.cyl(r, 0.22, 0.22, 0.03, Vector3(0.7, 0.06, -0.4), Kit.mat("ece6d8", 0.3))
	_tree_fixed.append([p + Vector2(-3.4, -1.8), 7.0, 0])


func _build_lookouts() -> void:
	var h := ParkMap.HILL
	_bench(h + Vector2(1.6, 1.3), PI)
	var t := _root(h + Vector2(-0.6, 2.4))
	Kit.cyl(t, 0.05, 0.07, 1.2, Vector3(0, 0.6, 0), Kit.mat("3f4750", 0.5), 8)
	Kit.cyl(t, 0.09, 0.12, 0.45, Vector3(0, 1.25, -0.05), Kit.mat("b8433a", 0.4), 10, Vector3(PI / 2 - 0.2, 0, 0))
	_tree_fixed.append([h + Vector2(-2.4, -0.8), 9.0, 0])
	_bench(ParkMap.LOOKOUT + Vector2(-0.9, 1.2), PI / 2)
	_tree_fixed.append([ParkMap.LOOKOUT + Vector2(-2.8, -2.4), 7.5, 0])


# ---------------------------------------------------------------- carsi

func _build_square() -> void:
	var s := ParkMap.SQUARE
	var shop := _model("petshop", ParkMap.PETSHOP, 13.0, 0.0)
	_block_model(shop, ParkMap.PETSHOP)
	var cafe := _model("kafe", ParkMap.CAFE, 13.0, -PI / 2)
	_block_model(cafe, ParkMap.CAFE)
	# Ortada buyuk agac ve cevresinde tas oturak
	_tree_fixed.append([s, 10.0, 0])
	Kit.cyl(self, 2.2, 2.3, 0.5, at(s, 0.25), Kit.mat("b9b3a6"), 20)
	Kit.cyl(self, 1.7, 1.7, 0.06, at(s, 0.52), Kit.mat("4d3a2a"), 20)
	circles.append(Vector3(s.x, s.y, 2.4))
	for i in 24:
		var a := i * TAU / 24.0
		_flower(at(s + Vector2(cos(a), sin(a)) * 1.4, 0.5), Color(FLOWER_COLORS[i % 3 + 2]))
	for deg in [45.0, 135.0, 225.0, 315.0]:
		var a := deg_to_rad(deg)
		_lamp(s + Vector2(cos(a), sin(a)) * 10.5)
	_bench(s + Vector2(-6.5, 6.5), PI * 0.75 + PI)
	_bench(s + Vector2(6.0, 7.0), -PI * 0.75 + PI)
	_bench(s + Vector2(-7.5, -5.0), PI * 0.3)
	# Kafe masalari
	_umbrella_table(ParkMap.CAFE + Vector2(-8.5, -3.2), "8f4a3a")
	_umbrella_table(ParkMap.CAFE + Vector2(-8.5, 3.4), "8f4a3a")
	_umbrella_table(ParkMap.CAFE + Vector2(-11.5, 0.2), "c9ab7a")
	# Pazar tezgahlari
	for i in 2:
		var p := s + Vector2(-5.0 + i * 9.0, 15.5)
		var r := _root(p, PI)
		var wood := Kit.mat("9a6b43")
		Kit.box(r, Vector3(3.0, 0.9, 1.2), Vector3(0, 0.45, 0), wood)
		for sx in [-1.4, 1.4]:
			Kit.box(r, Vector3(0.1, 2.4, 0.1), Vector3(sx, 1.2, -0.5), wood)
			Kit.box(r, Vector3(0.1, 2.0, 0.1), Vector3(sx, 1.0, 0.6), wood)
		Kit.box(r, Vector3(3.3, 0.06, 1.7), Vector3(0, 2.25, 0.05), Kit.checker(Color(["5d8f5a", "b8433a"][i]), Color("ece6d8"), 8, 1), Vector3(0.3, 0, 0))
		var fruit := ["c8452f", "e0a030", "7fae4f", "e9b93a"]
		for k in 4:
			Kit.box(r, Vector3(0.62, 0.16, 0.9), Vector3(-1.08 + k * 0.72, 0.98, 0), Kit.mat("b48a55"))
			for f in 6:
				Kit.ball(r, 0.1, Vector3(-1.25 + k * 0.72 + (f % 3) * 0.17, 1.12, -0.2 + (f / 3) * 0.35), Kit.mat(fruit[(k + i) % 4], 0.5), Vector3.ONE, 7)
		_block(p, Vector2(1.6, 0.8))
	# Cicek saksilari
	for deg in [0.0, 90.0, 180.0, 270.0]:
		var a := deg_to_rad(deg + 20.0)
		var p := s + Vector2(cos(a), sin(a)) * 8.0
		Kit.cyl(self, 0.6, 0.48, 0.5, at(p, 0.25), Kit.mat("9c6b4f"), 12)
		circles.append(Vector3(p.x, p.y, 0.65))
		_bush(p, 0.6, 0.42)
		for i in 7:
			_flower(at(p + Vector2(cos(i * 0.9), sin(i * 0.9)) * 0.45, 0.48), Color(FLOWER_COLORS[i % 2 + 3]))


func _build_orchard() -> void:
	var o := ParkMap.ORCHARD
	var apples: Array[Transform3D] = []
	var acol: Array[Color] = []
	for ix in 5:
		for iz in 4:
			var p := o + Vector2((ix - 2) * 6.2, (iz - 1.5) * 6.2)
			_tree_fixed.append([p, _rng.randf_range(4.6, 5.4), 2])
			for k in 12:
				var a := _rng.randf() * TAU
				var r := _rng.randf_range(0.6, 1.9)
				var on_tree := k < 8
				var pos := at(p + Vector2(cos(a), sin(a)) * r, _rng.randf_range(2.4, 4.0) if on_tree else 0.08)
				apples.append(Transform3D(Basis(), pos))
				acol.append(Color(["c8452f", "d9523f", "e0a030"][_rng.randi() % 3]))
	var am := SphereMesh.new()
	am.radius = 0.11
	am.height = 0.22
	am.radial_segments = 7
	am.rings = 4
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.5
	am.material = mat
	_multimesh(am, apples, acol, false, 64.0)
	# Citler ve kasalar
	var mn := o - Vector2(17.0, 13.5)
	var mx := o + Vector2(17.0, 13.5)
	_fence(mn, Vector2(o.x - 2.0, mn.y), "a8774a")
	_fence(Vector2(o.x + 2.0, mn.y), Vector2(mx.x, mn.y), "a8774a")
	_fence(Vector2(mx.x, mn.y), mx, "a8774a")
	_fence(mx, Vector2(mn.x, mx.y), "a8774a")
	_fence(Vector2(mn.x, mx.y), mn, "a8774a")
	for i in 3:
		var c := _root(o + Vector2(-14.5 + i * 0.9, -11.5 + (i % 2) * 0.5), i * 0.4)
		Kit.box(c, Vector3(0.7, 0.4, 0.5), Vector3(0, 0.2, 0), Kit.mat("b48a55"))
		for f in 4:
			Kit.ball(c, 0.1, Vector3(-0.18 + (f % 2) * 0.36, 0.44, -0.1 + (f / 2) * 0.2), Kit.mat("c8452f", 0.5), Vector3.ONE, 7)
	# Aycicegi tarlasi
	for i in 150:
		var p := o + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(15.0, 19.5))
		_flower(at(p), Color("f2c230"), _rng.randf_range(2.6, 3.6))


# ---------------------------------------------------------------- gol ve orman

func _build_beach() -> void:
	var b := ParkMap.BEACH
	var cols := ["c8452f", "3f6fa8", "e0b23e"]
	for i in 3:
		var p: Vector2 = b + [Vector2(-2.5, -3.0), Vector2(3.5, 1.5), Vector2(-1.0, 6.0)][i]
		var r := _root(p, i * 0.9)
		Kit.cyl(r, 0.04, 0.04, 2.4, Vector3(0, 1.2, 0), Kit.mat("ece6d8"), 6, Vector3(0, 0, 0.12))
		Kit.cyl(r, 0.02, 1.5, 0.55, Vector3(-0.14, 2.4, 0), Kit.checker(Color(cols[i]), Color("ece6d8"), 8, 1), 12, Vector3(0, 0, 0.12))
		Kit.box(r, Vector3(1.0, 0.03, 2.0), Vector3(1.0, 0.03, 0.4), Kit.checker(Color(cols[(i + 1) % 3]), Color("ece6d8"), 1, 6))
		circles.append(Vector3(p.x, p.y, 0.15))
	# Kumdan kale, kova, top
	var sc := _root(b + Vector2(-5.5, 2.0))
	var sand := Kit.mat("d9c48d")
	Kit.cyl(sc, 0.6, 0.75, 0.4, Vector3(0, 0.2, 0), sand, 12)
	for i in 4:
		var a := i * TAU / 4.0
		Kit.cyl(sc, 0.16, 0.2, 0.6, Vector3(cos(a) * 0.55, 0.3, sin(a) * 0.55), sand, 8)
		Kit.cyl(sc, 0.01, 0.18, 0.2, Vector3(cos(a) * 0.55, 0.7, sin(a) * 0.55), sand, 8)
	Kit.cyl(sc, 0.2, 0.25, 0.5, Vector3(0, 0.6, 0), sand, 10)
	Kit.cyl(sc, 0.13, 0.1, 0.24, Vector3(1.1, 0.12, 0.5), Kit.mat("3f6fa8", 0.4), 10)
	circles.append(Vector3(b.x - 5.5, b.y + 2.0, 0.9))
	var ball := Node3D.new()
	Kit.ball(ball, 0.3, Vector3.ZERO, Kit.checker(Color("c8452f"), Color("ece6d8"), 6, 2))
	_toy(ball, b + Vector2(1.5, -2.5), 0.3)
	_bench(Vector2(-12.6, 78.0), PI / 2)
	_lamp(Vector2(-27.2, 66.2))


func _build_camp() -> void:
	var c := ParkMap.CAMP
	var tent := _root(c + Vector2(-2.6, -1.6), 0.5)
	Kit.prism(tent, Vector3(2.6, 1.6, 3.0), Vector3(0, 0.8, 0), Kit.mat("c8763a"))
	Kit.prism(tent, Vector3(1.0, 1.0, 0.05), Vector3(0, 0.5, 1.51), Kit.mat("3a2a22"))
	circles.append(Vector3(c.x - 2.6, c.y - 1.6, 1.7))
	var fire := _root(c + Vector2(1.2, 0.8))
	for i in 8:
		var a := i * TAU / 8.0
		Kit.ball(fire, 0.16, Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), Kit.mat("8d8f92"), Vector3(1, 0.7, 1), 7)
	for i in 3:
		Kit.cyl(fire, 0.07, 0.07, 0.8, Vector3(0, 0.12, 0), Kit.mat("5a3d28"), 7, Vector3(PI / 2, i * 1.05, 0))
	_fire = Kit.cyl(fire, 0.01, 0.22, 0.6, Vector3(0, 0.45, 0), Kit.glow("ff9a3c", 2.2), 8)
	circles.append(Vector3(c.x + 1.2, c.y + 0.8, 0.7))
	for i in 2:
		var a := 0.6 + i * 1.9
		var lp := c + Vector2(1.2, 0.8) + Vector2(cos(a), sin(a)) * 1.9
		Kit.cyl(self, 0.24, 0.24, 1.7, at(lp, 0.24), Kit.mat("6b4a32"), 9, Vector3(PI / 2, -a + PI / 2, 0))
		circles.append(Vector3(lp.x, lp.y, 0.5))


func _build_lamps() -> void:
	for p in [Vector2(2.2, -17), Vector2(-2.3, -9.5), Vector2(1.4, 13), Vector2(11, -2.6), Vector2(-10, 2.5),
			Vector2(-24.6, 8.6), Vector2(-31.4, 5.4), Vector2(7.3, 1.6), Vector2(-7.3, -1.6), Vector2(1.6, 7.3),
			Vector2(-1.6, -7.3), Vector2(19.5, 3.6), Vector2(9, 22.2), Vector2(-9, -9.5), Vector2(9.5, -7),
			Vector2(30, -7.8), Vector2(46, -10.6), Vector2(-8, 31), Vector2(-15.5, 50), Vector2(28, 35), Vector2(48, 40.6),
			Vector2(-46.5, -16), Vector2(-50, -46)]:
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


## Cok sayida ornegi bolgelere bolerek cizer; uzaktaki bolgeler gizlenir.
func _multimesh(mesh: Mesh, xf: Array[Transform3D], col: Array[Color], shadows := true, cell := 48.0,
		view_range := 0.0, custom: Array[Color] = []) -> void:
	var groups := {}
	for i in xf.size():
		var key := Vector2i(floori(xf[i].origin.x / cell), floori(xf[i].origin.z / cell))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(i)
	for key in groups:
		var ids: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = custom.size() > 0
		mm.mesh = mesh
		mm.instance_count = ids.size()
		for k in ids.size():
			mm.set_instance_transform(k, xf[ids[k]])
			mm.set_instance_color(k, col[ids[k]])
			if custom.size() > 0:
				mm.set_instance_custom_data(k, custom[ids[k]])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if view_range > 0.0:
			mi.visibility_range_end = view_range + cell * 0.7
		add_child(mi)


func _spot_free(p: Vector2, margin: float) -> bool:
	if ParkMap.path_sd(p) < margin or ParkMap.water_sd(p) < margin + 0.6:
		return false
	if ParkMap.paved_sd(p) < margin or ParkMap.lot_sd(p) < margin:
		return false
	if ParkMap.rect_sd(p, ParkMap.PLAY_MIN, ParkMap.PLAY_MAX) < margin:
		return false
	for c in ParkMap.CLEARINGS:
		if p.distance_to(Vector2(c.x, c.y)) < c.z + margin:
			return false
	return true


func _xf(p: Vector2, s: float, y := 0.0, squash := 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * squash, s)), at(p, y))


## Tripo agac modelinden cok ornekli cizim icin mesh ve taban donusumu cikarir.
func _tree_kind(name: String) -> Array:
	var inst: Node3D = _scene(name).instantiate()
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var local := Transform3D()
	var n: Node = mi
	while n != inst:
		local = (n as Node3D).transform * local
		n = n.get_parent()
	var box := local * mi.mesh.get_aabb()
	var k := 1.0 / box.size.y
	var c := box.get_center()
	var base := Transform3D(Basis().scaled(Vector3.ONE * k), Vector3(-c.x, -box.position.y, -c.z) * k) * local
	var m := ShaderMaterial.new()
	m.shader = TREE_SHADER
	m.set_shader_parameter("tex", (mi.get_active_material(0) as BaseMaterial3D).albedo_texture)
	var mesh: Mesh = mi.mesh.duplicate()
	mesh.surface_set_material(0, m)
	inst.free()
	return [mesh, base]


func _build_trees() -> void:
	var kinds := [_tree_kind("agac_lod"), _tree_kind("cam_lod")]
	var xf: Array = [[] as Array[Transform3D], [] as Array[Transform3D]]
	var col: Array = [[] as Array[Color], [] as Array[Color]]
	var cus: Array = [[] as Array[Color], [] as Array[Color]]
	var spots: Array[Vector2] = []
	var tints := ["ffffff", "e4f0d0", "fff2c4", "d6e8d0", "f4ffd9"]

	var plant := func(p: Vector2, height: float, kind: int, tint: Color) -> void:
		var base: Transform3D = kinds[kind][1]
		var ground := gy(p) - 0.08
		var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * height), Vector3(p.x, ground, p.y)) * base
		xf[kind].append(t)
		col[kind].append(tint)
		cus[kind].append(Color(ground, height, 0, 0))

	for f in _tree_fixed:
		var p: Vector2 = f[0]
		spots.append(p)
		circles.append(Vector3(p.x, p.y, 0.5))
		var kind: int = f[2]
		plant.call(p, f[1], 1 if kind == 1 else 0, Color("f0ffd0") if kind == 2 else Color.WHITE)

	var mn := ParkMap.BOUNDS_MIN - Vector2(24, 24)
	var mx := ParkMap.BOUNDS_MAX + Vector2(24, 24)
	for i in 9000:
		var p := Vector2(_rng.randf_range(mn.x, mx.x), _rng.randf_range(mn.y, mx.y))
		var inside := ParkMap.inside_bounds(p, 1.0)
		var dens := ParkMap.forest(p)
		if inside:
			if not _spot_free(p, 1.9):
				continue
			var clump := 0.5 + 0.5 * sin(p.x * 0.16 + 0.7) * cos(p.y * 0.14 - 0.3)
			if _rng.randf() > maxf(dens, 0.05 + clump * 0.22):
				continue
		elif ParkMap.water_sd(p) < 2.0:
			continue
		var gap := 3.0 if dens > 0.5 else 4.2
		var near := false
		for s in spots:
			if absf(s.x - p.x) < gap and absf(s.y - p.y) < gap and s.distance_to(p) < gap:
				near = true
				break
		if near:
			continue
		spots.append(p)
		if inside:
			circles.append(Vector3(p.x, p.y, 0.45))
		var pine := _rng.randf() < (0.65 if dens > 0.4 else 0.2)
		var height := _rng.randf_range(5.0, 7.5) * (1.25 if not inside else 1.0) * (1.15 if pine else 1.0)
		plant.call(p, height, 1 if pine else 0, Color(tints[_rng.randi() % tints.size()]))
	for k in 2:
		_multimesh(kinds[k][0], xf[k], col[k], true, 40.0, 0.0, cus[k])


func _bush(p: Vector2, s := 1.0, y := 0.0) -> void:
	_bush_xf.append(_xf(p, s, y))
	_bush_col.append(Color(["3f7a3a", "4c8a3f", "5a9648"][_rng.randi() % 3]))


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
	_blob_mesh([[Vector3(0, 0.36, 0), Vector3(0.12, 0.05, 0.12)]], 6).commit(mesh)
	_blob_mesh([[Vector3(0, 0.385, 0), Vector3(0.05, 0.04, 0.05)]], 5).commit(mesh)
	var petal := StandardMaterial3D.new()
	petal.vertex_color_use_as_albedo = true
	petal.vertex_color_is_srgb = true
	petal.roughness = 0.9
	mesh.surface_set_material(0, Kit.mat("4c8a3f"))
	mesh.surface_set_material(1, petal)
	mesh.surface_set_material(2, Kit.mat("c9962e"))
	return mesh


func _grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for k in 5:
		var a := k * TAU / 5.0 + 0.3
		var d := Vector3(cos(a), 0, sin(a))
		var o := Vector3(cos(a * 2.3), 0, sin(a * 2.3)) * 0.1
		var tip := o + Vector3(d.z * 0.12, 0.26 + (k % 3) * 0.07, -d.x * 0.12)
		for tri in [[-1.0, 1.0], [1.0, -1.0]]:
			st.add_vertex(o + d * 0.035 * tri[0])
			st.add_vertex(tip)
			st.add_vertex(o + d * 0.035 * tri[1])
	var mesh := st.commit()
	mesh.surface_set_material(0, _foliage(0.0, 0.4, 0.3))
	return mesh


func _scatter_plants() -> void:
	var mn := ParkMap.BOUNDS_MIN
	var mx := ParkMap.BOUNDS_MAX
	# Kir cicegi cayiri
	for i in 380:
		var a := _rng.randf() * TAU
		var p := ParkMap.MEADOW + Vector2(cos(a), sin(a)) * sqrt(_rng.randf()) * 8.5
		_flower(at(p), Color(FLOWER_COLORS[_rng.randi() % 6]))
	# Yol kenarlari ve serpistirme
	var placed := 0
	var tries := 0
	while placed < 2600 and tries < 60000:
		tries += 1
		var p := Vector2(_rng.randf_range(mn.x, mx.x), _rng.randf_range(mn.y, mx.y))
		var d := ParkMap.path_sd(p)
		if d < 0.5 or ParkMap.water_sd(p) < 1.0 or ParkMap.paved_sd(p) < 0.4 or ParkMap.lot_sd(p) < 0.5 \
				or ParkMap.rect_sd(p, ParkMap.PLAY_MIN, ParkMap.PLAY_MAX) < 0.3 or p.distance_to(ParkMap.BEACH) < ParkMap.BEACH_R:
			continue
		if d < 2.2:
			_flower(at(p), Color(FLOWER_COLORS[_rng.randi() % 6]))
		elif _rng.randf() < 0.12:
			_flower(at(p), Color(FLOWER_COLORS[_rng.randi() % 2]))
		else:
			continue
		placed += 1
	_multimesh(_flower_mesh(), _flower_xf, _flower_col, false, 32.0, 46.0)

	# Calilar
	var n := 0
	while n < 260:
		var p := Vector2(_rng.randf_range(mn.x, mx.x), _rng.randf_range(mn.y, mx.y))
		if _spot_free(p, 0.8) and p.distance_to(ParkMap.BEACH) > ParkMap.BEACH_R + 2.0:
			_bush(p, _rng.randf_range(0.6, 1.2))
			n += 1
	var bush := ArrayMesh.new()
	_blob_mesh([[Vector3(0, 0.42, 0), Vector3.ONE * 0.62], [Vector3(0.5, 0.33, 0.1), Vector3.ONE * 0.45],
		[Vector3(-0.45, 0.36, -0.12), Vector3.ONE * 0.5]], 8).commit(bush)
	bush.surface_set_material(0, _foliage(0.0, 1.0, 0.03))
	_multimesh(bush, _bush_xf, _bush_col, true, 40.0, 70.0)

	# Cim tutamlari
	var gxf: Array[Transform3D] = []
	var gcol: Array[Color] = []
	var gcols := ["4f8a3a", "6a9c44", "436f33", "7a9a48"]
	tries = 0
	while gxf.size() < 26000 and tries < 200000:
		tries += 1
		var p := Vector2(_rng.randf_range(mn.x, mx.x), _rng.randf_range(mn.y, mx.y))
		if ParkMap.path_sd(p) < 0.3 or ParkMap.water_sd(p) < 0.9 or ParkMap.paved_sd(p) < 0.3 \
				or ParkMap.rect_sd(p, ParkMap.PLAY_MIN, ParkMap.PLAY_MAX) < 0.2 or p.distance_to(ParkMap.BEACH) < ParkMap.BEACH_R - 1.0:
			continue
		gxf.append(_xf(p, _rng.randf_range(0.6, 1.1)))
		gcol.append(Color(gcols[_rng.randi() % 4]))
	_multimesh(_grass_mesh(), gxf, gcol, false, 24.0, 34.0)

	# Kayalar
	var rxf: Array[Transform3D] = []
	var rcol: Array[Color] = []
	tries = 0
	while rxf.size() < 130 and tries < 40000:
		tries += 1
		var p := Vector2(_rng.randf_range(mn.x, mx.x), _rng.randf_range(mn.y, mx.y))
		var shore := ParkMap.water_sd(p)
		var ok := (shore > 0.7 and shore < 1.8) if rxf.size() < 80 else _spot_free(p, 1.0)
		if not ok or ParkMap.path_sd(p) < 0.8 or p.distance_to(ParkMap.BEACH) < ParkMap.BEACH_R:
			continue
		var s := _rng.randf_range(0.25, 0.8)
		rxf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.65, s * 0.8)), at(p, s * 0.15)))
		rcol.append(Color(["8d8f92", "7f8184", "9a968c"][_rng.randi() % 3]))
		if s > 0.5:
			circles.append(Vector3(p.x, p.y, s * 0.8))
	var rock := ArrayMesh.new()
	_blob_mesh([[Vector3.ZERO, Vector3.ONE]], 7).commit(rock)
	var rm := StandardMaterial3D.new()
	rm.vertex_color_use_as_albedo = true
	rm.vertex_color_is_srgb = true
	rm.roughness = 1.0
	rock.surface_set_material(0, rm)
	_multimesh(rock, rxf, rcol, true, 48.0, 80.0)

	# Orman mantarlari
	var mxf: Array[Transform3D] = []
	var mcol: Array[Color] = []
	tries = 0
	while mxf.size() < 90 and tries < 20000:
		tries += 1
		var p := Vector2(_rng.randf_range(-70, -34), _rng.randf_range(-60, -10))
		if ParkMap.forest(p) > 0.5 and ParkMap.path_sd(p) > 0.4:
			mxf.append(_xf(p, _rng.randf_range(0.7, 1.4)))
			mcol.append(Color(["c8452f", "d9a441", "ece6d8"][_rng.randi() % 3]))
	var mush := ArrayMesh.new()
	var stem := CylinderMesh.new()
	stem.top_radius = 0.03
	stem.bottom_radius = 0.045
	stem.height = 0.14
	stem.radial_segments = 6
	var st := SurfaceTool.new()
	st.append_from(stem, 0, Transform3D(Basis(), Vector3(0, 0.07, 0)))
	st.commit(mush)
	_blob_mesh([[Vector3(0, 0.15, 0), Vector3(0.1, 0.06, 0.1)]], 7).commit(mush)
	mush.surface_set_material(0, Kit.mat("ece6d8"))
	mush.surface_set_material(1, rm)
	_multimesh(mush, mxf, mcol, false, 32.0, 40.0)


func _build_pond_life() -> void:
	var rxf: Array[Transform3D] = []
	var rcol: Array[Color] = []
	var tries := 0
	while rxf.size() < 150 and tries < 60000:
		tries += 1
		var p := Vector2(_rng.randf_range(-72, -8), _rng.randf_range(-18, 98))
		var sd := ParkMap.water_sd(p)
		if sd < 0.15 or sd > 0.6 or p.distance_to(ParkMap.BEACH) < ParkMap.BEACH_R + 1.0 or ParkMap.deck_y(p) > -100.0:
			continue
		rxf.append(_xf(p, _rng.randf_range(0.8, 1.3), -0.1))
		rcol.append(Color.WHITE)
	var rm := ArrayMesh.new()
	var stem := CylinderMesh.new()
	stem.top_radius = 0.015
	stem.bottom_radius = 0.02
	stem.height = 1.0
	stem.radial_segments = 4
	var st := SurfaceTool.new()
	st.append_from(stem, 0, Transform3D(Basis(), Vector3(0, 0.5, 0)))
	st.commit(rm)
	_blob_mesh([[Vector3(0, 0.95, 0), Vector3(0.04, 0.12, 0.04)]], 6).commit(rm)
	rm.surface_set_material(0, Kit.mat("5f8a42"))
	rm.surface_set_material(1, Kit.mat("6b4428"))
	_multimesh(rm, rxf, rcol, false, 40.0, 60.0)
	var n := 0
	tries = 0
	while n < 26 and tries < 20000:
		tries += 1
		var p := Vector2(_rng.randf_range(-66, -18), _rng.randf_range(-16, 94))
		if ParkMap.water_sd(p) > -1.6 or ParkMap.deck_y(p + Vector2(0, 1)) > -100.0:
			continue
		Kit.cyl(self, 0.38, 0.38, 0.02, Vector3(p.x, ParkMap.WATER_Y + 0.02, p.y), Kit.mat("4c8a3f"), 10)
		if n % 2 == 0:
			Kit.ball(self, 0.12, Vector3(p.x + 0.1, ParkMap.WATER_Y + 0.1, p.y), Kit.mat("e88fb0"), Vector3(1, 0.7, 1), 8)
		n += 1
	for i in 6:
		var d := Node3D.new()
		add_child(d)
		var lake := i >= 3
		var white := Kit.mat("f2efe6" if i % 3 < 2 else "d9c46a")
		var s := 1.5 if lake else 1.0
		var up := 0.12 if lake else 0.0
		Kit.ball(d, 1.0, Vector3(0, 0.08, 0) * s, white, Vector3(0.17, 0.14, 0.26) * s, 10)
		Kit.ball(d, 0.09 * s, Vector3(0, 0.25 + up, -0.17) * s, white, Vector3.ONE, 10)
		if lake:
			Kit.cyl(d, 0.035, 0.045, 0.2, Vector3(0, 0.33, -0.22), white, 6, Vector3(0.3, 0, 0))
		Kit.box(d, Vector3(0.07, 0.03, 0.1) * s, Vector3(0, 0.23 + up, -0.28) * s, Kit.mat("d98a3a"))
		var c := Vector2(-50.0 + (i - 3) * 2.5, 76.0 - (i - 3) * 1.5) if lake else Vector2(-28.5 + i * 0.8, -6.5 - i * 0.5)
		_ducks.append([d, c, (5.0 if lake else 2.2) + (i % 3) * 0.9, i * 2.1])


func _build_clouds() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.emission_enabled = true
	m.emission = Color("dfe9f5")
	m.emission_energy_multiplier = 0.45
	var mesh := ArrayMesh.new()
	_blob_mesh([[Vector3(0, 0, 0), Vector3(5, 2.4, 3.4)], [Vector3(4, -0.4, 0.5), Vector3(3.6, 1.8, 2.6)],
		[Vector3(-4.2, -0.5, -0.4), Vector3(3.8, 1.7, 2.8)], [Vector3(1.4, 1.4, -0.3), Vector3(3, 1.8, 2.4)]]).commit(mesh)
	for i in 16:
		var c := Kit.add(self, mesh, m, Vector3(_rng.randf_range(-200, 220), _rng.randf_range(44, 60), _rng.randf_range(-260, 60)))
		c.scale = Vector3.ONE * _rng.randf_range(1.0, 2.2)
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
		var bob := sin(_t * 2.0 + d[3]) * 0.015
		if d[2] == 0.0:
			node.position.y = ParkMap.WATER_Y + 0.12 + bob
			node.rotation.z = sin(_t * 1.1) * 0.04
			continue
		node.position = Vector3(c.x + cos(a) * d[2], ParkMap.WATER_Y + bob, c.y + sin(a) * d[2] * 0.7)
		node.rotation.y = -a + PI
	if _fire:
		_fire.scale = Vector3(1.0 + sin(_t * 13.0) * 0.12, 1.0 + sin(_t * 9.0 + 1.0) * 0.2, 1.0 + cos(_t * 11.0) * 0.12)
	for c in _clouds:
		c.position.x += dt * 0.8
		if c.position.x > 230.0:
			c.position.x = -210.0
