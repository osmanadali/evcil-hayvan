extends Node3D
## M4 metro yolculugu: yer alti peronu, trenin gelisi, kapilarin acilmasi, vagon ici yolculuk ve anonslar.
## Sahne yerin cok altinda kurulur (y = -400); kamera bu sinif tarafindan yonetilir.
## Durak arasi ~20 sn; "Hizlandir" ile atlanabilir.

signal finished(station: String)
signal announce(text: String)

const Kit = preload("res://scripts/kit.gd")
const LINE := ["Belediye", "Meteoroloji", "Dışkapı", "ASKİ", "Atatürk Kültür Merkezi", "Gar", "Adliye"]
const LEG_TIME := 20.0
const CAR_H := 3.5            # gercek metro vagonu ~3.5 m yuksek
const PLAT_Z := 0.95          # peron kenari
const STAIR_Z0 := 6.3         # merdiven basi (peron seviyesi)
const STAIR_Z1 := 16.0        # merdiven sonu (ust kat)
const UPPER_Y := 6.0
const EXIT_Z := 19.5          # ust holde turnikelerin ardi: cikis

var cam: Camera3D
var owner_node: Node3D
var owner_model: Node3D
var stick := Vector2.ZERO      # main'den: oyuncu cubugu / klavye
var CAR_LEN := 20.0
var _walk_p := Vector2.ZERO    # yerel konum (x, z)
var _cam_dir := -1.0           # -1: kamera +z'de, -z'ye bakar; +1 tersi
var _cam_pos := Vector3.ZERO
var pets: Array = []
var from_station := ""
var to_station := ""
var _stops: Array = []         # gecilecek istasyonlar (sirayla, son = hedef)
var _phase := "peron"          # peron -> geliyor -> kapilar -> yolculuk -> varis -> bitti
var _t := 0.0
var _leg := 0
var _train: Node3D
var _doors: Array[Node3D] = []
var _platform: Node3D
var _tunnel: Node3D
var _tunnel_lights: Array[Node3D] = []
var _inside: Node3D
var _sign_labels: Array[Label3D] = []
var _chime: AudioStreamPlayer
var _speed := 0.0
var fast := false


func _ready() -> void:
	position = Vector3(0, -400, 0)
	_build_platform()
	_build_tunnel()
	_build_train()
	_build_inside()
	_chime = AudioStreamPlayer.new()
	_chime.stream = _make_chime()
	_chime.volume_db = -8.0
	add_child(_chime)


func begin(from: String, to: String) -> void:
	from_station = from
	to_station = to
	var a := LINE.find(from)
	var b := LINE.find(to)
	if a < 0:
		a = 1
	if b < 0 or b == a:
		b = clampi(a + 1, 0, LINE.size() - 1)
	var step := 1 if b > a else -1
	_stops.clear()
	var k := a + step
	while k != b + step and k >= 0 and k < LINE.size():
		_stops.append(LINE[k])
		k += step
	print("METRO ", from, " -> ", to, " ", _stops)
	_set_station_name(from)
	_phase = "iniyor"
	_t = 0.0
	_train.position.x = -CAR_LEN * 7.0
	_open_doors(0.0)
	_cam_dir = -1.0
	_platform.visible = true
	_train.visible = true
	_tunnel.visible = true
	_inside.visible = false
	_walk_p = Vector2(0.0, EXIT_Z - 0.5)
	owner_node.rotation.y = 0.0
	owner_node.visible = true
	_place_walkers(0.0)
	_cam_pos = Vector3.ZERO
	announce.emit("%s istasyonu · Merdivenden perona in" % from)


# ---------------------------------------------------------------- yapim

func _mat(hex: String, rough := 0.6) -> StandardMaterial3D:
	return Kit.mat(hex, rough)


