extends Node3D
## Oyunun girisi: dunyayi, sahibi, evcil hayvanlari, NPC'leri ve arayuzu kurar; girdiyi ve kamerayi yonetir.

const ParkMap = preload("res://scripts/park_map.gd")
const Kit = preload("res://scripts/kit.gd")
const World = preload("res://scripts/world.gd")
const GameState = preload("res://scripts/game_state.gd")
const PetModel = preload("res://scripts/pet_model.gd")
const PetAgent = preload("res://scripts/pet_agent.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const UiKit = preload("res://scripts/ui_kit.gd")
const Bus = preload("res://scripts/bus.gd")
const Minimap = preload("res://scripts/minimap.gd")
const Home = preload("res://scripts/home.gd")
const MetroRide = preload("res://scripts/metro_ride.gd")
const CarPlay = preload("res://scripts/carplay.gd")
const ShopInterior = preload("res://scripts/shop_interior.gd")
const Intro = preload("res://scripts/intro.gd")
const Npc = preload("res://scripts/npc.gd")
const Car = preload("res://scripts/car.gd")
const Ui = preload("res://scripts/ui.gd")
const MapScreen = preload("res://scripts/map_screen.gd")
const Accessories = preload("res://scripts/accessories.gd")

const WALK_SPEED := 5.0
const CAM_DIST := 7.2
const SKY_TURN := 2.5          # gokyuzu donusu (radyan)
const SUN_ELEVATION := 47.9   # gokyuzu gorselindeki gunes: yukseklik ve yatay aci (derece)
const SUN_AZIMUTH := 34.2

var state: Node
var world: Node3D
var ui: CanvasLayer
var map_screen: Control
var env: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var _sky_mat: PanoramaSkyMaterial
var clock := 10.0            # oyun saati (0-24)
var night := 0.0
var _night_sent := -1.0
const DAY_SECONDS := 1200.0  # bir oyun gunu 20 dakika surer
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
var _cam_yaw := 0.0        # 0 = kuzeye bakar
var _cam_pitch := 0.27
var _press_pos := Vector2.ZERO
var _press_moved := 0.0
var _press_time := 0.0
var _steering := false     # cubukla yuruyor
var _walk_v := 0.0          # su anki yurume hizi
var _kb_stick := false     # klavye cubugu dolduruyor
var _routing := false      # harita rotasi izleniyor (yurume hizinda)
var _direct := false       # son hedefe duz cizgiyle mi gidiliyor
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
var _ball_vel := Vector3.ZERO
var _ball_live := false
const GRAVITY := 9.8
const ROUTE_SPEED := 2.1     # haritadan secilen rotada yurume hizi
var _yarn: Node3D
var _bowl: Node3D
var _bowl_t := 0.0
var _food_pending := {}
var _coins: Array[Node3D] = []
var _fx: Array = []
var _npc_pets: Array[Node3D] = []
var _npc_people: Array[Node3D] = []
var _bark_t := 4.0
var _greet_cd := 0.0
const GREETINGS := ["Merhaba!", "Günaydın!", "Ne tatlı şey!", "Kolay gelsin!", "Maşallah, çok güzelmiş!", "İyi gezmeler!", "Adı ne?"]
var _cars: Array[Node3D] = []
var _near_npc: Node3D
var _pet_cd := 0.0
var _slow_t := 0.0
var _save_t := 0.0
var _args := {}
var _ready_done := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"

	if _args.has("clock"):
		clock = float(_args["clock"])
	state = GameState.new()
	add_child(state)
	if _args.has("shot"):
		state.reset()
	_build_environment()
	_setup_audio()
	# Dunya kurulurken yukleniyor ekrani goster
	var loading := CanvasLayer.new()
	var bg := ColorRect.new()
	bg.color = Color("f6e7c8")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var lt := Label.new()
	var zone: String = ParkMap.zone if travel_to != "" else _args.get("zone", state.d.get("zone", ""))
	if not ParkMap.ZONE_TITLES.has(zone):
		zone = ""
	if zone != ParkMap.zone or not ParkMap.loaded:
		ParkMap.reset(zone)
	state.d["zone"] = zone
	lt.text = "Patili Gezinti\n\n%s%s hazırlanıyor…" % ["M4 metrosuyla yoldasın…\n\n" if travel_to != "" else "", ParkMap.ZONE_TITLES[zone]]
	lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lt.add_theme_font_size_override("font_size", 44)
	lt.add_theme_color_override("font_color", Color("6b4a2f"))
	lt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(lt)
	add_child(loading)
	cam = Camera3D.new()
	add_child(cam)
	await get_tree().process_frame
	await get_tree().process_frame
	ParkMap.load_data()
	state.set_places()
	world = World.new()
	add_child(world)

	cam.fov = 60.0
	cam.far = 900.0
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
	ui.bought.connect(_on_bought)
	ui.select_pet.connect(_select_pet)
	ui.start_game.connect(_start_game)
	ui.continue_game.connect(_enter_play)
	ui.open_map.connect(_open_map)
	ui.photo.connect(_on_photo)
	ui.closet_toggled.connect(_on_closet)
	ui.worn_changed.connect(func(): agents[state.d["active"]].refresh())
	ui.adopted.connect(_on_adopted)
	ui.back_to_menu.connect(func():
		state.save_game()
		_mode = "menu"
		ui.show_screen("menu"))
	minimap = Minimap.new()
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ui.hud.add_child(minimap)
	minimap.tapped.connect(_open_map)
	map_screen.nav_chosen.connect(func(p: Vector2, n: String): _set_nav(p, n))
	get_tree().set_auto_accept_quit(false)
	loading.queue_free()
	_ready_done = true
	if travel_to != "":
		# Metroyla gelindi: istasyon girisinden cik, dogrudan oyuna devam
		for g in world.metro_gates:
			if g["name"] == travel_to:
				_spawn_at_gate(g)
				break
		ui.toast("%s istasyonundan çıktın · %s" % [travel_to, ParkMap.ZONE_TITLES[ParkMap.zone]])
		travel_to = ""
		_enter_play()
	elif _args.has("gate"):
		for g in world.metro_gates:
			if g["name"] == _args["gate"]:
				_spawn_at_gate(g)
				break
	if _args.has("shot"):
		if _args.has("intro"):
			_play_intro()
			await get_tree().create_timer(float(_args.get("secs", "3"))).timeout
			get_viewport().get_texture().get_image().save_png(_args["shot"])
			get_tree().quit()
		else:
			_debug_shot()
	elif travel_to == "" and _mode == "menu":
		_play_intro()


## Acilis introsu: sehrin uzerinde sinematik cekimler, sonra ana menu.
func _play_intro() -> void:
	var shots: Array = []
	var h := func(p: Vector2) -> float: return ParkMap.terrain_height(p)
	var st := ParkMap.spot("baslangic") if ParkMap.has_spot("baslangic") else Vector2.ZERO
	shots.append([Vector3(st.x - 90, h.call(st) + 70, st.y + 70), Vector3(st.x - 30, h.call(st) + 48, st.y + 45),
		Vector3(st.x, h.call(st), st.y), Vector3(st.x + 10, h.call(st), st.y), "KEÇİÖREN", "SUBAYEVLERİ · ANKARA", Color("f5c518")])
	if ParkMap.zone == "":
		# Altinpark golu: kiyidan suyun uzerine dogru alcak cekim
		var c := Vector2(540, 160)
		shots.append([Vector3(c.x - 25, h.call(c) + 5, c.y - 15), Vector3(c.x - 8, h.call(c) + 3.5, c.y - 4),
			Vector3(c.x + 40, h.call(c) + 0.5, c.y + 20), Vector3(c.x + 55, h.call(c), c.y + 30), "ALTINPARK", "BİR DOST, KOCA BİR ŞEHİR", Color("2fb7a8")])
	for r in _rides:
		if r.get_meta("kind") == "araba":
			var cp := Vector2(r.position.x, r.position.z)
			var f := Vector2(-sin(r.rotation.y), -cos(r.rotation.y))
			var sd := Vector2(-f.y, f.x)
			var a3 := func(v: Vector2, up: float) -> Vector3: return Vector3(v.x, h.call(v) + up, v.y)
			shots.append([a3.call(cp + f * 7.0 + sd * 3.5, 1.1), a3.call(cp + f * 5.0 - sd * 2.5, 0.8),
				r.position + Vector3(0, 0.6, 0), r.position + Vector3(0, 0.5, 0), "33 OA 2003", "SENİN ARABAN HAZIR", Color("ff5f8f")])
			break
	if not world.metro_gates.is_empty():
		var g: Vector2 = world.metro_gates[0]["pos"]
		shots.append([Vector3(g.x + 14, h.call(g) + 6, g.y + 10), Vector3(g.x + 6, h.call(g) + 3, g.y + 12),
			Vector3(g.x, h.call(g) + 1, g.y), Vector3(g.x, h.call(g) + 1, g.y), "M4 METRO", "METEOROLOJİ → GAR", Color("e8453c")])
	var it := Intro.new()
	it.cam = cam
	it.shots = shots
	ui.add_child(it)
	ui.menu.visible = false
	ui.hud.visible = false
	_mode = "intro"
	it.finished.connect(func():
		it.queue_free()
		_mode = "menu"
		ui.show_screen("menu"))


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
	# Fotograf tabanli gokyuzu (Poly Haven, CC0); gunesi kameranin arkasina almak icin dondurulur
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/sky.hdr")
	sky_mat.energy_multiplier = 1.0
	_sky_mat = sky_mat
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, SKY_TURN, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.68, 0.82)
	env.ambient_light_energy = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 5.0
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.92)
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.5
	add_child(sun)
	var el := deg_to_rad(SUN_ELEVATION)
	var az := deg_to_rad(SUN_AZIMUTH)
	var to_sun := Basis(Vector3.UP, SKY_TURN) * Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.look_at_from_position(to_sun * 50.0, Vector3.ZERO)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)
	moon.look_at_from_position(Vector3(-20, 40, 25), Vector3.ZERO)


## Gun donumu: saat ilerler; gunes dogudan dogar, batidan batar, gece ay isigi ve lambalar.
func _update_daylight(dt: float) -> void:
	clock = fposmod(clock + dt * 24.0 / DAY_SECONDS, 24.0)
	var t := (clock - 6.0) / 12.0                      # 0 = gun dogumu, 1 = gun batimi
	var el := sin(t * PI) * 62.0                       # derece; gece eksi
	var day := smoothstep(-10.0, 12.0, el)
	var az := lerpf(-PI * 0.5, PI * 0.5, clampf(t, -0.5, 1.5))    # dogu -> guney -> bati
	var e := deg_to_rad(maxf(el, 4.0))
	var to_sun := Vector3(-sin(az) * cos(e), sin(e), cos(az) * cos(e))
	sun.look_at_from_position(to_sun * 50.0, Vector3.ZERO)
	var low := 1.0 - smoothstep(4.0, 28.0, el)           # ufka yakinken kizil
	sun.light_color = Color(1.0, 0.93, 0.8).lerp(Color(1.0, 0.55, 0.3), low)
	sun.light_energy = smoothstep(-2.0, 10.0, el)
	sun.shadow_enabled = el > 0.0
	moon.light_energy = 0.5 * (1.0 - day)
	_sky_mat.energy_multiplier = lerpf(0.1, 1.0, day)
	env.ambient_light_color = Color(0.3, 0.38, 0.62).lerp(Color(0.6, 0.68, 0.82), day).lerp(Color(0.8, 0.6, 0.5), low * day * 0.5)
	env.ambient_light_energy = lerpf(0.6, 0.8, day)
	env.fog_light_color = Color(0.05, 0.07, 0.12).lerp(Color(0.7, 0.8, 0.92), day)
	# Gokyuzu gorselindeki gunes de ayni yone donsun
	env.sky_rotation = Vector3(0, atan2(to_sun.x, to_sun.z) - deg_to_rad(SUN_AZIMUTH) + PI, 0)
	night = 1.0 - day
	if absf(night - _night_sent) > 0.01:
		_night_sent = night
		world.set_night(night)


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
	# Bina icine dusmesin: en yakin acik noktaya kay
	if ParkMap.home == null and world and (world._inside_building(p) or not world.is_free(p, 0.4)):
		var found := false
		for r in range(2, 60, 2):
			for k in 16:
				var q := p + Vector2.from_angle(k * TAU / 16.0) * float(r)
				if world.is_free(q, 0.6) and not world._inside_building(q):
					p = q
					found = true
					break
			if found:
				break
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
	owner_model.tint = Color("3f8f8a") if state.d["owner"] == "kadin" else Color("34507a")
	var oi := int(state.d.get("outfit", -1))
	if oi >= 0 and oi < OUTFITS.size():
		var of: Array = OUTFITS[oi]
		owner_model.tint = Color(of[1])
		owner_model.tint2 = Color(of[2])
		owner_model.pattern = of[3]
		owner_model.pants = Color(of[4]) if of[4] != "" else Color(0, 0, 0, 0)
	_ride = null
	_spawn_rides()
	_spawn_buses()
	owner_model.stepped.connect(func(): _sfx("adim%d" % (randi() % 4 + 1), -9.0, randf_range(0.9, 1.1)))
	owner_node.add_child(owner_model)
	_place_owner(ParkMap.spot("baslangic"))
	owner_node.rotation.y = PI
	var pets: Array = state.owned_pets()
	if pets.is_empty():
		pets = ["kopek"]   # menude arka plan icin
	for kind in pets:
		_add_agent(kind)
	_link_buddies()
	for car in _cars:
		car.owner_node = owner_node
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
	ui.toast("Hoş geldin! Soldaki çubukla yürü, ekranı sürükleyerek etrafına bak.")
	ui.toast("Dostunu sevmek için üzerine dokun.")
	ui.toast("Haritayı aç: Altınpark'taki Pet Shop'ta mama ve aksesuar var.")


func _enter_play() -> void:
	if not state.d["started"]:
		ui.show_screen("setup")
		return
	_mode = "play"
	_link_buddies()
	ui.show_screen("hud")


func _spawn_npcs() -> void:
	# Sokaklarda ve parkta yuruyen insanlar (bazilarinin yaninda hayvani var)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var tints := ["c94f4f", "3f6fb5", "4f8f5a", "e0b84a", "7a5ea8", "f2f2f2", "2f3a4a", "d98a4f", "6fb1c9", "9a9a9a"]
	var pets := [["kopek", "f4f4f4", 0.8], [], ["kedi", "c9c9c9", 0.9], ["kopek", "b08a66", 1.1], [], ["kopek", "5a5a5a", 0.9], [], []]
	var park := ParkMap.spot("cesme") if ParkMap.has_spot("cesme") else ParkMap.spot("baslangic")
	var people := 30 if ParkMap.zone == "" else 18
	for i in people:
		var n := Npc.new()
		var v := PersonModel.new()
		v.kind = "kadin" if i % 2 == 0 else "erkek"
		v.tint = Color(tints[i % tints.size()])
		var of: Array = OUTFITS[rng.randi() % OUTFITS.size()]
		if rng.randf() < 0.6:
			v.tint = Color(of[1]).lerp(Color(tints[i % tints.size()]), rng.randf() * 0.5)
			v.tint2 = Color(of[2])
			v.pattern = of[3]
			v.pants = Color(of[4]) if of[4] != "" else Color(0, 0, 0, 0)
		n.visual = v
		# Yarisi parkin cevresinden, yarisi haritanin rastgele bir yerinden baslar
		var from := park + Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120)) if i < 12 else \
			Vector2(rng.randf_range(ParkMap.BOUNDS_MIN.x, ParkMap.BOUNDS_MAX.x) * 0.9, rng.randf_range(ParkMap.BOUNDS_MIN.y, ParkMap.BOUNDS_MAX.y) * 0.9)
		n.graph_node = ParkMap.nearest_node(from)
		n.walk_speed = rng.randf_range(1.2, 1.6)
		n.add_child(v)
		add_child(n)
		_npc_people.append(n)
		var pet_def: Array = pets[i % pets.size()]
		if pet_def.size() > 0:
			var np := _npc_pet(pet_def[0], Color(pet_def[1]), pet_def[2])
			np.follow = n
			np.place(ParkMap.nodes[n.graph_node] + Vector2(0.8, 0.5))
	# Sokaklarda dolasan arabalar
	if world.car_mesh:
		var paints := ["f2f2f2", "9a9da3", "3a3d42", "b23a34", "2f4f8a", "e9e4d6", "f2c230"]
		for i in (14 if ParkMap.zone == "" else 8):
			var car := Car.new()
			for t in 40:
				var k := rng.randi() % ParkMap.nodes.size()
				if ParkMap.road_next[k].size() > 0 and ParkMap.inside_bounds(ParkMap.nodes[k], 20.0):
					car.node = k
					break
			car.owner_node = owner_node
			car.add_child(world.traffic_car(i, Color(paints[i % paints.size()])))
			add_child(car)
			_cars.append(car)
	# Bisikletliler: yolun saginda yavas gider, donerken kolla isaret verir
	for i in (4 if ParkMap.zone == "" else 2):
		var bike := _vehicle("res://assets/models/bisiklet.glb", 1.75, true)
		if bike == null:
			break
		var cy := Car.new()
		cy.cruise = rng.randf_range(3.8, 5.2)
		for t in 40:
			var k := rng.randi() % ParkMap.nodes.size()
			if ParkMap.road_next[k].size() > 0 and ParkMap.inside_bounds(ParkMap.nodes[k], 20.0):
				cy.node = k
				break
		cy.owner_node = owner_node
		cy.add_child(bike)
		add_child(cy)
		var rd := PersonModel.new()
		rd.kind = "kadin" if i % 2 == 0 else "erkek"
		rd.tint = Color(["2f62a8", "e07b1f", "3f8f4a", "c8322b"][i % 4])
		bike.add_child(rd)
		rd.riding = "bisiklet"
		rd.ride_lean = 0.6
		rd.position = Vector3(0, 0.97 + 0.09 - rd.hips_height(), 0.2)
		cy.rider = rd
		_cyclists.append(cy)
	# Sokak kopekleri: kulaklari kupeli, sokak aginda kendi baslarina gezer
	for i in 5:
		var sd := _npc_pet("kopek", Color(["c9a070", "8a7a66", "e8dcc4", "6b5a48", "b89a74"][i]), rng.randf_range(1.0, 1.15))
		var from := Vector2(rng.randf_range(ParkMap.BOUNDS_MIN.x, ParkMap.BOUNDS_MAX.x) * 0.8, rng.randf_range(ParkMap.BOUNDS_MIN.y, ParkMap.BOUNDS_MAX.y) * 0.8)
		sd.graph_node = ParkMap.nearest_node(from)
		sd.walk_speed = rng.randf_range(1.0, 1.5)
		sd.place(ParkMap.nodes[sd.graph_node])
		sd._target = ParkMap.nodes[sd.graph_node]
	# Parkta kendi basina gezen hayvanlar (yalnizca oyun yerleri olan bolgede)
	if not ParkMap.has_spot("cesme"):
		return
	var free := [
		["kopek", "4a4038", 1.0, ParkMap.spot("oyun_alani"), 4.0, 2.2], ["kopek", "ffe0b0", 0.75, ParkMap.spot("oyun_alani") + Vector2(2, 1), 4.0, 2.6],
		["kopek", "ffffff", 0.9, ParkMap.spot("cesme") + Vector2(10, 12), 7.0, 1.8], ["kedi", "ffffff", 1.0, ParkMap.spot("piknik") + Vector2(3, 2), 4.0, 1.2],
		["kedi", "d8c8b0", 1.05, ParkMap.spot("cardak") + Vector2(-8, 6), 5.0, 1.6], ["kopek", "c9a070", 1.05, ParkMap.spot("petshop") + Vector2(6, 12), 6.0, 2.0],
	]
	for f in free:
		var np := _npc_pet(f[0], Color(f[1]), f[2])
		np.roam_center = f[3]
		np.roam_radius = f[4]
		np.walk_speed = f[5]
		np.world = world
		np.place(f[3])
	# Kovalamaca oynayan kediler (biri kacar, digeri kovalar)
	for c in [ParkMap.spot("dondurmaci") + Vector2(14, 24), ParkMap.spot("kafe") + Vector2(-16, 12)]:
		var runner := _npc_pet("kedi", Color("f2e2c4"), 0.9)
		runner.roam_center = c
		runner.roam_radius = 6.0
		runner.walk_speed = 3.6
		runner.short_pause = true
		runner.world = world
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
	# Park yollarinda sik, sokaklarda seyrek altin
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var id := 0
	var gold := Kit.mat("e9b93a", 0.25)
	for group in [[ParkMap.data["paths"], 17.0, 0.0], [ParkMap.data["roads"], 46.0, 1.0]]:
		for w in group[0]:
			var ids: Array = w["n"]
			var carry: float = group[1] * 0.5
			for i in ids.size() - 1:
				var a := ParkMap.nodes[int(ids[i])]
				var b := ParkMap.nodes[int(ids[i + 1])]
				var length := a.distance_to(b)
				if length < 0.5:
					continue
				var dir := (b - a) / length
				while carry < length:
					id += 1
					var side: float = (float(w["w"]) * 0.5 + 1.3) * group[2]
					var p := a + dir * carry + Vector2(-dir.y, dir.x) * side + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
					carry += group[1]
					if state.d["found"].has(id) or not world.is_free(p, 0.3):
						continue
					var c := Node3D.new()
					c.position = Vector3(p.x, ParkMap.walk_height(p) + 0.55, p.y)
					c.set_meta("id", id)
					Kit.cyl(c, 0.2, 0.2, 0.05, Vector3.ZERO, gold, 14, Vector3(PI / 2, 0, 0))
					add_child(c)
					_coins.append(c)
				carry -= length


