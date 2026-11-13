extends Node
## Para ve faturalar: cuzdandaki nakit (state.d["coins"]) ve Patibank hesabi (state.d["bank"]).
## Bankanin onunde ve iki marketin yaninda ATM var: F ile panel acilir (bakiye, 50/100/200 cek,
## tumunu yatir, fatura ode). Her ~40 dakikada bir elektrik, su ve dogalgaz faturasi telefona
## bildirim olarak duser; telefonda "Faturalar" (odenmemisler) ve "Banka" (bakiye + son 20 islem)
## uygulamalari var. Son odeme gunu gecen faturaya gecikme zammi biner; elektrik cok gecikirse
## evin lambalari kesilir.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")

const BRAND := "PATİBANK"
const BRAND_NAME := "Patibank"
const CYCLE := 2400.0          # fatura donemi (sn, ~40 dk)
const FIRST := 480.0           # yeni oyunda ilk faturalar
const DUE := 1200.0            # son odeme suresi
const LATE_STEP := 300.0       # gecikme zammi araligi
const CUT_AFTER := 900.0       # elektrik kesintisi (son odemeden sonra)
const BILLS := {
	"elektrik": ["Elektrik", "Başkent Işık Elektrik", 60, 110],
	"su": ["Su", "Çubuk Su İdaresi", 30, 60],
	"dogalgaz": ["Doğalgaz", "Anka Gaz", 45, 130],
}

var m: Node
var state: Node
var atms: Array = []           # [{pos: Vector2, name}]
var _near := -1
var _cut := false


# ---------------------------------------------------------------- durum

func _d() -> Dictionary:
	var d: Dictionary = state.d
	if not d.has("bank"):
		d["bank"] = 250
	if not d.has("tx") or typeof(d["tx"]) != TYPE_ARRAY:
		d["tx"] = []
	if not d.has("bills") or typeof(d["bills"]) != TYPE_ARRAY:
		d["bills"] = []
	if not d.has("bill_t"):
		d["bill_t"] = 0.0
		d["bill_next"] = FIRST
	return d


func balance() -> int:
	return int(_d()["bank"])


func cash() -> int:
	return int(state.d["coins"])


func _log(text: String, amount: int) -> void:
	var tx: Array = _d()["tx"]
	var clk: String = m.ui.clock_label.text if m.ui and m.ui.clock_label else ""
	tx.push_front({"t": text, "a": amount, "c": clk})
	while tx.size() > 20:
		tx.pop_back()


func unpaid() -> Array:
	return _d()["bills"]


func _now() -> float:
	return float(_d()["bill_t"])


# ---------------------------------------------------------------- ATM'ler

func build() -> void:
	var w: Node = m.world
	var spots: Array = []
	for po in ParkMap.data["pois"]:
		if po["k"] == "banka":
			var p := Vector2(po["pos"][0], po["pos"][1])
			spots.append([p, 1.7, po["name"]])
	var markets: Array = []
	for sp in w.shop_spots:
		if sp.get("kind", "") == "market":
			markets.append(sp)
	var home: Vector2 = m.HOME_DOOR
	markets.sort_custom(func(a, b): return (a["pos"] as Vector2).distance_to(home) < (b["pos"] as Vector2).distance_to(home))
	for i in mini(2, markets.size()):
		spots.append([markets[i]["pos"], 2.4, markets[i]["name"]])
	for s in spots:
		var p: Vector2 = s[0]
		var rp: Vector2 = w._road_point(p)
		var dir := (rp - p)
		dir = dir.normalized() if dir.length() > 0.2 else Vector2(0, 1)
		var side := Vector2(-dir.y, dir.x)
		var q: Vector2 = p + side * float(s[1]) + dir * minf(0.8, (rp - p).length() * 0.3)
		if not w.is_free(q, 0.4):
			q = p - side * float(s[1]) + dir * minf(0.8, (rp - p).length() * 0.3)
		_atm_model(w, q, atan2(dir.x, dir.y))
		w._add_circle(Vector3(q.x, q.y, 0.45))
		atms.append({"pos": q + dir * 0.9, "name": s[2]})


