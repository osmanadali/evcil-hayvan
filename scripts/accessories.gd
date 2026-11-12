extends RefCounted
## Aksesuar katalogu ve modelleri. Her aksesuar hayvanin bir baglanti noktasina takilir.
## Olculer hayvanin iskelet uzayinda (govde boyu 1).

const Kit = preload("res://scripts/kit.gd")

# id: [ad, yuva, fiyat]
const ITEMS := {
	"hasir_sapka": ["Hasır Şapka", "hat", 40],
	"parti_sapkasi": ["Parti Şapkası", "hat", 30],
	"bere": ["Bere", "hat", 45],
	"tac": ["Taç", "hat", 150],
	"kovboy": ["Kovboy Şapkası", "hat", 80],
	"gozluk": ["Yuvarlak Gözlük", "face", 50],
	"gunes_gozlugu": ["Güneş Gözlüğü", "face", 70],
	"tasma_kirmizi": ["Kırmızı Tasma", "neck", 0],
	"tasma_mavi": ["Mavi Tasma", "neck", 25],
	"fular": ["Fular", "neck", 35],
	"papyon": ["Papyon", "neck", 45],
	"patik_kirmizi": ["Kırmızı Patik", "paws", 60],
	"patik_sari": ["Sarı Patik", "paws", 60],
	"sirt_cantasi": ["Sırt Çantası", "back", 90],
	"pelerin": ["Pelerin", "back", 110],
}
const SLOTS := {"hat": "Şapka", "face": "Gözlük", "neck": "Boyun", "paws": "Patik", "back": "Sırt"}