# ---------------------------------------------------------------- girdi

func _unhandled_input(e: InputEvent) -> void:
	if not _ready_done or _mode == "menu" or ui.is_blocking() or map_screen.visible:
		return
	var touch := DisplayServer.is_touchscreen_available()
	if e is InputEventScreenTouch and touch:
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_pointer_down(e.position)
			else:
				_press_moved = 1000.0
		else:
			_touches.erase(e.index)
			if _touches.is_empty():
				_pointer_up(e.position)
	elif e is InputEventScreenDrag and touch:
		if _touches.size() >= 2 and _touches.has(e.index):
			var other: Vector2 = e.position
			for k in _touches:
				if k != e.index:
					other = _touches[k]
			_zoom_by(maxf(other.distance_to(_touches[e.index]), 1.0) / maxf(other.distance_to(e.position), 1.0))
		elif _dragging:
			_pointer_move(e.relative)
		_touches[e.index] = e.position
	elif e is InputEventMouseButton and not touch:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_pointer_down(e.position)
			else:
				_pointer_up(e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(0.92)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.08)
	elif e is InputEventMouseMotion and not touch and _dragging:
		_pointer_move(e.relative)


## Bilgisayar: WASD / oklar yurur, Shift kosar, E etkilesim, 1-2-3 sev-mama-top, Q komutlar, M harita, Esc menu,
## C fotograf, fare tekeri yakinlastirir, sol tikla surukleyince kamera doner.
func _input(e: InputEvent) -> void:
	if not (e is InputEventKey) or e.echo or not _ready_done:
		return
	var k: InputEventKey = e
	if not k.pressed:
		return
	if _mode == "play" and not ui.is_blocking() and not map_screen.visible:
		match k.keycode:
			KEY_E, KEY_F:
				if _taxi != null:
					_leave_taxi(false)
				elif _ride != null:
					if absf(_drive_speed) < 2.0:
						_exit_ride()
				elif ui._context.visible:
					_on_command(ui._context_cmd)
			KEY_1:
				_on_command("pet")
			KEY_2:
				ui._on_action("food")
			KEY_3:
				_on_command("yarn" if state.d["active"] == "kedi" else "throw")
			KEY_Q:
				ui._on_action("more")
			KEY_M:
				_open_map()
			KEY_C:
				_on_photo("enter")
			KEY_V:
				_toggle_fps()
			KEY_P:
				_open_phone()
			KEY_G:
				ui.open_quests()
			KEY_J:
				_open_jobs()
			KEY_TAB:
				var pets: Array = state.owned_pets()
				if pets.size() > 1:
					_select_pet(pets[(pets.find(state.d["active"]) + 1) % pets.size()])
	if k.keycode == KEY_SPACE and _mode == "play" and _ride == null:
		_jump()
	if _mode == "metro" and _metro and (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER):
		_metro.fast = true
	if k.keycode == KEY_ESCAPE:
		if map_screen.visible:
			map_screen.visible = false
		elif ui.is_blocking():
			ui.close_modal()
		elif _mode == "play":
			ui.open_pause()


## Klavyeden hareket: dokunmatik cubuk kullanilmiyorsa ui.stick'i doldurur.
func _keyboard_stick() -> void:
	if ui._stick_id != -2:
		return
	var v := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if v == Vector2.ZERO:
		if _kb_stick:
			ui.stick = Vector2.ZERO
			_kb_stick = false
		return
	var run := Input.is_physical_key_pressed(KEY_SHIFT) or _ride != null
	ui.stick = v.normalized() * (1.0 if run else 0.3)
	_kb_stick = true


func _zoom_by(f: float) -> void:
	if _mode == "photo":
		_photo["dist"] = clampf(_photo["dist"] * f, 1.8, 12.0)
	else:
		_zoom = clampf(_zoom * f, 0.45, 2.6)


## Surukleme kamerayi cevirir; kisa dokunus yurutur, hayvani sevdirir ya da atis hedefini secer.
func _pointer_down(pos: Vector2) -> void:
	_dragging = true
	_press_pos = pos
	_press_moved = 0.0
	_press_time = Time.get_ticks_msec() / 1000.0


func _pointer_move(rel: Vector2) -> void:
	_press_moved += rel.length()
	if _mode == "photo":
		_photo["yaw"] -= rel.x * 0.008
		_photo["pitch"] = clampf(_photo["pitch"] + rel.y * 0.006, 0.03, 1.2)
	elif _mode == "play":
		_cam_yaw -= rel.x * 0.006
		if _ride != null and _fps:
			_fps_yaw = clampf(_fps_yaw - rel.x * 0.005, -1.9, 1.9)
			_fps_pitch = clampf(_fps_pitch - rel.y * 0.004, -0.8, 0.55)
		else:
			_cam_pitch = clampf(_cam_pitch + rel.y * 0.004, 0.1, 1.15)


func _pointer_up(pos: Vector2) -> void:
	_dragging = false
	if _mode != "play" or _press_moved > 16.0 or Time.get_ticks_msec() / 1000.0 - _press_time > 0.45:
		return
	var hit = _ground_hit(pos)
	if _aim:
		_aim = false
		if hit != null:
			_throw_to(hit)
		return
	if ui.radial_open():
		ui.close_radial()
		return
	for k in agents:
		var a: Node3D = agents[k]
		if cam.unproject_position(a.position + Vector3(0, 0.35, 0)).distance_to(pos) < 64.0:
			_select_pet(k)
			ui.open_radial(cam.unproject_position(a.position + Vector3(0, 0.4, 0)), state.d["active"] == "kedi", state.owned_pets().size() > 1)
			return
	if hit != null:
		_queue.clear()
		if (hit as Vector2).distance_to(_owner_pos()) > 35.0:
			walk_to(hit)      # uzak hedef: sokaklari izle
		else:
			_go(hit)
			_direct = true
			_routing = false


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
	_direct = false
	_routing = true
	_queue = world.find_path(_owner_pos(), p)
	_go(_queue.pop_front())


func _go(p: Vector2) -> void:
	_target = p
	_moving = true
	_stuck = 0.0
	_marker.position = Vector3(p.x, ParkMap.walk_height(p) + 0.06, p.y)
	_marker.visible = _queue.is_empty()


# ---------------------------------------------------------------- komutlar

## Su icinde ne kadar batiyor (kiyidan uzaklastikca derinlesir, en cok ~0.75 m).
func _wade_depth(p: Vector2) -> float:
	if ParkMap.home != null:
		return 0.0
	var sd := ParkMap.water_sd(p)
	return clampf(-sd * 0.32, 0.0, 0.75) if sd < 0.0 else 0.0


## Suya girme / islanma: suda yavaslar, cikinca bir sure su damlar.
func _update_wet(dt: float) -> void:
	var p := _owner_pos()
	var inside := _ride == null and ParkMap.home == null and ParkMap.water_sd(p) < -0.2
	if inside and not _in_water:
		_sfx("su_sicrama" if _sounds.has("su_sicrama") else "firlat", -3.0)
		ui.toast("Suya girdin! Sırılsıklam oldun!")
		state.count("swim", 1.0)
	_in_water = inside
	if inside:
		_wet_t = 25.0
	else:
		_wet_t = maxf(_wet_t - dt, 0.0)
	if _drips == null or not is_instance_valid(_drips):
		_drips = CPUParticles3D.new()
		_drips.amount = 24
		_drips.lifetime = 0.7
		_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_drips.emission_box_extents = Vector3(0.2, 0.5, 0.12)
		_drips.direction = Vector3.DOWN
		_drips.spread = 10.0
		_drips.initial_velocity_min = 0.2
		_drips.initial_velocity_max = 0.6
		_drips.gravity = Vector3(0, -9.0, 0)
		_drips.scale_amount_min = 0.015
		_drips.scale_amount_max = 0.03
		var m := SphereMesh.new()
		m.radius = 1.0
		m.height = 2.0
		m.radial_segments = 6
		m.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.88, 1.0, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.05
		m.material = mat
		_drips.mesh = m
		_drips.position = Vector3(0, 0.9, 0)
		owner_node.add_child(_drips)
	_drips.emitting = _wet_t > 0.0 and not inside


var _shop: Node3D
var _shop_spot: Dictionary = {}


## Market / eczane ici: ev gibi yurunebilen ic mekan (yer altinda kurulur).
func _enter_shop(sp: Dictionary) -> void:
	if _shop:
		_shop.queue_free()
	_shop = ShopInterior.new()
	_shop.kind = sp["kind"]
	_shop.title = sp["name"]
	_shop.position = Vector3(0, 300, 0)      # gokyuzunde: kamera arazinin altina dusmesin
	add_child(_shop)
	_shop_spot = sp
	ParkMap.home = _shop
	_moving = false
	_queue.clear()
	var inside: Vector2 = _shop.w2(_shop.entrance_local)
	_place_owner(inside)
	owner_node.rotation.y = 0.0
	var i := 0
	for k in agents:
		agents[k].place(inside + Vector2(0.7 - 0.6 * i, 0.3))
		i += 1
	_cam_pitch = 0.55
	_cam_yaw = 0.0
	_zoom = 0.6
	ui.toast("%s · Hoş geldiniz!" % sp["name"])
	_sfx("dukkan_zil", -6.0)
	get_tree().create_timer(0.9).timeout.connect(func(): _sfx("hosgeldiniz", -2.0))


func _exit_shop() -> void:
	if _basket_node:
		_basket_node.queue_free()
		_basket_node = null
	_cart.clear()
	ParkMap.home = null
	if _shop:
		_shop.queue_free()
		_shop = null
	var out: Vector2 = _shop_spot["pos"]
	_place_owner(out)
	var i := 0
	for k in agents:
		agents[k].place(out + Vector2(1.0 + 0.6 * i, 0.5).rotated(i * 2.0))
		i += 1
	_cam_pitch = 0.27


func _shop_buy() -> void:
	_sfx("kasa", -8.0)
	ui.open_store(_shop.kind, _shop.title)


var _cart := {}            # marketteki sepet: kimlik -> adet
var _basket_node: Node3D


func _item(id: String) -> Array:
	for it in ui.SHOP_ITEMS["market"]:
		if it[0] == id:
			return it
	return [id, id, 0, "bag"]


func _cart_count() -> int:
	var n := 0
	for id in _cart:
		n += int(_cart[id])
	return n


func _cart_total() -> int:
	var t := 0
	for id in _cart:
		t += int(_item(id)[2]) * int(_cart[id])
	return t


## Giristen sepet al: elde tasinir, urunler icinde gorunur.
func _take_basket() -> void:
	_basket_node = Node3D.new()
	var red := Kit.mat("d0302b", 0.5)
	Kit.box(_basket_node, Vector3(0.4, 0.03, 0.28), Vector3(0, -0.24, 0), red)
	for sx in [-1.0, 1.0]:
		Kit.box(_basket_node, Vector3(0.03, 0.2, 0.28), Vector3(sx * 0.2, -0.14, 0), red)
		Kit.box(_basket_node, Vector3(0.4, 0.2, 0.03), Vector3(0, -0.14, sx * 0.14), red)
	Kit.torus(_basket_node, 0.12, 0.14, Vector3(0, 0.0, 0), Kit.mat("2a2a2a", 0.5), Vector3(0, 0, PI / 2))
	owner_model.hand.add_child(_basket_node)
	_basket_node.position = Vector3(0, -0.02, 0)
	_sfx("tik", -6.0)
	ui.toast("Sepeti aldın. Raflardan ürünleri seç, sonra kasada öde.")
	_update_context()


func _put_in_basket(id: String) -> void:
	if _basket_node == null:
		return
	_cart[id] = int(_cart.get(id, 0)) + 1
	var it := _item(id)
	# Sepette gorunsun: renkli kucuk kutu
	var n := _cart_count() - 1
	var col: String = ["c8322b", "2f62a8", "f2c230", "3f8f4a", "ffffff", "e07b1f", "7a4a2b"][n % 7]
	Kit.box(_basket_node, Vector3(0.11, 0.1 + (n % 3) * 0.03, 0.08), Vector3(-0.13 + (n % 4) * 0.085, -0.16 + (n / 4) * 0.06, -0.06 + (n % 2) * 0.12), Kit.mat(col, 0.5))
	owner_model.act("pet", 0.6)
	_sfx("tik", -4.0, 1.2)
	ui.toast("%s sepette · Toplam %d ₺" % [it[1], _cart_total()])
	_update_context()


func _pay_cart() -> void:
	var total := _cart_total()
	if state.d["coins"] < total:
		ui.toast("Paran yetmiyor! %d ₺ eksik. Bir şeyi rafa geri bırak." % (total - state.d["coins"]))
		var last: String = _cart.keys()[_cart.size() - 1]
		_cart[last] = int(_cart[last]) - 1
		if _cart[last] <= 0:
			_cart.erase(last)
		return
	state.d["coins"] -= total
	for id in _cart:
		var it := _item(id)
		var k: String = it[3]
		if k == "food":
			state.d["foods"][id] = int(state.d["foods"].get(id, 0)) + int(_cart[id])
		elif k == "bag":
			var bag: Dictionary = state.d.get("bag", {})
			bag[it[1]] = int(bag.get(it[1], 0)) + int(_cart[id])
			state.d["bag"] = bag
	var items := _cart.duplicate()
	_cart.clear()
	if _basket_node:
		_basket_node.queue_free()
		_basket_node = null
	state.changed.emit()
	state.save_game()
	_on_bought(items, total)
	_update_context()


func _on_bought(items: Dictionary, total: int) -> void:
	_sfx("kasa", -4.0)
	state.count("shop")
	# Hemen etki eden urunler (hayvana)
	var kind: String = _shop.kind if _shop else "market"
	for id in items:
		for it in ui.SHOP_ITEMS.get(kind, []):
			if it[0] == id and String(it[3]).begins_with("pet:"):
				var parts: PackedStringArray = String(it[3]).split(":")
				for k in agents:
					state.add_need(k, parts[1], float(parts[2]) * int(items[id]))
				_pet_voice(_active().kind, true)
	ui.toast("Fiş: %d ürün · %d ₺ · Teşekkürler, yine bekleriz!" % [items.values().reduce(func(a, b): return a + b, 0), total])


## Cantadan bir sey kullan: ye / ic.
func _use_item(name: String) -> void:
	owner_model.act("wave", 0.8)
	var a := _active()
	var pn: String = state.pet(a.kind)["name"]
	match name:
		"Çikolata":
			ui.toast("Çikolatayı yedin. %s de istedi ama çikolata ona zararlı, vermedin!" % pn)
		"Dondurma":
			ui.toast("Dondurma çok iyi geldi!")
			for k in agents:
				state.add_need(k, "fun", 8.0)
		"Su":
			ui.toast("Su içtin. %s'e de biraz verdin." % pn)
			for k in agents:
				state.add_need(k, "hunger", 5.0)
		"Simit", "Ekmek":
			ui.toast("%s yedin. %s kırıntıları kaptı!" % [name, pn])
			_pet_voice(a.kind)
		_:
			ui.toast("%s kullanıldı." % name)


# ---------------------------------------------------------------- saglik ve veteriner

const ILLNESSES := [["Öksürük", "Hapşırıyor ve öksürüyor"], ["Mide bozukluğu", "Yemek istemiyor"],
	["Pire", "Sürekli kaşınıyor"], ["Halsizlik", "Hiç enerjisi yok"]]
var _sick_t := 30.0
var _sneeze_t := 4.0


## Ihtiyaclar uzun sure dusukse (kirli, ac, yorgun) hayvan hastalanabilir; hastayken ihtiyaclar hizli duser.
func _update_health(dt: float) -> void:
	if _mode != "play":
		return
	_sick_t -= dt
	for k in agents:
		var p: Dictionary = state.pet(k)
		var sick: String = p.get("sick", "")
		if sick != "":
			state.add_need(k, "energy", -0.05 * dt)
			state.add_need(k, "fun", -0.04 * dt)
			_sneeze_t -= dt
			if _sneeze_t <= 0.0 and k == state.d["active"]:
				_sneeze_t = randf_range(6.0, 12.0)
				var a: Node3D = agents[k]
				_voice_at(a, "kedi" if k == "kedi" else "kopek", false)
				_say(a, "hapşu!" if sick == "Öksürük" else ("*kaşınıyor*" if sick == "Pire" else "..."))
		elif _sick_t <= 0.0:
			var low := float(p["clean"]) < 25.0 or float(p["hunger"]) < 20.0 or float(p["energy"]) < 15.0
			if (low and randf() < 0.35) or randf() < 0.01:
				var ill: Array = ILLNESSES[randi() % ILLNESSES.size()]
				p["sick"] = ill[0]
				state.save_game()
				ui.toast("%s hasta görünüyor: %s. Veterinere götür! (Telefon > Veteriner)" % [p["name"], ill[1].to_lower()])
	if _sick_t <= 0.0:
		_sick_t = 90.0


