extends "res://scripts/shop_interior.gd"
## Lokanta ici: market / eczane kabugunu (shop_interior.gd) kullanir, icini lokantaya gore doser.
## Uc tarz: "kebap" (ocakbasi, pide firini), "ev" (ev yemekleri, tencereler), "fast" (burger / doner).
## Masalar ve sandalyeler, arka duvarda servis tezgahi ve mutfak, solda kasa, menu panosu (fiyatlarla),
## garson (masaya gelir, yemegi tepsiyle getirir), asci ve oturan baska musteriler.
## Mantik scripts/eateries.gd'de; burada yalnizca yapi ve yerel noktalar var.

var style := "kebap"
var menu: Array = []                 # [[kimlik, ad, fiyat, tokluk, enerji], ...] (menu panosu icin)
## Masalar: [{c: Vector2, seats: [{local, yaw, busy}], food: Node3D}]
var tables: Array = []
var waiter: Node3D
var waiter_home := Vector2(W * 0.5, 2.75)
var cook: Node3D
var cashier: Node3D
var _spit: Node3D


func _ready() -> void:
	_rng.seed = hash(title)
	_build_shell()
	_build_restaurant()


func _process(dt: float) -> void:
	if _spit:
		_spit.rotation.y += dt * 0.6


func _style_col() -> Dictionary:
	match style:
		"ev":
			return {"wall": "efe4cc", "wood": "8a5a35", "cloth": "3f7a4a", "floor": "b98a5a", "top": "e8e2d4"}
		"fast":
			return {"wall": "f6efe2", "wood": "d9302b", "cloth": "f2c230", "floor": "3a3a3e", "top": "f4f4f0"}
	return {"wall": "e9d2b4", "wood": "6b3d22", "cloth": "b8401a", "floor": "8f5a36", "top": "d8c8a8"}


