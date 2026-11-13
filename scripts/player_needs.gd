extends Node
## Oyuncunun ihtiyaclari: Aclik (tokluk) ve Enerji (uyku), state.d["me"] icinde 0..100.
## Gercek zamanla azalir; kosmak enerjiyi daha hizli bitirir, aclik sifirsa enerji de yavasca duser.
## Enerji azsa karakter yavas yurur ve kosamaz. Cantadan yemek tokluk, cay / kahve enerji verir.
## Evde yatak odasindaki yatagin yaninda F "Uyu": ekran kararir, saat ertesi sabah 08:00 olur,
## enerji dolar. Parktaki banklarda F "Bankta Kestir": oturup kisa bir sekerleme (1 saat).
## Ekranda sol ustte, hayvan kartinin altinda iki kucuk cubuk.

const Icon = preload("res://scripts/icon.gd")

const HUNGER_DECAY := 1.25     # dakikada (gercek zaman)
const ENERGY_DECAY := 0.7
const RUN_DECAY := 3.0         # kosarken ek dusus
const STARVE_DECAY := 1.6      # aclik sifirken enerji dususu
const TIRED := 20.0            # bunun altinda yorgun: yavas, kosamaz
const BED_LOCAL := Vector2(3.4, 3.58)
const BED_HALF := Vector2(0.8, 1.0)
# Esya: [tokluk, enerji]
const ITEM_GAIN := {
	"Simit": [30, 0], "Ekmek": [25, 0], "Poğaça": [25, 0], "Çikolata": [12, 8], "Dondurma": [10, 3],
	"Su": [3, 2], "Ayran": [10, 0], "Meyve Suyu": [8, 4], "Çay": [3, 15], "Kahve": [3, 25],
}

var m: Node
var state: Node
var sleeping := false          # uyku / kestirme sirasinda oyuncu hareket etmez
var _bench_near: Array = []    # [pos, yaw]
var _hud: Control
var _rows := {}                # need -> {fill, style, icon, label}
var _layer: CanvasLayer
var _fade: ColorRect
var _fade_title: Label
var _fade_sub: Label
var _warned := {}
var _blink := 0.0
var _hud_t := 0.0
var _zzz: Label3D


func me() -> Dictionary:
	if not state.d.has("me") or typeof(state.d["me"]) != TYPE_DICTIONARY:
		state.d["me"] = {"hunger": 85.0, "energy": 90.0}
	return state.d["me"]


func value(need: String) -> float:
	return float(me().get(need, 80.0))


func add(need: String, amount: float) -> void:
	var d := me()
	d[need] = clampf(float(d.get(need, 80.0)) + amount, 0.0, 100.0)


func tired() -> bool:
	return value("energy") < TIRED


## Yurume hiz siniri: yorgunken yalniz yavas yurur.
func max_speed() -> float:
	var e := value("energy")
	if e < 5.0:
		return 1.6
	if e < TIRED:
		return 2.2
	return 99.0


func busy() -> bool:
	return sleeping


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	_update_hud(dt)
	if m._mode != "play" or sleeping:
		return
	var d := me()
	var running: bool = m._ride == null and m._bus_ride == null and m._taxi == null and m.owner_model.speed > 3.4
	var e_drain := ENERGY_DECAY + (RUN_DECAY if running else 0.0)
	if float(d["hunger"]) <= 0.0:
		e_drain += STARVE_DECAY
	if m.street_food.is_seated():
		e_drain *= 0.3      # oturup dinlenmek yoruyor sayilmaz
	d["hunger"] = maxf(float(d["hunger"]) - HUNGER_DECAY * dt / 60.0, 0.0)
	d["energy"] = maxf(float(d["energy"]) - e_drain * dt / 60.0, 0.0)
	_warn(d)


func _warn(d: Dictionary) -> void:
	var e := float(d["energy"])
	var h := float(d["hunger"])
	if e < TIRED and not _warned.has("tired"):
		_warned["tired"] = true
		m.ui.toast("Çok yorgunsun, koşamıyorsun. Evine gidip yatakta uyu ya da bir bankta kestir (F).")
	elif e > TIRED + 10.0:
		_warned.erase("tired")
	if h < 20.0 and not _warned.has("hungry"):
		_warned["hungry"] = true
		m.ui.toast("Karnın acıktı! Çantadan bir şey ye ya da simitçiden simit al.")
	elif h > 30.0:
		_warned.erase("hungry")
	if h <= 0.0 and not _warned.has("starve"):
		_warned["starve"] = true
		m.ui.toast("Açlıktan enerjin düşüyor, hemen bir şeyler ye!")
	elif h > 5.0:
		_warned.erase("starve")


## Cantadan bir sey yenince / icilince.
func on_item(name: String) -> void:
	var g: Array = ITEM_GAIN.get(name, [8, 0])
	add("hunger", float(g[0]))
	add("energy", float(g[1]))
	if float(g[1]) >= 10.0:
		m.ui.toast("%s içtin, biraz kendine geldin. (+%d enerji)" % [name, int(g[1])])


# ---------------------------------------------------------------- etkilesim

