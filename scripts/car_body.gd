extends RefCounted
## Polo govdesi (tek parca model): saydam camlar, mentesesinden acilan surucu kapisi, far / stop isimasi.
## Govde ag orgusu bolunmez: ayni ag iki kez cizilir; biri kapi bolgesini atar (govde), digeri yalniz kapi
## bolgesini cizer ve mentese dugumune baglidir. Kesim piksel basinadir (shaders/car_common.gdshaderinc),
## bu yuzden kapi kenarlari duzgundur. Model uzayi: 1.0 birim uzun, +Z on, +X surucu tarafi.

const HINGE := Vector3(0.214, 0.0, 0.169)      # surucu kapisinin mentese ekseni (model uzayi; on kenar)
const OPEN := 1.12                             # tam acik (radyan)


static func _mats(tex: Texture2D, door_mode: int) -> Array:
	var body := ShaderMaterial.new()
	body.shader = load("res://shaders/car_body.gdshader")
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/car_glass.gdshader")
	var inner := ShaderMaterial.new()
	inner.shader = load("res://shaders/car_body_inner.gdshader")
	for m: ShaderMaterial in [body, glass, inner]:
		m.set_shader_parameter("albedo_tex", tex)
		m.set_shader_parameter("door_mode", door_mode)
	glass.render_priority = 1
	body.next_pass = inner
	inner.next_pass = glass
	return [body, glass, inner]


## Govdeyi giydirir. Donus: basarili mi (dokulu malzeme yoksa false).
static func dress(car: Node3D, body: MeshInstance3D) -> bool:
	var src: BaseMaterial3D = body.get_active_material(0) as BaseMaterial3D
	if src == null or src.albedo_texture == null:
		return false
	var mats := _mats(src.albedo_texture, 0)
	body.material_override = mats[0]
	# Surucu kapisi: ayni ag, yalniz kapi bolgesi; mentese dugumu on kenarda
	var hinge := Node3D.new()
	hinge.name = "KapiMentese"
	hinge.transform = body.transform * Transform3D(Basis(), HINGE)
	body.get_parent().add_child(hinge)
	var door := MeshInstance3D.new()
	door.name = "SurucuKapisi"
	door.mesh = body.mesh
	door.position = -HINGE
	var dm := _mats(src.albedo_texture, 1)
	door.material_override = dm[0]
	hinge.add_child(door)
	car.set_meta("glass", true)
	car.set_meta("body_mats", mats + dm)
	car.set_meta("door_hinge", hinge)
	return true


## Kapi acikligi: 0 kapali, 1 tam acik. Kabindeki kapi dosemesi (KapiIc) birlikte doner.
static func door_angle(car: Node3D, k: float) -> void:
	if not is_instance_valid(car) or not car.has_meta("door_hinge"):
		return
	(car.get_meta("door_hinge") as Node3D).rotation.y = -OPEN * k
	var cab := car.get_node_or_null("Kabin/KapiIc") as Node3D
	if cab:
		cab.rotation.y = -OPEN * k


static func has_door(car: Node3D) -> bool:
	return is_instance_valid(car) and car.has_meta("door_hinge")


## Farlar (0..1), arka lambalar (0.35 park, 1 fren), geri vites.
static func set_lamps(car: Node3D, head: float, tail: float, rev: float) -> void:
	if not car.has_meta("body_mats"):
		return
	for m: ShaderMaterial in car.get_meta("body_mats"):
		if m.shader.resource_path.ends_with("car_body.gdshader"):
			m.set_shader_parameter("head_on", head)
			m.set_shader_parameter("tail_on", tail)
			m.set_shader_parameter("rev_on", rev)


## Iceriden bakis: camlar neredeyse gorunmez olur (gorusu kapatmasin).
static func set_inside(car: Node3D, on: bool) -> void:
	for gm: BaseMaterial3D in car.get_meta("glass_mats", []):      # kullanicinin modeli (custom_car.gd)
		gm.albedo_color.a = 0.04 if on else 0.16
	for gm: BaseMaterial3D in car.get_meta("rig_glass", []):       # ayrintili modeller (car_rig.gd)
		gm.albedo_color.a = 0.05 if on else float(gm.get_meta("alfa", 0.16))
		gm.metallic_specular = 0.15 if on else 0.5
	if not car.has_meta("body_mats"):
		return
	for m: ShaderMaterial in car.get_meta("body_mats"):
		if m.shader.resource_path.ends_with("car_glass.gdshader"):
			m.set_shader_parameter("inside", 1.0 if on else 0.0)
