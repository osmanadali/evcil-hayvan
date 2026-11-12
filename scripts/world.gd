extends Node3D
## Kecioren haritasini 3D sahneye cevirir: zemin, golet, apartmanlar, parklar ve oyuna eklenen yerler.
## Sokak, bina ve park verisi OpenStreetMap'ten gelir (park_map.gd / assets/city.json).

const ParkMap = preload("res://scripts/park_map.gd")
const Kit = preload("res://scripts/kit.gd")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")
const WATER_SHADER = preload("res://shaders/water.gdshader")
const FOLIAGE_SHADER = preload("res://shaders/foliage.gdshader")
const TREE_SHADER = preload("res://shaders/tree.gdshader")
const BUILDING_SHADER = preload("res://shaders/building.gdshader")

const FLOWER_COLORS := ["f4f1e4", "f2c94c", "a78bd4", "e88fb0", "e0624f", "f0a04b"]
const FACADES := ["e9dcc3", "e3c9a8", "d9d2c4", "e8d3b9", "cfd6cf", "e6c3b0", "dfd9b8", "c9c2b5", "e2cdd0", "d6c7a6"]
const CELL := 16.0

var toys: Array[Node3D] = []
var bowl_pos := Vector2.ZERO
var pool_pos := Vector2.ZERO
var kennel_pos := Vector2.ZERO
var yarn_pos := Vector2.ZERO

var _rng := RandomNumberGenerator.new()
var _splat_a: Texture2D
var _splat_b: Texture2D
var _img_a: Image
var _img_b: Image
var _px := 2048
var _scenes := {}
var _circles: Array[Vector3] = []
var _segments: Array = []
var _hash := {}
var _see_through: Array[ShaderMaterial] = []
var _flower_xf: Array[Transform3D] = []
var _flower_col: Array[Color] = []
var _bush_xf: Array[Transform3D] = []
var _bush_col: Array[Color] = []
var _tree_fixed: Array = []
var _keep_out: Array = []          # [merkez, yari boyut] agac dikilmeyen dikdortgenler
var _street_lamps: Array[Transform3D] = []
var _signs: Array[Node3D] = []
var car_mesh: Mesh
var car_base := Transform3D()
var _ducks: Array = []
var _clouds: Array[Node3D] = []
var _t := 0.0


func _ready() -> void:
	_rng.seed = 20261112
	ParkMap.load_data()
	_splat_a = load("res://assets/splat_a.png")
	_splat_b = load("res://assets/splat_b.png")
	_img_a = _splat_a.get_image()
	_img_b = _splat_b.get_image()
	_px = _img_a.get_width()
	var t0 := Time.get_ticks_msec()
	for step in ["ground", "water", "buildings", "spots", "pitches", "streets", "details", "doors", "road_marks", "cars", "parks", "pond_life", "plants"]:
		var t := Time.get_ticks_msec()
		call("_build_" + step)
		if OS.has_environment("SURE"):
			print("SURE ", step, " ", Time.get_ticks_msec() - t, " ms")
	if OS.has_environment("SURE"):
		print("SURE toplam ", Time.get_ticks_msec() - t0, " ms")


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


# ---------------------------------------------------------------- engeller

func _cells(mn: Vector2, mx: Vector2, entry: Vector2i) -> void:
	for cx in range(floori(mn.x / CELL), floori(mx.x / CELL) + 1):
		for cz in range(floori(mn.y / CELL), floori(mx.y / CELL) + 1):
			var key := Vector2i(cx, cz)
			if not _hash.has(key):
				_hash[key] = []
			_hash[key].append(entry)


func _add_circle(c: Vector3) -> void:
	_circles.append(c)
	var r := Vector2(c.z + 1.0, c.z + 1.0)
	_cells(Vector2(c.x, c.y) - r, Vector2(c.x, c.y) + r, Vector2i(0, _circles.size() - 1))


func _add_segment(a: Vector2, b: Vector2) -> void:
	_segments.append([a, b])
	var pad := Vector2(1.0, 1.0)
	_cells(a.min(b) - pad, a.max(b) + pad, Vector2i(1, _segments.size() - 1))


## Dikdortgen engel (eksenlere hizali).
func _block(c: Vector2, half: Vector2) -> void:
	var a := c - half
	var b := c + half
	_add_segment(a, Vector2(b.x, a.y))
	_add_segment(Vector2(b.x, a.y), b)
	_add_segment(b, Vector2(a.x, b.y))
	_add_segment(Vector2(a.x, b.y), a)


