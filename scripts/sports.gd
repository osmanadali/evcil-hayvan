extends Node
## Spor alani: parkta bos bir cimenlige kurulan kafesli hali saha ve yaninda yarim basket sahasi.
## Hali saha: fizikli top (RigidBody3D), yuruyerek surme, F ile sut, gol algilama, iki kaleci ve
## iki kirmizi formali oyuncu (topu kovalar, paslasir, sut ceker), "Maça Katıl" ile 5 dakikalik mac.
## Basket: zamanlama cubuguyla sut (yesil bolge mesafeye gore daralir), basket sayaci ve
## 10 atislik "Serbest Atış Yarışması" (rekor state.d["sp_ft_record"] icinde saklanir).
## Yer secimi dunya kurulurken yapilir (pick_site): agac ve cim o alana ekilmez.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PersonModel = preload("res://scripts/person_model.gd")

const LOT := Vector2(24.0, 12.0)       # tum alanin yari boyutu (yerel x uzun kenar)
const FC := Vector2(-8.5, 0.0)         # hali saha merkezi (yerel)
const FH := Vector2(14.0, 9.0)         # cizgilerin yari boyutu
const FCAGE := Vector2(15.6, 10.0)     # kafesin yari boyutu
const GW := 2.5                        # kale yari genisligi
const GH := 2.1                        # kale yuksekligi
const BC := Vector2(16.0, 0.0)         # basket sahasi merkezi
const BH := Vector2(6.5, 7.5)
const HOOP := Vector2(20.8, 0.0)       # cember merkezi
const RIM_H := 3.05
const FT := Vector2(16.2, 0.0)         # serbest atis noktasi (cembere 4.6 m)
const BOARD := Vector2(11.2, 5.6)      # yarisma panosu
const LIFT := 0.06
const PX := 16.0                       # zemin dokusu: piksel / metre
const BALL_R := 0.11
const MATCH_SECS := 300.0
const FT_SHOTS := 10
const SITE_NAME := "Çamlık Halı Saha"

var m: Node
var state: Node
var root: Node3D
var c := Vector2.ZERO
var ang := 0.0

var _body: StaticBody3D
var _steel: StandardMaterial3D
var _net: StandardMaterial3D
var _gnet: StandardMaterial3D
var _flood: StandardMaterial3D
var _lights: Array[OmniLight3D] = []
var _night_sent := -1.0

# futbol
var _ball: RigidBody3D
var _pl: Array = []              # [{n, v, team, role, home, cd}] 0-1 kaleciler, 2-3 kirmizi oyuncular
var _chaser := 0
var _last_touch := ""
var _goal_wait := 0.0
var _pk := 0.0                   # oyuncunun sutu: vurus anina kalan sure
var _touch_cd := 0.0
var _goals := 0                  # oyuncunun bugunku golleri (serbest oyun + mac)
var _match := false
var _mt := 0.0
var _score := [0, 0]
var _last_o := Vector2.ZERO
var _owner_vel := Vector2.ZERO
var _dog_mine: Node3D
var _dog_cd := 0.0

# basket
var _bb: RigidBody3D
var _bs := ""                    # "", "aim", "fly"
var _bar_t := 0.0
var _bar_zone := 0.2
var _bar_speed := 1.3
var _fly_t := 0.0
var _fly_T := 1.0
var _fly_a := Vector3.ZERO
var _fly_b := Vector3.ZERO
var _fly_h := 1.5
var _fly_res := 0                # 2 basket, 1 cemberden dondu, 0 karavana
var _fly_pts := 2
var _baskets := 0
var _contest := false
var _c_shots := 0
var _c_made := 0
var _rec_label: Label3D

# arayuz
var _hud: Label
var _layer: Control
var _bar: Control
var _bar_zone_rect: ColorRect
var _bar_mark: ColorRect


# ---------------------------------------------------------------- yer secimi (dunya kurulurken)

## Baslangic noktasina yakin, duz ve bos bir cimenlik arar. Bulursa agac / cim ekilmesin diye
## dunyaya bildirir ve {c, ang} dondurur.
static func pick_site(w: Node3D) -> Dictionary:
	var start := ParkMap.spot("baslangic") if ParkMap.has_spot("baslangic") else Vector2.ZERO
	var best := {}
	var best_s := 1e9
	for strict in [true, false]:
		for ix in range(-34, 35):
			for iz in range(-34, 35):
				var q := start + Vector2(ix, iz) * 8.0
				var dist := q.distance_to(start)
				if dist < 45.0 or dist > 270.0 or dist >= best_s or not ParkMap.inside_bounds(q, 40.0):
					continue
				for a in [0.0, PI * 0.5]:
					var r := _lot_range(w, q, a, strict)
					if r >= 0.0 and dist + r * 70.0 < best_s:
						best_s = dist + r * 70.0
						best = {"c": q, "ang": a}
		if not best.is_empty():
			break
	if best.is_empty():
		return best
	var half := LOT if best["ang"] == 0.0 else Vector2(LOT.y, LOT.x)
	w._keep_out.append([best["c"], half + Vector2(1.5, 1.5)])
	w.paved.append([Transform2D(-float(best["ang"]), best["c"]).affine_inverse(), Rect2(-LOT - Vector2(0.6, 0.6), LOT * 2.0 + Vector2(1.2, 1.2))])
	return best


## Alan uygunsa zemin yukseklik farkini, degilse -1 dondurur.
static func _lot_range(w: Node3D, q0: Vector2, a: float, strict: bool) -> float:
	var lo := 1e9
	var hi := -1e9
	for sx in [0, -4, 4, -2, 2, -3, 3, -1, 1]:
		for sz in [0, -2, 2, -1, 1]:
			var q: Vector2 = q0 + Vector2(sx * 6.0, sz * 6.0).rotated(-a)
			var mk: Array = w._mask(q)
			if mk[2] > 0.3 or mk[3] > 0.3 or mk[4] > 0.44:
				return -1.0
			if strict and not w._is_lawn(q):
				return -1.0
			if ParkMap.water_sd(q) < 5.0 or w._kept_out(q, 3.0) or w._inside_building(q) or not w.is_free(q, 0.6):
				return -1.0
			var h := ParkMap.terrain_height(q)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo if hi - lo < 1.3 else -1.0


# ---------------------------------------------------------------- koordinatlar

func w(l: Vector2) -> Vector2:
	return c + l.rotated(-ang)


func loc(p: Vector2) -> Vector2:
	return (p - c).rotated(ang)


func ly(l: Vector2) -> float:
	return ParkMap.terrain_height(w(l)) - root.position.y


