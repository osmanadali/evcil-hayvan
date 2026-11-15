extends Node
## Evcil hayvan saglik takibi: asi takvimi (karne), kisirlastirma + koruyucu tasma (kon), kilo takibi.
## Veriler state.pet(kind) icinde: vaccines {ad: "YYYY-AA-GG"}, neutered, cone_until (unix), weight, wlog [[t, kg]].
## Telefonda "Sağlık Karnesi" uygulamasi; asi zamani gelince Mesajlar'a veteriner mesaji duser (yol tarifiyle).

const VACCINES := [["Kuduz", 25, 365], ["Karma", 25, 365], ["İç-Dış Parazit", 20, 90]]   # ad, fiyat, gecerlilik (gun)
const NEUTER_COST := 150
const COLLAR_SECS := 300.0
const BASE_W := {"kopek": 12.0, "kedi": 4.2}
const IDEAL := {"kopek": [9.5, 14.5], "kedi": [3.4, 5.0]}
const KG_PER_M := 0.0004      # yurume ile verilen kilo
const MEAL_KG := 0.0028       # tokluk puani basina alinan kilo
const LOG_EVERY := 100.0      # saniye
const LOG_MAX := 18

var m: Node
var state: Node
var _t := 0.0
var _log_t := 0.0
var _rem_t := 25.0
var _last_pos := {}
var _acc := {}


func _p(kind: String) -> Dictionary:
	return state.pet(kind)


func weight(kind: String) -> float:
	var p := _p(kind)
	if not p.has("weight"):
		p["weight"] = BASE_W.get(kind, 8.0)
	return float(p["weight"])


func _add_w(kind: String, kg: float) -> void:
	var p := _p(kind)
	var lo: float = 0.6 * float(BASE_W[kind])
	p["weight"] = clampf(weight(kind) + kg, lo, 2.0 * float(BASE_W[kind]))


## Yemek yenince kilo alinir; diyet mama kilo verdirir.
func on_eat(kind: String, food_id: String) -> void:
	var f: Array = state.FOODS.get(food_id, state.FOODS["mama"])
	if food_id == "diyet":
		_add_w(kind, -0.12)
	else:
		_add_w(kind, float(f[2]) * MEAL_KG)


func band(kind: String) -> int:     # -1 zayif, 0 ideal, 1 kilolu
	var w := weight(kind)
	var r: Array = IDEAL[kind]
	return -1 if w < float(r[0]) else (1 if w > float(r[1]) else 0)


func band_text(kind: String) -> String:
	return ["Zayıf, daha çok beslemeli", "İdeal kilo", "Fazla kilolu · diyet ve yürüyüş önerilir"][band(kind) + 1]


# ---------------------------------------------------------------- asi takvimi

func _days_since(date: String) -> float:
	var u := Time.get_unix_time_from_datetime_string(date + "T00:00:00")
	return (Time.get_unix_time_from_system() - u) / 86400.0


## Kalan gun; asi hic yapilmadiysa -1 (hemen zamani gelmis).
func days_left(kind: String, vn: String) -> int:
	var vac: Dictionary = _p(kind).get("vaccines", {})
	if not vac.has(vn):
		return -1
	for v in VACCINES:
		if v[0] == vn:
			return int(floor(float(v[2]) - _days_since(vac[vn])))
	return 0


func due_text(kind: String, vn: String) -> String:
	var vac: Dictionary = _p(kind).get("vaccines", {})
	if not vac.has(vn):
		return "Yapılmadı · hemen yaptır"
	var dl := days_left(kind, vn)
	if dl < 0:
		return "Süresi %d gün önce doldu" % -dl
	if dl <= 14:
		return "Son yapılan %s · %d gün kaldı" % [vac[vn], dl]
	return "Yapıldı %s · sonraki %d gün sonra" % [vac[vn], dl]


func needs_vaccine(kind: String) -> Array:
	var out := []
	for v in VACCINES:
		if days_left(kind, v[0]) <= 7:
			out.append(v[0])
	return out


func _today() -> String:
	return Time.get_date_string_from_system()


