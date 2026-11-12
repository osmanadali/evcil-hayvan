extends RefCounted
## Oyun dunyasinin harita verisi ve arazi fonksiyonlari.
## Bolgeler: ev ve arka bahce, Leylak Sokagi (mahalle), Papatya Parki, carsi meydani,
## meyve bahcesi, seyir tepesi, gol ve kumsal, orman yolu.
## Koordinatlar metre; Vector2(x, z). Kuzey = -z, kamera guneyden kuzeye bakar.

const BOUNDS_MIN := Vector2(-72, -112)
const BOUNDS_MAX := Vector2(112, 100)
const SPLAT_CENTER := Vector2(20, -6)
const SPLAT_EXTENT := 236.0
const WATER_Y := -0.45

const PLAZA := Vector2(0, 0)
const PLAZA_R := 7.0
const HOUSE := Vector2(0, -36)
const YARD_MIN := Vector2(-11, -56)
const YARD_MAX := Vector2(11, -27)
const PLAY_MIN := Vector2(24.5, 2)
const PLAY_MAX := Vector2(39.5, 14)
const HILL := Vector2(6, 32)
const GARDEN := Vector2(22, -16)
const PICNIC := Vector2(-16, -20)
const KIOSK := Vector2(18, 16)
const MEADOW := Vector2(-14, 20)
const LOOKOUT := Vector2(-40, -7)
const SQUARE := Vector2(84, -16)
const SQUARE_R := 12.0
const PETSHOP := Vector2(84, -35)
const CAFE := Vector2(103, -16)
const BEACH := Vector2(-23, 66)
const BEACH_R := 11.0
const ORCHARD := Vector2(72, 60)
const CAMP := Vector2(-56, -30)
const STREET_Z := -63.0     # Leylak Sokagi (dogu-bati)
const AVENUE_X := 64.0      # Carsi Caddesi (kuzey-guney)

# Yaya yollari
const PATHS := [
	{"w": 1.8, "pts": [Vector2(0, -32.6), Vector2(0, -30), Vector2(0, -27)]},
	{"w": 2.6, "pts": [Vector2(0, -27), Vector2(0.8, -20), Vector2(-0.8, -12), Vector2(0, -6)]},
	{"w": 2.2, "pts": [Vector2(-6, 0), Vector2(-14, 1), Vector2(-21, 5), Vector2(-25, 7), Vector2(-31, 7), Vector2(-36, 5), Vector2(-39, -1), Vector2(-40, -7)]},
	{"w": 2.2, "pts": [Vector2(6, 0), Vector2(15, -1), Vector2(21, 2), Vector2(24.5, 6)]},
	{"w": 2.2, "pts": [Vector2(0, 6), Vector2(-1, 14), Vector2(2, 21), Vector2(9, 24), Vector2(13, 29), Vector2(11, 35), Vector2(7.5, 33.5)]},
	{"w": 1.7, "pts": [Vector2(4, -5), Vector2(12, -11), Vector2(18, -14.5)]},
	{"w": 1.7, "pts": [Vector2(-4, -5), Vector2(-10, -13), Vector2(-15, -19)]},
	{"w": 1.7, "pts": [Vector2(4, 5), Vector2(11, 11), Vector2(16, 14.5)]},
	# Parktan carsiya
	{"w": 2.6, "pts": [Vector2(15, -1), Vector2(26, -5), Vector2(42, -8), Vector2(58, -11), Vector2(64, -12.5), Vector2(73, -15)]},
	# Kumsala ve gol kiyisina
	{"w": 2.2, "pts": [Vector2(2, 21), Vector2(-6, 30), Vector2(-12, 44), Vector2(-17, 54), Vector2(-20, 60)]},
	{"w": 1.8, "pts": [Vector2(-20, 60), Vector2(-12.5, 72), Vector2(-15, 84), Vector2(-25, 93)]},
	# Orman yolu
	{"w": 1.6, "pts": [Vector2(-40, -7), Vector2(-48, -18), Vector2(-56, -30), Vector2(-52, -45), Vector2(-42, -55), Vector2(-40, -59.5)]},
	# Evin yanindan arka bahceye ve sokaga
	{"w": 1.4, "pts": [Vector2(0, -30), Vector2(7, -30.5), Vector2(8, -42), Vector2(0, -47), Vector2(0, -56), Vector2(0, -59.5)]},
	# Tepeden meyve bahcesine
	{"w": 2.0, "pts": [Vector2(13, 29), Vector2(26, 33), Vector2(42, 38), Vector2(58, 40), Vector2(64, 40)]},
	{"w": 1.8, "pts": [Vector2(64, 40), Vector2(80, 44), Vector2(92, 56), Vector2(88, 74), Vector2(70, 80), Vector2(54, 70), Vector2(52, 52), Vector2(58, 40)]},
]

