extends Node3D
## EGO otobusu: hattin gercek guzergahini izler, duraklarda durur, kapilarini acar.
## Guzergah assets/transit.json'dan gelir (tools/transit_build.py). Harita disina cikinca bir sure gorunmez
## (hattin Ulus / Kizilay kismi), sonra ters yonde geri gelir.

const ParkMap = preload("res://scripts/park_map.gd")
const Kit = preload("res://scripts/kit.gd")
const _World = preload("res://scripts/world.gd")
const CRUISE := 8.5
const DWELL := 9.0
const LANE := 1.8
const AWAY := 40.0            # harita disinda gecen sure (sn)

var line := "427"
var title := ""
var color := Color("1f5fae")
var owner_node: Node3D
var legs: Array = []          # [{path: PackedVector2Array, arc: PackedFloat32Array, stops: [{name, s, pos}]}]
var leg := 0
var s := 0.0
var speed := 0.0
var dwell := 0.0
var away := 0.0
var at_stop := ""             # durakta beklerken durak adi
var stop_pos := Vector2.ZERO  # son durulan duragin bekleme yeri
var last_stop := {}
var _next_stop := 0
var _doors: Array[Node3D] = []
var _wheels: Array = []


func setup(no: String, data: Dictionary, start_leg: int, start_s: float) -> void:
	line = no
	title = data["name"]
	color = Color(data["color"])
	for key in ["gidis", "donus"]:
		var lg: Dictionary = data[key]
		var path := PackedVector2Array()
		var arc := PackedFloat32Array()
		var total := 0.0
		for p in lg["path"]:
			var v := Vector2(p[0], p[1])
			if not path.is_empty():
				total += path[path.size() - 1].distance_to(v)
			path.append(v)
			arc.append(total)
		var stops: Array = []
		for st in lg["stops"]:
			stops.append({"name": st["name"], "s": float(st["s"]), "pos": Vector2(st["pos"][0], st["pos"][1])})
		legs.append({"path": path, "arc": arc, "stops": stops})
	leg = start_leg
	s = start_s
	_skip_passed_stops()


func _ready() -> void:
	if ResourceLoader.exists("res://assets/models/otobus.glb"):
		_model_from_file()
	else:
		_model_simple()


## Tripo'dan gelen model varsa: 12 m boya olceklenir, onu -Z'ye bakar.
func _model_from_file() -> void:
	var inst: Node3D = load("res://assets/models/otobus.glb").instantiate()
	var holder := Node3D.new()
	holder.add_child(inst)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D()
		var n: Node = mi
		while n != inst:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var a := xf * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	# Bu modelin onu +X yonunde (oyunda on = -Z): PI/2 + PI cevrilir
	inst.rotation.y = (PI / 2.0 if box.size.x > box.size.z else 0.0) + PI
	var k := 12.0 / maxf(box.size.x, box.size.z)
	inst.scale = Vector3.ONE * k
	var c := box.get_center()
	inst.position = Basis(Vector3.UP, inst.rotation.y) * Vector3(-c.x, 0, -c.z) * k
	inst.position.y = -box.position.y * k
	add_child(holder)
	_wheels = _World.find_wheels(inst, k)
	set_meta("wheels", _wheels)
	_destination(Vector3(0, 2.95, -6.02))


## Model gelene kadar: EGO otobusune benzeyen sade govde.
func _model_simple() -> void:
	var white := Kit.mat("f1f2ef", 0.35)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("18222b")
	dark.roughness = 0.08
	dark.metallic_specular = 0.9
	var stripe := Kit.mat(color.to_html(false), 0.4)
	var black := Kit.mat("1b1b1d", 0.9)
	Kit.box(self, Vector3(2.55, 2.55, 11.9), Vector3(0, 1.72, 0), white)
	Kit.box(self, Vector3(2.57, 0.95, 10.4), Vector3(0, 2.2, 0.55), dark)           # yan camlar
	Kit.box(self, Vector3(2.3, 1.35, 0.04), Vector3(0, 2.1, -5.96), dark)            # on cam
	Kit.box(self, Vector3(2.3, 0.9, 0.04), Vector3(0, 2.35, 5.96), dark)             # arka cam
	Kit.box(self, Vector3(2.58, 0.32, 11.92), Vector3(0, 1.1, 0), stripe)            # renkli serit
	Kit.box(self, Vector3(1.6, 0.35, 3.0), Vector3(0, 3.15, 1.2), Kit.mat("d8dad6", 0.5))   # klima
	for z in [-3.4, 1.6]:
		var door := Node3D.new()
		door.position = Vector3(1.29, 1.55, z)
		add_child(door)
		Kit.box(door, Vector3(0.03, 2.3, 1.15), Vector3.ZERO, dark)
		_doors.append(door)
	for z in [-3.9, 3.4]:
		for x in [-1.12, 1.12]:
			Kit.cyl(self, 0.5, 0.5, 0.32, Vector3(x, 0.5, z), black, 14, Vector3(0, 0, PI / 2))
	for x in [-0.85, 0.85]:
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = Color("fff6d8")
		lamp.emission_enabled = true
		lamp.emission = Color("fff1c4")
		Kit.box(self, Vector3(0.35, 0.16, 0.04), Vector3(x, 0.85, -5.97), lamp)
	_destination(Vector3(0, 2.95, -5.97))