## Yerel nokta (root altinda), zeminden h yukarida.
func lp(l: Vector2, h := 0.0) -> Vector3:
	return Vector3(l.x, ly(l) + h, l.y)


## Dunya noktasi, zeminden h yukarida.
func wp(l: Vector2, h := 0.0) -> Vector3:
	var p := w(l)
	return Vector3(p.x, ParkMap.terrain_height(p) + h, p.y)


func _wdir(l: Vector2) -> Vector2:
	return l.rotated(-ang)


func _yaw(wd: Vector2) -> float:
	return atan2(-wd.x, -wd.y)


# ---------------------------------------------------------------- kurulum

func build() -> void:
	var site: Dictionary = m.world.sports_site
	if site.is_empty():
		return
	c = site["c"]
	ang = site["ang"]
	root = Node3D.new()
	root.position = Vector3(c.x, ParkMap.terrain_height(c), c.y)
	root.rotation.y = ang
	m.world.add_child(root)
	_body = StaticBody3D.new()
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.35
	_body.physics_material_override = pm
	root.add_child(_body)
	_steel = Kit.mat("8d9499", 0.45)
	_steel.metallic = 0.6
	_net = _net_mat(Color("2f8f4a"), 0.22, 3)
	_gnet = _net_mat(Color("f4f4f0"), 0.14, 3)
	_flood = StandardMaterial3D.new()
	_flood.albedo_color = Color("ecece4")
	_flood.emission_enabled = true
	_flood.emission = Color("fff1cf")
	_flood.emission_energy_multiplier = 0.0
	_build_ground()
	_cage(FC, FCAGE, 4.2, "1f7a3d", SITE_NAME.to_upper())
	_cage(BC, BH, 3.4, "2c5f9e", "POTA BASKET SAHASI")
	for s in [-1.0, 1.0]:
		_goal(s)
	_build_lights()
	_build_hoop()
	_build_balls()
	_build_players()


func _net_mat(col: Color, cell: float, line: int) -> StandardMaterial3D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(col.r, col.g, col.b, 0.0))
	for i in 32:
		for k in line:
			img.set_pixel(i, k, col)
			img.set_pixel(k, i, col)
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE / cell
	mat.roughness = 0.8
	return mat


## Zemine oturan izgara: dokusu tum yuzeye yayilir (u = yerel x, v = yerel z).
func _grid_mesh(cl: Vector2, half: Vector2, step: float) -> ArrayMesh:
	var nx := int(ceil(half.x * 2.0 / step))
	var nz := int(ceil(half.y * 2.0 / step))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var pts := []
			for k in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var u := float(ix + k[0]) / nx
				var v := float(iz + k[1]) / nz
				var l := cl - half + Vector2(u * half.x * 2.0, v * half.y * 2.0)
				pts.append([Vector2(u, v), lp(l, LIFT)])
			for p in pts:
				st.set_normal(Vector3.UP)
				st.set_uv(p[0])
				st.add_vertex(p[1])
	return st.commit()


func _ipx(hf: Vector2, x: float, z: float) -> Vector2i:
	return Vector2i(int(round((x + hf.x) * PX)), int(round((z + hf.y) * PX)))


func _fill(img: Image, hf: Vector2, x0: float, z0: float, x1: float, z1: float, col: Color) -> void:
	var a := _ipx(hf, minf(x0, x1), minf(z0, z1))
	var b := _ipx(hf, maxf(x0, x1), maxf(z0, z1))
	img.fill_rect(Rect2i(a, (b - a).max(Vector2i(2, 2))), col)


func _outline(img: Image, hf: Vector2, x0: float, z0: float, x1: float, z1: float, col: Color) -> void:
	var t := 0.06
	_fill(img, hf, x0 - t, z0 - t, x1 + t, z0 + t, col)
	_fill(img, hf, x0 - t, z1 - t, x1 + t, z1 + t, col)
	_fill(img, hf, x0 - t, z0 - t, x0 + t, z1 + t, col)
	_fill(img, hf, x1 - t, z0 - t, x1 + t, z1 + t, col)


func _arc(img: Image, hf: Vector2, cx: float, cz: float, r: float, a0: float, a1: float, col: Color, lim := Rect2(-99, -99, 198, 198)) -> void:
	var n := int(r * absf(a1 - a0) * PX * 1.5) + 2
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		var p := Vector2(cx + cos(a) * r, cz + sin(a) * r)
		if lim.has_point(p):
			img.fill_rect(Rect2i(_ipx(hf, p.x, p.y) - Vector2i(1, 1), Vector2i(2, 2)), col)


func _tex_mat(img: Image, rough: float) -> StandardMaterial3D:
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = rough
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _build_ground() -> void:
	var white := Color("f4f4ee")
	# Hali saha: bicme seritli yesil hali, beyaz cizgiler
	var hf := FCAGE
	var img := Image.create(int(hf.x * 2.0 * PX), int(hf.y * 2.0 * PX), false, Image.FORMAT_RGB8)
	img.fill(Color("24692f"))
	var i := 0
	var x := -FH.x
	while x < FH.x - 0.01:
		_fill(img, hf, x, -FH.y, x + 2.0, FH.y, Color("2f8a3b") if i % 2 == 0 else Color("287a33"))
		x += 2.0
		i += 1
	_outline(img, hf, -FH.x, -FH.y, FH.x, FH.y, white)
	_fill(img, hf, -0.06, -FH.y, 0.06, FH.y, white)
	_arc(img, hf, 0.0, 0.0, 3.0, 0.0, TAU, white)
	_fill(img, hf, -0.15, -0.15, 0.15, 0.15, white)
	for s in [-1.0, 1.0]:
		_outline(img, hf, s * FH.x, -4.6, s * (FH.x - 4.5), 4.6, white)
		_outline(img, hf, s * FH.x, -3.0, s * (FH.x - 1.6), 3.0, white)
		_fill(img, hf, s * (FH.x - 3.3) - 0.1, -0.1, s * (FH.x - 3.3) + 0.1, 0.1, white)
		_arc(img, hf, s * (FH.x - 3.3), 0.0, 2.2, -0.95 + (PI if s > 0.0 else 0.0), 0.95 + (PI if s > 0.0 else 0.0), white,
			Rect2(-FH.x + 4.56, -9, FH.x * 2.0 - 9.12, 18))
	Kit.add(root, _grid_mesh(FC, FCAGE, 1.3), _tex_mat(img, 0.95))
	# Basket sahasi: mavi akrilik zemin, kiremit rengi boyali alan
	hf = BH
	img = Image.create(int(hf.x * 2.0 * PX), int(hf.y * 2.0 * PX), false, Image.FORMAT_RGB8)
	img.fill(Color("255a85"))
	var base := BH.x - 0.5                 # dip cizgisi (x)
	var hx := HOOP.x - BC.x                # cember (x)
	_fill(img, hf, -BH.x + 0.5, -BH.y + 0.5, base, BH.y - 0.5, Color("2f6e9f"))
	_fill(img, hf, base - 5.8, -1.8, base, 1.8, Color("ad472f"))
	_outline(img, hf, -BH.x + 0.5, -BH.y + 0.5, base, BH.y - 0.5, white)
	_outline(img, hf, base - 5.8, -1.8, base, 1.8, white)
	_arc(img, hf, base - 5.8, 0.0, 1.8, PI * 0.5, PI * 1.5, white)
	_arc(img, hf, hx, 0.0, 6.75, PI * 0.5, PI * 1.5, white, Rect2(-BH.x + 0.5, -BH.y + 0.9, BH.x * 2.0, BH.y * 2.0 - 1.8))
	_fill(img, hf, hx, -BH.y + 0.84, base, -BH.y + 0.96, white)
	_fill(img, hf, hx, BH.y - 0.96, base, BH.y - 0.84, white)
	_arc(img, hf, hx, 0.0, 1.25, PI * 0.5, PI * 1.5, white)
	Kit.add(root, _grid_mesh(BC, BH, 1.3), _tex_mat(img, 0.7))
	# Iki saha arasi ve cevre: sikistirilmis zemin
	Kit.add(root, _grid_mesh(Vector2.ZERO, LOT + Vector2(0.5, 0.5), 2.0), Kit.mat("9b8f7c", 0.95), Vector3(0, -0.035, 0))
	# Topun ustunde durdugu carpisma zemini
	var cs := CollisionShape3D.new()
	cs.shape = _grid_mesh(Vector2.ZERO, LOT + Vector2(1.0, 1.0), 1.3).create_trimesh_shape()
	_body.add_child(cs)


