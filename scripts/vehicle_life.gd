extends Node
## Arac hayati ayrintilari:
## - Binme / inme hareketleri (araba: kapiya yuru, kapi acilir, koltuga kay; iki tekerli: soldan bacak asir)
## - Yan ayak (motosiklet, scooter, bisiklet): park halinde sola yatik, binince kaldirilir
## - Hayvanin aractaki yeri: bisiklette arka sepet, motosiklette depo ustu, scooterda ayak tablasi,
##   arabada kabin icinde serbest (yolcu koltugu, arka koltuk, cam kenari); Otur / Yat komutlari
## - Surus gostergesi (mini haritanin ustunde), arabada gosterge paneli ve aynalar

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const CarCabin = preload("res://scripts/car_cabin.gd")

const LEAN := 0.17            # park halinde sola yatma (radyan, ~10 derece)
const STAND_UP := -1.4
## Yan ayak: [mafsal, yere basan uc] (arac uzayi; sol = -X, on = -Z)
const STANDS := {
	"motosiklet": [Vector3(-0.10, 0.30, -0.02), Vector3(-0.25, 0.045, 0.0)],
	"scooter": [Vector3(-0.10, 0.28, 0.25), Vector3(-0.25, 0.045, 0.27)],
	"bisiklet": [Vector3(-0.05, 0.30, 0.42), Vector3(-0.19, 0.035, 0.46)],
}
## Hayvanin iki tekerlideki yeri: [konum, en buyuk boy (m), ayak acikligi (0 = degismez)]
const PET_SEATS := {
	"bisiklet": [Vector3(0, 0.822, 0.72), 0.46, 0.0],
	"motosiklet": [Vector3(0, 0.935, -0.07), 0.44, 0.0],
	"scooter": [Vector3(0, 0.425, 0.15), 0.36, 0.2],
}
## Arabada hayvanin durdugu yerler: [konum, sapma, poz, pati kaldirma, burun kaldirma]
const CAR_SPOTS := {
	"on": [Vector3(0.36, 0.555, 0.26), 0.0, "sit", 0.0, 0.0],
	"cam": [Vector3(0.40, 0.555, 0.2), -PI / 2, "stand", 1.0, 0.5],
	"arka": [Vector3(0.08, 0.59, 1.04), PI / 2, "lie", 0.0, 0.0],
	"arkacam": [Vector3(0.38, 0.59, 1.02), -PI / 2, "stand", 1.0, 0.5],
}

var m: Node
var instant := false          # test: hareketsiz, aninda bin / in
var _busy := false
var _anim_ride: Node3D        # hareketi suren arac (yan ayak / yatma bu sirada elle yonetilir)
var _pet := {}                # {a, mode: wait / fly / seat, spot, hold, t, next, from, k}
var _flights: Array = []      # inen hayvanlar: [ajan, nereden, nereye, t]
var _gauge: Control
var _mirror_i := 0
var _frame := 0
var _door: Node3D
var _door_ride: Node3D
var _dbg_cam: Array = []


class Gauge extends Control:
	var kmh := 0.0
	var maxv := 80.0
	var limit := 50
	var gear := ""
	var fuel := -1.0
	var font: Font
	var font2: Font

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 78.0)
		var r := 66.0
		var a0 := deg_to_rad(150.0)
		var sweep := deg_to_rad(240.0)
		draw_circle(c, r - 14.0, Color(0.04, 0.05, 0.07, 0.62))
		draw_arc(c, r, a0, a0 + sweep, 48, Color(0, 0, 0, 0.55), 13.0, true)
		var n := 30
		var f := clampf(kmh / maxv, 0.0, 1.0)
		var over := kmh > limit + 3
		for i in n:
			var s0 := a0 + sweep * (i + 0.12) / n
			var s1 := a0 + sweep * (i + 0.88) / n
			var on := float(i) / n < f - 0.001
			var seg_v := maxv * float(i) / n
			var col := Color(1, 1, 1, 0.16)
			if on:
				col = Color("ffffff").lerp(Color("ffd23c"), clampf(float(i) / n * 1.6, 0.0, 1.0))
				if seg_v >= limit and limit < maxv:
					col = Color("ff4a3a")
			elif seg_v >= limit and limit < maxv:
				col = Color(1.0, 0.3, 0.25, 0.3)
			draw_arc(c, r, s0, s1, 4, col, 8.0, true)
		# Ibre
		var an := a0 + sweep * f
		var nd := Vector2(cos(an), sin(an))
		draw_line(c + nd * (r - 22.0), c + nd * (r + 5.0), Color("ff3d6e") if not over else Color("ff4a3a"), 3.5, true)
		# Hiz sayisi ve birim
		var txt := str(int(round(kmh)))
		var fs := 42
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, c + Vector2(-w * 0.5, 10), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.7))
		draw_string(font, c + Vector2(-w * 0.5, 10), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("ff5a4a") if over else Color.WHITE)
		var uw := font2.get_string_size("km/sa", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font2, c + Vector2(-uw * 0.5, 27), "km/sa", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.75))
		# Vites rozeti
		if gear != "":
			var gr := Rect2(c.x - 15, c.y + 33, 30, 25)
			draw_style_box(_badge(), gr)
			var gw := font.get_string_size(gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			draw_string(font, Vector2(c.x - gw * 0.5, gr.position.y + 20), gear, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffd23c"))
		# Yakit: alt yayda kucuk cubuk (solda bos, sagda dolu)
		if fuel >= 0.0:
			var f0 := deg_to_rad(138.0)
			var f1 := deg_to_rad(42.0)
			draw_arc(c, r, f0, f1, 16, Color(0, 0, 0, 0.55), 7.0, true)
			var fc := Color("e5483b") if fuel < 0.15 else Color("4cc46a")
			if fuel > 0.01:
				draw_arc(c, r, f0, lerpf(f0, f1, fuel), 16, fc, 4.0, true)
			draw_string(font2, c + Vector2(-50, 56), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ff8a7a"))
			draw_string(font2, c + Vector2(43, 56), "D", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.8))

	func _badge() -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.08, 0.9)
		sb.set_corner_radius_all(7)
		sb.border_color = Color("ffd23c")
		sb.set_border_width_all(2)
		return sb


func busy() -> bool:
	return _busy


func _ready() -> void:
	m._sounds["clack"] = _make_clack()


## Kisa metalik "clack": sonumlenen gurultu + cinlama.
func _make_clack() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.09)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * 55.0)
		var v := (rng.randf_range(-1.0, 1.0) * 0.55 + sin(t * TAU * 1850.0) * 0.5 + sin(t * TAU * 620.0) * 0.35) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# ---------------------------------------------------------------- yardimcilar

