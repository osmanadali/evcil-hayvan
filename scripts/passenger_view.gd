extends Node
## Yolcu bakisi: taksi, dolmus ya da otobuste yolcuyken V ile koltuktan birinci sahis kamera.
## Tripo modellerinin ici dolu oldugu icin arac govdesi gizlenir, yerine sade bir ic mekan cizilir
## (koltuklar, on panel, direksiyon, direkler, tavan); sofor figuru yerinde kalir.
## Ayrica kucuk yolcu gostergesi (hedef + kalan yol) ve dolmusta "Inecek var!" istegi.
## Arac uzayi: +X sag, +Y yukari, on = -Z; sofor solda.

const Kit = preload("res://scripts/kit.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const CarCabin = preload("res://scripts/car_cabin.gd")
const World = preload("res://scripts/world.gd")

var m: Node                   # main.gd
var on := false               # koltuktan bakis acik
var stop_req := false         # dolmus: inecek var
var _veh: Node3D              # ic mekani kurulan arac
var _cabin: Node3D
var _kind := ""               # taksi / dolmus / otobus
var _eye := Vector3.ZERO      # yolcunun goz yeri (arac uzayi)
var _hidden: Array = []       # gizlenen govde parcalari
var _hud: PanelContainer
var _title: Label
var _info: Label
var _btn: Button
var _sign: Label3D
var _meter: Label3D
var _total := 0.0             # binildigi andaki yol uzunlugu (ucret orani icin)
var _bob := 0.0
var _last_veh: Node3D


func vehicle() -> Node3D:
	if m._taxi != null:
		return m._taxi
	return m._bus_ride


func kind_of(v: Node3D) -> String:
	if v == m._bus_ride:
		return "otobus"
	return m._car_model(v)


func toggle() -> void:
	if vehicle() == null:
		return
	set_on(not on)


func set_on(want: bool) -> void:
	var v := vehicle()
	if want and v == null:
		return
	if want:
		_enter(v)
	else:
		_exit()
	m._fps_yaw = 0.0
	m._fps_pitch = 0.0
	m._cam_blend = 0.5


func _enter(v: Node3D) -> void:
	if on and _veh == v:
		return
	_exit()
	_veh = v
	_kind = kind_of(v)
	on = true
	_build()
	for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		if _cabin.is_ancestor_of(mi) or not mi.visible:
			continue
		var p: Node = mi.get_parent()
		var driver := false
		while p != null and p != v:
			if p.name == "Surucu":
				driver = true
				break
			p = p.get_parent()
		if driver:
			continue
		mi.visible = false
		_hidden.append(mi)


func _exit() -> void:
	on = false
	for mi in _hidden:
		if is_instance_valid(mi):
			mi.visible = true
	_hidden.clear()
	if _cabin and is_instance_valid(_cabin):
		_cabin.queue_free()
	_cabin = null
	_sign = null
	_meter = null
	_veh = null
	if m.cam:
		m.cam.near = 0.05
		m.cam.fov = 60.0


# ---------------------------------------------------------------- her kare

func update(_dt: float) -> void:
	var v := vehicle()
	if v != _last_veh:
		_last_veh = v
		stop_req = false
		_total = remaining() if v != null and v == m._taxi else 0.0
	if on and v != _veh:
		_exit()
		m._cam_blend = 0.5
	_update_hud(v)
	if on and _sign:
		if _kind == "otobus":
			var nx := _bus_next()
			_sign.text = ("DURAK: %s" % v.at_stop) if v.at_stop != "" else ("SIRADAKİ: %s" % nx[0] if nx[0] != "" else v.line)
		else:
			_sign.visible = stop_req
	if on and _meter:
		_meter.text = "%d ₺" % partial_fare(m._taxi_fare)


## Kalan yol (m): taksi / dolmusta hedefe, otobuste siradaki duraga.
func remaining() -> float:
	if m._taxi != null:
		var p := Vector2(m._taxi.position.x, m._taxi.position.z)
		var path: PackedVector2Array = m._taxi_path
		var i: int = m._taxi_i
		if i >= path.size():
			return 0.0
		var d := p.distance_to(path[i])
		for j in range(i + 1, path.size()):
			d += path[j - 1].distance_to(path[j])
		return d
	if m._bus_ride != null:
		return float(_bus_next()[1])
	return 0.0


func _bus_next() -> Array:
	var b: Node3D = m._bus_ride
	if b == null or b.legs.is_empty():
		return ["", 0.0]
	var st: Array = b.legs[b.leg]["stops"]
	var i: int = b._next_stop
	if i >= st.size():
		return ["", 0.0]
	return [String(st[i]["name"]), maxf(float(st[i]["s"]) - float(b.s), 0.0)]


## Yolun ortasinda inilirse gidilen yol kadar ucret.
func partial_fare(full: int) -> int:
	if _total < 1.0:
		return full
	return clampi(int(ceil(full * (1.0 - remaining() / _total))), mini(5, full), full)


func request_stop() -> void:
	if m._taxi == null or stop_req:
		return
	stop_req = true
	m._sfx("tik", -4.0, 1.3)
	m.ui.toast("İnecek var! Şoför müsait bir yerde duracak.")


func _dist_text(d: float) -> String:
	return ("%.1f km" % (d / 1000.0)) if d >= 1000.0 else ("%d m" % (int(d / 10.0) * 10))


func _update_hud(v: Node3D) -> void:
	var vis: bool = v != null and m._mode == "play" and not m.ui.is_blocking() and not m.map_screen.visible
	if not vis:
		if _hud:
			_hud.visible = false
		return
	if _hud == null:
		_make_hud()
	_hud.visible = true
	var touch := DisplayServer.is_touchscreen_available()
	_btn.visible = touch
	var view_hint := "" if touch else ("   ·   V: %s" % ("dış kamera" if on else "koltuktan bak"))
	if v == m._bus_ride:
		var nx := _bus_next()
		_title.text = "OTOBÜS %s" % v.line
		if v.at_stop != "":
			_info.text = "Durak: %s%s" % [v.at_stop, view_hint]
		elif nx[0] != "":
			_info.text = "Sıradaki durak: %s · %s%s" % [nx[0], _dist_text(nx[1]), view_hint]
		else:
			_info.text = "Son durak%s" % view_hint
	else:
		var dolmus: bool = m._car_model(v) == "dolmus"
		_title.text = "%s  →  %s" % ["DOLMUŞ" if dolmus else "TAKSİ", String(m.minimap.dest_name).to_upper()]
		var extra := "İnecek var! Duruyor…" if stop_req else ("Kalan: %s · %d ₺" % [_dist_text(remaining()), m._taxi_fare])
		_info.text = extra + view_hint


func _make_hud() -> void:
	_hud = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.07, 0.72)
	sb.set_corner_radius_all(14)
	sb.border_color = m.ui.ACCENT
	sb.border_width_bottom = 3
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_hud.add_theme_stylebox_override("panel", sb)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.ui.hud.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud.offset_top = 14
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_title = m.ui._fx_label(col, "", m.ui.F_TITLE, 26, m.ui.ACCENT, 4)
	_info = m.ui._fx_label(col, "", m.ui.F_BODY, 18, Color.WHITE, 3)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn = UiKit.button(row, "", "camera", func(): toggle(), m.ui.GLASS, Color.WHITE, Vector2(60, 60), 26, 30)


