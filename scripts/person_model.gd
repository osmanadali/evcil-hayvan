extends Node3D
## Tripo'dan gelen insan modeli; iskelet tools/rig_pet.py ile takildi, hareketler kodla.
## Model T duruşunda geldigi icin kollar once asagi indirilir. Yonu -Z.

const X := Vector3.RIGHT
const Y := Vector3.UP
const Z := Vector3.BACK
const HEIGHT := {"kadin": 1.62, "erkek": 1.78}
const ARM_DOWN := 1.32
const LEG_IN := {"kadin": 0.27, "erkek": 0.2}

var kind := "kadin"
# Yeniden olusturmada isleyici uyarisi vermemesi icin malzemeler canli tutulur
static var _keep: Array = []

var speed := 0.0
var tint := Color.WHITE
var hand: Node3D          # elde tasinan esya icin

var _skel: Skeleton3D
var _bones := {}
var _phase := 0.0
var _t := 0.0
var _act := ""
var _act_t := 1.0
var _act_d := 1.0


func _ready() -> void:
	_t = randf() * 10.0
	var model: Node3D = load("res://assets/models/%s.glb" % kind).instantiate()
	model.rotation.y = PI
	model.scale = Vector3.ONE * HEIGHT[kind]
	add_child(model)
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in _skel.get_bone_count():
		_bones[_skel.get_bone_name(i)] = i
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: BaseMaterial3D = mi.get_active_material(0).duplicate()
		m.roughness = 0.9
		m.albedo_color = tint
		mi.set_surface_override_material(0, m)
		_keep.append(m)
	var ba := BoneAttachment3D.new()
	ba.bone_name = "fore_b"
	_skel.add_child(ba)
	hand = Node3D.new()
	hand.position = Vector3(0, 0.2, 0)
	ba.add_child(hand)


func _turn(bone: String, turns: Array) -> void:
	var i: int = _bones[bone]
	var inv := _skel.get_bone_global_rest(i).basis.inverse()
	var q := _skel.get_bone_rest(i).basis.get_rotation_quaternion()
	for t in turns:
		var axis: Vector3 = t[0]
		q = q * Quaternion((inv * axis).normalized(), t[1])
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
	var move := clampf(speed / 1.4, 0.0, 1.0)
	var run := clampf((speed - 2.2) / 2.0, 0.0, 1.0)
	if speed > 0.05:
		_phase += dt * (4.6 + speed * 1.5)
	_act_t = minf(_act_t + dt / _act_d, 1.0)
	var k := sin(_act_t * PI) if _act_t < 1.0 else 0.0   # 0 -> 1 -> 0

	var sw := sin(_phase) * (0.5 + 0.25 * run) * move
	var breathe := sin(_t * 1.8) * 0.015
	var bend := 0.0
	var arm_b_lift := 0.0      # sag kolun one kalkisi
	var arm_b_side := 0.0
	var fore_b := 0.25
	match _act if _act_t < 1.0 else "":
		"throw":
			arm_b_lift = -2.6 * sin(minf(_act_t * 1.6, 1.0) * PI) + 0.6 * k
			fore_b = 0.25 + 0.9 * (1.0 - _act_t) * k
			bend = 0.15 * k
		"pet":
			bend = 0.75 * k
			arm_b_lift = -0.5 * k + sin(_t * 9.0) * 0.12 * k
			fore_b = 0.5
		"feed":
			bend = 0.9 * k
			arm_b_lift = -0.7 * k
		"wave":
			arm_b_side = -2.3 * k
			fore_b = 0.6 + sin(_t * 12.0) * 0.5 * k

	var leg_in: float = LEG_IN[kind]
	_turn("leg_a", [[X, sw - bend * 0.25], [Z, leg_in]])
	_turn("leg_b", [[X, -sw - bend * 0.25], [Z, -leg_in]])
	_turn("shin_a", [[X, maxf(-cos(_phase), 0.0) * 0.9 * move]])
	_turn("shin_b", [[X, maxf(cos(_phase), 0.0) * 0.9 * move]])
	_turn("hips", [[Y, sin(_phase) * 0.08 * move]])
	_turn("spine", [[Y, -sin(_phase) * 0.12 * move], [X, bend + breathe + 0.06 * run]])
	_turn("head", [[Y, sin(_t * 0.5) * 0.15 * (1.0 - move)], [X, -bend * 0.5 + sin(_t * 1.3) * 0.02]])
	_turn("arm_a", [[X, -sw * 0.9], [Z, ARM_DOWN + breathe]])
	_turn("arm_b", [[X, sw * 0.9 + arm_b_lift], [Z, -ARM_DOWN - breathe - arm_b_side]])
	# Dirsek: kol asagidayken one dogru bukulur
	_turn("fore_a", [[Basis(Z, -ARM_DOWN) * X, -0.25 - maxf(-sw, 0.0) * 0.8 - 0.6 * run]])
	_turn("fore_b", [[Basis(Z, ARM_DOWN) * X, -fore_b - maxf(sw, 0.0) * 0.8 - 0.6 * run]])
	position.y = absf(sin(_phase)) * 0.03 * move
