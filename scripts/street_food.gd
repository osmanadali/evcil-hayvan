extends Node
## Sokak lezzetleri ve cay ocagi.
## - Simitci arabasi: kirmizi-beyaz, cam vitrinli, ici simit (Ankara'da "gevrek") ve pogaca dolu; yaninda
##   simitci. Biri baslangicin yaninda parkta, biri (varsa) metro girisinin yaninda. F ile kucuk panel:
##   simit / pogaca / ayran; hemen ye-ic ya da cantaya koy.
## - Cay ocagi (parkta): alcak hasir tabureler, kucuk masalar, tabakli ince belli cay bardaklari, semaver ve
##   demlik, caycı. Tezgahta F: cay / simit / pogaca. Bos bir taburede F: otur; caycı cayi getirir (3 TL).
##   Otururken yudumlarsin, hayvan yanina uzanir, dinlenir ve neselenir, saat hizli akar.
##   Herhangi bir hareket tusu ya da dokunmatik cubuk kaldirir.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const F_TITLE := preload("res://assets/fonts/Bangers-Regular.ttf")

# kimlik: [ad, fiyat]
const ITEMS := {"simit": ["Simit", 5], "pogaca": ["Poğaça", 4], "ayran": ["Ayran", 6], "cay": ["Çay", 3]}
const CART_CALLS := ["Taze gevrek, sıcak simit!", "Gevreeek! Simiiit!", "Poğaça da var, sıcacık!", "Buyur abla, buyur abi!"]
const TEA_CALLS := ["Çaylar taze demlendi!", "Buyurun, oturun!", "Açık mı olsun, demli mi?", "Bir çay içmeden gitmek yok!"]
const SIP_EVERY := 4.5          # saniyede bir yudum
const SIPS := 4                 # bir bardak kac yudum
const TIME_BOOST := 5.0         # otururken saat kac kat hizli

var m: Node                     # main
var state: Node
var carts: Array = []           # [{root, pos, front, yaw, vendor}]
var tea: Dictionary = {}        # {root, pos, yaw, counter, stools: [{pos, yaw, table, busy}], cayci, home, light}
var seat: Dictionary = {}       # oturuluyorsa: {i, t, glass, has_tea, sips, sip_t}
var _serve: Dictionary = {}     # caycı servisi: {phase, from, to, t}
var _call_t := 8.0
var _sitters: Array = []        # oturan musteriler [model, glass]
var _bulb_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _tea_mat: StandardMaterial3D
var _simit_mat: StandardMaterial3D
var _seat_y := -0.05            # oturma pozunda modelin dikey kaymasi (tabure yuksekligine gore)


func is_seated() -> bool:
	return not seat.is_empty()


# ---------------------------------------------------------------- kurulum

func build() -> void:
	_materials()
	var w: Node3D = m.world
	if ParkMap.has_spot("baslangic"):
		var b: Vector2 = ParkMap.spot("baslangic")
		var cp := _free_spot(b + Vector2(22.0, 2.0), 1.6, 6.5)
		if cp != Vector2.INF:
			_add_cart(cp, (b - cp).normalized())
		var tp := _flat_spot(b + Vector2(12.0, -19.0), 4.4, 9.0)
		if tp != Vector2.INF:
			_build_tea_garden(tp, (b - tp).normalized())
	# Metro girisinin yaninda ikinci araba
	for g in w.metro_gates:
		var gp: Vector2 = g["pos"]
		var tw: Vector2 = g["toward"]
		var side := Vector2(-tw.y, tw.x)
		var cp := _free_spot(gp - tw * 6.5 + side * 3.5, 1.4, 5.5)
		if cp != Vector2.INF and cp.distance_to(gp) < 22.0:
			_add_cart(cp, -tw)
			break
	print("SOKAK LEZZETLERI arabalar=%d cay_ocagi=%s" % [carts.size(), not tea.is_empty()])


func _materials() -> void:
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.albedo_color = Color(0.9, 0.96, 1.0, 0.22)
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.roughness = 0.04
	_glass_mat.metallic_specular = 1.0
	_glass_mat.rim_enabled = true
	_glass_mat.rim = 0.6
	_tea_mat = StandardMaterial3D.new()
	_tea_mat.albedo_color = Color("9a2a0c")
	_tea_mat.roughness = 0.12
	_tea_mat.emission_enabled = true
	_tea_mat.emission = Color("b8401a")
	_tea_mat.emission_energy_multiplier = 0.35
	_bulb_mat = Kit.glow("ffd27a", 0.6)
	# Susamli simit: kahverengi uzerinde acik benekler
	_simit_mat = StandardMaterial3D.new()
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.frequency = 0.22
	var tex := NoiseTexture2D.new()
	tex.width = 64
	tex.height = 64
	tex.seamless = true
	tex.noise = nz
	var ramp := Gradient.new()
	ramp.set_color(0, Color("f3e3b8"))
	ramp.set_color(1, Color("a8652a"))
	ramp.set_offset(0, 0.18)
	ramp.set_offset(1, 0.3)
	tex.color_ramp = ramp
	_simit_mat.albedo_texture = tex
	_simit_mat.uv1_scale = Vector3(3, 1, 1)
	_simit_mat.roughness = 0.7


func _ok(p: Vector2, r: float, road_gap: float) -> bool:
	var w: Node3D = m.world
	if not ParkMap.inside_bounds(p, 12.0) or not w.is_free(p, r) or w._inside_building(p):
		return false
	if ParkMap.water_sd(p) < r + 2.0:
		return false
	if road_gap > 0.0 and w._road_point(p).distance_to(p) < road_gap:
		return false
	for k in 8:
		if not w.is_free(p + Vector2.from_angle(k * TAU / 8.0) * r * 0.8, 0.3):
			return false
	return true


func _free_spot(p: Vector2, r: float, road_gap: float) -> Vector2:
	if _ok(p, r, road_gap):
		return p
	for rad in range(2, 30, 2):
		for k in 12:
			var q := p + Vector2.from_angle(k * TAU / 12.0 + rad * 0.3) * float(rad)
			if _ok(q, r, road_gap):
				return q
	return Vector2.INF


## Duz bir yer: tercih edilen noktanin cevresinde egimi en az olan bos alan.
func _flat_spot(p: Vector2, r: float, road_gap: float) -> Vector2:
	var best := Vector2.INF
	var best_rng := 1e9
	for rad in range(0, 32, 2):
		for k in (1 if rad == 0 else 12):
			var q := p + Vector2.from_angle(k * TAU / 12.0 + rad * 0.3) * float(rad)
			if not _ok(q, r, road_gap):
				continue
			var lo := 1e9
			var hi := -1e9
			for j in 9:
				var h := ParkMap.terrain_height(q + (Vector2.ZERO if j == 8 else Vector2.from_angle(j * TAU / 8.0) * r))
				lo = minf(lo, h)
				hi = maxf(hi, h)
			var score := (hi - lo) + float(rad) * 0.03
			if score < best_rng:
				best_rng = score
				best = q
		if best_rng < 0.2:
			break
	return best