## Hareketi engellere ve suya gore duzeltir.
func resolve(np: Vector2, r: float, old: Vector2) -> Vector2:
	np = ParkMap.clamp_bounds(np)
	var list: Array = _hash.get(Vector2i(floori(np.x / CELL), floori(np.y / CELL)), [])
	for e in list:
		if e.x == 0:
			var c := _circles[e.y]
			var cp := Vector2(c.x, c.y)
			var d := np.distance_to(cp)
			if d < c.z + r and d > 0.001:
				np = cp + (np - cp) / d * (c.z + r)
		else:
			var s: Array = _segments[e.y]
			var a: Vector2 = s[0]
			var ab: Vector2 = s[1] - a
			var q := a + ab * clampf((np - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := np.distance_to(q)
			if d < r + 0.08 and d > 0.001:
				np = q + (np - q) / d * (r + 0.08)
	if _wet(np):
		if not _wet(Vector2(np.x, old.y)):
			return Vector2(np.x, old.y)
		if not _wet(Vector2(old.x, np.y)):
			return Vector2(old.x, np.y)
		return old
	return np


## Suda mi? Yol ve patikalarin gectigi yerler (kopruler) sayilmaz.
func _wet(p: Vector2) -> bool:
	if not ParkMap.water_blocked(p):
		return false
	var m := _mask(p)
	return m[0] < 0.5 and m[2] < 0.5


func is_free(p: Vector2, r := 0.4) -> bool:
	return ParkMap.inside_bounds(p, 3.0) and not _wet(p) and resolve(p, r, p).distance_to(p) < 0.05


## Kamera ile oyuncu arasina giren bina ve agaclari deler.
func set_focus(pos: Vector3, enabled := true) -> void:
	var f := pos if enabled else Vector3(0, -1000, 0)
	for m in _see_through:
		m.set_shader_parameter("focus", f)


## Zemin turu (boyama dokularindan): [patika, kiyi, asfalt, kaldirim, sehir zemini]
func _mask(p: Vector2) -> Array:
	var uv := p / ParkMap.SPLAT_EXTENT + Vector2(0.5, 0.5)
	var x := clampi(int(uv.x * _px), 0, _px - 1)
	var y := clampi(int(uv.y * _px), 0, _px - 1)
	var a := _img_a.get_pixel(x, y)
	var b := _img_b.get_pixel(x, y)
	return [a.r, a.g, b.r, b.g, b.b]


## Park cimi mi? (yol, su, kaldirim degil ve park icinde)
func _is_lawn(p: Vector2) -> bool:
	var m := _mask(p)
	return m[0] < 0.44 and m[1] > 0.62 and m[2] < 0.44 and m[3] < 0.44 and m[4] < 0.44


func _kept_out(p: Vector2, margin := 1.5) -> bool:
	for k in _keep_out:
		var c: Vector2 = k[0]
		var h: Vector2 = k[1]
		if absf(p.x - c.x) < h.x + margin and absf(p.y - c.y) < h.y + margin:
			return true
	return false


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
func _model(name: String, p: Vector2, size: float, rot_y := 0.0, by_height := false) -> Node3D:
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
	return holder


func _block_model(holder: Node3D, p: Vector2, shrink := 0.82) -> void:
	var h: Vector2 = holder.get_meta("half")
	var quarter := absf(fmod(absf(holder.rotation.y), PI) - PI / 2.0) < 0.1
	_block(p, (Vector2(h.y, h.x) if quarter else h) * shrink)


# ---------------------------------------------------------------- zemin ve su

func _build_ground() -> void:
	# Egimli arazi: 8 m aralikli izgara
	var half := ParkMap.height_extent * 0.5 - 4.0
	var n := int(half * 2.0 / 8.0)
	var verts := PackedVector3Array()
	verts.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var p := Vector2(-half + i * half * 2.0 / n, -half + j * half * 2.0 / n)
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
	m.set_shader_parameter("splat_a", _splat_a)
	m.set_shader_parameter("splat_b", _splat_b)
	m.set_shader_parameter("splat_center", ParkMap.SPLAT_CENTER)
	m.set_shader_parameter("splat_extent", ParkMap.SPLAT_EXTENT)
	m.set_shader_parameter("splat_c", load("res://assets/splat_c.png"))
	for pair in [["t_grass", "cim"], ["t_asphalt", "asfalt"], ["t_pavers", "kaldirim"], ["t_yard", "zemin"], ["t_gravel", "patika"], ["t_sand", "kum"]]:
		m.set_shader_parameter(pair[0], load("res://assets/tex/%s.jpg" % pair[1]))
	for pair in [["n_grass", "cim_n"], ["n_asphalt", "asfalt_n"], ["n_pavers", "kaldirim_n"]]:
		m.set_shader_parameter(pair[0], load("res://assets/tex/%s.jpg" % pair[1]))
	Kit.add(self, mesh, m)


func _build_water() -> void:
	# Su yuzeyi araziye serilir (izgara); kiyinin disi ve kopruler shader'da atilir
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("splat", _splat_a)
	m.set_shader_parameter("splat_b", _splat_b)
	m.set_shader_parameter("splat_center", ParkMap.SPLAT_CENTER)
	m.set_shader_parameter("splat_extent", ParkMap.SPLAT_EXTENT)
	for b in ParkMap.water_boxes:
		var r: Rect2 = b
		var nx := maxi(int(r.size.x / 6.0), 1)
		var nz := maxi(int(r.size.y / 6.0), 1)
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var idx := PackedInt32Array()
		for j in nz + 1:
			for i in nx + 1:
				var p := r.position + Vector2(r.size.x * i / nx, r.size.y * j / nz)
				verts.append(Vector3(p.x, ParkMap.terrain_height(p) + ParkMap.WATER_LIFT, p.y))
				normals.append(Vector3.UP)
				if i < nx and j < nz:
					var a := j * (nx + 1) + i
					idx.append_array([a, a + 1, a + nx + 2, a, a + nx + 2, a + nx + 1])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		Kit.add(self, mesh, m).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- binalar

func _build_buildings() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = BUILDING_SHADER
	mat.set_shader_parameter("t_wall", load("res://assets/tex/siva.jpg"))
	mat.set_shader_parameter("t_roof", load("res://assets/tex/kiremit.jpg"))
	mat.set_shader_parameter("t_flat", load("res://assets/tex/zemin.jpg"))
	mat.set_shader_parameter("n_wall", load("res://assets/tex/siva_n.jpg"))
	mat.set_shader_parameter("n_roof", load("res://assets/tex/kiremit_n.jpg"))
	_see_through.append(mat)
	var chunks := {}
	for b in ParkMap.data["buildings"]:
		var poly := ParkMap.to_poly(b["p"])
		if poly.size() < 3:
			continue
		var area := 0.0
		var c := Vector2.ZERO
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			area += p.x * q.y - q.x * p.y
			c += p
		c /= poly.size()
		if area < 0.0:
			poly.reverse()
		var h: float = b["h"]
		var kind: String = b["t"]
		# Egimde: taban en alcak koseye iner, cati en yuksek koseden olculur
		var y_lo := 1e9
		var y_hi := -1e9
		for p in poly:
			var gh := ParkMap.terrain_height(p)
			y_lo = minf(y_lo, gh)
			y_hi = maxf(y_hi, gh)
		y_lo -= 0.6
		var tint := Color(FACADES[_rng.randi() % FACADES.size()])
		if kind == "cami":
			tint = Color("ded8c9")
			h = 9.0
			_mosque(poly, c, sqrt(absf(area) * 0.5), y_hi + h)
		elif kind == "okul":
			tint = Color("ead9b0")
		var seed := _rng.randf()
		var key := Vector2i(floori(c.x / 128.0), floori(c.y / 128.0))
		if not chunks.has(key):
			chunks[key] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedVector2Array(), PackedColorArray(), PackedInt32Array()]
		var ch: Array = chunks[key]
		var v: PackedVector3Array = ch[0]
		var n: PackedVector3Array = ch[1]
		var uv: PackedVector2Array = ch[2]
		var uv2: PackedVector2Array = ch[3]
		var col: PackedColorArray = ch[4]
		var idx: PackedInt32Array = ch[5]
		var run := 0.0
		var solid := ParkMap.inside_bounds(c, -12.0)
		for i in poly.size():
			var a := poly[i]
			var bb := poly[(i + 1) % poly.size()]
			var d := bb - a
			var length := d.length()
			if length < 0.05:
				continue
			var normal := Vector3(d.y, 0, -d.x).normalized()
			var base := v.size()
			v.append_array([Vector3(a.x, y_lo, a.y), Vector3(bb.x, y_lo, bb.y), Vector3(bb.x, y_hi + h, bb.y), Vector3(a.x, y_hi + h, a.y)])
			uv.append_array([Vector2(run, y_lo - y_hi), Vector2(run + length, y_lo - y_hi), Vector2(run + length, h), Vector2(run, h)])
			for k in 4:
				n.append(normal)
				uv2.append(Vector2(h, seed))
				col.append(tint)
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
			# Yola bakan cephede gercek balkonlar (shader'daki balkon kapisi sutunlariyla ayni yerde)
			if kind == "apartman" and solid and b.has("door") and ((a + bb) * 0.5).distance_to(Vector2(b["door"][0], b["door"][1])) < 0.2:
				var floors := int((h - 0.7) / 3.0)
				var k0 := int(ceil((run + 0.4) / 3.1))
				var k1 := int(floor((run + length - 0.4) / 3.1)) - 1
				for kc in range(k0, k1 + 1):
					if kc % 3 != 1:
						continue
					var bc := a + d / length * ((kc + 0.5) * 3.1 - run)
					for f in range(1, floors):
						_balcony(ch, Vector3(bc.x, y_hi + f * 3.0 + 0.3, bc.y), Vector3(d.x, 0, d.y) / length, normal, tint)
			run += length
			if solid:
				_add_segment(a, bb)
		var top := y_hi + h
		var cap := poly
		if b.get("roof", "duz") == "kirma":
			# Kirma cati: sacaktan iceri dogru yukselen egimli yuzler
			var rise := clampf(sqrt(absf(area) * 0.5) * 0.16, 1.4, 2.6)
			cap = PackedVector2Array()
			for p in poly:
				cap.append(c + (p - c) * 0.32)
			for i in poly.size():
				var j := (i + 1) % poly.size()
				var e0 := Vector3(poly[i].x, top, poly[i].y)
				var e1 := Vector3(poly[j].x, top, poly[j].y)
				var r1 := Vector3(cap[j].x, top + rise, cap[j].y)
				var r0 := Vector3(cap[i].x, top + rise, cap[i].y)
				var fn := (r0 - e0).cross(e1 - e0).normalized()
				if fn.y < 0.0:
					fn = -fn
				var rb := v.size()
				v.append_array([e0, e1, r1, r0])
				uv.append_array([Vector2(e0.x, e0.z), Vector2(e1.x, e1.z), Vector2(r1.x, r1.z), Vector2(r0.x, r0.z)])
				for k in 4:
					n.append(fn)
					uv2.append(Vector2(h, seed * 0.5))
					col.append(tint)
				idx.append_array([rb, rb + 1, rb + 2, rb, rb + 2, rb + 3])
			top += rise
		var tris := Geometry2D.triangulate_polygon(cap)
		var base := v.size()
		for p in cap:
			v.append(Vector3(p.x, top, p.y))
			n.append(Vector3.UP)
			uv.append(p)
			uv2.append(Vector2(h, seed * 0.5 if cap != poly else 0.5 + seed * 0.5))
			col.append(tint)
		for t in range(0, tris.size(), 3):
			var p0 := cap[tris[t]]
			var p1 := cap[tris[t + 1]]
			var p2 := cap[tris[t + 2]]
			if (p1 - p0).cross(p2 - p0) > 0.0:
				idx.append_array([base + tris[t], base + tris[t + 1], base + tris[t + 2]])
			else:
				idx.append_array([base + tris[t], base + tris[t + 2], base + tris[t + 1]])
	for key in chunks:
		var ch: Array = chunks[key]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = ch[0]
		arr[Mesh.ARRAY_NORMAL] = ch[1]
		arr[Mesh.ARRAY_TEX_UV] = ch[2]
		arr[Mesh.ARRAY_TEX_UV2] = ch[3]
		arr[Mesh.ARRAY_COLOR] = ch[4]
		arr[Mesh.ARRAY_INDEX] = ch[5]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		# Gorunen kopya delinebilir; golgeyi delinmeyen ayri bir kopya duşurur
		Kit.add(self, mesh, mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Kit.add(self, mesh, Kit.mat("d9d2c4")).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


## Balkon: doseme ve uc tarafi kapali korkuluk. UV2.x = -1 shader'a "duz renk" der.
func _balcony(ch: Array, at_pos: Vector3, along: Vector3, out: Vector3, tint: Color) -> void:
	var v: PackedVector3Array = ch[0]
	var n: PackedVector3Array = ch[1]
	var uv: PackedVector2Array = ch[2]
	var uv2: PackedVector2Array = ch[3]
	var col: PackedColorArray = ch[4]
	var idx: PackedInt32Array = ch[5]
	var up := Vector3.UP
	var quad := func(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nn: Vector3, c: Color) -> void:
		var base := v.size()
		v.append_array([p0, p1, p2, p3])
		for k in 4:
			n.append(nn)
			uv.append(Vector2.ZERO)
			uv2.append(Vector2(-1.0, 0.0))
			col.append(c)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3, base, base + 2, base + 1, base, base + 3, base + 2])
	var w := 1.25
	var dep := 1.05
	var slab := Color(0.72, 0.71, 0.68)
	var rail := tint.darkened(0.12)
	var a0 := at_pos - along * w
	var a1 := at_pos + along * w
	var b0 := a0 + out * dep
	var b1 := a1 + out * dep
	# Doseme (ust, alt, on)
	quad.call(a0, a1, b1, b0, up, slab)
	quad.call(a0 - up * 0.14, a1 - up * 0.14, b1 - up * 0.14, b0 - up * 0.14, -up, slab.darkened(0.35))
	quad.call(b0 - up * 0.14, b1 - up * 0.14, b1, b0, out, slab)
	# Korkuluk: on ve iki yan
	var hgt := up * 0.95
	quad.call(b0, b1, b1 + hgt, b0 + hgt, out, rail)
	quad.call(a0, b0, b0 + hgt, a0 + hgt, -along, rail)
	quad.call(a1, b1, b1 + hgt, a1 + hgt, along, rail)


