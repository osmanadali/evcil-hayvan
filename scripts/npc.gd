extends Node3D
const _Car = preload("res://scripts/car.gd")
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
var play_mate: Node3D       # oyuncunun hayvaniyla kovalamaca (bu hayvan kacar)
var play_t := 0.0
var hold := 0.0              # > 0 iken durur ve hold_face noktasina doner (selamlasma)
var hold_face := Vector2.ZERO

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
		# Sokaklarda yolun sag kenarindan (kaldirimdan) yuru
		var from: Vector2 = ParkMap.nodes[graph_node]
		var to: Vector2 = ParkMap.nodes[next]
		var w := ParkMap.road_width(graph_node, next)
		var dir := (to - from).normalized()
		_prev_node = graph_node
		graph_node = next
		_target = to + Vector2(-dir.y, dir.x) * ((w * 0.5 + 1.2) if w > 0.0 else 0.0)
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
	if play_t > 0.0 and is_instance_valid(play_mate):
		play_t -= dt
		var away := p - Vector2(play_mate.position.x, play_mate.position.z)
		var d := away.length()
		var mv := Vector2.ZERO
		if d < 2.6:
			# Yakalanmamak icin yana kacar (daire cizerek), cok yakinsa itilir
			mv = away.normalized().rotated(0.7) * (3.6 if d > 0.7 else 5.0)
		var np := p + mv * dt
		if world == null or world.is_free(np, 0.3):
			place(np)
		if mv.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-mv.x, -mv.y), minf(1.0, dt * 10.0))
		else:
			rotation.y = lerp_angle(rotation.y, atan2(away.x, away.y), minf(1.0, dt * 6.0))
		visual.speed = mv.length()
		return
	if hold > 0.0:
		hold -= dt
		var f := hold_face - p
		if f.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(-f.x, -f.y), minf(1.0, dt * 6.0))
		visual.speed = 0.0
		return
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
	# Arac (otobus/araba) yolunun ustundeyse bekle; icinden gecme
	if d > 0.2:
		var fw := to / d
		for o in _Car.traffic:
			if not is_instance_valid(o) or not o.is_visible_in_tree():
				continue
			var rel := Vector2(o.global_position.x, o.global_position.z) - p
			if rel.length() < 7.0 and rel.dot(fw) > -1.0:
				visual.speed = 0.0
				return
	if d < 0.2:
		if not follow:
			_next()
		return
	place(p + to / d * minf(sp * dt, d))
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.y), minf(1.0, dt * 8.0))
	visual.speed = sp
