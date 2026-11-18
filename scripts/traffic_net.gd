extends RefCounted
## Serit agi: yol verisinden (ParkMap) yonlu seritler, serit genislikleri, hiz katsayilari, kavsaklar ve
## kavsak gecis sirasi (kimin once gececegi). Araclar (car.gd) bu agi izler; trafik yoneticisi
## (traffic_flow.gd) araclari buradaki "dogma yollari"na koyar.
##
## Anahtar: a * 65536 + b (a dugumunden b dugumune gidis yonu).

const ParkMap = preload("res://scripts/park_map.gd")

const SPEED := {"primary": 1.55, "primary_link": 1.1, "secondary": 1.4, "tertiary": 1.2, "residential": 1.0,
	"unclassified": 0.95, "service": 0.6}

static var _built_for := ""
static var lanes := {}        # yon -> o yondeki serit sayisi
static var lane_w := {}       # yon -> serit genisligi (m)
static var one_way := {}      # yon -> tek yonlu yol mu
static var speed := {}        # yon -> hiz katsayisi (yol turune gore)
static var service := {}      # yon -> ara yol / otopark yolu
static var good := {}         # yon -> devam edilebilir (cikmaza girmez)
static var exits := {}        # yon -> harita disina cikar (arac orada kaybolur)
static var jr := {}           # kavsak dugumu -> dur cizgisinin dugume uzakligi (m)
static var spawn_links: Array = []    # [a, b]: araclarin dogabilecegi yonler (genis yollar daha cok tekrarlanir)
static var _hold := {}        # kavsak -> [[arac, giris, cikis, zaman]] : su an kavsagi kullananlar
static var _wait := {}        # kavsak -> {arac kimligi: [arac, giris, cikis, ilk an, son an, varis suresi]}


static func key(a: int, b: int) -> int:
	return a * 65536 + b


static func ensure() -> void:
	var sig := "%s/%d" % [ParkMap.zone, ParkMap.nodes.size()]
	if sig == _built_for or ParkMap.nodes.is_empty():
		return
	_built_for = sig
	lanes = {}
	lane_w = {}
	one_way = {}
	speed = {}
	service = {}
	good = {}
	exits = {}
	jr = {}
	spawn_links = []
	_hold = {}
	_wait = {}
	var nodes := ParkMap.nodes
	for r in ParkMap.data["roads"]:
		var ids: Array = r["n"]
		var w := float(r["w"])
		var ow: bool = r["oneway"]
		var total := maxi(1, int(r.get("lanes", 1)))
		var n := total if ow else maxi(1, total / 2)
		# Genislik yetmiyorsa serit azalt (serit en az 2.3 m)
		n = clampi(n, 1, maxi(1, int(w * 0.8 / 2.3 / (1.0 if ow else 2.0))))
		var lw := w * 0.8 / float(n if ow else n * 2)
		if not ow:
			lw = maxf(lw, 2.1)
		var sp := float(SPEED.get(String(r["k"]), 1.0))
		for i in ids.size() - 1:
			var a := int(ids[i])
			var b := int(ids[i + 1])
			for kk in ([key(a, b)] if ow else [key(a, b), key(b, a)]):
				lanes[kk] = n
				lane_w[kk] = lw
				one_way[kk] = ow
				speed[kk] = sp
				service[kk] = String(r["k"]) == "service"
	# Kavsaklar: uc ya da daha cok yol kolu olan dugumler
	for k in nodes.size():
		var nb := road_nbs(k)
		if nb.size() < 3:
			continue
		var wmax := 0.0
		for q in nb:
			wmax = maxf(wmax, ParkMap.road_width(k, q))
		jr[k] = wmax * 0.5 + 1.2
	# Cikmaza girmeyen yonler: sonunda harita disina cikan ya da devami olan yollar
	for kk in lanes:
		var b: int = kk % 65536
		var a: int = kk / 65536
		if not ParkMap.inside_bounds(nodes[a], -40.0):
			continue
		good[kk] = true
		if not ParkMap.inside_bounds(nodes[b], -40.0):
			exits[kk] = true
	var changed := true
	while changed:
		changed = false
		for kk in good.keys():
			if exits.has(kk):
				continue
			var b: int = kk % 65536
			var a: int = kk / 65536
			var ok := false
			for c in ParkMap.road_next[b]:
				if c != a and good.has(key(b, c)):
					ok = true
					break
			if not ok:
				good.erase(kk)
				changed = true
	for kk in good:
		var b: int = kk % 65536
		var a: int = kk / 65536
		if service[kk] or exits.has(kk) or not ParkMap.inside_bounds(nodes[a], 10.0) or not ParkMap.inside_bounds(nodes[b], 10.0):
			continue
		if nodes[a].distance_to(nodes[b]) < 14.0:
			continue
		for i in int(lanes[kk]) * (2 if float(speed[kk]) > 1.1 else 1):
			spawn_links.append([a, b])


