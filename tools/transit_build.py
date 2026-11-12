"""Otobus hatlarini, duraklari, metro girislerini ve teleferigi oyun verisine cevirir: assets/transit.json

Kullanim: python3 tools/transit_build.py data/subayevleri.osm   (once tools/osm_build.py calismis olmali)

Kaynaklar:
  - Hat ve durak sirasi: data/ego_hatlari.json (EGO resmi sitesi)
  - Gercek durak, metro girisi ve istasyon konumlari: OpenStreetMap (data/subayevleri.osm)
  - Sokak agi: assets/city.json
Guzergah, hattin gectigi sokaklarin sirasina gore cizilir: siradaki sokak ucuz, digerleri pahali sayilir,
boylece otobus gercekte kullandigi sokaklardan gider. Tek yonlu yollara uyulur.
"""
import heapq
import json
import math
import os
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from osm_build import CENTER, M_LAT, M_LON   # noqa: E402

city = json.load(open(os.path.join(ROOT, 'assets/city.json')))
N = city['nodes']
HALF = city['half']


def proj(lat, lon):
    return [round((lon - CENTER[1]) * M_LON, 2), round(-(lat - CENTER[0]) * M_LAT, 2)]


# ---------------------------------------------------------------- OSM noktalari
osm = ET.parse(sys.argv[1]).getroot()
osm_stops, entrances, stations = [], [], []
for e in osm.findall('node'):
    t = {x.get('k'): x.get('v') for x in e.findall('tag')}
    p = proj(float(e.get('lat')), float(e.get('lon')))
    if t.get('highway') == 'bus_stop':
        osm_stops.append({'name': t.get('name', 'Durak'), 'pos': p, 'ref': t.get('ref', '')})
    elif t.get('railway') == 'subway_entrance':
        entrances.append({'ref': t.get('ref', ''), 'pos': p})
    elif t.get('public_transport') == 'station' and (t.get('railway') == 'station' or 'teleferi' in t.get('network', '')):
        stations.append({'name': t.get('name', ''), 'network': t.get('network', ''), 'pos': p})

inside = lambda p, m=0.0: abs(p[0]) < HALF[0] - m and abs(p[1]) < HALF[1] - m

# ---------------------------------------------------------------- yol agi (yonlu)
edges = {}            # a -> [(b, uzunluk, sokak adi, genislik)]
both = {}             # tek yon dikkate alinmadan (yedek)
for r in city['roads']:
    ids = r['n']
    for i in range(len(ids) - 1):
        a, b = ids[i], ids[i + 1]
        ln = math.dist(N[a], N[b])
        edges.setdefault(a, []).append((b, ln, r.get('name', ''), r['w']))
        both.setdefault(a, []).append((b, ln, r.get('name', ''), r['w']))
        both.setdefault(b, []).append((a, ln, r.get('name', ''), r['w']))
        if not r['oneway']:
            edges.setdefault(b, []).append((a, ln, r.get('name', ''), r['w']))
street_nodes = {}
for r in city['roads']:
    if r.get('name'):
        street_nodes.setdefault(r['name'], set()).update(r['n'])


# Ana sokak agi (birbirine bagli en buyuk parca): harita kenarinda kopuk kalan parcalar disarida
_seen = {}
for _s in both:
    if _s in _seen:
        continue
    _st = [_s]
    _seen[_s] = _s
    while _st:
        _u = _st.pop()
        for _v, *_ in both[_u]:
            if _v not in _seen:
                _seen[_v] = _s
                _st.append(_v)
_root = max(set(_seen.values()), key=lambda r: sum(1 for v in _seen.values() if v == r))
MAIN = {k for k, r in _seen.items() if r == _root and k in edges}


def nearest(p, among=None):
    pool = among if among is not None else MAIN
    return min(pool, key=lambda i: math.dist(N[i], p))


def path(a, b, prefer, graph=None):
    """a -> b en ucuz yol; 'prefer' kumesindeki sokaklar ucuz."""
    graph = graph or edges
    dist = {a: 0.0}
    back = {}
    q = [(0.0, a)]
    while q:
        d, u = heapq.heappop(q)
        if u == b:
            break
        if d > dist.get(u, 1e18):
            continue
        for v, ln, name, w in graph.get(u, []):
            nd = d + ln * (1.0 if name in prefer else (1.6 if w >= 8 else 3.0))
            if nd < dist.get(v, 1e18):
                dist[v] = nd
                back[v] = u
                heapq.heappush(q, (nd, v))
    if b not in back and a != b:
        if graph is both:
            raise SystemExit('yol bulunamadi: %d -> %d' % (a, b))
        print('  uyari: tek yon kurallariyla yol yok (%d -> %d), yon dikkate alinmadan cizildi' % (a, b))
        return path(a, b, prefer, both)
    out = [b]
    while out[-1] != a:
        out.append(back[out[-1]])
    return out[::-1]


