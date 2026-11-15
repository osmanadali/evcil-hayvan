extends Node
## Patigram: telefondaki sosyal medya uygulamasi. Fotograf modunda cekilen her fotograf otomatik
## paylasilir; begeni ve yorumlar zamanla birikir (hayvanin keyfi, kiyafet, mekan cesitliligi,
## numaralar ve gunluk etiket begeniyi etkiler). Takipci esiklerinde odul verilir.
## Altta uydurma hesaplarin hayvan paylasimlari (gunluk, tohumlu) listelenir.

const ParkMap = preload("res://scripts/park_map.gd")

const MILESTONES := [[10, 30, ""], [25, 50, "odul"], [50, 100, ""], [100, 180, "konserve"], [250, 350, "odul"], [500, 700, ""]]
const TAGS := ["#bugünparkta", "#patilidost", "#gezintidekiler", "#miniaslan"]
const COMMENTS := [
	"Çok tatlı!", "Bayıldım, bu kareyi kaydettim.", "Patileri öpülesi!", "Hangi parktı burası?",
	"Aynı bizim Fındık gibi :)", "Kıyafet harika, nereden aldın?", "Ankara'nın en şanslı hayvanı.",
	"Mükemmel poz!", "Günümün fotoğrafı bu oldu.", "Pofuduk pofuduk", "Işık da çok güzel.",
	"Yarın biz de oraya gideceğiz!", "Hayranlık verici...", "Bu bakışa dayanılmaz.",
]
const NPC_NAMES := ["fındık_ve_ben", "kedi.hanım", "çubuk.gezgini", "pati_ankara", "mısır.kuyruk", "gölbaşı.pati", "tombik_tarçın", "kızılay.kaşif"]
const NPC_PETS := ["Fındık", "Tarçın", "Duman", "Pamuk", "Karamel", "Zeytin", "Maviş", "Bulut"]
const NPC_CAPTIONS := [
	"%s bugün parkta çok enerjikti!", "%s güneşin tadını çıkarıyor.", "Akşam yürüyüşü: %s mutlu.",
	"%s yeni oyuncağını çok sevdi.", "Bu bakışa kim dayanabilir? %s", "%s ve ben, Keçiören sokaklarında.",
	"Uykucu %s yine iş başında.", "%s için en güzel gün oldu.",
]

var m: Node
var state: Node
var _park_boxes: Array = []
var _thumbs := {}
var _tick := 0.0


func _d() -> Dictionary:
	var d: Dictionary = state.d
	if not d.has("pg") or typeof(d["pg"]) != TYPE_DICTIONARY:
		d["pg"] = {"posts": [], "claimed": [], "bonus_day": ""}
	return d["pg"]


func followers() -> int:
	var f := 3
	for p in _d()["posts"]:
		f += int(float(p["likes"]) / 5.0)
	return f


func _in_park(p: Vector2) -> bool:
	if _park_boxes.is_empty():
		for pk in ParkMap.data.get("parks", []):
			var poly: PackedVector2Array = ParkMap.to_poly(pk["p"])
			if poly.size() < 3:
				continue
			var box := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				box = box.expand(q)
			_park_boxes.append([box, poly])
	for b in _park_boxes:
		if (b[0] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, b[1]):
			return true
	return false


func _challenge() -> String:
	var day := int(Time.get_unix_time_from_system() / 86400.0)
	return TAGS[0] if day % 2 == 0 else TAGS[day % TAGS.size()]


## Fotograf cekilince cagrilir: paylasimi olusturur.
func add_post(file: String) -> void:
	var g := _d()
	var kind: String = state.d["active"]
	var pet: Dictionary = state.pet(kind)
	var happy: float = (float(pet["hunger"]) + float(pet["energy"]) + float(pet["fun"]) + float(pet["clean"])) / 400.0
	var pos: Vector2 = m._owner_pos()
	var worn: int = (pet["worn"] as Dictionary).size()
	var tricks: int = m.pet_care.tricks_of(kind).size() if m.pet_care != null else 0
	var cells := {}
	for p in g["posts"]:
		cells[Vector2i(int(float(p["x"]) / 60.0), int(float(p["z"]) / 60.0))] = true
	var cell := Vector2i(int(pos.x / 60.0), int(pos.y / 60.0))
	var fresh: bool = not cells.has(cell)
	var in_park: bool = _in_park(pos)
	var tag := _challenge()
	var today := Time.get_date_string_from_system()
	var chal: bool = in_park if tag == TAGS[0] else true
	var target: float = 6.0 + happy * 22.0 + worn * 4.0 + tricks * 3.0 + (12.0 if fresh else 0.0) + (8.0 if in_park else 0.0)
	target *= 1.0 + minf(followers(), 300) / 150.0
	if chal and g["bonus_day"] != today:
		target *= 1.4
		g["bonus_day"] = today
		state.d["coins"] = int(state.d["coins"]) + 20
		m.ui.toast("Günün etiketi %s: +20 ₺" % tag)
	var caps := ["%s bugün harikaydı!", "Pozumuz nasıl? %s", "%s ile gezinti keyfi", "Yeni kare: %s"]
	var caption: String = (caps[randi() % caps.size()] as String) % pet["name"]
	if chal:
		caption += " " + tag
	g["posts"].push_front({"file": file, "t": Time.get_unix_time_from_system(), "age": 0.0, "x": pos.x, "z": pos.y,
		"kind": kind, "caption": caption, "loc": "Park" if in_park else "Sokak", "likes": 0, "target": int(target), "seed": randi()})
	if g["posts"].size() > 40:
		g["posts"].resize(40)
	m.ui.toast("Patigram'da paylaşıldı")
	state.count("patigram")


