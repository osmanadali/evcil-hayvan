"""OpenStreetMap verisini oyun haritasina cevirir:
  python3 tools/osm_build.py data/kecioren.osm
Uretir: assets/city.json (yollar, binalar, parklar, yerler), assets/splat_a.png, assets/splat_b.png (zemin boyama),
assets/park_map.png (harita uygulamasi gorseli).
Koordinatlar: metre, x dogu, z guney; merkez CENTER. Veri (c) OpenStreetMap katkicilari, ODbL."""
import os
import sys, json, math, random, xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFilter

# Bolgeler: her biri ayri bir oyun haritasi; aralarinda metroyla gidilir. OSM_ZONE ortam degiskeniyle secilir.
ZONES = {
    'subayevleri': {'center': (39.96950, 32.87150), 'half': (650.0, 560.0), 'out': 'assets', 'wanted': True},
    'gar': {'center': (39.93350, 32.84420), 'half': (620.0, 480.0), 'out': 'assets/gar', 'wanted': False, 'start': (39.93420, 32.84300)},
}
ZONE = os.environ.get('OSM_ZONE', 'subayevleri')
CENTER = ZONES[ZONE]['center']      # enlem, boylam
HALF = ZONES[ZONE]['half']          # oyun alaninin yari boyutu (dogu-bati, kuzey-guney)
OUT = ZONES[ZONE]['out']
MARGIN = 110.0                     # alanin disinda da cizilen serit
EXTENT = 2 * max(HALF) + 2 * MARGIN
PX = 4096
M_LAT = 111_132.0
M_LON = 111_320.0 * math.cos(math.radians(CENTER[0]))

ROAD_W = {'primary': 12.0, 'secondary': 10.0, 'tertiary': 8.5, 'residential': 6.5, 'unclassified': 6.5,
          'living_street': 5.5, 'service': 4.0, 'secondary_link': 7.0, 'primary_link': 7.0, 'tertiary_link': 6.0}
PATH_W = {'footway': 2.2, 'path': 2.0, 'pedestrian': 4.0, 'steps': 2.2, 'cycleway': 2.2}
GREEN = lambda t: t.get('leisure') in ('park', 'garden', 'playground', 'pitch') or t.get('landuse') in ('forest', 'grass', 'recreation_ground') \
    or t.get('natural') in ('wood', 'scrub', 'grassland')

# Gercek haritaya eklenen oyun yerleri (bos alanlara yerlestirildi)
# Gercek haritaya eklenen oyun yerleri: [istenen konum, yari boyut]. Arac en yakin bos park cimini bulur.
WANTED = {
    'bahce': ([330.0, 150.0], [10.0, 12.0]),       # kulube, havuz, oyuncaklar
    'petshop': ([370.0, 80.0], [7.0, 6.0]),
    'kafe': ([410.0, 60.0], [6.0, 7.0]),
    'dondurmaci': ([350.0, 200.0], [4.0, 4.0]),
    'cardak': ([300.0, 210.0], [4.5, 4.5]),
    'cesme': ([380.0, 150.0], [6.5, 6.5]),
    'oyun_alani': ([330.0, 250.0], [8.0, 6.5]),
    'piknik': ([290.0, 260.0], [4.0, 4.0]),
}
SPOTS = {}


def load(path):
    root = ET.parse(path).getroot()
    nodes = {n.get('id'): ((float(n.get('lon')) - CENTER[1]) * M_LON, -(float(n.get('lat')) - CENTER[0]) * M_LAT) for n in root.iter('node')}
    ways = []
    for w in root.iter('way'):
        tags = {t.get('k'): t.get('v') for t in w.findall('tag')}
        ids = [n.get('ref') for n in w.findall('nd') if n.get('ref') in nodes]
        if len(ids) >= 2:
            ways.append((tags, ids))
    tagged = []
    for n in root.iter('node'):
        tags = {t.get('k'): t.get('v') for t in n.findall('tag')}
        if tags:
            tagged.append((tags, n.get('id')))
    return nodes, ways, tagged


def near(pts, extra=0.0):
    return any(abs(x) < HALF[0] + MARGIN + extra and abs(z) < HALF[1] + MARGIN + extra for x, z in pts)


def area(p):
    return abs(sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))) / 2


