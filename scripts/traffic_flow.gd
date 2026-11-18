extends Node
## Trafik yoneticisi: oyuncunun cevresinde sabit sayida arac tutar. Araclar gorus disinda dogar, uzaklasinca ya da
## haritadan cikinca baska bir yola tasinir; takilan arac goz onunde degilse kaldirilir. Uzaktaki araclar ucuz
## simulasyona gecer (car.gd 'far'). Yogunluk Ayarlar'dan secilir (Az / Normal / Yogun).

const ParkMap = preload("res://scripts/park_map.gd")
const Car = preload("res://scripts/car.gd")
const TN = preload("res://scripts/traffic_net.gd")
const Kit = preload("res://scripts/kit.gd")
const PersonModel = preload("res://scripts/person_model.gd")

const COUNTS := [10, 18, 30]      # yogunluga gore arac sayisi
const BIKES := [2, 3, 5]
const NEAR := 110.0               # bundan uzaktaki arac ucuz calisir
const R_MIN := 65.0               # en yakin dogma uzakligi
const R_MAX := 165.0
const R_OUT := 205.0              # bundan uzaklasan arac baska yere tasinir
const KINDS := ["araba", "taksi", "hatchback", "dolmus", "araba", "kamyonet", "hatchback", "motosiklet",
	"taksi", "araba", "dolmus", "hatchback", "kamyonet", "araba", "motosiklet", "taksi"]
const PAINTS := ["f2f2f2", "9a9da3", "3a3d42", "b23a34", "2f4f8a", "e9e4d6", "f2c230", "6b7a5a", "1f2a44"]

var m: Node
var _t := 0.0
var _made := 0
var _bikes_made := 0
var _on := false


func density() -> int:
	return clampi(int(m._args.get("traffic", m.state.d.get("traffic", 1))), 0, 2)


func target() -> int:
	var n: int = COUNTS[density()]
	return n if ParkMap.zone == "" else int(n * 0.6)


func bike_target() -> int:
	var n: int = BIKES[density()]
	return n if ParkMap.zone == "" else maxi(1, n / 2)


## Dunya kurulunca: ilk araclari oyuncunun cevresine dagit.
func start() -> void:
	TN.ensure()
	Car.traffic.clear()
	Car.peds = m._npc_people
	Car.honk_cb = _honk
	Car.stops = []
	for st in m.world.stops:
		Car.stops.append(st["pos"])
	Car.crossings = []
	for c in ParkMap.data.get("crossings", []):
		Car.crossings.append(Vector2(c["pos"][0], c["pos"][1]))
	if m.world.car_mesh == null or TN.spawn_links.is_empty():
		return
	_on = true
	for i in target():
		_add_car(true)
	for i in bike_target():
		_add_bike(true)


func _process(dt: float) -> void:
	if not _on:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.35
	Car.player = m.owner_node
	var me: Vector2 = m._owner_pos()
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	for list: Array in [m._cars, m._cyclists]:
		for c in list.duplicate():
			if not is_instance_valid(c):
				list.erase(c)
				continue
			if not c.is_processing() or c.hold > 0.0:
				continue           # binilmis / cagrilmis arac: dokunma
			var d := me.distance_to(Vector2(c.position.x, c.position.z))
			c.far = d > NEAR
			var seen := d < 170.0 and cam != null and cam.is_position_in_frustum(c.global_position + Vector3(0, 1, 0))
			if c.dead or (d > R_OUT and (not seen or d > 340.0)) or (c.stuck_t > 28.0 and not seen):
				_recycle(c, list)
	var want := target()
	if m._cars.size() < want:
		_add_car(false)
	elif m._cars.size() > want:
		_drop_one(m._cars, me, cam)
	var bw := bike_target()
	if m._cyclists.size() < bw:
		_add_bike(false)
	elif m._cyclists.size() > bw:
		_drop_one(m._cyclists, me, cam)


## Dogma yeri: [a, b, oran] ya da bos. Oyuncunun gormedigi, baska aracin olmadigi bir yol parcasi.
func _find_spot(initial: bool, min_d := 45.0) -> Array:
	var me: Vector2 = m._owner_pos()
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	var best: Array = []
	var best_d := 1e9
	var found := 0
	for i in 140:
		var link: Array = TN.spawn_links[randi() % TN.spawn_links.size()]
		var pa := ParkMap.nodes[link[0]]
		var pb := ParkMap.nodes[link[1]]
		var t := randf_range(0.1, 0.8)
		var p := pa.lerp(pb, t)
		var d := p.distance_to(me)
		if d > R_MAX or d < (min_d if initial else R_MIN):
			continue
		if not initial and d < 150.0 and cam != null and cam.is_position_in_frustum(Vector3(p.x, ParkMap.terrain_height(p) + 1.0, p.y)):
			continue
		var free := true
		for o in Car.traffic:
			if is_instance_valid(o) and Vector2(o.position.x, o.position.z).distance_squared_to(p) < 20.0 * 20.0:
				free = false
				break
		if free and d < best_d:
			best_d = d
			best = [link[0], link[1], t]
			found += 1
			if found >= 3:
				break
	return best


