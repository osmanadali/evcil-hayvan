extends Node
## Ek ulasim: Pedal Ankara bisiklet istasyonlari (kirala / teslim et), taksi duragi, yogun saat trafik
## sikisikligi (kornalar) ve Kizilay meydani (metroyla gidilen hafif bolge).

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const Car = preload("res://scripts/car.gd")
const Npc = preload("res://scripts/npc.gd")
const PersonModel = preload("res://scripts/person_model.gd")

const TEAL := "13a89e"
const UNLOCK_FEE := 3
const PER_MIN := 3
const DOCKS := 6
const SQUARE := Vector2(138, -34)       # Kizilay meydani merkezi (gar haritasinda bos arazi)
const HALF := 34.0

var m: Node
var state: Node
var stations: Array = []     # {pos, yaw, axis, docks: [Vector2], bikes: [Node3D|null]}
var rented: Node3D = null
var rent_t := 0.0
var rent_paid := 0

var rank: Dictionary = {}    # {pos, yaw, slots: [Vector2], taxis: [Node3D|null], booth}
var _boarded: Node3D = null
var _board_t := 0.0
var _refill_t := 0.0

var jam_force := false
var jam: Dictionary = {}     # {nodes: [int], center: Vector2, extra: [Car]}
var _jam_t := 0.0
var _honk_t := 2.0
var _clock_t := 0.0
var _horns: Array = []

var _fountain_jets: Array = []
var _fx_t := 0.0


# ---------------------------------------------------------------- kurulum

func build() -> void:
	if ParkMap.zone == "kizilay":
		_build_square()
	_build_stations()
	_build_rank()
	_horns = [_make_horn(392.0, 0.32), _make_horn(440.0, 0.55), _make_horn(349.0, 0.2)]


## Cevrede serbest, tercihen kaldirimda bir nokta ara.
func _free_near(p: Vector2, extent := 3.6, max_r := 60.0) -> Vector2:
	var w: Node3D = m.world
	var best := Vector2.INF
	var r := 0.0
	while r <= max_r and best == Vector2.INF:
		for k in 16:
			var q := p + Vector2.from_angle(k * TAU / 16.0 + r) * r
			if w._inside_building(q) or not w.is_free(q, 1.4):
				continue
			if ParkMap.sidewalk_raise(q) < 0.05 and ParkMap.zone != "kizilay":
				continue
			var ok := true
			var d := Vector2(extent, 0)
			for s in [-1.0, 1.0]:
				if not w.is_free(q + d * s, 0.8) or w._inside_building(q + d * s):
					ok = false
			if ok:
				best = q
				break
		r += 3.0
	return best


func _axis_for(p: Vector2) -> float:
	var n := ParkMap.nearest_node(p)
	var yaw := 0.0
	if n >= 0 and ParkMap.links[n].size() > 0:
		var d := (ParkMap.nodes[ParkMap.links[n][0]] - ParkMap.nodes[n]).normalized()
		yaw = atan2(-d.y, d.x)
	return yaw


func _anchors() -> Array:
	var a: Array = []
	if ParkMap.zone == "kizilay":
		return [SQUARE + Vector2(26, 14), SQUARE + Vector2(-26, 10)]
	if ParkMap.has_spot("baslangic"):
		a.append(ParkMap.spot("baslangic") + Vector2(-9, 9))
	for g in m.world.metro_gates:
		a.append(g["pos"] - g["toward"] * 9.0)
		if a.size() >= 3:
			break
	if m.world.stops.size() > 4:
		a.append(m.world.stops[4]["pos"])
	return a


func _build_stations() -> void:
	var used: Array = []
	for an in _anchors():
		var p := _free_near(an)
		if p == Vector2.INF:
			continue
		var close := false
		for u in used:
			if u.distance_to(p) < 60.0:
				close = true
		if close or used.size() >= 3:
			continue
		used.append(p)
		_make_station(p, 0.0 if ParkMap.zone == "kizilay" else _axis_for(p))


