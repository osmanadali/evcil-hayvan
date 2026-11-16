extends Node
## Ilk kullanim ipuclari: bir ozellik ilk kez kullanilinca kisa, engellemeyen bir GTA tarzi kart.
## state.d["tutorials_seen"] {id: true}, state.d["tips"] (varsayilan acik). Ayarlar'dan sifirlanir.

const Keybinds = preload("res://scripts/keybinds.gd")

var m: Node
var state: Node

var _card: PanelContainer
var _title: Label
var _body: Label
var _queue: Array = []
var _showing := ""
var _t := 0.0
var _poll := 0.0
var _last_cmd := ""
var _started := false
var _start_wait := 0.0
var _drive_time := 0.0
var _was_ride := false
var _force := false
var _touch := DisplayServer.is_touchscreen_available()


func _k(a: String) -> String:
	return Keybinds.primary(a)


func _seen() -> Dictionary:
	if not state.d.has("tutorials_seen") or typeof(state.d["tutorials_seen"]) != TYPE_DICTIONARY:
		state.d["tutorials_seen"] = {}
	return state.d["tutorials_seen"]


func enabled() -> bool:
	return bool(state.d.get("tips", true))


## Ipucu: [baslik, metin]. Bos dizi = bilinmeyen kimlik.
func texts(id: String) -> Array:
	var move := "%s %s %s %s" % [_k("move_forward"), _k("move_left"), _k("move_back"), _k("move_right")]
	var f := _k("interact")
	var press: String = "düğmeye dokun" if _touch else "%s tuşuna bas" % f
	match id:
		"start":
			if _touch:
				return ["HOŞ GELDİN", "Sol alttaki çubukla yürü, ekranı sürükleyerek etrafına bak.\nBeliren düğmeye dokun: etkileşim. Menüden telefon ve haritayı aç."]
			return ["HOŞ GELDİN", "%s yürü  ·  %s koş  ·  Fareyle etrafına bak\n%s etkileşim  ·  %s telefon  ·  %s harita  ·  %s komutlar" % [move, _k("sprint"), f, _k("phone"), _k("map"), _k("commands")]]
		"car_near":
			return ["ARABAYA BİNME", "Arabanın yanına git, " + press + ".\nHayvanların seninle birlikte biner."]
		"drive":
			if _touch:
				return ["ARABA SÜRME", "Sağ alttaki pedallarla gaz ve fren, sol alttaki çubukla direksiyon.\nİç kamera ve in düğmeleri kamera yanında."]
			return ["ARABA SÜRME", "%s/%s gaz-fren  ·  %s/%s direksiyon  ·  %s el freni\n%s iç kamera  ·  %s radyo  ·  %s farlar  ·  %s in" % [_k("move_forward"), _k("move_back"), _k("move_left"), _k("move_right"), _k("jump"), _k("fps_view"), _k("radio"), _k("headlights"), f]]
		"radio":
			return ["RADYO", "%s ile istasyon değiştir.\nSürerken müzik keyfi!" % ("Radyo düğmesiyle" if _touch else _k("radio") + " tuşu")]
		"passenger":
			return ["YOLCU KAMERASI", "%s ile iç ve dış kamera arasında geçiş yap.\nİnmek için %s." % [("Kamera düğmesi" if _touch else _k("fps_view")), ("in düğmesi" if _touch else f)]]
		"metro":
			return ["METRO", "Girişte " + press + ", gideceğin istasyonu seç.\nYolculukta manzarayı izleyebilirsin."]
		"shop":
			return ["MARKET VE DÜKKÂNLAR", "İçeride sepet al, rafların yanında " + press + " ve ürünleri sepete koy.\nKasada öde, sonra çıkışa yürü."]
		"basket":
			return ["ALIŞVERİŞ SEPETİ", "Her ürün sepete eklenir. Kasaya gidip öde.\nÖdemeden çıkamazsın. Aldıklarını telefondan kullanabilirsin."]
		"phone":
			return ["TELEFON", "Mesajlar, harita, iş bul, taksi, araba çağır ve daha fazlası burada.\nKapatmak için %s." % ("geri düğmesi" if _touch else "ESC")]
		"map":
			return ["HARİTA", "Bir yere %s: yol tarifi başlar, mini haritada rota görünür.\n%s ile kapat." % [("dokun" if _touch else "tıkla"), ("Kapat düğmesi" if _touch else _k("map") + " veya ESC")]]
		"job":
			return ["İŞLER", "İşi tamamla, süre dolmadan teslim et: para ve görev ilerlemesi kazanırsın.\nİşi bırakmak için %s." % ("telefondan İş Bul" if _touch else _k("jobs") + " tuşu")]
		"leash":
			return ["TASMA", "%s ile tasmayı tak ya da çıkar.\nTasmalıyken hayvanın seni takip eder, trafikte güvende kalır." % ("Komutlar menüsü" if _touch else _k("leash") + " tuşu")]
		"train":
			return ["NUMARA EĞİTİMİ", "%s ile eğitim menüsü açılır. Hayvanına oturma, pati gibi numaralar öğret.\nÖğrendikçe komut verebilirsin." % ("Telefon > Eğitim" if _touch else _k("train") + " tuşu")]
		"rain":
			return ["YAĞMUR", "%s ile şemsiyeni aç. Hayvanların ıslanınca kirlenir.\nBir çatının altına sığınmak da işe yarar." % ("Şemsiye düğmesi" if _touch else _k("umbrella") + " tuşu")]
		"fuel_low":
			return ["YAKIT AZALDI", "Depo bitmek üzere. Benzin istasyonunda pompanın yanında dur ve %s." % ("düğmeye dokun" if _touch else f + " ile yakıt al")]
		"police":
			return ["POLİS KOVALAMACASI", "Kural ihlali yaptın! Hızını kes, kenara çek ve dur.\nKaçmak cezayı ve yıldızı artırır."]
		"atm":
			return ["ATM", "Para yatır, çek ve faturaları ödeyebilirsin.\nBakiyeni telefondaki Banka uygulamasında da görürsün."]
		"bill":
			return ["FATURALAR", "Faturaları süresi dolmadan öde, yoksa elektrik kesilir.\nATM'den ya da telefondaki Faturalar uygulamasından öde."]
		"neighbor":
			return ["KOMŞULARLA SOHBET", "Konuştukça dostluk kalpleri artar, küçük görevler ve hediyeler gelir.\nSık sık uğra."]
		"tea":
			return ["ÇAY BAHÇESİ", "Tabureye otur, çay iç, dinlen. Kalkmak için yürümen yeterli.\nOturmak keyif ve enerji verir."]
		"sleep":
			return ["UYKU", "Yatakta uyuyabilirsin. Uyku enerjini doldurur ve zamanı ilerletir.\nYorgunken hızın düşer."]
		"shelter":
			return ["BARINAK", "Yeni dostlar burada sahip arıyor. Birini seç ve evlat edin.\nBağış yaparak barınağa destek olabilirsin."]
		"dealer":
			return ["ARAÇ GALERİSİ", "Modelleri incele, fiyatını gör ve satın al.\nAldığın araç garajına gelir."]
		"hotel":
			return ["OTEL", "Resepsiyondan oda kirala, asansörle odana çık.\nOdada uyu, televizyon izle, oda servisi iste."]
		"boat":
			return ["GÖL TURU", "İskeleden tekne turu ya da pedallı bot kirala.\nBotu %s ile yönlendir." % ("sol çubuk" if _touch else move)]
		"football":
			return ["FUTBOL", "Topun yanında " + press + " ve şut çek.\nMaça katılıp 5 dakikada en çok golü atmaya çalış."]
		"basketball":
			return ["BASKET", "Çubuk yeşil bölgeye gelince bırak, top potaya gider.\nUzaklaştıkça yeşil bölge daralır, rekor kır!"]
		"eatery":
			return ["LOKANTA", "Masaya otur, garsonu çağır, menüden sipariş ver.\nYemek gelince ye, hesabı öde, hayvanına da bir şey iste."]
		"icecream":
			return ["DONDURMA", "Dondurma al, hayvanını sevindir.\nSıcak günlerde keyfin yerine gelir."]
	return []


