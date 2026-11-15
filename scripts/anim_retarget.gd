extends Node
## Hazir animasyonlari (Quaternius Universal Animation Library, CC0) MakeHuman iskeletine aktarir.
## Kaynak iskelet gorunmez olarak calisir; her karede kemiklerin dunya (iskelet uzayi) donus farki
## hedef kemiklere uygulanir. Dinlenme pozlari farkli oldugu icin her kemik once yon olarak hizalanir.

const SRC := "res://assets/anim/ual.gltf"
const MAP := {
	"Hips": "DEF-hips", "Spine": "DEF-spine.001", "Spine1": "DEF-spine.002", "Spine2": "DEF-spine.003",
	"Neck": "DEF-neck", "Head": "DEF-head",
	"LeftShoulder": "DEF-shoulder.L", "LeftArm": "DEF-upper_arm.L", "LeftForeArm": "DEF-forearm.L", "LeftHand": "DEF-hand.L",
	"RightShoulder": "DEF-shoulder.R", "RightArm": "DEF-upper_arm.R", "RightForeArm": "DEF-forearm.R", "RightHand": "DEF-hand.R",
	"LeftUpLeg": "DEF-thigh.L", "LeftLeg": "DEF-shin.L", "LeftFoot": "DEF-foot.L", "LeftToeBase": "DEF-toe.L",
	"RightUpLeg": "DEF-thigh.R", "RightLeg": "DEF-shin.R", "RightFoot": "DEF-foot.R", "RightToeBase": "DEF-toe.R",
}
const FINGERS := {"Index": "f_index", "Middle": "f_middle", "Pinky": "f_pinky", "Ring": "f_ring", "Thumb": "thumb"}

static var _scene: PackedScene

var target: Skeleton3D
var src: Skeleton3D
var player: AnimationPlayer
var weight := 1.0              # 0: hedefe dokunma
var _pairs: Array = []         # [hedef kemik, kaynak kemik (-1 = eslesmiyor)] hiyerarsi sirasinda
var _align := {}               # hedef kemik -> Quaternion (hizalanmis referans dunya donusu)
var _sref := {}                # kaynak kemik -> referans dunya donusu (A_TPose)
var _C := Quaternion.IDENTITY  # kaynak uzayindan hedef uzayina
var _hips_s := 1.0
var _src_hips_ref := Vector3.ZERO
var _tgt_hips_rest := Vector3.ZERO
var _tgt_foot_y := 0.0
var current := ""
var _started := false
var _straight := 0.0           # 1: ayakta durus (asagidaki "durus" eslemesi), 0: olagan esleme
var _stand := {}               # hedef kemik -> rahat ayakta durusun dunya donusu (kodla kurulur)
var _sref_idle := {}           # kaynak kemik -> Idle klibinin ilk karesindeki dunya donusu
var _src_hips_idle := Vector3.ZERO
const TRUNK := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "RightShoulder"]
const UPRIGHT := {"Walk": 0.45, "Jog_Fwd": 0.5, "Sprint": 0.35}
var _upright := 0.0
var _trunk_src := {}
const STAND_CLIPS := ["Idle"]
const GROUND_CLIPS := ["Idle", "Idle_Talking", "Walk", "Walk_Formal", "Jog_Fwd", "Sprint", "Interact", "PickUp_Table"]


