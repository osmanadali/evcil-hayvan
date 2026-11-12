extends Node3D
## Parkta gezen gecici insan figuru. Hazir karakter paketi gelince degisecek.

const Kit = preload("res://scripts/kit.gd")

var shirt := Color("5aa9e6")
var pants := Color("3d4b6b")
var hair := Color("4a3426")
var skin := Color("f2c9a5")
var long_hair := false
var speed := 0.0

var _limbs: Array[Node3D] = []
var _phase := 0.0


func _ready() -> void:
	var m_skin := Kit.mat(skin.to_html(false))
	var m_shirt := Kit.mat(shirt.to_html(false))
	var m_pants := Kit.mat(pants.to_html(false))
	var m_hair := Kit.mat(hair.to_html(false))
	for sx in [-1.0, 1.0]:
		var leg := Kit.pivot(self, Vector3(0.1 * sx, 0.56, 0))
		Kit.capsule(leg, 0.085, 0.56, Vector3(0, -0.26, 0), m_pants)
		Kit.ball(leg, 0.1, Vector3(0, -0.51, -0.04), Kit.mat("ffffff"), Vector3(1, 0.6, 1.4))
		_limbs.append(leg)
	for sx in [-1.0, 1.0]:
		var arm := Kit.pivot(self, Vector3(0.26 * sx, 1.06, 0))
		Kit.capsule(arm, 0.065, 0.46, Vector3(0, -0.2, 0), m_shirt)
		Kit.ball(arm, 0.07, Vector3(0, -0.43, 0), m_skin)
		_limbs.append(arm)
	Kit.capsule(self, 0.21, 0.66, Vector3(0, 0.84, 0), m_shirt)
	Kit.ball(self, 0.25, Vector3(0, 1.38, 0), m_skin)
	Kit.ball(self, 0.265, Vector3(0, 1.43, 0.035), m_hair, Vector3(1, 0.92, 1))
	if long_hair:
		Kit.ball(self, 0.24, Vector3(0, 1.24, 0.1), m_hair, Vector3(1, 1.3, 0.75))
		Kit.cyl(self, 0.2, 0.33, 0.34, Vector3(0, 0.58, 0), m_shirt)
	for sx in [-1.0, 1.0]:
		Kit.ball(self, 0.032, Vector3(0.09 * sx, 1.38, -0.228), Kit.mat("2a2320", 0.4))


func _process(dt: float) -> void:
	var move := clampf(speed / 1.2, 0.0, 1.0)
	if speed > 0.05:
		_phase += dt * 6.5
	var sw := sin(_phase) * 0.55 * move
	_limbs[0].rotation.x = sw
	_limbs[1].rotation.x = -sw
	_limbs[2].rotation.x = -sw * 0.8
	_limbs[3].rotation.x = sw * 0.8
