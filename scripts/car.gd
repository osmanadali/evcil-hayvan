extends Node3D
## Sokak aginda gezen arac (otomobil, taksi, dolmus, kamyonet, motosiklet, bisiklet): serit agini (traffic_net.gd)
## izler. Serit ortasindan gider, koseleri yay cizerek doner, onundekini izler, kirmizida ve dur cizgisinde durur,
## isiksiz kavsakta sagdan gelene yol verir, yayaya ve oyuncuya carpmadan durur. Uzaktayken ucuz calisir.

const ParkMap = preload("res://scripts/park_map.gd")
const _World = preload("res://scripts/world.gd")
const TN = preload("res://scripts/traffic_net.gd")
const CRUISE := 7.5

var node := 0
var owner_node: Node3D
var kind := "araba"           # araba / taksi / dolmus / kamyonet / motosiklet / bisiklet
var half_len := 2.05
var half_w := 0.9
var pace := 1.0               # arac turune gore hiz katsayisi
var accel := 2.2
var managed := false          # trafik yoneticisi (traffic_flow.gd) bakiyor: harita disina cikinca o tasir
var dead := false             # yonetici baska yere tasimali (haritadan cikti, yol bitti)
var far := false              # oyuncudan uzak: ucuz simulasyon
var stuck_t := 0.0            # baska bir arac / yaya yuzunden kipirdayamadigi sure
var _prev := -1
var _next := -1
var _after := -1              # _queued'dan sonraki dugum (serit secimi icin)
var lane := 0
var _qlane := 0
var _a := Vector2.ZERO        # duz parcanin basi
var _b := Vector2.ZERO        # duz parcanin sonu = donus yayinin basi
var _c := Vector2.ZERO        # yayin denetim noktasi
var _d := Vector2.ZERO        # yayin sonu = sonraki yolun serit basi
var _dir := Vector2(0, -1)
var _dir2 := Vector2(0, -1)
var _len := 1.0
var _clen := 0.0
var _ce := 0.0                # duz parcanin sonundan dugume uzaklik
var _s := 0.0                 # parca uzerinde gidilen yol
var _t: float:                # eski kodla uyum: duz parcadaki oran
	get:
		return _s / _len
	set(v):
		_s = v * _len
var _speed := 0.0
var hold := 0.0               # > 0 iken bekler (cagrilan taksi, durakta dolmus)
static var traffic: Array = []   # tum hareketli araclar (araba, otobus, oyuncunun araci): carpismamak icin
static var peds: Array = []      # yayalar (traffic_flow.gd doldurur)
static var player: Node3D        # oyuncu (yaya iken)
static var stops: Array = []     # durak konumlari (Vector2): dolmus burada durur
static var crossings: Array = [] # yaya gecitleri (Vector2)
static var honk_cb := Callable() # korna calan islev (arac)
var cruise := CRUISE
var rider: Node3D             # bisikletli / motosikletli: surucu (PersonModel); donerken kolla isaret verir
var grip := Vector3(0.3, 1.02, -0.36)
var turn_sign := 0            # -1 sola, +1 saga donecek (sinyal)
var _queued := -1             # bir sonraki kavsakta secilen yol
var _blinkers: Array = []     # [MeshInstance3D, taraf]
var _blink_t := 0.0
var _pos := Vector2.INF       # gercek konum (INF: bir sonraki karede yerine oturur)
var obey_lights := true       # trafik isiklarina uyar (polis kovalamada uymaz)
static var lights := {}       # isikli kavsak dugumu -> {axis: Vector2, off: float, r: float, ped: bool} (traffic_law.gd doldurur)
static var light_clock := 0.0
static var lamps_on := false   # aksam / gece / yagmur: trafik araclarinin far ve stop camlari isikli (isik kaynagi yok)
var _lamps: Array = []
var _sense_t := 0.0
var _gap := 1e9               # on tampondan engele uzaklik (yol boyunca)
var _lead_sp := 0.0           # engelin benim yonumdeki hizi
var _lead_type := 0           # 1 arac, 2 yaya, 3 oyuncu, 4 bisiklet / motosiklet
var _held := -1               # benim icin tutulan kavsak
var _nudge := 0.0             # sola kayma (bisikletliyi gecerken)
var _nudge_t := 0.0
var _stop_s := -1.0           # dolmus: durulacak yer (parca uzerinde)
var _dwell_cd := 0.0
var _honk_cd := 3.0
var _ghost_t := 0.0           # cok uzun takilinca: kisa sure araclari yok say (kurtulma)
var _acc_dt := 0.0
var _frame := 0

