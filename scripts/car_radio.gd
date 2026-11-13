extends Node
## Araba radyosu: arabaya binince (iki tekerlilerde yok) calar. N tusu / dokunmatik radyo dugmesi istasyon
## degistirir: Kent FM (lo-fi), Ankara Pop (hicaz arpej + darbuka), Gece Caz (yuruyen bas, swing) ve
## Haber Ankara (sunucu cumleleri + hafif fon). Muzikler GDScript'te sentezlenip dongulu AudioStreamWAV
## olur (arka planda, ilk binişte bir kez). Istasyon adi ve sarki CarPlay ekraninda ve kisa bildirimde.
## Konusma kayitlari varsa assets/sfx/radyo_haber1..4.mp3 calinir; yoksa haber metni ekranda akar.

const SR := 22050
const STATIONS := [
	{"name": "Kent FM 94.6", "genre": "Lo-fi", "color": "8e7cff",
		"songs": ["Yağmurlu Kızılay", "Simit ve Çay", "Dikmen Akşamı", "Çankaya Sokakları"]},
	{"name": "Ankara Pop 101.2", "genre": "Türkçe Pop", "color": "fa3c5a",
		"songs": ["Kalbim Keçiören'de", "Gel Gör Beni", "Yaz Yağmuru", "Ah Bu Şehir"]},
	{"name": "Gece Caz 88.0", "genre": "Caz", "color": "f2a23a",
		"songs": ["Ulus'ta Gece Yarısı", "Mavi Tramvay", "Kuğulu Blues", "Hamamönü Swing"]},
	{"name": "Haber Ankara 99.9", "genre": "Haber · Sohbet", "color": "30b0ff", "talk": true, "songs": []},
]
const NEWS := [
	"Ankara'da hava parçalı bulutlu, akşama doğru serinliyor.",
	"Keçiören'de trafik akıcı, Etlik yolunda hafif yoğunluk var.",
	"Altınpark'ta hafta sonu evcil hayvan şenliği düzenleniyor.",
	"Metro seferleri bu akşam yarım saat uzatıldı.",
	"Belediye sokak hayvanları için yeni mama kapları yerleştirdi.",
	"Dinleyicimiz Ayşe Hanım, kedisi Pamuk için şarkı istedi.",
]
const SONG_SECS := 48.0          # her "sarki" bu kadar surer; sonra ad ve perde degisir
const PITCHES := [1.0, 0.944, 1.06, 0.89]

var m: Node
var station := 0                 # -1 kapali
var playing := false
var song_title := ""
var _player: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _streams: Array = [null, null, null, null]
var _bufs: Array = [null, null, null, null]
var _tasks: Array = [-1, -1, -1, -1]
var _clips: Array = []
var _song := 0
var _song_t := 0.0
var _news_i := 0
var _news_t := 0.0
var _btn: Button


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -11.0
	add_child(_player)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = -4.0
	add_child(_voice)
	for i in 4:
		var p := "res://assets/sfx/radyo_haber%d.mp3" % (i + 1)
		if ResourceLoader.exists(p):
			_clips.append(load(p))


func _exit_tree() -> void:
	for t in _tasks:
		if t >= 0:
			WorkerThreadPool.wait_for_task_completion(t)


## Arabada miyiz (iki tekerliler radyosuz)
func in_car() -> bool:
	return m._ride != null and bool(m.RIDES[m._ride.get_meta("kind")]["hide"])


func on_enter() -> void:
	if not in_car():
		return
	station = int(m.state.d.get("radio", 0))
	if station >= STATIONS.size():
		station = 0
	for i in STATIONS.size():
		_render_async(i)
	_show_button(DisplayServer.is_touchscreen_available())
	_tune(false)


func on_exit() -> void:
	_stop()
	_show_button(false)


## N tusu: siradaki istasyon; sonuncudan sonra kapali.
func cycle() -> void:
	if not in_car():
		m.ui.toast("Radyo sadece arabada çalışır.")
		return
	station += 1
	if station >= STATIONS.size():
		station = -1
	m.state.d["radio"] = station
	_tune(true)


