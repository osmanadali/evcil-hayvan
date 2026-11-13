class_name Weather
extends Node3D

const Kit = preload("res://scripts/kit.gd")
## Hava durumu: birkac oyun saatinde bir degisen acik / bulutlu / yagmur / kar / sis.
## Mevsim gercek takvim ayindan gelir (Ankara ortalama sicakliklari); kar soguk aylarda ve gecelerde.
## Gorsel: kameranin cevresinde yagmur damlalari ya da kar taneleri, kararan gokyuzu ve ortam isigi,
## islak zemin ve su birikintileri, yavas yavas beyazlayan zemin ve catilar (shader global'leri),
## yagmur ve ruzgar sesi, uzaktan gok gurultusu. Insanlar yagmurda semsiye acar.

const NAMES := {"acik": "Açık", "bulutlu": "Bulutlu", "yagmur": "Yağmur", "saganak": "Sağanak", "kar": "Kar", "sis": "Sisli"}
const ICONS := {"acik": "sun", "bulutlu": "drop", "yagmur": "drop", "saganak": "bolt", "kar": "star", "sis": "drop"}
## Ankara aylik ortalama sicaklik (Ocak..Aralik)
const MONTH_TEMP := [0.5, 2.0, 6.5, 11.5, 16.5, 20.5, 24.0, 24.0, 19.5, 13.5, 7.0, 2.5]
const UMBRELLA_COLORS := ["1d1f24", "c8323c", "2f5fa8", "e6b03a", "3f7f5a", "6a3d8f", "1d1f24", "d9d4c7"]

## Sahne yeniden kurulsa da (metroyla bolge degisimi) hava surer
static var _keep: Dictionary = {}

var kind := "acik"
var power := 1.0             # su anki yagisin siddeti (0.5..1)
var left := 4.0              # su anki hava kac oyun saati daha surer
var plan: Array = []         # sonraki havalar: [tur, saat, siddet]
var month := 11
var temp := 10.0             # gosterilen sicaklik (yumusak)

# Yumusak gecisli degerler (0..1)
var rain := 0.0
var snow := 0.0
var fog := 0.0
var cloud := 0.0
var wet := 0.0               # zemin islakligi: yagmur bitince yavas kurur
var cover := 0.0             # kar ortusu: yavas birikir, sicakta erir

var indoor := false
var mobile := false
var _rng := RandomNumberGenerator.new()
var _last_clock := -1.0
var _fog_morning := 0.0       # bugun sabah sisi var mi (0..1)
var _rain_fx: GPUParticles3D
var _snow_fx: GPUParticles3D
var _rain_snd: AudioStreamPlayer
var _wind_snd: AudioStreamPlayer
var _thunder_snd: AudioStreamPlayer
var _flash := 0.0
var _thunder_t := 30.0
var _thunder_delay := -1.0
var _umb_t := 0.0
var _cloud_mat: StandardMaterial3D
var forced := false           # --weather ile sabitlendi


func _ready() -> void:
	_rng.randomize()
	month = int(Time.get_date_dict_from_system()["month"])
	mobile = RenderingServer.get_current_rendering_method() != "forward_plus"
	if _keep.is_empty():
		kind = _roll(base_temp(10.0))
		power = _rng.randf_range(0.6, 1.0)
		left = _rng.randf_range(2.0, 5.0)
		_fill_plan()
	else:
		kind = _keep["kind"]
		power = _keep["power"]
		left = _keep["left"]
		plan = _keep["plan"]
		wet = _keep["wet"]
		cover = _keep["cover"]
		_snap()
	_build_fx()
	_build_audio()


## Su anki ay ve saate gore beklenen sicaklik (hava etkisi olmadan).
func base_temp(clock: float) -> float:
	var m: float = MONTH_TEMP[clampi(month - 1, 0, 11)]
	return m + 5.5 * cos((clock - 15.0) / 24.0 * TAU)


func _kind_offset(k: String) -> float:
	match k:
		"bulutlu": return -1.0
		"yagmur": return -2.5
		"saganak": return -3.5
		"kar": return -3.0
		"sis": return -1.5
	return 0.5


