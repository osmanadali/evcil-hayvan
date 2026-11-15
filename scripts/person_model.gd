extends Node3D
## Insan modeli: MakeHuman verisinden tools/make_human.py ile uretilir (CC0), Mixamo adli iskelet.
## Hareketler kodla verilir. Model +Z'ye bakar (sol = +X); dugum PI dondurulur, yonu -Z.

const X := Vector3.RIGHT
const Y := Vector3.UP
const Z := Vector3.BACK
const FINGERS := ["Index", "Middle", "Ring", "Pinky"]

signal stepped            # ayak yere bastiginda

var kind := "kadin"
# Yeniden olusturmada isleyici uyarisi vermemesi icin malzemeler canli tutulur
static var _keep: Array = []

var speed := 0.0
var force_speed := -1.0   # test: animasyonu bu hizla oynat
var riding := ""          # "bisiklet" / "scooter": oturma ve pedal pozu
var ride_speed := 0.0
var ride_lean := -1.0      # surucunun one egilmesi (radyan); -1 = varsayilan
var grips: Array = []     # [sol, sag] gidon tutaclarinin dunya konumu (surerken)
var grip_palms: Array = []   # araba: [sol, sag] avuc icinin bakacagi dunya yonu (simidin merkezine dogru)
var grip_fwd := Vector3.ZERO # araba: direksiyon ekseninin surucuden uzaga bakan dunya yonu
var ride_feet := Vector3.ZERO    # ayak bileginin arac uzayindaki yeri (x = yarim aciklik); sifir = serbest poz
var ride_crank := Vector3.ZERO   # bisiklet: (pedal yarim acikligi, orta gobek y, orta gobek z); pedal dairesi
var ride_crank_r := 0.16
const FOOT_RIDES := ["bisiklet", "motosiklet", "scooter"]
var _lean_key := ""
var _lean_auto := 0.0
var _palm := {}           # taraf -> dinlenme durusunda avuc cercevesi (x: parmak yonu, y: avuc ici yonu)
var hand_twist := 1.2     # avucu asagi cevirmek icin on kol donusu
var _pedal := 0.0
var _arm_in := 0.0          # yuruyuste ust kollarin govdeye yaklastirilmasi (radyan)
const AnimRetarget = preload("res://scripts/anim_retarget.gd")
var anim: Node                 # hazir animasyonlar (yoksa kodla poz)
var use_anims := true
var airborne := false
var seated := false            # taburede / sandalyede oturuyor (Sitting_Idle)
var sit_exit := false          # oturmaktan kalkiyor (Sitting_Exit)
var _seat_t := 0.0             # oturali beri gecen sure (Sitting_Enter gecisi)
var _lod_i := randi() % 4          # ziplarken (main ayarlar)
var _anim_wait := 2            # ilk karelerde kodla notr poz kurulur, sonra animasyona gecilir
const ACT_CLIPS := {"pet": "PickUp_Table", "feed": "PickUp_Table", "wave": "Interact", "throw": "Interact",
	"eat": "Interact", "sit": "Sitting_Idle", "cook": "Interact"}
var tint := Color.WHITE   # tisort rengi
var tint2 := Color.WHITE  # desen ikinci rengi
var pattern := 0          # 0 duz, 1 cizgili, 2 kareli
var pants := Color(0, 0, 0, 0)   # a = 0: kot pantolon oldugu gibi
var hand: Node3D          # elde tasinan esya icin

var _skel: Skeleton3D
var _bones := {}
var _down := {}           # kolu A durusundan asagi indiren donus
var _fix := {}            # diger kemiklerin durus duzeltmeleri
var _phase := 0.0
var _t := 0.0
var _move := 0.0
var _act := ""
var _act_t := 1.0
var _act_d := 1.0


