extends Node
## Komsular ve telefon mesajlari.
## Evin (main.HOME_DOOR) onunde gunun saatine gore dort komsu durur: Kapici Hasan Efendi (supurge),
## bankta Ayse Teyze, kedisi Tekir'le Komsu Mert, cicek sulayan Fatma Hanim. F ile kisa diyalog paneli
## acilir (2-3 cevap); her komsunun dostluk degeri state.d["friends"] icinde. Komsular gunde birer
## kucuk iyilik ister: Hasan Efendi paket teslimi, Ayse Teyze kopegi Paşa'yı gezdirme (main._start_dog_walk),
## Mert kayip kedi, Fatma Hanim cantadan Ekmek. Odul: para + dostluk.
## Mesajlar: telefonda "Mesajlar" uygulamasi (konusmalar, okunmamis sayisi, eylem dugmeleri: konuma git,
## is ilanlari...). Yeni mesajlar zamanla gelir (ust bant + ses). state.d["msgs"] icinde saklanir.

const Kit = preload("res://scripts/kit.gd")
const ParkMap = preload("res://scripts/park_map.gd")
const PersonModel = preload("res://scripts/person_model.gd")

# id: [ad, cinsiyet, tisort, pantolon, yan kayma, disari kayma, saat bas, saat son, renk]
const PEOPLE := {
	"hasan": ["Kapıcı Hasan Efendi", "erkek", "5a6b4a", "3b3b3b", 2.4, 2.0, 7.0, 22.0, "8a6a3a"],
	"ayse": ["Ayşe Teyze", "kadin", "8a5a8a", "4a3a4a", -4.2, 4.6, 9.0, 19.0, "b0559a"],
	"mert": ["Komşu Mert", "erkek", "3f6fb5", "2b2f38", 4.8, 5.2, 12.0, 23.5, "2f80ff"],
	"fatma": ["Fatma Hanım", "kadin", "4f8f5a", "3a3a46", -7.0, 1.3, 7.0, 11.5, "34a853"],
}
const CHAT := {
	"hasan": [["Hal hatır sor", "Şükür evladım, merdivenleri yeni sildim, basarken dikkat!"],
		["Apartmanda ne var ne yok?", "3 numaradakiler yine geç saatte matkap çaldırdı. Yönetici bey kızdı."]],
	"ayse": [["Hal hatır sor", "İyiyim yavrum, güneşlenip kuşlara bakıyorum. Sen nasılsın?"],
		["Paşa nasıl?", "Paşa'm yaşlandı ama gezmeye bayılır. Dizlerim olmasa her gün götürürdüm."]],
	"mert": [["Selam Mert!", "Eyvallah komşu! Tekir'le biraz hava alıyoruz."],
		["Tekir ne yiyor?", "Ton balıklı mamaya bayılıyor. Senin %s ile de anlaşırlar bence."]],
	"fatma": [["Çiçekler çok güzel olmuş", "Sağ ol canım, sardunyalar bu yıl coştu. Sabahları suluyorum."],
		["Nasılsınız?", "İyiyiz kuzum, torunlar hafta sonu gelecek, börek açacağım."]],
}
const MSG_SENDERS := {
	"annem": ["Annem", "e8453c"],
	"vet": ["Pati Veteriner Kliniği", "1e9a8a"],
	"is": ["Pati İş Ajansı", "34a853"],
	"hasan": ["Kapıcı Hasan Efendi", "8a6a3a"],
	"ayse": ["Ayşe Teyze", "b0559a"],
	"mert": ["Komşu Mert", "2f80ff"],
	"fatma": ["Fatma Hanım", "34a853"],
}
const MOM_LINES := [
	["%s yemek yedin mi? Aç kalma sakın.", ["Yedim anne, merak etme.", "Birazdan yiyeceğim."]],
	["Hafta sonu gelir misin? Dolma yaptım.", ["Gelirim anne!", "Bu hafta zor, sonra gelirim."]],
	["%s nasıl? Bana bir fotoğrafını at.", ["Çok iyi, birazdan atarım.", "Uyuyor şimdi :)"]],
	["Hava soğuyor, kalın giyin. Hasta olma.", ["Tamam anne.", "Montumu aldım."]],
	["Komşulara selam söyle, Hasan Efendi'yi de unutma.", ["Söylerim anne.", "Az önce gördüm onu."]],
]

var m: Node
var state: Node
var people := {}          # id -> {node, model, pos, face, prop}
var _near := ""
var _vis_t := 0.0
var force_all := false    # test: saatten bagimsiz hepsi dursun
var quest := {}           # aktif iyilik: {id, type, ...}
var _label: Label
var _banner: PanelContainer
var _banner_t := 0.0
var _origin := Vector2.ZERO
var mert_cat: Node3D
var _cat_home := Vector2.ZERO