func _build_restaurant() -> void:
	var c := _style_col()
	# Ahsap / karo zemin (kabugun beyaz karosunun ustune)
	var fl := Kit.mat(c["floor"], 0.55)
	if style == "fast":
		fl = Kit.mat("2e2e33", 0.35)
	Kit.box(self, Vector3(W, 0.02, D), Vector3(W * 0.5, 0.005, D * 0.5), fl)
	if style != "fast":
		var line := Kit.mat("6a4026" if style == "kebap" else "9a6a40", 0.6)
		for k in 18:
			Kit.box(self, Vector3(0.015, 0.022, D), Vector3(k * W / 18.0, 0.006, D * 0.5), line)
	else:
		var chk := Kit.mat("f4f4f0", 0.35)
		for x in 11:
			for z in 9:
				if (x + z) % 2 == 0:
					Kit.box(self, Vector3(1.0, 0.022, 1.0), Vector3(x + 0.5, 0.006, z + 0.5), chk)
	# Duvarlar: lambri + boya
	var wall := Kit.mat(c["wall"], 0.85)
	var wains := Kit.mat(c["wood"], 0.6)
	Kit.box(self, Vector3(W, H, 0.02), Vector3(W * 0.5, H * 0.5, 0.01), wall)
	for side in [0.01, W - 0.01]:
		Kit.box(self, Vector3(0.02, H, D), Vector3(side, H * 0.5, D * 0.5), wall)
		Kit.box(self, Vector3(0.04, 1.0, D), Vector3(side, 0.5, D * 0.5), wains)
	Kit.box(self, Vector3(W, 1.0, 0.04), Vector3(W * 0.5, 0.5, 0.03), wains)

	# Mutfak ve servis tezgahi (arka duvar)
	_counter(Vector2(W * 0.5, 1.9), 6.0, c["top"])
	colliders.append([Vector2(0.0, 1.6), Vector2(2.5, 1.6)])     # mutfaga girilmez
	colliders.append([Vector2(8.5, 1.6), Vector2(W, 1.6)])
	Kit.box(self, Vector3(W, 0.3, 0.04), Vector3(W * 0.5, 3.05, 1.55), Kit.mat(accent, 0.6))   # mutfak sacagi
	match style:
		"kebap":
			_build_grill()
		"ev":
			_build_pots()
		_:
			_build_doner()
	cook = _person_at(Vector2(W * 0.5 + 1.2, 1.15), PI, Color("f4f4f0"), false)

	# Kasa (sol on)
	counter_local = Vector2(1.3, 6.45)
	_counter(Vector2(1.3, 5.6), 1.8, c["top"])
	Kit.box(self, Vector3(0.36, 0.22, 0.3), Vector3(1.0, 1.16, 5.55), Kit.mat("2a2a2e", 0.4))
	Kit.box(self, Vector3(0.3, 0.18, 0.02), Vector3(1.0, 1.32, 5.72), Kit.glow("5ad1ff", 0.8))
	cashier = _person_at(Vector2(1.3, 4.95), PI, Color(accent), true)

	# Menu panosu: arka duvarin solunda, fiyatlarla
	_menu_board(Vector3(W * 0.5 - 2.2, 2.4, 1.6))
	_sign(title, Vector3(W * 0.5 + 2.4, 2.55, 1.6), accent, Color.WHITE)

	# Masalar ve sandalyeler
	var chair_m := Kit.mat(c["wood"], 0.55)
	var cloth := Kit.mat(c["cloth"], 0.7)
	var cloth2 := Kit.mat("f4f1ea", 0.7)
	for tz in [4.0, 6.5]:
		for tx in [4.0, 6.5, 9.0]:
			var tc := Vector2(tx, tz)
			var t := Node3D.new()
			t.position = Vector3(tx, 0, tz)
			add_child(t)
			Kit.box(t, Vector3(0.9, 0.05, 0.9), Vector3(0, 0.74, 0), Kit.mat(c["wood"], 0.45))
			if style != "fast":
				Kit.box(t, Vector3(0.94, 0.012, 0.94), Vector3(0, 0.772, 0), cloth2)
				Kit.box(t, Vector3(0.5, 0.014, 0.94), Vector3(0, 0.776, 0), cloth, Vector3(0, PI * 0.25, 0))
			Kit.cyl(t, 0.05, 0.05, 0.72, Vector3(0, 0.36, 0), Kit.mat("3a3a3e", 0.4), 8)
			Kit.cyl(t, 0.26, 0.26, 0.03, Vector3(0, 0.015, 0), Kit.mat("3a3a3e", 0.4), 12)
			# Masada pecete, tuzluk, kurdan
			Kit.cyl(t, 0.025, 0.025, 0.08, Vector3(0.3, 0.82, 0.32), Kit.mat("f4f4f0", 0.3), 8)
			Kit.cyl(t, 0.025, 0.025, 0.08, Vector3(0.36, 0.82, 0.26), Kit.mat("b8401a", 0.3), 8)
			_solid(tc, Vector2(0.47, 0.47))
			var seats: Array = []
			for sz in [-1.0, 1.0]:
				var sp := tc + Vector2(0, sz * 0.66)
				var ch := Node3D.new()
				ch.position = Vector3(sp.x, 0, sp.y)
				ch.rotation.y = 0.0 if sz > 0 else PI
				add_child(ch)
				Kit.box(ch, Vector3(0.44, 0.05, 0.42), Vector3(0, 0.45, 0), chair_m)
				Kit.box(ch, Vector3(0.44, 0.5, 0.05), Vector3(0, 0.72, 0.21), chair_m)
				for lx in [-0.19, 0.19]:
					for lz in [-0.18, 0.18]:
						Kit.box(ch, Vector3(0.04, 0.45, 0.04), Vector3(lx, 0.225, lz), chair_m)
				var d := tc - sp
				seats.append({"local": sp, "yaw": atan2(-d.x, -d.y), "busy": false})
			var food := Node3D.new()
			food.position = Vector3(tx, 0.0, tz)
			add_child(food)
			tables.append({"c": tc, "seats": seats, "food": food})

	# Garson: servis tezgahinin onunda bekler
	waiter = _person_at(waiter_home, PI, Color("2b2b2e") if style != "fast" else Color(accent), false)
	# Saksi bitkisi, tablolar
	for p in [Vector2(10.5, 8.4), Vector2(0.5, 8.4)]:
		Kit.cyl(self, 0.22, 0.17, 0.4, Vector3(p.x, 0.2, p.y), Kit.mat("8a4a2b", 0.8), 10)
		Kit.ball(self, 0.42, Vector3(p.x, 0.8, p.y), Kit.mat("3f7a3a", 0.9), Vector3(1, 1.2, 1), 8)
		_solid(p, Vector2(0.3, 0.3))
	for k in 3:
		var z := 3.2 + k * 2.0
		Kit.box(self, Vector3(0.04, 0.6, 0.8), Vector3(W - 0.04, 1.75, z), Kit.mat("3a2a1e", 0.6))
		Kit.box(self, Vector3(0.05, 0.5, 0.7), Vector3(W - 0.05, 1.75, z), Kit.mat(["c9962e", "3f6f78", "b8401a"][k], 0.8))
	# Sicak isik
	var o := OmniLight3D.new()
	o.position = Vector3(W * 0.5, H - 0.5, 1.2)
	o.light_color = Color("ffd9a8")
	o.omni_range = 6.0
	o.light_energy = 0.9
	add_child(o)