static func build(id: String, neck_r := 0.15, face_w := 0.085) -> Node3D:
	var n := Node3D.new()
	match id:
		"hasir_sapka":
			n.rotation = Vector3(0.1, 0, -0.08)
			Kit.cyl(n, 0.29, 0.31, 0.025, Vector3.ZERO, Kit.mat("d9c078"), 18)
			Kit.cyl(n, 0.14, 0.17, 0.13, Vector3(0, 0.07, 0), Kit.mat("d9c078"), 18)
			Kit.cyl(n, 0.172, 0.176, 0.04, Vector3(0, 0.035, 0), Kit.mat("b8433a"), 18)
		"parti_sapkasi":
			Kit.cyl(n, 0.01, 0.13, 0.32, Vector3(0, 0.15, 0), Kit.checker(Color("d95f76"), Color("f2c94c"), 8, 3), 14)
			Kit.ball(n, 0.045, Vector3(0, 0.32, 0), Kit.mat("ffffff"))
		"bere":
			Kit.ball(n, 0.19, Vector3(0, 0.02, 0), Kit.mat("3f6fa8"), Vector3(1, 0.75, 1))
			Kit.torus(n, 0.15, 0.2, Vector3(0, -0.02, 0), Kit.mat("ece6d8"))
			Kit.ball(n, 0.06, Vector3(0, 0.17, 0), Kit.mat("ece6d8"))
		"tac":
			var gold := Kit.mat("e9b93a", 0.25)
			Kit.cyl(n, 0.14, 0.13, 0.08, Vector3(0, 0.04, 0), gold, 14)
			for i in 6:
				var a := i * TAU / 6.0
				Kit.cyl(n, 0.005, 0.04, 0.1, Vector3(cos(a) * 0.12, 0.12, sin(a) * 0.12), gold, 5)
				Kit.ball(n, 0.022, Vector3(cos(a) * 0.135, 0.045, sin(a) * 0.135), Kit.mat(["c8452f", "3f6fa8"][i % 2], 0.2), Vector3.ONE, 6)
		"kovboy":
			var brown := Kit.mat("7d5236")
			Kit.cyl(n, 0.32, 0.3, 0.02, Vector3.ZERO, brown, 18)
			Kit.cyl(n, 0.12, 0.16, 0.16, Vector3(0, 0.08, 0), brown, 14)
			Kit.cyl(n, 0.165, 0.165, 0.035, Vector3(0, 0.03, 0), Kit.mat("3a2a22"), 14)
		"gozluk", "gunes_gozlugu":
			var dark := id == "gunes_gozlugu"
			var frame := Kit.mat("2b2b2e" if dark else "b8433a", 0.4)
			var lens := Kit.mat("1d1d22" if dark else "cfe6f2", 0.1)
			for sx in [-1.0, 1.0]:
				Kit.torus(n, face_w * 0.62, face_w * 0.8, Vector3(sx * face_w, 0, 0), frame, Vector3(PI / 2, 0, 0))
				Kit.cyl(n, face_w * 0.62, face_w * 0.62, 0.008, Vector3(sx * face_w, 0, 0), lens, 12, Vector3(PI / 2, 0, 0))
				Kit.box(n, Vector3(0.012, 0.012, 0.2), Vector3(sx * face_w * 1.85, 0, 0.1), frame)
			Kit.box(n, Vector3(face_w * 0.5, 0.012, 0.012), Vector3.ZERO, frame)
		"tasma_kirmizi", "tasma_mavi":
			Kit.torus(n, neck_r * 0.82, neck_r * 1.05, Vector3.ZERO, Kit.mat("b8433a" if id == "tasma_kirmizi" else "3f6fa8", 0.6), Vector3(-0.5, 0, 0))
			Kit.ball(n, 0.03, Vector3(0, -neck_r * 0.75, -neck_r * 0.8), Kit.mat("e9b93a", 0.3))
		"fular":
			Kit.torus(n, neck_r * 0.8, neck_r * 1.08, Vector3.ZERO, Kit.mat("c8452f"), Vector3(-0.5, 0, 0))
			Kit.prism(n, Vector3(0.2, 0.17, 0.03), Vector3(0, -neck_r * 0.95, -neck_r * 0.85), Kit.mat("c8452f"), Vector3(0.5, 0, PI))
		"papyon":
			Kit.torus(n, neck_r * 0.82, neck_r * 1.0, Vector3.ZERO, Kit.mat("2b2b2e"), Vector3(-0.5, 0, 0))
			for sx in [-1.0, 1.0]:
				Kit.prism(n, Vector3(0.09, 0.09, 0.03), Vector3(sx * 0.05, -neck_r * 0.62, -neck_r * 0.95), Kit.mat("3f6fa8"), Vector3(0, 0, sx * PI / 2))
			Kit.ball(n, 0.022, Vector3(0, -neck_r * 0.62, -neck_r * 0.97), Kit.mat("2b2b2e"))
		"patik_kirmizi", "patik_sari":
			var c := "b8433a" if id == "patik_kirmizi" else "e9b93a"
			Kit.ball(n, 0.062, Vector3(0, 0, -0.01), Kit.mat(c, 0.6), Vector3(1, 0.85, 1.25))
			Kit.torus(n, 0.04, 0.06, Vector3(0, 0.045, 0), Kit.mat("ece6d8"))
		"sirt_cantasi":
			Kit.box(n, Vector3(0.2, 0.14, 0.24), Vector3(0, 0.06, 0), Kit.mat("5d9e6b"))
			Kit.box(n, Vector3(0.16, 0.06, 0.2), Vector3(0, 0.15, 0), Kit.mat("4c8a5a"))
			Kit.box(n, Vector3(0.22, 0.03, 0.05), Vector3(0, 0.0, -0.08), Kit.mat("3a2a22"))
		"pelerin":
			var cape := StandardMaterial3D.new()
			cape.albedo_color = Color("8f3a5a")
			cape.cull_mode = BaseMaterial3D.CULL_DISABLED
			Kit.box(n, Vector3(0.3, 0.02, 0.5), Vector3(0, 0.02, 0.12), cape, Vector3(-0.12, 0, 0))
			Kit.ball(n, 0.03, Vector3(0, 0.03, -0.12), Kit.mat("e9b93a", 0.3))
	return n
