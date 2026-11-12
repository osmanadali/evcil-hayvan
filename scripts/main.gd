extends Node3D
## Oyunun girisi: dunyayi, sahibi, evcil hayvanlari, NPC'leri ve arayuzu kurar; girdiyi ve kamerayi yonetir.

const ParkMap = preload("res://scripts/park_map.gd")
const Kit = preload("res://scripts/kit.gd")
const World = preload("res://scripts/world.gd")
const GameState = preload("res://scripts/game_state.gd")
const PetModel = preload("res://scripts/pet_model.gd")
const PetAgent = preload("res://scripts/pet_agent.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const Npc = preload("res://scripts/npc.gd")
const Ui = preload("res://scripts/ui.gd")
const MapScreen = preload("res://scripts/map_screen.gd")
const Accessories = preload("res://scripts/accessories.gd")

const WALK_SPEED := 3.6
const CAM_OFFSET := Vector3(0, 10.5, 9.6)
const POOL := Vector2(6.0, -51.0)
const KENNEL := Vector2(-7.2, -46.2)

var state: Node
var world: Node3D
var ui: CanvasLayer
var map_screen: Control
var env: Environment
var cam: Camera3D
var owner_node: Node3D
var owner_model: Node3D
var agents := {}

var _mode := "menu"   # menu, play, photo, closet
var _aim := false
var _target := Vector2.ZERO
var _moving := false
var _dragging := false
var _stuck := 0.0
var _queue: Array[Vector2] = []
var _touches := {}
var _focus := Vector3.ZERO
var _zoom := 1.0
var _menu_angle := 0.6
var _photo := {"yaw": 0.5, "pitch": 0.22, "dist": 4.2}
var _marker: MeshInstance3D
var _ball: Node3D
var _thrown: Node3D
var _fly_from := Vector3.ZERO
var _fly_to := Vector3.ZERO
var _fly_t := 1.0
var _fly_d := 1.0
var _fly_delay := 0.0
var _yarn: Node3D
var _bowl: Node3D
var _bowl_t := 0.0
var _food_pending := {}
var _coins: Array[Node3D] = []
var _fx: Array = []
var _npc_pets: Array[Node3D] = []
var _near_npc: Node3D
var _pet_cd := 0.0
var _slow_t := 0.0
var _save_t := 0.0
var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"

	state = GameState.new()
	add_child(state)
	if _args.has("shot"):
		state.reset()
	_build_environment()
	world = World.new()
	add_child(world)

	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 500.0
	add_child(cam)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.28
	ring.outer_radius = 0.38
	_marker = Kit.add(self, ring, Kit.glow("ffffff", 0.8))
	_marker.scale.y = 0.25
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	_ball = _make_ball("c8452f", 0.13)
	_ball.visible = false
	_yarn = _make_ball("d95f76", 0.12)
	_yarn.visible = false

	_spawn_cast()
	_spawn_npcs()
	_spawn_coins()

	ui = Ui.new()
	ui.state = state
	add_child(ui)
	map_screen = MapScreen.new()
	ui.add_child(map_screen)
	map_screen.place_chosen.connect(walk_to)
	ui.command.connect(_on_command)
	ui.select_pet.connect(_select_pet)
	ui.start_game.connect(_start_game)
	ui.continue_game.connect(_enter_play)
	ui.open_map.connect(func(): map_screen.open(_owner_pos()))
	ui.photo.connect(_on_photo)
	ui.closet_toggled.connect(_on_closet)
	ui.worn_changed.connect(func(): agents[state.d["active"]].refresh())
	ui.adopted.connect(_on_adopted)
	ui.back_to_menu.connect(func():
		state.save_game()
		_mode = "menu"
		ui.show_screen("menu"))
	get_tree().set_auto_accept_quit(false)
	if _args.has("shot"):
		_debug_shot()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		state.save_game()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state:
			state.save_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and _mode == "play":
		ui.open_pause()


func _build_environment() -> void:
	env = Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.48, 0.85)
	sky_mat.sky_horizon_color = Color(0.74, 0.85, 0.94)
	sky_mat.ground_bottom_color = Color(0.4, 0.55, 0.42)
	sky_mat.ground_horizon_color = Color(0.74, 0.85, 0.94)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.82, 0.9)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	sun.look_at_from_position(Vector3(6.5, 8.0, 3.5), Vector3.ZERO)


func _make_ball(hex: String, r: float) -> Node3D:
	var n := Node3D.new()
	Kit.ball(n, r, Vector3.ZERO, Kit.mat(hex, 0.6))
	if hex == "d95f76":
		Kit.torus(n, r * 0.85, r * 1.02, Vector3.ZERO, Kit.mat("b84a62"), Vector3(0.6, 0.3, 0))
		Kit.torus(n, r * 0.85, r * 1.02, Vector3.ZERO, Kit.mat("b84a62"), Vector3(-0.5, 1.2, 0.4))
	world.add_child(n)
	return n