func _build_platform() -> void:
	_platform = Node3D.new()
	add_child(_platform)
	var tile := StandardMaterial3D.new()
	tile.albedo_texture = load("res://assets/home/karo_beyaz.jpg")
	tile.uv1_scale = Vector3(30, 4, 1)
	tile.albedo_color = Color("d9d6cf")
	tile.roughness = 0.3
	Kit.box(_platform, Vector3(70, 0.3, 6), Vector3(0, -0.15, 3.5), tile)                 # peron
	Kit.box(_platform, Vector3(70, 0.06, 0.4), Vector3(0, 0.01, 0.75), _mat("e8c22a", 0.5))    # sari guvenlik seridi
	Kit.box(_platform, Vector3(70, 0.3, 4.5), Vector3(0, -1.35, -1.5), _mat("3a3836", 0.9))    # ray yatagi
	for z in [-0.8, -2.2]:
		Kit.box(_platform, Vector3(70, 0.15, 0.08), Vector3(0, -1.12, z), _mat("8d8f92", 0.3))  # raylar
	var wall := _mat("e2ddd2", 0.7)
	# Arka duvar: ortada merdiven acikligi
	Kit.box(_platform, Vector3(33.6, 6.5, 0.3), Vector3(-18.6, 2.5, 6.6), wall)
	Kit.box(_platform, Vector3(33.6, 6.5, 0.3), Vector3(18.6, 2.5, 6.6), wall)
	Kit.box(_platform, Vector3(4.6, 1.2, 0.3), Vector3(0, 5.2, 6.6), wall)
	_build_stairs(tile, wall)
	Kit.box(_platform, Vector3(70, 7.5, 0.3), Vector3(0, 2.2, -4.0), _mat("bdb6a8", 0.8)) # karsi duvar
	Kit.box(_platform, Vector3(70, 0.3, 11), Vector3(0, 5.6, 1.3), _mat("9a958c", 0.8))    # tavan
	# Kirmizi serit ve istasyon adlari
	Kit.box(_platform, Vector3(33.6, 0.5, 0.05), Vector3(-18.6, 2.2, 6.43), _mat("c8322b", 0.5))
	Kit.box(_platform, Vector3(33.6, 0.5, 0.05), Vector3(18.6, 2.2, 6.43), _mat("c8322b", 0.5))
	Kit.box(_platform, Vector3(70, 0.5, 0.05), Vector3(0, 2.2, -3.83), _mat("c8322b", 0.5))
	for x in [-24.0, -9.0, 9.0, 24.0]:
		for side in [[6.4, PI], [-3.8, 0.0]]:
			Kit.box(_platform, Vector3(6.0, 1.0, 0.06), Vector3(x, 3.3, side[0] + (-0.06 if side[1] == PI else 0.06)), _mat("1d2a33", 0.4))
			var l := Label3D.new()
			l.font_size = 96
			l.pixel_size = 0.009
			l.modulate = Color.WHITE
			l.position = Vector3(x, 3.3, side[0] + (-0.1 if side[1] == PI else 0.1))
			l.rotation.y = side[1]
			l.double_sided = false
			_platform.add_child(l)
			_sign_labels.append(l)
	# Tavan isiklari
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color.WHITE
	lamp.emission_enabled = true
	lamp.emission = Color("fff6e6")
	lamp.emission_energy_multiplier = 2.0
	for x in range(-32, 33, 8):
		Kit.box(_platform, Vector3(4.0, 0.06, 0.4), Vector3(x, 5.42, 3.2), lamp)
	for x in range(-30, 31, 15):
		var o := OmniLight3D.new()
		o.position = Vector3(x, 4.6, 2.5)
		o.omni_range = 16.0
		o.light_energy = 1.6
		o.light_color = Color("fff3e0")
		_platform.add_child(o)
	# Banklar ve kolonlar
	for x in [-18.0, -6.0, 6.0, 18.0]:
		Kit.box(_platform, Vector3(0.6, 5.7, 0.6), Vector3(x, 2.7, 4.6), _mat("cfc9bd", 0.6))
		Kit.box(_platform, Vector3(2.0, 0.08, 0.45), Vector3(x + 2.0, 0.45, 5.9), _mat("8d8f92", 0.3))