# ---------------------------------------------------------------- durum

func _friends() -> Dictionary:
	if not state.d.has("friends") or typeof(state.d["friends"]) != TYPE_DICTIONARY:
		state.d["friends"] = {}
	return state.d["friends"]


func friend(id: String) -> int:
	return int(_friends().get(id, 10))


func _add_friend(id: String, n: int) -> void:
	_friends()[id] = clampi(friend(id) + n, 0, 100)


func _today() -> String:
	return Time.get_date_string_from_system()


func _done_today(id: String, what: String) -> bool:
	var dn: Dictionary = state.d.get("nb_done", {})
	return dn.get(id + ":" + what, "") == _today()


func _mark_today(id: String, what: String) -> void:
	var dn: Dictionary = state.d.get("nb_done", {})
	dn[id + ":" + what] = _today()
	state.d["nb_done"] = dn


func _md() -> Dictionary:
	var d: Dictionary = state.d
	if not d.has("msgs") or typeof(d["msgs"]) != TYPE_DICTIONARY:
		d["msgs"] = {}
	if not d.has("msg_next"):
		d["msg_t"] = 0.0
		d["msg_next"] = 45.0
	return d["msgs"]


# ---------------------------------------------------------------- kurulum

func build() -> void:
	if ParkMap.zone != "":
		return
	var door: Vector2 = m.HOME_DOOR
	var out: Vector2 = m.HOME_DOOR_OUT
	var side := Vector2(-out.y, out.x)
	_origin = door + out * 3.0
	for id in PEOPLE:
		var info: Array = PEOPLE[id]
		var p: Vector2 = door + side * float(info[4]) + out * float(info[5])
		var root := Node3D.new()
		root.name = "Komsu_" + id
		m.add_child(root)
		root.position = Vector3(p.x, ParkMap.walk_height(p), p.y)
		var v := PersonModel.new()
		v.kind = info[1]
		v.tint = Color(info[2])
		v.tint2 = Color(info[2])
		v.pants = Color(info[3])
		root.add_child(v)
		var face: Vector2 = door + out * 8.0
		var prop: Node3D = null
		match id:
			"ayse":
				_bench(root)
				v.seated = true
				v.position = Vector3(0, 0.0, 0)
				face = p + out
			"fatma":
				face = p - out
				_flowers(root, -out)
				prop = Node3D.new()
				v.hand.add_child(prop)
				Kit.cyl(prop, 0.07, 0.08, 0.16, Vector3(0, -0.08, 0.04), Kit.mat("3f9a5a", 0.5), 12)
				Kit.cyl(prop, 0.012, 0.016, 0.2, Vector3(0, -0.02, 0.15), Kit.mat("3f9a5a", 0.5), 8, Vector3(1.0, 0, 0))
			"hasan":
				prop = Node3D.new()
				v.hand.add_child(prop)
				Kit.cyl(prop, 0.014, 0.014, 1.2, Vector3(0, -0.35, 0), Kit.mat("8a6a3a", 0.8), 8)
				Kit.box(prop, Vector3(0.28, 0.12, 0.06), Vector3(0, -0.98, 0), Kit.mat("c9a64a", 0.9))
			"mert":
				face = door + out * 6.0 + side * 2.0
		_turn(root, face)
		people[id] = {"node": root, "model": v, "pos": p, "face": face}
	_cat_home = people["mert"]["pos"] + out * 1.2 + side * 0.6
	mert_cat = m._npc_pet("kedi", Color("d9a066"), 0.85)
	mert_cat.roam_center = _cat_home
	mert_cat.roam_radius = 1.2
	mert_cat.short_pause = false
	mert_cat.place(_cat_home)
	_md()
	_update_visible()


func _turn(n: Node3D, to: Vector2) -> void:
	var d := to - Vector2(n.position.x, n.position.z)
	if d.length() > 0.01:
		n.rotation.y = atan2(-d.x, -d.y)


func _bench(root: Node3D) -> void:
	var wood := Kit.mat("8a5a32", 0.8)
	var iron := Kit.mat("2b2b2b", 0.5)
	var b := Node3D.new()
	root.add_child(b)
	for i in 3:
		Kit.box(b, Vector3(1.6, 0.04, 0.12), Vector3(0, 0.44, -0.12 + i * 0.13), wood)
	for i in 2:
		Kit.box(b, Vector3(1.6, 0.1, 0.03), Vector3(0, 0.62 + i * 0.14, 0.18), wood, Vector3(-0.15, 0, 0))
	for sx in [-0.7, 0.7]:
		Kit.box(b, Vector3(0.05, 0.44, 0.42), Vector3(sx, 0.22, 0.02), iron)


