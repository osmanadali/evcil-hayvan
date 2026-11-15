extends Node3D
## Kale Palas Otel ic mekanlari: lobi ("lobby") ve otel odasi ("room"). Dukkan ici (shop_interior.gd) ile
## ayni arayuz: has_point, resolve, is_free, w2, local2, update_view, entrance_local.
## Yerel koordinat: x 0..W, z 0..D; kapi z = D tarafinda (kamera o yonden bakar), arka duvar z = 0.

const Kit = preload("res://scripts/kit.gd")
const PersonModel = preload("res://scripts/person_model.gd")

var kind := "lobby"             # "lobby" | "room"
var hour := 12.0                # oda penceresindeki manzara icin gunun saati
var W := 14.0
var D := 10.0
var H := 4.2
var entrance_local := Vector2(7.0, 9.2)
var desk_local := Vector2(7.0, 3.0)        # lobi: resepsiyonun onu
var lift_local := Vector2(11.85, 1.2)      # lobi: asansor kapilarinin onu
var bed_c := Vector2(1.25, 2.9)            # oda: yatak merkezi
var bed_half := Vector2(1.05, 0.9)
var tv_local := Vector2(6.3, 2.9)
var bar_local := Vector2(6.3, 4.75)
var service_local := Vector2(4.4, 1.9)     # oda: pencere onundeki masa (oda servisi)
var petbed_local := Vector2(3.3, 5.2)
var colliders: Array = []
var ceiling: Node3D
var front: Node3D
var staff: Node3D                # resepsiyonist
var tv_screen: MeshInstance3D
var tv_on := false


func _ready() -> void:
	if kind == "room":
		W = 7.5
		D = 6.5
		H = 3.0
		entrance_local = Vector2(W - 1.3, D - 0.75)
		_build_room()
	else:
		_build_lobby()


# ---------------------------------------------------------------- arayuz

func w2(p: Vector2) -> Vector2:
	return Vector2(global_position.x + p.x, global_position.z + p.y)


func local2(p: Vector2) -> Vector2:
	return Vector2(p.x - global_position.x, p.y - global_position.z)


func has_point(p: Vector2) -> bool:
	var l := local2(p)
	return l.x > 0.0 and l.x < W and l.y > 0.0 and l.y < D


func resolve(np: Vector2, r: float, old: Vector2) -> Vector2:
	var p := local2(np)
	var o := local2(old)
	p.x = clampf(p.x, r, W - r)
	p.y = clampf(p.y, r, D - r)
	for pass_i in 3:
		for s in colliders:
			var q := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
			var d := p.distance_to(q)
			if d < r:
				var n := (p - q).normalized() if d > 0.0001 else (o - q).normalized()
				p = q + n * r
	for s in colliders:
		if Geometry2D.segment_intersects_segment(o, p, s[0], s[1]) != null:
			p = o
			break
	return w2(p)


func is_free(p: Vector2, r := 0.4) -> bool:
	return has_point(p) and resolve(p, r, p).distance_to(p) < 0.05


func update_view(cam_pos: Vector3) -> void:
	if ceiling:
		ceiling.visible = cam_pos.y < global_position.y + H - 0.05
	if front:
		front.visible = cam_pos.z - global_position.z < D


func near_bed(lo: Vector2) -> bool:
	var q := (lo - bed_c).abs() - bed_half
	return maxf(q.x, q.y) < 0.75


func set_tv(on: bool) -> void:
	tv_on = on
	if tv_screen:
		tv_screen.material_override = Kit.glow("5fa8ff", 1.6) if on else Kit.mat("0c0e12", 0.15)


# ---------------------------------------------------------------- yardimcilar

func _solid(c: Vector2, half: Vector2) -> void:
	var a := c - half
	var b := c + half
	colliders.append([a, Vector2(b.x, a.y)])
	colliders.append([Vector2(b.x, a.y), b])
	colliders.append([b, Vector2(a.x, b.y)])
	colliders.append([Vector2(a.x, b.y), a])