func _box_col(pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	_body.add_child(cs)


func _fence_piece(a: Vector2, b: Vector2, h: float, col: String) -> void:
	m.world._add_segment(w(a), w(b))
	var d := b - a
	var length := d.length()
	var rot := Vector3(0, atan2(-d.y, d.x), 0)
	var mid := (a + b) * 0.5
	Kit.box(root, Vector3(length, h, 0.02), lp(mid, h * 0.5), _net, rot)
	Kit.box(root, Vector3(length, 0.07, 0.07), lp(mid, h), _steel, rot)
	Kit.box(root, Vector3(length, 0.32, 0.05), lp(mid, 0.16), Kit.mat(col, 0.7), rot)
	var n := maxi(int(round(length / 3.4)), 1)
	for i in n + 1:
		Kit.cyl(root, 0.05, 0.05, h + 0.1, lp(a.lerp(b, float(i) / n), h * 0.5), _steel, 6)


## Tel kafes: uzun kenarlarin ortasinda birer kapi; top icin kesintisiz gorunmez duvar.
func _cage(cl: Vector2, half: Vector2, h: float, col: String, title: String) -> void:
	for sz in [-1.0, 1.0]:
		var z: float = cl.y + half.y * sz
		_fence_piece(Vector2(cl.x - half.x, z), Vector2(cl.x - 1.3, z), h, col)
		_fence_piece(Vector2(cl.x + 1.3, z), Vector2(cl.x + half.x, z), h, col)
		var g := Vector2(cl.x, z)
		Kit.box(root, Vector3(2.6, h - 2.4, 0.02), lp(g, (h + 2.4) * 0.5), _net)
		Kit.box(root, Vector3(3.4, 0.56, 0.08), lp(g, 2.68), Kit.mat(col, 0.6))
		var t: Label3D = m.world._text(root, title, lp(g, 2.68) + Vector3(0, 0, 0.05 * sz), Color.WHITE, 0.22 if title.length() < 17 else 0.18)
		t.rotation.y = 0.0 if sz > 0.0 else PI
		_box_col(lp(Vector2(cl.x, z + sz * 0.3), 4.5), Vector3(half.x * 2.0 + 1.2, 10.0, 0.6))
	for sx in [-1.0, 1.0]:
		var x: float = cl.x + half.x * sx
		_fence_piece(Vector2(x, cl.y - half.y), Vector2(x, cl.y + half.y), h, col)
		_box_col(lp(Vector2(x + sx * 0.3, cl.y), 4.5), Vector3(0.6, 10.0, half.y * 2.0 + 1.2))


func _goal(s: float) -> void:
	var gx := FC.x + s * FH.x
	var white := Kit.mat("f6f6f2", 0.4)
	var dp := 1.3
	for sz in [-1.0, 1.0]:
		Kit.cyl(root, 0.06, 0.06, GH, lp(Vector2(gx, sz * GW), GH * 0.5), white, 8)
		_box_col(lp(Vector2(gx, sz * GW), GH * 0.5), Vector3(0.12, GH, 0.12))
		Kit.cyl(root, 0.035, 0.035, GH * 0.9, lp(Vector2(gx + s * dp, sz * GW), GH * 0.45), white, 6)
		Kit.box(root, Vector3(dp, GH, 0.02), lp(Vector2(gx + s * dp * 0.5, sz * GW), GH * 0.5), _gnet)
		_box_col(lp(Vector2(gx + s * dp * 0.5, sz * (GW + 0.06)), GH * 0.5), Vector3(dp, GH, 0.1))
	Kit.cyl(root, 0.06, 0.06, GW * 2.0 + 0.12, lp(Vector2(gx, 0), GH), white, 8, Vector3(PI * 0.5, 0, 0))
	_box_col(lp(Vector2(gx, 0), GH), Vector3(0.12, 0.12, GW * 2.0))
	Kit.box(root, Vector3(0.02, GH, GW * 2.0), lp(Vector2(gx + s * dp, 0), GH * 0.5), _gnet)
	Kit.box(root, Vector3(dp, 0.02, GW * 2.0), lp(Vector2(gx + s * dp * 0.5, 0), GH), _gnet)
	_box_col(lp(Vector2(gx + s * (dp + 0.06), 0), GH * 0.5), Vector3(0.1, GH, GW * 2.0))
	_box_col(lp(Vector2(gx + s * dp * 0.5, 0), GH + 0.06), Vector3(dp, 0.1, GW * 2.0))


func _build_lights() -> void:
	var poles := [FC + Vector2(-FCAGE.x, -FCAGE.y), FC + Vector2(-FCAGE.x, FCAGE.y), FC + Vector2(FCAGE.x, -FCAGE.y),
		FC + Vector2(FCAGE.x, FCAGE.y), BC + Vector2(BH.x, -BH.y), BC + Vector2(BH.x, BH.y)]
	for p: Vector2 in poles:
		var inward := (Vector2(FC.x if p.x < 8.0 else BC.x, 0.0) - p).normalized()
		Kit.cyl(root, 0.08, 0.12, 8.4, lp(p, 4.2), _steel, 8)
		var head := lp(p + inward * 0.35, 8.3)
		Kit.box(root, Vector3(0.45, 0.6, 1.5), head, Kit.mat("3a3f45", 0.5), Vector3(0, atan2(-inward.y, inward.x), -0.5))
		Kit.box(root, Vector3(0.06, 0.48, 1.36), head + Vector3(inward.x, -0.5, inward.y) * 0.24, _flood, Vector3(0, atan2(-inward.y, inward.x), -0.5))
	for l in [[FC + Vector2(-7.5, 0), 20.0], [FC + Vector2(7.5, 0), 20.0], [BC, 15.0]]:
		var o := OmniLight3D.new()
		o.light_color = Color("fff3d6")
		o.omni_range = l[1]
		o.omni_attenuation = 0.9
		o.shadow_enabled = false
		o.visible = false
		o.position = lp(l[0], 7.0)
		root.add_child(o)
		_lights.append(o)


func _build_hoop() -> void:
	var pole := HOOP + Vector2(1.55, 0.0)
	Kit.cyl(root, 0.09, 0.1, 3.7, lp(pole, 1.85), Kit.mat("2b3a55", 0.5), 10)
	_box_col(lp(pole, 1.85), Vector3(0.2, 3.7, 0.2))
	Kit.box(root, Vector3(1.2, 0.1, 0.1), lp(HOOP + Vector2(0.98, 0.0), 3.45), Kit.mat("2b3a55", 0.5))
	var bpos := lp(HOOP + Vector2(0.4, 0.0), 3.5)
	Kit.box(root, Vector3(0.05, 1.05, 1.8), bpos, Kit.mat("f4f4f0", 0.3))
	_box_col(bpos, Vector3(0.08, 1.05, 1.8))
	var red := Kit.mat("d2392e", 0.5)
	for k in [[0.0, 0.225, 0.04, 0.62], [0.0, -0.225, 0.04, 0.62], [0.31, 0.0, 0.45, 0.04], [-0.31, 0.0, 0.45, 0.04]]:
		Kit.box(root, Vector3(0.02, k[2], k[3]), bpos + Vector3(-0.03, k[1] - 0.12, k[0]), red)
	Kit.torus(root, 0.215, 0.245, lp(HOOP, RIM_H), Kit.mat("e8612a", 0.4))
	Kit.box(root, Vector3(0.18, 0.03, 0.1), lp(HOOP + Vector2(0.3, 0.0), RIM_H), Kit.mat("e8612a", 0.4))
	var cm := CylinderMesh.new()
	cm.top_radius = 0.225
	cm.bottom_radius = 0.14
	cm.height = 0.42
	cm.radial_segments = 12
	cm.cap_top = false
	cm.cap_bottom = false
	Kit.add(root, cm, _net_mat(Color("f4f4f0"), 0.09, 4), lp(HOOP, RIM_H - 0.21))
	# Yarisma panosu
	var b := lp(BOARD)
	Kit.cyl(root, 0.04, 0.04, 1.5, b + Vector3(0, 0.75, 0), _steel, 6)
	Kit.box(root, Vector3(1.5, 0.8, 0.06), b + Vector3(0, 1.7, 0), Kit.mat("f2a81d", 0.6))
	m.world._text(root, "SERBEST ATIŞ", b + Vector3(0, 1.88, -0.04), Color("1a1a1a"), 0.17).rotation.y = PI
	_rec_label = m.world._text(root, "", b + Vector3(0, 1.55, -0.04), Color("1a1a1a"), 0.15)
	_rec_label.rotation.y = PI
	_refresh_record()


func _refresh_record() -> void:
	if _rec_label:
		_rec_label.text = "10 atış · Rekor: %d" % int(state.d.get("sp_ft_record", 0))


func _mk_ball(r: float, mat: Material, bounce: float, mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = mass
	b.continuous_cd = true
	b.linear_damp = 0.15
	b.angular_damp = 1.6
	b.can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.bounce = bounce
	pm.friction = 0.7
	b.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	cs.shape = sh
	b.add_child(cs)
	Kit.ball(b, r, Vector3.ZERO, mat)
	m.world.add_child(b)
	return b


func _build_balls() -> void:
	_ball = _mk_ball(BALL_R, Kit.checker(Color("f6f6f2"), Color("1c1c1f"), 6, 4), 0.6, 0.43)
	_ball.global_position = wp(FC, 0.3)
	var om := Kit.mat("d9702a", 0.75)
	_bb = _mk_ball(0.12, om, 0.72, 0.6)
	for r in [Vector3(0, 0, 0), Vector3(PI * 0.5, 0, 0), Vector3(0, 0, PI * 0.5)]:
		Kit.torus(_bb, 0.112, 0.123, Vector3.ZERO, Kit.mat("26211d", 0.8), r)
	_bb.global_position = wp(BOARD + Vector2(-0.9, -0.6), 0.3)


func _build_players() -> void:
	var defs := [
		["erkek", "2f62c4", "20263a", 1.0, Vector2(-FH.x + 0.8, 0.0), 0, "gk"],
		["erkek", "f2c230", "1c1c1c", 1.0, Vector2(FH.x - 0.8, 0.0), 1, "gk"],
		["erkek", "d6382e", "f2f2f2", 0.8, Vector2(4.0, -3.0), 1, "fw"],
		["kadin", "d6382e", "f2f2f2", 0.76, Vector2(5.5, 3.5), 1, "fw"],
	]
	for d in defs:
		var n := Node3D.new()
		var v := PersonModel.new()
		v.kind = d[0]
		v.tint = Color(d[1])
		v.pants = Color(d[2])
		n.add_child(v)
		n.scale = Vector3.ONE * float(d[3])
		m.add_child(n)
		n.position = wp(FC + d[4])
		n.rotation.y = _yaw(_wdir(Vector2(-1.0 if d[5] == 1 else 1.0, 0.0)))
		_pl.append({"n": n, "v": v, "team": d[5], "role": d[6], "home": d[4], "cd": 0.0})


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	if root == null:
		return
	if absf(m.night - _night_sent) > 0.02:
		_night_sent = m.night
		var k := clampf(m.night * 1.6 - 0.3, 0.0, 1.0)
		_flood.emission_energy_multiplier = k * 5.0
		for o in _lights:
			o.visible = k > 0.02
			o.light_energy = k * 3.2
	var o2: Vector2 = m._owner_pos()
	var ol := loc(o2)
	var near := ParkMap.home == null and absf(ol.x) < 95.0 and absf(ol.y) < 85.0
	if not near:
		if _match:
			_end_match(true)
		if _bs != "":
			_cancel_shot()
		_release_dog()
		if _hud:
			_hud.visible = false
		_last_o = o2
		return
	_owner_vel = (o2 - _last_o) / maxf(dt, 0.001)
	_last_o = o2
	_update_football(dt, ol)
	_update_basket(dt, ol)
	_update_hud(ol)


func _in_pitch(ol: Vector2, pad := 0.0) -> bool:
	return absf(ol.x - FC.x) < FCAGE.x + pad and absf(ol.y - FC.y) < FCAGE.y + pad


func _in_court(ol: Vector2) -> bool:
	return absf(ol.x - BC.x) < BH.x and absf(ol.y - BC.y) < BH.y


# ---------------------------------------------------------------- futbol

func _ball_l() -> Vector2:
	var bp := _ball.global_position
	return loc(Vector2(bp.x, bp.z)) - FC


func _kick_ball(dir_l: Vector2, speed: float, up: float, who: String) -> void:
	var wd := _wdir(dir_l.normalized())
	_ball.sleeping = false
	_ball.linear_velocity = Vector3(wd.x * speed, up, wd.y * speed)
	_ball.angular_velocity = Vector3(wd.y, 0.0, -wd.x) * speed / BALL_R * 0.5
	_last_touch = who
	_touch_cd = 0.25


func _reset_ball() -> void:
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_position = wp(FC, 0.25)
	_ball.sleeping = false
	_last_touch = ""


func _sound(snd: String, db: float, pitch := 1.0) -> void:
	var d := loc(m._owner_pos()).length()
	if d < 60.0:
		m._sfx(snd, db - d * 0.35, pitch)


func _update_football(dt: float, ol: Vector2) -> void:
	var bp := _ball.global_position
	var bl := _ball_l()
	var bh := bp.y - root.position.y - ly(bl + FC) - LIFT - BALL_R
	if absf(bl.x) > FCAGE.x + 1.0 or absf(bl.y) > FCAGE.y + 1.0 or bh < -0.5 or bh > 14.0:
		_reset_ball()
		return
	_touch_cd -= dt
	var fl := ol - FC
	var inside := _in_pitch(ol)
	# Gol
	if _goal_wait > 0.0:
		_goal_wait -= dt
		if _goal_wait <= 0.0:
			_reset_ball()
	elif absf(bl.x) > FH.x + BALL_R and absf(bl.y) < GW and bh < GH:
		_on_goal(1 if bl.x > 0.0 else -1)
	# Oyuncu: surme ve sut
	if m._ride == null:
		var bd := fl.distance_to(bl)
		if _pk > 0.0:
			_pk -= dt
			if _pk <= 0.0 and bd < 2.0 and bh < 0.9:
				_player_shot(fl, bl)
		elif bd < 0.6 and bh < 0.45 and _touch_cd <= 0.0:
			var pv := _owner_vel.rotated(ang)
			if pv.length() > 0.6 and pv.dot(bl - fl) > 0.0:
				_kick_ball(pv, minf(pv.length() * 1.3 + 0.9, 9.0), 0.0, "player")
				_touch_cd = 0.12
	# Kopek topu kovalar
	_update_dog(dt, inside, bl, bh)
	# Yapay zeka
	for p in _pl:
		p["cd"] -= dt
	if _goal_wait > 0.0:
		for p in _pl:
			_npc_move(p, p["home"], 2.6, dt)
	else:
		_update_reds(dt, bl, bh, fl)
		_update_keepers(dt, bl, bh)
	# Mac saati
	if _match:
		_mt -= dt
		if not _in_pitch(ol, 7.0):
			_end_match(true)
		elif _mt <= 0.0:
			_end_match(false)


func _player_shot(fl: Vector2, bl: Vector2) -> void:
	var yaw: float = m.owner_node.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw)).rotated(ang)
	var goal := Vector2(FH.x, 0.0)
	var gk: Vector2 = _npc_l(_pl[1])
	var corner := -1.9 if gk.y > 0.0 else 1.9
	var aim := (goal + Vector2(0.0, corner + randf_range(-0.55, 0.55)) - bl)
	var speed := 14.0
	var up := 3.2
	if fwd.dot(aim.normalized()) > 0.8 and bl.x < FH.x - 0.5:
		speed = 16.5
		up = clampf(aim.length() * 0.32, 2.0, 4.6)
	else:
		aim = fwd
	_kick_ball(aim, speed, up, "player")
	_sound("firlat", -4.0, 0.8)