## Peron ile ust hol arasi merdiven, ust hol, turnikeler ve cikis levhasi.
func _build_stairs(tile: Material, wall: Material) -> void:
	var steps := 24
	var dz := (STAIR_Z1 - STAIR_Z0) / steps
	var dy := UPPER_Y / steps
	var stone := _mat("bdb8ad", 0.6)
	for i in steps:
		var y := (i + 1) * dy
		Kit.box(_platform, Vector3(4.2, y, dz), Vector3(0, y * 0.5, STAIR_Z0 + (i + 0.5) * dz), stone)
		Kit.box(_platform, Vector3(4.2, 0.03, 0.06), Vector3(0, y + 0.005, STAIR_Z0 + i * dz + 0.04), _mat("e8c22a", 0.5))
	var run := STAIR_Z1 - STAIR_Z0
	var slope := atan2(UPPER_Y, run)
	var steel := _mat("c9cdd1", 0.2)
	steel.metallic = 0.7
	for sx in [-1.0, 1.0]:
		Kit.box(_platform, Vector3(0.3, 10.5, run + 0.4), Vector3(sx * 2.25, 4.0, STAIR_Z0 + run * 0.5), wall)   # yan duvarlar
		Kit.cyl(_platform, 0.03, 0.03, sqrt(run * run + UPPER_Y * UPPER_Y), Vector3(sx * 1.95, UPPER_Y * 0.5 + 0.95, STAIR_Z0 + run * 0.5),
			steel, 8, Vector3(PI / 2 - slope, 0, 0))   # tirabzan
	Kit.box(_platform, Vector3(4.8, 0.3, run + 1.0), Vector3(0, UPPER_Y * 0.5 + 4.6, STAIR_Z0 + run * 0.5), _mat("9a958c", 0.8), Vector3(-slope, 0, 0))
	# Ust hol
	Kit.box(_platform, Vector3(12, 0.3, 6), Vector3(0, UPPER_Y - 0.15, STAIR_Z1 + 3.0), tile)
	Kit.box(_platform, Vector3(12, 0.3, 6.4), Vector3(0, UPPER_Y + 3.6, STAIR_Z1 + 3.0), _mat("9a958c", 0.8))
	for sx in [-1.0, 1.0]:
		Kit.box(_platform, Vector3(0.3, 3.8, 6.4), Vector3(sx * 6.0, UPPER_Y + 1.8, STAIR_Z1 + 3.0), wall)
	Kit.box(_platform, Vector3(12, 3.8, 0.3), Vector3(0, UPPER_Y + 1.8, STAIR_Z1 + 6.1), wall)
	for sx in [-1.0, 1.0]:
		Kit.box(_platform, Vector3(3.8, 3.8, 0.3), Vector3(sx * 4.1, UPPER_Y + 1.8, STAIR_Z1), wall)
	# Turnikeler
	for x in [-1.6, -0.55, 0.55, 1.6]:
		Kit.box(_platform, Vector3(0.22, 1.0, 1.2), Vector3(x, UPPER_Y + 0.5, STAIR_Z1 + 1.8), _mat("8d9196", 0.3))
		Kit.box(_platform, Vector3(0.24, 0.04, 0.3), Vector3(x, UPPER_Y + 1.02, STAIR_Z1 + 1.5), _mat("2fa84f", 0.3))
	# Cikis levhasi
	Kit.box(_platform, Vector3(3.6, 0.7, 0.06), Vector3(0, UPPER_Y + 2.8, STAIR_Z1 + 5.9), _mat("1f6f3a", 0.4))
	var l := Label3D.new()
	l.text = "ÇIKIŞ · EXIT"
	l.font_size = 64
	l.pixel_size = 0.008
	l.position = Vector3(0, UPPER_Y + 2.8, STAIR_Z1 + 5.85)
	l.rotation.y = PI
	_platform.add_child(l)
	var down := Label3D.new()
	down.text = "↓ Peron · Platform"
	down.font_size = 48
	down.pixel_size = 0.008
	down.position = Vector3(0, UPPER_Y + 3.0, STAIR_Z1 + 0.18)
	_platform.add_child(down)
	var o := OmniLight3D.new()
	o.position = Vector3(0, UPPER_Y + 3.0, STAIR_Z1 + 3.0)
	o.omni_range = 10.0
	o.light_energy = 1.5
	_platform.add_child(o)
	var o2 := OmniLight3D.new()
	o2.position = Vector3(0, UPPER_Y * 0.5 + 3.5, STAIR_Z0 + run * 0.5)
	o2.omni_range = 9.0
	o2.light_energy = 1.2
	_platform.add_child(o2)


