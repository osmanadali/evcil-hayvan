extends Node3D
## Tripo'dan gelen kedi/kopek modeli. Iskelet tools/rig_pet.py ile takildi;
## butun hareketler burada kodla uretilir (yurume, kosma, oturma, yatma, yeme, ziplama).
## Yonu -Z. `speed` degerini hareket ettiren betik yazar.

const Kit = preload("res://scripts/kit.gd")
const X := Vector3.RIGHT
const Y := Vector3.UP
const Z := Vector3.BACK

# Iskelet uzayi: +Z on, +Y yukari (metre, model boyu 1)
const KINDS := {
	"kopek": {"model": "res://assets/models/kopek.glb", "size": 0.95, "hat": Vector3(-0.03, 0.745, 0.4), "hat_scale": 0.48, "back_scale": 0.6, "paw_scale": 0.6,
		"mouth": Vector3(-0.03, 0.58, 0.5), "neck": Vector3(0, 0.53, 0.3), "neck_r": 0.12, "shoulder": Vector3(0, 0.45, 0.28),
		"wag": 1.0, "step": 1.0, "lie_drop": 0.26, "head_yaw": 0.0, "face": Vector3(-0.03, 0.672, 0.485), "face_w": 0.045, "back": Vector3(0, 0.565, 0.02),
		"paws": {"fl2": Vector3(-0.11, 0.04, 0.33), "fr2": Vector3(0.11, 0.04, 0.33), "bl2": Vector3(-0.08, 0.04, -0.2), "br2": Vector3(0.12, 0.04, -0.2)}},
	"kedi": {"model": "res://assets/models/kedi.glb", "size": 0.5, "hat": Vector3(0.03, 0.81, 0.4), "hat_scale": 0.42, "back_scale": 0.55, "paw_scale": 0.6,
		"mouth": Vector3(0.06, 0.66, 0.5), "neck": Vector3(0.01, 0.6, 0.3), "neck_r": 0.13, "shoulder": Vector3(0, 0.48, 0.27),
		"wag": 0.25, "step": 1.25, "lie_drop": 0.24, "head_yaw": 0.25, "face": Vector3(0.05, 0.735, 0.49), "face_w": 0.04, "back": Vector3(0, 0.655, 0.0),
		"paws": {"fl2": Vector3(-0.1, 0.04, 0.28), "fr2": Vector3(0.1, 0.04, 0.27), "bl2": Vector3(-0.1, 0.04, -0.22), "br2": Vector3(0.1, 0.04, -0.22)}},
}

var kind := "kopek"
# Yeniden olusturmada isleyici uyarisi vermemesi icin malzemeler canli tutulur
static var _keep: Array = []

var speed := 0.0
var force_speed := -1.0   # test: animasyonu bu hizla oynat
var excited := false
var pose := "stand"   # stand, sit, lie, sleep, eat
var happy_time := 0.0
var stage := 2
var size_mul := 1.0
var mouth: Node3D
var hat_socket: Node3D
var neck_socket: Node3D
var face_socket: Node3D
var back_socket: Node3D
var paw_sockets: Array[Node3D] = []
var tint := Color.WHITE
var look_at_point = null   # Vector3 ya da null: basi bu noktaya cevirir

var sitting: bool:
	get: return pose == "sit"
	set(v): pose = "sit" if v else "stand"

var _cfg: Dictionary
var _rig: Node3D
var _pitch: Node3D
var _skel: Skeleton3D
var _bones := {}
var _phase := 0.0
var _t := 0.0
var _w := {"sit": 0.0, "lie": 0.0, "sleep": 0.0, "eat": 0.0}
var _hop_t := 1.0
var _hop_h := 0.0
var _hop_d := 0.4
var _blink := 0.0