func _on_goal(side: int) -> void:
	_goal_wait = 2.2
	var mine := side > 0 and (_last_touch == "player" or _last_touch == "dog")
	if _match:
		_score[0 if side > 0 else 1] += 1
	if side > 0 and (mine or _match):
		_goals += 1
		state.count("goal")
		_banner("GOL!", m.ui.ACCENT)
		_sound("mutlu", -2.0)
		if _last_touch == "dog":
			m.ui.toast("Golü %s attı!" % state.pet("kopek")["name"])
	elif _match:
		_banner("GOL YEDİN!", m.ui.ACCENT2)
		_sound("tik", -4.0, 0.6)
	else:
		_sound("mutlu", -12.0, 1.2)
		for p in _pl:
			if p["role"] == "fw" and randf() < 0.6:
				m._say(p["n"], ["Goool!", "Attım!", "Bu da gol!"].pick_random())
				break


func _npc_l(p: Dictionary) -> Vector2:
	var n: Node3D = p["n"]
	return loc(Vector2(n.position.x, n.position.z)) - FC


func _npc_move(p: Dictionary, target: Vector2, sp: float, dt: float) -> void:
	target = Vector2(clampf(target.x, -FH.x - 0.4, FH.x + 0.4), clampf(target.y, -FH.y + 0.3, FH.y - 0.3))
	var n: Node3D = p["n"]
	var v: PersonModel = p["v"]
	var cur := _npc_l(p)
	var to := target - cur
	var d := to.length()
	if d < 0.1:
		v.speed = move_toward(v.speed, 0.0, dt * 8.0)
		return
	sp = minf(sp, d * 5.0 + 0.4)
	var np := cur + to / d * minf(sp * dt, d)
	n.position = wp(np + FC)
	n.rotation.y = lerp_angle(n.rotation.y, _yaw(_wdir(to / d)), minf(1.0, dt * 10.0))
	v.speed = sp