func _flat(r: Node3D) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, r.rotation.y), r.position)


func _run(dur: float, step: Callable) -> void:
	var t := 0.0
	while t < dur:
		await get_tree().process_frame
		t += get_process_delta_time()
		step.call(clampf(t / dur, 0.0, 1.0))


func _ease(k: float) -> float:
	return smoothstep(0.0, 1.0, k)


func _is_two(r: Node3D) -> bool:
	return STANDS.has(String(r.get_meta("kind", "")))


func _set_grips(r: Node3D, cfg: Dictionary) -> void:
	if cfg.has("grip"):
		var g: Vector3 = cfg["grip"]
		m.owner_model.grips = [r.global_transform * Vector3(-g.x, g.y, g.z), r.global_transform * Vector3(g.x, g.y, g.z)]


func _stand_set(r: Node3D, down: float) -> void:
	if r.has_meta("stand"):
		(r.get_meta("stand") as Node3D).rotation.x = lerpf(STAND_UP, 0.0, down)
		r.set_meta("stand_k", down)


func _ground_foot(cfg: Dictionary, x: float, y := 0.15) -> Vector3:
	var seat: Vector3 = cfg["seat"]
	return Vector3(x, y, seat.z - 0.14)


## Iki tekerlilere yan ayak, bisiklete arka sepet takar.
func _dress(r: Node3D) -> void:
	r.set_meta("vl", true)
	var kind := String(r.get_meta("kind", ""))
	if not STANDS.has(kind):
		return
	var metal := Kit.mat("2a2c30", 0.4)
	metal.metallic = 0.7
	var pv: Vector3 = STANDS[kind][0]
	var ft: Vector3 = STANDS[kind][1]
	var stand := Node3D.new()
	stand.name = "YanAyak"
	stand.position = pv
	r.add_child(stand)
	var d := ft - pv
	var y := d.normalized()
	var x := y.cross(Vector3.BACK).normalized()
	var leg := Kit.cyl(stand, 0.011, 0.013, d.length(), d * 0.5, metal, 8)
	leg.basis = Basis(x, y, x.cross(y))
	Kit.box(stand, Vector3(0.07, 0.012, 0.035), d + Vector3(-0.015, -0.004, 0), metal, Vector3(0, 0, -LEAN))
	Kit.ball(stand, 0.02, Vector3.ZERO, metal)
	r.set_meta("stand", stand)
	r.set_meta("stand_k", 1.0)
	if kind == "bisiklet":
		_add_basket(r)


## Bisikletin arka portbagaji ve hasir hayvan sepeti.
func _add_basket(r: Node3D) -> void:
	var b := Node3D.new()
	b.name = "Sepet"
	b.position = Vector3(0, 0.8, 0.72)
	r.add_child(b)
	var metal := Kit.mat("3a3d42", 0.4)
	metal.metallic = 0.6
	var wick := Kit.mat("b98a52", 0.9)
	var wick2 := Kit.mat("8f6435", 0.9)
	var w := 0.34
	var l := 0.44
	var h := 0.2
	# Portbagaj: iki boyuna cubuk + tekerlek gobegine inen ayaklar
	for sx in [-1.0, 1.0]:
		Kit.cyl(b, 0.008, 0.008, l + 0.1, Vector3(sx * 0.07, -0.012, -0.03), metal, 6, Vector3(PI / 2, 0, 0))
		var strut := Kit.cyl(b, 0.007, 0.007, 0.5, Vector3(sx * 0.075, -0.24, -0.06), metal, 6, Vector3(0.42, 0, 0))
		strut.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Sepet: taban, hasir yan duvarlar (yatay seritli), yuvarlak kenar
	Kit.box(b, Vector3(w, 0.014, l), Vector3(0, 0.007, 0), wick2)
	var cush := Kit.ball(b, 1.0, Vector3(0, 0.02, 0), Kit.mat("c9463c", 1.0), Vector3(w * 0.44, 0.02, l * 0.44))
	cush.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-1.0, 1.0]:
		Kit.box(b, Vector3(0.012, h, l), Vector3(sx * w * 0.5, h * 0.5, 0), wick, Vector3(0, 0, -sx * 0.06))
		Kit.box(b, Vector3(w, h, 0.012), Vector3(0, h * 0.5, sx * l * 0.5), wick, Vector3(sx * 0.06, 0, 0))
		for k in 3:
			var yy := 0.045 + 0.055 * k
			Kit.box(b, Vector3(0.016, 0.012, l + 0.01), Vector3(sx * (w * 0.5 + yy * 0.06), yy, 0), wick2)
			Kit.box(b, Vector3(w + 0.01, 0.012, 0.016), Vector3(0, yy, sx * (l * 0.5 + yy * 0.06)), wick2)
		# Kenar (yuvarlak)
		Kit.capsule(b, 0.013, l + 0.05, Vector3(sx * (w * 0.5 + 0.012), h, 0), wick2, Vector3(PI / 2, 0, 0))
		Kit.capsule(b, 0.013, w + 0.05, Vector3(0, h, sx * (l * 0.5 + 0.012)), wick2, Vector3(0, 0, PI / 2))