func _near_bed() -> bool:
	if m._home == null or ParkMap_home() != m._home:
		return false
	var lo: Vector2 = m._home.local2(m._owner_pos())
	var q := (lo - BED_LOCAL).abs() - BED_HALF
	return maxf(q.x, q.y) < 0.75


func ParkMap_home() -> Node3D:
	return preload("res://scripts/park_map.gd").home


func _bench_at(o: Vector2) -> Array:
	var best: Array = []
	var bd := 1.6
	for b in m.world.benches:
		var dd: float = o.distance_to(b[0])
		if dd < bd:
			bd = dd
			best = b
	return best


## [metin, komut, simge] ya da bos.
func context() -> Array:
	if sleeping:
		return ["", "", ""]
	if _near_bed():
		return ["Uyu · sabah 08:00'e kadar", "sleep", "moon"]
	if ParkMap_home() == null and m._ride == null and not m.street_food.is_seated():
		var b := _bench_at(m._owner_pos())
		if not b.is_empty():
			_bench_near = b
			return ["Bankta Kestir", "nap", "sit"]
	return []


func command(cmd: String) -> void:
	match cmd:
		"sleep":
			sleep()
		"nap":
			if not _bench_near.is_empty():
				nap(_bench_near)


func _stop_owner() -> void:
	m._moving = false
	m._queue.clear()
	m._steering = false
	m._target = m._owner_pos()
	m.owner_model.speed = 0.0
	m.ui.stick = Vector2.ZERO