func set_station(i: int) -> void:
	station = clampi(i, -1, STATIONS.size() - 1)
	m.state.d["radio"] = station
	_tune(true)


func label() -> String:
	return "Radyo kapalı" if station < 0 else STATIONS[station]["name"]


func sub_label() -> String:
	if station < 0:
		return "N ile aç"
	return song_title


func color() -> Color:
	return Color("5a5f68") if station < 0 else Color(STATIONS[station]["color"])


func _tune(announce: bool) -> void:
	_stop()
	if station < 0:
		if announce:
			m.ui.toast("Radyo kapatıldı")
		return
	var st: Dictionary = STATIONS[station]
	_song = randi() % maxi(st["songs"].size(), 1)
	_song_t = randf_range(0.0, SONG_SECS * 0.6)
	_news_t = 1.5
	_set_title()
	playing = true
	_start_stream()
	m.state.count("radio", 1)
	if announce:
		m.ui.toast("%s · %s" % [st["name"], song_title])


func _set_title() -> void:
	var st: Dictionary = STATIONS[station]
	if st.get("talk", false):
		song_title = NEWS[_news_i % NEWS.size()]
	else:
		song_title = st["songs"][_song % st["songs"].size()]


func _start_stream() -> void:
	if station < 0:
		return
	var s: AudioStreamWAV = _streams[station]
	if s == null:
		return          # hazirlaniyor; update() hazir olunca baslatir
	_player.stream = s
	_player.pitch_scale = 1.0 if STATIONS[station].get("talk", false) else PITCHES[_song % PITCHES.size()]
	_player.volume_db = -20.0 if STATIONS[station].get("talk", false) else -11.0
	_player.play(randf() * s.get_length() * 0.9)


func _stop() -> void:
	playing = false
	if _player:
		_player.stop()
	if _voice:
		_voice.stop()


func update(dt: float) -> void:
	# Hazirlanan sesleri al
	for i in _tasks.size():
		if _tasks[i] >= 0 and WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks[i] = -1
			_streams[i] = _make_wav(_bufs[i])
			_bufs[i] = null
			if playing and station == i and not _player.playing:
				_start_stream()
	if not playing:
		return
	if not in_car():
		on_exit()
		return
	var st: Dictionary = STATIONS[station]
	if st.get("talk", false):
		_news_t -= dt
		if _news_t <= 0.0 and not _voice.playing:
			_news_i += 1
			_set_title()
			if not _clips.is_empty():
				_voice.stream = _clips[_news_i % _clips.size()]
				_voice.play()
			_news_t = 9.0
	else:
		_song_t += dt
		if _song_t > SONG_SECS:
			_song_t = 0.0
			_song += 1
			_set_title()
			_start_stream()
			m.ui.toast("%s · %s" % [st["name"], song_title])


func _show_button(on: bool) -> void:
	if on and _btn == null:
		_btn = m.UiKit.button(m.ui.hud, "", "sound", func(): cycle(), m.ui.GLASS, Color.WHITE, Vector2(68, 68), 30, 34)
		_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_btn.offset_left = -410
		_btn.offset_top = -126
		_btn.offset_right = -342
		_btn.offset_bottom = -58
	if _btn:
		_btn.visible = on


# ---------------------------------------------------------------- sentez

func _render_async(i: int) -> void:
	if _streams[i] != null or _tasks[i] >= 0:
		return
	_tasks[i] = WorkerThreadPool.add_task(_render.bind(i), false, "radyo")


func _render(i: int) -> void:
	var buf: PackedFloat32Array
	match i:
		0:
			buf = _lofi()
		1:
			buf = _pop()
		2:
			buf = _jazz()
		_:
			buf = _talk_bed()
	_bufs[i] = buf