func _reminders() -> void:
	var rd: Dictionary = state.d.get("vh_rem", {})
	for k in state.owned_pets():
		var due := needs_vaccine(k)
		if due.is_empty():
			continue
		var key := "%s:%s" % [k, _today()]
		if rd.has(key):
			continue
		rd[key] = true
		state.d["vh_rem"] = rd
		var nm: String = _p(k)["name"]
		m.neighbors.push_msg("vet", "%s için aşı zamanı geldi: %s. Kliniğe uğrarsan hemen yapalım, yol tarifini gönderiyorum." % [nm, ", ".join(due)],
			"vet", ["Tamam, geliyorum", "Bu hafta uğrarım"], false, "vet")
		return


# ---------------------------------------------------------------- kisirlastirma ve kon

func neutered(kind: String) -> bool:
	return _p(kind).has("neutered")


func in_recovery(kind: String) -> bool:
	return float(_p(kind).get("cone_until", 0.0)) > Time.get_unix_time_from_system()


func neuter(kind: String, free := false) -> bool:
	var p := _p(kind)
	if neutered(kind) or (not free and not state.spend(NEUTER_COST)):
		return false
	p["neutered"] = _today()
	p["cone_until"] = Time.get_unix_time_from_system() + COLLAR_SECS
	state.add_need(kind, "energy", -25.0)
	state.save_game()
	state.count("vet")
	_sync_cone(kind)
	return true


func make_cone() -> Node3D:
	var root := Node3D.new()
	root.name = "Cone"
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.93, 0.95, 0.98, 0.8)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mm.roughness = 0.35
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.075
	cm.height = 0.2
	cm.radial_segments = 20
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	cone.material_override = mm
	cone.rotation.x = -PI / 2.0
	root.add_child(cone)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.19
	tm.outer_radius = 0.21
	rim.mesh = tm
	rim.material_override = mm
	rim.rotation.x = PI / 2.0
	rim.position = Vector3(0, 0, -0.1)
	root.add_child(rim)
	return root


func _sync_cone(kind: String) -> void:
	if not m.agents.has(kind):
		return
	var a: Node3D = m.agents[kind]
	var sock: Node3D = a.model.face_socket
	var has := sock.get_node_or_null("Cone") != null
	var want := in_recovery(kind)
	if want and not has:
		var c := make_cone()
		sock.add_child(c)
		c.position = Vector3(0, -0.05, 0.1)
		c.scale = Vector3.ONE * 1.6
	elif not want and has:
		sock.get_node("Cone").queue_free()
		m.ui.toast("%s'nin koruyucu tasması çıkarıldı, iyileşti!" % _p(kind)["name"])


# ---------------------------------------------------------------- dongu

func update(dt: float) -> void:
	if m._mode != "play":
		return
	for k in m.agents:
		var a: Node3D = m.agents[k]
		var pos := Vector2(a.position.x, a.position.z)
		if _last_pos.has(k):
			var d: float = pos.distance_to(_last_pos[k])
			if d < 3.0:
				_acc[k] = float(_acc.get(k, 0.0)) + d
		_last_pos[k] = pos
		if float(_acc.get(k, 0.0)) >= 20.0:
			_add_w(k, -float(_acc[k]) * KG_PER_M)
			_acc[k] = 0.0
	_t -= dt
	if _t <= 0.0:
		_t = 1.0
		for k in m.agents:
			_sync_cone(k)
	_log_t -= dt
	if _log_t <= 0.0:
		_log_t = LOG_EVERY
		for k in state.owned_pets():
			log_weight(k)
	_rem_t -= dt
	if _rem_t <= 0.0:
		_rem_t = 90.0
		_reminders()


func log_weight(kind: String) -> void:
	var p := _p(kind)
	var wl: Array = p.get("wlog", [])
	wl.append([Time.get_unix_time_from_system(), snappedf(weight(kind), 0.01)])
	while wl.size() > LOG_MAX:
		wl.pop_front()
	p["wlog"] = wl


# ---------------------------------------------------------------- telefon uygulamasi

