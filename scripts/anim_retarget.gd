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
var current := ""


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
	# Eksen donusumu: yukari (kalca->bas) ve sol (sol uyluk - sag uyluk) iki iskelette eslesir
	var su := (_gpos(src, "DEF-head") - _gpos(src, "DEF-hips")).normalized()
	var sl := (_gpos(src, "DEF-thigh.L") - _gpos(src, "DEF-thigh.R")).normalized()
	var tu := (_tpos("Head") - _tpos("Hips")).normalized()
	var tl := (_tpos("LeftUpLeg") - _tpos("RightUpLeg")).normalized()
	var bs := Basis(sl, su, sl.cross(su).normalized()).orthonormalized()
	var bt := Basis(tl, tu, tl.cross(tu).normalized()).orthonormalized()
	_C = (bt * bs.inverse()).get_rotation_quaternion()
	_hips_s = (_tpos("Head") - _tpos("LeftFoot")).length() / maxf((_gpos(src, "DEF-head") - _gpos(src, "DEF-foot.L")).length(), 0.001)
	_src_hips_ref = src.get_bone_global_pose(src.find_bone("DEF-hips")).origin
	_tgt_hips_rest = target.get_bone_rest(target.find_bone("Hips")).origin
	for i in target.get_bone_count():
		var nm := target.get_bone_name(i)
		var sname := _src_name(nm)
		var si := src.find_bone(sname) if sname != "" else -1
		_pairs.append([i, si])
		if si >= 0:
			_sref[si] = sg[si]
			# Hedef kemigin notr yonunu kaynagin referans yonune ceviren hizalama
			# Ayni kemige eslesen cocuk uzerinden yon (iki iskelette de ayni zincir)
			var tdir := Vector3.ZERO
			var sdir := Vector3.ZERO
			for c in target.get_bone_children(i):
				var sc := src.find_bone(_src_name(target.get_bone_name(c)))
				if sc >= 0 and src.get_bone_parent(sc) == si:
					tdir = (tg[i] * target.get_bone_rest(c).origin).normalized()
					sdir = _C * (sg[si] * src.get_bone_pose_position(sc)).normalized()
					break
			var a := Quaternion.IDENTITY
			if tdir != Vector3.ZERO and sdir != Vector3.ZERO:
				a = Quaternion(tdir, sdir) if tdir.dot(sdir) > -0.999 else Quaternion(Vector3.UP, PI)
			_align[i] = a * tg[i]


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
	for pr in _pairs:
		var i: int = pr[0]
		var si: int = pr[1]
		var p := target.get_bone_parent(i)
		var pg: Quaternion = tg[p] if p >= 0 else Quaternion.IDENTITY
		var g: Quaternion
		if si >= 0:
			var delta: Quaternion = sg[si] * (_sref[si] as Quaternion).inverse()
			g = _C * delta * _C.inverse() * _align[i]
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
	target.set_bone_pose_position(hi, _tgt_hips_rest + _C * (hs * _hips_s))
