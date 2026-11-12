"""OpenStreetMap verisini oyun haritasina cevirir:
  python3 tools/osm_build.py data/kecioren.osm
Uretir: assets/city.json (yollar, binalar, parklar, yerler), assets/splat_a.png, assets/splat_b.png (zemin boyama),
assets/park_map.png (harita uygulamasi gorseli).
Koordinatlar: metre, x dogu, z guney; merkez CENTER. Veri (c) OpenStreetMap katkicilari, ODbL."""
import sys, json, math, random, xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFilter

CENTER = (39.99270, 32.87300)      # enlem, boylam
HALF = (430.0, 360.0)              # oyun alaninin yari boyutu (dogu-bati, kuzey-guney)
MARGIN = 110.0                     # alanin disinda da cizilen serit
EXTENT = 2 * max(HALF) + 2 * MARGIN
PX = 2048
M_LAT = 111_132.0
M_LON = 111_320.0 * math.cos(math.radians(CENTER[0]))

ROAD_W = {'primary': 12.0, 'secondary': 10.0, 'tertiary': 8.5, 'residential': 6.5, 'unclassified': 6.5,
          'living_street': 5.5, 'service': 4.0, 'secondary_link': 7.0, 'primary_link': 7.0, 'tertiary_link': 6.0}
PATH_W = {'footway': 2.2, 'path': 2.0, 'pedestrian': 4.0, 'steps': 2.2, 'cycleway': 2.2}
GREEN = lambda t: t.get('leisure') in ('park', 'garden', 'playground', 'pitch') or t.get('landuse') in ('forest', 'grass', 'recreation_ground') \
    or t.get('natural') in ('wood', 'scrub', 'grassland')

# Gercek haritaya eklenen oyun yerleri (bos alanlara yerlestirildi)
SPOTS = {
    'baslangic': {'pos': [229.0, -45.0], 'half': [1.0, 1.0]},
    'bahce': {'pos': [214.0, -45.0], 'half': [10.0, 12.0]},       # kulube, havuz, oyuncaklar
    'petshop': {'pos': [318.0, -160.0], 'half': [6.5, 5.0]},
    'kafe': {'pos': [350.0, -146.0], 'half': [5.0, 6.0]},
    'dondurmaci': {'pos': [247.0, -28.0]},
    'cardak': {'pos': [238.0, -192.0]},
    'cesme': {'pos': [248.0, 12.0]},
    'oyun_alani': {'pos': [214.0, -186.0], 'half': [8.0, 6.5]},
    'piknik': {'pos': [278.0, -138.0]},
}


def load(path):
    root = ET.parse(path).getroot()
    nodes = {n.get('id'): ((float(n.get('lon')) - CENTER[1]) * M_LON, -(float(n.get('lat')) - CENTER[0]) * M_LAT) for n in root.iter('node')}
    ways = []
    for w in root.iter('way'):
        tags = {t.get('k'): t.get('v') for t in w.findall('tag')}
        ids = [n.get('ref') for n in w.findall('nd') if n.get('ref') in nodes]
        if len(ids) >= 2:
            ways.append((tags, ids))
    return nodes, ways


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
    nodes, ways = load(path)
    rnd = random.Random(7)
    graph_nodes, index = [], {}
    def nid(i):
        if i not in index:
            index[i] = len(graph_nodes)
            graph_nodes.append([round(nodes[i][0], 2), round(nodes[i][1], 2)])
        return index[i]
    roads, paths, buildings, parks, water, pitches, places = [], [], [], [], [], [], []
    for tags, ids in ways:
        pts = [nodes[i] for i in ids]
        if not near(pts):
            continue
        ring = [[round(x, 2), round(z, 2)] for x, z in (pts[:-1] if ids[0] == ids[-1] else pts)]
        hw = tags.get('highway')
        if hw in ROAD_W and tags.get('area') != 'yes':
            roads.append({'n': [nid(i) for i in ids], 'w': ROAD_W[hw], 'k': hw, 'name': tags.get('name', '')})
        elif hw in PATH_W:
            paths.append({'n': [nid(i) for i in ids], 'w': PATH_W[hw]})
        elif 'building' in tags and len(ring) >= 3:
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
            buildings.append({'p': ring, 'h': round(levels * 3.0 + 0.8, 1), 't': kind, 'name': tags.get('name', '')})
        elif tags.get('natural') == 'water' and len(ring) >= 3:
            water.append({'p': ring})
        elif GREEN(tags) and len(ring) >= 3:
            (pitches if tags.get('leisure') == 'pitch' else parks).append({'p': ring, 'name': tags.get('name', '')})
        if tags.get('name') and len(ring) >= 3 and (tags.get('leisure') in ('park', 'pitch', 'stadium') or tags.get('amenity') in ('school', 'place_of_worship')):
            c = centroid(ring)
            if abs(c[0]) < HALF[0] - 15 and abs(c[1]) < HALF[1] - 15:
                kind = 'park' if tags.get('leisure') == 'park' else ('saha' if 'leisure' in tags else ('cami' if tags.get('amenity') == 'place_of_worship' else 'okul'))
                places.append({'name': tags['name'], 'kind': kind, 'pos': [round(c[0], 1), round(c[1], 1)], 'r': round(max(10.0, min(60.0, math.sqrt(area(ring)) * 0.6)), 1)})
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
            'buildings': buildings, 'parks': parks, 'pitches': pitches, 'water': water, 'places': places, 'streets': streets, 'spots': SPOTS}
    json.dump(data, open('assets/city.json', 'w'), ensure_ascii=False, separators=(',', ':'))
    print('yol %d, patika %d, bina %d, park %d, saha %d, su %d, yer %d, sokak adi %d, dugum %d' % (
        len(roads), len(paths), len(buildings), len(parks), len(pitches), len(water), len(places), len(streets), len(graph_nodes)))
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
    lines(asphalt, data['roads'], 0.0, 255)
    lines(walk, data['roads'], 4.4, 255)
    lines(foot, data['paths'], 0.0, 255)
    polys(urban, data['parks'], 0)
    polys(urban, data['pitches'], 0)
    polys(wat, data['water'], 255)
    soft = lambda im, r=0.8: im.filter(ImageFilter.GaussianBlur(r))
    shore = Image.eval(soft(wat, 4.0 * k), lambda v: 255 - v)       # 0.5 = kiyi, yaklasik +-4 m
    Image.merge('RGB', (soft(foot), shore, L())).save('assets/splat_a.png')
    Image.merge('RGB', (soft(asphalt), soft(walk), soft(urban, 1.5))).save('assets/splat_b.png')

    # Harita uygulamasi gorseli
    m = Image.new('RGB', (PX, PX), (236, 233, 224))
    d = ImageDraw.Draw(m)
    for it in data['parks']: d.polygon([P(p) for p in it['p']], fill=(200, 230, 178))
    for it in data['pitches']: d.polygon([P(p) for p in it['p']], fill=(168, 212, 150), outline=(140, 190, 128))
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
    m.filter(ImageFilter.GaussianBlur(0.5)).save('assets/park_map.png')


