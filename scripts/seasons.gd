extends Node
## Mevsimler ve etkinlikler (gercek sistem ayi + hava durumu).
## - Kis: kar yerdeyken F ile kardan adam (3 asamada buyur, kar erirse erir), Y ile kartopu (yay cizer, cocuklar
##   karsilik verir), buzda hafif kayma.
## - Yaz: parkta mangal + piknik battaniyesi. Komur ve et al, izgara yap, dumanli; yanda piknik yapan aileler.
## - Yilbasi (20 Aralik - 2 Ocak): isik dizileri, meydanda buyuk susli agac, gece yarisi havai fisek.
## - Mac gecesi: ana yolda bayrakli, kornali araba konvoyu (hayali takim: Cinaralti SK, kirmizi-lacivert).

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PersonModel = preload("res://scripts/person_model.gd")

const GRAVITY := 14.0
const GRILL_SECS := 9.0
const BALL_SPEED := 15.0
const CONVOY_COLORS := ["c8102e", "10205a"]

var m: Node                     # main
var state: Node

var f_summer := false           # test: yaz zorla
var f_newyear := false          # test: yilbasi zorla

var snowmen: Array = []         # [{root, stage, pos}]
var _balls: Array = []          # [{node, vel, mine}]
var _revenge: Array = []        # [{npc, t, n}]
var _ball_cd := 0.0
var _npc_throw_t := 15.0
var _slip := Vector2.ZERO
var _slip_t := 0.0
var _slip_cd := 6.0
var _snow_hint := false

var _summer_root: Node3D
var _mangal: Dictionary = {}    # {pos, smoke, ember, grill_t, cooked}
var _ny_root: Node3D
var _ny_tree_pos := Vector2.INF
var _prev_clock := -1.0
var _fw_t := 0.0
var _conv: Dictionary = {}
var _conv_cd := 90.0
var _horn: AudioStreamWAV
var _season_t := 0.0


# ---------------------------------------------------------------- durum

func _date() -> Dictionary:
	return Time.get_date_dict_from_system()


func is_summer() -> bool:
	var mo: int = int(_date()["month"])
	return f_summer or (mo >= 6 and mo <= 9)


func is_newyear() -> bool:
	var d := _date()
	return f_newyear or (int(d["month"]) == 12 and int(d["day"]) >= 20) or (int(d["month"]) == 1 and int(d["day"]) <= 2)


func snow_ok() -> bool:
	return m.weather != null and m.weather.cover > 0.25 and ParkMap.home == null


func _fwd() -> Vector2:
	var y: float = m.owner_node.rotation.y
	return Vector2(sin(y), cos(y))


# ---------------------------------------------------------------- kurulum

func build() -> void:
	var w: Node3D = m.world
	var base := Vector2.ZERO
	if ParkMap.has_spot("baslangic"):
		base = ParkMap.spot("baslangic")
	_build_picnic(w, base)
	_build_newyear(w, base)
	_apply_season()


func _spot(p: Vector2, r: float, gap: float) -> Vector2:
	return m.street_food._free_spot(p, r, gap)


func _apply_season() -> void:
	if _summer_root:
		_summer_root.visible = is_summer()
	if _ny_root:
		_ny_root.visible = is_newyear()


func _yaw(face: Vector2) -> float:
	return atan2(face.x, face.y)


func _person(kind: String, shirt: String, pants: String, sc := 1.0) -> Node3D:
	var v := PersonModel.new()
	v.kind = kind
	v.tint = Color(shirt)
	v.tint2 = Color(shirt)
	v.pants = Color(pants)
	v.scale = Vector3.ONE * sc
	return v


func _multi(parent: Node3D, mesh: Mesh, mat: Material, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ---------------------------------------------------------------- parcacik yardimcilari

func _smoke(parent: Node3D, pos: Vector3, amount: int, strength: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 3.2
	p.local_coords = false
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 16, 16))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.1, 1, 0.05)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.5 * strength
	pm.initial_velocity_max = 1.1 * strength
	pm.gravity = Vector3(0.35, 0.25, 0.1)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.damping_min = 0.2
	pm.damping_max = 0.4
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0.75, 0.75, 0.75, 0.0), Color(0.8, 0.8, 0.8, 0.45), Color(0.9, 0.9, 0.9, 0.0)])
	gr.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	pm.color_ramp = gt
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = sc
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mt.vertex_color_use_as_albedo = true
	mt.albedo_color = Color.WHITE
	q.material = mt
	p.draw_pass_1 = q
	parent.add_child(p)
	return p


## Tek atimlik parca patlamasi (kartopu parcalanmasi, havai fisek).
func _burst(pos: Vector3, color: Color, amount: int, speed: float, life: float, size: float, glow: bool, grav := 5.0) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.6
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -grav, 0)
	pm.damping_min = 1.5 if glow else 0.0
	pm.damping_max = 2.5 if glow else 0.0
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	gr.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	pm.color_ramp = gt
	p.process_material = pm
	var sp := SphereMesh.new()
	sp.radius = size
	sp.height = size * 2.0
	sp.radial_segments = 6
	sp.rings = 3
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.vertex_color_use_as_albedo = true
	mt.albedo_color = color
	if glow:
		mt.emission_enabled = true
		mt.emission = color
		mt.emission_energy_multiplier = 3.0
	sp.material = mt
	p.draw_pass_1 = sp
	m.world.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(func(): if is_instance_valid(p): p.queue_free())


# ---------------------------------------------------------------- yaz: mangal ve piknik