## Yerel +Z, 'face' yonune bakar.
func _yaw(face: Vector2) -> float:
	return atan2(face.x, face.y)


func _person(kind: String, shirt: String, pants: String) -> Node3D:
	var v := PersonModel.new()
	v.kind = kind
	v.tint = Color(shirt)
	v.tint2 = Color(shirt)
	v.pants = Color(pants)
	return v


func _multi(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, text: String, pos: Vector3, size: float, color: Color, rot_y := 0.0, outline := Color(0, 0, 0, 0)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = F_TITLE
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.modulate = color
	l.outline_size = 10 if outline.a > 0.0 else 0
	l.outline_modulate = outline
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = pos
	l.rotation.y = rot_y
	parent.add_child(l)
	return l


## Ince belli cay bardagi (istege bagli tabakli). Adi "Cay" olan dugum cayin kendisidir.
func tea_glass(parent: Node3D, pos: Vector3, full := true, saucer := true) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	parent.add_child(g)
	if saucer:
		Kit.cyl(g, 0.052, 0.042, 0.008, Vector3(0, 0.004, 0), Kit.mat("f4f1ea", 0.3), 16)
		Kit.torus(g, 0.046, 0.052, Vector3(0, 0.008, 0), Kit.mat("c9a13b", 0.3))
	var y0 := 0.008 if saucer else 0.0
	var tea_n := Node3D.new()
	tea_n.name = "Cay"
	g.add_child(tea_n)
	Kit.cyl(tea_n, 0.014, 0.018, 0.03, Vector3(0, y0 + 0.018, 0), _tea_mat, 10)
	Kit.cyl(tea_n, 0.02, 0.014, 0.034, Vector3(0, y0 + 0.05, 0), _tea_mat, 10)
	tea_n.visible = full
	var lo := Kit.cyl(g, 0.016, 0.021, 0.034, Vector3(0, y0 + 0.017, 0), _glass_mat, 12)
	var hi := Kit.cyl(g, 0.025, 0.016, 0.046, Vector3(0, y0 + 0.057, 0), _glass_mat, 12)
	for mi in [lo, hi]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return g


# ---------------------------------------------------------------- simitci arabasi

func _add_cart(p: Vector2, face: Vector2) -> void:
	var w: Node3D = m.world
	var yaw := _yaw(face)
	var r: Node3D = w._root(p, yaw)
	var red := Kit.mat("c8102e", 0.45)
	var white := Kit.mat("f6f3ee", 0.5)
	var chrome := Kit.mat("d9dde2", 0.18)
	chrome.metallic = 0.85
	var dark := Kit.mat("1d1d1f", 0.8)
	# Tekerlekler (yanlarda, ortada) ve on ayaklar
	for sz in [-1.0, 1.0]:
		var wh := Kit.pivot(r, Vector3(0.5, 0.36, sz * 0.47))
		Kit.torus(wh, 0.3, 0.36, Vector3.ZERO, dark, Vector3(PI / 2, 0, 0))
		Kit.torus(wh, 0.28, 0.31, Vector3.ZERO, chrome, Vector3(PI / 2, 0, 0))
		for k in 8:
			Kit.box(wh, Vector3(0.012, 0.56, 0.012), Vector3.ZERO, chrome, Vector3(0, 0, k * PI / 8.0))
		Kit.cyl(wh, 0.045, 0.045, 0.08, Vector3.ZERO, chrome, 10, Vector3(PI / 2, 0, 0))
	for sz in [-1.0, 1.0]:
		Kit.cyl(r, 0.022, 0.022, 0.55, Vector3(-0.68, 0.28, sz * 0.3), chrome, 8)
		# Itme kollari
		Kit.cyl(r, 0.018, 0.018, 0.55, Vector3(0.98, 0.78, sz * 0.3), chrome, 8, Vector3(0, 0, PI / 2 - 0.25))
	Kit.cyl(r, 0.022, 0.022, 0.66, Vector3(1.24, 0.85, 0), dark, 8, Vector3(PI / 2, 0, 0))
	# Govde: kirmizi kasa, beyaz seritler
	Kit.box(r, Vector3(1.5, 0.46, 0.78), Vector3(0, 0.78, 0), red)
	Kit.box(r, Vector3(1.52, 0.05, 0.8), Vector3(0, 0.58, 0), white)
	Kit.box(r, Vector3(1.52, 0.035, 0.8), Vector3(0, 0.93, 0), white)
	Kit.box(r, Vector3(1.58, 0.04, 0.84), Vector3(0, 1.02, 0), white)
	for sz in [-1.0, 1.0]:
		_label(r, "SİMİT", Vector3(-0.25, 0.77, sz * 0.395), 0.2, Color.WHITE, 0.0 if sz > 0 else PI)
	# Cam vitrin: krom dikmeler, cam, kirmizi cati
	for sx in [-0.74, 0.74]:
		for sz in [-0.38, 0.38]:
			Kit.box(r, Vector3(0.03, 0.56, 0.03), Vector3(sx, 1.32, sz), chrome)
	var glass := [
		[Vector3(1.48, 0.54, 0.01), Vector3(0, 1.32, 0.38)], [Vector3(1.48, 0.54, 0.01), Vector3(0, 1.32, -0.38)],
		[Vector3(0.01, 0.54, 0.76), Vector3(0.74, 1.32, 0)], [Vector3(0.01, 0.54, 0.76), Vector3(-0.74, 1.32, 0)]]
	for gl in glass:
		var gm := Kit.box(r, gl[0], gl[1], _glass_mat)
		gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.box(r, Vector3(1.5, 0.012, 0.74), Vector3(0, 1.3, 0), _glass_mat)
	Kit.box(r, Vector3(1.62, 0.06, 0.86), Vector3(0, 1.63, 0), red)
	Kit.box(r, Vector3(1.64, 0.025, 0.88), Vector3(0, 1.6, 0), white)
	# Catida tabela
	Kit.box(r, Vector3(0.9, 0.24, 0.04), Vector3(0, 1.8, 0), white)
	Kit.box(r, Vector3(0.94, 0.03, 0.05), Vector3(0, 1.93, 0), red)
	for sz in [-1.0, 1.0]:
		_label(r, "TAZE GEVREK", Vector3(0, 1.8, sz * 0.025), 0.11, Color("c8102e"), 0.0 if sz > 0 else PI)
	# Simitler (iki kat, ustuste) ve pogacalar: tek cizim
	var tor := TorusMesh.new()
	tor.inner_radius = 0.043
	tor.outer_radius = 0.08
	tor.rings = 16
	tor.ring_segments = 8
	var xf: Array = []
	for tier in 2:
		var y := 1.05 if tier == 0 else 1.32
		for ix in 4:
			for iz in 2:
				if tier == 0 and ix == 3:
					continue
				for s in (3 if tier == 0 else 2):
					var t := Transform3D(Basis().rotated(Vector3.UP, randf() * TAU).rotated(Vector3.RIGHT, randf_range(-0.06, 0.06)),
						Vector3(-0.54 + ix * 0.36 + randf_range(-0.02, 0.02), y + 0.022 + s * 0.035, -0.16 + iz * 0.32))
					xf.append(t)
	_multi(r, tor, _simit_mat, xf)
	var bun := SphereMesh.new()
	bun.radius = 0.055
	bun.height = 0.07
	bun.radial_segments = 12
	bun.rings = 6
	var px: Array = []
	for k in 6:
		px.append(Transform3D(Basis(), Vector3(0.5 + (k % 2) * 0.12, 1.07 + (k / 4) * 0.05, -0.2 + (k % 3) * 0.17)))
	_multi(r, bun, Kit.mat("d9a04c", 0.6), px)
	# Ayran sisesi kasasi (yanda)
	Kit.box(r, Vector3(0.3, 0.2, 0.26), Vector3(-0.35, 0.1, 0.05), Kit.mat("2d6fb5", 0.6))
	for k in 4:
		Kit.cyl(r, 0.03, 0.03, 0.16, Vector3(-0.42 + (k % 2) * 0.13, 0.26, -0.01 + (k / 2) * 0.12), white, 8)
	# Semsiye: kirmizi-beyaz dilimli
	Kit.cyl(r, 0.018, 0.018, 1.25, Vector3(-0.66, 2.2, -0.36), chrome, 8)
	var um := Kit.checker(Color("d61a32"), Color("fbf7f0"), 8, 1)
	um.cull_mode = BaseMaterial3D.CULL_DISABLED
	um.roughness = 0.7
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 1.05
	cone.height = 0.36
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	Kit.add(r, cone, um, Vector3(-0.66, 2.72, -0.36))
	# Simitci: arabanin arkasinda, musteriye donuk
	var v := _person("erkek", "f4f2ee", "2b2f38")
	v.position = Vector3(-0.1, 0, -0.95)
	r.add_child(v)
	# Kollar, govde: carpisma
	var fwd := face
	var side := Vector2(face.y, -face.x)
	w._add_circle(Vector3(p.x + side.x * 0.45, p.y + side.y * 0.45, 0.55))
	w._add_circle(Vector3(p.x - side.x * 0.45, p.y - side.y * 0.45, 0.55))
	carts.append({"root": r, "pos": p, "front": p + fwd * 1.15, "yaw": yaw, "vendor": v})


# ---------------------------------------------------------------- cay ocagi

func _build_tea_garden(p: Vector2, face: Vector2) -> void:
	var w: Node3D = m.world
	var yaw := _yaw(face)
	var r: Node3D = w._root(p, yaw)
	var wood := Kit.mat("7a4a2a", 0.7)
	var wood2 := Kit.mat("a8703f", 0.65)
	var steel := Kit.mat("cfd3d8", 0.2)
	steel.metallic = 0.9
	var brass := Kit.mat("c79a3a", 0.25)
	brass.metallic = 0.85
	var green := Kit.mat("2e6f4a", 0.6)
	# Zemin: araziye oturan tas doseme
	var stone := _paving_mat()
	_ground_patch(r, Rect2(-4.2, -4.0, 8.4, 7.4), stone)
	w.paved.append([Transform2D(Vector2(face.y, -face.x), face, p).affine_inverse(), Rect2(-4.4, -4.2, 8.8, 7.8)])
	# Ocak: tezgah, arka duvar, raf, tente (kendi pivotunda, en yuksek zemine gore)
	var cz := -2.9
	var kh := -1e9
	for lp in [Vector2(-1.5, cz - 0.7), Vector2(1.5, cz - 0.7), Vector2(-1.5, cz + 0.5), Vector2(1.5, cz + 0.5), Vector2(0, cz)]:
		kh = maxf(kh, _hl(r, lp))
	var k := Kit.pivot(r, Vector3(0, kh, 0))
	Kit.box(k, Vector3(2.6, 1.56, 0.78), Vector3(0, 0.18, cz), wood)
	for i in 5:
		Kit.box(k, Vector3(0.04, 0.8, 0.02), Vector3(-1.0 + i * 0.5, 0.5, cz + 0.4), wood2)
	Kit.box(k, Vector3(2.7, 0.05, 0.86), Vector3(0, 0.985, cz), Kit.mat("e9e2d4", 0.3))
	Kit.box(k, Vector3(2.9, 3.1, 0.1), Vector3(0, 0.95, cz - 0.62), Kit.mat("dccdb0", 0.9))
	Kit.box(k, Vector3(2.92, 0.4, 0.12), Vector3(0, 0.2, cz - 0.62), green)
	Kit.box(k, Vector3(2.0, 0.08, 1.0), Vector3(0, -0.04, cz - 0.15), Kit.mat("8f8577", 0.9))
	for sh in 2:
		Kit.box(k, Vector3(2.0, 0.035, 0.24), Vector3(0, 1.45 + sh * 0.38, cz - 0.48), wood2)
	# Rafta dizili bardaklar
	var glass_x: Array = []
	for sh in 2:
		for i in 14:
			glass_x.append(Transform3D(Basis(), Vector3(-0.9 + i * 0.138, 1.47 + sh * 0.38 + 0.035, cz - 0.48)))
	var gmesh := CylinderMesh.new()
	gmesh.top_radius = 0.025
	gmesh.bottom_radius = 0.018
	gmesh.height = 0.075
	gmesh.radial_segments = 10
	gmesh.rings = 1
	_multi(k, gmesh, _glass_mat, glass_x)
	# Tente: yesil-beyaz cizgili, one egimli
	var aw := Kit.checker(Color("2e7d4f"), Color("f4f1e8"), 12, 1)
	aw.cull_mode = BaseMaterial3D.CULL_DISABLED
	aw.roughness = 0.8
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.2, 1.5)
	Kit.add(k, pm, aw, Vector3(0, 2.45, cz + 0.1), Vector3(0.38, 0, 0))
	var qm := QuadMesh.new()
	qm.size = Vector2(3.2, 0.24)
	Kit.add(k, qm, aw, Vector3(0, 2.07, cz + 0.8))
	for sx in [-1.5, 1.5]:
		Kit.cyl(k, 0.035, 0.035, 3.0, Vector3(sx, 0.95, cz + 0.75), Kit.mat("3a3a3a", 0.5), 8)
	# Tabela
	Kit.box(k, Vector3(2.6, 0.42, 0.06), Vector3(0, 2.95, cz - 0.6), green)
	_label(k, "ÇINARALTI ÇAY OCAĞI", Vector3(0, 2.95, cz - 0.565), 0.2, Color("ffe7a8"))
	# Semaver (pirinc) ve iki katli caydanlik
	var sm := Kit.pivot(k, Vector3(-0.75, 1.01, cz - 0.05))
	Kit.cyl(sm, 0.15, 0.17, 0.08, Vector3(0, 0.04, 0), brass, 16)
	Kit.cyl(sm, 0.19, 0.15, 0.42, Vector3(0, 0.29, 0), brass, 16)
	Kit.cyl(sm, 0.12, 0.19, 0.08, Vector3(0, 0.54, 0), brass, 16)
	Kit.cyl(sm, 0.04, 0.05, 0.12, Vector3(0, 0.64, 0), brass, 10)
	Kit.ball(sm, 0.035, Vector3(0, 0.72, 0), brass)
	Kit.cyl(sm, 0.015, 0.015, 0.14, Vector3(0, 0.22, 0.2), brass, 8, Vector3(PI / 2, 0, 0))
	Kit.box(sm, Vector3(0.03, 0.05, 0.03), Vector3(0, 0.25, 0.27), Kit.mat("1d1d1d", 0.5))
	for sx in [-1.0, 1.0]:
		Kit.torus(sm, 0.04, 0.055, Vector3(sx * 0.2, 0.42, 0), brass, Vector3(0, 0, PI / 2))
	var ct := Kit.pivot(k, Vector3(0.35, 1.01, cz - 0.05))
	Kit.cyl(ct, 0.16, 0.16, 0.05, Vector3(0, 0.025, 0), Kit.mat("2a2a2a", 0.6), 16)   # ocak
	Kit.cyl(ct, 0.13, 0.15, 0.24, Vector3(0, 0.17, 0), steel, 16)
	Kit.cyl(ct, 0.09, 0.13, 0.04, Vector3(0, 0.31, 0), steel, 16)
	Kit.cyl(ct, 0.075, 0.09, 0.14, Vector3(0, 0.4, 0), steel, 14)
	Kit.cyl(ct, 0.05, 0.075, 0.03, Vector3(0, 0.485, 0), steel, 14)
	Kit.ball(ct, 0.022, Vector3(0, 0.51, 0), Kit.mat("1d1d1d", 0.5))
	Kit.cyl(ct, 0.012, 0.022, 0.16, Vector3(0.0, 0.42, 0.12), steel, 8, Vector3(-0.9, 0, 0))
	Kit.cyl(ct, 0.016, 0.026, 0.2, Vector3(0.0, 0.17, 0.18), steel, 8, Vector3(-1.0, 0, 0))
	Kit.torus(ct, 0.08, 0.1, Vector3(0, 0.52, -0.02), Kit.mat("1d1d1d", 0.5), Vector3(PI / 2, 0, 0))
	_steam(ct, Vector3(0, 0.52, 0.0))
	# Tezgahta tepsi ve bardaklar, seker kasesi
	Kit.cyl(k, 0.2, 0.2, 0.012, Vector3(0.95, 1.016, cz + 0.05), Kit.mat("b8b8b8", 0.25), 20)
	for i in 4:
		tea_glass(k, Vector3(0.88 + (i % 2) * 0.14, 1.022, cz - 0.02 + (i / 2) * 0.14), i != 3, true)
	Kit.cyl(k, 0.06, 0.045, 0.06, Vector3(-0.15, 1.04, cz + 0.15), Kit.mat("f4f1ea", 0.3), 12)
	# Isik zinciri: dort direk, aralarinda ampuller
	var poles := [Vector2(-3.9, -2.4), Vector2(3.9, -2.4), Vector2(3.9, 2.9), Vector2(-3.9, 2.9)]
	var tops: Array = []
	for pp in poles:
		var h := _hl(r, pp)
		Kit.cyl(r, 0.04, 0.05, 2.9, Vector3(pp.x, h + 1.25, pp.y), Kit.mat("3a3a3a", 0.5), 8)
		tops.append(Vector3(pp.x, h + 2.62, pp.y))
	var bulb := SphereMesh.new()
	bulb.radius = 0.035
	bulb.height = 0.07
	bulb.radial_segments = 8
	bulb.rings = 4
	var bx: Array = []
	var wire := Kit.mat("222222", 0.6)
	for i in 4:
		var a: Vector3 = tops[i]
		var b: Vector3 = tops[(i + 1) % 4]
		var n := int(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) / 0.55)
		var prev := a
		for j in range(1, n + 1):
			var f := float(j) / float(n)
			var cur := a.lerp(b, f) - Vector3(0, sin(f * PI) * 0.35, 0)
			var mid := (prev + cur) * 0.5
			var seg := Kit.box(r, Vector3(0.012, 0.012, prev.distance_to(cur)), mid, wire)
			seg.look_at_from_position(r.to_global(mid), r.to_global(cur), Vector3.UP)
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if j < n:
				bx.append(Transform3D(Basis(), cur + Vector3(0, -0.07, 0)))
			prev = cur
	var bm := _multi(r, bulb, _bulb_mat, bx)
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.position = Vector3(0, _hl(r, Vector2.ZERO) + 2.4, 0.2)
	light.omni_range = 8.5
	light.light_color = Color("ffc777")
	light.light_energy = 0.0
	light.shadow_enabled = false
	r.add_child(light)
	# Masalar ve hasir tabureler
	var stools: Array = []
	var tables := [Vector2(-2.3, 0.2), Vector2(0.2, 1.4), Vector2(2.5, -0.1), Vector2(-1.2, 2.4)]
	var cloth := Kit.mat("e9e1cf", 0.85)
	for ti in tables.size():
		var t: Vector2 = tables[ti]
		var th := _hl(r, t)
		Kit.box(r, Vector3(0.6, 0.035, 0.6), Vector3(t.x, th + 0.52, t.y), wood2)
		Kit.box(r, Vector3(0.62, 0.006, 0.62), Vector3(t.x, th + 0.541, t.y), cloth if ti % 2 == 0 else Kit.mat("b8433a", 0.85))
		for sx in [-0.25, 0.25]:
			for sz in [-0.25, 0.25]:
				Kit.box(r, Vector3(0.035, 0.7, 0.035), Vector3(t.x + sx, th + 0.17, t.y + sz), wood)
		var around := [Vector2(0, 0.62), Vector2(0, -0.62), Vector2(0.62, 0), Vector2(-0.62, 0)]
		for ai in (4 if ti != 3 else 3):
			var off: Vector2 = around[ai]
			var sp: Vector2 = t + off.rotated(0.12 * ti)
			var sh := _hl(r, sp)
			_stool(r, sp, sh)
			var to_t := t - sp
			stools.append({"local": sp, "h": sh, "yaw_l": atan2(-to_t.x, -to_t.y), "table": ti, "busy": false})
		# Masada bos / dolu bardaklar ve seker
		if ti != 1:
			tea_glass(r, Vector3(t.x + 0.12, th + 0.544, t.y - 0.1), ti == 2, true)
		Kit.box(r, Vector3(0.022, 0.022, 0.022), Vector3(t.x - 0.08, th + 0.556, t.y + 0.1), Kit.mat("ffffff", 0.6))
		Kit.box(r, Vector3(0.022, 0.022, 0.022), Vector3(t.x - 0.05, th + 0.556, t.y + 0.12), Kit.mat("ffffff", 0.6))
		w._add_circle(_wc(r, t, 0.3))
	# Tavla (2. masada)
	var t2: Vector2 = tables[2]
	var tv := Kit.pivot(r, Vector3(t2.x - 0.05, _hl(r, t2) + 0.545, t2.y + 0.05))
	Kit.box(tv, Vector3(0.44, 0.03, 0.3), Vector3(0, 0.015, 0), Kit.mat("5a3418", 0.6))
	Kit.box(tv, Vector3(0.4, 0.02, 0.26), Vector3(0, 0.022, 0), Kit.mat("d8b47a", 0.7))
	for i in 6:
		Kit.prism(tv, Vector3(0.03, 0.002, 0.1), Vector3(-0.17 + i * 0.034, 0.033, -0.07), Kit.mat("8a2b1d", 0.7), Vector3(-PI / 2, 0, 0))
		Kit.prism(tv, Vector3(0.03, 0.002, 0.1), Vector3(-0.17 + i * 0.034, 0.033, 0.07), Kit.mat("2b2b2b", 0.7), Vector3(PI / 2, 0, 0))
	for i in 5:
		Kit.cyl(tv, 0.016, 0.016, 0.008, Vector3(0.05 + (i % 3) * 0.035, 0.04, -0.08 + (i / 3) * 0.033), Kit.mat("f4f1ea" if i % 2 else "3a2016", 0.5), 10)
	# Tezgah carpismasi
	for sx in [-0.8, 0.0, 0.8]:
		w._add_circle(_wc(r, Vector2(sx, cz - 0.1), 0.62))
	# Caycı: tezgahin arkasinda
	var cayci := _person("erkek", "fbfbf8", "1e2228")
	var home := Vector3(-0.2, 0, cz - 0.35)
	cayci.position = Vector3(home.x, kh, home.z)
	r.add_child(cayci)
	# Masada oturan iki musteri (tavla oynuyorlar)
	for i in [0, 1]:
		var st: Dictionary = stools[8 + i]
		st["busy"] = true
		var v := _person("erkek", ["6b7d93", "8b5a3c"][i], ["2b2f38", "3b3b3b"][i])
		v.seated = true
		v.position = Vector3(st["local"].x, st["h"] + _seat_y, st["local"].y)
		v.rotation.y = st["yaw_l"]
		r.add_child(v)
		_sitters.append([v, null])
	for st in stools:
		st["pos"] = _w2(r, st["local"])
		st["yaw"] = st["yaw_l"] + yaw
	tea = {"root": r, "pos": p, "yaw": yaw, "counter": _w2(r, Vector2(0, cz + 0.95)), "stools": stools,
		"cayci": cayci, "home": home, "kh": kh, "light": light, "tables": tables}


