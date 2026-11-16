extends RefCounted
## Kullanicinin kendi yukledigi ic mekanli araba modeli (assets/vehicles/araba.glb). Dosya varsa oyuncunun
## arabasi olarak Polo yerine bu kullanilir. Beklenen parca adlari docs/arac-modeli-istegi.md'de.
## Parcalar ada gore bulunur (buyuk / kucuk harf ve Turkce karakter farki onemsiz; ad bu sozcukle baslamali
## ya da onu icermeli). Olcek ve yon mumkun oldugunca kendiliginden duzeltilir: uzunluk 2.5-7 m degilse
## 4 m'ye olceklenir, model enine duruyorsa cevrilir, direksiyon arkada kaliyorsa 180 derece dondurulur.

const PATH := "res://assets/vehicles/araba.glb"
const ARMS := "res://assets/vehicles/kollar.glb"
const POLO_WHEEL := Vector3(-0.36, 0.9, -0.32)       # Polo'da simit merkezi: koltuk, goz ve ayaklar buna gore kayar


static func exists() -> bool:
	return ResourceLoader.exists(PATH)


static func _norm(s: String) -> String:
	s = s.to_lower()
	for pair in [["ı", "i"], ["ö", "o"], ["ü", "u"], ["ş", "s"], ["ç", "c"], ["ğ", "g"], [" ", "_"], ["-", "_"], [".", "_"]]:
		s = s.replace(pair[0], pair[1])
	return s


## Adi verilen sozcuklerden biriyle baslayan (yoksa iceren) ilk Node3D.
static func find(root: Node, keys: Array) -> Node3D:
	var all := root.find_children("*", "Node3D", true, false)
	for pass_i in 2:
		for n in all:
			var nm := _norm(String(n.name))
			for k: String in keys:
				if (pass_i == 0 and nm.begins_with(k)) or (pass_i == 1 and nm.contains(k)):
					return n
	return null


## Dugumun (cocuklariyla) 'space' dugumunun uzayindaki sinir kutusu.
static func box_in(space: Node3D, n: Node) -> AABB:
	var out := AABB()
	var first := true
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for mi: MeshInstance3D in list:
		if mi.mesh == null:
			continue
		var a: AABB = _rel(space, mi) * mi.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != root and cur != null:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Dugumu yeni bir ebeveyne tasir; arac uzayindaki yeri degismez.
static func _move(holder: Node3D, n: Node3D, new_parent: Node3D) -> void:
	var xf := _rel(holder, n)
	n.get_parent().remove_child(n)
	n.owner = null
	for sub in n.find_children("*", "", true, false):
		sub.owner = null
	new_parent.add_child(n)
	n.transform = _rel(holder, new_parent).affine_inverse() * xf


## Modeli kurar. Donus: arac dugumu (arac uzayi: on = -Z, metre, zemin y = 0) ya da null.
static func build(cabin_script: GDScript) -> Node3D:
	var scene: PackedScene = load(PATH)
	if scene == null:
		return null
	var holder := Node3D.new()
	var pivot := Node3D.new()
	pivot.name = "Model"
	holder.add_child(pivot)
	var inst: Node3D = scene.instantiate()
	pivot.add_child(inst)
	var box := box_in(holder, inst)
	if box.size == Vector3.ZERO:
		holder.free()
		return null
	# Olcek ve yon
	var long := maxf(box.size.x, box.size.z)
	var k := 1.0 if long >= 2.5 and long <= 7.0 else 4.0 / long
	var turn := PI / 2.0 if box.size.x > box.size.z else 0.0
	var wheel_n := find(inst, ["direksiyon", "steering", "simit"])
	if wheel_n != null:
		pivot.rotation.y = turn
		var wc := box_in(holder, wheel_n).get_center()
		var cc := box_in(holder, inst).get_center()
		if wc.z > cc.z:
			turn += PI
	pivot.rotation.y = turn
	pivot.scale = Vector3.ONE * k
	pivot.position = Vector3.ZERO
	box = box_in(holder, inst)
	pivot.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	holder.set_meta("custom", true)
	holder.set_meta("glass", true)

	# Tekerler: merkezinde donen eksen dugumu
	var wheels: Array = []
	for keys in [["teker_onsol", "wheel_fl"], ["teker_onsag", "wheel_fr"], ["teker_arkasol", "wheel_rl"], ["teker_arkasag", "wheel_rr"]]:
		var w := find(inst, keys)
		if w == null:
			continue
		var wb := box_in(holder, w)
		var ax := Node3D.new()
		ax.name = "Aks_" + keys[0]
		ax.position = wb.get_center()
		holder.add_child(ax)
		_move(holder, w, ax)
		wheels.append([ax, maxf(wb.size.y * 0.5, 0.05), ax.basis, Vector3.RIGHT, null, 0.0])
	holder.set_meta("wheels", wheels)

	# Surucu kapisi: on kenarindaki mentese dugumu
	var door := find(inst, ["kapi_onsol", "door_fl"])
	if door != null:
		var db := box_in(holder, door)
		var hinge := Node3D.new()
		hinge.name = "KapiMentese"
		hinge.position = Vector3(db.position.x + db.size.x * 0.5, 0.0, db.position.z)
		holder.add_child(hinge)
		_move(holder, door, hinge)
		holder.set_meta("door_hinge", hinge)

	# Camlar: adi "cam" / "glass" / "window" iceren malzemeler ya da parcalar saydamlasir
	var glass_mats: Array = []
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var node_glass := _is_glass(String(mi.name))
		for si in mi.mesh.get_surface_count():
			var src := mi.get_active_material(si)
			if src is BaseMaterial3D and (node_glass or _is_glass(src.resource_name)):
				var gm: BaseMaterial3D = src.duplicate()
				gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				gm.albedo_color = Color(0.55, 0.64, 0.68, 0.16)
				gm.roughness = 0.05
				gm.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(si, gm)
				glass_mats.append(gm)
	holder.set_meta("glass_mats", glass_mats)

	# Kabin: ekranlar, direksiyon ekseni, aynalar (geometri modelden gelir)
	var cab: Node3D = cabin_script.call("build_custom", holder, inst)
	cab.name = "Kabin"
	holder.add_child(cab)
	if wheel_n != null:
		holder.set_meta("seat_off", (cab.get_node("Direksiyon") as Node3D).position - POLO_WHEEL)
	for key in [["goz", ["surucu_goz", "kamera_surucu", "driver_eye"]], ["koltuk", ["surucu_koltuk", "driver_seat"]]]:
		var mk := find(inst, key[1])
		if mk != null:
			holder.set_meta(key[0], _rel(holder, mk).origin)
	return holder


static func _is_glass(nm: String) -> bool:
	nm = _norm(nm)
	if nm.contains("camera") or nm.contains("kamera"):
		return false
	return nm.begins_with("cam") or nm.contains("_cam") or nm.contains("glass") or nm.contains("window")


## Birinci sahis kol / el modeli (istege bagli): orijin goz hizasi, -Z ileri, eller direksiyonda.
static func arms() -> Node3D:
	if not ResourceLoader.exists(ARMS):
		return null
	var n: Node3D = (load(ARMS) as PackedScene).instantiate()
	n.name = "Kollar"
	return n
