"""Oyuncunun surdugu ayrintili araba modellerini oyuna hazirlar (Blender gerekmez; numpy + Pillow).

Kullanim: python3 tools/build_vehicles.py        (repo kokunden)
  modeller/hatchback_kapili.glb -> assets/vehicles/hatchback.glb
  modeller/sedan_ic_mekanli.glb -> assets/vehicles/sedan.glb

Kaynak modellerde parcalar malzemeye gore birlestirilmis (kapilar, tekerler ayri dugum degil). Bu arac
her yuzeyi bagli parcalarina (komsu ucgen kumeleri) ayirir, parcalari konum / sinir kutusuna gore
siniflandirir ve oyunun arac uzayinda (metre; on = -Z, sag = +X, yer y = 0, merkez x = z = 0) adli
dugumler halinde yeniden yazar:
  Govde                       : sabit her sey (govde, ic mekan, camlar)
  KapiSol / KapiSag           : kapi (dis sac, ic doseme, kol, cam); eksen = on kenardaki dikey mentese
  Bagaj                       : bagaj kapagi (ust kenardan menteseli)
  TekerOnSol/OnSag/ArkaSol/ArkaSag : tekerler (eksen = teker merkezi; X ekseninde doner)
  FrenOnSol / FrenOnSag       : on fren diski / kaliper (yalniz dumenle doner)
  Direksiyon                  : simit (eksen = simit merkezi; yerel +Z surucuye bakan kolon ekseni)
  AynaSol / AynaSag / AynaIc  : ayna camlari (yerel +Z ayna yuzeyinin baktigi yon)
  Ekran / Gosterge            : orta ekran ve gosterge yuzeyi (sedan)
Marka amblemleri (sedan) atilir.
"""
import json
import struct
import io
import sys

import numpy as np
from PIL import Image

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


