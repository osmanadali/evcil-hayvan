extends RefCounted
## Polo ic mekani: govde kabugunun icine olculerek sigdirilmis, yuvarlak hatli parcalar.
## Arac uzayi (metre): +X sag, +Y yukari, on = -Z; surucu solda (x = -0.36).
## Govde olculeri (assets/models/polo.glb, 3.97 m): yarim genislik y<0.9'da 0.83, y=1.0'da 0.75,
## y=1.2'de 0.69, y=1.4'te 0.62; on cam tabani z=-1.0 / y=1.12, ust kenari z=-0.3 / y=1.50; tavan 1.53.
## Bu yuzden on panel yarim genisligi 0.69, ust yuzeyi y<=1.0; kapi dosemeleri x<=0.775.

const Kit = preload("res://scripts/kit.gd")
const CarPlay = preload("res://scripts/carplay.gd")
const DOOR_HINGE := Vector3(-0.85, 0.0, -0.671)     # surucu kapisi mentesesi (arac uzayi; car_body.gd HINGE ile ayni yer)


## Gosterge paneli (SubViewport icinde cizilir): devir saati, hiz saati, ortada sayisal hiz, vites, yakit.
class Cluster extends Control:
	var kmh := 0.0
	var rpm := 0.8
	var fuel := 1.0
	var gear := "P"
	var clock := "10:00"
	var font: Font

	func _ready() -> void:
		size = Vector2(512, 192)
		font = load("res://assets/fonts/Anton-Regular.ttf")

	func _dial(c: Vector2, r: float, maxv: float, step: float, label_every: int, val: float, unit: String, red_from: float) -> void:
		draw_circle(c, r + 5.0, Color("2a2d33"))
		draw_circle(c, r + 2.0, Color("07080a"))
		var a0 := deg_to_rad(140.0)
		var sweep := deg_to_rad(260.0)
		var n := int(round(maxv / step))
		for i in n + 1:
			var v := i * step
			var a := a0 + sweep * v / maxv
			var d := Vector2(cos(a), sin(a))
			var major := i % label_every == 0
			var col := Color("ff4a3a") if v >= red_from else Color("f2f4f8")
			draw_line(c + d * (r - (13.0 if major else 7.0)), c + d * (r - 1.0), col, 3.0 if major else 1.5, true)
			if major:
				var txt := str(int(v))
				var fs := 15
				var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, c + d * (r - 27.0) + Vector2(-w * 0.5, fs * 0.38), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var uw := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, c + Vector2(-uw * 0.5, r * 0.55), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("9aa3b0"))
		var an := a0 + sweep * clampf(val / maxv, 0.0, 1.0)
		var nd := Vector2(cos(an), sin(an))
		var side := Vector2(-nd.y, nd.x)
		draw_colored_polygon(PackedVector2Array([c - nd * 12.0 + side * 3.5, c + nd * (r - 9.0), c - nd * 12.0 - side * 3.5]), Color("ff5a1f"))
		draw_circle(c, 9.0, Color("1c1e22"))
		draw_circle(c, 5.0, Color("ff5a1f"))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0b0c0f"))
		_dial(Vector2(98, 98), 84.0, 7.0, 0.5, 2, rpm, "x1000 d/dk", 6.0)
		_dial(Vector2(414, 98), 84.0, 220.0, 10.0, 2, kmh, "km/sa", 999.0)
		# Orta ekran: sayisal hiz, vites, saat, yakit
		var r := Rect2(196, 22, 120, 150)
		draw_rect(r, Color("101a26"))
		draw_rect(r, Color("2c4a66"), false, 2.0)
		var txt := str(int(round(kmh)))
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54).x
		draw_string(font, Vector2(256 - w * 0.5, 86), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color("eaf6ff"))
		var uw := font.get_string_size("km/sa", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, Vector2(256 - uw * 0.5, 104), "km/sa", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("8fb4d6"))
		draw_string(font, Vector2(204, 42), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("8fb4d6"))
		var gw := font.get_string_size(gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, Vector2(308 - gw, 46), gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("ffd23c"))
		# Yakit: E ---- F
		var low := fuel < 0.15
		var fc := Color("e5483b") if low else Color("4cc46a")
		draw_string(font, Vector2(203, 162), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e5483b"))
		draw_string(font, Vector2(302, 162), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("eaf6ff"))
		draw_rect(Rect2(216, 150, 82, 12), Color("1d2a38"))
		draw_rect(Rect2(216, 150, 82.0 * clampf(fuel, 0.0, 1.0), 12), fc)
		for i in 5:
			draw_line(Vector2(216 + 20.5 * i, 146), Vector2(216 + 20.5 * i, 150), Color("8fb4d6"), 1.5)
		var yw := font.get_string_size("YAKIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2(256 - yw * 0.5, 140), "YAKIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fc.lightened(0.2))


## Cokgenin koselerini yuvarlatir (her kosede n parcali egri).
static func rounded(pts: Array, r: float, n := 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var cnt := pts.size()
	for i in cnt:
		var p: Vector2 = pts[i]
		var a: Vector2 = pts[(i + cnt - 1) % cnt]
		var b: Vector2 = pts[(i + 1) % cnt]
		var ra := minf(r, p.distance_to(a) * 0.45)
		var rb := minf(r, p.distance_to(b) * 0.45)
		var pa := p + (a - p).normalized() * ra
		var pb := p + (b - p).normalized() * rb
		for k in n + 1:
			var t := float(k) / n
			out.append(pa.lerp(p, t).lerp(p.lerp(pb, t), t))
	return out


## Kesiti (prof) bir eksen boyunca uzatir. axis 0: kesit (z, y), x boyunca; axis 2: kesit (x, y), z boyunca.
## Uclar hafif daraltilarak yuvarlatilir (bevel > 0).
static func extrude(parent: Node3D, prof: PackedVector2Array, a0: float, a1: float, axis: int, mat: Material, bevel := 0.03) -> MeshInstance3D:
	var cen := Vector2.ZERO
	for p in prof:
		cen += p
	cen /= prof.size()
	var stations: Array = [[a0, 1.0], [a1, 1.0]]
	if bevel > 0.0:
		var sc := 0.9
		stations = [[a0, sc], [a0 + bevel, 1.0], [a1 - bevel, 1.0], [a1, sc]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := prof.size()
	var at := func(si: int, i: int) -> Vector3:
		var p: Vector2 = cen + (prof[i % n] - cen) * float(stations[si][1])
		var a: float = stations[si][0]
		return Vector3(a, p.y, p.x) if axis == 0 else Vector3(p.x, p.y, a)
	st.set_smooth_group(0)
	for si in stations.size() - 1:
		for i in n:
			var v00: Vector3 = at.call(si, i)
			var v01: Vector3 = at.call(si, i + 1)
			var v10: Vector3 = at.call(si + 1, i)
			var v11: Vector3 = at.call(si + 1, i + 1)
			for v in [v00, v10, v11, v00, v11, v01]:
				st.add_vertex(v)
	st.set_smooth_group(1)
	for si in [0, stations.size() - 1]:
		var a: float = stations[si][0]
		var c3 := Vector3(a, cen.y, cen.x) if axis == 0 else Vector3(cen.x, cen.y, a)
		for i in n:
			st.add_vertex(c3)
			st.add_vertex(at.call(si, i))
			st.add_vertex(at.call(si, i + 1))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _m2(hex: String, rough: float) -> StandardMaterial3D:
	var m := Kit.mat(hex, rough)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _mirror_x(pts: Array, sx: float) -> Array:
	var out: Array = []
	for p: Vector2 in pts:
		out.append(Vector2(p.x * sx, p.y))
	return out


static func build() -> Node3D:
	var c := Node3D.new()
	c.set_meta("gosterge", true)
	var dash := _m2("26282c", 0.85)
	var soft := _m2("34363a", 0.95)
	var trim := _m2("1b1c1f", 0.6)
	var silver := Kit.mat("b9bcc0", 0.3)
	silver.metallic = 0.7
	var black := Kit.mat("101113", 0.45)
	var gloss := Kit.mat("08090a", 0.12)
	var fabric := Kit.mat("55585e", 1.0)
	var fabric2 := Kit.mat("3d4045", 1.0)
	var rubber := Kit.mat("17181a", 0.95)

	# ---- On panel: egri ustlu tek govde (kesit z, y), govde ic genisligine sigar
	var dprof := rounded([Vector2(-0.50, 0.70), Vector2(-0.515, 0.80), Vector2(-0.50, 0.90), Vector2(-0.535, 0.965),
		Vector2(-0.78, 0.995), Vector2(-1.0, 0.975), Vector2(-1.02, 0.62), Vector2(-0.80, 0.62)], 0.035)
	extrude(c, dprof, -0.69, 0.69, 0, dash, 0.05)
	# Ust yuzeyde yumusak dolgu (hafif kabarik, mat)
	var pad := Kit.ball(c, 1.0, Vector3(0.0, 0.978, -0.77), soft, Vector3(0.62, 0.028, 0.2), 20)
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Gosterge siperligi: surucunun onunde one uzanan egri sacak + yan yanaklar
	var cowl := rounded([Vector2(-0.44, 1.012), Vector2(-0.47, 1.047), Vector2(-0.62, 1.05), Vector2(-0.76, 0.985),
		Vector2(-0.60, 0.975), Vector2(-0.50, 0.995)], 0.02)
	extrude(c, cowl, -0.59, -0.13, 0, dash, 0.05)
	for cx in [-0.585, -0.135]:
		Kit.capsule(c, 0.022, 0.21, Vector3(cx, 0.925, -0.487), dash, Vector3(-0.3, 0, 0))
	# Gosterge paneli: SubViewport dokulu yuz (isikli, gece de okunur)
	var gvp := SubViewport.new()
	gvp.name = "GostergeVP"
	gvp.size = Vector2i(512, 192)
	gvp.transparent_bg = false
	gvp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cl := Cluster.new()
	cl.name = "G"
	gvp.add_child(cl)
	c.add_child(gvp)
	var gq := QuadMesh.new()
	gq.size = Vector2(0.40, 0.15)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_texture = gvp.get_texture()
	gm.albedo_color = Color(1.2, 1.2, 1.2)
	var gmi := Kit.add(c, gq, gm, Vector3(-0.36, 0.932, -0.485), Vector3(-0.3, 0, 0))
	gmi.name = "Gosterge"
	Kit.box(c, Vector3(0.43, 0.17, 0.03), Vector3(-0.36, 0.929, -0.502), black, Vector3(-0.3, 0, 0))

	# ---- Yan havalandirmalar (yuvarlak, kanatli) ve gumus serit (yolcu tarafi)
	for vx in [-0.615, 0.615]:
		Kit.torus(c, 0.04, 0.054, Vector3(vx, 0.905, -0.5), silver, Vector3(PI / 2, 0, 0))
		Kit.cyl(c, 0.042, 0.042, 0.012, Vector3(vx, 0.905, -0.503), black, 18, Vector3(PI / 2, 0, 0))
		for k in 3:
			Kit.box(c, Vector3(0.07, 0.006, 0.006), Vector3(vx, 0.885 + 0.02 * k, -0.495), trim)
	Kit.capsule(c, 0.008, 0.36, Vector3(0.37, 0.905, -0.497), silver, Vector3(0, 0, PI / 2))
	# Torpido: kapak cizgisi ve kolu
	for gy in [0.735, 0.865]:
		Kit.box(c, Vector3(0.40, 0.005, 0.006), Vector3(0.41, gy, -0.499 - (0.006 if gy > 0.8 else 0.0)), black)
	for gx in [0.21, 0.61]:
		Kit.box(c, Vector3(0.005, 0.13, 0.006), Vector3(gx, 0.80, -0.508), black)
	Kit.capsule(c, 0.007, 0.07, Vector3(0.41, 0.845, -0.502), silver, Vector3(0, 0, PI / 2))

	# ---- Orta konsol: buyuk ekran (surucuye donuk), havalandirmalar, klima dugmeleri
	var vp := SubViewport.new()
	vp.name = "CarPlayVP"
	vp.size = Vector2i(640, 300)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cp := CarPlay.new()
	cp.name = "CP"
	vp.add_child(cp)
	c.add_child(vp)
	var scr_root := Node3D.new()
	scr_root.name = "Ekran"
	scr_root.position = Vector3(0.04, 0.94, -0.468)
	scr_root.rotation = Vector3(-0.14, -0.3, 0)
	c.add_child(scr_root)
	var q := QuadMesh.new()
	q.size = Vector2(0.345, 0.162)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = vp.get_texture()
	sm.albedo_color = Color(1.35, 1.35, 1.35)
	Kit.add(scr_root, q, sm, Vector3(0, 0, 0.011))
	# Cerceve: yuvarlak koseli parlak siyah govde
	var bez := rounded([Vector2(-0.185, -0.093), Vector2(0.185, -0.093), Vector2(0.185, 0.093), Vector2(-0.185, 0.093)], 0.02)
	extrude(scr_root, bez, -0.012, 0.01, 2, gloss, 0.0)
	Kit.cyl(scr_root, 0.03, 0.045, 0.06, Vector3(0, -0.085, -0.035), dash, 12, Vector3(0.5, 0, 0))
	# Orta havalandirmalar (yuvarlak uclu) ve klima paneli
	for vx in [-0.085, 0.085]:
		var vent := Kit.capsule(c, 0.026, 0.15, Vector3(vx, 0.80, -0.508), black, Vector3(0, 0, PI / 2))
		vent.scale = Vector3(1, 1, 0.5)
		for k in 2:
			Kit.box(c, Vector3(0.11, 0.005, 0.005), Vector3(vx, 0.792 + 0.016 * k, -0.494), silver)
	var stack := rounded([Vector2(-0.49, 0.77), Vector2(-0.465, 0.62), Vector2(-0.40, 0.52), Vector2(-0.40, 0.40), Vector2(-0.62, 0.40), Vector2(-0.62, 0.77)], 0.025)
	extrude(c, stack, -0.13, 0.13, 0, trim, 0.02)
	for kx in [-0.075, 0.0, 0.075]:
		var ky := 0.705
		Kit.cyl(c, 0.021, 0.024, 0.022, Vector3(kx, ky, -0.468), black, 16, Vector3(PI / 2 - 0.16, 0, 0))
		Kit.torus(c, 0.019, 0.025, Vector3(kx, ky, -0.458), silver, Vector3(PI / 2 - 0.16, 0, 0))
	Kit.box(c, Vector3(0.2, 0.022, 0.004), Vector3(0, 0.655, -0.462), Kit.glow("16324a", 0.5), Vector3(-0.16, 0, 0))

	# ---- Orta tunel: yuvarlak hatli govde, vites kolu (koruklu), bardakliklar, el freni, kol dayama
	var tun := rounded([Vector2(-0.105, 0.38), Vector2(0.105, 0.38), Vector2(0.095, 0.60), Vector2(-0.095, 0.60)], 0.03)
	extrude(c, tun, -0.5, 0.5, 2, dash, 0.03)
	Kit.cyl(c, 0.062, 0.062, 0.006, Vector3(0, 0.603, -0.24), silver, 20)
	Kit.cyl(c, 0.055, 0.055, 0.008, Vector3(0, 0.604, -0.24), black, 20)
	Kit.cyl(c, 0.016, 0.046, 0.085, Vector3(0, 0.645, -0.24), Kit.mat("1f2023", 1.0), 12)
	Kit.cyl(c, 0.008, 0.008, 0.06, Vector3(0, 0.705, -0.24), silver, 8)
	Kit.ball(c, 0.03, Vector3(0, 0.745, -0.24), Kit.mat("232427", 0.4), Vector3(0.9, 1.15, 1.25))
	Kit.torus(c, 0.022, 0.027, Vector3(0, 0.728, -0.24), silver)
	var prnd := Label3D.new()
	prnd.text = "P R N D S"
	prnd.font_size = 24
	prnd.pixel_size = 0.0011
	prnd.modulate = Color("d0d4d8")
	prnd.position = Vector3(0.075, 0.606, -0.24)
	prnd.rotation = Vector3(-PI / 2, PI / 2, 0)
	c.add_child(prnd)
	for cz in [-0.08, 0.02]:
		Kit.torus(c, 0.034, 0.042, Vector3(0, 0.603, cz), silver)
		Kit.cyl(c, 0.034, 0.03, 0.01, Vector3(0, 0.6, cz), black, 16)
	var hb := Kit.capsule(c, 0.017, 0.2, Vector3(0.045, 0.635, 0.19), black, Vector3(PI / 2 - 0.2, 0, 0))
	hb.name = "ElFreni"
	Kit.cyl(c, 0.012, 0.012, 0.02, Vector3(0.045, 0.657, 0.085), silver, 10, Vector3(PI / 2 - 0.2, 0, 0))
	var arm := Kit.capsule(c, 0.045, 0.34, Vector3(-0.01, 0.63, 0.34), fabric2, Vector3(PI / 2, 0, 0))
	arm.scale = Vector3(1.7, 1.0, 1.0)

	# ---- Direksiyon (ayri model varsa o; yoksa cizilen uc kollu simit)
	var wheel := Node3D.new()
	wheel.name = "Direksiyon"
	wheel.position = Vector3(-0.36, 0.9, -0.32)
	c.add_child(wheel)
	if ResourceLoader.exists("res://assets/models/polo_ic.glb"):
		var wm: Node3D = load("res://assets/models/polo_ic.glb").instantiate()
		var k := 0.42
		var n := Vector3(-0.659, 0.403, 0.635).normalized()
		var up := (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
		var model_frame := Basis(up.cross(n).normalized(), up, n)
		var rb := model_frame.inverse()
		var spin := Node3D.new()
		spin.name = "Simit"
		wheel.add_child(spin)
		wm.transform = Transform3D(rb.scaled(Vector3.ONE * k), rb * (-Vector3(0.047, 0.566, 0.029)) * k)
		spin.add_child(wm)
		wheel.set_meta("model", true)
		wheel.rotation.x = -0.35
	else:
		wheel.rotation.x = -1.1
		Kit.torus(wheel, 0.16, 0.19, Vector3.ZERO, Kit.mat("1d1e21", 0.7), Vector3.ZERO)
		Kit.capsule(wheel, 0.02, 0.32, Vector3(0, 0, -0.01), soft, Vector3(0, 0, PI / 2))
		Kit.capsule(wheel, 0.02, 0.16, Vector3(0, 0, 0.08), soft, Vector3(PI / 2, 0, 0))
		Kit.cyl(wheel, 0.065, 0.07, 0.04, Vector3(0, 0.01, 0), Kit.mat("26282b", 0.6), 16)
	# Direksiyon kolonu kilifi
	Kit.capsule(c, 0.045, 0.24, Vector3(-0.36, 0.865, -0.43), dash, Vector3(PI / 2 - 0.35, 0, 0))
	# Sinyal ve silecek kollari
	for sx in [-1.0, 1.0]:
		Kit.capsule(c, 0.008, 0.13, Vector3(-0.36 + sx * 0.12, 0.875, -0.4), black, Vector3(0, 0, PI / 2 + sx * 0.25))

	# ---- Koltuklar
	for x in [-0.36, 0.36]:
		_seat(c, Vector3(x, 0.0, 0.0), fabric, fabric2)
	# Arka koltuk: yuvarlak minder ve sirt, uc baslik
	var bench := Kit.capsule(c, 0.09, 1.36, Vector3(0, 0.5, 1.05), fabric, Vector3(0, 0, PI / 2))
	bench.scale = Vector3(1.0, 1.0, 2.7)
	var bback := Kit.capsule(c, 0.075, 1.36, Vector3(0, 0.84, 1.3), fabric, Vector3(0.15, 0, PI / 2))
	bback.scale = Vector3(1.0, 1.0, 1.0)
	bback.scale = Vector3(3.9, 1.0, 1.0)
	for rx in [-0.44, 0.0, 0.44]:
		Kit.box(c, Vector3(0.3, 0.012, 0.4), Vector3(rx, 0.588, 1.05), fabric2)
		Kit.box(c, Vector3(0.28, 0.42, 0.012), Vector3(rx, 0.84, 1.222), fabric2, Vector3(0.15, 0, 0))
		var rh := Kit.capsule(c, 0.055, 0.22, Vector3(rx, 1.2, 1.36), fabric, Vector3(0, 0, PI / 2))
		rh.scale = Vector3(1.0, 1.0, 0.8)
		for hx in [-0.06, 0.06]:
			Kit.cyl(c, 0.007, 0.007, 0.1, Vector3(rx + hx, 1.12, 1.36), silver, 6)
	Kit.box(c, Vector3(1.2, 0.02, 0.26), Vector3(0, 0.97, 1.5), dash)

	# ---- Zemin, on duvar, paspaslar, pedallar, arka tekerlek kemerleri
	Kit.box(c, Vector3(1.5, 0.02, 2.5), Vector3(0, 0.38, 0.3), Kit.mat("232427", 1.0))
	Kit.box(c, Vector3(1.4, 0.4, 0.04), Vector3(0, 0.58, -1.02), dash)
	for mx in [-0.36, 0.36]:
		for mz in [-0.6, 0.74]:
			Kit.box(c, Vector3(0.44, 0.012, 0.46), Vector3(mx, 0.396, mz), rubber)
			Kit.box(c, Vector3(0.38, 0.006, 0.4), Vector3(mx, 0.404, mz), Kit.mat("2c2e31", 1.0))
			for k in 5:
				Kit.box(c, Vector3(0.34, 0.004, 0.012), Vector3(mx, 0.409, mz - 0.14 + 0.07 * k), rubber)
	# Pedallar: gaz (uzun), fren (genis), ayak dayama
	Kit.box(c, Vector3(0.045, 0.012, 0.13), Vector3(-0.255, 0.49, -0.85), black, Vector3(0.95, 0, 0))
	Kit.box(c, Vector3(0.085, 0.012, 0.06), Vector3(-0.39, 0.53, -0.84), black, Vector3(0.95, 0, 0))
	Kit.box(c, Vector3(0.075, 0.004, 0.05), Vector3(-0.39, 0.536, -0.836), silver, Vector3(0.95, 0, 0))
	Kit.cyl(c, 0.008, 0.008, 0.2, Vector3(-0.39, 0.62, -0.9), silver, 6, Vector3(0.5, 0, 0))
	Kit.box(c, Vector3(0.08, 0.012, 0.2), Vector3(-0.6, 0.47, -0.84), rubber, Vector3(0.8, 0, 0))
	for sx in [-1.0, 1.0]:
		var arch := Kit.ball(c, 1.0, Vector3(sx * 0.66, 0.42, 1.28), soft, Vector3(0.16, 0.3, 0.4))
		arch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ---- Kapi dosemeleri: yuvarlak kesitli panel (kol dayama cikintisi, cep), kapi kolu, cam dugmeleri, hoparlor
	var dp := [Vector2(0.775, 0.40), Vector2(0.775, 0.86), Vector2(0.735, 0.955), Vector2(0.705, 0.955), Vector2(0.715, 0.875),
		Vector2(0.668, 0.82), Vector2(0.663, 0.765), Vector2(0.725, 0.72), Vector2(0.735, 0.57), Vector2(0.70, 0.51), Vector2(0.70, 0.40)]
	# Surucu kapisinin dosemesi mentese dugumunde (KapiIc): kapi acilinca govdedeki kapiyla birlikte doner
	var kd := Node3D.new()
	kd.name = "KapiIc"
	kd.position = DOOR_HINGE
	c.add_child(kd)
	var kin := Node3D.new()
	kin.position = -DOOR_HINGE
	kd.add_child(kin)
	for sx in [-1.0, 1.0]:
		var fd: Node3D = kin if sx < 0.0 else c      # on kapi parcalari
		var prof := rounded(_mirror_x(dp, sx), 0.022, 3)
		extrude(fd, prof, -0.93, 0.5, 2, soft, 0.04)
		extrude(c, prof, 0.56, 1.02, 2, soft, 0.04)
		# Kol dayama yastigi (kumas), kapi cekme kolu, kapi acma kolu
		var padd := Kit.capsule(fd, 0.024, 0.5, Vector3(sx * 0.672, 0.812, -0.02), fabric2, Vector3(PI / 2, 0, 0))
		padd.scale = Vector3(1.0, 0.6, 1.0)
		var padr := Kit.capsule(c, 0.024, 0.3, Vector3(sx * 0.672, 0.812, 0.8), fabric2, Vector3(PI / 2, 0, 0))
		padr.scale = Vector3(1.0, 0.6, 1.0)
		Kit.capsule(fd, 0.011, 0.11, Vector3(sx * 0.706, 0.9, -0.42), silver, Vector3(PI / 2, 0, 0))
		Kit.capsule(c, 0.011, 0.1, Vector3(sx * 0.706, 0.9, 0.7), silver, Vector3(PI / 2, 0, 0))
		Kit.box(fd, Vector3(0.05, 0.012, 0.13), Vector3(sx * 0.675, 0.826, -0.26), gloss)
		for k in 3:
			Kit.box(fd, Vector3(0.022, 0.006, 0.018), Vector3(sx * 0.675, 0.834, -0.3 + 0.04 * k), silver)
		# Hoparlor izgarasi
		Kit.cyl(fd, 0.075, 0.075, 0.012, Vector3(sx * 0.727, 0.55, -0.6), black, 20, Vector3(0, 0, PI / 2))
		Kit.torus(fd, 0.07, 0.08, Vector3(sx * 0.722, 0.55, -0.6), trim, Vector3(0, 0, PI / 2))
		# Kapi cebi
		var pocket := Kit.capsule(fd, 0.03, 0.5, Vector3(sx * 0.705, 0.47, -0.05), trim, Vector3(PI / 2, 0, 0))
		pocket.scale = Vector3(0.6, 1.0, 1.0)
		# Arka yan doseme (tekerlek kemerinin ustu)
		Kit.box(c, Vector3(0.03, 0.42, 0.44), Vector3(sx * 0.735, 0.72, 1.25), soft, Vector3(0, 0, sx * 0.06))

	# ---- Gunes siperlikleri ve ic dikiz aynasi (tavanin hemen altinda, govdenin icinde)
	var liner := Kit.mat("c9c6bf", 0.98)
	for sx in [-1.0, 1.0]:
		# Tavana katlanmis (iceriden bakista gorusu kapatmaz)
		var visor := Kit.capsule(c, 0.01, 0.34, Vector3(sx * 0.34, 1.468, -0.17), liner, Vector3(0, 0, PI / 2))
		visor.scale = Vector3(1.0, 1.0, 6.0)
		visor.rotation.x = 0.07
	var mir := Node3D.new()
	mir.name = "DikizAynasi"
	mir.position = Vector3(0.0, 1.355, -0.37)
	mir.rotation = Vector3(-0.08, -0.42, 0)
	c.add_child(mir)
	var mhouse := Kit.capsule(mir, 0.036, 0.25, Vector3(0, 0, -0.012), black, Vector3(0, 0, PI / 2))
	mhouse.scale = Vector3(1.0, 1.0, 0.45)
	Kit.cyl(c, 0.008, 0.008, 0.07, Vector3(0, 1.4, -0.385), black, 6, Vector3(0.5, 0, 0))
	var mq := QuadMesh.new()
	mq.size = Vector2(0.225, 0.058)
	var mm := Kit.mat("8fa0b0", 0.05)
	mm.metallic = 0.9
	var mglass := Kit.add(mir, mq, mm, Vector3(0, 0, 0.006))
	mglass.name = "Cam"

	var il := OmniLight3D.new()
	il.position = Vector3(0, 1.3, 0.0)
	il.omni_range = 1.8
	il.light_energy = 0.45
	il.light_color = Color("fff1dc")
	c.add_child(il)
	# Eski duzenle uyum: yalniz birinci sahista acilan dugumler (yan ayna camlari burada)
	var ust := Node3D.new()
	ust.name = "Ust"
	c.add_child(ust)
	var dis := Node3D.new()
	dis.name = "Dis"
	c.add_child(dis)
	return c


## Kullanicinin ic mekanli modeli (assets/vehicles/araba.glb; scripts/custom_car.gd) icin kabin dugumu:
## geometri modelden gelir; burada yalniz oyunun bekledigi dugumler kurulur (gosterge ve navigasyon
## ekranlari, direksiyon ekseni, dikiz aynasi cami). holder: arac dugumu, inst: model.
static func build_custom(holder: Node3D, inst: Node3D) -> Node3D:
	var CC: GDScript = load("res://scripts/custom_car.gd")
	var c := Node3D.new()
	c.set_meta("gosterge", true)
	c.set_meta("custom", true)
	var gvp := SubViewport.new()
	gvp.name = "GostergeVP"
	gvp.size = Vector2i(512, 192)
	gvp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cl := Cluster.new()
	cl.name = "G"
	gvp.add_child(cl)
	c.add_child(gvp)
	var vp := SubViewport.new()
	vp.name = "CarPlayVP"
	vp.size = Vector2i(640, 300)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cp := CarPlay.new()
	cp.name = "CP"
	vp.add_child(cp)
	c.add_child(vp)
	for spec in [[["ekran_gosterge", "gosterge", "cluster"], gvp], [["ekran_nav", "navigasyon", "ekran_orta", "screen"], vp]]:
		var sn: Node3D = CC.call("find", inst, spec[0])
		if sn != null:
			_face_quad(holder, sn, (spec[1] as SubViewport).get_texture(), c)
	# Direksiyon: merkezinde, ekseni simidin ince yonu (surucuye dogru) olan dugum; model simidi icinde doner
	var wheel := Node3D.new()
	wheel.name = "Direksiyon"
	wheel.position = Vector3(-0.36, 0.9, -0.32)
	wheel.rotation.x = -0.35
	c.add_child(wheel)
	var spin := Node3D.new()
	spin.name = "Simit"
	wheel.add_child(spin)
	wheel.set_meta("model", true)
	var wn: Node3D = CC.call("find", inst, ["direksiyon", "steering", "simit"])
	if wn != null:
		var wb: AABB = CC.call("box_in", holder, wn)
		var axis := Vector3(0, 0.35, 0.94)
		var mis: Array = wn.find_children("*", "MeshInstance3D", true, false)
		if wn is MeshInstance3D:
			mis.push_front(wn)
		if not mis.is_empty() and (mis[0] as MeshInstance3D).mesh != null:
			# Simidin ince yonu (dugum olcegi hesaba katilir)
			var wxf: Transform3D = CC.call("_rel", holder, mis[0])
			var la: Vector3 = (mis[0] as MeshInstance3D).mesh.get_aabb().size * wxf.basis.get_scale()
			var ev := Vector3.RIGHT if la.x <= la.y and la.x <= la.z else (Vector3.UP if la.y <= la.z else Vector3.BACK)
			axis = (wxf.basis * ev).normalized()
			if axis.z < 0.0:
				axis = -axis
		var up := (Vector3.UP - axis * axis.dot(Vector3.UP)).normalized()
		wheel.transform = Transform3D(Basis(up.cross(axis).normalized(), up, axis), wb.get_center())
		holder.add_child(c)       # gecici: _move arac uzayindaki yolu izler
		CC.call("_move", holder, wn, spin)
		holder.remove_child(c)
	# Ic dikiz aynasi ve yan aynalar: parcanin ustune arkayi gosteren cam
	var mir := Node3D.new()
	mir.name = "DikizAynasi"
	mir.position = Vector3(0.0, 1.355, -0.37)
	c.add_child(mir)
	var msize := Vector2(0.225, 0.058)
	var mn: Node3D = CC.call("find", inst, ["ayna_ic", "dikiz", "mirror_in", "rearview"])
	if mn != null:
		var mb: AABB = CC.call("box_in", holder, mn)
		mir.position = Vector3(mb.get_center().x, mb.get_center().y, mb.end.z + 0.004)
		msize = Vector2(maxf(mb.size.x * 0.85, 0.12), maxf(mb.size.y * 0.8, 0.04))
	var mq := QuadMesh.new()
	mq.size = msize
	var mglass := Kit.add(mir, mq, Kit.mat("8fa0b0", 0.05))
	mglass.name = "Cam"
	var side: Array = []
	for keys in [["ayna_sol", "mirror_l"], ["ayna_sag", "mirror_r"]]:
		var an: Node3D = CC.call("find", inst, keys)
		if an == null:
			side.append([])
			continue
		var ab: AABB = CC.call("box_in", holder, an)
		side.append([Vector3(ab.get_center().x, ab.get_center().y, ab.end.z + 0.004), Vector2(ab.size.x * 0.8, ab.size.y * 0.75)])
	c.set_meta("yan_ayna", side)
	var il := OmniLight3D.new()
	il.position = Vector3(0, 1.3, 0.0)
	il.omni_range = 1.8
	il.light_energy = 0.45
	il.light_color = Color("fff1dc")
	c.add_child(il)
	for nm in ["Ust", "Dis"]:
		var n := Node3D.new()
		n.name = nm
		c.add_child(n)
	return c


## Parcanin (ince, duz) yuzune oturan isikli ekran: doku 'tex'.
static func _face_quad(holder: Node3D, n: Node3D, tex: Texture2D, c: Node3D) -> void:
	var CC: GDScript = load("res://scripts/custom_car.gd")
	var mis: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		mis.push_front(n)
	if mis.is_empty() or (mis[0] as MeshInstance3D).mesh == null:
		return
	var mi: MeshInstance3D = mis[0]
	var la: AABB = mi.mesh.get_aabb()
	var xf: Transform3D = CC.call("_rel", holder, mi)
	var axes := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var bsc: Vector3 = xf.basis.get_scale()
	var sz := [la.size.x, la.size.y, la.size.z]
	var ni := 0
	var real := [la.size.x * bsc.x, la.size.y * bsc.y, la.size.z * bsc.z]
	for i in 3:
		if real[i] < real[ni]:
			ni = i
	var nrm: Vector3 = (xf.basis * axes[ni]).normalized()
	if nrm.z < 0.0:
		nrm = -nrm
	# Diger iki eksenden yukariya en yakin olan ekranin dikeyi
	var a: int = (ni + 1) % 3
	var b: int = (ni + 2) % 3
	var va: Vector3 = xf.basis * axes[a]
	var vb: Vector3 = xf.basis * axes[b]
	var up_i := a if absf(va.normalized().y) >= absf(vb.normalized().y) else b
	var w_i := b if up_i == a else a
	var up: Vector3 = (xf.basis * axes[up_i])
	var h: float = sz[up_i] * up.length()
	var w: float = sz[w_i] * (xf.basis * axes[w_i]).length()
	up = up.normalized() * (1.0 if up.y >= 0.0 else -1.0)
	var q := QuadMesh.new()
	q.size = Vector2(w, h) * 0.96
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.albedo_color = Color(1.3, 1.3, 1.3)
	var qi := MeshInstance3D.new()
	qi.mesh = q
	qi.material_override = m
	qi.transform = Transform3D(Basis(up.cross(nrm).normalized(), up, nrm), xf * la.get_center() + nrm * (sz[ni] * 0.5 * (xf.basis * axes[ni]).length() + 0.003))
	c.add_child(qi)


## Aynalar: uc dusuk cozunurluklu kamera (ic dikiz, sol, sag). Yalniz birinci sahista guncellenir.
static func add_mirrors(c: Node3D) -> void:
	if c.has_node("AynaVP0"):
		return
	# [vp boyutu, kamera yeri, kamera sapmasi, fov, ayna dugumu / yeri, ayna boyutu, ayna sapmasi]
	var specs := [
		[Vector2i(256, 66), Vector3(0, 1.22, 2.06), PI, 34.0],
		[Vector2i(128, 128), Vector3(-1.02, 1.07, -0.3), PI - 0.14, 30.0],
		[Vector2i(128, 128), Vector3(1.02, 1.07, -0.3), PI + 0.14, 30.0]]
	for i in specs.size():
		var vp := SubViewport.new()
		vp.name = "AynaVP%d" % i
		vp.size = specs[i][0]
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.positional_shadow_atlas_size = 0
		vp.msaa_3d = Viewport.MSAA_DISABLED
		var cam := Camera3D.new()
		cam.name = "Kam"
		cam.fov = specs[i][3]
		cam.far = 160.0
		cam.near = 0.2
		cam.set_meta("local", Transform3D(Basis(Vector3.UP, specs[i][2]) * Basis(Vector3.RIGHT, -0.03), specs[i][1]))
		vp.add_child(cam)
		c.add_child(vp)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = vp.get_texture()
		mat.albedo_color = Color(0.9, 0.93, 0.96)
		mat.uv1_scale = Vector3(-1, 1, 1)
		mat.uv1_offset = Vector3(1, 0, 0)
		if i == 0:
			var g: MeshInstance3D = c.get_node("DikizAynasi/Cam")
			g.material_override = mat
		else:
			var sx := -1.0 if i == 1 else 1.0
			var q := QuadMesh.new()
			q.size = Vector2(0.105, 0.095)
			var at := Vector3(sx * 0.965, 1.07, -0.402)
			var custom: Array = c.get_meta("yan_ayna", [])
			if c.has_meta("custom"):
				# Kullanici modeli: ayna parcasinin ustune (parca yoksa yan ayna yok)
				if custom.size() <= i - 1 or (custom[i - 1] as Array).is_empty():
					continue
				at = custom[i - 1][0]
				q.size = custom[i - 1][1]
			var mi := Kit.add(c.get_node("Dis"), q, mat, at, Vector3(0, (0.3 if i == 1 else -0.45) if not c.has_meta("custom") else 0.0, 0))
			mi.name = "YanAyna%d" % i


## Yuvarlak hatli on koltuk: minder + sirt (yumusak kenarli), yan destekler, baslik.
static func _seat(parent: Node3D, at: Vector3, fabric: Material, center: Material) -> void:
	var s := Node3D.new()
	s.position = at
	parent.add_child(s)
	var cushion := Kit.capsule(s, 0.07, 0.5, Vector3(0, 0.47, 0.22), fabric, Vector3(PI / 2, 0, 0))
	cushion.scale = Vector3(3.4, 1.0, 1.0)
	Kit.box(s, Vector3(0.26, 0.05, 0.42), Vector3(0, 0.53, 0.22), center)
	var back := Node3D.new()
	back.position = Vector3(0, 0.52, 0.47)
	back.rotation.x = 0.16
	s.add_child(back)
	var bk := Kit.capsule(back, 0.07, 0.62, Vector3(0, 0.33, 0), fabric)
	bk.scale = Vector3(3.4, 1.0, 1.0)
	Kit.box(back, Vector3(0.24, 0.5, 0.05), Vector3(0, 0.33, -0.06), center)
	for sx in [-1.0, 1.0]:
		Kit.capsule(back, 0.05, 0.55, Vector3(sx * 0.22, 0.32, -0.05), fabric)
		Kit.capsule(s, 0.05, 0.42, Vector3(sx * 0.22, 0.52, 0.2), fabric, Vector3(PI / 2, 0, 0))
	var head := Kit.capsule(back, 0.06, 0.24, Vector3(0, 0.8, 0.0), fabric, Vector3(0, 0, PI / 2))
	head.scale = Vector3(1.0, 1.0, 0.8)
	for hx in [-0.07, 0.07]:
		Kit.cyl(back, 0.008, 0.008, 0.12, Vector3(hx, 0.7, 0.0), Kit.mat("b9bcc0", 0.3), 6)


## Camsiz (govdesi iceriden gizlenen) arabalar icin: yalniz birinci sahista gorunen basit kaput, direkler, tavan.
static func add_fake_shell(c: Node3D, glass: bool) -> void:
	if glass or c.has_meta("kabuk"):
		return
	c.set_meta("kabuk", true)
	var head := Kit.mat("cdc8bd", 0.95)
	var ust: Node3D = c.get_node("Ust")
	for sx in [-1.0, 1.0]:
		Kit.capsule(ust, 0.035, 0.66, Vector3(sx * 0.7, 1.22, -0.62), head, Vector3(-0.55, 0, 0))
		Kit.capsule(ust, 0.05, 0.56, Vector3(sx * 0.72, 1.2, 0.62), head)
		Kit.capsule(ust, 0.025, 1.3, Vector3(sx * 0.72, 1.46, 0.0), head, Vector3(PI / 2, 0, 0))
	Kit.box(ust, Vector3(1.46, 0.03, 1.5), Vector3(0, 1.49, 0.15), head)
	var dis: Node3D = c.get_node("Dis")
	var hood := Kit.ball(dis, 1.0, Vector3(0, 0.9, -1.6), Kit.mat("b8322c", 0.3), Vector3(0.78, 0.1, 0.62), 20)
	hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