func _place(c: Node3D, spot: Array) -> void:
	c._release()
	c.node = spot[0]
	c._prev = -1
	c._queued = spot[1]
	c._pos = Vector2.INF
	c._pick()
	c._s = float(spot[2]) * c._len
	c._speed = 4.0
	c.dead = false
	c.stuck_t = 0.0
	c._ghost_t = 0.0
	c._gap = 1e9
	c.far = false
	# Yerine hemen otursun (bir sonraki kareyi beklemeden)
	var p: Vector2 = c._point(c._s)
	c.position = Vector3(p.x, ParkMap.terrain_height(p), p.y)
	c.rotation.y = atan2(-c._dir.x, -c._dir.y)


## Hata ayiklama: butun araclari oyuncunun yeni yerinin cevresine yeniden dagitir.
func reseed(min_d := 45.0) -> void:
	for list: Array in [m._cars, m._cyclists]:
		for c in list:
			if is_instance_valid(c) and c.is_processing():
				c.position = Vector3(1e5, 0, 1e5)
	for list: Array in [m._cars, m._cyclists]:
		for c in list:
			if is_instance_valid(c) and c.is_processing():
				var spot := _find_spot(true, min_d)
				if not spot.is_empty():
					_place(c, spot)


## Hata ayiklama: merkeze en yakin i. isikli kavsak (100+: isiksiz, dort kollu kavsak).
func debug_junction(i: int) -> Vector2:
	var list: Array = []
	for k in TN.jr:
		if Car.lights.has(k) == (i < 100) and TN.road_nbs(k).size() >= (3 if i < 100 else 4):
			list.append(k)
	list.sort_custom(func(a, b): return ParkMap.nodes[a].length_squared() < ParkMap.nodes[b].length_squared())
	return ParkMap.nodes[list[(i % 100) % list.size()]] if not list.is_empty() else Vector2.ZERO


func _recycle(c: Node3D, list: Array) -> void:
	var spot := _find_spot(false)
	if spot.is_empty():
		if c.dead:
			_remove(c, list)
		return
	_place(c, spot)


func _remove(c: Node3D, list: Array) -> void:
	c._release()
	list.erase(c)
	Car.traffic.erase(c)
	c.queue_free()


func _drop_one(list: Array, me: Vector2, cam: Camera3D) -> void:
	var best: Node3D = null
	var bd := 60.0
	for c in list:
		if not is_instance_valid(c) or not c.is_processing() or c.hold > 0.0:
			continue
		var d := me.distance_to(Vector2(c.position.x, c.position.z))
		if d > bd and not (cam != null and d < 170.0 and cam.is_position_in_frustum(c.global_position + Vector3(0, 1, 0))):
			bd = d
			best = c
	if best:
		_remove(best, list)


func _add_car(initial: bool) -> void:
	var spot := _find_spot(initial)
	if spot.is_empty():
		return
	var i := _made
	_made += 1
	var kind: String = KINDS[i % KINDS.size()]
	var paint := Color(PAINTS[(i * 5 + i / 9) % PAINTS.size()])
	var car := Car.new()
	car.managed = true
	car.owner_node = m.owner_node
	if kind == "motosiklet":
		var mv: Node3D = m._vehicle("res://assets/models/motosiklet.glb", 2.05, true)
		if mv == null:
			kind = "araba"
		else:
			mv.set_meta("model", "motosiklet")
			car.add_child(mv)
	if kind == "kamyonet":
		car.add_child(_pickup(paint, i))
	elif kind != "motosiklet":
		car.add_child(m.world.traffic_model(kind, i, paint))
	car.set_kind("araba" if kind == "hatchback" else kind)
	car.pace *= randf_range(0.92, 1.08)
	_place(car, spot)
	m.add_child(car)
	if kind == "motosiklet":
		_seat_rider(car, car.get_child(0), "motosiklet", i)
	m._cars.append(car)
	Car.traffic.append(car)


func _add_bike(initial: bool) -> void:
	var spot := _find_spot(initial)
	if spot.is_empty():
		return
	var bike: Node3D = m._vehicle("res://assets/models/bisiklet.glb", 1.75, true)
	if bike == null:
		return
	var i := _bikes_made
	_bikes_made += 1
	var cy := Car.new()
	cy.managed = true
	cy.set_kind("bisiklet")
	cy.cruise = randf_range(3.8, 5.2)
	cy.owner_node = m.owner_node
	cy.add_child(bike)
	_place(cy, spot)
	m.add_child(cy)
	_seat_rider(cy, bike, "bisiklet", i)
	m._cyclists.append(cy)
	Car.traffic.append(cy)