## Tas doseme dokusu: 4x4 karo, derz cizgileri, karo basina hafif renk farki (2 m'de bir tekrar).
func _paving_mat() -> StandardMaterial3D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tiles: Array = []
	for i in 16:
		tiles.append(rng.randf_range(-0.05, 0.05))
	for y in n:
		for x in n:
			var tx := x / 32
			var ty := y / 32
			var lx := x % 32
			var ly := y % 32
			var c := Color("a59a86").lightened(tiles[ty * 4 + tx]) if tiles[ty * 4 + tx] > 0 else Color("a59a86").darkened(-tiles[ty * 4 + tx])
			c = c.darkened(rng.randf() * 0.06)
			if lx < 2 or ly < 2:
				c = Color("6f675b")
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = ImageTexture.create_from_image(img)
	mt.roughness = 0.92
	return mt


## Yerel noktadaki arazi yuksekligi (kok dugume gore).
func _hl(r: Node3D, local: Vector2) -> float:
	return ParkMap.terrain_height(_w2(r, local)) - r.global_position.y


## Araziye oturan dosemeli zemin (izgara agi).
func _ground_patch(r: Node3D, rect: Rect2, mat: Material) -> void:
	var nx := 14
	var nz := 12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz + 1:
		for ix in nx + 1:
			var u := float(ix) / nx
			var v := float(iz) / nz
			var lp := rect.position + rect.size * Vector2(u, v)
			st.set_uv(lp * 0.5)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(lp.x, _hl(r, lp) + 0.07, lp.y))
	for iz in nz:
		for ix in nx:
			var i0 := iz * (nx + 1) + ix
			st.add_index(i0)
			st.add_index(i0 + 1)
			st.add_index(i0 + nx + 1)
			st.add_index(i0 + 1)
			st.add_index(i0 + nx + 2)
			st.add_index(i0 + nx + 1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(mi)
	# Kenar: alcak tas bordur
	var curb := Kit.mat("9c917e", 0.9)
	var e := rect.end
	var q := rect.position
	for seg in [[Vector2(q.x, q.y), Vector2(e.x, q.y)], [Vector2(e.x, q.y), Vector2(e.x, e.y)], [Vector2(e.x, e.y), Vector2(q.x, e.y)], [Vector2(q.x, e.y), Vector2(q.x, q.y)]]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var n := int(a.distance_to(b) / 1.2) + 1
		for j in n:
			var c := a.lerp(b, (j + 0.5) / n)
			var ln := a.distance_to(b) / n
			var bx := Kit.box(r, Vector3(ln + 0.02 if absf(a.y - b.y) < 0.01 else 0.12, 0.22, 0.12 if absf(a.y - b.y) < 0.01 else ln + 0.02), Vector3(c.x, _hl(r, c) + 0.02, c.y), curb)
			bx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


var _weave: StandardMaterial3D

func _stool(r: Node3D, sp: Vector2, h: float) -> void:
	if _weave == null:
		_weave = Kit.checker(Color("d4b06c"), Color("b98f4a"), 6, 6)
	var leg := Kit.mat("6b3e22", 0.7)
	for sx in [-0.12, 0.12]:
		for sz in [-0.12, 0.12]:
			Kit.box(r, Vector3(0.03, 0.5, 0.03), Vector3(sp.x + sx, h + 0.13, sp.y + sz), leg)
	Kit.box(r, Vector3(0.32, 0.05, 0.32), Vector3(sp.x, h + 0.39, sp.y), Kit.mat("c9a35f", 0.95))
	Kit.box(r, Vector3(0.33, 0.012, 0.33), Vector3(sp.x, h + 0.41, sp.y), _weave)


func _steam(parent: Node3D, at: Vector3) -> void:
	var pt := CPUParticles3D.new()
	pt.position = at
	pt.amount = 10
	pt.lifetime = 2.4
	pt.local_coords = false
	pt.direction = Vector3.UP
	pt.spread = 12.0
	pt.gravity = Vector3(0.05, 0.22, 0)
	pt.initial_velocity_min = 0.12
	pt.initial_velocity_max = 0.22
	pt.scale_amount_min = 0.6
	pt.scale_amount_max = 1.2
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.6))
	pt.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.35))
	g.set_color(1, Color(1, 1, 1, 0.0))
	pt.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var gt := GradientTexture2D.new()
	var rg := Gradient.new()
	rg.set_color(0, Color(1, 1, 1, 1))
	rg.set_color(1, Color(1, 1, 1, 0))
	gt.gradient = rg
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = gt
	q.material = mat
	pt.mesh = q
	parent.add_child(pt)


