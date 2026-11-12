"""Modeli sadelestirir: python3 decimate_glb.py girdi.glb cikti.glb hedef_ucgen"""
import bpy, sys
src, dst, target = sys.argv[-3], sys.argv[-2], int(sys.argv[-1])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in [o for o in bpy.data.objects if o.type == 'MESH']:
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    if tris > target:
        m = o.modifiers.new('d', 'DECIMATE'); m.ratio = target / tris
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier='d')
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=False, export_yup=True)