class Glb:
    def __init__(self, path):
        d = open(path, 'rb').read()
        ln, _ = struct.unpack('<II', d[12:20])
        self.j = json.loads(d[20:20 + ln])
        o = 20 + ln
        l2, _ = struct.unpack('<II', d[o:o + 8])
        self.bin = d[o + 8:o + 8 + l2]
        self.mats = self._node_mats()

    def view(self, i):
        bv = self.j['bufferViews'][i]
        o = bv.get('byteOffset', 0)
        return self.bin[o:o + bv['byteLength']]

    def acc(self, i):
        a = self.j['accessors'][i]
        bv = self.j['bufferViews'][a['bufferView']]
        dt = np.dtype(CT[a['componentType']])
        n = NC[a['type']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride', 0)
        if stride and stride != dt.itemsize * n:
            raw = np.frombuffer(self.bin, dtype=np.uint8, count=stride * (a['count'] - 1) + dt.itemsize * n, offset=off)
            idx = (np.arange(a['count'])[:, None] * stride + np.arange(dt.itemsize * n)[None, :]).ravel()
            arr = np.frombuffer(raw[idx].tobytes(), dtype=dt).reshape(a['count'], n)
        else:
            arr = np.frombuffer(self.bin, dtype=dt, count=a['count'] * n, offset=off).reshape(a['count'], n)
        if a.get('normalized'):
            arr = arr.astype(np.float64) / np.iinfo(dt).max
        return arr.copy()

    def _node_mats(self):
        out = {}

        def mat(n):
            if 'matrix' in n:
                return np.array(n['matrix']).reshape(4, 4).T
            T = np.eye(4)
            if 'translation' in n:
                T[:3, 3] = n['translation']
            R = np.eye(4)
            if 'rotation' in n:
                x, y, z, w = n['rotation']
                R[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                             [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                             [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
            S = np.eye(4)
            if 'scale' in n:
                S[0, 0], S[1, 1], S[2, 2] = n['scale']
            return T @ R @ S

        def walk(i, M):
            W = M @ mat(self.j['nodes'][i])
            out[i] = W
            for c in self.j['nodes'][i].get('children', []):
                walk(c, W)
        for r in self.j['scenes'][self.j.get('scene', 0)]['nodes']:
            walk(r, np.eye(4))
        return out

    def prims(self):
        """Her yuzey: (dugum adi, malzeme no, konum, normal, uv ya da None, ucgenler) - sahne uzayinda."""
        for ni, n in enumerate(self.j['nodes']):
            if 'mesh' not in n or ni not in self.mats:
                continue
            W = self.mats[ni]
            for p in self.j['meshes'][n['mesh']]['primitives']:
                pos = self.acc(p['attributes']['POSITION']).astype(np.float64) @ W[:3, :3].T + W[:3, 3]
                if 'NORMAL' in p['attributes']:
                    nrm = self.acc(p['attributes']['NORMAL']).astype(np.float64) @ np.linalg.inv(W[:3, :3])
                    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
                else:
                    nrm = np.zeros_like(pos)
                    nrm[:, 1] = 1.0
                uv = self.acc(p['attributes']['TEXCOORD_0']).astype(np.float64) if 'TEXCOORD_0' in p['attributes'] else None
                idx = self.acc(p['indices']).ravel().astype(np.int64) if 'indices' in p else np.arange(len(pos))
                yield n.get('name', ''), p.get('material', 0), pos, nrm, uv, idx.reshape(-1, 3)


def components(pos, tris, tol=1e-4):
    """Kaynakli koselere gore bagli parcalar: her ucgen icin etiket."""
    key = np.round(pos / tol).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.ravel()
    parent = np.arange(inv.max() + 1)

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    t = inv[tris]
    for a, b, c in t:
        ra, rb, rc = find(a), find(b), find(c)
        if ra != rb:
            parent[rb] = ra
        if ra != rc:
            parent[find(rc)] = ra
    return np.array([find(x) for x in t[:, 0]])


def clip(pos, nrm, uv, tris, axis, value):
    """Ucgenleri pos[axis] = value duzleminde keser: (alt taraf ucgenleri, ust taraf ucgenleri) + yeni koseler."""
    P, N = list(pos), list(nrm)
    U = list(uv) if uv is not None else None
    lo, hi = [], []
    cache = {}

    def cut(a, b):
        k = (min(a, b), max(a, b))
        if k not in cache:
            t = (value - P[a][axis]) / (P[b][axis] - P[a][axis])
            P.append(P[a] + (P[b] - P[a]) * t)
            n = N[a] + (N[b] - N[a]) * t
            N.append(n / max(np.linalg.norm(n), 1e-9))
            if U is not None:
                U.append(U[a] + (U[b] - U[a]) * t)
            cache[k] = len(P) - 1
        return cache[k]
    for tri in tris:
        s = [P[i][axis] >= value for i in tri]
        if all(s):
            hi.append(list(tri))
        elif not any(s):
            lo.append(list(tri))
        else:
            # Tek kalan koseyi basa al
            k = [i for i in range(3) if s[i] != s[(i + 1) % 3] and s[i] != s[(i + 2) % 3]][0]
            a, b, c = tri[k], tri[(k + 1) % 3], tri[(k + 2) % 3]
            ab, ac = cut(a, b), cut(a, c)
            one, two = [[a, ab, ac]], [[ab, b, c], [ab, c, ac]]
            if s[k]:
                hi += one
                lo += two
            else:
                lo += one
                hi += two
    return (np.array(P), np.array(N), np.array(U) if U is not None else None,
            np.array(lo, dtype=np.int64).reshape(-1, 3), np.array(hi, dtype=np.int64).reshape(-1, 3))


class Builder:
    """Parcalari toplar ve GLB yazar."""

    def __init__(self, src, turn, length):
        self.g = Glb(src)
        self.parts = {}        # ad -> {malzeme: [(pos, nrm, uv, tris)]}
        lo = np.full(3, 1e9)
        hi = -lo
        for _, _, pos, _, _, _ in self.g.prims():
            lo = np.minimum(lo, pos.min(0))
            hi = np.maximum(hi, pos.max(0))
        self.k = length / (hi[2] - lo[2])
        self.c = np.array([(lo[0] + hi[0]) * 0.5, lo[1], (lo[2] + hi[2]) * 0.5])
        self.s = -1.0 if turn else 1.0
        self.frames = {}       # ad -> (merkez, 3x3 eksenler) (oyun uzayinda)

    def to_game(self, p):
        q = (p - self.c) * self.k
        q[..., 0] *= self.s
        q[..., 2] *= self.s
        return q

    def dir_game(self, n):
        q = n.copy()
        q[..., 0] *= self.s
        q[..., 2] *= self.s
        return q

    def add(self, part, mat, pos, nrm, uv, tris):
        if len(tris) == 0:
            return
        used, inv = np.unique(tris, return_inverse=True)
        self.parts.setdefault(part, {}).setdefault(mat, []).append(
            (self.to_game(pos[used]), self.dir_game(nrm[used]), uv[used] if uv is not None else None, inv.reshape(-1, 3)))

    def verts(self, part):
        return np.concatenate([a[0] for lst in self.parts[part].values() for a in lst])

    def write(self, dst, max_tex=1024):
        g = self.g
        out = {'asset': {'version': '2.0', 'generator': 'tools/build_vehicles.py'}, 'scene': 0, 'scenes': [{'nodes': []}],
               'nodes': [], 'meshes': [], 'accessors': [], 'bufferViews': [], 'buffers': [{}]}
        for key in ('materials', 'textures', 'samplers', 'extensionsUsed', 'extensionsRequired'):
            if key in g.j:
                out[key] = json.loads(json.dumps(g.j[key]))
        blob = bytearray()

        def push(data, target=None):
            while len(blob) % 4:
                blob.append(0)
            bv = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)}
            if target:
                bv['target'] = target
            blob.extend(data)
            out['bufferViews'].append(bv)
            return len(out['bufferViews']) - 1

        def accessor(arr, ctype, kind, target, minmax=False):
            a = {'bufferView': push(arr.tobytes(), target), 'componentType': ctype, 'count': len(arr), 'type': kind}
            if minmax:
                a['min'] = arr.min(0).tolist()
                a['max'] = arr.max(0).tolist()
            out['accessors'].append(a)
            return len(out['accessors']) - 1
        # Dokular: renk dokulari max_tex, ayrinti (normal / puruzluluk) dokulari yarisi; saydam olmayanlar JPEG
        if 'images' in g.j:
            color = set()
            for m in g.j.get('materials', []):
                for slot in (m.get('pbrMetallicRoughness', {}).get('baseColorTexture'), m.get('emissiveTexture')):
                    if slot:
                        color.add(g.j['textures'][slot['index']]['source'])
            out['images'] = []
            for i, im in enumerate(g.j['images']):
                data = g.view(im['bufferView'])
                mime = im.get('mimeType', 'image/png')
                pil = Image.open(io.BytesIO(data))
                lim = max_tex if i in color else max_tex // 2
                if max(pil.size) > lim or (len(data) > 150000 and mime == 'image/png'):
                    r = min(1.0, lim / max(pil.size))
                    pil = pil.resize((max(1, int(pil.size[0] * r)), max(1, int(pil.size[1] * r))), Image.LANCZOS)
                    buf = io.BytesIO()
                    if pil.mode in ('RGBA', 'LA') or 'transparency' in pil.info:
                        pil.save(buf, 'PNG', optimize=True)
                    else:
                        pil.convert('RGB').save(buf, 'JPEG', quality=90)
                        mime = 'image/jpeg'
                    data = buf.getvalue()
                out['images'].append({'bufferView': push(data), 'mimeType': mime, 'name': im.get('name', 'doku%d' % len(out['images']))})
        for name in sorted(self.parts):
            center, axes = self.frames.get(name, (np.zeros(3), np.eye(3)))
            prims = []
            for mat in sorted(self.parts[name]):
                lst = self.parts[name][mat]
                has_uv = any(a[2] is not None for a in lst)
                P, N, U, T = [], [], [], []
                base = 0
                for pos, nrm, uv, tris in lst:
                    P.append((pos - center) @ axes)       # yerel = eksenler^T * (p - merkez)
                    N.append(nrm @ axes)
                    U.append(uv if uv is not None else np.zeros((len(pos), 2)))
                    T.append(tris + base)
                    base += len(pos)
                P = np.concatenate(P).astype(np.float32)
                N = np.concatenate(N).astype(np.float32)
                T = np.concatenate(T).astype(np.uint32).ravel()
                attrs = {'POSITION': accessor(P, 5126, 'VEC3', 34962, True), 'NORMAL': accessor(N, 5126, 'VEC3', 34962)}
                if has_uv:
                    attrs['TEXCOORD_0'] = accessor(np.concatenate(U).astype(np.float32), 5126, 'VEC2', 34962)
                prims.append({'attributes': attrs, 'indices': accessor(T, 5125, 'SCALAR', 34963), 'material': int(mat)})
            out['meshes'].append({'name': name, 'primitives': prims})
            node = {'name': name, 'mesh': len(out['meshes']) - 1, 'translation': [float(v) for v in center]}
            if name in self.frames and not np.allclose(axes, np.eye(3)):
                node['rotation'] = quat(axes)
            out['nodes'].append(node)
            out['scenes'][0]['nodes'].append(len(out['nodes']) - 1)
        while len(blob) % 4:
            blob.append(0)
        out['buffers'][0]['byteLength'] = len(blob)
        js = json.dumps(out, separators=(',', ':')).encode()
        while len(js) % 4:
            js += b' '
        with open(dst, 'wb') as f:
            f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
            f.write(struct.pack('<II', len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack('<II', len(blob), 0x004E4942))
            f.write(blob)
        tris = sum(len(a[3]) for p in self.parts.values() for lst in p.values() for a in lst)
        print('%s: %d parca, %d ucgen, %.1f MB' % (dst, len(self.parts), tris, (len(js) + len(blob)) / 1e6))
        for name in sorted(self.parts):
            v = self.verts(name)
            print('   %-12s merkez=%s  kutu %s .. %s' % (name, np.round(self.frames.get(name, (np.zeros(3),))[0], 3).tolist(),
                                                        np.round(v.min(0), 3).tolist(), np.round(v.max(0), 3).tolist()))


def quat(m):
    """3x3 donme (sutunlar = yerel eksenler) -> [x, y, z, w]"""
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    return [float(v) for v in q]


def facing_frame(v, toward):
    """Duz / halka bicimli parcanin ekseni: +Z = en ince yon ('toward' tarafina bakan), +X yatay."""
    c = (v.min(0) + v.max(0)) * 0.5
    w, e = np.linalg.eigh(np.cov((v - v.mean(0)).T))
    z = e[:, 0]
    if z @ toward < 0:
        z = -z
    x = np.cross([0, 1, 0], z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return c, np.stack([x, y, z], axis=1)


def center_frame(v):
    return (v.min(0) + v.max(0)) * 0.5, np.eye(3)


def inside(lo, hi, blo, bhi):
    return bool(np.all(lo >= np.array(blo)) and np.all(hi <= np.array(bhi)))


# ------------------------------------------------------------------ hatchback (Ariel hatchback V2, gandoplyas)

def build_hatchback(src, dst):
    b = Builder(src, True, 3.97)
    g = b.g
    names = [m['name'] for m in g.j['materials']]
    # Kaynak uzayi: on = +Z, sol = +X. Teker merkezleri (jant kutularindan), kapi kutusu.
    wheels = {'TekerOnSol': (0.905, 0.03, 1.985), 'TekerOnSag': (-0.905, 0.03, 1.985),
              'TekerArkaSol': (0.93, 0.015, -0.305), 'TekerArkaSag': (-0.93, 0.015, -0.305)}
    DOOR_Z = (0.085, 1.235)

    def wheel_of(lo, hi, rad, xin):
        c = (lo + hi) * 0.5
        for nm, w in wheels.items():
            if c[0] * w[0] > 0 and lo[0] * hi[0] > 0 and min(abs(lo[0]), abs(hi[0])) > xin and \
                    max(abs(lo[1] - w[1]), abs(hi[1] - w[1]), abs(lo[2] - w[2]), abs(hi[2] - w[2])) < rad:
                return nm
        return None
    for node, mat, pos, nrm, uv, tris in g.prims():
        mn = names[mat]
        lab = components(pos, tris)
        for l in np.unique(lab):
            tt = tris[lab == l]
            v = pos[np.unique(tt)]
            lo, hi = v.min(0), v.max(0)
            side = 'Sol' if (lo[0] + hi[0]) > 0 else 'Sag'
            part = 'Govde'
            if mn in ('rims.013', 'tyres.005') or (mn == 'plactic' and wheel_of(lo, hi, 0.2, 0.9)):
                part = wheel_of(lo, hi, 0.45, 0.6) or 'Govde'
            elif mn == 'metal' and wheel_of(lo, hi, 0.3, 0.68):
                w = wheel_of(lo, hi, 0.3, 0.68)
                part = w.replace('Teker', 'Fren') if 'On' in w else 'Govde'
            elif mn == 'mirror':
                part = 'Ayna' + side
            elif node == 'Object_13':
                part = 'Direksiyon'
            elif mn == 'windshield':
                if hi[2] < 0.0 and abs(lo[0] + hi[0]) < 0.1:
                    part = 'Bagaj'
                elif abs(lo[0] + hi[0]) > 0.5:
                    # Yan cam: kapinin ustunde kalan bolum kapiyla acilir
                    P, N, U, t_lo, t_hi = clip(pos, nrm, uv, tt, 2, DOOR_Z[0])
                    b.add('Govde', mat, P, N, U, t_lo)
                    P, N, U, t_mid, t_hi = clip(P, N, U, t_hi, 2, DOOR_Z[1])
                    b.add('Kapi' + side, mat, P, N, U, t_mid)
                    b.add('Govde', mat, P, N, U, t_hi)
                    continue
            elif mn == 'body' and node == 'Object_9' and lo[2] < -0.05 and abs(lo[0] + hi[0]) < 0.1:
                part = 'Bagaj'          # bagaj kapagi ve ustundeki ruzgarlik
            elif min(abs(lo[0]), abs(hi[0])) > 0.74 and max(abs(lo[0]), abs(hi[0])) < 1.02 and \
                    lo[2] > DOOR_Z[0] and hi[2] < DOOR_Z[1] and lo[1] > -0.04 and hi[1] < 0.62 and mn != 'plactic' or \
                    (mn == 'plactic' and len(tt) == 192 and min(abs(lo[0]), abs(hi[0])) > 0.8 and lo[1] > 0.3):
                part = 'Kapi' + side    # dis sac, ic doseme, kapi kolu
            b.add(part, mat, pos, nrm, uv, tt)
    for nm in list(b.parts):
        v = b.verts(nm)
        if nm.startswith('Teker') or nm.startswith('Fren'):
            w = wheels[nm.replace('Fren', 'Teker')]
            b.frames[nm] = (b.to_game(np.array(w, dtype=np.float64)), np.eye(3))
        elif nm.startswith('Kapi'):
            # Mentese: kapinin on kenarinda (oyun uzayinda en kucuk z), dis sacin hemen icinde, dikey
            front = v[v[:, 2] < v[:, 2].min() + 0.04]
            sx = np.sign(front[:, 0].mean())
            b.frames[nm] = (np.array([sx * (np.abs(front[:, 0]).max() - 0.03), 0.0, v[:, 2].min() + 0.02]), np.eye(3))
        elif nm == 'Bagaj':
            top = v[v[:, 1] > v[:, 1].max() - 0.05]
            b.frames[nm] = (np.array([0.0, v[:, 1].max() - 0.02, top[:, 2].min()]), np.eye(3))
        elif nm == 'Direksiyon':
            rim = max(b.parts[nm][names.index('interior')], key=lambda a: np.ptp(a[0][:, 0]))[0]
            b.frames[nm] = facing_frame(rim, np.array([0, 0.2, 1.0]))
        elif nm.startswith('Ayna'):
            b.frames[nm] = facing_frame(v, np.array([0, 0, 1.0]))
    b.write(dst)


# ------------------------------------------------------------------ sedan (Armored Wave)

def build_sedan(src, dst):
    b = Builder(src, True, 4.55)
    g = b.g
    names = [m['name'] for m in g.j['materials']]
    for node, mat, pos, nrm, uv, tris in g.prims():
        lab = components(pos, tris)
        for l in np.unique(lab):
            tt = tris[lab == l]
            v = pos[np.unique(tt)]
            lo, hi = v.min(0), v.max(0)
            c = (lo + hi) * 0.5
            part = 'Govde'
            if '_wheels_' in node:
                part = 'Teker' + ('On' if c[2] > 0 else 'Arka') + ('Sol' if c[0] > 0 else 'Sag')
            elif '_steering_wheel_' in node:
                part = 'Direksiyon'
                if names[mat] == 'main_paint' and hi[1] - lo[1] < 0.07 and lo[1] > 0.8:
                    continue            # simit gobegindeki marka amblemi
            elif node.endswith('body_miror_0'):
                part = 'Ayna' + ('Sol' if c[0] > 0 else 'Sag')
            elif node.endswith('interior1_miror_0'):
                part = 'AynaIc'
            elif node.endswith('dashboard.001_screen_0'):
                part = 'Ekran'
            elif node.endswith('dashboard_M_dashboard.001_0'):
                part = 'Gosterge'
            elif node.endswith('body_main_paint_0'):
                # Krom amblemler: ondeki ve arkadaki logo, bagajdaki marka / model yazilari
                if abs(c[0]) < 0.02 and hi[0] - lo[0] < 0.2 and abs(c[2]) > 2.0:
                    continue
                if lo[2] < -1.9 and hi[1] - lo[1] < 0.04 and hi[0] - lo[0] < 0.08 and lo[1] > 0.88:
                    continue
            b.add(part, mat, pos, nrm, uv, tt)
    for nm in list(b.parts):
        v = b.verts(nm)
        if nm.startswith('Teker'):
            c, axes = center_frame(v)
            c[0] = np.sign(c[0]) * (np.abs(v[:, 0]).max() - 0.12)      # lastigin ortasi (aks mili haric)
            b.frames[nm] = (c, axes)
        elif nm == 'Direksiyon':
            rim = max(b.parts[nm][names.index('M_Steering_wheel')], key=lambda a: np.ptp(a[0][:, 0]))[0]
            b.frames[nm] = facing_frame(rim, np.array([0, 0.2, 1.0]))
        elif nm.startswith('Ayna') or nm in ('Ekran', 'Gosterge'):
            b.frames[nm] = facing_frame(v, np.array([0, 0, 1.0]))
    b.write(dst)


if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'hepsi'
    if which in ('hepsi', 'hatchback'):
        build_hatchback('modeller/hatchback_kapili.glb', 'assets/vehicles/hatchback.glb')
    if which in ('hepsi', 'sedan'):
        build_sedan('modeller/sedan_ic_mekanli.glb', 'assets/vehicles/sedan.glb')