# ---------------------------------------------------------------- binme

func mount(r: Node3D) -> void:
	if _busy:
		return
	if instant:
		m._enter_ride_now(r)
		return
	_busy = true
	_anim_ride = r
	var kind: String = r.get_meta("kind")
	var cfg: Dictionary = m.RIDES[kind]
	var car: bool = cfg["hide"]
	var on: Node3D = m.owner_node
	var om: Node3D = m.owner_model
	m._moving = false
	m._queue.clear()
	m._marker.visible = false
	m.ui.set_context("", "")
	var base := _flat(r)
	var seat: Vector3 = cfg["seat"]
	var side_l := Vector3(-1.25, 0, 0.45) if car else Vector3(-0.56, 0, seat.z - 0.02)
	# Aracin saginda / onunde ise arkadan dolan
	var pts: Array = []
	var me := base.affine_inverse() * on.position
	if car and me.x > -0.9:
		var zz := 2.5 if me.z > -1.0 else -2.5
		if me.x > 0.5 and absf(me.z) < 2.3:
			pts.append(base * Vector3(1.3, 0, zz))
		pts.append(base * Vector3(-1.3, 0, zz))
	elif not car and me.x > 0.25 and me.z < 1.2:
		pts.append(base * Vector3(0.0, 0, 1.4))
	pts.append(base * side_l)
	for tgt: Vector3 in pts:
		var from := on.position
		var d2 := Vector2(tgt.x - from.x, tgt.z - from.z)
		if d2.length() < 0.05:
			continue
		var yaw0 := on.rotation.y
		var yaw1 := atan2(-d2.x, -d2.y)
		var sp := 3.0
		om.speed = sp
		await _run(clampf(d2.length() / sp, 0.12, 2.0), func(k: float):
			var p := from.lerp(tgt, k)
			p.y = ParkMap.walk_height(Vector2(p.x, p.z))
			on.position = p
			on.rotation.y = lerp_angle(yaw0, yaw1, minf(1.0, k * 5.0)))
	om.speed = 0.0
	if not is_instance_valid(r):
		_busy = false
		return
	if car:
		await _mount_car(r, cfg, side_l)
	else:
		await _mount_two(r, cfg, side_l)
	_anim_ride = null
	_busy = false


func _mount_car(r: Node3D, _cfg: Dictionary, side_l: Vector3) -> void:
	var on: Node3D = m.owner_node
	var om: Node3D = m.owner_model
	var glass := r.has_meta("glass")
	# Kapiya don, kola uzan; kapi acilir
	var yaw0 := on.rotation.y
	var face := r.rotation.y - PI / 2
	om.act("door", 0.7)
	m._sfx("araba_kapi", -6.0)
	_door_show(r, glass)
	await _run(0.42, func(k: float):
		on.rotation.y = lerp_angle(yaw0, face, minf(1.0, k * 2.5))
		_door_angle(_ease(k)))
	# Koltuga kay: egil, don, otur
	m._enter_ride_now(r, true)
	om.visible = true
	on.position = r.position
	on.rotation = r.rotation
	var seat_p: Vector3 = m.CAR_SEAT
	_pet_wait()
	await _run(0.62, func(k: float):
		var e := _ease(k)
		on.position = r.position
		on.rotation = r.rotation
		om.position = side_l.lerp(seat_p, e) + Vector3(0, -0.16 * sin(k * PI), 0)
		om.rotation.y = lerpf(-PI / 2, 0.0, _ease(minf(1.0, k * 1.4)))
		m._wheel_grips())
	om.position = seat_p
	om.rotation.y = 0.0
	om.visible = glass or m._fps
	# Kapi kapanir; hayvan arkadan atlar
	_pet_board()
	await _run(0.3, func(k: float):
		_door_angle(1.0 - _ease(k)))
	_door_hide()
	m._sfx("araba_kapi", -8.0, 0.92)


func _mount_two(r: Node3D, cfg: Dictionary, side_l: Vector3) -> void:
	var on: Node3D = m.owner_node
	var om: Node3D = m.owner_model
	var yaw0 := on.rotation.y
	var lean0 := r.rotation.z
	m._enter_ride_now(r, true)
	_pet_wait()
	var seat_p: Vector3 = om.position
	om.ride_mount = 0.0
	om.ride_foot_down = 1.0
	om.ride_seat_y = (cfg["seat"] as Vector3).y
	om.ride_ground = _ground_foot(cfg, -0.68, 0.09)
	om.position = side_l
	on.position = r.position
	# Gidonu tut, araci dikle
	await _run(0.38, func(k: float):
		r.rotation.z = lerpf(lean0, 0.0, _ease(k))
		on.position = r.position
		on.rotation = Vector3(0, lerp_angle(yaw0, r.rotation.y, minf(1.0, k * 2.5)), 0)
		_set_grips(r, cfg))
	# Sag bacagi selenin ustunden asir, otur
	await _run(0.75, func(k: float):
		var e := _ease(k)
		om.ride_mount = k
		om.position = side_l.lerp(seat_p, e) + Vector3(0, 0.05 * sin(k * PI), 0)
		om.ride_ground = _ground_foot(cfg, lerpf(-0.68, -0.36, e), lerpf(0.09, 0.15, e))
		on.rotation = r.rotation
		_set_grips(r, cfg))
	om.ride_mount = 1.0
	om.position = seat_p
	# Sol ayakla yan ayagi kaldir
	_pet_board()
	var base_g := _ground_foot(cfg, -0.36)
	var tip: Vector3 = STANDS[r.get_meta("kind")][1] + Vector3(0.0, 0.12, -0.04)
	var clacked := [false]
	await _run(0.5, func(k: float):
		om.ride_ground = base_g.lerp(tip, sin(k * PI))
		_stand_set(r, 1.0 - _ease(clampf((k - 0.35) / 0.4, 0.0, 1.0)))
		if k > 0.5 and not clacked[0]:
			clacked[0] = true
			m._sfx("clack", -7.0)
		_set_grips(r, cfg))
	om.ride_ground = base_g
	_stand_set(r, 0.0)


