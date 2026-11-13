extends Node
## Yakit: araba, motosiklet ve scooter'in depolari (bisiklet yakitsiz). Surdukce yakit azalir; bitince arac
## gaz almaz (tekler). Benzinlikte pompanin yanina yanasip F ile panel acilir: depoyu doldur ya da
## 20 / 50 / 100 TL'lik yakit. Dolum birkac saniye surer: karakter arabadan inip tabancayi tutar, pompa
## ekraninda ve ekranda litre / tutar sayaci akar. Ekranda mini haritanin ustunde yakit cubugu,
## arabanin gosterge panelinde yakit gostergesi. Telefonda "Benzinlik" uygulamasi en yakin istasyona
## yol tarifi verir ve yolda kalana bidonla yakit getirtir.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const Icon = preload("res://scripts/icon.gd")
const GasStation = preload("res://scripts/gas_station.gd")

const TANK := {"araba": 40.0, "motosiklet": 14.0, "scooter": 6.0}      # depo (litre)
const USE := {"araba": 3.0, "motosiklet": 1.0, "scooter": 0.5}          # litre / km (oyun olcegi)
const NAMES := {"araba": "Arabam", "motosiklet": "Motosiklet", "scooter": "Scooter"}
const PRICE := 4.59                                                     # benzin TL / litre
const CAN_L := 5.0                                                      # yol yardim bidonu
const CAN_FEE := 12                                                     # bidon getirme ucreti

var m: Node                       # main
var state: Node                   # GameState (main.state)
var fill: Dictionary = {}         # suren dolum
var _hud: Control
var _bar_bg: Panel
var _bar_fill: Panel
var _bar_style: StyleBoxFlat
var _bar_label: Label
var _bar_icon: Control
var _fill_hud: PanelContainer
var _fill_l: Label
var _fill_tl: Label
var _fill_bar: ProgressBar
var _pump_audio: AudioStreamPlayer
var _sputter: AudioStream
var _sputter_t := 0.0
var _warned := {}
var _near: Dictionary = {}
var _near_t := 0.0
var _nozzle: Node3D
var _hose: MeshInstance3D
var _saved := {}
var _blink := 0.0
var _night_on := -1


func _ready() -> void:
	if ResourceLoader.exists("res://assets/sfx/pompa.wav"):
		var ps: AudioStreamWAV = load("res://assets/sfx/pompa.wav")
		ps.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ps.loop_end = int(ps.get_length() * ps.mix_rate)
		_pump_audio = AudioStreamPlayer.new()
		_pump_audio.stream = ps
		_pump_audio.volume_db = -10.0
		add_child(_pump_audio)
	if ResourceLoader.exists("res://assets/sfx/tekleme.wav"):
		_sputter = load("res://assets/sfx/tekleme.wav")


# ---------------------------------------------------------------- depo

func _tanks() -> Dictionary:
	if not state.d.has("fuel") or typeof(state.d["fuel"]) != TYPE_DICTIONARY:
		state.d["fuel"] = {}
	return state.d["fuel"]


static func uses_fuel(kind: String) -> bool:
	return TANK.has(kind)


func level(kind: String) -> float:
	if not TANK.has(kind):
		return 1.0
	var t := _tanks()
	if not t.has(kind):
		t[kind] = float(TANK[kind]) * 0.6
	return float(t[kind])


func frac(kind: String) -> float:
	return clampf(level(kind) / float(TANK.get(kind, 1.0)), 0.0, 1.0) if TANK.has(kind) else 1.0


func set_frac(kind: String, f: float) -> void:
	if TANK.has(kind):
		_tanks()[kind] = clampf(f, 0.0, 1.0) * float(TANK[kind])


func busy() -> bool:
	return not fill.is_empty()


static func tl(v: float) -> String:
	return ("%.2f" % v).replace(".", ",")


## Surus: gaz girdisini yakit durumuna gore duzeltir (dolumda ve bos depoda gaz yok).
func throttle(kind: String, gas: float, speed: float, dt: float) -> float:
	if busy():
		return 0.0
	if not TANK.has(kind):
		return gas
	var lv := level(kind)
	_sputter_t -= dt
	if lv <= 0.0:
		if absf(gas) > 0.12 and not (gas < 0.0 and speed > 0.2):
			if _sputter_t <= 0.0:
				_sputter_t = 3.5
				m.ui.toast("Yakıt bitti! Araç tekliyor · Telefon > Benzinlik ile bidon getirt")
				_play_sputter()
			return 0.0
		return gas
	# Son damlalar: motor ara ara tekler
	if frac(kind) < 0.03 and gas > 0.12 and randf() < 0.25:
		if _sputter_t <= 0.0:
			_sputter_t = 2.0
			_play_sputter()
		return gas * 0.15
	return gas