func phone_app() -> void:
	var kind: String = state.d["active"]
	var p := _p(kind)
	var ui: Node = m.ui
	var body: VBoxContainer = ui.phone_page("Sağlık Karnesi", "%s · %.1f kg" % [p["name"], weight(kind)])
	ui._fx_label(body, "AŞI TAKVİMİ", ui.F_TITLE, 22, ui.ACCENT, 3)
	for v in VACCINES:
		var vn: String = v[0]
		var dl := days_left(kind, vn)
		var col := Color("ff6b5a") if dl <= 7 else Color("8be28b")
		var l: Label = ui._fx_label(body, "%s\n%s" % [vn, due_text(kind, vn)], ui.F_UI, 18, col)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var op := "Kısırlaştırıldı (%s)" % p["neutered"] if neutered(kind) else "Kısırlaştırma yapılmadı"
	if in_recovery(kind):
		op += " · koruyucu tasma takılı"
	var ol: Label = ui._fx_label(body, op, ui.F_UI, 18, Color(1, 1, 1, 0.85))
	ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui._fx_label(body, "KİLO GRAFİĞİ", ui.F_TITLE, 22, ui.ACCENT, 3)
	_chart(body, kind)
	var bl: Label = ui._fx_label(body, band_text(kind), ui.F_UI, 18, [Color("ffd35a"), Color("8be28b"), Color("ff6b5a")][band(kind) + 1])
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if m.world.vet_pos != Vector2.INF:
		ui.phone_item(body, "Veterinere Yol Tarifi", func(): m._phone_nav(m.world.vet_pos, "Veteriner"))


func _chart(body: Node, kind: String) -> void:
	var wl: Array = _p(kind).get("wlog", []).duplicate()
	wl.append([Time.get_unix_time_from_system(), weight(kind)])
	var c := Control.new()
	c.custom_minimum_size = Vector2(300, 130)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(c)
	var rng: Array = IDEAL[kind]
	c.draw.connect(func():
		var sz: Vector2 = c.size
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.06))
		var lo: float = minf(float(rng[0]) - 0.6, _minw(wl)) - 0.2
		var hi: float = maxf(float(rng[1]) + 0.6, _maxw(wl)) + 0.2
		var y_of := func(w: float) -> float: return sz.y - 8.0 - (w - lo) / (hi - lo) * (sz.y - 16.0)
		var y1: float = y_of.call(float(rng[1]))
		var y0: float = y_of.call(float(rng[0]))
		c.draw_rect(Rect2(0, y1, sz.x, y0 - y1), Color(0.3, 0.8, 0.4, 0.18))
		var pts := PackedVector2Array()
		for i in wl.size():
			var x: float = 8.0 + (sz.x - 16.0) * (float(i) / maxf(wl.size() - 1, 1.0))
			pts.append(Vector2(x, y_of.call(float(wl[i][1]))))
		if pts.size() >= 2:
			c.draw_polyline(pts, Color("ffd35a"), 3.0, true)
		for pt in pts:
			c.draw_circle(pt, 3.5, Color.WHITE)
		c.draw_string(ThemeDB.fallback_font, Vector2(6, 14), "%.1f kg" % hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
		c.draw_string(ThemeDB.fallback_font, Vector2(6, sz.y - 4), "%.1f kg" % lo, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6)))


func _minw(wl: Array) -> float:
	var r := 1e9
	for e in wl:
		r = minf(r, float(e[1]))
	return r


func _maxw(wl: Array) -> float:
	var r := -1e9
	for e in wl:
		r = maxf(r, float(e[1]))
	return r


# ---------------------------------------------------------------- veteriner ekleri

func vet_items(body: Node, kind: String, reopen: Callable) -> void:
	var ui: Node = m.ui
	var p := _p(kind)
	if not neutered(kind):
		ui._panel_item(body, "KISIRLAŞTIRMA  ·  %d ₺" % NEUTER_COST, func():
			if state.d["coins"] < NEUTER_COST:
				ui.toast("Paran yetmiyor · %d ₺ gerekli" % NEUTER_COST)
				return
			if neuter(kind):
				ui.close_modal()
				ui.toast("Ameliyat başarılı. %s birkaç dakika koruyucu tasma takacak, dinlenmesi lazım." % p["name"]))
	ui._panel_item(body, "KİLO DANIŞMANI  ·  %.1f kg" % weight(kind), func():
		var adv: String = ["Biraz zayıf, mamasını artır.", "Kilosu ideal, böyle devam!", "Fazla kilolu. Diyet mama ver ve bol yürüt."][band(kind) + 1]
		ui.toast("Veteriner: \"%s\"" % adv))
	if band(kind) >= 0:
		ui._panel_item(body, "DİYET MAMA AL  ·  12 ₺", func():
			if state.spend(12):
				state.d["foods"]["diyet"] = int(state.d["foods"].get("diyet", 0)) + 1
				ui.toast("Diyet Mama çantaya eklendi. Mama menüsünden ver.")
				reopen.call()
			else:
				ui.toast("Paran yetmiyor."))
