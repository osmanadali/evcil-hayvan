extends Node
## Sigara (yetiskin yasam simulasyonu). Uydurma markalar: "Kervan", "Yayla".
## - Marketten (bakkal / market rafinda, kasanin yaninda) "Sigara Paketi" (20 dal) ve "Çakmak" alinir; cantaya girer.
## - B tusu (Ayarlar > Kontroller'de "SİGARA YAK / SÖNDÜR") ya da cantadan / telefondan "Sigara Paketi" ile yakilir.
##   Karakter sol elini agzina goturur (person_model.mouth_w), uctaki kor nefeste parlar, duman cikar.
##   Bir sigara ~40 sn surer; yururken de icilir. B ya da F (yakinda baska etkilesim yoksa) ile sondurulur.
## - Etki: kisa sure enerji / keyif (+), uzun vadede "zarar" birikir: kosarken enerji daha hizli biter, oksuruk.
## - Kapali yerlerde (dukkan, lokanta, otel, metro, otobus, taksi, hayvan binmis arac) icilmez: uyari.
## - Kayit: state.d["smoke"] = {left: acik paketteki dal, total: icilen, harm: birikmis zarar}

const Kit = preload("res://scripts/kit.gd")
const PACK := "Sigara Paketi"
const LIGHTER := "Çakmak"
const PER_PACK := 20
const DURATION := 40.0
const PUFF_EVERY := 6.5
const ENERGY_GAIN := 6.0          # bir sigara boyunca toplam
const HARM_PER := 1.0             # her sigara
const HARM_DECAY := 0.12          # dakikada (gercek zaman)

var m: Node
var state: Node
var active := false
var _t := 0.0                     # yakali beri gecen sure
var _puff_t := 0.0
var _puff := 0.0                  # 0..1 nefes egrisi
var _cig: Node3D
var _paper: MeshInstance3D
var _ember: MeshInstance3D
var _ember_mat: StandardMaterial3D
var _light: OmniLight3D
var _smoke: CPUParticles3D        # uctan ince duman
var _exhale: CPUParticles3D       # agizdan nefes
var _cough_t := 90.0
var _warn_t := 0.0


func _d() -> Dictionary:
	if not state.d.has("smoke") or typeof(state.d["smoke"]) != TYPE_DICTIONARY:
		state.d["smoke"] = {"left": 0, "total": 0, "harm": 0.0}
	return state.d["smoke"]


func _bag() -> Dictionary:
	if not state.d.has("bag"):
		state.d["bag"] = {}
	return state.d["bag"]


func packs() -> int:
	return int(_bag().get(PACK, 0))


func has_lighter() -> bool:
	return int(_bag().get(LIGHTER, 0)) > 0


## Kalan toplam dal: acik paket + kapali paketler.
func sticks() -> int:
	var left := int(_d().get("left", 0))
	var p := packs()
	# Acik paket cantadaki paketlerden biri sayilir
	return left + maxi(p - (1 if left > 0 else 0), 0) * PER_PACK


func harm() -> float:
	return float(_d().get("harm", 0.0))


## Kisa durum metni (telefon / canta).
func status() -> String:
	return "%d paket · açık pakette %d dal · çakmak %s" % [packs(), int(_d().get("left", 0)), "var" if has_lighter() else "yok"]


# ---------------------------------------------------------------- kurallar

## Icilemeyen yer: neden metni; bos ise icilebilir.
func blocked_reason() -> String:
	var PM = preload("res://scripts/park_map.gd")
	if m._mode == "metro":
		return "Metroda sigara içilmez."
	if m._mode != "play":
		return "Şu an sigara yakamazsın."
	if m._bus_ride != null:
		return "Toplu taşımada sigara içilmez."
	if m._taxi != null:
		return "Takside sigara içilmez, şoför izin vermiyor."
	if m._shop != null and PM.home == m._shop:
		return "Kapalı alanda sigara içilmez. Dışarı çık." if m._shop.kind != "lokanta" else "Lokantada sigara içilmez. Dışarı çık."
	if PM.home != null and PM.home != m._home:
		return "Kapalı alanda sigara içilmez. Dışarı çık."
	if m._ride != null and not m.life._pet.is_empty():
		return "Araçta dostun var, onun yanında sigara içilmez."
	if m.needs.busy() or m.life.busy():
		return "Şu an sigara yakamazsın."
	return ""