const CYCLE := 31.0           # isik dongusu (sn): A yesil 11, sari 3, hepsi kirmizi 1.5, B yesil 11, sari 3, hepsi kirmizi 1.5

# Ortak engel listesi (birkac karede bir yenilenir): daire merkezi, yaricap, hiz vektoru, sahip, tur
static var _ox := PackedVector2Array()
static var _or := PackedFloat32Array()
static var _ov := PackedVector2Array()
static var _oid := PackedInt64Array()
static var _ot := PackedByteArray()
static var _obs_frame := -10


## Isik durumu: 0 yesil, 1 sari, 2 kirmizi, 3 hepsi kirmizi (gecis); isik yoksa -1. dir: kavsaga girerken gidis yonu.
static func light_at(k: int, dir: Vector2) -> int:
	var j: Dictionary = lights.get(k, {})
	if j.is_empty():
		return -1
	var t := fmod(light_clock + float(j["off"]), CYCLE)
	if j["ped"]:
		# Yaya gecidi isigi: arabalara 20 sn yesil, 3 sn sari, 8 sn kirmizi
		return 0 if t < 20.0 else (1 if t < 23.0 else 2)
	var ax: Vector2 = j["axis"]
	var main := absf(dir.dot(ax)) > 0.6
	if not main:
		t = fmod(t + 15.5, CYCLE)
	if t < 11.0:
		return 0
	if t < 14.0:
		return 1
	if t < 15.5 or t >= 29.5:
		return 3
	return 2


## Aracin yari boyu ve yari eni (m).
static func extent_of(o: Object) -> Vector2:
	if "half_len" in o:
		return Vector2(o.half_len, o.half_w)
	if o.get("line") != null:
		return Vector2(6.0, 1.3)
	if o.has_meta("kind") and str(o.get_meta("kind")) != "araba":
		return Vector2(0.9, 0.35)
	return Vector2(2.05, 0.9)


static func speed_of(o: Object) -> float:
	if "half_len" in o:
		return o._speed if o.is_processing() else 0.0
	if o.get("line") != null:
		return float(o.speed)
	return 0.0


static func _obstacles() -> void:
	var f := Engine.get_process_frames()
	if f - _obs_frame < 3:
		return
	_obs_frame = f
	_ox.clear()
	_or.clear()
	_ov.clear()
	_oid.clear()
	_ot.clear()
	for o in traffic:
		if not is_instance_valid(o) or not o.is_inside_tree() or not o.is_visible_in_tree():
			continue
		var p := Vector2(o.global_position.x, o.global_position.z)
		var yaw: float = o.global_rotation.y
		var fw := Vector2(-sin(yaw), -cos(yaw))
		var e := extent_of(o)
		var v := fw * speed_of(o)
		var id: int = o.get_instance_id()
		var tp := 4 if e.y < 0.5 else 1
		var span := maxf(e.x - e.y, 0.0)
		var n := 1 if span < 0.3 else 1 + int(ceil(2.0 * span / (1.5 * e.y)))
		for i in n:
			var along := 0.0 if n == 1 else lerpf(-span, span, float(i) / float(n - 1))
			_ox.append(p + fw * along)
			_or.append(e.y)
			_ov.append(v)
			_oid.append(id)
			_ot.append(tp)
	for o in peds:
		if not is_instance_valid(o) or not o.is_inside_tree() or not o.is_visible_in_tree():
			continue
		var p := Vector2(o.global_position.x, o.global_position.z)
		var r := 0.9
		for c: Vector2 in crossings:
			if c.distance_squared_to(p) < 49.0:
				r = 1.9           # yaya gecidinde: yola adim atacak yayaya da yol ver
				break
		_ox.append(p)
		_or.append(r)
		_ov.append(Vector2.ZERO)
		_oid.append(o.get_instance_id())
		_ot.append(2)
	if is_instance_valid(player) and player.is_inside_tree() and player.is_visible_in_tree():
		_ox.append(Vector2(player.global_position.x, player.global_position.z))
		_or.append(1.5)
		_ov.append(Vector2.ZERO)
		_oid.append(player.get_instance_id())
		_ot.append(3)