# Asfalt yollar (merkez cizgisi); iki yaninda kaldirim var
const ROADS := [
	[Vector2(-58, STREET_Z), Vector2(-40, STREET_Z), Vector2(0, STREET_Z), Vector2(AVENUE_X, STREET_Z)],
	[Vector2(AVENUE_X, STREET_Z), Vector2(AVENUE_X, -12.5), Vector2(AVENUE_X, 40)],
]
const ROAD_HALF := 3.0
const SIDEWALK := 2.0

# Parseller: [merkez, bakis yonu (0 = guneye, PI = kuzeye)]
const LOTS := [
	[Vector2(-48, -80), 0.0], [Vector2(-28, -80), 0.0], [Vector2(-8, -80), 0.0],
	[Vector2(12, -80), 0.0], [Vector2(32, -80), 0.0], [Vector2(52, -80), 0.0],
	[Vector2(-30, -45), PI], [Vector2(30, -45), PI], [Vector2(48, -45), PI],
]
const LOT_HALF := Vector2(8.5, 11.5)

# Su: golet, dere ve gol (x, z, yaricap)
const WATER_CIRCLES := [
	Vector3(-28, -6, 7.0), Vector3(-33, -9, 5.0), Vector3(-24, -10, 4.5),
	Vector3(-48, 74, 18.0), Vector3(-37, 87, 9.0), Vector3(-62, 66, 10.0),
]
const STREAM := [Vector2(-28, -1), Vector2(-28, 14), Vector2(-33, 26), Vector2(-40, 42), Vector2(-45, 58)]
const STREAM_HALF := 1.3

# Uzerinde yurunen ahsap yapilar: [merkez, yari boyut, kemer yuksekligi, taban yuksekligi]
const DECKS := [
	[Vector2(-28, 7), Vector2(2.9, 1.2), 0.5, 0.12],     # kopru
	[Vector2(-35, 68), Vector2(7.0, 1.3), 0.0, 0.02],    # iskele
]
const BRIDGE := Vector2(-28, 7)