func _make_station(p: Vector2, yaw: float) -> void:
	var w: Node3D = m.world
	var r: Node3D = w._root(p, yaw)
	r.position.y += ParkMap.sidewalk_raise(p)
	var teal := Kit.mat(TEAL, 0.45)
	var dark := Kit.mat("2c3338", 0.6)
	Kit.box(r, Vector3(DOCKS * 0.95 + 0.6, 0.03, 1.5), Vector3(0, 0.02, 0), Kit.mat("3a4247", 0.9))
	var st := {"pos": p, "yaw": yaw, "axis": Vector2(cos(yaw), -sin(yaw)), "docks": [], "bikes": []}
	var axis: Vector2 = st["axis"]
	var bike_len := 1.75
	for i in DOCKS:
		var x := (i - (DOCKS - 1) * 0.5) * 0.95
		Kit.box(r, Vector3(0.1, 0.75, 0.1), Vector3(x, 0.4, -0.55), teal)
		Kit.box(r, Vector3(0.06, 0.06, 0.04), Vector3(x, 0.8, -0.5), Kit.glow("6dffb0", 1.6))
		var dp := p + axis * x
		st["docks"].append(dp)
		var bike: Node3D = null
		if i % 2 == 0 or i == 1:
			bike = m._vehicle("res://assets/models/bisiklet.glb", bike_len, bool(m.VEHICLE_FLIP.get("bisiklet", false)))
			if bike:
				bike.set_meta("kind", "bisiklet")
				bike.set_meta("pa", true)
				bike.position = Vector3(dp.x, ParkMap.walk_height(dp), dp.y)
				bike.rotation.y = yaw
				m.add_child(bike)
		st["bikes"].append(bike)
	# Kiosk: ucta ince pano
	var kx := (DOCKS * 0.95) * 0.5 + 0.7
	Kit.box(r, Vector3(0.18, 2.3, 0.9), Vector3(kx, 1.15, 0), dark)
	Kit.box(r, Vector3(0.22, 1.5, 0.84), Vector3(kx, 1.4, 0), teal)
	var l: Label3D = w._text(r, "PEDAL\nANKARA", Vector3(kx + 0.12, 1.55, 0), Color.WHITE, 0.3)
	l.rotation.y = PI / 2.0
	l.double_sided = true
	var l2: Label3D = w._text(r, "%d ₺ + dk %d ₺" % [UNLOCK_FEE, PER_MIN], Vector3(kx + 0.12, 0.8, 0), Color("ffe36e"), 0.2)
	l2.rotation.y = PI / 2.0
	l2.double_sided = true
	var l3: Label3D = w._text(r, "PEDAL\nANKARA", Vector3(kx - 0.12, 1.55, 0), Color.WHITE, 0.3)
	l3.rotation.y = -PI / 2.0
	l3.double_sided = true
	var kp := p + axis * kx
	w._add_circle(Vector3(kp.x, kp.y, 0.5))
	stations.append(st)


# ---------------------------------------------------------------- taksi duragi