func _ready() -> void:
	_sense_t = randf() * 0.15
	_frame = randi() % 3
	if _next < 0:
		_pick()
		_s = randf() * _len


func set_kind(k: String) -> void:
	kind = k
	match k:
		"dolmus":
			half_len = 2.7
			half_w = 1.0
			pace = 0.92
			accel = 1.7
		"kamyonet":
			half_len = 2.6
			half_w = 0.98
			pace = 0.9
			accel = 1.6
		"taksi":
			pace = 1.05
		"motosiklet":
			half_len = 1.0
			half_w = 0.4
			pace = 1.12
			accel = 3.0
		"bisiklet":
			half_len = 0.9
			half_w = 0.35
			accel = 1.2


## Serit ortasinin yol eksenine uzakligi (saga +).
func _off(a: int, b: int, l: int) -> float:
	var o := TN.offset(a, b, l)
	if kind == "bisiklet":
		o += clampf(float(TN.lane_w.get(TN.key(a, b), 2.6)) * 0.5 - 0.35, 0.0, 1.0)
	return o


## Dugumde kose payi: kavsakta dur cizgisine kadar, virajda birkac metre.
func _cut(k: int) -> float:
	if TN.jr.has(k):
		return float(TN.jr[k])
	return 2.5


## Telefonla cagrildi: verilen yol dugumunden baslayip bekle.
func summon(k: int, wait: float) -> void:
	node = k
	_prev = -1
	_queued = -1
	_pos = Vector2.INF
	_pick()
	_s = 0.0
	_speed = 0.0
	hold = wait
	dead = false
	stuck_t = 0.0


## a'dan b'ye gelen arac b'den sonra nereye gider (-1: yol yok).
func _choose(a: int, b: int) -> int:
	if b < 0:
		return -1
	var opts := TN.options(a, b)
	if not opts.is_empty():
		return opts[randi() % opts.size()]
	if a >= 0 and ParkMap.road_next[b].has(a):
		return a          # cikmaz: U donusu
	return -1


func _lane_for(a: int, b: int, c: int) -> int:
	var n := TN.lane_count(a, b)
	if n <= 1:
		return 0
	if kind == "bisiklet" or kind == "motosiklet" or kind == "dolmus":
		return n - 1
	var tk := TN.turn_kind(a, b, c) if TN.jr.has(b) else 0
	if tk < 0:
		return 0
	if tk > 0:
		return n - 1
	return clampi(lane, 0, n - 1) if randf() < 0.8 else randi() % n


## Bulundugu dugumden (node) yeniden yola koyulur. _queued verilmisse ilk hedef odur.
func _pick() -> void:
	TN.ensure()
	_release()
	var first := -1
	if _queued >= 0 and ParkMap.road_next[node].has(_queued) and _queued != _prev:
		first = _queued
	_queued = -1
	if first < 0:
		first = _choose(_prev, node)
	if first < 0 and not ParkMap.road_next[node].is_empty():
		first = ParkMap.road_next[node][randi() % ParkMap.road_next[node].size()]
	if first < 0:
		# Hic yol yok: baska bir yerden yeniden basla
		dead = true
		_pos = Vector2.INF
		for i in 40:
			var k := randi() % ParkMap.nodes.size()
			if ParkMap.road_next[k].size() > 0 and ParkMap.inside_bounds(ParkMap.nodes[k], 30.0):
				node = k
				_prev = -1
				break
		first = ParkMap.road_next[node][randi() % ParkMap.road_next[node].size()]
	_next = first
	_queued = _choose(node, _next)
	_after = _choose(_next, _queued)
	lane = randi() % TN.lane_count(node, _next)
	lane = _lane_for(node, _next, _queued)
	_qlane = _lane_for(_next, _queued, _after) if _queued >= 0 else 0
	var pa := ParkMap.nodes[node]
	var ln := pa.distance_to(ParkMap.nodes[_next])
	var dir := (ParkMap.nodes[_next] - pa) / maxf(ln, 0.01)
	_a = pa + dir * minf(_cut(node), ln * 0.45) + Vector2(-dir.y, dir.x) * _off(node, _next, lane)
	_build()
	_s = 0.0
	_stop_s = -1.0