func _mosque(poly: PackedVector2Array, c: Vector2, size: float, h: float) -> void:
	var lead := Kit.mat("8fa9b5", 0.5)
	var stone := Kit.mat("e6e1d6")
	Kit.ball(self, size * 0.75, Vector3(c.x, h - size * 0.1, c.y), lead, Vector3(1, 0.8, 1), 20)
	Kit.cyl(self, 0.04, 0.2, 1.6, Vector3(c.x, h + size * 0.5 + 0.7, c.y), Kit.mat("d9b24a", 0.3), 6)
	# En uzak iki koseye minare
	var far := 0
	for i in poly.size():
		if poly[i].distance_to(poly[0]) > poly[far].distance_to(poly[0]):
			far = i
	for i in [0, far]:
		var p: Vector2 = poly[i].lerp(c, 0.12)
		var g := h - 9.0
		Kit.cyl(self, 0.75, 0.95, 24.0, Vector3(p.x, g + 12.0, p.y), stone, 10)
		Kit.cyl(self, 1.25, 1.25, 0.5, Vector3(p.x, g + 17.0, p.y), stone, 10)
		Kit.cyl(self, 0.02, 0.85, 5.0, Vector3(p.x, g + 26.5, p.y), lead, 10)


# ---------------------------------------------------------------- parcalar

func _fence(a: Vector2, b: Vector2, hex: String, h := 0.9) -> void:
	_add_segment(a, b)
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var m := Kit.mat(hex)
	var count := int(ceil(length / 1.6))
	for i in count + 1:
		var p := a + dir * (length * i / count)
		Kit.box(self, Vector3(0.14, h, 0.14), at(p, h * 0.5), m)
		Kit.box(self, Vector3(0.2, 0.06, 0.2), at(p, h + 0.03), m)
	var mid := (a + b) * 0.5
	var rot := Vector3(0, atan2(-dir.y, dir.x), atan2(gy(b) - gy(a), length))
	for k in [0.38, 0.78]:
		Kit.box(self, Vector3(length, 0.09, 0.06), at(mid, h * k), m, rot)


func _bench(p: Vector2, rot_y: float) -> void:
	_model("bank_lod", p, 1.9, rot_y)
	_add_circle(Vector3(p.x, p.y, 0.8))


func _lamp(p: Vector2) -> void:
	_model("lamba_lod", p, 3.6, 0.0, true)
	_add_circle(Vector3(p.x, p.y, 0.18))


func _umbrella_table(p: Vector2, hex: String, stools := 3) -> void:
	var t := _root(p)
	Kit.cyl(t, 0.65, 0.65, 0.06, Vector3(0, 0.75, 0), Kit.mat("ece7dc"), 16)
	Kit.cyl(t, 0.04, 0.04, 2.3, Vector3(0, 1.15, 0), Kit.mat("7d7f84"), 6)
	Kit.cyl(t, 0.02, 1.35, 0.5, Vector3(0, 2.4, 0), Kit.mat(hex), 10)
	for j in stools:
		var a := j * TAU / stools + p.x
		Kit.cyl(t, 0.22, 0.2, 0.45, Vector3(cos(a) * 1.0, 0.22, sin(a) * 1.0), Kit.mat("9a6b43"), 10)
	_add_circle(Vector3(p.x, p.y, 0.75))


func _toy(node: Node3D, p: Vector2, y: float) -> void:
	node.position = at(p, y)
	add_child(node)
	toys.append(node)


# ---------------------------------------------------------------- oyuna eklenen yerler

func _build_spots() -> void:
	for k in ParkMap.spots:
		if k != "baslangic":
			_keep_out.append([ParkMap.spots[k], ParkMap.spot_half[k] + Vector2(2, 2)])
	_build_garden()
	# Pet Shop ve kafe
	var ps := ParkMap.spot("petshop")
	_block_model(_model("petshop", ps, 12.0, 0.0), ps)
	var cf := ParkMap.spot("kafe")
	_block_model(_model("kafe", cf, 11.0, -PI / 2), cf)
	_umbrella_table(cf + Vector2(-8.0, -3.0), "8f4a3a")
	_umbrella_table(cf + Vector2(-8.0, 3.2), "c9ab7a")
	# Dondurmaci
	var k := ParkMap.spot("dondurmaci")
	_model("dondurmaci", k, 3.6, 0.0)
	_add_circle(Vector3(k.x, k.y, 2.3))
	_umbrella_table(k + Vector2(-4.0, 2.6), "d9a441")
	# Cardak
	var g := ParkMap.spot("cardak")
	_model("cardak", g, 6.4, 0.0)
	for i in 6:
		var a := i * TAU / 6.0 + PI / 6.0
		_add_circle(Vector3(g.x + cos(a) * 2.7, g.y + sin(a) * 2.7, 0.25))
	for i in 160:
		var a := _rng.randf() * TAU
		_flower(at(g + Vector2(cos(a), sin(a)) * _rng.randf_range(4.4, 6.4)), Color(FLOWER_COLORS[int(a / TAU * 4.0) + 1]), _rng.randf_range(0.9, 1.3))
	# Cesme ve cevresi
	var f := ParkMap.spot("cesme")
	_model("cesme", f, 5.0, 0.0)
	_add_circle(Vector3(f.x, f.y, 2.6))
	for deg in [40.0, 140.0, 220.0, 320.0]:
		var a := deg_to_rad(deg)
		var p := f + Vector2(cos(a), sin(a)) * 5.2
		_bench(p, atan2(-cos(a), -sin(a)))
	# Piknik
	var pk := ParkMap.spot("piknik")
	var r := _root(pk, 0.3)
	Kit.box(r, Vector3(2.8, 0.03, 2.1), Vector3(0, 0.03, 0), Kit.checker(Color("b8433a"), Color("ece6d8"), 8, 6))
	Kit.box(r, Vector3(0.6, 0.34, 0.42), Vector3(-0.7, 0.2, -0.3), Kit.mat("b48a55"))
	Kit.torus(r, 0.2, 0.24, Vector3(-0.7, 0.4, -0.3), Kit.mat("8a5a35"), Vector3(PI / 2, 0, 0))
	Kit.ball(r, 0.09, Vector3(0.1, 0.12, 0.3), Kit.mat("c8452f", 0.4))
	Kit.cyl(r, 0.22, 0.22, 0.03, Vector3(0.7, 0.06, -0.4), Kit.mat("ece6d8", 0.3))
	_tree_fixed.append([pk + Vector2(-3.4, -1.8), 7.0, 0])
	_build_play_area()


