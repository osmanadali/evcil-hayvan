extends Node3D
## Oyunun girisi: ortami, parki, oyuncunun kopegini, NPC'leri ve arayuzu kurar.

const ParkMap = preload("res://scripts/park_map.gd")
const Kit = preload("res://scripts/kit.gd")
const World = preload("res://scripts/world.gd")
const Dog = preload("res://scripts/dog.gd")
const PetModel = preload("res://scripts/pet_model.gd")
const Person = preload("res://scripts/person.gd")
const Npc = preload("res://scripts/npc.gd")
const MapScreen = preload("res://scripts/map_screen.gd")

const RUN_SPEED := 4.6
const CAM_OFFSET := Vector3(0, 11.5, 10.5)

var world: Node3D
var player: Node3D
var cam: Camera3D
var env: Environment
var ui: CanvasLayer
var map_screen: Control

var _target := Vector2.ZERO
var _moving := false
var _dragging := false
var _stuck := 0.0
var _focus := Vector3.ZERO
var _zoom := 1.0
var _marker: MeshInstance3D
var _npc_dogs: Array[Node3D] = []
var _args := {}
var _queue: Array[Vector2] = []

enum { FETCH_NONE, FETCH_FLY, FETCH_CHASE, FETCH_RETURN }
var _fetch := FETCH_NONE
var _fetch_home := Vector2.ZERO
var _ball: MeshInstance3D
var _ball_from := Vector3.ZERO
var _ball_to := Vector3.ZERO
var _ball_t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"

	_build_environment()
	world = World.new()
	add_child(world)

	player = PetModel.new()
	player.kind = _args.get("kind", "kopek")
	add_child(player)
	_place_player(Vector2(0, -25))
	player.rotation.y = PI

	cam = Camera3D.new()
	cam.fov = 50.0
	cam.far = 400.0
	add_child(cam)
	_focus = player.position
	_update_camera(1.0)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.28
	ring.outer_radius = 0.38
	_marker = Kit.add(self, ring, Kit.glow("ffffff", 0.8))
	_marker.scale.y = 0.25
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false

	var bm := SphereMesh.new()
	bm.radius = 0.13
	bm.height = 0.26
	_ball = Kit.add(self, bm, Kit.mat("ff5a4d", 0.5))
	_ball.visible = false

	_spawn_npcs()
	_build_ui()
	if _args.has("shot"):
		_debug_shot()


func _build_environment() -> void:
	env = Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.27, 0.53, 0.92)
	sky_mat.sky_horizon_color = Color(0.78, 0.89, 0.98)
	sky_mat.ground_bottom_color = Color(0.48, 0.66, 0.5)
	sky_mat.ground_horizon_color = Color(0.78, 0.89, 0.98)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.86, 0.96)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.0
	env.glow_enabled = false
	env.glow_intensity = 0.15
	env.glow_bloom = 0.04
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.84)
	sun.light_energy = 0.82
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	sun.look_at_from_position(Vector3(6.5, 8.0, 3.5), Vector3.ZERO)


func _place_player(p: Vector2) -> void:
	player.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
	_target = p


func _spawn_npcs() -> void:
	var people := [
		{"shirt": "ff8a65", "pants": "5d6d8e", "hair": "3b2a20", "long": true, "dog": ["f4f1ea", "ffffff", "d9d2c4", "4f8fd9"],
			"route": [Vector2(0, -25.5), Vector2(0.8, -20), Vector2(-0.8, -12), Vector2(0, -7.3), Vector2(5.2, -5.2),
				Vector2(7.2, 0), Vector2(15, -1), Vector2(21, 2), Vector2(23.5, 5.6)]},
		{"shirt": "5aa9e6", "pants": "3d4b6b", "hair": "c98b4a", "long": false, "dog": [],
			"route": [Vector2(-40, -6.5), Vector2(-39, -1), Vector2(-36, 5), Vector2(-31, 7), Vector2(-25, 7), Vector2(-21, 5),
				Vector2(-14, 1), Vector2(-7.4, 0), Vector2(-5.2, 5.2), Vector2(0, 7.3), Vector2(-1, 14), Vector2(2, 21),
				Vector2(9, 24), Vector2(13, 29), Vector2(11, 35), Vector2(8, 33.6)]},
		{"shirt": "9ccc65", "pants": "795548", "hair": "2a2320", "long": true, "dog": ["6b4a35", "e8d2b0", "4a3426", "ffd15c"],
			"route": [Vector2(18, -14.5), Vector2(12, -11), Vector2(5.2, -5.4), Vector2(0, -7.4), Vector2(-5.2, -5.4),
				Vector2(-10, -13), Vector2(-14.2, -18.2)]},
	]
	for d in people:
		var n := Npc.new()
		var v := Person.new()
		v.shirt = Color(d["shirt"])
		v.pants = Color(d["pants"])
		v.hair = Color(d["hair"])
		v.long_hair = d["long"]
		n.visual = v
		n.route = d["route"]
		n.add_child(v)
		add_child(n)
		var dc: Array = d["dog"]
		if dc.size() > 0:
			var nd := _npc_dog(dc, 0.8)
			nd.follow = n
			nd.place(n.route[0] + Vector2(0.8, 0.5))
	# Kendi basina gezinen kopekler
	var free := [
		[["3a3632", "f4f1ea", "2a2320", "e2574c"], Vector2(32, 8.5), 3.5, 1.0],
		[["c9793f", "ffffff", "8c4a22", "5fbf8f"], Vector2(33.5, 7), 3.5, 0.7],
		[["e9d7b5", "ffffff", "c9a878", "b48be8"], ParkMap.MEADOW, 6.5, 0.9],
		[["8a8f98", "f4f1ea", "5b5f66", "ffd15c"], ParkMap.PICNIC + Vector2(2.5, 1.5), 2.5, 0.6],
	]
	for f in free:
		var nd := _npc_dog(f[0], f[3])
		nd.roam_center = f[1]
		nd.roam_radius = f[2]
		nd.walk_speed = 1.8
		nd.place(f[1])