func _build_picnic(w: Node3D, base: Vector2) -> void:
	_summer_root = Node3D.new()
	w.add_child(_summer_root)
	var p := _spot(base + Vector2(-16.0, 14.0), 5.5, 9.0)
	if p == Vector2.INF:
		return
	var fam := _spot(p + Vector2(15.0, 5.0), 4.5, 8.0)
	_make_picnic_site(p, _yaw(base - p), false)
	if fam != Vector2.INF:
		_make_picnic_site(fam, _yaw(p - fam), true)


func _make_picnic_site(p: Vector2, yaw: float, family: bool) -> void:
	var w: Node3D = m.world
	var r := Node3D.new()
	r.position = w.at(p)
	r.rotation.y = yaw
	_summer_root.add_child(r)
	# Battaniye (kareli) + minderler + sepet
	var bl := Kit.box(r, Vector3(2.6, 0.03, 2.0), Vector3(0, 0.02, 1.8), Kit.checker(Color("d8453c"), Color("f4ecd8"), 8, 6))
	bl.rotation.y = 0.06
	for i in 2:
		Kit.box(r, Vector3(0.5, 0.12, 0.5), Vector3(-0.7 + i * 1.3, 0.1, 2.2), Kit.mat(["3f7f9a", "e6b03a"][i], 0.9), Vector3(0, 0.3 * i, 0))
	Kit.box(r, Vector3(0.55, 0.3, 0.38), Vector3(0.2, 0.2, 1.4), Kit.mat("a8743d", 0.9))
	Kit.cyl(r, 0.07, 0.07, 0.3, Vector3(0.75, 0.2, 1.6), Kit.mat("3f7a52", 0.3), 8)
	Kit.cyl(r, 0.1, 0.1, 0.04, Vector3(-0.2, 0.06, 1.2), Kit.mat("f1ead8", 0.5), 12)
	# Mangal: demir govde, bacaklar, izgara teli, kor
	var steel := Kit.mat("2d2f34", 0.55)
	Kit.box(r, Vector3(1.0, 0.22, 0.5), Vector3(0, 0.8, 0), steel)
	for sx in [-0.45, 0.45]:
		for sz in [-0.2, 0.2]:
			Kit.cyl(r, 0.025, 0.025, 0.72, Vector3(sx, 0.38, sz), steel, 6)
	var ember := Kit.box(r, Vector3(0.9, 0.04, 0.4), Vector3(0, 0.88, 0), Kit.glow("ff4a12", 0.4))
	for i in 9:
		Kit.box(r, Vector3(0.012, 0.012, 0.5), Vector3(-0.4 + i * 0.1, 0.93, 0), Kit.mat("8a8d93", 0.4))
	for i in 5:
		Kit.cyl(r, 0.02, 0.02, 0.2, Vector3(-0.3 + i * 0.15, 0.97, 0.05 * (i % 2)), Kit.mat("7a3524", 0.7), 6).rotation.z = PI / 2.0
	var smoke := _smoke(r, Vector3(0, 1.0, 0), 28, 1.0)
	smoke.emitting = family
	if family:
		# Aile: baba mangalda, anne ve cocuklar battaniyede
		var man := _person("erkek", "4a6f99", "2b2f38")
		man.position = Vector3(0.9, 0, -0.5)
		man.rotation.y = PI * 0.8
		r.add_child(man)
		var mom := _person("kadin", "c9645a", "3b3b3b")
		mom.seated = true
		mom.position = Vector3(-0.9, 0.0, 2.0)
		mom.rotation.y = 0.5
		r.add_child(mom)
		for i in 2:
			var kid := _person(["erkek", "kadin"][i], ["e6b03a", "7a4aa8"][i], "3b4a6b", 0.62)
			kid.position = Vector3(1.1 - i * 0.5, 0, 1.8 + i * 0.3)
			kid.rotation.y = PI - 0.4 + i
			r.add_child(kid)
		ember.material_override = Kit.glow("ff4a12", 1.2)
	else:
		_mangal = {"pos": p + Vector2(0, 1.0).rotated(-yaw), "root": r, "smoke": smoke, "ember": ember, "grill_t": 0.0, "cooked": 0}
		var lb := Label3D.new()
		lb.text = "MANGAL KEYFİ"
		lb.font = preload("res://assets/fonts/Bangers-Regular.ttf")
		lb.font_size = 48
		lb.pixel_size = 0.006
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.position = Vector3(0, 2.0, 0)
		lb.modulate = Color("ffd23c")
		lb.outline_modulate = Color(0.1, 0.05, 0.02)
		lb.outline_size = 14
		r.add_child(lb)


func _inv() -> Dictionary:
	var s: Dictionary = state.d.get("seasons", {})
	state.d["seasons"] = s
	return s


func _mangal_near() -> bool:
	if _mangal.is_empty() or not _summer_root.visible or m._ride != null:
		return false
	return m._owner_pos().distance_to(_mangal["pos"]) < 2.6


func open_mangal() -> void:
	var ui: Node = m.ui
	var inv := _inv()
	var body: VBoxContainer = ui._open_panel("Mangal Keyfi", "Kömür %d · Et %d · Hazır %d porsiyon" % [int(inv.get("komur", 0)), int(inv.get("et", 0)), int(_mangal.get("cooked", 0))])
	ui._panel_item(body, "Kömür Al · 8 ₺", func(): _buy("komur", 8))
	ui._panel_item(body, "Köfte ve Et Al · 15 ₺", func(): _buy("et", 15))
	if int(inv.get("komur", 0)) > 0 and int(inv.get("et", 0)) > 0 and float(_mangal["grill_t"]) <= 0.0:
		ui._panel_item(body, "Mangalı Yak ve Pişir", func(): ui.close_modal(); start_grill())
	ui._panel_item(body, "Kapat", func(): ui.close_modal())
	ui._focus_first(body)