## Hayvanlarin bahcesi: kulube, mama kaplari, havuz, kedi agaci, sebze tarhi, oyuncaklar.
func _build_garden() -> void:
	var b := ParkMap.spot("bahce")
	var h: Vector2 = ParkMap.spot_half["bahce"]
	var mn := b - h
	var mx := b + h
	var hex := "ece6d8"
	_fence(mn, Vector2(mx.x, mn.y), hex)
	_fence(mn, Vector2(mn.x, b.y - 1.5), hex)      # bati kenarinda da kapi
	_fence(Vector2(mn.x, b.y + 1.5), Vector2(mn.x, mx.y), hex)
	_fence(Vector2(mn.x, mx.y), mx, hex)
	_fence(Vector2(mx.x, mn.y), Vector2(mx.x, b.y - 1.5), hex)
	_fence(Vector2(mx.x, b.y + 1.5), mx, hex)
	for z in [b.y - 1.5, b.y + 1.5]:
		Kit.box(self, Vector3(0.2, 2.4, 0.2), at(Vector2(mx.x, z), 1.2), Kit.mat("7d5236"))
	Kit.box(self, Vector3(0.22, 0.4, 3.4), at(Vector2(mx.x, b.y), 2.5), Kit.mat("9a6b43"))
	var wood := Kit.mat("7d5236")
	kennel_pos = b + Vector2(-5.5, -7.0)
	_model("kulube", kennel_pos, 2.3, 0.6)
	_add_circle(Vector3(kennel_pos.x, kennel_pos.y, 1.25))
	bowl_pos = b + Vector2(-1.5, -9.8)
	for i in 2:
		var bw := _root(bowl_pos + Vector2(i * 0.75, 0))
		Kit.cyl(bw, 0.24, 0.3, 0.13, Vector3(0, 0.065, 0), Kit.mat(["b8433a", "3f6fa8"][i], 0.4))
		Kit.cyl(bw, 0.2, 0.2, 0.02, Vector3(0, 0.125, 0), Kit.mat(["8a5a35", "7fb9d6"][i], 0.3))
	pool_pos = b + Vector2(4.5, 7.0)
	var pool := _root(pool_pos)
	Kit.cyl(pool, 1.7, 1.7, 0.42, Vector3(0, 0.21, 0), Kit.mat("3f6fa8", 0.5), 22)
	Kit.cyl(pool, 1.55, 1.55, 0.04, Vector3(0, 0.41, 0), Kit.mat("7fc4d9", 0.1), 22)
	Kit.ball(pool, 0.16, Vector3(0.5, 0.5, 0.3), Kit.mat("f2c94c", 0.4))
	_add_circle(Vector3(pool_pos.x, pool_pos.y, 1.75))
	# Kedi tirmalama agaci
	var cp := b + Vector2(6.8, -8.5)
	var ct := _root(cp)
	var rope := Kit.mat("c9ab7a")
	var felt := Kit.mat("8f7f9e")
	Kit.box(ct, Vector3(1.1, 0.1, 1.1), Vector3(0, 0.05, 0), felt)
	Kit.cyl(ct, 0.09, 0.09, 1.5, Vector3(-0.3, 0.8, 0), rope, 8)
	Kit.cyl(ct, 0.09, 0.09, 0.8, Vector3(0.3, 0.45, 0.1), rope, 8)
	Kit.box(ct, Vector3(0.7, 0.08, 0.7), Vector3(0.3, 0.88, 0.1), felt)
	Kit.box(ct, Vector3(0.6, 0.08, 0.6), Vector3(-0.3, 1.58, 0), felt)
	Kit.ball(ct, 0.07, Vector3(-0.55, 1.14, 0.2), Kit.mat("d95f76"))
	_add_circle(Vector3(cp.x, cp.y, 0.7))
	# Sebze tarhi
	var vp := b + Vector2(-4.5, 9.6)
	var bed := _root(vp)
	Kit.box(bed, Vector3(4.6, 0.22, 2.0), Vector3(0, 0.11, 0), wood)
	Kit.box(bed, Vector3(4.4, 0.06, 1.8), Vector3(0, 0.22, 0), Kit.mat("4d3a2a"))
	for i in 14:
		var px := -1.9 + (i % 7) * 0.63
		var pz := -0.45 + (i / 7) * 0.9
		Kit.ball(bed, 0.16, Vector3(px, 0.33, pz), Kit.mat(["4c8a3f", "6aa84f"][i % 2]), Vector3(1, 0.8, 1), 8)
		if i % 3 == 0:
			Kit.ball(bed, 0.07, Vector3(px + 0.08, 0.42, pz), Kit.mat("d2452f", 0.4), Vector3.ONE, 6)
	_block(vp, Vector2(2.3, 1.0))
	_tree_fixed.append([b + Vector2(-7.5, 2.5), 7.0, 0])
	# Oyuncaklar
	var cols := ["c8452f", "e9b93a", "3f6fa8"]
	for i in 3:
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.26
		ball.mesh = sm
		ball.material_override = Kit.mat(cols[i], 0.5)
		_toy(ball, b + Vector2(-2.5 + i * 2.3, -2.0 + (i % 2) * 1.6), 0.13)
	var bone := Node3D.new()
	Kit.capsule(bone, 0.05, 0.36, Vector3.ZERO, Kit.mat("efe6d2"), Vector3(0, 0, PI / 2))
	for sx in [-0.17, 0.17]:
		Kit.ball(bone, 0.075, Vector3(sx, 0, 0.045), Kit.mat("efe6d2"))
		Kit.ball(bone, 0.075, Vector3(sx, 0, -0.045), Kit.mat("efe6d2"))
	_toy(bone, b + Vector2(1.5, 2.5), 0.08)
	var frisbee := Node3D.new()
	Kit.cyl(frisbee, 0.22, 0.24, 0.04, Vector3.ZERO, Kit.mat("d95f76", 0.4), 16)
	_toy(frisbee, b + Vector2(-4.0, -2.5), 0.03)
	yarn_pos = b + Vector2(6.0, -4.5)
	var basket := _root(yarn_pos + Vector2(1.0, 0.4))
	Kit.cyl(basket, 0.42, 0.34, 0.3, Vector3(0, 0.15, 0), Kit.mat("b48a55"), 12)
	for i in 3:
		Kit.ball(basket, 0.14, Vector3(cos(i * 2.1) * 0.18, 0.34, sin(i * 2.1) * 0.18), Kit.mat(["d95f76", "6b8fd6", "f2c94c"][i], 0.9), Vector3.ONE, 10)
	for i in 70:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_flower(at(Vector2(b.x + _rng.randf_range(-h.x + 0.6, h.x - 0.6), b.y + side * _rng.randf_range(h.y - 1.0, h.y - 0.3))), Color(FLOWER_COLORS[_rng.randi() % 6]))


func _build_play_area() -> void:
	var c := ParkMap.spot("oyun_alani")
	var h: Vector2 = ParkMap.spot_half["oyun_alani"]
	var mn := c - h
	var mx := c + h
	var hex := "a8774a"
	_fence(mn, Vector2(mx.x, mn.y), hex)
	_fence(mn, Vector2(mn.x, mx.y), hex)
	_fence(Vector2(mn.x, mx.y), mx, hex)
	_fence(Vector2(mx.x, mn.y), Vector2(mx.x, c.y - 1.4), hex)
	_fence(Vector2(mx.x, c.y + 1.4), mx, hex)
	for z in [c.y - 1.4, c.y + 1.4]:
		Kit.box(self, Vector3(0.2, 2.6, 0.2), at(Vector2(mx.x, z), 1.3), Kit.mat("b8433a"))
	Kit.box(self, Vector3(0.24, 0.5, 3.2), at(Vector2(mx.x, c.y), 2.7), Kit.mat("e0b23e"))
	var cols := ["b8433a", "e0b23e", "3f6fa8"]
	for i in 3:
		var p := c + Vector2(-4.5 + i * 2.6, -4.2)
		var r := _root(p)
		Kit.box(r, Vector3(0.1, 0.6, 0.1), Vector3(0, 0.3, 0), Kit.mat("ece6d8"))
		Kit.torus(r, 0.5, 0.62, Vector3(0, 1.15 + i * 0.12, 0), Kit.mat(cols[i], 0.5), Vector3(0, 0, PI / 2))
		_add_circle(Vector3(p.x, p.y, 0.12))
	var rp := c + Vector2(3.5, 1.0)
	var ramp := _root(rp, 0.4)
	Kit.box(ramp, Vector3(1.2, 0.1, 2.3), Vector3(0, 0.55, -0.98), Kit.mat("e0b23e"), Vector3(0.52, 0, 0))
	Kit.box(ramp, Vector3(1.2, 0.1, 2.3), Vector3(0, 0.55, 0.98), Kit.mat("3f6fa8"), Vector3(-0.52, 0, 0))
	_add_circle(Vector3(rp.x, rp.y, 1.2))
	var tube := StandardMaterial3D.new()
	tube.albedo_color = Color("4f9a76")
	tube.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tm := CylinderMesh.new()
	tm.top_radius = 0.6
	tm.bottom_radius = 0.6
	tm.height = 2.6
	tm.cap_top = false
	tm.cap_bottom = false
	var tp := c + Vector2(-3.0, 3.6)
	Kit.add(self, tm, tube, at(tp, 0.58), Vector3(0, 0.3, PI / 2))
	_add_circle(Vector3(tp.x, tp.y, 1.0))
	for i in 5:
		var p := c + Vector2(1.0 + i * 0.9, 4.8)
		Kit.cyl(self, 0.05, 0.05, 1.1, at(p, 0.55), Kit.mat(cols[i % 3], 0.5), 8)
		_add_circle(Vector3(p.x, p.y, 0.08))


