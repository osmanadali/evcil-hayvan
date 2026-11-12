extends SceneTree
## Zemin boyama dokularini uretir: godot --headless --path . -s tools/bake_splat.gd
## splat_a: R = yaya yolu, G = kiyiya mesafe (0.5 = kiyi, +-4 m), B = kum
## splat_b: R = asfalt, G = tas doseme (kaldirim, meydan), B = orman zemini

const ParkMap = preload("res://scripts/park_map.gd")


func _init() -> void:
	var n := 1024
	var a := Image.create(n, n, false, Image.FORMAT_RGB8)
	var b := Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			var p := Vector2((i + 0.5) / n - 0.5, (j + 0.5) / n - 0.5) * ParkMap.SPLAT_EXTENT + ParkMap.SPLAT_CENTER
			var road := ParkMap.road_dist(p)
			var paved := 1.0 - smoothstep(-0.15, 0.15, ParkMap.paved_sd(p))
			var path := (1.0 - smoothstep(-0.3, 0.3, ParkMap.path_sd(p))) * (1.0 - paved)
			var sand := 1.0 - smoothstep(-0.8, 0.2, ParkMap.rect_sd(p, ParkMap.PLAY_MIN, ParkMap.PLAY_MAX))
			sand = maxf(sand, 1.0 - smoothstep(-3.0, 1.5, p.distance_to(ParkMap.BEACH) - ParkMap.BEACH_R))
			a.set_pixel(i, j, Color(path, clampf(0.5 + ParkMap.water_sd(p) * 0.125, 0.0, 1.0), sand))
			b.set_pixel(i, j, Color(1.0 - smoothstep(-0.12, 0.12, road - ParkMap.ROAD_HALF), paved, ParkMap.forest(p)))
	a.save_png("res://assets/splat_a.png")
	b.save_png("res://assets/splat_b.png")
	print("splat dokulari yazildi")
	quit()