func _destination(at: Vector3) -> void:
	var board := Label3D.new()
	board.text = "%s  %s" % [line, title.get_slice("-", 0)]
	board.font_size = 64
	board.pixel_size = 0.0045
	board.modulate = Color("ffb52e")
	board.outline_size = 0
	board.position = at
	board.rotation.y = PI
	board.double_sided = false
	add_child(board)
	var side := board.duplicate() as Label3D
	side.position = Vector3(1.3, 2.95, -2.2)
	side.rotation.y = PI / 2
	add_child(side)


func _skip_passed_stops() -> void:
	_next_stop = 0
	var st: Array = legs[leg]["stops"]
	while _next_stop < st.size() and float(st[_next_stop]["s"]) < s:
		_next_stop += 1


func _process(dt: float) -> void:
	if away > 0.0:
		away -= dt
		visible = false
		if away <= 0.0:
			leg = (leg + 1) % legs.size()
			s = 0.0
			_skip_passed_stops()
		return
	var lg: Dictionary = legs[leg]
	var arc: PackedFloat32Array = lg["arc"]
	var total: float = arc[arc.size() - 1]
	var stops: Array = lg["stops"]
	if dwell > 0.0:
		dwell -= dt
		speed = 0.0
		_open_doors(1.0)
		if dwell <= 0.0:
			at_stop = ""
	else:
		_open_doors(0.0)
		var want := CRUISE
		if _next_stop < stops.size():
			var gap: float = float(stops[_next_stop]["s"]) - s
			want = minf(want, sqrt(2.0 * 1.4 * maxf(gap, 0.0)) + 0.4)
			if gap < 0.4:
				var st: Dictionary = stops[_next_stop]
				dwell = DWELL
				at_stop = st["name"]
				stop_pos = st["pos"]
				last_stop = st
				_next_stop += 1
		if owner_node and owner_node.is_visible_in_tree():
			var here := _point(s)
			var dir := (_point(s + 2.0) - here).normalized()
			var rel := Vector2(owner_node.global_position.x, owner_node.global_position.z) - here
			var ahead := rel.dot(dir)
			if ahead > 0.0 and ahead < 13.0 and absf(rel.dot(Vector2(-dir.y, dir.x)) - LANE) < 2.4:
				want = 0.0          # yolun ortasindaki oyuncuya yol verir
		speed = move_toward(speed, want, dt * (3.0 if want < speed else 1.6))
		s += speed * dt
		if not _wheels.is_empty():
			_World.spin_wheels(self, speed * dt)
		if s >= total:
			var end := _point(total)
			if ParkMap.inside_bounds(end, -30.0):
				leg = (leg + 1) % legs.size()      # harita icinde donuyor
				s = 0.0
				_skip_passed_stops()
			else:
				away = AWAY
				visible = false
				return
	var p := _point(s)
	var ahead_p := _point(s + 3.0)
	var d := ahead_p - p
	if d.length() < 0.01:
		d = Vector2(0, -1)
	d = d.normalized()
	var lane := p + Vector2(-d.y, d.x) * LANE
	var h := ParkMap.terrain_height(lane)
	var h2 := ParkMap.terrain_height(lane + d * 4.0)
	position = Vector3(lane.x, h, lane.y)
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.y), minf(1.0, dt * 4.0))
	rotation.x = lerpf(rotation.x, atan2(h2 - h, 4.0), minf(1.0, dt * 3.0))
	visible = ParkMap.inside_bounds(lane, -80.0)


func _point(at_s: float) -> Vector2:
	var lg: Dictionary = legs[leg]
	var path: PackedVector2Array = lg["path"]
	var arc: PackedFloat32Array = lg["arc"]
	at_s = clampf(at_s, 0.0, arc[arc.size() - 1])
	var i := arc.bsearch(at_s)
	if i <= 0:
		return path[0]
	var t := (at_s - arc[i - 1]) / maxf(arc[i] - arc[i - 1], 0.001)
	return path[i - 1].lerp(path[i], t)


func _open_doors(k: float) -> void:
	for dr in _doors:
		dr.position.x = lerpf(dr.position.x, 1.29 + 0.08 * k, 0.2)
		dr.scale.z = lerpf(dr.scale.z, 1.0 - 0.85 * k, 0.2)