## Iki tekerlinin surucusu (PersonModel): selede oturur, gidonu tutar.
func _seat_rider(car: Node3D, holder: Node3D, ride: String, i: int) -> void:
	var spec: Dictionary = m.RIDES[ride]
	var rd := PersonModel.new()
	rd.kind = "kadin" if i % 2 == 0 else "erkek"
	rd.tint = Color(["2f62a8", "e07b1f", "3f8f4a", "c8322b", "3a3d42"][i % 5])
	holder.add_child(rd)
	rd.riding = ride
	rd.ride_lean = float(spec["lean"])
	if spec.has("crank"):
		rd.ride_crank = spec["crank"]
	if spec.has("foot") and ride != "bisiklet":
		rd.ride_feet = spec["foot"]
	var seat: Vector3 = spec["seat"]
	rd.position = Vector3(0, seat.y + 0.09 - rd.hips_height(), seat.z)
	car.rider = rd
	car.grip = spec["grip"]


## Kamyonet: kabin + acik kasa (sade govde; modeli yok).
func _pickup(paint: Color, i: int) -> Node3D:
	var h := Node3D.new()
	h.set_meta("model", "kamyonet")
	var body := Kit.mat(paint.to_html(false), 0.4)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("18222b")
	dark.roughness = 0.1
	dark.metallic_specular = 0.9
	var black := Kit.mat("1b1b1d", 0.9)
	var grey := Kit.mat("55595f", 0.7)
	Kit.box(h, Vector3(1.9, 0.5, 5.2), Vector3(0, 0.72, 0), body)                 # govde
	Kit.box(h, Vector3(1.86, 0.3, 1.0), Vector3(0, 1.1, -2.08), body)              # kaput
	Kit.box(h, Vector3(1.86, 0.92, 1.75), Vector3(0, 1.42, -0.75), body)           # kabin
	Kit.box(h, Vector3(1.88, 0.5, 1.35), Vector3(0, 1.56, -0.75), dark)            # yan camlar
	Kit.box(h, Vector3(1.62, 0.52, 0.05), Vector3(0, 1.56, -1.63), dark)           # on cam
	Kit.box(h, Vector3(1.5, 0.45, 0.05), Vector3(0, 1.56, 0.13), dark)             # arka cam
	for x in [-0.92, 0.92]:
		Kit.box(h, Vector3(0.07, 0.42, 2.45), Vector3(x, 1.17, 1.37), body)         # kasa yanlari
	Kit.box(h, Vector3(1.9, 0.42, 0.07), Vector3(0, 1.17, 2.57), body)             # kasa kapagi
	Kit.box(h, Vector3(1.76, 0.04, 2.4), Vector3(0, 0.98, 1.37), grey)             # kasa tabani
	Kit.box(h, Vector3(1.92, 0.16, 0.12), Vector3(0, 0.5, -2.6), grey)             # on tampon
	Kit.box(h, Vector3(1.92, 0.16, 0.12), Vector3(0, 0.5, 2.6), grey)
	# Yuk: kasalar ya da branda
	if i % 2 == 0:
		var wood := Kit.mat("a8793f", 0.9)
		Kit.box(h, Vector3(0.8, 0.55, 0.8), Vector3(-0.4, 1.28, 0.8), wood)
		Kit.box(h, Vector3(0.8, 0.55, 0.8), Vector3(0.42, 1.28, 0.85), wood)
		Kit.box(h, Vector3(0.9, 0.45, 0.9), Vector3(0.0, 1.23, 1.85), Kit.mat("8a6a3a", 0.9))
	else:
		Kit.box(h, Vector3(1.7, 0.4, 2.3), Vector3(0, 1.25, 1.37), Kit.mat("3d5a4a", 0.95))
	for z in [-1.7, 1.55]:
		for x in [-0.88, 0.88]:
			var w := Kit.cyl(h, 0.37, 0.37, 0.26, Vector3(x, 0.37, z), black, 14, Vector3(0, 0, PI / 2))
			w.name = "wheel_k%d" % h.get_child_count()
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color("fff6d8")
	lamp.emission_enabled = true
	lamp.emission = Color("fff1c4")
	var red := StandardMaterial3D.new()
	red.albedo_color = Color("b8140c")
	red.emission_enabled = true
	red.emission = Color("a01008")
	for x in [-0.7, 0.7]:
		Kit.box(h, Vector3(0.34, 0.16, 0.05), Vector3(x, 0.86, -2.61), lamp)
		Kit.box(h, Vector3(0.2, 0.3, 0.05), Vector3(x * 1.2, 0.95, 2.62), red)
	m.world.add_driver(h, Vector3(-0.44, 1.02, -0.72), i)
	return h


func _honk(c: Node3D) -> void:
	if m.tplus == null or not is_instance_valid(c):
		return
	if m._owner_pos().distance_to(Vector2(c.position.x, c.position.z)) < 70.0:
		m.tplus._honk(c)