## Muayene: teshis, tedavi ve asilar.
func _open_vet() -> void:
	var a := _active()
	var p: Dictionary = state.pet(a.kind)
	var sick: String = p.get("sick", "")
	var vac: Dictionary = p.get("vaccines", {})
	var sub := "%s · %s" % [p["name"], ("Teşhis: " + sick) if sick != "" else "Sağlıklı görünüyor"]
	var body: VBoxContainer = ui._open_page("MUAYENE", sub)
	# Hayvan masaya cikar
	a.place(_shop.w2(_shop.table_local))
	a.position.y = _shop.global_position.y + 0.93
	a.set_process(false)
	a.model.speed = 0.0
	ui._modal.tree_exiting.connect(func():
		if is_instance_valid(a):
			a.set_process(true)
			a.place(_owner_pos() + Vector2(0.8, 0.6)))
	ui._menu_item(body, ("TEDAVİ ET  ·  60 ₺" if sick != "" else "GENEL KONTROL  ·  30 ₺"), func():
		var cost := 60 if sick != "" else 30
		if not state.spend(cost):
			ui.toast("Paran yetmiyor.")
			return
		p.erase("sick")
		for n in state.NEEDS:
			state.add_need(a.kind, n, 15.0)
		p["checkup"] = Time.get_date_string_from_system()
		state.save_game()
		_pet_voice(a.kind, true)
		_hearts(a.position)
		ui.close_modal()
		ui.toast("Veteriner: \"%s\"" % ("İlacını verdim, birkaç günde toparlanır. Geçmiş olsun!" if sick != "" else "Turp gibi! Aşılarını aksatmayın.")))
	for v in [["Kuduz", 25], ["Karma", 25], ["İç-Dış Parazit", 20]]:
		var vn: String = v[0]
		var cost: int = v[1]
		var done := vac.has(vn)
		ui._menu_item(body, ("%s AŞISI  ·  YAPILDI ✓" % vn.to_upper()) if done else ("%s AŞISI  ·  %d ₺" % [vn.to_upper(), cost]), func():
			if done:
				ui.toast("%s aşısı %s tarihinde yapıldı." % [vn, vac[vn]])
				return
			if not state.spend(cost):
				ui.toast("Paran yetmiyor.")
				return
			vac[vn] = Time.get_date_string_from_system()
			p["vaccines"] = vac
			state.save_game()
			_pet_voice(a.kind)
			ui.toast("%s aşısı yapıldı. %s biraz mızmızlandı ama ödül bisküvisiyle unuttu." % [vn, p["name"]])
			_open_vet())
	ui._menu_item(body, "AŞI KARNESİ", func():
		var lines := []
		for vn in ["Kuduz", "Karma", "İç-Dış Parazit"]:
			lines.append("%s: %s" % [vn, vac.get(vn, "yapılmadı")])
		lines.append("Son kontrol: %s" % p.get("checkup", "yok"))
		ui.toast("  ·  ".join(lines)))
	ui._menu_item(body, "GERİ", func(): ui.close_modal())
	ui._focus_first(body)


# ---------------------------------------------------------------- isler (para kazanma)

var _job := {}          # {type, stage, target, client, dog, box, t, pay, base}
var _job_label: Label
const DOG_NAMES := ["Karabaş", "Çomar", "Boncuk", "Fındık", "Zeytin", "Paşa", "Tarçın", "Duman"]
const CLIENTS := ["Ayşe Teyze", "Mehmet Bey", "Zeynep Hanım", "Ali Amca", "Elif", "Hasan Bey"]


## Belirtme hali eki (unlu uyumu): Karabas -> Karabas'i, Boncuk -> Boncuk'u, Pasa -> Pasa'yi.
func _acc(name: String) -> String:
	var last := ""
	for ch in name.to_lower():
		if ch in "aeıioöuü":
			last = ch
	var v: String = {"a": "ı", "ı": "ı", "e": "i", "i": "i", "o": "u", "u": "u", "ö": "ü", "ü": "ü"}.get(last, "ı")
	var ends_vowel := name.to_lower().right(1) in ["a", "e", "ı", "i", "o", "ö", "u", "ü"]
	return name + "'" + ("y" if ends_vowel else "") + v


## En yakin sokagin adi (adres yazmak icin).
func _street_name(p: Vector2) -> String:
	var best := ""
	var bd := 1e9
	for r in ParkMap.data["roads"]:
		if r["name"] == "":
			continue
		var ids: Array = r["n"]
		for i in ids.size() - 1:
			var d := ParkMap.seg_dist(p, ParkMap.nodes[int(ids[i])], ParkMap.nodes[int(ids[i + 1])])
			if d < bd:
				bd = d
				best = r["name"]
	return best


## Rastgele bir apartman kapisi: [konum, adres], oyuncudan min..max metre uzakta.
func _random_door(min_d: float, max_d: float) -> Array:
	var me := _owner_pos()
	var cands: Array = []
	for b in ParkMap.data["buildings"]:
		var dr = b.get("door")
		if dr == null or not (dr is Array) or dr.size() < 4:
			continue
		var p := Vector2(dr[0], dr[1]) + Vector2(dr[2], dr[3]) * 1.5
		var d := p.distance_to(me)
		if d > min_d and d < max_d and ParkMap.inside_bounds(p, 10.0):
			cands.append([p, "%s No: %s" % [_street_name(p), b["no"] if b["no"] != "" else str(randi() % 60 + 1)]])
	return cands[randi() % cands.size()] if not cands.is_empty() else []


func _open_jobs() -> void:
	if not _job.is_empty():
		var body: VBoxContainer = ui._open_page("İŞ", _job_text())
		ui._menu_item(body, "İŞİ BIRAK", func():
			_end_job(false, "İşi bıraktın.")
			ui.close_modal())
		ui._menu_item(body, "GERİ", func(): ui.close_modal())
		ui._focus_first(body)
		return
	var body: VBoxContainer = ui._open_page("İŞ BUL", "Para kazan: işi seç, haritadaki noktaya git")
	ui._menu_item(body, "KÖPEK GEZDİR  ·  40–60 ₺", func():
		ui.close_modal()
		_start_dog_walk())
	ui._menu_item(body, "KURYE (MOTOR)  ·  25–70 ₺", func():
		ui.close_modal()
		_start_courier())
	ui._menu_item(body, "GERİ", func(): ui.close_modal())
	ui._focus_first(body)


func _job_text() -> String:
	if _job.is_empty():
		return ""
	var left := int(maxf(_job["t"], 0.0))
	var tm := "%d:%02d" % [left / 60, left % 60]
	match _job["type"]:
		"dog":
			return ("%s parka götür" % _acc(_job["name"]) if _job["stage"] == "go" else "%s sahibine (%s) geri getir" % [_acc(_job["name"]), _job["client_name"]]) + "  ·  " + tm
		"courier":
			return ("Paketi al: %s" if _job["stage"] == "pickup" else "Teslim et: %s") % _job["addr"] + "  ·  " + tm
	return ""


## Komsunun kopegini gezdir: kopek seni izler, parka goturup sahibine geri getir.
func _start_dog_walk() -> void:
	var me := _owner_pos()
	var cpos: Vector2 = world.resolve(me + Vector2(2.5, 1.0), 0.4, me)
	var client := Npc.new()
	var cv := PersonModel.new()
	cv.kind = "kadin" if randi() % 2 == 0 else "erkek"
	cv.tint = Color(["8a5a8a", "3f6fb5", "c94f4f", "4f8f5a"][randi() % 4])
	client.visual = cv
	client.add_child(cv)
	client.roam_center = cpos
	client.roam_radius = 0.1
	add_child(client)
	client.place(cpos)
	client.hold = 1e6
	client.hold_face = me
	var dog := _npc_pet("kopek", Color(["c9a070", "3a3330", "f4f4f4", "8a6a4a", "e8d6b0"][randi() % 5]), randf_range(0.85, 1.15))
	dog.follow = owner_node
	dog.place(cpos + Vector2(0.8, 0.4))
	var tgt := ParkMap.spot("oyun_alani") if ParkMap.has_spot("oyun_alani") else Vector2.ZERO
	if tgt == Vector2.ZERO or tgt.distance_to(me) < 60.0:
		var dd := _random_door(120.0, 260.0)
		tgt = dd[0] if not dd.is_empty() else me + Vector2(120, 0)
	var nm: String = DOG_NAMES[randi() % DOG_NAMES.size()]
	var cn: String = CLIENTS[randi() % CLIENTS.size()]
	_job = {"type": "dog", "stage": "go", "target": tgt, "client": client, "client_pos": cpos, "dog": dog,
		"name": nm, "client_name": cn, "t": 300.0, "pay": 40 + int(tgt.distance_to(me) / 15.0)}
	_job["pay"] = mini(int(_job["pay"]), 60)
	_say(client, "%s parka götürür müsün?" % _acc(nm))
	_set_nav(tgt, "Gezdirme: Park")
	ui.toast("%s, köpeği %s sana emanet etti. Parka götür, geri getir." % [cn, nm])


## Kurye: motor/scooter ile dukkandan paketi al, adrese teslim et.
func _start_courier() -> void:
	var me := _owner_pos()
	var pick := Vector2.INF
	var pick_name := ""
	var bd := 1e9
	for sp in world.shop_spots:
		var d: float = (sp["pos"] as Vector2).distance_to(me)
		if d < bd and d > 15.0:
			bd = d
			pick = sp["pos"]
			pick_name = sp["name"]
	if pick == Vector2.INF:
		pick = me + Vector2(30, 0)
		pick_name = "Dükkan"
	var dd := _random_door(200.0, 520.0)
	if dd.is_empty():
		ui.toast("Şu an teslimat yok.")
		return
	_job = {"type": "courier", "stage": "pickup", "target": pick, "addr": pick_name, "drop": dd[0], "drop_addr": dd[1],
		"t": 360.0, "pay": 25 + int(pick.distance_to(dd[0]) / 12.0)}
	_job["pay"] = mini(int(_job["pay"]), 70)
	_set_nav(pick, "Paket: " + pick_name)
	ui.toast("Kurye işi: paket hazır, %s. Motorla daha hızlı!" % pick_name)


func _update_job(dt: float) -> void:
	if _job_label == null:
		_job_label = ui._fx_label(ui.hud, "", ui.F_BODY, 26, Color.WHITE, 7)
		_job_label.position = Vector2(26, 104)
		_job_label.size = Vector2(760, 40)
	_job_label.visible = not _job.is_empty() and ui.hud.visible
	if _job.is_empty():
		return
	_job["t"] -= dt
	_job_label.text = "▶  " + _job_text()
	_job_label.add_theme_color_override("font_color", Color("ff6b6b") if _job["t"] < 30.0 else Color.WHITE)
	var me := _owner_pos()
	match _job["type"]:
		"dog":
			if _job["stage"] == "go" and me.distance_to(_job["target"]) < 9.0:
				_job["stage"] = "back"
				_set_nav(_job["client_pos"], _job["client_name"])
				_pet_voice("kopek")
				ui.toast("%s parkı çok sevdi! Şimdi sahibine geri götür." % _job["name"])
			elif _job["stage"] == "back" and me.distance_to(_job["client_pos"]) < 3.5:
				_end_job(true, "%s: \"Çok teşekkürler, al bakalım!\"" % _job["client_name"])
		"courier":
			if _job["stage"] == "pickup" and me.distance_to(_job["target"]) < 5.0:
				_job["stage"] = "drop"
				_job["target"] = _job["drop"]
				_job["addr"] = _job["drop_addr"]
				_set_nav(_job["drop"], _job["drop_addr"])
				_courier_box(true)
				_sfx("tik", -4.0)
				ui.toast("Paketi aldın. Adres: %s" % _job["drop_addr"])
			elif _job["stage"] == "drop" and me.distance_to(_job["drop"]) < 6.0:
				_end_job(true, "Teslim edildi! Müşteri memnun.")
	if not _job.is_empty() and _job["t"] <= 0.0:
		_end_job(false, "Süre doldu! İş iptal oldu.")


## Kuryede motorun arkasinda turuncu teslimat cantasi.
func _courier_box(on: bool) -> void:
	if _job.has("box") and is_instance_valid(_job["box"]):
		_job["box"].queue_free()
		_job.erase("box")
	if not on:
		return
	var holder: Node3D = _ride if _ride != null and not RIDES[_ride.get_meta("kind")]["hide"] else owner_node
	var b := Node3D.new()
	holder.add_child(b)
	if holder == owner_node:
		b.position = Vector3(0, 1.25, 0.22)
		Kit.box(b, Vector3(0.36, 0.4, 0.22), Vector3.ZERO, Kit.mat("e8622c", 0.6))
	else:
		b.position = Vector3(0, 1.15, 0.55)
		Kit.box(b, Vector3(0.42, 0.42, 0.42), Vector3.ZERO, Kit.mat("e8622c", 0.6))
	Kit.box(b, Vector3(0.2, 0.08, 0.005), Vector3(0, 0.05, 0.23 if holder != owner_node else 0.115), Kit.mat("ffffff", 0.5))
	_job["box"] = b


func _end_job(ok: bool, msg: String) -> void:
	if _job.is_empty():
		return
	var job := _job
	_job = {}
	if job.has("box") and is_instance_valid(job["box"]):
		job["box"].queue_free()
	if job["type"] == "dog":
		var dog: Node3D = job["dog"]
		_npc_pets.erase(dog)
		var client: Node3D = job["client"]
		if is_instance_valid(dog):
			dog.follow = client
		get_tree().create_timer(6.0).timeout.connect(func():
			if is_instance_valid(dog):
				dog.queue_free()
			if is_instance_valid(client):
				client.queue_free())
		if is_instance_valid(client):
			client.hold = 0.0
			client.graph_node = ParkMap.nearest_node(job["client_pos"])
	_nav = Vector2.INF
	minimap.route = []
	if ok:
		var pay: int = job["pay"] + (10 if job["t"] > 120.0 else 0)
		state.d["coins"] += pay
		state.count("job")
		state.changed.emit()
		state.save_game()
		_sfx("para", -4.0)
		ui.toast("%s  +%d ₺%s" % [msg, pay, "  (hızlı teslim bonusu!)" if job["t"] > 120.0 else ""])
	else:
		ui.toast(msg)


## Telefon: arabani yanina cagir## Telefon: arabani yanina cagir, taksi/dolmus cagir, eve yol tarifi.
func _open_phone() -> void:
	var body: VBoxContainer = ui._open_modal("Telefon", 120, 120)
	body.add_theme_constant_override("separation", 10)
	UiKit.button(body, "İş bul (para kazan)", "coin", func():
		ui.close_modal()
		_open_jobs(), UiKit.SOFT, UiKit.BROWN, Vector2(0, 68), 24, 28)
	if world.vet_pos != Vector2.INF:
		UiKit.button(body, "Veteriner (yol tarifi)", "plus", func():
			ui.close_modal()
			_set_nav(world.vet_pos, "Veteriner"), UiKit.SOFT, UiKit.BROWN, Vector2(0, 68), 24, 28)
	UiKit.button(body, "Arabamı yanıma getir", "play", func():
		ui.close_modal()
		_summon_my_car(), UiKit.SOFT, UiKit.BROWN, Vector2(0, 68), 24, 28)
	UiKit.button(body, "Taksi çağır", "star", func():
		ui.close_modal()
		_call_taxi("taksi"), UiKit.SOFT, UiKit.BROWN, Vector2(0, 68), 24, 28)
	UiKit.button(body, "Dolmuş çağır", "star", func():
		ui.close_modal()
		_call_taxi("dolmus"), UiKit.SOFT, UiKit.BROWN, Vector2(0, 68), 24, 28)
	if ParkMap.zone == "":
		UiKit.button(body, "Eve yol tarifi", "home", func():
			ui.close_modal()
			_set_nav(HOME_DOOR, "Evim"), UiKit.SOFT, UiKit.BROWN, Vector2(0, 68), 24, 28)


## Oyuncuya en yakin yol kenari: [konum, yon acisi, dugum]
func _curb_near(p: Vector2) -> Array:
	var best := -1
	var bd := 1e18
	for i in ParkMap.nodes.size():
		if ParkMap.road_next[i].size() > 0:
			var d := ParkMap.nodes[i].distance_squared_to(p)
			if d < bd:
				bd = d
				best = i
	if best < 0:
		return []
	var a := ParkMap.nodes[best]
	var nb: int = ParkMap.road_next[best][0]
	var b := ParkMap.nodes[nb]
	var dir := (b - a).normalized()
	var w := ParkMap.road_width(best, nb)
	var q := a + dir * minf(5.0, a.distance_to(b) * 0.4) + Vector2(-dir.y, dir.x) * maxf(w * 0.5 - 1.0, 0.0)
	return [q, atan2(-dir.x, -dir.y), best]


func _summon_my_car() -> void:
	if _ride != null:
		ui.toast("Zaten araçtasın.")
		return
	var car: Node3D = null
	for r in _rides:
		if r.get_meta("kind") == "araba":
			car = r
	var c := _curb_near(_owner_pos())
	if car == null or c.is_empty():
		ui.toast("Araban bulunamadı.")
		return
	car.position = Vector3(c[0].x, ParkMap.walk_height(c[0]), c[0].y)
	car.rotation = Vector3(0, c[1], 0)
	_set_nav(c[0], "Arabam")
	ui.toast("Araban %d m ötede, yol kenarında seni bekliyor." % int(_owner_pos().distance_to(c[0])))


func _call_taxi(model: String) -> void:
	var c := _curb_near(_owner_pos())
	if c.is_empty():
		return
	var best: Node3D = null
	for car in _cars:
		if _car_model(car) == model and car.is_processing():
			best = car
			break
	if best == null:
		ui.toast("Şu an boşta %s yok." % ("dolmuş" if model == "dolmus" else "taksi"))
		return
	best.summon(c[2], 90.0)
	_set_nav(ParkMap.nodes[c[2]], "Taksi" if model == "taksi" else "Dolmuş")
	ui.toast("%s geldi! Yanına git ve bin (önce haritadan hedef seç)." % ("Taksi" if model == "taksi" else "Dolmuş"))


