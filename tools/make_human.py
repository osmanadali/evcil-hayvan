"""MakeHuman verisinden (CC0) iskeletli insan modeli uretir.

Kullanim: python3 tools/make_human.py <mh_klasoru> <kadin|erkek> <cikti.glb>

<mh_klasoru> icinde:
  mpfb2/src/mpfb/data   (github.com/makehumancommunity/mpfb2: temel govde, hedefler, iskelet)
  assets/               (makehuman_system_assets_cc0.zip: giysi, sac, ten)
Yalnizca veri dosyalari okunur; MakeHuman/MPFB kodu calistirilmaz.
MakeHuman koordinatlari: Y yukari, birim desimetre. Blender: Z yukari, metre.
"""
import gzip
import json
import os
import sys

import bpy
import numpy as np

MH, KIND, OUT = sys.argv[-3:]
DATA = os.path.join(MH, 'mpfb2/src/mpfb/data')
ASSETS = os.path.join(MH, 'assets')

LOOKS = {
    'kadin': {
        'targets': [('macrodetails/caucasian-female-young', 1.0),
                    ('macrodetails/universal-female-young-averagemuscle-averageweight', 1.0)],
        'skin': 'skins/young_caucasian_female/young_lightskinned_female_diffuse.png',
        'parts': [('giysi', 'clothes/female_casualsuit01/female_casualsuit01'),
                  ('ayakkabi', 'clothes/shoes05/shoes05'),
                  ('sac', 'hair/ponytail01/ponytail01'),
                  ('kas', 'eyebrows/eyebrow001/eyebrow001'),
                  ('kirpik', 'eyelashes/eyelashes01/eyelashes01'),
                  ('goz', 'eyes/low-poly/low-poly')],
    },
    'erkek': {
        'targets': [('macrodetails/caucasian-male-young', 1.0),
                    ('macrodetails/universal-male-young-averagemuscle-averageweight', 1.0)],
        'skin': 'skins/young_caucasian_male/young_lightskinned_male_diffuse.png',
        'parts': [('giysi', 'clothes/male_casualsuit06/male_casualsuit06'),
                  ('ayakkabi', 'clothes/shoes06/shoes06'),
                  ('sac', 'hair/short02/short02'),
                  ('kas', 'eyebrows/eyebrow006/eyebrow006'),
                  ('kirpik', 'eyelashes/eyelashes01/eyelashes01'),
                  ('goz', 'eyes/low-poly/low-poly')],
    },
}
RIGID = {'sac': 'Head', 'kas': 'Head', 'kirpik': 'Head', 'goz': 'Head'}
ALPHA = {'sac', 'kas', 'kirpik'}
EYE_TEX = 'eyes/materials/brown_eye.png'


def read_obj(path):
    verts, uvs, faces, group = [], [], [], ''
    for line in open(path, encoding='utf-8', errors='replace'):
        p = line.split()
        if not p:
            continue
        if p[0] == 'v':
            verts.append([float(p[1]), float(p[2]), float(p[3])])
        elif p[0] == 'vt':
            uvs.append((float(p[1]), float(p[2])))
        elif p[0] == 'g':
            group = p[1]
        elif p[0] == 'f':
            vi, ti = [], []
            for c in p[1:]:
                s = c.split('/')
                vi.append(int(s[0]) - 1)
                ti.append(int(s[1]) - 1 if len(s) > 1 and s[1] else -1)
            faces.append((vi, ti, group))
    return np.array(verts), uvs, faces


def to_bl(v):
    v = np.asarray(v)
    return np.stack([v[..., 0], -v[..., 2], v[..., 1]], axis=-1) * 0.1


def find_file(folder, name):
    if name and os.path.exists(os.path.join(folder, name)):
        return os.path.join(folder, name)
    return None


def read_mhmat(path):
    out = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        p = line.split()
        if len(p) >= 2 and p[0] in ('diffuseTexture', 'normalmapTexture'):
            out[p[0]] = find_file(os.path.dirname(path), os.path.basename(p[1]))
    return out


