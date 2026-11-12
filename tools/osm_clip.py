"""Birden cok .osm dosyasini birlestirir ve bir kutuya kirpar:
  python3 tools/osm_clip.py cikti.osm bati,guney,dogu,kuzey girdi1.osm girdi2.osm ..."""
import sys, xml.etree.ElementTree as ET
out, box, files = sys.argv[1], [float(v) for v in sys.argv[2].split(',')], sys.argv[3:]
nodes, ways = {}, {}
for f in files:
    r = ET.parse(f).getroot()
    for n in r.iter('node'): nodes[n.get('id')] = n
    for w in r.iter('way'): ways[w.get('id')] = w
inside = {i for i, n in nodes.items() if box[0] <= float(n.get('lon')) <= box[2] and box[1] <= float(n.get('lat')) <= box[3]}
root = ET.Element('osm', version='0.6', attribution='(c) OpenStreetMap contributors, ODbL')
keep = set()
kept_ways = []
for w in ways.values():
    refs = [x.get('ref') for x in w.findall('nd')]
    if any(r in inside for r in refs) and all(r in nodes for r in refs):
        kept_ways.append(w); keep.update(refs)
for i in keep | {i for i in inside if len(nodes[i]) > 0}:
    n = nodes[i]
    e = ET.SubElement(root, 'node', id=i, lat=n.get('lat'), lon=n.get('lon'))
    for t in n.findall('tag'): e.append(t)
for w in kept_ways:
    e = ET.SubElement(root, 'way', id=w.get('id'))
    for c in w: e.append(c)
ET.ElementTree(root).write(out, encoding='utf-8')
print('dugum', len(keep), 'yol/alan', len(kept_ways))