def route(start, streets, end):
    """start/end: nokta; streets: sirayla gecilen sokaklar."""
    ids = [nearest(start)]
    end_node = nearest(end)
    for i, s in enumerate(streets):
        nxt = streets[i + 1] if i + 1 < len(streets) else None
        here = street_nodes[s]
        if nxt and street_nodes[nxt] & here:
            target = min(street_nodes[nxt] & here, key=lambda k: math.dist(N[k], N[ids[-1]]) * 0 + 0)
            # Iki sokagin birlestigi kavsaklardan, mevcut konumdan en uzak olani degil en mantikli olani: sokak boyunca ilerleyen
            joints = list(street_nodes[nxt] & here)
            target = min(joints, key=lambda k: abs(math.dist(N[k], N[ids[-1]]) - 0.0))
        elif nxt:
            # Sokaklar kesismiyor: bu sokagin, bir sonrakine en yakin noktasi
            target = min(here, key=lambda k: min(math.dist(N[k], N[j]) for j in street_nodes[nxt]))
        else:
            target = end_node
        if target in edges or any(target == v for u in edges for v, *_ in edges[u]):
            seg = path(ids[-1], target, {s} | ({nxt} if nxt else set()))
            ids += seg[1:]
    if ids[-1] != end_node:
        ids += path(ids[-1], end_node, set())[1:]
    pts = [N[i] for i in ids]
    clean = [pts[0]]
    for p in pts[1:]:
        if math.dist(p, clean[-1]) > 0.5:
            clean.append(p)
    return clean, ids


def arc(pts):
    s = [0.0]
    for i in range(1, len(pts)):
        s.append(s[-1] + math.dist(pts[i - 1], pts[i]))
    return s


def project_on(pts, p, s_min=0.0):
    """Noktanin guzergah uzerindeki en yakin yeri (s_min'den sonra): (s, nokta, yon)."""
    S = arc(pts)
    best = None
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ab = (b[0] - a[0], b[1] - a[1])
        L2 = ab[0] ** 2 + ab[1] ** 2 or 1e-9
        t = max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / L2))
        q = (a[0] + ab[0] * t, a[1] + ab[1] * t)
        s = S[i] + math.sqrt(L2) * t
        if s < s_min:
            continue
        d = math.dist(q, p)
        if best is None or d < best[0]:
            L = math.sqrt(L2)
            best = (d, s, q, (ab[0] / L, ab[1] / L))
    return best


def point_at(pts, s):
    S = arc(pts)
    for i in range(len(pts) - 1):
        if S[i + 1] >= s:
            t = (s - S[i]) / max(S[i + 1] - S[i], 1e-6)
            a, b = pts[i], pts[i + 1]
            L = max(S[i + 1] - S[i], 1e-6)
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
    a, b = pts[-2], pts[-1]
    L = math.dist(a, b) or 1.0
    return tuple(b), ((b[0] - a[0]) / L, (b[1] - a[1]) / L)


# Durak adlarini sokak adlarina eslemek icin
STREET_OF = {'Sandalcı Sk.': 'Sandalcı Caddesi', 'Kalender Sk.': 'Kalender Sokak', 'Üçyıldız Cd.': 'Üçyıldız Caddesi',
             'Bando Sk.': 'Bando Sokak', 'Fahrettin Altay Cd.': 'Fahrettin Altay Caddesi', 'Şehit Makbule Sk.': 'Şht. Makbule Sokak',
             'Cihangir Cd.': 'Cihangir Caddesi', 'Fethi Bey Sk.': 'Fethibey Sokak', 'Centilmen Sk.': 'Centilmen Caddesi'}