func _ready() -> void:
	_cfg = KINDS[kind]
	_t = randf() * 10.0
	_rig = Kit.pivot(self)
	var flip := Kit.pivot(_rig)
	flip.rotation.y = PI
	_pitch = Kit.pivot(flip)
	var model: Node3D = load(_cfg["model"]).instantiate()
	_pitch.add_child(model)
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in _skel.get_bone_count():
		_bones[_skel.get_bone_name(i)] = i
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: BaseMaterial3D = mi.get_active_material(0).duplicate()
		m.roughness = 0.95
		m.rim_enabled = true
		m.rim = 0.2
		m.rim_tint = 0.7
		m.albedo_color = tint
		mi.set_surface_override_material(0, m)
		_keep.append(m)
	mouth = _attach("head", _cfg["mouth"])
	hat_socket = _attach("head", _cfg["hat"])
	hat_socket.scale = Vector3.ONE * _cfg["hat_scale"]
	neck_socket = _attach("chest", _cfg["neck"])
	face_socket = _attach("head", _cfg["face"])
	back_socket = _attach("chest", _cfg["back"])
	back_socket.scale = Vector3.ONE * _cfg["back_scale"]
	for b in _cfg["paws"]:
		paw_sockets.append(_attach(b, _cfg["paws"][b]))
		paw_sockets[-1].scale = Vector3.ONE * _cfg["paw_scale"]
	set_stage(stage)


## Iskelet uzayindaki bir noktaya, eksenleri govdeyle hizali (-Z on) baglanti noktasi ekler.
func _attach(bone: String, skel_pos: Vector3) -> Node3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	_skel.add_child(ba)
	var n := Node3D.new()
	n.transform = _skel.get_bone_global_rest(_bones[bone]).affine_inverse() * Transform3D(Basis(Y, PI), skel_pos)
	ba.add_child(n)
	return n


func _turn(bone: String, turns: Array) -> void:
	if not _bones.has(bone):
		return
	var i: int = _bones[bone]
	var inv := _skel.get_bone_global_rest(i).basis.inverse()
	var q := _skel.get_bone_rest(i).basis.get_rotation_quaternion()
	for t in turns:
		var axis: Vector3 = t[0]
		q = q * Quaternion((inv * axis).normalized(), t[1])
	_skel.set_bone_pose_rotation(i, q)


## Buyume evresi: tek model, oranlar degisir (yavruda buyuk bas).
func set_stage(s: int) -> void:
	stage = clampi(s, 0, 2)
	scale = Vector3.ONE * _cfg["size"] * size_mul * [0.7, 0.85, 1.0][stage]
	_skel.set_bone_pose_scale(_bones["head"], Vector3.ONE * [1.12, 1.06, 1.0][stage])


func hop(height := 0.35, duration := 0.45) -> void:
	_hop_t = 0.0
	_hop_h = height
	_hop_d = duration


func is_hopping() -> bool:
	return _hop_t < 1.0