def preview(data, out):
    """Yer secmek icin: oyun alani, izgara ve bos alanlar."""
    N = 1800; R = max(HALF) + 40; k = N / (2 * R)
    P = lambda p: ((p[0] + R) * k, (p[1] + R) * k)
    im = Image.new('RGB', (N, N), (240, 238, 228)); d = ImageDraw.Draw(im)
    nodes = data['nodes']
    for it in data['parks']: d.polygon([P(p) for p in it['p']], fill=(190, 226, 170))
    for it in data['pitches']: d.polygon([P(p) for p in it['p']], fill=(150, 204, 140))
    for it in data['water']: d.polygon([P(p) for p in it['p']], fill=(150, 200, 238))
    for w in data['paths']: d.line([P(nodes[i]) for i in w['n']], fill=(200, 160, 110), width=2)
    for w in data['roads']: d.line([P(nodes[i]) for i in w['n']], fill=(255, 255, 255), width=max(2, int(w['w'] * k)))
    for b in data['buildings']: d.polygon([P(p) for p in b['p']], fill=(214, 170, 140), outline=(150, 110, 90))
    for g in range(-400, 401, 50):
        col = (120, 120, 200) if g % 100 == 0 else (200, 200, 230)
        d.line([P((g, -R)), P((g, R))], fill=col); d.line([P((-R, g)), P((R, g))], fill=col)
        if g % 100 == 0:
            d.text(P((g + 2, -R + 4)), str(g), fill=(0, 0, 160)); d.text(P((-R + 4, g + 2)), str(g), fill=(0, 0, 160))
    d.rectangle([P((-HALF[0], -HALF[1])), P((HALF[0], HALF[1]))], outline=(220, 40, 40), width=3)
    for pl in data['places']: d.text(P(pl['pos']), pl['name'][:24], fill=(20, 80, 20))
    for name, s in data['spots'].items():
        p = P(s['pos']); d.ellipse([p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6], fill=(230, 30, 30)); d.text((p[0] + 8, p[1] - 6), name, fill=(200, 0, 0))
    im.save(out)


if __name__ == '__main__':
    data = build(sys.argv[1])
    raster(data)
    # Eklenen yerlerin bos alanda oldugunu denetle
    a = Image.open('assets/splat_a.png'); b = Image.open('assets/splat_b.png'); k = PX / EXTENT
    for name, sp in data['spots'].items():
        h = sp.get('half', [3.0, 3.0]); bad = []
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                q = (sp['pos'][0] + dx * h[0], sp['pos'][1] + dz * h[1])
                px = (int((q[0] + EXTENT / 2) * k), int((q[1] + EXTENT / 2) * k))
                ra, ga, _ = a.getpixel(px); rb, gb, bb = b.getpixel(px)
                inside = any(_in(q, bl['p']) for bl in data['buildings'])
                if ra > 60 or ga < 150 or rb > 60 or gb > 60 or inside:
                    bad.append((dx, dz, 'patika' if ra > 60 else 'su' if ga < 150 else 'bina' if inside else 'yol'))
        print('  yer', name, 'TEMIZ' if not bad else bad)
    if len(sys.argv) > 2:
        preview(data, sys.argv[2])