## Evdeki gomme dolap: kiyafet sec, aninda giy.
func _open_closet() -> void:
	var body: VBoxContainer = ui._open_modal("Dolap · Ne giysem?", 90, 90)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	for i in OUTFITS.size():
		var of: Array = OUTFITS[i]
		var idx := i
		var b := UiKit.button(grid, of[0], "", func():
			_wear_outfit(idx)
			ui.close_modal(), Color(of[1]).lerp(Color.WHITE, 0.15), Color.BLACK if Color(of[1]).get_luminance() > 0.5 else Color.WHITE,
			Vector2(300, 64), 20, 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _wear_outfit(i: int) -> void:
	var of: Array = OUTFITS[i]
	owner_model.set_outfit(Color(of[1]), Color(of[2]), of[3], Color(of[4]) if of[4] != "" else Color(0, 0, 0, 0))
	owner_model.act("wave", 0.8)
	state.d["outfit"] = i
	state.count("outfit")
	state.save_game()
	ui.toast("%s giydin. Yakıştı!" % of[0])


## Tahterevalli (bir ucta sen, obur ucta hayvanin) ve salincak.
func _start_play_ride(pr: Dictionary) -> void:
	_play_ride = pr
	_play_t = 0.0
	_moving = false
	_queue.clear()
	owner_model.speed = 0.0
	owner_model.riding = "otur"
	owner_model.ride_lean = 0.05
	ui._actions.visible = false
	if pr["kind"] == "tahterevalli":
		state.count("seesaw")
		var a := _active()
		a.set_process(false)
		a.set_physics_process(false)
		ui.toast("%s öbür uca atladı!" % state.pet(a.kind)["name"])
		_pet_voice(a.kind)
	_update_context()


func _end_play_ride() -> void:
	if _play_ride.is_empty():
		return
	var pr := _play_ride
	_play_ride = {}
	(pr["pivot"] as Node3D).rotation = Vector3.ZERO
	owner_model.riding = ""
	owner_model.grips = []
	owner_model.position = Vector3.ZERO
	owner_node.rotation = Vector3(0, owner_node.rotation.y, 0)
	var out: Vector2 = pr["pos"] + (Vector2(-2.6, 0.8) if pr["kind"] == "tahterevalli" else Vector2(0, 1.4))
	_place_owner(out)
	for k in agents:
		agents[k].set_process(true)
		agents[k].set_physics_process(true)
		agents[k].place(out + Vector2(1.0, 0.6))
	ui._actions.visible = true
	_update_context()


func _update_play_ride(dt: float) -> void:
	if _play_ride.is_empty():
		return
	if ui.stick.length() > 0.5 and _play_t > 0.8:
		_end_play_ride()
		return
	_play_t += dt
	var pv: Node3D = _play_ride["pivot"]
	var ramp := clampf(_play_t / 2.0, 0.0, 1.0)
	if _play_ride["kind"] == "tahterevalli":
		pv.rotation.z = sin(_play_t * 1.7) * 0.26 * ramp
		var xf := pv.global_transform
		owner_node.global_position = xf * Vector3(-1.6, 0.04, 0)
		owner_node.rotation = Vector3(0, -PI / 2, 0)
		owner_model.position = Vector3(0, 0.09 - owner_model.hips_height(), 0)
		owner_model.grips = [xf * Vector3(-1.3, 0.42, 0.18), xf * Vector3(-1.3, 0.42, -0.18)]
		var a := _active()
		a.global_position = xf * Vector3(1.55, 0.04, 0)
		a.rotation.y = PI / 2
		if Engine.get_process_frames() % 200 == 0:
			_pet_voice(a.kind)
	else:
		pv.rotation.x = sin(_play_t * 2.1) * 0.6 * ramp
		var xf := pv.global_transform
		owner_node.global_position = xf * Vector3(0, -1.66, 0.0)
		owner_node.rotation = Vector3(pv.rotation.x, 0, 0)
		owner_model.position = Vector3(0, 0.09 - owner_model.hips_height(), 0.1)
		owner_model.grips = [xf * Vector3(-0.2, -1.15, 0.0), xf * Vector3(0.2, -1.15, 0.0)]


## Ziplama: gorsel olarak yukari; konum yerde kalir (engeller ayni).
func _jump() -> void:
	if _jump_h > 0.0 or _ride != null or _bus_ride != null:
		return
	_jump_v = 5.6
	_jump_h = 0.001
	owner_model.airborne = true


func _on_command(cmd: String) -> void:
	if cmd.begins_with("shop_take:"):
		_put_in_basket(cmd.substr(10))
		return
	if cmd.begins_with("use:"):
		_use_item(cmd.substr(4))
		return
	if cmd == "jump":
		_jump()
		return
	var a := _active()
	var p: Dictionary = state.pet(a.kind)
	if cmd.begins_with("feed:"):
		_do_feed(cmd.trim_prefix("feed:"))
		return
	match cmd:
		"bus":
			_enter_bus()
		"busexit":
			_exit_bus()
		"metro":
			_open_metro()
		"home_in":
			_enter_home()
		"home_out":
			_exit_home()
		"drive":
			_enter_ride()
		"playride":
			var o := _owner_pos()
			for pr in world.play_rides:
				if o.distance_to(pr["pos"]) < 2.0:
					_start_play_ride(pr)
					break
		"playexit":
			_end_play_ride()
		"phone":
			_open_phone()
		"shop_in":
			for sp in world.shop_spots:
				if _owner_pos().distance_to(sp["pos"]) < 2.6 and sp.has("kind"):
					_enter_shop(sp)
					break
		"shop_out":
			if not _cart.is_empty():
				ui.toast("Önce kasada ödemelisin! (%d ürün, %d ₺)" % [_cart_count(), _cart_total()])
			else:
				_exit_shop()
		"shop_basket":
			_take_basket()
		"vet_desk":
			ui.toast("Hoş geldiniz! Muayene için masanın yanına geçin. Muayene 30 ₺, aşı 25 ₺.")
		"vet_exam":
			_open_vet()
		"shop_pay":
			_pay_cart()
		"shop_buy":
			_shop_buy()
		"wardrobe":
			_open_closet()
		"taxi":
			var tx := _nearest_taxi()
			if tx:
				_board_taxi(tx)
		"exit":
			_exit_ride()
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
			_pet_voice(a.kind)
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
			a.wash(world.pool_pos)
		"bed":
			a.place(world.kennel_pos + Vector2(1.0, 1.6))
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
				state.count("npcplay")
				_near_npc.play_mate = a
				_near_npc.play_t = 11.0
				if _near_npc.world == null:
					_near_npc.world = world
				# Hayvanin sahibi durup izler
				var own = _near_npc.follow
				if own and "hold" in own:
					own.hold = 12.0
					own.hold_face = Vector2(_near_npc.position.x, _near_npc.position.z)
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
	_pet_voice(a.kind, true)
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


# ---------------------------------------------------------------- arac surme

const VEHICLE_FLIP := {"polo": true, "bisiklet": true, "taksi": true, "dolmus": true}      # modelin onu ters gelenler
var _rides: Array[Node3D] = []       # binilebilen araclar
var _ride: Node3D                    # su an surulen arac
var _drive_speed := 0.0
var _last_speed := 0.0
var _steer := 0.0
var _fps := false          # surerken birinci sahis kamera
var _fps_pitch := 0.0
var _jump_h := 0.0
var _blink_t := 0.0
var _cyclists: Array = []
var _in_water := false
var _play_ride: Dictionary = {}
## Dolaptaki kiyafetler: [ad, tisort, desen rengi, desen (0 duz, 1 cizgili, 2 kareli), pantolon ("" = kot)]
const OUTFITS := [
	["Günlük (yeşil)", "3f8f8a", "ffffff", 0, ""], ["Lacivert tişört", "34507a", "ffffff", 0, ""],
	["Denizci çizgili", "f2f2f2", "1f3a6b", 1, "e8e2d4"], ["Kırmızı kareli gömlek", "b8322b", "2a2a2a", 2, "3a3d42"],
	["Spor (gri eşofman)", "8a8f96", "ffffff", 0, "4a4d52"], ["Sarı yazlık", "f2c230", "ffffff", 0, "e8e2d4"],
	["Siyah şık", "1d1e21", "ffffff", 0, "1d1e21"], ["Pembe çizgili", "f2a2b8", "ffffff", 1, ""],
	["Haki kareli", "6b7a4a", "c9b98a", 2, "7a6a4a"], ["Beyaz klasik", "f4f4f0", "ffffff", 0, "2f3a4a"],
]
var _play_t := 0.0
var _wet_t := 0.0
var _drips: CPUParticles3D
var _jump_v := 0.0
var _fps_yaw := 0.0     # araç icinde bas cevirme (0 = ileri); birakinca yavasca ortalanir
var _cockpit: Node3D
var _cam_btn: Button
var minimap: Control
var _nav := Vector2.INF       # navigasyon hedefi
var _nav_t := 0.0
var _exit_btn: Button
var _engine: AudioStreamPlayer
var _cam_last := Transform3D()
var _cam_blend := 0.0      # > 0: kamera gecisi yumusatiliyor
var _rider_pet: Node3D     # iki tekerlide arkada oturan hayvan
var _taxi: Node3D          # yolcu olarak binilen taksi / dolmus
var _taxi_path := PackedVector2Array()
var _taxi_i := 0
var _taxi_speed := 0.0
var _taxi_fare := 0

## Arac ayarlari: en yuksek hiz (m/sn), ivme, fren, direksiyon donus hizi, en buyuk teker acisi, dingil arasi,
## carpisma yaricapi, surucu gizlenir mi, sele (yukseklik, arac merkezine gore arkada), one egilme,
## gidon tutaclari, arkadaki hayvanin yeri, motor sesi perdesi.
const RIDES := {
	"araba": {"max": 15.0, "acc": 3.4, "brake": 9.0, "steer": 1.6, "lock": 0.55, "base": 2.6, "r": 1.15, "hide": true,
		"seat": Vector3.ZERO, "engine": 1.0, "ad": "Arabaya Bin"},
	"scooter": {"max": 11.0, "acc": 2.2, "brake": 7.0, "steer": 1.2, "lock": 0.45, "base": 1.3, "r": 0.5, "hide": false,
		"seat": Vector3(0, 0.8, 0.26), "lean": 0.5, "engine": 1.6, "ad": "Scooter'a Bin",
		"grip": Vector3(0.25, 1.0, -0.36), "pet": Vector3(0, 0.84, 0.66)},
	"motosiklet": {"max": 16.0, "acc": 2.8, "brake": 8.0, "steer": 1.0, "lock": 0.4, "base": 1.45, "r": 0.55, "hide": false,
		"seat": Vector3(0, 0.8, 0.3), "lean": 0.78, "engine": 1.35, "ad": "Motosiklete Bin",
		"grip": Vector3(0.34, 1.0, -0.44), "pet": Vector3(0, 0.9, 0.72)},
	"bisiklet": {"max": 6.5, "acc": 1.5, "brake": 6.0, "steer": 1.3, "lock": 0.5, "base": 1.1, "r": 0.45, "hide": false,
		"seat": Vector3(0, 0.97, 0.2), "lean": 0.6, "engine": 0.0, "ad": "Bisiklete Bin",
		"grip": Vector3(0.3, 1.02, -0.36), "pet": Vector3(0, 0.82, 0.58)},
}


func _vehicle(path: String, length: float, flip := false) -> Node3D:
	return world.vehicle(path, length, flip)


func _spawn_rides() -> void:
	for r in _rides:
		r.queue_free()
	_rides.clear()
	var start := ParkMap.spot("baslangic")
	var best := -1
	var best_d := 1e9
	for i in ParkMap.nodes.size():
		if ParkMap.road_next[i].size() > 0:
			var d := ParkMap.nodes[i].distance_squared_to(start)
			if d < best_d:
				best_d = d
				best = i
	if best >= 0:
		var a := ParkMap.nodes[best]
		var b: Vector2 = ParkMap.nodes[ParkMap.road_next[best][0]]
		var dir := (b - a).normalized()
		var w := ParkMap.road_width(best, ParkMap.road_next[best][0])
		var p := a + dir * 6.0 + Vector2(-dir.y, dir.x) * maxf(w * 0.5 - 1.0, 0.0)
		# Oyuncunun arabasi: 2015 Polo (kendi modeli); yoksa boyali hatchback
		var car: Node3D = world.vehicle("res://assets/models/polo.glb", 3.97, bool(VEHICLE_FLIP.get("polo", false)))
		if car == null:
			car = world.vehicle("res://assets/models/hatchback.glb", 4.1)
			if car:
				_paint(car, Color("b8322c"))
		if car == null:
			car = world.make_car(Color("c23b32"))
		else:
			_dress_polo(car)
		car.set_meta("kind", "araba")
		car.set_meta("blinkers", Car.add_blinkers(car))
		_place_ride(car, p, atan2(-dir.x, -dir.y))
	# Bahce kapisinin onunde bisiklet ve scooter
	for spec in [["bisiklet", "res://assets/models/bisiklet.glb", 1.75, Vector2(1.8, -3.6)], ["scooter", "res://assets/models/scooter.glb", 1.8, Vector2(2.2, 3.6)],
			["motosiklet", "res://assets/models/motosiklet.glb", 2.05, Vector2(2.2, 6.4)]]:
		var v := _vehicle(spec[1], spec[2], bool(VEHICLE_FLIP.get(spec[0], false)))
		if v == null:
			continue
		v.set_meta("kind", spec[0])
		var p: Vector2 = start + spec[3]
		for i in 12:
			if world.is_free(p, 0.6):
				break
			p += Vector2(0.8, 0.0)
		_place_ride(v, p, PI)


## Govde boyasini degistirir (lastik ve camlar koyu oldugu icin carpim az etkiler).
func _paint(v: Node3D, c: Color) -> void:
	for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D:
				var mm: BaseMaterial3D = m.duplicate()
				mm.albedo_color = c.lerp(Color.WHITE, 0.15) * 1.6
				mi.set_surface_override_material(i, mm)


## Polo: on/arka "33 OA 2003" plakasi ve marka logolarinin uzerine uydurma amblem (model uzayinda,
## govde 1.0 birim uzunlukta; +Z on).
func _dress_polo(car: Node3D) -> void:
	var body: Node3D = null
	for mi in car.find_children("tripo_node*", "MeshInstance3D", true, false):
		body = mi
	if body == null:
		return
	const U := 1.0 / 3.97                  # 1 metre, model biriminde
	for spec in [[Vector3(0, 0.141, 0.504), 0.0], [Vector3(0, 0.221, -0.475), PI]]:
		var plate := Node3D.new()
		plate.position = spec[0]
		plate.rotation.y = spec[1]
		body.add_child(plate)
		Kit.box(plate, Vector3(0.53, 0.12, 0.012) * U, Vector3.ZERO, Kit.mat("111111", 0.5))
		Kit.box(plate, Vector3(0.51, 0.10, 0.014) * U, Vector3.ZERO, Kit.mat("f6f6f2", 0.4))
		Kit.box(plate, Vector3(0.045, 0.10, 0.016) * U, Vector3(-0.232 * U, 0, 0), Kit.mat("1f4fa8", 0.4))
		var tr := Label3D.new()
		tr.text = "TR"
		tr.font_size = 32
		tr.pixel_size = 0.0008 * U
		tr.modulate = Color.WHITE
		tr.position = Vector3(-0.232 * U, -0.025 * U, 0.009 * U)
		plate.add_child(tr)
		var num := Label3D.new()
		num.text = "33 OA 2003"
		num.font_size = 96
		num.pixel_size = 0.00092 * U
		num.modulate = Color("111111")
		num.outline_size = 0
		num.position = Vector3(0.02 * U, 0, 0.009 * U)
		plate.add_child(num)
	# Logolarin uzeri: uydurma amblem (koyu yuvarlak, gumus halka)
	var chrome := Kit.mat("c9ccd0", 0.25)
	chrome.metallic = 0.8
	for spec in [[Vector3(0, 0.176, 0.494), 0.0, "151618"], [Vector3(0, 0.264, -0.481), PI, "f2f2f2"]]:
		var e := Node3D.new()
		e.position = spec[0]
		e.rotation.y = spec[1]
		body.add_child(e)
		Kit.cyl(e, 0.088 * U, 0.088 * U, 0.012 * U, Vector3.ZERO, Kit.mat(spec[2], 0.4), 20, Vector3(PI / 2, 0, 0))
		Kit.torus(e, 0.075 * U, 0.088 * U, Vector3(0, 0, 0.004 * U), chrome, Vector3(PI / 2, 0, 0))
		Kit.box(e, Vector3(0.08, 0.012, 0.004) * U, Vector3(0, 0, 0.007 * U), chrome)


func _place_ride(v: Node3D, p: Vector2, yaw: float) -> void:
	v.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
	v.rotation.y = yaw
	add_child(v)
	_rides.append(v)


## Yakindaki binilebilir arac: kendi araclarimiz ya da trafikteki herhangi bir araba (taksi ve dolmus haric).
func _nearest_rideable() -> Node3D:
	var o := _owner_pos()
	var best: Node3D = null
	var best_d := 1e9
	for r in _rides:
		var dd := o.distance_to(Vector2(r.position.x, r.position.z))
		if dd < (3.6 if r.get_meta("kind") == "araba" else 2.2) and dd < best_d:
			best_d = dd
			best = r
	if best == null:
		for c in _cars:
			if _car_model(c) in ["taksi", "dolmus"]:
				continue
			var dd := o.distance_to(Vector2(c.position.x, c.position.z))
			if dd < 3.4 and dd < best_d:
				best_d = dd
				best = c
	return best


func _car_model(c: Node3D) -> String:
	if c.get_child_count() > 0 and c.get_child(0).has_meta("model"):
		return c.get_child(0).get_meta("model")
	return "araba"


## Trafikteki arabayi binilebilir araca cevirir (GTA gibi).
func _take_traffic_car(c: Node3D) -> void:
	c.set_process(false)
	_cars.erase(c)
	c.set_meta("kind", "araba")
	if c.get_child_count() > 0 and c.get_child(0).has_meta("wheels"):
		c.set_meta("wheels", c.get_child(0).get_meta("wheels"))
	_rides.append(c)


func _enter_ride() -> void:
	var r := _nearest_rideable()
	if r == null:
		return
	if not r in _rides:
		_take_traffic_car(r)
	_ride = r
	var cfg: Dictionary = RIDES[_ride.get_meta("kind")]
	_drive_speed = 0.0
	_last_speed = 0.0
	_steer = 0.0
	_moving = false
	_queue.clear()
	_marker.visible = false
	owner_model.speed = 0.0
	_board_pets(not cfg["hide"], cfg.get("pet", Vector3.ZERO))
	if cfg["hide"]:
		_sfx("araba_kapi", -6.0)
	if cfg["hide"]:
		owner_model.visible = false
	else:
		owner_model.riding = _ride.get_meta("kind")
		owner_model.ride_lean = float(cfg.get("lean", -1.0))
		# seat: sele ust yuzeyinin yuksekligi ve arac merkezine gore konumu; kalca kemigi selenin 9 cm ustunde
		var seat: Vector3 = cfg["seat"]
		owner_model.position = Vector3(0, seat.y + 0.09 - owner_model.hips_height(), seat.z)
	if _engine and cfg["engine"] > 0.0:
		_engine.play()
	ui._actions.visible = false
	var touch := DisplayServer.is_touchscreen_available()
	if _cam_btn == null:
		_cam_btn = UiKit.button(ui.hud, "", "camera", func(): _toggle_fps(), ui.GLASS, Color.WHITE, Vector2(68, 68), 30, 34)
		_cam_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_cam_btn.offset_left = -330
		_cam_btn.offset_top = -126
		_cam_btn.offset_right = -262
		_cam_btn.offset_bottom = -58
	_cam_btn.visible = touch
	if _exit_btn == null:
		_exit_btn = UiKit.button(ui.hud, "", "come", func():
			if absf(_drive_speed) < 2.0:
				_exit_ride(), ui.GLASS, Color.WHITE, Vector2(68, 68), 30, 34)
		_exit_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_exit_btn.offset_left = -330
		_exit_btn.offset_top = -206
		_exit_btn.offset_right = -262
		_exit_btn.offset_bottom = -138
	_exit_btn.visible = touch      # bilgisayarda E tusu
	_cam_blend = 0.6
	if touch:
		ui.toast("Çubuk: gaz, fren, direksiyon · kamera düğmesi: içeriden sür")
	else:
		ui.toast("W/S gaz-fren · A/D direksiyon · Boşluk el freni · V içeriden · E in")


## Hayvanlar araca biner: arabada iceride (gorunmez), iki tekerlide aktif hayvan arkada oturur.
func _board_pets(rear_seat: bool, seat: Vector3) -> void:
	_rider_pet = null
	for k in agents:
		var a: Node3D = agents[k]
		a.set_process(false)
		a.visible = false
		if rear_seat and k == state.d["active"] and _rider_pet == null:
			_rider_pet = a
			a.visible = true
			a.model.pose = "sit"
			a.model.speed = 0.0
			a.set_meta("seat", seat)


func _unboard_pets(at: Vector2) -> void:
	var i := 0
	for k in agents:
		var a: Node3D = agents[k]
		a.visible = true
		a.set_process(true)
		a.rotation = Vector3.ZERO
		a.place(at + Vector2(0.9 + 0.6 * i, 0.6).rotated(i * 2.0))
		a.command("come")
		i += 1
	_rider_pet = null


func _exit_ride() -> void:
	if _ride == null:
		return
	var c := Vector2(_ride.position.x, _ride.position.z)
	var side := Vector2(-cos(_ride.rotation.y), sin(_ride.rotation.y))     # aracin solu
	var gap: float = 1.9 if RIDES[_ride.get_meta("kind")]["hide"] else 0.9
	var out := c + side * gap
	for cand in [c + side * gap, c - side * gap, c + side * (gap + 0.7), c - side * (gap + 0.7)]:
		if world.is_free(cand, 0.4):
			out = cand
			break
	ui._actions.visible = true
	if _cam_btn:
		_cam_btn.visible = false
	if _exit_btn:
		_exit_btn.visible = false
	_fps = false
	cam.near = 0.05
	cam.fov = 60.0
	if _cockpit:
		_cockpit.queue_free()
		_cockpit = null
	_set_body_visible(_ride, true)
	if RIDES[_ride.get_meta("kind")]["hide"]:
		_sfx("araba_kapi", -6.0, 1.05)
	_ride.rotation.z = 0.0
	_ride.rotation.x = 0.0
	_ride = null
	_drive_speed = 0.0
	owner_node.position = Vector3(out.x, ParkMap.walk_height(out), out.y)
	owner_node.rotation = Vector3(0, owner_node.rotation.y, 0)
	owner_model.visible = true
	owner_model.riding = ""
	owner_model.grips = []
	owner_model.position = Vector3.ZERO
	_unboard_pets(out)
	_cam_blend = 0.6
	if _engine:
		_engine.stop()


func _toggle_fps() -> void:
	if _ride == null:
		return
	_fps = not _fps
	_fps_pitch = 0.0
	_fps_yaw = 0.0
	_cam_blend = 0.5
	if not _fps:
		_set_body_visible(_ride, true)
		if _cockpit:
			_cockpit.visible = false
		cam.near = 0.05
		cam.fov = 60.0


## Birinci sahis: arabada surucu koltugundan (on panel, direksiyon), iki tekerlikte surucunun gozunden.
func _cockpit_camera() -> void:
	var kind: String = _ride.get_meta("kind")
	if not _dragging:
		_fps_yaw = lerpf(_fps_yaw, 0.0, minf(1.0, get_process_delta_time() * 1.5))
	var look := Basis(Vector3.UP, _fps_yaw) * Basis(Vector3.RIGHT, _fps_pitch)
	if kind == "araba":
		if _cockpit == null:
			_cockpit = _make_cockpit()
			_ride.add_child(_cockpit)
		_cockpit.visible = true
		_set_body_visible(_ride, false)
		var wheel: Node3D = _cockpit.get_node("Direksiyon")
		# Simit kendi ekseninde (kolon ekseni) doner: saga kirinca saat yonunde
		if wheel.has_meta("model"):
			wheel.basis = Basis(Vector3.RIGHT, -0.3) * Basis(Vector3.BACK, -_steer * 2.6)
		else:
			wheel.basis = Basis(Vector3.RIGHT, -1.1) * Basis(Vector3.UP, _steer * 2.6)
		(_cockpit.get_node("Hiz") as Label3D).text = "%d" % int(absf(_drive_speed) * 3.6)
		var kmh := absf(_drive_speed) * 3.6
		(_cockpit.get_node("Ibre1") as Node3D).rotation.z = 2.1 - clampf(kmh / 200.0, 0.0, 1.0) * 4.2
		(_cockpit.get_node("Ibre0") as Node3D).rotation.z = 2.1 - clampf(0.12 + kmh / 120.0 * 0.5 + absf(ui.stick.y) * 0.2, 0.0, 1.0) * 4.2
		var cpn = _cockpit.get_node("CarPlayVP/CP")
		cpn.player = _owner_pos()
		cpn.heading = _ride.rotation.y
		cpn.route = minimap.route
		cpn.dest_name = minimap.dest_name
		cpn.speed_kmh = absf(_drive_speed) * 3.6
		cpn.clock = ui.clock_label.text
		if _args.has("cpdump") and Engine.get_process_frames() % 60 == 0:
			_cockpit.get_node("CarPlayVP").get_texture().get_image().save_png(_args["cpdump"])
		cam.global_transform = _ride.global_transform * Transform3D(look * Basis(Vector3.RIGHT, -0.06), Vector3(-0.36, 1.18, 0.22))
		cam.near = 0.05
		cam.fov = 72.0
	else:
		# Surucunun gozlerinden: bas kemiginin biraz ustu, kendi basi gorunmesin diye yakin duzlem
		var hb: Transform3D = owner_model.head_transform()
		cam.global_position = hb.origin + _ride.global_basis * Vector3(0, 0.1, -0.06)
		cam.global_basis = _ride.global_basis * look * Basis(Vector3.RIGHT, -0.1)
		cam.near = 0.16
		cam.fov = 75.0


func _carplay_text() -> String:
	if _nav == Vector2.INF or minimap.route.is_empty():
		return "CarPlay\nHaritadan hedef seç (M)"
	var d := 0.0
	var prev := _owner_pos()
	for q in minimap.route:
		d += prev.distance_to(q)
		prev = q
	return "%s\n%s" % [minimap.dest_name, ("%.1f km" % (d / 1000.0)) if d > 1000.0 else ("%d m" % int(d))]


func _set_body_visible(v: Node3D, on: bool) -> void:
	for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		if _cockpit != null and _cockpit.is_ancestor_of(mi):
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


## Araba ici (2015 kompakt hatchback, Polo 6C duzeni): iki kadranli gosterge, yuvarlak yan
## havalandirmalar, gumus serit, orta konsolda CarPlay ekrani, klima dugmeleri, otomatik vites kolu,
## uc kollu direksiyon, gri kumas koltuklar, kapi dosemeleri.
func _make_cockpit() -> Node3D:
	var c := Node3D.new()
	var dash := Kit.mat("2b2d31", 0.8)
	var soft := Kit.mat("3a3c40", 0.9)
	var silver := Kit.mat("b9bcc0", 0.3)
	silver.metallic = 0.6
	var black := Kit.mat("141517", 0.4)
	var fabric := Kit.mat("55585e", 1.0)
	var fabric2 := Kit.mat("3d4045", 1.0)
	var head := Kit.mat("cdc8bd", 0.95)
	# On panel govdesi ve ust yuzey
	Kit.box(c, Vector3(1.56, 0.38, 0.5), Vector3(0, 0.72, -0.8), dash)
	Kit.box(c, Vector3(1.56, 0.06, 0.6), Vector3(0, 0.94, -0.88), soft, Vector3(0.2, 0, 0))
	# Gumus serit (panel boyunca)
	Kit.box(c, Vector3(1.5, 0.035, 0.02), Vector3(0, 0.84, -0.545), silver)
	# Gosterge kapagi ve iki yuvarlak kadran + ortada kucuk ekran
	Kit.box(c, Vector3(0.46, 0.13, 0.24), Vector3(-0.36, 1.0, -0.64), dash, Vector3(-0.3, 0, 0))
	var face := Kit.mat("0d0f12", 0.4)
	var ring := Kit.mat("c9ccd0", 0.3)
	for gx in [-0.47, -0.25]:
		Kit.cyl(c, 0.068, 0.068, 0.01, Vector3(gx, 0.935, -0.565), face, 24, Vector3(PI / 2 - 0.3, 0, 0))
		Kit.torus(c, 0.064, 0.072, Vector3(gx, 0.935, -0.56), ring, Vector3(PI / 2 - 0.3, 0, 0))
		var needle := Kit.box(c, Vector3(0.006, 0.05, 0.004), Vector3(gx, 0.95, -0.556), Kit.glow("ff5a1f", 1.5), Vector3(-0.3, 0, 0.7))
		needle.name = "Ibre%d" % (0 if gx < -0.3 else 1)
	Kit.box(c, Vector3(0.07, 0.07, 0.005), Vector3(-0.36, 0.935, -0.562), Kit.glow("1d3a52", 0.6), Vector3(-0.3, 0, 0))
	var speed := Label3D.new()
	speed.name = "Hiz"
	speed.font_size = 40
	speed.pixel_size = 0.0011
	speed.modulate = Color("e8f4ff")
	speed.position = Vector3(-0.36, 0.936, -0.558)
	speed.rotation.x = -0.3
	speed.text = "0"
	c.add_child(speed)
	# Yan havalandirmalar (yuvarlak) ve orta havalandirmalar (dikdortgen)
	for vx in [-0.68, 0.68]:
		Kit.torus(c, 0.045, 0.06, Vector3(vx, 0.86, -0.548), silver, Vector3(PI / 2, 0, 0))
		Kit.cyl(c, 0.045, 0.045, 0.01, Vector3(vx, 0.86, -0.552), black, 16, Vector3(PI / 2, 0, 0))
	for vx in [-0.02, 0.18]:
		Kit.box(c, Vector3(0.16, 0.06, 0.02), Vector3(vx, 1.0, -0.6), black, Vector3(-0.25, 0, 0))
		Kit.box(c, Vector3(0.17, 0.008, 0.022), Vector3(vx, 1.033, -0.6), silver, Vector3(-0.25, 0, 0))
	# Orta konsol: CarPlay ekrani (SubViewport), altinda klima paneli
	var vp := SubViewport.new()
	vp.name = "CarPlayVP"
	vp.size = Vector2i(640, 300)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cp := CarPlay.new()
	cp.name = "CP"
	vp.add_child(cp)
	c.add_child(vp)
	var scr := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.27, 0.13)
	scr.mesh = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = vp.get_texture()
	scr.material_override = sm
	scr.position = Vector3(0.08, 0.9, -0.528)
	scr.rotation.x = -0.18
	c.add_child(scr)
	Kit.box(c, Vector3(0.31, 0.17, 0.02), Vector3(0.08, 0.9, -0.54), black, Vector3(-0.18, 0, 0))
	Kit.box(c, Vector3(0.32, 0.18, 0.012), Vector3(0.08, 0.9, -0.546), silver, Vector3(-0.18, 0, 0))
	Kit.box(c, Vector3(0.3, 0.1, 0.03), Vector3(0.08, 0.74, -0.54), black)
	for kx in [-0.02, 0.08, 0.18]:
		Kit.cyl(c, 0.022, 0.022, 0.025, Vector3(kx, 0.74, -0.52), silver, 14, Vector3(PI / 2, 0, 0))
	# Orta tunel, otomatik vites kolu (P R N D), el freni
	Kit.box(c, Vector3(0.24, 0.3, 0.75), Vector3(0.0, 0.43, -0.2), dash)
	Kit.box(c, Vector3(0.16, 0.012, 0.22), Vector3(0.0, 0.585, -0.2), black)
	Kit.cyl(c, 0.014, 0.018, 0.13, Vector3(0.0, 0.65, -0.2), black, 8)
	Kit.capsule(c, 0.028, 0.1, Vector3(0.0, 0.73, -0.2), Kit.mat("26282b", 0.5))
	Kit.box(c, Vector3(0.012, 0.012, 0.12), Vector3(0.0, 0.745, -0.2), silver)
	var prnd := Label3D.new()
	prnd.text = "P R N D S"
	prnd.font_size = 24
	prnd.pixel_size = 0.0012
	prnd.modulate = Color("d0d4d8")
	prnd.position = Vector3(0.05, 0.593, -0.2)
	prnd.rotation = Vector3(-PI / 2, PI / 2, 0)
	c.add_child(prnd)
	Kit.box(c, Vector3(0.04, 0.04, 0.24), Vector3(0.0, 0.62, 0.12), black, Vector3(-0.2, 0, 0))
	# Direksiyon: kendi modelimiz (Tripo, kolon ve kollariyla) varsa o; yoksa cizilen uc kollu simit
	var wheel := Node3D.new()
	wheel.name = "Direksiyon"
	wheel.position = Vector3(-0.36, 0.9, -0.4)
	c.add_child(wheel)
	if ResourceLoader.exists("res://assets/models/polo_ic.glb"):
		var wm: Node3D = load("res://assets/models/polo_ic.glb").instantiate()
		var k := 0.42                                   # simit capi ~37 cm
		wm.scale = Vector3.ONE * k
		wm.position = -Vector3(-0.015, 0.53, 0.0) * k  # simit merkezi pivotta
		wheel.add_child(wm)
		wheel.set_meta("model", true)
		wheel.rotation.x = -0.3
	else:
		wheel.rotation.x = -1.1
		Kit.cyl(c, 0.03, 0.035, 0.3, Vector3(-0.36, 0.86, -0.54), dash, 8, Vector3(-1.1 + PI / 2, 0, 0))
		Kit.torus(wheel, 0.16, 0.19, Vector3.ZERO, Kit.mat("1d1e21", 0.7), Vector3.ZERO)
		Kit.box(wheel, Vector3(0.3, 0.02, 0.045), Vector3(0, 0, -0.01), soft)
		Kit.box(wheel, Vector3(0.05, 0.02, 0.15), Vector3(0, 0, 0.08), soft)
		Kit.box(wheel, Vector3(0.16, 0.022, 0.012), Vector3(0, 0.005, 0.03), silver)
		Kit.cyl(wheel, 0.065, 0.07, 0.04, Vector3(0, 0.01, 0), Kit.mat("26282b", 0.6), 16)
	# Koltuklar (gri kumas, ortasi koyu seritli) ve basliklar
	for x in [-0.36, 0.36]:
		Kit.box(c, Vector3(0.52, 0.12, 0.52), Vector3(x, 0.46, 0.22), fabric)
		Kit.box(c, Vector3(0.28, 0.125, 0.5), Vector3(x, 0.462, 0.22), fabric2)
		Kit.box(c, Vector3(0.5, 0.72, 0.12), Vector3(x, 0.86, 0.5), fabric, Vector3(0.12, 0, 0))
		Kit.box(c, Vector3(0.26, 0.6, 0.125), Vector3(x, 0.86, 0.49), fabric2, Vector3(0.12, 0, 0))
		Kit.box(c, Vector3(0.26, 0.18, 0.1), Vector3(x, 1.32, 0.57), fabric)
	Kit.box(c, Vector3(1.4, 0.14, 0.5), Vector3(0, 0.5, 1.05), fabric)
	Kit.box(c, Vector3(1.4, 0.6, 0.12), Vector3(0, 0.82, 1.3), fabric, Vector3(0.15, 0, 0))
	Kit.box(c, Vector3(1.5, 0.02, 1.6), Vector3(0, 0.38, 0.2), Kit.mat("232427", 1.0))
	# Kapi dosemeleri: kol dayama, gumus kapi kolu, hoparlor
	for sx in [-1.0, 1.0]:
		Kit.box(c, Vector3(0.06, 0.5, 1.5), Vector3(sx * 0.78, 0.72, 0.0), soft)
		Kit.box(c, Vector3(0.1, 0.05, 0.5), Vector3(sx * 0.72, 0.8, 0.05), dash)
		Kit.box(c, Vector3(0.02, 0.025, 0.12), Vector3(sx * 0.745, 0.92, -0.32), silver)
		Kit.cyl(c, 0.07, 0.07, 0.01, Vector3(sx * 0.745, 0.55, -0.35), black, 16, Vector3(0, 0, PI / 2))
		Kit.box(c, Vector3(0.05, 0.04, 1.3), Vector3(sx * 0.77, 0.97, 0.0), dash)
		Kit.box(c, Vector3(0.07, 0.62, 0.08), Vector3(sx * 0.72, 1.22, -0.62), head, Vector3(-0.55, 0, 0))
		Kit.box(c, Vector3(0.07, 0.55, 0.12), Vector3(sx * 0.74, 1.2, 0.62), head)
		Kit.box(c, Vector3(0.04, 0.04, 1.3), Vector3(sx * 0.76, 1.45, 0.0), head)
		Kit.box(c, Vector3(0.38, 0.02, 0.18), Vector3(sx * 0.36, 1.42, -0.42), head, Vector3(0.15, 0, 0))
	Kit.box(c, Vector3(1.5, 0.03, 1.5), Vector3(0, 1.48, 0.15), head)
	Kit.box(c, Vector3(0.24, 0.07, 0.02), Vector3(0.0, 1.38, -0.5), black)
	var il := OmniLight3D.new()
	il.position = Vector3(0, 1.3, 0.0)
	il.omni_range = 1.8
	il.light_energy = 0.45
	il.light_color = Color("fff1dc")
	c.add_child(il)
	# Dis: kaput ve yan aynalar (govde iceriden gizlenince yerine)
	var paint := Kit.mat("eeeeec" if ResourceLoader.exists("res://assets/models/polo.glb") else "b8322c", 0.3)
	Kit.box(c, Vector3(1.5, 0.08, 1.2), Vector3(0, 0.92, -1.55), paint, Vector3(0.12, 0, 0))
	for sx in [-1.0, 1.0]:
		Kit.box(c, Vector3(0.18, 0.12, 0.06), Vector3(sx * 0.92, 1.1, -0.55), black)
	return c