func _w2(r: Node3D, local: Vector2) -> Vector2:
	var g := r.global_transform * Vector3(local.x, 0, local.y)
	return Vector2(g.x, g.z)


func _wc(r: Node3D, local: Vector2, rad: float) -> Vector3:
	var g := _w2(r, local)
	return Vector3(g.x, g.y, rad)


# ---------------------------------------------------------------- etkilesim

## Baglam ipucu: [metin, komut, simge] ya da bos.
func context() -> Array:
	if m._ride != null or m._taxi != null or ParkMap.home != null:
		return []
	if is_seated():
		if not _serve.is_empty():
			return ["Çayın geliyor…", "", "sit"]
		if seat["has_tea"]:
			return ["Çay keyfi · kalkmak için yürü", "food_up", "sit"]
		return ["Bir Çay Daha · %d ₺" % ITEMS["cay"][1], "food_order", "sit"]
	var o: Vector2 = m._owner_pos()
	for i in carts.size():
		if o.distance_to(carts[i]["front"]) < 2.0 or o.distance_to(carts[i]["pos"]) < 1.9:
			return ["Simitçi · Simit %d ₺" % ITEMS["simit"][1], "food_cart:%d" % i, "bag"]
	if tea.is_empty() or o.distance_to(tea["pos"]) > 7.0:
		return []
	if o.distance_to(tea["counter"]) < 1.5:
		return ["Çaycı · Çay %d ₺" % ITEMS["cay"][1], "food_tea", "drop"]
	var best := -1
	var bd := 0.85
	for i in tea["stools"].size():
		var st: Dictionary = tea["stools"][i]
		var d := o.distance_to(st["pos"])
		if not st["busy"] and d < bd:
			bd = d
			best = i
	if best >= 0:
		return ["Tabureye Otur · Çay İç", "food_sit:%d" % best, "sit"]
	return []