func _npc_dog(c: Array, size: float) -> Node3D:
	var n := Npc.new()
	var v := Dog.new()
	v.coat = Color(c[0])
	v.accent = Color(c[1])
	v.ear_color = Color(c[2])
	v.collar_color = Color(c[3])
	n.visual = v
	n.add_child(v)
	add_child(n)
	v.scale = Vector3.ONE * size
	_npc_dogs.append(n)
	return n


# ---------------------------------------------------------------- girdi

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_set_target(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_set_target(event.position)
	elif event is InputEventMagnifyGesture:
		_zoom = clampf(_zoom / event.factor, 0.55, 1.5)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.92, 0.55, 1.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * 1.08, 0.55, 1.5)


func _set_target(screen: Vector2) -> void:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var t := 0.0
	var prev := 0.0
	while t < 120.0:
		var p := o + d * t
		if p.y < ParkMap.walk_height(Vector2(p.x, p.z)):
			break
		prev = t
		t += 0.5
	if t >= 120.0:
		return
	for i in 6:
		var mid := (prev + t) * 0.5
		var p := o + d * mid
		if p.y < ParkMap.walk_height(Vector2(p.x, p.z)):
			t = mid
		else:
			prev = mid
	var hit := o + d * t
	_cancel_actions()
	_go(Vector2(hit.x, hit.z))


## Haritadan secilen yere yollari izleyerek yuru.
func walk_to(p: Vector2) -> void:
	_cancel_actions()
	_queue = ParkMap.find_route(Vector2(player.position.x, player.position.z), p)
	_go(_queue.pop_front())


func _go(p: Vector2) -> void:
	_target = p
	_moving = true
	_stuck = 0.0
	_marker.position = Vector3(p.x, ParkMap.walk_height(p) + 0.06, p.y)
	_marker.visible = _queue.is_empty()


func _cancel_actions() -> void:
	_queue.clear()
	player.sitting = false
	if _fetch != FETCH_NONE:
		_fetch = FETCH_NONE
		_ball.reparent(self)
		_ball.visible = false


func _toggle_sit() -> void:
	var s: bool = not player.sitting
	_cancel_actions()
	_moving = false
	player.sitting = s


## Topu ileri firlat; kopek kosup getirir.
func _throw_ball() -> void:
	_cancel_actions()
	var p := Vector2(player.position.x, player.position.z)
	var land := p
	for i in 12:
		var a := randf_range(-2.4, -0.7)   # ekranda yukari dogru yay
		var c := p + Vector2(cos(a), sin(a)) * randf_range(6.0, 9.5)
		if c.length() < ParkMap.PLAY_RADIUS - 1.0 and ParkMap.water_sd(c) > 1.0 and world.resolve(c, 0.4, p).distance_to(c) < 0.05:
			land = c
			break
	if land == p:
		return
	_fetch_home = p
	_ball_from = player.position + Vector3(0, 0.9, 0)
	_ball_to = Vector3(land.x, ParkMap.walk_height(land) + 0.13, land.y)
	_ball_t = 0.0
	_ball.visible = true
	_fetch = FETCH_FLY
	_queue.clear()
	_go(land)
	_marker.visible = false


func _update_fetch(dt: float) -> void:
	var p := Vector2(player.position.x, player.position.z)
	if _fetch == FETCH_FLY:
		_ball_t = minf(_ball_t + dt / 0.9, 1.0)
		_ball.position = _ball_from.lerp(_ball_to, _ball_t) + Vector3(0, sin(_ball_t * PI) * 3.2, 0)
		if _ball_t >= 1.0:
			_fetch = FETCH_CHASE
	elif _fetch == FETCH_CHASE:
		_ball.position.y = _ball_to.y
		if p.distance_to(Vector2(_ball_to.x, _ball_to.z)) < 0.7 or not _moving:
			_ball.reparent(player.mouth, false)
			_ball.position = Vector3.ZERO
			_fetch = FETCH_RETURN
			_go(_fetch_home)
			_marker.visible = false
	elif _fetch == FETCH_RETURN and not _moving:
		_ball.reparent(self)
		_ball.position = player.position + Vector3(0, 0.13, 0) - player.basis.z * 0.7
		_fetch = FETCH_NONE
		player.happy_time = 2.5


