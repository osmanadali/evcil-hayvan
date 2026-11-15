extends Node
## Altinpark gol iskelesi: bilet kulubesi, beyaz tur teknesi ve pedalli botlar.
## - Kulubede F: "Gol Turu" (40 TL, ~90 sn) ya da "Pedalli Bot" (20 TL / 5 dk).
## - Tur: tekne kiyidan iceri kayan bir halka boyunca (water_sd ile hesaplanir) gole bir tur atar, kaptan
##   konusur, martilar eslik eder; yalniz iskelede inilir.
## - Pedalli bot: hareket tuslari / cubuk ile suda dolasilir; iskele yakininda F ile birakilir.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PersonModel = preload("res://scripts/person_model.gd")
const F_TITLE := preload("res://assets/fonts/Bangers-Regular.ttf")

const TOUR_PRICE := 40
const PEDAL_PRICE := 20
const PEDAL_TIME := 300.0
const RING_STEPS := 96
const HALF_LEN := 4.5

var m: Node                     # main
var state: Node
var built := false
var wy := 0.0                   # su yuzeyi yuksekligi
var center := Vector2.ZERO
var ring := PackedVector2Array()
var i0 := 0                     # iskeleye en yakin halka noktasi
var p0 := Vector2.ZERO          # iskelenin kara ucu
var d := Vector2.ZERO           # iskelenin suya dogru yonu
var n := Vector2.ZERO           # iskelenin yan yonu
var pier_len := 12.0
var booth_pos := Vector2.ZERO
var booth_front := Vector2.ZERO
var exit_pos := Vector2.ZERO
var dock_pos := Vector2.ZERO
var dock_yaw_out := 0.0

var root: Node3D
var boat: Node3D
var captain: Node3D
var wheel: Node3D
var flag: Node3D
var pax: Array = []
var pedalos: Array = []         # [{node, home, rot, pedal}]
var wake: CPUParticles3D
var spray: CPUParticles3D
var birds: Array = []           # martilar
var ducks: Array = []

var mode := ""                  # "" / "tour" / "pedal"
var phase := ""                 # tour: turn, sail, docked | pedal: free, return, docked
var _t := 0.0
var _path: Array = []           # [Vector2]
var _cum: PackedFloat32Array = PackedFloat32Array()
var _len := 0.0
var _s := 0.0
var _cruise := 5.5
var _yaw := 0.0
var _turn_t := 0.0
var _speak_i := 0
var _speak_t := 0.0
var _bird_t := 4.0
var _pedal_left := 0.0
var _pspeed := 0.0
var _pedalo: Dictionary = {}
var _save_zoom := 1.0
var _motor_p: AudioStreamPlayer
var _wash_p: AudioStreamPlayer
var _gull_p: AudioStreamPlayer
var _horn_p: AudioStreamPlayer
var _foam_tex: Texture2D
var _roll := 0.0

const SPEECH := [
	[0.0, "Hoş geldiniz! Göl turumuza çıkıyoruz, sıkı tutunun!"],
	[0.10, "Sağ tarafımızda Altınpark. Ankara'nın yeşil kalbi."],
	[0.26, "Ördekler selam veriyor, el sallayın!"],
	[0.42, "Gölün ortasından geçiyoruz. Manzara bedava!"],
	[0.58, "Kıyıdaki piknikçilere bakın, kim bilir ne pişiriyorlar."],
	[0.74, "Martılar bizi bırakmıyor. Simit istiyorlar galiba."],
	[0.90, "İskeleye yaklaşıyoruz. Tur bitti, gelişinize değdi!"],
]
const PAX_LINES := ["Ne güzel manzara!", "Çok serinledik.", "Fotoğraf çekelim mi?", "Vay be, harika!"]


func riding() -> bool:
	return mode != ""


# ---------------------------------------------------------------- kurulum

func build() -> void:
	var idx := _pick_lake()
	if idx < 0:
		return
	var box: Rect2 = ParkMap.water_boxes[idx]
	# En derin nokta (kiyidan en uzak) halkanin merkezi olur
	var best := 99.0
	for x in range(int(box.position.x), int(box.end.x), 5):
		for z in range(int(box.position.y), int(box.end.y), 5):
			var sd: float = ParkMap.water_sd(Vector2(x, z))
			if sd < best:
				best = sd
				center = Vector2(x, z)
	if best > -12.0:
		return
	wy = ParkMap.terrain_height(center) + ParkMap.WATER_LIFT
	if not _build_ring():
		return
	if not _pick_pier():
		return
	root = Node3D.new()
	root.name = "GolIskelesi"
	m.world.add_child(root)
	_build_pier()
	_build_booth()
	boat = _build_yacht()
	root.add_child(boat)
	_yaw = dock_yaw_out
	boat.position = Vector3(dock_pos.x, wy, dock_pos.y)
	boat.rotation.y = _yaw
	_build_pedalos()
	_build_wildlife()
	_setup_audio()
	built = true


## Gol: genisligi 400 m'den kucuk, en genis su govdesi.
func _pick_lake() -> int:
	var idx := -1
	var best := 0.0
	for i in ParkMap.water_boxes.size():
		var r: Rect2 = ParkMap.water_boxes[i]
		if r.size.x > 400.0 or r.size.y > 400.0:
			continue
		var a := r.size.x * r.size.y
		if a > best:
			best = a
			idx = i
	return idx


func _ray_exit(dir: Vector2, level: float) -> float:
	var r := 2.0
	while r < 300.0:
		if ParkMap.water_sd(center + dir * r) > level:
			return r - 1.5
		r += 1.5
	return 300.0


func _build_ring() -> bool:
	var inset := 14.0
	var rs := PackedFloat32Array()
	for tries in 2:
		rs.resize(RING_STEPS)
		for i in RING_STEPS:
			rs[i] = _ray_exit(Vector2.from_angle(TAU * i / RING_STEPS), -inset)
		# En yakin komsulara gore kisalt, sonra yumusat
		var mn := PackedFloat32Array()
		mn.resize(RING_STEPS)
		for i in RING_STEPS:
			var v := rs[i]
			for k in range(-3, 4):
				v = minf(v, rs[posmod(i + k, RING_STEPS)])
			mn[i] = v
		for pass_i in 4:
			var sm := PackedFloat32Array()
			sm.resize(RING_STEPS)
			for i in RING_STEPS:
				sm[i] = (mn[posmod(i - 1, RING_STEPS)] + mn[i] * 2.0 + mn[posmod(i + 1, RING_STEPS)]) * 0.25
			mn = sm
		ring.clear()
		var lo := 999.0
		for i in RING_STEPS:
			var p := center + Vector2.from_angle(TAU * i / RING_STEPS) * mn[i]
			# suyun disina tasmasin
			var guard := 0
			while ParkMap.water_sd(p) > -inset * 0.6 and guard < 20:
				mn[i] -= 1.0
				p = center + Vector2.from_angle(TAU * i / RING_STEPS) * mn[i]
				guard += 1
			ring.append(p)
			lo = minf(lo, mn[i])
		if lo > 22.0:
			return true
		inset = 8.0
	return ring.size() == RING_STEPS and center.distance_to(ring[0]) > 12.0


