extends Node3D
## Oyuncunun surdugu ayrintili arabalar (assets/vehicles/*.glb; tools/build_vehicles.py hazirlar).
## Model arac uzayinda gelir (metre; on = -Z, sag = +X, yer y = 0) ve adli parcalardan olusur:
## Govde, KapiSol / KapiSag (on kenardan menteseli), Bagaj, Teker*, FrenOn*, Direksiyon, Ayna*, Ekran, Gosterge.
## Bu dugum aracin kendisidir (main._rides'a girer). Modelin kendi ic mekani kullanilir; kodla uretilen
## kabin (car_cabin.gd) yerine ayni adlarla ("Kabin": Direksiyon/Simit, CarPlayVP, GostergeVP, AynaVP0-2)
## ince bir dugum kurulur, boylece main.gd / vehicle_life.gd'nin gosterge, navigasyon ekrani, ayna ve
## direksiyon kodu degismeden calisir.
## Yalniz oyuncunun araclarinda kullanilir; trafikte ve galeri vitrininde dusuk ayrintili modeller kalir.

const Kit = preload("res://scripts/kit.gd")
const CarPlay = preload("res://scripts/carplay.gd")
const CarCabin = preload("res://scripts/car_cabin.gd")
const Car = preload("res://scripts/car.gd")

## seat: surus pozundaki karakterin arac icindeki yeri; eye: iceriden bakis (surucunun goz hizasi);
## feet: ayak bileklerinin yeri [sol, sag] (pedal bolgesi, tabanin ustu);
## door_spot: binerken durulan yer (kapinin acilma yayinin disinda); exit_spots: inilen yerler;
## pet: hayvanin arka koltuktaki yerleri [konum, sapma, poz, pati kaldirma, burun kaldirma];
## screen / cluster: [konum, donme] (modelde hazir yuzey yoksa); mirror: ic dikiz aynasi [konum, donme]
## (modelde yoksa); plates: [konum, sapma (yerel +Z disari bakar), genislik]; glass: [malzeme adi, saydamlik].
const SPECS := {
	"hatchback": {
		"ad": "Bora GT", "path": "res://assets/vehicles/hatchback.glb", "doors": true,
		"seat": Vector3(-0.455, -0.11, 0.03), "eye": Vector3(-0.455, 1.08, 0.2), "eye_pitch": -0.1,
		"feet": [Vector3(-0.56, 0.36, -0.42), Vector3(-0.34, 0.36, -0.45)],
		"door_spot": Vector3(-1.75, 0, 0.8), "exit_spots": [Vector3(-1.75, 0, 0.8), Vector3(1.75, 0, 0.8)],
		"pet": {"on": [Vector3(0.2, 0.55, 0.98), 0.0, "sit", 0.0, 0.0], "cam": [Vector3(0.42, 0.55, 0.95), -PI / 2, "stand", 0.0, 0.0],
			"arka": [Vector3(0.0, 0.55, 1.0), PI / 2, "lie", 0.0, 0.0], "arkacam": [Vector3(-0.3, 0.55, 0.98), 0.0, "sit", 0.0, 0.0]},
		"pet_size": 0.5,
		"screen": [Vector3(-0.02, 0.905, -0.47), Vector3(-0.2, -0.22, 0), Vector2(0.27, 0.127)],
		"cluster": [Vector3(-0.455, 0.93, -0.52), Vector3(-0.32, 0, 0), Vector2(0.26, 0.0975)],
		"mirror": [Vector3(-0.06, 1.2, -0.31), Vector3(0.0, -0.36, 0)],
		"plates": [[Vector3(0, 0.383, 1.893), 0.0, 0.44]],
		"plate_text": "33 OA 2003",
		"glass": {"windshield": 0.16},
		"paint": {"body": [Color("c41f1b"), 0.28, 0.35], "material": [Color("c41f1b"), 0.28, 0.35], "interior": [Color("2b2d31"), 0.85, 0.0],
			"number_plate": [Color("f4f4f0"), 0.5, 0.0]},
		"rear_cam": Vector3(0, 1.05, 2.1),
	},
	"sedan": {
		"ad": "Derya 1.6 Sedan", "path": "res://assets/vehicles/sedan.glb", "doors": false,
		"seat": Vector3(-0.376, 0.07, -0.13), "eye": Vector3(-0.376, 1.22, 0.03), "eye_pitch": -0.1,
		"feet": [Vector3(-0.49, 0.38, -0.6), Vector3(-0.25, 0.38, -0.64)],
		"door_spot": Vector3(-1.4, 0, 0.1), "exit_spots": [Vector3(-1.4, 0, 0.1), Vector3(1.4, 0, 0.1), Vector3(-1.8, 0, 0.1), Vector3(1.8, 0, 0.1)],
		"pet": {"on": [Vector3(0.36, 0.56, 0.72), 0.0, "sit", 0.0, 0.0], "cam": [Vector3(0.42, 0.56, 0.7), -PI / 2, "stand", 1.0, 0.5],
			"arka": [Vector3(0.05, 0.56, 0.74), PI / 2, "lie", 0.0, 0.0], "arkacam": [Vector3(-0.4, 0.56, 0.7), PI / 2, "stand", 1.0, 0.5]},
		"pet_size": 0.58,
		"plates": [[Vector3(0, 0.466, -2.28), PI, 0.5], [Vector3(0, 0.791, 2.227), 0.0, 0.5]],
		"plate_text": "06 DRY 26",
		"glass": {"Material.004": 0.2},
		"paint": {},
		"rear_cam": Vector3(0, 1.1, 2.35),
	},
}