## Sicakliga ve mevsime gore rastgele hava sec.
func _roll(t_at: float) -> String:
	var w := {"acik": 42.0, "bulutlu": 30.0, "yagmur": 16.0, "saganak": 5.0, "kar": 0.0, "sis": 3.0}
	if month >= 6 and month <= 8:
		w["acik"] = 62.0
		w["yagmur"] = 6.0
		w["saganak"] = 6.0
		w["sis"] = 0.0
	elif month >= 11 or month <= 2:
		w["bulutlu"] = 36.0
		w["sis"] = 7.0
	if t_at < 4.0:
		var c := clampf((4.0 - t_at) / 6.0, 0.35, 1.0)
		w["kar"] = 26.0 * c
		w["yagmur"] *= clampf(t_at / 4.0, 0.15, 1.0)
		w["saganak"] = 0.0
	var total := 0.0
	for k in w:
		total += w[k]
	var r := _rng.randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "acik"


func _fill_plan() -> void:
	var at := left
	while plan.size() < 5:
		var t := base_temp(fmod(_clock_now() + at, 24.0))
		var prev: String = kind if plan.is_empty() else plan[-1][0]
		var k := _roll(t)
		if k == prev and _rng.randf() < 0.5:
			k = _roll(t)
		var hrs := _rng.randf_range(3.0, 6.0)
		plan.append([k, hrs, _rng.randf_range(0.55, 1.0)])
		at += hrs


func _clock_now() -> float:
	return _last_clock if _last_clock >= 0.0 else 10.0


## Debug / test: havayi hemen ve tam siddette kur.
func force(k: String) -> void:
	var map := {"rain": "yagmur", "storm": "saganak", "snow": "kar", "fog": "sis", "clear": "acik", "cloudy": "bulutlu"}
	kind = map.get(k, k)
	if not NAMES.has(kind):
		kind = "acik"
	power = 1.0
	left = 6.0
	forced = true
	wet = 1.0 if kind == "yagmur" or kind == "saganak" else 0.0
	cover = 1.0 if kind == "kar" else 0.0
	_snap()


func _snap() -> void:
	var tg := _targets()
	rain = tg[0]
	snow = tg[1]
	fog = tg[2]
	cloud = tg[3]


## [yagmur, kar, sis, bulut] hedefleri
func _targets() -> Array:
	match kind:
		"bulutlu": return [0.0, 0.0, 0.0, 0.7]
		"yagmur": return [power * 0.75, 0.0, 0.15, 0.95]
		"saganak": return [1.0, 0.0, 0.25, 1.0]
		"kar": return [0.0, power, 0.18, 0.9]
		"sis": return [0.0, 0.0, 1.0, 0.6]
	return [0.0, 0.0, 0.0, 0.0]


func is_wet_weather() -> bool:
	return rain > 0.25 or snow > 0.35


## Ekrandaki kisa yazi: "Yağmur 9°C"
func hud_text() -> String:
	return "%s %d°C" % [NAMES[kind], int(round(temp))]


func icon() -> String:
	return ICONS.get(kind, "sun")


## Telefon "Hava" uygulamasi icin: [[saat, ad, sicaklik], ...]
func forecast(clock: float) -> Array:
	var out: Array = []
	var at := left
	for p in plan:
		var h := fmod(clock + at, 24.0)
		var tt := base_temp(h) + _kind_offset(p[0])
		if p[0] == "kar":
			tt = minf(tt, 0.0)
		out.append(["%02d:00" % int(h), NAMES[p[0]], int(round(tt))])
		at += float(p[1])
	return out


func describe() -> String:
	match kind:
		"yagmur": return "Yağmur yağıyor. Hayvanın çabuk kirlenir; dükkânlara sığınabilirsin."
		"saganak": return "Sağanak ve gök gürültüsü! Sokaklar su birikintisiyle dolu."
		"kar": return "Kar yağıyor, sokaklar beyaza bürünüyor. Sıkı giyin!"
		"sis": return "Sis var, görüş mesafesi düşük. Araç kullanırken dikkat."
		"bulutlu": return "Hava kapalı ama yağış beklenmiyor."
	return "Hava açık, yürüyüş için harika bir gün."


# ---------------------------------------------------------------- her kare