func _set_station_name(name: String) -> void:
	for l in _sign_labels:
		l.text = name.to_upper()


func _build_tunnel() -> void:
	_tunnel = Node3D.new()
	add_child(_tunnel)
	var dark := _mat("2a2826", 0.95)
	Kit.box(_tunnel, Vector3(400, 0.2, 6), Vector3(-235, -1.4, -1.5), dark)
	Kit.box(_tunnel, Vector3(400, 0.2, 6), Vector3(235, -1.4, -1.5), dark)
	for x in [-235.0, 235.0]:
		Kit.box(_tunnel, Vector3(400, 6, 0.2), Vector3(x, 1.5, 1.5), dark)
		Kit.box(_tunnel, Vector3(400, 6, 0.2), Vector3(x, 1.5, -4.5), dark)
		Kit.box(_tunnel, Vector3(400, 0.2, 6), Vector3(x, 4.5, -1.5), dark)
	# Tunel lambalari: yolculukta pencereden kayar
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color.WHITE
	lamp.emission_enabled = true
	lamp.emission = Color("ffd9a0")
	lamp.emission_energy_multiplier = 3.0
	for i in 12:
		var n := Node3D.new()
		n.position = Vector3(-200 + i * 16.0, 2.6, 1.3)
		Kit.box(n, Vector3(1.2, 0.12, 0.08), Vector3.ZERO, lamp)
		_tunnel.add_child(n)
		_tunnel_lights.append(n)


func _build_train() -> void:
	_train = Node3D.new()
	add_child(_train)
	if ResourceLoader.exists("res://assets/models/metro.glb"):
		CAR_LEN = _load_car().get_meta("len")
	for i in 3:
		var car: Node3D = null
		if ResourceLoader.exists("res://assets/models/metro.glb"):
			car = _load_car()
		if car == null:
			car = Node3D.new()
			Kit.box(car, Vector3(CAR_LEN - 0.4, 3.2, 2.8), Vector3(0, 1.0, 0), _mat("c9cdd1", 0.3))
		car.position = Vector3(i * CAR_LEN, -1.2, -1.5)
		_train.add_child(car)
		# Kapilar: peron tarafinda uc cift; acilinca yana kayar
		for k in 3:
			var x := i * CAR_LEN - CAR_LEN * 0.3 + k * CAR_LEN * 0.3
			for s in [-1.0, 1.0]:
				var d := Node3D.new()
				d.position = Vector3(x + s * 0.35, 0.0, 0.05)
				d.set_meta("closed_x", x + s * 0.35)
				d.set_meta("dir", s)
				Kit.box(d, Vector3(0.7, 2.0, 0.06), Vector3(0, 0.95, 0), _mat("b8bcc0", 0.25))
				Kit.box(d, Vector3(0.5, 1.0, 0.065), Vector3(0, 1.3, 0), _mat("2b3540", 0.1))
				_train.add_child(d)
				_doors.append(d)