func _ready() -> void:
	_t = randf() * 10.0
	var model: Node3D = load("res://assets/models/%s.glb" % kind).instantiate()
	model.rotation.y = PI
	add_child(model)
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in _skel.get_bone_count():
		_bones[_skel.get_bone_name(i)] = i
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		_dress(mi)
	# Dinlenme durusunda kollar acik, dirsekler bukuk, bacaklar ayrik: hepsini duzelt
	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var arm_want := Vector3(sx * 0.13, -1.0, 0.0).normalized()
		var leg_want := Vector3(sx * 0.03, -1.0, 0.0).normalized()
		var d := Quaternion(_dir(side + "Arm", side + "ForeArm"), arm_want)
		_down[side] = d
		_fix[side + "ForeArm"] = Quaternion(_dir(side + "ForeArm", side + "Hand"), d.inverse() * arm_want)
		var u := Quaternion(_dir(side + "UpLeg", side + "Leg"), leg_want)
		_fix[side + "UpLeg"] = u
		_fix[side + "Leg"] = Quaternion(_dir(side + "Leg", side + "Foot"), u.inverse() * leg_want)
		_fix[side + "Foot"] = (u * _fix[side + "Leg"]).inverse()
		# Avuc cercevesi: parmak yonu ve avuc icinin baktigi yon (dinlenme durusunda avuc asagi bakar)
		var hp := _skel.get_bone_global_rest(_bones[side + "Hand"]).origin
		var pf := (_skel.get_bone_global_rest(_bones[side + "HandMiddle1"]).origin - hp).normalized()
		var pn := (_skel.get_bone_global_rest(_bones[side + "HandIndex1"]).origin - hp).cross(_skel.get_bone_global_rest(_bones[side + "HandPinky1"]).origin - hp)
		pn = (pn - pf * pn.dot(pf)).normalized()
		if pn.y > 0.0:
			pn = -pn
		_palm[side] = Basis(pf, pn, pf.cross(pn))
	var ba := BoneAttachment3D.new()
	ba.bone_name = "LeftHand"
	_skel.add_child(ba)
	hand = Node3D.new()
	hand.position = Vector3(0, 0.08, 0)
	ba.add_child(hand)


func _dress(mi: MeshInstance3D) -> void:
	var part := String(mi.name).to_lower()
	var src: BaseMaterial3D = mi.get_active_material(0)
	var m: Material
	if part.begins_with("giysi"):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/cloth.gdshader")
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		sm.set_shader_parameter("normal_tex", src.normal_texture)
		sm.set_shader_parameter("shirt", tint)
		sm.set_shader_parameter("shirt2", tint2)
		sm.set_shader_parameter("pattern", pattern)
		sm.set_shader_parameter("pants", pants)
		m = sm
	else:
		var bm: BaseMaterial3D = src.duplicate()
		bm.roughness = 0.75
		bm.metallic_specular = 0.25
		if part.begins_with("sac"):
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			bm.roughness = 0.55
			# Sac rengi tisort rengine bagli degissin (herkes ayni olmasin)
			var k := fposmod(tint.r * 3.0 + tint.g * 5.0 + tint.b * 7.0, 1.0)
			bm.albedo_color = Color(0.45, 0.33, 0.25).lerp(Color(1.0, 0.92, 0.8), k)
		elif part.begins_with("kas") or part.begins_with("kirpik"):
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif part.begins_with("goz"):
			bm.roughness = 0.2
		elif part.begins_with("govde"):
			bm.roughness = 0.62
		m = bm
	mi.set_surface_override_material(0, m)
	_keep.append(m)


func _dir(a: String, b: String) -> Vector3:
	return (_skel.get_bone_global_rest(_bones[b]).origin - _skel.get_bone_global_rest(_bones[a]).origin).normalized()


## Kemigi iskelet uzayindaki donuslerle cevirir; listedeki son donus once uygulanir.
func _turn(bone: String, turns: Array) -> void:
	var i: int = _bones[bone]
	var g := _skel.get_bone_global_rest(i).basis.get_rotation_quaternion()
	var gi := g.inverse()
	var q := _skel.get_bone_rest(i).basis.get_rotation_quaternion()
	for t in turns:
		var r: Quaternion = t if t is Quaternion else Quaternion((t[0] as Vector3).normalized(), t[1])
		q = q * (gi * r * g)
	_skel.set_bone_pose_rotation(i, q)


## Tek seferlik hareket: "throw" (firlat), "pet" (egilip sev), "wave" (el salla), "feed" (mama koy)
## Kiyafeti degistir (dolaptan): tisort, desen ve pantolon.
func set_outfit(shirt: Color, shirt2: Color, pat: int, pant: Color) -> void:
	tint = shirt
	tint2 = shirt2
	pattern = pat
	pants = pant
	for m in _keep:
		if m is ShaderMaterial:
			m.set_shader_parameter("shirt", tint)
			m.set_shader_parameter("shirt2", tint2)
			m.set_shader_parameter("pattern", pattern)
			m.set_shader_parameter("pants", pants)


