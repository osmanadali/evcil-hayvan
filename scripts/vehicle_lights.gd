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
	var lamps: Array = []
	if not ride.has_meta("body_mats"):
		# Model dugumu: trafik arabasinda ilk cocuk (tutucu), kendi araclarimizda aracin kendisi
		var holder: Node3D = ride
		if ride.get_child_count() > 0 and ride.get_child(0) is Node3D and (ride.get_child(0) as Node3D).has_meta("wheels"):
			holder = ride.get_child(0)
		lamps = Car.add_lamps(holder, two)
	ride.set_meta("isiklar", {"spots": spots, "lamps": lamps})
	return true


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
		s.light_energy = 2.6 if head else 0.0
	var tail := 1.0 if brake else (0.35 if head else 0.0)
	CarBody.set_lamps(ride, 1.0 if head else 0.0, tail, 1.0 if rev else 0.0)
	var lamps: Array = d["lamps"]
	if lamps.is_empty():
		return
	for b: Node3D in lamps[0]:
		b.visible = head
	for b: Node3D in lamps[1]:
		b.visible = tail > 0.0 or rev
	var rm: StandardMaterial3D = lamps[3]
	var col := Color("fff6ea") if rev and not brake else Color("ff2010")
	rm.albedo_color = col
	rm.emission = col
	rm.emission_energy_multiplier = 5.0 if brake else (3.0 if rev else 1.4)