func _update_reds(dt: float, bl: Vector2, bh: float, fl: Vector2) -> void:
	var goal := Vector2(-FH.x, 0.0)
	var d0 := _npc_l(_pl[2]).distance_to(bl)
	var d1 := _npc_l(_pl[3]).distance_to(bl)
	_chaser = 2 if d0 <= d1 + (0.9 if _chaser == 2 else -0.9) else 3
	var ch: Dictionary = _pl[_chaser]
	var sup: Dictionary = _pl[5 - _chaser]
	var sp := 3.9 if _match else 3.3
	var cur := _npc_l(ch)
	var to_goal := (goal - bl).normalized()
	var bv3 := _ball.linear_velocity
	var bv := Vector2(bv3.x, bv3.z).rotated(ang)
	var tgt := bl + bv * 0.25 - to_goal * 0.3
	if cur.distance_to(bl) > 1.2 and (cur - bl).dot(to_goal) > 0.3:
		var perp := Vector2(-to_goal.y, to_goal.x)
		tgt = bl - to_goal * 1.0 + perp * (0.8 if (cur - bl).dot(perp) > 0.0 else -0.8)
	_npc_move(ch, tgt, sp, dt)
	if ch["cd"] <= 0.0 and cur.distance_to(bl) < 0.72 and bh < 0.5:
		var v: PersonModel = ch["v"]
		var gd := bl.distance_to(goal)
		var mate := _npc_l(sup)
		if gd < 10.5:
			var aim := (goal + Vector2(0.0, randf_range(-2.3, 2.3)) - bl).rotated(randf_range(-0.12, 0.12))
			_kick_ball(aim, 12.5, randf_range(2.0, 3.8), "npc")
			v.act("kick", 0.45)
			_sound("firlat", -8.0, 0.85)
			ch["cd"] = 0.9
		elif randf() < 0.3 and mate.x < bl.x + 3.0:
			_kick_ball(mate - bl, clampf(mate.distance_to(bl) * 1.45, 6.0, 11.0), 1.2, "npc")
			v.act("kick", 0.45)
			_sound("firlat", -11.0, 1.0)
			ch["cd"] = 0.8
		else:
			_kick_ball(to_goal.rotated(randf_range(-0.4, 0.4)), 5.2, 0.0, "npc")
			ch["cd"] = 0.35
	# Diger oyuncu: bos alana kosar; macta top oyuncudaysa kalenin onunu kapatir
	var open := Vector2(clampf(bl.x - 6.0, -FH.x + 3.0, FH.x - 3.0), 4.6 if bl.y < 0.0 else -4.6)
	if _match and fl.distance_to(bl) < 2.5:
		open = bl.lerp(Vector2(FH.x, 0.0), 0.45)
	_npc_move(sup, open, sp * 0.85, dt)


