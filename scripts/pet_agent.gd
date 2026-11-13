extends Node3D
## Oyuncunun evcil hayvani: sahibini takip eder, komutlari yapar, oyun oynar.

const ParkMap = preload("res://scripts/park_map.gd")
const Kit = preload("res://scripts/kit.gd")
const PetModel = preload("res://scripts/pet_model.gd")
const Accessories = preload("res://scripts/accessories.gd")

enum Mode { FOLLOW, STAY, FETCH, RETURN, EAT, SLEEP, PLAY, YARN, WASH }

signal reward(kind: String, what: String)

var kind := "kopek"
var model: Node3D
var world: Node3D
var owner_node: Node3D
var owner_speed := 0.0
var state: Node
var mode := Mode.FOLLOW
var slot := Vector2(1.1, 0.5)     # sahibin yanindaki yeri (sag, arka)
var buddy: Node3D                 # oyuncunun diger hayvani
var play_partner: Node3D
var idle_time := 0.0
var external := false             # true: hareketi baska bir betik (pet_care.gd) yonetir
var stay_far := 22.0              # STAY modunda sahibi bu kadar uzaklasirsa gelir

var _t := 0.0
var _stuck := 0.0
var _wander := Vector2.ZERO
var _has_wander := false
var _item: Node3D
var _land := Vector2.ZERO
var _air_catch := false
var _role := 0
var _center := Vector2.ZERO
var _bats := 0
var _ball_vel := Vector2.ZERO
var _worn_nodes: Array[Node3D] = []
var _zzz: Label3D
var _ring: MeshInstance3D
var _tag: Label3D
var _stage := -1


func _ready() -> void:
	model = PetModel.new()
	model.kind = kind
	var pd: Dictionary = state.pet(kind)
	model.tint = Color(String(pd.get("tint", "ffffff")))
	model.size_mul = float(pd.get("size", 1.0))
	add_child(model)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 0.58
	_ring = Kit.add(self, ring, Kit.glow("ffe9a8", 0.9), Vector3(0, 0.04, 0))
	_ring.scale.y = 0.2
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	_zzz = _label("Zzz", Color("dfe9ff"))
	_zzz.visible = false
	_tag = _label("", Color.WHITE)
	_tag.font_size = 40
	refresh()


func _label(text: String, c: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.outline_size = 14
	l.modulate = c
	l.outline_modulate = Color(0.2, 0.15, 0.1, 0.9)
	l.pixel_size = 0.0032
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position = Vector3(0, 1.15, 0)
	add_child(l)
	return l


func pos2() -> Vector2:
	return Vector2(position.x, position.z)


func owner_pos() -> Vector2:
	return Vector2(owner_node.position.x, owner_node.position.z)


func place(p: Vector2) -> void:
	position = Vector3(p.x, ParkMap.walk_height(p), p.y)


func set_selected(on: bool) -> void:
	_ring.visible = on


## Fotograf ve dolap modunda isim etiketi ve halka gizlenir.
func set_chrome(on: bool) -> void:
	_tag.visible = on
	if not on:
		_ring.visible = false


## Aksesuarlari, ismi ve buyume evresini kayittan yeniden uygular.
func refresh() -> void:
	var p: Dictionary = state.pet(kind)
	_tag.text = p["name"]
	for n in _worn_nodes:
		n.queue_free()
	_worn_nodes.clear()
	var cfg: Dictionary = model._cfg
	for slot_name in p["worn"]:
		var id: String = p["worn"][slot_name]
		var sockets: Array = []
		match slot_name:
			"hat": sockets = [model.hat_socket]
			"face": sockets = [model.face_socket]
			"neck": sockets = [model.neck_socket]
			"back": sockets = [model.back_socket]
			"paws": sockets = model.paw_sockets
		for s in sockets:
			var acc: Node3D = Accessories.build(id, cfg["neck_r"], cfg["face_w"])
			s.add_child(acc)
			_worn_nodes.append(acc)
	_apply_stage()


func _apply_stage() -> void:
	var s: int = state.stage(kind)
	if s != _stage:
		_stage = s
		model.set_stage(s)
		var h: float = model.scale.y
		_tag.position.y = 0.95 * h + 0.25
		_zzz.position.y = 0.95 * h + 0.55
		_ring.scale = Vector3(h, 0.2, h)


func _move(target: Vector2, sp: float, dt: float) -> float:
	var p := pos2()
	var to := target - p
	var d := to.length()
	if d < 0.05:
		model.speed = 0.0
		return d
	if float(state.pet(kind)["energy"]) < 12.0:
		sp = minf(sp, 2.2)   # yorgunken yavaslar
	var np: Vector2 = world.resolve(p + to / d * minf(sp * dt, d), 0.3, p)
	var moved := np.distance_to(p) / maxf(dt, 0.0001)
	place(np)
	if moved > 0.2:
		var dir := np - p
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.y), minf(1.0, dt * 10.0))
	model.speed = moved
	_stuck = _stuck + dt if moved < sp * 0.3 else 0.0
	return np.distance_to(target)