func _person_at(at: Vector2, face_y: float, shirt: Color, female: bool) -> Node3D:
	var v := PersonModel.new()
	v.kind = "kadin" if female else "erkek"
	v.tint = shirt
	v.position = Vector3(at.x, 0, at.y)
	v.rotation.y = face_y
	add_child(v)
	return v


func _menu_board(at: Vector3) -> void:
	Kit.box(self, Vector3(3.4, 1.5, 0.05), at, Kit.mat("1e1e22", 0.5))
	Kit.box(self, Vector3(3.5, 0.08, 0.07), at + Vector3(0, 0.78, 0), Kit.mat(accent, 0.5))
	var txt := "MENÜ\n"
	for it in menu:
		txt += "%s  ·  %d ₺\n" % [it[1], int(it[2])]
	var l := Label3D.new()
	l.text = txt.strip_edges()
	l.font_size = 48
	l.pixel_size = 0.003
	l.line_spacing = 2.0
	l.modulate = Color("fff3d6")
	l.position = at + Vector3(0, 0, 0.035)
	add_child(l)


func _build_grill() -> void:
	# Ocakbasi: uzun mangal, kor, siste kebaplar, bakir davlumbaz; yaninda tas pide firini
	Kit.box(self, Vector3(3.0, 0.9, 0.7), Vector3(4.2, 0.45, 0.6), Kit.mat("4a4a4e", 0.4))
	Kit.box(self, Vector3(2.8, 0.05, 0.55), Vector3(4.2, 0.92, 0.6), Kit.glow("ff5a1a", 2.5))
	for k in 9:
		Kit.cyl(self, 0.008, 0.008, 0.6, Vector3(3.0 + k * 0.3, 1.0, 0.6), Kit.mat("c9ccd0", 0.3), 6, Vector3(PI * 0.5, 0, 0))
		Kit.capsule(self, 0.028, 0.32, Vector3(3.0 + k * 0.3, 1.0, 0.6), Kit.mat("7a3a1e", 0.7), Vector3(PI * 0.5, 0, 0))
	Kit.box(self, Vector3(3.2, 0.5, 0.9), Vector3(4.2, 2.35, 0.5), Kit.mat("b87333", 0.25))
	var fire := OmniLight3D.new()
	fire.position = Vector3(4.2, 1.2, 0.8)
	fire.light_color = Color("ff8a3a")
	fire.omni_range = 3.0
	fire.light_energy = 1.2
	add_child(fire)
	# Pide firini: kubbe, agzinda kor
	Kit.box(self, Vector3(1.8, 1.0, 1.2), Vector3(8.4, 0.5, 0.7), Kit.mat("a8a09a", 0.9))
	Kit.ball(self, 0.95, Vector3(8.4, 1.0, 0.7), Kit.mat("c2b8ae", 0.95), Vector3(1.0, 0.75, 0.65), 12)
	Kit.box(self, Vector3(0.6, 0.35, 0.05), Vector3(8.4, 1.25, 1.3), Kit.glow("ff6a1a", 2.0))
	# Tezgahta pide ve lahmacun tepsileri
	for k in 3:
		Kit.box(self, Vector3(0.6, 0.02, 0.2), Vector3(3.5 + k * 1.6, 1.06, 1.9), Kit.mat("c9893e", 0.7))
		Kit.box(self, Vector3(0.5, 0.02, 0.12), Vector3(3.5 + k * 1.6, 1.075, 1.9), Kit.mat("8a2a1a", 0.7))