func _build_pitches() -> void:
	var white := Kit.mat("f2f2ee")
	for it in ParkMap.data["pitches"]:
		var poly := ParkMap.to_poly(it["p"])
		var c := Vector2.ZERO
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			c += a
			var d := b - a
			Kit.box(self, Vector3(d.length(), 0.03, 0.18), at((a + b) * 0.5, 0.02), white, Vector3(0, atan2(-d.y, d.x), 0))
		c /= poly.size()
		for i in 24:
			var a := i * TAU / 24.0
			Kit.box(self, Vector3(2.4, 0.03, 0.18), at(c + Vector2(cos(a), sin(a)) * 9.0, 0.02), white, Vector3(0, -a + PI / 2, 0))


# ---------------------------------------------------------------- sokaklar

func _build_streets() -> void:
	# Ana caddelerde lamba, sokaklarda kaldirim agaci
	var nodes := ParkMap.nodes
	var side := 1.0
	for r in ParkMap.data["roads"]:
		var w: float = r["w"]
		var big := w >= 8.0
		var gap := 34.0 if big else 30.0
		var carry := gap * 0.5
		var ids: Array = r["n"]
		for i in ids.size() - 1:
			var a := nodes[int(ids[i])]
			var b := nodes[int(ids[i + 1])]
			var length := a.distance_to(b)
			if length < 0.5:
				continue
			var dir := (b - a) / length
			var perp := Vector2(-dir.y, dir.x)
			while carry < length:
				side = -side
				var p := a + dir * carry + perp * side * (w * 0.5 + 1.4)
				carry += gap
				if not ParkMap.inside_bounds(p, 4.0) or _mask(p)[2] > 0.5 or not is_free(p, 0.5):
					continue
				if big or side > 0.0:
					_street_lamps.append(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y) + (PI / 2 if side > 0.0 else -PI / 2)), at(p)))
					_add_circle(Vector3(p.x, p.y, 0.15))
				else:
					_tree_fixed.append([p, _rng.randf_range(4.5, 6.5), 0])
			carry -= length


# ---------------------------------------------------------------- tabelalar ve ayrintilar

const SIGN_STYLE := {   # tur: [levha rengi, yazi rengi, harf]
	"eczane": ["c8322b", "ffffff", "E"], "market": ["e07b1f", "ffffff", ""], "yemek": ["7a4a2b", "fff3d6", ""],
	"banka": ["1f3f7a", "ffffff", ""], "akaryakit": ["1e6b45", "ffffff", ""], "taksi": ["f2c230", "2b2b2e", "T"],
	"kargo": ["8a5a2b", "ffffff", ""], "polis": ["1f2f5a", "ffffff", ""], "muze": ["6b4a8a", "ffffff", ""],
	"okul": ["c9962e", "2b2b2e", ""], "dukkan": ["3f6f78", "ffffff", ""], "ofis": ["5b5f66", "ffffff", ""],
	"spor": ["3f7a4a", "ffffff", ""], "durak": ["1a4fa0", "ffffff", "D"], "metro": ["c8322b", "ffffff", "M"],
}


func _text(parent: Node3D, text: String, pos: Vector3, color: Color, size := 0.26) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size / 64.0 * 1.35
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = pos
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.visibility_range_end = 75.0
	parent.add_child(l)
	return l


## Guneye (kameraya) bakan yazili levha. Direkli ya da duvara asili.
func _sign(p: Vector2, text: String, plate: String, ink: String, height := 2.7, pole := true, size := 0.26, badge := "") -> Node3D:
	var r := _root(p)
	var w := maxf(text.length() * size * 0.62 + 0.3, 0.9)
	var hgt := size * 1.75
	if pole:
		Kit.cyl(r, 0.045, 0.055, height + hgt * 0.5, Vector3(0, (height + hgt * 0.5) * 0.5, 0), Kit.mat("6f7378", 0.5), 6)
		_add_circle(Vector3(p.x, p.y, 0.12))
	Kit.box(r, Vector3(w, hgt, 0.06), Vector3(0, height, 0.05), Kit.mat(plate, 0.6))
	Kit.box(r, Vector3(w + 0.08, hgt + 0.08, 0.03), Vector3(0, height, 0.03), Kit.mat("f2f2ee", 0.6))
	_text(r, text, Vector3(0, height, 0.09), Color(ink), size)
	if badge != "":
		Kit.box(r, Vector3(0.62, 0.62, 0.07), Vector3(0, height + hgt * 0.5 + 0.42, 0.05), Kit.mat(plate, 0.6))
		_text(r, badge, Vector3(0, height + hgt * 0.5 + 0.42, 0.1), Color(ink), 0.42)
	_signs.append(r)
	return r


## Yakindaki tabelalari kameraya dondurur (kamera artik donebiliyor).
func face_signs(cam_pos: Vector3) -> void:
	for sg in _signs:
		var d := cam_pos - sg.position
		if absf(d.x) < 90.0 and absf(d.z) < 90.0:
			sg.rotation.y = atan2(d.x, d.z)


func _build_details() -> void:
	var d: Dictionary = ParkMap.data
	# Sokak tabelalari (mavi)
	for sg in d["signs"]:
		var p := Vector2(sg["pos"][0], sg["pos"][1])
		if is_free(p, 0.3):
			_sign(p, sg["name"], "1a4fa0", "ffffff", 2.8, true, 0.2)
	# Isletmeler, duraklar, metro
	for po in d["pois"]:
		var p := Vector2(po["pos"][0], po["pos"][1])
		var st: Array = SIGN_STYLE.get(po["k"], SIGN_STYLE["dukkan"])
		var wall: bool = po["wall"]
		_sign(p, po["name"], st[0], st[1], 3.4 if wall else 2.9, not wall, 0.3, st[2])
		if po["k"] == "durak":
			_bus_shelter(p + Vector2(2.6, 0.0))
	# Adli binalar: catinin on kenarinda levha
	for b in d["buildings"]:
		var bname: String = b["name"]
		if bname == "":
			continue
		var south := Vector2(0, -1e9)
		for q in b["p"]:
			if q[1] > south.y:
				south = Vector2(q[0], q[1])
		if ParkMap.inside_bounds(south, 4.0):
			_sign(south + Vector2(0, 0.4), bname, "2f3a45", "ffffff", minf(float(b["h"]), 7.5), false, 0.42)
	# Trafik isiklari
	for sg in d["signals"]:
		var p := Vector2(sg[0], sg[1]) + Vector2(4.5, 4.5)
		var r := _root(p)
		Kit.cyl(r, 0.06, 0.08, 3.4, Vector3(0, 1.7, 0), Kit.mat("3f4750", 0.5), 8)
		Kit.box(r, Vector3(0.34, 0.95, 0.3), Vector3(0, 3.0, 0.1), Kit.mat("2b2b2e", 0.6))
		for i in 3:
			Kit.ball(r, 0.11, Vector3(0, 3.3 - i * 0.3, 0.26), Kit.glow(["e0352b", "f2c230", "3fbf5a"][i], 1.2), Vector3.ONE, 8)
		_add_circle(Vector3(p.x, p.y, 0.15))
	# Yaya gecitleri
	var white := Kit.mat("eeeeea", 0.8)
	for c in d["crossings"]:
		var p := Vector2(c["pos"][0], c["pos"][1])
		var rot: float = c["rot"]
		var along := Vector2(cos(rot), sin(rot))
		var across := Vector2(-along.y, along.x)
		var n := int(float(c["w"]) / 1.0)
		for i in n:
			var q := p + across * ((i - (n - 1) * 0.5) * 1.0)
			Kit.box(self, Vector3(3.2, 0.03, 0.5), at(q, 0.03), white, Vector3(0, -rot, 0))
	# Duvarlar ve citler (yalnizca gorsel; gecisi engellemez)
	for bar in d["barriers"]:
		var pts: Array = bar["p"]
		var wall: bool = bar["k"] == "duvar"
		var m := Kit.mat("b3ada0" if wall else "7d8088")
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var b2 := Vector2(pts[i + 1][0], pts[i + 1][1])
			var dd := b2 - a
			if dd.length() < 0.3 or not ParkMap.inside_bounds((a + b2) * 0.5):
				continue
			var mid := (a + b2) * 0.5
			var slope := atan2(gy(b2) - gy(a), dd.length())
			Kit.box(self, Vector3(dd.length() + 0.1, 1.3 if wall else 1.0, 0.25 if wall else 0.05), at(mid, 0.6), m, Vector3(0, atan2(-dd.y, dd.x), slope))
	# Kopru korkuluklari
	for br in d["bridges"]:
		var pts: Array = br["p"]
		var w: float = br["w"]
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][1])
			var b2 := Vector2(pts[i + 1][0], pts[i + 1][1])
			var dd := b2 - a
			if dd.length() < 0.5:
				continue
			var perp := Vector2(-dd.y, dd.x).normalized() * (w * 0.5 + 1.9)
			for side in [-1.0, 1.0]:
				var mid: Vector2 = (a + b2) * 0.5 + perp * side
				if ParkMap.water_sd(mid) < 3.0:
					Kit.box(self, Vector3(dd.length(), 0.12, 0.12), at(mid, 1.0), Kit.mat("d8d2c4"), Vector3(0, atan2(-dd.y, dd.x), 0))
					Kit.box(self, Vector3(dd.length(), 0.7, 0.2), at(mid, 0.35), Kit.mat("b3ada0"), Vector3(0, atan2(-dd.y, dd.x), 0))
	# Oyun parklari: salincak ve kaydirak
	for pg in d["playgrounds"]:
		var p := Vector2(pg["pos"][0], pg["pos"][1])
		_keep_out.append([p, Vector2(6, 6)])
		var r := _root(p)
		var red := Kit.mat("c8452f", 0.5)
		var blue := Kit.mat("3f6fa8", 0.5)
		for sx in [-1.6, 1.6]:
			Kit.box(r, Vector3(0.1, 2.4, 0.1), Vector3(sx, 1.2, 0), red)
		Kit.box(r, Vector3(3.4, 0.1, 0.1), Vector3(0, 2.4, 0), red)
		for sx in [-0.7, 0.7]:
			Kit.box(r, Vector3(0.02, 1.7, 0.02), Vector3(sx - 0.2, 1.55, 0), Kit.mat("8d8f92"))
			Kit.box(r, Vector3(0.02, 1.7, 0.02), Vector3(sx + 0.2, 1.55, 0), Kit.mat("8d8f92"))
			Kit.box(r, Vector3(0.5, 0.05, 0.2), Vector3(sx, 0.7, 0), blue)
		Kit.box(r, Vector3(0.9, 0.08, 2.8), Vector3(4.0, 0.9, 0.6), Kit.mat("e9b93a", 0.5), Vector3(0.55, 0, 0))
		Kit.box(r, Vector3(1.0, 1.7, 1.0), Vector3(4.0, 0.85, -1.2), blue)
		_add_circle(Vector3(p.x + 4.0, p.y - 1.2, 0.8))