func _update_drive(dt: float) -> void:
	var cfg: Dictionary = RIDES[_ride.get_meta("kind")]
	var top: float = cfg["max"]
	var gas: float = -ui.stick.y
	var steer: float = ui.stick.x
	var handbrake := Input.is_physical_key_pressed(KEY_SPACE)
	if handbrake:
		_drive_speed = move_toward(_drive_speed, 0.0, 11.0 * dt)
	elif gas > 0.12:
		if _drive_speed < -0.2:
			_drive_speed = move_toward(_drive_speed, 0.0, float(cfg["brake"]) * dt)
		else:
			# Hiz arttikca ivme azalir
			var acc: float = float(cfg["acc"]) * (1.0 - 0.6 * clampf(_drive_speed / top, 0.0, 1.0))
			_drive_speed = move_toward(_drive_speed, top * gas, acc * dt)
	elif gas < -0.12:
		if _drive_speed > 0.2:
			_drive_speed = move_toward(_drive_speed, 0.0, float(cfg["brake"]) * dt)     # fren
		else:
			_drive_speed = move_toward(_drive_speed, -top * 0.22 * -gas, 1.8 * dt)     # geri vites
	else:
		_drive_speed = move_toward(_drive_speed, 0.0, (1.2 + absf(_drive_speed) * 0.08) * dt)   # motor freni ve suruklenme
	# Direksiyon: yavas doner, birakinca ortalanir; hizlandikca daha az kirilir
	_steer = move_toward(_steer, steer, dt * float(cfg["steer"]) * (1.0 if absf(steer) > 0.05 else 1.6))
	var lock: float = float(cfg["lock"]) * lerpf(1.0, 0.35, clampf(absf(_drive_speed) / top, 0.0, 1.0))
	var yaw_rate := _drive_speed * tan(_steer * lock) / float(cfg["base"])
	if handbrake and cfg["hide"] and absf(_drive_speed) > 3.0:
		yaw_rate *= 1.7      # el freniyle kayarak donus
	var yaw := _ride.rotation.y - yaw_rate * dt
	var p := Vector2(_ride.position.x, _ride.position.z)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var want := p + fwd * _drive_speed * dt
	var np: Vector2 = ParkMap.clamp_bounds(world.resolve(want, float(cfg["r"]), p))
	np = _push_from_vehicles(np, float(cfg["r"]) + 0.2, _ride)
	if np.distance_to(want) > 0.02:
		_drive_speed *= maxf(0.0, 1.0 - 6.0 * dt)       # carpti: yavasla
	var hide: bool = cfg["hide"]
	var h := ParkMap.terrain_height(np) if hide else ParkMap.walk_height(np)
	var slope := atan2(ParkMap.terrain_height(np + fwd * 1.5) - ParkMap.terrain_height(np - fwd * 1.5), 3.0)
	_ride.position = Vector3(np.x, h, np.y)
	_ride.rotation.y = yaw
	var accel := (_drive_speed - _last_speed) / maxf(dt, 0.001)
	_last_speed = _drive_speed
	# Egim + hizlanirken burun hafif kalkar, frende hafif iner (birikmez; hedefe yaklasir)
	var pitch_to := slope + clampf(accel * 0.004, -0.03, 0.02) * (1.0 if hide else 0.5)
	_ride.rotation.x = lerpf(_ride.rotation.x, pitch_to, minf(1.0, dt * 6.0))
	World.spin_wheels(_ride, _drive_speed * dt, _steer * float(cfg["lock"]))
	_blink_t += dt
	var turn := (1 if _steer > 0.0 else -1) if absf(_steer) > 0.3 and absf(_drive_speed) < 14.0 else 0
	if _ride.has_meta("blinkers"):
		Car.blink(_ride.get_meta("blinkers"), turn, _blink_t)
	if hide:
		# Araba: virajda govde hafif disa yatar
		_ride.rotation.z = lerpf(_ride.rotation.z, _steer * clampf(_drive_speed / top, 0.0, 1.0) * 0.04, minf(1.0, dt * 3.0))
	else:
		# Iki tekerlekli: donus hizina gore iceri yatar
		var lean_to := clampf(-yaw_rate * absf(_drive_speed) * 0.07, -0.6, 0.6)
		_ride.rotation.z = lerpf(_ride.rotation.z, lean_to, minf(1.0, dt * 3.0))
		owner_model.ride_speed = absf(_drive_speed)
		if cfg.has("grip"):
			var g: Vector3 = cfg["grip"]
			var gl := _ride.global_transform * Vector3(-g.x, g.y, g.z)
			var gr := _ride.global_transform * Vector3(g.x, g.y, g.z)
			# Bisiklette donerken el isareti (yavas giderken direksiyonu kirinca)
			if _ride.get_meta("kind") == "bisiklet" and turn != 0 and absf(_drive_speed) > 1.0 and absf(_drive_speed) < 5.0:
				if turn < 0:
					gl = _ride.global_transform * Vector3(-0.95, 1.42, 0.2)
				else:
					gr = _ride.global_transform * Vector3(0.95, 1.42, 0.2)
			owner_model.grips = [gl, gr]
	if _rider_pet:
		var seat: Vector3 = _rider_pet.get_meta("seat")
		_rider_pet.global_transform = _ride.global_transform * Transform3D(Basis(), seat - Vector3(0, 0.62, 0))
	owner_node.position = _ride.position
	owner_node.rotation = _ride.rotation
	if absf(_drive_speed) > 1.0 and not _dragging:
		_cam_yaw = lerp_angle(_cam_yaw, yaw, minf(1.0, dt * 2.2))
	state.count("drive", absf(_drive_speed) * dt)
	if _engine and float(cfg["engine"]) > 0.0:
		_engine.pitch_scale = (0.75 + absf(_drive_speed) / top * 1.3) * float(cfg["engine"])
		_engine.volume_db = -16.0 + 6.0 * clampf(absf(gas), 0.0, 1.0)