func drain(kind: String, meters: float) -> void:
	if not TANK.has(kind) or meters <= 0.0:
		return
	var before := frac(kind)
	_tanks()[kind] = maxf(level(kind) - meters / 1000.0 * float(USE[kind]), 0.0)
	var after := frac(kind)
	for th in [0.15, 0.05]:
		if before > th and after <= th:
			m.ui.toast(("Yakıt azalıyor (%%%d) · Telefon > Benzinlik" % int(th * 100.0)) if th > 0.1 else "Depo neredeyse boş! En yakın benzinliğe git")
			if th < 0.1:
				_play_sputter()
	if after <= 0.0 and before > 0.0:
		_play_sputter()


func _play_sputter() -> void:
	if _sputter == null or not state.d["sound"]:
		return
	var p := AudioStreamPlayer.new()
	p.stream = _sputter
	p.volume_db = -4.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# ---------------------------------------------------------------- istasyonlar

func stations() -> Array:
	return m.world.fuel_stations


func nearest_station(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1e18
	for st in stations():
		var d: float = (st["entry"] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = st
	return best


## Aracin yanindaki pompa (yoksa bos).
func _pump_near(p: Vector2) -> Dictionary:
	for st in stations():
		if (st["pos"] as Vector2).distance_to(p) > 30.0:
			continue
		var best: Dictionary = {}
		var bd := 3.4
		for pu in st["pumps"]:
			var d: float = (pu["lane"] as Vector2).distance_to(p)
			if d < bd:
				bd = d
				best = pu
		if not best.is_empty():
			return best
	return {}


## Etkilesim ipucu (main._update_context): [metin, komut] ya da bos.
func context() -> Array:
	if m._ride == null:
		return []
	if busy():
		return ["Yakıt dolduruluyor…", ""]
	var kind: String = m._ride.get_meta("kind")
	if not TANK.has(kind):
		return []
	var p := Vector2(m._ride.position.x, m._ride.position.z)
	_near = _pump_near(p)
	if _near.is_empty():
		return []
	if absf(m._drive_speed) > 1.5:
		return ["Pompa %s · Yakıt almak için dur" % _near["label"], ""]
	return ["Pompa %s · Yakıt Al (%%%d)" % [_near["label"], int(frac(kind) * 100.0)], "fuel"]


func command(cmd: String) -> void:
	match cmd:
		"fuel":
			open_panel()
		"fuel_app":
			phone_app()


# ---------------------------------------------------------------- panel ve dolum

func open_panel() -> void:
	if m._ride == null or busy():
		return
	var kind: String = m._ride.get_meta("kind")
	if not TANK.has(kind):
		return
	if _near.is_empty():
		_near = _pump_near(Vector2(m._ride.position.x, m._ride.position.z))
	if _near.is_empty():
		return
	var cap: float = TANK[kind]
	var lv := level(kind)
	var need := cap - lv
	var body: VBoxContainer = m.ui._open_panel("YAKAMOZ PETROL", "Pompa %s · Benzin %s ₺/L · Cüzdan %d ₺" % [_near["label"], tl(PRICE), int(state.d["coins"])])
	# Depo gostergesi
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(400, 40)
	body.add_child(row)
	var ic := Icon.new("drop", Color("ffcf4a"), 26.0)
	row.add_child(ic)
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(250, 18)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.max_value = cap
	pb.value = lv
	_style_bar(pb, _fuel_color(lv / cap))
	row.add_child(pb)
	m.ui._fx_label(row, "%.1f / %d L" % [lv, int(cap)], m.ui.F_BODY, 20, Color.WHITE)
	if need < 0.3:
		m.ui._panel_item(body, "Depo zaten dolu", func(): m.ui.close_modal())
		m.ui._focus_first(body)
		return
	var full_cost := ceili(need * PRICE)
	m.ui._panel_item(body, "Depoyu Doldur · %.1f L · %d ₺" % [need, full_cost], func(): start_fill(need))
	for amt in [20, 50, 100]:
		var liters: float = float(amt) / PRICE
		if liters < need - 0.4:
			m.ui._panel_item(body, "%d ₺'lik Yakıt · %.1f L" % [amt, liters], func(): start_fill(liters))
	m.ui._panel_item(body, "Vazgeç", func(): m.ui.close_modal())
	m.ui._focus_first(body)


func _fuel_color(f: float) -> Color:
	if f < 0.15:
		return Color("e5483b")
	if f < 0.35:
		return Color("f2b230")
	return Color("4cc46a")


func _style_bar(pb: ProgressBar, c: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = c
	fg.set_corner_radius_all(5)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)


func start_fill(liters: float) -> void:
	if m._ride == null or busy() or _near.is_empty():
		m.ui.close_modal()
		return
	var kind: String = m._ride.get_meta("kind")
	liters = minf(liters, float(TANK[kind]) - level(kind))
	var cost := ceili(liters * PRICE)
	if not state.spend(cost):
		m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % cost)
		return
	m.ui.close_modal()
	m._drive_speed = 0.0
	fill = {"kind": kind, "total": liters, "done": 0.0, "cost": cost, "pump": _near, "t": 0.0,
		"start": level(kind), "rate": clampf(liters / 5.0, 1.0, 7.0)}
	_begin_visual()
	_show_fill_hud(true)


func _begin_visual() -> void:
	var ride: Node3D = m._ride
	var pu: Dictionary = fill["pump"]
	_saved = {"fps": m._fps, "vis": m.owner_model.visible, "riding": m.owner_model.riding,
		"pos": m.owner_model.position, "rot": m.owner_model.rotation, "grips": m.owner_model.grips}
	if m._fps:
		m._toggle_fps()
	var hide: bool = m.RIDES[ride.get_meta("kind")]["hide"]
	var loc: Vector3 = ride.global_transform.affine_inverse() * (pu["nozzle"] as Vector3)
	var sx := 1.0 if loc.x > 0.0 else -1.0
	var stand := Vector3(sx * 1.35, 0.0, 1.05) if hide else Vector3(sx * 0.8, 0.0, 0.05)
	fill["stand"] = stand
	m.owner_model.riding = ""
	m.owner_model.grips = []
	m.owner_model.visible = true
	m.owner_model.position = stand
	m.owner_model.rotation = Vector3(0, atan2(sx, 0.0), 0)      # araca donuk (model -Z'ye bakar)
	m.owner_model.speed = 0.0
	m.owner_model.act("pet", 0.8)
	# Tabanca: elde yesil kabza + metal uc
	_nozzle = Node3D.new()
	Kit.box(_nozzle, Vector3(0.05, 0.13, 0.08), Vector3(0, -0.02, 0), Kit.mat(GasStation.PRICES[0][2], 0.5))
	Kit.box(_nozzle, Vector3(0.04, 0.04, 0.2), Vector3(0, 0.04, -0.1), Kit.mat("26292d", 0.5))
	Kit.cyl(_nozzle, 0.012, 0.012, 0.16, Vector3(0, 0.03, -0.24), Kit.mat("c3c7cc", 0.3), 8, Vector3(PI * 0.5, 0, 0))
	var hand: Node3D = m.owner_model.hand
	if hand:
		hand.add_child(_nozzle)
	else:
		m.owner_model.add_child(_nozzle)
		_nozzle.position = Vector3(0.25, 1.0, -0.3)
	_hose = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022
	cm.bottom_radius = 0.022
	cm.height = 1.0
	cm.radial_segments = 8
	_hose.mesh = cm
	_hose.material_override = Kit.mat("1a1b1d", 0.6)
	_hose.top_level = true
	m.add_child(_hose)
	if _pump_audio and state.d["sound"]:
		_pump_audio.play()
	if hide:
		m._sfx("araba_kapi", -10.0, 1.1)


func _end_visual() -> void:
	if is_instance_valid(_nozzle):
		_nozzle.queue_free()
	if is_instance_valid(_hose):
		_hose.queue_free()
	_nozzle = null
	_hose = null
	if _pump_audio:
		_pump_audio.stop()
	if not _saved.is_empty():
		m.owner_model.riding = _saved["riding"]
		m.owner_model.visible = _saved["vis"]
		m.owner_model.position = _saved["pos"]
		m.owner_model.rotation = _saved["rot"]
		m.owner_model.grips = _saved["grips"]
		if _saved["fps"] and not m._fps and m._ride != null:
			m._toggle_fps()
	_saved = {}


func _finish_fill() -> void:
	var f := fill
	fill = {}
	_end_visual()
	_show_fill_hud(false)
	_tanks()[f["kind"]] = minf(float(f["start"]) + float(f["total"]), float(TANK[f["kind"]]))
	_warned.erase(f["kind"])
	m._sfx("kasa", -6.0)
	m.ui.toast("Yakıt alındı · %s L · %d ₺ ödendi" % [tl(f["total"]), int(f["cost"])])
	state.count("fuel", 1)
	state.save_game()


func _update_fill(dt: float) -> void:
	if m._ride == null:
		# arac terk edildiyse (olmamali) dolumu kapat
		fill = {}
		_end_visual()
		_show_fill_hud(false)
		return
	fill["t"] = float(fill["t"]) + dt
	if float(fill["t"]) > 1.0:
		fill["done"] = minf(float(fill["done"]) + float(fill["rate"]) * dt, float(fill["total"]))
	var done: float = fill["done"]
	_tanks()[fill["kind"]] = float(fill["start"]) + done
	var pu: Dictionary = fill["pump"]
	var pump: Node3D = pu["node"]
	if is_instance_valid(pump):
		var lt := pump.get_node_or_null("Litre" + str(pu["side"]))
		var tt := pump.get_node_or_null("Tutar" + str(pu["side"]))
		if lt:
			(lt as Label3D).text = tl(done)
		if tt:
			(tt as Label3D).text = tl(done * PRICE)
	if _fill_l:
		_fill_l.text = "%s L" % tl(done)
		_fill_tl.text = "%s ₺" % tl(done * PRICE)
		_fill_bar.max_value = float(TANK[fill["kind"]])
		_fill_bar.value = float(fill["start"]) + done
	# hortum: pompadan eldeki tabancaya
	if is_instance_valid(_hose) and is_instance_valid(_nozzle):
		var a: Vector3 = pu["nozzle"]
		var b: Vector3 = _nozzle.global_position
		var d := b - a
		var L := maxf(d.length(), 0.05)
		var mid := (a + b) * 0.5 - Vector3(0, minf(L * 0.12, 0.3), 0)
		var up := d / L
		var side := up.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var fwd := side.cross(up).normalized()
		_hose.global_transform = Transform3D(Basis(side, up * L, fwd), mid)
	# tabancayi depo kapagina dogru tut (kol pozu animasyonda; karakter araca donuk)
	if float(fill["t"]) > 0.8 and float(fill["t"]) < 1.0:
		m.owner_model.act("pet", 0.3)
	if done >= float(fill["total"]) - 0.0001 and float(fill["t"]) > 1.2:
		_finish_fill()


func _show_fill_hud(on: bool) -> void:
	if not on:
		if _fill_hud:
			_fill_hud.queue_free()
			_fill_hud = null
			_fill_l = null
		return
	if _fill_hud:
		return
	var ui: Node = m.ui
	_fill_hud = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.86)
	sb.border_width_top = 6
	sb.border_color = Color("f28c28")
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 10
	sb.content_margin_bottom = 14
	_fill_hud.add_theme_stylebox_override("panel", sb)
	_fill_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fill_hud.offset_left = -230
	_fill_hud.offset_right = 230
	_fill_hud.offset_top = 96
	_fill_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_fill_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.hud.add_child(_fill_hud)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_fill_hud.add_child(col)
	var pu: Dictionary = fill["pump"]
	var t: Label = ui._fx_label(col, "POMPA %s · BENZİN · %s ₺/L" % [pu["label"], tl(PRICE)], ui.F_BODY, 20, Color(1, 1, 1, 0.8))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	col.add_child(row)
	_fill_l = ui._fx_label(row, "0,00 L", ui.F_TITLE, 50, Color("ffcf4a"), 6)
	_fill_tl = ui._fx_label(row, "0,00 ₺", ui.F_TITLE, 50, Color.WHITE, 6)
	_fill_bar = ProgressBar.new()
	_fill_bar.show_percentage = false
	_fill_bar.custom_minimum_size = Vector2(400, 14)
	_style_bar(_fill_bar, Color("4cc46a"))
	col.add_child(_fill_bar)