func command(cmd: String) -> void:
	if cmd.begins_with("food_cart:"):
		open_menu("cart")
	elif cmd == "food_tea":
		open_menu("tea")
	elif cmd.begins_with("food_sit:"):
		sit(int(cmd.substr(9)), true)
	elif cmd == "food_order":
		order_tea()
	elif cmd == "food_up":
		stand_up()
	elif cmd == "food_app":
		phone_app()


func open_menu(where: String) -> void:
	var cart := where == "cart"
	var body: VBoxContainer = m.ui._open_panel("SİMİTÇİ" if cart else "ÇAY OCAĞI",
		("Taze gevrek, sıcak poğaça · Cüzdan %d ₺" if cart else "Çınaraltı · Demli çay, taze simit · Cüzdan %d ₺") % int(state.d["coins"]))
	if not cart:
		m.ui._panel_item(body, "Çay İç, Otur · %d ₺" % ITEMS["cay"][1], func():
			m.ui.close_modal()
			var i := _free_stool(m._owner_pos())
			if i < 0:
				m.ui.toast("Boş tabure kalmadı, biraz bekle.")
			else:
				sit(i, true))
	m.ui._panel_item(body, "Simit Ye · %d ₺" % ITEMS["simit"][1], func(): buy("simit", false))
	m.ui._panel_item(body, "Simit Al (Çantaya) · %d ₺" % ITEMS["simit"][1], func(): buy("simit", true))
	m.ui._panel_item(body, "Poğaça Ye · %d ₺" % ITEMS["pogaca"][1], func(): buy("pogaca", false))
	if cart:
		m.ui._panel_item(body, "Poğaça Al (Çantaya) · %d ₺" % ITEMS["pogaca"][1], func(): buy("pogaca", true))
		m.ui._panel_item(body, "Ayran İç · %d ₺" % ITEMS["ayran"][1], func(): buy("ayran", false))
		m.ui._panel_item(body, "Ayran Al (Çantaya) · %d ₺" % ITEMS["ayran"][1], func(): buy("ayran", true))
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func buy(id: String, to_bag: bool) -> void:
	var it: Array = ITEMS[id]
	if not state.spend(int(it[1])):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % int(it[1]))
		return
	m.ui.close_modal()
	m._sfx("kasa", -8.0)
	state.count("shop")
	var nm: String = it[0]
	if to_bag:
		var bag: Dictionary = state.d.get("bag", {})
		bag[nm] = int(bag.get(nm, 0)) + 1
		state.d["bag"] = bag
		m.ui.toast("%s çantana kondu · Çanta: %d" % [nm, int(bag[nm])])
	else:
		_face_vendor()
		m._use_item(nm)
	_vendor_say(["Afiyet olsun!", "Güle güle ye!", "Yine bekleriz!"][randi() % 3])
	state.save_game()