def place_stops(pts, names, width_of):
    """Duraklari guzergah boyunca sirayla yerlestirir. Bilinmeyenler iki komsunun arasina."""
    S = arc(pts)
    total = S[-1]
    spots = [None] * len(names)
    s_min = 0.0
    for i, n in enumerate(names):
        street = STREET_OF.get(n)
        if street and street in street_nodes:
            nodes = street_nodes[street]
            c = (sum(N[k][0] for k in nodes) / len(nodes), sum(N[k][1] for k in nodes) / len(nodes))
            best = project_on(pts, c, s_min)
            # Sokagin guzergaha degdigi ilk yer: sokak dugumlerinden guzergaha en yakin olani
            cand = [project_on(pts, N[k], s_min) for k in nodes]
            cand = [x for x in cand if x and x[0] < 3.0]
            if cand:
                best = min(cand, key=lambda x: x[1])
            if best:
                spots[i] = best[1] + 25.0
                s_min = spots[i] + 30.0
    # Bilinmeyenleri komsularin arasina dagit
    known = [(i, s) for i, s in enumerate(spots) if s is not None]
    for i in range(len(names)):
        if spots[i] is not None:
            continue
        lo = max([(j, s) for j, s in known if j < i], default=(-1, 20.0))
        hi = min([(j, s) for j, s in known if j > i], default=(len(names), total - 20.0))
        spots[i] = lo[1] + (hi[1] - lo[1]) * (i - lo[0]) / (hi[0] - lo[0])
    out = []
    last = -1e9
    for n, s in zip(names, spots):
        s = max(s, last + 40.0)
        s = min(s, total - 10.0)
        last = s
        p, d = point_at(pts, s)
        right = (-d[1], d[0])          # oyunda sag serit tarafi
        w = width_of(p)
        q = (p[0] + right[0] * (w * 0.5 + 1.6), p[1] + right[1] * (w * 0.5 + 1.6))
        out.append({'name': n, 's': round(s, 1), 'pos': [round(q[0], 2), round(q[1], 2)],
                    'road': [round(p[0], 2), round(p[1], 2)], 'dir': [round(d[0], 4), round(d[1], 4)]})
    return out


def width_at(p):
    best, w = 1e9, 6.5
    for r in city['roads']:
        for i in range(len(r['n']) - 1):
            a, b = N[r['n'][i]], N[r['n'][i + 1]]
            ab = (b[0] - a[0], b[1] - a[1])
            L2 = ab[0] ** 2 + ab[1] ** 2 or 1e-9
            t = max(0.0, min(1.0, ((p[0] - a[0]) * ab[0] + (p[1] - a[1]) * ab[1]) / L2))
            d = math.dist(p, (a[0] + ab[0] * t, a[1] + ab[1] * t))
            if d < best:
                best, w = d, r['w']
    return w


ego = json.load(open(os.path.join(ROOT, 'data/ego_hatlari.json')))['hatlar']
lines = {}

# 427 ve 464: Subayevleri'nden kalkar, Fahrettin Altay Caddesi'nden guneye cikar, ayni yoldan doner
go_pts, _ = route((440.0, -150.0), ['Sandalcı Caddesi', 'Kalender Sokak', 'Üçyıldız Caddesi', 'Bando Sokak', 'Fahrettin Altay Caddesi'], (-113.0, 676.0))
back_pts, _ = route((-249.0, 819.0), ['Fahrettin Altay Caddesi', 'Şht. Makbule Sokak', 'Üçyıldız Caddesi', 'Kalender Sokak', 'Cihangir Caddesi', 'Fethibey Sokak', 'Centilmen Caddesi'], (380.0, -150.0))
for no in ('427', '464'):
    h = ego[no]
    lines[no] = {'name': h['ad'], 'color': '1f5fae' if no == '427' else '2f8f4e',
                 'gidis': {'path': [[round(x, 2), round(z, 2)] for x, z in go_pts], 'stops': place_stops(go_pts, h['haritada_gidis'], width_at)},
                 'donus': {'path': [[round(x, 2), round(z, 2)] for x, z in back_pts], 'stops': place_stops(back_pts, h['haritada_donus'], width_at)}}

# 481, 479, 419: Fatih Caddesi'nden gecer (bolunmus yol, iki yon ayri)
# Bolunmus yol: guneye ve kuzeye giden seritler ayri yollar
sb, nb = set(), set()
for r in city['roads']:
    if r.get('name') == 'Fatih Caddesi' and r['oneway']:
        (sb if N[r['n'][-1]][1] > N[r['n'][0]][1] else nb).update(k for k in r['n'] if k in MAIN)
south_pts, _ = route(N[min(sb, key=lambda k: N[k][1])], ['Fatih Caddesi'], N[max(sb, key=lambda k: N[k][1])])   # Kizilay yonu
north_pts, _ = route(N[max(nb, key=lambda k: N[k][1])], ['Fatih Caddesi'], N[min(nb, key=lambda k: N[k][1])])   # Uyanis yonu
for no in ('481', '479', '419'):
    lines[no] = {'name': ego[no]['ad'], 'color': '1f5fae',
                 'gidis': {'path': [[round(x, 2), round(z, 2)] for x, z in south_pts], 'stops': []},
                 'donus': {'path': [[round(x, 2), round(z, 2)] for x, z in north_pts],
                           'stops': place_stops(north_pts, ['Teleferik', 'Atatürk Bahçesi'], width_at)}}
