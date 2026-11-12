extends Control
## Kodla cizilen simgeler (gorsel dosyasi gerektirmez).

var icon := "paw":
	set(v):
		icon = v
		queue_redraw()
var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()


func _init(name_ := "paw", color_ := Color.WHITE, px := 40.0) -> void:
	icon = name_
	color = color_
	custom_minimum_size = Vector2(px, px)
	mouse_filter = MOUSE_FILTER_IGNORE


func _p(pts: Array) -> PackedVector2Array:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var out := PackedVector2Array()
	for p in pts:
		out.append(o + Vector2(p[0], p[1]) * s)
	return out


func _c(x: float, y: float, r: float, c := color) -> void:
	var s := minf(size.x, size.y)
	draw_circle((size - Vector2(s, s)) * 0.5 + Vector2(x, y) * s, r * s, c)


func _l(pts: Array, w := 0.09, c := color) -> void:
	draw_polyline(_p(pts), c, w * minf(size.x, size.y), true)


func _arc(x: float, y: float, r: float, a0: float, a1: float, w := 0.09, c := color) -> void:
	var s := minf(size.x, size.y)
	draw_arc((size - Vector2(s, s)) * 0.5 + Vector2(x, y) * s, r * s, a0, a1, 24, c, w * s, true)


func _draw() -> void:
	var dark := Color(0, 0, 0, 0.28)
	match icon:
		"paw":
			_c(0.5, 0.64, 0.2)
			for p in [[0.2, 0.42], [0.39, 0.24], [0.61, 0.24], [0.8, 0.42]]:
				_c(p[0], p[1], 0.105)
		"coin":
			_c(0.5, 0.5, 0.42, Color("e9b93a"))
			_c(0.5, 0.5, 0.31, Color("f6d76a"))
			_c(0.5, 0.5, 0.12, Color("e9b93a"))
		"heart":
			_c(0.33, 0.37, 0.21)
			_c(0.67, 0.37, 0.21)
			draw_colored_polygon(_p([[0.13, 0.45], [0.87, 0.45], [0.5, 0.88]]), color)
		"bone":
			_l([[0.26, 0.5], [0.74, 0.5]], 0.16)
			for p in [[0.2, 0.38], [0.2, 0.62], [0.8, 0.38], [0.8, 0.62]]:
				_c(p[0], p[1], 0.12)
		"bolt":
			draw_colored_polygon(_p([[0.58, 0.06], [0.2, 0.56], [0.46, 0.56], [0.4, 0.94], [0.8, 0.42], [0.54, 0.42]]), color)
		"smile":
			_arc(0.5, 0.5, 0.38, 0.0, TAU, 0.09)
			_c(0.36, 0.42, 0.055)
			_c(0.64, 0.42, 0.055)
			_arc(0.5, 0.5, 0.2, 0.25, PI - 0.25, 0.08)
		"drop":
			_c(0.5, 0.62, 0.27)
			draw_colored_polygon(_p([[0.27, 0.52], [0.73, 0.52], [0.5, 0.1]]), color)
		"ball":
			_c(0.5, 0.5, 0.4)
			_arc(0.18, 0.5, 0.36, -0.9, 0.9, 0.06, dark)
			_arc(0.82, 0.5, 0.36, PI - 0.9, PI + 0.9, 0.06, dark)
		"yarn":
			_c(0.48, 0.52, 0.36)
			for k in 3:
				_arc(0.48, 0.2 + k * 0.2, 0.42, 0.5, PI - 0.5, 0.045, dark)
			_l([[0.76, 0.74], [0.9, 0.86], [0.78, 0.94]], 0.06)
		"map":
			draw_colored_polygon(_p([[0.08, 0.2], [0.36, 0.1], [0.64, 0.2], [0.92, 0.1], [0.92, 0.8], [0.64, 0.9], [0.36, 0.8], [0.08, 0.9]]), color)
			_l([[0.36, 0.1], [0.36, 0.8]], 0.04, dark)
			_l([[0.64, 0.2], [0.64, 0.9]], 0.04, dark)
		"pin":
			_c(0.5, 0.38, 0.28)
			draw_colored_polygon(_p([[0.25, 0.5], [0.75, 0.5], [0.5, 0.95]]), color)
			_c(0.5, 0.38, 0.11, dark)
		"camera":
			draw_rect(Rect2(_p([[0.08, 0.28]])[0], Vector2(0.84, 0.56) * minf(size.x, size.y)), color)
			draw_rect(Rect2(_p([[0.34, 0.16]])[0], Vector2(0.32, 0.16) * minf(size.x, size.y)), color)
			_c(0.5, 0.56, 0.19, dark)
			_c(0.5, 0.56, 0.11)
		"bag":
			_l([[0.5, 0.3], [0.5, 0.2], [0.6, 0.14]], 0.06)
			draw_colored_polygon(_p([[0.5, 0.28], [0.92, 0.6], [0.92, 0.72], [0.08, 0.72], [0.08, 0.6]]), color)
		"cart":
			_l([[0.06, 0.18], [0.2, 0.18], [0.32, 0.62], [0.8, 0.62], [0.9, 0.3], [0.25, 0.3]], 0.08)
			_c(0.38, 0.8, 0.08)
			_c(0.74, 0.8, 0.08)
		"list":
			for k in 3:
				_c(0.2, 0.26 + k * 0.24, 0.07)
				_l([[0.36, 0.26 + k * 0.24], [0.86, 0.26 + k * 0.24]], 0.09)
		"gear":
			_arc(0.5, 0.5, 0.26, 0.0, TAU, 0.14)
			for k in 8:
				var a := k * TAU / 8.0
				_l([[0.5 + cos(a) * 0.3, 0.5 + sin(a) * 0.3], [0.5 + cos(a) * 0.44, 0.5 + sin(a) * 0.44]], 0.13)
		"pause":
			_l([[0.35, 0.22], [0.35, 0.78]], 0.16)
			_l([[0.65, 0.22], [0.65, 0.78]], 0.16)
		"close":
			_l([[0.22, 0.22], [0.78, 0.78]], 0.13)
			_l([[0.78, 0.22], [0.22, 0.78]], 0.13)
		"check":
			_l([[0.16, 0.52], [0.4, 0.76], [0.84, 0.24]], 0.14)
		"plus":
			_l([[0.5, 0.18], [0.5, 0.82]], 0.14)
			_l([[0.18, 0.5], [0.82, 0.5]], 0.14)
		"minus":
			_l([[0.18, 0.5], [0.82, 0.5]], 0.14)
		"home":
			draw_colored_polygon(_p([[0.5, 0.1], [0.94, 0.5], [0.06, 0.5]]), color)
			draw_rect(Rect2(_p([[0.2, 0.48]])[0], Vector2(0.6, 0.42) * minf(size.x, size.y)), color)
			draw_rect(Rect2(_p([[0.42, 0.62]])[0], Vector2(0.16, 0.28) * minf(size.x, size.y)), dark)
		"sit":
			_c(0.6, 0.3, 0.17)
			draw_colored_polygon(_p([[0.42, 0.42], [0.74, 0.5], [0.72, 0.9], [0.2, 0.9], [0.24, 0.7]]), color)
		"sun":
			_c(0.5, 0.5, 0.22)
			for k in 8:
				var a := k * TAU / 8.0
				_l([[0.5 + cos(a) * 0.32, 0.5 + sin(a) * 0.32], [0.5 + cos(a) * 0.46, 0.5 + sin(a) * 0.46]], 0.08)
		"moon":
			_c(0.5, 0.5, 0.38)
			draw_circle(_p([[0.66, 0.4]])[0], 0.3 * minf(size.x, size.y), get_meta("bg", Color("fff8ec")))
		"come":
			_l([[0.84, 0.5], [0.2, 0.5]], 0.12)
			_l([[0.46, 0.24], [0.18, 0.5], [0.46, 0.76]], 0.12)
		"play":
			draw_colored_polygon(_p([[0.26, 0.14], [0.86, 0.5], [0.26, 0.86]]), color)
		"hand":
			_c(0.5, 0.62, 0.26)
			for k in 4:
				_l([[0.3 + k * 0.135, 0.5], [0.27 + k * 0.15, 0.2 + absf(k - 1.5) * 0.06]], 0.105)
		"star":
			var pts := []
			for k in 10:
				var a := -PI / 2 + k * PI / 5.0
				var r := 0.44 if k % 2 == 0 else 0.19
				pts.append([0.5 + cos(a) * r, 0.52 + sin(a) * r])
			draw_colored_polygon(_p(pts), color)
		"walk":
			_c(0.52, 0.16, 0.11)
			_l([[0.52, 0.3], [0.48, 0.56], [0.3, 0.9]], 0.1)
			_l([[0.48, 0.56], [0.7, 0.9]], 0.1)
			_l([[0.3, 0.48], [0.52, 0.34], [0.74, 0.48]], 0.08)
		"lock":
			_arc(0.5, 0.4, 0.2, PI, TAU, 0.09)
			draw_rect(Rect2(_p([[0.22, 0.42]])[0], Vector2(0.56, 0.46) * minf(size.x, size.y)), color)
		"shirt":
			draw_colored_polygon(_p([[0.3, 0.14], [0.7, 0.14], [0.94, 0.34], [0.8, 0.5], [0.72, 0.42], [0.72, 0.88], [0.28, 0.88], [0.28, 0.42], [0.2, 0.5], [0.06, 0.34]]), color)
		"sound":
			draw_colored_polygon(_p([[0.1, 0.38], [0.3, 0.38], [0.54, 0.16], [0.54, 0.84], [0.3, 0.62], [0.1, 0.62]]), color)
			_arc(0.54, 0.5, 0.2, -0.9, 0.9, 0.07)
			_arc(0.54, 0.5, 0.34, -0.9, 0.9, 0.07)
		_:
			_c(0.5, 0.5, 0.3)