func _atm_model(w: Node, p: Vector2, rot: float) -> void:
	var r: Node3D = w._root(p, rot)
	var body := Kit.mat("2b3440", 0.45)
	body.metallic = 0.5
	var trim := Kit.mat("c9ced6", 0.3)
	trim.metallic = 0.8
	var brand := Kit.mat("1d5fd1", 0.4)
	Kit.box(r, Vector3(0.86, 0.08, 0.7), Vector3(0, 0.04, 0), Kit.mat("4a4f57"))
	Kit.box(r, Vector3(0.78, 1.55, 0.6), Vector3(0, 0.85, -0.02), body)
	Kit.box(r, Vector3(0.82, 0.28, 0.66), Vector3(0, 1.76, 0.0), brand)
	var head := Kit.glow("3d8bff", 1.6)
	Kit.box(r, Vector3(0.74, 0.16, 0.02), Vector3(0, 1.76, 0.335), head)
	var lab: Label3D = w._text(r, BRAND, Vector3(0, 1.76, 0.348), Color.WHITE, 0.085)
	lab.outline_size = 0
	# egik on yuz: ekran + tus takimi
	Kit.box(r, Vector3(0.7, 0.62, 0.06), Vector3(0, 1.32, 0.29), trim, Vector3(-0.22, 0, 0))
	Kit.box(r, Vector3(0.5, 0.34, 0.02), Vector3(0, 1.37, 0.33), Kit.glow("58b6ff", 1.3), Vector3(-0.22, 0, 0))
	var st: Label3D = w._text(r, "HOŞ GELDİNİZ\nKARTINIZI TAKINIZ", Vector3(0, 1.37, 0.345), Color("0b2a55"), 0.05)
	st.rotation.x = -0.22
	var shelf := Kit.mat("3a414c", 0.5)
	Kit.box(r, Vector3(0.7, 0.05, 0.3), Vector3(0, 0.98, 0.42), shelf, Vector3(0.25, 0, 0))
	var key := Kit.mat("dfe3e8", 0.4)
	var keyc := [Kit.mat("d33b3b", 0.4), Kit.mat("e6b422", 0.4), Kit.mat("2fa04a", 0.4)]
	for row in 4:
		for col in 3:
			Kit.box(r, Vector3(0.05, 0.02, 0.04), Vector3(-0.12 + col * 0.065, 1.015 + row * 0.012, 0.36 + row * 0.05), key, Vector3(0.25, 0, 0))
		Kit.box(r, Vector3(0.07, 0.02, 0.04), Vector3(0.12, 1.015 + row * 0.012, 0.36 + row * 0.05), keyc[mini(row, 2)] if row < 3 else key, Vector3(0.25, 0, 0))
	# kart ve para yuvasi
	Kit.box(r, Vector3(0.12, 0.03, 0.03), Vector3(0.22, 1.12, 0.33), Kit.glow("2fe07a", 1.0))
	Kit.box(r, Vector3(0.42, 0.05, 0.05), Vector3(0, 0.78, 0.29), Kit.mat("111317", 0.6))
	Kit.box(r, Vector3(0.82, 0.03, 0.62), Vector3(0, 1.9, -0.02), trim)


# ---------------------------------------------------------------- dongu

func update(dt: float) -> void:
	var d := _d()
	d["bill_t"] = float(d["bill_t"]) + dt
	var now := float(d["bill_t"])
	if now >= float(d.get("bill_next", FIRST)):
		d["bill_next"] = now + CYCLE
		_issue()
	for b in unpaid():
		var late := now - float(b["due"])
		if late > 0.0 and int(late / LATE_STEP) + 1 > int(b.get("late", 0)) and int(b.get("late", 0)) < 4:
			b["late"] = int(b.get("late", 0)) + 1
			var fee := maxi(3, int(round(float(b["amount"]) * 0.1)))
			b["amount"] = int(b["amount"]) + fee
			m.ui.toast("%s faturan gecikti! +%d ₺ gecikme zammı (toplam %d ₺)" % [BILLS[b["k"]][0], fee, int(b["amount"])])
			m._sfx("tik", -4.0, 0.7)
	_apply_power()


func _issue() -> void:
	var now := _now()
	var lines: Array = []
	for k in BILLS:
		var info: Array = BILLS[k]
		var exists := false
		for b in unpaid():
			if b["k"] == k:
				exists = true
		if exists:
			continue          # odenmemis olan uzerine yeni fatura binmez; gecikme surer
		var amt := randi_range(int(info[2]), int(info[3]))
		unpaid().append({"k": k, "amount": amt, "base": amt, "due": now + DUE, "late": 0})
		lines.append("%s %d ₺" % [info[0], amt])
	if lines.is_empty():
		return
	m.ui.toast("Telefon · Yeni faturalar: " + ", ".join(lines))
	m.ui.toast("Faturaları telefondan ya da ATM'den ödeyebilirsin (P · Faturalar).")
	m._sfx("tik", -2.0, 1.4)
	state.save_game()


