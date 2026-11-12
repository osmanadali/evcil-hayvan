"""Gercek yaprak ve kabuk dokularindan (Poly Haven, CC0) agac modeli uretir.

Kullanim: python3 tools/make_tree.py <doku_klasoru> <yaprakli|cam> <cikti.glb>

<doku_klasoru> icinde (2K jpg): tree_small_02_leaves_diff/alpha, tree_small_02_diff,
fir_tree_01_twig_diff/alpha, fir_tree_01_bark_diff.
Agac: govde + dallar (kabuk dokusu) ve yaprak kumesi kartlari (saydam doku). Tek mesh, tek doku:
dokunun sol yarisi yaprak kumesi, sag yarisi kabuk. Kart normalleri tacin disina bakar (yumusak isik).
"""
import math
import os
import random
import sys

import bpy
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

SRC, KIND, OUT = sys.argv[-3:]
rnd = random.Random(7 if KIND == 'yaprakli' else 11)
A = 1024  # doku yarisinin kenari


def pieces(diff, alpha, keep, clean=0):
    """Dokudaki tek tek yaprak/surgunleri keser; uzun eksenleri dikey olacak sekilde dondurur."""
    d = Image.open(os.path.join(SRC, diff)).convert('RGB')
    a = np.array(Image.open(os.path.join(SRC, alpha)).convert('L'))
    mask = a > 110
    if clean:
        # Ince sap artiklarini sil: asindir, sonra geri genislet
        yy, xx = np.ogrid[-clean:clean + 1, -clean:clean + 1]
        disk = xx * xx + yy * yy <= clean * clean
        mask = ndimage.binary_dilation(ndimage.binary_erosion(mask, disk), disk)
    lab, n = ndimage.label(mask)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        m = lab[sl] == i + 1
        if not keep(sl, m.sum(), a.shape):
            continue
        rgba = np.dstack([np.array(d)[sl], (m * 255).astype(np.uint8)])
        ys, xs = np.nonzero(m)
        c = np.cov(np.stack([xs, ys]))
        w, v = np.linalg.eigh(c)
        ang = math.degrees(math.atan2(v[1, 1], v[0, 1]))
        im = Image.fromarray(rgba, 'RGBA').rotate(ang - 90, expand=True, resample=Image.BICUBIC)
        out.append(im.crop(im.getbbox()))
    return out


def paste(canvas, im, x, y, angle, length, shade):
    """Parcanin tabani (x, y)'de, ucu 'angle' yonunde (0 = yukari) olacak sekilde yapistirir."""
    k = length / im.size[1]
    im = im.resize((max(2, int(im.size[0] * k)), max(2, int(length))), Image.BICUBIC)
    r, g, b, al = im.split()
    rgb = Image.merge('RGB', (r, g, b)).point(lambda v: min(255, int(v * shade)))
    im = Image.merge('RGBA', (*rgb.split(), al))
    big = Image.new('RGBA', (im.size[0], im.size[1] * 2), (0, 0, 0, 0))
    big.paste(im, (0, 0))                        # taban, buyuk resmin ortasinda kalir
    big = big.rotate(-angle, expand=True, resample=Image.BICUBIC)
    canvas.alpha_composite(big, (int(x - big.size[0] / 2), int(y - big.size[1] / 2)))


