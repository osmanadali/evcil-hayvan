extends RefCounted
## Basit sekillerden model kurmak icin ortak yardimcilar.

static var _mats := {}


static func mat(hex: String, rough := 0.9) -> StandardMaterial3D:
	var key := "%s_%s" % [hex, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = rough
	_mats[key] = m
	return m


static func glow(hex: String, energy := 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.emission_enabled = true
	m.emission = Color(hex)
	m.emission_energy_multiplier = energy
	return m


## Tuy hissi veren, kenarlari hafif aydinlik malzeme.
static func plush(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.6
	return m


static func checker(c1: Color, c2: Color, nx: int, ny: int) -> StandardMaterial3D:
	var img := Image.create(nx, ny, false, Image.FORMAT_RGB8)
	for j in ny:
		for i in nx:
			img.set_pixel(i, j, c1 if (i + j) % 2 == 0 else c2)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.95
	return m


static func add(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func pivot(parent: Node3D, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


static func box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return add(parent, b, m, pos, rot)


static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, m: Material,
		segs := 14, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return add(parent, c, m, pos, rot)


static func ball(parent: Node3D, r: float, pos: Vector3, m: Material, scl := Vector3.ONE, segs := 14) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(segs / 2, 3)
	return add(parent, s, m, pos, Vector3.ZERO, scl)


static func capsule(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return add(parent, c, m, pos, rot)


static func torus(parent: Node3D, r_in: float, r_out: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = r_in
	t.outer_radius = r_out
	t.rings = 20
	t.ring_segments = 8
	return add(parent, t, m, pos, rot)


## Ucgen prizma (cati). Ucgen XY duzleminde, Z boyunca uzar.
static func prism(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var p := PrismMesh.new()
	p.size = size
	return add(parent, p, m, pos, rot)
