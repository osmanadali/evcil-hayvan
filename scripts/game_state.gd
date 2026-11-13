extends Node
## Oyunun kalici durumu: para, mamalar, aksesuarlar, hayvanlarin ihtiyaclari, gorevler.
## user://kayit.json dosyasina kaydedilir; oyun kapaliyken gecen sure ihtiyaclara yansir.

signal changed
signal coins_added
signal toast(text: String)
signal leveled(kind: String, level: int)

const Accessories = preload("res://scripts/accessories.gd")
const SAVE_PATH := "user://kayit.json"
const NEEDS := ["hunger", "energy", "fun", "clean"]
const NEED_NAMES := {"hunger": "Tokluk", "energy": "Enerji", "fun": "Neşe", "clean": "Temizlik"}
const DECAY := {"hunger": 3.2, "energy": 2.0, "fun": 2.6, "clean": 1.2}   # dakikada
const PET_NAMES := {"kopek": "Köpek", "kedi": "Kedi"}
const ADOPT_PRICE := 150
# id: [ad, fiyat, tokluk, nese]
const FOODS := {
	"mama": ["Kuru Mama", 8, 35, 0],
	"konserve": ["Konserve", 14, 60, 5],
	"odul": ["Ödül Bisküvisi", 6, 12, 18],
}
# Gunluk gorevler: [anahtar, aciklama, hedef, odul]
const QUESTS := [
	["pet", "Hayvanını 5 kez sev", 5, 20], ["fetch", "3 kez oyun oyna", 3, 25], ["feed", "Hayvanını besle", 1, 15],
	["walk", "500 metre yürü", 500, 25], ["coin", "10 altın topla", 10, 20], ["photo", "Bir fotoğraf çek", 1, 15],
	["metro", "Metroyla bir yolculuk yap", 1, 40], ["drive", "Arabayla 1 km sür", 1000, 30],
	["shop", "Market ya da eczaneden alışveriş yap", 1, 20], ["swim", "Göle gir, ıslan", 1, 10],
	["seesaw", "Hayvanınla tahterevalliye bin", 1, 15], ["npcplay", "Başka bir hayvanla oynat", 1, 20],
	["taxi", "Taksi ya da dolmuşla bir yere git", 1, 30], ["job", "Bir iş bitir (köpek gezdir / kurye)", 1, 25], ["outfit", "Dolaptan kıyafet değiştir", 1, 10],
	["weather", "Yağmurda ya da karda 1 dakika dışarıda gez", 60, 20],
	["fuel", "Benzinlikte aracına yakıt al", 1, 20],
	["tea", "Çay ocağında çay iç", 1, 15],
	["lawful", "Hız sınırına uyarak 1 km araba sür", 1000, 30],
]


## Bugunun gorevleri: havuzdan gune gore 6 tanesi (her gun degisir).
func daily_quests() -> Array:
	_roll_day()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(d["day"])
	var pool := QUESTS.duplicate()
	var out: Array = [pool.pop_at(0)]          # "sev" her gun var
	while out.size() < 6 and not pool.is_empty():
		out.append(pool.pop_at(rng.randi() % pool.size()))
	return out

var d := {}
var places: Array = []   # kesfedilecek yerler: [ad, merkez, yaricap]


func _ready() -> void:
	reset()
	load_game()


## Kesfedilecek yerleri harita verisinden doldurur.
func set_places() -> void:
	const ParkMap = preload("res://scripts/park_map.gd")
	const SPOT_NAMES := {"bahce": "Bahçe", "petshop": "Pet Shop", "kafe": "Park Kafe", "dondurmaci": "Dondurmacı",
		"cardak": "Çardak", "cesme": "Çeşme", "oyun_alani": "Köpek Oyun Alanı", "piknik": "Piknik Alanı"}
	places.clear()
	for k in SPOT_NAMES:
		if ParkMap.has_spot(k):
			places.append([SPOT_NAMES[k], ParkMap.spot(k), 9.0])
	for pl in ParkMap.data["places"]:
		places.append([pl["name"], Vector2(pl["pos"][0], pl["pos"][1]), float(pl["r"]) + 12.0])


func reset() -> void:
	d = {
		"started": false, "owner": "kadin", "coins": 120, "active": "kopek",
		"foods": {"mama": 4, "konserve": 1, "odul": 3},
		"owned": ["tasma_kirmizi"],
		"pets": {"kopek": _new_pet("Pamuk"), "kedi": _new_pet("Limon")},
		"found": [], "places": [], "quests": {}, "quest_done": [], "day": "",
		"last_time": Time.get_unix_time_from_system(), "sound": true,
	}
	d["pets"]["kopek"]["worn"] = {"neck": "tasma_kirmizi"}