func face(p: Vector2, dt: float) -> void:
	var dir := p - pos2()
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.y), minf(1.0, dt * 6.0))


func _free_point_near(c: Vector2, r: float) -> Vector2:
	for i in 10:
		var a := randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * randf_range(r * 0.35, r)
		if world.is_free(p, 0.3):
			return p
	return c


# ---------------------------------------------------------------- komutlar

func command(cmd: String) -> void:
	_drop_item()
	play_partner = null
	external = false
	stay_far = 22.0
	_zzz.visible = false
	match cmd:
		"sit":
			mode = Mode.STAY
			model.pose = "sit"
		"lie":
			mode = Mode.STAY
			model.pose = "lie"
		"come":
			mode = Mode.FOLLOW
			model.pose = "stand"
			model.hop(0.18, 0.3)
		"sleep":
			mode = Mode.SLEEP
			model.pose = "sleep"
			_zzz.visible = true


func fetch(item: Node3D, land: Vector2, flight: float) -> void:
	command("come")
	mode = Mode.FETCH
	_item = item
	_land = land
	_t = flight
	_air_catch = false
	_stuck = 0.0


func eat() -> void:
	command("come")
	mode = Mode.EAT
	model.pose = "eat"
	_t = 4.0


func wash(pool: Vector2) -> void:
	command("come")
	mode = Mode.WASH
	_land = pool
	_t = -1.0


func play_yarn(ball: Node3D) -> void:
	command("come")
	mode = Mode.YARN
	_item = ball
	_bats = 0
	_ball_vel = Vector2.ZERO


func play_with(other: Node3D) -> void:
	command("come")
	mode = Mode.PLAY
	play_partner = other
	_role = 1
	_t = 11.0
	_center = pos2()
	_has_wander = false
	if other.has_method("play_with") and other.mode != Mode.PLAY:
		other.command("come")
		other.mode = Mode.PLAY
		other.play_partner = self
		other._role = 0
		other._t = 11.0
		other._center = _center
		other._has_wander = false


func is_busy() -> bool:
	return mode != Mode.FOLLOW and mode != Mode.STAY


func _drop_item() -> void:
	if _item and is_instance_valid(_item) and _item.get_parent() == model.mouth:
		_item.reparent(world)
		_item.position = Vector3(position.x, ParkMap.walk_height(pos2()) + 0.13, position.z)
		_item.set_meta("held", false)
	_item = null


# ---------------------------------------------------------------- dongu

func _process(dt: float) -> void:
	var p: Dictionary = state.pet(kind)
	p["energy"] = maxf(float(p["energy"]) - model.speed * dt * 0.06, 0.0)
	model.excited = state.mood(kind) > 60.0 and owner_speed > 0.3
	model.look_at_point = null
	_apply_stage()
	var od := pos2().distance_to(owner_pos())
	if external:
		return
	match mode:
		Mode.FOLLOW: _follow(dt, od)
		Mode.STAY:
			model.speed = 0.0
			model.look_at_point = owner_node.position + Vector3(0, 1.2, 0)
			if od > stay_far:
				command("come")
		Mode.FETCH: _fetch(dt)
		Mode.RETURN: _return(dt, od)
		Mode.EAT:
			model.speed = 0.0
			_t -= dt
			if _t <= 0.0:
				command("come")
				model.happy_time = 2.0
				reward.emit(kind, "ate")
		Mode.SLEEP:
			model.speed = 0.0
			p["energy"] = minf(float(p["energy"]) + 9.0 * dt, 100.0)
			_zzz.position.x = sin(Time.get_ticks_msec() * 0.002) * 0.1
			if float(p["energy"]) >= 99.0 or od > 22.0:
				command("come")
				reward.emit(kind, "woke")
		Mode.PLAY: _play(dt)
		Mode.YARN: _yarn(dt)
		Mode.WASH: _wash(dt)


func _follow(dt: float, od: float) -> void:
	var desired := owner_pos() + slot.rotated(-owner_node.rotation.y)
	var d := pos2().distance_to(desired)
	if od > 30.0 or (_stuck > 1.6 and od > 5.0):
		place(_free_point_near(owner_pos(), 2.0))   # takilirsa sahibine yetisir
		_stuck = 0.0
		return
	if owner_speed > 0.3 or d > 3.0:
		idle_time = 0.0
		_has_wander = false
		model.pose = "stand"
		if d > 0.7:
			_move(desired, clampf(d * 1.9, 1.6, 6.2), dt)
		else:
			model.speed = 0.0
		return
	idle_time += dt
	if float(state.pet(kind)["energy"]) < 8.0 and idle_time > 2.0:
		command("sleep")
		reward.emit(kind, "tired")
		return
	if _has_wander:
		if _move(_wander, 1.4, dt) < 0.3 or _stuck > 1.0:
			_has_wander = false
			_stuck = 0.0
			model.pose = ["stand", "eat", "sit"][randi() % 3]
			_t = randf_range(2.0, 4.5)
		return
	model.speed = 0.0
	if model.pose != "eat":
		model.look_at_point = owner_node.position + Vector3(0, 1.2, 0)
	_t -= dt
	if _t > 0.0:
		return
	var r := randf()
	_t = randf_range(2.5, 5.0)
	if r < 0.4:
		_wander = _free_point_near(owner_pos(), 3.8)
		_has_wander = true
		model.pose = "stand"
	elif r < 0.62:
		model.pose = "sit"
	elif r < 0.74 and idle_time > 14.0:
		model.pose = "lie"
		_t = randf_range(5.0, 9.0)
	elif r < 0.9 and buddy and buddy.mode == Mode.FOLLOW and buddy.idle_time > 3.0 and idle_time > 5.0:
		play_with(buddy)
	else:
		model.pose = "stand"
		model.hop(0.2, 0.35)