## Duz parca (_a -> _b) ve ardindan sonraki yola donus yayi (_b -> _d).
func _build() -> void:
	var pa := ParkMap.nodes[node]
	var pb := ParkMap.nodes[_next]
	var seg := pb - pa
	var ln := maxf(seg.length(), 0.01)
	var dir := seg / ln
	_ce = minf(_cut(_next), ln * 0.45)
	_b = pb - dir * _ce + Vector2(-dir.y, dir.x) * _off(node, _next, lane)
	if (_b - _a).dot(dir) < 0.3:
		_b = _a + dir * 0.3
	_len = _a.distance_to(_b)
	_dir = (_b - _a) / _len
	if _queued < 0:
		_c = _b
		_d = _b
		_clen = 0.0
		_dir2 = _dir
		return
	var pc := ParkMap.nodes[_queued]
	var seg2 := pc - pb
	var ln2 := maxf(seg2.length(), 0.01)
	var d2 := seg2 / ln2
	_dir2 = d2
	_d = pb + d2 * minf(_cut(_next), ln2 * 0.45) + Vector2(-d2.y, d2.x) * _off(_next, _queued, _qlane)
	var chord := _b.distance_to(_d)
	var mid := (_b + _d) * 0.5
	if _queued == node:
		_c = mid + _dir * (chord * 0.9 + 2.0)          # U donusu
	else:
		var cr := _dir.cross(d2)
		_c = mid
		if absf(cr) > 0.12:
			var t := (_d - _b).cross(d2) / cr
			var u := (_d - _b).cross(_dir) / cr
			if t > 0.05 and u < -0.05 and t < chord * 2.5:
				_c = _b + _dir * t
				_d = _c + (_d - _c) * (0.5 if cr > 0.0 else 0.65)
				chord = _b.distance_to(_d)
	_clen = maxf((chord + _b.distance_to(_c) + _c.distance_to(_d)) * 0.5, 0.01)


func _point(s: float) -> Vector2:
	var p: Vector2
	if s <= _len:
		p = _a + _dir * s
	elif s < _len + _clen:
		var u := (s - _len) / _clen
		p = _b.lerp(_c, u).lerp(_c.lerp(_d, u), u)
	else:
		p = _d + _dir2 * (s - _len - _clen)
	if _nudge > 0.01:
		var t := _tangent(s)
		p -= Vector2(-t.y, t.x) * _nudge
	return p


func _tangent(s: float) -> Vector2:
	if s <= _len:
		return _dir
	if s < _len + _clen:
		var u := (s - _len) / _clen
		var t := (_c - _b).lerp(_d - _c, u)
		return t.normalized() if t.length_squared() > 0.0001 else _dir2
	return _dir2


func _release() -> void:
	if _held >= 0:
		TN.release(self, _held)
		_held = -1


func _advance() -> void:
	_s -= _len + _clen
	_prev = node
	node = _next
	_next = _queued
	lane = _qlane
	_stop_s = -1.0
	var outside := not ParkMap.inside_bounds(ParkMap.nodes[node], -40.0)
	if _next < 0 or outside:
		dead = true
		if not managed or _next < 0:
			# Yonetilmeyen arac (polis vb.): geri doner; yol yoksa baska yerden baslar
			var back := _prev
			_prev = -1
			_queued = back if outside and ParkMap.road_next[node].has(back) else -1
			_pos = Vector2.INF if _queued < 0 else _pos
			_pick()
			dead = managed
			return
	_a = _d
	_queued = _after
	_after = _choose(_next, _queued)
	_qlane = _lane_for(_next, _queued, _after) if _queued >= 0 else 0
	_build()