# ---------------------------------------------------------------- inme

func dismount() -> void:
	if _busy or m._ride == null or m.fuel.busy():
		return
	if instant:
		m._exit_ride_now()
		return
	_busy = true
	var r: Node3D = m._ride
	_anim_ride = r
	var cfg: Dictionary = m.RIDES[r.get_meta("kind")]
	m._drive_speed = 0.0
	if cfg["hide"]:
		await _dismount_car(r)
	else:
		await _dismount_two(r, cfg)
	_anim_ride = null
	_busy = false


func _free_side(r: Node3D, locals: Array) -> Vector3:
	var base := _flat(r)
	for l: Vector3 in locals:
		var w := base * l
		if m.world.is_free(Vector2(w.x, w.z), 0.4):
			return l
	return locals[0]


func _dismount_car(r: Node3D) -> void:
	var on: Node3D = m.owner_node
	var om: Node3D = m.owner_model
	var glass := r.has_meta("glass")
	# Bos olan taraf: once surucu kapisi (sol), doluysa sag
	var side_l := _free_side(r, [Vector3(-1.25, 0, 0.45), Vector3(1.25, 0, 0.45), Vector3(-1.6, 0, 0.45), Vector3(1.6, 0, 0.45)])
	var left := side_l.x < 0.0
	m._sfx("araba_kapi", -6.0, 1.05)
	if left:
		_door_show(r, glass)
	await _run(0.34, func(k: float):
		_door_angle(_ease(k)))
	var base := _flat(r)
	var out := base * side_l
	var pet: Node3D = m._rider_pet
	var pet_from := pet.global_position if pet else Vector3.ZERO
	m._exit_ride_now(Vector2(out.x, out.z), true)
	on.rotation = Vector3(0, r.rotation.y - (PI / 2 if left else -PI / 2), 0)       # arabaya sirtini doner
	var start := on.global_transform.affine_inverse() * (r.global_transform * (m.CAR_SEAT as Vector3))
	start.y = 0.0
	om.position = start
	if pet and pet.visible:
		_fly_out(pet, pet_from, 0.35)
	await _run(0.6, func(k: float):
		om.position = start.lerp(Vector3.ZERO, _ease(k)) + Vector3(0, -0.14 * sin(k * PI), 0))
	om.position = Vector3.ZERO
	await _run(0.28, func(k: float):
		_door_angle(1.0 - _ease(k)))
	_door_hide()
	m._sfx("araba_kapi", -8.0, 0.92)


func _dismount_two(r: Node3D, cfg: Dictionary) -> void:
	var on: Node3D = m.owner_node
	var om: Node3D = m.owner_model
	var seat: Vector3 = cfg["seat"]
	var side_l := Vector3(-0.56, 0, seat.z - 0.02)
	var seat_p: Vector3 = om.position
	var base_g := _ground_foot(cfg, -0.36)
	var tip: Vector3 = STANDS[r.get_meta("kind")][1] + Vector3(0.0, 0.12, -0.04)
	om.ride_ground = base_g
	om.ride_seat_y = seat.y
	r.rotation.x = 0.0
	var lean0 := r.rotation.z
	var fd0: float = om.ride_foot_down
	var clacked := [false]
	# Sol ayakla yan ayagi indir
	await _run(0.5, func(k: float):
		om.ride_foot_down = lerpf(fd0, 1.0, minf(1.0, k * 4.0))
		r.rotation.z = lerpf(lean0, 0.0, minf(1.0, k * 3.0))
		on.rotation = r.rotation
		om.ride_ground = base_g.lerp(tip, sin(k * PI))
		_stand_set(r, _ease(clampf((k - 0.3) / 0.4, 0.0, 1.0)))
		if k > 0.6 and not clacked[0]:
			clacked[0] = true
			m._sfx("clack", -7.0, 0.9)
		_set_grips(r, cfg))
	om.ride_ground = base_g
	# Araci ayagin ustune yatir
	await _run(0.36, func(k: float):
		r.rotation.z = LEAN * _ease(k)
		on.rotation = r.rotation
		_set_grips(r, cfg))
	# Sag bacagi geri asir, sola in
	await _run(0.75, func(k: float):
		var e := _ease(k)
		om.ride_mount = 1.0 - k
		om.position = seat_p.lerp(side_l, e) + Vector3(0, 0.05 * sin(k * PI), 0)
		om.ride_ground = _ground_foot(cfg, lerpf(-0.36, -0.68, e), lerpf(0.15, 0.09, e))
		on.rotation = Vector3(0, r.rotation.y, LEAN * (1.0 - e))
		_set_grips(r, cfg))
	var w := _flat(r) * _free_side(r, [side_l, Vector3(0.7, 0, seat.z), Vector3(-1.2, 0, seat.z), Vector3(1.3, 0, seat.z)])
	var pet: Node3D = m._rider_pet
	var pet_from := pet.global_position if pet else Vector3.ZERO
	m._exit_ride_now(Vector2(w.x, w.z), true)
	om.ride_mount = 1.0
	om.ride_foot_down = 0.0
	r.rotation.z = LEAN
	if pet:
		_fly_out(pet, pet_from, 0.3)