func _pick_pier() -> bool:
	var ref := ParkMap.spot("baslangic") if ParkMap.has_spot("baslangic") else center
	var cands: Array = []
	for i in RING_STEPS:
		var dir := Vector2.from_angle(TAU * i / RING_STEPS)
		var r := 2.0
		while r < 300.0 and ParkMap.water_sd(center + dir * r) < 0.0:
			r += 1.0
		var shore := center + dir * r
		cands.append([shore.distance_to(ref), i, shore, dir])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands:
		var shore: Vector2 = c[2]
		var dir: Vector2 = c[3]
		var land1 := shore + dir * 2.5
		var land2 := shore + dir * 6.0
		if not (m.world.is_free(land1, 0.7) and m.world.is_free(land2, 0.7) and not m.world._inside_building(land2)):
			continue
		d = -dir
		n = Vector2(-d.y, d.x)
		p0 = shore + dir * 1.0
		i0 = c[1]
		# Tekne yeri: iskeleye paralel, suyun yeterince derin oldugu yerde
		var ok := false
		for side in [1.0, -1.0]:
			for t in range(7, 20):
				var dp: Vector2 = p0 + d * float(t) + n * 3.6 * side
				if _boat_clear(dp):
					dock_pos = dp
					pier_len = float(t) + 3.0
					ok = true
					break
			if ok:
				break
		if not ok:
			continue
		dock_yaw_out = atan2(-d.x, -d.y)
		# Kulube: kara tarafinda, iskele eksenine bakar
		for side in [1.0, -1.0]:
			var bp: Vector2 = p0 - d * 2.2 + n * 3.4 * side
			if m.world.is_free(bp, 1.4) and m.world.is_free(bp - n * side * 2.3, 0.4):
				booth_pos = bp
				booth_front = bp - n * side * 2.3
				break
		if booth_pos == Vector2.ZERO:
			continue
		exit_pos = p0 - d * 1.6
		if not m.world.is_free(exit_pos, 0.4):
			exit_pos = booth_front
		m.world._add_circle(Vector3(booth_pos.x, booth_pos.y, 1.5))
		return true
	return false


func _boat_clear(p: Vector2) -> bool:
	for k in [-HALF_LEN - 0.5, 0.0, HALF_LEN + 0.5]:
		for s in [-1.9, 0.0, 1.9]:
			if ParkMap.water_sd(p + d * k + n * s) > -1.2:
				return false
	return true


func _mat_vc() -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.roughness = 0.38
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mt


func _hw(z: float) -> float:
	var u := (z + HALF_LEN) / (HALF_LEN * 2.0)      # 0 bornoz .. 1 kic
	var b := clampf(u / 0.45, 0.0, 1.0)
	var w := 1.6 * sqrt(maxf(1.0 - (1.0 - b) * (1.0 - b), 0.0))
	if u > 0.8:
		w *= 1.0 - 0.1 * (u - 0.8) / 0.2
	return w


func _deck_h(z: float) -> float:
	var u := (z + HALF_LEN) / (HALF_LEN * 2.0)
	return 0.8 + 0.35 * (1.0 - u) * (1.0 - u)


# ---------------------------------------------------------------- iskele ve kulube

func _build_pier() -> void:
	var wood := Kit.mat("8a6a43", 0.9)
	var dark := Kit.mat("4f3a26", 0.9)
	var metal := Kit.mat("9aa3ab", 0.5)
	var pr := Node3D.new()
	pr.name = "Iskele"
	pr.position = Vector3(p0.x, wy, p0.y)
	pr.rotation.y = atan2(-d.x, -d.y)
	root.add_child(pr)
	var L := pier_len + 1.5
	var zc := 1.0 - L * 0.5
	# Tahta zemin: enine tahtalar
	var nb := int(L / 0.42)
	for i in nb:
		var z := 1.0 - (i + 0.5) * L / nb
		var w := 2.5
		Kit.box(pr, Vector3(w, 0.07, L / nb - 0.04), Vector3(0, 0.5, z), wood if i % 2 == 0 else dark)
	for sx in [-1.0, 1.0]:
		Kit.box(pr, Vector3(0.12, 0.22, L), Vector3(sx * 1.2, 0.38, zc), dark)
	# Kazik ve korkuluk
	var np := int(L / 2.4) + 1
	for i in np:
		var z := 0.6 - i * 2.4
		for sx in [-1.0, 1.0]:
			Kit.cyl(pr, 0.1, 0.1, 2.6, Vector3(sx * 1.2, -0.7, z), dark, 8)
			if i > 0:
				Kit.cyl(pr, 0.04, 0.04, 0.8, Vector3(sx * 1.2, 0.95, z), metal, 6)
	for sx in [-1.0, 1.0]:
		Kit.box(pr, Vector3(0.05, 0.05, L - 2.4), Vector3(sx * 1.2, 1.32, zc - 1.2), metal)
		Kit.box(pr, Vector3(0.04, 0.04, L - 2.4), Vector3(sx * 1.2, 0.95, zc - 1.2), metal)
	# Giris takı ve tabela
	for sx in [-1.0, 1.0]:
		Kit.cyl(pr, 0.09, 0.09, 3.0, Vector3(sx * 1.45, 1.9, 0.4), Kit.mat("f1f3f5", 0.5), 8)
	Kit.box(pr, Vector3(3.5, 0.9, 0.12), Vector3(0, 3.1, 0.4), Kit.mat("1d5fa8", 0.6))
	var l1 := _label(pr, "ALTINPARK GÖL İSKELESİ", Vector3(0, 3.1, 0.47), 0.42, Color("ffffff"), Color("0c2d52"))
	l1.position.y = 3.1
	var l2 := _label(pr, "İYİ SEYİRLER", Vector3(0, 3.1, 0.33), 0.42, Color("ffffff"), Color("0c2d52"))
	l2.rotation.y = PI
	# Uc fener (gece yanar)
	var lamp := Kit.glow("ffd98a", 1.6)
	for sx in [-1.0, 1.0]:
		Kit.cyl(pr, 0.06, 0.06, 1.8, Vector3(sx * 1.2, 1.4, 2.0 - L), dark, 6)
		Kit.ball(pr, 0.13, Vector3(sx * 1.2, 2.4, 2.0 - L), lamp, Vector3.ONE, 8)
	# Can simidi
	var ring_m := Kit.mat("e5432d", 0.7)
	Kit.torus(pr, 0.16, 0.32, Vector3(1.28, 1.0, -2.0), ring_m, Vector3(0, 0, PI * 0.5))
	# Tekne tarafinda baglama babalari
	var bside := signf((dock_pos - p0).dot(n))
	for k in 3:
		Kit.cyl(pr, 0.07, 0.09, 0.35, Vector3(1.0 * bside, 0.7, -3.0 - k * 3.0), metal, 8)


