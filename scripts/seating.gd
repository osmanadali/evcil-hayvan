extends Node
## Her yerde oturma: parktaki tum banklar, kafe / lokanta terasi sandalyeleri ve masa tabureleri.
## F -> koltuga otur (Sitting_Enter, sonra Sitting_Idle), evcil hayvan yanina uzanir.
## Bankta oturunca F "Kestir" (player_needs.nap). Herhangi bir yurume tusu -> Sitting_Exit ve kalk.

const PersonModel = preload("res://scripts/person_model.gd")
const ParkMap = preload("res://scripts/park_map.gd")

var m: Node
var seats: Array = []          # [{pos, yaw, h, kind, busy, bench}]
var cur: Dictionary = {}       # oturulan koltuk
var _exit_t := -1.0            # >= 0: kalkis animasyonu suruyor
var _t := 0.0
var _npcs: Array = []


func busy() -> bool:
	return not cur.is_empty()


func build() -> void:
	var w: Node3D = m.world
	if w == null:
		return
	# Bank: iki kisilik (iki yuva)
	for b in w.benches:
		var bp: Vector2 = b[0]
		var yaw: float = float(b[1]) + PI
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var side := Vector2(cos(yaw), -sin(yaw))
		for s in [-0.42, 0.42]:
			var p: Vector2 = bp + fwd * 0.2 + side * s
			seats.append({"pos": p, "yaw": yaw, "h": ParkMap.walk_height(bp) + 0.48, "kind": "bank", "busy": false, "bench": b})
	for sd in w.seats:
		seats.append(sd)
	_spawn_npcs()


## Bazi bankta / sandalyede NPC'ler oturur (baslangica yakin olanlardan birkac tane).
func _spawn_npcs() -> void:
	var o: Vector2 = m._owner_pos()
	var cand: Array = []
	for s in seats:
		var d: float = o.distance_to(s["pos"])
		if d > 8.0 and d < 160.0:
			cand.append(s)
	cand.shuffle()
	var shirts := ["6b7d93", "8b5a3c", "b34a4a", "4f7a5a", "caa24c", "5d5fa8"]
	var pants := ["2b2f38", "3b3b3b", "3a4a6b"]
	var n := 0
	for s in cand:
		if n >= 6:
			break
		if s["kind"] == "bank" and randf() < 0.5:
			continue
		var v := PersonModel.new()
		v.kind = "kadin" if randf() < 0.5 else "erkek"
		var sh: String = shirts[randi() % shirts.size()]
		v.tint = Color(sh)
		v.tint2 = Color(sh)
		v.pants = Color(pants[randi() % pants.size()])
		v.seated = true
		v.position = Vector3(s["pos"].x, s["h"] - 0.05, s["pos"].y)
		v.rotation.y = s["yaw"]
		m.world.add_child(v)
		s["busy"] = true
		_npcs.append(v)
		n += 1