## Yol boyunca one bak: ilk engele uzaklik ve hizi.
func _sense(look: float) -> void:
	_obstacles()
	_gap = 1e9
	_lead_sp = 0.0
	_lead_type = 0
	var me := _pos if _pos != Vector2.INF else _point(_s)
	var my_id := get_instance_id()
	var lim := (look + 4.0) * (look + 4.0)
	var cand := PackedInt32Array()
	var two_wheel := kind == "bisiklet" or kind == "motosiklet"
	var bike_near := false
	var beside := false           # bisikletli tam yanimda: saga geri kayma
	var oncoming := false
	var here := _tangent(_s)
	for i in _ox.size():
		if _oid[i] != my_id and _ox[i].distance_squared_to(me) < lim:
			if _ghost_t > 0.0 and (_ot[i] == 1 or _ot[i] == 4):
				continue
			cand.append(i)
			if _ot[i] == 4 and not two_wheel and _ov[i].length() < 5.6:
				# Onumde ya da yanimda ayni yone giden bisikletli: gecene kadar sola acik dur
				var rel := _ox[i] - me
				var ah := rel.dot(here)
				if ah > -(half_len + 3.0) and absf(rel.cross(here)) < 3.2 and _ov[i].dot(here) > -0.3 * _ov[i].length():
					bike_near = true
					if ah < half_len + 2.0 or (_nudge > 0.3 and ah < half_len + 4.0 + _speed * _speed / 9.0):
						beside = true      # yanimda ya da artik arkasinda duramam: gecisi tamamla
		if _oid[i] != my_id and _ot[i] == 1 and not two_wheel:
			# Karsidan gelen arac (sol onumde, bana dogru): sola acilma
			var rel2 := _ox[i] - me
			var ah2 := rel2.dot(here)
			if ah2 > -4.0 and ah2 < 38.0 and absf(rel2.cross(here)) < 5.0 and _ov[i].dot(here) < -1.0:
				oncoming = true
	if bike_near and (beside or not oncoming):
		_nudge_t = maxf(_nudge_t, 1.5)
	elif oncoming:
		_nudge_t = 0.0
	if cand.is_empty():
		return
	var sd := half_len
	while sd <= look:
		var q := _point(_s + sd - half_len) + _tangent(_s + sd - half_len) * half_len
		for i in cand:
			var tp := _ot[i]
			var rr := half_w + _or[i] + (0.15 if tp == 1 else 0.1)
			if q.distance_squared_to(_ox[i]) > rr * rr:
				continue
			var v := _ov[i]
			var along := v.dot(_tangent(_s + sd))
			if (tp == 1 or tp == 4) and v.length() > 0.5 and along < -0.5 * v.length():
				continue          # karsi seritten gelen
			_gap = sd - half_len
			_lead_sp = maxf(along, 0.0)
			_lead_type = tp
			return
		sd += 1.5


## k kavsagina (from yonunden, to yonune) girmeden once: durulacak yere uzaklik (on tampondan), yoksa 1e9.
func _gate(k: int, from: int, to: int, dn: float, dir: Vector2, straight_end: float) -> float:
	var stop := 1e9
	var line := straight_end - half_len - 1.5      # donen uzun aracin burnu icin pay
	var lit := false
	if obey_lights and lights.has(k):
		var j: Dictionary = lights[k]
		line = dn - float(j["r"]) - half_len
		if line > -1.5:
			var ls := light_at(k, dir)
			if ls >= 2 or (ls == 1 and line > _speed * _speed / 8.0):
				stop = maxf(line, 0.0)
				lit = true
				if _held == k:
					_release()        # kirmizida bekleyen kavsagi tutmasin
	if not lit and TN.jr.has(k) and line > -1.0 and line < 40.0:
		var ok := TN.request(self, k, from, to, maxf(line, 0.0), _speed)
		if ok and _lead_type == 1 and _lead_sp < 1.0 and _gap > line + 1.0 and _gap < line + _ce * 2.0 + _clen + half_len * 2.0 + 2.5:
			# Cikis dolu: kavsagi kilitleme, cizgide bekle
			ok = false
			TN.forget(self, k)
		if ok:
			_held = k
		else:
			stop = minf(stop, maxf(line, 0.0))
	return stop