func _build_booth() -> void:
	var b := Node3D.new()
	b.name = "BiletKulubesi"
	b.position = m.world.at(booth_pos)
	var face := (booth_front - booth_pos).normalized()
	b.rotation.y = atan2(face.x, face.y)       # yerel +Z, cepheye bakar
	root.add_child(b)
	var wall := Kit.mat("f3efe4", 0.7)
	var blue := Kit.mat("1d5fa8", 0.6)
	var red := Kit.mat("d9423a", 0.6)
	Kit.box(b, Vector3(2.4, 0.2, 2.2), Vector3(0, 0.1, 0), Kit.mat("8c8f94", 0.9))
	Kit.box(b, Vector3(2.2, 0.9, 2.0), Vector3(0, 0.65, 0), wall)
	Kit.box(b, Vector3(0.12, 1.2, 2.0), Vector3(-1.05, 1.7, 0), wall)
	Kit.box(b, Vector3(0.12, 1.2, 2.0), Vector3(1.05, 1.7, 0), wall)
	Kit.box(b, Vector3(2.2, 1.2, 0.12), Vector3(0, 1.7, -0.95), wall)
	# On tezgah ve acik pencere
	Kit.box(b, Vector3(2.4, 0.08, 0.5), Vector3(0, 1.12, 1.15), Kit.mat("6a4a2e", 0.7))
	# Cati: mavi-beyaz seritli, one dogru uzanir
	for i in 6:
		Kit.box(b, Vector3(0.43, 0.1, 2.9), Vector3(-1.08 + i * 0.43, 2.4, 0.35), blue if i % 2 == 0 else Kit.mat("f6f8fa", 0.6), Vector3(0.12, 0, 0))
	Kit.box(b, Vector3(2.5, 0.35, 0.08), Vector3(0, 2.1, 1.75), red)
	var t1 := _label(b, "GÖL TURU · 40 ₺", Vector3(0, 2.1, 1.8), 0.3, Color("ffffff"), Color("5a0f0b"))
	t1.double_sided = false
	var board := Kit.box(b, Vector3(1.7, 1.0, 0.07), Vector3(1.55, 1.25, 0.9), Kit.mat("22313f", 0.8), Vector3(0, 0.4, 0))
	var t2 := _label(board, "GÖL TURU  40 ₺\nPEDALLI BOT 20 ₺\n/ 5 dk", Vector3(0, 0.05, 0.05), 0.2, Color("ffe07a"), Color("000000"))
	t2.text = "GÖL TURU  40 ₺\nPEDALLI BOT\n20 ₺ / 5 dk"
	# Gorevli
	var clerk := _person("erkek", "1d5fa8", "22303d")
	clerk.position = Vector3(0, 0.2, 0.15)
	clerk.rotation.y = 0.0
	b.add_child(clerk)
	Kit.box(b, Vector3(0.5, 0.06, 0.4), Vector3(0.6, 1.2, 1.05), Kit.mat("d8d2c4", 0.8))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.0, 0.8)
	lamp.light_energy = 0.0
	lamp.omni_range = 7.0
	lamp.light_color = Color("ffd9a0")
	b.add_child(lamp)
	b.set_meta("lamp", lamp)


