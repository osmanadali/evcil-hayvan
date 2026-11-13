extends Node
## Trafik kurallari (Mafia tarzi): calisan trafik isiklari, hiz sinirlari, devriye gezen polis arabasi,
## kovalamaca ve ceza, yanlis park cezasi.
## - Isikli kavsaklar: OSM'deki isiklar + ana yollarin buyuk kavsaklari. Her kavsakta iki eksen sirayla
##   yesil / sari / kirmizi yanar; trafik arabalari (car.gd) kirmizida dur cizgisinde bekler.
## - Hiz siniri sehirde 50, park ve okul cevresinde 30 km/s; surerken hiz gostergesinin yaninda levha.
## - Polis (beyaz-mavi, tepe lambali; gece lambalari yanip soner) devriye gezer. Yakinindayken sinirin
##   15 km/s ustunde gitmek, kirmizida gecmek, arabaya ya da yayaya carpmak kovalamaca baslatir (siren,
##   ekranda POLIS ve yildizlar). Polisin yaninda durursan ceza yazilir (para duser, yetmezse borc);
##   yeterince uzaklasirsan polisi atlatirsin.
## - Kendi aracini durakta ya da yolun ortasinda 60 sn'den fazla birakirsan cam sileceginin altina sari
##   park cezasi kagidi konur; araca donunce ceza kesilir.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const Car = preload("res://scripts/car.gd")
const Icon = preload("res://scripts/icon.gd")
const _World = preload("res://scripts/world.gd")

const FINES := {"hiz": 150, "kirmizi": 300, "kaza": 400, "yaya": 600}
const FINE_NAMES := {"hiz": "Hız sınırını aşma", "kirmizi": "Kırmızı ışıkta geçme", "kaza": "Kazaya sebep olma",
	"yaya": "Yayaya çarpma"}
const STARS := {"hiz": 1, "kirmizi": 2, "kaza": 2, "yaya": 3}
const PARK_FINE := 200
const PARK_LIMIT := 60.0
const SEE_R := 60.0          # polisin ihlali gordugu mesafe
const CATCH_R := 15.0        # durunca ceza yazilan mesafe
const LOSE_R := 150.0        # bu kadar uzaklasinca polis kaybeder

var m: Node                  # main
var state: Node
var junctions: Array = []    # {node, pos, r, axis, ped, mats: [[k,s,y], [k,s,y]], heads}
var _world: Node3D
var _lit_last := -99.0
var limit := 50
var _zone_t := 0.0
var _slow_zones: Array = []  # [merkez, yaricap] (park ve okul)

# Polis
var police: Node3D
var _bar_mats: Array = []    # [kirmizi, mavi]
var _bar_lights: Array = []  # OmniLight3D
var _siren: AudioStreamPlayer3D
var chasing := false
var _chase_t := 0.0
var _far_t := 0.0
var _stop_t := 0.0
var _offenses: Dictionary = {}     # tur -> true (bu kovalamacada)
var stars := 0
var _route: Array = []
var _route_t := 0.0
var _pspeed := 0.0
var _pyaw := 0.0
var _flash_t := 0.0
var _cool := {}                    # ihlal turu -> bekleme
var _respawn_t := 0.0

# Oyuncu
var _in_junction := -1
var _whistle: AudioStreamWAV

# Park
var _parked := {}                  # arac -> {t, ticket: Node3D}
var _park_t := 0.0

# HUD
var _sign: Control
var _wanted: PanelContainer
var _wanted_sb: StyleBoxFlat
var _star_icons: Array = []


class LimitSign extends Control:
	var limit := 50
	var warn := 0.0
	var font: Font

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c + Vector2(0, 2), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, Color.WHITE)
		draw_circle(c, r * 0.97, Color("d42a24").lerp(Color("ff6a3d"), warn))
		draw_circle(c, r * 0.74, Color.WHITE)
		var txt := str(limit)
		var fs := int(r * 0.92)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("151515"))


func _ready() -> void:
	Car.lights = {}
	Car.light_clock = randf() * Car.CYCLE
	_whistle = _make_whistle()


func setup_world() -> void:
	_world = m.world
	junctions.clear()
	Car.lights = {}
	_build_lights()
	_build_slow_zones()
	_spawn_police()


# ---------------------------------------------------------------- isiklar

## Yol komsulari (yaya yollari haric).
func _road_nbs(k: int) -> Array:
	var out: Array = []
	for nb in ParkMap.links[k]:
		if ParkMap.road_width(k, nb) > 0.0 and not nb in out:
			out.append(nb)
	return out


