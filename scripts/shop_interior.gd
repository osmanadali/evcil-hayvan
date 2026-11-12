extends Node3D
## Market ve eczane ici: yer altinda (y = -300) kurulan, yurunebilen dukkan.
## Ev (home.gd) ile ayni arayuz: has_point, resolve, is_free, w2, local2, update_view, entrance_local.
## Yerel koordinat: x 0..W (genislik), z 0..D (derinlik); kapi z = D tarafinda (on cephe).

const Kit = preload("res://scripts/kit.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const W := 11.0
const D := 9.0
const H := 3.2

var kind := "market"            # "market" | "eczane"
var title := "Market"
var entrance_local := Vector2(W * 0.5, D - 0.8)
var counter_local := Vector2(2.2, D - 2.6)   # kasanin onu (oyuncu burada alisveris yapar)
var colliders: Array = []        # [Vector2 a, Vector2 b] yerel
var ceiling: Node3D
var front: Node3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 11 if kind == "market" else 23
	_build_shell()
	if kind == "eczane":
		_build_pharmacy()
	else:
		_build_market()


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
		# Kamera on cephenin disindaysa cam/cerceve gorusu kapatmasin
		front.visible = cam_pos.z - global_position.z < D


# ---------------------------------------------------------------- yapim

func _solid(c: Vector2, half: Vector2) -> void:
	var a := c - half
	var b := c + half
	colliders.append([a, Vector2(b.x, a.y)])
	colliders.append([Vector2(b.x, a.y), b])
	colliders.append([b, Vector2(a.x, b.y)])
	colliders.append([Vector2(a.x, b.y), a])


func _build_shell() -> void:
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_texture = load("res://assets/home/karo_beyaz.jpg")
	floor_m.uv1_scale = Vector3(W / 0.6, D / 0.6, 1)
	floor_m.albedo_color = Color("cfcac0") if kind == "market" else Color("d6dbd8")
	floor_m.roughness = 0.25
	Kit.box(self, Vector3(W, 0.1, D), Vector3(W * 0.5, -0.05, D * 0.5), floor_m)
	var wall := Kit.mat("e2ddd2" if kind == "market" else "d9e6df", 0.8)
	Kit.box(self, Vector3(W, H, 0.12), Vector3(W * 0.5, H * 0.5, -0.06), wall)
	Kit.box(self, Vector3(0.12, H, D), Vector3(-0.06, H * 0.5, D * 0.5), wall)
	Kit.box(self, Vector3(0.12, H, D), Vector3(W + 0.06, H * 0.5, D * 0.5), wall)
	# On cephe: vitrin camlari, ortada kapi
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.88, 0.95, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var frame := Kit.mat("3a3d42", 0.4)
	front = Node3D.new()
	add_child(front)
	Kit.box(front, Vector3(W, 0.5, 0.12), Vector3(W * 0.5, 0.25, D + 0.06), frame)
	Kit.box(front, Vector3(W, 0.6, 0.12), Vector3(W * 0.5, H - 0.3, D + 0.06), frame)
	for side in [-1.0, 1.0]:
		var cx: float = W * 0.5 + side * (W * 0.25 + 0.5)
		Kit.box(front, Vector3(W * 0.5 - 1.0, H - 1.1, 0.04), Vector3(cx, 0.5 + (H - 1.1) * 0.5, D + 0.06), glass)
		Kit.box(front, Vector3(0.1, H, 0.14), Vector3(W * 0.5 + side * 1.0, H * 0.5, D + 0.06), frame)
	# Disarisi: parlak gun isigi (camdan gorunsun)
	var outside := StandardMaterial3D.new()
	outside.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outside.albedo_color = Color("dfe9ef")
	Kit.box(self, Vector3(W + 6, H + 2, 0.1), Vector3(W * 0.5, H * 0.5, D + 3.0), outside)
	Kit.box(self, Vector3(W + 6, 0.1, 3.0), Vector3(W * 0.5, -0.06, D + 1.5), Kit.mat("b9b4aa", 0.9))
	# Kapi paspasi
	Kit.box(self, Vector3(1.6, 0.02, 1.0), Vector3(W * 0.5, 0.01, D - 0.6), Kit.mat("3b3d41", 1.0))
	# Tavan, aydinlatma
	ceiling = Node3D.new()
	add_child(ceiling)
	Kit.box(ceiling, Vector3(W, 0.1, D), Vector3(W * 0.5, H + 0.05, D * 0.5), Kit.mat("f6f6f4", 0.8))
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color.WHITE
	lamp.emission_enabled = true
	lamp.emission = Color("fbfbff")
	lamp.emission_energy_multiplier = 2.0
	for x in [2.5, 5.5, 8.5]:
		for z in [2.2, 5.2]:
			Kit.box(ceiling, Vector3(1.2, 0.04, 0.3), Vector3(x, H - 0.02, z), lamp)
	for x in [2.8, 8.2]:
		var o := OmniLight3D.new()
		o.position = Vector3(x, H - 0.4, D * 0.45)
		o.omni_range = 9.0
		o.light_energy = 0.8
		add_child(o)
	var o2 := OmniLight3D.new()
	o2.position = Vector3(W * 0.5, H - 0.4, D - 2.0)
	o2.omni_range = 7.0
	o2.light_energy = 0.6
	add_child(o2)


func _product(at: Vector3, size: Vector3, col: Color) -> void:
	Kit.box(self, size, at + Vector3(0, size.y * 0.5, 0), Kit.mat(col.to_html(false), 0.55))


func _shelf_unit(c: Vector2, length: float, two_sided: bool, palette: Array) -> void:
	var metal := Kit.mat("d9dcdf", 0.4)
	var depth := 0.9 if two_sided else 0.45
	Kit.box(self, Vector3(length, 1.9, 0.05), Vector3(c.x, 0.95, c.y), metal)
	for y in [0.12, 0.55, 0.98, 1.41]:
		Kit.box(self, Vector3(length, 0.03, depth), Vector3(c.x, y, c.y), metal)
		for side in ([-1.0, 1.0] if two_sided else [1.0]):
			var x := c.x - length * 0.5 + 0.12
			while x < c.x + length * 0.5 - 0.15:
				var w: float = _rng.randf_range(0.12, 0.26)
				var h: float = _rng.randf_range(0.18, 0.36)
				var col: Color = Color(palette[_rng.randi() % palette.size()])
				_product(Vector3(x + w * 0.5, y + 0.015, c.y + side * depth * 0.28), Vector3(w * 0.9, h, 0.2), col.lightened(_rng.randf_range(-0.1, 0.15)))
				x += w
	_solid(c, Vector2(length * 0.5, depth * 0.5))


func _counter(c: Vector2, length: float, top_hex: String) -> void:
	Kit.box(self, Vector3(length, 1.0, 0.7), Vector3(c.x, 0.5, c.y), Kit.mat("4a4d52", 0.5))
	Kit.box(self, Vector3(length + 0.06, 0.05, 0.76), Vector3(c.x, 1.02, c.y), Kit.mat(top_hex, 0.3))
	_solid(c, Vector2(length * 0.5, 0.35))


func _staff(at: Vector2, face_y: float, shirt: Color, female: bool) -> void:
	var v := PersonModel.new()
	v.kind = "kadin" if female else "erkek"
	v.tint = shirt
	v.position = Vector3(at.x, 0, at.y)
	v.rotation.y = face_y
	add_child(v)


func _sign(text: String, at: Vector3, bg: String, fg: Color) -> void:
	Kit.box(self, Vector3(text.length() * 0.2 + 0.6, 0.5, 0.05), at, Kit.mat(bg, 0.4))
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.0045
	l.modulate = fg
	l.position = at + Vector3(0, 0, 0.04)
	add_child(l)


func _build_market() -> void:
	var foods := ["c8322b", "e07b1f", "f2c230", "2f62a8", "3f8f4a", "ffffff", "7a4a2b", "b84a8a", "1d6e8a"]
	# Ortada iki cift tarafli raf, arka duvarda buzdolaplari, sag duvarda raf
	_shelf_unit(Vector2(4.2, 4.0), 4.0, true, foods)
	_shelf_unit(Vector2(4.2, 6.0), 4.0, true, foods)
	# Sag duvar boyunca raf (90 derece donuk; elle kur)
	var metal := Kit.mat("d9dcdf", 0.4)
	for y in [0.12, 0.55, 0.98, 1.41]:
		Kit.box(self, Vector3(0.45, 0.03, 5.0), Vector3(W - 0.25, y, 4.0), metal)
		var z := 1.6
		while z < 6.4:
			var w: float = _rng.randf_range(0.14, 0.26)
			_product(Vector3(W - 0.3, y + 0.015, z + w * 0.5), Vector3(0.22, _rng.randf_range(0.2, 0.36), w * 0.9), Color(foods[_rng.randi() % foods.size()]))
			z += w
	_solid(Vector2(W - 0.25, 4.0), Vector2(0.25, 2.5))
	# Buzdolaplari: arka duvar, isikli
	var fridge_glass := StandardMaterial3D.new()
	fridge_glass.albedo_color = Color(0.85, 0.95, 1.0, 0.25)
	fridge_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("eaf6ff")
	glow.emission_enabled = true
	glow.emission = Color("d9efff")
	glow.emission_energy_multiplier = 0.8
	for i in 4:
		var x := 1.4 + i * 1.6
		Kit.box(self, Vector3(1.5, 2.1, 0.7), Vector3(x, 1.05, 0.4), Kit.mat("e8eaec", 0.3))
		Kit.box(self, Vector3(1.4, 1.9, 0.02), Vector3(x, 1.1, 0.06), glow)
		for y in [0.35, 0.8, 1.25, 1.7]:
			for k in 6:
				var col: Color = Color(["e0322b", "2f8a3a", "f2c230", "ffffff", "1f5aa8", "f07a1a"][(i + k) % 6])
				Kit.cyl(self, 0.035, 0.035, 0.26, Vector3(x - 0.55 + k * 0.22, y + 0.13, 0.35), Kit.mat(col.to_html(false), 0.3), 8)
		Kit.box(self, Vector3(1.42, 1.9, 0.02), Vector3(x, 1.1, 0.76), fridge_glass)
	_solid(Vector2(3.8, 0.4), Vector2(3.3, 0.4))
	# Meyve-sebze kasalari (girisin solunda)
	for i in 3:
		var c := Vector2(8.2 + (i % 2) * 0.9, 7.2 - (i / 2) * 0.8)
		Kit.box(self, Vector3(0.8, 0.5, 0.6), Vector3(c.x, 0.25, c.y), Kit.mat("a8774a", 0.8))
		var fc: String = ["e0322b", "f2a01a", "6aa84f"][i]
		for k in 8:
			Kit.ball(self, 0.06, Vector3(c.x - 0.28 + (k % 4) * 0.18, 0.55, c.y - 0.12 + (k / 4) * 0.22), Kit.mat(fc, 0.5), Vector3.ONE, 8)
	_solid(Vector2(8.65, 6.8), Vector2(0.85, 0.7))
	# Mama reyonu: kopek/kedi mamalari
	for k in 6:
		_product(Vector3(6.6 + (k % 3) * 0.45, 0.0, 2.0 + (k / 3) * 0.0 + (k / 3) * 0.5), Vector3(0.38, 0.55, 0.22), Color(["c9962e", "8a5a2b", "e07b1f"][k % 3]))
	_sign("Mama Reyonu", Vector3(7.05, 2.2, 1.6), "e07b1f", Color.WHITE)
	_solid(Vector2(7.05, 2.25), Vector2(0.75, 0.45))
	# Kasa
	_counter(Vector2(2.2, D - 1.6), 2.4, "e8e2d4")
	Kit.box(self, Vector3(0.4, 0.3, 0.3), Vector3(1.6, 1.2, D - 1.6), Kit.mat("1d1e21", 0.4))
	Kit.box(self, Vector3(0.6, 0.02, 0.4), Vector3(2.6, 1.05, D - 1.6), Kit.mat("2a2c30", 0.3))
	_staff(Vector2(2.0, D - 2.3), PI, Color("c8322b"), true)
	counter_local = Vector2(2.6, D - 0.85)
	_sign(title, Vector3(W * 0.5, H - 0.5, 0.1), "c8322b", Color.WHITE)
	# Alisveris sepetleri
	for k in 3:
		Kit.box(self, Vector3(0.45, 0.25, 0.32), Vector3(4.0, 0.12 + k * 0.08, D - 0.9), Kit.mat("d0302b", 0.5))


func _build_pharmacy() -> void:
	var meds := ["ffffff", "f4f4f0", "d9ecf7", "fde7e7", "e6f4e6"]
	var stripes := ["c8322b", "2f62a8", "3f8f4a", "e07b1f", "7a4ab8"]
	# Arka duvar boyunca ilac dolaplari (tezgahin arkasi)
	var wood := Kit.mat("e8e2d4", 0.6)
	Kit.box(self, Vector3(W - 1.0, 2.6, 0.5), Vector3(W * 0.5, 1.3, 0.3), wood)
	for row in 6:
		var y := 0.3 + row * 0.38
		Kit.box(self, Vector3(W - 1.1, 0.02, 0.45), Vector3(W * 0.5, y, 0.35), Kit.mat("d4cdbd", 0.5))
		var x := 0.8
		while x < W - 0.8:
			var w: float = _rng.randf_range(0.1, 0.2)
			var h: float = _rng.randf_range(0.12, 0.28)
			var c := Vector3(x + w * 0.5, y + 0.01, 0.45)
			_product(c, Vector3(w * 0.9, h, 0.16), Color(meds[_rng.randi() % meds.size()]))
			Kit.box(self, Vector3(w * 0.9, 0.03, 0.005), c + Vector3(0, h * 0.6, 0.082), Kit.mat(stripes[_rng.randi() % stripes.size()], 0.5))
			x += w + 0.02
	_solid(Vector2(W * 0.5, 0.3), Vector2(W * 0.5 - 0.5, 0.3))
	# Uzun tezgah ve eczaci
	_counter(Vector2(W * 0.5, 2.4), 6.0, "f4f4f0")
	Kit.box(self, Vector3(0.45, 0.32, 0.06), Vector3(W * 0.5 - 1.5, 1.25, 2.3), Kit.mat("1d1e21", 0.3))
	_staff(Vector2(W * 0.5 - 0.5, 1.4), 0.0, Color("f4f4f0"), false)
	counter_local = Vector2(W * 0.5 - 0.5, 3.3)
	# Yesil hac, adi
	var green := StandardMaterial3D.new()
	green.albedo_color = Color("1e9a4a")
	green.emission_enabled = true
	green.emission = Color("1e9a4a")
	green.emission_energy_multiplier = 1.2
	Kit.box(self, Vector3(0.6, 0.18, 0.04), Vector3(1.4, 2.75, 0.6), green)
	Kit.box(self, Vector3(0.18, 0.6, 0.04), Vector3(1.4, 2.75, 0.6), green)
	_sign(title, Vector3(W * 0.5, 2.85, 0.6), "1e9a4a", Color.WHITE)
	# Sergi standlari: bakim urunleri, evcil hayvan urunleri
	for i in 2:
		var c := Vector2(2.5 + i * 6.0, 5.6)
		Kit.box(self, Vector3(1.2, 1.3, 1.2), Vector3(c.x, 0.65, c.y), Kit.mat("ffffff", 0.4))
		for k in 9:
			_product(Vector3(c.x - 0.4 + (k % 3) * 0.4, 1.3, c.y - 0.4 + (k / 3) * 0.4), Vector3(0.14, 0.22, 0.14), Color(stripes[(k + i) % stripes.size()]).lightened(0.3))
		_solid(c, Vector2(0.6, 0.6))
	_sign("Evcil Hayvan Bakım", Vector3(8.5, 1.85, 5.6 - 0.62), "2f62a8", Color.WHITE)
	# Bekleme sandalyeleri, tarti
	for k in 3:
		Kit.box(self, Vector3(0.45, 0.45, 0.45), Vector3(W - 0.5, 0.45, 4.0 + k * 0.55), Kit.mat("2f62a8", 0.6))
		Kit.box(self, Vector3(0.06, 0.5, 0.45), Vector3(W - 0.28, 0.85, 4.0 + k * 0.55), Kit.mat("2f62a8", 0.6))
	_solid(Vector2(W - 0.5, 4.55), Vector2(0.3, 0.85))
	Kit.box(self, Vector3(0.35, 1.6, 0.35), Vector3(0.6, 0.8, 6.2), Kit.mat("d9dcdf", 0.3))
	_solid(Vector2(0.6, 6.2), Vector2(0.2, 0.2))