# ---------------------------------------------------------------- kapi (Polo)

func _door_show(r: Node3D, glass: bool) -> void:
	_door_hide()
	if not glass:
		return
	_door = Node3D.new()
	_door.position = Vector3(-0.85, 0.0, -0.78)
	r.add_child(_door)
	_door_ride = r
	var paint := Kit.mat("f1f1ee", 0.3)
	paint.metallic = 0.2
	var p := Kit.box(_door, Vector3(0.035, 0.5, 0.96), Vector3(-0.012, 0.66, 0.49), paint)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.box(_door, Vector3(0.03, 0.46, 0.9), Vector3(0.02, 0.66, 0.49), Kit.mat("34363a", 0.95))
	Kit.capsule(_door, 0.012, 0.12, Vector3(-0.034, 0.83, 0.82), Kit.mat("d8d8d4", 0.3), Vector3(PI / 2, 0, 0))


func _door_angle(k: float) -> void:
	if _door and is_instance_valid(_door):
		_door.rotation.y = -1.12 * k


func _door_hide() -> void:
	if _door and is_instance_valid(_door):
		_door.queue_free()
	_door = null


# ---------------------------------------------------------------- hayvan

func _pet_scale(a: Node3D, target: float) -> void:
	if not a.has_meta("vl_scale"):
		a.set_meta("vl_scale", a.scale)
	var cur: float = a.model.scale.x * (a.get_meta("vl_scale") as Vector3).x
	a.scale = (a.get_meta("vl_scale") as Vector3) * minf(1.0, target / maxf(cur, 0.05))


func _spot_xf(r: Node3D, spot: String) -> Transform3D:
	var kind: String = r.get_meta("kind")
	if PET_SEATS.has(kind):
		return Transform3D(Basis(), PET_SEATS[kind][0])
	var s: Array = CAR_SPOTS.get(spot, CAR_SPOTS["on"])
	var out := 0.0
	if float(s[3]) > 0.5 and absf(m._drive_speed) > 3.0:
		out = 0.07          # giderken basini camdan hafifce cikarir
	return Transform3D(Basis(Vector3.UP, s[1]) * Basis(Vector3.RIGHT, s[4]), (s[0] as Vector3) + Vector3(out, 0, 0))


func _pet_init(a: Node3D, mode: String) -> void:
	var r: Node3D = m._ride
	var kind: String = r.get_meta("kind")
	_pet = {"a": a, "mode": mode, "spot": "on", "hold": false, "t": 0.0, "next": randf_range(4.0, 7.0)}
	if PET_SEATS.has(kind):
		_pet_scale(a, PET_SEATS[kind][1])
		var fx: float = PET_SEATS[kind][2]
		if fx > 0.0:
			var f: Vector3 = m.owner_model.ride_feet
			m.owner_model.ride_feet = Vector3(maxf(f.x, fx), f.y, f.z)
	else:
		_pet_scale(a, 0.62)


## Binme hareketi surerken hayvan oldugu yerde bekler.
func _pet_wait() -> void:
	var a: Node3D = m._rider_pet
	if a == null:
		_pet = {}
		return
	_pet_init(a, "wait")
	a.model.pose = "stand"


## Hayvan yerine atlar.
func _pet_board() -> void:
	if _pet.is_empty() or not is_instance_valid(_pet["a"]):
		return
	_pet["mode"] = "fly"
	_pet["k"] = 0.0
	_pet["from"] = (_pet["a"] as Node3D).global_transform
	(_pet["a"] as Node3D).model.hop(0.1, 0.45)
	m._pet_voice((_pet["a"] as Node3D).kind, true)


func _apply_spot(a: Node3D, spot: String) -> void:
	var kind: String = m._ride.get_meta("kind")
	if PET_SEATS.has(kind):
		a.model.pose = "sit"
		a.model.paws_up = 0.0
	else:
		var s: Array = CAR_SPOTS[spot]
		a.model.pose = s[2]
		a.model.paws_up = move_toward(a.model.paws_up, float(s[3]), get_process_delta_time() * 3.0)
	a.model.speed = 0.0


func _goto(spot: String) -> void:
	if _pet.is_empty() or _pet["spot"] == spot and _pet["mode"] == "seat":
		return
	var a: Node3D = _pet["a"]
	_pet["spot"] = spot
	_pet["mode"] = "fly"
	_pet["k"] = 0.0
	_pet["from"] = a.global_transform
	a.model.paws_up = 0.0
	a.model.pose = "stand"
	a.model.hop(0.08, 0.4)


## Oyuncunun komutu arac icinde: Otur -> yolcu koltugu, Yat -> arka koltuk, Gel -> serbest.
func pet_command(cmd: String) -> bool:
	if m._ride == null or m._rider_pet == null or _pet.is_empty():
		return false
	var kind: String = m._ride.get_meta("kind")
	var a: Node3D = m._rider_pet
	var nm := String(m.state.pet(a.kind).get("name", "Dostun"))
	if PET_SEATS.has(kind):
		m.ui.toast("%s yerinde güvenle oturuyor." % nm)
		return true
	match cmd:
		"sit":
			_pet["hold"] = true
			_goto("on")
			m.ui.toast("%s yolcu koltuğuna oturdu." % nm)
		"lie", "sleep":
			_pet["hold"] = true
			_goto("arka")
			m.ui.toast("%s arka koltuğa uzandı." % nm)
		_:
			_pet["hold"] = false
			_pet["next"] = 1.5
			m.ui.toast("%s arabanın içinde serbest." % nm)
	m._pet_voice(a.kind, true)
	return true