func _bus_shelter(p: Vector2) -> void:
	var r := _root(p)
	var frame := Kit.mat("4a5058", 0.5)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.85, 0.92, 0.45)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for sx in [-1.5, 1.5]:
		Kit.box(r, Vector3(0.08, 2.3, 0.08), Vector3(sx, 1.15, -0.5), frame)
	Kit.box(r, Vector3(3.3, 0.08, 1.4), Vector3(0, 2.3, 0), frame)
	Kit.box(r, Vector3(3.0, 1.5, 0.04), Vector3(0, 1.3, -0.5), glass)
	Kit.box(r, Vector3(2.4, 0.08, 0.4), Vector3(0, 0.5, -0.25), Kit.mat("9a6b43"))
	_add_segment(p + Vector2(-1.5, -0.5), p + Vector2(1.5, -0.5))


func _merge(parts: Array) -> ArrayMesh:
	# parts: [mesh, transform, malzeme] -> malzemeye gore yuzeyleri birlesmis tek mesh
	var mesh := ArrayMesh.new()
	var by_mat := {}
	for part in parts:
		if not by_mat.has(part[2]):
			by_mat[part[2]] = SurfaceTool.new()
		(by_mat[part[2]] as SurfaceTool).append_from(part[0], 0, part[1])
	for m in by_mat:
		(by_mat[m] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	return mesh


func _plain(xf: Array[Transform3D]) -> Array[Color]:
	var out: Array[Color] = []
	out.resize(xf.size())
	out.fill(Color.WHITE)
	return out


## Kapilar, kapi numaralari ve apartman adlari.
func _build_doors() -> void:
	var door := BoxMesh.new()
	door.size = Vector3(1.3, 2.2, 0.12)
	var canopy := BoxMesh.new()
	canopy.size = Vector3(2.0, 0.12, 0.9)
	var step := BoxMesh.new()
	step.size = Vector3(1.8, 0.16, 0.7)
	var mesh := _merge([[door, Transform3D(Basis(), Vector3(0, 1.1, 0.02)), Kit.mat("4a3426", 0.6)],
		[canopy, Transform3D(Basis(), Vector3(0, 2.5, 0.42)), Kit.mat("8d8f92", 0.7)],
		[step, Transform3D(Basis(), Vector3(0, 0.08, 0.38)), Kit.mat("a9a59c")]])
	var xf: Array[Transform3D] = []
	for b in ParkMap.data["buildings"]:
		if not b.has("door"):
			continue
		var dd: Array = b["door"]
		var p := Vector2(dd[0], dd[1])
		if not ParkMap.inside_bounds(p, 2.0):
			continue
		var out := Vector2(dd[2], dd[3])
		xf.append(Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), at(p)))
		var label := ""
		if b["name"] != "" and b["t"] == "apartman":
			label = b["name"]
		if b["no"] != "":
			label = ("No: " + str(b["no"])) if label == "" else label + "  No: " + str(b["no"])
		if label != "":
			var q := p + out * 0.45
			var r := _root(q)
			var size := 0.17
			var w := label.length() * size * 0.6 + 0.24
			Kit.box(r, Vector3(w, size * 1.7, 0.04), Vector3(0, 2.95, 0), Kit.mat("1a4fa0", 0.6))
			_text(r, label, Vector3(0, 2.95, 0.03), Color.WHITE, size).visibility_range_end = 40.0
			_signs.append(r)
	_multimesh(mesh, xf, _plain(xf), false, 64.0, 90.0)


## Serit cizgileri, tek yon oklari, merdivenler ve sokak lambalari.
func _build_road_marks() -> void:
	var nodes := ParkMap.nodes
	var white := Kit.mat("e8e8e2", 0.8)
	var dash := BoxMesh.new()
	dash.size = Vector3(0.16, 0.02, 2.4)
	dash.material = white
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for tri in [[Vector3(-0.12, 0, 1.2), Vector3(0.12, 0, 1.2), Vector3(0.12, 0, -0.3)], [Vector3(-0.12, 0, 1.2), Vector3(0.12, 0, -0.3), Vector3(-0.12, 0, -0.3)],
			[Vector3(-0.42, 0, -0.3), Vector3(0.42, 0, -0.3), Vector3(0, 0, -1.2)]]:
		for vv in [tri[0], tri[2], tri[1], tri[0], tri[1], tri[2]]:
			st.add_vertex(vv)
	var arrow := st.commit()
	arrow.surface_set_material(0, white)
	var dxf: Array[Transform3D] = []
	var axf: Array[Transform3D] = []
	for r in ParkMap.data["roads"]:
		var ids: Array = r["n"]
		var lanes := int(r["lanes"])
		var w: float = r["w"]
		var oneway: bool = r["oneway"]
		var carry := 4.0
		var acarry := 14.0
		for i in ids.size() - 1:
			var a := nodes[int(ids[i])]
			var b := nodes[int(ids[i + 1])]
			var length := a.distance_to(b)
			if length < 0.5:
				continue
			var dir := (b - a) / length
			var perp := Vector2(-dir.y, dir.x)
			var basis := Basis(Vector3.UP, atan2(-dir.x, -dir.y))
			if lanes >= 2:
				while carry < length:
					var c := a + dir * carry
					if ParkMap.inside_bounds(c):
						for k in range(1, lanes):
							var q := c + perp * ((k - lanes * 0.5) * w * 0.8 / lanes)
							dxf.append(Transform3D(basis, at(q, 0.03)))
					carry += 6.5
				carry -= length
			if oneway:
				while acarry < length:
					var c := a + dir * acarry
					if ParkMap.inside_bounds(c):
						axf.append(Transform3D(basis.scaled(Vector3(1.5, 1, 1.5)), at(c, 0.035)))
					acarry += 42.0
				acarry -= length
	_multimesh(dash, dxf, _plain(dxf), false, 96.0, 120.0)
	_multimesh(arrow, axf, _plain(axf), false, 96.0, 120.0)

	# Merdivenli gecitler: basamaklar
	var tread := BoxMesh.new()
	tread.size = Vector3(2.3, 0.14, 0.34)
	tread.material = Kit.mat("b3ada0")
	var sxf: Array[Transform3D] = []
	for path in ParkMap.data["paths"]:
		if not path.get("steps", false):
			continue
		var ids: Array = path["n"]
		for i in ids.size() - 1:
			var a := nodes[int(ids[i])]
			var b := nodes[int(ids[i + 1])]
			var length := a.distance_to(b)
			if length < 0.3 or not ParkMap.inside_bounds((a + b) * 0.5):
				continue
			var dir := (b - a) / length
			var basis := Basis(Vector3.UP, atan2(-dir.x, -dir.y))
			var k := 0.2
			while k < length:
				sxf.append(Transform3D(basis, at(a + dir * k, 0.05)))
				k += 0.4
	_multimesh(tread, sxf, _plain(sxf), false, 64.0, 90.0)

	# Sokak lambasi: direk, kol ve armatur
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.1
	pole.height = 7.0
	pole.radial_segments = 6
	var arm := BoxMesh.new()
	arm.size = Vector3(0.08, 0.08, 1.6)
	var head := BoxMesh.new()
	head.size = Vector3(0.3, 0.1, 0.6)
	var grey := Kit.mat("7d8088", 0.5)
	var lamp := _merge([[pole, Transform3D(Basis(), Vector3(0, 3.5, 0)), grey], [arm, Transform3D(Basis(), Vector3(0, 6.95, -0.75)), grey],
		[head, Transform3D(Basis(), Vector3(0, 6.9, -1.6)), Kit.glow("fff3d0", 0.6)]])
	_multimesh(lamp, _street_lamps, _plain(_street_lamps), false, 96.0, 140.0)