## Bir kimlik daha once gosterilmediyse (ve ipuclari aciksa) kuyruga al / goster.
func show_once(id: String, force := false) -> void:
	if state == null or m == null:
		return
	if not force:
		if not enabled() or _seen().has(id) or id in _queue or id == _showing:
			return
	if texts(id).is_empty():
		return
	if force:
		_queue.clear()
		_display(id, true)
		return
	_queue.append(id)
	if _showing == "":
		_pop()


func _pop() -> void:
	while not _queue.is_empty():
		var id: String = _queue.pop_front()
		if _seen().has(id) or not enabled():
			continue
		_display(id, false)
		return


func _build() -> void:
	if _card != null or m.ui == null or m.ui.hud == null:
		return
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.9)
	sb.border_color = m.ui.ACCENT
	sb.border_width_left = 8
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 22
	sb.content_margin_right = 26
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_size = 10
	sb.shadow_color = Color(0, 0, 0, 0.4)
	_card.add_theme_stylebox_override("panel", sb)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	_card.add_child(v)
	_title = m.ui._fx_label(v, "", m.ui.F_TITLE, 40, m.ui.ACCENT, 6)
	_body = m.ui._fx_label(v, "", m.ui.F_BODY, 24, Color(1, 1, 1, 0.92), 4)
	_card.visible = false
	_card.z_index = 60
	m.ui.hud.add_child(_card)


