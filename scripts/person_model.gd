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
var _pedal := 0.0
var tint := Color.WHITE   # tisort rengi
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
		_ride_pose(dt)
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


## Bisiklet / scooter uzerinde: oturur, eller gidonda; bisiklette pedal cevirir.
func _ride_pose(dt: float) -> void:
	var bike := riding == "bisiklet"
	_pedal += dt * ride_speed / 0.55 * (1.0 if bike else 0.0)
	var lean := 0.32 if bike else 0.08
	_turn("Hips", [[X, lean * 0.5]])
	_turn("Spine", [[X, lean * 0.6]])
	_turn("Spine1", [[X, lean * 0.3]])
	_turn("Spine2", [])
	_turn("Neck", [[X, -lean * 0.8]])
	_turn("Head", [[X, -lean * 0.3], [Y, sin(_t * 0.4) * 0.08]])
	for side in ["Left", "Right"]:
		var sx := 1.0 if side == "Left" else -1.0
		var ph := _pedal + (0.0 if side == "Left" else PI)
		var thigh := (-1.05 + 0.32 * sin(ph)) if bike else -1.4
		var knee := (1.15 + 0.45 * sin(ph + 1.2)) if bike else 1.5
		var u: Quaternion = _fix[side + "UpLeg"]
		_turn(side + "UpLeg", [[X, thigh], [Z, sx * 0.08], u])
		_turn(side + "Leg", [[u.inverse() * X, knee], _fix[side + "Leg"]])
		_turn(side + "Foot", [_fix[side + "Foot"], [X, -0.3]])
		var d: Quaternion = _down[side]
		_turn(side + "Arm", [[X, -1.05 - lean * 0.6], [Z, sx * 0.12], d])
		_turn(side + "ForeArm", [[d.inverse() * X, -0.35], _fix[side + "ForeArm"]])
		for f in FINGERS:
			for n in 3:
				_turn("%sHand%s%d" % [side, f, n + 1], [[d.inverse() * Z, -sx * 0.9]])
