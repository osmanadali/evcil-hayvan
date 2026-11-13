extends Control
## Acilis introsu: studyo karti, sehrin uzerinde sinematik kamera cekimleri ve GTA tarzi
## egik baslik kartlari, sonunda buyuk logo. Herhangi bir tus / dokunus ile atlanir.

signal finished

const FONT_TITLE := preload("res://assets/fonts/Bangers-Regular.ttf")
const FONT_BODY := preload("res://assets/fonts/Anton-Regular.ttf")
const SHOT_TIME := 3.4
const STUDIO_TIME := 2.6

var cam: Camera3D
## [kamera baslangic, kamera bitis, bakis baslangic, bakis bitis, baslik, alt yazi, renk]
var shots: Array = []
var _t := 0.0
var _shot := -1
var _done := false
var _black: ColorRect
var _bars: Array[ColorRect] = []
var _card: Control
var _title: Label
var _sub: Label
var _stripe: Panel
var _studio: Label
var _logo: Control
var _whoosh: AudioStreamPlayer


func _ready() -> void:
	K_full(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_black = ColorRect.new()
	_black.color = Color.BLACK
	K_full(_black)
	add_child(_black)
	# Sinema seritleri
	for top in [true, false]:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		b.offset_top = 0.0 if top else -90.0
		b.offset_bottom = 90.0 if top else 0.0
		add_child(b)
		_bars.append(b)
	# Baslik karti: egik renkli serit + buyuk yazi
	_card = Control.new()
	_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_card.position = Vector2(70, -330)
	_card.rotation = -0.06
	add_child(_card)
	_stripe = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("f5c518")
	sb.skew = Vector2(0.35, 0)
	_stripe.add_theme_stylebox_override("panel", sb)
	_stripe.size = Vector2(620, 26)
	_stripe.position = Vector2(10, 128)
	_card.add_child(_stripe)
	_title = _label(_card, "", FONT_TITLE, 120, Color.WHITE, 16)
	_title.position = Vector2(0, 0)
	_sub = _label(_card, "", FONT_BODY, 34, Color.WHITE, 8)
	_sub.position = Vector2(26, 160)
	# Studyo karti
	_studio = _label(self, "OA OYUN\nsunar", FONT_BODY, 46, Color.WHITE, 0)
	_studio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_studio.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_studio.offset_left = -300
	_studio.offset_right = 300
	_studio.offset_top = -80
	_studio.offset_bottom = 80
	_studio.modulate.a = 0.0
	# Son logo
	_logo = Control.new()
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.modulate.a = 0.0
	add_child(_logo)
	var l1 := _label(_logo, "PATİLİ", FONT_TITLE, 190, Color("f5c518"), 26)
	l1.position = Vector2(-330, -190)
	var l2 := _label(_logo, "GEZİNTİ", FONT_TITLE, 150, Color("ff5f8f"), 24)
	l2.position = Vector2(-250, -30)
	var l3 := _label(_logo, "KEÇİÖREN · ANKARA", FONT_BODY, 34, Color.WHITE, 8)
	l3.position = Vector2(-150, 140)
	_logo.rotation = -0.05
	var skip := _label(self, "Atlamak için bir tuşa bas", FONT_BODY, 22, Color(1, 1, 1, 0.55), 0)
	skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip.offset_left = -360
	skip.offset_top = -64
	skip.offset_right = -30
	skip.offset_bottom = -30
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_whoosh = AudioStreamPlayer.new()
	_whoosh.stream = _make_whoosh()
	_whoosh.volume_db = -8.0
	add_child(_whoosh)
	_card.visible = false


static func K_full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _label(parent: Node, text: String, font: Font, size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.05))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_x", 5)
	l.add_theme_constant_override("shadow_offset_y", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _input(e: InputEvent) -> void:
	if _done or not visible:
		return
	if (e is InputEventKey and e.pressed) or (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		if _t > 0.4:
			_finish()
		get_viewport().set_input_as_handled()


func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		visible = false
		finished.emit())


func _process(dt: float) -> void:
	if _done or not visible:
		return
	_t += dt
	# 1) Studyo karti
	if _t < STUDIO_TIME:
		_studio.modulate.a = clampf(minf(_t - 0.3, STUDIO_TIME - 0.4 - _t) * 2.5, 0.0, 1.0)
		return
	_studio.visible = false
	var st := _t - STUDIO_TIME
	var i := int(st / SHOT_TIME)
	if i < shots.size():
		var k := fmod(st, SHOT_TIME) / SHOT_TIME
		if i != _shot:
			_shot = i
			_start_card(shots[i])
		var s: Array = shots[i]
		var e := k * k * (3.0 - 2.0 * k) * 0.6 + k * 0.4         # yumusak ama durmayan hareket
		cam.global_position = (s[0] as Vector3).lerp(s[1], e)
		cam.look_at((s[2] as Vector3).lerp(s[3], e))
		cam.fov = 58.0
		# Siyahtan acil / siyaha kapan (kesme)
		_black.color.a = clampf(1.0 - k * 6.0, 0.0, 1.0) + clampf((k - 0.9) * 10.0, 0.0, 1.0)
		_card.modulate.a = clampf((k - 0.12) * 5.0, 0.0, 1.0) * clampf((0.92 - k) * 8.0, 0.0, 1.0)
		_card.position.x = 70.0 - 40.0 * (1.0 - clampf((k - 0.12) * 5.0, 0.0, 1.0)) + k * 30.0
		return
	# 3) Logo
	_card.visible = false
	var lt := st - shots.size() * SHOT_TIME
	if _logo.modulate.a == 0.0:
		_whoosh.play()
	var s2: Array = shots[shots.size() - 1] if not shots.is_empty() else []
	if not s2.is_empty():
		cam.global_position = (s2[1] as Vector3) + Vector3(0, lt * 1.5, 0)
		cam.look_at(s2[3])
	_black.color.a = 0.55
	_logo.modulate.a = clampf(lt * 3.0, 0.0, 1.0)
	_logo.scale = Vector2.ONE * lerpf(1.6, 1.0, clampf(lt * 4.0, 0.0, 1.0))
	if lt > 3.2:
		_finish()


func _start_card(s: Array) -> void:
	_card.visible = true
	_title.text = s[4]
	_sub.text = s[5]
	var sb: StyleBoxFlat = _stripe.get_theme_stylebox("panel")
	sb.bg_color = s[6]
	_title.add_theme_color_override("font_color", Color.WHITE)
	_stripe.size.x = 80.0 + s[4].length() * 62.0
	_whoosh.play()


## Kisa "whoosh" sesi (sentez): filtrelenmis gurultu, yukselip alcalan.
func _make_whoosh() -> AudioStreamWAV:
	var sr := 22050
	var n := int(sr * 0.9)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / n
		var cut := lerpf(0.02, 0.35, sin(t * PI))
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cut
		var v := lp * sin(t * PI) * 0.9
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.data = data
	return w
