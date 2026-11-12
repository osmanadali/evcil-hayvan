"""Yuksek ayrintili agac modelini oyun icin hafifletir:
  python3 foliage_lod.py girdi.gltf cikti.glb yaprak_orani yaprak_buyutme govde_ucgen
Yapraklar: adacik (tek yaprak/dal) bazinda rastgele bir bolumu tutulur ve buyutulur; govde ve dallar sadelestirilir."""
import bpy, bmesh, sys, random
from mathutils import Vector
src, dst, keep, grow, trunk_tris = sys.argv[-5], sys.argv[-4], float(sys.argv[-3]), float(sys.argv[-2]), int(sys.argv[-1])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
random.seed(3)
objs = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in objs: o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1: bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = obj.data
leaf_slots = {i for i, m in enumerate(obj.material_slots) if any(k in m.name.lower() for k in ('leav', 'leaf', 'twig', 'needle'))}
print('malzemeler', [m.name for m in obj.material_slots], 'yaprak', leaf_slots, 'ucgen', sum(len(p.vertices) - 2 for p in me.polygons))
bm = bmesh.new(); bm.from_mesh(me)
bm.faces.ensure_lookup_table()
# Yaprak adaciklarini bul
seen = set(); drop = []; kept = 0
for f in bm.faces:
    if f.index in seen or f.material_index not in leaf_slots: continue
    stack = [f]; island = []
    seen.add(f.index)
    while stack:
        g = stack.pop(); island.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h.index not in seen and h.material_index in leaf_slots:
                    seen.add(h.index); stack.append(h)
    if random.random() > keep:
        drop += island
    else:
        kept += 1
        verts = {v for g in island for v in g.verts}
        c = sum((v.co for v in verts), Vector()) / len(verts)
        for v in verts: v.co = c + (v.co - c) * grow
bmesh.ops.delete(bm, geom=drop, context='FACES')
bm.to_mesh(me); bm.free()
print('tutulan yaprak adacigi', kept, 'ucgen', sum(len(p.vertices) - 2 for p in me.polygons))
# Govde ve dallari sadelestir: yaprak olmayan yuzleri ayir, decimate et, birlestir
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='DESELECT')
bpy.ops.object.mode_set(mode='OBJECT')
for p in me.polygons: p.select = p.material_index not in leaf_slots
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.separate(type='SELECTED')
bpy.ops.object.mode_set(mode='OBJECT')
parts = [o for o in bpy.data.objects if o.type == 'MESH']
for o in parts:
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    is_trunk = o != obj
    if is_trunk and tris > trunk_tris:
        m = o.modifiers.new('d', 'DECIMATE'); m.ratio = trunk_tris / tris
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier='d')
    for p in o.data.polygons: p.use_smooth = True
bpy.ops.object.select_all(action='DESELECT')
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
print('sonuc ucgen', sum(len(p.vertices) - 2 for p in o.data.polygons), 'boyut', [round(v, 2) for v in o.dimensions])
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=False, export_yup=True)