## Hareketli araclarin (trafik, park etmis kendi araclarimiz, otobus) icinden gecilmez.
func _push_from_vehicles(p: Vector2, r: float, skip: Node3D = null) -> Vector2:
	var list: Array = []
	for c in _cars:
		list.append([c, 2.0, 0.95])
	for c in _rides:
		if c != skip:
			list.append([c, 2.0 if c.get_meta("kind") == "araba" else 0.8, 0.95 if c.get_meta("kind") == "araba" else 0.35])
	for b in _buses:
		if b.visible:
			list.append([b, 5.8, 1.35])
	if _taxi:
		list.erase(_taxi)
	for e in list:
		var n: Node3D = e[0]
		if n == skip or not n.visible:
			continue
		var c := Vector2(n.global_position.x, n.global_position.z)
		if c.distance_squared_to(p) > 100.0:
			continue
		var f := Vector2(-sin(n.global_rotation.y), -cos(n.global_rotation.y))
		var half: float = e[1] - e[2]
		var q := Geometry2D.get_closest_point_to_segment(p, c - f * half, c + f * half)
		var rr: float = e[2] + r
		var d := p.distance_to(q)
		if d < rr:
			p = q + ((p - q) / d if d > 0.001 else Vector2(f.y, -f.x)) * rr
	return p


# ---------------------------------------------------------------- taksi ve dolmus (yolcu)

## Arac yolu: yalnizca araclarin gidebildigi sokaklar (tek yonlere uyulur).
func _road_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var nodes := ParkMap.nodes
	var start := -1
	var goal := -1
	var bs := 1e18
	var bg := 1e18
	for i in nodes.size():
		if ParkMap.road_next[i].is_empty():
			continue
		var ds := nodes[i].distance_squared_to(from)
		var dg := nodes[i].distance_squared_to(to)
		if ds < bs:
			bs = ds
			start = i
		if dg < bg:
			bg = dg
			goal = i
	var dist := {start: 0.0}
	var back := {}
	var open: Array = [start]
	while not open.is_empty():
		var bi := 0
		for k in open.size():
			if dist[open[k]] < dist[open[bi]]:
				bi = k
		var u: int = open[bi]
		open.remove_at(bi)
		if u == goal:
			break
		for v in ParkMap.road_next[u]:
			var nd: float = dist[u] + nodes[u].distance_to(nodes[v])
			if nd < dist.get(v, 1e18):
				dist[v] = nd
				back[v] = u
				open.append(v)
	var out := PackedVector2Array()
	var k := goal
	while k != start and back.has(k):
		out.insert(0, nodes[k])
		k = back[k]
	out.insert(0, nodes[start])
	return out


func _nearest_taxi() -> Node3D:
	var o := _owner_pos()
	for c in _cars:
		if _car_model(c) in ["taksi", "dolmus"] and o.distance_to(Vector2(c.position.x, c.position.z)) < 4.0:
			return c
	return null


func _board_taxi(c: Node3D) -> void:
	if _nav == Vector2.INF or _nav.distance_to(Vector2(c.position.x, c.position.z)) < 25.0:
		_nav = Vector2.INF
		minimap.route = []
		_open_map()
		ui.toast("Önce haritadan (M) nereye gideceğini seç, sonra bin.")
		return
	_taxi = c
	_taxi.set_process(false)
	_taxi_path = _road_route(Vector2(c.position.x, c.position.z), _nav)
	_taxi_i = 0
	_taxi_speed = 0.0
	var length := 0.0
	for i in range(1, _taxi_path.size()):
		length += _taxi_path[i - 1].distance_to(_taxi_path[i])
	var dolmus := _car_model(c) == "dolmus"
	_taxi_fare = (5 if dolmus else 10) + int(length / (250.0 if dolmus else 90.0))
	_moving = false
	_queue.clear()
	owner_model.visible = false
	_board_pets(false, Vector3.ZERO)
	ui._actions.visible = false
	_cam_blend = 0.6
	ui.toast("%s · %s · %d ₺" % ["Dolmuş" if dolmus else "Taksi", minimap.dest_name, _taxi_fare])


func _update_taxi(dt: float) -> void:
	var c := _taxi
	var p := Vector2(c.position.x, c.position.z)
	if _taxi_i >= _taxi_path.size():
		_leave_taxi(true)
		return
	var tgt := _taxi_path[_taxi_i]
	var seg_dir := (tgt - (_taxi_path[_taxi_i - 1] if _taxi_i > 0 else p)).normalized()
	var lane := tgt + Vector2(-seg_dir.y, seg_dir.x) * 1.7
	var to := lane - p
	var d := to.length()
	if d < 2.5:
		_taxi_i += 1
		return
	# Viraj oncesi yavasla
	var want := 9.0
	if _taxi_i + 1 < _taxi_path.size():
		var nd := (_taxi_path[_taxi_i + 1] - tgt).normalized()
		want = lerpf(4.0, 9.0, clampf(nd.dot(seg_dir), 0.0, 1.0)) if d < 14.0 else 9.0
	_taxi_speed = move_toward(_taxi_speed, want, dt * 2.5)
	var dir := to / d
	var np := p + dir * minf(_taxi_speed * dt, d)
	var yaw := lerp_angle(c.rotation.y, atan2(-dir.x, -dir.y), minf(1.0, dt * 3.0))
	c.position = Vector3(np.x, ParkMap.terrain_height(np), np.y)
	c.rotation.y = yaw
	if c.get_child_count() > 0:
		World.spin_wheels(c.get_child(0), _taxi_speed * dt)
	owner_node.position = c.position
	if not _dragging:
		_cam_yaw = lerp_angle(_cam_yaw, yaw, minf(1.0, dt * 1.6))


func _leave_taxi(arrived: bool) -> void:
	var c := _taxi
	if arrived:
		state.count("taxi")
	_taxi = null
	var p := Vector2(c.position.x, c.position.z)
	var side := Vector2(cos(c.rotation.y), -sin(c.rotation.y))
	var out := p + side * 2.2
	for cand in [p + side * 2.2, p - side * 2.2, p + side * 3.2]:
		if world.is_free(cand, 0.4):
			out = cand
			break
	owner_node.position = Vector3(out.x, ParkMap.walk_height(out), out.y)
	owner_model.visible = true
	ui._actions.visible = true
	_unboard_pets(out)
	_cam_blend = 0.6
	if arrived:
		state.d["coins"] = maxi(0, int(state.d["coins"]) - _taxi_fare)
		ui.toast("Vardın · %d ₺ ödedin" % _taxi_fare)
	# Arac yeniden trafige karisir
	c.set("node", ParkMap.nearest_node(p))
	c.set("_prev", -1)
	if c.has_method("_pick"):
		c._pick()
	c.set_process(true)


# ---------------------------------------------------------------- navigasyon ve mini harita

## Harita: evim, araclarim, otobus duraklari ve metro girisleri her acilista guncellenir.
func _open_map() -> void:
	var dyn: Array = []
	if ParkMap.zone == "":
		dyn.append(["Evim", HOME_DOOR + HOME_DOOR_OUT * 1.5, "e0703a", "home"])
	for r in _rides:
		var kind: String = r.get_meta("kind")
		var label: String = {"araba": "Arabam", "scooter": "Scooter", "motosiklet": "Motosiklet", "bisiklet": "Bisiklet"}.get(kind, "Aracım")
		dyn.append([label, Vector2(r.position.x, r.position.z), "333a44", "play"])
	for st in world.stops:
		dyn.append([st["name"] + ((" · " + " ".join(st["lines"])) if not st["lines"].is_empty() else ""), st["pos"], "1a4fa0", "pin"])
	for g in world.metro_gates:
		dyn.append(["M · " + str(g["name"]), g["pos"], "c8322b", "pin"])
	if world.vet_pos != Vector2.INF:
		dyn.append(["Veteriner", world.vet_pos, "1e9a8a", "plus"])
	map_screen.dynamic = dyn
	map_screen.open(_owner_pos())


func _set_nav(p: Vector2, label := "") -> void:
	_nav = p
	_nav_t = 0.0
	var best := label
	if best == "":
		var bd := 1e9
		for pin in map_screen.PINS:
			var d: float = (pin[2] as Vector2).distance_to(p)
			if d < bd:
				bd = d
				best = pin[0]
	minimap.dest_name = best
	minimap.route = []


func _update_minimap(dt: float) -> void:
	minimap.visible = _mode == "play" and not map_screen.visible and ParkMap.home == null and not (_fps and _ride != null and _ride.get_meta("kind") == "araba")
	# Sag altta, komut dugmelerinin ustunde
	var vp := get_viewport().get_visible_rect().size
	var bottom := 130.0 if ui._actions.visible else 60.0
	minimap.position = Vector2(vp.x - minimap.SIZE - 40.0, vp.y - minimap.SIZE - bottom - 50.0)
	minimap.player = _owner_pos()
	minimap.heading = _cam_yaw
	minimap.coins = int(state.d["coins"])
	minimap.speed_kmh = absf(_drive_speed) * 3.6 if _ride != null else (_taxi_speed * 3.6 if _taxi != null else -1.0)
	var mk: Array = []
	if ParkMap.zone == "":
		mk.append([HOME_DOOR, Color("e0703a"), "ev"])
	for r in _rides:
		if r != _ride:
			mk.append([Vector2(r.position.x, r.position.z), Color("2d3440"), "arac"])
	for b in _buses:
		if b.visible:
			mk.append([Vector2(b.position.x, b.position.z), Color("1f6fd0"), "otobus"])
	minimap.markers = mk
	var pet: Dictionary = state.pet(state.d["active"])
	for n in state.NEEDS:
		minimap.needs[n] = float(pet[n])
	if ui.clock_label:
		ui.clock_label.text = "%02d:%02d" % [int(clock), int(fmod(clock, 1.0) * 60.0)]
		ui._clock_icon.icon = "sun" if night < 0.5 else "moon"
	if _nav == Vector2.INF:
		minimap.route = []
		return
	_nav_t -= dt
	# Rota yalnizca gerektiginde hesaplanir (cizgi titremesin): ilk kez, yoldan 12 m sapinca ya da arac degisince
	var off_route := true
	var o := _owner_pos()
	if minimap.route.size() > 0:
		var prev: Vector2 = minimap.route[0]
		off_route = o.distance_to(prev) > 12.0
		for q in minimap.route:
			if Geometry2D.get_closest_point_to_segment(o, prev, q).distance_to(o) < 12.0:
				off_route = false
				break
			prev = q
	var driving: bool = (_ride != null and bool(RIDES[_ride.get_meta("kind")]["hide"])) or _taxi != null
	if off_route or _nav_t <= -8.0 or driving != bool(minimap.get_meta("driving", false)):
		_nav_t = 0.0
		minimap.set_meta("driving", driving)
		if driving:
			minimap.route = Array(_road_route(o, _nav)) + [_nav]
		else:
			minimap.route = world.find_path(o, _nav)
	# Gecilen noktalari at
	while minimap.route.size() > 1 and o.distance_to(minimap.route[0]) < 6.0:
		minimap.route.remove_at(0)
	if _owner_pos().distance_to(_nav) < 6.0:
		ui.toast("Vardın: %s" % minimap.dest_name)
		_nav = Vector2.INF


# ---------------------------------------------------------------- ev (ic mekan)

## Ev: Subayevleri'nde, Aksa Camii'nin kuzeyindeki parkin kosesi, Arif Sokak ile Vadi Sokak arasinda parka inen
## yarim yolun basindaki 4 katli apartman (OSM bina 407), 2. kat. Balkon kuzeydeki parka bakar.
const HOME_BUILDING := Vector2(42.95, -365.43)
const HOME_CORNERS := [Vector2(26.8, -370.6), Vector2(33.6, -351.3), Vector2(59.1, -360.2), Vector2(52.3, -379.6)]
const HOME_DOOR := Vector2(30.17, -360.93)
const HOME_DOOR_OUT := Vector2(-0.944, 0.331)
const HOME_FLOOR := 2
var _home: Node3D


func _near_home_door() -> bool:
	return ParkMap.zone == "" and ParkMap.home == null and _owner_pos().distance_to(HOME_DOOR + HOME_DOOR_OUT * 1.2) < 3.2


func _enter_home() -> void:
	if _home == null:
		_home = Home.new()
		# Yerel x: binanin kisa ekseni boyunca guneye (x = 0 kuzey cephesi: balkon parka bakar),
		# yerel z: uzun ekseni boyunca batiya (salon penceresi sokaga)
		var theta := atan2(-0.944, 0.331)
		_home.rotation.y = theta
		var ground := -1e9
		for q in HOME_CORNERS:
			ground = maxf(ground, ParkMap.terrain_height(q))
		var c3 := Vector3(HOME_BUILDING.x, ground + HOME_FLOOR * 3.0 + 0.05, HOME_BUILDING.y)
		_home.position = c3 - Basis(Vector3.UP, theta) * Vector3(9.6, 0, 5.8)
		add_child(_home)
	_home.visible = true
	ParkMap.home = _home
	# Binanin bu kattan yukarisi gorunmesin (yukaridan bakinca daire acik gorunur)
	world.hide_above(HOME_BUILDING, Vector2(0.944, -0.33), Vector2(14.2, 10.9), _home.global_position.y - 0.2)
	_moving = false
	_queue.clear()
	var inside: Vector2 = _home.w2(_home.entrance_local)
	_place_owner(inside)
	owner_node.rotation.y = _home.rotation.y + PI
	var i := 0
	for k in agents:
		agents[k].place(inside + Vector2(0.6 - 0.5 * i, 0.9).rotated(-_home.rotation.y))
		i += 1
	_cam_pitch = 0.9
	ui.toast("Evdesin · 2. kat, daire 29")


func _exit_home() -> void:
	ParkMap.home = null
	_home.visible = false
	world.hide_above(Vector2(0, 1e6), Vector2(1, 0), Vector2.ZERO, 1e6)
	var out := HOME_DOOR + HOME_DOOR_OUT * 2.2
	_place_owner(out)
	var i := 0
	for k in agents:
		agents[k].place(out + Vector2(1.0 + 0.6 * i, 0.5).rotated(i * 2.0))
		i += 1
	_cam_pitch = 0.27


func _near_home_exit() -> bool:
	return _home != null and ParkMap.home == _home and _owner_pos().distance_to(_home.w2(_home.entrance_local)) < 1.0


# ---------------------------------------------------------------- metro (bolgeler arasi)

## M4 hattinda oyunda olan istasyonlar: [istasyon, bolge, aciklama]
const METRO_STOPS := [["Meteoroloji", "", "Subayevleri"], ["Gar", "gar", "Ankara Garı · Gazi Mühendislik"],
	["Adliye", "gar", "Adliye · Maltepe Pazarı"]]
var _metro: Node3D
static var travel_to := ""      # bolge degisince cikilacak istasyon
static var _debug_traveled := false


func _open_metro() -> void:
	var here := ""
	for g in world.metro_gates:
		if _owner_pos().distance_to(g["pos"]) < 4.5:
			here = g["name"]
	var body: VBoxContainer = ui._open_modal("M4 Metro · %s" % here, 120, 120)
	body.add_theme_constant_override("separation", 10)
	for st in METRO_STOPS:
		if st[0] == here:
			continue
		var name_: String = st[0]
		var zone_: String = st[1]
		UiKit.button(body, "%s  —  %s" % [name_, st[2]], "play", func():
			ui.close_modal()
			_travel(name_, zone_), UiKit.SOFT, UiKit.BROWN, Vector2(0, 70), 24, 28)