func _build_rank() -> void:
	var w: Node3D = m.world
	var o := Vector2.INF
	var dir := Vector2.RIGHT
	var side := Vector2.DOWN
	if ParkMap.zone == "kizilay":
		o = SQUARE + Vector2(-8, 36)
		dir = Vector2.RIGHT
		side = Vector2.DOWN
	else:
		var anchor: Vector2 = ParkMap.spot("baslangic") if ParkMap.has_spot("baslangic") else Vector2.ZERO
		if m.world.stops.size() > 2:
			anchor = m.world.stops[2]["pos"]
		var best_d := 1e9
		var nodes := ParkMap.nodes
		for i in nodes.size():
			for j in ParkMap.road_next[i]:
				var wd := ParkMap.road_width(i, j)
				var seg := nodes[i].distance_to(nodes[j])
				if wd < 8.0 or seg < 32.0:
					continue
				var mid := (nodes[i] + nodes[j]) * 0.5
				var d := mid.distance_to(anchor)
				if d < best_d and ParkMap.inside_bounds(mid, 20.0):
					var dd := (nodes[j] - nodes[i]) / seg
					var nn := Vector2(-dd.y, dd.x)
					var off := wd * 0.5 - 1.5
					var s0: Vector2 = nodes[i] + dd * (seg * 0.5 - 8.0) + nn * off
					var ok := true
					for k in 4:
						var q := s0 + dd * 5.5 * k
						if w._inside_building(q):
							ok = false
					if ok:
						best_d = d
						o = s0
						dir = dd
						side = nn
		if o == Vector2.INF:
			return
	var yaw := atan2(-dir.x, -dir.y)           # arac -Z'ye bakar
	rank = {"pos": o, "dir": dir, "side": side, "yaw": yaw, "slots": [], "taxis": []}
	for k in 4:
		var sp: Vector2 = o + dir * 5.4 * k
		rank["slots"].append(sp)
		rank["taxis"].append(_spawn_taxi(sp, yaw))
	# Kabin: kaldirimda (yol disinda)
	var bp: Vector2 = o + side * (3.4 if ParkMap.zone != "kizilay" else 4.2) + dir * 5.4
	var r: Node3D = w._root(bp, atan2(side.x, side.y) + PI)
	r.position.y += ParkMap.sidewalk_raise(bp)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.72, 0.86, 0.95, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var yel := Kit.mat("f2c230", 0.4)
	var dk := Kit.mat("2b2b2e", 0.6)
	Kit.box(r, Vector3(2.6, 0.12, 2.2), Vector3(0, 0.06, 0), dk)
	for sx in [-1.2, 1.2]:
		for sz in [-0.95, 0.95]:
			Kit.box(r, Vector3(0.08, 2.2, 0.08), Vector3(sx, 1.15, sz), dk)
	Kit.box(r, Vector3(2.9, 0.12, 2.5), Vector3(0, 2.3, 0), yel)
	Kit.box(r, Vector3(2.4, 1.5, 0.04), Vector3(0, 1.3, -0.95), glass)
	Kit.box(r, Vector3(0.04, 1.5, 1.9), Vector3(-1.2, 1.3, 0), glass)
	Kit.box(r, Vector3(0.04, 1.5, 1.9), Vector3(1.2, 1.3, 0), glass)
	Kit.box(r, Vector3(1.6, 0.06, 0.5), Vector3(0, 1.0, -0.6), Kit.mat("9a6b43", 0.7))
	var lan := Kit.box(r, Vector3(0.9, 0.3, 0.3), Vector3(0, 2.6, 0), Kit.glow("ffcc33", 1.4))
	lan.name = "Fener"
	var t1: Label3D = w._text(r, "TAKSİ", Vector3(0, 2.6, 0.17), Color("1a1a1a"), 0.26)
	t1.double_sided = true
	var t2: Label3D = w._text(r, "TAKSİ", Vector3(0, 2.6, -0.17), Color("1a1a1a"), 0.26)
	t2.rotation.y = PI
	var t3: Label3D = w._text(r, "Yıldız Taksi Durağı", Vector3(0, 2.0, 1.27), Color("1a1a1a"), 0.2)
	t3.double_sided = true
	w._add_circle(Vector3(bp.x, bp.y, 1.3))
	rank["booth"] = bp


func _spawn_taxi(p: Vector2, yaw: float) -> Node3D:
	var v: Node3D = m.world.vehicle("res://assets/models/taksi.glb", 4.5, true)
	if v == null:
		v = m.world.make_car(Color("f2c230"))
	v.set_meta("model", "taksi")
	var wr := Node3D.new()
	wr.add_child(v)
	wr.position = Vector3(p.x, ParkMap.terrain_height(p), p.y)
	wr.rotation.y = yaw
	m.add_child(wr)
	return wr


# ---------------------------------------------------------------- etkilesim

func context() -> Array:
	if m._taxi != null or m._bus_ride != null or ParkMap.home != null:
		return []
	var o: Vector2 = m._owner_pos()
	if m._ride != null:
		if m._ride == rented:
			var s := _station_near(o, 5.0)
			if s >= 0:
				return ["Bisikleti Teslim Et · Pedal Ankara", "pa_return", "coin"]
		return []
	for si in stations.size():
		var st: Dictionary = stations[si]
		if o.distance_to(st["pos"]) > 6.0:
			continue
		for bi in st["bikes"].size():
			var b: Node3D = st["bikes"][bi]
			if b != null and o.distance_to(Vector2(b.position.x, b.position.z)) < 1.4:
				if rented != null:
					return ["Zaten bir bisiklet kiraladın", "", "bag"]
				return ["Bisiklet Kirala · %d ₺ + dk %d ₺" % [UNLOCK_FEE, PER_MIN], "pa_rent:%d:%d" % [si, bi], "coin"]
	if not rank.is_empty():
		var near := false
		for t in rank["taxis"]:
			if t != null and o.distance_to(Vector2(t.position.x, t.position.z)) < 3.6:
				near = true
		if near or o.distance_to(rank["booth"]) < 3.0:
			if _front_taxi() != null:
				return ["Duraktan Taksiye Bin", "tr_board", "star"]
			return ["Taksi Durağı · sıra boş, biraz bekle", "", "star"]
	return []