func _build_fade() -> void:
	if _layer:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.02, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade.modulate.a = 0.0
	_fade.visible = false
	_layer.add_child(_fade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	_fade.add_child(box)
	_fade_title = m.ui._fx_label(box, "Zzz...", m.ui.F_TITLE, 96, Color("9fb4ff"), 0)
	_fade_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_sub = m.ui._fx_label(box, "", m.ui.F_BODY, 30, Color(1, 1, 1, 0.8), 0)
	_fade_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _fade_to(a: float, secs: float) -> void:
	_build_fade()
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", a, secs)
	await tw.finished
	if a <= 0.0:
		_fade.visible = false


func _sit_at(pos: Vector2, yaw: float, h: float) -> void:
	m.owner_node.position = Vector3(pos.x, h, pos.y)
	m.owner_node.rotation = Vector3(0, yaw, 0)
	m.owner_model.position = Vector3(0, -0.05, 0)
	m.owner_model.seated = true


func _stand(pos: Vector2) -> void:
	m.owner_model.seated = false
	m.owner_model.position = Vector3.ZERO
	m.owner_node.position = Vector3(pos.x, preload("res://scripts/park_map.gd").walk_height(pos), pos.y)
	m._target = pos


## Evde yatakta uyu: karar, saat ertesi sabah 08:00, enerji dolar.
func sleep() -> void:
	if sleeping or m._home == null:
		return
	sleeping = true
	_stop_owner()
	m.ui.set_context("", "")
	m.ui._actions.visible = false
	var home: Node3D = m._home
	var stand_l: Vector2 = home.local2(m._owner_pos())
	# Yatagin kenarina otur (yatak odasina bakan uzun kenar)
	var edge_l := Vector2(BED_LOCAL.x + 0.62, clampf(stand_l.y, BED_LOCAL.y - 0.5, BED_LOCAL.y + 0.7))
	var edge: Vector2 = home.w2(edge_l)
	var out: Vector2 = home.w2(edge_l + Vector2(0.75, 0.0))
	var face := out - edge
	_sit_at(edge, atan2(-face.x, -face.y), home.global_position.y + 0.55)
	for k in m.agents:
		m.agents[k].command("lie")
	var hours := fposmod(8.0 - float(m.clock), 24.0)
	if hours < 1.0:
		hours += 24.0
	await get_tree().create_timer(0.8).timeout
	_build_fade()
	_fade_title.text = "Zzz..."
	_fade_sub.text = "İyi uykular"
	await _fade_to(1.0, 1.4)
	# Karanlikta saat ilerler
	var steps := 24
	var start: float = m.clock
	for i in steps:
		m.clock = fposmod(start + hours * float(i + 1) / steps, 24.0)
		_fade_sub.text = "%02d:%02d" % [int(m.clock), int(fmod(m.clock, 1.0) * 60.0)]
		await get_tree().create_timer(0.06).timeout
	m.clock = 8.0
	_fade_sub.text = "08:00"
	var d := me()
	d["energy"] = 100.0
	d["hunger"] = maxf(float(d["hunger"]) - minf(hours, 10.0) * 2.0, 5.0)
	for k in m.agents:
		state.add_need(k, "energy", 100.0)
	state.count("sleep")
	state.save_game()
	_fade_title.text = "Günaydın!"
	_fade_title.add_theme_color_override("font_color", Color("ffd36b"))
	await get_tree().create_timer(1.1).timeout
	_stand(out)
	for k in m.agents:
		m.agents[k].command("come")
	await _fade_to(0.0, 1.2)
	_fade_title.add_theme_color_override("font_color", Color("9fb4ff"))
	sleeping = false
	m.ui._actions.visible = true
	m.ui.toast("Günaydın! Dinlenmiş uyandın, enerjin doldu.")
	m._pet_voice(m._active().kind)
	m._update_context()


## Bankta kisa sekerleme: oturur, ekran yari kararir, bir saat gecer.
func nap(b: Array) -> void:
	if sleeping:
		return
	sleeping = true
	_stop_owner()
	m.ui.set_context("", "")
	m.ui._actions.visible = false
	var bp: Vector2 = b[0]
	var yaw: float = float(b[1]) + PI      # bankin onune bak
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var seat := bp + fwd * 0.2
	var stand_p: Vector2 = bp + fwd * 0.95
	_sit_at(seat, yaw, preload("res://scripts/park_map.gd").walk_height(bp) + 0.48)
	var side := Vector2(cos(yaw), -sin(yaw))
	var i := 0
	for k in m.agents:
		var a: Node3D = m.agents[k]
		a.command("lie")
		a.place(bp + fwd * 1.1 + side * (0.6 - 1.0 * i))
		i += 1
	_show_zzz(true)
	await get_tree().create_timer(1.2).timeout
	_build_fade()
	_fade_title.text = "Zzz..."
	_fade_sub.text = "Bankta kestiriyorsun"
	_show_zzz(false)
	await _fade_to(0.82, 1.0)
	var start: float = m.clock
	for s in 30:
		m.clock = fposmod(start + float(s + 1) / 30.0, 24.0)
		add("energy", 1.0)
		_fade_sub.text = "%02d:%02d" % [int(m.clock), int(fmod(m.clock, 1.0) * 60.0)]
		await get_tree().create_timer(0.07).timeout
	add("hunger", -3.0)
	for k in m.agents:
		state.add_need(k, "energy", 25.0)
	state.count("sleep")
	await _fade_to(0.0, 0.9)
	_show_zzz(false)
	_stand(stand_p)
	for k in m.agents:
		m.agents[k].command("come")
	sleeping = false
	m.ui._actions.visible = true
	m.ui.toast("Biraz kestirdin, dinçleştin. (+30 enerji)")
	m._update_context()


func _show_zzz(on: bool) -> void:
	if on:
		if _zzz == null:
			_zzz = Label3D.new()
			_zzz.text = "z Z z"
			_zzz.font_size = 72
			_zzz.pixel_size = 0.004
			_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_zzz.modulate = Color("cfe0ff")
			_zzz.outline_size = 14
			_zzz.no_depth_test = true
		if _zzz.get_parent() == null:
			m.owner_node.add_child(_zzz)
		_zzz.position = Vector3(0.2, 1.75, 0)
		_zzz.visible = true
	elif _zzz:
		_zzz.visible = false


# ---------------------------------------------------------------- gosterge

func _build_hud() -> void:
	_hud = VBoxContainer.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_constant_override("separation", 4)
	m.ui.hud.add_child(_hud)
	_row("hunger", "fork", "AÇLIK", Color("f29a3a"))
	_row("energy", "bolt", "ENERJİ", Color("5cc8ff"))


func _row(need: String, icon: String, title: String, c: Color) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	_hud.add_child(row)
	var ic := Icon.new(icon, c, 20.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(62, 0)
	l.add_theme_font_override("font", m.ui.F_BODY)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	row.add_child(l)
	var bg := Panel.new()
	bg.custom_minimum_size = Vector2(150, 12)
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0, 0, 0, 0.55)
	bs.border_color = Color(0, 0, 0, 0.85)
	bs.set_border_width_all(2)
	bg.add_theme_stylebox_override("panel", bs)
	row.add_child(bg)
	var fill := Panel.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2(2, 2)
	fill.size = Vector2(146, 8)
	var fs := StyleBoxFlat.new()
	fs.bg_color = c
	fill.add_theme_stylebox_override("panel", fs)
	bg.add_child(fill)
	_rows[need] = {"fill": fill, "style": fs, "icon": ic, "color": c}


func _update_hud(dt: float) -> void:
	if m.ui == null or m.ui.hud == null:
		return
	if _hud == null:
		_build_hud()
	var show: bool = m.ui.hud.visible and m._mode == "play"
	_hud.visible = show
	if not show:
		return
	_blink += dt
	_hud_t -= dt
	if _hud_t <= 0.0:
		_hud_t = 0.25
		var cards: Control = m.ui.hud.get_node("Cards")
		_hud.position = cards.position + Vector2(4, cards.size.y + 8.0)
	for need in _rows:
		var r: Dictionary = _rows[need]
		var v := value(need) / 100.0
		var f: Panel = r["fill"]
		f.size.x = 146.0 * v
		f.visible = v > 0.01
		var low := v < 0.2
		var c: Color = r["color"]
		var fl: bool = low and fmod(_blink, 0.8) < 0.4
		(r["style"] as StyleBoxFlat).bg_color = Color("e5483b") if fl else c
		(r["icon"] as Control).set("color", Color("e5483b") if fl else c)
		(r["icon"] as Control).queue_redraw()