func _update_keepers(dt: float, bl: Vector2, bh: float) -> void:
	var bv3 := _ball.linear_velocity
	var slow := Vector2(bv3.x, bv3.z).length() < 2.5
	for i in 2:
		var gk: Dictionary = _pl[i]
		var s := -1.0 if i == 0 else 1.0
		var cur := _npc_l(gk)
		var own := bl.x * s > 0.0
		var tgt := Vector2(s * (FH.x - 0.8), clampf(bl.y * (0.6 if own else 0.3), -1.9, 1.9))
		var in_box := bl.x * s > FH.x - 4.6 and absf(bl.y) < 4.6
		if in_box and slow:
			tgt = bl + Vector2(s * 0.3, 0.0)
		_npc_move(gk, tgt, 3.2 if in_box and slow else 2.1, dt)
		if not (in_box and slow) and (gk["v"] as PersonModel).speed < 0.3:
			var n: Node3D = gk["n"]
			n.rotation.y = lerp_angle(n.rotation.y, _yaw(_wdir(bl - cur)), minf(1.0, dt * 5.0))
		if gk["cd"] <= 0.0 and cur.distance_to(bl) < 0.85 and bh < 1.9 and absf(bl.x) < FH.x + 0.2:
			var fast := Vector2(bv3.x, bv3.z).length() > 7.0
			var out := Vector2(-s, randf_range(-0.75, 0.75))
			_kick_ball(out, randf_range(9.0, 12.0), 3.6, "gk")
			(gk["v"] as PersonModel).act("kick", 0.45)
			_sound("firlat", -9.0, 0.7)
			gk["cd"] = 0.9
			if fast and i == 1:
				m._say(gk["n"], ["Kurtardım!", "Geçemezsin!", "Bu top bende!"].pick_random())


func _update_dog(dt: float, inside: bool, bl: Vector2, bh: float) -> void:
	var a: Node3D = m.agents.get("kopek")
	var want: bool = inside and a != null and is_instance_valid(a) and state.d["active"] == "kopek" and m._ride == null \
		and not a.is_busy() and (not a.external or a == _dog_mine)
	if not want:
		_release_dog()
		return
	_dog_mine = a
	a.external = true
	_dog_cd -= dt
	var wb := w(bl + FC)
	var d: float = a._move(wb, 5.2, dt)
	if d < 0.55 and bh < 0.5 and _dog_cd <= 0.0 and _touch_cd <= 0.0:
		var dir := (Vector2(FH.x, 0.0) - bl).normalized().rotated(randf_range(-0.5, 0.5))
		_kick_ball(dir, 5.5, 0.6, "dog")
		_dog_cd = 1.1


func _release_dog() -> void:
	if _dog_mine != null and is_instance_valid(_dog_mine):
		_dog_mine.external = false
	_dog_mine = null


func _start_match() -> void:
	if _match:
		return
	_match = true
	_mt = MATCH_SECS
	_score = [0, 0]
	_goal_wait = 0.0
	_reset_ball()
	for p in _pl:
		(p["n"] as Node3D).position = wp(FC + p["home"])
	m._place_owner(w(FC + Vector2(-3.5, 0.0)))
	m.owner_node.rotation.y = _yaw(_wdir(Vector2(1, 0)))
	_last_o = m._owner_pos()
	m.ui.toast("Maç başladı! Sarı kalecinin kalesine gol at · 5 dakika")
	_banner("BAŞLA!", m.ui.ACCENT)


func _end_match(left: bool) -> void:
	if not _match:
		return
	_match = false
	if left:
		m.ui.toast("Maçı yarıda bıraktın")
		return
	var a: int = _score[0]
	var b: int = _score[1]
	var prize := 60 if a > b else (25 if a == b else 10)
	state.add_coins(prize)
	if a > b:
		state.d["sp_wins"] = int(state.d.get("sp_wins", 0)) + 1
	state.save_game()
	_banner("KAZANDIN!" if a > b else ("BERABERE" if a == b else "KAYBETTİN"), m.ui.ACCENT if a >= b else m.ui.ACCENT2)
	m.ui.toast("Maç bitti: %d - %d · +%d altın" % [a, b, prize])
	m._sfx("para", -4.0)