# ---------------------------------------------------------------- kamera

func camera(dt: float) -> void:
	if _veh == null or not is_instance_valid(_veh):
		return
	if not m._looking():
		m._fps_yaw = lerpf(m._fps_yaw, 0.0, minf(1.0, dt * 0.8))
	# Dogal bas araligi
	m._fps_yaw = clampf(m._fps_yaw, -1.75, 1.75)
	m._fps_pitch = clampf(m._fps_pitch, -0.6, 0.45)
	var sp: float = m._taxi_speed if m._taxi != null else float(_veh.get("speed"))
	_bob += dt * (3.0 + sp * 1.3)
	var k := clampf(sp / 9.0, 0.0, 1.0)
	var amp := 0.004 + 0.011 * k
	var off := Vector3(sin(_bob * 0.53) * amp * 0.6, sin(_bob) * amp + sin(_bob * 2.7) * amp * 0.35, 0.0)
	var roll := sin(_bob * 0.41) * 0.006 * k
	var look := Basis(Vector3.UP, m._fps_yaw) * Basis(Vector3.RIGHT, m._fps_pitch - 0.05) * Basis(Vector3.BACK, roll)
	m.cam.global_transform = _veh.global_transform * Transform3D(look, _eye + off)
	m.cam.near = 0.05
	m.cam.fov = 70.0