func update(dt: float) -> void:
	_tick += dt
	if _tick < 1.0:
		return
	var step := _tick
	_tick = 0.0
	var g := _d()
	var changed := false
	for p in g["posts"]:
		if int(p["likes"]) >= int(p["target"]):
			continue
		p["age"] = float(p["age"]) + step
		# yaklasik 6 dakikada hedefe ulasir (hizli baslayip yavaslayan egri)
		var k: float = 1.0 - pow(1.0 - clampf(float(p["age"]) / 360.0, 0.0, 1.0), 2.0)
		p["likes"] = int(float(p["target"]) * k)
		changed = true
	if changed:
		_check_milestones(followers())


func _check_milestones(f: int) -> void:
	var g := _d()
	for ms in MILESTONES:
		if f >= int(ms[0]) and not g["claimed"].has(ms[0]):
			g["claimed"].append(ms[0])
			state.d["coins"] = int(state.d["coins"]) + int(ms[1])
			var extra := ""
			if ms[2] != "":
				state.d["foods"][ms[2]] = int(state.d["foods"].get(ms[2], 0)) + 2
				extra = " + 2 mama"
			m.ui.toast("%d takipçi! +%d ₺%s" % [ms[0], ms[1], extra])
			state.save_game()
			m._sfx("para", -4.0)


func _comments_of(p: Dictionary) -> Array:
	var n: int = mini(int(p["likes"]) / 6, 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var out := []
	for i in n:
		out.append("%s: %s" % [NPC_NAMES[rng.randi() % NPC_NAMES.size()], COMMENTS[rng.randi() % COMMENTS.size()]])
	return out


func _thumb(file: String) -> Texture2D:
	if _thumbs.has(file):
		return _thumbs[file]
	var img := Image.load_from_file("user://fotolar/" + file)
	if img == null or img.is_empty():
		return null
	img.resize(384, int(384.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	var tex := ImageTexture.create_from_image(img)
	_thumbs[file] = tex
	return tex


func _lbl(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", m.ui.F_UI)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 420
	parent.add_child(l)
	return l


func phone_app() -> void:
	var g := _d()
	var f := followers()
	var body: VBoxContainer = m.ui._open_page("PATİGRAM", "%d takipçi · %d paylaşım" % [f, g["posts"].size()])
	var next := ""
	for ms in MILESTONES:
		if f < int(ms[0]):
			next = "Sıradaki hedef: %d takipçi (+%d ₺)" % [ms[0], ms[1]]
			break
	var done: bool = g["bonus_day"] == Time.get_date_string_from_system()
	_lbl(body, "Günün etiketi: %s%s" % [_challenge(), "  (tamamlandı)" if done else ""], 30, Color("f2c230"))
	if next != "":
		_lbl(body, next, 26, Color(1, 1, 1, 0.8))
	m.ui._menu_item(body, "Fotoğraf çek", func():
		m.ui.close_modal()
		m._on_photo("enter"))
	if g["posts"].is_empty():
		_lbl(body, "Henüz paylaşımın yok. Fotoğraf modunda çektiğin her kare buraya düşer.", 28, Color.WHITE)
	var shown := 0
	for p in g["posts"]:
		if shown >= 8:
			break
		shown += 1
		_post_card(body, "sen", p)
	_lbl(body, "Keşfet", 40, Color("e0708f"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Time.get_date_string_from_system())
	for i in 4:
		var ni: int = rng.randi() % NPC_NAMES.size()
		var cap: String = (NPC_CAPTIONS[rng.randi() % NPC_CAPTIONS.size()] as String) % NPC_PETS[ni]
		var likes := 20 + rng.randi() % 400
		_lbl(body, "@%s" % NPC_NAMES[ni], 30, Color("5ad1ff"))
		_lbl(body, cap + (" " + TAGS[rng.randi() % TAGS.size()] if rng.randf() < 0.5 else ""), 26, Color.WHITE)
		_lbl(body, "♥ %d" % likes, 24, Color(1, 1, 1, 0.65))
	m.ui._focus_first(body)


func _post_card(body: Node, who: String, p: Dictionary) -> void:
	_lbl(body, "@%s · %s" % [who, p["loc"]], 28, Color("5ad1ff"))
	var tex := _thumb(p["file"])
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(384, 384.0 * tex.get_height() / tex.get_width())
		body.add_child(tr)
	_lbl(body, p["caption"], 26, Color.WHITE)
	var cm := _comments_of(p)
	_lbl(body, "♥ %d   yorum %d" % [p["likes"], cm.size()], 26, Color("ff6b8a"))
	for c in cm:
		_lbl(body, c, 22, Color(1, 1, 1, 0.75))