func _update_pet(dt: float) -> void:
	var a: Node3D = m._rider_pet
	var r: Node3D = m._ride
	if a == null or r == null:
		return
	if _pet.get("a") != a:
		_pet_init(a, "seat")
	var kind: String = r.get_meta("kind")
	var two := PET_SEATS.has(kind)
	var sp := absf(m._drive_speed)
	match _pet["mode"]:
		"wait":
			return
		"fly":
			_pet["k"] = float(_pet["k"]) + dt / 0.45
			var k := clampf(_pet["k"], 0.0, 1.0)
			var to := r.global_transform * _spot_xf(r, _pet["spot"])
			var from: Transform3D = _pet["from"]
			var e := _ease(k)
			var xf := Transform3D(Basis(from.basis.orthonormalized().get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), e)).scaled(a.scale), from.origin.lerp(to.origin, e))
			xf.origin.y += sin(k * PI) * (0.35 if from.origin.distance_to(to.origin) > 1.2 else 0.12)
			a.global_transform = xf
			if k >= 1.0:
				_pet["mode"] = "seat"
		"seat":
			var xf := r.global_transform * _spot_xf(r, _pet["spot"])
			a.global_transform = Transform3D(xf.basis.scaled(a.scale), xf.origin)
			_apply_spot(a, _pet["spot"])
			if not two and not _pet["hold"]:
				_pet["next"] = float(_pet["next"]) - dt
				if float(_pet["next"]) <= 0.0:
					_pet["next"] = randf_range(5.0, 9.0)
					var opts := ["on", "cam", "arka", "arkacam", "cam"]
					opts.erase(_pet["spot"])
					_goto(opts[randi() % opts.size()])
	# Ruzgar: acikta (iki tekerli) ya da camdan bakarken kulaklar ucusur, dil disarida
	var windy: bool = two or (_pet["mode"] == "seat" and float(CAR_SPOTS[_pet["spot"]][3]) > 0.5)
	a.model.wind = move_toward(a.model.wind, clampf(sp / 7.0, 0.0, 1.0) if windy else 0.0, dt * 2.0)
	_tongue(a, a.model.wind)
	if sp > 0.5:
		m.state.count("petride", sp * dt)


func _tongue(a: Node3D, wind: float) -> void:
	if a.kind != "kopek" or a.model.mouth == null:
		return
	var t: Node3D = a.model.mouth.get_node_or_null("Dil")
	if t == null:
		if wind < 0.3:
			return
		t = Node3D.new()
		t.name = "Dil"
		a.model.mouth.add_child(t)
		Kit.box(t, Vector3(0.035, 0.008, 0.075), Vector3(0.0, -0.012, -0.03), Kit.mat("e8788f", 0.6))
	t.visible = wind > 0.3
	if t.visible:
		var tt := Time.get_ticks_msec() * 0.001
		t.rotation = Vector3(-0.5 + sin(tt * 17.0) * 0.18 * wind, sin(tt * 11.0) * 0.5 * wind, 0)


## Hayvanlar aractan inmeden hemen once (main._unboard_pets): boyut, ruzgar, dil sifirlanir.
func pets_out() -> void:
	for k in m.agents:
		var a: Node3D = m.agents[k]
		if a.has_meta("vl_scale"):
			a.scale = a.get_meta("vl_scale")
			a.remove_meta("vl_scale")
		a.model.wind = 0.0
		a.model.paws_up = 0.0
		if a.model.mouth:
			var t: Node3D = a.model.mouth.get_node_or_null("Dil")
			if t:
				t.visible = false
	_pet = {}


## Inen hayvan koltugundan yere atlar.
func _fly_out(a: Node3D, from: Vector3, delay: float) -> void:
	var to := a.position
	a.set_process(false)
	a.position = from
	a.model.pose = "stand"
	_flights.append([a, from, to, -delay / 0.45])


func _update_flights(dt: float) -> void:
	for i in range(_flights.size() - 1, -1, -1):
		var f: Array = _flights[i]
		var a: Node3D = f[0]
		if not is_instance_valid(a):
			_flights.remove_at(i)
			continue
		f[3] = float(f[3]) + dt / 0.45
		var k := clampf(f[3], 0.0, 1.0)
		if float(f[3]) > 0.0 and float(f[3]) - dt / 0.45 <= 0.0:
			a.model.hop(0.1, 0.45)
		a.position = (f[1] as Vector3).lerp(f[2], _ease(k)) + Vector3(0, sin(k * PI) * 0.3, 0)
		if k >= 1.0:
			if m._ride == null and m._taxi == null:
				a.set_process(true)
				a.command("come")
			_flights.remove_at(i)


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	_frame += 1
	var ride: Node3D = m._ride
	for r in m._rides:
		if not is_instance_valid(r):
			continue
		if not r.has_meta("vl"):
			_dress(r)
		if r == _anim_ride or not r.has_meta("stand"):
			continue
		# Park halinde ayak inik ve sola yatik; surulurken ayak kalkik
		var k: float = r.get_meta("stand_k", 1.0)
		if r == ride:
			if k > 0.0:
				_stand_set(r, move_toward(k, 0.0, dt * 4.0))
		else:
			if k < 1.0:
				_stand_set(r, move_toward(k, 1.0, dt * 4.0))
			if absf(r.rotation.z - LEAN) > 0.001 and not r.has_meta("garage"):
				r.rotation.z = move_toward(r.rotation.z, LEAN, dt * 0.8)
	if ride != null and not _busy and _is_two(ride):
		# Dururken sol ayak yerde
		var om: Node3D = m.owner_model
		var cfg: Dictionary = m.RIDES[ride.get_meta("kind")]
		om.ride_ground = _ground_foot(cfg, -0.36)
		om.ride_seat_y = (cfg["seat"] as Vector3).y
		om.ride_mount = 1.0
		om.ride_foot_down = move_toward(om.ride_foot_down, 1.0 if absf(m._drive_speed) < 0.7 else 0.0, dt * 3.5)
	if ride != null:
		_update_pet(dt)
	_update_flights(dt)
	_update_gauge()
	_update_cabin()