func act(what: String, duration := 0.9) -> void:
	_act = what
	_act_t = 0.0
	_act_d = duration


func is_acting() -> bool:
	return _act_t < 1.0


func _process(dt: float) -> void:
	_t += dt
	if force_speed >= 0.0:
		speed = force_speed
	var run := clampf((speed - 2.0) / 2.2, 0.0, 1.0)
	_move = move_toward(_move, clampf(speed / 1.0, 0.0, 1.0), dt * 5.0)
	var move := _move
	if speed > 0.05:
		var before := _phase
		_phase += dt * PI * speed / lerpf(0.72, 1.35, run)
		if floorf(_phase / PI + 0.5) != floorf(before / PI + 0.5):
			stepped.emit()
	_act_t = minf(_act_t + dt / _act_d, 1.0)
	if riding != "":
		if anim and riding == "araba":
			anim.play("Driving", 0.2)
			anim.apply()
			# Govde simide dogru hafifce egilir, bas dik kalir
			_swing("Spine", 0.2)
			_swing("Neck", -0.14)
			_wheel_hands()
			return
		_ride_pose(dt)
		return
	if use_anims and anim == null and _anim_wait <= 0 and ResourceLoader.exists(AnimRetarget.SRC):
		anim = AnimRetarget.new()
		add_child(anim)
		_neutral_pose()
		anim.setup(_skel)
		_stand_pose()
		anim.capture_stand()
	_anim_wait -= 1
	if anim:
		# Uzaktakiler daha seyrek guncellenir (performans)
		var cam := get_viewport().get_camera_3d()
		var far := cam.global_position.distance_to(global_position) if cam else 0.0
		anim.player.active = far < 120.0
		_lod_i += 1
		if far > 120.0 or (far > 35.0 and _lod_i % (2 if far < 70.0 else 4) != 0):
			return
		_anim_pose()
		return
	var k := sin(_act_t * PI) if _act_t < 1.0 else 0.0   # 0 -> 1 -> 0

	var breathe := sin(_t * 1.6) * 0.012
	var bend := 0.0
	var lift := 0.0           # sol kolun one kalkisi
	var side_lift := 0.0
	var fore := 0.0
	match _act if _act_t < 1.0 else "":
		"throw":
			lift = -2.6 * sin(minf(_act_t * 1.6, 1.0) * PI) + 0.6 * k
			fore = 0.9 * (1.0 - _act_t) * k
			bend = 0.15 * k
		"pet":
			bend = 0.75 * k
			lift = -0.5 * k + sin(_t * 9.0) * 0.12 * k
			fore = 0.3 * k
		"feed":
			bend = 0.9 * k
			lift = -0.7 * k
		"wave":
			side_lift = 2.3 * k
			fore = 0.5 * k + sin(_t * 12.0) * 0.4 * k

	var amp := lerpf(0.4, 0.72, run) * move
	var knee_amp := lerpf(0.95, 1.6, run) * move
	var sway := sin(_phase) * move
	var idle := 1.0 - move
	_turn("Hips", [[Y, sway * 0.07], [Z, sway * 0.035 + sin(_t * 0.45) * 0.02 * idle], [X, bend * 0.25]])
	_turn("Spine", [[X, bend * 0.4 + 0.06 * move + 0.12 * run]])
	_turn("Spine1", [[Y, -sway * 0.09], [Z, -sway * 0.03], [X, bend * 0.3 + breathe]])
	_turn("Spine2", [[Y, -sway * 0.09], [X, breathe]])
	_turn("Neck", [[X, -bend * 0.3]])
	_turn("Head", [[Y, sin(_t * 0.5) * 0.18 * idle], [X, -bend * 0.3 - 0.04 * run + sin(_t * 1.3) * 0.02]])
	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ph := _phase + (0.0 if side == "Left" else PI)
		var th := sin(ph) * amp                              # + = bacak geride
		var kn := (0.06 + maxf(-cos(ph), 0.0) * knee_amp) * move
		var u: Quaternion = _fix[side + "UpLeg"]
		_turn(side + "UpLeg", [[X, th - kn * 0.35 - bend * 0.3], u])
		_turn(side + "Leg", [[u.inverse() * X, kn], _fix[side + "Leg"]])
		_turn(side + "Foot", [_fix[side + "Foot"], [X, -th * 0.55 - kn * 0.3 + maxf(sin(ph), 0.0) * 0.3 * move]])
		# Kollar: bacagin tersine sallanir, dirsek one bukulur
		var d: Quaternion = _down[side]
		var sw := -sin(ph) * amp * lerpf(0.75, 1.1, run)
		var arm_x := sw + (lift if side == "Left" else 0.0)
		var out := 0.03 * sin(_t * 0.7 + sx) * idle + breathe + (side_lift if side == "Left" else 0.0)
		_turn(side + "Arm", [[X, arm_x], [Z, sx * out], d])
		var elbow := 0.12 + maxf(-sw, 0.0) * 0.7 + 1.1 * run + (fore if side == "Left" else 0.0)
		_turn(side + "ForeArm", [[d.inverse() * X, -elbow], _fix[side + "ForeArm"]])
		var curl := -sx * (0.22 + 0.25 * run)
		for f in FINGERS:
			for n in 3:
				_turn("%sHand%s%d" % [side, f, n + 1], [[d.inverse() * Z, curl]])
	position.y = -absf(sin(_phase)) * 0.03 * move * (1.0 + run)


