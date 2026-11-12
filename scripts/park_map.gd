extends RefCounted
## Papatya Parki'nin harita verisi ve arazi fonksiyonlari.
## Koordinatlar metre; Vector2(x, z). Kuzey = -z, kamera guneyden kuzeye bakar.

const SPLAT_EXTENT := 128.0   # zemin boyama dokusunun kapladigi kenar uzunlugu
const WATER_Y := -0.45
const PLAY_RADIUS := 47.0     # oyuncunun cikabilecegi en uzak mesafe

const PLAZA := Vector2(0, 0)
const PLAZA_R := 7.0
const HOUSE := Vector2(0, -36)
const YARD_MIN := Vector2(-9, -43)
const YARD_MAX := Vector2(9, -27)
const PLAY_MIN := Vector2(24.5, 2)
const PLAY_MAX := Vector2(39.5, 14)
const HILL := Vector2(6, 32)
const GARDEN := Vector2(22, -16)
const PICNIC := Vector2(-16, -20)
const KIOSK := Vector2(18, 16)
const MEADOW := Vector2(-14, 20)
const LOOKOUT := Vector2(-40, -7)
const BRIDGE := Vector2(-28, 7)
const BRIDGE_LEN := 5.8
const BRIDGE_W := 2.4

const PATHS := [
	{"w": 1.8, "pts": [Vector2(0, -32.6), Vector2(0, -27)]},
	{"w": 2.6, "pts": [Vector2(0, -27), Vector2(0.8, -20), Vector2(-0.8, -12), Vector2(0, -6)]},
	{"w": 2.2, "pts": [Vector2(-6, 0), Vector2(-14, 1), Vector2(-21, 5), Vector2(-25, 7), Vector2(-31, 7), Vector2(-36, 5), Vector2(-39, -1), Vector2(-40, -7)]},
	{"w": 2.2, "pts": [Vector2(6, 0), Vector2(15, -1), Vector2(21, 2), Vector2(24.5, 6)]},
	{"w": 2.2, "pts": [Vector2(0, 6), Vector2(-1, 14), Vector2(2, 21), Vector2(9, 24), Vector2(13, 29), Vector2(11, 35), Vector2(7.5, 33.5)]},
	{"w": 1.7, "pts": [Vector2(4, -5), Vector2(12, -11), Vector2(18, -14.5)]},
	{"w": 1.7, "pts": [Vector2(-4, -5), Vector2(-10, -13), Vector2(-15, -19)]},
	{"w": 1.7, "pts": [Vector2(4, 5), Vector2(11, 11), Vector2(16, 14.5)]},
]

# Golet: ust uste binen daireler (x, z, yaricap)
const POND := [Vector3(-28, -6, 7.0), Vector3(-33, -9, 5.0), Vector3(-24, -10, 4.5)]
const STREAM := [Vector2(-28, -1), Vector2(-28, 14), Vector2(-33, 26), Vector2(-44, 38), Vector2(-62, 54)]
const STREAM_HALF := 1.3

# Agac dikilmeyen ve zemini duzlenen acikliklar (x, z, yaricap)
const CLEARINGS := [
	Vector3(22, -16, 8.0), Vector3(-16, -20, 5.5), Vector3(18, 16, 5.5),
	Vector3(6, 32, 4.5), Vector3(-14, 20, 8.0), Vector3(-28, 7, 4.0), Vector3(-40, -7, 3.0),
]


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func poly_dist(p: Vector2, pts: Array) -> float:
	var d := 1e9
	for i in pts.size() - 1:
		d = minf(d, seg_dist(p, pts[i], pts[i + 1]))
	return d


static func rect_sd(p: Vector2, mn: Vector2, mx: Vector2) -> float:
	var q := (p - (mn + mx) * 0.5).abs() - (mx - mn) * 0.5
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


## Yola olan isaretli mesafe (yolun icinde negatif).
static func path_sd(p: Vector2) -> float:
	var d := p.distance_to(PLAZA) - PLAZA_R
	for path in PATHS:
		var w: float = path["w"]
		d = minf(d, poly_dist(p, path["pts"]) - w * 0.5)
	return d


## Suya olan isaretli mesafe (suyun icinde negatif).
static func water_sd(p: Vector2) -> float:
	var d := poly_dist(p, STREAM) - STREAM_HALF
	for c in POND:
		d = minf(d, p.distance_to(Vector2(c.x, c.y)) - c.z)
	return d


