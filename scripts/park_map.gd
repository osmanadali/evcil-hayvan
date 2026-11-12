extends RefCounted
## Oyun haritasi: Ankara, Kecioren merkezi (Gokcek Parki cevresi).
## Veri OpenStreetMap'ten tools/osm_build.py ile uretilir (assets/city.json).
## Koordinatlar metre; Vector2(x, z). Kuzey = -z, kamera guneyden kuzeye bakar.

const WATER_LIFT := 0.07      # su yuzeyi zeminin bu kadar ustunde
const SPLAT_CENTER := Vector2.ZERO

static var loaded := false
static var BOUNDS_MIN := Vector2(-430, -360)
static var BOUNDS_MAX := Vector2(430, 360)
static var SPLAT_EXTENT := 1080.0
static var data := {}
static var nodes := PackedVector2Array()
static var links: Array = []            # dugum -> komsu dugumler
static var water: Array = []            # PackedVector2Array listesi
static var water_boxes: Array = []      # Rect2 (genisletilmis)
static var spots := {}                  # ad -> Vector2
static var spot_half := {}              # ad -> Vector2
static var heights := PackedFloat32Array()   # arazi yuksekligi izgarasi (metre, harita merkezine gore)
static var height_n := 0
static var height_extent := 1.0


static func load_data() -> void:
	if loaded:
		return
	loaded = true
	data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/city.json"))
	var half := Vector2(data["half"][0], data["half"][1])
	BOUNDS_MIN = -half
	BOUNDS_MAX = half
	SPLAT_EXTENT = data["extent"]
	for n in data["nodes"]:
		nodes.append(Vector2(n[0], n[1]))
		links.append([])
	for group in [data["roads"], data["paths"]]:
		for w in group:
			var ids: Array = w["n"]
			for i in ids.size() - 1:
				var a := int(ids[i])
				var b := int(ids[i + 1])
				links[a].append(b)
				links[b].append(a)
	for w in data["water"]:
		var poly := to_poly(w["p"])
		water.append(poly)
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		water_boxes.append(box.grow(6.0))
	# Arazi yuksekligi: assets/height.png (16 bit, R = ust bayt, G = alt bayt)
	var hd: Dictionary = data["height"]
	var img: Image = (load("res://assets/height.png") as Texture2D).get_image()
	height_n = int(hd["n"])
	height_extent = hd["extent"]
	heights.resize(height_n * height_n)
	for j in height_n:
		for i in height_n:
			var c := img.get_pixel(i, j)
			heights[j * height_n + i] = float(hd["min"]) + (c.r8 * 256.0 + c.g8) / 65535.0 * float(hd["range"])
	for k in data["spots"]:
		var s: Dictionary = data["spots"][k]
		spots[k] = Vector2(s["pos"][0], s["pos"][1])
		spot_half[k] = Vector2(s["half"][0], s["half"][1]) if s.has("half") else Vector2(3, 3)


static func to_poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p[0], p[1]))
	return out


static func spot(name: String) -> Vector2:
	return spots[name]


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func rect_sd(p: Vector2, mn: Vector2, mx: Vector2) -> float:
	var q := (p - (mn + mx) * 0.5).abs() - (mx - mn) * 0.5
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


static func poly_sd(p: Vector2, poly: PackedVector2Array) -> float:
	var d := 1e9
	for i in poly.size():
		d = minf(d, seg_dist(p, poly[i], poly[(i + 1) % poly.size()]))
	return -d if Geometry2D.is_point_in_polygon(p, poly) else d


## Suya isaretli mesafe (suyun icinde negatif); uzaktaysa 99.
static func water_sd(p: Vector2) -> float:
	var d := 99.0
	for i in water.size():
		if (water_boxes[i] as Rect2).has_point(p):
			d = minf(d, poly_sd(p, water[i]))
	return d


static func deck_y(_p: Vector2) -> float:
	return -1000.0


static func water_blocked(p: Vector2) -> bool:
	return water_sd(p) < 0.35


static func inside_bounds(p: Vector2, margin := 0.0) -> bool:
	return rect_sd(p, BOUNDS_MIN, BOUNDS_MAX) < -margin


static func clamp_bounds(p: Vector2) -> Vector2:
	return p.clamp(BOUNDS_MIN + Vector2(2, 2), BOUNDS_MAX - Vector2(2, 2))


## Gercek arazi yuksekligi (SRTM verisinden, harita merkezine gore metre).
static func terrain_height(p: Vector2) -> float:
	var f := (p / height_extent + Vector2(0.5, 0.5)) * height_n - Vector2(0.5, 0.5)
	var x := clampi(int(f.x), 0, height_n - 2)
	var y := clampi(int(f.y), 0, height_n - 2)
	var tx := clampf(f.x - x, 0.0, 1.0)
	var ty := clampf(f.y - y, 0.0, 1.0)
	var i := y * height_n + x
	return lerpf(lerpf(heights[i], heights[i + 1], tx), lerpf(heights[i + height_n], heights[i + height_n + 1], tx), ty)


static func walk_height(p: Vector2) -> float:
	return terrain_height(p)


static func nearest_node(p: Vector2, need_links := true) -> int:
	var best := 0
	var best_d := 1e9
	for i in nodes.size():
		var d := nodes[i].distance_squared_to(p)
		if d < best_d and inside_bounds(nodes[i], -20.0) and (not need_links or links[i].size() > 0):
			best_d = d
			best = i
	return best


## Sokaklari ve park yollarini izleyen en kisa rota.
static func find_route(from: Vector2, to: Vector2) -> Array[Vector2]:
	var start := nearest_node(from)
	var goal := nearest_node(to)
	var n := nodes.size()
	var dist := PackedFloat32Array()
	var back := PackedInt32Array()
	var done := PackedByteArray()
	dist.resize(n)
	back.resize(n)
	done.resize(n)
	dist.fill(1e9)
	back.fill(-1)
	dist[start] = 0.0
	var frontier: Array[int] = [start]
	while not frontier.is_empty():
		var at := 0
		for i in frontier.size():
			if dist[frontier[i]] < dist[frontier[at]]:
				at = i
		var cur := frontier[at]
		frontier.remove_at(at)
		if cur == goal:
			break
		if done[cur] == 1:
			continue
		done[cur] = 1
		for nb in links[cur]:
			var nd := dist[cur] + nodes[cur].distance_to(nodes[nb])
			if nd < dist[nb]:
				dist[nb] = nd
				back[nb] = cur
				frontier.append(nb)
	var out: Array[Vector2] = [to]
	var k := goal
	while k >= 0:
		out.push_front(nodes[k])
		k = back[k]
	if out.size() > 2 and from.distance_to(out[1]) < out[0].distance_to(out[1]):
		out.remove_at(0)
	return out