## Notr durus: dik govde, kollar yanda asagi, bacaklar duz. Animasyon aktariminin referansi
## (o anki yuruyus / nefes salinimindan etkilenmesin diye sifirdan kurulur).
func _neutral_pose() -> void:
	for i in _skel.get_bone_count():
		_skel.set_bone_pose_rotation(i, _skel.get_bone_rest(i).basis.get_rotation_quaternion())
	for side in ["Left", "Right"]:
		_turn(side + "UpLeg", [_fix[side + "UpLeg"]])
		_turn(side + "Leg", [_fix[side + "Leg"]])
		_turn(side + "Foot", [_fix[side + "Foot"]])
		_turn(side + "Arm", [_down[side]])
		_turn(side + "ForeArm", [_fix[side + "ForeArm"]])


## Rahat ayakta durus: notr durus + dirsekler hafif bukuk, eller hafif onde, parmaklar gevsek kivrik.
func _stand_pose() -> void:
	_neutral_pose()
	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var d: Quaternion = _down[side]
		_turn(side + "Arm", [[X, -0.02], d])
		_turn(side + "ForeArm", [[d.inverse() * X, -0.16], _fix[side + "ForeArm"]])
		for f in FINGERS:
			for n in 3:
				_turn("%sHand%s%d" % [side, f, n + 1], [[d.inverse() * Z, -sx * 0.35]])


## Bas kemiginin dunya donusumu (birinci sahis kamera icin).
func head_transform() -> Transform3D:
	return _skel.global_transform * _skel.get_bone_global_pose(_bones["Head"])


## Ayakta dururken kalca kemiginin yerden yuksekligi (sele hizalamak icin).
func hips_height() -> float:
	return _skel.get_bone_global_rest(_bones["Hips"]).origin.y


## Tum kemikleri dinlenme durusuna alir (animasyondan kalan poz temizlenir).
func _reset_pose() -> void:
	for i in _skel.get_bone_count():
		_skel.set_bone_pose_rotation(i, _skel.get_bone_rest(i).basis.get_rotation_quaternion())
	_skel.set_bone_pose_position(_bones["Hips"], _skel.get_bone_rest(_bones["Hips"]).origin)


## Govdenin one egilmesi (kalcadan gogse dagitilir); bas karsi yone donup ileri bakar.
func _lean_pose(lean: float) -> void:
	_turn("Hips", [[X, lean * 0.45]])
	_turn("Spine", [[X, lean * 0.3]])
	_turn("Spine1", [[X, lean * 0.25]])
	_turn("Neck", [[X, -lean * 0.45]])
	_turn("Head", [[X, -lean * 0.35], [Y, sin(_t * 0.4) * 0.08]])


## Surus egimi: en az 'ride_lean'; eller gidona rahat yetisene kadar artirilir (arac ve boya gore).
func _ride_lean_now() -> float:
	var base := ride_lean if ride_lean >= 0.0 else (0.3 if riding == "bisiklet" else (0.25 if riding == "motosiklet" else 0.06))
	if grips.size() != 2 or not riding in FOOT_RIDES:
		return base
	var key := "%s %.2f" % [riding, base]
	if key != _lean_key:
		_lean_key = key
		var inv := _skel.global_transform.affine_inverse()
		var ia: int = _bones["LeftArm"]
		var reach := (_skel.get_bone_rest(_bones["LeftForeArm"]).origin.length() + _skel.get_bone_rest(_bones["LeftHand"]).origin.length()) * 0.93 + 0.07
		# El isareti sirasinda tutacak uzaga tasinir: iki taraftan yakin olan olculur
		var l := base
		while l < 0.95:
			_lean_pose(l)
			var sh := _skel.get_bone_global_pose(ia).origin
			var gl: Vector3 = inv * (grips[0] as Vector3)
			var gr: Vector3 = inv * (grips[1] as Vector3)
			gr.x = -gr.x
			if minf(sh.distance_to(gl), sh.distance_to(gr)) <= reach:
				break
			l += 0.04
		_lean_auto = l
	return _lean_auto


