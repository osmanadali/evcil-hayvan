extends RefCounted
## Oyuncunun surdugu aracin isiklari: yolu aydinlatan farlar (SpotLight3D), isikli far camlari, kirmizi
## stoplar (frende parlar), beyaz geri vites lambasi. Polo'da camlar govde shader'i ile isir
## (scripts/car_body.gd); diger araclarda govdeye oturan isikli mercekler eklenir (scripts/car.gd add_lamps).
## Arac uzayi: on = -Z, metre.

const Car = preload("res://scripts/car.gd")
const CarBody = preload("res://scripts/car_body.gd")


## Isik dugumlerini kurar (bir kez). kind: araba / motosiklet / scooter (bisiklette far yok).
static func attach(ride: Node3D, kind: String) -> bool:
	if kind == "bisiklet":
		return false
	if ride.has_meta("isiklar"):
		return true
	var two := kind != "araba"
	var root := Node3D.new()
	root.name = "Isiklar"
	ride.add_child(root)
	var box := _box(ride)
	var front_z := box.position.z
	var spots: Array = []
	for sx in ([0.0] if two else [-1.0, 1.0]):
		var s := SpotLight3D.new()
		s.position = Vector3(sx * box.size.x * 0.3, box.position.y + box.size.y * (0.7 if two else 0.47), front_z - 0.05)
		s.rotation.x = -0.07
		s.rotation.y = -sx * 0.05
		s.spot_range = 22.0 if two else 30.0
		s.spot_angle = 30.0 if two else 34.0
		s.spot_angle_attenuation = 0.7
		s.spot_attenuation = 0.9
		s.light_color = Color("fff1d2")
		s.light_energy = 0.0
		s.light_specular = 0.3
		s.shadow_enabled = false
		s.visible = false
		root.add_child(s)
		spots.append(s)
	# Yol dolgusu: farlar yere cok yakin oldugu icin isik yola siyirarak duser ve birkac metre otesi karanlik kalir.
	# On tamponun ustunden one-asagi bakan genis bir isik, 8-30 m arasini surucunun gorecegi kadar aydinlatir
	# (koni aracin onunde baslar: kendi kaputunu / tavanini aydinlatmaz).
	var fill := SpotLight3D.new()
	fill.position = Vector3(0, box.position.y + (2.3 if two else 2.7), front_z - 0.4)
	fill.rotation.x = -atan2(fill.position.y, 13.0 if two else 16.0)
	fill.spot_range = 30.0 if two else 42.0
	fill.spot_angle = 24.0 if two else 30.0
	fill.spot_angle_attenuation = 1.1
	fill.spot_attenuation = 0.55
	fill.light_color = Color("fff1d2")
	fill.light_energy = 0.0
	fill.light_specular = 0.1
	fill.shadow_enabled = false
	fill.visible = false
	fill.set_meta("dolgu", true)
	root.add_child(fill)
	spots.append(fill)
	var lamps: Array = []
	if not ride.has_meta("body_mats"):
		# Model dugumu: trafik arabasinda ilk cocuk (tutucu), kendi araclarimizda aracin kendisi
		var holder: Node3D = ride
		if ride.get_child_count() > 0 and ride.get_child(0) is Node3D and (ride.get_child(0) as Node3D).has_meta("wheels"):
			holder = ride.get_child(0)
		lamps = Car.add_lamps(holder, two)
	# Parlama haleleri: far / stop merceginin onunde kameraya donuk yumusak isik lekesi (gece uzaktan da secilir)
	var halos: Array = [[], []]
	var holder2: Node3D = root
	var fpos: Array = []
	var rpos: Array = []
	if not lamps.is_empty() and not (lamps[0] as Array).is_empty():
		holder2 = (lamps[0][0] as Node3D).get_parent()
		for b: Node3D in lamps[0]:
			fpos.append(b.position + Vector3(0, 0, -0.07))
		for b: Node3D in lamps[1]:
			rpos.append(b.position + Vector3(0, 0, 0.07))
	else:
		for sx in ([0.0] if two else [-1.0, 1.0]):
			fpos.append(Vector3(sx * box.size.x * 0.3, box.position.y + box.size.y * (0.7 if two else 0.47), front_z - 0.07))
			rpos.append(Vector3(sx * box.size.x * 0.3, box.position.y + box.size.y * 0.55, box.end.z + 0.07))
	for k in 2:
		for at: Vector3 in ([fpos, rpos][k] as Array):
			var h := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2.ONE
			h.mesh = q
			h.material_override = _halo_mat(Color("fff0d0") if k == 0 else Color("ff2a18"))
			h.position = at
			h.scale = Vector3.ONE * (0.6 if k == 0 else 0.34)
			h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			h.visible = false
			holder2.add_child(h)
			(halos[k] as Array).append(h)
	ride.set_meta("isiklar", {"spots": spots, "lamps": lamps, "halos": halos})
	return true


static var _halo_tex: GradientTexture2D


static func _halo_mat(col: Color) -> StandardMaterial3D:
	if _halo_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
		_halo_tex = GradientTexture2D.new()
		_halo_tex.gradient = g
		_halo_tex.fill = GradientTexture2D.FILL_RADIAL
		_halo_tex.fill_from = Vector2(0.5, 0.5)
		_halo_tex.fill_to = Vector2(1.0, 0.5)
		_halo_tex.width = 64
		_halo_tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = col
	m.albedo_texture = _halo_tex
	m.disable_fog = true
	return m


static func _box(ride: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in ride.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		var a: AABB = Car._rel(ride, mi) * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	if first:
		return AABB(Vector3(-0.8, 0, -2.0), Vector3(1.6, 1.4, 4.0))
	return box


## head: farlar acik; brake: frene basiliyor; rev: geri vites.
static func update(ride: Node3D, head: bool, brake: bool, rev: bool) -> void:
	if not is_instance_valid(ride) or not ride.has_meta("isiklar"):
		return
	var d: Dictionary = ride.get_meta("isiklar")
	for s: SpotLight3D in d["spots"]:
		s.visible = head
		s.light_energy = (6.0 if s.has_meta("dolgu") else 5.5) if head else 0.0
	var tail := 1.0 if brake else (0.35 if head else 0.0)
	CarBody.set_lamps(ride, 1.0 if head else 0.0, tail, 1.0 if rev else 0.0)
	var halos: Array = d.get("halos", [[], []])
	for h: MeshInstance3D in halos[0]:
		h.visible = head
	for h: MeshInstance3D in halos[1]:
		h.visible = tail > 0.0
		h.scale = Vector3.ONE * (0.55 if brake else 0.3)
		(h.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.16, 0.09, 1.0 if brake else 0.6)
	var lamps: Array = d["lamps"]
	if lamps.is_empty():
		return
	for b: Node3D in lamps[0]:
		b.visible = head
	for b: Node3D in lamps[1]:
		b.visible = tail > 0.0 or rev
	var rm: StandardMaterial3D = lamps[3]
	var col := Color("fff6ea") if rev and not brake else Color("ff1206")
	rm.albedo_color = col
	rm.emission = col
	rm.emission_energy_multiplier = 4.0 if brake else (3.0 if rev else 1.2)
	(lamps[2] as StandardMaterial3D).emission_energy_multiplier = 5.0
