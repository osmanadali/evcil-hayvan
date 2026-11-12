extends SceneTree
## Zemin boyama dokusunu uretir: godot --headless --path . -s tools/bake_splat.gd
## R = yol, G = kiyiya mesafe (0.5 = kiyi, +-4 m), B = kum alani

const ParkMap = preload("res://scripts/park_map.gd")


func _init() -> void:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			var p := Vector2((i + 0.5) / n - 0.5, (j + 0.5) / n - 0.5) * ParkMap.SPLAT_EXTENT
			var r := 1.0 - smoothstep(-0.3, 0.3, ParkMap.path_sd(p))
			var g := clampf(0.5 + ParkMap.water_sd(p) * 0.125, 0.0, 1.0)
			var b := 1.0 - smoothstep(-0.8, 0.2, ParkMap.rect_sd(p, ParkMap.PLAY_MIN, ParkMap.PLAY_MAX))
			img.set_pixel(i, j, Color(r, g, b))
	img.save_png("res://assets/park_splat.png")
	print("park_splat.png yazildi")
	quit()