# ---------------------------------------------------------------- ic mekan

func _bar(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var d := b - a
	var mi := Kit.cyl(parent, r, r, d.length(), (a + b) * 0.5, mat, 8)
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.basis = Basis(x, y, x.cross(y))


func _local_aabb(v: Node3D) -> AABB:
	var inv := v.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		var p: Node = mi.get_parent()
		if p.name == "Surucu" or mi.mesh == null:
			continue
		var a: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func _driver_hip(v: Node3D, fallback: Vector3) -> Vector3:
	var list := v.find_children("Surucu", "", true, false)
	if list.is_empty():
		return fallback
	return v.global_transform.affine_inverse() * (list[0] as Node3D).global_position


func _build() -> void:
	_cabin = Node3D.new()
	_cabin.name = "YolcuKabin"
	_veh.add_child(_cabin)
	var box := _local_aabb(_veh)
	if _kind == "taksi":
		_build_taxi(box)
	else:
		_build_van(box, _kind == "otobus")


func _wheel(at: Vector3, r: float, tilt: float, mat: Material) -> void:
	var w := Node3D.new()
	w.position = at
	w.rotation.x = tilt
	_cabin.add_child(w)
	Kit.torus(w, r - 0.022, r, Vector3.ZERO, mat)
	Kit.box(w, Vector3(r * 1.9, 0.02, 0.035), Vector3.ZERO, mat)
	Kit.box(w, Vector3(0.035, 0.02, r), Vector3(0, 0, r * 0.5), mat)
	Kit.cyl(w, 0.045, 0.045, 0.03, Vector3.ZERO, mat, 10)
	Kit.cyl(w, 0.03, 0.035, 0.4, Vector3(0, -0.2, 0), mat, 8)


func _build_taxi(box: AABB) -> void:
	var h := _driver_hip(_veh, Vector3(-0.36, 0.46, -0.18))
	var w := clampf(box.size.x * 0.5 - 0.1, 0.68, 0.84)
	var sx := absf(h.x)
	var fy := maxf(h.y - 0.44, 0.16)      # zemin yolun ustunde kalsin
	var top := h.y + 0.98
	var sill := h.y + 0.34
	var zf := h.z - 1.12          # on camin alti
	var zb := h.z + 1.7           # arka duvar
	var trim := Kit.mat("2b2d31", 0.85)
	var dash := Kit.mat("1c1d20", 0.7)
	var liner := Kit.mat("d8d3c8", 0.95)
	var fabric := Kit.mat("3a3d44", 0.95)
	var fabric2 := Kit.mat("55585f", 0.95)
	var paint := Kit.mat("f2c230", 0.3)
	var black := Kit.mat("111214", 0.5)
	# Zemin, tavan
	Kit.box(_cabin, Vector3(w * 2.0 + 0.1, 0.04, zb - zf), Vector3(0, fy, (zf + zb) * 0.5), Kit.mat("17181a", 0.95))
	Kit.box(_cabin, Vector3(w * 2.0 + 0.12, 0.04, zb - h.z + 0.42), Vector3(0, top, (h.z - 0.42 + zb) * 0.5), liner)
	# Kapilar (cam altina kadar), direkler
	for s in [-1.0, 1.0]:
		Kit.box(_cabin, Vector3(0.06, sill - fy, zb - zf), Vector3(s * (w + 0.03), (sill + fy) * 0.5, (zf + zb) * 0.5), trim)
		Kit.box(_cabin, Vector3(0.1, 0.05, 1.5), Vector3(s * (w - 0.03), sill - 0.12, h.z + 0.3), fabric2)      # kolcak
		_bar(_cabin, Vector3(s * w, sill, zf), Vector3(s * (w - 0.04), top, h.z - 0.42), 0.04, liner)          # A
		Kit.box(_cabin, Vector3(0.07, top - sill, 0.11), Vector3(s * (w + 0.02), (top + sill) * 0.5, h.z + 0.38), liner)   # B
		Kit.box(_cabin, Vector3(0.07, top - sill, 0.34), Vector3(s * (w + 0.02), (top + sill) * 0.5, zb - 0.2), liner)     # C
		_bar(_cabin, Vector3(s * (w + 0.02), top - 0.02, h.z - 0.42), Vector3(s * (w + 0.02), top - 0.02, zb), 0.03, liner)
		Kit.box(_cabin, Vector3(0.05, 0.12, 0.16), Vector3(s * (w + 0.2), sill + 0.1, zf + 0.25), paint)        # yan ayna
	# Arka: sirtlik duvari, sapka rafi, arka cam ustu
	Kit.box(_cabin, Vector3(w * 2.0, sill - fy, 0.06), Vector3(0, (sill + fy) * 0.5, zb), trim)
	Kit.box(_cabin, Vector3(w * 2.0, 0.03, 0.3), Vector3(0, sill, zb - 0.15), trim)
	Kit.box(_cabin, Vector3(w * 2.0, 0.1, 0.06), Vector3(0, top - 0.05, zb), liner)
	# On panel
	Kit.box(_cabin, Vector3(w * 2.0, 0.3, 0.46), Vector3(0, h.y + 0.25, zf + 0.25), dash)
	Kit.box(_cabin, Vector3(w * 2.0, 0.4, 0.2), Vector3(0, h.y - 0.08, zf + 0.2), trim)
	Kit.box(_cabin, Vector3(0.36, 0.1, 0.24), Vector3(h.x, h.y + 0.43, zf + 0.34), dash)                    # gosterge siperi
	Kit.box(_cabin, Vector3(0.3, 0.2, 0.03), Vector3(0, h.y + 0.26, zf + 0.49), Kit.glow("2f7bd6", 0.5))  # ekran
	Kit.box(_cabin, Vector3(0.22, 0.34, 0.7), Vector3(0, fy + 0.2, h.z - 0.25), trim)                       # orta konsol
	Kit.cyl(_cabin, 0.015, 0.015, 0.16, Vector3(0, fy + 0.44, h.z - 0.35), black, 6)
	Kit.ball(_cabin, 0.03, Vector3(0, fy + 0.53, h.z - 0.35), black)
	_wheel(Vector3(h.x, h.y + 0.31, h.z - 0.4), 0.18, 1.1, black)
	# Taksimetre + dikiz aynasi
	Kit.box(_cabin, Vector3(0.2, 0.09, 0.07), Vector3(0.02, h.y + 0.46, zf + 0.4), black)
	_meter = Label3D.new()
	_meter.font_size = 40
	_meter.pixel_size = 0.0014
	_meter.modulate = Color("ff3b2e")
	_meter.outline_size = 0
	_meter.shaded = false
	_meter.position = Vector3(0.02, h.y + 0.46, zf + 0.44)
	_cabin.add_child(_meter)
	Kit.box(_cabin, Vector3(0.22, 0.06, 0.02), Vector3(0, top - 0.11, h.z - 0.52), black)
	Kit.box(_cabin, Vector3(0.012, 0.1, 0.012), Vector3(0.04, top - 0.2, h.z - 0.5), Kit.mat("b9bcc0", 0.3))
	Kit.ball(_cabin, 0.03, Vector3(0.04, top - 0.27, h.z - 0.5), Kit.mat("2f8f5a", 0.5))                 # aynadan sarkan sus
	# Disaridan gorunen kaput + tavan lambasi
	Kit.box(_cabin, Vector3(w * 2.0 + 0.1, 0.06, 1.05), Vector3(0, h.y + 0.36, zf - 0.5), paint, Vector3(0.06, 0, 0))
	# Koltuklar: iki on, arka sira
	for x in [h.x, sx]:
		CarCabin._seat(_cabin, Vector3(x, h.y - 0.6, h.z - 0.3), fabric, fabric2)
	var rz := h.z + 0.92
	Kit.box(_cabin, Vector3(w * 2.0 - 0.06, 0.16, 0.5), Vector3(0, h.y - 0.1, rz - 0.05), fabric)
	Kit.box(_cabin, Vector3(w * 2.0 - 0.06, 0.6, 0.14), Vector3(0, h.y + 0.22, rz + 0.3), fabric, Vector3(0.18, 0, 0))
	for x in [-sx, sx]:
		Kit.box(_cabin, Vector3(0.34, 0.03, 0.4), Vector3(x, h.y - 0.01, rz - 0.06), fabric2)
		Kit.box(_cabin, Vector3(0.24, 0.16, 0.08), Vector3(x, h.y + 0.6, rz + 0.36), fabric)
	_eye = Vector3(sx * 0.62, h.y + 0.7, rz + 0.02)


## Dolmus / otobus: koridor, cam kenari koltuklar, tutunma borulari, on panel, yolcular.
func _build_van(box: AABB, bus: bool) -> void:
	var h := _driver_hip(_veh, Vector3(-0.78, 1.2, -5.05) if bus else Vector3(-0.4, 0.9, -1.62))
	var w := clampf(box.size.x * 0.5 - 0.1, 0.82, 1.0) if not bus else clampf(box.size.x * 0.5 - 0.1, 1.05, 1.22)
	var fy := h.y - 0.47
	var top := fy + (2.05 if bus else 1.58)
	var sill := fy + 0.8
	var head := top - 0.24        # cam ustu
	var zf := h.z - (0.95 if bus else 1.0)
	var zb := clampf(box.end.z - 0.12, 4.5, 6.0) if bus else clampf(box.end.z - 0.12, 2.0, 2.9)
	var wall := Kit.mat("d9dcd8" if bus else "cfc9bb", 0.7)
	var liner := Kit.mat("eceee9", 0.8)
	var floor_m := Kit.mat("3b3e42", 0.95)
	var dash := Kit.mat("202226", 0.7)
	var seat_m := Kit.mat("27508c" if bus else "7a3a2c", 0.9)
	var seat_b := Kit.mat("1d2530", 0.8)
	var pole := Kit.mat("f0b81e", 0.35)
	var black := Kit.mat("111214", 0.5)
	var ln := zb - zf
	var zc := (zf + zb) * 0.5
	Kit.box(_cabin, Vector3(w * 2.0 + 0.1, 0.05, ln), Vector3(0, fy - 0.025, zc), floor_m)
	Kit.box(_cabin, Vector3(0.5, 0.01, ln - 1.2), Vector3(0.12 if not bus else 0.0, fy + 0.006, zc + 0.5), Kit.mat("55595e", 0.9))   # koridor seridi
	Kit.box(_cabin, Vector3(w * 2.0 + 0.14, 0.05, ln), Vector3(0, top + 0.025, zc), liner)
	var gap := 1.5 if bus else 1.05
	for s in [-1.0, 1.0]:
		Kit.box(_cabin, Vector3(0.06, sill - fy, ln), Vector3(s * (w + 0.03), (sill + fy) * 0.5, zc), wall)
		Kit.box(_cabin, Vector3(0.06, top - head, ln), Vector3(s * (w + 0.03), (top + head) * 0.5, zc), liner)
		Kit.box(_cabin, Vector3(0.09, 0.03, ln), Vector3(s * (w - 0.015), sill + 0.015, zc), seat_b)       # cam fitili
		var z := zf
		while z <= zb + 0.01:
			Kit.box(_cabin, Vector3(0.07, head - sill, 0.1 if z > zf + 0.1 else 0.14), Vector3(s * (w + 0.03), (head + sill) * 0.5, z), liner)
			z += gap
		Kit.box(_cabin, Vector3(0.07, head - sill, 0.14), Vector3(s * (w + 0.03), (head + sill) * 0.5, zb), liner)
		# Tavan tutunma borusu
		_bar(_cabin, Vector3(s * 0.34, top - 0.2, h.z + 0.6), Vector3(s * 0.34, top - 0.2, zb - 0.3), 0.016, pole)
	# Arka duvar (ustte cam)
	Kit.box(_cabin, Vector3(w * 2.0, sill + 0.15 - fy, 0.06), Vector3(0, (sill + 0.15 + fy) * 0.5, zb), wall)
	Kit.box(_cabin, Vector3(w * 2.0, top - head, 0.06), Vector3(0, (top + head) * 0.5, zb), liner)
	# On: panel, on cam ustu, direksiyon, sofor koltugu, bolme
	Kit.box(_cabin, Vector3(w * 2.0, 0.34, 0.42), Vector3(0, h.y + 0.2, zf + 0.21), dash)
	Kit.box(_cabin, Vector3(w * 2.0, h.y + 0.05 - fy, 0.1), Vector3(0, (h.y + 0.05 + fy) * 0.5, zf + 0.05), dash)
	Kit.box(_cabin, Vector3(0.42, 0.1, 0.2), Vector3(h.x, h.y + 0.4, zf + 0.3), dash)
	Kit.box(_cabin, Vector3(0.3, 0.03, 0.2), Vector3(h.x + 0.5, h.y + 0.385, zf + 0.26), Kit.mat("8a2f2a", 0.9))    # panel ortusu
	Kit.box(_cabin, Vector3(w * 2.0, top - head + 0.06, 0.08), Vector3(0, (top + head) * 0.5 - 0.03, zf), liner)
	for s in [-1.0, 1.0]:
		Kit.box(_cabin, Vector3(0.09, head - h.y - 0.3, 0.09), Vector3(s * (w + 0.01), (head + h.y + 0.3) * 0.5, zf), liner)
	_wheel(Vector3(h.x, h.y + 0.31, h.z - 0.4), 0.21 if bus else 0.19, 0.75 if bus else 0.95, black)
	Kit.box(_cabin, Vector3(0.46, 0.1, 0.46), Vector3(h.x, h.y - 0.1, h.z + 0.02), seat_b)
	Kit.box(_cabin, Vector3(0.46, 0.66, 0.09), Vector3(h.x, h.y + 0.27, h.z + 0.26), seat_b, Vector3(0.1, 0, 0))
	Kit.box(_cabin, Vector3(0.2, 0.3, 0.2), Vector3(h.x, fy + 0.17, h.z + 0.02), dash)
	Kit.box(_cabin, Vector3(0.24, 0.07, 0.02), Vector3(0, head - 0.08, zf + 0.1), black)                     # dikiz aynasi
	if bus:
		Kit.box(_cabin, Vector3(0.04, 1.0, 0.7), Vector3(h.x + 0.36, fy + 0.5, h.z + 0.1), wall)             # sofor bolmesi
		_bar(_cabin, Vector3(h.x + 0.36, fy, h.z + 0.48), Vector3(h.x + 0.36, top, h.z + 0.48), 0.018, pole)
		Kit.box(_cabin, Vector3(0.26, 0.3, 0.2), Vector3(h.x + 0.62, fy + 1.0, h.z - 0.1), Kit.mat("d8dad6", 0.5))   # kart okuyucu
		Kit.box(_cabin, Vector3(0.16, 0.1, 0.01), Vector3(h.x + 0.62, fy + 1.05, h.z + 0.005), Kit.glow("34c26a", 0.8))
	else:
		# Para kutusu + panel ustu sus
		Kit.box(_cabin, Vector3(0.3, 0.07, 0.2), Vector3(h.x + 0.5, h.y + 0.42, zf + 0.28), Kit.mat("6b4a2a", 0.6))
		Kit.box(_cabin, Vector3(w * 2.0 + 0.1, 0.06, 0.5), Vector3(0, h.y + 0.2, zf - 0.28), Kit.mat("e9e6dc", 0.35))   # kisa burun
	# Isikli tabela
	_sign = Label3D.new()
	_sign.font_size = 56
	_sign.pixel_size = 0.0016 if bus else 0.0013
	_sign.outline_size = 0
	_sign.shaded = false
	_sign.modulate = Color("ffb52e") if bus else Color("ff4a3a")
	_sign.text = "" if bus else "İNECEK VAR"
	_sign.position = Vector3(0.1, head + 0.09, zf + 0.12)
	_cabin.add_child(_sign)
	Kit.box(_cabin, Vector3(1.1 if bus else 0.6, 0.15, 0.02), Vector3(0.1, head + 0.09, zf + 0.105), black)
	# Koltuk siralari: solda cift, sagda (dolmus: tek, otobus: cift); kapi hizasi bos
	var pitch := 0.82 if bus else 0.76
	var z0 := h.z + (1.25 if bus else 0.95)
	var rows := int((zb - 0.45 - z0) / pitch) + 1
	var xs_l := [-(w - 0.27), -(w - 0.73)]
	var xs_r := [w - 0.27, w - 0.73] if bus else [w - 0.27]
	var my_row := mini(3 if bus else 1, rows - 1)
	var folk := 0
	for r in rows:
		var z := z0 + r * pitch
		var door := bus and (r == 1 or r == 7)
		var xs: Array = xs_l.duplicate()
		if not door and not (not bus and r == 0):
			xs.append_array(xs_r)
		for x in xs:
			Kit.box(_cabin, Vector3(0.42, 0.08, 0.42), Vector3(x, fy + 0.43, z), seat_m)
			Kit.box(_cabin, Vector3(0.42, 0.56, 0.07), Vector3(x, fy + 0.74, z + 0.24), seat_m, Vector3(0.1, 0, 0))
			Kit.box(_cabin, Vector3(0.36, 0.38, 0.05), Vector3(x, fy + 0.2, z + 0.02), seat_b)
			var mine: bool = r == my_row and x == xs_r[0]
			var front_of_me: bool = r == my_row - 1 and x > 0.0
			if not mine and not front_of_me and (r * 7 + int(absf(x) * 10.0)) % 3 == 0 and folk < (7 if bus else 3):
				var p := World.add_driver(_cabin, Vector3(x, fy + 0.52, z + 0.04), r * 3 + folk)
				for mi: MeshInstance3D in p.find_children("*", "MeshInstance3D", true, false):
					mi.visibility_range_end = 0.0
				folk += 1
		# Koridor kenarinda dikey boru (iki sirada bir)
		if r % 2 == 1:
			var px: float = xs_l[1] + 0.25
			_bar(_cabin, Vector3(px, fy + 1.0, z + 0.28), Vector3(px, top, z + 0.28), 0.016, pole)
	_eye = Vector3(xs_r[0] - 0.03, fy + 1.13, z0 + my_row * pitch + 0.02)