func _process(dt: float) -> void:
	if far:
		# Uzakta: uc karede bir, sade
		_acc_dt += dt
		_frame += 1
		if _frame % 3 != 0:
			return
		dt = _acc_dt
		_acc_dt = 0.0
	var want := cruise * pace * (1.0 if kind == "bisiklet" else TN.speed_factor(node, _next))
	if hold > 0.0:
		hold -= dt
		want = 0.0
	_dwell_cd -= dt
	_honk_cd -= dt
	if _ghost_t > 0.0:
		_ghost_t -= dt
		want = minf(want, 2.5)
	if _nudge_t > 0.0:
		_nudge_t -= dt
	_nudge = move_toward(_nudge, 0.55 if _nudge_t > 0.0 else 0.0, dt * minf(_speed * 0.2, 1.0))
	var straight := _s < _len
	var to_end := _len - _s
	var dn := to_end + _ce
	# Donus: yaya girmeden yavasla
	var ang := 0.0
	if _clen > 0.5:
		ang = PI if _queued == node else _dir.angle_to(_dir2)
		if absf(ang) > 0.3:
			var vturn := lerpf(6.5, 2.6, clampf((absf(ang) - 0.3) / 1.2, 0.0, 1.0))
			want = minf(want, sqrt(vturn * vturn + 3.6 * to_end) if straight else vturn)
	if straight and dn < 30.0 and absf(ang) > 0.45:
		turn_sign = 1 if ang > 0.0 else -1
	elif straight and _s > 5.0 and _stop_s < 0.0 and hold <= 0.0:
		turn_sign = 0
	# Onundeki arac / yaya
	_sense_t -= dt
	if _sense_t <= 0.0:
		_sense_t = 0.36 if far else 0.12
		var look := half_len + 5.0 + _speed * 2.2
		if straight and TN.jr.has(_next) and dn < 26.0:
			look = maxf(look, dn + _ce + _clen + half_len * 3.0 + 4.0)
		_sense(minf(look, 44.0))
		if kind == "dolmus" and _dwell_cd <= 0.0 and _stop_s < 0.0 and straight and hold <= 0.0:
			_find_stop()
	var obstacle := false
	var hard := 0.0               # cizgide durabilmek icin gereken fren
	if _gap < 1e8:
		var g0 := 2.0 if _lead_type == 1 or _lead_type == 4 else 2.6
		var room := _gap - g0
		var safe := sqrt(maxf(0.0, _lead_sp * _lead_sp + 5.0 * room)) if room > 0.0 else 0.0
		if room > 0.0 and _lead_sp > 0.5:
			safe = minf(safe, _lead_sp + room * 0.6)      # yaklasirken hizini ondekine uydur
		if safe < want:
			want = safe
			obstacle = safe < 0.3
	# Isik ve kavsak
	if straight:
		var stop := 1e9
		if TN.jr.has(_next) or lights.has(_next):
			stop = _gate(_next, node, _queued, dn, _dir, to_end)
		elif _queued >= 0 and (TN.jr.has(_queued) or lights.has(_queued)) and dn < 22.0:
			var l2 := ParkMap.nodes[_next].distance_to(ParkMap.nodes[_queued])
			stop = _gate(_queued, _next, _after, dn + l2, _dir2, dn + l2 - minf(_cut(_queued), l2 * 0.45))
		if stop < 1e8:
			want = minf(want, sqrt(5.0 * maxf(stop - 0.5, 0.0)))
			hard = _speed * _speed / (2.0 * maxf(stop, 0.3))
	if _held >= 0 and ((_held == node and _s > half_len + 1.0) or (_held != node and _held != _next and _held != _queued)):
		_release()
	# Dolmus duragi
	if _stop_s >= 0.0:
		var sg := _stop_s - _s
		turn_sign = 1
		want = minf(want, sqrt(3.6 * maxf(sg, 0.0)))
		if sg < 0.8 and _speed < 0.5:
			hold = randf_range(4.0, 7.0)
			_dwell_cd = 30.0
			_stop_s = -1.0
	# Takilma: korna, sonra kurtulma
	if obstacle and _speed < 0.2 and hold <= 0.0:
		stuck_t += dt
		if _honk_cd <= 0.0 and ((_lead_type == 3 and stuck_t > 4.0) or stuck_t > 18.0) and honk_cb.is_valid():
			_honk_cd = randf_range(5.0, 9.0)
			honk_cb.call(self)
		if stuck_t > 45.0 and _lead_type != 3 and _lead_type != 2:
			_ghost_t = 5.0
			stuck_t = 20.0
	elif _speed > 1.0:
		stuck_t = 0.0
	var rate := accel
	if want < _speed:
		rate = 9.0 if (want < 0.3 and _gap < 3.0) else clampf(hard, 4.5, 9.0)
	_speed = move_toward(_speed, want, dt * rate)
	_s += _speed * dt
	var guard := 0
	while _s >= _len + _clen and guard < 4:
		guard += 1
		_advance()
	var p := _point(_s)
	var face := _tangent(_s)
	var snap := _pos == Vector2.INF
	_pos = p
	if far:
		position = Vector3(p.x, ParkMap.terrain_height(p), p.y)
		rotation.y = atan2(-face.x, -face.y)
		return
	_update_signals(dt)
	if get_child_count() > 0:
		_World.spin_wheels(get_child(0), _speed * dt)
	var h := ParkMap.terrain_height(p)
	var h2 := ParkMap.terrain_height(p + face * 2.0)
	position = Vector3(p.x, h, p.y)
	var yaw := atan2(-face.x, -face.y)
	rotation.y = yaw if snap else lerp_angle(rotation.y, yaw, minf(1.0, dt * 10.0))
	rotation.x = atan2(h2 - h, 2.0) if snap else lerpf(rotation.x, atan2(h2 - h, 2.0), minf(1.0, dt * 4.0))