func _label(parent: Node3D, text: String, pos: Vector3, size: float, color: Color, outline: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = F_TITLE
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = outline
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.position = pos
	parent.add_child(l)
	return l


func _person(kind: String, shirt: String, pants: String) -> Node3D:
	var v := PersonModel.new()
	v.kind = kind
	v.tint = Color(shirt)
	v.tint2 = Color(shirt)
	v.pants = Color(pants)
	return v


# ---------------------------------------------------------------- tekne

func _build_yacht() -> Node3D:
	var b := Node3D.new()
	b.name = "TurTeknesi"
	# Govde: kesitlerden olusan mesh
	var stations := 19
	var rows_l := [[0.0, 1.0, Color("f6f8fa")], [-0.17, 1.0, Color("f6f8fa")], [-0.19, 0.995, Color("d9423a")], [-0.36, 0.985, Color("d9423a")],
		[-0.38, 0.98, Color("f6f8fa")], [-9.0, 0.96, Color("f6f8fa")], [-9.1, 0.8, Color("1c3d6e")], [-9.2, 0.5, Color("1c3d6e")]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in stations:
		var z := -HALF_LEN + i * (HALF_LEN * 2.0) / (stations - 1)
		var w := _hw(z)
		var dh := _deck_h(z)
		var ring_pts: Array = []
		var left: Array = []
		for r in rows_l:
			var y: float = dh + float(r[0]) if float(r[0]) > -2.0 else (0.05 if float(r[0]) == -9.0 else (-0.1 if float(r[0]) == -9.1 else -0.55))
			left.append([Vector3(-w * float(r[1]), y, z), r[2]])
		ring_pts.append_array(left)
		for k in range(left.size() - 1, -1, -1):
			var lp: Array = left[k]
			var v: Vector3 = lp[0]
			ring_pts.append([Vector3(-v.x, v.y, v.z), lp[1]])
		rings.append(ring_pts)
	for i in stations - 1:
		var a: Array = rings[i]
		var c: Array = rings[i + 1]
		for j in a.size() - 1:
			_quad(st, a[j], a[j + 1], c[j + 1], c[j])
	# Kic aynalik
	var last: Array = rings[stations - 1]
	for j in range(1, last.size() - 1):
		_tri(st, last[0], last[j], last[j + 1])
	st.generate_normals()
	var hull := Kit.add(b, st.commit(), _mat_vc())
	hull.name = "Govde"
	# Tik guverte
	var sd := SurfaceTool.new()
	sd.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color("a67c4e")
	for i in stations - 1:
		var za := -HALF_LEN + i * (HALF_LEN * 2.0) / (stations - 1)
		var zb := -HALF_LEN + (i + 1) * (HALF_LEN * 2.0) / (stations - 1)
		var wa := _hw(za) * 0.97
		var wb := _hw(zb) * 0.97
		_quad(sd, [Vector3(-wa, _deck_h(za) - 0.03, za), wood], [Vector3(wa, _deck_h(za) - 0.03, za), wood],
			[Vector3(wb, _deck_h(zb) - 0.03, zb), wood], [Vector3(-wb, _deck_h(zb) - 0.03, zb), wood])
	sd.generate_normals()
	var deck_mat := _mat_vc()
	deck_mat.roughness = 0.8
	Kit.add(b, sd.commit(), deck_mat).name = "Guverte"
	var white := Kit.mat("f6f8fa", 0.4)
	var chrome := Kit.mat("c9d0d6", 0.25)
	var blue := Kit.mat("1d5fa8", 0.6)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.45, 0.65, 0.8, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var dkh := _deck_h(0.0)
	# Kabin (acik onu ile dumen yeri)
	Kit.box(b, Vector3(0.1, 0.9, 3.0), Vector3(-1.1, dkh + 0.45, -0.1), white)
	Kit.box(b, Vector3(0.1, 0.9, 3.0), Vector3(1.1, dkh + 0.45, -0.1), white)
	Kit.box(b, Vector3(2.3, 0.9, 0.1), Vector3(0, dkh + 0.45, 1.4), white)
	Kit.box(b, Vector3(2.3, 0.1, 3.3), Vector3(0, dkh + 2.2, -0.1), white)
	Kit.box(b, Vector3(2.4, 0.06, 3.4), Vector3(0, dkh + 2.27, -0.1), blue)
	for sx in [-1.0, 1.0]:
		Kit.box(b, Vector3(0.06, 0.8, 2.6), Vector3(sx * 1.1, dkh + 1.4, -0.1), glass)
		for zz in [-1.55, 1.4]:
			Kit.cyl(b, 0.05, 0.05, 1.3, Vector3(sx * 1.1, dkh + 1.55, zz), chrome, 8)
	Kit.box(b, Vector3(2.2, 0.8, 0.05), Vector3(0, dkh + 1.4, -1.5), glass, Vector3(-0.25, 0, 0))
	Kit.box(b, Vector3(2.2, 0.8, 0.05), Vector3(0, dkh + 1.4, 1.38), glass)
	# Dumen tezgahi ve dumen
	Kit.box(b, Vector3(1.6, 0.55, 0.45), Vector3(0, dkh + 0.28, -1.25), blue)
	wheel = Kit.pivot(b, Vector3(0, dkh + 0.82, -1.1))
	wheel.rotation.x = -0.9
	Kit.torus(wheel, 0.19, 0.25, Vector3.ZERO, Kit.mat("6a4a2e", 0.5), Vector3(PI * 0.5, 0, 0))
	for k in 4:
		Kit.box(wheel, Vector3(0.5, 0.03, 0.03), Vector3.ZERO, Kit.mat("6a4a2e", 0.5), Vector3(0, k * PI * 0.25, 0))
	# Kaptan
	captain = _person("erkek", "f4f6f8", "1c2f4a")
	captain.position = Vector3(0, dkh, -0.55)
	captain.rotation.y = PI
	b.add_child(captain)
	var cap := Kit.cyl(b, 0.19, 0.22, 0.12, Vector3(0, dkh + 1.82, -0.55), Kit.mat("f4f6f8", 0.6), 14)
	Kit.cyl(b, 0.23, 0.23, 0.03, Vector3(0, dkh + 1.77, -0.64), Kit.mat("1c2f4a", 0.6), 14)
	cap.name = "Kasket"
	# Kic tente (yari saydam seritli) ve bankler
	var awn_a := StandardMaterial3D.new()
	awn_a.albedo_color = Color(0.11, 0.37, 0.66, 0.6)
	awn_a.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	awn_a.cull_mode = BaseMaterial3D.CULL_DISABLED
	var awn_b := awn_a.duplicate() as StandardMaterial3D
	awn_b.albedo_color = Color(0.97, 0.97, 0.97, 0.6)
	for i in 6:
		Kit.box(b, Vector3(0.5, 0.04, 2.5), Vector3(-1.25 + i * 0.5, dkh + 2.15 - (0.0 if i < 3 else 0.0), 3.0), awn_a if i % 2 == 0 else awn_b)
	for sx in [-1.0, 1.0]:
		for zz in [1.9, 4.0]:
			Kit.cyl(b, 0.04, 0.04, 2.15, Vector3(sx * 1.35, dkh + 1.07, zz - 0.25 if zz > 3.0 else zz), chrome, 8)
		Kit.box(b, Vector3(0.5, 0.08, 2.0), Vector3(sx * 1.05, dkh + 0.4, 3.0), Kit.mat("f1ead8", 0.7))
		Kit.box(b, Vector3(0.1, 0.5, 2.0), Vector3(sx * 1.32, dkh + 0.65, 3.0), Kit.mat("f1ead8", 0.7))
	# Yolcular: iki oturan, bir ayakta
	var cols := [["e07b39", "2b3a55"], ["3f9d63", "5a4a3a"], ["d95f76", "2b3a55"]]
	for i in 3:
		var pm := _person("kadin" if i != 1 else "erkek", cols[i][0], cols[i][1])
		b.add_child(pm)
		if i < 2:
			pm.position = Vector3((-1.05 if i == 0 else 1.05), dkh + 0.4, 3.0 + (0.3 if i == 0 else -0.2))
			pm.rotation.y = -PI * 0.5 * (-1.0 if i == 0 else 1.0) + PI
			pm.set("seated", true)
		else:
			pm.position = Vector3(0.0, dkh, 2.6)
			pm.rotation.y = PI
		pax.append(pm)
	# Korkuluk: kenar boyunca direkler ve iki hat
	var zs := []
	var zz := -3.8
	while zz < 4.4:
		zs.append(zz)
		zz += 0.75
	for sx in [-1.0, 1.0]:
		var prev := Vector3.ZERO
		var has := false
		for z in zs:
			if z > -1.7 and z < 1.6:
				has = false
				continue        # kabin
			var w := _hw(z) * 0.93
			var y := _deck_h(z)
			var top := Vector3(sx * w, y + 0.85, z)
			Kit.cyl(b, 0.025, 0.025, 0.85, Vector3(sx * w, y + 0.42, z), chrome, 6)
			if has:
				_rail(b, prev, top, chrome)
				_rail(b, prev - Vector3(0, 0.4, 0), top - Vector3(0, 0.4, 0), chrome)
			prev = top
			has = true
	# Pruva halati
	# Direk, bayrak ve fener
	var mast_z := -0.1
	Kit.cyl(b, 0.04, 0.05, 1.6, Vector3(0, dkh + 3.1, mast_z), chrome, 8)
	Kit.ball(b, 0.09, Vector3(0, dkh + 3.95, mast_z), Kit.glow("ffe9b0", 1.5), Vector3.ONE, 8)
	Kit.box(b, Vector3(0.5, 0.06, 0.06), Vector3(0, dkh + 3.5, mast_z), chrome)
	var radar := Kit.pivot(b, Vector3(0, dkh + 3.7, mast_z))
	Kit.box(radar, Vector3(0.7, 0.05, 0.14), Vector3.ZERO, white)
	flag = Kit.pivot(b, Vector3(0, dkh + 1.6, HALF_LEN - 0.35))
	Kit.cyl(flag, 0.025, 0.025, 1.4, Vector3(0, 0.2, 0), chrome, 6)
	Kit.box(flag, Vector3(0.02, 0.35, 0.55), Vector3(0, 0.78, 0.3), Kit.mat("d9423a", 0.9))
	Kit.ball(flag, 0.12, Vector3(0, 0.78, 0.3), Kit.mat("f6f8fa", 0.9), Vector3(0.1, 1.0, 1.0), 8)
	# Yan ve kic isiklari
	Kit.ball(b, 0.07, Vector3(-_hw(-2.5) * 0.9, _deck_h(-2.5) + 0.3, -2.5), Kit.glow("ff3030", 1.5), Vector3.ONE, 8)
	Kit.ball(b, 0.07, Vector3(_hw(-2.5) * 0.9, _deck_h(-2.5) + 0.3, -2.5), Kit.glow("30ff60", 1.5), Vector3.ONE, 8)
	# Kopuk ve sicrama parcaciklari
	wake = _foam(Vector3(0, 0.05, HALF_LEN - 0.4), 110, 4.0, false)
	b.add_child(wake)
	spray = _foam(Vector3(0, 0.45, -HALF_LEN + 0.6), 36, 0.9, true)
	b.add_child(spray)
	return b


func _rail(parent: Node3D, a: Vector3, b: Vector3, mat: Material) -> void:
	var mid := (a + b) * 0.5
	var len := a.distance_to(b)
	var mi := Kit.box(parent, Vector3(0.03, 0.03, len), mid, mat)
	mi.look_at_from_position(mid, b, Vector3.UP)


func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, e: Array) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, e)