# ---------------------------------------------------------------- telefon

func phone_app() -> void:
	var o: Vector2 = m._owner_pos()
	var st := nearest_station(o)
	if st.is_empty():
		m.ui.toast("Bu bölgede benzinlik yok.")
		return
	var dist := int((st["entry"] as Vector2).distance_to(o))
	var levels: Array = []
	for k in ["araba", "motosiklet", "scooter"]:
		levels.append("%s %%%d" % [NAMES[k], int(frac(k) * 100.0)])
	var body: VBoxContainer = m.ui._open_panel("BENZİNLİK", "En yakın: %s · %s · Benzin %s ₺/L\n%s" % [st["name"],
		("%.1f km" % (dist / 1000.0)) if dist > 1000 else ("%d m" % dist), tl(PRICE), "  ·  ".join(levels)])
	m.ui._panel_item(body, "Yol Tarifi Al", func():
		m.ui.close_modal()
		m._set_nav(st["entry"], st["name"])
		m.ui.toast("Yol tarifi haritada · %s" % st["name"]))
	var kind: String = m._ride.get_meta("kind") if m._ride != null else ""
	if TANK.has(kind) and frac(kind) < 0.25 and dist > 60:
		var cost := ceili(CAN_L * PRICE) + CAN_FEE
		m.ui._panel_item(body, "Yol Yardım: %d L Bidon · %d ₺" % [int(CAN_L), cost], func():
			if not state.spend(cost):
				m.ui.toast("Yeterli paran yok · %d ₺ gerekli" % cost)
				return
			m.ui.close_modal()
			_tanks()[kind] = minf(level(kind) + CAN_L, float(TANK[kind]))
			m._sfx("kasa", -6.0)
			m.ui.toast("Yol yardım geldi: %d L yakıt kondu. Benzinliğe git!" % int(CAN_L))
			m._set_nav(st["entry"], st["name"]))
	m.ui._panel_item(body, "Kapat", func(): m.ui.close_modal())
	m.ui._focus_first(body)


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	_update_lights()
	if busy():
		_update_fill(dt)
	_update_hud(dt)
	_update_cockpit()