func _face_vendor() -> void:
	var o: Vector2 = m._owner_pos()
	var best := Vector2.INF
	for c in carts:
		if o.distance_to(c["pos"]) < o.distance_to(best):
			best = c["pos"]
	if not tea.is_empty() and o.distance_to(tea["counter"]) < o.distance_to(best):
		best = tea["counter"]
	if best != Vector2.INF:
		var d := best - o
		m.owner_node.rotation.y = atan2(-d.x, -d.y)


func _vendor_say(text: String) -> void:
	var o: Vector2 = m._owner_pos()
	var who: Node3D = null
	var bd := 6.0
	for c in carts:
		var d := o.distance_to(c["pos"])
		if d < bd:
			bd = d
			who = c["vendor"]
	if not tea.is_empty() and o.distance_to(tea["pos"]) < bd + 3.0:
		who = tea["cayci"]
	if who:
		m._say(who, text)
		if who is Node3D and who.has_method("act"):
			who.act("wave", 1.2)


func _free_stool(near: Vector2) -> int:
	var best := -1
	var bd := 1e9
	for i in tea["stools"].size():
		var st: Dictionary = tea["stools"][i]
		var d := near.distance_to(st["pos"])
		if not st["busy"] and d < bd:
			bd = d
			best = i
	return best