func _travel(station: String, zone: String) -> void:
	var here := ""
	for g in world.metro_gates:
		if _owner_pos().distance_to(g["pos"]) < 6.0:
			here = g["name"]
	if here == "":
		here = "Meteoroloji" if ParkMap.zone == "" else "Gar"
	# Yer altina in: peron, tren, yolculuk
	if _metro == null:
		_metro = MetroRide.new()
		add_child(_metro)
		_metro.announce.connect(func(t: String): ui.toast(t))
		_metro.finished.connect(func(st: String): _metro_arrived(st))
	_metro.cam = cam
	_metro.owner_node = owner_node
	_metro.owner_model = owner_model
	_metro.auto = _args.has("fastride")
	_metro.pets = []
	for k in agents:
		agents[k].set_process(false)
		_metro.pets.append(agents[k])
	_metro.visible = true
	_metro.set_meta("zone", zone)
	_mode = "metro"
	ui._actions.visible = false
	minimap.visible = false
	_metro.begin(here, station)


func _metro_arrived(station: String) -> void:
	state.count("metro")
	print("METRO VARIS ", station)
	var zone: String = _metro.get_meta("zone")
	for k in agents:
		agents[k].set_process(true)
	ui._actions.visible = true
	_mode = "play"
	if zone == ParkMap.zone:
		for g in world.metro_gates:
			if g["name"] == station:
				_spawn_at_gate(g)
				ui.toast("%s istasyonundan çıktın." % station)
				return
		return
	state.d["zone"] = zone
	state.save_game()
	travel_to = station
	ParkMap.reset(zone)
	get_tree().reload_current_scene()


func _spawn_at_gate(g: Dictionary) -> void:
	var out: Vector2 = g["pos"] - g["toward"] * 4.8
	# Bina ya da duvar icine dusmesin: cevrede bos bir kaldirim ara
	if not world.is_free(out, 0.6) or world._inside_building(out):
		var found := false
		for r in range(2, 40, 2):
			for k in 16:
				var q: Vector2 = g["pos"] + Vector2.from_angle(k * TAU / 16.0) * float(r)
				if world.is_free(q, 0.8) and not world._inside_building(q):
					out = q
					found = true
					break
			if found:
				break
	_place_owner(out)
	print("CIKIS ", g["name"], " ", out, " serbest=", world.is_free(out, 0.6), " binada=", world._inside_building(out))
	owner_node.rotation.y = atan2(g["toward"].x, g["toward"].y)
	var i := 0
	for k in agents:
		agents[k].place(out + Vector2(1.0 + 0.6 * i, 0.8).rotated(i * 2.0))
		i += 1


# ---------------------------------------------------------------- otobus

var _buses: Array[Node3D] = []
var _bus_ride: Node3D


## Gercek EGO hatlari: 427 ve 464 Subayevleri'nden, 481 / 479 / 419 Fatih Caddesi'nden gecer.
func _spawn_buses() -> void:
	for b in _buses:
		b.queue_free()
	_buses.clear()
	_bus_ride = null
	if world.transit.is_empty():
		return
	var plan := [["427", 0, 0.0], ["427", 1, 900.0], ["464", 0, 1300.0], ["464", 1, 200.0],
		["481", 0, 300.0], ["479", 1, 500.0], ["419", 0, 1000.0]]
	for pl in plan:
		if not world.transit["lines"].has(pl[0]):
			continue
		var b := Bus.new()
		b.setup(pl[0], world.transit["lines"][pl[0]], pl[1], pl[2])
		b.owner_node = owner_model       # binince gizlenir: otobus kendi yolcusuna yol vermez
		add_child(b)
		_buses.append(b)


func _set_party_visible(on: bool, at := Vector2.ZERO) -> void:
	owner_model.visible = on
	owner_model.speed = 0.0
	ui._actions.visible = on
	var i := 0
	for k in agents:
		agents[k].visible = on
		agents[k].set_process(on)
		if on:
			agents[k].place(at + Vector2(0.9 + 0.6 * i, 0.6).rotated(i * 2.0))
		i += 1


func _enter_bus() -> void:
	var o := _owner_pos()
	for b in _buses:
		if b.at_stop != "" and o.distance_to(Vector2(b.position.x, b.position.z)) < 7.5:
			_bus_ride = b
	if _bus_ride == null:
		return
	_moving = false
	_queue.clear()
	_marker.visible = false
	_set_party_visible(false)
	_bus_ride.dwell = maxf(_bus_ride.dwell, 2.0)
	ui.toast("%s · %s. İnmek için bir durakta 'İn'e bas." % [_bus_ride.line, _bus_ride.title])


func _exit_bus(at := Vector2.INF) -> void:
	if _bus_ride == null:
		return
	var p: Vector2 = _bus_ride.stop_pos if at == Vector2.INF else at
	if not world.is_free(p, 0.4):
		p = Vector2(_bus_ride.position.x, _bus_ride.position.z)
	_bus_ride = null
	owner_node.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
	_set_party_visible(true, p)


func _update_bus_ride(dt: float) -> void:
	var b := _bus_ride
	if not b.visible or b.away > 0.0 or not ParkMap.inside_bounds(Vector2(b.position.x, b.position.z), 8.0):
		# Otobus haritadan cikiyor: son durakta in
		var last: Dictionary = b.last_stop
		_exit_bus(last.get("pos", Vector2(b.position.x, b.position.z)))
		ui.toast("Otobüs harita dışına çıkıyor, %s durağında indin." % last.get("name", "son"))
		return
	owner_node.position = b.position
	owner_node.rotation.y = b.rotation.y
	if b.speed > 1.0 and not _dragging:
		_cam_yaw = lerp_angle(_cam_yaw, b.rotation.y, minf(1.0, dt * 1.5))


# ---------------------------------------------------------------- ses