# ---------------------------------------------------------------- karakterler

func _owner_pos() -> Vector2:
	return Vector2(owner_node.position.x, owner_node.position.z)


func _place_owner(p: Vector2) -> void:
	owner_node.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
	_target = p


func _spawn_cast() -> void:
	if owner_node:
		owner_node.free()
	for k in agents:
		agents[k].free()
	agents.clear()
	owner_node = Node3D.new()
	add_child(owner_node)
	owner_model = PersonModel.new()
	owner_model.kind = state.d["owner"]
	owner_node.add_child(owner_model)
	_place_owner(Vector2(0.6, -24.5))
	owner_node.rotation.y = PI
	var pets: Array = state.owned_pets()
	if pets.is_empty():
		pets = ["kopek"]   # menude arka plan icin
	for kind in pets:
		_add_agent(kind)
	_link_buddies()
	_focus = owner_node.position


func _add_agent(kind: String) -> void:
	var a := PetAgent.new()
	a.kind = kind
	a.state = state
	a.world = world
	a.owner_node = owner_node
	a.slot = Vector2(1.1, 0.4) if kind == "kopek" else Vector2(-1.0, 0.7)
	a.reward.connect(_on_reward)
	add_child(a)
	a.place(_owner_pos() + a.slot)
	agents[kind] = a


func _link_buddies() -> void:
	for k in agents:
		agents[k].buddy = null
		for o in agents:
			if o != k:
				agents[k].buddy = agents[o]
		agents[k].set_selected(_mode != "menu" and k == state.d["active"] and agents.size() > 1)


func _active() -> Node3D:
	if not agents.has(state.d["active"]):
		state.d["active"] = agents.keys()[0]
	return agents[state.d["active"]]


func _select_pet(kind: String) -> void:
	if agents.has(kind):
		state.d["active"] = kind
		_link_buddies()
		ui.refresh()


func _on_adopted(kind: String) -> void:
	_add_agent(kind)
	_link_buddies()
	agents[kind].model.happy_time = 3.0
	_hearts(agents[kind].position)


func _start_game(owner_kind: String, pet_kind: String, pet_name: String) -> void:
	state.reset()
	state.d["owner"] = owner_kind
	state.d["started"] = true
	state.d["active"] = pet_kind
	state.pet(pet_kind)["owned"] = true
	state.pet(pet_kind)["name"] = pet_name
	if pet_kind == "kedi":
		state.pet("kedi")["worn"] = {"neck": "tasma_kirmizi"}
		state.pet("kopek")["worn"] = {}
	state.save_game()
	_spawn_cast()
	for c in _coins:
		c.queue_free()
	_coins.clear()
	_spawn_coins()
	_enter_play()
	ui.toast("Hoş geldin! Yürümek için bir yere dokun.")


func _enter_play() -> void:
	if not state.d["started"]:
		ui.show_screen("setup")
		return
	_mode = "play"
	_link_buddies()
	ui.show_screen("hud")