func _load_car() -> Node3D:
	var inst: Node3D = load("res://assets/models/metro.glb").instantiate()
	var holder := Node3D.new()
	var pivot := Node3D.new()
	holder.add_child(pivot)
	pivot.add_child(inst)
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
	# Uzun eksen x olsun
	if box.size.z > box.size.x:
		pivot.rotation.y = PI / 2.0
	var k := CAR_H / box.size.y
	pivot.scale = Vector3.ONE * k
	holder.set_meta("len", maxf(box.size.x, box.size.z) * k + 0.6)
	var c := box.get_center()
	pivot.position = Basis(Vector3.UP, pivot.rotation.y) * Vector3(-c.x, 0, -c.z) * k
	pivot.position.y = -box.position.y * k
	return holder


## Vagon ici: oturaklar, tutunma direkleri, isiklar, pencereler (disarisi tunel).
func _build_inside() -> void:
	_inside = Node3D.new()
	_inside.position = Vector3(0, 0, 40)      # perondan ayri bir yerde
	add_child(_inside)
	var floor_m := _mat("4a4d52", 0.8)
	var wall := _mat("dfe2e4", 0.4)
	Kit.box(_inside, Vector3(18, 0.1, 2.7), Vector3(0, 0, 0), floor_m)
	Kit.box(_inside, Vector3(18, 0.1, 2.7), Vector3(0, 2.3, 0), _mat("eceeef", 0.4))
	for z in [-1.4, 1.4]:
		Kit.box(_inside, Vector3(18, 0.9, 0.08), Vector3(0, 0.45, z), wall)
		Kit.box(_inside, Vector3(18, 0.5, 0.08), Vector3(0, 2.05, z), wall)
		for x in range(-8, 9, 3):
			Kit.box(_inside, Vector3(0.25, 0.9, 0.09), Vector3(x, 1.35, z), wall)    # pencere aralari
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.05, 0.06, 0.55)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Pencerelerin disinda karanlik tunel duvari
	for z in [-2.6, 2.6]:
		Kit.box(_inside, Vector3(60, 4.0, 0.2), Vector3(0, 1.3, z), _mat("1c1b1a", 0.95))
	for z in [-2.4, 2.4]:
		for y in [0.6, 2.2]:
			Kit.box(_inside, Vector3(60, 0.06, 0.06), Vector3(0, y, z), _mat("3d3b38", 0.8))   # kablolar
	for z in [-1.42, 1.42]:
		Kit.box(_inside, Vector3(18, 0.9, 0.02), Vector3(0, 1.35, z), glass)
	var seat := _mat("2f62a8", 0.6)
	for x in range(-7, 8, 3):
		for z in [-1.1, 1.1]:
			Kit.box(_inside, Vector3(2.0, 0.08, 0.45), Vector3(x, 0.48, z), seat)
			Kit.box(_inside, Vector3(2.0, 0.5, 0.06), Vector3(x, 0.75, z + signf(z) * 0.22), seat)
	var steel := _mat("c9cdd1", 0.15)
	steel.metallic = 0.8
	for x in range(-8, 9, 2):
		Kit.cyl(_inside, 0.025, 0.025, 2.3, Vector3(x, 1.15, 0.0), steel, 8)
	Kit.cyl(_inside, 0.02, 0.02, 18.0, Vector3(0, 2.0, 0.5), steel, 6, Vector3(0, 0, PI / 2))
	Kit.cyl(_inside, 0.02, 0.02, 18.0, Vector3(0, 2.0, -0.5), steel, 6, Vector3(0, 0, PI / 2))
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color.WHITE
	lamp.emission_enabled = true
	lamp.emission = Color("f4f8ff")
	lamp.emission_energy_multiplier = 1.8
	Kit.box(_inside, Vector3(17, 0.04, 0.3), Vector3(0, 2.24, 0), lamp)
	for x in [-6.0, 0.0, 6.0]:
		var o := OmniLight3D.new()
		o.position = Vector3(x, 2.0, 0)
		o.omni_range = 6.0
		o.light_energy = 1.2
		_inside.add_child(o)
	# Kayan tunel isiklari pencerenin disinda
	var tl := StandardMaterial3D.new()
	tl.albedo_color = Color.WHITE
	tl.emission_enabled = true
	tl.emission = Color("ffcf8a")
	tl.emission_energy_multiplier = 4.0
	for i in 10:
		var n := Node3D.new()
		n.name = "TL%d" % i
		n.position = Vector3(-20 + i * 4.5, 1.6, -2.4 if i % 2 == 0 else 2.4)
		Kit.box(n, Vector3(0.6, 0.08, 0.05), Vector3.ZERO, tl)
		_inside.add_child(n)
	# Kapi ustu bilgi ekrani
	var info := Label3D.new()
	info.name = "Bilgi"
	info.font_size = 54
	info.pixel_size = 0.004
	info.modulate = Color("ff9a3c")
	info.position = Vector3(5.5, 2.05, 1.32)
	info.rotation.y = PI
	_inside.add_child(info)
	Kit.box(_inside, Vector3(2.4, 0.3, 0.04), Vector3(5.5, 2.05, 1.36), _mat("101010", 0.3))