## Dolmus: yolun sagindaki yakin duragi bul.
func _find_stop() -> void:
	var me := _pos if _pos != Vector2.INF else _point(_s)
	var right := Vector2(-_dir.y, _dir.x)
	var room := _len - _s - 2.0
	for st: Vector2 in stops:
		var rel := st - me
		if absf(rel.x) > 30.0 or absf(rel.y) > 30.0:
			continue
		var ah := rel.dot(_dir)
		var lat := rel.dot(right)
		if ah > 6.0 and ah < minf(28.0, room) and lat > 0.0 and lat < 10.0:
			_stop_s = _s + ah
			return


## Sinyal lambalari: aracin dort kosesinde turuncu; donus yonundekiler yanip soner.
static func add_blinkers(holder: Node3D) -> Array:
	# Modelin yuzey noktalari (arac uzayinda): sinyaller farlarin hizasinda govdeye oturur
	var pts := PackedVector3Array()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or String(mi.name).begins_with("wheel"):
			continue
		var xf := _rel(holder, mi)
		var a := xf * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
		for si in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 6000)
			for k in range(0, verts.size(), step):
				pts.append(xf * verts[k])
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("ffa31a")
	m.emission_enabled = true
	m.emission = Color("ff9a00")
	m.emission_energy_multiplier = 4.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var out: Array = []
	var w := box.size.x
	var hgt := box.size.y
	for front in [true, false]:
		for side in [-1, 1]:
			# Farin yaklasik yeri: yanlardan icerde, on/arka yuzeyde
			var target := Vector3(box.get_center().x + side * w * 0.36, box.position.y + hgt * (0.5 if front else 0.58),
				box.position.z if front else box.end.z)
			var best := target
			var bd := 1e9
			for q in pts:
				var d := (q - target).length_squared() + absf(q.y - target.y) * 2.0
				if d < bd:
					bd = d
					best = q
			var b := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 12
			sm.rings = 6
			b.mesh = sm
			b.scale = Vector3(0.13, 0.07, 0.04)
			b.material_override = m
			b.position = best + Vector3(0, 0, -0.01 if front else 0.01)
			b.visible = false
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(b)
			out.append([b, side])
	return out