func _lbl(text: String, pos: Vector3, size: float, col: Color, yrot := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.pixel_size = size / 72.0
	l.outline_size = 0
	l.modulate = col
	l.position = pos
	l.rotation.y = yrot
	if ResourceLoader.exists("res://assets/fonts/Anton-Regular.ttf"):
		l.font = load("res://assets/fonts/Anton-Regular.ttf")
	add_child(l)
	return l


func _metal(hex: String, rough := 0.3) -> StandardMaterial3D:
	var m := Kit.mat(hex, rough)
	m.metallic = 0.8
	return m


func _plant(at: Vector2, s := 1.0) -> void:
	Kit.cyl(self, 0.26 * s, 0.2 * s, 0.5 * s, Vector3(at.x, 0.25 * s, at.y), Kit.mat("e9e2d2", 0.5), 14)
	var leaf := Kit.mat("2f7a45", 0.8)
	Kit.cyl(self, 0.03, 0.04, 0.7 * s, Vector3(at.x, 0.8 * s, at.y), Kit.mat("5b4630", 0.9), 6)
	Kit.ball(self, 0.42 * s, Vector3(at.x, 1.3 * s, at.y), leaf, Vector3(1, 1.15, 1))
	Kit.ball(self, 0.3 * s, Vector3(at.x + 0.2 * s, 1.0 * s, at.y + 0.12 * s), Kit.mat("3b8f52", 0.8))
	_solid(at, Vector2(0.24, 0.24) * s)


## Kanepe: sirti "back" yonunde (0: -z, PI: +z).
func _sofa(c: Vector2, length: float, back_at_minus_z: bool, hex: String) -> void:
	var m := Kit.mat(hex, 0.95)
	var s := -1.0 if back_at_minus_z else 1.0
	Kit.box(self, Vector3(length, 0.42, 0.9), Vector3(c.x, 0.23, c.y), m)
	Kit.box(self, Vector3(length, 0.55, 0.22), Vector3(c.x, 0.66, c.y + s * 0.36), m)
	for sx in [-1.0, 1.0]:
		Kit.box(self, Vector3(0.2, 0.62, 0.9), Vector3(c.x + sx * (length * 0.5 - 0.1), 0.33, c.y), m)
	Kit.box(self, Vector3(length - 0.5, 0.1, 0.6), Vector3(c.x, 0.47, c.y - s * 0.08), Kit.mat(Color(hex).lightened(0.1).to_html(false), 0.95))
	_solid(c, Vector2(length * 0.5, 0.45))


func _shell(floor_hex: String, wall_hex: String, window: bool) -> void:
	var floor_m := StandardMaterial3D.new()
	if ResourceLoader.exists("res://assets/home/karo_beyaz.jpg"):
		floor_m.albedo_texture = load("res://assets/home/karo_beyaz.jpg")
		floor_m.uv1_scale = Vector3(W / 0.9, D / 0.9, 1)
	floor_m.albedo_color = Color(floor_hex)
	floor_m.roughness = 0.18
	Kit.box(self, Vector3(W, 0.1, D), Vector3(W * 0.5, -0.05, D * 0.5), floor_m)
	var wall := Kit.mat(wall_hex, 0.85)
	if window:
		# Arka duvar: ortada genis pencere boslugu (x 2.3..6.3, y 0.75..2.55)
		Kit.box(self, Vector3(2.3, H, 0.12), Vector3(1.15, H * 0.5, -0.06), wall)
		Kit.box(self, Vector3(W - 6.3, H, 0.12), Vector3((W + 6.3) * 0.5, H * 0.5, -0.06), wall)
		Kit.box(self, Vector3(4.0, 0.75, 0.12), Vector3(4.3, 0.375, -0.06), wall)
		Kit.box(self, Vector3(4.0, H - 2.55, 0.12), Vector3(4.3, (H + 2.55) * 0.5, -0.06), wall)
	else:
		Kit.box(self, Vector3(W, H, 0.12), Vector3(W * 0.5, H * 0.5, -0.06), wall)
	Kit.box(self, Vector3(0.12, H, D), Vector3(-0.06, H * 0.5, D * 0.5), wall)
	Kit.box(self, Vector3(0.12, H, D), Vector3(W + 0.06, H * 0.5, D * 0.5), wall)
	# Supurgelik
	var skirt := Kit.mat("4a3324", 0.5)
	Kit.box(self, Vector3(0.03, 0.12, D), Vector3(0.015, 0.06, D * 0.5), skirt)
	Kit.box(self, Vector3(0.03, 0.12, D), Vector3(W - 0.015, 0.06, D * 0.5), skirt)
	ceiling = Node3D.new()
	add_child(ceiling)
	Kit.box(ceiling, Vector3(W, 0.1, D), Vector3(W * 0.5, H + 0.05, D * 0.5), Kit.mat("f4efe6", 0.9))
	front = Node3D.new()
	add_child(front)


# ---------------------------------------------------------------- lobi

func _build_lobby() -> void:
	_shell("cbbd9f", "e2d7c2", false)
	var gold := _metal("c9a45c", 0.25)
	var wood := Kit.mat("4a2f20", 0.35)
	var burgundy := Kit.mat("7a1f2b", 0.9)
	# Ahsap lambri ve altin serit (arka duvar)
	Kit.box(self, Vector3(W, 1.2, 0.05), Vector3(W * 0.5, 0.6, 0.03), wood)
	Kit.box(self, Vector3(W, 0.05, 0.06), Vector3(W * 0.5, 1.22, 0.04), gold)
	# On cephe: cam, ortada kapi boslugu
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.78, 0.88, 0.94, 0.3)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var frame := _metal("2b2e33", 0.4)
	Kit.box(front, Vector3(W, 0.6, 0.12), Vector3(W * 0.5, H - 0.3, D + 0.06), frame)
	for side in [-1.0, 1.0]:
		var cx: float = W * 0.5 + side * (W * 0.25 + 0.65)
		Kit.box(front, Vector3(W * 0.5 - 1.3, H - 0.6, 0.04), Vector3(cx, (H - 0.6) * 0.5, D + 0.06), glass)
		Kit.box(front, Vector3(0.12, H, 0.14), Vector3(W * 0.5 + side * 1.3, H * 0.5, D + 0.06), gold)
	var outside := StandardMaterial3D.new()
	outside.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outside.albedo_color = Color("dfe9ef") if hour > 6.5 and hour < 19.0 else Color("1a2238")
	Kit.box(self, Vector3(W + 6, H + 2, 0.1), Vector3(W * 0.5, H * 0.5, D + 3.0), outside)
	Kit.box(self, Vector3(W + 6, 0.1, 3.0), Vector3(W * 0.5, -0.06, D + 1.5), Kit.mat("b9b4aa", 0.9))
	# Kirmizi hali: kapidan resepsiyona
	Kit.box(self, Vector3(2.2, 0.02, D - 2.6), Vector3(W * 0.5, 0.011, (D + 2.6) * 0.5), burgundy)
	for sx in [-1.0, 1.0]:
		Kit.box(self, Vector3(0.08, 0.022, D - 2.6), Vector3(W * 0.5 + sx * 1.06, 0.012, (D + 2.6) * 0.5), gold)
	# Resepsiyon bankosu
	var dc := Vector2(7.0, 1.75)
	Kit.box(self, Vector3(4.6, 1.05, 0.8), Vector3(dc.x, 0.525, dc.y), wood)
	Kit.box(self, Vector3(4.7, 0.06, 0.92), Vector3(dc.x, 1.08, dc.y), Kit.mat("efe9df", 0.12))
	Kit.box(self, Vector3(4.62, 0.08, 0.03), Vector3(dc.x, 0.75, dc.y + 0.41), gold)
	Kit.box(self, Vector3(4.2, 0.03, 0.03), Vector3(dc.x, 0.06, dc.y + 0.42), Kit.glow("ffd9a0", 1.4))
	_solid(dc, Vector2(2.3, 0.4))
	# Zil, ekran, kalemlik
	Kit.cyl(self, 0.07, 0.09, 0.05, Vector3(dc.x + 0.9, 1.135, dc.y + 0.15), gold, 14)
	Kit.ball(self, 0.02, Vector3(dc.x + 0.9, 1.175, dc.y + 0.15), gold)
	Kit.box(self, Vector3(0.5, 0.34, 0.04), Vector3(dc.x - 0.9, 1.3, dc.y - 0.15), Kit.mat("15171a", 0.2), Vector3(0, 0.3, 0))
	Kit.box(self, Vector3(0.34, 0.24, 0.02), Vector3(dc.x + 1.6, 1.24, dc.y + 0.2), Kit.mat("ffffff", 0.5), Vector3(-0.3, 0, 0))
	_lbl("EVCİL DOSTU\nOTEL", Vector3(dc.x + 1.6, 1.245, dc.y + 0.215), 0.07, Color("7a1f2b")).rotation.x = -0.3
	# Resepsiyonist
	var v := PersonModel.new()
	v.kind = "kadin"
	v.tint = Color("7a1f2b")
	v.pants = Color("22232a")
	v.position = Vector3(dc.x, 0, 0.8)
	add_child(v)
	staff = v
	# Arka duvar: tabela, anahtarlik, saatler
	Kit.box(self, Vector3(3.6, 0.62, 0.05), Vector3(dc.x, 3.25, 0.04), wood)
	_lbl("KALE PALAS", Vector3(dc.x, 3.25, 0.08), 0.42, Color("e7c67a"))
	_lbl("RESEPSİYON", Vector3(dc.x, 2.78, 0.05), 0.17, Color("4a2f20"))
	Kit.box(self, Vector3(1.9, 1.0, 0.04), Vector3(dc.x - 0.2, 1.95, 0.04), Kit.mat("3a2619", 0.5))
	for r in 3:
		for c in 6:
			Kit.box(self, Vector3(0.05, 0.14, 0.02), Vector3(dc.x - 0.95 + c * 0.3, 2.25 - r * 0.3, 0.07), gold)
	for i in 3:
		var cx: float = 2.2 + i * 0.9
		Kit.cyl(self, 0.26, 0.26, 0.04, Vector3(cx, 2.6, 0.05), Kit.mat("fbfaf5", 0.4), 20, Vector3(PI * 0.5, 0, 0))
		Kit.torus(self, 0.25, 0.29, Vector3(cx, 2.6, 0.06), gold, Vector3(PI * 0.5, 0, 0))
		Kit.box(self, Vector3(0.02, 0.18, 0.01), Vector3(cx, 2.66, 0.08), Kit.mat("15171a", 0.4), Vector3(0, 0, 0.6 + i * 1.3))
		_lbl(["ANKARA", "PARİS", "TOKYO"][i], Vector3(cx, 2.2, 0.05), 0.1, Color("4a2f20"))
	# Asansorler
	var steel := _metal("b9bdc2", 0.25)
	for i in 2:
		var ex: float = 11.0 + i * 1.7
		Kit.box(self, Vector3(1.5, 2.5, 0.06), Vector3(ex, 1.25, 0.04), Kit.mat("3a2619", 0.4))
		Kit.box(self, Vector3(0.62, 2.25, 0.04), Vector3(ex - 0.32, 1.125, 0.08), steel)
		Kit.box(self, Vector3(0.62, 2.25, 0.04), Vector3(ex + 0.32, 1.125, 0.08), steel)
		Kit.box(self, Vector3(0.5, 0.16, 0.03), Vector3(ex, 2.68, 0.06), Kit.mat("15171a", 0.3))
		_lbl(["3", "Z"][i], Vector3(ex, 2.68, 0.08), 0.12, Color("ff8a3c"))
	Kit.box(self, Vector3(0.1, 0.22, 0.03), Vector3(11.85, 1.2, 0.06), steel)
	Kit.ball(self, 0.025, Vector3(11.85, 1.24, 0.08), Kit.glow("ffb347", 2.0))
	_lbl("ASANSÖR · ODALAR", Vector3(11.85, 3.1, 0.05), 0.16, Color("4a2f20"))
	# Oturma grubu (sagda)
	_sofa(Vector2(11.2, 5.1), 2.4, true, "2f4a5a")
	_sofa(Vector2(11.2, 7.9), 2.4, false, "2f4a5a")
	Kit.box(self, Vector3(1.3, 0.06, 0.7), Vector3(11.2, 0.42, 6.5), Kit.mat("efe9df", 0.12))
	Kit.box(self, Vector3(1.1, 0.4, 0.5), Vector3(11.2, 0.2, 6.5), wood)
	Kit.cyl(self, 0.09, 0.06, 0.2, Vector3(11.2, 0.55, 6.5), Kit.mat("f4f4f0", 0.3), 12)
	Kit.ball(self, 0.13, Vector3(11.2, 0.75, 6.5), Kit.mat("d95f76", 0.8))
	_solid(Vector2(11.2, 6.5), Vector2(0.65, 0.35))
	Kit.box(self, Vector3(3.4, 0.015, 4.2), Vector3(11.2, 0.008, 6.5), Kit.plush(Color("b7a58a")))
	# Solda: koltuklar, sehpa, bagaj arabasi
	_sofa(Vector2(2.4, 4.6), 1.1, true, "7a1f2b")
	_sofa(Vector2(2.4, 7.0), 1.1, false, "7a1f2b")
	Kit.cyl(self, 0.4, 0.4, 0.05, Vector3(2.4, 0.5, 5.8), Kit.mat("efe9df", 0.12), 20)
	Kit.cyl(self, 0.05, 0.2, 0.5, Vector3(2.4, 0.25, 5.8), gold, 12)
	_solid(Vector2(2.4, 5.8), Vector2(0.35, 0.35))
	var cart := Vector2(4.6, 8.6)
	Kit.box(self, Vector3(1.2, 0.06, 0.6), Vector3(cart.x, 0.2, cart.y), burgundy)
	for sx in [-1.0, 1.0]:
		Kit.cyl(self, 0.025, 0.025, 1.6, Vector3(cart.x + sx * 0.56, 1.0, cart.y), gold, 8)
	Kit.cyl(self, 0.025, 0.025, 1.15, Vector3(cart.x, 1.8, cart.y), gold, 8, Vector3(0, 0, PI * 0.5))
	Kit.box(self, Vector3(0.6, 0.4, 0.36), Vector3(cart.x - 0.2, 0.43, cart.y), Kit.mat("5b4630", 0.6))
	Kit.box(self, Vector3(0.45, 0.3, 0.3), Vector3(cart.x + 0.3, 0.38, cart.y), Kit.mat("2f4a5a", 0.6))
	_solid(cart, Vector2(0.62, 0.32))
	# Hayvan kosesi: su kabi ve minder
	Kit.cyl(self, 0.16, 0.12, 0.08, Vector3(8.9, 0.04, 8.9), Kit.mat("c8322b", 0.4), 14)
	Kit.cyl(self, 0.13, 0.13, 0.02, Vector3(8.9, 0.075, 8.9), Kit.mat("6fb1e0", 0.1), 14)
	# Bitkiler
	for p in [Vector2(0.6, 0.7), Vector2(W - 0.6, 3.2), Vector2(0.6, D - 0.7), Vector2(W - 0.6, D - 0.7), Vector2(3.9, 0.7)]:
		_plant(p, 1.15)
	# Avize ve isiklar
	var cy := H - 0.75
	Kit.cyl(ceiling, 0.02, 0.02, 0.7, Vector3(W * 0.5, H - 0.35, 5.6), gold, 6)
	Kit.torus(ceiling, 0.62, 0.7, Vector3(W * 0.5, cy, 5.6), gold)
	Kit.torus(ceiling, 0.32, 0.38, Vector3(W * 0.5, cy - 0.22, 5.6), gold)
	for k in 8:
		var a := k * TAU / 8.0
		Kit.ball(ceiling, 0.07, Vector3(W * 0.5 + cos(a) * 0.66, cy - 0.1, 5.6 + sin(a) * 0.66), Kit.glow("fff0c8", 3.0))
	for x in [3.0, 11.0]:
		for z in [2.6, 7.2]:
			Kit.cyl(ceiling, 0.14, 0.14, 0.03, Vector3(x, H - 0.01, z), Kit.glow("fff3dc", 2.5), 12)
	for lp in [Vector3(W * 0.5, H - 0.9, 5.4), Vector3(3.0, H - 0.6, 4.0), Vector3(11.0, H - 0.6, 4.0)]:
		var o := OmniLight3D.new()
		o.position = lp
		o.omni_range = 10.0
		o.light_energy = 0.42
		o.light_color = Color("fff0d6")
		add_child(o)
	Kit.box(self, Vector3(1.8, 0.02, 1.0), Vector3(W * 0.5, 0.012, D - 0.6), Kit.mat("3b3d41", 1.0))