## Saat, kamera ve ortam: main._update_daylight'tan SONRA cagrilir (onun degerlerini olcekler).
func update(dt: float, clock: float, cam: Camera3D, env: Environment, sun: DirectionalLight3D,
		sky: PanoramaSkyMaterial, clouds: Array, day: float) -> void:
	var first := _last_clock < 0.0
	if first:
		_last_clock = clock
	var prev := _last_clock
	var adv := fposmod(clock - _last_clock, 24.0)
	_last_clock = clock
	if adv < 3.0 and not forced:
		left -= adv
		if left <= 0.0:
			var nx: Array = plan.pop_front()
			kind = nx[0]
			left = float(nx[1])
			power = float(nx[2])
			# Kar sicakta yagmura, yagmur dondurucu soguta kara doner
			var t_now := base_temp(clock)
			if kind == "kar" and t_now > 5.0:
				kind = "yagmur"
			elif (kind == "yagmur" or kind == "saganak") and t_now < 0.5:
				kind = "kar"
			_fill_plan()
	# Sabah sisi: gunde bir kez karar ver (sabah 4.5 - 9.5 arasi)
	if first or (prev < 3.0 and clock >= 3.0):
		_fog_morning = _rng.randf_range(0.5, 0.9) if _rng.randf() < (0.45 if month >= 10 or month <= 3 else 0.2) else 0.0
	var morning := smoothstep(4.0, 5.5, clock) * (1.0 - smoothstep(8.0, 9.8, clock))

	var tg := _targets()
	var k := minf(1.0, dt / 12.0)
	rain = lerpf(rain, tg[0], k)
	snow = lerpf(snow, tg[1], k)
	fog = lerpf(fog, maxf(tg[2], _fog_morning * morning * 0.7), k)
	cloud = lerpf(cloud, tg[3], k)
	var want_t := base_temp(clock) + _kind_offset(kind)
	if kind == "kar":
		want_t = minf(want_t, 0.0)     # kar yagarken sifirin alti
	temp = lerpf(temp, want_t, minf(1.0, dt / 4.0))
	if absf(temp - want_t) > 15.0 or first:
		temp = want_t
	# Islaklik ve kar ortusu (gercek saniye): yagmurda 40 sn'de islanir, 4 dk'da kurur
	if rain > 0.1:
		wet = minf(wet + dt * rain / 40.0, 1.0)
	else:
		wet = maxf(wet - dt / (240.0 if cloud > 0.5 else 150.0), 0.0)
	if snow > 0.1:
		cover = minf(cover + dt * snow / 150.0, 1.0)
		wet = maxf(wet, cover * 0.3)
	elif temp > 1.0:
		cover = maxf(cover - dt * (temp / 8.0) / 200.0, 0.0)
		wet = maxf(wet, cover * 0.8)
	RenderingServer.global_shader_parameter_set("weather_wet", wet)
	RenderingServer.global_shader_parameter_set("weather_snow", cover)
	RenderingServer.global_shader_parameter_set("weather_rain", rain if not indoor else 0.0)
	_keep = {"kind": kind, "power": power, "left": left, "plan": plan, "wet": wet, "cover": cover}

	_update_fx(cam)
	_update_sound(dt)
	if not indoor:
		_apply_env(dt, env, sun, sky, clouds, day)
	else:
		sun.shadow_opacity = 1.0


func _apply_env(dt: float, env: Environment, sun: DirectionalLight3D, sky: PanoramaSkyMaterial,
		clouds: Array, day: float) -> void:
	var over := clampf(maxf(cloud, maxf(rain, snow)), 0.0, 1.0)
	var gloom := maxf(rain, snow * 0.8)
	sun.light_energy *= lerpf(1.0, 0.22, over) * lerpf(1.0, 0.6, fog)
	sun.shadow_opacity = lerpf(1.0, 0.15, over)
	sky.energy_multiplier *= lerpf(1.0, 0.7, over)
	var grey := Color(0.56, 0.6, 0.66) * lerpf(0.12, 1.0, day)
	env.ambient_light_color = env.ambient_light_color.lerp(grey, over * 0.7)
	env.ambient_light_energy *= lerpf(1.0, 1.1, over) * lerpf(1.0, 0.8, gloom)
	# Kapali gokyuzu: sis rengini gri yapip gokyuzunu de boyar
	var fog_c := Color(0.62, 0.65, 0.7) if snow < 0.3 else Color(0.78, 0.8, 0.84)
	env.fog_light_color = env.fog_light_color.lerp(fog_c * lerpf(0.1, 1.0, day), over * 0.85)
	env.fog_sky_affect = over * 0.82
	env.fog_density = 0.0006 + rain * 0.0035 + snow * 0.006 + fog * 0.03
	env.adjustment_saturation = 1.06 - over * 0.28
	# Simsek
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 5.0, 0.0)
		env.ambient_light_energy += _flash * 3.0
		sky.energy_multiplier += _flash * 1.5
	# Bulutlar kapali havada koyulasir
	if _cloud_mat == null and not clouds.is_empty():
		var c: MeshInstance3D = clouds[0]
		_cloud_mat = c.material_override as StandardMaterial3D
	if _cloud_mat:
		var light := lerpf(1.0, 0.5, gloom) * lerpf(1.0, 0.85, cloud)
		_cloud_mat.albedo_color = Color(light, light, light * 1.03)
		_cloud_mat.emission = Color("dfe9f5") * light * lerpf(0.1, 1.0, day)