func _update_lights() -> void:
	var on := 1 if float(m.world._lamp_night) > 0.3 else 0
	if on == _night_on:
		return
	_night_on = on
	for st in stations():
		for l in st["lights"]:
			(l as OmniLight3D).visible = on == 1
			(l as OmniLight3D).light_energy = 1.6 if on == 1 else 0.0
		var pm: StandardMaterial3D = st["panels"]
		pm.emission_energy_multiplier = 2.4 if on == 1 else 0.15


func _build_hud() -> void:
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.size = Vector2(200, 24)
	m.minimap.get_parent().add_child(_hud)
	_bar_icon = Icon.new("drop", Color("ffcf4a"), 22.0)
	_bar_icon.position = Vector2(0, 0)
	_bar_icon.size = Vector2(22, 22)
	_hud.add_child(_bar_icon)
	_bar_bg = Panel.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(6)
	bg.border_color = Color(1, 1, 1, 0.75)
	bg.set_border_width_all(2)
	_bar_bg.add_theme_stylebox_override("panel", bg)
	_bar_bg.position = Vector2(28, 4)
	_bar_bg.size = Vector2(118, 15)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_bar_bg)
	_bar_fill = Panel.new()
	_bar_style = StyleBoxFlat.new()
	_bar_style.set_corner_radius_all(4)
	_bar_fill.add_theme_stylebox_override("panel", _bar_style)
	_bar_fill.position = Vector2(31, 7)
	_bar_fill.size = Vector2(112, 9)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_bar_fill)
	_bar_label = Label.new()
	_bar_label.add_theme_font_size_override("font_size", 18)
	_bar_label.add_theme_color_override("font_color", Color.WHITE)
	_bar_label.add_theme_constant_override("outline_size", 6)
	_bar_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_bar_label.position = Vector2(152, -1)
	_hud.add_child(_bar_label)