# Teleferik duragini gercek istasyonun onune cek
tele = next((s for s in stations if s['name'] == 'Atatürk'), None)
if tele:
    for no in ('481', '479', '419'):
        st = lines[no]['donus']['stops']
        best = project_on(north_pts, tele['pos'])
        if best:
            s0 = best[1]
            p, d = point_at(north_pts, s0)
            right = (-d[1], d[0])
            w = width_at(p)
            st[0].update({'s': round(s0, 1), 'pos': [round(p[0] + right[0] * (w * 0.5 + 1.6), 2), round(p[1] + right[1] * (w * 0.5 + 1.6), 2)],
                          'road': [round(p[0], 2), round(p[1], 2)], 'dir': [round(d[0], 4), round(d[1], 4)]})
            p2, d2 = point_at(north_pts, s0 + 160.0)
            r2 = (-d2[1], d2[0])
            st[1].update({'s': round(s0 + 160.0, 1), 'pos': [round(p2[0] + r2[0] * (w * 0.5 + 1.6), 2), round(p2[1] + r2[1] * (w * 0.5 + 1.6), 2)],
                          'road': [round(p2[0], 2), round(p2[1], 2)], 'dir': [round(d2[0], 4), round(d2[1], 4)]})

# Haritadaki diger gercek duraklar (baska hatlarin): sadece durak yapisi
used = [s['pos'] for ln in lines.values() for leg in ('gidis', 'donus') for s in ln[leg]['stops']]
extra = [s for s in osm_stops if inside(s['pos'], 4.0) and all(math.dist(s['pos'], u) > 25.0 for u in used)]
for s in extra:
    best = None
    for r in city['roads']:
        for i in range(len(r['n']) - 1):
            a, b = N[r['n'][i]], N[r['n'][i + 1]]
            ab = (b[0] - a[0], b[1] - a[1])
            L2 = ab[0] ** 2 + ab[1] ** 2 or 1e-9
            t = max(0.0, min(1.0, ((s['pos'][0] - a[0]) * ab[0] + (s['pos'][1] - a[1]) * ab[1]) / L2))
            q = (a[0] + ab[0] * t, a[1] + ab[1] * t)
            d = math.dist(q, s['pos'])
            if best is None or d < best[0]:
                L = math.sqrt(L2)
                best = (d, q, (ab[0] / L, ab[1] / L), r['w'])
    d, q, dr, w = best
    side = 1.0 if (s['pos'][0] - q[0]) * (-dr[1]) + (s['pos'][1] - q[1]) * dr[0] >= 0 else -1.0
    right = (-dr[1] * side, dr[0] * side)
    s['road'] = [round(q[0], 2), round(q[1], 2)]
    s['dir'] = [round(dr[0] * side, 4), round(dr[1] * side, 4)]
    s['pos'] = [round(q[0] + right[0] * (w * 0.5 + 1.6), 2), round(q[1] + right[1] * (w * 0.5 + 1.6), 2)]

metro = [{'name': st['name'], 'line': st['network'] or 'M4', 'pos': st['pos'],
          'entrances': [e for e in entrances if math.dist(e['pos'], st['pos']) < 60.0]}
         for st in stations if 'teleferi' not in st['network']]
cable = [st for st in stations if 'teleferi' in st['network']]

out = {'lines': lines, 'other_stops': extra, 'metro': metro, 'cable_car': cable,
       'source': 'EGO hat bilgisi (data/ego_hatlari.json) + OpenStreetMap'}
json.dump(out, open(os.path.join(ROOT, 'assets/transit.json'), 'w'), ensure_ascii=False)
for no, ln in lines.items():
    print(no, 'gidis %.0f m %d durak' % (arc(ln['gidis']['path'])[-1], len(ln['gidis']['stops'])),
          'donus %.0f m %d durak' % (arc(ln['donus']['path'])[-1], len(ln['donus']['stops'])))
print('diger durak', len(extra), [s['name'] for s in extra])
print('metro', [(m['name'], len(m['entrances']), inside(m['pos'])) for m in metro])
print('teleferik', [(c['name'], inside(c['pos'])) for c in cable])