## Bisiklet / scooter / motosiklet uzerinde: selede oturur, iki el gidonu kavrar, ayaklar pedalda /
## basamakta; bisiklette pedal cevirir. ("otur": tahterevalli / salincak, yalniz oturma pozu.)
func _ride_pose(dt: float) -> void:
	var bike := riding == "bisiklet"
	var moto := riding == "motosiklet"
	_pedal += dt * ride_speed / 0.55 * (1.0 if bike else 0.0)
	_reset_pose()
	var lean := _ride_lean_now()
	_lean_pose(lean)
	var to_skel := _skel.global_transform.affine_inverse() * (get_parent() as Node3D).global_transform
	var use_feet := riding in FOOT_RIDES and (ride_feet != Vector3.ZERO or ride_crank != Vector3.ZERO)
	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ph := _pedal + (0.0 if side == "Left" else PI)
		var thigh := (-1.05 + 0.32 * sin(ph)) if bike else (-1.15 if moto else -1.4)
		var knee := (1.15 + 0.45 * sin(ph + 1.2)) if bike else (1.6 if moto else 1.5)
		var u: Quaternion = _fix[side + "UpLeg"]
		_turn(side + "UpLeg", [[X, thigh], [Z, sx * (0.22 if moto else 0.08)], u])
		_turn(side + "Leg", [[u.inverse() * X, knee], _fix[side + "Leg"]])
		_turn(side + "Foot", [_fix[side + "Foot"], [X, -0.3]])
		if use_feet:
			# Ayak hedefi (arac uzayi; sol = -X, on = -Z): pedal dairesi ya da sabit basamak
			var ank := Vector3(-sx * ride_feet.x, ride_feet.y, ride_feet.z)
			var pitch := 0.12
			if ride_crank != Vector3.ZERO:
				ank = Vector3(-sx * ride_crank.x, ride_crank.y + ride_crank_r * cos(ph) + 0.1, ride_crank.z - ride_crank_r * sin(ph) + 0.07)
				pitch = 0.2 + 0.15 * sin(ph)
			_leg_ik(side, to_skel * ank, pitch, 0.35 if moto else 0.12)
		var d: Quaternion = _down[side]
		_turn(side + "Arm", [[X, -1.05 - lean * 0.6], [Z, sx * 0.12], d])
		_turn(side + "ForeArm", [[d.inverse() * X, -0.35], _fix[side + "ForeArm"]])
		if grips.size() == 2:
			var tgt: Vector3 = _skel.global_transform.affine_inverse() * (grips[0] if side == "Left" else grips[1])
			_arm_ik(side, tgt, true)
		else:
			_curl_fingers(side, 0.5)


## Araba: iki el direksiyon simidini (saat 9 ve 3) kavrar; tutma noktalari simitle birlikte doner.
func _wheel_hands() -> void:
	if grips.size() != 2:
		return
	var inv := _skel.global_transform.affine_inverse()
	for n in 2:
		var palm := Vector3.ZERO
		var fwd := Vector3.ZERO
		if grip_palms.size() == 2:
			palm = (inv.basis * (grip_palms[n] as Vector3)).normalized()
			fwd = (inv.basis * grip_fwd).normalized()
		_arm_ik("Left" if n == 0 else "Right", inv * (grips[n] as Vector3), true, palm, fwd)


## Bas gizlenir / gosterilir (birinci sahis kamerada kendi basi goruntuye girmesin; kollar gorunur kalir).
func set_head_hidden(on: bool) -> void:
	if _skel and _bones.has("Head"):
		_skel.set_bone_pose_scale(_bones["Head"], Vector3.ONE * (0.001 if on else 1.0))