def fix_cloth_texture(path):
    """Tisortteki MakeHuman logosunu siler; kadin tisortunu oyunda renklendirilebilsin diye griye cevirir."""
    from PIL import Image
    im = np.array(Image.open(path).convert('RGB')).astype(np.float32)
    if KIND == 'kadin':
        shirt = np.zeros(im.shape[:2], bool)
        shirt[:870, :] = True
        shirt[1150:1750, 1450:] = True
        lum = im @ np.array([0.3, 0.59, 0.11], np.float32)
        gray = np.clip(lum / lum[200:700, 300:800].mean() * 225.0, 0, 255)
        im[shirt] = gray[shirt][:, None]
        im[345:630, 1460:1790] = im[345:630, 1110:1440]
    else:
        im[240:335, 410:600] = im[360:455, 410:600]
        im[250:420, 915:1280] = im[440:610, 915:1280]
        im[310:365, 1500:1545] = im[310:365, 1440:1485]
    out = os.path.join(os.path.dirname(OUT), KIND + '_giysi.png')
    Image.fromarray(im.astype(np.uint8)).save(out)
    return out


def read_mhclo(path):
    info = {'verts': [], 'delete': [], 'scale': {}}
    mode = ''
    for line in open(path, encoding='utf-8', errors='replace'):
        p = line.split()
        if not p or p[0].startswith('#'):
            continue
        if p[0] == 'verts':
            mode = 'verts'
        elif p[0] == 'delete_verts':
            mode = 'delete'
        elif p[0] in ('x_scale', 'y_scale', 'z_scale'):
            info['scale'][p[0][0]] = (int(p[1]), int(p[2]), float(p[3]))
        elif p[0] in ('obj_file', 'material'):
            info[p[0]] = p[1]
        elif p[0][0].isalpha():
            pass
        elif mode == 'verts':
            info['verts'].append([float(x) for x in p])
        elif mode == 'delete':
            i = 0
            while i < len(p):
                if i + 2 < len(p) and p[i + 1] == '-':
                    info['delete'].extend(range(int(p[i]), int(p[i + 2]) + 1))
                    i += 3
                else:
                    info['delete'].append(int(p[i]))
                    i += 1
    return info


def material(name, tex, normal=None, alpha=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = 0.85
    if tex:
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(tex)
        nt.links.new(t.outputs['Color'], bsdf.inputs['Base Color'])
        if alpha:
            nt.links.new(t.outputs['Alpha'], bsdf.inputs['Alpha'])
            m.blend_method = 'BLEND' if hasattr(m, 'blend_method') else m.blend_method
    if normal:
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(normal)
        t.image.colorspace_settings.name = 'Non-Color'
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nt.links.new(t.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    return m


def make_mesh(name, verts_bl, faces, uvs, mat, weights, arm):
    """faces: (vi, ti); weights: {vertex: {bone: w}}. Kullanilmayan noktalar atilir."""
    used = sorted({i for f in faces for i in f[0]})
    remap = {old: new for new, old in enumerate(used)}
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(verts_bl[i]) for i in used], [], [[remap[i] for i in f[0]] for f in faces])
    uv = me.uv_layers.new(name='UVMap')
    k = 0
    for f in faces:
        for t in f[1]:
            if t >= 0:
                uv.data[k].uv = uvs[t]
            k += 1
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    groups = {}
    for old in used:
        for bone, w in weights.get(old, {}).items():
            if w > 0.001:
                if bone not in groups:
                    groups[bone] = ob.vertex_groups.new(name=bone)
                groups[bone].add([remap[old]], w, 'REPLACE')
    ob.parent = arm
    mod = ob.modifiers.new('Armature', 'ARMATURE')
    mod.object = arm
    return ob