def leaf_cluster():
    def keep(sl, area, shape):
        return area > 30000
    fronds = []
    for im in pieces('jacaranda_tree_leaves_diff.jpg', 'jacaranda_tree_leaves_alpha.jpg', keep):
        al = np.array(im.split()[3]) > 0
        k = max(2, im.size[1] // 9)
        if al[:k].sum() < al[-k:].sum():          # sap (seyrek uc) altta olsun
            im = im.rotate(180)
        fronds.append(im)
    print('yaprak parcasi', len(fronds))
    cv = Image.new('RGBA', (A, A), (0, 0, 0, 0))
    dr = ImageDraw.Draw(cv)
    base = (A / 2, A - 16)
    jobs = []
    for i in range(5):                            # arkada uzun dallar
        ang = -50 + i * 25 + rnd.uniform(-6, 6)
        a = math.radians(ang)
        ln = rnd.uniform(330, 420)
        mid = (base[0] + math.sin(a) * ln, base[1] - math.cos(a) * ln)
        dr.line([base, mid], fill=(78, 60, 42, 255), width=7)
        jobs.append((mid[0], mid[1], ang + rnd.uniform(-10, 10), rnd.uniform(430, 520), 0.8))
        for side in (-1, 1):
            jobs.append((mid[0], mid[1], ang + side * rnd.uniform(38, 60), rnd.uniform(330, 420), 0.9))
    for i in range(7):                            # onde kisa, acik renkli yapraklar
        ang = -66 + i * 22 + rnd.uniform(-8, 8)
        jobs.append((base[0] + rnd.uniform(-30, 30), base[1] - rnd.uniform(20, 160), ang, rnd.uniform(360, 470), 1.12))
    for x, y, ang, ln, shade in jobs:
        paste(cv, rnd.choice(fronds), x, y, ang, ln, shade + rnd.uniform(-0.06, 0.06))
    return cv


def fir_bough():
    def keep(sl, area, shape):
        return 9000 < area and sl[1].start > shape[1] * 0.16 and sl[0].stop < shape[0] * 0.84
    sprigs = pieces('fir_tree_01_twig_diff.jpg', 'fir_tree_01_twig_alpha.jpg', keep)
    print('surgun parcasi', len(sprigs))
    cv = Image.new('RGBA', (A, A), (0, 0, 0, 0))
    dr = ImageDraw.Draw(cv)
    dr.line([(A / 2, A - 10), (A / 2, 90)], fill=(70, 54, 38, 255), width=9)
    n = 15
    for s in range(n):
        t = s / (n - 1)
        y = A - 60 - t * (A - 200)
        ln = (1.0 - 0.72 * t) * 430
        for side in (-1, 1):
            paste(cv, rnd.choice(sprigs), A / 2, y, side * rnd.uniform(48, 66), ln * rnd.uniform(0.85, 1.1), rnd.uniform(0.85, 1.15))
    paste(cv, rnd.choice(sprigs), A / 2, 230, 0, 220, 1.1)
    return cv


def atlas():
    card = leaf_cluster() if KIND == 'yaprakli' else fir_bough()
    bark = Image.open(os.path.join(SRC, 'tree_small_02_diff.jpg' if KIND == 'yaprakli' else 'fir_tree_01_bark_diff.jpg'))
    bark = bark.convert('RGB').resize((A, A), Image.LANCZOS)
    # Saydam yerlerin rengi yaprak yesili olsun (kenarlarda siyah sizinti olmasin)
    arr = np.array(card).astype(np.float32)
    al = arr[..., 3:4] / 255.0
    mean = (arr[..., :3] * al).sum((0, 1)) / max(al.sum(), 1.0)
    arr[..., :3] = arr[..., :3] * al + mean * (1 - al)
    card = Image.fromarray(arr.astype(np.uint8), 'RGBA')
    out = Image.new('RGBA', (A * 2, A), (0, 0, 0, 255))
    out.paste(card, (0, 0))
    out.paste(bark, (A, 0))
    path = OUT[:-4] + '_doku.png'
    out.save(path)
    print('kaplama', round(float(al.mean()), 2))
    return path


V, N, UV, F = [], [], [], []


def tube(points, radii, sides=7):
    """Noktalar boyunca incelen boru; kabuk dokusu sag yarida."""
    start = len(V)
    for i, (p, r) in enumerate(zip(points, radii)):
        p = np.array(p, float)
        d = np.array(points[min(i + 1, len(points) - 1)], float) - np.array(points[max(i - 1, 0)], float)
        d /= np.linalg.norm(d)
        ref = np.array([1.0, 0, 0]) if abs(d[0]) < 0.9 else np.array([0, 1.0, 0])
        u = np.cross(d, ref); u /= np.linalg.norm(u)
        w = np.cross(d, u)
        for s in range(sides + 1):
            a = s / sides * math.tau
            n = math.cos(a) * u + math.sin(a) * w
            V.append(p + n * r); N.append(n)
            UV.append((0.5 + 0.5 * s / sides, min(0.999, i / (len(points) - 1) * len(points) * 0.16)))
    for i in range(len(points) - 1):
        for s in range(sides):
            a = start + i * (sides + 1) + s
            F.append((a, a + 1, a + sides + 2, a + sides + 1))


def card(base, along, side, normal, length, width):
    """Yaprak karti: taban ortasi 'base', 'along' yonunde uzar. Doku sol yarida, tabani altta."""
    base, along, side = np.array(base, float), np.array(along, float), np.array(side, float)
    q = [base - side * width / 2, base + side * width / 2, base + side * width / 2 + along * length, base - side * width / 2 + along * length]
    start = len(V)
    for p, uv in zip(q, [(0.0, 0.0), (0.5, 0.0), (0.5, 1.0), (0.0, 1.0)]):
        V.append(p); N.append(normal); UV.append(uv)
    F.append((start, start + 1, start + 2, start + 3))


def unit(v):
    v = np.array(v, float)
    return v / max(np.linalg.norm(v), 1e-6)


def rand_dir():
    z = rnd.uniform(-1, 1); a = rnd.uniform(0, math.tau); r = math.sqrt(1 - z * z)
    return np.array([r * math.cos(a), r * math.sin(a), z])


def leafy():
    H = 8.0
    top = np.array([0.15, -0.1, H * 0.4])
    tube([(0, 0, -0.3), (0.03, 0.02, 0.6), (0.1, -0.04, H * 0.22), top], [0.26, 0.2, 0.16, 0.13], 9)
    centre = np.array([0.0, 0.0, H * 0.67])
    rad = np.array([H * 0.36, H * 0.36, H * 0.3])
    tips = []
    for i in range(6):
        a = i / 6 * math.tau + rnd.uniform(-0.3, 0.3)
        end = centre + np.array([math.cos(a), math.sin(a), rnd.uniform(-0.25, 0.5)]) * rad * 0.62
        mid = (top + end) / 2 + np.array([0, 0, 0.35])
        tube([top, mid, end], [0.1, 0.065, 0.03], 5)
        tips.append(end)
        for j in range(2):
            e2 = end + (unit(end - centre) * 0.7 + rand_dir() * 0.5) * rad.mean() * 0.4
            tube([mid, (mid + e2) / 2 + np.array([0, 0, 0.2]), e2], [0.05, 0.035, 0.015], 4)
            tips.append(e2)
    up = np.array([0, 0, 1.0])
    for i in range(420):
        d = rand_dir()
        if d[2] < -0.6:
            continue
        r = rnd.uniform(0.5, 1.0) ** 0.6
        p = centre + d * rad * r
        if i < len(tips) * 3:
            p = tips[i % len(tips)] + rand_dir() * 0.3
            d = unit(p - centre)
        along = unit(d + rand_dir() * 0.55 + up * 0.15)
        side = unit(np.cross(along, rand_dir()))
        size = rnd.uniform(1.5, 2.3)
        card(p - along * size * 0.45, along, side, unit(d * 0.8 + up * 0.45), size, size)


def fir():
    H = 9.0
    tube([(0, 0, -0.3), (0, 0, H * 0.3), (0.02, 0, H * 0.7), (0, 0, H)], [0.2, 0.15, 0.08, 0.015], 7)
    z = H * 0.16
    level = 0
    while z < H * 0.97:
        t = (z - H * 0.16) / (H * 0.81)
        reach = (1.0 - t) ** 0.85 * H * 0.27 + 0.25
        count = max(4, int(9 - 4 * t))
        for i in range(count):
            a = (i + 0.5 * (level % 2)) / count * math.tau + rnd.uniform(-0.2, 0.2)
            out = np.array([math.cos(a), math.sin(a), 0.0])
            droop = rnd.uniform(0.18, 0.42) * (1.0 - 0.6 * t)
            along = unit(out - np.array([0, 0, droop]))
            side = unit(np.cross(along, np.array([0, 0, 1.0])))
            tilt = rnd.uniform(-0.35, 0.35)
            side = unit(side * math.cos(tilt) + np.cross(along, side) * math.sin(tilt))
            ln = reach * rnd.uniform(0.9, 1.15)
            card(np.array([0, 0, z + rnd.uniform(-0.12, 0.12)]), along, side, unit(out * 0.6 + np.array([0, 0, 0.8])), ln, ln * 0.78)
        z += 0.42 + 0.3 * (1 - t)
        level += 1
    for a in (0.0, math.pi / 2):
        card((0, 0, H - 0.9), (0, 0, 1.0), (math.cos(a), math.sin(a), 0), (math.sin(a), -math.cos(a), 0.3), 1.1, 0.7)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tex = atlas()
    leafy() if KIND == 'yaprakli' else fir()
    me = bpy.data.meshes.new('agac')
    me.from_pydata([tuple(v) for v in V], [], F)
    uv = me.uv_layers.new(name='UVMap')
    for poly in me.polygons:
        for li, vi in zip(poly.loop_indices, poly.vertices):
            uv.data[li].uv = UV[vi]
        poly.use_smooth = True
    me.normals_split_custom_set_from_vertices([tuple(unit(n)) for n in N])
    mat = bpy.data.materials.new('agac')
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    t = nt.nodes.new('ShaderNodeTexImage')
    t.image = bpy.data.images.load(tex)
    nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
    nt.links.new(t.outputs['Alpha'], bsdf.inputs['Alpha'])
    me.materials.append(mat)
    ob = bpy.data.objects.new('agac', me)
    bpy.context.collection.objects.link(ob)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_normals=True, export_animations=False)
    print('yazildi', OUT, len(F), 'yuz', os.path.getsize(OUT) // 1024, 'KB')


main()