func toggle() -> void:
	if active:
		stop(true)
	else:
		light()


func light() -> bool:
	if active:
		return true
	var why := blocked_reason()
	if why != "":
		m.ui.toast(why)
		return false
	var d := _d()
	if int(d.get("left", 0)) <= 0:
		if packs() <= 0:
			m.ui.toast("Sigaran yok. Marketten (kasanın yanındaki raftan) paket alabilirsin.")
			return false
		d["left"] = PER_PACK          # yeni paket acildi (paket cantada kalir, bitince duser)
	if not has_lighter():
		m.ui.toast("Çakmağın yok. Marketten çakmak al.")
		return false
	d["left"] = int(d["left"]) - 1
	d["total"] = int(d.get("total", 0)) + 1
	if int(d["left"]) <= 0:
		_bag()[PACK] = packs() - 1     # paket bitti
		if packs() <= 0:
			_bag().erase(PACK)
		d["left"] = 0
	active = true
	_t = 0.0
	_puff_t = 1.2
	_build_cig()
	m.owner_model.act("sip", 1.2)       # yakarken el agza gider
	m._sfx("tik", -10.0, 1.6)
	state.save_game()
	var msg := "Sigarayı yaktın. (B ya da F: söndür)"
	if int(d["left"]) <= 0:
		msg = "Paketteki son sigarayı yaktın. " + ("Kalan paket: %d" % packs() if packs() > 0 else "Paketin bitti.")
	m.ui.toast(msg)
	return true


func stop(by_hand := false) -> void:
	if not active:
		return
	active = false
	m.owner_model.mouth_w = 0.0
	if _cig and is_instance_valid(_cig):
		# Duman biraz daha suzulsun, sonra kaybolsun
		var c := _cig
		_ember.visible = false
		_light.visible = false
		_smoke.emitting = false
		_exhale.emitting = false
		_paper.visible = false
		get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(c): c.queue_free())
	_cig = null
	if by_hand:
		m.ui.toast("Sigarayı söndürdün.")
	state.save_game()


# ---------------------------------------------------------------- canta / komut

## Cantadan kullanim: paket yakar, cakmak bilgi verir. Canta adedi geri eklenir (paket dal dal azalir).
func use_item(name: String) -> bool:
	if name != PACK and name != LIGHTER:
		return false
	_bag()[name] = int(_bag().get(name, 0)) + 1
	if name == LIGHTER:
		m.ui.toast("Çakmağın çantanda. Sigara yakmak için B'ye bas.")
		return true
	m.ui.close_modal()
	if active:
		m.ui.toast("Zaten sigara içiyorsun.")
	else:
		light()
	return true


func phone_app() -> void:
	var d := _d()
	var body: VBoxContainer = m.ui._open_panel("SİGARA", status())
	var l := Label.new()
	l.text = "Toplam içilen: %d dal · Akciğer yükü: %s" % [int(d.get("total", 0)), _harm_text()]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 20)
	body.add_child(l)
	if active:
		m.ui._panel_item(body, "Söndür", func():
			m.ui.close_modal()
			stop(true))
	elif sticks() > 0:
		m.ui._panel_item(body, "Bir Sigara Yak (%s)" % key_hint(), func():
			m.ui.close_modal()
			light())
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func key_hint() -> String:
	return preload("res://scripts/keybinds.gd").primary("smoke")