# ---------------------------------------------------------------- oturma

func sit(i: int, order := true) -> void:
	if tea.is_empty() or is_seated() or i < 0 or i >= tea["stools"].size():
		return
	var st: Dictionary = tea["stools"][i]
	if st["busy"]:
		return
	st["busy"] = true
	m._moving = false
	m._queue.clear()
	m._steering = false
	m.owner_model.speed = 0.0
	var glass := tea_glass(m.owner_model.hand, Vector3.ZERO, false, false)
	glass.visible = false
	seat = {"i": i, "t": 0.0, "glass": glass, "has_tea": false, "sips": 0, "sip_t": 2.0, "warm": 0.0}
	_place_seated()
	m.owner_model.seated = true
	# Hayvanlar yanina uzanir
	var k := 0
	var side := Vector2.from_angle(-float(st["yaw"])) * 0.75
	for kind in m.agents:
		var a: Node3D = m.agents[kind]
		a.command("lie")
		var ap: Vector2 = st["pos"] + side * (1.0 + 0.7 * k) + Vector2(0.15, 0.1) * k
		if not m.world.is_free(ap, 0.25):
			ap = st["pos"] - side * (1.0 + 0.7 * k)
		a.place(ap)
		a.rotation.y = float(st["yaw"]) + PI * 0.5
		k += 1
	var pn: String = state.pet(m._active().kind)["name"]
	m.ui.toast("Tabureye oturdun. %s yanına uzandı. Kalkmak için yürü." % pn)
	m.ui._actions.visible = false
	if order:
		order_tea()
	m._update_context()


func _place_seated() -> void:
	var st: Dictionary = tea["stools"][seat["i"]]
	var sp: Vector2 = st["pos"]
	m.owner_node.position = Vector3(sp.x, tea["root"].global_position.y + float(st["h"]), sp.y)
	m.owner_node.rotation = Vector3(0, float(st["yaw"]), 0)
	m.owner_model.position = Vector3(0, _seat_y, 0)
	m._target = sp


func order_tea() -> void:
	if not is_seated() or not _serve.is_empty() or seat["has_tea"]:
		return
	var price: int = ITEMS["cay"][1]
	if not state.spend(price):
		m.ui.toast("Çay için %d ₺ gerekli." % price)
		return
	m._sfx("kasa", -10.0)
	var cayci: Node3D = tea["cayci"]
	m._say(cayci, ["Hemen geliyor!", "Bir çay, tavşan kanı!", "Geliyor abi!"][randi() % 3])
	var st: Dictionary = tea["stools"][seat["i"]]
	var tl: Vector2 = tea["tables"][st["table"]]
	var to_l: Vector2 = st["local"] + (tl - st["local"]).normalized().rotated(PI * 0.5) * 0.55
	var tray := Kit.pivot(cayci, Vector3(0.0, 1.05, -0.32))
	tray.name = "Tepsi"
	Kit.cyl(tray, 0.17, 0.17, 0.012, Vector3.ZERO, Kit.mat("b8b8b8", 0.25), 18)
	tea_glass(tray, Vector3(0, 0.006, 0), true, true)
	var cz: float = tea["home"].z
	var way: Array = [Vector2(1.65, cz), Vector2(1.65, cz + 1.0)]
	var path: Array = way.duplicate()
	path.append(to_l)
	_serve = {"phase": 0, "from": Vector2(tea["home"].x, tea["home"].z), "way": way, "path": path, "t": 0.6, "tray": tray}
	m._update_context()


func stand_up() -> void:
	if not is_seated():
		return
	var st: Dictionary = tea["stools"][seat["i"]]
	st["busy"] = false
	if is_instance_valid(seat["glass"]):
		seat["glass"].queue_free()
	seat = {}
	m.owner_model.seated = false
	m.owner_model.position = Vector3.ZERO
	var tl: Vector2 = tea["tables"][st["table"]]
	var away: Vector2 = (st["local"] - tl).normalized()
	var out: Vector2 = _w2(tea["root"], st["local"] + away * 0.45)
	m.owner_node.position = Vector3(out.x, ParkMap.walk_height(out), out.y)
	m._target = out
	for kind in m.agents:
		m.agents[kind].command("come")
	m.ui._actions.visible = true
	m._update_context()


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	if tea.is_empty() and carts.is_empty():
		return
	var o: Vector2 = m._owner_pos()
	# Gece: ampuller ve isik
	if not tea.is_empty():
		var nt: float = m.night
		_bulb_mat.emission_energy_multiplier = lerpf(0.5, 4.0, nt)
		(tea["light"] as OmniLight3D).light_energy = 1.8 * nt
		(tea["light"] as OmniLight3D).visible = nt > 0.05 and o.distance_to(tea["pos"]) < 80.0
	_update_serve(dt)
	_update_sitters(dt)
	# Saticilarin seslenmesi
	_call_t -= dt
	if _call_t <= 0.0 and m._mode == "play":
		_call_t = randf_range(9.0, 16.0)
		for c in carts:
			if o.distance_to(c["pos"]) < 14.0 and o.distance_to(c["pos"]) > 2.5:
				m._say(c["vendor"], CART_CALLS[randi() % CART_CALLS.size()])
				c["vendor"].act("wave", 1.4)
				break
		if not tea.is_empty() and not is_seated() and _serve.is_empty() and o.distance_to(tea["pos"]) < 12.0 and o.distance_to(tea["pos"]) > 3.0:
			m._say(tea["cayci"], TEA_CALLS[randi() % TEA_CALLS.size()])
	# Saticilar yaklasan oyuncuya doner
	for c in carts:
		if o.distance_to(c["pos"]) < 6.0:
			var v: Node3D = c["vendor"]
			var lp: Vector3 = (c["root"] as Node3D).to_local(m.owner_node.global_position)
			var want := atan2(-(lp.x - v.position.x), -(lp.z - v.position.z))
			v.rotation.y = lerp_angle(v.rotation.y, want, minf(1.0, dt * 3.0))
	if not is_seated():
		return
	# Oturuyor: hareket edince kalk
	seat["t"] += dt
	if (m._mode != "play" and m._mode != "debug") or m._ride != null or m._jump_h > 0.0 or (seat["t"] > 0.6 and (m.ui.stick.length() > 0.5 or m._moving)):
		stand_up()
		return
	_place_seated()
	var glass: Node3D = seat["glass"]
	if is_instance_valid(glass):
		glass.global_basis = Basis().scaled(Vector3.ONE * 1.1)
	if seat["has_tea"]:
		# Saat hizli akar, hayvanlar dinlenir ve neselenir
		m.clock = fposmod(m.clock + dt * 24.0 / m.DAY_SECONDS * (TIME_BOOST - 1.0), 24.0)
		for kind in m.agents:
			state.add_need(kind, "fun", 0.45 * dt)
			state.add_need(kind, "energy", 0.9 * dt)
		seat["sip_t"] -= dt
		if seat["sip_t"] <= 0.0:
			seat["sip_t"] = SIP_EVERY
			seat["sips"] += 1
			m.owner_model.act("sip", 1.8)
			if seat["sips"] >= SIPS:
				get_tree().create_timer(1.4).timeout.connect(_tea_done)