# Agac dikilmeyen ve zemini duzlenen acikliklar (x, z, yaricap)
const CLEARINGS := [
	Vector3(22, -16, 8.0), Vector3(-16, -20, 5.5), Vector3(18, 16, 5.5),
	Vector3(6, 32, 4.5), Vector3(-14, 20, 8.0), Vector3(-28, 7, 4.0), Vector3(-40, -7, 3.0),
	Vector3(84, -16, 26.0), Vector3(-23, 66, 12.0), Vector3(-56, -30, 5.0), Vector3(72, 60, 21.0),
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


## Yaya yoluna isaretli mesafe (yolun icinde negatif).
static func path_sd(p: Vector2) -> float:
	var d := p.distance_to(PLAZA) - PLAZA_R
	for path in PATHS:
		var w: float = path["w"]
		d = minf(d, poly_dist(p, path["pts"]) - w * 0.5)
	return d


## Asfaltin merkez cizgisine mesafe.
static func road_dist(p: Vector2) -> float:
	var d := 1e9
	for r in ROADS:
		d = minf(d, poly_dist(p, r))
	return d


## Tas doseli alanlara (kaldirim, meydanlar) isaretli mesafe.
static func paved_sd(p: Vector2) -> float:
	return minf(road_dist(p) - ROAD_HALF - SIDEWALK, p.distance_to(SQUARE) - SQUARE_R)


## Parsellere (ev bahcesi dahil) isaretli mesafe.
static func lot_sd(p: Vector2) -> float:
	var d := rect_sd(p, YARD_MIN, YARD_MAX)
	for l in LOTS:
		var c: Vector2 = l[0]
		d = minf(d, rect_sd(p, c - LOT_HALF, c + LOT_HALF))
	return d


static func water_sd(p: Vector2) -> float:
	var d := poly_dist(p, STREAM) - STREAM_HALF
	for c in WATER_CIRCLES:
		d = minf(d, p.distance_to(Vector2(c.x, c.y)) - c.z)
	return d


## Uzerinde durulan ahsap yapinin yuksekligi; yoksa -1000.
static func deck_y(p: Vector2) -> float:
	for d in DECKS:
		var c: Vector2 = d[0]
		var h: Vector2 = d[1]
		if absf(p.x - c.x) < h.x and absf(p.y - c.y) < h.y:
			var t := (p.x - c.x) / h.x
			return d[3] + d[2] * (1.0 - t * t)
	return -1000.0


static func water_blocked(p: Vector2) -> bool:
	return water_sd(p) < 0.35 and deck_y(p) < -100.0


static func inside_bounds(p: Vector2, margin := 0.0) -> bool:
	return rect_sd(p, BOUNDS_MIN, BOUNDS_MAX) < -margin


static func clamp_bounds(p: Vector2) -> Vector2:
	return p.clamp(BOUNDS_MIN + Vector2(2, 2), BOUNDS_MAX - Vector2(2, 2))


## Orman yogunlugu (0..1): kuzeybati ormani ve harita kenarlari.
static func forest(p: Vector2) -> float:
	var f := smoothstep(-34.0, -46.0, p.x) * smoothstep(-8.0, -18.0, p.y) * smoothstep(-60.0, -52.0, p.y)
	return maxf(f, smoothstep(-8.0, 0.0, rect_sd(p, BOUNDS_MIN, BOUNDS_MAX)))


static func terrain_height(p: Vector2) -> float:
	var n := 0.22 * sin(p.x * 0.11 + 1.3) * cos(p.y * 0.09 + 0.4) \
		+ 0.10 * sin(p.x * 0.27 + p.y * 0.23) + 0.05 * sin(p.x * 0.6 - p.y * 0.5)
	var flat := smoothstep(PLAZA_R, PLAZA_R + 6.0, p.distance_to(PLAZA))
	flat *= smoothstep(0.0, 5.0, lot_sd(p))
	flat *= smoothstep(0.0, 5.0, rect_sd(p, PLAY_MIN, PLAY_MAX))
	flat *= smoothstep(0.0, 5.0, road_dist(p) - ROAD_HALF - SIDEWALK)
	for c in CLEARINGS:
		flat *= smoothstep(c.z - 1.0, c.z + 4.0, p.distance_to(Vector2(c.x, c.y)))
	var h := n * flat
	# Seyir tepesi
	h += 5.0 * exp(-p.distance_squared_to(HILL) / 128.0)
	# Su yataklari
	h -= 1.5 * (1.0 - smoothstep(-1.0, 1.2, water_sd(p)))
	# Haritayi cevreleyen tepeler
	var k := rect_sd(p, BOUNDS_MIN, BOUNDS_MAX) + 1.0
	if k > 0.0:
		h += k * k * 0.04 + k * 0.3 * (0.5 + 0.5 * sin(p.x * 0.13 + p.y * 0.17))
	return h


## Uzerinde yurunen yukseklik (kopru ve iskele dahil).
static func walk_height(p: Vector2) -> float:
	return maxf(terrain_height(p), deck_y(p))


## Yollari izleyen rota: en yakin yol dugumunden hedefe en kisa yol.
static func find_route(from: Vector2, to: Vector2) -> Array[Vector2]:
	var nodes: Array[Vector2] = []
	var links: Array = []
	var lines: Array = []
	for path in PATHS:
		lines.append(path["pts"])
	for r in ROADS:
		# Kaldirimdan yuru: merkez cizgisini kuzeye/doguya kaydir
		var off: Array = []
		for pt in r:
			off.append(pt + (Vector2(0, ROAD_HALF + 1.0) if r[0].y == r[1].y else Vector2(-ROAD_HALF - 1.0, 0)))
		lines.append(off)
	for line in lines:
		var prev := -1
		for pt in line:
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
	# Birbirine yakin dugumler (kavsaklar) ve meydana acilan yol uclari baglanir
	for a in nodes.size():
		for b in a:
			var near := nodes[a].distance_to(nodes[b]) < 4.5
			var plaza := nodes[a].distance_to(PLAZA) < PLAZA_R + 0.5 and nodes[b].distance_to(PLAZA) < PLAZA_R + 0.5 \
					and seg_dist(PLAZA, nodes[a], nodes[b]) > 3.3
			if (near or plaza) and not links[a].has(b):
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