func _foam(pos: Vector3, amount: int, life: float, spray_mode: bool) -> CPUParticles3D:
	if _foam_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.9))
		g.set_color(1, Color(1, 1, 1, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_foam_tex = gt
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = spray_mode
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.9 if not spray_mode else 0.3, 0.02, 0.3)
	p.direction = Vector3(0, 1, 0) if spray_mode else Vector3(0, 0.02, 1)
	p.spread = 25.0 if spray_mode else 60.0
	p.initial_velocity_min = 1.2 if spray_mode else 0.2
	p.initial_velocity_max = 2.4 if spray_mode else 0.9
	p.gravity = Vector3(0, -6.0, 0) if spray_mode else Vector3.ZERO
	p.scale_amount_min = 0.16 if spray_mode else 0.9
	p.scale_amount_max = 0.3 if spray_mode else 1.7
	var cg := Gradient.new()
	cg.set_color(0, Color(1, 1, 1, 0.85))
	cg.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = cg
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = _foam_tex
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.vertex_color_use_as_albedo = true
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mt
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


# ---------------------------------------------------------------- pedalli botlar

func _build_pedalos() -> void:
	var yaw := atan2(-d.x, -d.y)
	var side := signf((dock_pos - p0).dot(n))
	var cols := ["f2c230", "e5432d", "3f9ad6"]
	for k in 3:
		var pos := p0 + d * (4.0 + 3.0 * k) - n * side * 2.7
		var tries := 0
		while ParkMap.water_sd(pos) > -2.0 and tries < 12:
			pos += d * 1.0
			tries += 1
		var pn := _build_pedalo(cols[k])
		pn.position = Vector3(pos.x, wy, pos.y)
		pn.rotation.y = yaw
		root.add_child(pn)
		pedalos.append({"node": pn, "home": pos, "yaw": yaw, "pedal": pn.get_node("Pedal")})


func _build_pedalo(col: String) -> Node3D:
	var p := Node3D.new()
	p.name = "PedalliBot"
	var body := Kit.mat(col, 0.4)
	var white := Kit.mat("f6f8fa", 0.4)
	for sx in [-1.0, 1.0]:
		var c := Kit.capsule(p, 0.34, 2.7, Vector3(sx * 0.62, 0.12, 0), body, Vector3(PI * 0.5, 0, 0))
		c.scale = Vector3(1.0, 1.0, 1.0)
	Kit.box(p, Vector3(1.9, 0.08, 1.9), Vector3(0, 0.46, 0.15), white)
	for sx in [-1.0, 1.0]:
		Kit.box(p, Vector3(0.5, 0.1, 0.5), Vector3(sx * 0.4, 0.72, 0.5), Kit.mat("2b3a55", 0.7))
		Kit.box(p, Vector3(0.5, 0.45, 0.08), Vector3(sx * 0.4, 0.98, 0.76), Kit.mat("2b3a55", 0.7))
	Kit.cyl(p, 0.03, 0.03, 0.8, Vector3(0, 0.9, -0.5), Kit.mat("c9d0d6", 0.3), 8)
	Kit.box(p, Vector3(0.7, 0.04, 0.04), Vector3(0, 1.3, -0.5), Kit.mat("c9d0d6", 0.3))
	var pedal := Kit.pivot(p, Vector3(0, 0.55, 1.15))
	for k in 4:
		Kit.box(pedal, Vector3(1.0, 0.04, 0.22), Vector3.ZERO, Kit.mat("d9423a", 0.6), Vector3(0, 0, k * PI * 0.25))
	pedal.name = "Pedal"
	# Tepe tenteli (kucuk)
	Kit.box(p, Vector3(1.9, 0.04, 1.5), Vector3(0, 1.75, 0.25), Kit.mat(col, 0.7))
	for sx in [-1.0, 1.0]:
		Kit.cyl(p, 0.03, 0.03, 1.3, Vector3(sx * 0.9, 1.1, 0.8), Kit.mat("c9d0d6", 0.3), 6)
		Kit.cyl(p, 0.03, 0.03, 1.3, Vector3(sx * 0.9, 1.1, -0.3), Kit.mat("c9d0d6", 0.3), 6)
	return p


# ---------------------------------------------------------------- yasam: martilar ve ordekler

func _build_wildlife() -> void:
	for i in 9:
		var g := Node3D.new()
		var wh := Kit.mat("f6f8fa", 0.8)
		Kit.ball(g, 0.14, Vector3.ZERO, wh, Vector3(1.0, 0.8, 2.2), 8)
		Kit.ball(g, 0.07, Vector3(0, 0.05, -0.32), wh, Vector3.ONE, 6)
		Kit.box(g, Vector3(0.02, 0.02, 0.1), Vector3(0, 0.04, -0.42), Kit.mat("f2a22d", 0.6))
		var wings: Array = []
		for sx in [-1.0, 1.0]:
			var pv := Kit.pivot(g, Vector3(sx * 0.08, 0.04, 0))
			Kit.box(pv, Vector3(0.6, 0.015, 0.22), Vector3(sx * 0.3, 0, 0), Kit.mat("e9edf0", 0.8))
			Kit.box(pv, Vector3(0.22, 0.016, 0.16), Vector3(sx * 0.66, 0, 0.0), Kit.mat("40454d", 0.8))
			wings.append(pv)
		m.world.add_child(g)
		birds.append({"n": g, "wings": wings, "a": randf() * TAU, "r": randf_range(18.0, 55.0), "h": randf_range(7.0, 14.0),
			"w": randf_range(0.18, 0.34) * (1.0 if i % 2 == 0 else -1.0), "ph": randf() * TAU, "o": center})
	for i in 6:
		var dk := Node3D.new()
		var br := Kit.mat("7a5a3a" if i % 3 else "e8e2d0", 0.9)
		Kit.ball(dk, 0.16, Vector3(0, 0.1, 0), br, Vector3(1.0, 0.8, 1.5), 8)
		Kit.ball(dk, 0.09, Vector3(0, 0.27, -0.2), Kit.mat("2f7d4f", 0.7), Vector3.ONE, 8)
		Kit.box(dk, Vector3(0.05, 0.02, 0.08), Vector3(0, 0.25, -0.32), Kit.mat("f2a22d", 0.6))
		Kit.box(dk, Vector3(0.08, 0.06, 0.1), Vector3(0, 0.17, 0.26), br, Vector3(0.5, 0, 0))
		var pos := center
		var tries := 0
		while tries < 40:
			var c := center + Vector2.from_angle(randf() * TAU) * randf_range(5.0, 50.0)
			if ParkMap.water_sd(c) < -6.0:
				pos = c
				break
			tries += 1
		dk.position = Vector3(pos.x, wy, pos.y)
		m.world.add_child(dk)
		ducks.append({"n": dk, "to": pos, "ph": randf() * TAU, "yaw": randf() * TAU})


func _update_wildlife(dt: float) -> void:
	var o: Vector2 = m._owner_pos()
	if o.distance_to(center) > 260.0 and mode == "":
		return
	var focus := center
	if boat != null and mode == "tour":
		focus = Vector2(boat.position.x, boat.position.z)
	for b in birds:
		var nd: Node3D = b["n"]
		b["o"] = (b["o"] as Vector2).lerp(focus, minf(1.0, dt * 0.5))
		b["a"] += b["w"] * dt
		var o2: Vector2 = b["o"]
		var pos: Vector2 = o2 + Vector2.from_angle(float(b["a"])) * float(b["r"])
		var y: float = wy + b["h"] + sin(_t * 0.6 + b["ph"]) * 1.2
		nd.position = Vector3(pos.x, y, pos.y)
		var tang: Vector2 = Vector2(-sin(float(b["a"])), cos(float(b["a"]))) * signf(float(b["w"]))
		nd.rotation.y = atan2(-tang.x, -tang.y)
		nd.rotation.z = -signf(float(b["w"])) * 0.35
		var fl: float = sin(_t * 7.0 + b["ph"]) * 0.45
		(b["wings"][0] as Node3D).rotation.z = fl
		(b["wings"][1] as Node3D).rotation.z = -fl
	for dk in ducks:
		var nd: Node3D = dk["n"]
		var p := Vector2(nd.position.x, nd.position.z)
		var to: Vector2 = dk["to"]
		if p.distance_to(to) < 1.0:
			for tries in 12:
				var c := p + Vector2.from_angle(randf() * TAU) * randf_range(6.0, 18.0)
				if ParkMap.water_sd(c) < -5.0:
					dk["to"] = c
					break
			continue
		var dir := (to - p).normalized()
		var np := p + dir * 0.55 * dt
		dk["yaw"] = lerp_angle(dk["yaw"], atan2(-dir.x, -dir.y), minf(1.0, dt * 2.0))
		nd.position = Vector3(np.x, wy + sin(_t * 2.0 + dk["ph"]) * 0.02, np.y)
		nd.rotation.y = dk["yaw"]
	_bird_t -= dt
	if _bird_t <= 0.0 and mode != "" and _gull_p != null and state.d["sound"]:
		_bird_t = randf_range(5.0, 11.0)
		_gull_p.pitch_scale = randf_range(0.85, 1.2)
		_gull_p.play()


# ---------------------------------------------------------------- ses

func _setup_audio() -> void:
	_motor_p = _loop_player(_make_loop("motor"), -80.0)
	_wash_p = _loop_player(_make_loop("wash"), -80.0)
	_gull_p = AudioStreamPlayer.new()
	_gull_p.stream = _make_wav(_gull_samples(), false)
	_gull_p.volume_db = -14.0
	add_child(_gull_p)
	_horn_p = AudioStreamPlayer.new()
	_horn_p.stream = _make_wav(_horn_samples(), false)
	_horn_p.volume_db = -9.0
	add_child(_horn_p)


func _loop_player(w: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = w
	p.volume_db = db
	add_child(p)
	return p


func _make_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


func _make_loop(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var cnt := rate * 2
	var buf := PackedFloat32Array()
	buf.resize(cnt)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 if kind == "motor" else 91
	var lp := 0.0
	var lp2 := 0.0
	for i in cnt:
		var t := float(i) / rate
		var v := 0.0
		if kind == "motor":
			v = 0.5 * sin(TAU * 46.0 * t) + 0.3 * sin(TAU * 92.0 * t + 0.6) + 0.18 * sin(TAU * 138.0 * t + 1.1) + 0.1 * sin(TAU * 230.0 * t)
			v *= 0.75 + 0.25 * sin(TAU * 11.0 * t)
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.18)
			v += lp * 0.18
			v *= 0.6
		else:
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
			lp2 = lerpf(lp2, lp, 0.5)
			v = lp2 * 1.6 * (0.7 + 0.3 * sin(TAU * 1.0 * t))
		var edge := minf(1.0, minf(float(i), float(cnt - i)) / 110.0)
		buf[i] = v * edge
	return _make_wav(buf, true)


func _gull_samples() -> PackedFloat32Array:
	var rate := 22050
	var cnt := int(rate * 0.55)
	var buf := PackedFloat32Array()
	buf.resize(cnt)
	var ph := 0.0
	for i in cnt:
		var t := float(i) / cnt
		var f := 1500.0 + 900.0 * sin(t * PI) + 60.0 * sin(t * 60.0)
		ph += TAU * f / rate
		var env := sin(t * PI) * (0.6 + 0.4 * sin(t * 24.0))
		buf[i] = (sin(ph) + 0.4 * sin(ph * 2.0)) * 0.35 * env
	return buf


func _horn_samples() -> PackedFloat32Array:
	var rate := 22050
	var cnt := int(rate * 1.3)
	var buf := PackedFloat32Array()
	buf.resize(cnt)
	for i in cnt:
		var t := float(i) / rate
		var env := minf(1.0, t * 12.0) * clampf((1.3 - t) * 4.0, 0.0, 1.0)
		var v := 0.0
		for h in 5:
			v += sin(TAU * 174.0 * (h + 1) * t) / (h + 1.0) + sin(TAU * 220.0 * (h + 1) * t) / (h + 1.0)
		buf[i] = v * 0.22 * env
	return buf


func _audio_update(dt: float, speed: float, want: bool) -> void:
	if _motor_p == null:
		return
	var on: bool = want and state.d["sound"]
	var base := clampf(speed / 6.0, 0.0, 1.0)
	var vm := -80.0 if not on else lerpf(-27.0, -13.0, base)
	var vw := -80.0 if not on else lerpf(-60.0, -15.0, base)
	_motor_p.volume_db = lerpf(_motor_p.volume_db, vm, minf(1.0, dt * 3.0))
	_wash_p.volume_db = lerpf(_wash_p.volume_db, vw, minf(1.0, dt * 3.0))
	_motor_p.pitch_scale = 0.8 + base * 0.5
	for p in [_motor_p, _wash_p]:
		if on and not p.playing:
			p.play()
		elif not on and p.volume_db < -70.0 and p.playing:
			p.stop()


# ---------------------------------------------------------------- yol

func _chaikin(pts: Array, it: int) -> Array:
	for _k in it:
		var out: Array = [pts[0]]
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			out.append(a.lerp(b, 0.25))
			out.append(a.lerp(b, 0.75))
		out.append(pts[pts.size() - 1])
		pts = out
	return pts


func _set_path(pts: Array) -> void:
	var sm := _chaikin(pts, 3)
	# 1.5 m araliklarla yeniden ornekle
	_path = [sm[0]]
	var acc := 0.0
	for i in range(1, sm.size()):
		var a: Vector2 = sm[i - 1]
		var b: Vector2 = sm[i]
		var seg := a.distance_to(b)
		var rest := 1.5 - acc
		var pos := 0.0
		while seg - pos >= rest:
			pos += rest
			_path.append(a.lerp(b, pos / seg))
			rest = 1.5
			acc = 0.0
		acc += seg - pos
	_path.append(sm[sm.size() - 1])
	_cum = PackedFloat32Array()
	_cum.resize(_path.size())
	var s := 0.0
	for i in _path.size():
		if i > 0:
			s += (_path[i] as Vector2).distance_to(_path[i - 1])
		_cum[i] = s
	_len = s
	_s = 0.0


func _sample(s: float) -> Vector2:
	if _path.is_empty():
		return Vector2.ZERO
	s = clampf(s, 0.0, _len)
	var lo := 0
	var hi := _cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := _cum[hi] - _cum[lo]
	var f := 0.0 if seg < 0.0001 else (s - _cum[lo]) / seg
	return (_path[lo] as Vector2).lerp(_path[hi], f)


func _ring_path_from(from: Vector2, out_to_dock: bool, dock: Vector2, dock_in: float) -> Array:
	# from -> en yakin halka noktasi -> kisa yonden i0'a -> iskele onune
	var j := 0
	var bd := 1e9
	for i in RING_STEPS:
		var dd := from.distance_to(ring[i])
		if dd < bd:
			bd = dd
			j = i
	var fwd := posmod(j - i0, RING_STEPS)        # j'den i0'a artan yonde adim
	var up := posmod(i0 - j, RING_STEPS)
	var pts: Array = [from]
	var step := 1 if up <= fwd else -1
	var k := j
	var cnt := mini(up, fwd)
	for _i in cnt + 1:
		pts.append(ring[k])
		k = posmod(k + step, RING_STEPS)
	pts.append(dock + d * dock_in)
	pts.append(dock)
	return pts


func _tour_path() -> Array:
	var pts: Array = [dock_pos, dock_pos + d * 5.0]
	# Saat yonunun tersi (kiyi sagda): aci azalir
	for k in range(3, RING_STEPS + 3):
		pts.append(ring[posmod(i0 - k, RING_STEPS)])
	for k in [2, 1]:
		pts.append(ring[posmod(i0 + k, RING_STEPS)])
	pts.append(dock_pos + d * 5.0)
	pts.append(dock_pos)
	return pts


# ---------------------------------------------------------------- baslat / bitir

func context() -> Array:
	if not built:
		return []
	if mode == "tour":
		if phase == "docked":
			return ["Tekneden İn", "boat_off", "come"]
		return []
	if mode == "pedal":
		var pp := Vector2(_pedalo["node"].position.x, _pedalo["node"].position.z)
		if phase == "docked":
			return ["Pedallı Botdan İn", "boat_off", "come"]
		if phase == "free" and pp.distance_to(dock_pos) < 22.0:
			return ["Pedallı Botu İskeleye Bırak", "boat_return", "come"]
		return []
	if m._ride != null or m._taxi != null or m._bus_ride != null or ParkMap.home != null:
		return []
	var o: Vector2 = m._owner_pos()
	if o.distance_to(booth_front) < 2.8 or o.distance_to(p0) < 2.2:
		return ["Göl İskelesi · Tur %d ₺ / Pedallı %d ₺" % [TOUR_PRICE, PEDAL_PRICE], "boat_menu", "coin"]
	return []


func command(cmd: String) -> void:
	match cmd:
		"boat_menu":
			open_menu()
		"boat_tour":
			m.ui.close_modal()
			start_tour(true)
		"boat_pedal":
			m.ui.close_modal()
			start_pedal(true)
		"boat_off":
			disembark()
		"boat_return":
			if mode == "pedal" and phase == "free":
				_begin_pedal_return(false)
		"boat_app":
			phone_app()


func open_menu() -> void:
	var body: VBoxContainer = m.ui._open_panel("GÖL İSKELESİ", "Altınpark · Bilet kulübesi")
	m.ui._panel_item(body, "Göl Turu · %d ₺ · yaklaşık 90 sn" % TOUR_PRICE, func(): command("boat_tour"))
	m.ui._panel_item(body, "Pedallı Bot · %d ₺ / 5 dk" % PEDAL_PRICE, func(): command("boat_pedal"))
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func phone_app() -> void:
	if not built:
		m.ui.toast("Bu bölgede gölde tekne turu yok.")
		return
	var body: VBoxContainer = m.ui._open_panel("GÖL İSKELESİ", "Tur %d ₺ · Pedallı Bot %d ₺ / 5 dk" % [TOUR_PRICE, PEDAL_PRICE])
	var dist := int(m._owner_pos().distance_to(booth_front))
	m.ui._panel_item(body, "İskeleye Git · %d m" % dist, func():
		m.ui.close_modal()
		m._set_nav(booth_front, "Göl İskelesi"))
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _board_common() -> void:
	m._moving = false
	m._queue.clear()
	m._steering = false
	m._target = m._owner_pos()
	m.owner_model.speed = 0.0
	_save_zoom = m._zoom
	m._cam_blend = 0.6
	var act: Node3D = m._active()
	for k in m.agents:
		var a: Node3D = m.agents[k]
		a.set_process(false)
		a.visible = a == act
	if act != null:
		act.model.pose = "sit"
		act.model.speed = 0.0


func start_tour(pay: bool) -> void:
	if not built or mode != "":
		return
	if pay and not state.spend(TOUR_PRICE):
		return
	_board_common()
	mode = "tour"
	phase = "turn"
	_turn_t = 0.0
	_speak_i = 0
	_speak_t = 0.0
	# Tekne iskeleye pruva icerde durmus olabilir: dondurerek hazirla
	_set_path(_tour_path())
	_cruise = clampf(_len / 80.0, 2.4, 8.0)
	m._zoom = 1.45
	m.owner_model.riding = ""
	m.ui.toast("Göl Turu başladı · %d ₺" % TOUR_PRICE)
	if _horn_p != null and state.d["sound"]:
		_horn_p.play()
	m._say(captain, "Demir alıyoruz! Hazır mısınız?")
	_place_tour_riders()
	m._update_context()


func _place_tour_riders() -> void:
	var dh := _deck_h(-3.2)
	var tr: Transform3D = boat.global_transform
	var p: Vector3 = tr * Vector3(-0.45, dh, -3.2)
	m.owner_node.position = p
	m.owner_node.rotation.y = boat.rotation.y
	var act: Node3D = m._active()
	if act != null:
		act.position = tr * Vector3(0.5, dh, -3.1)
		act.rotation.y = boat.rotation.y


func start_pedal(pay: bool) -> void:
	if not built or mode != "":
		return
	if pay and not state.spend(PEDAL_PRICE):
		return
	_board_common()
	mode = "pedal"
	phase = "free"
	_pedalo = pedalos[0]
	var pn: Node3D = _pedalo["node"]
	pn.rotation.y = dock_yaw_out
	pn.position = Vector3(_pedalo["home"].x, wy, _pedalo["home"].y)
	_yaw = dock_yaw_out
	_pspeed = 0.0
	_pedal_left = PEDAL_TIME
	m._zoom = 1.0
	m.owner_model.riding = "bisiklet"
	m.owner_model.grips = []
	m.ui.toast("Pedallı Bot · %d ₺ · 5 dk. Yönlendirmek için hareket tuşları." % PEDAL_PRICE)
	_place_pedal_riders()
	m._update_context()


func _place_pedal_riders() -> void:
	var pn: Node3D = _pedalo["node"]
	var tr: Transform3D = pn.global_transform
	m.owner_node.position = tr * Vector3(-0.4, 0.46, 0.45)
	m.owner_node.rotation.y = pn.rotation.y
	var act: Node3D = m._active()
	if act != null:
		act.position = tr * Vector3(0.4, 0.5, 0.45)
		act.rotation.y = pn.rotation.y


func _begin_pedal_return(timeup: bool) -> void:
	phase = "return"
	var pn: Node3D = _pedalo["node"]
	_set_path(_ring_path_from(Vector2(pn.position.x, pn.position.z), true, _pedalo["home"], 3.0))
	_cruise = 2.8
	if timeup:
		m.ui.toast("Süre doldu! Pedallı bot seni iskeleye götürüyor.")
	else:
		m.ui.toast("İskeleye dönüyoruz…")


func disembark() -> void:
	if mode == "tour" and phase != "docked":
		return
	if mode == "pedal" and phase != "docked":
		return
	var was := mode
	mode = ""
	phase = ""
	var out := exit_pos
	for cand in [exit_pos, exit_pos - d * 1.2, exit_pos + n * 1.6, exit_pos - n * 1.6, booth_front]:
		if m.world.is_free(cand, 0.4):
			out = cand
			break
	m.owner_node.position = Vector3(out.x, ParkMap.walk_height(out), out.y)
	m.owner_node.rotation.y = atan2(d.x, d.y) + PI
	m.owner_model.riding = ""
	m.owner_model.speed = 0.0
	m._target = out
	m._moving = false
	m._queue.clear()
	m._zoom = _save_zoom
	m._cam_blend = 0.6
	m._unboard_pets(out)
	if was == "pedal":
		_pedalo["node"].rotation.y = dock_yaw_out
		_pedalo = {}
	m._update_context()


func _finish(kind: String) -> void:
	phase = "docked"
	state.count("boat", 1.0)
	if kind == "tour":
		m._say(captain, "Tur bitti. İyi günler, yine bekleriz!")
		m.ui.toast("İskeleye vardık · inmek için F")
	else:
		m.ui.toast("Pedallı bot iskelede · inmek için F")
	m._update_context()


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	if not built:
		return
	_t += dt
	_update_wildlife(dt)
	# Kulube lambasi gece
	if root != null:
		var bn: Node = root.get_node_or_null("BiletKulubesi")
		if bn != null and bn.has_meta("lamp"):
			var lamp: OmniLight3D = bn.get_meta("lamp")
			lamp.light_energy = 1.4 * m.night
	_bob_all(dt)
	match mode:
		"tour":
			_update_tour(dt)
		"pedal":
			_update_pedal(dt)
		_:
			_audio_update(dt, 0.0, false)
			wake.emitting = false
			spray.emitting = false


func _bob_all(dt: float) -> void:
	# Bosta duran tekne ve pedalli botlar hafif sallanir
	for i in pedalos.size():
		var pe: Dictionary = pedalos[i]
		if mode == "pedal" and pe == _pedalo:
			continue
		var nd: Node3D = pe["node"]
		nd.position.y = wy + sin(_t * 1.4 + i * 1.7) * 0.03
		nd.rotation.z = sin(_t * 1.1 + i) * 0.03
	if mode != "tour":
		boat.position.y = wy + sin(_t * 1.2) * 0.04
		boat.rotation.z = sin(_t * 0.9) * 0.02
	flag.rotation.y = sin(_t * 3.0) * 0.25


func _update_tour(dt: float) -> void:
	var bp := Vector2(boat.position.x, boat.position.z)
	match phase:
		"turn":
			# Iskelede pruvayi disari cevir
			_turn_t += dt
			var target := dock_yaw_out
			_yaw = lerp_angle(_yaw, target, minf(1.0, dt * 1.6))
			boat.rotation.y = _yaw
			if _turn_t > 2.4 or absf(angle_difference(_yaw, target)) < 0.05 and _turn_t > 1.0:
				phase = "sail"
				_s = 0.0
			_speed_now = 0.0
		"sail":
			var rem := _len - _s
			var ease_k := minf(1.0, minf(_s / 14.0 + 0.12, rem / 16.0 + 0.12))
			_speed_now = _cruise * ease_k
			_s = minf(_s + _speed_now * dt, _len)
			var np := _sample(_s)
			var ahead := _sample(_s + 4.0)
			var dirv := ahead - np
			if dirv.length() > 0.05:
				var want := atan2(-dirv.x, -dirv.y)
				var old := _yaw
				_yaw = lerp_angle(_yaw, want, minf(1.0, dt * 2.6))
				_roll = lerpf(_roll, clampf(angle_difference(old, _yaw) / maxf(dt, 0.001) * 0.07 * _speed_now / 5.0, -0.12, 0.12), minf(1.0, dt * 3.0))
			bp = np
			boat.position = Vector3(bp.x, wy, bp.y)
			boat.rotation.y = _yaw
			_announce(dt)
			if _len - _s < 0.4:
				_finish("tour")
		"docked":
			_speed_now = 0.0
			_roll = lerpf(_roll, 0.0, minf(1.0, dt * 2.0))
	# Yalpa: hafif yatma, kafa vurma, yukselme
	if phase != "turn":
		boat.position.y = wy + 0.05 + sin(_t * 1.5) * 0.035 + 0.04 * sin(_t * 0.7)
		boat.rotation.z = _roll + sin(_t * 0.9) * 0.02
		boat.rotation.x = sin(_t * 1.1 + 1.0) * 0.012 - clampf(_speed_now * 0.004, 0.0, 0.03)
	else:
		boat.rotation.z = 0.0
	wheel.rotation.z = lerpf(wheel.rotation.z, -_roll * 12.0, minf(1.0, dt * 4.0))
	wake.emitting = _speed_now > 1.0
	spray.emitting = _speed_now > 2.5
	_place_tour_riders()
	_audio_update(dt, _speed_now, true)
	_cam(dt, true)


var _speed_now := 0.0


func _announce(dt: float) -> void:
	_speak_t -= dt
	if _speak_i >= SPEECH.size() or _speak_t > 0.0:
		return
	if _s / _len >= float(SPEECH[_speak_i][0]):
		m._say(captain, SPEECH[_speak_i][1])
		_speak_t = 3.2
		_speak_i += 1
		if _speak_i % 2 == 1 and not pax.is_empty():
			m._say(pax[randi() % pax.size()], PAX_LINES[randi() % PAX_LINES.size()])


func _cam(dt: float, cinematic: bool) -> void:
	if m._looking():
		return
	if cinematic:
		# Yavasca salinan, yanlardan ve onden gosteren sinema kamerasi
		var swing := 1.45 * sin(_t * 0.17) + 0.5 * sin(_t * 0.41 + 1.0)
		m._cam_yaw = lerp_angle(m._cam_yaw, _yaw + swing, minf(1.0, dt * 1.2))
		m._cam_pitch = lerpf(m._cam_pitch, 0.32 + 0.1 * sin(_t * 0.23), minf(1.0, dt * 1.0))
	else:
		if absf(_pspeed) > 0.3:
			m._cam_yaw = lerp_angle(m._cam_yaw, _yaw, minf(1.0, dt * 1.4))


func _update_pedal(dt: float) -> void:
	var pn: Node3D = _pedalo["node"]
	var p := Vector2(pn.position.x, pn.position.z)
	if phase == "free":
		var thr: float = -m.ui.stick.y
		var steer: float = m.ui.stick.x
		var top := 3.4
		var want := 0.0
		if thr > 0.1:
			want = top * minf(thr * 1.2, 1.0)
		elif thr < -0.1:
			want = thr * 1.4
		_pspeed = move_toward(_pspeed, want, dt * (1.5 if absf(want) > 0.1 else 1.1))
		var rate := steer * (0.5 + 0.55 * clampf(absf(_pspeed) / top, 0.0, 1.0)) * (1.0 if _pspeed >= -0.1 else -1.0)
		_yaw -= rate * dt
		var fwd := Vector2(-sin(_yaw), -cos(_yaw))
		var np := p + fwd * _pspeed * dt
		var cur := ParkMap.water_sd(p)
		var nsd := ParkMap.water_sd(np)
		if nsd < -1.7 or nsd < cur:
			p = np
		else:
			_pspeed *= maxf(0.0, 1.0 - 5.0 * dt)
		_pedal_left -= dt
		if _pedal_left < 0.0:
			_begin_pedal_return(true)
		elif absf(_pedal_left - 60.0) < dt:
			m.ui.toast("1 dakikan kaldı.")
		_audio_update(dt, 0.0, false)
	elif phase == "return":
		var rem := _len - _s
		_pspeed = _cruise * minf(1.0, rem / 6.0 + 0.2)
		_s = minf(_s + _pspeed * dt, _len)
		var np := _sample(_s)
		var ahead := _sample(_s + 2.5)
		var dv := ahead - np
		if dv.length() > 0.05:
			_yaw = lerp_angle(_yaw, atan2(-dv.x, -dv.y), minf(1.0, dt * 3.0))
		p = np
		if _len - _s < 0.3:
			_pspeed = 0.0
			_finish("pedal")
		_audio_update(dt, 0.0, false)
	else:
		_pspeed = 0.0
	pn.position = Vector3(p.x, wy + 0.02 + sin(_t * 2.0) * 0.03, p.y)
	pn.rotation.y = _yaw
	pn.rotation.z = sin(_t * 1.3) * 0.03 - m.ui.stick.x * 0.04 * absf(_pspeed) / 3.0
	pn.rotation.x = sin(_t * 1.7) * 0.015
	(_pedalo["pedal"] as Node3D).rotation.x += _pspeed * dt * 2.2
	m.owner_model.ride_speed = absf(_pspeed) * 0.9
	_place_pedal_riders()
	_cam(dt, false)


# ---------------------------------------------------------------- test

func debug_board(kind: String, secs: float) -> void:
	if not built:
		print("GOL YOK")
		return
	state.d["coins"] = maxi(int(state.d["coins"]), 500)
	m._place_owner(exit_pos)
	await get_tree().process_frame
	if kind == "pedal":
		start_pedal(true)
		var pn: Node3D = _pedalo["node"]
		var p := Vector2(pn.position.x, pn.position.z) + d * 14.0
		pn.position = Vector3(p.x, wy, p.y)
		_yaw = dock_yaw_out
		return
	start_tour(true)
	phase = "sail"
	_s = clampf(_cruise * secs, 0.0, _len - 5.0)
	var np := _sample(_s)
	var ahead := _sample(_s + 4.0)
	_yaw = atan2(-(ahead - np).x, -(ahead - np).y)
	boat.position = Vector3(np.x, wy, np.y)
	boat.rotation.y = _yaw
	m._cam_yaw = _yaw + 0.9
	print("BOAT tur_uzunluk=%.0f hiz=%.1f pier=%s dock=%s" % [_len, _cruise, p0, dock_pos])