func _flowers(root: Node3D, toward: Vector2) -> void:
	var f := Node3D.new()
	root.add_child(f)
	var dir := toward.normalized() * 0.75
	f.position = Vector3(dir.x, 0, dir.y)
	var pot := Kit.mat("b8603a", 0.8)
	var leaf := Kit.mat("3f7a3a", 0.8)
	var cols := ["e8453c", "f26fa0", "f2c230", "e8453c"]
	var side := Vector2(-toward.y, toward.x).normalized()
	for i in 4:
		var o: Vector2 = side * (-0.75 + i * 0.5)
		Kit.cyl(f, 0.15, 0.11, 0.28, Vector3(o.x, 0.14, o.y), pot, 12)
		Kit.ball(f, 0.17, Vector3(o.x, 0.36, o.y), leaf, Vector3(1, 0.7, 1), 8)
		for k in 4:
			var a := k * 1.57 + i
			Kit.ball(f, 0.05, Vector3(o.x + cos(a) * 0.09, 0.46, o.y + sin(a) * 0.09), Kit.mat(cols[i], 0.6), Vector3.ONE, 6)


func _present(id: String) -> bool:
	if force_all:
		return true
	var info: Array = PEOPLE[id]
	var h: float = m.clock
	if m.weather and m.weather.kind in ["yagmur", "saganak", "kar"] and id != "hasan":
		return false
	return h >= float(info[6]) and h < float(info[7])


func _update_visible() -> void:
	var outside: bool = ParkMap.home == null
	for id in people:
		var n: Node3D = people[id]["node"]
		var on: bool = outside and _present(id)
		if n.visible != on:
			n.visible = on
			n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if mert_cat and not (quest.get("type", "") == "cat"):
		mert_cat.visible = outside and people["mert"]["node"].visible


# ---------------------------------------------------------------- her kare

func update(dt: float) -> void:
	if people.is_empty() and _banner == null:
		_update_messages(dt)
		return
	_vis_t -= dt
	if _vis_t <= 0.0:
		_vis_t = 1.0
		_update_visible()
	_update_quest(dt)
	_update_messages(dt)


func context() -> Array:
	_near = ""
	if people.is_empty() or m._ride != null or ParkMap.home != null:
		return []
	var o: Vector2 = m._owner_pos()
	if o.distance_to(_origin) > 16.0:
		return []
	var best := 2.6
	for id in people:
		if people[id]["node"].visible:
			var d: float = o.distance_to(people[id]["pos"])
			if d < best:
				best = d
				_near = id
	if _near == "":
		return []
	var icon := "smile"
	if quest.get("id", "") == _near:
		icon = "check"
	return ["%s ile Konuş" % PEOPLE[_near][0], "nb_talk", icon]


func command(cmd: String) -> void:
	match cmd:
		"nb_talk":
			if _near != "":
				talk(_near)
		"nb_msgs":
			open_messages()


# ---------------------------------------------------------------- diyalog

func _hearts_text(id: String) -> String:
	var f := friend(id)
	var lvl := "Yabancı" if f < 20 else ("Tanıdık" if f < 45 else ("Dost" if f < 75 else "Can Dostu"))
	return "Dostluk: %d / 100 · %s" % [f, lvl]


func _greet(id: String) -> String:
	var h: float = m.clock
	var g := "Günaydın" if h < 11.0 else ("İyi akşamlar" if h >= 18.0 else "Merhaba")
	match id:
		"hasan":
			return "%s evladım! Kapı önü tertemiz, bak." % g
		"ayse":
			return "%s yavrum, gel otur biraz yanıma." % g
		"mert":
			return "%s komşu! N'aber?" % g
		_:
			return "%s kuzum, çiçeklere su veriyorum." % g


func talk(id: String) -> void:
	var ui: Node = m.ui
	var info: Array = PEOPLE[id]
	var pd: Dictionary = people[id]
	if not pd["model"].seated:
		_turn(pd["node"], m._owner_pos())
	m.owner_model.act("wave", 0.8)
	_voice(id)
	var line := _greet(id)
	var q_line := _quest_status_line(id)
	if q_line != "":
		line = q_line
	var body: VBoxContainer = ui._open_panel(info[0].to_upper(), "\"%s\"\n%s" % [line, _hearts_text(id)])
	# 1) sohbet
	var chats: Array = CHAT[id]
	var ch: Array = chats[(int(m.clock) + friend(id)) % chats.size()]
	ui._panel_item(body, ch[0], func(): _chat(id, ch))
	# 2) iyilik / gorev
	var fv: Array = _favor_option(id)
	if not fv.is_empty():
		ui._panel_item(body, fv[0], fv[1])
	ui._panel_item(body, "Hoşça kal", func():
		ui.close_modal()
		m._say(pd["node"], "Güle güle!"))
	ui._focus_first(body)