func _update_hud(dt: float) -> void:
	var kind: String = m._ride.get_meta("kind") if m._ride != null else ""
	var show: bool = TANK.has(kind) and m.minimap.visible
	if _hud == null:
		if not show:
			return
		_build_hud()
	_hud.visible = show
	if not show:
		return
	_hud.position = m.minimap.position + Vector2(18, -86)
	var f := frac(kind)
	_bar_fill.size.x = maxf(112.0 * f, 0.0)
	_bar_fill.visible = f > 0.005
	_bar_style.bg_color = _fuel_color(f)
	_bar_label.text = "%%%d" % int(round(f * 100.0))
	_blink += dt
	var low := f < 0.15
	_bar_icon.color = Color("e5483b") if low and fmod(_blink, 0.8) < 0.4 else Color("ffcf4a")


## Araba gosterge panelinde (orta ekranin altinda) yakit yazisi ve cubugu.
func _update_cockpit() -> void:
	var cp: Node3D = m._cockpit
	if cp == null or not is_instance_valid(cp) or not cp.visible or m._ride == null:
		return
	var kind: String = m._ride.get_meta("kind")
	if not TANK.has(kind):
		return
	var lab: Label3D = cp.get_node_or_null("Yakit")
	if lab == null:
		lab = Label3D.new()
		lab.name = "Yakit"
		lab.font_size = 32
		lab.pixel_size = 0.0005
		lab.modulate = Color("ffcf4a")
		lab.outline_size = 0
		lab.position = Vector3(-0.36, 0.9105, -0.549)
		lab.rotation.x = -0.3
		cp.add_child(lab)
		var bg := Kit.box(cp, Vector3(0.05, 0.0045, 0.001), Vector3(-0.36, 0.9035, -0.547), Kit.glow("1a1d22", 0.2), Vector3(-0.3, 0, 0))
		bg.name = "YakitBg"
		var fg := Kit.box(cp, Vector3(0.05, 0.0045, 0.001), Vector3(-0.36, 0.9035, -0.5465), Kit.glow("4cc46a", 1.2), Vector3(-0.3, 0, 0))
		fg.name = "YakitBar"
	var f := frac(kind)
	lab.text = "YAKIT %%%d" % int(round(f * 100.0))
	lab.modulate = _fuel_color(f).lightened(0.2)
	var bar: MeshInstance3D = cp.get_node("YakitBar")
	bar.scale.x = maxf(f, 0.02)
	bar.position.x = -0.36 - 0.025 * (1.0 - bar.scale.x)
	var mat := bar.get_active_material(0) as StandardMaterial3D
	if mat:
		mat.emission = _fuel_color(f)
		mat.albedo_color = _fuel_color(f)