func _fetch(dt: float) -> void:
	_t -= dt
	if is_instance_valid(_item) and _t <= 0.0:
		_land = Vector2(_item.global_position.x, _item.global_position.z)   # yere dustu: seken topu kovala
	var d := _move(_land, 6.4, dt)
	if _t > 0.0 and _t < 0.3 and d < 1.6 and not _air_catch:
		_air_catch = true
		model.hop(0.55, 0.5)
	if (_t <= 0.0 and d < 0.75) or (_air_catch and _t <= 0.06):
		_item.set_meta("held", true)
		_item.reparent(model.mouth, false)
		_item.position = Vector3.ZERO
		mode = Mode.RETURN
		_stuck = 0.0
	elif _stuck > 2.5:
		_item = null
		command("come")


func _return(dt: float, od: float) -> void:
	var o := owner_pos()
	_move(o + (pos2() - o).normalized() * 1.0, 5.2, dt)
	if od < 1.6:
		var front := o + Vector2(0, -0.6).rotated(-owner_node.rotation.y)
		_item.reparent(world)
		_item.position = Vector3(front.x, ParkMap.walk_height(front) + 0.13, front.y)
		_item.set_meta("held", false)
		_item = null
		mode = Mode.FOLLOW
		model.pose = "stand"
		model.happy_time = 2.5
		reward.emit(kind, "fetch_air" if _air_catch else "fetch")
	elif _stuck > 2.5:
		place(_free_point_near(o, 1.5))
		_stuck = 0.0


func _play(dt: float) -> void:
	_t -= dt
	if _t <= 0.0 or not is_instance_valid(play_partner):
		var was_first := _role == 1
		command("come")
		model.happy_time = 2.0
		if was_first:
			reward.emit(kind, "play")
		return
	var pp := Vector2(play_partner.position.x, play_partner.position.z)
	if _role == 1:
		# Kovalayan: arkadasinin icine girmez, ~0.9 m'de durur
		var chase := pp + (pos2() - pp).normalized() * 0.85
		if _move(chase, 5.4, dt) < 0.15 and not model.is_hopping():
			model.hop(0.3, 0.4)
			if play_partner.has_method("play_with"):
				_role = 0
				play_partner._role = 1
				_has_wander = false
	else:
		# Kacan
		if not _has_wander or _stuck > 0.8:
			_wander = _free_point_near(_center, 7.0)
			_has_wander = true
			_stuck = 0.0
		if _move(_wander, 4.8, dt) < 0.5:
			_has_wander = false


func _yarn(dt: float) -> void:
	if not is_instance_valid(_item):
		command("come")
		return
	# Yumak yuvarlanir
	var bp := Vector2(_item.position.x, _item.position.z)
	if _ball_vel.length() > 0.05:
		var np: Vector2 = world.resolve(bp + _ball_vel * dt, 0.15, bp)
		_item.position = Vector3(np.x, ParkMap.walk_height(np) + 0.12, np.y)
		_item.rotate_x(_ball_vel.length() * dt * 6.0)
		_ball_vel = _ball_vel.move_toward(Vector2.ZERO, dt * 2.6)
		bp = np
	var d := pos2().distance_to(bp)
	if d > 0.55:
		_move(bp, 2.6 if _ball_vel.length() > 0.5 else 4.2, dt)
	elif not model.is_hopping() and _ball_vel.length() < 0.6:
		model.speed = 0.0
		_bats += 1
		if _bats > 6:
			command("come")
			model.happy_time = 2.0
			reward.emit(kind, "yarn")
			return
		model.hop(0.28, 0.4)
		var a := randf() * TAU
		_ball_vel = Vector2(cos(a), sin(a)) * randf_range(2.6, 3.8)


func _wash(dt: float) -> void:
	if _t < 0.0:
		# Havuza kos
		if _move(_land, 4.5, dt) < 2.3 or _stuck > 1.5:
			model.hop(0.5, 0.5)
			position = Vector3(_land.x, ParkMap.walk_height(_land) + 0.2, _land.y)
			model.speed = 0.0
			model.pose = "sit"
			_t = 4.0
			reward.emit(kind, "splash")
		return
	_t -= dt
	rotation.y += dt * 1.5
	if _t <= 0.0:
		place(_land + Vector2(0, 2.4))
		state.pet(kind)["clean"] = 100.0
		command("come")
		model.hop(0.3, 0.4)
		model.happy_time = 2.5
		reward.emit(kind, "wash")