func _process(dt: float) -> void:
	var p := Vector2(player.position.x, player.position.z)
	var to := _target - p
	var d := to.length()
	if _moving and d < 0.9 and not _queue.is_empty():
		_go(_queue.pop_front())
	elif _moving and d > 0.15:
		var sp := minf(RUN_SPEED, 1.2 + d * 2.5)
		var np: Vector2 = world.resolve(p + to / d * minf(sp * dt, d), 0.35, p)
		var moved := np.distance_to(p) / maxf(dt, 0.0001)
		player.position = Vector3(np.x, ParkMap.walk_height(np), np.y)
		if moved > 0.2:
			var dir := np - p
			player.rotation.y = lerp_angle(player.rotation.y, atan2(-dir.x, -dir.y), minf(1.0, dt * 10.0))
		player.speed = moved
		_stuck = _stuck + dt if moved < sp * 0.25 else 0.0
		if _stuck > 0.6 and not _dragging:
			_moving = false
	else:
		_moving = false
		player.speed = 0.0
	if not _moving:
		_marker.visible = false
	if _fetch != FETCH_NONE:
		_update_fetch(dt)
	_marker.rotation.y += dt * 2.0

	# Yakindaki kopekler birbirini gorunce sevinir
	var any_near := false
	for n in _npc_dogs:
		var near: bool = n.position.distance_to(player.position) < 3.0
		n.visual.excited = near
		any_near = any_near or near
	player.excited = any_near
	_update_camera(minf(1.0, dt * 5.0))


func _update_camera(k: float) -> void:
	_focus = _focus.lerp(player.position, k)
	cam.position = _focus + CAM_OFFSET * _zoom
	cam.look_at(_focus + Vector3(0, 0.6, 0))


# ---------------------------------------------------------------- arayuz

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(118, 84)
	b.add_theme_font_size_override("font_size", 25)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.92) if state != "pressed" else Color(1.0, 0.9, 0.7)
		sb.set_corner_radius_all(30)
		sb.shadow_color = Color(0, 0, 0, 0.18)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 4)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		b.add_theme_stylebox_override(state, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, Color("5a4636"))
	b.pressed.connect(cb)
	return b


func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_top = -150
	row.offset_bottom = -56
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	ui.add_child(row)
	row.add_child(_button("Harita", func(): map_screen.open(Vector2(player.position.x, player.position.z))))
	row.add_child(_button("Otur", _toggle_sit))
	row.add_child(_button("Top At", _throw_ball))
	row.add_child(_button("Şapka", func(): pass))
	row.add_child(_button("Büyüt", func(): player.set_stage((player.stage + 1) % 3)))

	map_screen = MapScreen.new()
	map_screen.place_chosen.connect(walk_to)
	ui.add_child(map_screen)


# ---------------------------------------------------------------- gelistirme

## Ekran goruntusu al: -- --shot=dosya.png [--view=top|wide] [--at=x,z] [--hat] [--stage=0] [--map] [--noui]
func _debug_shot() -> void:
	if _args.has("at"):
		var xy: PackedStringArray = _args["at"].split(",")
		_place_player(Vector2(float(xy[0]), float(xy[1])))
		_focus = player.position
	if _args.has("hat"):
		pass
	if _args.has("stage"):
		player.set_stage(int(_args["stage"]))
	var view: String = _args.get("view", "")
	if view != "" or _args.has("noui"):
		ui.visible = false
	if _args.has("pose"):
		player.pose = _args["pose"]
	if _args.has("hop"):
		player.hop()
	if _args.has("throw"):
		_throw_ball()
	if _args.has("map"):
		map_screen.open(Vector2(player.position.x, player.position.z))
	if _args.has("run"):
		_go(Vector2(player.position.x + 30.0, player.position.z))
	var frames := int(_args.get("frames", "40"))
	for i in frames:
		await get_tree().process_frame
		if view == "top":
			set_process(false)
			env.fog_enabled = false
			world.hide_clouds()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(_args.get("size", "100"))
			cam.position = Vector3(0, 150, 0)
			cam.rotation = Vector3(-PI / 2, 0, 0)
		elif view == "wide":
			set_process(false)
			cam.fov = 50
			cam.position = Vector3(10, 34, 62)
			cam.look_at(Vector3(0, 0, -4))
		elif view == "low":
			set_process(false)
			cam.fov = 45
			var a := float(_args.get("ang", "0.5"))
			cam.position = player.position + Vector3(sin(a) * 3.2, 1.3, cos(a) * 3.2)
			cam.look_at(player.position + Vector3(0, 0.45, 0))
	get_viewport().get_texture().get_image().save_png(_args["shot"])
	get_tree().quit()