func _spawn_npcs() -> void:
	# Yuruyen insanlar (bazilarinin yaninda hayvani var)
	var people := [
		["kadin", "ffe6e0", ["kopek", "f4f4f4", 0.8], [Vector2(0, -25.5), Vector2(0.8, -20), Vector2(-0.8, -12), Vector2(0, -7.3),
			Vector2(5.2, -5.2), Vector2(7.2, 0), Vector2(15, -1), Vector2(26, -5), Vector2(42, -8), Vector2(58, -11), Vector2(73, -15), Vector2(78, -10)]],
		["erkek", "e6f0ff", [], [Vector2(-40, -6.5), Vector2(-39, -1), Vector2(-36, 5), Vector2(-31, 7), Vector2(-25, 7), Vector2(-21, 5),
			Vector2(-14, 1), Vector2(-7.4, 0), Vector2(-5.2, 5.2), Vector2(0, 7.3), Vector2(-1, 14), Vector2(2, 21),
			Vector2(9, 24), Vector2(13, 29), Vector2(11, 35), Vector2(8, 33.6)]],
		["kadin", "e8ffe6", ["kedi", "c9c9c9", 0.9], [Vector2(18, -14.5), Vector2(12, -11), Vector2(5.2, -5.4), Vector2(0, -7.4),
			Vector2(-5.2, -5.4), Vector2(-10, -13), Vector2(-14.2, -18.2)]],
		["erkek", "fff0d6", ["kopek", "b08a66", 1.1], [Vector2(-50, -59), Vector2(-20, -59), Vector2(4, -59), Vector2(30, -59), Vector2(59.5, -59),
			Vector2(60, -40), Vector2(60, -14)]],
		["kadin", "f0e6ff", [], [Vector2(78, -8), Vector2(90, -10), Vector2(92, -22), Vector2(80, -26), Vector2(74, -18), Vector2(78, -8)]],
		["erkek", "ffffff", ["kopek", "5a5a5a", 0.9], [Vector2(-20, 60), Vector2(-17, 54), Vector2(-12, 44), Vector2(-6, 30), Vector2(2, 21), Vector2(9, 24),
			Vector2(13, 29), Vector2(26, 33), Vector2(42, 38), Vector2(58, 40)]],
	]
	for d in people:
		var n := Npc.new()
		var v := PersonModel.new()
		v.kind = d[0]
		v.tint = Color(d[1])
		n.visual = v
		n.route = d[3]
		n.add_child(v)
		add_child(n)
		var pet_def: Array = d[2]
		if pet_def.size() > 0:
			var np := _npc_pet(pet_def[0], Color(pet_def[1]), pet_def[2])
			np.follow = n
			np.place(n.route[0] + Vector2(0.8, 0.5))
	# Kendi basina gezen hayvanlar
	var free := [
		["kopek", "4a4038", 1.0, Vector2(32, 8.5), 3.5, 2.2], ["kopek", "ffe0b0", 0.75, Vector2(33.5, 7), 3.5, 2.6],
		["kopek", "ffffff", 0.9, ParkMap.MEADOW, 6.5, 1.8], ["kedi", "ffffff", 1.0, ParkMap.PICNIC + Vector2(2.5, 1.5), 3.0, 1.2],
		["kedi", "8a8a8a", 0.95, ParkMap.SQUARE + Vector2(-4, 8), 5.0, 3.4], ["kedi", "d8c8b0", 1.05, ParkMap.BEACH + Vector2(6, -4), 5.0, 1.6],
		["kopek", "c9a070", 1.05, ParkMap.ORCHARD + Vector2(0, -16), 5.0, 2.0], ["kedi", "5f5048", 1.0, Vector2(-30, -62), 4.0, 1.4],
	]
	var last: Node3D
	for f in free:
		var np := _npc_pet(f[0], Color(f[1]), f[2])
		np.roam_center = f[3]
		np.roam_radius = f[4]
		np.walk_speed = f[5]
		np.place(f[3])
		last = np
	# Kovalamaca oynayan kediler (biri kacar, digeri kovalar)
	for c in [ParkMap.SQUARE + Vector2(-4, 8), ParkMap.GARDEN + Vector2(-9, 6)]:
		var runner := _npc_pet("kedi", Color("f2e2c4"), 0.9)
		runner.roam_center = c
		runner.roam_radius = 6.0
		runner.walk_speed = 3.6
		runner.short_pause = true
		runner.place(c)
		var chaser := _npc_pet("kedi", Color("707070"), 0.95)
		chaser.follow = runner
		chaser.place(c + Vector2(1.5, 1.0))


func _npc_pet(kind: String, tint: Color, size: float) -> Node3D:
	var n := Npc.new()
	var v := PetModel.new()
	v.kind = kind
	v.tint = tint
	v.size_mul = size
	n.visual = v
	n.add_child(v)
	add_child(n)
	_npc_pets.append(n)
	return n


func _spawn_coins() -> void:
	var lines: Array = []
	for path in ParkMap.PATHS:
		lines.append(path["pts"])
	for r in ParkMap.ROADS:
		var off: Array = []
		for pt in r:
			off.append(pt + (Vector2(0, 4.2) if r[0].y == r[1].y else Vector2(-4.2, 0)))
		lines.append(off)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var id := 0
	var gold := Kit.mat("e9b93a", 0.25)
	for line in lines:
		for i in line.size() - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var n := int(a.distance_to(b) / 13.0)
			for k in n:
				id += 1
				var p := a.lerp(b, (k + 0.5) / n) + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
				if state.d["found"].has(id) or ParkMap.water_blocked(p):
					continue
				var c := Node3D.new()
				c.position = Vector3(p.x, ParkMap.walk_height(p) + 0.55, p.y)
				c.set_meta("id", id)
				Kit.cyl(c, 0.2, 0.2, 0.05, Vector3.ZERO, gold, 14, Vector3(PI / 2, 0, 0))
				add_child(c)
				_coins.append(c)


# ---------------------------------------------------------------- girdi