func _display(id: String, force: bool) -> void:
	_build()
	if _card == null:
		return
	var tx := texts(id)
	if not force:
		_seen()[id] = true
		state.save_game()
	_showing = id
	_t = 0.0
	_title.text = tx[0]
	_body.text = tx[1]
	_card.reset_size()
	_card.visible = true
	_card.modulate.a = 0.0
	_force = force
	_place()
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.35)


func _place() -> void:
	var vs: Vector2 = m.ui.hud.size
	_card.reset_size()
	_card.position = Vector2((vs.x - _card.size.x) * 0.5, vs.y - _card.size.y - (230.0 if _touch else 120.0))


func _hide() -> void:
	if _card == null or _showing == "":
		return
	_showing = ""
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if _showing == "":
			_card.visible = false)
	_t = -0.6      # kisa ara, sonraki kart


func _input(e: InputEvent) -> void:
	if _showing != "" and _t > 2.5 and e is InputEventKey and e.pressed and not e.echo:
		_hide()


static func id_of_cmd(cmd: String) -> String:
	if cmd == "":
		return ""
	if cmd in ["drive", "taxi"]:
		return "car_near"
	if cmd == "metro":
		return "metro"
	if cmd == "shop_in":
		return "shop"
	if cmd == "shop_basket" or cmd.begins_with("shop_take:"):
		return "basket"
	if cmd == "atm":
		return "atm"
	if cmd == "bills_app":
		return "bill"
	if cmd.begins_with("nb_"):
		return "neighbor"
	if cmd == "leash":
		return "leash"
	if cmd == "train" or cmd.begins_with("train:"):
		return "train"
	if cmd.begins_with("shelter"):
		return "shelter"
	if cmd == "dealer":
		return "dealer"
	if cmd == "htl_in":
		return "hotel"
	if cmd.begins_with("htl_bed") or cmd == "htl_homebed" or cmd in ["sleep", "nap", "bed"]:
		return "sleep"
	if cmd.begins_with("boat_menu"):
		return "boat"
	if cmd.begins_with("food_"):
		return "tea"
	if cmd.begins_with("eat_"):
		return "eatery"
	if cmd in ["sp_kick", "sp_match"]:
		return "football"
	if cmd in ["sp_bshoot", "sp_contest"]:
		return "basketball"
	if cmd == "icecream":
		return "icecream"
	return ""


## main._on_command basinda cagrilir.
func on_command(cmd: String) -> void:
	var id := id_of_cmd(cmd)
	if id != "" and id != "car_near":
		show_once(id)


func update(dt: float) -> void:
	if m == null or not m._ready_done or m._mode != "play":
		return
	var dbg: bool = m._args.has("tutorial")
	if not _started:
		_start_wait += dt
		if dbg:
			_started = true
		elif _start_wait > 2.0:
			_started = true
			show_once("start")
	if _showing != "":
		_t += dt
		if _card != null:
			_place()
		if _t > 8.0 and not _force:
			_hide()
	elif _t < 0.0:
		_t += dt
	elif not _queue.is_empty():
		_pop()
	var riding: bool = m._ride != null
	if riding:
		_drive_time += dt
		if _drive_time > 12.0 and not dbg:
			show_once("radio")
	else:
		_drive_time = 0.0
	if riding and not _was_ride and not dbg:
		show_once("drive")
	_was_ride = riding
	if dbg:
		return
	_poll -= dt
	if _poll > 0.0:
		return
	_poll = 0.3
	var cmd: String = m.ui._context_cmd
	if cmd != _last_cmd:
		_last_cmd = cmd
		var id := id_of_cmd(cmd)
		if id != "":
			show_once(id)
	if m._taxi != null or m._bus_ride != null:
		show_once("passenger")
	if m.weather != null and not m.weather.indoor and not riding and m.weather.rain > 0.25:
		show_once("rain")
	if riding and m.fuel != null:
		var kind: String = m._ride.get_meta("kind", "")
		if m.fuel.uses_fuel(kind) and m.fuel.frac(kind) < 0.2:
			show_once("fuel_low")
	if m.traffic != null and m.traffic.chasing:
		show_once("police")
	if m.bank != null and m.bank.unpaid().size() > 0:
		show_once("bill")