func _make_chime() -> AudioStreamWAV:
	var sr := 22050
	var data := PackedByteArray()
	var n := int(sr * 1.2)
	data.resize(n * 2)
	for i in n:
		var t := float(i) / sr
		var f := 659.0 if t < 0.45 else 523.0
		var env := exp(-(t if t < 0.45 else t - 0.45) * 4.0)
		var v := int(clampf(sin(TAU * f * t) * env * 0.5, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.data = data
	return w


# ---------------------------------------------------------------- akis

func _process(dt: float) -> void:
	if not visible:
		return
	var tdt := dt * (4.0 if fast else 1.0)
	_t += tdt
	match _phase:
		"iniyor":
			# Oyuncu merdivenden iner; perona varinca tren gelir
			_walk(dt)
			_follow_cam(dt)
			if _walk_p.y < STAIR_Z0 - 0.3:
				_phase = "geliyor"
				_t = 0.0
				announce.emit("Tren yaklaşıyor · Lütfen sarı çizginin gerisinde bekleyin")
		"geliyor":
			_walk(dt)
			_follow_cam(dt)
			var k := clampf(_t / 6.0, 0.0, 1.0)
			_train.position.x = lerpf(-CAR_LEN * 7.0, -CAR_LEN, 1.0 - pow(1.0 - k, 3.0))
			if k >= 1.0:
				_phase = "kapilar"
				_t = 0.0
				_chime.play()
				announce.emit("Kapılar açılıyor · Açık kapıya yürü ve bin")
		"kapilar":
			_open_doors(clampf(_t / 1.2, 0.0, 1.0))
			_walk(dt)
			_follow_cam(dt)
			# Acik bir kapinin onune yuruyunce bin
			var dx := _nearest_door_x(_walk_p.x)
			if _t > 1.2 and _walk_p.y < PLAT_Z + 0.9 and absf(dx - _walk_p.x) < 0.9:
				owner_node.visible = false
				for p in pets:
					p.visible = false
				_phase = "kapaniyor"
				_t = 0.0
		"kapaniyor":
			_open_doors(clampf(1.0 - _t / 1.0, 0.0, 1.0))
			if _t > 1.3:
				_phase = "yolculuk"
				_t = 0.0
				_leg = 0
				_platform.visible = false
				_train.visible = false
				_tunnel.visible = false
				_inside.visible = true
				announce.emit("Kapılar kapanıyor · Doors closing")
				_announce_next()
		"yolculuk":
			_inside_cam()
			_speed = 18.0 * clampf(minf(_t, LEG_TIME - _t) / 4.0, 0.0, 1.0)
			for i in 10:
				var n: Node3D = _inside.get_node("TL%d" % i)
				n.position.x -= _speed * tdt
				if n.position.x < -22.0:
					n.position.x += 45.0
			if _t >= LEG_TIME:
				_t = 0.0
				var here: String = _stops[_leg]
				_chime.play()
				if _leg == _stops.size() - 1:
					_arrive(here)
				else:
					announce.emit("%s istasyonu" % here)
					_leg += 1
					_announce_next()
		"cikis":
			# Varis peronu: tren birkac saniye bekler, sonra gider; oyuncu merdivenden cikar
			if _t < 4.0:
				_open_doors(clampf(_t / 1.0, 0.0, 1.0))
			else:
				_open_doors(clampf(1.0 - (_t - 4.0), 0.0, 1.0))
				if _t > 5.2:
					_train.position.x += clampf((_t - 5.2) * 6.0, 0.0, 25.0) * tdt
			_walk(dt)
			_follow_cam(dt)
			if _walk_p.y > EXIT_Z:
				_phase = "bitti"
				visible = false
				for p in pets:
					p.visible = true
				finished.emit(to_station)


func _arrive(station: String) -> void:
	_phase = "cikis"
	_t = 0.0
	_set_station_name(station)
	_inside.visible = false
	_platform.visible = true
	_train.visible = true
	_tunnel.visible = true
	_train.position.x = -CAR_LEN
	var dx := _nearest_door_x(0.0)
	_walk_p = Vector2(dx, PLAT_Z + 0.6)
	owner_node.visible = true
	owner_node.rotation.y = PI
	for p in pets:
		p.visible = true
	_place_walkers(0.0)
	_cam_dir = 1.0
	_cam_pos = Vector3.ZERO
	announce.emit("%s · İnilecek istasyon · Çıkış için merdivenden yukarı çık" % station)


func _announce_next() -> void:
	var nxt: String = _stops[_leg]
	(_inside.get_node("Bilgi") as Label3D).text = "Sıradaki: %s" % nxt
	announce.emit("Sıradaki istasyon: %s · Next station: %s" % [nxt, nxt])


func _open_doors(k: float) -> void:
	for d in _doors:
		d.position.x = float(d.get_meta("closed_x")) + float(d.get_meta("dir")) * 0.68 * k


## Yerel x'teki en yakin kapi ortasi (dunya-yerel).
func _nearest_door_x(x: float) -> float:
	var best := 1e9
	for d in _doors:
		var cx: float = float(d.get_meta("closed_x")) - float(d.get_meta("dir")) * 0.35 + _train.position.x
		if absf(cx - x) < absf(best - x):
			best = cx
	return best


# ---------------------------------------------------------------- yurume

func _inside_walk(p: Vector2) -> bool:
	if p.x > -33.0 and p.x < 33.0 and p.y > PLAT_Z + 0.25 and p.y < STAIR_Z0 - 0.2:
		return true
	if p.x > -1.75 and p.x < 1.75 and p.y >= STAIR_Z0 - 0.2 and p.y <= STAIR_Z1 + 0.2:
		return true
	if p.x > -5.6 and p.x < 5.6 and p.y > STAIR_Z1 + 0.2 and p.y < STAIR_Z1 + 5.7:
		# turnike sirasi: yalniz gecitlerden
		if absf(p.y - (STAIR_Z1 + 1.8)) < 0.7:
			for x in [-1.6, -0.55, 0.55, 1.6]:
				if absf(p.x - x) < 0.35:
					return false
			return absf(p.x) < 2.2
		return true
	return false


func _floor_y(p: Vector2) -> float:
	return clampf((p.y - STAIR_Z0) / (STAIR_Z1 - STAIR_Z0), 0.0, 1.0) * UPPER_Y


var auto := false    # test: kendi kendine yuru

func _auto_stick() -> Vector2:
	var goal := Vector2(0, 3.0)
	if _phase == "kapilar":
		goal = Vector2(_nearest_door_x(_walk_p.x), PLAT_Z + 0.5)
	elif _phase == "cikis":
		goal = Vector2(0, EXIT_Z + 1.0) if absf(_walk_p.x) < 0.5 or _walk_p.y > STAIR_Z0 else Vector2(0, _walk_p.y)
	elif _walk_p.y > STAIR_Z0 - 0.5:
		goal = Vector2(0, 2.0)
	var d := goal - _walk_p
	if d.length() < 0.1:
		return Vector2.ZERO
	return d.normalized() * 0.6 * -_cam_dir


func _walk(dt: float) -> void:
	var v := _auto_stick() if auto else stick
	if v.length() > 1.0:
		v = v.normalized()
	var mv := Vector2(v.x, v.y) * 4.6 * dt * _cam_dir * -1.0
	var p := _walk_p
	var np := p + mv
	if not _inside_walk(np):
		np = Vector2(np.x, p.y) if _inside_walk(Vector2(np.x, p.y)) else (Vector2(p.x, np.y) if _inside_walk(Vector2(p.x, np.y)) else p)
	_walk_p = np
	var moved := np.distance_to(p) / maxf(dt, 0.0001)
	if moved > 0.2:
		owner_node.rotation.y = lerp_angle(owner_node.rotation.y, atan2(-(np - p).x, -(np - p).y), minf(1.0, dt * 9.0))
	if owner_model and "speed" in owner_model:
		owner_model.speed = moved
	_place_walkers(dt)


func _place_walkers(dt: float) -> void:
	owner_node.global_position = global_position + Vector3(_walk_p.x, _floor_y(_walk_p), _walk_p.y)
	var back := Vector2(sin(owner_node.rotation.y), cos(owner_node.rotation.y))
	for i in pets.size():
		var pt: Node3D = pets[i]
		var want := _walk_p + back * (1.1 + i * 0.7) + Vector2(-back.y, back.x) * (0.5 if i % 2 == 0 else -0.5)
		if not _inside_walk(want):
			want = _walk_p
		var cur := Vector2(pt.global_position.x, pt.global_position.z) - Vector2(global_position.x, global_position.z)
		var nxt := cur.lerp(want, minf(1.0, dt * 3.0)) if dt > 0.0 else want
		pt.global_position = global_position + Vector3(nxt.x, _floor_y(nxt), nxt.y)
		var d := nxt - cur
		if d.length() > 0.005:
			pt.rotation.y = atan2(-d.x, -d.y)
		if "model" in pt and pt.model and "speed" in pt.model:
			pt.model.speed = d.length() / maxf(dt, 0.0001) if dt > 0.0 else 0.0


func _follow_cam(dt: float) -> void:
	var o := owner_node.global_position
	var want := o + Vector3(0, 2.3, -_cam_dir * 4.2)
	# Istasyonun icinde kal: duvarlarin disina cikma
	var l := want - global_position
	l.z = clampf(l.z, -3.4, STAIR_Z1 + 5.6)
	l.x = clampf(l.x, -32.0, 32.0)
	if l.z > STAIR_Z1 + 0.3:
		l.x = clampf(l.x, -5.4, 5.4)
		l.y = clampf(l.y, UPPER_Y + 0.5, UPPER_Y + 3.2)
	elif l.z > STAIR_Z0 - 0.3:
		l.x = clampf(l.x, -1.7, 1.7)
		var ceil_y := UPPER_Y * 0.5 + 4.3 + (l.z - (STAIR_Z0 + STAIR_Z1) * 0.5) * UPPER_Y / (STAIR_Z1 - STAIR_Z0)
		l.y = minf(l.y, ceil_y - 0.4)
	else:
		l.y = minf(l.y, 5.0)
	want = global_position + l
	if _cam_pos == Vector3.ZERO:
		_cam_pos = want
	_cam_pos = _cam_pos.lerp(want, minf(1.0, dt * 5.0))
	cam.global_position = _cam_pos
	cam.look_at(o + Vector3(0, 1.1, _cam_dir * 1.5))


func _platform_cam() -> void:
	var o := global_position
	cam.global_position = o + Vector3(14.0, 2.4, 5.6)
	cam.look_at(o + Vector3(-4.0, 1.0, -0.5))


func _inside_cam() -> void:
	var o := _inside.global_position
	cam.global_position = o + Vector3(7.5, 1.6, 0.9)
	cam.look_at(o + Vector3(-6.0, 1.2, -0.3))
