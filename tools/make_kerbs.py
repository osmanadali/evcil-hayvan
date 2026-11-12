"""Yuksek kaldirim modelini uretir: assets/models/kaldirim.glb

Kullanim: python3 tools/make_kerbs.py   (once tools/osm_build.py calismis olmali)

Kaldirim alani zemin maskesinden (assets/splat_b.png: R asfalt, G asfalt+kaldirim; 0.5 = kenar, 1 m = 1/12)
1 m'lik izgarada "marching squares" ile cikarilir: ustu 14 cm yuksekte, kenarlari bordur duvari.
Oyun ayni maskeden yurume yuksekligini hesaplar (park_map.gd: sidewalk_raise), ikisi birbirini tutar.
"""
import json
import os

import bpy
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
RAISE = 0.14
CHUNK = 80.0
STEP = 1.0

data = json.load(open(os.path.join(ROOT, 'assets/city.json')))
EXT = data['extent']
half = data['half']
b = np.asarray(Image.open(os.path.join(ROOT, 'assets/splat_b.png')).convert('RGB')).astype(np.float32) / 255.0
PX = b.shape[0]
hd = data['height']
himg = np.asarray(Image.open(os.path.join(ROOT, 'assets/height.png')).convert('RGB')).astype(np.float64)
H = hd['min'] + (himg[..., 0] * 256.0 + himg[..., 1]) / 65535.0 * hd['range']


def bilinear(img, fx, fy):
    x0 = np.clip(np.floor(fx).astype(int), 0, img.shape[1] - 2)
    y0 = np.clip(np.floor(fy).astype(int), 0, img.shape[0] - 2)
    tx = np.clip(fx - x0, 0, 1); ty = np.clip(fy - y0, 0, 1)
    return (img[y0, x0] * (1 - tx) + img[y0, x0 + 1] * tx) * (1 - ty) + (img[y0 + 1, x0] * (1 - tx) + img[y0 + 1, x0 + 1] * tx) * ty


def field(x, z):
    """> 0: kaldirim (asfalt degil ama kaldirim seridinin icinde)."""
    fx = (x / EXT + 0.5) * PX - 0.5
    fy = (z / EXT + 0.5) * PX - 0.5
    return np.minimum(bilinear(b[..., 1], fx, fy) - 0.5, 0.5 - bilinear(b[..., 0], fx, fy))


def terrain(x, z):
    n = hd['n']
    return bilinear(H, (x / hd['extent'] + 0.5) * n - 0.5, (z / hd['extent'] + 0.5) * n - 0.5)


xs = np.arange(-half[0] - 8, half[0] + 8 + STEP, STEP)
zs = np.arange(-half[1] - 8, half[1] + 8 + STEP, STEP)
X, Z = np.meshgrid(xs, zs)
F = field(X, Z)
inside = F > 0
active = inside[:-1, :-1] | inside[:-1, 1:] | inside[1:, :-1] | inside[1:, 1:]
print('izgara', F.shape, 'etkin hucre', int(active.sum()))

chunks = {}


def chunk(x, z):
    key = (int(np.floor(x / CHUNK)), int(np.floor(z / CHUNK)))
    if key not in chunks:
        chunks[key] = {'v': [], 'f': [], 'uv': [], 'col': []}
    return chunks[key]


def add_face(c, pts, uvs, col):
    start = len(c['v'])
    c['v'].extend(pts)
    c['uv'].extend(uvs)
    c['col'].extend([col] * len(pts))
    c['f'].append(list(range(start, start + len(pts))))


def bl(x, z, y):
    return (x, -z, y)


for j, i in zip(*np.nonzero(active)):
    cx = [xs[i], xs[i + 1], xs[i + 1], xs[i]]
    cz = [zs[j], zs[j], zs[j + 1], zs[j + 1]]
    cv = [F[j, i], F[j, i + 1], F[j + 1, i + 1], F[j + 1, i]]
    poly, cross = [], []
    for k in range(4):
        n = (k + 1) % 4
        if cv[k] > 0:
            poly.append((cx[k], cz[k]))
        if (cv[k] > 0) != (cv[n] > 0):
            t = cv[k] / (cv[k] - cv[n])
            p = (cx[k] + (cx[n] - cx[k]) * t, cz[k] + (cz[n] - cz[k]) * t)
            poly.append(p); cross.append(p)
    if len(poly) < 3:
        continue
    c = chunk(xs[i], zs[j])
    px = np.array([p[0] for p in poly]); pz = np.array([p[1] for p in poly])
    py = terrain(px, pz) + RAISE
    pts = [bl(x, z, y) for x, z, y in zip(px, pz, py)]
    add_face(c, pts[::-1], [(x * 0.4, z * 0.4) for x, z in zip(px, pz)][::-1], (1.0, 1.0, 1.0, 1.0))
    if len(cross) == 2:                       # bordur duvari
        (x0, z0), (x1, z1) = cross
        y0 = float(terrain(np.array(x0), np.array(z0))); y1 = float(terrain(np.array(x1), np.array(z1)))
        ln = float(np.hypot(x1 - x0, z1 - z0))
        add_face(c, [bl(x0, z0, y0 + RAISE), bl(x1, z1, y1 + RAISE), bl(x1, z1, y1 - 0.06), bl(x0, z0, y0 - 0.06)],
                 [(0, 0.2), (ln * 0.4, 0.2), (ln * 0.4, 0.0), (0, 0.0)], (0.78, 0.78, 0.76, 1.0))

bpy.ops.wm.read_factory_settings(use_empty=True)
mat = bpy.data.materials.new('kaldirim')
total = 0
for key, c in chunks.items():
    me = bpy.data.meshes.new('k_%d_%d' % key)
    me.from_pydata(c['v'], [], c['f'])
    uv = me.uv_layers.new(name='UVMap')
    col = me.color_attributes.new(name='Color', type='BYTE_COLOR', domain='CORNER')
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uv.data[li].uv = c['uv'][vi]
            col.data[li].color = c['col'][vi]
    # Bordur yuzleri de ust yuz gibi isik alsin (yoksa golgede simsiyah kaliyor)
    me.normals_split_custom_set([(0.0, 0.0, 1.0)] * len(me.loops))
    me.materials.append(mat)
    ob = bpy.data.objects.new(me.name, me)
    bpy.context.collection.objects.link(ob)
    total += len(c['f'])
out = os.path.join(ROOT, 'assets/models/kaldirim.glb')
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_yup=True, export_animations=False)
print('yazildi', out, len(chunks), 'parca', total, 'yuz', os.path.getsize(out) // 1024, 'KB')