func _buy(what: String, price: int) -> void:
	if not state.spend(price):
		return
	var inv := _inv()
	inv[what] = int(inv.get(what, 0)) + 1
	m._sfx("para", -6.0)
	m.ui.toast("%s aldın" % ("Kömür" if what == "komur" else "Köfte ve et"))
	open_mangal()


func start_grill() -> void:
	var inv := _inv()
	if int(inv.get("komur", 0)) < 1 or int(inv.get("et", 0)) < 1:
		return
	inv["komur"] = int(inv["komur"]) - 1
	inv["et"] = int(inv["et"]) - 1
	_mangal["grill_t"] = GRILL_SECS
	m.ui.toast("Mangal yandı, et pişiyor…")
	m.owner_model.act("cook", 2.0)


func _eat_grilled() -> void:
	_mangal["cooked"] = int(_mangal["cooked"]) - 1
	m.owner_model.act("eat", 2.4)
	m.needs.add("hunger", 35.0)
	m.needs.add("energy", 4.0)
	var a: Node = m._active()
	if a != null:
		state.add_need(a.kind, "hunger", 18.0)
		state.add_need(a.kind, "fun", 10.0)
	m.ui.toast("Izgara köfte çok lezzetliydi! Hayvanın da payını aldı.")


# ---------------------------------------------------------------- yilbasi

func _build_newyear(w: Node3D, base: Vector2) -> void:
	_ny_root = Node3D.new()
	w.add_child(_ny_root)
	# Meydandaki buyuk agac
	var tp := _spot(base + Vector2(10.0, 12.0), 4.0, 9.0)
	if tp != Vector2.INF:
		_ny_tree_pos = tp
		_make_ny_tree(tp, 1.0)
		for i in 3:
			var q := _spot(tp + Vector2.from_angle(1.0 + i * 2.1) * 9.0, 2.0, 6.0)
			if q != Vector2.INF:
				_make_ny_tree(q, 0.45)
	# Sokak isik dizileri: yolun iki yanindaki direkler arasinda
	var cols := ["ffb347", "ff5a6a", "6ad1ff", "9dff8a"]
	var bulbs := [[], [], [], []]
	var placed: Array = []
	var ref := base
	var idxs := range(ParkMap.nodes.size())
	idxs.shuffle()
	var poles := Kit.mat("3b3d44", 0.6)
	for i in idxs:
		if placed.size() >= 9:
			break
		var np: Vector2 = ParkMap.nodes[i]
		if np.distance_to(ref) > 130.0 or ParkMap.links[i].size() < 2:
			continue
		var far := false
		for q in placed:
			if q.distance_to(np) < 30.0:
				far = true
		if far:
			continue
		var nb: int = ParkMap.links[i][0]
		var dir := (ParkMap.nodes[nb] - np).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var a := np + perp * 6.0
		var b := np - perp * 6.0
		if not (w.is_free(a, 0.3) and w.is_free(b, 0.3)) or w._inside_building(a) or w._inside_building(b):
			continue
		placed.append(np)
		var ya: float = w.gy(a)
		var yb: float = w.gy(b)
		for e in [a, b]:
			Kit.cyl(_ny_root, 0.07, 0.09, 6.2, w.at(e, 3.1), poles, 6)
		var n := 18
		for k in n + 1:
			var t := float(k) / n
			var pos := a.lerp(b, t)
			var hy := lerpf(ya, yb, t) + 5.9 - sin(t * PI) * 1.1
			bulbs[k % 4].append(Transform3D(Basis(), Vector3(pos.x, hy, pos.y)))
			if k % 6 == 3:
				var star := Kit.ball(_ny_root, 0.16, Vector3(pos.x, hy - 0.35, pos.y), Kit.glow("ffe27a", 2.5), Vector3(1, 1.3, 0.3), 6)
				star.rotation.y = _yaw(perp)
	var sp := SphereMesh.new()
	sp.radius = 0.07
	sp.height = 0.14
	sp.radial_segments = 6
	sp.rings = 3
	for c in 4:
		_multi(_ny_root, sp, Kit.glow(cols[c], 3.0), bulbs[c])


func _make_ny_tree(p: Vector2, sc: float) -> void:
	var w: Node3D = m.world
	var r := Node3D.new()
	r.position = w.at(p)
	r.scale = Vector3.ONE * sc
	_ny_root.add_child(r)
	var green := Kit.mat("1f5a34", 0.9)
	Kit.cyl(r, 0.25, 0.3, 0.8, Vector3(0, 0.4, 0), Kit.mat("5a3b22", 0.9), 8)
	var tiers := 5
	for i in tiers:
		var rad := 2.5 - i * 0.42
		Kit.cyl(r, 0.05, rad, 1.5, Vector3(0, 1.3 + i * 1.05, 0), green, 12)
	# Susler ve isik sarmali
	var cols := ["e63946", "f1c40f", "3a86ff", "ffffff", "ff7ac8"]
	var orn: Array = [[], [], [], [], []]
	var lights: Array = []
	for k in 46:
		var t := float(k) / 46.0
		var h := 1.2 + t * 4.9
		var rad := (2.45 - t * 2.15) * 0.92
		var ang := t * TAU * 4.5
		var pos := Vector3(cos(ang) * rad, h, sin(ang) * rad)
		if k % 2 == 0:
			lights.append(Transform3D(Basis(), pos))
		else:
			orn[(k / 2) % 5].append(Transform3D(Basis(), pos))
	var ball := SphereMesh.new()
	ball.radius = 0.14
	ball.height = 0.28
	ball.radial_segments = 8
	ball.rings = 4
	for c in 5:
		_multi(r, ball, Kit.mat(cols[c], 0.25), orn[c])
	var bulb := SphereMesh.new()
	bulb.radius = 0.06
	bulb.height = 0.12
	bulb.radial_segments = 5
	bulb.rings = 3
	_multi(r, bulb, Kit.glow("fff0a8", 4.0), lights)
	var star := Kit.ball(r, 0.34, Vector3(0, 6.4, 0), Kit.glow("ffd23c", 5.0), Vector3(1, 1, 0.35), 6)
	star.rotation.z = 0.3
	for i in 4:
		Kit.box(r, Vector3(0.7, 0.6, 0.6), Vector3(cos(i * 1.7) * 1.9, 0.3, sin(i * 1.7) * 1.9), Kit.mat(["c8323c", "2f5fa8", "e6b03a", "3f7f5a"][i], 0.6), Vector3(0, i, 0))
	var l := OmniLight3D.new()
	l.position = Vector3(0, 3.0, 0)
	l.light_color = Color("ffd9a0")
	l.light_energy = 1.4 * sc
	l.omni_range = 9.0 * sc
	r.add_child(l)
	if sc > 0.9:
		var lb := Label3D.new()
		lb.text = "MUTLU YILLAR"
		lb.font = preload("res://assets/fonts/Bangers-Regular.ttf")
		lb.font_size = 64
		lb.pixel_size = 0.008
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.position = Vector3(0, 7.4, 0)
		lb.modulate = Color("ffd23c")
		lb.outline_modulate = Color(0.45, 0.05, 0.05)
		lb.outline_size = 16
		r.add_child(lb)