var _sounds := {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_i := 0


func _setup_audio() -> void:
	for n in ["ortam", "adim1", "adim2", "adim3", "adim4", "para", "firlat", "tik", "mutlu"]:
		_sounds[n] = load("res://assets/sfx/%s.wav" % n)
	for n in ["hosgeldiniz", "dukkan_zil", "kasa", "su_sicrama", "araba_kapi"]:
		if ResourceLoader.exists("res://assets/sfx/%s.mp3" % n):
			_sounds[n] = load("res://assets/sfx/%s.mp3" % n)
	for n in ["havla1", "havla2", "havla3", "miyav1", "miyav2", "miyav3", "mirla1", "solu1"]:
		_sounds[n] = load("res://assets/sfx/%s.mp3" % n)
	var amb: AudioStreamWAV = _sounds["ortam"]
	amb.loop_mode = AudioStreamWAV.LOOP_FORWARD
	amb.loop_end = int(amb.get_length() * amb.mix_rate)
	var ap := AudioStreamPlayer.new()
	ap.stream = amb
	ap.volume_db = -14.0
	add_child(ap)
	ap.play()
	if ResourceLoader.exists("res://assets/sfx/motor.wav"):
		var ms: AudioStreamWAV = load("res://assets/sfx/motor.wav")
		ms.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ms.loop_end = int(ms.get_length() * ms.mix_rate)
		_engine = AudioStreamPlayer.new()
		_engine.stream = ms
		add_child(_engine)
	for i in 6:
		var v := AudioStreamPlayer.new()
		add_child(v)
		_voices.append(v)
	state.coins_added.connect(func(): _sfx("para", -8.0))
	state.leveled.connect(func(_k, _l): _sfx("mutlu", -6.0))
	UiKit.on_click = func(): _sfx("tik", -12.0)


## Sokak hayati: sokak kopekleri havlar, kediler miyavlar (sesi bulunduklari yerden gelir),
## yanindan gecen insanlar durup selam verir.
func _update_street_life(dt: float) -> void:
	if _mode != "play" or ParkMap.home:
		return
	var me := _owner_pos()
	_bark_t -= dt
	if _bark_t <= 0.0:
		_bark_t = randf_range(5.0, 12.0)
		var near: Array = []
		for n in _npc_pets:
			if is_instance_valid(n) and Vector2(n.position.x, n.position.z).distance_to(me) < 35.0:
				near.append(n)
		if not near.is_empty():
			var n: Node3D = near[randi() % near.size()]
			var close := Vector2(n.position.x, n.position.z).distance_to(me) < 8.0
			_voice_at(n, n.visual.kind, close)
			if close:
				_bark_t *= 0.5
	_greet_cd -= dt
	if _greet_cd > 0.0 or _ride:
		return
	for n in _npc_people:
		var p := Vector2(n.position.x, n.position.z)
		if p.distance_to(me) < 2.6 and n.hold <= 0.0 and not n.has_meta("greeted"):
			n.set_meta("greeted", true)
			n.hold = 2.8
			n.hold_face = me
			_say(n, GREETINGS[randi() % GREETINGS.size()])
			_greet_cd = 6.0
			get_tree().create_timer(60.0).timeout.connect(func(): if is_instance_valid(n): n.remove_meta("greeted"))
			break


func _say(n: Node3D, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.006
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, 2.15, 0)
	n.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", 2.35, 2.6)
	tw.tween_callback(l.queue_free)


func _voice_at(n: Node3D, kind: String, loud: bool) -> void:
	if not state.d["sound"]:
		return
	var a: AudioStreamPlayer3D = n.get_node_or_null("Ses")
	if a == null:
		a = AudioStreamPlayer3D.new()
		a.name = "Ses"
		a.unit_size = 6.0
		a.max_distance = 45.0
		a.position.y = 0.5
		n.add_child(a)
	var key := ("miyav%d" if kind == "kedi" else "havla%d") % (randi() % 3 + 1)
	a.stream = _sounds[key]
	a.volume_db = 0.0 if loud else -4.0
	var vis = n.visual if "visual" in n else n.model
	a.pitch_scale = randf_range(0.85, 1.15) * (1.1 if vis.size_mul < 0.85 else 1.0)
	a.play()


## Hayvanin kendi sesi: kopek havlar, kedi miyavlar. soft = sevilirken (soluma / mirlama)
func _pet_voice(kind: String, soft := false) -> void:
	if kind == "kedi":
		_sfx("mirla1" if soft else "miyav%d" % (randi() % 3 + 1), -5.0, randf_range(0.95, 1.08))
	else:
		_sfx("solu1" if soft else "havla%d" % (randi() % 3 + 1), -5.0, randf_range(0.95, 1.05))


func _sfx(sound: String, db := -6.0, pitch := 1.0) -> void:
	if _voices.is_empty() or not state.d["sound"]:
		return
	var v := _voices[_voice_i]
	_voice_i = (_voice_i + 1) % _voices.size()
	if not _sounds.has(sound):
		return
	v.stream = _sounds[sound]
	v.volume_db = db
	v.pitch_scale = pitch
	v.play()


func _throw_to(hit: Vector2) -> void:
	_sfx("firlat", -7.0)
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
	_ball_live = true
	_ball_vel = Vector3.ZERO
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
			_pet_voice("kopek")
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
	if minimap:
		_update_minimap(dt)
	if _ready_done and (_mode == "play" or _mode == "metro") and not _args.has("cmd"):
		_keyboard_stick()
	if _mode == "metro" and _metro:
		_metro.stick = ui.stick
	if world:
		_update_daylight(dt)
	AudioServer.set_bus_mute(0, not state.d["sound"])
	if not _ready_done or _mode == "metro":
		return
	_pet_cd -= dt
	if _play_ride.is_empty():
		_update_owner(dt)
	if _jump_h > 0.0 or _jump_v > 0.0:
		_jump_v -= 18.0 * dt
		_jump_h = maxf(_jump_h + _jump_v * dt, 0.0)
		if _jump_h == 0.0:
			_jump_v = 0.0
			_sfx("adim%d" % (randi() % 4 + 1), -4.0)
		if _ride == null:
			owner_model.position.y = _jump_h
		owner_model.airborne = _jump_h > 0.05
	_update_street_life(dt)
	_update_job(dt)
	_update_health(dt)
	_update_play_ride(dt)
	_update_wet(dt)
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
			world.face_signs(cam.position)
			world.update_lamp_lights(_owner_pos())

		_save_t += dt
		if _save_t > 20.0:
			_save_t = 0.0
			state.save_game()
	_update_camera(dt)
	world.set_focus(owner_node.position, _mode == "play")


func _update_owner(dt: float) -> void:
	var p := _owner_pos()
	var to := _target - p
	var d := to.length()
	var limit := WALK_SPEED
	if _ride != null and _mode == "play":
		_update_drive(dt)
		return
	if _bus_ride != null and _mode == "play":
		_update_bus_ride(dt)
		return
	if _taxi != null and _mode == "play":
		_update_taxi(dt)
		return
	if _mode != "play":
		_moving = false
	elif _steering and ui.stick.length() <= 0.15:
		# Cubuk / tus birakildi: kalan hedefe kosmadan yerinde dur
		_steering = false
		_moving = false
		_target = p
		d = 0.0
	if _mode != "play":
		pass
	elif ui.stick.length() > 0.15:
		_steering = true
		# Cubuk az itilince yurur, sonuna kadar itilince kosar
		limit = lerpf(1.5, WALK_SPEED, clampf((ui.stick.length() - 0.35) / 0.55, 0.0, 1.0))
		_routing = false
		# Hareket cubugu: kameraya gore yon
		var fwd := Vector2(-sin(_cam_yaw), -cos(_cam_yaw))
		var right := Vector2(cos(_cam_yaw), -sin(_cam_yaw))
		var dir: Vector2 = (right * ui.stick.x - fwd * ui.stick.y).normalized()
		_queue.clear()
		_target = p + dir * (1.0 + 2.5 * ui.stick.length())
		_moving = true
		_stuck = 0.0
		_marker.visible = false
		to = _target - p
		d = to.length()
	if _moving and d < 1.0 and not _queue.is_empty():
		_go(_queue.pop_front())
	elif _moving and d > 0.15:
		if _routing:
			limit = ROUTE_SPEED
		var want_sp := minf(limit, 1.0 + d * 2.5) if _queue.is_empty() else limit
		# Yumusak hizlanma; yavaslama daha cabuk
		_walk_v = move_toward(_walk_v, want_sp, dt * (5.0 if want_sp > _walk_v else 9.0))
		var sp := maxf(_walk_v, 0.6)
		world.wade = true
		var np: Vector2 = _push_from_vehicles(world.resolve(p + to / d * minf(sp * dt * (0.55 if _in_water else 1.0), d), 0.35, p), 0.35)
		world.wade = false
		var moved := np.distance_to(p) / maxf(dt, 0.0001)
		owner_node.position = Vector3(np.x, ParkMap.walk_height(np) - _wade_depth(np), np.y)
		if moved > 0.2:
			var dir := np - p
			owner_node.rotation.y = lerp_angle(owner_node.rotation.y, atan2(-dir.x, -dir.y), minf(1.0, dt * 9.0))
		owner_model.speed = moved
		state.count("walk", np.distance_to(p))
		_stuck = _stuck + dt if moved < sp * 0.25 else 0.0
		if _stuck > 0.6 and not _dragging and ui.stick.length() < 0.15:
			if _direct and _queue.is_empty():
				# Duz giderken engele takildi: bir kez sokak agindan rota dene
				_direct = false
				walk_to(_target)
			else:
				_moving = false
	else:
		_moving = false
		_walk_v = 0.0
		owner_model.speed = move_toward(owner_model.speed, 0.0, dt * 8.0)


## Atilan esyanin fizigi: egik atis, yerde sekme, yuvarlanma ve surtunme.
func _update_thrown(dt: float) -> void:
	if not _ball_live or not _thrown:
		return
	if _fly_delay > 0.0:
		_fly_delay -= dt
		_thrown.global_position = owner_model.hand.global_position
		if _fly_delay <= 0.0:
			# Birakma ani: hedefe _fly_d saniyede varacak ilk hiz
			var from := _thrown.global_position
			var d := _fly_to - from
			_ball_vel = Vector3(d.x / _fly_d, d.y / _fly_d + 0.5 * GRAVITY * _fly_d, d.z / _fly_d)
		return
	if _thrown.get_meta("held", false):
		_ball_live = false
		return
	_ball_vel.y -= GRAVITY * dt
	var pos := _thrown.position + _ball_vel * dt
	# Duvar, cit, araba: carpip geri donsun
	var flat := Vector2(pos.x, pos.z)
	var fixed: Vector2 = world.resolve(flat, 0.14, Vector2(_thrown.position.x, _thrown.position.z))
	if fixed.distance_to(flat) > 0.01 and pos.y < ParkMap.walk_height(fixed) + 2.5:
		var n := (fixed - flat).normalized()
		var hv := Vector2(_ball_vel.x, _ball_vel.z)
		hv = (hv - 2.0 * hv.dot(n) * n) * 0.45
		_ball_vel.x = hv.x
		_ball_vel.z = hv.y
		pos.x = fixed.x
		pos.z = fixed.y
	var ground := ParkMap.walk_height(Vector2(pos.x, pos.z)) + 0.13
	if pos.y <= ground:
		pos.y = ground
		if _ball_vel.y < -1.4:
			_ball_vel.y = -_ball_vel.y * 0.48          # sekme
			_ball_vel.x *= 0.72
			_ball_vel.z *= 0.72
			_sfx("adim%d" % (randi() % 4 + 1), -14.0, 1.6)
		else:
			_ball_vel.y = 0.0                           # yuvarlanma: surtunme yavaslatir
			var hv2 := Vector2(_ball_vel.x, _ball_vel.z)
			hv2 = hv2.move_toward(Vector2.ZERO, 3.2 * dt)
			_ball_vel.x = hv2.x
			_ball_vel.z = hv2.y
			if hv2.length() < 0.08:
				_ball_live = false
	_thrown.position = pos
	var roll := Vector2(_ball_vel.x, _ball_vel.z)
	if roll.length() > 0.05:
		_thrown.rotate(Vector3(roll.y, 0, -roll.x).normalized(), roll.length() * dt / 0.13)


func _update_context() -> void:
	if _mode != "play":
		ui.set_context("", "")
		return
	var o := _owner_pos()
	var a := _active()
	_near_npc = null
	for n in _npc_pets:
		if n != _job.get("dog") and Vector2(n.position.x, n.position.z).distance_to(o) < 4.5:
			_near_npc = n
	if _bus_ride != null:
		if _bus_ride.at_stop != "":
			ui.set_context("Otobüsten İn", "busexit", "come")
		else:
			ui.set_context("", "")
		return
	for b in _buses:
		if b.at_stop != "" and b.visible and o.distance_to(Vector2(b.position.x, b.position.z)) < 7.5:
			ui.set_context("%s Otobüsüne Bin" % b.line, "bus", "play")
			return
	for g in world.metro_gates:
		if o.distance_to(g["pos"]) < 4.0:
			ui.set_context("Metroya İn", "metro", "star")
			return
	if _near_home_exit():
		ui.set_context("Dışarı Çık", "home_out", "come")
		return
	if _shop != null and ParkMap.home == _shop:
		var lo: Vector2 = _shop.local2(o)
		if lo.distance_to(_shop.entrance_local) < 1.1:
			ui.set_context("Dışarı Çık", "shop_out", "come")
		elif lo.distance_to(_shop.counter_local) < 1.4:
			if _shop.kind == "market":
				if _cart.is_empty():
					ui.set_context("Kasa · Sepetin boş", "", "cart")
				else:
					ui.set_context("Kasada Öde · %d ürün · %d ₺" % [_cart_count(), _cart_total()], "shop_pay", "cart")
			else:
				ui.set_context("Eczacıdan İste" if _shop.kind == "eczane" else "Resepsiyon · Kayıt", "shop_buy" if _shop.kind == "eczane" else "vet_desk", "cart")
		elif _shop.kind == "veteriner" and lo.distance_to(_shop.exam_local) < 1.3:
			ui.set_context("Muayene Ettir", "vet_exam", "plus")
		elif _shop.kind == "market" and _basket_node == null and lo.distance_to(_shop.basket_local) < 1.3:
			ui.set_context("Sepet Al", "shop_basket", "cart")
		elif _shop.kind == "market" and _basket_node != null:
			var near := ""
			for sp in _shop.spots:
				if lo.distance_to(sp[1]) < 0.9:
					near = sp[0]
			if near != "":
				var it := _item(near)
				ui.set_context("Sepete Koy: %s · %d ₺" % [it[1], it[2]], "shop_take:" + near, "plus")
			else:
				ui.set_context("", "")
		else:
			ui.set_context("", "")
		return
	if ParkMap.home == null:
		for sp in world.shop_spots:
			if o.distance_to(sp["pos"]) < 2.6 and sp.has("kind"):
				ui.set_context({"eczane": "Eczaneye Gir", "market": "Markete Gir", "veteriner": "Veterinere Gir"}.get(sp["kind"], "İçeri Gir"), "shop_in", "cart")
				return
	if _home != null and ParkMap.home == _home and _home.local2(o).distance_to(Vector2(7.0, 2.6)) < 1.1:
		ui.set_context("Dolabı Aç", "wardrobe", "star")
		return
	if _near_home_door():
		ui.set_context("Eve Gir", "home_in", "home")
		return
	if not _play_ride.is_empty():
		ui.set_context("İn", "playexit", "come")
		return
	if _ride == null and _taxi == null:
		for pr in world.play_rides:
			if o.distance_to(pr["pos"]) < 2.0:
				ui.set_context("Tahterevalliye Bin" if pr["kind"] == "tahterevalli" else "Salıncağa Bin", "playride", "play")
				return
	if _ride != null:
		ui.set_context("", "")      # inmek: kamera dugmesinin yanindaki in dugmesi ya da E
		return
	if _taxi != null:
		ui.set_context("", "")
		return
	var tx := _nearest_taxi()
	if tx:
		ui.set_context("%s Bin" % ("Dolmuşa" if _car_model(tx) == "dolmus" else "Taksiye"), "taxi", "play")
		return
	var rd := _nearest_rideable()
	if rd:
		ui.set_context(RIDES[rd.get_meta("kind") if rd.has_meta("kind") else "araba"]["ad"], "drive", "play")
		return
	if ParkMap.has_spot("petshop") and o.distance_to(ParkMap.spot("petshop") + Vector2(0, 6.5)) < 4.5:
		ui.set_context("Pet Shop'a Gir", "shop", "cart")
	elif ParkMap.has_spot("dondurmaci") and o.distance_to(ParkMap.spot("dondurmaci") + Vector2(0, 2.5)) < 3.6:
		ui.set_context("Dondurma Al  (10)", "icecream", "star")
	elif o.distance_to(world.pool_pos) < 4.2 and not a.is_busy():
		ui.set_context("Havuzda Yıka", "wash", "drop")
	elif o.distance_to(world.kennel_pos) < 3.8 and not a.is_busy():
		ui.set_context("Kulübede Uyut", "bed", "moon")
	elif _near_npc and not a.is_busy():
		ui.set_context("Arkadaşıyla Oynat", "npcplay", "play")
	else:
		ui.set_context("", "")


func _update_camera(dt: float) -> void:
	_update_camera_raw(dt)
	# Kamera gecisleri (arac, ic gorunum, ev) isinlanmadan yumusak
	if _cam_blend > 0.0:
		_cam_blend -= dt
		cam.global_transform = _cam_last.interpolate_with(cam.global_transform, minf(1.0, dt * 9.0))
	_cam_last = cam.global_transform


func _update_camera_raw(dt: float) -> void:
	var k := minf(1.0, dt * 5.0)
	match _mode:
		"menu":
			_menu_angle += dt * 0.06
			var g := ParkMap.spot("cesme") if ParkMap.has_spot("cesme") else ParkMap.spot("baslangic")
			var c := Vector3(g.x, 1.5, g.y)
			_focus = _focus.lerp(c, k)
			cam.position = c + Vector3(sin(_menu_angle) * 24.0, 11.0, cos(_menu_angle) * 24.0)
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
		"debug", "metro", "intro":
			pass
		"closet":
			var a := _active()
			_focus = _focus.lerp(a.position, k)
			cam.position = _focus + Vector3(1.4, 2.2, 3.4)
			cam.look_at(_focus + Vector3(1.1, 0.9, 0))
		_ when _ride != null and _fps:
			_cockpit_camera()
		_:
			_focus = _focus.lerp(owner_node.position, k)
			var dist := CAM_DIST * _zoom
			if ParkMap.home != null:
				# Evde: yukaridan, tavan ve aradaki duvarlar gorunmez
				dist = clampf(dist, 3.2, 6.0)
				_cam_pitch = maxf(_cam_pitch, 0.75)
				ParkMap.home.update_view(cam.global_position)
			var pos := _focus + Vector3(0, 1.3, 0) + Vector3(sin(_cam_yaw) * cos(_cam_pitch), sin(_cam_pitch), cos(_cam_yaw) * cos(_cam_pitch)) * dist
			pos.y = maxf(pos.y, ParkMap.walk_height(Vector2(pos.x, pos.z)) + 0.5)
			cam.position = pos
			cam.look_at(_focus + Vector3(0, 1.55, 0))


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

## Menulerden gecen uctan uca deneme: yeni oyun, alisveris, giydirme, sahiplenme, fotograf, menuye donus.
func _debug_flow() -> void:
	ui.show_screen("menu")
	ui.show_screen("setup")
	ui.start_game.emit("erkek", "kedi", "Mırmır")
	await get_tree().create_timer(0.5).timeout
	state.d["coins"] = 600
	ui.open_shop("food")
	await get_tree().create_timer(0.2).timeout
	ui.open_shop("acc")
	await get_tree().create_timer(0.2).timeout
	ui.open_shop("pets")
	await get_tree().create_timer(0.2).timeout
	for b in ui.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.find_child("Text", true, false) and (b.find_child("Text", true, false) as Label).text == str(state.ADOPT_PRICE):
			b.pressed.emit()
			break
	await get_tree().create_timer(0.3).timeout
	state.d["owned"].append("bere")
	ui.open_closet("hat")
	await get_tree().create_timer(0.3).timeout
	state.pet("kedi")["worn"]["hat"] = "bere"
	ui.worn_changed.emit()
	ui.open_closet("paws")
	ui.close_modal()
	ui.select_pet.emit("kopek")
	_on_command("play")
	await get_tree().create_timer(1.0).timeout
	ui.open_quests()
	ui.open_pause()
	ui.close_modal()
	_on_photo("enter")
	_on_photo("pose:sit")
	_on_photo("pose:hop")
	_on_photo("pose:look")
	_on_photo("exit")
	map_screen.open(_owner_pos())
	await get_tree().create_timer(0.2).timeout
	map_screen.select_by_name("Pet Shop")
	map_screen._go()
	await get_tree().create_timer(3.0).timeout
	_on_command("icecream")
	_on_command("npcplay")
	_on_command("sleep")
	_on_command("come")
	ui.back_to_menu.emit()
	ui.continue_game.emit()
	print("AKIS tamam: sahip=%s hayvanlar=%s aktif=%s giyilen=%s mesafe=%.0f" % [state.d["owner"], state.owned_pets(), state.d["active"],
		state.pet("kedi")["worn"], _owner_pos().distance_to(ParkMap.spot("baslangic"))])

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
	if _args.has("shop"):
		for sp in world.shop_spots:
			if sp.get("kind", "") == _args["shop"]:
				if _args.has("sick"):
					state.pet(state.d["active"])["sick"] = "Öksürük"
				_enter_shop(sp)
				if _args.has("vetexam"):
					_place_owner(_shop.w2(_shop.exam_local))
					_open_vet()
				if _args.has("store"):
					_take_basket()
					for id in ["simit", "simit", "mama", "dondurma", "su"]:
						_put_in_basket(id)
					_place_owner(_shop.w2(Vector2(3.0, 3.15)))
				break
	if _args.has("follow"):
		# Test: bir bisikletliyi / arabayi arkadan izle, sinyali zorla
		var tgt: Node3D = _cyclists[0] if _args["follow"] == "bike" else _cars[1]
		_mode = "debug"
		ui.visible = false
		for f in 400:
			tgt.turn_sign = -1 if _args["follow"] == "bike" else 1
			var fw := -tgt.global_basis.z
			var side := tgt.global_basis.x
			cam.global_position = tgt.global_position + (fw * 3.2 - side * 2.4 + Vector3(0, 1.6, 0) if _args["follow"] == "bike" else -fw * 4.2 + side * 1.2 + Vector3(0, 1.4, 0))
			cam.look_at(tgt.global_position + Vector3(0, 1.0, 0))
			await get_tree().process_frame
			if f > 120 and fmod(_blink_t, 0.8) < 0.3:
				break
	if _args.has("perf"):
		await get_tree().create_timer(6.0).timeout
		var t0 := Time.get_ticks_usec()
		var f0 := Engine.get_process_frames()
		await get_tree().create_timer(5.0).timeout
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(Engine.get_process_frames() - f0)
		print("PERF kare=%.1f ms  islem=%.2f ms  kisi=%d" % [ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, _npc_people.size()])
		get_tree().quit()
	if _args.has("jumptest"):
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = true
		Input.parse_input_event(ev)
		for f in 30:
			await get_tree().process_frame
			if f % 5 == 0:
				print("ZIPLA ", f, " h=", snappedf(_jump_h, 0.01), " model_y=", snappedf(owner_model.position.y, 0.01), " mode=", _mode)
	if _args.has("job"):
		if _args["job"] == "dog":
			_start_dog_walk()
		else:
			_start_courier()
		if _args.has("jobrun"):
			print("IS ", _job_text(), " ucret=", _job["pay"])
			for step in 3:
				if _job.is_empty():
					break
				await get_tree().create_timer(0.5).timeout
				_place_owner(_job["client_pos"] if _job["type"] == "dog" and _job["stage"] == "back" else _job["target"])
				await get_tree().create_timer(0.5).timeout
				print("IS ADIM ", step, " ", _job_text() if not _job.is_empty() else "bitti", " para=", state.d["coins"])
	if _args.has("summon"):
		if _args["summon"] == "car":
			_summon_my_car()
		else:
			_call_taxi(_args["summon"])
	if _args.has("outfit"):
		_wear_outfit(int(_args["outfit"]))
	if _args.has("playride") and not world.play_rides.is_empty():
		var pr: Dictionary = world.play_rides[int(_args["playride"]) % world.play_rides.size()]
		_place_owner(pr["pos"])
		_start_play_ride(pr)
		print("OYUN ", pr["kind"], " ", pr["pos"])
	if _args.has("home"):
		_enter_home()
		if _args.has("room"):
			var rp: PackedStringArray = _args["room"].split(",")
			var lp := Vector2(float(rp[0]), float(rp[1]))
			_place_owner(_home.w2(lp))
			var i := 0
			for k in agents:
				agents[k].place(_home.w2(lp + Vector2(0.7 + 0.5 * i, 0.4)))
				i += 1
		for f in 3:
			await get_tree().process_frame
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
				"settings": ui.open_settings()
				"map": map_screen.open(_owner_pos())
				"photo": _on_photo("enter")
			if _args.has("cmd"):
				var c: String = _args["cmd"]
				if c == "throw":
					_throw_to(_owner_pos() + Vector2(float(_args.get("tx", "-3")), float(_args.get("tz", "-8"))))
				elif c == "walk":
					_go(_owner_pos() + Vector2(float(_args.get("dx", "0")), float(_args.get("dz", "-30"))))
				elif c == "flow":
					await _debug_flow()
				elif c == "route":
					walk_to(Vector2(float(_args.get("tx", "0")), float(_args.get("tz", "0"))))
				elif c == "pin":
					map_screen.select_by_name(_args.get("pin", "Pet Shop"))
				else:
					_on_command(c)
		if view == "top":
			set_process(false)
			env.fog_enabled = false
			world.hide_clouds()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(_args.get("size", "900"))
			cam.position = Vector3(float(_args.get("cx", "0")), 400, float(_args.get("cz", "0")))
			cam.rotation = Vector3(-PI / 2, 0, 0)
		elif view == "wide":
			var wc := Vector3(float(_args.get("cx", "0")), 0, float(_args.get("cz", "0")))
			wc.y = ParkMap.terrain_height(Vector2(wc.x, wc.z))
			_mode = "debug"
			cam.position = wc + Vector3(8, 30, 48) * float(_args.get("dist", "1"))
			cam.look_at(wc)
		elif view == "look":
			# Dunyada serbest bakis: --look=x,y,z,hx,hy,hz
			_mode = "debug"
			var e: PackedStringArray = _args["look"].split(",")
			cam.position = Vector3(float(e[0]), float(e[1]), float(e[2]))
			cam.look_at(Vector3(float(e[3]), float(e[4]), float(e[5])))
		elif view == "eye" and _home:
			# Ev icinde sabit bakis: --eye=x,z,hedefx,hedefz (yerel metre)
			_mode = "debug"
			var e: PackedStringArray = _args["eye"].split(",")
			var p0: Vector2 = _home.w2(Vector2(float(e[0]), float(e[1])))
			var p1: Vector2 = _home.w2(Vector2(float(e[2]), float(e[3])))
			var fy := _home.global_position.y
			cam.position = Vector3(p0.x, fy + 1.6, p0.y)
			cam.look_at(Vector3(p1.x, fy + 1.0, p1.y))
			cam.fov = 75.0
		elif view == "low":
			_mode = "debug"
			var a := float(_args.get("ang", "0.5"))
			var dist := float(_args.get("dist", "4.5"))
			var t := owner_node.position + Vector3(0, 0.8, 0)
			cam.position = t + Vector3(sin(a) * dist, 0.9, cos(a) * dist)
			cam.look_at(t)
	if _args.has("lineup"):
		# Modelleri yan yana diz (yon denetimi): on tarafinda kirmizi top
		var names: PackedStringArray = _args["lineup"].split(",")
		var o := _owner_pos()
		for i in names.size():
			var parts := names[i].split(":")
			var v := _vehicle("res://assets/models/%s.glb" % parts[0], float(parts[1]) if parts.size() > 1 else 4.0, parts.size() > 2)
			if v == null:
				continue
			var at := o + Vector2(-(names.size() - 1) * 3.5 + i * 7.0, -6.0)
			v.position = Vector3(at.x, ParkMap.terrain_height(at), at.y)
			v.rotation.y = PI / 2.0     # on (-Z) sola baksin
			add_child(v)
			Kit.ball(v, 0.25, Vector3(0, 2.0, -float(parts[1]) * 0.55 if parts.size() > 1 else -2.2), Kit.mat("ff0000", 0.5))
	if _args.has("travel") and not _debug_traveled:
		_debug_traveled = true
		print("YOLCULUK ", ParkMap.zone, " -> ", _args["travel"])
		for st in METRO_STOPS:
			if st[0] == _args["travel"]:
				_travel(st[0], st[1])
				if _metro and _args.has("fastride"):
					_metro.fast = true
				break
	if _args.has("busride"):
		# Bir otobus durakta beklerken yanina git ve bin
		for i in 400:
			for b in _buses:
				if b.at_stop != "" and b.visible and ParkMap.inside_bounds(Vector2(b.position.x, b.position.z), 20.0):
					owner_node.position = b.position + Vector3(3, 0, 0)
					_enter_bus()
					break
			if _bus_ride:
				print("BINDI %s %s" % [_bus_ride.line, _bus_ride.at_stop])
				break
			await get_tree().create_timer(0.5).timeout
	if _args.has("nav"):
		var pin_i := int(_args["nav"])
		_set_nav(map_screen.PINS[pin_i][2])
	if _args.has("taxiride"):
		await get_tree().create_timer(1.0).timeout
		var tx: Node3D = null
		for c in _cars:
			if _car_model(c) == "taksi" and c.hold > 0.0:
				tx = c
		if tx:
			_set_nav(map_screen.PINS[int(_args["taxiride"])][2])
			owner_node.position = tx.position + Vector3(1.5, 0, 0)
			_board_taxi(tx)
			print("TAKSIYE BINDI ", _taxi != null, " yol=", _taxi_path.size())
	if _args.has("drive") and not _rides.is_empty():
		for r in _rides:
			if r.get_meta("kind") == (_args["drive"] if _args["drive"] != "1" else "araba"):
				owner_node.position = r.position + Vector3(1.0, 0, 0)
		_enter_ride()
		_fps = _args.has("fps")
	if _args.has("trace"):
		for i in int(_args["trace"]):
			if _args.get("cmd", "") == "stick":
				ui.stick = Vector2(float(_args.get("sx", "-1")), float(_args.get("sy", "0")))
			await get_tree().create_timer(2.0).timeout
			print("IZ %d %s moving=%s queue=%d%s" % [i * 2, _owner_pos(), _moving, _queue.size(),
				(" otobus=%s durak=%s hiz=%.1f" % [_bus_ride.line, _bus_ride.at_stop, _bus_ride.speed]) if _bus_ride else (" ev_yerel=%s" % _home.local2(_owner_pos()) if ParkMap.home else "")])
	if _args.has("secs"):
		await get_tree().create_timer(float(_args["secs"])).timeout
	if _args.has("more"):
		ui._on_action("more")
		await get_tree().process_frame
		await get_tree().process_frame
	if _args.has("panim"):
		agents[state.d["active"]].model.force_speed = float(_args["panim"])
		await get_tree().create_timer(float(_args.get("wait", "1.0"))).timeout
	if _args.has("anim"):
		owner_model.force_speed = float(_args["anim"])
		await get_tree().create_timer(float(_args.get("wait", "1.0"))).timeout
	if _args.has("chase"):
		# Yuruyen karakteri yandan goster (animasyon denetimi)
		_mode = "debug"
		var ct := owner_node.position + Vector3(0, 0.85, 0)
		if _args["chase"] == "hand":
			ct = owner_model.hand.global_position
		if _args["chase"] == "pet":
			ct = agents[state.d["active"]].model.global_position + Vector3(0, 0.3, 0)
		var ca := float(_args.get("ang", "0.5"))
		var cd := float(_args.get("dist", "4.5"))
		cam.position = ct + Vector3(sin(ca) * cd, 0.5, cos(ca) * cd)
		cam.look_at(ct)
		await get_tree().process_frame
		await get_tree().process_frame
	var report := {"coins": state.d["coins"], "foods": state.d["foods"], "quests": state.d["quests"], "places": state.d["places"],
		"owner": _owner_pos()}
	for k in agents:
		var p: Dictionary = state.pet(k)
		report[k] = "mode=%d pose=%s pos=%s hunger=%.0f energy=%.0f fun=%.0f clean=%.0f xp=%.1f" % [agents[k].mode, agents[k].model.pose,
			agents[k].pos2(), p["hunger"], p["energy"], p["fun"], p["clean"], p["xp"]]
	print("RAPOR ", report)
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(_args["shot"])
	get_tree().quit()