func _station_near(o: Vector2, r: float) -> int:
	for i in stations.size():
		if o.distance_to(stations[i]["pos"]) < r:
			return i
	return -1


func _front_taxi() -> Node3D:
	var o: Vector2 = m._owner_pos()
	var best: Node3D = null
	var bd := 1e9
	for t in rank["taxis"]:
		if t == null:
			continue
		var d := o.distance_to(Vector2(t.position.x, t.position.z))
		if d < bd:
			bd = d
			best = t
	return best


func command(cmd: String) -> void:
	if cmd.begins_with("pa_rent:"):
		var parts := cmd.split(":")
		var st: Dictionary = stations[int(parts[1])]
		var b: Node3D = st["bikes"][int(parts[2])]
		if b == null or rented != null:
			return
		if not state.spend(UNLOCK_FEE):
			return
		st["bikes"][int(parts[2])] = null
		rented = b
		rent_t = 0.0
		rent_paid = UNLOCK_FEE
		m._rides.append(b)
		m._enter_ride()
		state.count("bikerent")
		m.ui.toast("Bisiklet açıldı · dakikası %d ₺ · istasyona geri bırakınca kiralama biter." % PER_MIN)
	elif cmd == "pa_return":
		_return_bike()
	elif cmd == "tr_board":
		var t := _front_taxi()
		if t != null:
			var i: int = rank["taxis"].find(t)
			m._board_taxi(t)
			if m._taxi == t:
				_boarded = t
				_board_t = 0.0
				rank["taxis"][i] = null
				_refill_t = 20.0


func _return_bike() -> void:
	if rented == null or m._ride != rented:
		return
	var o: Vector2 = m._owner_pos()
	var si := _station_near(o, 5.0)
	if si < 0:
		return
	var st: Dictionary = stations[si]
	var slot := -1
	for i in st["bikes"].size():
		if st["bikes"][i] == null:
			slot = i
			break
	if slot < 0:
		m.ui.toast("Bu istasyon dolu, başka bir istasyona git.")
		return
	var b := rented
	m._exit_ride()
	m._rides.erase(b)
	var dp: Vector2 = st["docks"][slot]
	b.position = Vector3(dp.x, ParkMap.walk_height(dp), dp.y)
	b.rotation = Vector3(0, st["yaw"], 0)
	st["bikes"][slot] = b
	rented = null
	m.ui.toast("Bisiklet teslim edildi · toplam %d ₺ (%d dk)" % [rent_paid, ceili(rent_t / 60.0)])


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	if rented != null:
		rent_t += dt
		var due := UNLOCK_FEE + int(rent_t / 60.0) * PER_MIN
		if due > rent_paid:
			if state.d["coins"] >= PER_MIN:
				state.d["coins"] -= PER_MIN
				state.changed.emit()
				rent_paid += PER_MIN
				m.ui.toast("Pedal Ankara · %d ₺ ücret çekildi" % PER_MIN)
			else:
				m.ui.toast("Bakiye bitti, kiralama sona erdi.")
				if m._ride == rented:
					m._exit_ride()
				m._rides.erase(rented)
				rented.queue_free()
				rented = null
	# Taksi duragi: binen taksi kalkar, sira yenilenir
	if _boarded != null:
		if m._taxi != _boarded:
			_board_t += dt
			if _board_t > 8.0:
				_boarded.queue_free()
				_boarded = null
	if not rank.is_empty():
		_refill_t -= dt
		if _refill_t <= 0.0:
			_refill_t = 6.0
			var slots: Array = rank["slots"]
			for i in slots.size():
				if rank["taxis"][i] == null and (i == 0 or rank["taxis"][i - 1] != null or true):
					var sp: Vector2 = slots[i]
					if m._owner_pos().distance_to(sp) > 12.0:
						rank["taxis"][i] = _spawn_taxi(sp, rank["yaw"])
						break
	_update_jam(dt)
	if ParkMap.zone == "kizilay" and not _fountain_jets.is_empty():
		_fx_t += dt
		for i in _fountain_jets.size():
			var j: Node3D = _fountain_jets[i]
			var k := 0.75 + 0.25 * sin(_fx_t * 3.0 + i)
			j.scale.y = k
			j.position.y = 0.7 + 1.0 * k