func _tea_done() -> void:
	if not is_seated() or not seat["has_tea"]:
		return
	seat["has_tea"] = false
	var tn: Node3D = seat["glass"].get_node_or_null("Cay")
	if tn:
		tn.visible = false
	state.count("tea")
	print("CAY BITTI saat=", snappedf(m.clock, 0.01))
	var a: Node3D = m._active()
	state.add_need(a.kind, "fun", 6.0)
	m.ui.toast("Çay bitti, oh be! %s de dinlendi. Bir çay daha? [F]" % state.pet(a.kind)["name"])
	m._update_context()


func _update_serve(dt: float) -> void:
	if _serve.is_empty():
		return
	var cayci: Node3D = tea["cayci"]
	_serve["t"] -= dt
	if _serve["t"] > 0.0:
		cayci.speed = 0.0
		return
	var path: Array = _serve["path"]
	var cp := Vector2(cayci.position.x, cayci.position.z)
	var target: Vector2 = path[0]
	var d := target - cp
	var step := 1.3 * dt
	if d.length() <= step:
		cayci.position = Vector3(target.x, float(tea["kh"]) if target.y < float(tea["home"].z) + 0.3 else _hl(tea["root"], target), target.y)
		path.pop_front()
		if path.is_empty():
			if _serve["phase"] == 0:
				_deliver()
				_serve["phase"] = 1
				_serve["t"] = 1.0
				var back: Array = _serve["way"].duplicate()
				back.reverse()
				back.append(_serve["from"])
				_serve["path"] = back
			else:
				cayci.speed = 0.0
				cayci.rotation.y = 0.0
				_serve = {}
				m._update_context()
		return
	cp += d / d.length() * step
	cayci.position = Vector3(cp.x, maxf(_hl(tea["root"], cp), float(tea["kh"]) if cp.y < float(tea["home"].z) + 0.3 else -1e9), cp.y)
	cayci.rotation.y = lerp_angle(cayci.rotation.y, atan2(-d.x, -d.y), minf(1.0, dt * 8.0))
	cayci.speed = 1.3


func _deliver() -> void:
	var tray: Node3D = _serve.get("tray")
	if is_instance_valid(tray):
		tray.queue_free()
	var cayci: Node3D = tea["cayci"]
	cayci.act("feed", 1.0)
	m._say(cayci, ["Afiyet olsun!", "Buyur, taze demlendi!", "Şekerin tabakta!"][randi() % 3])
	if not is_seated():
		return
	seat["has_tea"] = true
	seat["sips"] = 0
	seat["sip_t"] = 1.5
	var g: Node3D = seat["glass"]
	g.visible = true
	var tn: Node3D = g.get_node_or_null("Cay")
	if tn:
		tn.visible = true
	print("CAY GELDI")
	m._sfx("mutlu", -12.0, 1.3)
	m.ui.toast("Çayın geldi! Yudumla, keyfine bak. Saat hızlı akıyor.")
	m._update_context()


func _update_sitters(dt: float) -> void:
	if _sitters.is_empty() or m.owner_node.position.distance_to(tea["root"].global_position) > 40.0:
		return
	for s in _sitters:
		var v: Node3D = s[0]
		if s[1] == null:
			s[1] = tea_glass(v.hand, Vector3.ZERO, true, false)
		var g: Node3D = s[1]
		g.global_basis = Basis().scaled(Vector3.ONE * 1.1)
		if not v.is_acting() and randf() < dt * 0.12:
			v.act("sip", 1.8)


# ---------------------------------------------------------------- telefon ve test

func phone_app() -> void:
	if tea.is_empty() and carts.is_empty():
		m.ui.toast("Bu bölgede çay ocağı ya da simitçi yok.")
		return
	var o: Vector2 = m._owner_pos()
	var body: VBoxContainer = m.ui._open_panel("SOKAK LEZZETLERİ", "Çay %d ₺ · Simit %d ₺ · Poğaça %d ₺ · Ayran %d ₺" % [ITEMS["cay"][1], ITEMS["simit"][1], ITEMS["pogaca"][1], ITEMS["ayran"][1]])
	if not tea.is_empty():
		var d := int(o.distance_to(tea["pos"]))
		m.ui._panel_item(body, "Çınaraltı Çay Ocağı · %d m" % d, func():
			m.ui.close_modal()
			m._set_nav(tea["counter"], "Çay Ocağı"))
	var best: Dictionary = {}
	for c in carts:
		if best.is_empty() or o.distance_to(c["pos"]) < o.distance_to(best["pos"]):
			best = c
	if not best.is_empty():
		m.ui._panel_item(body, "En Yakın Simitçi · %d m" % int(o.distance_to(best["pos"])), func():
			m.ui.close_modal()
			m._set_nav(best["front"], "Simitçi"))
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


## Test: cay ocaginda oturt, cayi hemen getir.
func debug_sit() -> void:
	if tea.is_empty():
		print("CAY OCAGI YOK")
		return
	var i := 0
	m._place_owner(tea["stools"][i]["pos"])
	sit(i, false)
	seat["has_tea"] = true
	var g: Node3D = seat["glass"]
	g.visible = true
	(g.get_node("Cay") as Node3D).visible = true
	seat["sip_t"] = 0.4
	print("CAY OTUR ", tea["stools"][i]["pos"], " ocak=", tea["pos"])


func debug_cart() -> void:
	if carts.is_empty():
		return
	var c: Dictionary = carts[0]
	m._place_owner(c["front"] + (c["front"] - c["pos"]).normalized() * 0.4)
	var d: Vector2 = c["pos"] - m._owner_pos()
	m.owner_node.rotation.y = atan2(-d.x, -d.y)
	m._cam_yaw = m.owner_node.rotation.y + 0.5
	for kind in m.agents:
		m.agents[kind].place(m._owner_pos() + Vector2(1.0, 0.6))
	print("SIMITCI ", c["pos"])