func start_fireworks(secs := 45.0) -> void:
	_fw_t = secs
	m.ui.toast("Saat 00:00 · Mutlu yıllar! Yeni yılınız kutlu olsun!")


func _firework() -> void:
	var o: Vector2 = m._owner_pos()
	var a := randf() * TAU
	var d := randf_range(35.0, 75.0)
	var tp := o + Vector2.from_angle(a) * d
	var h := randf_range(38.0, 60.0)
	var base: Vector3 = m.world.at(tp)
	var col := Color.from_hsv(randf(), 0.75, 1.0)
	var rocket := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.25
	sp.height = 0.5
	sp.material = Kit.glow("ffe9a8", 6.0)
	rocket.mesh = sp
	m.world.add_child(rocket)
	rocket.position = base
	m._sfx("firlat", -8.0, randf_range(0.5, 0.8))
	var tw := create_tween()
	tw.tween_property(rocket, "position:y", base.y + h, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		var at: Vector3 = rocket.position
		rocket.queue_free()
		_burst(at, col, 140, 17.0, 2.4, 0.22, true, 4.0)
		_burst(at, col.lerp(Color.WHITE, 0.6), 50, 9.0, 1.8, 0.16, true, 3.0)
		var fl := OmniLight3D.new()
		fl.light_color = col
		fl.light_energy = 6.0
		fl.omni_range = 120.0
		m.world.add_child(fl)
		fl.position = at
		var t2 := create_tween()
		t2.tween_property(fl, "light_energy", 0.0, 1.2)
		t2.tween_callback(fl.queue_free))


# ---------------------------------------------------------------- kar: kardan adam, kartopu

func _near_snowman(o: Vector2, r: float) -> int:
	for i in snowmen.size():
		if o.distance_to(snowmen[i]["pos"]) < r:
			return i
	return -1