func _harm_text() -> String:
	var h := harm()
	if h < 3.0:
		return "temiz"
	if h < 8.0:
		return "hafif"
	if h < 15.0:
		return "orta · koşunca çabuk yorulursun"
	return "ağır · öksürük, nefes darlığı"


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	var d := _d()
	# Uzun vadeli zarar yavasca azalir (icmeyi birakinca vucut toparlanir)
	d["harm"] = maxf(float(d.get("harm", 0.0)) - HARM_DECAY * dt / 60.0, 0.0)
	if m._mode == "play" and not m.needs.busy():
		var h := harm()
		var running: bool = m._ride == null and m.owner_model.speed > 3.4
		if running and h > 5.0:
			m.needs.add("energy", -minf(h / 10.0, 2.5) * dt / 60.0 * 1.5)
		if h > 12.0:
			_cough_t -= dt * (h / 12.0)
			if _cough_t <= 0.0:
				_cough_t = randf_range(70.0, 130.0)
				_cough()
	if not active:
		return
	if _cig == null or not is_instance_valid(_cig):
		active = false
		return
	_warn_t -= dt
	var why := blocked_reason()
	if why != "" and m._mode == "play":
		stop(false)
		m.ui.toast(why + " Sigarayı söndürdün.")
		return
	_t += dt
	var k := clampf(_t / DURATION, 0.0, 1.0)
	# Sigara kisalir (kagit kismi), kor geri cekilir
	var L := lerpf(0.062, 0.012, k)
	(_paper.mesh as CylinderMesh).height = L
	_paper.position.y = 0.022 + L * 0.5
	_ember.position.y = 0.022 + L + 0.003
	_smoke.position = _ember.position
	_light.position = _ember.position
	# Nefes: el agza gider, kor parlar, sonra agizdan duman
	_puff_t -= dt
	var walking: bool = m.owner_model.speed > 0.3
	if _puff_t <= 0.0 and m._ride == null:
		_puff_t = PUFF_EVERY * randf_range(0.85, 1.2)
		_puff = 0.001
	if _puff > 0.0:
		_puff += dt / (1.6 if not walking else 1.4)
		if _puff >= 1.0:
			_puff = 0.0
			_exhale_now()
	var w := clampf(sin(_puff * PI) * 1.5, 0.0, 1.0) if _puff > 0.0 else 0.0
	m.owner_model.mouth_w = w
	var glow := 1.0 + 5.0 * w
	_ember_mat.emission_energy_multiplier = glow
	_light.light_energy = 0.15 + 0.6 * w
	# Etki: sigara boyunca yavasca enerji
	m.needs.add("energy", ENERGY_GAIN * dt / DURATION)
	if _t >= DURATION:
		d["harm"] = float(d.get("harm", 0.0)) + HARM_PER
		stop(false)
		m.ui.toast("Sigara bitti, izmariti çöpe attın. (%s)" % ("kalan %d dal" % sticks() if sticks() > 0 else "sigaran kalmadı"))
		for kk in m.agents:
			state.add_need(kk, "fun", -2.0)     # dostun dumandan pek hoslanmadi


func _exhale_now() -> void:
	if _exhale == null:
		return
	_exhale.restart()
	_exhale.emitting = true


func _cough() -> void:
	var lb := Label3D.new()
	lb.text = "öhö öhö"
	lb.font_size = 56
	lb.pixel_size = 0.004
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.outline_size = 12
	lb.no_depth_test = true
	lb.position = Vector3(0.2, 1.85, 0)
	m.owner_node.add_child(lb)
	get_tree().create_timer(2.2).timeout.connect(func(): if is_instance_valid(lb): lb.queue_free())
	m.ui.toast("Öksürdün. Çok sigara içmek nefesini daraltıyor.")


# ---------------------------------------------------------------- model

