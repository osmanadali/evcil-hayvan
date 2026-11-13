extends RefCounted
## Benzinlik: OpenStreetMap'teki akaryakit noktalarinin yakininda, yola bakan bos bir arsaya kurulan
## uydurma markali istasyon (Yakamoz Petrol). Isikli kanopi, uc cift tarafli pompa adasi, kucuk market,
## fiyat panosu. world.gd'nin carpisma ve zemin yardimcilarini kullanir; sonuc world.fuel_stations'a yazilir.

const ParkMap = preload("res://scripts/park_map.gd")
const Kit = preload("res://scripts/kit.gd")

const BRAND := "YAKAMOZ"
const BRAND_GREEN := "17694a"
const BRAND_ORANGE := "f28c28"
## Oyun ici fiyatlar (oyundaki tum fiyatlar gibi kucultulmus): [ad, TL/litre, tabanca rengi]
const PRICES := [["BENZİN", 4.59, "1f8a4c"], ["MOTORİN", 4.72, "2b2b2e"], ["LPG", 2.45, "e0b22a"]]
const ISLANDS := [-5.0, 0.0, 5.0]          # pompa adalarinin yerel x konumu
const LOT_X := 10.5                        # arsa yari genisligi
const LOT_Z0 := -14.0                      # arsanin arka kenari (yerel z)
const LOT_Z1 := 5.5                        # on kenar (yola bakan)


static func build_all(w: Node3D) -> Array:
	var out: Array = []
	var used: Array[Vector2] = []
	for po in ParkMap.data["pois"]:
		if po["k"] != "akaryakit":
			continue
		var p := Vector2(po["pos"][0], po["pos"][1])
		if not ParkMap.inside_bounds(p, 0.0):
			continue
		var lot := _find_lot(w, p, used)
		if lot.is_empty():
			continue
		used.append(lot[0])
		out.append(_build(w, lot[0], lot[1], out.size()))
	return out


## Yola bakan, bina / yol / su olmayan, yeterince duz 21 x 19.5 m'lik arsa: [merkez, yola dogru birim yon]
static func _find_lot(w: Node3D, poi: Vector2, used: Array[Vector2]) -> Array:
	var cands: Array = []
	for r in ParkMap.data["roads"]:
		if r["k"] == "service" or r["k"] == "primary_link":
			continue
		var hw := float(r.get("w", 7.0)) * 0.5
		var ids: Array = r["n"]
		for i in ids.size() - 1:
			var a := ParkMap.nodes[int(ids[i])]
			var b := ParkMap.nodes[int(ids[i + 1])]
			if a.distance_to(poi) > 260.0 and b.distance_to(poi) > 260.0:
				continue
			var L := a.distance_to(b)
			if L < 24.0:
				continue
			var dir := (b - a) / L
			var nrm := Vector2(-dir.y, dir.x)
			var t := 11.0
			while t < L - 11.0:
				var q := a + dir * t
				for s in [1.0, -1.0]:
					var c: Vector2 = q + nrm * s * (hw + 1.5 + LOT_Z1)
					cands.append([c.distance_to(poi), c, -nrm * s])
				t += 3.0
	cands.sort_custom(func(x, y): return x[0] < y[0])
	for cd in cands:
		var c: Vector2 = cd[1]
		var near_used := false
		for u in used:
			if u.distance_to(c) < 60.0:
				near_used = true
		if near_used or not ParkMap.inside_bounds(c, 16.0):
			continue
		if _lot_ok(w, c, cd[2]):
			return [c, cd[2]]
	return []


static func _local(c: Vector2, toward: Vector2, x: float, z: float) -> Vector2:
	# yerel +Z = yola dogru, +X = sag (yukaridan bakinca)
	var right := Vector2(toward.y, -toward.x)
	return c + right * x + toward * z