var id := ""
var spec := {}
var has_doors := false
var model: Node3D
var cabin: Node3D
var _doors := {}           # -1 sol, +1 sag -> dugum
var _brakes: Array = []
var _spin: Node3D
static var _fixed := {}    # malzemeleri bir kez duzelt (yol -> true)


## Araci kurar: id SPECS anahtari. Bulunamazsa null.
static func make(rig_id: String) -> Node3D:
	if not SPECS.has(rig_id) or not ResourceLoader.exists(SPECS[rig_id]["path"]):
		return null
	var r: Node3D = load("res://scripts/car_rig.gd").new()
	r._build(rig_id)
	return r


func _build(rig_id: String) -> void:
	id = rig_id
	spec = SPECS[id]
	has_doors = spec["doors"]
	name = "Arac_" + id
	model = load(spec["path"]).instantiate()
	model.name = "Model"
	add_child(model)
	_fix_materials()
	var wheels: Array = []
	for n: Node3D in model.get_children():
		var nm := String(n.name)
		if nm.begins_with("Teker") and n is MeshInstance3D:
			wheels.append([n, maxf((n as MeshInstance3D).mesh.get_aabb().size.y * 0.5, 0.05), n.basis, Vector3.RIGHT, null, 0.0])
		elif nm.begins_with("Fren"):
			_brakes.append(n)
		elif nm == "KapiSol":
			_doors[-1] = n
		elif nm == "KapiSag":
			_doors[1] = n
		if n is MeshInstance3D:
			(n as MeshInstance3D).visibility_range_end = 220.0
	set_meta("kind", "araba")
	set_meta("rig", true)
	set_meta("rig_id", id)
	set_meta("glass", true)            # camlar saydam: surucu ve ic mekan disaridan gorunur
	set_meta("wheels", wheels)
	set_meta("seat", spec["seat"])
	set_meta("eye", Transform3D(Basis(Vector3.RIGHT, float(spec["eye_pitch"])), spec["eye"]))
	set_meta("feet", spec["feet"])
	set_meta("door_spot", spec["door_spot"])
	set_meta("exit_spots", spec["exit_spots"])
	set_meta("pet_spots", spec["pet"])
	set_meta("pet_size", spec["pet_size"])
	set_meta("pet_seat", (spec["pet"]["on"] as Array)[0])
	_build_cabin()
	_build_plates()
	set_meta("blinkers", Car.add_blinkers(model))


