
extends CanvasLayer
const Ui = preload("res://scripts/ui.gd")
## GTA tarzi yukleniyor ekrani: Ken-Burns illustrasyon, logo, gercek ilerleme cubugu, ipuclari.

const ART := ["res://assets/ui/load_park.jpg", "res://assets/ui/load_metro.jpg", "res://assets/ui/load_lake.jpg", "res://assets/ui/menu_bg.jpg"]
const TIPS := [
	"Tasmayı L ile takabilirsin.",
	"Metroya Meteoroloji girişinden inebilirsin.",
	"F tuşu yakındaki kapı, dükkan ve kişilerle etkileşim kurar.",
	"Dostunun açlığı azalınca marketten mama al.",
	"Telefonu açarak haritaya, görevlere ve uygulamalara ulaşabilirsin.",
	"Gece olunca sokaklar sakinleşir, ama kapanan dükkanlar da olur.",
	"Yağmurda dostun ıslanır; eve dönüp temizlenmesi gerekebilir.",
	"Madeni paraları toplayıp dükkanlarda harcayabilirsin.",
	"Veteriner, hasta dostunu hemen iyileştirir.",
	"Araca binmek için yakınındaki arabaya F ile yaklaş.",
	"Göl kenarında yürüyüş dostunun neşesini artırır.",
	"Günlük görevleri tamamlayarak ödül kazan.",
	"Eczaneden ilaç, marketten yiyecek alabilirsin.",
	"Fotoğraf modunda dostunla hatıra çekebilirsin.",
	"Haritada bir yere dokun, dostun seni oraya götürsün.",
	"Otobüs duraklarında beklersen şehrin başka yerlerine gidebilirsin.",
]

var _imgs: Array[TextureRect] = []
var _cur := 0
var _t := 0.0
var _next_swap := 5.0
var _bar: ColorRect
var _bar_fill: ColorRect
var _pct: Label
var _status: Label
var _tip: Label
var _tip_t := 0.0
var _tip_i := 0
var _prog := 0.0
var _shown := 0.0
var _root: Control
var _done := false


func setup(place: String, sub := "", first_art := -1) -> CanvasLayer:
	layer = 50
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color("17161c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(clip)
	var r: int = first_art % ART.size() if first_art >= 0 else randi() % ART.size()
	var order: Array = [r]
	for i in ART.size():
		if i != r:
			order.append(i)
	for i in order:
		var tr := TextureRect.new()
		tr.texture = load(ART[i])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.modulate.a = 0.0
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(tr)
		_imgs.append(tr)
	_imgs[0].modulate.a = 1.0
	for top in [true, false]:
		var g := TextureRect.new()
		var gt := GradientTexture2D.new()
		gt.gradient = Gradient.new()
		gt.gradient.set_color(0, Color(0.03, 0.03, 0.05, 0.85 if top else 0.0))
		gt.gradient.set_color(1, Color(0.03, 0.03, 0.05, 0.0 if top else 0.95))
		gt.fill_from = Vector2(0.5, 0)
		gt.fill_to = Vector2(0.5, 1)
		g.texture = gt
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if top:
			g.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			g.offset_bottom = 260
		else:
			g.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			g.offset_top = -340
		_root.add_child(g)
	var logo := Ui._static_label(_root, "PATİLİ GEZİNTİ", Ui.F_TITLE, 78, Ui.ACCENT, 14)
	logo.position = Vector2(56, 30)
	var stripe := ColorRect.new()
	stripe.color = Ui.ACCENT2
	stripe.position = Vector2(60, 124)
	stripe.size = Vector2(300, 6)
	_root.add_child(stripe)
	var loc := Ui._static_label(_root, "Keçiören · " + place, Ui.F_BODY, 28, Color.WHITE, 6)
	loc.position = Vector2(60, 138)
	if sub != "":
		var sl := Ui._static_label(_root, sub, Ui.F_UI, 22, Color(1, 1, 1, 0.85), 4)
		sl.position = Vector2(60, 176)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 60
	box.offset_right = -60
	box.offset_top = -200
	box.offset_bottom = -36
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_tip = Ui._static_label(box, "", Ui.F_UI, 24, Color.WHITE, 4)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_i = randi() % TIPS.size()
	_show_tip()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_status = Ui._static_label(row, "Yükleniyor…", Ui.F_BODY, 24, Color.WHITE, 5)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pct = Ui._static_label(row, "0%", Ui.F_BODY, 24, Ui.ACCENT, 5)
	_bar = ColorRect.new()
	_bar.color = Color(1, 1, 1, 0.18)
	_bar.custom_minimum_size = Vector2(0, 12)
	box.add_child(_bar)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Ui.ACCENT
	_bar_fill.position = Vector2.ZERO
	_bar_fill.size = Vector2(0, 12)
	_bar.add_child(_bar_fill)
	return self


func _show_tip() -> void:
	_tip.text = "İPUCU  ·  " + TIPS[_tip_i % TIPS.size()]


## Gercek ilerleme (0..1) ve durum yazisi.
func set_progress(p: float, status := "") -> void:
	_prog = maxf(_prog, clampf(p, 0.0, 1.0))
	if status != "":
		_status.text = status


## Ilerleme 1'e getirilir, sonra yumusakca kapanir ve silinir (hold: ekran acik kalir).
func finish(hold := false) -> void:
	set_progress(1.0, "Hazır!")
	_shown = 1.0
	_update_bar()
	if hold or _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


func _update_bar() -> void:
	_bar_fill.size = Vector2(_bar.size.x * _shown, 12)
	_pct.text = "%d%%" % int(round(_shown * 100.0))


func _process(dt: float) -> void:
	_t += dt
	_shown = move_toward(_shown, _prog, dt * 0.9)
	_update_bar()
	var vs := _root.size
	for i in _imgs.size():
		var tr := _imgs[i]
		var k: float = minf(1.0 + 0.012 * (_t + i * 3.0), 1.25)
		tr.pivot_offset = vs * 0.5
		tr.scale = Vector2(k, k)
		tr.position = Vector2(sin(_t * 0.07 + i) * 18.0, cos(_t * 0.05 + i * 2.0) * 10.0)
	if _t >= _next_swap and _imgs.size() > 1:
		_next_swap += 5.0
		var nxt := (_cur + 1) % _imgs.size()
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_imgs[nxt], "modulate:a", 1.0, 1.2)
		tw.tween_property(_imgs[_cur], "modulate:a", 0.0, 1.2)
		_cur = nxt
	_tip_t += dt
	if _tip_t > 4.0:
		_tip_t = 0.0
		_tip_i += 1
		_show_tip()