def centroid(p):
    return [sum(q[0] for q in p) / len(p), sum(q[1] for q in p) / len(p)]


def _in(q, poly):
    c = False
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        if (a[1] > q[1]) != (b[1] > q[1]) and q[0] < (b[0] - a[0]) * (q[1] - a[1]) / (b[1] - a[1]) + a[0]:
            c = not c
    return c


def build(path):
    nodes, ways, tagged = load(path)
    rnd = random.Random(7)
    graph_nodes, index = [], {}
    def nid(i):
        if i not in index:
            index[i] = len(graph_nodes)
            graph_nodes.append([round(nodes[i][0], 2), round(nodes[i][1], 2)])
        return index[i]
    roads, paths, buildings, parks, water, pitches, places = [], [], [], [], [], [], []
    barriers, parking, playgrounds, bridges, road_at = [], [], [], [], {}
    for tags, ids in ways:
        pts = [nodes[i] for i in ids]
        if not near(pts):
            continue
        ring = [[round(x, 2), round(z, 2)] for x, z in (pts[:-1] if ids[0] == ids[-1] else pts)]
        hw = tags.get('highway')
        if tags.get('tunnel') in ('yes', 'building_passage') and hw not in PATH_W:
            if hw: continue          # yer alti yollari cizme
        if hw in ROAD_W and tags.get('area') != 'yes':
            try: lanes = int(tags.get('lanes', '0'))
            except ValueError: lanes = 0
            if lanes == 0: lanes = 4 if ROAD_W[hw] >= 12 else (2 if ROAD_W[hw] >= 8 else 1)
            roads.append({'n': [nid(i) for i in ids], 'w': ROAD_W[hw], 'k': hw, 'name': tags.get('name', ''),
                          'oneway': tags.get('oneway') == 'yes', 'lanes': lanes})
            for a_, b_ in zip(ids, ids[1:]):
                d_ = (nodes[b_][0] - nodes[a_][0], nodes[b_][1] - nodes[a_][1])
                road_at[a_] = road_at[b_] = (math.atan2(d_[1], d_[0]), ROAD_W[hw])
            if tags.get('bridge') in ('yes', 'viaduct'):
                bridges.append({'p': [[round(x, 2), round(z, 2)] for x, z in pts], 'w': ROAD_W[hw]})
        elif hw in PATH_W:
            paths.append({'n': [nid(i) for i in ids], 'w': PATH_W[hw], 'steps': hw == 'steps'})
        elif 'building' in tags and len(ring) >= 3 and not (tags.get('layer', '0').lstrip('-').isdigit() and int(tags.get('layer', '0')) < 0) and tags.get('location') != 'underground':
            a = area(ring)
            kind = 'cami' if tags.get('amenity') == 'place_of_worship' or tags.get('building') == 'mosque' else \
                ('okul' if tags.get('amenity') == 'school' or tags.get('building') == 'school' else 'apartman')
            if 'building:levels' in tags:
                try: levels = max(1, int(float(tags['building:levels'])))
                except ValueError: levels = 4
            elif a < 45: levels = 1
            elif a < 110: levels = rnd.choice([2, 3])
            elif kind == 'okul': levels = 3
            else: levels = rnd.choice([4, 4, 5, 5, 6])
            hip = kind == 'apartman' and 70 < a < 700 and len(ring) <= 8 and tags.get('roof:shape', 'hipped') != 'flat'
            buildings.append({'p': ring, 'h': round(levels * 3.0 + 0.8, 1), 't': kind, 'name': tags.get('name', ''),
                              'no': tags.get('addr:housenumber', ''), 'roof': 'kirma' if hip else 'duz'})
        elif (tags.get('natural') == 'water' or tags.get('leisure') == 'swimming_pool') and len(ring) >= 3:
            water.append({'p': ring})
        elif tags.get('barrier') in ('wall', 'fence', 'retaining_wall', 'hedge'):
            barriers.append({'p': [[round(x, 2), round(z, 2)] for x, z in pts], 'k': 'cit' if tags['barrier'] == 'fence' else 'duvar'})
        elif tags.get('amenity') == 'parking' and len(ring) >= 3:
            parking.append({'p': ring})
        elif tags.get('leisure') == 'playground' and len(ring) >= 3:
            playgrounds.append({'p': ring, 'pos': [round(v, 1) for v in centroid(ring)]})
        elif GREEN(tags) and len(ring) >= 3:
            (pitches if tags.get('leisure') == 'pitch' else parks).append({'p': ring, 'name': tags.get('name', '')})
        if tags.get('name') and len(ring) >= 3 and (tags.get('leisure') in ('park', 'pitch', 'stadium') or tags.get('amenity') in ('school', 'place_of_worship')):
            c = centroid(ring)
            if abs(c[0]) < HALF[0] - 15 and abs(c[1]) < HALF[1] - 15:
                kind = 'park' if tags.get('leisure') == 'park' else ('saha' if 'leisure' in tags else ('cami' if tags.get('amenity') == 'place_of_worship' else 'okul'))
                places.append({'name': tags['name'], 'kind': kind, 'pos': [round(c[0], 1), round(c[1], 1)], 'r': round(max(10.0, min(60.0, math.sqrt(area(ring)) * 0.6)), 1)})
    # Zincir markalarin adlari oyunda uydurma adlarla degistirilir (marka hakki)
    FAKE = {"BİM": "Bizim Market", "Migros": "Mavi Market", "Şok": "Şimşek Market", "Shell": "Sarı Petrol", "Total": "Toprak Petrol", "Petrol Ofisi": "Petrol Durağı", "Türkiye İş Bankası": "Başkent Bankası"}
    # Noktasal ayrintilar: dukkanlar, duraklar, trafik isiklari, yaya gecitleri...
    KIND = [('highway', 'bus_stop', 'durak'), ('public_transport', 'station', 'metro'), ('railway', 'station', 'metro'),
            ('amenity', 'pharmacy', 'eczane'), ('shop', 'supermarket', 'market'), ('shop', 'convenience', 'market'), ('shop', 'kiosk', 'market'),
            ('shop', 'bakery', 'market'), ('shop', 'butcher', 'market'), ('amenity', 'restaurant', 'yemek'), ('amenity', 'cafe', 'yemek'),
            ('amenity', 'fast_food', 'yemek'), ('amenity', 'bank', 'banka'), ('amenity', 'atm', 'banka'), ('amenity', 'fuel', 'akaryakit'),
            ('amenity', 'taxi', 'taksi'), ('amenity', 'post_office', 'kargo'), ('amenity', 'police', 'polis'), ('tourism', 'museum', 'muze'),
            ('amenity', 'kindergarten', 'okul'), ('amenity', 'college', 'okul'), ('amenity', 'university', 'okul'), ('shop', None, 'dukkan'),
            ('office', None, 'ofis'), ('leisure', 'sports_centre', 'spor')]
    inb = lambda p, m=6.0: abs(p[0]) < HALF[0] - m and abs(p[1]) < HALF[1] - m
    pois, signals, crossings, props = [], [], [], []
    for tags, i in tagged:
        p = nodes[i]
        if not inb(p):
            continue
        q = [round(p[0], 2), round(p[1], 2)]
        if tags.get('highway') == 'traffic_signals':
            signals.append(q); continue
        if tags.get('highway') == 'crossing' and i in road_at:
            crossings.append({'pos': q, 'rot': round(road_at[i][0], 3), 'w': road_at[i][1]}); continue
        for key, val, kind in (('amenity', 'bench', 'bank'), ('natural', 'tree', 'agac'), ('amenity', 'fountain', 'cesme'),
                               ('leisure', 'picnic_table', 'piknik'), ('tourism', 'artwork', 'heykel'), ('man_made', 'flagpole', 'bayrak')):
            if tags.get(key) == val:
                props.append({'k': kind, 'pos': q})
        name = tags.get('name')
        if not name:
            continue
        name = FAKE.get(name, name)
        kind = next((k for key, val, k in KIND if key in tags and (val is None or tags[key] == val)), None)
        if kind is None or any(o['name'] == name and math.dist(o['pos'], q) < 25 for o in pois):
            continue
        wall = False
        for bl in buildings:
            if _in(q, bl['p']):
                # Bina icindeki nokta: en yakin cepheye tasi, tabela duvara asilsin
                best = None
                poly = bl['p']
                for e in range(len(poly)):
                    a_, b_ = poly[e], poly[(e + 1) % len(poly)]
                    ab = (b_[0] - a_[0], b_[1] - a_[1]); L2 = ab[0] ** 2 + ab[1] ** 2 or 1e-9
                    t = max(0.0, min(1.0, ((q[0] - a_[0]) * ab[0] + (q[1] - a_[1]) * ab[1]) / L2))
                    c = (a_[0] + ab[0] * t, a_[1] + ab[1] * t); dd = math.dist(c, q)
                    if best is None or dd < best[0]: best = (dd, c)
                d_ = (best[1][0] - q[0], best[1][1] - q[1]); L = math.hypot(*d_) or 1.0
                q = [round(best[1][0] + d_[0] / L * 0.5, 2), round(best[1][1] + d_[1] / L * 0.5, 2)]
                wall = True
                break
        pois.append({'name': name, 'k': kind, 'pos': q, 'wall': wall})
    # Sokak tabelalari: adli her yolun iki ucunda
    signs = []
    for r in roads:
        if not r['name']:
            continue
        pts = [graph_nodes[i] for i in r['n']]
        for a_, b_ in ((pts[0], pts[1]), (pts[-1], pts[-2])):
            d_ = (b_[0] - a_[0], b_[1] - a_[1]); L = math.hypot(*d_) or 1.0
            q = [round(a_[0] + d_[0] / L * 5.0 - d_[1] / L * (r['w'] / 2 + 1.3), 1), round(a_[1] + d_[1] / L * 5.0 + d_[0] / L * (r['w'] / 2 + 1.3), 1)]
            if inb(q) and not any(math.dist(o['pos'], q) < 7 or (o['name'] == r['name'] and math.dist(o['pos'], q) < 60) for o in signs) \
                    and not any(_in(q, bl['p']) for bl in buildings):
                signs.append({'name': r['name'], 'pos': q})

    # Bina kapilari: yola en yakin cephe kenarinin ortasi
    segs = []
    for r in roads:
        pts = [graph_nodes[i] for i in r['n']]
        segs += [(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    def seg_d(q, a_, b_):
        ab = (b_[0] - a_[0], b_[1] - a_[1]); L2 = ab[0] ** 2 + ab[1] ** 2 or 1e-9
        t = max(0.0, min(1.0, ((q[0] - a_[0]) * ab[0] + (q[1] - a_[1]) * ab[1]) / L2))
        return math.hypot(q[0] - a_[0] - ab[0] * t, q[1] - a_[1] - ab[1] * t)
    doors = 0
    for bl in buildings:
        c = centroid(bl['p'])
        if not inb(c, -10) or bl['t'] == 'cami':
            continue
        near_segs = [sg for sg in segs if abs((sg[0][0] + sg[1][0]) / 2 - c[0]) < 90 and abs((sg[0][1] + sg[1][1]) / 2 - c[1]) < 90]
        if not near_segs:
            continue
        best = None
        poly = bl['p']
        for e in range(len(poly)):
            a_, b_ = poly[e], poly[(e + 1) % len(poly)]
            if math.dist(a_, b_) < 2.5:
                continue
            m = ((a_[0] + b_[0]) / 2, (a_[1] + b_[1]) / 2)
            dd = min(seg_d(m, s0, s1) for s0, s1 in near_segs)
            if best is None or dd < best[0]:
                out = (m[0] - c[0], m[1] - c[1]); L = math.hypot(*out) or 1.0
                best = (dd, m, (out[0] / L, out[1] / L))
        if best and best[0] < 45:
            bl['door'] = [round(best[1][0], 2), round(best[1][1], 2), round(best[2][0], 3), round(best[2][1], 3)]
            doors += 1
    print('kapi %d, kapi numarali bina %d, kirma catili %d, tek yon %d, merdiven %d' % (
        doors, sum(1 for b_ in buildings if b_['no']), sum(1 for b_ in buildings if b_['roof'] == 'kirma'),
        sum(1 for r in roads if r['oneway']), sum(1 for p_ in paths if p_['steps'])))

    # Sokak adlari icin etiket noktalarini cikar (her ad icin en uzun parca)
    labels = {}
    for r in roads:
        if not r['name']:
            continue
        pts = [graph_nodes[i] for i in r['n']]
        best = max(range(len(pts) - 1), key=lambda i: math.dist(pts[i], pts[i + 1]))
        a, b = pts[best], pts[best + 1]
        length = sum(math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
        mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]
        if abs(mid[0]) < HALF[0] and abs(mid[1]) < HALF[1] and length > labels.get(r['name'], (0,))[0]:
            ang = math.atan2(b[1] - a[1], b[0] - a[0])
            if ang > math.pi / 2: ang -= math.pi
            if ang < -math.pi / 2: ang += math.pi
            labels[r['name']] = (length, [round(mid[0], 1), round(mid[1], 1)], round(ang, 3))
    streets = [{'name': k, 'pos': v[1], 'rot': v[2]} for k, v in labels.items()]

    data = {'center': CENTER, 'half': HALF, 'extent': EXTENT, 'nodes': graph_nodes, 'roads': roads, 'paths': paths,
            'buildings': buildings, 'parks': parks, 'pitches': pitches, 'water': water, 'places': places, 'streets': streets, 'spots': SPOTS,
            'pois': pois, 'signs': signs, 'signals': signals, 'crossings': crossings, 'props': props, 'barriers': barriers,
            'parking': parking, 'playgrounds': playgrounds, 'bridges': bridges}
    for bl in data['buildings']:
        bl['name'] = FAKE.get(bl.get('name', ''), bl.get('name', ''))
    json.dump(data, open(os.path.join(OUT, 'city.json'), 'w'), ensure_ascii=False, separators=(',', ':'))
    print('yol %d, patika %d, bina %d, park %d, saha %d, su %d, yer %d, sokak adi %d, dugum %d' % (
        len(roads), len(paths), len(buildings), len(parks), len(pitches), len(water), len(places), len(streets), len(graph_nodes)))
    print('isletme/durak %d, sokak tabelasi %d, trafik isigi %d, yaya gecidi %d, esya %d, duvar/cit %d, otopark %d, oyun parki %d, kopru %d' % (
        len(pois), len(signs), len(signals), len(crossings), len(props), len(barriers), len(parking), len(playgrounds), len(bridges)))
    return data


def raster(data):
    k = PX / EXTENT
    P = lambda p: ((p[0] + EXTENT / 2) * k, (p[1] + EXTENT / 2) * k)
    nodes = data['nodes']
    def lines(img, ways, extra, value):
        d = ImageDraw.Draw(img)
        for w in ways:
            pts = [P(nodes[i]) for i in w['n']]
            width = max(1, int(round((w['w'] + extra) * k)))
            d.line(pts, fill=value, width=width, joint='curve')
            for p in (pts[0], pts[-1]):
                d.ellipse([p[0] - width / 2, p[1] - width / 2, p[0] + width / 2, p[1] + width / 2], fill=value)
    def polys(img, items, value):
        d = ImageDraw.Draw(img)
        for it in items:
            d.polygon([P(p) for p in it['p']], fill=value)
    L = lambda: Image.new('L', (PX, PX), 0)
    asphalt, walk, foot, urban, wat = L(), L(), L(), Image.new('L', (PX, PX), 255), L()
    polys(asphalt, data['parking'], 255)
    lines(asphalt, data['roads'], 0.0, 255)
    lines(walk, data['roads'], 4.4, 255)
    lines(foot, data['paths'], 0.0, 255)
    polys(urban, data['parks'], 0)
    polys(urban, data['pitches'], 0)
    polys(wat, data['water'], 255)
    # Maskeler mesafe alani olarak saklanir (0.5 = kenar): buyutulunce kenarlar keskin kalir
    import numpy as np
    from scipy import ndimage
    def sdf(mask, reach):
        m = np.asarray(mask) > 127
        d = ndimage.distance_transform_edt(~m) - ndimage.distance_transform_edt(m)     # disarida +, iceride -
        v = np.clip(0.5 - d / k / (2.0 * reach), 0.0, 1.0)                             # iceride > 0.5
        return Image.fromarray((v * 255).astype(np.uint8), 'L')
    inv = lambda im: Image.eval(im, lambda v: 255 - v)
    sandbox = L()
    polys(sandbox, data['playgrounds'], 255)
    built = L()
    polys(built, data['buildings'], 255)
    walk_all = Image.fromarray(np.maximum(np.asarray(walk), np.asarray(asphalt)), 'L')
    Image.merge('RGB', (sdf(foot, 6.0), inv(sdf(wat, 4.0)), sdf(sandbox, 6.0))).save(os.path.join(OUT, 'splat_a.png'))    # patika, kiyi, kum
    Image.merge('RGB', (sdf(asphalt, 6.0), sdf(walk_all, 6.0), sdf(urban, 6.0))).save(os.path.join(OUT, 'splat_b.png'))   # asfalt, kaldirim, sehir zemini
    Image.merge('RGB', (sdf(built, 6.0), L(), L())).resize((2048, 2048), Image.BILINEAR).save(os.path.join(OUT, 'splat_c.png'))  # bina yakinligi (golgeleme)

    # Harita uygulamasi gorseli
    m = Image.new('RGB', (PX, PX), (236, 233, 224))
    d = ImageDraw.Draw(m)
    for it in data['parks']: d.polygon([P(p) for p in it['p']], fill=(200, 230, 178))
    for it in data['pitches']: d.polygon([P(p) for p in it['p']], fill=(168, 212, 150), outline=(140, 190, 128))
    for it in data['parking']: d.polygon([P(p) for p in it['p']], fill=(226, 226, 230))
    for it in data['playgrounds']: d.polygon([P(p) for p in it['p']], fill=(240, 226, 180))
    for it in data['water']: d.polygon([P(p) for p in it['p']], fill=(159, 208, 238), outline=(111, 179, 220))
    for w in data['paths']:
        d.line([P(nodes[i]) for i in w['n']], fill=(214, 198, 160), width=max(2, int(w['w'] * k)))
    for extra, col in ((1.6, (203, 205, 210)), (0.0, (255, 255, 255))):
        for w in data['roads']:
            pts = [P(nodes[i]) for i in w['n']]
            width = max(2, int(round((w['w'] + extra) * k)))
            c = (252, 232, 170) if extra == 0.0 and w['k'] in ('primary', 'secondary') else col
            d.line(pts, fill=c, width=width, joint='curve')
            for p in (pts[0], pts[-1]):
                d.ellipse([p[0] - width / 2, p[1] - width / 2, p[0] + width / 2, p[1] + width / 2], fill=c)
    for b in data['buildings']:
        col = {'cami': (190, 214, 220), 'okul': (240, 214, 170)}.get(b['t'], (226, 212, 200))
        d.polygon([P(p) for p in b['p']], fill=col, outline=(196, 180, 166))
    m.filter(ImageFilter.GaussianBlur(0.5)).save(os.path.join(OUT, 'park_map.png'))


def heightmap(data):
    """Yukseklik karolarindan (data/dem, terrarium bicimi, z13) arazi yuksekligini uretir: assets/height.png."""
    import numpy as np
    Z = 13
    ext0 = EXTENT + 400.0
    n0 = 2 ** Z
    def tile(lat, lon):
        return ((lon + 180) / 360 * n0, (1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n0)
    dlat, dlon = ext0 / 2 / M_LAT, ext0 / 2 / M_LON
    t0 = tile(CENTER[0] + dlat, CENTER[1] - dlon)
    t1 = tile(CENTER[0] - dlat, CENTER[1] + dlon)
    xs = tuple(range(int(t0[0]), int(t1[0]) + 1))
    ys = tuple(range(int(t0[1]), int(t1[1]) + 1))
    for x in xs:
        for y in ys:
            f = 'data/dem/%d_%d_%d.png' % (Z, x, y)
            if not os.path.exists(f):
                import urllib.request
                urllib.request.urlretrieve('https://elevation-tiles-prod.s3.amazonaws.com/terrarium/%d/%d/%d.png' % (Z, x, y), f)
    big = np.zeros((256 * len(ys), 256 * len(xs)))
    for i, x in enumerate(xs):
        for j, y in enumerate(ys):
            a = np.asarray(Image.open('data/dem/%d_%d_%d.png' % (Z, x, y)).convert('RGB'), dtype=np.float64)
            big[j * 256:(j + 1) * 256, i * 256:(i + 1) * 256] = a[:, :, 0] * 256 + a[:, :, 1] + a[:, :, 2] / 256 - 32768
    N = 256
    ext = EXTENT + 400.0
    out = np.zeros((N, N))
    n = 2 ** Z
    for j in range(N):
        lat = CENTER[0] - ((j + 0.5) / N - 0.5) * ext / M_LAT
        fy = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
        py = (fy - ys[0]) * 256 - 0.5
        for i in range(N):
            lon = CENTER[1] + ((i + 0.5) / N - 0.5) * ext / M_LON
            pxx = ((lon + 180) / 360 * n - xs[0]) * 256 - 0.5
            x0, y0 = int(pxx), int(py); tx, ty = pxx - x0, py - y0
            out[j, i] = (big[y0, x0] * (1 - tx) + big[y0, x0 + 1] * tx) * (1 - ty) + (big[y0 + 1, x0] * (1 - tx) + big[y0 + 1, x0 + 1] * tx) * ty
    # Veri 30 m cozunurluklu ve gurultulu: yumusat
    kx = np.exp(-0.5 * (np.arange(-9, 10) / 3.0) ** 2); kx /= kx.sum()
    pad = np.pad(out, 9, mode='edge')
    pad = np.apply_along_axis(lambda r: np.convolve(r, kx, mode='valid'), 1, pad)
    out = np.apply_along_axis(lambda r: np.convolve(r, kx, mode='valid'), 0, pad)
    lo, hi = float(out.min()), float(out.max())
    v = np.clip((out - lo) / (hi - lo) * 65535, 0, 65535).astype(np.uint32)
    rgb = np.zeros((N, N, 3), dtype=np.uint8)
    rgb[:, :, 0] = v >> 8
    rgb[:, :, 1] = v & 255
    Image.fromarray(rgb, 'RGB').save(os.path.join(OUT, 'height.png'))
    c = out[N // 2, N // 2]
    data['height'] = {'min': round(lo - c, 2), 'range': round(hi - lo, 2), 'extent': ext, 'n': N}
    print('yukseklik: en alcak %.0f m, en yuksek %.0f m (deniz seviyesinden), fark %.0f m' % (lo, hi, hi - lo))


def preview(data, out):
    """Yer secmek icin: oyun alani, izgara ve bos alanlar."""
    N = 2400; R = max(HALF) + 40; k = N / (2 * R)
    P = lambda p: ((p[0] + R) * k, (p[1] + R) * k)
    im = Image.new('RGB', (N, N), (240, 238, 228)); d = ImageDraw.Draw(im)
    nodes = data['nodes']
    for it in data['parks']: d.polygon([P(p) for p in it['p']], fill=(190, 226, 170))
    for it in data['pitches']: d.polygon([P(p) for p in it['p']], fill=(150, 204, 140))
    for it in data['water']: d.polygon([P(p) for p in it['p']], fill=(150, 200, 238))
    for w in data['paths']: d.line([P(nodes[i]) for i in w['n']], fill=(200, 160, 110), width=2)
    for w in data['roads']: d.line([P(nodes[i]) for i in w['n']], fill=(255, 255, 255), width=max(2, int(w['w'] * k)))
    for b in data['buildings']: d.polygon([P(p) for p in b['p']], fill=(214, 170, 140), outline=(150, 110, 90))
    for g in range(-700, 701, 50):
        col = (120, 120, 200) if g % 100 == 0 else (200, 200, 230)
        d.line([P((g, -R)), P((g, R))], fill=col); d.line([P((-R, g)), P((R, g))], fill=col)
        if g % 100 == 0:
            d.text(P((g + 2, -R + 4)), str(g), fill=(0, 0, 160)); d.text(P((-R + 4, g + 2)), str(g), fill=(0, 0, 160))
    d.rectangle([P((-HALF[0], -HALF[1])), P((HALF[0], HALF[1]))], outline=(220, 40, 40), width=3)
    for pl in data['places']: d.text(P(pl['pos']), pl['name'][:24].encode('ascii', 'replace').decode(), fill=(20, 80, 20))
    for name, s in data['spots'].items():
        p = P(s['pos']); d.ellipse([p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6], fill=(230, 30, 30)); d.text((p[0] + 8, p[1] - 6), name, fill=(200, 0, 0))
    im.save(out)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    data = build(sys.argv[1])
    heightmap(data)
    raster(data)
    # Oyun yerlerini istenen konuma en yakin bos park cimine yerlestir
    a = Image.open(os.path.join(OUT, 'splat_a.png')).load(); b = Image.open(os.path.join(OUT, 'splat_b.png')).load(); k = PX / EXTENT
    cimg = Image.open(os.path.join(OUT, 'splat_c.png')); cpx = cimg.load(); kc = cimg.size[0] / EXTENT
    def clean(c, h, placed):
        if abs(c[0]) + h[0] > HALF[0] - 10 or abs(c[1]) + h[1] > HALF[1] - 10:
            return False
        for o, oh in placed:
            if abs(c[0] - o[0]) < h[0] + oh[0] + 6 and abs(c[1] - o[1]) < h[1] + oh[1] + 6:
                return False
        for i in range(5):
            for j in range(5):
                q = (c[0] + (i - 2) * h[0] * 0.55, c[1] + (j - 2) * h[1] * 0.55)
                px = (int((q[0] + EXTENT / 2) * k), int((q[1] + EXTENT / 2) * k))
                ra, ga, _ = a[px]; rb, gb, bb = b[px]
                if ra > 100 or ga < 175 or rb > 100 or gb > 100 or bb > 110:
                    return False
                # Binalardan en az 5 m uzakta olmali (bina mesafe alani: 127 = duvar, 6 m = 64 birim)
                if cpx[int((q[0] + EXTENT / 2) * kc), int((q[1] + EXTENT / 2) * kc)][0] > 74:
                    return False
        return True
    placed = []
    for name, (want, h) in (WANTED.items() if ZONES[ZONE]['wanted'] else []):
        best = None
        for r in range(0, 260, 4):
            steps = max(1, int(2 * math.pi * r / 4))
            for t in range(steps):
                c = (want[0] + r * math.cos(t * 2 * math.pi / steps), want[1] + r * math.sin(t * 2 * math.pi / steps))
                if clean(c, [h[0] + 2, h[1] + 2], placed) and (name != 'bahce' or clean((c[0] + h[0] + 3.0, c[1]), [2.0, 2.0], [])):
                    best = c; break
            if best: break
        if not best:
            print('  YER BULUNAMADI', name); continue
        placed.append((best, h))
        data['spots'][name] = {'pos': [round(best[0], 1), round(best[1], 1)], 'half': h}
        print('  yer %-11s istenen %s -> %s' % (name, want, data['spots'][name]['pos']))
    # Baslangic: bahce kapisinin (dogu kenari) hemen onu; bahcesiz bolgede metro istasyonunun yaninda bos bir kaldirim
    if 'bahce' in data['spots']:
        g = data['spots']['bahce']
        start = [g['pos'][0] + g['half'][0] + 3.0, g['pos'][1]]
        if not clean(start, [2.0, 2.0], []):
            raise SystemExit('baslangic noktasi bos degil: bahcenin yerini degistir')
    else:
        st = ZONES[ZONE].get('start', CENTER)
        want = ((st[1] - CENTER[1]) * M_LON, -(st[0] - CENTER[0]) * M_LAT)
        start = None
        for r in range(0, 200, 2):
            for t in range(max(1, r * 2)):
                q = (want[0] + r * math.cos(t * math.pi / max(1, r)), want[1] + r * math.sin(t * math.pi / max(1, r)))
                px = (int((q[0] + EXTENT / 2) * k), int((q[1] + EXTENT / 2) * k))
                if b[px][0] < 90 and cpx[int((q[0] + EXTENT / 2) * kc), int((q[1] + EXTENT / 2) * kc)][0] < 70 \
                        and not any(_in(q, bl['p']) for bl in data['buildings']):
                    start = [round(q[0], 1), round(q[1], 1)]
                    break
            if start:
                break
        print('  baslangic', start)
    data['spots']['baslangic'] = {'pos': start, 'half': [1.0, 1.0]}
    for name, sp in data['spots'].items():
        hh = sp['half']
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                q = (sp['pos'][0] + dx * hh[0], sp['pos'][1] + dz * hh[1])
                assert not any(_in(q, bl['p']) for bl in data['buildings']), 'bina icinde: ' + name
    json.dump(data, open(os.path.join(OUT, 'city.json'), 'w'), ensure_ascii=False, separators=(',', ':'))
    if len(sys.argv) > 2:
        preview(data, sys.argv[2])