## Camlar saydam ve iki yuzlu (iceriden de gorunur), boya parlak; kaynak malzemeler paylasildigi icin bir kez.
func _fix_materials() -> void:
	if _fixed.has(id):
		return
	_fixed[id] = true
	var glass: Dictionary = spec["glass"]
	var paint: Dictionary = spec["paint"]
	var seen := {}
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m == null or seen.has(m):
				continue
			seen[m] = true
			var nm := m.resource_name
			if glass.has(nm):
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color = Color(0.05, 0.09, 0.11, float(glass[nm]))
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.roughness = 0.05
				m.metallic = 0.3
				m.emission_enabled = false
			elif paint.has(nm):
				m.albedo_color = paint[nm][0]
				m.roughness = paint[nm][1]
				m.metallic = paint[nm][2]


func _part(nm: String) -> MeshInstance3D:
	return model.get_node_or_null(nm) as MeshInstance3D


## Ekran yuzeyi: SubViewport dokulu, isiksiz dortgen.
func _screen_quad(parent: Node3D, vp: SubViewport, size: Vector2, xf: Transform3D, gain := 1.3) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = vp.get_texture()
	sm.albedo_color = Color(gain, gain, gain)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = sm
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Modeldeki duz bir yuzeyin (yerel +Z'ye bakan) hemen onunde, yuzeyin boyutunda donusum ve boyut.
func _face_of(mi: MeshInstance3D, lift := 0.004) -> Array:
	var bb := mi.mesh.get_aabb()
	var c := bb.get_center()
	return [mi.transform * Transform3D(Basis(), Vector3(c.x, c.y, bb.end.z + lift)), Vector2(bb.size.x, bb.size.y)]


func _build_cabin() -> void:
	cabin = Node3D.new()
	cabin.name = "Kabin"
	cabin.set_meta("gosterge", true)
	add_child(cabin)
	for nm in ["Ust", "Dis"]:
		var e := Node3D.new()
		e.name = nm
		cabin.add_child(e)
	var black := Kit.mat("0c0d0f", 0.3)
	# ---- Direksiyon: modelin simidi, kolon ekseninde (yerel Z) donen "Simit" dugumune tasinir
	var wheel := Node3D.new()
	wheel.name = "Direksiyon"
	wheel.set_meta("model", true)
	cabin.add_child(wheel)
	_spin = Node3D.new()
	_spin.name = "Simit"
	wheel.add_child(_spin)
	var sw := _part("Direksiyon")
	if sw:
		wheel.transform = sw.transform
		wheel.set_meta("r", sw.mesh.get_aabb().size.x * 0.5 - 0.018)
		sw.get_parent().remove_child(sw)
		sw.transform = Transform3D()
		sw.name = "SimitModel"
		_spin.add_child(sw)
	# ---- Orta ekran (navigasyon / radyo): modeldeki ekran yuzeyi ya da panele oturan tablet
	var vp := SubViewport.new()
	vp.name = "CarPlayVP"
	vp.size = Vector2i(640, 300)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cp := CarPlay.new()
	cp.name = "CP"
	vp.add_child(cp)
	cabin.add_child(vp)
	var scr := _part("Ekran")
	if scr:
		var f := _face_of(scr)
		# Modelin ekrani kucuk: navigasyon okunsun diye cerceveyi de kaplayacak kadar buyutulur
		var w: float = (f[1] as Vector2).x * 1.28
		_screen_quad(cabin, vp, Vector2(w, w * 300.0 / 640.0), f[0])
	elif spec.has("screen"):
		var s: Array = spec["screen"]
		var holder := Node3D.new()
		holder.name = "Ekran"
		holder.position = s[0]
		holder.rotation = s[1]
		cabin.add_child(holder)
		var sz: Vector2 = s[2]
		_screen_quad(holder, vp, sz, Transform3D(Basis(), Vector3(0, 0, 0.009)))
		var bez := CarCabin.rounded([Vector2(-sz.x * 0.5 - 0.012, -sz.y * 0.5 - 0.012), Vector2(sz.x * 0.5 + 0.012, -sz.y * 0.5 - 0.012),
			Vector2(sz.x * 0.5 + 0.012, sz.y * 0.5 + 0.012), Vector2(-sz.x * 0.5 - 0.012, sz.y * 0.5 + 0.012)], 0.014)
		CarCabin.extrude(holder, bez, -0.012, 0.008, 2, black, 0.0)
		Kit.cyl(holder, 0.016, 0.03, 0.09, Vector3(0, -sz.y * 0.5 - 0.03, -0.03), black, 10, Vector3(0.5, 0, 0))
	# ---- Gosterge paneli: canli hiz / devir / yakit (car_cabin.gd'nin cizimi)
	var gvp := SubViewport.new()
	gvp.name = "GostergeVP"
	gvp.size = Vector2i(512, 192)
	gvp.transparent_bg = false
	gvp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cl := CarCabin.Cluster.new()
	cl.name = "G"
	gvp.add_child(cl)
	cabin.add_child(gvp)
	var gg := _part("Gosterge")
	if gg:
		var f := _face_of(gg, 0.012)
		var h: float = (f[1] as Vector2).y * 1.04
		_screen_quad(cabin, gvp, Vector2(h * 512.0 / 192.0, h), f[0], 1.2)
	elif spec.has("cluster"):
		var s: Array = spec["cluster"]
		var holder := Node3D.new()
		holder.name = "Gosterge"
		holder.position = s[0]
		holder.rotation = s[1]
		cabin.add_child(holder)
		var sz: Vector2 = s[2]
		_screen_quad(holder, gvp, sz, Transform3D(Basis(), Vector3(0, 0, 0.006)), 1.2)
		Kit.box(holder, Vector3(sz.x + 0.024, sz.y + 0.024, 0.02), Vector3(0, 0, -0.006), black)
		# Siperlik
		Kit.box(holder, Vector3(sz.x + 0.03, 0.012, 0.07), Vector3(0, sz.y * 0.5 + 0.016, 0.022), black)
	# ---- Aynalar: ic dikiz + iki yan ayna, arkaya bakan dusuk cozunurluklu kameralar (vehicle_life gunceller)
	var faces: Array = []
	var glasses: Array = [_part("AynaIc"), _part("AynaSol"), _part("AynaSag")]
	if glasses[0]:
		faces.append(_face_of(glasses[0]))
	else:
		var s: Array = spec["mirror"]
		var holder := Node3D.new()
		holder.name = "DikizAynasi"
		holder.position = s[0]
		holder.rotation = s[1]
		cabin.add_child(holder)
		var mh := Kit.capsule(holder, 0.034, 0.24, Vector3(0, 0, -0.012), black, Vector3(0, 0, PI / 2))
		mh.scale = Vector3(1.0, 1.0, 0.45)
		Kit.cyl(holder, 0.007, 0.007, 0.07, Vector3(0, 0.05, -0.02), black, 6)
		faces.append([holder.transform * Transform3D(Basis(), Vector3(0, 0, 0.006)), Vector2(0.215, 0.055)])
	for i in [1, 2]:
		faces.append(_face_of(glasses[i]) if glasses[i] else [])
	var rear: Vector3 = spec["rear_cam"]
	for i in 3:
		if (faces[i] as Array).is_empty():
			continue
		var fxf: Transform3D = faces[i][0]
		var fsz: Vector2 = faces[i][1]
		var mvp := SubViewport.new()
		mvp.name = "AynaVP%d" % i
		mvp.size = Vector2i(256, 66) if i == 0 else Vector2i(160, 110)
		mvp.render_target_update_mode = SubViewport.UPDATE_ONCE
		mvp.positional_shadow_atlas_size = 0
		mvp.msaa_3d = Viewport.MSAA_DISABLED
		var mc := Camera3D.new()
		mc.name = "Kam"
		mc.fov = 30.0 if i == 0 else 26.0
		mc.far = 160.0
		mc.near = 0.2
		# Ic ayna kamerasi arka camin disinda durur (kabin goruntuye girmesin); yan aynalar kendi yerinden bakar
		var side := 0.0 if i == 0 else (-1.0 if i == 1 else 1.0)
		var at := rear if i == 0 else fxf.origin + Vector3(side * 0.07, 0.0, 0.12)
		var local := Transform3D(Basis(Vector3.UP, PI + side * 0.1) * Basis(Vector3.RIGHT, -0.03), at)
		mc.set_meta("local", local)
		mc.transform = local
		mvp.add_child(mc)
		cabin.add_child(mvp)
		if glasses[i]:
			# Modelin kendi ayna cami: goruntu, camin yerel sinir kutusuna gore (ayna gibi ters) yansitilir
			var gmi: MeshInstance3D = glasses[i]
			var bb := gmi.mesh.get_aabb()
			var sh := ShaderMaterial.new()
			sh.shader = _mirror_shader()
			sh.set_shader_parameter("tex", mvp.get_texture())
			sh.set_shader_parameter("rect", Vector4(bb.position.x, bb.position.y, bb.size.x, bb.size.y))
			gmi.material_override = sh
			gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			var q := _screen_quad(cabin, mvp, fsz, fxf, 0.92)
			q.name = "AynaCam%d" % i
			var mm: StandardMaterial3D = q.material_override
			mm.uv1_scale = Vector3(-1, 1, 1)
			mm.uv1_offset = Vector3(1, 0, 0)
	# Ic aydinlatma (koyu ic mekan gece de secilsin)
	var il := OmniLight3D.new()
	il.position = Vector3(0, (spec["eye"] as Vector3).y + 0.05, 0.1)
	il.omni_range = 1.7
	il.light_energy = 0.35
	il.light_color = Color("fff1dc")
	il.shadow_enabled = false
	cabin.add_child(il)


static var _mirror_sh: Shader


static func _mirror_shader() -> Shader:
	if _mirror_sh == null:
		_mirror_sh = Shader.new()
		_mirror_sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform vec4 rect;
varying vec2 muv;
void vertex() {
	muv = (VERTEX.xy - rect.xy) / rect.zw;
}
void fragment() {
	ALBEDO = texture(tex, vec2(1.0 - muv.x, 1.0 - muv.y)).rgb * vec3(0.86, 0.9, 0.93);
}
"""
	return _mirror_sh


func _build_plates() -> void:
	for p: Array in spec["plates"]:
		var plate := Node3D.new()
		plate.position = p[0]
		plate.rotation.y = p[1]
		add_child(plate)
		var w: float = p[2]
		var k := w / 0.52
		Kit.box(plate, Vector3(w, 0.115 * k, 0.006), Vector3.ZERO, Kit.mat("f6f6f2", 0.4))
		Kit.box(plate, Vector3(0.045 * k, 0.115 * k, 0.008), Vector3(-w * 0.5 + 0.0225 * k, 0, 0), Kit.mat("1f4fa8", 0.4))
		var tr := Label3D.new()
		tr.text = "TR"
		tr.font_size = 32
		tr.pixel_size = 0.0008 * k
		tr.position = Vector3(-w * 0.5 + 0.0225 * k, -0.025 * k, 0.006)
		plate.add_child(tr)
		var num := Label3D.new()
		num.text = spec["plate_text"]
		num.font_size = 96
		num.pixel_size = 0.00088 * k
		num.modulate = Color("111111")
		num.outline_size = 0
		num.position = Vector3(0.02 * k, 0, 0.006)
		plate.add_child(num)


## Kapi acikligi: k 0 (kapali) .. 1 (acik); side -1 sol (surucu), +1 sag.
func door(k: float, side := -1) -> void:
	var d: Node3D = _doors.get(side)
	if d:
		d.rotation.y = side * 1.15 * clampf(k, 0.0, 1.0)


## Surerken her kare: on fren diskleri tekerle birlikte doner, simit kolon ekseninde cevrilir.
func drive(steer_angle: float, steer_k: float) -> void:
	for b: Node3D in _brakes:
		b.rotation.y = -steer_angle
	_spin.rotation.z = -steer_k * 2.6


# ---------------------------------------------------------------- kapisi acilmayan arac: binis / inis

## Kapiya don, kola uzanip kisa bir egilme; sonra surucu koltugunda belir. vl: vehicle_life dugumu.
func mount_closed(vl: Node, side_l: Vector3) -> void:
	var m: Node = vl.m
	var on: Node3D = m.owner_node
	var om: Node3D = m.owner_model
	var yaw0 := on.rotation.y
	var face := rotation.y - PI / 2
	om.act("door", 0.6)
	m._sfx("araba_kapi", -6.0)
	await vl._run(0.5, func(k: float):
		on.rotation.y = lerp_angle(yaw0, face, minf(1.0, k * 2.5))
		om.position = Vector3(0, -0.22 * sin(k * PI * 0.5), -0.25 * vl._ease(k)))
	m._enter_ride_now(self, true)
	on.position = position
	on.rotation = rotation
	om.position = spec["seat"]
	om.rotation.y = 0.0
	om.visible = true
	vl._pet_wait()
	vl._pet_board()
	await vl._run(0.25, func(_k: float):
		on.position = position
		on.rotation = rotation
		m._wheel_grips())
	m._sfx("araba_kapi", -8.0, 0.92)


## Koltuktan kaybol, kapinin yaninda hafif egik belirip dogrul.
func dismount_closed(vl: Node, side_l: Vector3) -> void:
	var m: Node = vl.m
	var on: Node3D = m.owner_node
	var om: Node3D = m.owner_model
	var left := side_l.x < 0.0
	m._sfx("araba_kapi", -6.0, 1.05)
	var base: Transform3D = vl._flat(self)
	var out := base * side_l
	var pet: Node3D = m._rider_pet
	var pet_from := pet.global_position if pet else Vector3.ZERO
	m._exit_ride_now(Vector2(out.x, out.z), true)
	on.rotation = Vector3(0, rotation.y - (PI / 2 if left else -PI / 2), 0)
	if pet and pet.visible:
		vl._fly_out(pet, pet_from, 0.3)
	await vl._run(0.45, func(k: float):
		om.position = Vector3(0, -0.22 * (1.0 - vl._ease(k)), -0.3 * (1.0 - vl._ease(k))))
	om.position = Vector3.ZERO
	m._sfx("araba_kapi", -8.0, 0.92)


# ---------------------------------------------------------------- test

## --rigshots[=hatchback,sedan] [--rigpart=dis,ic,bin]: her arac icin ardisik goruntuler (<shot>_<arac>_<bakis>.png):
## dis: disaridan sol yan, on capraz, arkadan; ic: iceriden (V) ve surerken ucuncu sahis; bin: binis / inis
## hareketinin ortasi (kapi acik / egilme). Yavas makinede hareketi yakalamak icin motoru --fixed-fps 20 ile calistir.
static func debug_shots(m: Node, args: Dictionary) -> void:
	var ids: Array = ["hatchback", "sedan"]
	if String(args["rigshots"]) != "1":
		ids = Array(String(args["rigshots"]).split(","))
	var tree := m.get_tree()
	var parts: Array = Array(String(args.get("rigpart", "dis,ic,bin")).split(","))
	m.state.d["tips"] = false
	var vp := m.get_viewport()
	var out := String(args["shot"])
	var save := func(tag: String) -> void:
		if DisplayServer.get_name() == "headless":
			return
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out.replace(".png", "_%s.png" % tag))
	for rid: String in ids:
		var r: Node3D = null
		for q in m._rides:
			if q.get_meta("rig_id", "") == rid:
				r = q
		if r == null:
			print("RIG yok: ", rid)
			continue
		var b: Transform3D = m.life._flat(r)
		print("RIG ", rid, " konum=", r.position, " ad=", r.spec["ad"])
		var p := b * Vector3(-2.4, 0, 1.0)
		m._place_owner(Vector2(p.x, p.z))
		for k in m.agents:
			m.agents[k].place(Vector2(p.x, p.z) + Vector2(0.8, 0.6))
		for i in 4:
			await tree.process_frame
		m.life.instant = true
		m._enter_ride_now(r)
		for i in 40:
			await tree.process_frame
		m._mode = "debug"
		var cam: Camera3D = m.cam
		for v: Array in [] if not "dis" in parts else [["yan", Vector3(-4.2, 1.35, 0.1), Vector3(0, 0.85, 0.1), 42.0], ["on", Vector3(-2.3, 1.5, -4.2), Vector3(0, 0.8, 0), 45.0],
				["arka", Vector3(1.2, 1.7, 4.8), Vector3(0, 0.8, 0), 45.0], ["hayvan", Vector3(2.6, 1.35, 1.3), Vector3(0, 0.9, 0.7), 40.0]]:
			cam.fov = v[3]
			cam.global_position = b * (v[1] as Vector3)
			cam.look_at(b * (v[2] as Vector3))
			for i in 3:
				await tree.process_frame
			await save.call("%s_%s" % [rid, v[0]])
		m._mode = "play"
		if "ic" in parts:
			m._fps = true
			for i in 24:
				m._drive_speed = 3.0
				await tree.process_frame
			await save.call("%s_ic" % rid)
			m._fps_yaw = 0.75
			for i in 4:
				m._fps_yaw = 0.75
				m._drive_speed = 3.0
				await tree.process_frame
			await save.call("%s_ic_sol" % rid)
			m._fps_yaw = 0.0
			m._toggle_fps()
			for i in 30:
				m._drive_speed = 6.0
				m.ui.stick = Vector2(0.6, -1.0)
				await tree.process_frame
			await save.call("%s_surus" % rid)
		m.ui.stick = Vector2.ZERO
		m._drive_speed = 0.0
		for i in 5:
			await tree.process_frame
		m._exit_ride_now()
		for i in 5:
			await tree.process_frame
		if not "bin" in parts:
			continue
		# Binis hareketi (gercek zamanli): ortasinda goruntu
		m.life.instant = false
		b = m.life._flat(r)
		p = b * Vector3(-2.6, 0, 1.2)
		m._place_owner(Vector2(p.x, p.z))
		await tree.process_frame
		m.life._dbg_cam = [b * Vector3(-4.0, 1.7, 2.6), b * Vector3(-0.6, 0.85, 0.1)]
		m._enter_ride()
		var t := 0.0
		var shot_a := false
		var shot_b := false
		while m.life.busy() and t < 12.0:
			await tree.process_frame
			t += m.get_process_delta_time()
			var open: float = absf((r._doors[-1] as Node3D).rotation.y) if r.has_doors else 0.0
			if not shot_a and ((r.has_doors and open > 0.9) or (not r.has_doors and m.owner_model.position.y < -0.1)):
				shot_a = true
				await save.call("%s_bin1" % rid)
			elif shot_a and not shot_b and m._ride != null and m.owner_model.position.distance_to(r.spec["seat"]) < 0.25 and (open > 0.5 or not r.has_doors):
				shot_b = true
				await save.call("%s_bin2" % rid)
		print("RIG bindi=", m._ride == r, " sure=%.1f" % t, " kapi=", (r._doors[-1] as Node3D).rotation.y if r.has_doors else 0.0)
		for i in 10:
			await tree.process_frame
		await save.call("%s_bin3" % rid)
		m._exit_ride()
		t = 0.0
		while m.life.busy() and t < 12.0:
			await tree.process_frame
			t += m.get_process_delta_time()
		print("RIG indi=", m._ride == null, " sure=%.1f" % t, " sahip=", m._owner_pos(), " arac=", Vector2(r.position.x, r.position.z))
		await save.call("%s_in" % rid)
		m.life._dbg_cam = []
		m.life.instant = true