# ---------------------------------------------------------------- parcaciklar

func _build_fx() -> void:
	# Yagmur: ince, dikey uzayan, yari saydam cizgiler
	_rain_fx = GPUParticles3D.new()
	_rain_fx.amount = 2000 if mobile else 6000
	_rain_fx.lifetime = 1.1
	_rain_fx.local_coords = false
	_rain_fx.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	_rain_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13, 4, 13)
	pm.direction = Vector3(0.08, -1, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 17.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.8
	pm.scale_max = 1.25
	_rain_fx.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.028, 0.85)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.albedo_color = Color(0.8, 0.85, 0.92, 0.5)
	var grad := GradientTexture2D.new()
	grad.fill_from = Vector2(0.5, 0.0)
	grad.fill_to = Vector2(0.5, 1.0)
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(1, 1, 1, 0.0))
	grad.gradient.set_color(1, Color(1, 1, 1, 1.0))
	grad.width = 4
	grad.height = 32
	m.albedo_texture = grad
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.8
	m.distance_fade_max_distance = 4.0
	q.material = m
	_rain_fx.draw_pass_1 = q
	_rain_fx.emitting = false
	add_child(_rain_fx)

	# Kar: yumusak beyaz tanecikler, yavas suzulur ve ruzgarda savrulur
	_snow_fx = GPUParticles3D.new()
	_snow_fx.amount = 2200 if mobile else 7000
	_snow_fx.lifetime = 7.0
	_snow_fx.preprocess = 4.0
	_snow_fx.local_coords = false
	_snow_fx.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	_snow_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sp := ParticleProcessMaterial.new()
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sp.emission_box_extents = Vector3(15, 6, 15)
	sp.direction = Vector3(0.2, -1, 0.1)
	sp.spread = 25.0
	sp.initial_velocity_min = 0.9
	sp.initial_velocity_max = 1.7
	sp.gravity = Vector3(0.25, -0.35, 0.1)
	sp.turbulence_enabled = true
	sp.turbulence_noise_strength = 1.2
	sp.turbulence_noise_scale = 6.0
	sp.turbulence_influence_min = 0.03
	sp.turbulence_influence_max = 0.08
	sp.scale_min = 0.6
	sp.scale_max = 1.4
	_snow_fx.process_material = sp
	var sq := QuadMesh.new()
	sq.size = Vector2(0.09, 0.09)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.albedo_color = Color(1, 1, 1, 0.92)
	var rg := GradientTexture2D.new()
	rg.fill = GradientTexture2D.FILL_RADIAL
	rg.fill_from = Vector2(0.5, 0.5)
	rg.fill_to = Vector2(1.0, 0.5)
	rg.width = 16
	rg.height = 16
	rg.gradient = Gradient.new()
	rg.gradient.set_color(0, Color(1, 1, 1, 1))
	rg.gradient.set_color(1, Color(1, 1, 1, 0))
	smat.albedo_texture = rg
	sq.material = smat
	_snow_fx.draw_pass_1 = sq
	_snow_fx.emitting = false
	add_child(_snow_fx)


func _update_fx(cam: Camera3D) -> void:
	if cam == null:
		return
	var fw := -cam.global_basis.z
	fw.y = 0.0
	var c := cam.global_position + fw.normalized() * 7.0
	var show_rain := rain > 0.03 and not indoor
	var show_snow := snow > 0.03 and not indoor
	_rain_fx.emitting = show_rain
	_snow_fx.emitting = show_snow
	if show_rain:
		_rain_fx.global_position = c + Vector3(0, 11, 0)
		_rain_fx.amount_ratio = clampf(rain * 1.1, 0.05, 1.0)
	if show_snow:
		_snow_fx.global_position = c + Vector3(0, 7, 0)
		_snow_fx.amount_ratio = clampf(snow, 0.05, 1.0)