def main():
    look = LOOKS[KIND]
    bpy.ops.wm.read_factory_settings(use_empty=True)

    V, uvs, faces = read_obj(os.path.join(DATA, '3dobjs/base.obj'))
    for rel, w in look['targets']:
        path = os.path.join(DATA, 'targets', rel + '.target.gz')
        if not os.path.exists(path):
            print('hedef yok:', rel)
            continue
        for line in gzip.open(path, 'rt'):
            p = line.split()
            if len(p) == 4 and not p[0].startswith('#'):
                V[int(p[0])] += w * np.array([float(p[1]), float(p[2]), float(p[3])])
    V[:, 1] -= V[[f[0][0] for f in faces if f[2] == 'body'], 1].min()      # ayak tabani y = 0
    VB = to_bl(V)

    # Iskelet
    rig = json.load(open(os.path.join(DATA, 'rigs/standard/rig.mixamo.json')))['bones']
    joints = {}
    for vi, _, g in faces:
        if g.startswith('joint-'):
            joints.setdefault(g, set()).update(vi)

    def place(spec):
        s = spec.get('strategy')
        if s == 'MEAN':
            return VB[spec['vertex_indices']].mean(axis=0)
        if s == 'VERTEX':
            return VB[spec['vertex_index']]
        if s == 'CUBE':
            return VB[sorted(joints[spec['cube_name']])].mean(axis=0)
        raise SystemExit('bilinmeyen strateji: ' + str(s))

    short = lambda n: n.split(':')[-1]
    ad = bpy.data.armatures.new('Iskelet')
    arm = bpy.data.objects.new('Iskelet', ad)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    for name, b in rig.items():
        eb = ad.edit_bones.new(short(name))
        eb.head = place(b['head'])
        eb.tail = place(b['tail'])
        eb.roll = b.get('roll', 0.0)
    for name, b in rig.items():
        if b.get('parent'):
            ad.edit_bones[short(name)].parent = ad.edit_bones[short(b['parent'])]
    bpy.ops.object.mode_set(mode='OBJECT')

    # Agirliklar
    raw = json.load(open(os.path.join(DATA, 'rigs/standard/weights.mixamo.json')))['weights']
    W = {}
    for bone, pairs in raw.items():
        for i, w in pairs:
            W.setdefault(int(i), {})[short(bone)] = float(w)
    body_faces = [f for f in faces if f[2] == 'body']
    body_verts = sorted({i for f in body_faces for i in f[0]})
    from mathutils import kdtree
    kd = kdtree.KDTree(len(body_verts))
    for i in body_verts:
        kd.insert(VB[i], i)
    kd.balance()

    deleted = set()
    for kind, rel in look['parts']:
        folder = os.path.join(ASSETS, os.path.dirname(rel))
        info = read_mhclo(os.path.join(ASSETS, rel + '.mhclo'))
        cv, cuv, cf = read_obj(os.path.join(folder, info['obj_file']))
        sc = {}
        for ax, k in (('x', 0), ('y', 1), ('z', 2)):
            if ax in info['scale']:
                a, b, den = info['scale'][ax]
                sc[k] = abs(V[a][k] - V[b][k]) / den
            else:
                sc[k] = 1.0
        pos = np.zeros((len(info['verts']), 3))
        cw = {}
        for n, row in enumerate(info['verts']):
            if len(row) == 1:
                ids, ws, off = [int(row[0])], [1.0], np.zeros(3)
            else:
                ids = [int(row[0]), int(row[1]), int(row[2])]
                ws = row[3:6]
                off = np.array([row[6] * sc[0], row[7] * sc[1], row[8] * sc[2]])
            pos[n] = sum(w * V[i] for i, w in zip(ids, ws)) + off
            if kind in RIGID:
                cw[n] = {RIGID[kind]: 1.0}
                continue
            acc = {}
            for i, w in zip(ids, ws):
                for bone, bw in W.get(i, {}).items():
                    acc[bone] = acc.get(bone, 0.0) + max(w, 0.0) * bw
            if not acc:
                acc = dict(W.get(kd.find(to_bl(pos[n]))[1], {}))
            top = sorted(acc.items(), key=lambda kv: -kv[1])[:4]
            tot = sum(w for _, w in top) or 1.0
            cw[n] = {bone: w / tot for bone, w in top}
        mm = read_mhmat(os.path.join(folder, info['material'])) if 'material' in info else {}
        tex = mm.get('diffuseTexture')
        if kind == 'goz':
            tex = os.path.join(ASSETS, EYE_TEX)
        if kind == 'giysi':
            tex = fix_cloth_texture(tex)
        mat = material(kind, tex, mm.get('normalmapTexture'), kind in ALPHA)
        make_mesh(kind, to_bl(pos), [(f[0], f[1]) for f in cf], cuv, mat, cw, arm)
        if kind in ('giysi', 'ayakkabi'):
            deleted.update(info['delete'])
        print(kind, len(pos), 'nokta', len(cf), 'yuz', 'silinen', len(info['delete']))

    keep = [(f[0], f[1]) for f in body_faces if not any(i in deleted for i in f[0])]
    skin = material('ten', os.path.join(ASSETS, look['skin']))
    make_mesh('govde', VB, keep, uvs, skin, W, arm)
    print('govde', len(keep), 'yuz; boy', round(float(VB[body_verts, 2].max()), 3), 'm')

    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_skins=True,
                              export_animations=False, export_apply=False)
    print('yazildi', OUT, os.path.getsize(OUT) // 1024, 'KB')


main()