func _build_pots() -> void:
	# Ev yemekleri: benmari tezgahinda tencereler ve tepsiler
	var steel := Kit.mat("c9ccd0", 0.25)
	var dishes := ["c8622b", "e8c86a", "6b3a1e", "8a9a3a", "f2e6c8", "b8401a"]
	for k in 6:
		var x := 3.0 + k * 1.0
		Kit.box(self, Vector3(0.8, 0.06, 0.45), Vector3(x, 1.07, 1.9), steel)
		Kit.box(self, Vector3(0.72, 0.03, 0.38), Vector3(x, 1.1, 1.9), Kit.mat(dishes[k], 0.6))
	# Arkada ocak ve buyuk tencereler
	Kit.box(self, Vector3(4.0, 0.9, 0.7), Vector3(5.5, 0.45, 0.5), steel)
	for k in 3:
		Kit.cyl(self, 0.28, 0.28, 0.45, Vector3(4.2 + k * 1.3, 1.13, 0.5), steel, 16)
		Kit.cyl(self, 0.29, 0.29, 0.03, Vector3(4.2 + k * 1.3, 1.37, 0.5), Kit.mat("8a8d92", 0.3), 16)
	# Raflarda kavanozlar
	Kit.box(self, Vector3(2.2, 0.04, 0.3), Vector3(8.8, 1.8, 0.2), Kit.mat("8a5a35", 0.6))
	for k in 6:
		Kit.cyl(self, 0.08, 0.08, 0.22, Vector3(7.9 + k * 0.36, 1.93, 0.2), Kit.mat(["c8322b", "e8c86a", "3f7a3a"][k % 3], 0.3), 10)


func _build_doner() -> void:
	# Doner ocagi: dikey sis, donen et; fritoz ve isikli menu
	Kit.box(self, Vector3(0.9, 1.6, 0.4), Vector3(3.6, 0.8, 0.35), Kit.mat("c9ccd0", 0.25))
	Kit.box(self, Vector3(0.7, 1.0, 0.05), Vector3(3.6, 1.35, 0.56), Kit.glow("ff5a1a", 1.8))
	_spit = Node3D.new()
	_spit.position = Vector3(3.6, 0.0, 0.95)
	add_child(_spit)
	Kit.cyl(_spit, 0.02, 0.02, 1.5, Vector3(0, 1.4, 0), Kit.mat("c9ccd0", 0.3), 6)
	Kit.cyl(_spit, 0.17, 0.24, 0.8, Vector3(0, 1.45, 0), Kit.mat("a8682e", 0.7), 14)
	Kit.cyl(_spit, 0.25, 0.25, 0.03, Vector3(0, 1.03, 0), Kit.mat("c9ccd0", 0.3), 14)
	# Fritoz ve burger izgarasi
	Kit.box(self, Vector3(1.0, 0.9, 0.7), Vector3(6.2, 0.45, 0.5), Kit.mat("c9ccd0", 0.25))
	Kit.box(self, Vector3(0.8, 0.05, 0.5), Vector3(6.2, 0.92, 0.5), Kit.mat("c99a3a", 0.3))
	Kit.box(self, Vector3(1.4, 0.9, 0.7), Vector3(7.8, 0.45, 0.5), Kit.mat("3a3a3e", 0.3))
	for k in 4:
		Kit.cyl(self, 0.07, 0.07, 0.03, Vector3(7.4 + k * 0.27, 0.93, 0.5), Kit.mat("6b3a1e", 0.7), 10)
	# Tezgahta tepsiler ve icecek makinesi
	Kit.box(self, Vector3(0.6, 0.5, 0.4), Vector3(8.0, 1.27, 1.9), Kit.mat("d9302b", 0.4))
	for k in 3:
		Kit.box(self, Vector3(0.12, 0.08, 0.05), Vector3(7.8 + k * 0.2, 1.2, 2.12), Kit.mat("2a2a2e", 0.4))
	for k in 2:
		Kit.box(self, Vector3(0.45, 0.02, 0.32), Vector3(5.0 + k * 0.6, 1.05, 1.9), Kit.mat("d9302b", 0.5))