## Far ve stop camlari: on koselerde beyaz, arka koselerde kirmizi isikli mercekler (yalniz isikli malzeme;
## isik kaynagi degil). two: iki tekerli (ortada tek far, tek stop). Donus: [on dugumler, arka dugumler, on malzeme,
## arka malzeme]. Baslangicta gizlidir.
static func add_lamps(holder: Node3D, two := false) -> Array:
	var pts := PackedVector3Array()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or String(mi.name).begins_with("wheel") or not (mi.mesh is ArrayMesh):
			continue
		var xf := _rel(holder, mi)
		var a := xf * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
		for si in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 6000)
			for k in range(0, verts.size(), step):
				pts.append(xf * verts[k])
	var mats: Array = []
	for hex in ["fff6dc", "ff2010"]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(hex)
		m.emission_enabled = true
		m.emission = Color(hex)
		m.emission_energy_multiplier = 3.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mats.append(m)
	var out: Array = [[], [], mats[0], mats[1]]
	if first:
		return out
	var w := box.size.x
	var hgt := box.size.y
	for front in [true, false]:
		for side in ([0] if two else [-1, 1]):
			var target := Vector3(box.get_center().x + side * w * 0.27,
				box.position.y + hgt * ((0.66 if front else 0.5) if two else (0.5 if front else 0.58)),
				box.position.z if front else box.end.z)
			var best := target
			var bd := 1e9
			for q in pts:
				var d := (q - target).length_squared() + absf(q.y - target.y) * 2.0
				if d < bd:
					bd = d
					best = q
			var b := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 12
			sm.rings = 6
			b.mesh = sm
			b.scale = Vector3(0.12, 0.1, 0.05) if two else Vector3(0.2, 0.09, 0.05)
			b.material_override = mats[0 if front else 1]
			b.position = best + Vector3(0, 0, -0.012 if front else 0.012)
			b.visible = false
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(b)
			out[0 if front else 1].append(b)
	return out


## Govdenin yuzey noktalari (holder uzayinda; tekerler haric). Tepe lambasi, serit, tabela gibi eklentiler
## sinir kutusuna degil bu noktalara gore yerlestirilir (kutu aynalari ve anteni de sayar; eklenti havada kalir).
static func body_points(holder: Node3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or String(mi.name).begins_with("wheel") or not (mi.mesh is ArrayMesh):
			continue
		var xf := _rel(holder, mi)
		for si in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 20000)
			for k in range(0, verts.size(), step):
				pts.append(xf * verts[k])
	return pts


## Verilen yukseklik ve boy araliginda govdenin yan yuzeyi: side (-1 sol, +1 sag) yonunde en dis x. Nokta yoksa NAN.
static func side_x(pts: PackedVector3Array, side: float, y0: float, y1: float, z0: float, z1: float) -> float:
	var best := -1e9
	for q in pts:
		if q.y >= y0 and q.y <= y1 and q.z >= z0 and q.z <= z1 and q.x * side > best:
			best = q.x * side
	return best * side if best > -1e8 else NAN


## Verilen alanda (|x - cx| <= hx, z0..z1) govdenin en ust noktasi (tavan / kaput yuksekligi). Nokta yoksa NAN.
static func top_y(pts: PackedVector3Array, cx: float, hx: float, z0: float, z1: float) -> float:
	var best := -1e9
	for q in pts:
		if absf(q.x - cx) <= hx and q.z >= z0 and q.z <= z1 and q.y > best:
			best = q.y
	return best if best > -1e8 else NAN


static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != root and cur != null:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func blink(list: Array, sign: int, t: float) -> void:
	var on := sign != 0 and fmod(t, 0.8) < 0.4
	for b in list:
		b[0].visible = on and b[1] == sign


func _update_signals(dt: float) -> void:
	_blink_t += dt
	if rider:
		rider.ride_speed = _speed
		var h := get_child(0) as Node3D
		var xf := h.global_transform
		var l := xf * Vector3(-grip.x, grip.y, grip.z)
		var r := xf * Vector3(grip.x, grip.y, grip.z)
		# El isareti: donecegi taraftaki kol omuz hizasinda yana uzanir
		if turn_sign < 0:
			l = xf * Vector3(-0.95, 1.42, 0.2)
		elif turn_sign > 0:
			r = xf * Vector3(0.95, 1.42, 0.2)
		rider.grips = [l, r]
		return
	if _blinkers.is_empty() and get_child_count() > 0:
		_blinkers = add_blinkers(get_child(0))
	blink(_blinkers, turn_sign, _blink_t)
	# Aksam / gece / yagmurda far ve stop camlari isikli (yalniz malzeme)
	if lamps_on and _lamps.is_empty() and get_child_count() > 0:
		_lamps = add_lamps(get_child(0))
	if not _lamps.is_empty() and not _lamps[0].is_empty() and (_lamps[0][0] as Node3D).visible != lamps_on:
		for b: Node3D in _lamps[0] + _lamps[1]:
			b.visible = lamps_on
