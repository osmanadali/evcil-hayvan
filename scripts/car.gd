extends Node3D
## Sokak aginda gezen araba: sag seritten gider, tek yonlere uyar, oyuncuya yol verir.

const ParkMap = preload("res://scripts/park_map.gd")
const _World = preload("res://scripts/world.gd")
const CRUISE := 7.5

var node := 0
var owner_node: Node3D
var _prev := -1
var _next := -1
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0
var _len := 1.0
var _speed := 0.0
var _pos := Vector2.INF       # gercek konum: serit noktasini yumusakca izler (koselerde ziplamaz)


func _ready() -> void:
	_pick()
	_t = randf()


func _lane(a: int, b: int, at_b: bool) -> Vector2:
	var pa := ParkMap.nodes[a]
	var pb := ParkMap.nodes[b]
	var dir := (pb - pa).normalized()
	var w := ParkMap.road_width(a, b)
	# Park edilen sokaklarda (5-9 m) kenarlar dolu: ortaya yakin git
	var off := clampf(w * 0.5 - 3.0, 0.0, 2.2) if w >= 5.0 and w <= 9.0 else minf(w * 0.22, 2.2)
	return (pb if at_b else pa) + Vector2(-dir.y, dir.x) * off


func _pick() -> void:
	var options: Array = []
	for nb in ParkMap.road_next[node]:
		if nb != _prev and ParkMap.inside_bounds(ParkMap.nodes[nb], -40.0):
			options.append(nb)
	if options.is_empty() and _prev >= 0 and _prev < ParkMap.nodes.size():
		# Cikmaz ya da harita kenari: geri don (isinlanmak yerine U donusu)
		options = [_prev]
	if options.is_empty():
		# Hic yol yok: baska bir yerden yeniden basla
		_pos = Vector2.INF
		for i in 40:
			var k := randi() % ParkMap.nodes.size()
			if ParkMap.road_next[k].size() > 0 and ParkMap.inside_bounds(ParkMap.nodes[k], 30.0):
				node = k
				_prev = -1
				break
		options = ParkMap.road_next[node].duplicate()
	_next = options[randi() % options.size()]
	_from = _lane(node, _next, false)
	_to = _lane(node, _next, true)
	_len = maxf(_from.distance_to(_to), 0.1)
	_t = 0.0


func _process(dt: float) -> void:
	var p := _from.lerp(_to, _t)
	var dir := (_to - _from) / _len
	var want := CRUISE
	if owner_node:
		var rel := Vector2(owner_node.position.x, owner_node.position.z) - (p if _pos == Vector2.INF else _pos)
		var ahead := rel.dot(dir)
		if ahead > -1.0 and ahead < 11.0 and absf(rel.dot(Vector2(-dir.y, dir.x))) < 3.2:
			want = 0.0
	_speed = move_toward(_speed, want, dt * (9.0 if want < _speed else 3.5))
	_t += _speed * dt / _len
	if get_child_count() > 0:
		_World.spin_wheels(get_child(0), _speed * dt)
	if _t >= 1.0:
		_prev = node
		node = _next
		_pick()
		return
	if _pos == Vector2.INF:
		_pos = p
	var prev_pos := _pos
	# Serit noktasini ~1 sn gecikmeyle izle: koseler yay cizer, seritler arasi gecis kayar
	_pos = _pos.lerp(p, minf(1.0, dt * 2.2))
	var mv := _pos - prev_pos
	var face := mv.normalized() if mv.length() > 0.002 else dir
	var h := ParkMap.terrain_height(_pos)
	var h2 := ParkMap.terrain_height(_pos + face * 2.0)
	position = Vector3(_pos.x, h, _pos.y)
	rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.y), minf(1.0, dt * 4.0))
	rotation.x = lerpf(rotation.x, atan2(h2 - h, 2.0), minf(1.0, dt * 4.0))