func gear() -> String:
	var ride: Node3D = m._ride
	if ride == null:
		return ""
	var kind: String = ride.get_meta("kind")
	if kind == "bisiklet":
		return ""
	var v: float = m._drive_speed
	var gas: float = -m.ui.stick.y
	if v < -0.3:
		return "R"
	if absf(v) <= 0.3:
		return "D" if gas > 0.12 else ("R" if gas < -0.12 else "P")
	if kind == "motosiklet":
		return str(clampi(int(v * 3.6 / 12.0) + 1, 1, 5))
	return "D" if gas > -0.12 or v > 2.0 else "N"


func rpm() -> float:
	var kmh := absf(m._drive_speed) * 3.6
	var gas := absf(m.ui.stick.y)
	var band := 13.0
	var g := minf(floorf(kmh / band), 4.0)
	return 0.85 + clampf((kmh - g * band) / band, 0.0, 1.3) * 2.6 + gas * 0.6 + g * 0.12


func _update_gauge() -> void:
	var mm: Control = m.minimap
	if mm == null:
		return
	var on: bool = mm.visible and mm.speed_kmh >= 0.0
	if _gauge == null:
		if not on:
			return
		_gauge = Gauge.new()
		_gauge.font = m.ui.F_BODY
		_gauge.font2 = m.ui.F_BODY
		_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gauge.size = Vector2(mm.SIZE, 150)
		mm.get_parent().add_child(_gauge)
	_gauge.visible = on
	mm.gauge_h = 158.0 if on else 0.0
	if not on:
		return
	_gauge.position = mm.position + Vector2(0, -174)
	var ride: Node3D = m._ride
	var top := 15.0
	var fuel := -1.0
	if ride != null:
		var kind: String = ride.get_meta("kind")
		top = float(m.RIDES[kind]["max"])
		if m.fuel.TANK.has(kind):
			fuel = m.fuel.frac(kind)
	_gauge.maxv = maxf(ceilf(top * 3.6 * 1.4 / 20.0) * 20.0, 40.0)
	_gauge.kmh = mm.speed_kmh
	_gauge.limit = int(m.traffic.limit) if (ride == null or ride.get_meta("kind") != "bisiklet") else 999
	_gauge.gear = gear()
	_gauge.fuel = fuel
	_gauge.queue_redraw()


