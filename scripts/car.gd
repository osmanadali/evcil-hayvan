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
var hold := 0.0               # > 0 iken bekler (cagrilan taksi)
var cruise := CRUISE
var rider: Node3D             # bisikletli: surucu (PersonModel); donerken kolla isaret verir
var grip := Vector3(0.3, 1.02, -0.36)
var turn_sign := 0            # -1 sola, +1 saga donecek (sinyal)
var _queued := -1             # bir sonraki kavsakta secilen yol (onceden; sinyal icin)
var _blinkers: Array = []     # [MeshInstance3D, taraf]
var _blink_t := 0.0
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


## Telefonla cagrildi: verilen yol dugumunden baslayip bekle.
func summon(k: int, wait: float) -> void:
	node = k
	_prev = -1
	_pos = Vector2.INF
	_pick()
	_t = 0.0
	_speed = 0.0
	hold = wait


func _pick() -> void:
	if _queued >= 0 and ParkMap.road_next[node].has(_queued) and _queued != _prev:
		_next = _queued
		_queued = -1
		_from = _lane(node, _next, false)
		_to = _lane(node, _next, true)
		_len = maxf(_from.distance_to(_to), 0.1)
		_t = 0.0
		return
	_queued = -1
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
	var want := cruise
	if hold > 0.0:
		hold -= dt
		want = 0.0
	if owner_node:
		var rel := Vector2(owner_node.position.x, owner_node.position.z) - (p if _pos == Vector2.INF else _pos)
		var ahead := rel.dot(dir)
		if ahead > -1.0 and ahead < 11.0 and absf(rel.dot(Vector2(-dir.y, dir.x))) < 3.2:
			want = 0.0
	_speed = move_toward(_speed, want, dt * (9.0 if want < _speed else 3.5))
	_t += _speed * dt / _len
	# Kavsaga yaklasirken sonraki yolu sec ve donus yonunu hesapla (sinyal)
	if _queued < 0 and (1.0 - _t) * _len < 18.0:
		var opts: Array = []
		for nb in ParkMap.road_next[_next]:
			if nb != node and ParkMap.inside_bounds(ParkMap.nodes[nb], -40.0):
				opts.append(nb)
		if not opts.is_empty():
			_queued = opts[randi() % opts.size()]
			var d1 := (ParkMap.nodes[_next] - ParkMap.nodes[node]).normalized()
			var d2 := (ParkMap.nodes[_queued] - ParkMap.nodes[_next]).normalized()
			var ang := d1.angle_to(d2)
			turn_sign = (1 if ang > 0.0 else -1) if absf(ang) > 0.45 else 0
	if _t > 0.25 and _t < 0.6 and _queued < 0:
		turn_sign = 0
	_update_signals(dt)
	if get_child_count() > 0:
		_World.spin_wheels(get_child(0), _speed * dt)
	if _t >= 1.0:
		get_tree().create_timer(1.5).timeout.connect(func(): if _queued < 0: turn_sign = 0)
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


## Sinyal lambalari: aracin dort kosesinde turuncu; donus yonundekiler yanip soner.
static func add_blinkers(holder: Node3D) -> Array:
	# Modelin yuzey noktalari (arac uzayinda): sinyaller farlarin hizasinda govdeye oturur
	var pts := PackedVector3Array()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or String(mi.name).begins_with("wheel"):
			continue
		var xf := _rel(holder, mi)
		var a := xf * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
		for si in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 6000)
			for k in range(0, verts.size(), step):
				pts.append(xf * verts[k])
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("ffa31a")
	m.emission_enabled = true
	m.emission = Color("ff9a00")
	m.emission_energy_multiplier = 4.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var out: Array = []
	var w := box.size.x
	var hgt := box.size.y
	for front in [true, false]:
		for side in [-1, 1]:
			# Farin yaklasik yeri: yanlardan icerde, on/arka yuzeyde
			var target := Vector3(box.get_center().x + side * w * 0.36, box.position.y + hgt * (0.5 if front else 0.58),
				box.position.z if front else box.end.z)
			var best := target
			var bd := 1e9
			for q in pts:
				var d := (q - target).length_squared() + absf(q.y - target.y) * 2.0
				if d < bd:
					bd = d
					best = q
			var b := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 12
			sm.rings = 6
			b.mesh = sm
			b.scale = Vector3(0.13, 0.07, 0.04)
			b.material_override = m
			b.position = best + Vector3(0, 0, -0.01 if front else 0.01)
			b.visible = false
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(b)
			out.append([b, side])
	return out


static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != root and cur != null:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func blink(list: Array, sign: int, t: float) -> void:
	var on := sign != 0 and fmod(t, 0.8) < 0.4
	for b in list:
		b[0].visible = on and b[1] == sign


func _update_signals(dt: float) -> void:
	_blink_t += dt
	if rider:
		rider.ride_speed = _speed
		var h := get_child(0) as Node3D
		var xf := h.global_transform
		var l := xf * Vector3(-grip.x, grip.y, grip.z)
		var r := xf * Vector3(grip.x, grip.y, grip.z)
		# El isareti: donecegi taraftaki kol omuz hizasinda yana uzanir
		if turn_sign < 0:
			l = xf * Vector3(-0.95, 1.42, 0.2)
		elif turn_sign > 0:
			r = xf * Vector3(0.95, 1.42, 0.2)
		rider.grips = [l, r]
		return
	if _blinkers.is_empty() and get_child_count() > 0:
		_blinkers = add_blinkers(get_child(0))
	blink(_blinkers, turn_sign, _blink_t)