func _make_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var k := 0.85 / peak
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for s in buf.size():
		bytes.encode_s16(s * 2, int(clampf(buf[s] * k, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = buf.size()
	return w


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Ton: sinus + ikinci/ucuncu harmonik, ustel sonum. Dongunun sonunu asan kisim basa sarar.
static func _tone(b: PackedFloat32Array, t0: float, dur: float, f: float, amp: float, decay: float, h2 := 0.3, h3 := 0.0) -> void:
	var n := b.size()
	var s0 := int(t0 * SR)
	var cnt := int(dur * SR)
	var w := TAU * f / SR
	for s in cnt:
		var tt := float(s) / SR
		var env := exp(-tt * decay) * minf(1.0, tt * 300.0) * minf(1.0, (cnt - s) / 400.0)
		var ph := w * s
		b[(s0 + s) % n] += amp * env * (sin(ph) + h2 * sin(ph * 2.0) + h3 * sin(ph * 3.0))


static func _kick(b: PackedFloat32Array, t0: float, amp: float) -> void:
	var n := b.size()
	var s0 := int(t0 * SR)
	var ph := 0.0
	for s in int(0.28 * SR):
		var tt := float(s) / SR
		var f := 45.0 + 90.0 * exp(-tt * 30.0)
		ph += TAU * f / SR
		b[(s0 + s) % n] += amp * exp(-tt * 11.0) * sin(ph)


## Gurultu vurusu: hp = 0 karanlik (trampet / firca), 1'e yakin parlak (hi-hat / ride)
static func _noise(b: PackedFloat32Array, t0: float, dur: float, amp: float, decay: float, hp: float, rng: RandomNumberGenerator) -> void:
	var n := b.size()
	var s0 := int(t0 * SR)
	var prev := 0.0
	var lp := 0.0
	for s in int(dur * SR):
		var tt := float(s) / SR
		var x := rng.randf() * 2.0 - 1.0
		var y := x - prev * hp       # basit yuksek geciren
		prev = x
		lp = lerpf(lp, y, 0.55 + hp * 0.45)
		b[(s0 + s) % n] += amp * exp(-tt * decay) * lp


static func _lowpass(b: PackedFloat32Array, a: float) -> void:
	var y := 0.0
	for s in b.size():
		y += (b[s] - y) * a
		b[s] = tanh(y * 1.3)


## Kent FM: 80 bpm lo-fi, Am7-Fmaj7-Cmaj7-G7 elektrik piyano, yumusak davul, plak cizirtisi.
func _lofi() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var beat := 60.0 / 80.0
	var b := PackedFloat32Array()
	b.resize(int(beat * 16.0 * SR))
	var chords := [[57, 60, 64, 67], [53, 57, 60, 64], [48, 55, 59, 64], [55, 59, 62, 65]]
	for bar in 4:
		var t := bar * 4.0 * beat
		var ch: Array = chords[bar]
		for nt in ch:
			_tone(b, t + rng.randf() * 0.02, 2.2, _hz(nt), 0.12, 1.4, 0.25, 0.05)
			_tone(b, t + 2.5 * beat, 1.2, _hz(nt), 0.07, 2.5, 0.2)
		_tone(b, t, 1.6, _hz(ch[0] - 12), 0.32, 1.8, 0.1)
		_tone(b, t + 2.5 * beat, 0.9, _hz(ch[0] - 12), 0.24, 3.0, 0.1)
		# ust melodi: pentatonik birkac nota
		for k in 3:
			var mel: int = [69, 72, 76, 74, 72, 67][(bar * 3 + k) % 6]
			_tone(b, t + (0.5 + k * 1.25) * beat, 0.7, _hz(mel), 0.06, 4.0, 0.1)
		for q in 4:
			var qt := t + q * beat
			if q == 0 or q == 2:
				_kick(b, qt + (0.5 * beat if q == 2 else 0.0), 0.5)
			else:
				_noise(b, qt, 0.25, 0.22, 16.0, 0.2, rng)
			for e in 2:
				_noise(b, qt + e * beat * 0.56, 0.06, 0.06, 60.0, 0.95, rng)
	for s in 140:
		var at := rng.randi() % b.size()
		b[at] += rng.randf_range(-0.25, 0.25)
	_lowpass(b, 0.32)
	return b


## Ankara Pop: 118 bpm, Re hicaz arpej, darbuka (dum-tek) ve dortluk kick, ritmik bas.
func _pop() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var beat := 60.0 / 118.0
	var b := PackedFloat32Array()
	b.resize(int(beat * 16.0 * SR))
	var chords := [[62, 66, 69], [67, 70, 74], [60, 63, 67], [62, 66, 69]]
	var scale := [62, 63, 66, 67, 69, 70, 72, 74]
	var mel := [7, 6, 5, 4, 5, 4, 2, 1, 2, 3, 2, 1, 0, 1, 2, 0]
	for bar in 4:
		var t := bar * 4.0 * beat
		var ch: Array = chords[bar]
		for st in 16:
			var nt: int = ch[[0, 1, 2, 1][st % 4]] + (12 if st % 8 >= 4 else 0)
			_tone(b, t + st * beat * 0.25, 0.3, _hz(nt), 0.07, 11.0, 0.5, 0.25)
		for e in 8:
			_tone(b, t + e * beat * 0.5, 0.3, _hz(ch[0] - 24), 0.28, 7.0, 0.35)
		for q in 4:
			_kick(b, t + q * beat, 0.42)
		# darbuka: dum (0, 1.5), tek (1, 2.5, 3, 3.5)
		for d in [0.0, 1.5]:
			_tone(b, t + d * beat, 0.25, 95.0, 0.3, 14.0, 0.2)
		for tk in [1.0, 2.5, 3.0, 3.5]:
			_noise(b, t + tk * beat, 0.08, 0.2, 45.0, 0.9, rng)
		for k in 4:
			var mi: int = mel[(bar * 4 + k) % mel.size()]
			_tone(b, t + k * beat, beat * 0.95, _hz(scale[mi] + 12), 0.09, 2.6, 0.6, 0.3)
	_lowpass(b, 0.7)
	return b


## Gece Caz: 132 bpm swing, ii-V-I-VI, yuruyen kontrbas, ride zil ve piyano vurgu akorlari.
func _jazz() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var beat := 60.0 / 132.0
	var b := PackedFloat32Array()
	b.resize(int(beat * 16.0 * SR))
	var roots := [50, 55, 48, 57]
	var voicings := [[65, 69, 72], [65, 71, 74], [64, 67, 71], [61, 67, 70]]
	for bar in 4:
		var t := bar * 4.0 * beat
		var r: int = roots[bar]
		var nxt: int = roots[(bar + 1) % 4]
		var walk := [r - 12, r - 12 + 4 - (1 if bar != 2 else 0), r - 12 + 7, nxt - 12 + (1 if nxt < r else -1)]
		for q in 4:
			_tone(b, t + q * beat, beat * 1.05, _hz(walk[q]), 0.36, 3.2, 0.45, 0.1)
		for rt in [0.0, 1.0, 1.0 + 2.0 / 3.0, 2.0, 3.0, 3.0 + 2.0 / 3.0]:
			_noise(b, t + rt * beat, 0.35, 0.07, 9.0, 0.97, rng)
			_tone(b, t + rt * beat, 0.4, 5200.0 + rng.randf() * 200.0, 0.01, 8.0, 0.0)
		for q in [1, 3]:
			_noise(b, t + q * beat, 0.05, 0.08, 55.0, 0.98, rng)
			_noise(b, t + q * beat, 0.2, 0.06, 14.0, 0.1, rng)
		var vc: Array = voicings[bar]
		for ct in [1.0 + 2.0 / 3.0, 3.0]:
			for nt in vc:
				_tone(b, t + ct * beat, 0.5, _hz(nt), 0.06, 5.0, 0.3, 0.1)
	_lowpass(b, 0.55)
	return b


## Haber Ankara fonu: yavas yumusak pad ve saat tik takligi.
func _talk_bed() -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	var b := PackedFloat32Array()
	b.resize(int(8.0 * SR))
	for nt in [48, 55, 60, 64, 67]:
		_tone(b, 0.0, 8.0, _hz(nt), 0.08, 0.15, 0.1)
		_tone(b, 4.0, 8.0, _hz(nt + 2), 0.04, 0.3, 0.1)
	for q in 16:
		_noise(b, q * 0.5, 0.04, 0.05 if q % 2 == 0 else 0.03, 70.0, 0.95, rng)
	_lowpass(b, 0.3)
	return b
