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
var hand_twist := 1.2     # avucu asagi cevirmek icin on kol donusu
var _pedal := 0.0
const AnimRetarget = preload("res://scripts/anim_retarget.gd")
var anim: Node                 # hazir animasyonlar (yoksa kodla poz)
var use_anims := true
var airborne := false
var seated := false            # taburede / sandalyede oturuyor (Sitting_Idle)
var _lod_i := randi() % 4          # ziplarken (main ayarlar)
var _anim_wait := 2            # ilk karelerde kodla notr poz kurulur, sonra animasyona gecilir
const ACT_CLIPS := {"pet": "PickUp_Table", "feed": "PickUp_Table", "wave": "Interact", "throw": "Interact",
	"eat": "Interact", "sit": "Sitting_Idle"}
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
			return
		_ride_pose(dt)
		return
	if use_anims and anim == null and _anim_wait <= 0 and ResourceLoader.exists(AnimRetarget.SRC):
		anim = AnimRetarget.new()
		add_child(anim)
		anim.setup(_skel)
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


## Bas kemiginin dunya donusumu (birinci sahis kamera icin).
func head_transform() -> Transform3D:
	return _skel.global_transform * _skel.get_bone_global_pose(_bones["Head"])


## Ayakta dururken kalca kemiginin yerden yuksekligi (sele hizalamak icin).
func hips_height() -> float:
	return _skel.get_bone_global_rest(_bones["Hips"]).origin.y


## Bisiklet / scooter uzerinde: oturur, eller gidonda; bisiklette pedal cevirir.
func _ride_pose(dt: float) -> void:
	var bike := riding == "bisiklet"
	var moto := riding == "motosiklet"
	_pedal += dt * ride_speed / 0.55 * (1.0 if bike else 0.0)
	var lean := ride_lean if ride_lean >= 0.0 else (0.32 if bike else (0.22 if moto else 0.08))
	_turn("Hips", [[X, lean * 0.5]])
	_turn("Spine", [[X, lean * 0.6]])
	_turn("Spine1", [[X, lean * 0.3]])
	_turn("Spine2", [])
	_turn("Neck", [[X, -lean * 0.8]])
	_turn("Head", [[X, -lean * 0.3], [Y, sin(_t * 0.4) * 0.08]])
	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ph := _pedal + (0.0 if side == "Left" else PI)
		var thigh := (-1.05 + 0.32 * sin(ph)) if bike else (-1.15 if moto else -1.4)
		var knee := (1.15 + 0.45 * sin(ph + 1.2)) if bike else (1.6 if moto else 1.5)
		var u: Quaternion = _fix[side + "UpLeg"]
		_turn(side + "UpLeg", [[X, thigh], [Z, sx * (0.22 if moto else 0.08)], u])
		_turn(side + "Leg", [[u.inverse() * X, knee], _fix[side + "Leg"]])
		_turn(side + "Foot", [_fix[side + "Foot"], [X, -0.3]])
		var d: Quaternion = _down[side]
		_turn(side + "Arm", [[X, -1.05 - lean * 0.6], [Z, sx * 0.12], d])
		_turn(side + "ForeArm", [[d.inverse() * X, -0.35], _fix[side + "ForeArm"]])
		for f in FINGERS:
			for n in 3:
				_turn("%sHand%s%d" % [side, f, n + 1], [[d.inverse() * Z, -sx * 0.9]])
		if grips.size() == 2:
			var tgt: Vector3 = _skel.global_transform.affine_inverse() * (grips[0] if side == "Left" else grips[1])
			_arm_ik(side, tgt)


## Hazir animasyon secimi: hiza gore dur / yuru / kos / depar; tek seferlik hareketler.
func _anim_pose() -> void:
	if airborne:
		anim.play("Jump" if anim.current == "Jump" or anim.current == "Jump_Start" and anim.player.current_animation_position > 0.25 else "Jump_Start", 0.08, 1.4)
	elif seated:
		anim.play("Sitting_Idle", 0.35)
	elif _act_t < 1.0 and (_act == "eat" or _act == "sip"):
		anim.play("Idle", 0.2)
	elif _act_t < 1.0 and ACT_CLIPS.has(_act):
		anim.play(ACT_CLIPS[_act], 0.15, 1.3)
	elif speed < 0.15:
		anim.play("Idle", 0.3)
	elif speed < 2.3:
		anim.play("Walk", 0.25, clampf(speed / 1.35, 0.5, 1.6))
	elif speed < 4.6:
		anim.play("Jog_Fwd", 0.25, clampf(speed / 3.3, 0.7, 1.4))
	else:
		anim.play("Sprint", 0.25, clampf(speed / 6.0, 0.7, 1.4))
	anim.apply()
	if _act_t < 1.0 and (_act == "eat" or _act == "sip"):
		# Yemek: sol el agiza gider, iki kez isirir; yudum: el yavasca agiza gider, kisa bekler
		var w := clampf(sin(_act_t * PI) * 1.6, 0.0, 1.0)
		var head := _skel.get_bone_global_pose(_bones["Head"]).origin
		var mouth := head + Vector3(0.0, 0.0, 0.2) * _scale_k() + Vector3(0, 0.02, 0) * (sin(_act_t * 18.0) if _act == "eat" else 0.0)
		var hand_p := _skel.get_bone_global_pose(_bones["LeftHand"]).origin
		_arm_ik("Left", hand_p.lerp(mouth, w))


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


## Iki kemikli kol cozucusu: eli hedefe (iskelet uzayi) goturur, dirsek asagi-disari bakar,
## avuc asagi doner (gidonu kavrar).
func _arm_ik(side: String, target: Vector3) -> void:
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
	target -= (target - sh).normalized() * 0.07      # bilek, avucun ortasindan el boyu kadar geride
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
	bf = Basis(axis, -sx * hand_twist) * bf
	_skel.set_bone_pose_rotation(iff, (bg.inverse() * bf).get_rotation_quaternion())
	# El: on kolla ayni dogrultuda, hafif asagi bukuk
	var hrest := _skel.get_bone_rest(ih).basis.get_rotation_quaternion()
	_skel.set_bone_pose_rotation(ih, hrest * Quaternion(Vector3.RIGHT, 0.15))