func _build_lights() -> void:
	var d: Dictionary = ParkMap.data
	var picked: Array = []      # dugumler
	# 1) Haritadaki (OSM) isiklar
	for sg in d.get("signals", []):
		var p := Vector2(sg[0], sg[1])
		if not ParkMap.inside_bounds(p, -10.0):
			continue
		var best := -1
		var bd := 1e9
		for i in ParkMap.nodes.size():
			var dd := ParkMap.nodes[i].distance_squared_to(p)
			if dd < bd and _road_nbs(i).size() > 0:
				bd = dd
				best = i
		if best >= 0 and bd < 400.0 and not best in picked:
			picked.append(best)
	# 2) Ana yollarin buyuk kavsaklari (4 kolu olanlar once), aralarinda en az 110 m
	var majors := {}
	for r in d["roads"]:
		if String(r["k"]) in ["primary", "secondary", "tertiary", "primary_link"]:
			for n in r["n"]:
				majors[int(n)] = true
	var cands: Array = []
	for k in majors:
		var nb := _road_nbs(k)
		if nb.size() >= 3 and ParkMap.inside_bounds(ParkMap.nodes[k], -25.0):
			cands.append([k, nb.size()])
	cands.sort_custom(func(a, b): return a[1] > b[1] if a[1] != b[1] else a[0] < b[0])
	for c in cands:
		if picked.size() >= 16:
			break
		var p: Vector2 = ParkMap.nodes[c[0]]
		var ok := true
		for q in picked:
			if ParkMap.nodes[q].distance_to(p) < 110.0:
				ok = false
				break
		if ok:
			picked.append(c[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for k in picked:
		_make_junction(k, rng.randf() * Car.CYCLE)


func _lamp_mat(hex: String) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(hex).darkened(0.75)
	mt.emission_enabled = true
	mt.emission = Color(hex)
	mt.emission_energy_multiplier = 0.0
	mt.roughness = 0.25
	return mt


func _make_junction(k: int, off: float) -> void:
	var c: Vector2 = ParkMap.nodes[k]
	var nbs := _road_nbs(k)
	var wmax := 0.0
	for nb in nbs:
		wmax = maxf(wmax, ParkMap.road_width(k, nb))
	var ped := nbs.size() < 3
	var r := (wmax * 0.5 + 2.6) if not ped else 3.2
	var axis := (c - ParkMap.nodes[nbs[0]]).normalized()
	var mats: Array = [[_lamp_mat("ff1206"), _lamp_mat("ff9a00"), _lamp_mat("12ff4a")],
		[_lamp_mat("ff1206"), _lamp_mat("ff9a00"), _lamp_mat("12ff4a")]]
	var j := {"node": k, "pos": c, "r": r, "axis": axis, "ped": ped, "mats": mats, "shown": -1}
	var pole_m := Kit.mat("3a4048", 0.45)
	var dark := Kit.mat("1d1f22", 0.55)
	var white := Kit.mat("e9e9e4", 0.8)
	for nb in nbs:
		var dvec := (c - ParkMap.nodes[nb])
		if dvec.length() < 0.5:
			continue
		var dir := dvec.normalized()           # kavsaga giris yonu
		var w := ParkMap.road_width(k, nb)
		var right := Vector2(-dir.y, dir.x)
		var ai := 0 if (ped or absf(dir.dot(axis)) > 0.6) else 1
		var base := c - dir * r + right * (w * 0.5 + 0.9)
		var root := Node3D.new()
		root.position = Vector3(base.x, ParkMap.terrain_height(base), base.y)
		root.rotation.y = atan2(-dir.x, -dir.y)      # yerel +z surucuye bakar
		_world.add_child(root)
		var arm := clampf(w * 0.5 - 0.5, 1.5, 4.6)
		Kit.cyl(root, 0.09, 0.12, 5.4, Vector3(0, 2.7, 0), pole_m, 10)
		Kit.cyl(root, 0.16, 0.2, 0.3, Vector3(0, 0.15, 0), pole_m, 10)
		# Yola uzanan kol (sola, seridin ustune)
		Kit.box(root, Vector3(arm + 0.2, 0.12, 0.12), Vector3(-arm * 0.5, 5.25, 0), pole_m)
		_head(root, Vector3(-arm + 0.2, 4.55, 0.0), mats[ai], dark)
		_head(root, Vector3(0, 2.75, 0.14), mats[ai], dark, 0.8)
		# Yaya dugmesi kutusu
		Kit.box(root, Vector3(0.14, 0.22, 0.1), Vector3(0, 1.15, 0.13), Kit.mat("f2c230", 0.6))
		m.world._add_circle(Vector3(base.x, base.y, 0.18))
		# Dur cizgisi (seridin uzerinde)
		var sl := c - dir * (r - 0.4)
		var lane_w := clampf(w * 0.5, 2.5, 7.0)
		var mid := sl + right * lane_w * 0.5
		Kit.box(_world, Vector3(lane_w, 0.02, 0.4), Vector3(mid.x, ParkMap.terrain_height(mid) + 0.035, mid.y), white,
			Vector3(0, atan2(-dir.x, -dir.y), 0))
	junctions.append(j)
	Car.lights[k] = {"axis": axis, "off": off, "r": r, "ped": ped}


## Uc lambali isik kafasi: yerel +z'ye bakar; lambalarin ustunde siperlik.
func _head(root: Node3D, at: Vector3, mats: Array, dark: Material, s := 1.0) -> void:
	Kit.box(root, Vector3(0.38, 1.02, 0.3) * s, at, dark)
	Kit.box(root, Vector3(0.52, 1.16, 0.03) * s, at + Vector3(0, 0, -0.16 * s), Kit.mat("111214", 0.7))
	for i in 3:
		var y := (0.32 - i * 0.32) * s
		Kit.cyl(root, 0.115 * s, 0.115 * s, 0.05 * s, at + Vector3(0, y, 0.16 * s), mats[i], 14, Vector3(PI / 2, 0, 0))
		Kit.box(root, Vector3(0.3, 0.03, 0.16) * s, at + Vector3(0, y + 0.13 * s, 0.22 * s), dark, Vector3(-0.3, 0, 0))


func _update_lights() -> void:
	var night: float = clampf(float(m.world._lamp_night), 0.0, 1.0)
	for j in junctions:
		var k: int = j["node"]
		var a: int = Car.light_at(k, j["axis"])
		var b: int = Car.light_at(k, Vector2(-j["axis"].y, j["axis"].x))
		var key := a * 10 + b + int(night * 4.0) * 100
		if key == j["shown"]:
			continue
		j["shown"] = key
		var on_e := 1.5 + night * 0.5
		for ai in 2:
			var st := a if ai == 0 else b
			var mats: Array = j["mats"][ai]
			mats[0].emission_energy_multiplier = on_e if st >= 2 else 0.0
			mats[1].emission_energy_multiplier = on_e if st == 1 else 0.0
			mats[2].emission_energy_multiplier = on_e if st == 0 else 0.0
			for i in 3:
				var e: bool = mats[i].emission_energy_multiplier > 0.0
				mats[i].albedo_color = mats[i].emission if e else Color(mats[i].emission).darkened(0.78)


# ---------------------------------------------------------------- hiz siniri

func _build_slow_zones() -> void:
	_slow_zones.clear()
	for pk in ParkMap.data.get("parks", []):
		var poly := ParkMap.to_poly(pk["p"])
		var box := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		if box.size.x * box.size.y < 2500.0:
			continue
		_slow_zones.append([box.get_center(), box.size.length() * 0.5 + 20.0])
	for po in ParkMap.data.get("pois", []):
		if po["k"] == "okul":
			_slow_zones.append([Vector2(po["pos"][0], po["pos"][1]), 70.0])


func _zone_limit(p: Vector2) -> int:
	for z in _slow_zones:
		if p.distance_to(z[0]) < z[1]:
			return 30
	return 50


# ---------------------------------------------------------------- polis arabasi

func _spawn_police() -> void:
	if m.world.car_mesh == null:
		return
	police = Car.new()
	police.cruise = 7.0
	police.node = _node_near(m._owner_pos(), 90.0, 220.0)
	police.owner_node = m.owner_node
	var body: Node3D = m.world.make_car(Color("f4f6f8"))
	police.add_child(body)
	_dress_police(body)
	m.add_child(police)
	Car.traffic.append(police)
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = _make_siren()
	_siren.unit_size = 18.0
	_siren.max_db = 2.0
	_siren.volume_db = -2.0
	_siren.position = Vector3(0, 1.6, 0)
	police.add_child(_siren)


## Yol aginda, verilen uzaklik araliginda rastgele bir dugum.
func _node_near(p: Vector2, dmin: float, dmax: float) -> int:
	for t in 120:
		var k := randi() % ParkMap.nodes.size()
		var dd := ParkMap.nodes[k].distance_to(p)
		if ParkMap.road_next[k].size() > 0 and dd > dmin and dd < dmax and ParkMap.inside_bounds(ParkMap.nodes[k], 20.0):
			return k
	return ParkMap.nearest_node(p)


func _dress_police(body: Node3D) -> void:
	var mi: MeshInstance3D = body.get_child(0)
	var box: AABB = mi.transform * mi.mesh.get_aabb()
	var L := box.size.z
	var W := box.size.x
	var H := box.size.y
	var cz := box.get_center().z
	var blue := Kit.mat("1f4fb8", 0.35)
	blue.metallic = 0.3
	# Yanlarda lacivert-mavi serit ve POLIS yazisi
	for side in [-1, 1]:
		var x: float = box.get_center().x + side * (W * 0.5 + 0.005)
		Kit.box(body, Vector3(0.02, H * 0.1, L * 0.6), Vector3(x, box.position.y + H * 0.4, cz + L * 0.04), blue)
		var lb := Label3D.new()
		lb.text = "POLİS"
		lb.font = preload("res://assets/fonts/Anton-Regular.ttf")
		lb.font_size = 64
		lb.pixel_size = 0.0055
		lb.modulate = Color("1f3f9a")
		lb.outline_size = 0
		lb.position = Vector3(x + side * 0.012, box.position.y + H * 0.53, cz + L * 0.05)
		lb.rotation.y = side * PI / 2
		body.add_child(lb)
	# Kaput: POLIS
	var hood := Label3D.new()
	hood.text = "POLİS"
	hood.font = preload("res://assets/fonts/Anton-Regular.ttf")
	hood.font_size = 64
	hood.pixel_size = 0.005
	hood.modulate = Color("1f3f9a")
	hood.outline_size = 0
	hood.position = Vector3(box.get_center().x, box.position.y + H * 0.62, box.position.z + L * 0.17)
	hood.rotation = Vector3(-PI / 2 + 0.12, PI, 0)
	body.add_child(hood)
	# Tepe lambasi
	var roof_y := box.end.y
	var roof_z := cz + L * 0.04
	Kit.box(body, Vector3(W * 0.62, 0.08, 0.3), Vector3(box.get_center().x, roof_y + 0.02, roof_z), Kit.mat("2a2d33", 0.5))
	var red := Kit.glow("ff2a2a", 0.3)
	var bl := Kit.glow("2a6bff", 0.3)
	red.albedo_color = Color("6a1010")
	bl.albedo_color = Color("102a6a")
	_bar_mats = [red, bl]
	for i in 2:
		var side := -1 if i == 0 else 1
		Kit.box(body, Vector3(W * 0.27, 0.13, 0.26), Vector3(box.get_center().x + side * W * 0.155, roof_y + 0.12, roof_z), _bar_mats[i])
		var l := OmniLight3D.new()
		l.light_color = Color("ff3030") if i == 0 else Color("3a70ff")
		l.omni_range = 9.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.position = Vector3(box.get_center().x + side * W * 0.3, roof_y + 0.4, roof_z)
		body.add_child(l)
		_bar_lights.append(l)
	Kit.box(body, Vector3(W * 0.06, 0.14, 0.27), Vector3(box.get_center().x, roof_y + 0.12, roof_z), Kit.glow("f2f2f2", 0.6))


func _update_police_lights(dt: float) -> void:
	if police == null:
		return
	var night: float = clampf(float(m.world._lamp_night), 0.0, 1.0)
	var flash := chasing or night > 0.3
	_flash_t += dt
	# Cift cakar: kirmizi iki kez, mavi iki kez
	var ph := fmod(_flash_t, 0.6)
	var red_on := flash and (ph < 0.08 or (ph > 0.14 and ph < 0.22))
	var blue_on := flash and (ph > 0.3 and ph < 0.38 or (ph > 0.44 and ph < 0.52))
	var e := 9.0 if chasing else 6.0
	var idle := 1.1 if flash else 0.25
	_bar_mats[0].emission_energy_multiplier = e if red_on else idle
	_bar_mats[1].emission_energy_multiplier = e if blue_on else idle
	_bar_lights[0].light_energy = (2.0 + night * 5.0) if red_on else 0.0
	_bar_lights[1].light_energy = (2.0 + night * 5.0) if blue_on else 0.0


# ---------------------------------------------------------------- ses

func _make_siren() -> AudioStreamWAV:
	var rate := 22050
	var secs := 4.0
	var n := int(rate * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		# Yukselip alcalan uzun "uuuu-iiii" (wail): 4 sn'de bir tur
		var f := 760.0 + 560.0 * (0.5 - 0.5 * cos(TAU * t / secs))
		ph += TAU * f / rate
		var v := sin(ph) * 0.62 + sin(ph * 2.0) * 0.22 + sin(ph * 3.0) * 0.1
		v = tanh(v * 1.6) * 0.55
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w


func _make_whistle() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.75)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var f := 2750.0 + 140.0 * sin(TAU * 28.0 * t)       # duduk titremesi
		ph += TAU * f / rate
		var env := minf(t / 0.03, 1.0) * clampf((0.75 - t) / 0.12, 0.0, 1.0)
		var v := sin(ph) * env * (0.75 + 0.25 * sin(TAU * 28.0 * t)) * 0.5 + (randf() - 0.5) * 0.04 * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _play_2d(s: AudioStream, db: float) -> void:
	if not state.d.get("sound", true):
		return
	var a := AudioStreamPlayer.new()
	a.stream = s
	a.volume_db = db
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


# ---------------------------------------------------------------- ana dongu

func update(dt: float) -> void:
	if m.world == null or m.owner_node == null or ParkMap.home != null and m._ride == null and not chasing:
		return
	if _world != m.world:
		setup_world()
	Car.light_clock += dt
	_update_lights()
	_update_police_lights(dt)
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - dt
	var driving: bool = m._ride != null and m._ride.has_meta("kind") and m._ride.get_meta("kind") != "bisiklet"
	var kmh: float = absf(m._drive_speed) * 3.6 if m._ride != null else 0.0
	_zone_t -= dt
	if _zone_t <= 0.0:
		_zone_t = 0.4
		limit = _zone_limit(m._owner_pos())
	if driving:
		_check_driver(dt, kmh)
		if kmh <= limit + 3 and kmh > 8.0:
			state.count("lawful", absf(m._drive_speed) * dt)
	else:
		_in_junction = -1
	if police and is_instance_valid(police):
		if chasing:
			_update_chase(dt)
		else:
			_patrol_check(dt)
	_park_t -= dt
	if _park_t <= 0.0:
		_park_t = 1.0
		_update_parking(1.0)
		if police and is_instance_valid(police):
			police.owner_node = m.owner_node
			if not police in Car.traffic:
				Car.traffic.append(police)
	_update_hud(dt, driving, kmh)


func _police_dist() -> float:
	if police == null:
		return 1e9
	return Vector2(police.position.x, police.position.z).distance_to(m._owner_pos())


func _check_driver(_dt: float, kmh: float) -> void:
	var p: Vector2 = m._owner_pos()
	var near_police := _police_dist() < SEE_R
	# Hiz
	if kmh > limit + 15 and near_police:
		_offense("hiz")
	# Kirmizi isik: kavsak kutusuna girerken
	var inside := -1
	for j in junctions:
		if p.distance_to(j["pos"]) < float(j["r"]) * 0.8:
			inside = j["node"]
			break
	if inside >= 0 and inside != _in_junction and kmh > 10.0:
		var fwd := Vector2(-sin(m._ride.rotation.y), -cos(m._ride.rotation.y)) * signf(m._drive_speed)
		if Car.light_at(inside, fwd) == 2:
			if near_police:
				_offense("kirmizi")
			else:
				m.ui.toast("Kırmızı ışıkta geçtin! Polis görseydi ceza yazardı.")
	_in_junction = inside
	# Carpma: araba ve yaya
	if kmh > 14.0:
		for o in Car.traffic:
			if o == m._ride or o == police or not is_instance_valid(o) or not o.is_visible_in_tree():
				continue
			if Vector2(o.global_position.x, o.global_position.z).distance_to(p) < 2.7:
				if near_police:
					_offense("kaza")
				elif float(_cool.get("kaza_t", 0.0)) <= 0.0:
					_cool["kaza_t"] = 5.0
					m._sfx("araba_kapi", -2.0, 0.6)
				break
	if kmh > 10.0:
		for n in m._npc_people:
			if n.visible and Vector2(n.position.x, n.position.z).distance_to(p) < 1.7:
				if near_police:
					_offense("yaya")
				elif float(_cool.get("yaya_t", 0.0)) <= 0.0:
					_cool["yaya_t"] = 5.0
					m._say(n, "Hey! Dikkat etsene!")
				break


func _offense(kind: String) -> void:
	if float(_cool.get(kind, 0.0)) > 0.0:
		return
	_cool[kind] = 6.0
	var first := not chasing
	_offenses[kind] = true
	stars = maxi(stars, int(STARS[kind]))
	if first:
		_start_chase()
	m.ui.toast("Polis: %s! Kenara çek!" % FINE_NAMES[kind])


func _start_chase() -> void:
	chasing = true
	_chase_t = 0.0
	_far_t = 0.0
	_stop_t = 0.0
	_route_t = 0.0
	police.set_process(false)
	police.obey_lights = false
	_pspeed = float(police._speed)
	_pyaw = police.rotation.y
	if state.d.get("sound", true):
		_siren.play()
	m._say(police, "Polis! Sağa çek!")


func _end_chase() -> void:
	chasing = false
	_offenses.clear()
	stars = 0
	_siren.stop()
	var pp := Vector2(police.position.x, police.position.z)
	police.summon(ParkMap.nearest_node(pp), 3.0)
	police._pos = Vector2.INF
	police.obey_lights = true
	police.set_process(true)


func _patrol_check(dt: float) -> void:
	# Oyuncudan cok uzaklasan devriye gorus disinda yakina yeniden cikar
	_respawn_t -= dt
	if _respawn_t > 0.0:
		return
	_respawn_t = 3.0
	if _police_dist() > 380.0:
		var k := _node_near(m._owner_pos(), 140.0, 260.0)
		police.summon(k, 0.0)
		police.hold = 0.0


## Yol aginda (yaya yollari haric) en kisa yol: polis kovalarken izler.
func _road_route(from: Vector2, to: Vector2) -> Array:
	var start := ParkMap.nearest_node(from)
	var goal := ParkMap.nearest_node(to)
	var n := ParkMap.nodes.size()
	var dist := PackedFloat32Array()
	var back := PackedInt32Array()
	dist.resize(n)
	back.resize(n)
	dist.fill(1e9)
	back.fill(-1)
	dist[start] = 0.0
	var open: Array[int] = [start]
	var steps := 0
	while not open.is_empty() and steps < 4000:
		steps += 1
		var at := 0
		for i in open.size():
			if dist[open[i]] < dist[open[at]]:
				at = i
		var cur: int = open[at]
		open.remove_at(at)
		if cur == goal:
			break
		for nb in ParkMap.links[cur]:
			if ParkMap.road_width(cur, nb) <= 0.0:
				continue
			var nd := dist[cur] + ParkMap.nodes[cur].distance_to(ParkMap.nodes[nb])
			if nd < dist[nb]:
				dist[nb] = nd
				back[nb] = cur
				open.append(nb)
	var out: Array = []
	var k := goal
	while k >= 0:
		out.push_front(ParkMap.nodes[k])
		k = back[k]
	return out


func _update_chase(dt: float) -> void:
	_chase_t += dt
	var me := Vector2(police.position.x, police.position.z)
	var target: Vector2 = m._owner_pos()
	var d := me.distance_to(target)
	_route_t -= dt
	if _route_t <= 0.0:
		_route_t = 1.2
		_route = _road_route(me, target) if d > 30.0 else []
	# Rota uzerindeki bir sonraki hedef
	var aim := target
	while _route.size() > 1 and me.distance_to(_route[0]) < 6.0:
		_route.pop_front()
	if d > 30.0 and not _route.is_empty():
		aim = _route[0]
	var want := 23.0
	if d < 30.0:
		var ps := absf(m._drive_speed) if m._ride != null else 0.0
		want = clampf(ps + (d - 9.0) * 0.8, 0.0, 23.0)
	if d < 8.5:
		want = 0.0
	_pspeed = move_toward(_pspeed, want, dt * (10.0 if want < _pspeed else 6.0))
	var to := aim - me
	if to.length() > 0.5:
		var yaw_to := atan2(-to.x, -to.y)
		_pyaw = rotate_toward(_pyaw, yaw_to, dt * (1.6 + 1.2 * clampf(1.0 - _pspeed / 23.0, 0.0, 1.0)))
	var fwd := Vector2(-sin(_pyaw), -cos(_pyaw))
	var np: Vector2 = m.world.resolve(me + fwd * _pspeed * dt, 1.1, me)
	if np.distance_to(me + fwd * _pspeed * dt) > 0.05:
		_pspeed *= maxf(0.0, 1.0 - 3.0 * dt)
	var h := ParkMap.terrain_height(np)
	police.position = Vector3(np.x, h, np.y)
	police.rotation.y = _pyaw
	police.rotation.x = 0.0
	police._speed = _pspeed
	var body: Node3D = police.get_child(0)
	_World.spin_wheels(body, _pspeed * dt)
	# Ceza: oyuncu polisin yaninda durdu
	var ps2 := absf(m._drive_speed) if m._ride != null else 0.0
	if d < CATCH_R and ps2 < 1.0:
		_stop_t += dt
		if _stop_t > 1.4:
			_issue_ticket()
			return
	else:
		_stop_t = 0.0
	# Kacis
	if d > LOSE_R or (d > 95.0 and _chase_t > 50.0):
		_far_t += dt
		if _far_t > 4.0:
			m.ui.toast("Polisi atlattın! Şimdilik...")
			_end_chase()
	else:
		_far_t = 0.0


func _issue_ticket() -> void:
	var total := 0
	var lines: Array = []
	for k in _offenses:
		total += int(FINES[k])
		lines.append("%s: %d ₺" % [FINE_NAMES[k], FINES[k]])
	_play_2d(_whistle, -6.0)
	m._say(police, "Ehliyet, ruhsat lütfen.")
	var res := _charge(total)
	_end_chase()
	police.hold = 6.0
	_show_receipt("TRAFİK CEZASI", lines, total, res)


## Cezayi tahsil eder: para yetmezse kalan borca yazilir (para eksiye dusmez). [odenen, borc]
func _charge(total: int) -> Array:
	var coins := int(state.d.get("coins", 0))
	var pay := mini(coins, total)
	state.d["coins"] = coins - pay
	var debt := int(state.d.get("traffic_debt", 0)) + (total - pay)
	state.d["traffic_debt"] = debt
	state.d["traffic_fines"] = int(state.d.get("traffic_fines", 0)) + 1
	state.save_game()
	return [pay, total - pay]


func _show_receipt(title: String, lines: Array, total: int, res: Array) -> void:
	var sub := "Kesilen ceza: %d ₺" % total
	m.ui.toast("Ceza yazıldı: %d ₺" % total)
	var body: VBoxContainer = m.ui._open_panel(title, sub)
	for l in lines:
		_row(body, "• " + l, Color.WHITE)
	_row(body, "Ödenen: %d ₺" % res[0], Color("8fe39a"))
	if int(res[1]) > 0:
		_row(body, "Borca yazılan: %d ₺  (toplam borç %d ₺)" % [res[1], state.d["traffic_debt"]], Color("ff8a7a"))
	m.ui._panel_item(body, "Tamam", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _row(body: Node, text: String, col: Color) -> void:
	var l: Label = m.ui._fx_label(body, text, m.ui.F_BODY, 22, col, 4)
	l.custom_minimum_size = Vector2(400, 30)


# ---------------------------------------------------------------- park cezasi

func _bad_parking(p: Vector2) -> String:
	for st in m.world.stops:
		if p.distance_to(st["pos"]) < 9.0:
			return "Otobüs durağına park"
	for po in ParkMap.data.get("pois", []):
		if po["k"] == "durak" and p.distance_to(Vector2(po["pos"][0], po["pos"][1])) < 9.0:
			return "Otobüs durağına park"
	# Yolun ortasi: en yakin yol parcasinin eksenine cok yakin
	for i in ParkMap.nodes.size():
		var a: Vector2 = ParkMap.nodes[i]
		if absf(a.x - p.x) > 60.0 or absf(a.y - p.y) > 60.0:
			continue
		for nb in ParkMap.road_next[i]:
			var w := ParkMap.road_width(i, nb)
			if w <= 0.0:
				continue
			if ParkMap.seg_dist(p, a, ParkMap.nodes[nb]) < maxf(w * 0.5 - 2.4, 1.0):
				return "Yolun ortasına park"
	return ""


func _update_parking(step: float) -> void:
	for r in m._rides:
		if not is_instance_valid(r) or not r.has_meta("kind") or r.get_meta("kind") == "bisiklet":
			continue
		if r == m._ride:
			r.set_meta("driven", true)
			var info: Dictionary = _parked.get(r, {})
			if info.has("ticket"):
				_collect_park_fine(r, info)
			_parked.erase(r)
			continue
		if not r.has_meta("driven"):
			continue
		var info: Dictionary = _parked.get(r, {"t": 0.0, "why": ""})
		var p := Vector2(r.position.x, r.position.z)
		var why := _bad_parking(p) if not info.has("ticket") else String(info["why"])
		if why == "":
			_parked.erase(r)
			continue
		info["why"] = why
		info["t"] = float(info["t"]) + step
		if float(info["t"]) > PARK_LIMIT and not info.has("ticket"):
			info["ticket"] = _put_ticket(r)
		_parked[r] = info


## Cam sileceginin altina sari ceza kagidi.
func _put_ticket(r: Node3D) -> Node3D:
	var body: Node3D = r.get_child(0) if r.get_child_count() > 0 else r
	var box := AABB()
	var first := true
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or String(mi.name).begins_with("wheel"):
			continue
		var xf := Car._rel(r, mi)
		var a := xf * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
		for si in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var stp := maxi(1, verts.size() / 5000)
			for k in range(0, verts.size(), stp):
				pts.append(xf * verts[k])
	var paper := Node3D.new()
	paper.name = "ParkCezasi"
	# On cam: surucu tarafinda, camin alt-orta yuksekliginde en ondeki (dis) yuzey noktasi
	var tx := box.get_center().x - box.size.x * 0.17
	var y := box.position.y + box.size.y * 0.76
	var at := Vector3(tx, y, box.position.z + box.size.z * 0.33)
	var bz := 1e9
	for q in pts:
		if absf(q.x - tx) < 0.12 and absf(q.y - y) < 0.06 and q.z < bz and q.z > box.position.z + box.size.z * 0.15:
			bz = q.z
			at = q
	paper.position = at + Vector3(0, 0.03, -0.035)
	paper.rotation.x = -0.95
	r.add_child(paper)
	var pm := Kit.mat("ffe14a", 0.85)
	pm.emission_enabled = true
	pm.emission = Color("ffe14a")
	pm.emission_energy_multiplier = 0.25
	Kit.box(paper, Vector3(0.3, 0.012, 0.42), Vector3.ZERO, pm)
	var lb := Label3D.new()
	lb.text = "PARK\nCEZASI"
	lb.font_size = 40
	lb.pixel_size = 0.0022
	lb.modulate = Color("b0201a")
	lb.outline_size = 0
	lb.position = Vector3(0, 0.008, 0)
	lb.basis = Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
	paper.add_child(lb)
	# Kagidin uzerinde silecek kolu
	Kit.box(paper, Vector3(0.035, 0.02, 0.5), Vector3(0.13, 0.012, 0.0), Kit.mat("15171a", 0.6), Vector3(0, 0.35, 0))
	return paper


func _collect_park_fine(r: Node3D, info: Dictionary) -> void:
	var t: Node3D = info["ticket"]
	if is_instance_valid(t):
		t.queue_free()
	var res := _charge(PARK_FINE)
	_show_receipt("PARK CEZASI", [String(info.get("why", "Hatalı park")) + ": %d ₺" % PARK_FINE], PARK_FINE, res)


# ---------------------------------------------------------------- HUD

func _update_hud(dt: float, driving: bool, kmh: float) -> void:
	var mm: Control = m.minimap
	if mm == null:
		return
	if _sign == null:
		_sign = LimitSign.new()
		_sign.font = m.ui.F_BODY
		_sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sign.size = Vector2(54, 54)
		mm.get_parent().add_child(_sign)
	_sign.visible = driving and mm.visible
	if _sign.visible:
		_sign.position = mm.position + Vector2(-50, -64)
		var over := kmh > limit + 3
		var w := (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)) if over else 0.0
		if _sign.limit != limit or absf(_sign.warn - w) > 0.02:
			_sign.limit = limit
			_sign.warn = w
			_sign.scale = Vector2.ONE * (1.0 + w * 0.12)
			_sign.pivot_offset = _sign.size * 0.5
			_sign.queue_redraw()
	# Aranma gostergesi
	if chasing and _wanted == null:
		_build_wanted()
	if _wanted:
		_wanted.visible = chasing
		if chasing:
			var ph := fmod(_flash_t, 0.6) < 0.3
			_wanted_sb.border_color = Color("ff2a2a") if ph else Color("2a6bff")
			for i in _star_icons.size():
				(_star_icons[i] as Control).modulate = Color.WHITE if i < stars else Color(1, 1, 1, 0.22)


func _build_wanted() -> void:
	_wanted = PanelContainer.new()
	_wanted_sb = StyleBoxFlat.new()
	_wanted_sb.bg_color = Color(0.03, 0.03, 0.06, 0.82)
	_wanted_sb.set_border_width_all(3)
	_wanted_sb.border_width_bottom = 6
	_wanted_sb.set_corner_radius_all(6)
	_wanted_sb.content_margin_left = 16
	_wanted_sb.content_margin_right = 16
	_wanted_sb.content_margin_top = 4
	_wanted_sb.content_margin_bottom = 6
	_wanted.add_theme_stylebox_override("panel", _wanted_sb)
	_wanted.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wanted.offset_top = 18
	_wanted.offset_left = -130
	_wanted.offset_right = 130
	_wanted.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wanted.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.ui.hud.add_child(_wanted)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	_wanted.add_child(row)
	m.ui._fx_label(row, "POLİS", m.ui.F_TITLE, 40, Color.WHITE, 8)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(8, 0)
	row.add_child(sp)
	_star_icons.clear()
	for i in 3:
		var ic := Icon.new("star", Color("ffd23a"), 34.0)
		row.add_child(ic)
		_star_icons.append(ic)


# ---------------------------------------------------------------- telefon

func phone_app() -> void:
	var debt := int(state.d.get("traffic_debt", 0))
	var body: VBoxContainer = m.ui._open_panel("TRAFİK", "Şehirde hız sınırı 50 km/s, park ve okul çevresinde 30 km/s. Kırmızıda dur, polisin önünde dikkatli ol.")
	_row(body, "Ceza borcun: %d ₺" % debt, Color("ff8a7a") if debt > 0 else Color("8fe39a"))
	_row(body, "Yazılan ceza sayısı: %d" % int(state.d.get("traffic_fines", 0)), Color.WHITE)
	if debt > 0:
		m.ui._panel_item(body, "Borcu öde", func():
			var coins := int(state.d.get("coins", 0))
			var pay := mini(coins, debt)
			if pay <= 0:
				m.ui.toast("Yeterli paran yok")
				return
			state.d["coins"] = coins - pay
			state.d["traffic_debt"] = debt - pay
			state.save_game()
			m.ui.toast("%d ₺ ceza borcu ödendi" % pay)
			phone_app())
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


# ---------------------------------------------------------------- test

## --police: oyuncuyu araca bindirip hizla surdurur, polisi arkasina koyar ve kovalamayi baslatir.
func debug_police() -> void:
	if police == null:
		return
	var p: Vector2 = m._owner_pos()
	var fwd := Vector2(-sin(m._ride.rotation.y), -cos(m._ride.rotation.y)) if m._ride else Vector2(0, -1)
	var back := p - fwd * 14.0
	police.set_process(false)
	police.position = Vector3(back.x, ParkMap.terrain_height(back), back.y)
	police.rotation.y = m._ride.rotation.y if m._ride else 0.0
	if m._ride:
		m._drive_speed = 22.0
	_offense("hiz")
	_pspeed = 18.0
	_pyaw = police.rotation.y


## --redlight: en yakin isikli kavsagin yanina gider; o yon kirmizi olacak sekilde saati ayarlar.
func debug_redlight() -> Dictionary:
	if junctions.is_empty():
		return {}
	var best: Dictionary = junctions[0]
	for j in junctions:
		if not j["ped"] and j["pos"].distance_to(m._owner_pos()) < best["pos"].distance_to(m._owner_pos()):
			best = j
	# Ana eksen kirmizi olsun (t = 20)
	var lj: Dictionary = Car.lights[best["node"]]
	Car.light_clock = fposmod(20.0 - float(lj["off"]), Car.CYCLE)
	return best


## Isikli kavsaga gelen bir kolun basindan (kavsaktan en az 35 m geride) dugum zinciri.
func approach_chain(j: Dictionary) -> Array:
	var k: int = j["node"]
	var ax: Vector2 = j["axis"]
	for nb in _road_nbs(k):
		var dir: Vector2 = (ParkMap.nodes[k] - ParkMap.nodes[nb]).normalized()
		if not j["ped"] and absf(dir.dot(ax)) < 0.6:
			continue
		if not ParkMap.road_next[nb].has(k):
			continue
		var chain: Array = [k, nb]
		var cur: int = nb
		var prev: int = k
		while ParkMap.nodes[cur].distance_to(ParkMap.nodes[k]) < 45.0 and chain.size() < 12:
			var nxt := -1
			for q in _road_nbs(cur):
				if q != prev and ParkMap.road_next[q].has(cur):
					nxt = q
					break
			if nxt < 0:
				break
			prev = cur
			cur = nxt
			chain.append(cur)
		return chain
	return []


## --redlight: kavsaga gelen kola iki trafik arabasi koyar (kirmizida durmalari icin), kamerayi ayarlar.
func debug_redlight_scene() -> void:
	var j := debug_redlight()
	if j.is_empty():
		return
	var chain := approach_chain(j)
	print("ISIK kavsak=", j["node"], " konum=", j["pos"], " r=", j["r"], " zincir=", chain.size(), " sayi=", junctions.size())
	if chain.size() < 2:
		return
	var placed := 0
	for c in m._cars:
		if placed >= 2:
			break
		var i: int = chain.size() - 1 - placed * 2
		if i < 1:
			break
		c.node = chain[i]
		c._prev = -1
		c._queued = chain[i - 1]
		c._pos = Vector2.INF
		c._pick()
		c._t = 0.3
		c._speed = 6.0
		placed += 1
	var c0: Vector2 = j["pos"]
	var far: Vector2 = ParkMap.nodes[chain[mini(2, chain.size() - 1)]]
	var dir := (c0 - far).normalized()
	var right := Vector2(-dir.y, dir.x)
	var side := c0 - dir * (float(j["r"]) + 4.0) + right * 9.0
	m._place_owner(c0 - dir * (float(j["r"]) + 2.0) + right * 6.5)
	m._mode = "debug"
	m.ui.visible = false
	var eye := c0 - dir * (float(j["r"]) + float(m._args.get("tdist", "16"))) - right * 0.5
	m.cam.position = Vector3(eye.x, ParkMap.terrain_height(eye) + 2.2, eye.y)
	m.cam.look_at(Vector3(c0.x + right.x * 1.0, ParkMap.terrain_height(c0) + 2.8, c0.y + right.y * 1.0))
	if side == Vector2.INF:
		pass


## --parkfine: oyuncunun arabasini yolun ortasina birakir ve 60 sn gecmis gibi ceza kagidi koyar.
func debug_parkfine() -> void:
	var car: Node3D = null
	for r in m._rides:
		if r.get_meta("kind") == "araba":
			car = r
	if car == null:
		return
	var k := 0
	var bd := 1e9
	for i in ParkMap.nodes.size():
		if ParkMap.road_next[i].size() > 0 and ParkMap.road_width(i, ParkMap.road_next[i][0]) >= 6.0:
			var dd := ParkMap.nodes[i].distance_to(m._owner_pos())
			if dd < bd:
				bd = dd
				k = i
	var nb: int = ParkMap.road_next[k][0]
	var p: Vector2 = ParkMap.nodes[k].lerp(ParkMap.nodes[nb], 0.5)
	var d := (ParkMap.nodes[nb] - p).normalized()
	car.position = Vector3(p.x, ParkMap.terrain_height(p), p.y)
	car.rotation.y = atan2(-d.x, -d.y)
	car.set_meta("driven", true)
	_parked[car] = {"t": PARK_LIMIT + 1.0, "why": _bad_parking(p)}
	_update_parking(1.0)
	print("PARK ", _parked.get(car, {}).get("why", "yok"), " kagit=", _parked.get(car, {}).has("ticket"))
	m._place_owner(p + Vector2(-d.y, d.x) * 3.0)
	m._mode = "debug"
	var f := Vector3(-sin(car.rotation.y), 0, -cos(car.rotation.y))
	m.cam.position = car.position + f * 3.6 + Vector3(0, 2.2, 0) + Vector3(f.z, 0, -f.x) * 1.2
	m.cam.look_at(car.position + Vector3(0, 1.1, 0) + f * 0.6)


## --police: oyuncunun arabasini en yakin genis ve uzun yol parcasina koyar, polisi arkasina.
func debug_police_scene() -> void:
	var o: Vector2 = m._owner_pos()
	var best := -1
	var bd := 1e9
	for i in ParkMap.nodes.size():
		for nb in ParkMap.road_next[i]:
			if ParkMap.road_width(i, nb) >= 8.0 and ParkMap.nodes[i].distance_to(ParkMap.nodes[nb]) > 25.0:
				var dd := ParkMap.nodes[i].distance_to(o)
				if dd < bd and ParkMap.inside_bounds(ParkMap.nodes[i], 40.0):
					bd = dd
					best = i * 65536 + nb
	if best < 0:
		return
	var a: Vector2 = ParkMap.nodes[best / 65536]
	var b: Vector2 = ParkMap.nodes[best % 65536]
	var d := (b - a).normalized()
	var p := a + d * 18.0 + Vector2(-d.y, d.x) * 2.0
	m._ride.position = Vector3(p.x, ParkMap.terrain_height(p), p.y)
	m._ride.rotation.y = atan2(-d.x, -d.y)
	m._cam_yaw = m._ride.rotation.y
	m.owner_node.position = m._ride.position
	debug_police()