# ---------------------------------------------------------------- test

## --atpump: arabayi ilk istasyonun bir pompasinin yanina koyup bindirir. mode: "", "panel", "fill"
func debug_at_pump(mode: String) -> void:
	var st: Dictionary = stations()[0] if not stations().is_empty() else {}
	if st.is_empty():
		print("BENZINLIK YOK")
		return
	if mode == "view":
		# test: istasyona yol tarafindan genis bakis
		m._mode = "debug"
		var root: Node3D = st["root"]
		m.cam.global_position = root.to_global(Vector3(-17.0, 7.5, 21.0))
		m.cam.look_at(root.to_global(Vector3(0.0, 2.0, -3.0)))
		m.cam.fov = 60.0
		return
	var car: Node3D = null
	for r in m._rides:
		if r.get_meta("kind") == "araba":
			car = r
	if car == null:
		return
	var pu: Dictionary = st["pumps"][1]
	var lane: Vector2 = pu["lane"]
	car.position = Vector3(lane.x, ParkMap.walk_height(lane), lane.y)
	car.rotation = Vector3(0, float(st["rot"]), 0)
	m.owner_node.position = car.position + Vector3(1.0, 0, 0)
	m._enter_ride()
	print("POMPA ", st["name"], " ", lane, " yakit=%", int(frac("araba") * 100.0))
	if mode == "panel" or mode.begins_with("fill"):
		for i in 3:
			await get_tree().process_frame
		m._update_context()
		open_panel()
		if mode.begins_with("fill"):
			state.d["coins"] = maxi(int(state.d["coins"]), 400)
			start_fill(float(TANK["araba"]) - level("araba"))
			if mode == "fillcam" and busy():
				# test: dolum yavas aksin, kamera yandan baksin
				fill["rate"] = 2.5
				m._mode = "debug"
				var stand: Vector3 = fill["stand"]
				var sx := signf(stand.x)
				m.cam.global_position = car.to_global(Vector3(sx * 5.2, 2.3, 4.8))
				m.cam.look_at(car.to_global(Vector3(sx * 1.0, 0.9, 0.3)))