## Parmaklari avuc icine kivirir (0 = acik, 1 = yumruk); bas parmak hafifce kapanir.
func _curl_fingers(side: String, k: float) -> void:
	var pf: Basis = _palm[side]
	var ax := pf.x.cross(pf.y).normalized()
	for f in FINGERS:
		for n in 3:
			_turn("%sHand%s%d" % [side, f, n + 1], [[ax, k * (1.15 if n < 2 else 0.7)]])
	for n in 3:
		var nm := "%sHandThumb%d" % [side, n + 1]
		if _bones.has(nm) and n > 0:
			_turn(nm, [[pf.x, (-0.5 if side == "Left" else 0.5) * k]])


## Kemigin dunya (iskelet uzayi) donusunu verir.
func _set_global_basis(i: int, b: Basis) -> void:
	var gp := _skel.get_bone_global_pose(_skel.get_bone_parent(i)).basis.orthonormalized()
	_skel.set_bone_pose_rotation(i, (gp.inverse() * b).get_rotation_quaternion())


## Iki kemikli bacak cozucusu: ayak bilegini hedefe (iskelet uzayi) goturur, diz one-disa bakar,
## ayak tabani yere paralel ('pitch' kadar burun asagi).
func _leg_ik(side: String, ankle: Vector3, pitch := 0.0, knee_out := 0.12) -> void:
	var sx := 1.0 if side == "Left" else -1.0
	var iu: int = _bones[side + "UpLeg"]
	var il: int = _bones[side + "Leg"]
	var ifo: int = _bones[side + "Foot"]
	var gp := _skel.get_bone_global_pose(_skel.get_bone_parent(iu))
	var off_l := _skel.get_bone_pose_position(il)
	var off_f := _skel.get_bone_pose_position(ifo)
	var a := off_l.length()
	var b := off_f.length()
	var hip := gp * _skel.get_bone_pose_position(iu)
	var to := ankle - hip
	var dist := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.004)
	var n := to.normalized()
	var x := (a * a - b * b + dist * dist) / (2.0 * dist)
	var hgt := sqrt(maxf(a * a - x * x, 0.0))
	var pole := Vector3(sx * knee_out, 0.25, 1.0)
	pole = (pole - n * pole.dot(n)).normalized()
	var knee := hip + n * x + pole * hgt
	var foot := hip + n * dist
	var bg := gp.basis.orthonormalized() * Basis(_skel.get_bone_pose_rotation(iu))
	bg = _rot_between(bg * off_l, knee - hip) * bg
	_skel.set_bone_pose_rotation(iu, (gp.basis.orthonormalized().inverse() * bg).get_rotation_quaternion())
	var bf := bg * Basis(_skel.get_bone_pose_rotation(il))
	bf = _rot_between(bf * off_f, foot - knee) * bf
	_skel.set_bone_pose_rotation(il, (bg.inverse() * bf).get_rotation_quaternion())
	var fb := Basis(X, pitch) * Basis(Y, sx * 0.12) * _skel.get_bone_global_rest(ifo).basis.orthonormalized()
	_skel.set_bone_pose_rotation(ifo, (bf.inverse() * fb).get_rotation_quaternion())


