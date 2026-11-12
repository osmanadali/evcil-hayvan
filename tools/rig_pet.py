"""Tripo modeline iskelet takar.
  python3 rig_pet.py <ad> girdi.glb cikti.glb      -> iskeletli GLB
  python3 rig_pet.py <ad> girdi.glb noktalar.npy   -> yalnizca hizalanmis noktalari yazar (kemik yerlestirmek icin)
Model once hizalanir: Z yukari, -Y on, ayaklar z=0, govde ortada."""
import bpy, sys, math, json, os
import numpy as np
from mathutils import Vector, Matrix

name, src, dst = sys.argv[-3], sys.argv[-2], sys.argv[-1]
CFG = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rig_pets.json')))[name]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
mesh = max([o for o in bpy.data.objects if o.type == 'MESH'], key=lambda o: len(o.data.vertices))
mw = mesh.matrix_world.copy()
mesh.parent = None
mesh.matrix_world = mw
for m in list(mesh.modifiers): mesh.modifiers.remove(m)
mesh.vertex_groups.clear()
for o in list(bpy.data.objects):
    if o != mesh: bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.objects.active = mesh
mesh.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mesh.data.transform(Matrix.Rotation(math.radians(CFG['turn']), 4, 'Z'))
P = np.array([v.co[:] for v in mesh.data.vertices])
s = CFG.get('length', 1.0) / (P[:, 1].max() - P[:, 1].min())
off = Vector((-(P[:, 0].max() + P[:, 0].min()) / 2, -(P[:, 1].max() + P[:, 1].min()) / 2, -P[:, 2].min()))
mesh.data.transform(Matrix.Scale(s, 4) @ Matrix.Translation(off))
mesh.data.update()
mesh.name = name
P = np.array([v.co[:] for v in mesh.data.vertices])
if dst.endswith('.npy'):
    np.save(dst, P); sys.exit(0)

bones = CFG['bones']   # [ad, ebeveyn, bas, kuyruk]
arm = bpy.data.armatures.new('Iskelet')
ao = bpy.data.objects.new('Iskelet', arm)
bpy.context.scene.collection.objects.link(ao)
bpy.ops.object.select_all(action='DESELECT')
bpy.context.view_layer.objects.active = ao
bpy.ops.object.mode_set(mode='EDIT')
for bname, parent, h, t in bones:
    b = arm.edit_bones.new(bname)
    b.head, b.tail = Vector(h), Vector(t)
    b.use_deform = bname != 'root'
    if parent: b.parent = arm.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')

# Agirliklar: her kose en yakin kemiklere mesafenin tersiyle baglanir.
# "limits": kemik on eki -> [eksen, yon, esik, ceza]; kemigin etkisini bir bolgeyle sinirlar.
def segdist(a, b):
    a, b = np.array(a), np.array(b); ab = b - a
    t = np.clip(((P - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
names, D = [], []
for bname, parent, h, t in bones:
    if bname == 'root': continue
    d = segdist(h, t)
    for prefix, rules in CFG.get('limits', {}).items():
        if bname.startswith(prefix):
            for axis, sign, thr, pen in rules:
                val = np.abs(P[:, abs(axis) - 1]) if axis < 0 else P[:, axis]
                d = d + np.maximum(0, (thr - val) * sign) * pen
    d = d * CFG.get('reach', {}).get(bname, 1.0)
    names.append(bname); D.append(d)
D = np.array(D).T
W = 1.0 / (D + 0.01) ** 5
keep = np.argsort(-W, axis=1)[:, :4]
mask = np.zeros_like(W); np.put_along_axis(mask, keep, 1, axis=1)
W = W * mask; W /= W.sum(1, keepdims=True); W[W < 0.02] = 0; W /= W.sum(1, keepdims=True)
for j, bname in enumerate(names):
    g = mesh.vertex_groups.new(name=bname)
    for i in np.nonzero(W[:, j])[0]:
        g.add([int(i)], float(W[i, j]), 'REPLACE')
mesh.parent = ao
mod = mesh.modifiers.new('Armature', 'ARMATURE'); mod.object = ao
print('AGIRLIK', {n: int((W[:, j] > 0.5).sum()) for j, n in enumerate(names)})
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=False, export_skins=True, export_yup=True)