func _new_pet(pet_name: String) -> Dictionary:
	return {"owned": false, "name": pet_name, "hunger": 80.0, "energy": 90.0, "fun": 70.0, "clean": 85.0, "xp": 0.0, "worn": {}}


func pet(kind: String) -> Dictionary:
	return d["pets"][kind]


func owned_pets() -> Array:
	var out := []
	for k in ["kopek", "kedi"]:
		if d["pets"][k]["owned"]:
			out.append(k)
	return out


func level(kind: String) -> int:
	return 1 + int(sqrt(float(pet(kind)["xp"]) / 12.0))


func level_progress(kind: String) -> float:
	var l := level(kind)
	var lo := 12.0 * (l - 1) * (l - 1)
	var hi := 12.0 * l * l
	return clampf((float(pet(kind)["xp"]) - lo) / (hi - lo), 0.0, 1.0)


## Buyume evresi seviyeye bagli: 1-2 yavru, 3-5 genc, 6+ yetiskin.
func stage(kind: String) -> int:
	var l := level(kind)
	return 0 if l < 3 else (1 if l < 6 else 2)


func mood(kind: String) -> float:
	var p := pet(kind)
	return (p["hunger"] + p["energy"] + p["fun"] + p["clean"]) / 4.0


func add_need(kind: String, need: String, amount: float) -> void:
	var p := pet(kind)
	p[need] = clampf(p[need] + amount, 0.0, 100.0)
	changed.emit()


func add_xp(kind: String, amount: float) -> void:
	var before := level(kind)
	pet(kind)["xp"] += amount
	if level(kind) > before:
		leveled.emit(kind, level(kind))
		d["coins"] += 20
		toast.emit("%s %d. seviye oldu! +20 altın" % [pet(kind)["name"], level(kind)])
	changed.emit()


func add_coins(n: int) -> void:
	d["coins"] += n
	coins_added.emit()
	changed.emit()


func spend(n: int) -> bool:
	if d["coins"] < n:
		toast.emit("Yeterli altının yok")
		return false
	d["coins"] -= n
	changed.emit()
	return true


func tick(dt: float) -> void:
	for k in owned_pets():
		var p := pet(k)
		for n in NEEDS:
			p[n] = maxf(p[n] - DECAY[n] * dt / 60.0, 0.0)


## Gunluk gorev sayaclari.
func count(key: String, amount := 1.0) -> void:
	_roll_day()
	d["quests"][key] = float(d["quests"].get(key, 0.0)) + amount
	for q in daily_quests():
		if q[0] == key and d["quests"][key] >= q[2] and not d["quest_done"].has(key):
			d["quest_done"].append(key)
			d["coins"] += q[3]
			toast.emit("Görev tamam: %s  +%d altın" % [q[1], q[3]])
			changed.emit()


func quest_progress(key: String) -> float:
	_roll_day()
	return float(d["quests"].get(key, 0.0))


func _roll_day() -> void:
	var today := Time.get_date_string_from_system()
	if d["day"] != today:
		d["day"] = today
		d["quests"] = {}
		d["quest_done"] = []
		d["found"] = []


func visit(p: Vector2) -> void:
	for pl in places:
		var c: Vector2 = pl[1]
		if p.distance_to(c) < pl[2] and not d["places"].has(pl[0]):
			d["places"].append(pl[0])
			d["coins"] += 15
			toast.emit("Yeni yer keşfedildi: %s  +15 altın" % pl[0])
			changed.emit()


func save_game() -> void:
	d["last_time"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for k in parsed:
		if k == "pets":
			for kind in parsed[k]:
				for f in parsed[k][kind]:
					d["pets"][kind][f] = parsed[k][kind][f]
		else:
			d[k] = parsed[k]
	# Oyun kapaliyken gecen sure: en fazla 8 saat sayilir, ihtiyaclar 20'nin altina dusmez
	var away := clampf(Time.get_unix_time_from_system() - float(d["last_time"]), 0.0, 8.0 * 3600.0)
	for k in owned_pets():
		var p := pet(k)
		for n in NEEDS:
			p[n] = maxf(float(p[n]) - DECAY[n] * away / 60.0 * 0.35, minf(float(p[n]), 20.0))
		p["energy"] = minf(float(p["energy"]) + away / 60.0 * 1.5, 100.0)