# ---------------------------------------------------------------- trafik sikisikligi

func _rush() -> bool:
	var c: float = m.clock
	return jam_force or (c >= 7.5 and c < 9.5) or (c >= 17.0 and c < 19.5)


func _update_jam(dt: float) -> void:
	_clock_t -= dt
	if _clock_t > 0.0:
		return
	_clock_t = 0.3
	var rush := _rush()
	if rush and jam.is_empty():
		_start_jam()
	elif not rush and not jam.is_empty():
		_end_jam()
	if jam.is_empty():
		return
	_jam_t += 0.3
	var nodes: Array = jam["nodes"]
	var idx := 0
	var cars: Array = m._cars.duplicate()
	cars.append_array(jam["extra"])
	var stopped: Array = []
	for c in cars:
		if not is_instance_valid(c) or not c.is_processing():
			continue
		idx += 1
		var p := Vector2(c.position.x, c.position.z)
		var inside := false
		for n in nodes:
			if p.distance_to(ParkMap.nodes[n]) < 22.0:
				inside = true
				break
		if inside:
			var ph := fmod(_jam_t * 0.16 + idx * 0.37, 1.0)
			c.cruise = 0.0 if ph < 0.6 else 2.2
			if c._speed < 0.4:
				stopped.append(c)
		else:
			c.cruise = Car.CRUISE
	# Korna
	_honk_t -= 0.3
	if _honk_t <= 0.0 and not stopped.is_empty():
		_honk_t = randf_range(1.2, 3.5)
		var hc: Node3D = stopped[randi() % stopped.size()]
		if m._owner_pos().distance_to(Vector2(hc.position.x, hc.position.z)) < 80.0:
			_honk(hc)


func _start_jam() -> void:
	var o: Vector2 = m._owner_pos()
	var best_i := -1
	var best_s := 1e9
	var roads: Array = ParkMap.data["roads"]
	for i in roads.size():
		var rd: Dictionary = roads[i]
		var ids: Array = rd["n"]
		if float(rd["w"]) < 7.0 or ids.size() < 4:
			continue
		var c: Vector2 = ParkMap.nodes[ids[ids.size() / 2]]
		if not ParkMap.inside_bounds(c, 40.0):
			continue
		var d := c.distance_to(o)
		var s := absf(d - 120.0)       # oyuncuya yakin ama tam yaninda degil
		if s < best_s and ParkMap.road_next[ids[ids.size() / 2]].size() > 0:
			best_s = s
			best_i = i
	if best_i < 0:
		return
	var ids: Array = roads[best_i]["n"]
	jam = {"nodes": ids.duplicate(), "center": ParkMap.nodes[ids[ids.size() / 2]], "extra": []}
	_jam_t = 0.0
	# Ek arabalar sirayla yol boyunca dizilir
	for k in 9:
		var n: int = ids[mini(k * ids.size() / 9, ids.size() - 1)]
		if ParkMap.road_next[n].is_empty():
			continue
		var car := Car.new()
		car.node = n
		car.owner_node = m.owner_node
		var paints := ["f2f2f2", "9a9da3", "3a3d42", "b23a34", "2f4f8a", "e9e4d6"]
		car.add_child(m.world.traffic_car(k * 2 + 1, Color(paints[k % paints.size()])))
		m.add_child(car)
		Car.traffic.append(car)
		jam["extra"].append(car)
	if jam_force or m.ui != null:
		m.ui.toast("Yoğun saat: trafik sıkışık, ana yollarda kuyruk var.")


func _end_jam() -> void:
	for c in jam["extra"]:
		if is_instance_valid(c):
			Car.traffic.erase(c)
			c.queue_free()
	for c in m._cars:
		c.cruise = Car.CRUISE
	jam = {}


func _honk(c: Node3D) -> void:
	if not state.d["sound"]:
		return
	var n := 2 if randi() % 3 == 0 else 1
	for i in n:
		var pl := AudioStreamPlayer3D.new()
		pl.stream = _horns[randi() % _horns.size()]
		pl.pitch_scale = randf_range(0.92, 1.12)
		pl.max_distance = 90.0
		pl.unit_size = 9.0
		pl.volume_db = -4.0
		c.add_child(pl)
		pl.finished.connect(pl.queue_free)
		get_tree().create_timer(0.38 * i).timeout.connect(func():
			if is_instance_valid(pl):
				pl.play())