func _make_snowman_parts(root: Node3D, stage: int) -> void:
	var snow := Kit.mat("f4f8fc", 0.95)
	var part := Node3D.new()
	root.add_child(part)
	match stage:
		1:
			Kit.ball(part, 0.42, Vector3(0, 0.34, 0), snow, Vector3(1, 0.85, 1), 14)
		2:
			Kit.ball(part, 0.32, Vector3(0, 0.88, 0), snow, Vector3.ONE, 14)
			for i in 2:
				Kit.ball(part, 0.035, Vector3(0, 0.95 - i * 0.2, 0.31), Kit.mat("1a1a1a", 0.6), Vector3.ONE, 6)
		3:
			Kit.ball(part, 0.23, Vector3(0, 1.36, 0), snow, Vector3.ONE, 14)
			var coal := Kit.mat("15151a", 0.5)
			for sx in [-0.08, 0.08]:
				Kit.ball(part, 0.027, Vector3(sx, 1.42, 0.2), coal, Vector3.ONE, 6)
			for k in 5:
				var a := -0.5 + k * 0.25
				Kit.ball(part, 0.014, Vector3(sin(a) * 0.12, 1.3 - cos(a) * 0.03, 0.21), coal, Vector3.ONE, 4)
			Kit.cyl(part, 0.0, 0.035, 0.24, Vector3(0, 1.36, 0.3), Kit.mat("f07a1c", 0.6), 6).rotation.x = PI / 2.0
			Kit.cyl(part, 0.17, 0.17, 0.03, Vector3(0, 1.56, 0), coal, 12)
			Kit.cyl(part, 0.11, 0.11, 0.2, Vector3(0, 1.68, 0), coal, 12)
			Kit.torus(part, 0.045, 0.2, Vector3(0, 1.18, 0), Kit.mat("c8323c", 0.8))
			for sx in [-1.0, 1.0]:
				var arm := Kit.cyl(part, 0.012, 0.018, 0.7, Vector3(sx * 0.55, 0.98, 0), Kit.mat("5a3b22", 0.9), 5)
				arm.rotation.z = sx * -1.0
	part.scale = Vector3.ONE * 0.2
	create_tween().tween_property(part, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func make_snowman() -> void:
	var o: Vector2 = m._owner_pos()
	var p := o + _fwd() * 1.3
	var w: Node3D = m.world
	if not w.is_free(p, 0.4):
		p = o
	var root := Node3D.new()
	root.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
	root.rotation.y = _yaw(o - p) + 0.0
	w.add_child(root)
	snowmen.append({"root": root, "stage": 1, "pos": p})
	_make_snowman_parts(root, 1)
	m.owner_model.act("pet", 1.2)
	m._sfx("adim2", -6.0, 0.7)
	m.ui.toast("Kar topladın, kardan adamın gövdesini yuvarladın.")


func grow_snowman(i: int) -> void:
	if i < 0 or i >= snowmen.size():
		return
	var s: Dictionary = snowmen[i]
	if int(s["stage"]) >= 3:
		return
	s["stage"] = int(s["stage"]) + 1
	_make_snowman_parts(s["root"], int(s["stage"]))
	m.owner_model.act("pet", 1.2)
	if int(s["stage"]) == 2:
		m.ui.toast("Göbeği tamam, şimdi kafası kaldı.")
	else:
		m.ui.toast("Kardan adam hazır! Havaya girene kadar duracak.")
		state.count("snowman", 1)
		m._sfx("mutlu", -6.0)
		var a: Node = m._active()
		if a != null:
			state.add_need(a.kind, "fun", 15.0)


func throw_ball() -> void:
	if not snow_ok() or _ball_cd > 0.0 or m._mode != "play" or m._ride != null:
		if m._mode == "play" and not snow_ok() and m._ride == null:
			m.ui.toast("Kartopu için yerde kar olmalı")
		return
	_ball_cd = 0.4
	var o: Vector2 = m._owner_pos()
	var from := Vector3(o.x, m.owner_node.position.y + 1.4, o.y) + Vector3(_fwd().x, 0, _fwd().y) * 0.4
	var best: Node3D = null
	var bd := 24.0
	for n in m._npc_people:
		var d := Vector2(n.position.x, n.position.z).distance_to(o)
		if d < bd and d > 2.0 and _fwd().dot((Vector2(n.position.x, n.position.z) - o).normalized()) > 0.8:
			bd = d
			best = n
	var target := Vector3(o.x + _fwd().x * 12.0, from.y - 0.5, o.y + _fwd().y * 12.0)
	if best != null:
		target = Vector3(best.position.x, best.position.y + 1.1, best.position.z)
	m.owner_model.act("throw", 0.7)
	_launch(from, target, true)
	m._sfx("firlat", -9.0, 1.3)


func _launch(from: Vector3, to: Vector3, mine: bool) -> void:
	var ball := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.1
	sp.height = 0.2
	sp.radial_segments = 8
	sp.rings = 4
	sp.material = Kit.mat("ffffff", 0.9)
	ball.mesh = sp
	m.world.add_child(ball)
	ball.position = from
	var dv := to - from
	var flat := Vector2(dv.x, dv.z)
	var t := maxf(flat.length() / BALL_SPEED, 0.25)
	var vel := Vector3(dv.x / t, (dv.y + 0.5 * GRAVITY * t * t) / t, dv.z / t)
	_balls.append({"node": ball, "vel": vel, "mine": mine})


func _splat(p: Vector3) -> void:
	_burst(p, Color(0.95, 0.97, 1.0), 14, 3.2, 0.7, 0.05, false, 9.0)


func _update_balls(dt: float) -> void:
	var o: Vector2 = m._owner_pos()
	var op := Vector3(o.x, m.owner_node.position.y + 1.0, o.y)
	for i in range(_balls.size() - 1, -1, -1):
		var b: Dictionary = _balls[i]
		var n: Node3D = b["node"]
		var v: Vector3 = b["vel"]
		v.y -= GRAVITY * dt
		b["vel"] = v
		n.position += v * dt
		var hit := false
		if b["mine"]:
			for p in m._npc_people:
				if absf(p.position.y + 1.0 - n.position.y) < 1.1 and Vector2(p.position.x, p.position.z).distance_to(Vector2(n.position.x, n.position.z)) < 0.7:
					hit = true
					p.hold = 2.5
					p.hold_face = o
					m._say(p, ["Hey, ne yapıyorsun!", "Dur bakalım, ben de sana atarım!", "Ooo, kartopu savaşı mı?"][randi() % 3])
					var found := false
					for rv in _revenge:
						if rv["npc"] == p:
							rv["n"] = 3
							found = true
					if not found and _revenge.size() < 4:
						_revenge.append({"npc": p, "t": 1.8, "n": 3})
					break
		else:
			if n.position.distance_to(op) < 0.9:
				hit = true
				m.ui.toast(["Kartopu tam üstüne geldi!", "Bir çocuk seni vurdu!", "Ensene kar girdi, brr!"][randi() % 3])
				m._sfx("su_sicrama", -12.0, 1.4)
		if hit or n.position.y < ParkMap.terrain_height(Vector2(n.position.x, n.position.z)) + 0.05 or n.position.distance_to(op) > 120.0:
			_splat(n.position)
			n.queue_free()
			_balls.remove_at(i)


func _update_revenge(dt: float) -> void:
	for i in range(_revenge.size() - 1, -1, -1):
		var rv: Dictionary = _revenge[i]
		var p: Node3D = rv["npc"] if is_instance_valid(rv["npc"]) else null      # silinmis dugum turlu degiskene atanamaz
		if not is_instance_valid(p):
			_revenge.remove_at(i)
			continue
		rv["t"] = float(rv["t"]) - dt
		if float(rv["t"]) > 0.0:
			continue
		var o: Vector2 = m._owner_pos()
		var d := Vector2(p.position.x, p.position.z).distance_to(o)
		if d > 30.0 or not snow_ok():
			_revenge.remove_at(i)
			continue
		p.hold = 1.0
		p.hold_face = o
		_launch(p.position + Vector3(0, 1.3, 0), Vector3(o.x, m.owner_node.position.y + 1.0, o.y) + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)), false)
		rv["n"] = int(rv["n"]) - 1
		rv["t"] = randf_range(1.6, 2.8)
		if int(rv["n"]) <= 0:
			_revenge.remove_at(i)