static func _lot_ok(w: Node3D, c: Vector2, toward: Vector2) -> bool:
	var hmin := 1e9
	var hmax := -1e9
	var x := -LOT_X
	while x <= LOT_X + 0.01:
		var z := LOT_Z0
		while z <= LOT_Z1 + 0.01:
			var q := _local(c, toward, x, z)
			if not ParkMap.inside_bounds(q, 4.0) or w._inside_building(q) or not w.is_free(q, 0.7) or w._kept_out(q, 0.5):
				return false
			if ParkMap.water_sd(q) < 4.0:
				return false
			var m: Array = w._mask(q)
			# on sira kaldirimda olabilir; geri kalan asfalt / kaldirim / patika olmamali
			if m[2] > 0.45 or m[0] > 0.5 or (z < LOT_Z1 - 2.5 and m[3] > 0.5):
				return false
			var h := ParkMap.terrain_height(q)
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			z += 2.4
		x += 2.6
	return hmax - hmin < 1.8


static func _mat_metal(hex: String, rough := 0.35) -> StandardMaterial3D:
	var m := Kit.mat(hex, rough)
	m.metallic = 0.55
	return m


static func _label(parent: Node3D, text: String, pos: Vector3, color: Color, size: float, yrot := 0.0, bold := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.outline_size = 0
	l.pixel_size = size / 72.0
	l.modulate = color
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = pos
	l.rotation.y = yrot
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.visibility_range_end = 140.0
	if bold:
		var f: Font = load("res://assets/fonts/Anton-Regular.ttf") if ResourceLoader.exists("res://assets/fonts/Anton-Regular.ttf") else null
		if f:
			l.font = f
	parent.add_child(l)
	return l


## Arazi egimine uyan beton zemin (izgara mesh), kok dugume gore.
static func _pad(root: Node3D, c: Vector2, toward: Vector2) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 14
	var nz := 13
	var y0 := root.position.y
	var verts: Array = []
	for iz in nz + 1:
		for ix in nx + 1:
			var x := lerpf(-LOT_X, LOT_X, float(ix) / nx)
			var z := lerpf(LOT_Z0, LOT_Z1 + 0.6, float(iz) / nz)
			var q := _local(c, toward, x, z)
			verts.append(Vector3(x, ParkMap.terrain_height(q) - y0 + 0.035, z))
	for iz in nz:
		for ix in nx:
			var i0 := iz * (nx + 1) + ix
			var quad := [verts[i0], verts[i0 + 1], verts[i0 + nx + 2], verts[i0 + nx + 1]]
			for k in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = quad[k]
				st.set_uv(Vector2(v.x, v.z) * 0.25)
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := Kit.mat("b9b7b0", 0.85)
	var tex_path := "res://assets/tex/asfalt.jpg"
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
		m.albedo_color = Color(1.0, 1.0, 0.98)
	mi.material_override = m
	root.add_child(mi)


static func _build(w: Node3D, c: Vector2, toward: Vector2, idx: int) -> Dictionary:
	var rot := atan2(toward.x, toward.y)
	var root: Node3D = w._root(c, rot)
	root.name = "Benzinlik%d" % idx
	var y0 := root.position.y
	var hmax := -1e9
	for q in [_local(c, toward, -LOT_X, LOT_Z0), _local(c, toward, LOT_X, LOT_Z0), _local(c, toward, -LOT_X, LOT_Z1), _local(c, toward, LOT_X, LOT_Z1), c]:
		hmax = maxf(hmax, ParkMap.terrain_height(q))
	var lift := hmax - y0          # en yuksek koseye gore
	var gh := func(x: float, z: float) -> float:
		return ParkMap.terrain_height(_local(c, toward, x, z)) - y0
	_pad(root, c, toward)
	var white := Kit.mat("f2f3f1", 0.45)
	var green := Kit.mat(BRAND_GREEN, 0.5)
	var orange := Kit.mat(BRAND_ORANGE, 0.5)
	var steel := _mat_metal("c3c7cc", 0.35)
	var dark := Kit.mat("26292d", 0.6)
	var curb := Kit.mat("d8d6cf", 0.8)
	var yellow := Kit.mat("e8c02a", 0.6)
	# ---- Kanopi
	var ch := lift + 5.4
	var cz := -1.0
	var cw := 19.0
	var cd := 10.0
	Kit.box(root, Vector3(cw, 0.25, cd), Vector3(0, ch, cz), white)                  # tavan
	Kit.box(root, Vector3(cw + 0.2, 0.95, 0.12), Vector3(0, ch + 0.25, cz + cd * 0.5), white)   # on alin
	Kit.box(root, Vector3(cw + 0.2, 0.95, 0.12), Vector3(0, ch + 0.25, cz - cd * 0.5), white)
	Kit.box(root, Vector3(0.12, 0.95, cd), Vector3(-cw * 0.5 - 0.05, ch + 0.25, cz), white)
	Kit.box(root, Vector3(0.12, 0.95, cd), Vector3(cw * 0.5 + 0.05, ch + 0.25, cz), white)
	# Alinda marka seritleri (yesil + turuncu)
	for sz in [1.0, -1.0]:
		var zf: float = cz + sz * (cd * 0.5 + 0.07)
		Kit.box(root, Vector3(cw + 0.22, 0.32, 0.03), Vector3(0, ch + 0.02, zf), green)
		Kit.box(root, Vector3(cw + 0.22, 0.09, 0.03), Vector3(0, ch + 0.24, zf), orange)
		var lg := _label(root, BRAND, Vector3(-cw * 0.32, ch + 0.5, zf + sz * 0.03), Color(BRAND_GREEN), 0.62, 0.0 if sz > 0 else PI)
		lg.outline_size = 0
		_label(root, "PETROL", Vector3(-cw * 0.32 + 2.3 * sz, ch + 0.5, zf + sz * 0.03), Color(BRAND_ORANGE), 0.42, 0.0 if sz > 0 else PI)
	for sx in [1.0, -1.0]:
		Kit.box(root, Vector3(0.03, 0.32, cd), Vector3(sx * (cw * 0.5 + 0.12), ch + 0.02, cz), green)
	# Tavan alti aydinlatma panelleri (gece parlar) ve isiklar
	var panel_mat := Kit.glow("fff6e0", 0.0)
	for lx in [-7.5, -2.5, 2.5, 7.5]:
		for lz in [-3.0, 1.0]:
			Kit.box(root, Vector3(1.6, 0.04, 0.6), Vector3(lx, ch - 0.14, cz + lz), panel_mat)
	var lights: Array = []
	for lx in [-5.0, 5.0]:
		var ol := OmniLight3D.new()
		ol.position = Vector3(lx, ch - 0.6, cz)
		ol.omni_range = 13.0
		ol.light_energy = 0.0
		ol.light_color = Color("fff1d6")
		ol.shadow_enabled = false
		ol.visible = false
		root.add_child(ol)
		lights.append(ol)
	# ---- Pompa adalari, direkler ve pompalar
	var pumps: Array = []
	for i in ISLANDS.size():
		var ix: float = ISLANDS[i]
		var base := float(gh.call(ix, cz))
		Kit.box(root, Vector3(1.2, 0.2 + lift, 5.2), Vector3(ix, base + (0.2 + lift) * 0.5 - lift * 0.5, cz), curb)
		# sari-siyah carpma korumasi
		for ez in [-2.65, 2.65]:
			Kit.cyl(root, 0.09, 0.09, 0.9, Vector3(ix, base + 0.55, cz + ez), yellow, 10)
			Kit.cyl(root, 0.095, 0.095, 0.12, Vector3(ix, base + 0.75, cz + ez), dark, 10)
		# kanopi diregi (adanin arka ucunda)
		var ph: float = ch - base
		Kit.box(root, Vector3(0.42, ph, 0.42), Vector3(ix, base + ph * 0.5, cz - 2.0), steel)
		Kit.box(root, Vector3(0.44, 0.5, 0.44), Vector3(ix, base + 0.45, cz - 2.0), green)
		# Pompa: cift tarafli dispenser
		var pump := Node3D.new()
		pump.name = "Pompa%d" % (i + 1)
		pump.position = Vector3(ix, base + 0.2, cz + 0.4)
		root.add_child(pump)
		Kit.box(pump, Vector3(0.7, 0.2, 1.2), Vector3(0, 0.1, 0), dark)
		Kit.box(pump, Vector3(0.55, 1.55, 1.0), Vector3(0, 0.98, 0), white)
		Kit.box(pump, Vector3(0.6, 0.42, 1.06), Vector3(0, 1.95, 0), green)
		Kit.box(pump, Vector3(0.61, 0.07, 1.07), Vector3(0, 1.72, 0), orange)
		for sx in [1.0, -1.0]:
			var fx: float = sx * 0.285
			var yr: float = PI * 0.5 if sx > 0 else -PI * 0.5
			# ekran (litre / tutar) ve fiyat camlari
			Kit.box(pump, Vector3(0.02, 0.34, 0.62), Vector3(fx, 1.38, 0), Kit.glow("0c1a24", 0.3))
			_label(pump, "LİTRE", Vector3(fx + sx * 0.012, 1.48, -0.15), Color("8fd3ff"), 0.05, yr, false)
			_label(pump, "TUTAR", Vector3(fx + sx * 0.012, 1.33, -0.15), Color("8fd3ff"), 0.05, yr, false)
			var lt := _label(pump, "0,00", Vector3(fx + sx * 0.012, 1.48, 0.12), Color("ffcf4a"), 0.09, yr)
			lt.name = "Litre%s" % ("R" if sx > 0 else "L")
			var tt := _label(pump, "0,00", Vector3(fx + sx * 0.012, 1.33, 0.12), Color("ffcf4a"), 0.09, yr)
			tt.name = "Tutar%s" % ("R" if sx > 0 else "L")
			_label(pump, "%d" % (i + 1), Vector3(fx + sx * 0.012, 1.95, 0.0), Color.WHITE, 0.3, yr)
			# uc tabanca ve hortum
			for g in PRICES.size():
				var gz: float = -0.32 + g * 0.32
				Kit.box(pump, Vector3(0.06, 0.2, 0.09), Vector3(fx + sx * 0.03, 1.0, gz), Kit.mat(PRICES[g][2], 0.5))
				Kit.box(pump, Vector3(0.05, 0.035, 0.16), Vector3(fx + sx * 0.06, 1.1, gz - 0.03), dark)
				_label(pump, PRICES[g][0], Vector3(fx + sx * 0.012, 0.82, gz), Color("2b2b2e"), 0.035, yr, false)
			var hose := Kit.torus(pump, 0.33, 0.36, Vector3(fx + sx * 0.06, 0.82, 0.0), Kit.mat("1a1b1d", 0.6), Vector3(0, 0, PI * 0.5))
			hose.scale = Vector3(1.0, 1.0, 0.6)
		# carpisma: ada dikdortgeni
		var hx := 0.62
		var hz := 2.75
		var corners: Array[Vector2] = [_local(c, toward, ix - hx, cz - hz), _local(c, toward, ix + hx, cz - hz),
			_local(c, toward, ix + hx, cz + hz), _local(c, toward, ix - hx, cz + hz)]
		for k in 4:
			w._add_segment(corners[k], corners[(k + 1) % 4])
		# her iki yandaki serit: aracin durdugu yer ve hortumun ucu
		for sx in [-1.0, 1.0]:
			var lane_x: float = ix + sx * 2.45
			if absf(lane_x) > 8.5:
				lane_x = ix + sx * 2.3
			pumps.append({"pump": i + 1, "node": pump, "side": "R" if sx > 0 else "L",
				"lane": _local(c, toward, lane_x, cz), "nozzle": root.to_global(pump.position + Vector3(sx * 0.35, 1.05, 0.0)),
				"label": "%d" % (i + 1)})
	# Zemin cizgileri (seritler)
	for lx in [-7.5, -2.5, 2.5, 7.5]:
		for side in [-1.0, 1.0]:
			Kit.box(root, Vector3(0.1, 0.012, 6.0), Vector3(lx + side * 1.35, float(gh.call(lx, cz)) + 0.045, cz), Kit.mat("f0f0ea", 0.8))
	# ---- Market binasi (arkada)
	var sz := -10.6
	var sw := 12.0
	var sd := 6.0
	var sh := 3.8
	var sbase := float(gh.call(0.0, sz))
	var floor_h := lift - sbase + 0.05
	Kit.box(root, Vector3(sw, sh, sd), Vector3(0, sbase + floor_h + sh * 0.5 - 0.05, sz - 0.3), Kit.mat("e9e6df", 0.75))
	Kit.box(root, Vector3(sw + 0.4, floor_h + 0.2, sd + 0.8), Vector3(0, sbase + (floor_h + 0.2) * 0.5 - 0.15, sz), curb)
	# cati sacagi
	Kit.box(root, Vector3(sw + 0.6, 0.35, sd + 0.6), Vector3(0, sbase + floor_h + sh + 0.12, sz - 0.3), white)
	Kit.box(root, Vector3(sw + 0.62, 0.12, 0.04), Vector3(0, sbase + floor_h + sh, sz + sd * 0.5 + 0.01), orange)
	# vitrin camlari ve icerden gelen isik
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.7, 0.75, 0.42)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	var fz := sz + sd * 0.5 - 0.3 + 0.02
	var inner := Kit.glow("fff0cf", 0.35)
	inner.albedo_color = Color("f3eadb")
	Kit.box(root, Vector3(sw - 0.6, 2.5, 0.04), Vector3(0, sbase + floor_h + 1.35, fz - 1.4), inner)       # ic duvar
	# raflar (camdan gorunur)
	for rx in [-4.0, -2.0, 2.2, 4.2]:
		Kit.box(root, Vector3(1.4, 1.5, 0.45), Vector3(rx, sbase + floor_h + 0.75, fz - 1.0), Kit.mat(["d35b3a", "3b7fc4", "e0b22a", "5aa05a"][int(rx + 4.0) % 4], 0.7))
	Kit.box(root, Vector3(sw - 0.2, 2.6, 0.05), Vector3(0, sbase + floor_h + 1.4, fz), glass)
	for mx in [-5.9, -3.0, 0.0, 3.0, 5.9]:
		Kit.box(root, Vector3(0.1, 2.7, 0.08), Vector3(mx, sbase + floor_h + 1.4, fz + 0.03), dark)
	Kit.box(root, Vector3(sw, 0.1, 0.08), Vector3(0, sbase + floor_h + 2.72, fz + 0.03), dark)
	# kapi (orta)
	Kit.box(root, Vector3(1.8, 2.4, 0.03), Vector3(1.5, sbase + floor_h + 1.25, fz + 0.06), Kit.mat("3a3d42", 0.4))
	Kit.box(root, Vector3(1.6, 2.2, 0.02), Vector3(1.5, sbase + floor_h + 1.25, fz + 0.08), glass)
	# tabela
	Kit.box(root, Vector3(5.6, 0.75, 0.1), Vector3(-1.5, sbase + floor_h + 3.3, fz + 0.05), green)
	_label(root, "YAKAMOZ MARKET", Vector3(-1.5, sbase + floor_h + 3.3, fz + 0.11), Color.WHITE, 0.42)
	_label(root, "7/24 AÇIK", Vector3(3.7, sbase + floor_h + 3.3, fz + 0.06), Color(BRAND_ORANGE), 0.3)
	# market carpismasi
	var sc: Array[Vector2] = [_local(c, toward, -sw * 0.5, sz - sd * 0.5 - 0.3), _local(c, toward, sw * 0.5, sz - sd * 0.5 - 0.3),
		_local(c, toward, sw * 0.5, sz + sd * 0.5 - 0.25), _local(c, toward, -sw * 0.5, sz + sd * 0.5 - 0.25)]
	for k in 4:
		w._add_segment(sc[k], sc[(k + 1) % 4])
	# hava / su istasyonu ve cop kutusu
	var ax := -8.6
	var az := -6.0
	Kit.box(root, Vector3(0.5, 1.3, 0.4), Vector3(ax, float(gh.call(ax, az)) + 0.65, az), Kit.mat("2f6fb5", 0.5))
	_label(root, "HAVA · SU", Vector3(ax, float(gh.call(ax, az)) + 1.1, az + 0.21), Color.WHITE, 0.09)
	Kit.cyl(root, 0.25, 0.22, 0.8, Vector3(8.7, float(gh.call(8.7, -6.0)) + 0.4, -6.0), green, 12)
	# ---- Fiyat panosu (yol kenarinda, sag on kose)
	var px := 9.2
	var pz := 4.3
	var pb := float(gh.call(px, pz))
	var pole := Node3D.new()
	pole.position = Vector3(px, pb, pz)
	root.add_child(pole)
	Kit.box(pole, Vector3(0.9, 0.6, 0.6), Vector3(0, 0.3, 0), curb)
	Kit.box(pole, Vector3(1.6, 5.4, 0.36), Vector3(0, 3.3, 0), white)
	Kit.box(pole, Vector3(1.64, 1.3, 0.4), Vector3(0, 5.35, 0), green)
	Kit.box(pole, Vector3(1.66, 0.1, 0.42), Vector3(0, 4.65, 0), orange)
	for sdir in [1.0, -1.0]:
		var fzz: float = sdir * 0.205
		var yr: float = 0.0 if sdir > 0 else PI
		_label(pole, BRAND, Vector3(0, 5.5, fzz + sdir * 0.01), Color.WHITE, 0.36, yr)
		_label(pole, "PETROL", Vector3(0, 5.12, fzz + sdir * 0.01), Color(BRAND_ORANGE), 0.2, yr)
		for g in PRICES.size():
			var gy := 4.15 - g * 0.78
			Kit.box(pole, Vector3(1.42, 0.62, 0.02), Vector3(0, gy, fzz), Kit.glow("101418", 0.2))
			_label(pole, PRICES[g][0], Vector3(0, gy + 0.17, fzz + sdir * 0.012), Color(PRICES[g][2]).lightened(0.35), 0.15, yr)
			_label(pole, ("%.2f ₺" % PRICES[g][1]).replace(".", ","), Vector3(0, gy - 0.08, fzz + sdir * 0.012), Color("ff5a3a"), 0.28, yr)
	w._add_circle(Vector3(_local(c, toward, px, pz).x, _local(c, toward, px, pz).y, 0.75))
	# kanopi direkleri de carpar (adalarin arka uclarinda zaten ada var)
	w._keep_out.append([c, Vector2(17.0, 17.0)])
	# cim bitmesin: arsa dikdortgeni (dunya -> yerel)
	var right := Vector2(toward.y, -toward.x)
	w.paved.append([Transform2D(right, toward, c).affine_inverse(), Rect2(-LOT_X - 0.5, LOT_Z0 - 0.5, LOT_X * 2.0 + 1.0, LOT_Z1 - LOT_Z0 + 1.5)])
	var door := _local(c, toward, 1.5, sz + sd * 0.5 + 0.9)
	return {"name": "Yakamoz Petrol", "pos": c, "entry": _local(c, toward, 0.0, LOT_Z1 + 1.0), "rot": rot,
		"root": root, "pumps": pumps, "lights": lights, "panels": panel_mat, "door": door}