func setup(tgt: Skeleton3D) -> void:
	target = tgt
	if _scene == null:
		_scene = load(SRC)
	var inst: Node3D = _scene.instantiate()
	add_child(inst)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		mi.queue_free()
	src = inst.find_children("*", "Skeleton3D", true, false)[0]
	player = inst.find_children("*", "AnimationPlayer", true, false)[0]
	for n in player.get_animation_list():
		if n in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Driving", "Sitting_Idle", "Swim_Fwd", "Swim_Idle", "Crouch_Fwd", "Crouch_Idle", "Jump"]:
			player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	# Kaynak referans pozu: A_TPose ilk karesi
	player.play("A_TPose")
	player.seek(0.0, true)
	player.advance(0.0)
	var sg := _globals(src)
	# Hedef "notr durus": karakterin o anki (kodla kurulmus dik) pozu
	var tg := _globals(target)
	# Eksen donusumu: iki iskelet de dik durur (yukari = Y); sol yon (sol uyluk - sag uyluk) eslestirilir.
	# (Kalca->bas yonu kullanilmaz: kalca kemiginin kokü iki iskelette farkli yerde, egik eksen verir.)
	var sl := (_gpos(src, "DEF-thigh.L") - _gpos(src, "DEF-thigh.R")) * Vector3(1, 0, 1)
	var tl := (_tpos("LeftUpLeg") - _tpos("RightUpLeg")) * Vector3(1, 0, 1)
	_C = Quaternion(Vector3.UP, sl.signed_angle_to(tl, Vector3.UP))
	_hips_s = (_tpos("Head") - _tpos("LeftFoot")).length() / maxf((_gpos(src, "DEF-head") - _gpos(src, "DEF-foot.L")).length(), 0.001)
	_src_hips_ref = src.get_bone_global_pose(src.find_bone("DEF-hips")).origin
	_tgt_hips_rest = target.get_bone_rest(target.find_bone("Hips")).origin
	_tgt_foot_y = minf(_tpos("LeftFoot").y, _tpos("RightFoot").y)
	for i in target.get_bone_count():
		var nm := target.get_bone_name(i)
		var sname := _src_name(nm)
		var si := src.find_bone(sname) if sname != "" else -1
		_pairs.append([i, si])
		if si >= 0:
			_sref[si] = sg[si]
			if nm in TRUNK and not nm.ends_with("Shoulder"):
				_trunk_src[si] = true
			# Hizalama: kaynak referans pozunda (T durusu) hedef kemik hangi dunya donusunde olmali?
			# - Govde (kalca, omurga, boyun, bas, kopruculk): iki iskelet de dik durdugu icin notr durus
			#   aynen kullanilir. Bu kemiklerin kokleri iki iskelette farkli yerde (ornegin kaynakta
			#   koprucuk gogsun onunden, kalca belin arkasindan baslar); yon hizalamak omuzlari geri ceker,
			#   kalcayi dondurur.
			# - Kol ve bacak kemikleri: kemik yonu (kendi -> cocuk eklem) kaynaktaki yone getirilir (en kisa yay).
			# - El: orta parmak + isaret parmagi ile tam cerceve (avuc yonu de eslesir).
			var a := Quaternion.IDENTITY
			if not nm in TRUNK:
				var pairs: Array = []
				for c in target.get_bone_children(i):
					var sc := src.find_bone(_src_name(target.get_bone_name(c)))
					if sc >= 0 and src.get_bone_parent(sc) == si:
						var td: Vector3 = (tg[i] * target.get_bone_rest(c).origin).normalized()
						var sd: Vector3 = _C * (sg[si] * src.get_bone_pose_position(sc)).normalized()
						if td != Vector3.ZERO and sd != Vector3.ZERO:
							var sn := src.get_bone_name(sc)
							if sn.contains("middle"):
								pairs.push_front([td, sd])
							elif not sn.contains("thumb"):
								pairs.append([td, sd])
				if pairs.size() >= 2:
					var ft := _frame(pairs[0][0], pairs[1][0])
					var fs := _frame(pairs[0][1], pairs[1][1])
					a = (fs * ft.inverse()).get_rotation_quaternion()
				elif pairs.size() == 1:
					var tdir: Vector3 = pairs[0][0]
					var sdir: Vector3 = pairs[0][1]
					a = Quaternion(tdir, sdir) if tdir.dot(sdir) > -0.999 else Quaternion(Vector3.UP, PI)
			_align[i] = a * tg[i]
	# Ayakta durus referansi: Idle klibinin ilk karesi
	player.play("Idle")
	player.seek(0.0, true)
	player.advance(0.0)
	var si0 := _globals(src)
	for pr in _pairs:
		if pr[1] >= 0:
			_sref_idle[pr[1]] = si0[pr[1]]
	_src_hips_idle = src.get_bone_global_pose(src.find_bone("DEF-hips")).origin
	player.stop()


## Hedef iskeletin o anki pozunu "rahat ayakta durus" olarak kaydeder. Kaynak Idle klibi egik ve
## carpik bir durus (bir ayak geride, govde donuk, bas one egik); onun yerine karakterin kendi dik
## durusu kullanilir, klipten yalniz hareket (nefes, hafif salinim) alinir.
func capture_stand() -> void:
	var tg := _globals(target)
	for pr in _pairs:
		_stand[pr[0]] = tg[pr[0]]