# ---------------------------------------------------------------- ses

func _loop_player(path: String, db: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStreamWAV = load(path)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(s.get_length() * s.mix_rate)
	var ap := AudioStreamPlayer.new()
	ap.stream = s
	ap.volume_db = db
	add_child(ap)
	return ap


func _build_audio() -> void:
	_rain_snd = _loop_player("res://assets/sfx/yagmur.wav", -60.0)
	_wind_snd = _loop_player("res://assets/sfx/ruzgar.wav", -60.0)
	if ResourceLoader.exists("res://assets/sfx/gok.wav"):
		_thunder_snd = AudioStreamPlayer.new()
		_thunder_snd.stream = load("res://assets/sfx/gok.wav")
		add_child(_thunder_snd)


func _fade(ap: AudioStreamPlayer, amount: float, top_db: float) -> void:
	if ap == null:
		return
	if amount < 0.02:
		if ap.playing:
			ap.stop()
		return
	if not ap.playing:
		ap.play()
	ap.volume_db = top_db + linear_to_db(clampf(amount, 0.001, 1.0))


func _update_sound(dt: float) -> void:
	var muffle := -12.0 if indoor else 0.0
	_fade(_rain_snd, rain, -6.0 + muffle)
	_fade(_wind_snd, maxf(snow * 0.8, rain * 0.3 + fog * 0.0), -14.0 + muffle)
	# Saganakta simsek ve gok gurultusu
	if kind == "saganak" and rain > 0.6:
		_thunder_t -= dt
		if _thunder_t <= 0.0:
			_thunder_t = _rng.randf_range(18.0, 45.0)
			if not indoor:
				_flash = 1.0
			_thunder_delay = _rng.randf_range(0.6, 2.5)
	if _thunder_delay > 0.0:
		_thunder_delay -= dt
		if _thunder_delay <= 0.0 and _thunder_snd:
			_thunder_snd.volume_db = _rng.randf_range(-6.0, 0.0) + muffle
			_thunder_snd.pitch_scale = _rng.randf_range(0.85, 1.1)
			_thunder_snd.play()


# ---------------------------------------------------------------- semsiyeler

## Yagmurda insanlarin cogu semsiye acar (yarim saniyede bir denetlenir).
func update_people(dt: float, people: Array) -> void:
	_umb_t -= dt
	if _umb_t > 0.0:
		return
	_umb_t = 0.5
	var want := rain > 0.3 and not indoor
	for i in people.size():
		var n: Node3D = people[i]
		if not is_instance_valid(n):
			continue
		var u: Node3D = n.get_node_or_null("Semsiye")
		var should := want and (i * 7 + 3) % 10 < 7
		if should and u == null:
			u = make_umbrella(i)
			n.add_child(u)
			u.scale = Vector3(0.3, 0.3, 0.3)
			u.create_tween().tween_property(u, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_delay(float(i % 5) * 0.3)
		elif u != null and should != u.visible:
			u.visible = should


func make_umbrella(i: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Semsiye"
	# Elde, omuz hizasinin biraz onunde; hafif yana yatik
	root.position = Vector3(-0.3, 0.0, -0.05)
	var tilt := Node3D.new()
	tilt.rotation = Vector3(-0.08, 0.0, 0.12)
	root.add_child(tilt)
	var hex: String = UMBRELLA_COLORS[i % UMBRELLA_COLORS.size()]
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(hex)
	cm.roughness = 0.35
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark: StandardMaterial3D = Kit.mat("2a2a2c", 0.4)
	Kit.cyl(tilt, 0.011, 0.011, 0.95, Vector3(0, 1.6, 0), dark, 6)
	# Kanat: sekiz parcali alcak koni + kenarda hafif sarkma
	Kit.cyl(tilt, 0.04, 0.6, 0.24, Vector3(0, 2.0, 0), cm, 8)
	Kit.cyl(tilt, 0.6, 0.62, 0.05, Vector3(0, 1.865, 0), cm, 8)
	Kit.ball(tilt, 0.025, Vector3(0, 2.13, 0), dark, Vector3.ONE, 6)
	# Kivrik sap
	Kit.cyl(tilt, 0.022, 0.022, 0.14, Vector3(0, 1.1, 0), Kit.mat("4a3020", 0.6), 6)
	return root
