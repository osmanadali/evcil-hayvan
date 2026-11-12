extends SceneTree
## Harita uygulamasi gorselini uretir: godot --headless --path . -s tools/bake_map.gd

const ParkMap = preload("res://scripts/park_map.gd")


func _box(p: Vector2, c: Vector2, half: Vector2) -> float:
	return ParkMap.rect_sd(p, c - half, c + half)


func _init() -> void:
	var n := 1024
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var land := Color("dcebc0")
	var forest := Color("b3d49a")
	var water := Color("9fd0ee")
	var shore := Color("6fb3dc")
	var sand := Color("f4e8bd")
	var path := Color("fbf3e1")
	var path_edge := Color("d9caa6")
	var road := Color("ffffff")
	var road_edge := Color("c2c6cc")
	var walk := Color("e9e5dc")
	var lot := Color("e6f0cf")
	var house := Color("f0b490")
	var house_edge := Color("c98a66")
	var shop := Color("f3c865")
	var outside := Color("c4d8a8")
	for j in n:
		for i in n:
			var p := Vector2((i + 0.5) / n - 0.5, (j + 0.5) / n - 0.5) * ParkMap.SPLAT_EXTENT + ParkMap.SPLAT_CENTER
			var c := land.lerp(forest, ParkMap.forest(p))
			var hill := p.distance_to(ParkMap.HILL)
			if hill < 14.0 and fmod(hill, 3.5) < 0.35:
				c = c.darkened(0.08)
			if ParkMap.lot_sd(p) < 0.0:
				c = lot if ParkMap.lot_sd(p) < -0.5 else lot.darkened(0.15)
			if p.distance_to(ParkMap.BEACH) < ParkMap.BEACH_R or ParkMap.rect_sd(p, ParkMap.PLAY_MIN, ParkMap.PLAY_MAX) < 0.0:
				c = sand
			if p.distance_to(ParkMap.GARDEN) < 7.5 or p.distance_to(ParkMap.MEADOW) < 8.5:
				c = Color("f2d9e6") if p.distance_to(ParkMap.GARDEN) < 7.5 else Color("eee6a8")
			var ob := _box(p, ParkMap.ORCHARD, Vector2(17, 13.5))
			if ob < 0.0:
				c = Color("cfe6a8")
				var g := Vector2(fposmod(p.x - ParkMap.ORCHARD.x + 3.1, 6.2) - 3.1, fposmod(p.y - ParkMap.ORCHARD.y, 6.2) - 3.1)
				if g.length() < 1.5:
					c = Color("8fc06a")
			var ps := ParkMap.path_sd(p)
			if ps < 0.35:
				c = path if ps < -0.05 else path_edge
			var pv := ParkMap.paved_sd(p)
			if pv < 0.3:
				c = walk if pv < 0.0 else road_edge
			var rd := ParkMap.road_dist(p) - ParkMap.ROAD_HALF
			if rd < 0.0:
				c = road
			var w := ParkMap.water_sd(p)
			if w < 0.5:
				c = water if w < -0.6 else shore
			if ParkMap.deck_y(p) > -100.0:
				c = Color("c9a57a")
			# Binalar
			var b := _box(p, ParkMap.HOUSE, Vector2(4.7, 3.9))
			var col := house
			for l in ParkMap.LOTS:
				var lc: Vector2 = l[0]
				b = minf(b, _box(p, lc + Vector2(0, -2.5 if l[1] == 0.0 else 2.5), Vector2(4.2, 3.4)))
			var sb := minf(_box(p, ParkMap.PETSHOP, Vector2(6.5, 5.0)), _box(p, ParkMap.CAFE, Vector2(5.0, 6.5)))
			sb = minf(sb, _box(p, ParkMap.KIOSK, Vector2(2.3, 1.8)))
			if sb < b:
				b = sb
				col = shop
			if b < 0.0:
				c = col if b < -0.6 else house_edge
			if p.distance_to(ParkMap.PLAZA) < 2.6:
				c = water
			var edge := ParkMap.rect_sd(p, ParkMap.BOUNDS_MIN, ParkMap.BOUNDS_MAX)
			if edge > 0.0:
				c = c.lerp(outside, clampf(edge / 6.0, 0.0, 1.0))
			img.set_pixel(i, j, c)
	img.save_png("res://assets/park_map.png")
	print("harita yazildi")
	quit()