func _process(dt: float) -> void:
	_t += dt
	if force_speed >= 0.0:
		speed = force_speed
	var move := clampf(speed / 3.0, 0.0, 1.0)
	var run := clampf((speed - 2.5) / 2.0, 0.0, 1.0)
	if speed > 0.05:
		_phase += dt * (5.5 + speed * 2.4) * _cfg["step"]
	var still := speed < 0.05
	for k in _w:
		var on: bool = still and (pose == k or (k == "lie" and pose == "sleep"))
		_w[k] = move_toward(_w[k], 1.0 if on else 0.0, dt * 3.5)
	var sit := smoothstep(0.0, 1.0, _w["sit"])
	var lie := smoothstep(0.0, 1.0, _w["lie"])
	var slp := smoothstep(0.0, 1.0, _w["sleep"])
	var eat := smoothstep(0.0, 1.0, _w["eat"])
	happy_time = maxf(happy_time - dt, 0.0)
	var happy := happy_time > 0.0 and still and pose == "stand"
	_hop_t = minf(_hop_t + dt / _hop_d, 1.0)
	var air := sin(_hop_t * PI) * _hop_h if _hop_t < 1.0 else 0.0

	# Bacaklar: capraz adim; kosarken on-arka birlikte (dortnala)
	var sw := sin(_phase) * (0.55 + 0.25 * run) * move
	var sw2 := sin(_phase + PI * (1.0 - run * 0.7)) * (0.55 + 0.25 * run) * move
	var lift := cos(_phase)
	var tuck := air * 1.6
	_turn("fl1", [[X, sw + 0.6 * sit - 1.35 * lie - tuck]])
	_turn("fr1", [[X, sw2 + 0.6 * sit - 1.35 * lie - tuck]])
	_turn("bl1", [[X, sw2 - 1.5 * sit - 1.35 * lie + tuck]])
	_turn("br1", [[X, sw - 1.5 * sit - 1.35 * lie + tuck]])
	_turn("fl2", [[X, maxf(lift, 0.0) * 0.6 * move]])
	_turn("fr2", [[X, maxf(-lift if run < 0.5 else lift, 0.0) * 0.6 * move]])
	_turn("bl2", [[X, maxf(-lift if run < 0.5 else lift, 0.0) * 0.5 * move + 1.3 * sit]])
	_turn("br2", [[X, maxf(lift, 0.0) * 0.5 * move + 1.3 * sit]])

	# Govde: oturunca on omuz sabit kalir, arka iner
	var p := -0.6 * sit + 0.12 * eat
	var sh: Vector3 = _cfg["shoulder"]
	_pitch.rotation.x = p
	_pitch.position = sh - Basis(X, p) * sh + Vector3(0, -float(_cfg["lie_drop"]) * lie, 0)
	var breathe := sin(_t * (1.2 if slp > 0.5 else 2.2)) * (0.012 if slp > 0.5 else 0.006)
	_rig.position.y = absf(sin(_phase)) * (0.035 + 0.05 * run) * move + breathe + air \
			+ (absf(sin(_t * 9.0)) * 0.1 if happy else 0.0)
	_rig.rotation.z = sin(_phase) * 0.045 * move
	_rig.rotation.x = -sin(_hop_t * TAU) * 0.25 if _hop_t < 1.0 else sin(_phase * 2.0) * 0.03 * run
	_turn("chest", [[Y, sin(_phase) * 0.07 * move], [X, 0.25 * sit]])
	_turn("hips", [[Y, -sin(_phase) * 0.07 * move]])

	# Kuyruk: kopek sallar, kedi agir agir kivirir
	var fast: bool = excited or happy or speed > 0.05
	var wag: float = sin(_t * (14.0 if fast else 4.0) * (1.0 if _cfg["wag"] > 0.5 else 0.35))
	var amp: float = (0.5 if fast else 0.25) * (1.0 - slp)
	var droop := 0.5 * sit + 0.9 * lie
	_turn("tail1", [[Y, wag * amp], [X, droop]])
	_turn("tail2", [[Y, wag * amp * 1.2], [X, sin(_t * 1.3) * 0.12]])
	_turn("tail3", [[Y, sin(_t * 1.6 + 1.0) * 0.5 * (1.0 - slp)], [X, sin(_t * 1.1) * 0.2]])

	# Bas: bakis, yemek, uyku
	var yaw := sin(_t * 0.6) * 0.18 * (1.0 - move) * (1.0 - slp)
	var nod := sin(_t * 1.7) * 0.04 + 0.05 * move - sin(_phase * 2.0) * 0.05 * move
	if look_at_point != null and still:
		var local: Vector3 = to_local(look_at_point)
		yaw = clampf(atan2(-local.x, -local.z), -0.9, 0.9)
	_turn("head", [[Y, yaw + float(_cfg["head_yaw"])], [X, nod + 0.5 * sit + 0.75 * eat + sin(_t * 10.0) * 0.07 * eat + 0.55 * slp + 0.15 * lie],
		[Z, sin(_t * 0.9) * 0.1 * (1.0 - move) * (1.0 - slp)]])
	var flap := sin(_phase * 2.0) * 0.25 * move + sin(_t * 1.3) * 0.04
	_blink -= dt
	var twitch := 0.0
	if _blink < 0.0:
		_blink = randf_range(2.0, 6.0)
	elif _blink < 0.15:
		twitch = 0.35
	_turn("ear_l", [[Z, flap + twitch]])
	_turn("ear_r", [[Z, -flap]])