func _chat(id: String, ch: Array) -> void:
	var txt: String = ch[1]
	if txt.contains("%s"):
		txt = txt % state.pet(state.d["active"])["name"]
	m.ui.close_modal()
	m._say(people[id]["node"], txt.substr(0, 46) + ("…" if txt.length() > 46 else ""))
	m.ui.toast("%s: \"%s\"" % [PEOPLE[id][0], txt])
	if not _done_today(id, "chat"):
		_mark_today(id, "chat")
		_add_friend(id, 3)
		m.ui.toast("%s ile dostluğun arttı (+3)." % PEOPLE[id][0])
		state.save_game()


func _quest_status_line(id: String) -> String:
	if quest.get("id", "") != id:
		return ""
	match quest["type"]:
		"bread":
			return "Ekmeği getirdin mi kuzum?" if _bag_has("Ekmek") else "Marketten bir ekmek alıverirsen çok sevinirim."
		"cat":
			return "Tekir'i bulabildin mi? Çok merak ediyorum." if not quest.get("found", false) else "Tekir! Buldun mu onu? Gel buraya oğlum!"
		"parcel":
			return "Paketi %s adresine bıraktın mı evladım?" % quest["addr"]
	return ""


func _bag_has(item: String) -> bool:
	var bag: Dictionary = state.d.get("bag", {})
	return int(bag.get(item, 0)) > 0


## [dugme yazisi, Callable] ya da bos
func _favor_option(id: String) -> Array:
	var ui: Node = m.ui
	if quest.get("id", "") == id:
		if quest["type"] == "bread" and _bag_has("Ekmek"):
			return ["Ekmeği ver", func(): _finish("Allah razı olsun kuzum, buyur bu da senin harçlığın.")]
		if quest["type"] == "cat" and quest.get("found", false) and _cat_close():
			return ["Tekir'i teslim et", func(): _finish("Tekir! Seni yaramaz! Komşu, sana borçluyum, al şunu.")]
		return ["Vazgeç (iyiliği bırak)", func():
			_cancel_quest("Peki, önemli değil.")
			ui.close_modal()]
	if _done_today(id, "favor"):
		return []
	match id:
		"hasan":
			return ["Yardım lazım mı?", func(): _offer(id, "Şu kargo paketi yanlışlıkla bize gelmiş. Sahibine bırakıverir misin evladım?", "parcel")]
		"ayse":
			return ["Paşa'yı gezdireyim mi?", func(): _offer(id, "Ah ne iyi olur! Paşa'yı parka götürüp getirir misin? Dizlerim tutmuyor.", "dog")]
		"mert":
			return ["Tekir nerede?", func(): _offer(id, "Abi Tekir sabah kaçtı, mahallede bir yerde. Bulursan çok sevinirim!", "cat")]
		"fatma":
			if _bag_has("Ekmek"):
				return ["Ekmek lazım mı? (Çantada var)", func():
					quest = {"id": id, "type": "bread", "t": 600.0}
					_finish("Aa tam da ekmeğim bitmişti! Sağ ol kuzum.")]
			return ["Bir ihtiyacınız var mı?", func(): _offer(id, "Ekmeğim bitti kuzum, marketten bir ekmek alıverir misin?", "bread")]
	return []


func _offer(id: String, text: String, type: String) -> void:
	var ui: Node = m.ui
	var body: VBoxContainer = ui._open_panel(PEOPLE[id][0].to_upper(), "\"%s\"" % text)
	ui._panel_item(body, "Tabii, hallederim", func(): _accept(id, type))
	ui._panel_item(body, "Şimdi olmaz, sonra", func():
		ui.close_modal()
		m._say(people[id]["node"], "Tamam, sonra olur."))
	ui._focus_first(body)