func _update_snow(dt: float) -> void:
	var ok := snow_ok()
	if ok and not _snow_hint:
		_snow_hint = true
		m.ui.toast("Kar yağdı! F: kardan adam · Y: kartopu")
	# Eriyince kardan adamlar da gider; yarim kalanlar kuculur
	var cover: float = m.weather.cover
	if cover < 0.08 and not snowmen.is_empty():
		for s in snowmen:
			if is_instance_valid(s["root"]):
				s["root"].queue_free()
		snowmen.clear()
		m.ui.toast("Kar eridi, kardan adamlar da gitti…")
	else:
		var sc := clampf(cover * 2.0 + 0.2, 0.55, 1.0)
		for s in snowmen:
			if is_instance_valid(s["root"]):
				s["root"].scale = Vector3.ONE * sc
	if not ok:
		return
	# Gelip gecen cocuklar ara sira kartopu atar
	_npc_throw_t -= dt
	if _npc_throw_t <= 0.0:
		_npc_throw_t = randf_range(14.0, 28.0)
		var o: Vector2 = m._owner_pos()
		for n in m._npc_people:
			var d := Vector2(n.position.x, n.position.z).distance_to(o)
			if d > 7.0 and d < 22.0 and _revenge.size() < 3:
				_revenge.append({"npc": n, "t": 0.5, "n": 1})
				m._say(n, "Kartopu geliyor!")
				break
	# Buz: kosarken hafif kayma
	if m._ride == null and m.weather.temp < 2.0 and cover > 0.5:
		_slip_cd -= dt
		if _slip_t <= 0.0 and _slip_cd <= 0.0 and m.owner_model.speed > 2.4 and randf() < dt * 0.2:
			_slip_t = 0.55
			_slip_cd = randf_range(9.0, 18.0)
			_slip = _fwd().rotated(randf_range(-0.6, 0.6)) * 3.2
			m.ui.toast("Buz tutmuş, ayağın kaydı!")
	if _slip_t > 0.0:
		_slip_t -= dt
		var o2: Vector2 = m._owner_pos()
		var np := o2 + _slip * dt * (_slip_t / 0.55 + 0.3)
		if m.world.is_free(np, 0.4):
			m.owner_node.position.x = np.x
			m.owner_node.position.z = np.y


# ---------------------------------------------------------------- konvoy

