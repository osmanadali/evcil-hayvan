extends RefCounted
## Sakal ve biyik (berber). Ayri bir model yok: govde aginin yuz bolgesindeki ucgenleri kopyalanip
## yuzey normali boyunca biraz disari itilir; boylece sakal her yuze tam oturur. Bas kemigine baglanir.
## Bolgeler bas kemiginin dinlenme konumuna gore (iskelet uzayi, yuz +Z) metre cinsinden tanimli.

# style -> [disari itme (m), kalinlik egimi, opaklik]
const LOOK := {1: [0.0022, 0.0, 0.55], 2: [0.006, 0.0, 1.0], 3: [0.007, 0.004, 1.0], 4: [0.008, 0.005, 1.0]}

static var _cache := {}      # mesh -> [PackedVector3Array konum, PackedVector3Array normal, PackedInt32Array]


static func _region(style: int, r: Vector3) -> bool:
	var ax := absf(r.x)
	var dy := r.y
	var dz := r.z
	# Ortak: yuzun on yarisi, kulak arkasi ve ense yok
	if ax > 0.095 or dz < -0.03:
		return false
	var mouth := ax < 0.03 and dy > 0.009 and dy < 0.026 and dz > 0.11
	match style:
		2:  # biyik: ust dudagin ustu
			return ax < 0.036 and dy > 0.024 and dy < 0.042 and dz > 0.115
		3:  # keci sakal: cene ucu + biyik, dudak acik
			if mouth:
				return false
			if ax < 0.036 and dy > 0.024 and dy < 0.042 and dz > 0.115:
				return true
			return ax < 0.03 and dy > -0.03 and dy < 0.012 and dz > 0.07
		_:  # tam sakal / kirli sakal: cene hatti, yanaklarin alti, favoriler
			if mouth:
				return false
			var top := lerpf(0.04, 0.095, clampf((ax - 0.04) / 0.04, 0.0, 1.0))
			if style == 1:
				top -= 0.006
			if dy > top or dy < -0.045:
				return false
			if dz < 0.0 and dy < 0.03:
				return false       # cene altinin arkasi (boyun) yok
			if ax > 0.07 and dz < -0.01:
				return false
			# Burun ve ust dudak ortasi acik kalsin
			if ax < 0.022 and dy > 0.026:
				return false
			return true


static func _arrays(mi: MeshInstance3D) -> Array:
	var key := mi.mesh.get_rid().get_id()
	if _cache.has(key):
		return _cache[key]
	var a := mi.mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var out := [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], idx]
	_cache[key] = out
	return out


## Sakal dugumu (bas kemigine bagli BoneAttachment3D) doner; bolge bos kalirsa null.
static func build(skel: Skeleton3D, head: int, body: MeshInstance3D, style: int, col: Color) -> Node3D:
	if body.mesh == null:
		return null
	var arr := _arrays(body)
	var vs: PackedVector3Array = arr[0]
	var ns: PackedVector3Array = arr[1]
	var ix: PackedInt32Array = arr[2]
	if ix.is_empty():
		return null
	var rel := skel.global_transform.affine_inverse() * body.global_transform
	var hrest := skel.get_bone_global_rest(head)
	var inv := hrest.affine_inverse()
	var hp := hrest.origin
	var look: Array = LOOK.get(style, LOOK[4])
	var push: float = look[0]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_tri := 0
	for t in range(0, ix.size(), 3):
		var p0: Vector3 = rel * vs[ix[t]]
		var p1: Vector3 = rel * vs[ix[t + 1]]
		var p2: Vector3 = rel * vs[ix[t + 2]]
		var c := (p0 + p1 + p2) / 3.0 - hp
		if not _region(style, c):
			continue
		for j in 3:
			var vi: int = ix[t + j]
			var p: Vector3 = rel * vs[vi]
			var nn: Vector3 = (rel.basis * ns[vi]).normalized()
			# Cene altinda biraz daha dolgun (tam sakal)
			var extra: float = float(look[1]) * clampf((0.02 - (p.y - hp.y)) / 0.06, 0.0, 1.0)
			st.set_normal(inv.basis * nn)
			st.add_vertex(inv * (p + nn * (push + extra)))
		n_tri += 1
	if n_tri == 0:
		return null
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, float(look[2])).darkened(0.08)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if float(look[2]) < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var att := BoneAttachment3D.new()
	att.bone_name = skel.get_bone_name(head)
	skel.add_child(att)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	att.add_child(mi)
	return att