## Hazir animasyon secimi: hiza gore dur / yuru / kos / depar; tek seferlik hareketler.
func _anim_pose() -> void:
	if airborne:
		anim.play("Jump" if anim.current == "Jump" or anim.current == "Jump_Start" and anim.player.current_animation_position > 0.25 else "Jump_Start", 0.08, 1.4)
	elif seated:
		_seat_t += 0.05
		var pl: AnimationPlayer = anim.player
		if sit_exit and pl.has_animation("Sitting_Exit"):
			anim.play("Sitting_Exit", 0.12)
		elif _seat_t < 0.9 and pl.has_animation("Sitting_Enter"):
			anim.play("Sitting_Enter", 0.15)
		else:
			anim.play("Sitting_Idle", 0.35)
	elif _act_t < 1.0 and (_act == "eat" or _act == "sip"):
		anim.play("Idle", 0.2)
	elif _act_t < 1.0 and _act == "kick":
		anim.play("Idle", 0.12)
	elif _act_t < 1.0 and ACT_CLIPS.has(_act):
		anim.play(ACT_CLIPS[_act], 0.15, 1.3)
	elif speed < 0.15:
		_seat_t = 0.0
		anim.play("Idle", 0.3)
	elif speed < 2.3:
		anim.play("Walk", 0.25, clampf(speed / 1.35, 0.5, 1.6))
	elif speed < 4.6:
		anim.play("Jog_Fwd", 0.25, clampf(speed / 3.3, 0.7, 1.4))
	else:
		anim.play("Sprint", 0.25, clampf(speed / 6.0, 0.7, 1.4))
	anim.apply()
	# Yuruyus / kosu kliplerinde kollar govdeden fazla acik: ust kollar govdeye yaklastirilir
	var loco: bool = anim.current in ["Walk", "Jog_Fwd", "Sprint"] and not airborne
	_arm_in = move_toward(_arm_in, 0.16 if loco else 0.0, get_process_delta_time() * 0.8)
	if _arm_in > 0.0:
		_roll("LeftArm", -_arm_in)
		_roll("RightArm", _arm_in)
	if _act_t < 1.0 and _act == "kick":
		# Sut: sag bacak geriye acilir, one savrulur; govde hafifce geri yaslanir
		var t := _act_t
		var sw := 0.55 * smoothstep(0.0, 0.3, t) - 1.8 * smoothstep(0.3, 0.5, t) + 1.25 * smoothstep(0.55, 1.0, t)
		_swing("RightUpLeg", sw)
		_swing("RightLeg", 1.0 * smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.3, 0.48, t)))
		_swing("Spine", -0.18 * sin(t * PI))
		_swing("LeftArm", 0.5 * sin(t * PI))
	if _act_t < 1.0 and (_act == "eat" or _act == "sip"):
		# Yemek: sol el agiza gider, iki kez isirir; yudum: el yavasca agiza gider, kisa bekler
		var w := clampf(sin(_act_t * PI) * 1.6, 0.0, 1.0)
		var head := _skel.get_bone_global_pose(_bones["Head"]).origin
		var mouth := head + Vector3(0.0, 0.0, 0.2) * _scale_k() + Vector3(0, 0.02, 0) * (sin(_act_t * 18.0) if _act == "eat" else 0.0)
		var hand_p := _skel.get_bone_global_pose(_bones["LeftHand"]).origin
		_arm_ik("Left", hand_p.lerp(mouth, w))


## Kemigi iskelet uzayinda X ekseni etrafinda dondurur (+ = geriye).
func _swing(bone: String, a: float) -> void:
	if not _bones.has(bone):
		return
	var i: int = _bones[bone]
	var gp := _skel.get_bone_global_pose(_skel.get_bone_parent(i)).basis.orthonormalized()
	var bg := Basis(Vector3.RIGHT, a) * (gp * Basis(_skel.get_bone_pose_rotation(i)))
	_skel.set_bone_pose_rotation(i, (gp.inverse() * bg).get_rotation_quaternion())


## Kemigi iskelet uzayinda ileri (Z) ekseni etrafinda dondurur (sol kol icin - = govdeye dogru).
func _roll(bone: String, a: float) -> void:
	var i: int = _bones[bone]
	var gp := _skel.get_bone_global_pose(_skel.get_bone_parent(i)).basis.orthonormalized()
	var bg := Basis(Vector3.BACK, a) * (gp * Basis(_skel.get_bone_pose_rotation(i)))
	_skel.set_bone_pose_rotation(i, (gp.inverse() * bg).get_rotation_quaternion())


## Iskelet birimi -> metre (ice aktarilan modelin olcegi).
func _scale_k() -> float:
	var h := _skel.get_bone_global_rest(_bones["Head"]).origin.y
	return maxf(h, 0.001) / 1.55


func _rot_between(u: Vector3, v: Vector3) -> Basis:
	u = u.normalized()
	v = v.normalized()
	var ax := u.cross(v)
	if ax.length() < 1e-5:
		return Basis()
	return Basis(ax.normalized(), acos(clampf(u.dot(v), -1.0, 1.0)))