## Yol komsulari (yaya yollari haric, tekrarsiz).
static func road_nbs(k: int) -> Array:
	var out: Array = []
	for nb in ParkMap.links[k]:
		if ParkMap.road_width(k, nb) > 0.0 and not nb in out:
			out.append(nb)
	return out


static func lane_count(a: int, b: int) -> int:
	return int(lanes.get(key(a, b), 1))


## Serit ortasinin yol eksenine uzakligi (saga dogru +). Serit 0 en soldaki (hizli) serittir.
static func offset(a: int, b: int, lane: int) -> float:
	var kk := key(a, b)
	if not lanes.has(kk):
		return minf(ParkMap.road_width(a, b) * 0.22, 1.6)
	var n: int = lanes[kk]
	var lw: float = lane_w[kk]
	lane = clampi(lane, 0, n - 1)
	if one_way[kk]:
		return (lane + 0.5 - n * 0.5) * lw
	return (lane + 0.5) * lw


static func speed_factor(a: int, b: int) -> float:
	return float(speed.get(key(a, b), 1.0))


## Bir sonraki dugumden sonra gidilebilecek dugumler (cikmaza girmeyenler once; ara yollar ancak baska yol yoksa).
static func options(a: int, b: int) -> Array:
	var best: Array = []
	var service_only: Array = []
	var any: Array = []
	for c in ParkMap.road_next[b]:
		if c == a:
			continue
		var kk := key(b, c)
		if good.has(kk):
			if service.get(kk, false) and not service.get(key(a, b), false):
				service_only.append(c)
			else:
				best.append(c)
		elif ParkMap.inside_bounds(ParkMap.nodes[c], -40.0):
			any.append(c)
	if not best.is_empty():
		# Ana yoldan ara sokaga sapma olasiligi dusuk olsun: genis yollar agirlikli
		var out: Array = []
		for c in best:
			for i in (3 if float(speed[key(b, c)]) >= float(speed.get(key(a, b), 1.0)) else 1):
				out.append(c)
		return out
	if not service_only.is_empty():
		return service_only
	return any


# ---------------------------------------------------------------- kavsak gecis sirasi

## Donus turu: 0 duz, +1 saga, -1 sola (U donusu de sola sayilir).
static func turn_kind(a: int, k: int, c: int) -> int:
	if c < 0:
		return 0
	if c == a:
		return -1
	var d1 := (ParkMap.nodes[k] - ParkMap.nodes[a]).normalized()
	var d2 := (ParkMap.nodes[c] - ParkMap.nodes[k]).normalized()
	var ang := d1.angle_to(d2)
	return 0 if absf(ang) < 0.6 else (1 if ang > 0.0 else -1)


## Iki gecis (giris -> cikis) kavsakta kesisir mi?
static func conflict(k: int, a1: int, c1: int, a2: int, c2: int) -> bool:
	if a1 == a2:
		return false          # ayni koldan gelenler birbirini izler
	if c1 < 0 or c2 < 0:
		return true
	if c1 == c2:
		return true           # ayni yola cikiyorlar
	var t1 := turn_kind(a1, k, c1)
	var t2 := turn_kind(a2, k, c2)
	var d1 := (ParkMap.nodes[k] - ParkMap.nodes[a1]).normalized()
	var d2 := (ParkMap.nodes[k] - ParkMap.nodes[a2]).normalized()
	# Dar kavsaklarda yaylar birbirine cok yakin: yalnizca karsilikli kollardan gelip sola donmeyenler ayni anda gecer
	if d1.dot(d2) < -0.6 and t1 >= 0 and t2 >= 0:
		return false
	return true


static func _bike_cross(v: Object, o: Object, a1: int, c1: int, a2: int, c2: int) -> bool:
	return a1 == a2 and c1 != c2 and (v.get("kind") == "bisiklet" or o.get("kind") == "bisiklet")