# ---------------------------------------------------------------- basket

func _hoop_w() -> Vector3:
	return wp(HOOP, RIM_H)


func _start_shot() -> void:
	if _bs != "":
		return
	if _contest:
		m._place_owner(w(FT))
		_last_o = m._owner_pos()
	var o: Vector2 = m._owner_pos()
	var hw := w(HOOP)
	var dist := o.distance_to(hw)
	m.owner_node.rotation.y = _yaw(hw - o)
	_bs = "aim"
	_bar_t = randf() * 0.6
	_bar_zone = clampf(0.36 - dist * 0.028, 0.07, 0.3)
	_bar_speed = 1.15 + dist * 0.05
	_bb.freeze = true


func _cancel_shot() -> void:
	_bs = ""
	_bb.freeze = false
	_bb.sleeping = false
	if _bar:
		_bar.visible = false


func _release_shot() -> void:
	if _bs != "aim":
		return
	var mark := pingpong(_bar_t * _bar_speed, 1.0)
	var err := absf(mark - 0.5)
	var o: Vector2 = m._owner_pos()
	var hw := w(HOOP)
	var dist := o.distance_to(hw)
	var dir := (hw - o).normalized() if dist > 0.05 else Vector2.RIGHT
	_fly_res = 2 if err <= _bar_zone * 0.5 else (1 if err <= _bar_zone * 0.5 + 0.1 else 0)
	_fly_pts = 3 if dist > 6.75 else 2
	_fly_a = _bb.global_position
	_fly_b = _hoop_w() + Vector3(0, 0.06, 0)
	if _fly_res == 1:
		var side := Vector2(-dir.y, dir.x) * (0.26 if randf() < 0.5 else -0.26)
		_fly_b += Vector3(side.x + dir.x * 0.1, 0.02, side.y + dir.y * 0.1)
	elif _fly_res == 0:
		var off := dir * (-0.85 if mark < 0.5 else 0.75)
		_fly_b += Vector3(off.x, -0.35 if mark < 0.5 else 0.5, off.y)
	_fly_h = 1.0 + dist * 0.17
	_fly_T = 0.75 + dist * 0.055
	_fly_t = 0.0
	_bs = "fly"
	if _bar:
		_bar.visible = false
	m.owner_model.act("throw", 0.7)
	m._sfx("firlat", -5.0, 1.1)


func _update_basket(dt: float, ol: Vector2) -> void:
	var bp := _bb.global_position
	var bl := loc(Vector2(bp.x, bp.z))
	if _bs == "" and (absf(bl.x - BC.x) > BH.x + 1.0 or absf(bl.y - BC.y) > BH.y + 1.0 or bp.y < root.position.y + ly(bl) - 0.6):
		_bb.linear_velocity = Vector3.ZERO
		_bb.global_position = wp(BOARD + Vector2(-0.9, -0.6), 0.3)
	if _bs == "aim":
		if not _in_court(ol) or m._ride != null:
			_cancel_shot()
			return
		_bar_t += dt
		var yaw: float = m.owner_node.rotation.y
		_bb.global_position = m.owner_node.position + Vector3(-sin(yaw) * 0.28, 1.95, -cos(yaw) * 0.28)
		_show_bar(pingpong(_bar_t * _bar_speed, 1.0))
	elif _bs == "fly":
		_fly_t += dt
		var u := minf(_fly_t / _fly_T, 1.0)
		_bb.global_position = _fly_a.lerp(_fly_b, u) + Vector3(0, 4.0 * _fly_h * u * (1.0 - u), 0)
		_bb.rotate_x(-dt * 9.0)
		if u >= 1.0:
			_land_shot()


func _land_shot() -> void:
	_bs = ""
	_bb.freeze = false
	_bb.sleeping = false
	var flat := (_fly_b - _fly_a) / _fly_T
	flat.y = 0.0
	var vy := -4.0 * _fly_h / _fly_T + (_fly_b.y - _fly_a.y) / _fly_T
	if _fly_res == 2:
		_bb.linear_velocity = flat * 0.12 + Vector3(0, vy * 0.7, 0)
		_baskets += 1
		state.count("basket")
		_banner("ÜÇLÜK!" if _fly_pts == 3 else "BASKET!", m.ui.ACCENT)
		m._sfx("mutlu", -5.0, 1.15)
	elif _fly_res == 1:
		var back := -flat.normalized() * randf_range(1.6, 2.8)
		_bb.linear_velocity = back.rotated(Vector3.UP, randf_range(-0.9, 0.9)) + Vector3(0, 3.0, 0)
		m._sfx("tik", -2.0, 0.7)
		m.ui.toast("Çemberden döndü!")
	else:
		_bb.linear_velocity = flat * 0.8 + Vector3(0, vy, 0)
		m.ui.toast("Karavana… Çubuğu yeşilde durdur")
	if _contest:
		_c_shots += 1
		if _fly_res == 2:
			_c_made += 1
		if _c_shots >= FT_SHOTS:
			_end_contest()


func _start_contest() -> void:
	_contest = true
	_c_shots = 0
	_c_made = 0
	m.ui.toast("Serbest atış yarışması: %d atış. Çubuk yeşildeyken bırak!" % FT_SHOTS)
	_start_shot()


func _end_contest() -> void:
	_contest = false
	var rec := int(state.d.get("sp_ft_record", 0))
	var prize := _c_made * 5
	if _c_made > rec:
		state.d["sp_ft_record"] = _c_made
		prize += 20
		_banner("YENİ REKOR!", m.ui.ACCENT)
		_refresh_record()
	if prize > 0:
		state.add_coins(prize)
		m._sfx("para", -4.0)
	state.save_game()
	m.ui.toast("Yarışma bitti: %d / %d isabet · +%d altın" % [_c_made, FT_SHOTS, prize])


# ---------------------------------------------------------------- arayuz

## Tam ekran tasiyici: HUD gorunurken gorunur.
func _holder() -> Control:
	if _layer == null:
		_layer = Control.new()
		_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.ui.add_child(_layer)
	return _layer


