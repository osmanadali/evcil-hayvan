extends RefCounted
## Ozellestirilebilir klavye tuslari: InputMap eylemleri. Ozel atamalar state.d["keys"] icinde saklanir.

# [eylem, Turkce ad, varsayilan tuslar]
const ACTIONS := [
	["move_forward", "İLERİ", [KEY_W, KEY_UP]],
	["move_back", "GERİ", [KEY_S, KEY_DOWN]],
	["move_left", "SOLA", [KEY_A, KEY_LEFT]],
	["move_right", "SAĞA", [KEY_D, KEY_RIGHT]],
	["sprint", "KOŞ", [KEY_SHIFT]],
	["jump", "ZIPLA / EL FRENİ", [KEY_SPACE]],
	["interact", "ETKİLEŞİM", [KEY_F, KEY_E]],
	["pet_love", "HAYVANI SEV", [KEY_1]],
	["pet_feed", "HAYVANI BESLE", [KEY_2]],
	["pet_play", "HAYVANLA OYNA", [KEY_3]],
	["commands", "KOMUTLAR", [KEY_Q]],
	["call_pet", "HAYVANI ÇAĞIR", [KEY_R]],
	["switch_pet", "HAYVAN DEĞİŞTİR", [KEY_TAB]],
	["map", "HARİTA", [KEY_M]],
	["phone", "TELEFON", [KEY_P]],
	["quests", "GÖREVLER", [KEY_G]],
	["jobs", "İŞLER", [KEY_J]],
	["photo", "FOTOĞRAF", [KEY_C]],
	["fps_view", "ARAÇ İÇİ KAMERA", [KEY_V]],
	["umbrella", "ŞEMSİYE", [KEY_U]],
	["leash", "TASMA", [KEY_L]],
	["train", "NUMARA EĞİTİMİ", [KEY_T]],
	["radio", "RADYO", [KEY_N]],
	["headlights", "FARLAR", [KEY_H]],
	["messages", "MESAJLAR", [KEY_K]],
	["snowball", "KARTOPU", [KEY_Y]],
]
const RESERVED := [KEY_ESCAPE, KEY_ALT]


static func setup(saved: Dictionary) -> void:
	for a in ACTIONS:
		var name: String = a[0]
		if InputMap.has_action(name):
			InputMap.erase_action(name)
		InputMap.add_action(name)
		if saved.has(name):
			_set_events(name, [int(saved[name])])
		else:
			_set_events(name, a[2])


static func _set_events(name: String, codes: Array) -> void:
	InputMap.action_erase_events(name)
	for c in codes:
		var ev := InputEventKey.new()
		ev.physical_keycode = c
		InputMap.action_add_event(name, ev)


static func label_of(name: String) -> String:
	for a in ACTIONS:
		if a[0] == name:
			return a[1]
	return name


static func codes_of(name: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(name):
		if ev is InputEventKey:
			out.append(ev.physical_keycode)
	return out


static func key_name(code: int) -> String:
	var s := OS.get_keycode_string(code).to_upper()
	match code:
		KEY_SPACE: return "BOŞLUK"
		KEY_SHIFT: return "SHIFT"
		KEY_TAB: return "TAB"
		KEY_ENTER: return "ENTER"
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
	return s


static func key_text(name: String) -> String:
	var parts := []
	for c in codes_of(name):
		parts.append(key_name(c))
	return " / ".join(parts)


## Etkilesim ipucunda gosterilecek ana tus harfi.
static func primary(name: String) -> String:
	var c := codes_of(name)
	return key_name(c[0]) if c.size() > 0 else "?"


static func is_default(name: String) -> bool:
	for a in ACTIONS:
		if a[0] == name:
			return codes_of(name) == a[2]
	return true


## Tusu eyleme ata; baska eylemde kullaniliyorsa tuslari takas eder. Donus: takas edilen eylemin adi ("" yok).
static func rebind(name: String, code: int, store: Dictionary) -> String:
	var swapped := ""
	var old := codes_of(name)
	for a in ACTIONS:
		var o: String = a[0]
		if o != name and code in codes_of(o):
			swapped = o
			var rest := codes_of(o).filter(func(c): return c != code)
			_set_events(o, rest if rest.size() > 0 else (old if old.size() > 0 else a[2]))
			var oc := codes_of(o)
			store[o] = oc[0]
	_set_events(name, [code])
	store[name] = code
	return swapped


static func reset(store: Dictionary) -> void:
	store.clear()
	setup({})