func power_cut() -> bool:
	for b in unpaid():
		if b["k"] == "elektrik" and _now() - float(b["due"]) > CUT_AFTER:
			return true
	return false


func _apply_power() -> void:
	var cut := power_cut()
	var h: Node = m._home
	if h == null:
		_cut = cut
		return
	if cut == _cut and h.has_meta("power_set"):
		return
	_cut = cut
	h.set_meta("power_set", true)
	for l in h.lights:
		l.visible = not cut
	if cut and ParkMap.home == h:
		m.ui.toast("Elektrik kesildi! Elektrik faturası çok gecikti.")
	elif not cut and ParkMap.home == h:
		m.ui.toast("Elektrik geri geldi.")


func _time_left(b: Dictionary) -> String:
	var s := float(b["due"]) - _now()
	if s <= 0.0:
		return "GECİKTİ"
	# oyun saati: 1200 sn = 1 gun
	var hours := int(s / float(m.DAY_SECONDS) * 24.0)
	return "%d saat kaldı" % hours if hours < 24 else "%d gün kaldı" % int(hours / 24)


# ---------------------------------------------------------------- odeme

func pay(i: int, from_bank: bool) -> bool:
	var bills := unpaid()
	if i < 0 or i >= bills.size():
		return false
	var b: Dictionary = bills[i]
	var amt := int(b["amount"])
	var nm: String = BILLS[b["k"]][0]
	if from_bank:
		if balance() < amt:
			m.ui.toast("Hesabında yeterli para yok (%d ₺)." % balance())
			return false
		_d()["bank"] = balance() - amt
		_log("%s faturası" % nm, -amt)
	else:
		if cash() < amt:
			m.ui.toast("Cüzdanında yeterli nakit yok.")
			return false
		state.d["coins"] = cash() - amt
		state.changed.emit()
	bills.remove_at(i)
	m.ui.toast("%s faturası ödendi · %d ₺" % [nm, amt])
	m._sfx("kasa", -4.0)
	state.count("bill")
	_apply_power()
	state.save_game()
	return true


func withdraw(n: int) -> void:
	if balance() < n:
		m.ui.toast("Bakiye yetersiz.")
		return
	_d()["bank"] = balance() - n
	state.d["coins"] = cash() + n
	state.changed.emit()
	_log("ATM para çekme", -n)
	m._sfx("kasa", -4.0)
	state.count("atm")
	state.save_game()


func deposit_all() -> void:
	var n := cash()
	if n <= 0:
		m.ui.toast("Cüzdanın boş.")
		return
	_d()["bank"] = balance() + n
	state.d["coins"] = 0
	state.changed.emit()
	_log("ATM para yatırma", n)
	m._sfx("para", -4.0)
	state.count("atm")
	state.save_game()


# ---------------------------------------------------------------- etkilesim

func context() -> Array:
	_near = -1
	if m._ride != null or ParkMap.home != null:
		return []
	var o: Vector2 = m._owner_pos()
	for i in atms.size():
		if o.distance_to(atms[i]["pos"]) < 1.8:
			_near = i
			return ["%s ATM" % BRAND_NAME, "atm", "coin"]
	return []


func command(cmd: String) -> void:
	match cmd:
		"atm":
			open_atm()
		"bank_app":
			open_bank_app()
		"bills_app":
			open_bills(false)


func open_atm() -> void:
	var ui: Node = m.ui
	m._sfx("tik", -6.0, 1.2)
	var body: VBoxContainer = ui._open_panel(BRAND + " ATM", "Hesap: %d ₺  ·  Cüzdan: %d ₺  ·  Ödenmemiş fatura: %d" % [balance(), cash(), unpaid().size()])
	for n in [50, 100, 200]:
		var amt: int = n
		var b: Button = ui._panel_item(body, "%d ₺ Çek" % amt, func(): withdraw(amt); open_atm())
		b.disabled = balance() < amt
	var dep: Button = ui._panel_item(body, "Tüm Nakdi Yatır · %d ₺" % cash(), func(): deposit_all(); open_atm())
	dep.disabled = cash() <= 0
	if not unpaid().is_empty():
		ui._panel_item(body, "Fatura Öde (%d)" % unpaid().size(), func(): open_bills(true))
	ui._panel_item(body, "Kartı Al · Çık", func(): ui.close_modal())
	ui._focus_first(body)