static func on_bridge(p: Vector2) -> bool:
	return absf(p.x - BRIDGE.x) < BRIDGE_LEN * 0.5 and absf(p.y - BRIDGE.y) < BRIDGE_W * 0.5


static func bridge_y(p: Vector2) -> float:
	var t := clampf((p.x - BRIDGE.x) / (BRIDGE_LEN * 0.5), -1.0, 1.0)
	return 0.12 + 0.5 * (1.0 - t * t)


static func water_blocked(p: Vector2) -> bool:
	return water_sd(p) < 0.35 and not on_bridge(p)


static func terrain_height(p: Vector2) -> float:
	var n := 0.22 * sin(p.x * 0.11 + 1.3) * cos(p.y * 0.09 + 0.4) \
		+ 0.10 * sin(p.x * 0.27 + p.y * 0.23) + 0.05 * sin(p.x * 0.6 - p.y * 0.5)
	var flat := smoothstep(PLAZA_R, PLAZA_R + 6.0, p.distance_to(PLAZA))
	flat *= smoothstep(0.0, 5.0, rect_sd(p, YARD_MIN, YARD_MAX))
	flat *= smoothstep(0.0, 5.0, rect_sd(p, PLAY_MIN, PLAY_MAX))
	for c in CLEARINGS:
		flat *= smoothstep(c.z - 1.0, c.z + 4.0, p.distance_to(Vector2(c.x, c.y)))
	var h := n * flat
	# Seyir tepesi
	h += 5.0 * exp(-p.distance_squared_to(HILL) / 128.0)
	# Golet ve dere yatagi
	h -= 1.5 * (1.0 - smoothstep(-1.0, 1.2, water_sd(p)))
	# Parki cevreleyen tepeler
	var r := p.length()
	if r > 48.0:
		var k := r - 48.0
		h += k * k * 0.045 + k * 0.3 * (0.5 + 0.5 * sin(atan2(p.y, p.x) * 6.0 + 1.0))
	return h


## Uzerinde yurunen yukseklik (kopru dahil).
static func walk_height(p: Vector2) -> float:
	var h := terrain_height(p)
	if on_bridge(p):
		h = maxf(h, bridge_y(p))
	return h


## Yollari izleyen rota: en yakin yol dugumunden hedefe en kisa yol.
static func find_route(from: Vector2, to: Vector2) -> Array[Vector2]:
	var nodes: Array[Vector2] = []
	var links: Array = []
	for path in PATHS:
		var prev := -1
		for pt in path["pts"]:
			var idx := -1
			for i in nodes.size():
				if nodes[i].distance_to(pt) < 0.1:
					idx = i
			if idx < 0:
				idx = nodes.size()
				nodes.append(pt)
				links.append([])
			if prev >= 0:
				links[prev].append(idx)
				links[idx].append(prev)
			prev = idx
	# Meydana acilan yol uclari birbirine baglanir (cesmenin icinden gecmeden)
	for a in nodes.size():
		for b in a:
			if nodes[a].distance_to(PLAZA) < PLAZA_R + 0.5 and nodes[b].distance_to(PLAZA) < PLAZA_R + 0.5 \
					and seg_dist(PLAZA, nodes[a], nodes[b]) > 3.3:
				links[a].append(b)
				links[b].append(a)
	var start := 0
	var goal := 0
	for i in nodes.size():
		if nodes[i].distance_to(from) < nodes[start].distance_to(from):
			start = i
		if nodes[i].distance_to(to) < nodes[goal].distance_to(to):
			goal = i
	var dist: Array[float] = []
	var back: Array[int] = []
	var done: Array[bool] = []
	for i in nodes.size():
		dist.append(1e9)
		back.append(-1)
		done.append(false)
	dist[start] = 0.0
	while true:
		var cur := -1
		for i in nodes.size():
			if not done[i] and (cur < 0 or dist[i] < dist[cur]):
				cur = i
		if cur < 0 or cur == goal or dist[cur] >= 1e9:
			break
		done[cur] = true
		for nb in links[cur]:
			var nd: float = dist[cur] + nodes[cur].distance_to(nodes[nb])
			if nd < dist[nb]:
				dist[nb] = nd
				back[nb] = cur
	var out: Array[Vector2] = [to]
	var k := goal
	while k >= 0:
		out.push_front(nodes[k])
		k = back[k]
	if out.size() > 2 and from.distance_to(out[1]) < out[0].distance_to(out[1]):
		out.remove_at(0)
	return out