## Arabanin gosterge paneli ve aynalari (yalniz iceriden bakarken canli).
func _update_cabin() -> void:
	var cp: Node3D = m._cockpit
	if cp == null or not is_instance_valid(cp) or not cp.has_meta("gosterge"):
		return
	var live: bool = m._fps and m._ride != null and cp.visible
	var gvp: SubViewport = cp.get_node("GostergeVP")
	if not live:
		if gvp.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
			gvp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			for i in 3:
				var v: SubViewport = cp.get_node_or_null("AynaVP%d" % i)
				if v:
					v.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	gvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cl = gvp.get_node("G")
	cl.kmh = absf(m._drive_speed) * 3.6
	cl.rpm = rpm()
	cl.gear = gear()
	cl.fuel = m.fuel.frac("araba")
	cl.clock = m.ui.clock_label.text if m.ui.clock_label else ""
	cl.queue_redraw()
	# Aynalar: her karede yalniz biri yenilenir (kare hizi dusukse daha seyrek)
	CarCabin.add_mirrors(cp)
	var ride: Node3D = m._ride
	var fps := Engine.get_frames_per_second()
	var every := 2 if fps >= 40.0 else (4 if fps >= 26.0 else 9)
	for i in 3:
		var v: SubViewport = cp.get_node("AynaVP%d" % i)
		var cam: Camera3D = v.get_node("Kam")
		cam.global_transform = ride.global_transform * (cam.get_meta("local") as Transform3D)
	if _frame % every == 0:
		_mirror_i = (_mirror_i + 1) % 3
		(cp.get_node("AynaVP%d" % _mirror_i) as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


# ---------------------------------------------------------------- test

## --mount=araba|motosiklet|bisiklet|scooter: bin, biraz bekle, in. --petseat[=arac]: aninda bin (hayvan yerinde).
## --petcmd=sit|lie, --vcam=side|front|fps|rear: sabit kamera.
func debug(args: Dictionary) -> void:
	var want := String(args.get("mount", args.get("petseat", "")))
	if want == "" or want == "1":
		want = "araba"
	if args.has("mount") or args.has("petseat"):
		var target: Node3D = null
		for r in m._rides:
			if r.get_meta("kind") == want and not r.has_meta("garage"):
				target = r
				break
		if target == null:
			print("ARAC yok: ", want)
			return
		var off := Vector3(-2.2, 0, 1.2) if not args.has("mountright") else Vector3(2.0, 0, 0.5)
		if _is_two(target):
			off = Vector3(-1.4, 0, 0.9) if not args.has("mountright") else Vector3(1.3, 0, 0.6)
		var p := _flat(target) * off
		m._place_owner(Vector2(p.x, p.z))
		for k in m.agents:
			m.agents[k].place(Vector2(p.x, p.z) + Vector2(0.8, 0.6))
		await get_tree().process_frame
		if args.has("petseat"):
			m._enter_ride_now(target)
			if args.has("petcmd"):
				pet_command(args["petcmd"])
			for i in 15:
				await get_tree().process_frame
			if args.has("go"):
				m._drive_speed = float(args["go"])
				for i in 40:
					m._drive_speed = float(args["go"])
					await get_tree().process_frame
		else:
			_debug_cycle(float(args.get("stay", "1.2")))
	if args.has("vcam") and m._ride == null and not args.has("mount"):
		return
	if args.has("vcam"):
		_debug_cam(args["vcam"], args.has("mount"))


## --vtour: her araca aninda binip yandan birer goruntu kaydeder (<shot>_<arac>.png).
func debug_tour(args: Dictionary) -> void:
	var kinds: Array = ["bisiklet", "motosiklet", "scooter", "araba"]
	if String(args["vtour"]) != "1":
		kinds = Array(String(args["vtour"]).split(","))
	for kind in kinds:
		var target: Node3D = null
		for r in m._rides:
			if r.get_meta("kind") == kind and not r.has_meta("garage"):
				target = r
				break
		if target == null:
			continue
		var p := _flat(target) * Vector3(-1.4, 0, 0.9)
		m._place_owner(Vector2(p.x, p.z))
		for k in m.agents:
			m.agents[k].place(Vector2(p.x, p.z) + Vector2(0.8, 0.6))
		await get_tree().process_frame
		m._enter_ride_now(target)
		for i in 12:
			await get_tree().process_frame
		if kind == "araba":
			_goto("cam")
			for i in 24:
				await get_tree().process_frame
		m._mode = "debug"
		var b := _flat(target)
		var cam: Camera3D = m.cam
		cam.fov = 50.0
		cam.global_position = b * (Vector3(-2.3, 1.25, 1.0) if kind != "araba" else Vector3(3.0, 1.5, -0.9))
		cam.look_at(b * Vector3(0, 0.85, 0.25))
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(args["shot"]).replace(".png", "_%s.png" % kind))
		m._mode = "play"
		m._exit_ride_now()
		for i in 4:
			await get_tree().process_frame
	if not args.has("tourmount"):
		return
	# Binme hareketinin ortasindan goruntu
	instant = false
	for spec in [["araba", 1.2, Vector3(-2.2, 0, 1.2), Vector3(-3.4, 1.7, 2.2)], ["motosiklet", 1.05, Vector3(-1.4, 0, 0.9), Vector3(-2.2, 1.3, 1.9)]]:
		var target: Node3D = null
		for r in m._rides:
			if r.get_meta("kind") == spec[0] and not r.has_meta("garage"):
				target = r
				break
		if target == null:
			continue
		var b := _flat(target)
		var p := b * (spec[2] as Vector3)
		m._place_owner(Vector2(p.x, p.z))
		await get_tree().process_frame
		_dbg_cam = [b * (spec[3] as Vector3), b * Vector3(-0.4, 0.85, 0.2)]
		m._enter_ride()
		var t := 0.0
		while t < float(spec[1]):
			await get_tree().process_frame
			t += get_process_delta_time()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(args["shot"]).replace(".png", "_bin_%s.png" % spec[0]))
		while _busy:
			await get_tree().process_frame
		_dbg_cam = []
		m._exit_ride_now()
		for i in 3:
			await get_tree().process_frame


func _debug_cycle(stay: float) -> void:
	m._enter_ride()
	while _busy:
		await get_tree().process_frame
	print("BINDI arac=", m._ride, " ayak=", m._ride.get_meta("stand_k", -1.0) if m._ride else -1.0)
	await get_tree().create_timer(stay).timeout
	m._exit_ride()
	while _busy:
		await get_tree().process_frame
	print("INDI arac=", m._ride, " konum=", m._owner_pos())


func _debug_cam(mode: String, follow: bool) -> void:
	var r: Node3D = m._ride if m._ride != null else _anim_ride
	if r == null:
		for q in m._rides:
			if m.owner_node.position.distance_to(q.position) < 6.0:
				r = q
	if r == null:
		return
	if mode == "fps":
		m._fps = true
		return
	m._mode = "debug"
	var cam: Camera3D = m.cam
	var b := _flat(r)
	var eye := Vector3(-3.4, 1.5, 0.3)
	var look := Vector3(0, 0.9, 0)
	match mode:
		"front":
			eye = Vector3(-0.5, 2.2, -3.0)
			look = Vector3(0, 1.0, -0.4)
		"rear":
			eye = Vector3(-1.6, 1.7, 2.6)
			look = Vector3(0, 0.9, 0.3)
		"side2":
			eye = Vector3(-2.3, 1.25, 0.2)
			look = Vector3(0, 0.85, 0.2)
		"right":
			eye = Vector3(2.6, 1.5, -0.6)
			look = Vector3(0, 0.95, 0.3)
	cam.fov = 55.0
	cam.global_position = b * eye
	cam.look_at(b * look)
	if follow:
		# Hareketi izlemek icin oyun kipinde kal; kamera her kare main._update_camera'da sabitlenir
		m._mode = "play"
		_dbg_cam = [b * eye, b * look]


## Test kamerasi (--vcam ile --mount birlikte): true donerse main kamerayi guncellemez.
func cam_override(cam: Camera3D) -> bool:
	if _dbg_cam.is_empty():
		return false
	cam.fov = 55.0
	cam.global_position = _dbg_cam[0]
	cam.look_at(_dbg_cam[1])
	return true
