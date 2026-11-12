extends Control
## Araba ici CarPlay ekrani (SubViewport icinde cizilir, on paneldeki ekrana doku olarak gider).
## Solda dock (Harita, Muzik, Telefon), ortada donen harita ve rota, sagda yol tarifi karti.

const ParkMap = preload("res://scripts/park_map.gd")
const W := 640.0
const H := 300.0
const RANGE := 110.0

var player := Vector2.ZERO
var heading := 0.0
var route: Array = []
var dest_name := ""
var speed_kmh := 0.0
var clock := "10:00"
var _tex: Texture2D
var _font: Font


func _ready() -> void:
	size = Vector2(W, H)
	_tex = load(ParkMap.asset("park_map.png"))
	_font = ThemeDB.fallback_font


func _process(_dt: float) -> void:
	queue_redraw()


func _map_rect() -> Rect2:
	return Rect2(78, 10, W - 78 - 10, H - 20)


func _to_px(w: Vector2) -> Vector2:
	var r := _map_rect()
	var k := r.size.y * 0.5 / RANGE
	# Oyuncu haritanin alt-orta kismina yakin: ileriyi daha cok goster
	var c := r.position + Vector2(r.size.x * 0.36, r.size.y * 0.66)
	return c + (w - player).rotated(heading) * k


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0a0b0d"))
	# Dock
	draw_rect(Rect2(0, 0, 70, H), Color("16181c"))
	draw_string(_font, Vector2(14, 34), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	var icons := [["◎", Color("2f80ff")], ["♪", Color("fa3c5a")], ["✆", Color("34c759")], ["✉", Color("30b0ff")]]
	for i in icons.size():
		var p := Vector2(12, 56 + i * 58)
		draw_rect(Rect2(p, Vector2(46, 46)), icons[i][1])
		draw_string(_font, p + Vector2(10, 34), icons[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	# Harita: kucuk dortgenlerle donmus parca
	var r := _map_rect()
	draw_rect(r, Color("dfe6d8"))
	var cells := 18
	var step := RANGE * 2.6 / cells
	var px_per_m := float(_tex.get_width()) / ParkMap.SPLAT_EXTENT
	var k := r.size.y * 0.5 / RANGE
	for j in cells:
		for i in cells:
			var local := Vector2(-RANGE * 1.3 + (i + 0.5) * step, -RANGE * 1.3 + (j + 0.5) * step)
			var w := player + local.rotated(-heading)
			var d := _to_px(w)
			if not r.grow(step * k).has_point(d):
				continue
			var uv := (w / ParkMap.SPLAT_EXTENT + Vector2(0.5, 0.5)) * _tex.get_width()
			var src := Rect2(uv - Vector2.ONE * step * px_per_m * 0.75, Vector2.ONE * step * px_per_m * 1.5)
			var cell := step * k * 1.5
			draw_set_transform(d, heading, Vector2.ONE)
			draw_texture_rect_region(_tex, Rect2(-Vector2.ONE * cell * 0.5, Vector2.ONE * cell), src)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Haritanin disina tasanlari ortu
	draw_rect(Rect2(70, 0, 8, H), Color("0a0b0d"))
	draw_rect(Rect2(70, 0, W - 70, 10), Color("0a0b0d"))
	draw_rect(Rect2(70, H - 10, W - 70, 10), Color("0a0b0d"))
	draw_rect(Rect2(W - 10, 0, 10, H), Color("0a0b0d"))
	if not route.is_empty():
		var pts := PackedVector2Array([_to_px(player)])
		for q in route:
			pts.append(_to_px(q))
		draw_polyline(pts, Color("1d6ef5"), 7.0, true)
		var last := _to_px(route[route.size() - 1])
		if r.has_point(last):
			draw_circle(last, 8.0, Color("e8453c"))
	var c := _to_px(player)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(10, 11), c + Vector2(0, 5), c + Vector2(-10, 11)]), Color.WHITE)
	draw_polyline(PackedVector2Array([c + Vector2(0, -14), c + Vector2(10, 11), c + Vector2(0, 5), c + Vector2(-10, 11), c + Vector2(0, -14)]), Color("1d6ef5"), 3.0, true)
	# Yol tarifi karti
	var card := Rect2(W - 230, 18, 210, 120)
	draw_rect(card, Color(0.09, 0.1, 0.12, 0.92))
	if route.is_empty():
		draw_string(_font, card.position + Vector2(14, 40), "Hedef yok", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		draw_string(_font, card.position + Vector2(14, 76), "Haritadan seç (M)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("a0a4ab"))
	else:
		var total := 0.0
		var prev := player
		for q in route:
			total += prev.distance_to(q)
			prev = q
		var turn := _next_turn()
		draw_string(_font, card.position + Vector2(14, 44), turn[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color.WHITE)
		draw_string(_font, card.position + Vector2(56, 42), turn[1], HORIZONTAL_ALIGNMENT_LEFT, 150, 17, Color.WHITE)
		draw_string(_font, card.position + Vector2(14, 80), dest_name, HORIZONTAL_ALIGNMENT_LEFT, 190, 18, Color("a0a4ab"))
		var eta := int(ceil(total / maxf(speed_kmh / 3.6, 8.0) / 60.0))
		var dist := ("%.1f km" % (total / 1000.0)) if total > 1000.0 else ("%d m" % int(total))
		draw_string(_font, card.position + Vector2(14, 108), "%s · %d dk" % [dist, eta], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("34c759"))
	# Hiz
	draw_circle(Vector2(118, H - 50), 32.0, Color.WHITE)
	draw_string(_font, Vector2(86, H - 42), "%d" % int(speed_kmh), HORIZONTAL_ALIGNMENT_CENTER, 64, 26, Color.BLACK)


## Sonraki donus: rotadaki ilk belirgin yon degisimi -> [ok, "120 m sonra saga"].
func _next_turn() -> Array:
	var prev := player
	var dist := 0.0
	for i in route.size() - 1:
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		dist += prev.distance_to(a)
		prev = a
		var d1 := (a - (player if i == 0 else route[i - 1] as Vector2)).normalized()
		var d2 := (b - a).normalized()
		var ang := d1.angle_to(d2)
		if absf(ang) > 0.6 and dist > 2.0:
			return ["→" if ang > 0.0 else "←", "%d m sonra %s" % [int(dist), "sağa" if ang > 0.0 else "sola"]]
	return ["↑", "Düz devam"]