## Iki yonden dik cerceve (ilk yon ana eksen).
func _frame(a: Vector3, b: Vector3) -> Basis:
	var x := a.normalized()
	var z := x.cross(b).normalized()
	if z.length() < 0.001:
		z = x.cross(Vector3.FORWARD if absf(x.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, z.cross(x), z).orthonormalized()


func _src_name(nm: String) -> String:
	if MAP.has(nm):
		return MAP[nm]
	for side in ["Left", "Right"]:
		if nm.begins_with(side + "Hand"):
			var rest := nm.substr((side + "Hand").length())
			for f in FINGERS:
				if rest.begins_with(f):
					return "DEF-%s.0%s.%s" % [FINGERS[f], rest.right(1), "L" if side == "Left" else "R"]
	return ""


func _gpos(s: Skeleton3D, n: String) -> Vector3:
	return s.get_bone_global_pose(s.find_bone(n)).origin


func _tpos(n: String) -> Vector3:
	return target.get_bone_global_rest(target.find_bone(n)).origin


## Kemigin (ilk) cocuguna dogru yon, verilen dunya donusleriyle (yoksa bos).
func _child_dir(s: Skeleton3D, i: int, globals: Dictionary) -> Vector3:
	for c in s.get_bone_children(i):
		var off: Vector3 = (s.get_bone_rest(c) if s == target else s.get_bone_rest(c)).origin
		if off.length() > 0.0001:
			return (globals[i] * off).normalized()
	return Vector3.ZERO


func _globals(s: Skeleton3D) -> Dictionary:
	var g := {}
	for i in s.get_bone_count():
		var p := s.get_bone_parent(i)
		var local := s.get_bone_pose_rotation(i)
		g[i] = (g[p] if p >= 0 else Quaternion.IDENTITY) * local
	return g


func play(anim: String, blend := 0.25, speed := 1.0) -> void:
	if anim != current:
		current = anim
		player.play(anim, blend)
	player.speed_scale = speed


## Her karede cagrilir (AnimationPlayer ilerledikten sonra).
func apply() -> void:
	var sg := _globals(src)
	var tg := {}
	var want := 1.0 if current in STAND_CLIPS else 0.0
	_straight = move_toward(_straight, want, get_process_delta_time() * 4.0) if _started else want
	_upright = move_toward(_upright, UPRIGHT.get(current, 0.0), get_process_delta_time() * 2.0) if _started else float(UPRIGHT.get(current, 0.0))
	_started = true
	for pr in _pairs:
		var i: int = pr[0]
		var si: int = pr[1]
		var p := target.get_bone_parent(i)
		var pg: Quaternion = tg[p] if p >= 0 else Quaternion.IDENTITY
		var g: Quaternion
		if si >= 0:
			var delta: Quaternion = sg[si] * (_sref[si] as Quaternion).inverse()
			if _upright > 0.0 and si in _trunk_src:
				# Yuruyus / kosu klipleri govdeyi fazla one egiyor: govde donusu yumusatilir (daha dik)
				delta = delta.slerp(Quaternion.IDENTITY, _upright)
			g = _C * delta * _C.inverse() * _align[i]
			if _straight > 0.0 and _stand.has(i):
				var d2: Quaternion = sg[si] * (_sref_idle[si] as Quaternion).inverse()
				g = g.slerp(_C * d2 * _C.inverse() * _stand[i], _straight)
		else:
			g = pg * target.get_bone_rest(i).basis.get_rotation_quaternion()
		tg[i] = g
		var local := pg.inverse() * g
		if weight < 1.0:
			local = target.get_bone_pose_rotation(i).slerp(local, weight)
		target.set_bone_pose_rotation(i, local)
	# Kalca yuksekligi/ileri-geri: kaynaktaki kayma olcekli aktarilir
	var hs := src.get_bone_global_pose(src.find_bone("DEF-hips")).origin - _src_hips_ref
	var hi := target.find_bone("Hips")
	if _straight > 0.0 and not _stand.is_empty():
		hs = hs.lerp(src.get_bone_global_pose(src.find_bone("DEF-hips")).origin - _src_hips_idle, _straight)
	var hp := _tgt_hips_rest + _C * (hs * _hips_s)
	target.set_bone_pose_position(hi, hp)
	if current in GROUND_CLIPS and weight >= 1.0:
		# Ayak kilidi: alttaki ayak dinlenme durusundaki yerde kalir (havada/yere gomulu durmasin)
		var fy := minf(target.get_bone_global_pose(target.find_bone("LeftFoot")).origin.y,
			target.get_bone_global_pose(target.find_bone("RightFoot")).origin.y)
		var parent := target.get_bone_parent(hi)
		var up := Vector3.UP
		if parent >= 0:
			up = target.get_bone_global_pose(parent).basis.inverse() * Vector3.UP
		hp += up * (_tgt_foot_y - fy)
		target.set_bone_pose_position(hi, hp)