func _make_horn() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 1.0)
	var buf := PackedByteArray()
	buf.resize(n * 2)
	# ta-ta-ta-taaa: iki tonlu korna
	var pat := [[0.0, 0.14], [0.2, 0.34], [0.4, 0.54], [0.6, 0.98]]
	for i in n:
		var t := float(i) / rate
		var on := 0.0
		for pp in pat:
			if t >= pp[0] and t < pp[1]:
				on = minf(minf((t - pp[0]) * 80.0, (pp[1] - t) * 80.0), 1.0)
		var s := sin(TAU * 410.0 * t) + 0.8 * sin(TAU * 515.0 * t)
		s = clampf(s * 1.4, -1.0, 1.0) * 0.45 * on
		buf.encode_s16(i * 2, int(s * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = buf
	return w


func _conv_path(o: Vector2) -> PackedVector2Array:
	var path := PackedVector2Array()
	var cur := ParkMap.nearest_node(o)
	var prev := -1
	# once oyuncudan uzaklas, sonra ona dogru gel ve gec
	for s in 14:
		var nx: Array = ParkMap.road_next[cur]
		var pick := -1
		for c in nx:
			if c != prev and (pick < 0 or ParkMap.nodes[c].distance_to(o) > ParkMap.nodes[pick].distance_to(o)):
				pick = c
		if pick < 0 or ParkMap.nodes[cur].distance_to(o) > 90.0:
			break
		prev = cur
		cur = pick
	var start := cur
	prev = -1
	path.append(ParkMap.nodes[cur])
	var passed := false
	for s in 70:
		var nx: Array = ParkMap.road_next[cur]
		if nx.is_empty():
			break
		var pick := -1
		var best := 1e9
		for c in nx:
			if c == prev and nx.size() > 1:
				continue
			var sc := ParkMap.nodes[c].distance_to(o) if not passed else randf() * 100.0
			if sc < best:
				best = sc
				pick = c
		if pick < 0:
			break
		prev = cur
		cur = pick
		path.append(ParkMap.nodes[cur])
		if ParkMap.nodes[cur].distance_to(o) < 18.0:
			passed = true
	if path.size() < 4 and start >= 0:
		return PackedVector2Array()
	return path


func start_convoy() -> void:
	if not _conv.is_empty():
		return
	var o: Vector2 = m._owner_pos()
	var path := _conv_path(o)
	if path.size() < 4:
		return
	if _horn == null:
		_horn = _make_horn()
	var cum: Array = [0.0]
	for i in range(1, path.size()):
		cum.append(float(cum[i - 1]) + path[i - 1].distance_to(path[i]))
	var cars: Array = []
	for i in 7:
		var c := _make_convoy_car(i)
		m.world.add_child(c)
		var pl: AudioStreamPlayer3D = null
		if i % 2 == 0:
			pl = AudioStreamPlayer3D.new()
			pl.stream = _horn
			pl.unit_size = 22.0
			pl.max_distance = 220.0
			pl.volume_db = -3.0
			c.add_child(pl)
		cars.append({"node": c, "d": -float(i) * 10.0, "horn": pl, "ht": randf() * 2.0, "flag": c.get_node("flag")})
	_conv = {"path": path, "cum": cum, "cars": cars, "speed": 10.5}
	m.ui.toast("Maç bitti! Cinaralti SK kazandı, taraftarlar kutlamada!".replace("Cinaralti", "Çınaraltı"))


func _make_convoy_car(i: int) -> Node3D:
	var r := Node3D.new()
	var body := Kit.mat(["d8d8dc", "22242a", "a8b2c0", "7a1c1c", "e8e0c8", "35527a", "6a6f78"][i % 7], 0.35)
	Kit.box(r, Vector3(1.8, 0.55, 4.1), Vector3(0, 0.6, 0), body)
	Kit.box(r, Vector3(1.6, 0.5, 2.1), Vector3(0, 1.1, -0.2), body)
	Kit.box(r, Vector3(1.62, 0.42, 1.9), Vector3(0, 1.12, -0.2), Kit.mat("1d2a38", 0.1))
	for sx in [-0.9, 0.9]:
		for sz in [-1.3, 1.3]:
			Kit.cyl(r, 0.33, 0.33, 0.25, Vector3(sx, 0.33, sz), Kit.mat("15151a", 0.8), 10).rotation.z = PI / 2.0
	for sx in [-0.6, 0.6]:
		Kit.box(r, Vector3(0.3, 0.14, 0.06), Vector3(sx, 0.7, 2.06), Kit.glow("fff4c8", 2.5))
		Kit.box(r, Vector3(0.3, 0.12, 0.06), Vector3(sx, 0.7, -2.06), Kit.glow("ff2020", 1.5))
	# Atkiyi: sol ve sag cama bayrak direkleri, tavanda sal
	var fl := Node3D.new()
	fl.name = "flag"
	fl.position = Vector3(0.88, 1.35, 0.1)
	r.add_child(fl)
	Kit.cyl(fl, 0.015, 0.015, 1.2, Vector3(0, 0.6, 0), Kit.mat("d8d8d8", 0.5), 5)
	Kit.box(fl, Vector3(0.03, 0.4, 0.7), Vector3(0, 1.0, -0.36), Kit.mat(CONVOY_COLORS[i % 2], 0.8))
	Kit.box(fl, Vector3(0.032, 0.2, 0.7), Vector3(0, 1.0, -0.36), Kit.mat(CONVOY_COLORS[(i + 1) % 2], 0.8))
	var fl2 := Node3D.new()
	fl2.position = Vector3(-0.88, 1.35, 0.1)
	r.add_child(fl2)
	Kit.cyl(fl2, 0.015, 0.015, 1.1, Vector3(0, 0.55, 0), Kit.mat("d8d8d8", 0.5), 5)
	Kit.box(fl2, Vector3(0.03, 0.35, 0.6), Vector3(0, 0.95, -0.32), Kit.mat(CONVOY_COLORS[(i + 1) % 2], 0.8))
	Kit.box(r, Vector3(1.4, 0.02, 0.35), Vector3(0, 0.89, 1.1), Kit.mat(CONVOY_COLORS[i % 2], 0.8))
	return r


func _update_convoy(dt: float) -> void:
	if _conv.is_empty():
		return
	var path: PackedVector2Array = _conv["path"]
	var cum: Array = _conv["cum"]
	var total: float = cum[cum.size() - 1]
	var alive := false
	for c in _conv["cars"]:
		c["d"] = float(c["d"]) + float(_conv["speed"]) * dt
		var d: float = c["d"]
		var n: Node3D = c["node"]
		if d < 0.0 or d > total - 1.0:
			n.visible = false
			if d <= total:
				alive = true
			continue
		alive = true
		n.visible = true
		var seg := 1
		while seg < cum.size() - 1 and float(cum[seg]) < d:
			seg += 1
		var a: Vector2 = path[seg - 1]
		var b: Vector2 = path[seg]
		var t := clampf((d - float(cum[seg - 1])) / maxf(float(cum[seg]) - float(cum[seg - 1]), 0.01), 0.0, 1.0)
		var dir := (b - a).normalized()
		var p := a.lerp(b, t) + Vector2(dir.y, -dir.x) * 1.9
		n.position = Vector3(p.x, ParkMap.terrain_height(p), p.y)
		n.rotation.y = lerp_angle(n.rotation.y, _yaw(dir), minf(1.0, dt * 6.0))
		c["flag"].rotation.x = sin(Time.get_ticks_msec() * 0.012 + d) * 0.25
		n.position.y += absf(sin(Time.get_ticks_msec() * 0.008 + d)) * 0.02
		var pl: AudioStreamPlayer3D = c["horn"]
		if pl != null:
			c["ht"] = float(c["ht"]) - dt
			if float(c["ht"]) <= 0.0:
				c["ht"] = randf_range(1.6, 3.6)
				pl.pitch_scale = randf_range(0.9, 1.15)
				pl.play()
	if not alive:
		for c in _conv["cars"]:
			c["node"].queue_free()
		_conv.clear()


func _update_convoy_spawn(dt: float) -> void:
	_conv_cd -= dt
	if _conv_cd > 0.0 or not _conv.is_empty():
		return
	_conv_cd = 25.0
	var h: float = m.clock
	if (h >= 21.0 or h < 1.0) and m._mode == "play" and ParkMap.home == null and m._ride == null and randf() < 0.12:
		start_convoy()
		_conv_cd = 420.0


# ---------------------------------------------------------------- baglam / komut

func context() -> Array:
	if m._ride != null or m._taxi != null or ParkMap.home != null:
		return []
	var o: Vector2 = m._owner_pos()
	if _mangal_near():
		if float(_mangal["grill_t"]) > 0.0:
			return ["Et pişiyor… %d sn" % int(ceil(float(_mangal["grill_t"]))), "", "bone"]
		if int(_mangal["cooked"]) > 0:
			return ["Izgara Köfte Ye · %d porsiyon" % int(_mangal["cooked"]), "ss_eat", "bone"]
		var inv := _inv()
		if int(inv.get("komur", 0)) > 0 and int(inv.get("et", 0)) > 0:
			return ["Mangalı Yak ve Et Pişir", "ss_grill", "bolt"]
		return ["Mangal · Kömür ve Et Al", "ss_shop", "bag"]
	if snow_ok():
		var i := _near_snowman(o, 1.9)
		if i >= 0 and int(snowmen[i]["stage"]) < 3:
			return ["Kardan Adamı Büyüt (%d/3)" % int(snowmen[i]["stage"]), "ss_snow_grow:%d" % i, "plus"]
	return []


## Baska bir sey yokken: karda kardan adam yap.
func fallback() -> Array:
	if m._ride == null and m._taxi == null and snow_ok() and _near_snowman(m._owner_pos(), 3.0) < 0 and m.owner_model.speed < 0.5:
		return ["Kardan Adam Yap · Y: Kartopu", "ss_snow_make", "star"]
	return []


func command(cmd: String) -> void:
	match cmd:
		"ss_snow_make":
			make_snowman()
		"ss_shop":
			open_mangal()
		"ss_grill":
			start_grill()
		"ss_eat":
			_eat_grilled()
		"ss_ball":
			throw_ball()
		_:
			if cmd.begins_with("ss_snow_grow:"):
				grow_snowman(int(cmd.substr(13)))


## Telefonda "Kis Oyunlari" uygulamasi (dokunmatik icin).
func phone_app() -> void:
	var ui: Node = m.ui
	var body: VBoxContainer = ui._open_panel("Kış Oyunları", "Kar yerde: kartopu ve kardan adam")
	ui._panel_item(body, "Kartopu At (Y)", func(): ui.close_modal(); throw_ball())
	ui._panel_item(body, "Kardan Adam Yap", func(): ui.close_modal(); make_snowman())
	ui._panel_item(body, "Kapat", func(): ui.close_modal())
	ui._focus_first(body)


# ---------------------------------------------------------------- dongu

func update(dt: float) -> void:
	_ball_cd = maxf(_ball_cd - dt, 0.0)
	_season_t -= dt
	if _season_t <= 0.0:
		_season_t = 3.0
		_apply_season()
	_update_snow(dt)
	_update_balls(dt)
	_update_revenge(dt)
	_update_convoy(dt)
	_update_convoy_spawn(dt)
	# Mangal
	if not _mangal.is_empty():
		var gt: float = _mangal["grill_t"]
		if gt > 0.0:
			gt -= dt
			_mangal["grill_t"] = gt
			_mangal["smoke"].emitting = true
			_mangal["ember"].material_override = Kit.glow("ff5a1a", 0.8 + randf() * 1.6)
			if gt <= 0.0:
				_mangal["cooked"] = int(_mangal["cooked"]) + 3
				_mangal["smoke"].emitting = false
				_mangal["ember"].material_override = Kit.glow("ff4a12", 0.4)
				m.ui.toast("Izgara hazır! 3 porsiyon köfte pişti.")
				state.count("grill", 1)
	# Gece yarisi
	var c: float = m.clock
	if _prev_clock > 22.0 and c < 2.0 and is_newyear() and ParkMap.home == null:
		start_fireworks()
	_prev_clock = c
	if _fw_t > 0.0 and ParkMap.home == null:
		_fw_t -= dt
		if randf() < dt * 1.6:
			_firework()


# ---------------------------------------------------------------- test

func debug(args: Dictionary) -> void:
	var o: Vector2 = m._owner_pos()
	if args.has("snowman"):
		m.weather.force("snow")
		m.weather.cover = 0.9
		m.weather.snow = 0.6
		await get_tree().create_timer(1.0).timeout
		o = m._owner_pos()
		for k in 3:
			var p := o + Vector2(2.2 + k * 1.6, 1.0 + k * 0.7)
			var root := Node3D.new()
			root.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
			root.rotation.y = 0.5
			m.world.add_child(root)
			snowmen.append({"root": root, "stage": 3 - k, "pos": p})
			for st in range(1, 4 - k):
				_make_snowman_parts(root, st)
		_launch(Vector3(o.x + 3.0, 2.0, o.y - 4.0), Vector3(o.x + 0.5, 1.2, o.y), false)
		_launch(Vector3(o.x, 1.5, o.y), Vector3(o.x + 4.0, 1.0, o.y + 6.0), true)
	elif args.has("mangal"):
		f_summer = true
		_apply_season()
		if not _mangal.is_empty():
			var mp: Vector2 = _mangal["pos"]
			m._place_owner(mp + Vector2(1.5, 1.0))
			m._focus = m.owner_node.position
		var inv := _inv()
		inv["komur"] = 1
		inv["et"] = 1
		await get_tree().create_timer(1.0).timeout
		start_grill()
	elif args.has("yilbasi"):
		f_newyear = true
		_apply_season()
		if _ny_tree_pos != Vector2.INF:
			m._place_owner(_ny_tree_pos + Vector2(-7.0, 4.0))
			m._focus = m.owner_node.position
		m.clock = 23.9
		await get_tree().create_timer(2.0).timeout
		start_fireworks(30.0)
	elif args.has("konvoy"):
		m.clock = 22.0
		await get_tree().create_timer(1.0).timeout
		start_convoy()
		if not _conv.is_empty():
			for c in _conv["cars"]:
				c["d"] = float(c["d"]) + 60.0