## Park halindeki arabalar (dar sokaklarda yol kenarinda).
func _build_cars() -> void:
	if not ResourceLoader.exists("res://assets/models/araba_lod.glb"):
		return
	var inst: Node3D = _scene("araba_lod").instantiate()
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var local := Transform3D()
	var nd: Node = mi
	while nd != inst:
		local = (nd as Node3D).transform * local
		nd = nd.get_parent()
	var box := local * mi.mesh.get_aabb()
	var k := 4.1 / maxf(box.size.x, box.size.z)
	var c := box.get_center()
	# Bu modelin onu +Z'ye bakar; oyunda on = -Z
	car_base = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * k), Vector3.ZERO) * Transform3D(Basis(), Vector3(-c.x, -box.position.y, -c.z)) * local
	var m := StandardMaterial3D.new()
	m.albedo_texture = (mi.get_active_material(0) as BaseMaterial3D).albedo_texture
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.45
	m.metallic = 0.1
	car_mesh = mi.mesh.duplicate()
	car_mesh.surface_set_material(0, m)
	inst.free()
	var paints := ["f2f2f2", "d9d9d9", "9a9da3", "3a3d42", "b23a34", "2f4f8a", "e9e4d6", "6b7a5a", "1f2a44"]
	var xf: Array[Transform3D] = []
	var col: Array[Color] = []
	var nodes := ParkMap.nodes
	for r in ParkMap.data["roads"]:
		var w: float = r["w"]
		if w > 9.0 or w < 5.0:
			continue
		var ids: Array = r["n"]
		for i in ids.size() - 1:
			var a := nodes[int(ids[i])]
			var b := nodes[int(ids[i + 1])]
			var length := a.distance_to(b)
			if length < 16.0:
				continue
			var dir := (b - a) / length
			var perp := Vector2(-dir.y, dir.x)
			var s := 8.0
			while s < length - 8.0:
				for side in [-1.0, 1.0]:
					if _rng.randf() < 0.3:
						var p: Vector2 = a + dir * (s + _rng.randf_range(-0.6, 0.6)) + perp * side * (w * 0.5 - 0.2)
						if not ParkMap.inside_bounds(p, 4.0) or ParkMap.water_sd(p) < 3.0:
							continue
						var slope := atan2(gy(p + dir * 2.0) - gy(p - dir * 2.0), 4.0)
						var facing := dir if side > 0.0 else -dir
						var basis := Basis(Vector3.UP, atan2(-facing.x, -facing.y)) * Basis(Vector3.RIGHT, slope * (1.0 if side > 0.0 else -1.0))
						xf.append(Transform3D(basis, at(p)) * car_base)
						col.append(Color(paints[_rng.randi() % paints.size()]))
						_add_circle(Vector3(p.x + dir.x * 1.0, p.y + dir.y * 1.0, 0.95))
						_add_circle(Vector3(p.x - dir.x * 1.0, p.y - dir.y * 1.0, 0.95))
				s += 5.6
	_multimesh(car_mesh, xf, col, true, 64.0, 110.0)


## Hareketli araba icin govde uretir.
func make_car(paint: Color) -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = car_mesh
	mi.transform = car_base
	var m: StandardMaterial3D = car_mesh.surface_get_material(0).duplicate()
	m.vertex_color_use_as_albedo = false
	m.albedo_color = paint
	mi.material_override = m
	holder.add_child(mi)
	return holder


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
		view_range := 0.0, custom: Array[Color] = [], shadow_only := false) -> void:
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
		if shadow_only:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		if view_range > 0.0:
			mi.visibility_range_end = view_range + cell * 0.7
		add_child(mi)


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
	_see_through.append(m)
	var mesh: Mesh = mi.mesh.duplicate()
	mesh.surface_set_material(0, m)
	# Golge icin delinmeyen kopya
	var sm: ShaderMaterial = m.duplicate()
	var shadow_mesh: Mesh = mi.mesh.duplicate()
	shadow_mesh.surface_set_material(0, sm)
	inst.free()
	return [mesh, base, shadow_mesh]


func _random_in(poly: PackedVector2Array, box: Rect2) -> Vector2:
	for i in 30:
		var p := Vector2(_rng.randf_range(box.position.x, box.end.x), _rng.randf_range(box.position.y, box.end.y))
		if Geometry2D.is_point_in_polygon(p, poly):
			return p
	return box.get_center()


func _build_parks() -> void:
	var kinds := [_tree_kind("agac_lod"), _tree_kind("cam_lod")]
	var xf: Array = [[] as Array[Transform3D], [] as Array[Transform3D]]
	var col: Array = [[] as Array[Color], [] as Array[Color]]
	var cus: Array = [[] as Array[Color], [] as Array[Color]]
	var spots: Array[Vector2] = []
	var tints := ["ffffff", "e4f0d0", "fff2c4", "d6e8d0", "f4ffd9"]

	var plant := func(p: Vector2, height: float, kind: int, tint: Color) -> void:
		var base: Transform3D = kinds[kind][1]
		height *= 1.35 if kind == 0 else 1.5      # gercek agac boylari
		var ground := gy(p) - 0.08
		xf[kind].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * height), Vector3(p.x, ground, p.y)) * base)
		col[kind].append(tint)
		cus[kind].append(Color(ground, height, 0, 0))
		spots.append(p)
		if ParkMap.inside_bounds(p):
			_add_circle(Vector3(p.x, p.y, 0.45))

	for f in _tree_fixed:
		plant.call(f[0], f[1], f[2], Color.WHITE)

	# Park agaclari
	for park in ParkMap.data["parks"]:
		var poly := ParkMap.to_poly(park["p"])
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		var want := mini(int(box.get_area() * 0.5 / 110.0), 900)
		for i in want:
			var p := _random_in(poly, box)
			if not _is_lawn(p) or _kept_out(p) or ParkMap.water_sd(p) < 2.5 or _mask(p)[0] > 0.36:
				continue
			var near := false
			for s in spots:
				if absf(s.x - p.x) < 4.5 and absf(s.y - p.y) < 4.5:
					near = true
					break
			if near:
				continue
			var pine := _rng.randf() < 0.25
			plant.call(p, _rng.randf_range(5.5, 8.5) * (1.1 if pine else 1.0), 1 if pine else 0, Color(tints[_rng.randi() % tints.size()]))
		# Patika kenarinda banklar ve lambalar
	var nodes := ParkMap.nodes
	var count := 0
	for path in ParkMap.data["paths"]:
		var ids: Array = path["n"]
		var carry := 18.0
		for i in ids.size() - 1:
			var a := nodes[int(ids[i])]
			var b := nodes[int(ids[i + 1])]
			var length := a.distance_to(b)
			if length < 0.5:
				continue
			var dir := (b - a) / length
			var perp := Vector2(-dir.y, dir.x)
			while carry < length:
				count += 1
				var s := 1.0 if count % 2 == 0 else -1.0
				var p := a + dir * carry + perp * s * 2.1
				carry += 26.0
				if not _is_lawn(p) or _kept_out(p, 0.5) or not is_free(p, 0.9):
					continue
				if count % 3 == 0:
					_lamp(p)
				else:
					_bench(p, atan2(-perp.x * s, -perp.y * s))
			carry -= length

	# Binalar arasinda seyrek agaclar
	var mn := ParkMap.BOUNDS_MIN - Vector2(60, 60)
	var mx := ParkMap.BOUNDS_MAX + Vector2(60, 60)
	for i in 5200:
		var p := Vector2(_rng.randf_range(mn.x, mx.x), _rng.randf_range(mn.y, mx.y))
		var m := _mask(p)
		if m[2] > 0.38 or m[3] > 0.4 or m[4] < 0.6 or resolve(p, 2.2, p).distance_to(p) > 0.05:
			continue
		var near := false
		for s in spots:
			if absf(s.x - p.x) < 6.0 and absf(s.y - p.y) < 6.0:
				near = true
				break
		if near or _inside_building(p):
			continue
		plant.call(p, _rng.randf_range(4.5, 7.0), 1 if _rng.randf() < 0.3 else 0, Color(tints[_rng.randi() % tints.size()]))
	for k in 2:
		_multimesh(kinds[k][0], xf[k], col[k], false, 40.0, 0.0, cus[k])
		_multimesh(kinds[k][2], xf[k], col[k], true, 40.0, 0.0, cus[k], true)