## Iki kemikli kol cozucusu: eli hedefe (iskelet uzayi) goturur, dirsek asagi-disari bakar.
## grip: hedef yatay bir gidon tutacagi; avuc tutacagin ustune oturur, parmaklar tutacagi sarar.
## Degilse el on kolun devaminda durur, avuc asagi doner.
## palm / fwd verilirse (direksiyon simidi): avuc 'palm' yonune bakar, parmaklar 'fwd' yonunde simidi sarar.
func _arm_ik(side: String, target: Vector3, grip := false, palm := Vector3.ZERO, fwd_dir := Vector3.ZERO) -> void:
	var sx := 1.0 if side == "Left" else -1.0
	var ia: int = _bones[side + "Arm"]
	var iff: int = _bones[side + "ForeArm"]
	var ih: int = _bones[side + "Hand"]
	var gp := _skel.get_bone_global_pose(_skel.get_bone_parent(ia))
	var off_f := _skel.get_bone_pose_position(iff)       # dirsegin kol icindeki yeri
	var off_h := _skel.get_bone_pose_position(ih)        # bilegin on kol icindeki yeri
	var a := off_f.length()
	var b := off_h.length()
	var sh := gp * _skel.get_bone_pose_position(ia)
	var reach := target - sh
	# Yana uzanan kol (el isareti) kavrama sayilmaz
	grip = grip and absf(reach.normalized().x) < 0.75
	var hf := Vector3.ZERO      # elin parmak yonu
	var hn := Vector3.ZERO      # avuc icinin baktigi yon
	if grip and palm != Vector3.ZERO:
		hn = palm
		hf = fwd_dir + reach.normalized() * 0.7
		hf = (hf - hn * hf.dot(hn)).normalized()
		target = target - hf * 0.08 - hn * 0.035       # bilek: avuc ortasi simidin dis yuzunde
	elif grip:
		var fwd := (reach * Vector3(0, 1, 1)).normalized()
		var flat := (reach * Vector3(0, 0, 1)).normalized()
		hf = (fwd + flat * 0.6 + Vector3(-sx * 0.12, 0, 0)).normalized()
		hn = Vector3.RIGHT.cross(hf).normalized()
		if hn.y > 0.0:
			hn = -hn
		hn = (hn - hf * hn.dot(hf)).normalized()
		target = target - hf * 0.085 - hn * 0.03       # bilek: avuc ortasi tutacagin ustunde
	else:
		target -= reach.normalized() * 0.07      # bilek, avucun ortasindan el boyu kadar geride
	var to := target - sh
	var dist := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.005)
	var n := to.normalized()
	var x := (a * a - b * b + dist * dist) / (2.0 * dist)
	var hgt := sqrt(maxf(a * a - x * x, 0.0))
	var pole := Vector3(sx * 0.7, -1.0, -0.2)
	pole = (pole - n * pole.dot(n)).normalized()
	var elbow := sh + n * x + pole * hgt
	var wrist := sh + n * dist
	# Ust kol
	var bg := gp.basis.orthonormalized() * Basis(_skel.get_bone_pose_rotation(ia))
	bg = _rot_between(bg * off_f, elbow - sh) * bg
	_skel.set_bone_pose_rotation(ia, (gp.basis.orthonormalized().inverse() * bg).get_rotation_quaternion())
	# On kol
	var bf := bg * Basis(_skel.get_bone_pose_rotation(iff))
	bf = _rot_between(bf * off_h, wrist - elbow) * bf
	var axis := (wrist - elbow).normalized()
	var hrest := _skel.get_bone_rest(ih).basis.get_rotation_quaternion()
	if not grip:
		bf = Basis(axis, -sx * hand_twist) * bf
		_skel.set_bone_pose_rotation(iff, (bg.inverse() * bf).get_rotation_quaternion())
		# El: on kolla ayni dogrultuda, hafif asagi bukuk
		_skel.set_bone_pose_rotation(ih, hrest * Quaternion(Vector3.RIGHT, 0.15))
		return
	# Kavrama: elin dunya donusu avuc cercevesinden; on kol, avuc yonune dogru burulur (bilek kirilmasin)
	var pf: Basis = _palm[side]
	var hand_rest_g := _skel.get_bone_global_rest(ih).basis.orthonormalized()
	var hg := Basis(hf, hn, hf.cross(hn)) * pf.inverse() * hand_rest_g
	var n0: Vector3 = bf * Basis(hrest) * (hand_rest_g.inverse() * pf.y)
	var p0 := (n0 - axis * n0.dot(axis)).normalized()
	var p1 := (hn - axis * hn.dot(axis)).normalized()
	if p0.length() > 0.5 and p1.length() > 0.5:
		bf = Basis(axis, p0.signed_angle_to(p1, axis) * 0.8) * bf
	_skel.set_bone_pose_rotation(iff, (bg.inverse() * bf).get_rotation_quaternion())
	_skel.set_bone_pose_rotation(ih, (bf.inverse() * hg).get_rotation_quaternion())
	_curl_fingers(side, 1.0)