## Otobus gibi kendi guzergahinda giden arac kavsagi tutar (yaklasirken ve gecerken her cagrida yenilenir).
static func claim(v: Object, k: int, dir: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Otobusun geldigi kol: ayni koldan gelen araclar onu beklemez (onunde giderler)
	var from := -2
	var best := 0.5
	for nb in road_nbs(k):
		var dn := (ParkMap.nodes[k] - ParkMap.nodes[nb]).normalized().dot(dir)
		if dn > best:
			best = dn
			from = nb
	var list: Array = _hold.get(k, [])
	for h in list:
		if h[0] == v:
			h[3] = now - 11.0        # 3 sn sonra kendiliginden duser
			return
	list.append([v, from, -1, now - 11.0, true])
	_hold[k] = list


## Arac bu kavsaga simdilik giremiyor (cikisi dolu): sirasini birakir, baskalari gecebilsin.
static func forget(v: Object, k: int) -> void:
	release(v, k)
	if _wait.has(k):
		(_wait[k] as Dictionary).erase(v.get_instance_id())


static func debug_state(k: int) -> String:
	var now := Time.get_ticks_msec() / 1000.0
	var out := "tutanlar:"
	for h in _hold.get(k, []):
		var o: Object = h[0]
		out += " [%s %s>%s yas=%.0f]" % [(str(o.get("kind")) if o.get("kind") != null else "otobus") if is_instance_valid(o) else "yok", h[1], h[2], now - float(h[3])]
	out += " bekleyenler:"
	var ws: Dictionary = _wait.get(k, {})
	for id in ws:
		var w: Array = ws[id]
		out += " [%s %s>%s bekledi=%.0f son=%.1f]" % [str(w[0].get("kind")) if is_instance_valid(w[0]) else "yok", w[1], w[2], now - float(w[3]), now - float(w[4])]
	return out


static func release(v: Object, k: int) -> void:
	if not _hold.has(k):
		return
	var list: Array = _hold[k]
	for i in range(list.size() - 1, -1, -1):
		if list[i][0] == v:
			list.remove_at(i)


## Arac v, a kolundan gelip c koluna cikmak icin k kavsagina girmek istiyor. d: dur cizgisine uzaklik, sp: hiz.
## true donerse girebilir (yaklasiyorsa henuz yer ayrilmaz; yakindaysa kavsak onun icin tutulur).
static func request(v: Object, k: int, a: int, c: int, d: float, sp: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var list: Array = _hold.get(k, [])
	for i in range(list.size() - 1, -1, -1):
		var h: Array = list[i]
		if not is_instance_valid(h[0]) or now - float(h[3]) > 14.0 or not (h[0] as Node).is_processing():
			list.remove_at(i)
	for h in list:
		if h[0] == v:
			if d > 0.5:
				for h2 in list:
					if h2.size() > 4 and h2[0] != v and int(h2[1]) != a:
						list.erase(h)      # otobus yaklasiyor: henuz girmedim, yol ver
						return false
			h[2] = c
			return true
	var waits: Dictionary = _wait.get(k, {})
	var id := v.get_instance_id()
	var me: Array
	if waits.has(id) and now - float(waits[id][4]) < 1.0:
		me = waits[id]
		me[2] = c
		me[4] = now
	else:
		me = [v, a, c, now, now, 0.0]
		waits[id] = me
		_wait[k] = waits
	me[5] = d / maxf(sp, 2.0)
	for h in list:
		if conflict(k, a, c, int(h[1]), int(h[2])) or _bike_cross(v, h[0], a, c, int(h[1]), int(h[2])):
			return false
	var waited := now - float(me[3])
	var pk := ParkMap.nodes[k]
	var din := (pk - ParkMap.nodes[a]).normalized()
	var right := Vector2(-din.y, din.x)
	var my_turn := turn_kind(a, k, c)
	for oid in waits.keys():
		if oid == id:
			continue
		var w: Array = waits[oid]
		if not is_instance_valid(w[0]) or now - float(w[4]) > 0.6:
			waits.erase(oid)
			continue
		if not conflict(k, a, c, int(w[1]), int(w[2])):
			continue
		var w_waited := now - float(w[3])
		if w_waited > waited + 3.0:
			return false                     # cok bekleyen once gecer
		if waited > 2.5 + float(id % 10) * 0.35:
			continue                         # yeterince bekledim: kilitlenmeyi coz
		var wd := (pk - ParkMap.nodes[int(w[1])]).normalized()
		if my_turn == -1 and wd.dot(din) < -0.6 and turn_kind(int(w[1]), k, int(w[2])) != -1 and float(w[5]) < float(me[5]) + 3.0:
			return false                     # sola donen, karsidan gelene yol verir
		if (-wd).dot(right) > 0.5 and float(w[5]) < float(me[5]) + 2.0:
			return false                     # sagdan gelene yol ver
	if d < 5.0 + sp * 0.7 + sp * sp / 6.0:
		list.append([v, a, c, now])
		_hold[k] = list
		waits.erase(id)
	return true
