extends Node3D
## Basit sekillerden kurulan, kodla canlandirilan kopek.
## Gecici: Tripo'dan gelen model hazir olunca bu dosyanin yerini alacak.
## Yonu -Z. `speed` degerini hareket ettiren betik yazar.

const Kit = preload("res://scripts/kit.gd")

var coat := Color("dba25c")
var accent := Color("f8ead2")
var ear_color := Color("a9713b")
var collar_color := Color("e2574c")
var speed := 0.0
var excited := false
var stage := 2   # 0 yavru, 1 genc, 2 yetiskin
var sitting := false
var happy_time := 0.0
var mouth: Node3D   # agizda tasinan esya buraya takilir

var _rig: Node3D
var _head: Node3D
var _tail: Node3D
var _hat: Node3D
var _legs: Array[Node3D] = []
var _ears: Array[Node3D] = []
var _phase := 0.0
var _t := 0.0
var _base_y := 0.0
var _sit := 0.0


func _ready() -> void:
	_t = randf() * 10.0
	var body := Kit.plush(coat)
	var light := Kit.plush(accent)
	var ear := Kit.plush(ear_color)
	var dark := Kit.mat("2a2320", 0.4)

	_rig = Kit.pivot(self)
	Kit.capsule(_rig, 0.2, 0.8, Vector3(0, 0.47, 0.02), body, Vector3(PI / 2, 0, 0))
	Kit.ball(_rig, 0.19, Vector3(0, 0.41, -0.2), light, Vector3(0.85, 0.85, 0.9))

	_head = Kit.pivot(_rig, Vector3(0, 0.74, -0.4))
	Kit.ball(_head, 0.23, Vector3.ZERO, body)
	Kit.ball(_head, 1.0, Vector3(0, -0.06, -0.19), light, Vector3(0.13, 0.11, 0.17))
	Kit.ball(_head, 0.045, Vector3(0, -0.02, -0.35), dark)
	for sx in [-1.0, 1.0]:
		Kit.ball(_head, 0.04, Vector3(0.1 * sx, 0.06, -0.19), dark)
		Kit.ball(_head, 0.013, Vector3(0.09 * sx, 0.078, -0.222), Kit.glow("ffffff", 0.6), Vector3.ONE, 6)
		var e := Kit.pivot(_head, Vector3(0.18 * sx, 0.13, 0.02))
		e.rotation.z = 0.3 * sx
		Kit.ball(e, 1.0, Vector3(0, -0.13, 0), ear, Vector3(0.07, 0.17, 0.11))
		_ears.append(e)

	mouth = Kit.pivot(_head, Vector3(0, -0.1, -0.36))

	for lp in [Vector3(-0.12, 0.42, -0.24), Vector3(0.12, 0.42, -0.24), Vector3(-0.12, 0.42, 0.28), Vector3(0.12, 0.42, 0.28)]:
		var leg := Kit.pivot(_rig, lp)
		Kit.capsule(leg, 0.065, 0.42, Vector3(0, -0.2, 0), body)
		Kit.ball(leg, 0.08, Vector3(0, -0.385, -0.02), light, Vector3(1, 0.7, 1.2))
		_legs.append(leg)

	_tail = Kit.pivot(_rig, Vector3(0, 0.6, 0.4))
	_tail.rotation.x = 0.7
	Kit.capsule(_tail, 0.045, 0.34, Vector3(0, 0.15, 0), body)
	Kit.ball(_tail, 0.05, Vector3(0, 0.31, 0), light)

	# Tasma ve kunye
	Kit.torus(_rig, 0.17, 0.22, Vector3(0, 0.63, -0.27), Kit.mat(collar_color.to_html(false), 0.6), Vector3(-0.55, 0, 0))
	Kit.ball(_rig, 0.04, Vector3(0, 0.5, -0.4), Kit.mat("f2c14e", 0.3))

	# Hasir sapka (aksesuar ornegi)
	_hat = Kit.pivot(_head, Vector3(0, 0.2, 0.02))
	_hat.rotation = Vector3(0.12, 0, -0.1)
	Kit.cyl(_hat, 0.29, 0.31, 0.025, Vector3.ZERO, Kit.mat("ecd08a"), 18)
	Kit.cyl(_hat, 0.14, 0.17, 0.13, Vector3(0, 0.07, 0), Kit.mat("ecd08a"), 18)
	Kit.cyl(_hat, 0.172, 0.176, 0.04, Vector3(0, 0.035, 0), Kit.mat("e2574c"), 18)
	_hat.visible = false
	set_stage(stage)


func set_hat(on: bool) -> void:
	_hat.visible = on


func has_hat() -> bool:
	return _hat.visible


## Buyume evresi: tek model, oranlar degisir (yavruda buyuk bas, kisa bacak).
func set_stage(s: int) -> void:
	stage = clampi(s, 0, 2)
	var total: float = [0.55, 0.78, 1.0][stage]
	var head: float = [1.32, 1.15, 1.0][stage]
	var leg: float = [0.78, 0.9, 1.0][stage]
	scale = Vector3.ONE * total
	_head.scale = Vector3.ONE * head
	for l in _legs:
		l.scale.y = leg
	_base_y = -(1.0 - leg) * 0.42


func _process(dt: float) -> void:
	_t += dt
	var move := clampf(speed / 3.0, 0.0, 1.0)
	if speed > 0.05:
		_phase += dt * (5.0 + speed * 2.4)
	var sw := sin(_phase) * 0.75 * move
	# Oturma: govde arkaya yatar, arka bacaklar one uzanir
	_sit = move_toward(_sit, 1.0 if sitting and speed < 0.05 else 0.0, dt * 4.0)
	var s := smoothstep(0.0, 1.0, _sit)
	happy_time = maxf(happy_time - dt, 0.0)
	var hop := absf(sin(_t * 9.0)) * 0.12 if happy_time > 0.0 and speed < 0.05 else 0.0
	_legs[0].rotation.x = sw - 0.55 * s
	_legs[1].rotation.x = -sw - 0.55 * s
	_legs[2].rotation.x = -sw - 1.75 * s
	_legs[3].rotation.x = sw - 1.75 * s
	_rig.rotation.x = 0.55 * s
	_rig.position.y = _base_y + absf(sin(_phase)) * 0.05 * move + sin(_t * 2.0) * 0.006 + hop
	_rig.rotation.z = sin(_phase) * 0.04 * move
	_tail.rotation.y = sin(_t * (14.0 if excited or happy_time > 0.0 or speed > 0.05 else 5.0)) * 0.55
	_head.rotation.z = sin(_t * 0.9) * 0.1 * (1.0 - move)
	_head.rotation.x = sin(_t * 1.7) * 0.04 - 0.08 * move - 0.45 * s
	for i in 2:
		_ears[i].rotation.x = sin(_phase * 2.0 + i) * 0.3 * move