func _make_horn(f: float, dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := minf(1.0, t / 0.015) * minf(1.0, (dur - t) / 0.04)
		var v := tanh(2.2 * (sin(TAU * f * t) + sin(TAU * f * 1.26 * t) + 0.4 * sin(TAU * f * 2.0 * t))) * 0.32 * env
		data.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# ---------------------------------------------------------------- Kizilay meydani

func _build_square() -> void:
	var w: Node3D = m.world
	var C := SQUARE
	var h := ParkMap.terrain_height(C)
	print("KIZILAY zemin ", h, " kose ", ParkMap.terrain_height(C + Vector2(HALF, HALF)), " ", ParkMap.terrain_height(C - Vector2(HALF, HALF)))
	var root: Node3D = w._root(C)
	var stone := Kit.mat("d8d0c0", 0.85)
	var stone2 := Kit.mat("b9b09e", 0.85)
	var granite := Kit.mat("7d838a", 0.6)
	# Kaplama: araziyi izleyen, iki tonlu karo agi (4 m'lik bloklar)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 34
	var cs := HALF * 2.0 / cells
	for ix in cells:
		for iz in cells:
			var col := Color("dcd4c4") if (ix / 2 + iz / 2) % 2 == 0 else Color("c4bba8")
			var p00 := Vector2(-HALF + ix * cs, -HALF + iz * cs)
			var q: Array = []
			for o in [Vector2(0, 0), Vector2(cs, 0), Vector2(cs, cs), Vector2(0, cs)]:
				var pp: Vector2 = p00 + o
				q.append(Vector3(pp.x, ParkMap.terrain_height(C + pp) - h + 0.04, pp.y))
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.add_vertex(q[idx])
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.roughness = 0.85
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = pm
	root.add_child(mi)
	# Cesme: havuz, su, orta sutun, fiskiyeler
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.25, 0.55, 0.75, 0.75)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.05
	Kit.cyl(root, 5.4, 5.6, 0.75, Vector3(0, 0.4, 0), granite, 28)
	Kit.cyl(root, 4.8, 4.8, 0.05, Vector3(0, 0.72, 0), water, 28)
	Kit.cyl(root, 0.5, 0.75, 2.2, Vector3(0, 1.6, 0), granite, 12)
	Kit.cyl(root, 1.5, 0.5, 0.3, Vector3(0, 2.6, 0), granite, 14)
	var jet := Kit.mat("e8f6ff", 0.2)
	jet.emission_enabled = true
	jet.emission = Color("bfe6ff")
	jet.emission_energy_multiplier = 0.5
	for i in 8:
		var a := i * TAU / 8.0
		var jn := Kit.cyl(root, 0.04, 0.11, 2.0, Vector3(cos(a) * 2.6, 1.6, sin(a) * 2.6), jet, 6)
		_fountain_jets.append(jn)
	var jc := Kit.cyl(root, 0.06, 0.16, 2.8, Vector3(0, 3.9, 0), jet, 6)
	_fountain_jets.append(jc)
	w._add_circle(Vector3(C.x, C.y, 5.7))
	# Aniti: Ozgurluk Aniti (hayali): basamakli kaide, egimli iki levha ve halka
	var mp := C + Vector2(0, -23)
	var mr: Node3D = w._root(mp)
	Kit.box(mr, Vector3(7.0, 0.5, 7.0), Vector3(0, 0.3, 0), granite)
	Kit.box(mr, Vector3(5.0, 0.6, 5.0), Vector3(0, 0.85, 0), stone2)
	Kit.box(mr, Vector3(2.4, 4.0, 2.4), Vector3(0, 3.1, 0), granite)
	var bronze := Kit.mat("8a6a3c", 0.35)
	bronze.metallic = 0.7
	Kit.box(mr, Vector3(0.7, 5.0, 0.7), Vector3(-0.7, 7.5, 0), bronze, Vector3(0, 0, 0.18))
	Kit.box(mr, Vector3(0.7, 5.0, 0.7), Vector3(0.7, 7.5, 0), bronze, Vector3(0, 0, -0.18))
	Kit.torus(mr, 1.0, 1.25, Vector3(0, 10.4, 0), bronze, Vector3(PI / 2, 0, 0))
	var nm: Label3D = w._text(mr, "ÖZGÜRLÜK ANITI", Vector3(0, 3.2, 1.23), Color("f1e8d0"), 0.24)
	nm.double_sided = true
	w._add_circle(Vector3(mp.x, mp.y, 3.6))
	# Agaclar, banklar, lambalar
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var trunk := Kit.mat("5a4630", 0.9)
	var leaf := Kit.mat("3f7a3a", 0.9)
	for i in 14:
		var a := i * TAU / 14.0 + 0.2
		var rad := 25.0
		var tp := C + Vector2.from_angle(a) * rad
		if absf(tp.x - C.x) > HALF - 3.0 or absf(tp.y - C.y) > HALF - 3.0:
			continue
		var tr: Node3D = w._root(tp)
		Kit.cyl(tr, 0.18, 0.26, 3.0, Vector3(0, 1.5, 0), trunk, 6)
		Kit.ball(tr, 2.3, Vector3(0, 4.4, 0), leaf, Vector3(1, 0.85, 1))
		w._add_circle(Vector3(tp.x, tp.y, 0.3))
	var wood := Kit.mat("9a6b43", 0.7)
	for i in 10:
		var a := i * TAU / 10.0 + 0.3
		var bp := C + Vector2.from_angle(a) * 13.5
		var br: Node3D = w._root(bp, -a + PI / 2.0)
		Kit.box(br, Vector3(1.8, 0.08, 0.5), Vector3(0, 0.5, 0), wood)
		Kit.box(br, Vector3(1.8, 0.5, 0.06), Vector3(0, 0.8, -0.22), wood)
		Kit.box(br, Vector3(0.08, 0.5, 0.45), Vector3(-0.8, 0.25, 0), granite)
		Kit.box(br, Vector3(0.08, 0.5, 0.45), Vector3(0.8, 0.25, 0), granite)
		w._add_circle(Vector3(bp.x, bp.y, 0.6))
	for i in 8:
		var a := i * TAU / 8.0 + 0.4
		var lp := C + Vector2.from_angle(a) * 19.0
		var lr: Node3D = w._root(lp)
		Kit.cyl(lr, 0.07, 0.1, 4.6, Vector3(0, 2.3, 0), Kit.mat("2c3338", 0.5), 6)
		Kit.ball(lr, 0.3, Vector3(0, 4.8, 0), Kit.glow("ffe9b0", 1.2))
		w._add_circle(Vector3(lp.x, lp.y, 0.15))
	# Cevre binalari
	_building(C + Vector2(0, -HALF - 4.0), Vector2(26, 5), Vector2(0, 1), 26.0, "d4ccbd", "KIZILAY PALAS", [])
	_building(C + Vector2(HALF + 4.0, 0), Vector2(5, 20), Vector2(-1, 0), 12.0, "c7a98a", "ÇARŞI",
		[["Kitapçı", "7a3b8f"], ["Börekçi", "c8452f"], ["Çiçekçi", "d9488f"], ["Çay Evi", "2f7a4f"]])
	_building(C + Vector2(-HALF - 4.0, 0), Vector2(5, 20), Vector2(1, 0), 14.0, "b9c2c9", "GÜVEN PASAJI",
		[["Saatçi", "1f4f8a"], ["Dönerci", "b8401a"], ["Tatlıcı", "e0a020"]])
	# Metro girisi
	var gp := C + Vector2(-27, 24)
	var toward := Vector2(0, -1)
	w._metro_entrance(gp, toward, "Kızılay", "M4", "K1")
	w.metro_gates.append({"name": "Kızılay", "line": "M4", "ref": "K1", "pos": gp, "toward": toward})
	# Kalabalik
	var tints := ["c94f4f", "3f6fb5", "4f8f5a", "e0b84a", "7a5ea8", "f2f2f2", "2f3a4a", "d98a4f", "6fb1c9", "9a9a9a"]
	for i in 26:
		var n := Npc.new()
		var v := PersonModel.new()
		v.kind = "kadin" if i % 2 == 0 else "erkek"
		v.tint = Color(tints[i % tints.size()])
		n.visual = v
		n.add_child(v)
		n.world = w
		n.walk_speed = rng.randf_range(0.9, 1.5)
		n.roam_center = C + Vector2(rng.randf_range(-26, 26), rng.randf_range(-26, 26))
		n.roam_radius = rng.randf_range(4.0, 12.0) if i % 4 != 0 else 1.5
		n.short_pause = i % 3 == 0
		m.add_child(n)
		m._npc_people.append(n)