func _nearest(o: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1.5
	for s in seats:
		if s["busy"]:
			continue
		var lim := 1.5 if s["kind"] == "bank" else 1.1
		var d: float = o.distance_to(s["pos"])
		if d < lim and d < bd:
			bd = d
			best = s
	return best


## Baglam ipucu: [metin, komut, simge] ya da bos.
func context() -> Array:
	if m._ride != null or m._taxi != null or ParkMap.home != null or m.street_food.is_seated() or m.needs.sleeping:
		return []
	if not cur.is_empty():
		if _exit_t >= 0.0:
			return ["", "", ""]
		if cur["kind"] == "bank":
			return ["Kestir · kalkmak için yürü", "nap", "sit"]
		return ["Oturuyorsun · kalkmak için yürü", "", "sit"]
	if m._mode != "play":
		return []
	var s := _nearest(m._owner_pos())
	if s.is_empty():
		return []
	return ["Otur", "seat_sit", "sit"]


func command(cmd: String) -> void:
	if cmd == "seat_sit" and cur.is_empty():
		var s := _nearest(m._owner_pos())
		if not s.is_empty():
			sit(s)


func sit(s: Dictionary) -> void:
	if not cur.is_empty() or s["busy"]:
		return
	s["busy"] = true
	cur = s
	_exit_t = -1.0
	m._moving = false
	m._queue.clear()
	m._steering = false
	m._target = s["pos"]
	m.owner_model.speed = 0.0
	m.ui.stick = Vector2.ZERO
	m.owner_model._seat_t = 0.0
	m.owner_model.sit_exit = false
	m.owner_model.seated = true
	_place()
	if s["kind"] == "bank":
		m.needs._bench_near = s["bench"]
	# Hayvanlar yanina uzanir
	var fwd := Vector2(-sin(s["yaw"]), -cos(s["yaw"]))
	var side := Vector2(cos(s["yaw"]), -sin(s["yaw"]))
	var i := 0
	for k in m.agents:
		var a: Node3D = m.agents[k]
		a.command("lie")
		var ap: Vector2 = s["pos"] + fwd * 1.0 + side * (0.6 - 1.0 * i)
		if not m.world.is_free(ap, 0.25):
			ap = s["pos"] + fwd * 0.5 - side * (0.9 + 0.7 * i)
		a.place(ap)
		a.rotation.y = float(s["yaw"]) + PI * 0.5
		i += 1
	var pn: String = m.state.pet(m._active().kind)["name"]
	m.ui.toast("Oturdun. %s yanına uzandı. Kalkmak için yürü." % pn)
	m._update_context()


func _place() -> void:
	m.owner_node.position = Vector3(cur["pos"].x, cur["h"], cur["pos"].y)
	m.owner_node.rotation = Vector3(0, cur["yaw"], 0)
	m.owner_model.position = Vector3(0, -0.05, 0)


## Kestirme basliyorsa koltugu birakir (kalkma animasyonu yok); eski koltugu dondurur.
func release() -> Dictionary:
	var s := cur
	if not cur.is_empty():
		cur["busy"] = false
	cur = {}
	_exit_t = -1.0
	return s


func stand_up() -> void:
	if cur.is_empty() or _exit_t >= 0.0:
		return
	_exit_t = 0.0
	m.owner_model.sit_exit = true


func _finish_stand() -> void:
	var s := cur
	cur = {}
	_exit_t = -1.0
	s["busy"] = false
	var fwd := Vector2(-sin(s["yaw"]), -cos(s["yaw"]))
	var out: Vector2 = s["pos"] + fwd * 0.9
	if not m.world.is_free(out, 0.3):
		out = s["pos"] - fwd * 0.9
	m.owner_model.sit_exit = false
	m.owner_model.seated = false
	m.owner_model.position = Vector3.ZERO
	m.owner_node.position = Vector3(out.x, ParkMap.walk_height(out), out.y)
	m._target = out
	for k in m.agents:
		m.agents[k].command("come")
	m.ui._actions.visible = true
	m._update_context()


func update(dt: float) -> void:
	if cur.is_empty():
		return
	if m.needs.busy():
		return      # kestirme kendi akisini yonetir
	_t += dt
	if _exit_t >= 0.0:
		_exit_t += dt
		if _exit_t > 0.8:
			_finish_stand()
		else:
			_place()
		return
	if (m._mode != "play" and m._mode != "debug") or m._ride != null or m._jump_h > 0.0 \
			or m.ui.stick.length() > 0.1 or m._moving or m._steering or _move_key():
		stand_up()
		return
	_place()


func _move_key() -> bool:
	return Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_back") \
		or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")


func debug_sit() -> void:
	var o: Vector2 = m._owner_pos()
	var best: Dictionary = {}
	var bd := 1e9
	for s in seats:
		if s["busy"] or s["kind"] != "bank":
			continue
		var d: float = o.distance_to(s["pos"])
		if d < bd:
			bd = d
			best = s
	if best.is_empty():
		print("OTURMA: bank yok")
		return
	m._place_owner(best["pos"] + Vector2(-sin(best["yaw"]), -cos(best["yaw"])) * 1.0)
	for f in 3:
		await get_tree().process_frame
	sit(best)
	print("OTURMA ", best["kind"], " ", best["pos"], " koltuk=", seats.size())