func _unhandled_input(e: InputEvent) -> void:
	if _mode == "menu" or ui.is_blocking() or map_screen.visible:
		return
	var touch := DisplayServer.is_touchscreen_available()
	if e is InputEventScreenTouch and touch:
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_pointer_down(e.position)
			else:
				_dragging = false
		else:
			_touches.erase(e.index)
			if _touches.is_empty():
				_dragging = false
	elif e is InputEventScreenDrag and touch:
		if _touches.size() >= 2 and _touches.has(e.index):
			var other: Vector2 = e.position
			for k in _touches:
				if k != e.index:
					other = _touches[k]
			_zoom_by(maxf(other.distance_to(_touches[e.index]), 1.0) / maxf(other.distance_to(e.position), 1.0))
		elif _dragging:
			_pointer_move(e.position, e.relative)
		_touches[e.index] = e.position
	elif e is InputEventMouseButton and not touch:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_pointer_down(e.position)
			else:
				_dragging = false
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(0.92)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.08)
	elif e is InputEventMouseMotion and not touch and _dragging:
		_pointer_move(e.position, e.relative)


func _zoom_by(f: float) -> void:
	if _mode == "photo":
		_photo["dist"] = clampf(_photo["dist"] * f, 1.8, 12.0)
	else:
		_zoom = clampf(_zoom * f, 0.5, 1.6)


func _pointer_down(pos: Vector2) -> void:
	_dragging = true
	if _mode == "photo":
		return
	if _mode == "closet":
		return
	var hit = _ground_hit(pos)
	if _aim:
		_aim = false
		_dragging = false
		if hit != null:
			_throw_to(hit)
		return
	# Hayvana dokunma: sec ve sev
	for k in agents:
		var a: Node3D = agents[k]
		if cam.unproject_position(a.position + Vector3(0, 0.35, 0)).distance_to(pos) < 64.0:
			_dragging = false
			_select_pet(k)
			_do_pet()
			return
	if hit != null:
		_queue.clear()
		_go(hit)


func _pointer_move(pos: Vector2, rel: Vector2) -> void:
	if _mode == "photo":
		_photo["yaw"] -= rel.x * 0.008
		_photo["pitch"] = clampf(_photo["pitch"] + rel.y * 0.006, 0.03, 1.2)
	elif _mode == "play":
		var hit = _ground_hit(pos)
		if hit != null:
			_queue.clear()
			_go(hit)


## Ekrandaki noktanin araziyle kesisimi (Vector2) ya da null.
func _ground_hit(screen: Vector2):
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var t := 0.0
	var prev := 0.0
	while t < 150.0:
		var p := o + d * t
		if p.y < ParkMap.walk_height(Vector2(p.x, p.z)):
			break
		prev = t
		t += 0.5
	if t >= 150.0:
		return null
	for i in 6:
		var mid := (prev + t) * 0.5
		var p := o + d * mid
		if p.y < ParkMap.walk_height(Vector2(p.x, p.z)):
			t = mid
		else:
			prev = mid
	var hit := o + d * t
	return Vector2(hit.x, hit.z)


## Haritadan secilen yere yollari izleyerek yuru.
func walk_to(p: Vector2) -> void:
	_queue = ParkMap.find_route(_owner_pos(), p)
	_go(_queue.pop_front())


func _go(p: Vector2) -> void:
	_target = p
	_moving = true
	_stuck = 0.0
	_marker.position = Vector3(p.x, ParkMap.walk_height(p) + 0.06, p.y)
	_marker.visible = _queue.is_empty()


# ---------------------------------------------------------------- komutlar

func _on_command(cmd: String) -> void:
	var a := _active()
	var p: Dictionary = state.pet(a.kind)
	if cmd.begins_with("feed:"):
		_do_feed(cmd.trim_prefix("feed:"))
		return
	match cmd:
		"pet":
			_do_pet()
		"throw":
			_aim = true
			ui.toast("Nereye atayım? Bir yere dokun.")
		"yarn":
			_do_yarn()
		"come":
			for k in agents:
				agents[k].command("come")
			owner_model.act("wave", 0.9)
		"sit", "lie":
			a.command(cmd)
			state.add_xp(a.kind, 0.5)
		"sleep":
			a.command("sleep")
			ui.toast("%s uyuyor…" % p["name"])
		"play":
			if agents.size() > 1:
				a.play_with(a.buddy)
				ui.toast("Kovalamaca başladı!")
		"wash":
			a.wash(POOL)
		"bed":
			a.place(KENNEL + Vector2(1.0, 1.6))
			a.command("sleep")
			ui.toast("%s kulübesinde uyuyor…" % p["name"])
		"shop":
			ui.open_shop()
		"icecream":
			if state.spend(10):
				owner_model.act("wave", 1.2)
				for k in agents:
					state.add_need(k, "fun", 22.0)
					agents[k].model.happy_time = 2.5
					_hearts(agents[k].position)
				ui.toast("Dondurma molası! Herkes çok mutlu.")
		"npcplay":
			if _near_npc:
				a.play_with(_near_npc)
				ui.toast("%s yeni arkadaşıyla oynuyor!" % p["name"])