func _update_hud(ol: Vector2) -> void:
	if m.ui == null or m.ui.hud == null:
		return
	_holder().visible = m.ui.hud.visible
	if _hud == null:
		_hud = m.ui._fx_label(_holder(), "", m.ui.F_TITLE, 38, Color.WHITE, 8)
		_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hud.offset_top = 92
		_hud.offset_bottom = 140
	var text := ""
	if _match:
		var t := int(ceil(maxf(_mt, 0.0)))
		text = "SEN  %d - %d  KIRMIZILAR   ·   %d:%02d" % [_score[0], _score[1], t / 60, t % 60]
	elif _contest:
		text = "SERBEST ATIŞ  %d / %d   ·   İSABET %d   ·   REKOR %d" % [mini(_c_shots + 1, FT_SHOTS), FT_SHOTS, _c_made, int(state.d.get("sp_ft_record", 0))]
	elif _in_court(ol) and m._ride == null:
		text = "BASKET: %d" % _baskets
	elif _in_pitch(ol) and m._ride == null and _goals > 0:
		text = "GOL: %d" % _goals
	_hud.text = text
	_hud.visible = text != ""


func _show_bar(mark: float) -> void:
	if _bar == null:
		_bar = Control.new()
		_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_bar.offset_top = -210
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_holder().add_child(_bar)
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.03, 0.05, 0.85)
		bg.position = Vector2(-216, -6)
		bg.size = Vector2(432, 40)
		_bar.add_child(bg)
		var red := ColorRect.new()
		red.color = Color("b8402f")
		red.position = Vector2(-210, 0)
		red.size = Vector2(420, 28)
		_bar.add_child(red)
		_bar_zone_rect = ColorRect.new()
		_bar_zone_rect.color = Color("3fd15a")
		_bar.add_child(_bar_zone_rect)
		_bar_mark = ColorRect.new()
		_bar_mark.color = Color.WHITE
		_bar_mark.size = Vector2(7, 44)
		_bar.add_child(_bar_mark)
		var lb: Label = m.ui._fx_label(_bar, "ŞUT ÇEK  ·  YEŞİLDE BIRAK", m.ui.F_TITLE, 30, m.ui.ACCENT, 6)
		lb.position = Vector2(-210, -52)
		lb.size = Vector2(420, 40)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for it in [bg, red, _bar_zone_rect, _bar_mark]:
			(it as ColorRect).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.visible = true
	_bar_zone_rect.position = Vector2(-210.0 + (0.5 - _bar_zone * 0.5) * 420.0, 0)
	_bar_zone_rect.size = Vector2(_bar_zone * 420.0, 28)
	_bar_mark.position = Vector2(-210.0 + mark * 420.0 - 3.5, -8)


func _banner(text: String, col: Color) -> void:
	if m.ui == null or m.ui.hud == null:
		return
	var l: Label = m.ui._fx_label(_holder(), text, m.ui.F_TITLE, 150, col, 22)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.offset_bottom = -260
	var tw := l.create_tween()
	tw.tween_interval(1.3)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


# ---------------------------------------------------------------- etkilesim

func context() -> Array:
	if root == null or m._ride != null or ParkMap.home != null:
		return []
	if _bs == "aim":
		return ["Bırak!", "sp_brelease", "ball"]
	var ol := loc(m._owner_pos())
	if _in_pitch(ol, 2.2):
		if _in_pitch(ol) and _pk <= 0.0 and (ol - FC).distance_to(_ball_l()) < 1.8:
			return ["Şut Çek", "sp_kick", "ball"]
		if not _match:
			return ["Maça Katıl · 5 dk", "sp_match", "play"]
		return ["", "", "ball"]
	if _in_court(ol):
		if _bs == "fly":
			return ["", "", "ball"]
		if _contest:
			return ["Atış %d / %d · Şut Çek" % [_c_shots + 1, FT_SHOTS], "sp_bshoot", "ball"]
		if ol.distance_to(BOARD) < 2.2:
			return ["Serbest Atış Yarışması · Rekor %d" % int(state.d.get("sp_ft_record", 0)), "sp_contest", "star"]
		return ["Şut Çek", "sp_bshoot", "ball"]
	if _contest:
		_contest = false
		m.ui.toast("Yarışmadan çıktın")
	return []


func command(cmd: String) -> void:
	if root == null:
		return
	match cmd:
		"sp_kick":
			if _pk <= 0.0:
				_pk = 0.2
				m.owner_model.act("kick", 0.55)
		"sp_match":
			_start_match()
		"sp_bshoot":
			_start_shot()
		"sp_brelease":
			_release_shot()
		"sp_contest":
			_start_contest()
		"sp_quit":
			_end_match(true)
		"sp_nav":
			m.ui.close_modal()
			m._set_nav(w(FC + Vector2(0.0, FCAGE.y + 1.5)), SITE_NAME)


func phone_app() -> void:
	var body: VBoxContainer = m.ui._open_panel("SPOR", "%s ve Pota Basket Sahası · Bugün %d gol, %d basket · Kazanılan maç: %d · Serbest atış rekoru: %d / %d" % [
		SITE_NAME, _goals, _baskets, int(state.d.get("sp_wins", 0)), int(state.d.get("sp_ft_record", 0)), FT_SHOTS])
	m.ui._panel_item(body, "Yol tarifi al", func(): command("sp_nav"))
	if _match:
		m.ui._panel_item(body, "Maçı bırak", func():
			m.ui.close_modal()
			command("sp_quit"))
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


# ---------------------------------------------------------------- test

func debug(kind: String, arg: String) -> void:
	if root == null:
		print("SPOR: uygun alan bulunamadi")
		return
	print("SPOR alan ", c, " aci ", ang)
	if kind == "football":
		m._place_owner(w(FC + Vector2(-4.0, 0.6)))
		m.owner_node.rotation.y = _yaw(_wdir(Vector2(1, 0)))
		m._cam_yaw = _yaw(_wdir(Vector2(1, -0.25)))
		for k in m.agents:
			m.agents[k].place(m._owner_pos() + Vector2(0.8, 0.8))
		_last_o = m._owner_pos()
		if arg != "free":
			_start_match()
		if arg == "goal":
			await get_tree().create_timer(0.4).timeout
			_ball.global_position = wp(FC + Vector2(FH.x - 2.0, 1.6), 0.4)
			_kick_ball(Vector2(1, 0.05), 14.0, 2.0, "player")
		elif arg == "kick":
			await get_tree().create_timer(0.5).timeout
			m._place_owner(w(FC + Vector2(-0.7, 0.0)))
			command("sp_kick")
	else:
		m._place_owner(w(FT + Vector2(-1.2, 0.0)))
		m._cam_yaw = _yaw(_wdir(Vector2(1, 0.2)))
		for k in m.agents:
			m.agents[k].place(m._owner_pos() + Vector2(-1.5, 1.5).rotated(-ang))
		_last_o = m._owner_pos()
		_start_contest()
		if arg == "shoot":
			await get_tree().create_timer(0.3).timeout
			_bar_t = 0.5 / _bar_speed
			_release_shot()