func _build_cig() -> void:
	if _cig and is_instance_valid(_cig):
		_cig.queue_free()
	_cig = Node3D.new()
	m.owner_model.hand.add_child(_cig)
	# Isaret ve orta parmak arasinda; avuctan disari, parmak yonune dogru
	_cig.position = Vector3(0.0, 0.02, 0.025)
	_cig.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	var filt := Kit.cyl(_cig, 0.0048, 0.0048, 0.022, Vector3(0, 0.011, 0), Kit.mat("c98a3e", 0.7), 10)
	filt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := CylinderMesh.new()
	pm.top_radius = 0.0046
	pm.bottom_radius = 0.0046
	pm.height = 0.062
	pm.radial_segments = 10
	pm.rings = 1
	_paper = Kit.add(_cig, pm, Kit.mat("f4f1ea", 0.8), Vector3(0, 0.022 + 0.031, 0))
	_paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ember_mat = StandardMaterial3D.new()
	_ember_mat.albedo_color = Color("ff5a1a")
	_ember_mat.emission_enabled = true
	_ember_mat.emission = Color("ff4a10")
	_ember_mat.emission_energy_multiplier = 1.0
	var em := CylinderMesh.new()
	em.top_radius = 0.0042
	em.bottom_radius = 0.0046
	em.height = 0.006
	em.radial_segments = 10
	em.rings = 1
	_ember = Kit.add(_cig, em, _ember_mat, Vector3(0, 0.022 + 0.062 + 0.003, 0))
	_ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.light_color = Color("ff7a30")
	_light.omni_range = 0.35
	_light.light_energy = 0.15
	_light.shadow_enabled = false
	_cig.add_child(_light)
	_light.position = _ember.position
	_smoke = _make_smoke(false)
	_cig.add_child(_smoke)
	_smoke.position = _ember.position
	_exhale = _make_smoke(true)
	_exhale.emitting = false
	m.owner_model.add_child(_exhale)
	_exhale.position = Vector3(0, 1.58, -0.16)    # agzin onu (model -Z'ye bakar)


func _make_smoke(burst: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.local_coords = false
	p.amount = 26 if burst else 40
	p.lifetime = 2.2 if burst else 3.0
	p.one_shot = burst
	p.explosiveness = 0.7 if burst else 0.0
	p.emitting = true
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06) if burst else Vector2(0.035, 0.035)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff_tex()
	q.material = mat
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if burst:
		p.direction = Vector3(0, 0.25, -1)
		p.spread = 22.0
		p.initial_velocity_min = 0.35
		p.initial_velocity_max = 0.7
		p.damping_min = 0.4
		p.damping_max = 0.8
	else:
		p.direction = Vector3.UP
		p.spread = 8.0
		p.initial_velocity_min = 0.08
		p.initial_velocity_max = 0.16
	p.gravity = Vector3(0, 0.12, 0)
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.4))
	sc.add_point(Vector2(1.0, 3.2 if burst else 4.0))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.86, 0.9, 0.0))
	g.set_color(1, Color(0.8, 0.82, 0.86, 0.0))
	g.add_point(0.12, Color(0.86, 0.87, 0.9, 0.55 if burst else 0.4))
	p.color_ramp = g
	return p


static var _tex: ImageTexture


## Yumusak kenarli yuvarlak duman lekesi.
func _puff_tex() -> ImageTexture:
	if _tex:
		return _tex
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_tex = ImageTexture.create_from_image(img)
	return _tex


# ---------------------------------------------------------------- test

## Test: cantaya paket ve cakmak koy, sigarayi yak. mode "walk": karakter ileri yurur.
func debug(mode: String) -> void:
	_bag()[PACK] = 1
	_bag()[LIGHTER] = 1
	await get_tree().create_timer(1.0).timeout
	var ok := light()
	print("SIGARA yakildi=", ok, " ", status(), " dal=", sticks())
	if mode == "walk":
		m.owner_model.force_speed = 1.3


func _process(_dt: float) -> void:
	# Metroda main.update calismaz: binerken sigara sonsun
	if active and m != null and m._mode == "metro":
		stop(false)
		m.ui.toast("Metroda sigara içilmez, söndürdün.")