func _accept(id: String, type: String) -> void:
	var ui: Node = m.ui
	ui.close_modal()
	if not quest.is_empty():
		_cancel_quest("")
	match type:
		"dog":
			if not m._job.is_empty():
				ui.toast("Önce elindeki işi bitir.")
				return
			var pos: Vector2 = people[id]["pos"]
			m._start_dog_walk("Ayşe Teyze", "Paşa", pos)
			m._job["neighbor"] = id
			m._job["pay"] = 35
			quest = {"id": id, "type": "dog", "t": 300.0}
			m._say(people[id]["node"], "Paşa, uslu dur!")
		"bread":
			quest = {"id": id, "type": "bread", "t": 900.0}
			var best := Vector2.INF
			for sp in m.world.shop_spots:
				if sp.get("kind", "") == "market":
					if best == Vector2.INF or (sp["pos"] as Vector2).distance_to(m._owner_pos()) < best.distance_to(m._owner_pos()):
						best = sp["pos"]
			if best != Vector2.INF:
				m._set_nav(best, "Market")
			ui.toast("Marketten Ekmek al, Fatma Hanım'a getir.")
		"cat":
			var dd: Array = m._random_door(50.0, 140.0)
			var p: Vector2 = dd[0] if not dd.is_empty() else m._owner_pos() + Vector2(60, 20)
			p = m.world.resolve(p, 0.4, p)
			quest = {"id": id, "type": "cat", "t": 600.0, "pos": p, "found": false}
			mert_cat.follow = null
			mert_cat.roam_center = p
			mert_cat.roam_radius = 2.0
			mert_cat.place(p)
			mert_cat.visible = true
			m._set_nav(p, "Tekir (son görülen yer)")
			ui.toast("Tekir en son %s civarında görülmüş. Haritada işaretli." % (dd[1] if not dd.is_empty() else "yakınlarda"))
		"parcel":
			var dd2: Array = m._random_door(70.0, 200.0)
			if dd2.is_empty():
				ui.toast("Paketin adresi okunmuyor, sonra bakarız.")
				return
			quest = {"id": id, "type": "parcel", "t": 480.0, "target": dd2[0], "addr": dd2[1]}
			m._set_nav(dd2[0], dd2[1])
			_parcel(true)
			ui.toast("Paketi %s adresine bırak." % dd2[1])
	_mark_today(id, "favor")
	state.save_game()


func _parcel(on: bool) -> void:
	if quest.has("box") and is_instance_valid(quest["box"]):
		quest["box"].queue_free()
		quest.erase("box")
	if on:
		var b := Node3D.new()
		m.owner_model.hand.add_child(b)
		Kit.box(b, Vector3(0.26, 0.18, 0.2), Vector3(0, -0.06, 0.06), Kit.mat("c9a070", 0.9))
		Kit.box(b, Vector3(0.27, 0.03, 0.05), Vector3(0, 0.035, 0.06), Kit.mat("e8d6b0", 0.6))
		quest["box"] = b


func _cat_close() -> bool:
	return mert_cat != null and Vector2(mert_cat.position.x, mert_cat.position.z).distance_to(m._owner_pos()) < 6.0


func _reward(id: String) -> int:
	return {"hasan": 30, "ayse": 35, "mert": 45, "fatma": 25}.get(id, 25)


func _finish(text: String) -> void:
	var id: String = quest.get("id", "")
	if id == "":
		return
	var type: String = quest["type"]
	if type == "bread":
		var bag: Dictionary = state.d.get("bag", {})
		bag["Ekmek"] = int(bag.get("Ekmek", 0)) - 1
		if int(bag["Ekmek"]) <= 0:
			bag.erase("Ekmek")
	if type == "cat":
		_return_cat()
	_parcel(false)
	quest = {}
	var pay := _reward(id)
	if type != "dog":
		state.d["coins"] += pay
	_add_friend(id, 12)
	state.count("neighbor")
	state.changed.emit()
	state.save_game()
	m._nav = Vector2.INF
	m.minimap.route = []
	if m.ui.is_blocking():
		m.ui.close_modal()
	if is_instance_valid(people[id]["node"]):
		m._say(people[id]["node"], "Sağ ol!")
		m._hearts(people[id]["node"].position)
	m._sfx("para", -4.0)
	m.ui.toast("%s: \"%s\"%s" % [PEOPLE[id][0], text, ("  +%d ₺" % pay) if type != "dog" else ""])
	m.ui.toast("%s ile dostluğun arttı (+12)." % PEOPLE[id][0])
	var thanks := {"hasan": "Paketi bırakmışsın, sahibi aradı teşekkür etti. Eline sağlık evladım.",
		"ayse": "Paşa eve gelince mışıl mışıl uyudu. Sana kurabiye ayırdım yavrum.",
		"mert": "Tekir şimdi koltukta horluyor :) Bir daha kaçarsa seni ararım komşu!",
		"fatma": "Ekmek için sağ ol kuzum, akşam börek yapınca kapını çalacağım."}
	get_tree().create_timer(25.0).timeout.connect(func(): push_msg(id, thanks[id]))