func _face_owner(p: Vector2) -> void:
	var dir := p - _owner_pos()
	if dir.length() > 0.1:
		owner_node.rotation.y = atan2(-dir.x, -dir.y)


func _do_pet() -> void:
	var a := _active()
	if a.pos2().distance_to(_owner_pos()) > 2.6:
		a.command("come")
		ui.toast("%s geliyor…" % state.pet(a.kind)["name"])
		return
	_moving = false
	_face_owner(a.pos2())
	owner_model.act("pet", 1.3)
	a.model.happy_time = 1.6
	_hearts(a.position)
	if _pet_cd <= 0.0:
		_pet_cd = 1.2
		state.add_need(a.kind, "fun", 7.0)
		state.add_xp(a.kind, 1.5)
		state.count("pet")


func _do_feed(id: String) -> void:
	var a := _active()
	if int(state.d["foods"].get(id, 0)) <= 0 or a.is_busy():
		return
	if a.pos2().distance_to(_owner_pos()) > 3.0:
		a.command("come")
		ui.toast("Önce %s yanına gelsin." % state.pet(a.kind)["name"])
		return
	state.d["foods"][id] -= 1
	_food_pending[a.kind] = id
	_moving = false
	_face_owner(a.pos2())
	owner_model.act("feed", 1.4)
	if not _bowl:
		_bowl = Node3D.new()
		Kit.cyl(_bowl, 0.2, 0.25, 0.11, Vector3(0, 0.055, 0), Kit.mat("b8433a", 0.4))
		Kit.cyl(_bowl, 0.17, 0.17, 0.02, Vector3(0, 0.11, 0), Kit.mat("8a5a35", 0.6))
		add_child(_bowl)
	var front: Vector2 = a.pos2() + Vector2(0, -0.45 * a.model.scale.x).rotated(-a.rotation.y)
	_bowl.position = Vector3(front.x, ParkMap.walk_height(front), front.y)
	_bowl.visible = true
	_bowl_t = 4.3
	a.eat()


func _throw_to(hit: Vector2) -> void:
	var a := _active()
	if a.kind == "kedi" and agents.has("kopek"):
		a = agents["kopek"]
	var o := _owner_pos()
	var dir := hit - o
	var land := o + dir.normalized() * clampf(dir.length(), 4.0, 16.0)
	if not world.is_free(land, 0.3):
		ui.toast("Oraya atamam, başka bir yer seç.")
		return
	# Yakinda bir oyuncak varsa onu at, yoksa topu
	_thrown = _ball
	for t in world.toys:
		if not t.get_meta("held", false) and Vector2(t.position.x, t.position.z).distance_to(o) < 2.5:
			_thrown = t
	_moving = false
	_face_owner(land)
	owner_model.act("throw", 0.8)
	_thrown.visible = true
	_thrown.set_meta("held", false)
	_fly_from = owner_node.position + Vector3(0, 1.5, 0)
	_fly_to = Vector3(land.x, ParkMap.walk_height(land) + 0.13, land.y)
	_fly_d = 0.55 + o.distance_to(land) * 0.06
	_fly_t = 0.0
	_fly_delay = 0.3
	_thrown.position = _fly_from
	a.fetch(_thrown, land, _fly_d + _fly_delay)


func _do_yarn() -> void:
	if not agents.has("kedi"):
		return
	var o := _owner_pos()
	var front := o + Vector2(0, -1.6).rotated(-owner_node.rotation.y)
	if not world.is_free(front, 0.2):
		front = o
	owner_model.act("throw", 0.8)
	_yarn.visible = true
	_yarn.position = Vector3(front.x, ParkMap.walk_height(front) + 0.12, front.y)
	agents["kedi"].play_yarn(_yarn)


func _on_reward(kind: String, what: String) -> void:
	var pet_name: String = state.pet(kind)["name"]
	match what:
		"fetch", "fetch_air":
			state.add_need(kind, "fun", 18.0)
			state.add_xp(kind, 4.0)
			state.add_coins(5 if what == "fetch_air" else 3)
			state.count("fetch")
			_hearts(agents[kind].position)
			if what == "fetch_air":
				ui.toast("%s havada yakaladı! +5 altın" % pet_name)
		"play":
			for k in agents:
				state.add_need(k, "fun", 25.0)
				state.add_xp(k, 3.0)
			state.count("fetch")
		"yarn":
			state.add_need(kind, "fun", 28.0)
			state.add_xp(kind, 4.0)
			state.count("fetch")
			_yarn.visible = false
			_hearts(agents[kind].position)
		"ate":
			var f: Array = state.FOODS[_food_pending.get(kind, "mama")]
			state.add_need(kind, "hunger", f[2])
			state.add_need(kind, "fun", f[3])
			state.add_xp(kind, 2.0)
			state.count("feed")
		"splash":
			_bubbles(agents[kind].position)
		"wash":
			state.add_xp(kind, 3.0)
			ui.toast("%s mis gibi oldu!" % pet_name)
		"woke":
			ui.toast("%s dinlendi." % pet_name)
		"tired":
			ui.toast("%s çok yoruldu, biraz uyuyor." % pet_name)