func open_bills(at_atm: bool) -> void:
	var ui: Node = m.ui
	var total := 0
	for b in unpaid():
		total += int(b["amount"])
	var sub := "Hesap: %d ₺  ·  Cüzdan: %d ₺" % [balance(), cash()]
	if unpaid().is_empty():
		sub += "\nTüm faturaların ödenmiş. Yeni faturalar dönem sonunda gelir."
	else:
		sub += "\nToplam borç: %d ₺" % total
		if power_cut():
			sub += "  ·  EVDE ELEKTRİK KESİK"
	var body: VBoxContainer = ui._open_panel("FATURALAR", sub)
	for i in unpaid().size():
		var b: Dictionary = unpaid()[i]
		var info: Array = BILLS[b["k"]]
		var idx: int = i
		var late := " (+%d)" % (int(b["amount"]) - int(b["base"])) if int(b["late"]) > 0 else ""
		ui._panel_item(body, "%s %d ₺ · %s%s" % [info[0], int(b["amount"]), _time_left(b), late], func(): _pay_menu(idx, at_atm))
	if at_atm:
		ui._panel_item(body, "Geri", func(): open_atm())
	else:
		ui._panel_item(body, "Kapat", func(): ui.close_modal())
	ui._focus_first(body)


func _pay_menu(i: int, at_atm: bool) -> void:
	var ui: Node = m.ui
	var b: Dictionary = unpaid()[i]
	var info: Array = BILLS[b["k"]]
	var body: VBoxContainer = ui._open_panel(info[0].to_upper() + " FATURASI", "%s · Tutar: %d ₺ · %s" % [info[1], int(b["amount"]), _time_left(b)])
	var bb: Button = ui._panel_item(body, "Hesaptan Öde · %d ₺" % balance(), func(): pay(i, true); open_bills(at_atm))
	bb.disabled = balance() < int(b["amount"])
	var cb: Button = ui._panel_item(body, "Nakit Öde · %d ₺" % cash(), func(): pay(i, false); open_bills(at_atm))
	cb.disabled = cash() < int(b["amount"])
	ui._panel_item(body, "Geri", func(): open_bills(at_atm))
	ui._focus_first(body)


func open_bank_app() -> void:
	var ui: Node = m.ui
	var body: VBoxContainer = ui._open_panel(BRAND, "Bakiye: %d ₺  ·  Cüzdan: %d ₺" % [balance(), cash()])
	var tx: Array = _d()["tx"]
	if tx.is_empty():
		ui._fx_label(body, "Henüz işlem yok.", ui.F_BODY, 22, Color(1, 1, 1, 0.7))
	for i in mini(tx.size(), 8):
		var t: Dictionary = tx[i]
		var a := int(t["a"])
		var l: Label = ui._fx_label(body, "%s  %s  %s%d ₺" % [t.get("c", ""), t["t"], "+" if a > 0 else "−", absi(a)], ui.F_BODY, 22,
			Color("7ee08a") if a > 0 else Color("ff8a7a"))
		l.custom_minimum_size = Vector2(400, 30)
	ui._panel_item(body, "Faturalar (%d)" % unpaid().size(), func(): open_bills(false))
	ui._panel_item(body, "En Yakın ATM'ye Yol Tarifi", func():
		var best := -1
		var bd := 1e18
		for j in atms.size():
			var dd: float = (atms[j]["pos"] as Vector2).distance_to(m._owner_pos())
			if dd < bd:
				bd = dd
				best = j
		if best >= 0:
			m._set_nav(atms[best]["pos"], BRAND_NAME + " ATM")
			ui.close_modal())
	ui._panel_item(body, "Kapat", func(): ui.close_modal())
	ui._focus_first(body)


## Test: en yakin ATM'nin onune isinlan ve paneli ac.
func debug_atm() -> void:
	if atms.is_empty():
		return
	var a: Dictionary = atms[0]
	m._place_owner(a["pos"])
	m._focus = m.owner_node.position
	open_atm()


func debug_bills() -> void:
	_d()["bill_next"] = _now()
	update(0.0)
	# bir faturayi gecikmis goster
	if not unpaid().is_empty():
		unpaid()[0]["due"] = _now() - LATE_STEP * 1.5
		update(0.0)
	open_bills(false)