func _cancel_quest(text: String) -> void:
	if quest.is_empty():
		return
	var id: String = quest["id"]
	if quest["type"] == "cat":
		_return_cat()
	if quest["type"] == "dog" and not m._job.is_empty() and m._job.get("neighbor", "") == id:
		m._end_job(false, "Paşa'yı Ayşe Teyze'ye bıraktın.")
	_parcel(false)
	quest = {}
	m._nav = Vector2.INF
	m.minimap.route = []
	if text != "":
		m.ui.toast("%s: \"%s\"" % [PEOPLE[id][0], text])


func _return_cat() -> void:
	mert_cat.follow = null
	mert_cat.roam_center = _cat_home
	mert_cat.roam_radius = 1.2
	mert_cat.place(_cat_home)


## Kopek gezdirme isi bittiginde main._end_job cagirir.
func on_job_done(id: String, ok: bool) -> void:
	if quest.get("id", "") != id or quest.get("type", "") != "dog":
		return
	if ok:
		_finish("Paşa'm ne kadar mutlu olmuş! Allah razı olsun yavrum.")
	else:
		quest = {}


func _update_quest(dt: float) -> void:
	if _label == null and m.ui and m.ui.hud:
		_label = m.ui._fx_label(m.ui.hud, "", m.ui.F_BODY, 24, Color("ffd36b"), 7)
		_label.position = Vector2(26, 140)
		_label.size = Vector2(760, 36)
	if _label:
		_label.visible = not quest.is_empty() and quest["type"] != "dog" and m.ui.hud.visible
	if quest.is_empty():
		return
	quest["t"] -= dt
	var me: Vector2 = m._owner_pos()
	var nm: String = PEOPLE[quest["id"]][0]
	match quest["type"]:
		"bread":
			_label.text = "♥  %s: Ekmek götür%s" % [nm, "  ·  Çantanda var, eve dön" if _bag_has("Ekmek") else "  ·  Marketten al"]
			if _bag_has("Ekmek") and not quest.get("nav_home", false):
				quest["nav_home"] = true
				m._set_nav(people["fatma"]["pos"], nm)
		"cat":
			if not quest["found"]:
				_label.text = "♥  %s: Kayıp Tekir'i bul" % nm
				if me.distance_to(Vector2(mert_cat.position.x, mert_cat.position.z)) < 3.5:
					quest["found"] = true
					mert_cat.follow = m.owner_node
					m._sfx("miyav2", -4.0)
					m.ui.toast("Tekir'i buldun! Seni takip ediyor. Mert'e geri götür.")
					m._set_nav(people["mert"]["pos"], nm)
			else:
				_label.text = "♥  %s: Tekir'i Mert'e götür" % nm
		"parcel":
			_label.text = "♥  %s: Paketi bırak · %s" % [nm, quest["addr"]]
			if me.distance_to(quest["target"]) < 5.0:
				_finish("Paketi bırakmışsın, aferin evladım.")
				return
	if not quest.is_empty() and quest["t"] <= 0.0 and quest["type"] != "dog":
		_cancel_quest("Boş ver, ben hallettim.")


func _voice(id: String) -> void:
	var key := "komsu_" + id
	if m._sounds.has(key) and not _done_today(id, "voice"):
		_mark_today(id, "voice")
		m._sfx(key, -2.0)


# ---------------------------------------------------------------- mesajlar

func _child() -> String:
	return "Kızım" if state.d.get("owner", "kadin") == "kadin" else "Oğlum"


func unread() -> int:
	var n := 0
	var md := _md()
	for k in md:
		n += int(md[k].get("unread", 0))
	return n


## Yeni mesaj. act: "" | "nav:x,z:Ad" | "jobs" | "vet" | "home" ; replies: hizli cevaplar
func push_msg(from: String, text: String, act := "", replies: Array = [], quiet := false) -> void:
	var md := _md()
	if not md.has(from):
		var s: Array = MSG_SENDERS.get(from, [from, "777777"])
		md[from] = {"name": s[0], "col": s[1], "items": [], "unread": 0, "order": 0}
	var th: Dictionary = md[from]
	var clk: String = m.ui.clock_label.text if m.ui and m.ui.clock_label else ""
	th["items"].append({"me": false, "t": text, "c": clk, "act": act, "r": replies})
	while th["items"].size() > 14:
		th["items"].pop_front()
	th["unread"] = int(th["unread"]) + 1
	th["order"] = Time.get_unix_time_from_system()
	if not quiet:
		_show_banner(th["name"], text)
		m._sfx("tik", -3.0, 1.7)
		get_tree().create_timer(0.14).timeout.connect(func(): m._sfx("tik", -3.0, 2.1))


