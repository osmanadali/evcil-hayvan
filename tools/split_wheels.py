"""Arac modelinde tekerlekleri bulur ve ayri parca yapar (oyunda donebilsinler).

Kullanim: python3 tools/split_wheels.py girdi.glb cikti.glb <2|4> [yaricap/boy orani]

Tekerlekler modelin en alt noktalarindan bulunur: yere degen kumeler (on/arka, araba icin sag/sol),
yan gorunuste bu noktadan gecen cember taranir ve en cok noktanin oturdugu yaricap secilir.
Cemberin icindeki yuzler ayri nesneye alinir; nesnenin merkezi teker merkezidir ve adi
wheel_<eksen>_<sira> olur (eksen: tekerin dondugu yatay eksen, x ya da y; Blender koordinatlari).
"""
import sys

import bpy
import bmesh  # noqa: E402  (bpy'den sonra yuklenmeli)
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
src, dst, count = args[0], args[1], int(args[2])
ratio = float(args[3]) if len(args) > 3 else 0.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
mesh = max([o for o in bpy.data.objects if o.type == 'MESH'], key=lambda o: len(o.data.vertices))
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
P = np.array([v.co[:] for v in mesh.data.vertices])
lo, hi = P.min(0), P.max(0)
along = 0 if (hi[0] - lo[0]) > (hi[1] - lo[1]) else 1      # aracin uzun ekseni
side = 1 - along
L = hi[along] - lo[along]
W = hi[side] - lo[side]
H = hi[2] - lo[2]
ground = P[:, 2] < lo[2] + 0.025 * H

wheels = []
ends = [lo[along] + L * 0.5 - 1e-6]
for e, sel in enumerate([P[:, along] < lo[along] + L * 0.5, P[:, along] >= lo[along] + L * 0.5]):
    g = ground & sel
    if g.sum() < 3:
        continue
    sides = [g] if count == 2 else [g & (P[:, side] < (lo[side] + hi[side]) / 2), g & (P[:, side] >= (lo[side] + hi[side]) / 2)]
    for gs in sides:
        if gs.sum() < 3:
            continue
        c_al = float(np.median(P[gs, along]))
        s_lo, s_hi = float(P[gs, side].min()), float(P[gs, side].max())
        if count == 2:
            s_lo, s_hi = s_lo - 0.02 * W, s_hi + 0.02 * W
        else:
            mid = (lo[side] + hi[side]) / 2
            s_lo, s_hi = (s_lo - 0.06 * W, min(s_hi + 0.06 * W, mid)) if s_hi <= mid + 1e-6 else (max(s_lo - 0.06 * W, mid), s_hi + 0.06 * W)
        band = (P[:, side] > s_lo) & (P[:, side] < s_hi)
        best = (0, None)
        for r in np.linspace(0.06 * L, 0.24 * L, 40):
            d = np.hypot(P[band, along] - c_al, P[band, 2] - (lo[2] + r))
            score = np.sum(np.abs(d - r) < 0.012 * L) / r
            if score > best[0]:
                best = (score, r)
        r = float(best[1]) if ratio <= 0.0 else ratio * L
        wheels.append((c_al, lo[2] + r, r, s_lo, s_hi))
print('tekerlek', len(wheels), [(round(w[0], 3), round(w[2], 3)) for w in wheels])

bm = bmesh.new()
bm.from_mesh(mesh.data)
bm.verts.ensure_lookup_table()
for i, (c_al, c_z, r, s_lo, s_hi) in enumerate(wheels):
    def inside(v):
        co = v.co
        return np.hypot(co[along] - c_al, co[2] - c_z) < r * 1.04 and s_lo < co[side] < s_hi
    faces = [f for f in bm.faces if all(inside(v) for v in f.verts)]
    if not faces:
        continue
    nb = bmesh.new()
    vmap = {}
    uv_src = bm.loops.layers.uv.active
    uv_dst = nb.loops.layers.uv.new('UVMap') if uv_src else None
    for f in faces:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = nb.verts.new(v.co)
            vs.append(vmap[v])
        try:
            nf = nb.faces.new(vs)
        except ValueError:
            continue
        nf.material_index = f.material_index
        nf.smooth = f.smooth
        if uv_src:
            for la, lb in zip(f.loops, nf.loops):
                lb[uv_dst].uv = la[uv_src].uv
    bmesh.ops.delete(bm, geom=faces, context='FACES_ONLY')
    # Teker merkezi: ayrilan noktalarin sinir kutusunun ortasi (yaricap tahmininden daha dogru; yalpalamaz)
    co = np.array([v.co[:] for v in nb.verts])
    mid = (co.min(0) + co.max(0)) / 2
    c_al, c_z = float(mid[along]), float(mid[2])
    me = bpy.data.meshes.new('wheel')
    nb.to_mesh(me)
    for m in mesh.data.materials:
        me.materials.append(m)
    center = Vector((0.0, 0.0, c_z))
    center[along] = c_al
    center[side] = float(mid[side])
    me.transform(__import__('mathutils').Matrix.Translation(-center))
    ob = bpy.data.objects.new('wheel_%s_%d' % ('xy'[side], i), me)
    ob.location = center
    bpy.context.collection.objects.link(ob)
bm.to_mesh(mesh.data)
bm.free()
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_yup=True, export_animations=False)
print('yazildi', dst)
