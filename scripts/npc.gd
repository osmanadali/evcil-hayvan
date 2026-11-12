extends Node3D
## NPC hareketi: rota boyunca git-gel, bir bolgede gezin veya birini takip et.

const ParkMap = preload("res://scripts/park_map.gd")

var visual               # `speed` degiskeni olan gorsel (kopek veya insan)
var route: Array = []    # Vector2 listesi; bos ise bolgede gezinir
var roam_center := Vector2.ZERO
var roam_radius := 5.0
var follow: Node3D
var walk_speed := 1.3
var short_pause := false
var graph_node := -1        # >= 0 ise sokak aginda rastgele yurur
var world: Node3D          # verilirse gezinirken engelli noktalari secmez
var _prev_node := -1

var _target := Vector2.ZERO
var _idx := 0
var _dir := 1
var _pause := 0.0


func _ready() -> void:
	if graph_node >= 0:
		_target = ParkMap.nodes[graph_node]
		place(_target)
	elif route.size() > 0:
		_target = route[0]
		place(_target)
	else:
		place(roam_center)
		_next()


func place(p: Vector2) -> void:
	position = Vector3(p.x, ParkMap.walk_height(p), p.y)


func _next() -> void:
	if graph_node >= 0:
		# Geldigi yone donmemeye calisarak komsu dugumlerden birini sec
		var options: Array = []
		for nb in ParkMap.links[graph_node]:
			if nb != _prev_node and ParkMap.inside_bounds(ParkMap.nodes[nb], 6.0):
				options.append(nb)
		var next: int = options[randi() % options.size()] if options.size() > 0 else _prev_node
		if next < 0:
			next = graph_node
		_prev_node = graph_node
		graph_node = next
		_target = ParkMap.nodes[graph_node]
		if randf() < 0.08:
			_pause = randf_range(2.0, 6.0)
	elif route.size() > 1:
		if _idx + _dir < 0 or _idx + _dir >= route.size():
			_dir = -_dir
			_pause = randf_range(2.0, 5.0)
		_idx += _dir
		_target = route[_idx]
	else:
		for i in 8:
			var a := randf() * TAU
			_target = roam_center + Vector2(cos(a), sin(a)) * randf() * roam_radius
			if ParkMap.water_sd(_target) > 1.0 and (world == null or world.is_free(_target, 0.4)):
				break
		_pause = randf_range(0.1, 0.6) if short_pause else randf_range(0.5, 4.0)


func _process(dt: float) -> void:
	var p := Vector2(position.x, position.z)
	var sp := walk_speed
	if follow:
		var fp := Vector2(follow.position.x, follow.position.z)
		var side := Vector2(cos(follow.rotation.y), -sin(follow.rotation.y))
		_target = fp + side * 0.8
		sp = clampf(p.distance_to(_target) * 2.0, 0.0, 3.2)
		if sp < 0.5:
			visual.speed = 0.0
			return
	elif _pause > 0.0:
		_pause -= dt
		visual.speed = 0.0
		return
	var to := _target - p
	var d := to.length()
	if d < 0.2:
		if not follow:
			_next()
		return
	place(p + to / d * minf(sp * dt, d))
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.y), minf(1.0, dt * 8.0))
	visual.speed = sp