func _update_messages(dt: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= dt
		if _banner_t <= 0.0 and _banner:
			var tw := create_tween()
			tw.tween_property(_banner, "modulate:a", 0.0, 0.4)
			tw.tween_callback(func(): _banner.visible = false)
	if m._mode != "play":
		return
	var d: Dictionary = state.d
	_md()
	d["msg_t"] = float(d["msg_t"]) + dt
	if float(d["msg_t"]) >= float(d["msg_next"]):
		d["msg_t"] = 0.0
		d["msg_next"] = randf_range(160.0, 320.0)
		_random_msg()


func _random_msg() -> void:
	var pet: Dictionary = state.pet(state.d["active"])
	# Asi hatirlatmasi: eksik asi varsa gunde bir kez
	var vac: Dictionary = pet.get("vaccines", {})
	if vac.size() < 3 and state.d.get("msg_vet_day", "") != _today() and m.world.vet_pos != Vector2.INF:
		state.d["msg_vet_day"] = _today()
		var miss: Array = []
		for vn in ["Kuduz", "Karma", "İç-Dış Parazit"]:
			if not vac.has(vn):
				miss.append(vn)
		push_msg("vet", "Sayın hasta sahibi, %s için %s aşısının zamanı geldi. Kliniğimizde randevusuz bekleriz." % [pet["name"], ", ".join(miss)], "vet", ["Bugün gelirim.", "Hatırlattığınız için sağ olun."])
		return
	var r := randi() % 4
	if r == 0:
		var ml: Array = MOM_LINES[randi() % MOM_LINES.size()]
		var t: String = ml[0]
		if t.begins_with("%s yemek"):
			t = t % _child()
		elif t.contains("%s"):
			t = t % pet["name"]
		push_msg("annem", t, "", ml[1])
	elif r == 1:
		push_msg("is", "Yeni ilan: Keçiören'de köpek gezdirme ve kurye işleri var. Hemen başlayabilirsin, 40-60 ₺.", "jobs", ["Bakarım, teşekkürler."])
	else:
		var ids: Array = PEOPLE.keys()
		var id: String = ids[randi() % ids.size()]
		var lines := {"hasan": "Evladım apartman aidatını yöneticiye vermeyi unutma. Bir de kapı önüne uğra, sana sorum var.",
			"ayse": "Yavrum bugün bankta olacağım, uğrarsan Paşa çok sevinir.",
			"mert": "Komşu akşam maç var, bizde izleyelim mi? Tekir de seni özledi.",
			"fatma": "Kuzum çiçeklerden çelik ayırdım, kapı önünden alabilirsin."}
		push_msg(id, lines[id], "home", ["Uğrarım!", "Tamam, haber veririm."])


func _show_banner(who: String, text: String) -> void:
	if m.ui == null or m.ui.hud == null:
		return
	if _banner == null:
		_banner = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.06, 0.08, 0.92)
		sb.set_corner_radius_all(18)
		sb.border_width_left = 6
		sb.border_color = m.ui.ACCENT2
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 10
		_banner.add_theme_stylebox_override("panel", sb)
		_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_banner.offset_left = -330
		_banner.offset_right = 330
		_banner.offset_top = 18
		_banner.mouse_filter = Control.MOUSE_FILTER_STOP
		_banner.gui_input.connect(func(e):
			if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed and not m.ui.is_blocking():
				open_messages())
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		_banner.add_child(col)
		m.ui._fx_label(col, "", m.ui.F_BODY, 22, m.ui.ACCENT).name = "Who"
		var tl: Label = m.ui._fx_label(col, "", m.ui.F_BODY, 20, Color.WHITE)
		tl.name = "Text"
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(620, 0)
		m.ui.hud.add_child(_banner)
	var col2: Node = _banner.get_child(0)
	(col2.get_node("Who") as Label).text = "MESAJLAR · " + who
	(col2.get_node("Text") as Label).text = text.substr(0, 110) + ("…" if text.length() > 110 else "")
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner_t = 4.5


func _sorted_threads() -> Array:
	var md := _md()
	var ks: Array = md.keys()
	ks.sort_custom(func(a, b): return float(md[a].get("order", 0)) > float(md[b].get("order", 0)))
	return ks