## Duz cepheli bina: face = meydana bakan yon. shops = [[ad, tente rengi]]
func _building(c: Vector2, half: Vector2, face: Vector2, height: float, hex: String, sign_text: String, shops: Array) -> void:
	var w: Node3D = m.world
	var r: Node3D = w._root(c, atan2(face.x, face.y))
	var along := half.x if absf(face.y) > 0.5 else half.y      # cephe uzunlugu / 2
	var depth := half.y if absf(face.y) > 0.5 else half.x
	Kit.box(r, Vector3(along * 2, height + 3.0, depth * 2), Vector3(0, height * 0.5 - 1.5, 0), Kit.mat(hex, 0.85))
	Kit.box(r, Vector3(along * 2 + 0.6, 0.5, depth * 2 + 0.6), Vector3(0, height + 0.25, 0), Kit.mat("6b6f75", 0.7))
	var glass := Kit.mat("2d4a63", 0.2)
	glass.metallic = 0.4
	var lit := Kit.glow("ffdc8a", 0.5)
	var floors := int((height - 4.0) / 3.4)
	for f in floors:
		var y := 4.6 + f * 3.4
		Kit.box(r, Vector3(along * 2 - 1.5, 1.5, 0.08), Vector3(0, y, depth + 0.03), glass if f % 2 == 0 else lit)
	var sg: Label3D = w._text(r, sign_text, Vector3(0, height - 1.4, depth + 0.1), Color("f4f0e6"), 0.9)
	sg.double_sided = true
	if shops.is_empty():
		Kit.box(r, Vector3(along * 2 - 2, 3.0, 0.1), Vector3(0, 1.6, depth + 0.04), Kit.mat("22282c", 0.4))
		var l: Label3D = w._text(r, "Giriş · Lobi", Vector3(0, 3.4, depth + 0.12), Color("ffe9b0"), 0.35)
		l.double_sided = true
	else:
		var sw := along * 2.0 / shops.size()
		for i in shops.size():
			var x := -along + sw * (i + 0.5)
			Kit.box(r, Vector3(sw - 0.5, 2.6, 0.08), Vector3(x, 1.5, depth + 0.04), Kit.mat("20262a", 0.35))
			Kit.box(r, Vector3(sw - 0.3, 0.12, 1.4), Vector3(x, 3.1, depth + 0.7), Kit.mat(shops[i][1], 0.7), Vector3(0.25, 0, 0))
			var t: Label3D = w._text(r, shops[i][0], Vector3(x, 3.55, depth + 0.1), Color.WHITE, 0.36)
			t.double_sided = true
	var cc: Vector2 = c
	w._block(cc, half)