# ---------------------------------------------------------------- efektler

func _hearts(at_pos: Vector3) -> void:
	var m := Kit.glow("f0708c", 0.7)
	for i in 5:
		var h := Node3D.new()
		Kit.ball(h, 0.07, Vector3(-0.05, 0.03, 0), m, Vector3.ONE, 8)
		Kit.ball(h, 0.07, Vector3(0.05, 0.03, 0), m, Vector3.ONE, 8)
		Kit.cyl(h, 0.115, 0.005, 0.14, Vector3(0, -0.06, 0), m, 8)
		h.position = at_pos + Vector3(randf_range(-0.3, 0.3), 0.7, randf_range(-0.3, 0.3))
		add_child(h)
		_fx.append({"n": h, "v": Vector3(randf_range(-0.3, 0.3), randf_range(0.9, 1.5), randf_range(-0.3, 0.3)), "t": randf_range(0.9, 1.4), "face": true})


func _bubbles(at_pos: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.1
	for i in 16:
		var b := Node3D.new()
		Kit.ball(b, randf_range(0.05, 0.13), Vector3.ZERO, m, Vector3.ONE, 8)
		b.position = at_pos + Vector3(randf_range(-0.8, 0.8), 0.4, randf_range(-0.8, 0.8))
		add_child(b)
		_fx.append({"n": b, "v": Vector3(randf_range(-0.2, 0.2), randf_range(0.3, 0.8), randf_range(-0.2, 0.2)), "t": randf_range(1.5, 4.0), "face": false})


func _sparkle(at_pos: Vector3) -> void:
	var m := Kit.glow("ffe27a", 1.5)
	for i in 6:
		var s := Node3D.new()
		Kit.ball(s, 0.05, Vector3.ZERO, m, Vector3.ONE, 6)
		s.position = at_pos
		add_child(s)
		var a := i * TAU / 6.0
		_fx.append({"n": s, "v": Vector3(cos(a) * 1.4, 1.6, sin(a) * 1.4), "t": 0.5, "face": false})


# ---------------------------------------------------------------- dongu

func _process(dt: float) -> void:
	_pet_cd -= dt
	_update_owner(dt)
	for k in agents:
		agents[k].owner_speed = owner_model.speed
	_update_thrown(dt)
	if _bowl and _bowl.visible:
		_bowl_t -= dt
		_bowl.visible = _bowl_t > 0.0
	_marker.rotation.y += dt * 2.0
	if not _moving:
		_marker.visible = false

	# Efektler
	for i in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[i]
		f["t"] -= dt
		var n: Node3D = f["n"]
		n.position += f["v"] * dt
		n.scale = Vector3.ONE * clampf(f["t"] * 2.0, 0.0, 1.0)
		if f["face"]:
			n.rotation.y = cam.rotation.y
		if f["t"] <= 0.0:
			n.queue_free()
			_fx.remove_at(i)

	# Altinlar
	var op := owner_node.position
	for i in range(_coins.size() - 1, -1, -1):
		var c := _coins[i]
		if absf(c.position.x - op.x) > 30.0:
			continue
		c.rotation.y += dt * 3.0
		if _mode == "play" and c.position.distance_to(op + Vector3(0, 0.6, 0)) < 1.3:
			state.d["found"].append(c.get_meta("id"))
			state.add_coins(2)
			state.count("coin")
			_sparkle(c.position)
			c.queue_free()
			_coins.remove_at(i)

	if _mode == "play" or _mode == "closet" or _mode == "photo":
		state.tick(dt)
		_slow_t -= dt
		if _slow_t <= 0.0:
			_slow_t = 0.3
			state.visit(_owner_pos())
			_update_context()
		_save_t += dt
		if _save_t > 20.0:
			_save_t = 0.0
			state.save_game()
	_update_camera(dt)


func _update_owner(dt: float) -> void:
	var p := _owner_pos()
	var to := _target - p
	var d := to.length()
	if _mode != "play":
		_moving = false
	if _moving and d < 1.0 and not _queue.is_empty():
		_go(_queue.pop_front())
	elif _moving and d > 0.15:
		var sp := minf(WALK_SPEED, 1.0 + d * 2.5)
		var np: Vector2 = world.resolve(p + to / d * minf(sp * dt, d), 0.35, p)
		var moved := np.distance_to(p) / maxf(dt, 0.0001)
		owner_node.position = Vector3(np.x, ParkMap.walk_height(np), np.y)
		if moved > 0.2:
			var dir := np - p
			owner_node.rotation.y = lerp_angle(owner_node.rotation.y, atan2(-dir.x, -dir.y), minf(1.0, dt * 9.0))
		owner_model.speed = moved
		state.count("walk", np.distance_to(p))
		_stuck = _stuck + dt if moved < sp * 0.25 else 0.0
		if _stuck > 0.6 and not _dragging:
			_moving = false
	else:
		_moving = false
		owner_model.speed = 0.0


func _update_thrown(dt: float) -> void:
	if _fly_t >= 1.0 or not _thrown:
		return
	if _fly_delay > 0.0:
		_fly_delay -= dt
		_thrown.global_position = owner_model.hand.global_position
		_fly_from = _thrown.global_position
		return
	if _thrown.get_meta("held", false):
		_fly_t = 1.0
		return
	_fly_t = minf(_fly_t + dt / _fly_d, 1.0)
	_thrown.position = _fly_from.lerp(_fly_to, _fly_t) + Vector3(0, sin(_fly_t * PI) * (1.5 + _fly_d * 1.6), 0)
	_thrown.rotate_x(dt * 9.0)


func _update_context() -> void:
	if _mode != "play":
		ui.set_context("", "")
		return
	var o := _owner_pos()
	var a := _active()
	_near_npc = null
	for n in _npc_pets:
		if Vector2(n.position.x, n.position.z).distance_to(o) < 4.5:
			_near_npc = n
	if o.distance_to(ParkMap.PETSHOP + Vector2(0, 7.0)) < 4.5:
		ui.set_context("Pet Shop'a Gir", "shop", "cart")
	elif o.distance_to(ParkMap.KIOSK + Vector2(0, 2.5)) < 3.6:
		ui.set_context("Dondurma Al  (10)", "icecream", "star")
	elif o.distance_to(POOL) < 4.2 and not a.is_busy():
		ui.set_context("Havuzda Yıka", "wash", "drop")
	elif o.distance_to(KENNEL) < 3.8 and not a.is_busy():
		ui.set_context("Kulübede Uyut", "bed", "moon")
	elif _near_npc and not a.is_busy():
		ui.set_context("Arkadaşıyla Oynat", "npcplay", "play")
	else:
		ui.set_context("", "")


func _update_camera(dt: float) -> void:
	var k := minf(1.0, dt * 5.0)
	match _mode:
		"menu":
			_menu_angle += dt * 0.06
			var c := Vector3(0, 1.5, -31)
			_focus = _focus.lerp(c, k)
			cam.position = c + Vector3(sin(_menu_angle) * 17.0, 7.5, cos(_menu_angle) * 17.0)
			cam.look_at(c)
		"photo":
			var a := _active()
			_focus = _focus.lerp(a.position + Vector3(0, 0.35 * a.model.scale.y + 0.1, 0), k)
			var yaw: float = _photo["yaw"]
			var pitch: float = _photo["pitch"]
			var dist: float = _photo["dist"]
			var pos := _focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
			pos.y = maxf(pos.y, ParkMap.walk_height(Vector2(pos.x, pos.z)) + 0.25)
			cam.position = pos
			cam.look_at(_focus)
		"debug":
			pass
		"closet":
			var a := _active()
			_focus = _focus.lerp(a.position + Vector3(0, -0.7, 0), k)
			cam.position = _focus + Vector3(0.6, 3.0, 3.6)
			cam.look_at(_focus)
		_:
			_focus = _focus.lerp(owner_node.position, k)
			cam.position = _focus + CAM_OFFSET * _zoom
			cam.look_at(_focus + Vector3(0, 0.9, 0))


# ---------------------------------------------------------------- fotograf ve dolap

func _hold(a: Node3D, pose: String) -> void:
	a.command("sit")
	a.model.pose = pose


func _set_chrome(on: bool) -> void:
	for k in agents:
		agents[k].set_chrome(on)
	if on:
		_link_buddies()


func _on_closet(open: bool) -> void:
	_set_chrome(not open)
	if open and _mode == "play":
		_mode = "closet"
		_moving = false
		_hold(_active(), "stand")
		_active().face(Vector2(cam.position.x, cam.position.z + 20.0), 10.0)
	elif not open and _mode == "closet":
		_mode = "play"
		_active().command("come")


func _on_photo(action: String) -> void:
	var a := _active()
	if action == "enter":
		_set_chrome(false)
		_mode = "photo"
		_moving = false
		_hold(a, "stand")
		_photo["yaw"] = a.rotation.y + PI + 0.5
		ui.show_screen("photo")
	elif action == "exit":
		_mode = "play"
		_set_chrome(true)
		a.command("come")
		ui.show_screen("hud")
	elif action == "take":
		_take_photo()
	elif action.begins_with("pose:"):
		var pose := action.trim_prefix("pose:")
		if pose == "hop":
			a.model.hop(0.4, 0.5)
		elif pose == "look":
			var dir: Vector2 = Vector2(cam.position.x, cam.position.z) - a.pos2()
			a.rotation.y = atan2(-dir.x, -dir.y)
		else:
			_hold(a, pose)


func _take_photo() -> void:
	ui.set_photo_chrome(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	ui.set_photo_chrome(true)
	ui.flash()
	var file := "foto_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	DirAccess.make_dir_recursive_absolute("user://fotolar")
	img.save_png("user://fotolar/" + file)
	# Telefonda galeride gorunsun diye resimler klasorune de yazmayi dene
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics != "" and DirAccess.make_dir_recursive_absolute(pics + "/PatiliGezinti") == OK:
		img.save_png(pics + "/PatiliGezinti/" + file)
	state.count("photo")
	ui.toast("Fotoğraf kaydedildi")


# ---------------------------------------------------------------- gelistirme

## Ekran goruntusu: -- --shot=dosya.png [--screen=menu|setup|play|shop|acc|pets|quests|closet|map|photo|pause]
## [--view=top|wide|low] [--at=x,z] [--both] [--level=n] [--wear=id,id] [--cmd=sit] [--pet=kedi] [--frames=n]
func _debug_shot() -> void:
	var screen: String = _args.get("screen", "play")
	var pet_kind: String = _args.get("pet", "kopek")
	if screen != "menu" and screen != "setup":
		state.d["started"] = true
		state.d["owner"] = _args.get("owner", "kadin")
		state.d["active"] = pet_kind
		state.pet(pet_kind)["owned"] = true
		if _args.has("both"):
			state.pet("kopek")["owned"] = true
			state.pet("kedi")["owned"] = true
		if _args.has("level"):
			for k in ["kopek", "kedi"]:
				state.pet(k)["xp"] = 12.0 * pow(float(_args["level"]) - 1.0, 2.0) + 1.0
		if _args.has("wear"):
			for id in _args["wear"].split(","):
				state.d["owned"].append(id)
				state.pet(pet_kind)["worn"][Accessories.ITEMS[id][1]] = id
		state.d["coins"] = int(_args.get("coins", "120"))
		_spawn_cast()
		_enter_play()
	elif screen == "setup":
		ui.show_screen("setup")
	if _args.has("at"):
		var xy: PackedStringArray = _args["at"].split(",")
		_place_owner(Vector2(float(xy[0]), float(xy[1])))
		for k in agents:
			agents[k].place(_owner_pos() + agents[k].slot)
		_focus = owner_node.position
	var view: String = _args.get("view", "")
	if view != "":
		ui.visible = false
	var frames := int(_args.get("frames", "40"))
	for i in frames:
		await get_tree().process_frame
		if i == 8:
			match screen:
				"shop": ui.open_shop("food")
				"acc": ui.open_shop("acc")
				"pets": ui.open_shop("pets")
				"quests": ui.open_quests()
				"closet": ui.open_closet()
				"pause": ui.open_pause()
				"map": map_screen.open(_owner_pos())
				"photo": _on_photo("enter")
			if _args.has("cmd"):
				var c: String = _args["cmd"]
				if c == "throw":
					_throw_to(_owner_pos() + Vector2(2, -9))
				elif c == "walk":
					_go(_owner_pos() + Vector2(float(_args.get("dx", "0")), float(_args.get("dz", "-30"))))
				elif c == "pin":
					map_screen.select_by_name(_args.get("pin", "Pet Shop"))
				else:
					_on_command(c)
		if view == "top":
			set_process(false)
			env.fog_enabled = false
			world.hide_clouds()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(_args.get("size", "236"))
			cam.position = Vector3(float(_args.get("cx", "20")), 150, float(_args.get("cz", "-6")))
			cam.rotation = Vector3(-PI / 2, 0, 0)
		elif view == "wide":
			var wc := Vector3(float(_args.get("cx", "0")), 0, float(_args.get("cz", "0")))
			_mode = "debug"
			cam.position = wc + Vector3(8, 30, 48) * float(_args.get("dist", "1"))
			cam.look_at(wc)
		elif view == "low":
			_mode = "debug"
			var a := float(_args.get("ang", "0.5"))
			var dist := float(_args.get("dist", "4.5"))
			var t := owner_node.position + Vector3(0, 0.8, 0)
			cam.position = t + Vector3(sin(a) * dist, 0.9, cos(a) * dist)
			cam.look_at(t)
	get_viewport().get_texture().get_image().save_png(_args["shot"])
	get_tree().quit()