# ---------------------------------------------------------------- oda

func _build_room() -> void:
	_shell("a8845c", "ddd3c0", true)
	var gold := _metal("c9a45c", 0.25)
	var wood := Kit.mat("5a3a26", 0.4)
	var white := Kit.mat("f6f3ec", 0.9)
	var night := hour < 6.5 or hour > 19.0
	# Hali
	Kit.box(self, Vector3(3.6, 0.015, 3.0), Vector3(3.6, 0.008, 3.2), Kit.mat("6e1f2a", 0.95))
	# Pencere: cam, cerceve, perde, sehir manzarasi
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.8, 0.9, 0.96, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.03
	Kit.box(self, Vector3(4.0, 1.8, 0.03), Vector3(4.3, 1.65, -0.06), glass)
	for x in [2.3, 4.3, 6.3]:
		Kit.box(self, Vector3(0.07, 1.8, 0.08), Vector3(x, 1.65, -0.05), white)
	Kit.box(self, Vector3(4.1, 0.07, 0.2), Vector3(4.3, 0.75, 0.02), white)
	for x in [2.0, 6.6]:
		Kit.box(self, Vector3(0.55, 2.3, 0.1), Vector3(x, 1.6, 0.1), Kit.mat("7a1f2b", 0.95))
	Kit.cyl(self, 0.025, 0.025, 5.2, Vector3(4.3, 2.78, 0.1), gold, 8, Vector3(0, 0, PI * 0.5))
	var sky := StandardMaterial3D.new()
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky.albedo_color = Color("141b33") if night else (Color("f0b98a") if hour > 17.5 or hour < 7.5 else Color("a9d3f2"))
	Kit.box(self, Vector3(10.0, 9.0, 0.05), Vector3(4.3, 0.2, -1.9), sky)
	# Ucuncu kattan gorunen sehir: catilar asagida, pencereleri isikli
	var rng := RandomNumberGenerator.new()
	rng.seed = 304
	var bx := -0.4
	while bx < 9.0:
		var bw := rng.randf_range(0.8, 1.5)
		var top := rng.randf_range(-0.7, 1.9)
		var bz := rng.randf_range(-1.7, -1.1)
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var shade := rng.randf_range(0.0, 0.25)
		bm.albedo_color = Color("1d2440").lightened(shade * 0.4) if night else Color("8d9aa8").lightened(shade)
		Kit.box(self, Vector3(bw, top + 4.2, 0.1), Vector3(bx + bw * 0.5, (top - 4.2) * 0.5, bz), bm)
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.albedo_color = Color("ffd98a") if night else Color("5d7186")
		for r in 6:
			for c in int(bw / 0.36):
				if rng.randf() < (0.45 if night else 0.85):
					Kit.box(self, Vector3(0.14, 0.18, 0.02), Vector3(bx + 0.22 + c * 0.36, top - 0.3 - r * 0.42, bz + 0.07), wm)
		bx += bw + rng.randf_range(0.0, 0.2)
	if night:
		var moon := StandardMaterial3D.new()
		moon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		moon.albedo_color = Color("f4f0d8")
		Kit.ball(self, 0.16, Vector3(5.6, 2.3, -1.8), moon)
	# Yatak: basi sol duvarda
	Kit.box(self, Vector3(2.1, 0.3, 1.8), Vector3(bed_c.x, 0.2, bed_c.y), wood)
	Kit.box(self, Vector3(2.05, 0.24, 1.74), Vector3(bed_c.x, 0.45, bed_c.y), white)
	Kit.box(self, Vector3(1.35, 0.1, 1.78), Vector3(bed_c.x + 0.36, 0.56, bed_c.y), Kit.mat("7a1f2b", 0.95))
	Kit.box(self, Vector3(0.3, 0.11, 1.78), Vector3(bed_c.x - 0.42, 0.565, bed_c.y), Kit.plush(Color("f1ead9")))
	Kit.box(self, Vector3(0.12, 1.25, 2.1), Vector3(0.08, 0.72, bed_c.y), Kit.plush(Color("5b4630")))
	Kit.box(self, Vector3(0.04, 0.06, 2.14), Vector3(0.16, 1.36, bed_c.y), gold)
	for sz in [-0.42, 0.42]:
		Kit.box(self, Vector3(0.4, 0.14, 0.62), Vector3(0.48, 0.64, bed_c.y + sz), white, Vector3(0, 0, 0.12))
	_solid(bed_c, bed_half)
	# Komodinler, abajurlar
	for sz in [-1.25, 1.25]:
		var np := Vector2(0.32, bed_c.y + sz)
		Kit.box(self, Vector3(0.48, 0.5, 0.46), Vector3(np.x, 0.25, np.y), wood)
		Kit.cyl(self, 0.03, 0.06, 0.26, Vector3(np.x, 0.63, np.y), gold, 8)
		Kit.cyl(self, 0.1, 0.15, 0.2, Vector3(np.x, 0.84, np.y), Kit.glow("ffe2b0", 1.6), 12)
		_solid(np, Vector2(0.24, 0.23))
	Kit.box(self, Vector3(0.16, 0.06, 0.2), Vector3(0.34, 0.53, bed_c.y - 1.12), Kit.mat("22232a", 0.3))
	# Tablo
	Kit.box(self, Vector3(0.04, 0.7, 1.1), Vector3(0.03, 2.05, bed_c.y), gold)
	Kit.box(self, Vector3(0.05, 0.58, 0.98), Vector3(0.04, 2.05, bed_c.y), Kit.mat("6fa0b8", 0.7))
	Kit.box(self, Vector3(0.055, 0.2, 0.98), Vector3(0.042, 1.86, bed_c.y), Kit.mat("5c8a55", 0.7))
	# TV unitesi (sag duvar)
	Kit.box(self, Vector3(0.45, 0.55, 1.9), Vector3(W - 0.26, 0.275, 2.9), wood)
	Kit.box(self, Vector3(0.05, 0.85, 1.45), Vector3(W - 0.06, 1.55, 2.9), Kit.mat("15171a", 0.3))
	tv_screen = Kit.box(self, Vector3(0.02, 0.76, 1.36), Vector3(W - 0.095, 1.55, 2.9), Kit.mat("0c0e12", 0.15))
	_solid(Vector2(W - 0.26, 2.9), Vector2(0.24, 0.95))
	# Mini bar
	Kit.box(self, Vector3(0.52, 0.85, 0.6), Vector3(W - 0.3, 0.425, 4.75), Kit.mat("2b2e33", 0.3))
	Kit.box(self, Vector3(0.02, 0.7, 0.5), Vector3(W - 0.565, 0.44, 4.75), _metal("8a8f96", 0.2))
	Kit.box(self, Vector3(0.36, 0.02, 0.5), Vector3(W - 0.3, 0.86, 4.75), gold)
	for i in 3:
		Kit.cyl(self, 0.03, 0.03, 0.2, Vector3(W - 0.3, 0.97, 4.6 + i * 0.14), Kit.mat(["cfe8f5", "f29f4b", "3b8f52"][i], 0.2), 10)
	_lbl("MİNİ BAR", Vector3(W - 0.58, 0.72, 4.75), 0.07, Color("e7c67a"), -PI * 0.5)
	_solid(Vector2(W - 0.3, 4.75), Vector2(0.28, 0.32))
	# Pencere onu: yuvarlak masa, iki koltuk, servis tepsisi
	var tc := Vector2(4.4, 1.0)
	Kit.cyl(self, 0.42, 0.42, 0.04, Vector3(tc.x, 0.72, tc.y), Kit.mat("efe9df", 0.15), 20)
	Kit.cyl(self, 0.04, 0.22, 0.72, Vector3(tc.x, 0.36, tc.y), gold, 12)
	Kit.cyl(self, 0.2, 0.2, 0.015, Vector3(tc.x, 0.75, tc.y), _metal("d7dade", 0.15), 16)
	Kit.ball(self, 0.13, Vector3(tc.x, 0.78, tc.y), _metal("d7dade", 0.15), Vector3(1, 0.7, 1))
	_solid(tc, Vector2(0.36, 0.36))
	for sx in [-1.0, 1.0]:
		var cc := Vector2(tc.x + sx * 0.95, tc.y)
		Kit.box(self, Vector3(0.6, 0.4, 0.6), Vector3(cc.x, 0.22, cc.y), Kit.plush(Color("2f4a5a")))
		Kit.box(self, Vector3(0.14, 0.5, 0.6), Vector3(cc.x + sx * 0.25, 0.62, cc.y), Kit.plush(Color("2f4a5a")))
		_solid(cc, Vector2(0.3, 0.3))
	# Hayvan yatagi ve mama kabi
	Kit.cyl(self, 0.5, 0.52, 0.1, Vector3(petbed_local.x, 0.05, petbed_local.y), Kit.plush(Color("d9c7a3")), 18)
	Kit.torus(self, 0.36, 0.54, Vector3(petbed_local.x, 0.11, petbed_local.y), Kit.mat("7a1f2b", 0.95))
	Kit.cyl(self, 0.13, 0.1, 0.07, Vector3(petbed_local.x + 0.85, 0.035, petbed_local.y + 0.2), Kit.mat("c8322b", 0.4), 12)
	_lbl("EVCİL DOSTU ODA", Vector3(0.02, 1.3, 5.3), 0.1, Color("7a1f2b"), PI * 0.5)
	# Gardirop (sol on kose) ve valiz
	Kit.box(self, Vector3(0.6, 2.2, 1.2), Vector3(0.32, 1.1, D - 0.65), wood)
	Kit.box(self, Vector3(0.02, 2.0, 0.02), Vector3(0.63, 1.1, D - 0.65), gold)
	_solid(Vector2(0.32, D - 0.65), Vector2(0.3, 0.6))
	# On duvar ve oda kapisi (kamera bu yonden bakar)
	Kit.box(front, Vector3(W, H, 0.1), Vector3(W * 0.5, H * 0.5, D + 0.05), Kit.mat("e9e1d2", 0.85))
	Kit.box(self, Vector3(1.0, 0.02, 0.6), Vector3(entrance_local.x, 0.011, D - 0.35), Kit.mat("3b3d41", 1.0))
	Kit.box(self, Vector3(0.95, 2.1, 0.06), Vector3(entrance_local.x, 1.05, D - 0.02), wood)
	Kit.ball(self, 0.035, Vector3(entrance_local.x - 0.36, 1.0, D - 0.08), gold)
	_lbl("304", Vector3(entrance_local.x, 1.7, D - 0.06), 0.12, Color("e7c67a"), PI)
	# Isiklar
	Kit.cyl(ceiling, 0.3, 0.3, 0.05, Vector3(3.7, H - 0.02, 3.2), Kit.glow("fff3dc", 2.2), 16)
	for lp in [Vector3(3.7, H - 0.5, 3.2), Vector3(1.0, 1.4, 2.9)]:
		var o := OmniLight3D.new()
		o.position = lp
		o.omni_range = 7.5
		o.light_energy = 0.5 if lp.y > 2.0 else 0.25
		o.light_color = Color("ffe9c8")
		add_child(o)