func open_messages() -> void:
	var ui: Node = m.ui
	var md := _md()
	var n := unread()
	var body: VBoxContainer = ui._open_panel("MESAJLAR", ("%d okunmamış mesaj" % n) if n > 0 else "Tüm mesajlar okundu.")
	if md.is_empty():
		ui._fx_label(body, "Henüz mesaj yok.", ui.F_BODY, 22, Color(1, 1, 1, 0.7))
	var ks := _sorted_threads()
	for i in mini(ks.size(), 7):
		var k: String = ks[i]
		var th: Dictionary = md[k]
		var last: Dictionary = th["items"][-1] if not th["items"].is_empty() else {"t": ""}
		var un := int(th.get("unread", 0))
		var pre := ("● (%d) " % un) if un > 0 else ""
		var line: String = "%s%s: %s" % [pre, th["name"], last["t"]]
		line = line.substr(0, 36) + ("…" if line.length() > 36 else "")
		var b: Button = ui._panel_item(body, line, func(): open_thread(k))
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 22)
		if un > 0:
			b.add_theme_color_override("font_color", Color(th["col"]).lightened(0.35))
	ui._panel_item(body, "Kapat", func(): ui.close_modal())
	ui._focus_first(body)


func open_thread(k: String) -> void:
	var ui: Node = m.ui
	var th: Dictionary = _md()[k]
	th["unread"] = 0
	var body: VBoxContainer = ui._open_panel(String(th["name"]).to_upper(), "Konuşma")
	var items: Array = th["items"]
	for i in range(maxi(items.size() - 5, 0), items.size()):
		var it: Dictionary = items[i]
		var row := HBoxContainer.new()
		body.add_child(row)
		var bubble := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("2f80ff") if it["me"] else Color(0.18, 0.18, 0.22, 0.95)
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 5
		sb.content_margin_bottom = 6
		bubble.add_theme_stylebox_override("panel", sb)
		var l: Label = ui._fx_label(bubble, "%s  %s" % [it["t"], it.get("c", "")], ui.F_BODY, 19, Color.WHITE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(330, 0)
		if it["me"]:
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(sp)
		row.add_child(bubble)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		body.add_child(gap)
	var last: Dictionary = items[-1] if not items.is_empty() else {}
	if not last.is_empty() and not last["me"]:
		var act: String = last.get("act", "")
		if act != "":
			ui._panel_item(body, _act_label(act), func(): _do_act(act))
		for rp in last.get("r", []):
			var rtxt: String = rp
			ui._panel_item(body, "Cevapla: " + rtxt, func():
				var clk: String = ui.clock_label.text if ui.clock_label else ""
				items.append({"me": true, "t": rtxt, "c": clk, "act": "", "r": []})
				if PEOPLE.has(k) and not _done_today(k, "msg"):
					_mark_today(k, "msg")
					_add_friend(k, 2)
				state.save_game()
				open_thread(k))
	ui._panel_item(body, "Geri", func(): open_messages())
	ui._focus_first(body)
	state.save_game()


func _act_label(act: String) -> String:
	if act.begins_with("nav:"):
		return "Konuma Git"
	return {"jobs": "İş İlanlarını Aç", "vet": "Veterinere Yol Tarifi", "home": "Apartmana Git (Konuma git)"}.get(act, "Aç")


func _do_act(act: String) -> void:
	m.ui.close_modal()
	if act.begins_with("nav:"):
		var parts := act.split(":")
		var xy := parts[1].split(",")
		m._set_nav(Vector2(float(xy[0]), float(xy[1])), parts[2] if parts.size() > 2 else "")
		m.ui.toast("Konum haritada işaretlendi.")
	elif act == "jobs":
		m._open_jobs()
	elif act == "vet":
		if m.world.vet_pos != Vector2.INF:
			m._set_nav(m.world.vet_pos, "Veteriner")
			m.ui.toast("Veteriner haritada işaretlendi.")
	elif act == "home":
		m._set_nav(m.HOME_DOOR, "Evim")
		m.ui.toast("Apartmanın kapısı haritada işaretlendi.")


# ---------------------------------------------------------------- test

func debug_neighbors() -> void:
	force_all = true
	_update_visible()
	if people.is_empty():
		return
	var a: Vector2 = people["ayse"]["pos"]
	var out: Vector2 = m.HOME_DOOR_OUT
	m._place_owner(a + out * 1.6 + Vector2(-out.y, out.x) * 0.6)
	m._focus = m.owner_node.position
	_near = "ayse"
	talk("ayse")


func debug_msgs() -> void:
	push_msg("annem", "%s yemek yedin mi? Aç kalma sakın." % _child(), "", ["Yedim anne, merak etme."], true)
	push_msg("vet", "Sayın hasta sahibi, %s için Kuduz aşısının zamanı geldi." % state.pet(state.d["active"])["name"], "vet", [], true)
	push_msg("is", "Yeni ilan: Keçiören'de köpek gezdirme işi var, 40-60 ₺.", "jobs", [], true)
	push_msg("ayse", "Yavrum bugün bankta olacağım, uğrarsan Paşa çok sevinir.", "home", ["Uğrarım!", "Tamam, haber veririm."])
	open_messages()