# ---------------------------------------------------------------- test

func debug(arg: String) -> void:
	match arg:
		"bikerent":
			if stations.is_empty():
				print("TP istasyon yok")
				return
			var st: Dictionary = stations[0]
			var d := Vector2(sin(st["yaw"]), cos(st["yaw"]))
			m._place_owner(st["pos"] + d * 3.2)
			m.owner_node.rotation.y = atan2(-d.x, -d.y) + PI
			print("TP istasyon sayisi ", stations.size(), " ilk ", st["pos"])
		"taxirank":
			if rank.is_empty():
				print("TP durak yok")
				return
			var p: Vector2 = rank["pos"] + rank["dir"] * 8.0 + rank["side"] * 8.0
			m._place_owner(p)
			var f: Vector2 = (rank["pos"] + rank["dir"] * 8.0 - p).normalized()
			m.owner_node.rotation.y = atan2(-f.x, -f.y)
			print("TP taksi duragi ", rank["pos"])
		"jam":
			jam_force = true
			_clock_t = 0.0
			_update_jam(0.0)
			if not jam.is_empty():
				var c: Vector2 = jam["center"]
				var n := ParkMap.nearest_node(c)
				var q: Vector2 = ParkMap.nodes[jam["nodes"][0]]
				var nx: Vector2 = ParkMap.nodes[jam["nodes"][1]]
				var d := (nx - q).normalized()
				m._place_owner(q + d * 4.0 + Vector2(-d.y, d.x) * 5.0)
				m.owner_node.rotation.y = atan2(-d.x, -d.y)
				print("TP trafik sikisikligi ", q, " araba ", jam["extra"].size())
