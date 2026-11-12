extends Control
## Sag altta yuvarlak mini harita: oyuncu ortada, harita kameranin baktigi yone doner.
## Navigasyon hedefi varsa rota cizgisi ve hedefe kalan mesafe; dokununca buyuk harita acilir.

const ParkMap = preload("res://scripts/park_map.gd")

signal tapped

const SIZE := 200.0
const RANGE := 160.0          # mini haritanin yaricapi (metre)

var player := Vector2.ZERO
var heading := 0.0            # kamera yonu (radyan, main._cam_yaw)
var route: Array = []         # [Vector2] navigasyon rotasi
var dest_name := ""
var _tex: Texture2D
var _dist_label: Label


var _layer: Control


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Bu dugum yalnizca daire cizer; cocuklari bu dairenin icine kirpilir
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_layer = Control.new()
	_layer.size = Vector2(SIZE, SIZE)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.draw.connect(_draw_map)
	add_child(_layer)
	_tex = load(ParkMap.asset("park_map.png"))
	_dist_label = Label.new()
	_dist_label.add_theme_font_size_override("font_size", 17)
	_dist_label.add_theme_color_override("font_color", Color.WHITE)
	_dist_label.add_theme_constant_override("outline_size", 6)
	_dist_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dist_label.position = Vector2(0, SIZE + 4)
	_dist_label.size = Vector2(SIZE, 24)
	# Yazi daire disinda: kirpilmasin diye kardes dugum olarak eklenir
	call_deferred("_attach_label")


func _attach_label() -> void:
	get_parent().add_child(_dist_label)




func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		tapped.emit()
		accept_event()


func _process(_dt: float) -> void:
	_layer.queue_redraw()
	_dist_label.position = position + Vector2(-20, SIZE + 4)
	_dist_label.size = Vector2(SIZE + 40, 24)
	_dist_label.visible = visible
	if route.is_empty():
		_dist_label.text = ""
	else:
		var d := 0.0
		var prev := player
		for p in route:
			d += prev.distance_to(p)
			prev = p
		_dist_label.text = "%s · %d m" % [dest_name, int(d)] if d >= 10.0 else "%s · vardın" % dest_name


## Dunya noktasi -> mini harita pikseli (merkez = oyuncu, ust = kameranin baktigi yon).
func _to_mini(w: Vector2) -> Vector2:
	var rel := (w - player).rotated(heading) * (SIZE * 0.5 / RANGE)
	return Vector2(SIZE, SIZE) * 0.5 + rel


func _draw() -> void:
	draw_circle(Vector2(SIZE, SIZE) * 0.5, SIZE * 0.5, Color.WHITE)


func _draw_map() -> void:
	var L := _layer
	var c := Vector2(SIZE, SIZE) * 0.5
	var r := SIZE * 0.5
	# Harita gorselinden dairesel bir parca: kucuk dortgenlerle donmus olarak cizilir
	var cells := 22
	var step := RANGE * 2.0 / cells
	var px_per_m := float(_tex.get_width()) / ParkMap.SPLAT_EXTENT
	for j in cells:
		for i in cells:
			var local := Vector2(-RANGE + (i + 0.5) * step, -RANGE + (j + 0.5) * step)
			if local.length() > RANGE + step:
				continue
			var w := player + local.rotated(-heading)
			var uv := (w / ParkMap.SPLAT_EXTENT + Vector2(0.5, 0.5)) * _tex.get_width()
			var src := Rect2(uv - Vector2.ONE * step * px_per_m * 0.75, Vector2.ONE * step * px_per_m * 1.5)
			var dst_c := _to_mini(w)
			var cell := step * SIZE * 0.5 / RANGE * 1.5
			L.draw_set_transform(dst_c, heading, Vector2.ONE)
			L.draw_texture_rect_region(_tex, Rect2(-Vector2.ONE * cell * 0.5, Vector2.ONE * cell), src)
	L.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Rota
	if not route.is_empty():
		var pts := PackedVector2Array([_to_mini(player)])
		for p in route:
			pts.append(_to_mini(p))
		L.draw_polyline(pts, Color("3d8bff"), 5.0, true)
		L.draw_circle(_to_mini(route[route.size() - 1]), 6.0, Color("e8453c"))
	# Kenar ve kuzey isareti
	L.draw_arc(c, r - 2.0, 0.0, TAU, 64, Color(1, 1, 1, 0.85), 4.0, true)
	L.draw_arc(c, r + 1.0, 0.0, TAU, 64, Color(0, 0, 0, 0.35), 2.0, true)
	var north := c + Vector2(0, -1).rotated(heading) * (r - 14.0)
	L.draw_circle(north, 10.0, Color(0.1, 0.1, 0.12, 0.85))
	L.draw_string(ThemeDB.fallback_font, north + Vector2(-5, 6), "K", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	# Oyuncu oku (hep yukari bakar: harita kamerayla doner)
	L.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -12), c + Vector2(9, 10), c + Vector2(0, 5), c + Vector2(-9, 10)]), Color("ffffff"))
	L.draw_polyline(PackedVector2Array([c + Vector2(0, -12), c + Vector2(9, 10), c + Vector2(0, 5), c + Vector2(-9, 10), c + Vector2(0, -12)]), Color("1d6ef5"), 2.5, true)