func _inside_building(p: Vector2) -> bool:
	# Engel dogrularina cok yakin degilse ve cevresi kapaliysa bina icidir: dort yone isin atarak say
	var hits := 0
	var list: Array = _hash.get(Vector2i(floori(p.x / CELL), floori(p.y / CELL)), [])
	for e in list:
		if e.x == 1:
			var s: Array = _segments[e.y]
			var a: Vector2 = s[0]
			var b: Vector2 = s[1]
			if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
				hits += 1
	return hits % 2 == 1


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


func _build_plants() -> void:
	var gxf: Array[Transform3D] = []
	var gcol: Array[Color] = []
	var gcols := ["4f8a3a", "6a9c44", "436f33", "7a9a48"]
	var rxf: Array[Transform3D] = []
	var rcol: Array[Color] = []
	for park in ParkMap.data["parks"]:
		var poly := ParkMap.to_poly(park["p"])
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		var n := mini(int(box.get_area() * 0.55), 70000)
		for i in n:
			var p := Vector2(_rng.randf_range(box.position.x, box.end.x), _rng.randf_range(box.position.y, box.end.y))
			if not _is_lawn(p):
				continue
			var r := _rng.randf()
			if r < 0.55:
				var gs := _rng.randf_range(0.6, 1.1)
				gxf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(gs, gs, gs)), Vector3(p.x, gy(p), p.y)))
				gcol.append(Color(gcols[_rng.randi() % 4]))
			elif r < 0.6 and not _kept_out(p, 0.0):
				_flower(at(p), Color(FLOWER_COLORS[_rng.randi() % 6]))
			elif r < 0.607 and not _kept_out(p) and is_free(p, 1.0):
				_bush(p, _rng.randf_range(0.6, 1.2))
			elif r < 0.61 and ParkMap.water_sd(p) < 3.0 and not _kept_out(p):
				var s := _rng.randf_range(0.25, 0.8)
				rxf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * 0.65, s * 0.8)), at(p, s * 0.15)))
				rcol.append(Color(["8d8f92", "7f8184", "9a968c"][_rng.randi() % 3]))
				if s > 0.5:
					_add_circle(Vector3(p.x, p.y, s * 0.8))
	_multimesh(_grass_mesh(), gxf, gcol, false, 24.0, 34.0)
	_multimesh(_flower_mesh(), _flower_xf, _flower_col, false, 32.0, 46.0)
	var bush := ArrayMesh.new()
	_blob_mesh([[Vector3(0, 0.42, 0), Vector3.ONE * 0.62], [Vector3(0.5, 0.33, 0.1), Vector3.ONE * 0.45],
		[Vector3(-0.45, 0.36, -0.12), Vector3.ONE * 0.5]], 8).commit(bush)
	bush.surface_set_material(0, _foliage(0.0, 1.0, 0.03))
	_multimesh(bush, _bush_xf, _bush_col, true, 40.0, 70.0)
	var rock := ArrayMesh.new()
	_blob_mesh([[Vector3.ZERO, Vector3.ONE]], 7).commit(rock)
	var rm := StandardMaterial3D.new()
	rm.vertex_color_use_as_albedo = true
	rm.vertex_color_is_srgb = true
	rm.roughness = 1.0
	rock.surface_set_material(0, rm)
	_multimesh(rock, rxf, rcol, true, 48.0, 80.0)


func _build_pond_life() -> void:
	var rxf: Array[Transform3D] = []
	var rcol: Array[Color] = []
	for wi in ParkMap.water.size():
		var box: Rect2 = ParkMap.water_boxes[wi]
		var tries := 0
		var reeds := 0
		while reeds < 60 and tries < 6000:
			tries += 1
			var p := Vector2(_rng.randf_range(box.position.x, box.end.x), _rng.randf_range(box.position.y, box.end.y))
			var sd := ParkMap.water_sd(p)
			if sd > 0.15 and sd < 0.6:
				rxf.append(_xf(p, _rng.randf_range(0.8, 1.3), -0.1))
				rcol.append(Color.WHITE)
				reeds += 1
		var pads := 0
		tries = 0
		while pads < 12 and tries < 2000:
			tries += 1
			var p := Vector2(_rng.randf_range(box.position.x, box.end.x), _rng.randf_range(box.position.y, box.end.y))
			if ParkMap.water_sd(p) > -1.6 or not ParkMap.inside_bounds(p):
				continue
			Kit.cyl(self, 0.38, 0.38, 0.02, at(p, ParkMap.WATER_LIFT + 0.02), Kit.mat("4c8a3f"), 10)
			if pads % 2 == 0:
				Kit.ball(self, 0.12, at(p + Vector2(0.1, 0), ParkMap.WATER_LIFT + 0.1), Kit.mat("e88fb0"), Vector3(1, 0.7, 1), 8)
			pads += 1
		# Ordekler: suyun icinde bir noktanin cevresinde yuzerler
		var poly: PackedVector2Array = ParkMap.water[wi]
		for i in 3:
			var c := _random_in(poly, box.grow(-8.0))
			if not ParkMap.inside_bounds(c) or ParkMap.water_sd(c) > -2.0:
				continue
			var radius := clampf(-ParkMap.water_sd(c) - 1.5, 0.5, 6.0)
			var d := Node3D.new()
			add_child(d)
			var white := Kit.mat("f2efe6" if i % 3 < 2 else "d9c46a")
			Kit.ball(d, 1.0, Vector3(0, 0.08, 0), white, Vector3(0.17, 0.14, 0.26), 10)
			Kit.ball(d, 0.09, Vector3(0, 0.25, -0.17), white, Vector3.ONE, 10)
			Kit.box(d, Vector3(0.07, 0.03, 0.1), Vector3(0, 0.23, -0.28), Kit.mat("d98a3a"))
			_ducks.append([d, c, radius, i * 2.1])
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


func _build_clouds() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.emission_enabled = true
	m.emission = Color("dfe9f5")
	m.emission_energy_multiplier = 0.45
	var mesh := ArrayMesh.new()
	_blob_mesh([[Vector3(0, 0, 0), Vector3(5, 2.4, 3.4)], [Vector3(4, -0.4, 0.5), Vector3(3.6, 1.8, 2.6)],
		[Vector3(-4.2, -0.5, -0.4), Vector3(3.8, 1.7, 2.8)], [Vector3(1.4, 1.4, -0.3), Vector3(3, 1.8, 2.4)]]).commit(mesh)
	for i in 22:
		var c := Kit.add(self, mesh, m, Vector3(_rng.randf_range(-700, 700), _rng.randf_range(70, 110), _rng.randf_range(-900, 200)))
		c.scale = Vector3.ONE * _rng.randf_range(1.5, 3.5)
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
		var dp: Vector2 = c + Vector2(cos(a), sin(a)) * float(d[2])
		node.position = at(dp, ParkMap.WATER_LIFT + sin(_t * 2.0 + d[3]) * 0.015)
		node.rotation.y = -a + PI
	for c in _clouds:
		c.position.x += dt * 0.8
		if c.position.x > 720.0:
			c.position.x = -720.0
