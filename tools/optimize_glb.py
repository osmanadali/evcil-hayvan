"""GLB kucultucu: yalnizca renk dokusunu tutar ve kucultur.
kullanim: python3 optimize_glb.py girdi.glb cikti.glb [doku_boyutu]"""
import sys, struct, json, io
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
size = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
d = open(src, 'rb').read()
clen = struct.unpack('<I', d[12:16])[0]
j = json.loads(d[20:20 + clen])
bin0 = d[20 + clen + 8:]
views = j['bufferViews']

def view_bytes(i):
    v = views[i]
    o = v.get('byteOffset', 0)
    return bin0[o:o + v['byteLength']]

out = bytearray()
new_views = []
def add(data, extra=None):
    while len(out) % 4: out.append(0)
    nv = {'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data)}
    if extra: nv.update(extra)
    out.extend(data)
    new_views.append(nv)
    return len(new_views) - 1

remap = {}
for a in j['accessors']:
    if 'bufferView' in a:
        i = a['bufferView']
        if i not in remap:
            remap[i] = add(view_bytes(i), {k: views[i][k] for k in ('byteStride', 'target') if k in views[i]})
        a['bufferView'] = remap[i]
for s in j.get('skins', []):
    pass  # inverseBindMatrices bir accessor, yukarida tasindi

images, textures = [], []
for m in j.get('materials', []):
    pbr = m.setdefault('pbrMetallicRoughness', {})
    bc = pbr.get('baseColorTexture')
    for k in ('normalTexture', 'occlusionTexture', 'emissiveTexture'): m.pop(k, None)
    pbr.pop('metallicRoughnessTexture', None)
    pbr['metallicFactor'] = 0.0
    pbr['roughnessFactor'] = 0.9
    m.pop('extensions', None)
    if bc:
        img = j['images'][j['textures'][bc['index']]['source']]
        im = Image.open(io.BytesIO(view_bytes(img['bufferView']))).convert('RGB')
        if max(im.size) > size: im = im.resize((size, size), Image.LANCZOS)
        buf = io.BytesIO(); im.save(buf, 'JPEG', quality=88)
        images.append({'bufferView': add(buf.getvalue()), 'mimeType': 'image/jpeg'})
        textures.append({'source': len(images) - 1, 'sampler': 0})
        pbr['baseColorTexture'] = {'index': len(textures) - 1}
j['images'], j['textures'] = images, textures
j['samplers'] = [{'magFilter': 9729, 'minFilter': 9987}]
j['bufferViews'] = new_views
j.pop('extensionsUsed', None); j.pop('extensionsRequired', None)
for p in [p for m in j['meshes'] for p in m['primitives']]: p.pop('extensions', None)
while len(out) % 4: out.append(0)
j['buffers'] = [{'byteLength': len(out)}]
js = json.dumps(j, separators=(',', ':')).encode()
js += b' ' * (-len(js) % 4)
with open(dst, 'wb') as f:
    f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(out)))
    f.write(struct.pack('<I4s', len(js), b'JSON')); f.write(js)
    f.write(struct.pack('<I4s', len(out), b'BIN\0')); f.write(out)
tris = sum(j['accessors'][p['indices']]['count'] // 3 for m in j['meshes'] for p in m['primitives'])
print(dst.split('/')[-1], '%d KB' % ((len(js) + len(out)) // 1024), tris, 'ucgen')
