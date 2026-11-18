extends RefCounted
## --trafficdbg[=sn]: trafigi belirli bir sure izler ve sayilari yazar (arac sayisi, ortalama hiz, ic ice gecme,
## takilan arac, bina / park etmis arac icinden gecme, goz onunde belirme). Yalnizca dugum konumlarina bakar;
## trafik kodunun ic yapisindan bagimsizdir (duzeltme oncesi ve sonrasi ayni olcum).

const ParkMap = preload("res://scripts/park_map.gd")
const Car = preload("res://scripts/car.gd")


## Aracin yari boyu ve yari eni (m).
static func extent(o: Node3D) -> Vector2:
	if o.get("line") != null:
		return Vector2(6.0, 1.3)
	if o.get("rider") != null:
		return Vector2(0.9, 0.35)
	if o.has_meta("kind") and str(o.get_meta("kind")) != "araba":
		return Vector2(0.9, 0.35)
	if o.get_child_count() > 0 and o.get_child(0).has_meta("model") and str(o.get_child(0).get_meta("model")) == "dolmus":
		return Vector2(2.7, 1.0)
	return Vector2(2.05, 0.9)


## Iki yonlu dikdortgen kesisiyor mu (ayirici eksen).
static func obb_hit(pa: Vector2, fa: Vector2, ea: Vector2, pb: Vector2, fb: Vector2, eb: Vector2) -> bool:
	var d := pb - pa
	if d.length_squared() > (ea.x + eb.x) * (ea.x + eb.x) + 4.0:
		return false
	var ra := Vector2(-fa.y, fa.x)
	var rb := Vector2(-fb.y, fb.x)
	for ax: Vector2 in [fa, ra, fb, rb]:
		var ha := absf(ax.dot(fa)) * ea.x + absf(ax.dot(ra)) * ea.y
		var hb := absf(ax.dot(fb)) * eb.x + absf(ax.dot(rb)) * eb.y
		if absf(d.dot(ax)) > ha + hb:
			return false
	return true


static func run(m: Node, secs: float) -> void:
	var tree := m.get_tree()
	var t := 0.0
	var acc := 0.0
	var samples := 0
	var count_sum := 0
	var near_sum := 0
	var dist_sum := 0.0          # toplam yol (m)
	var time_sum := 0.0          # toplam arac-saniye
	var last := {}               # arac -> son konum
	var still := {}              # arac -> kesintisiz durma suresi
	var max_still := {}          # arac -> en uzun durma
	var pairs := {}              # ic ice gecmis ciftler (anahtar) -> true
	var overlap_events := 0
	var overlap_time := 0.0
	var in_building := 0
	var in_parked := 0
	var pop_in := 0              # goz onunde (kamera gorusunde, 110 m icinde) belirme / isinlanma
	var jumps := 0
	var seen := {}
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	var last_ms := Time.get_ticks_msec()
	while t < secs:
		await tree.process_frame
		var now := Time.get_ticks_msec()
		var dt := minf((now - last_ms) / 1000.0, 0.25)
		last_ms = now
		t += dt
		acc += dt
		if acc < 0.1:
			continue
		var step := acc
		acc = 0.0
		samples += 1
		var me: Vector2 = m._owner_pos()
		var list: Array = []
		for o in Car.traffic:
			if not is_instance_valid(o) or not o.is_inside_tree() or not o.is_visible_in_tree() or o == m._ride:
				continue
			list.append(o)
		count_sum += list.size()
		var info: Array = []
		for o: Node3D in list:
			var p := Vector2(o.global_position.x, o.global_position.z)
			var f := Vector2(-sin(o.global_rotation.y), -cos(o.global_rotation.y))
			info.append([p, f, extent(o) * 0.92])
			if p.distance_to(me) < 150.0:
				near_sum += 1
			var id := o.get_instance_id()
			seen[id] = true
			if last.has(id):
				var mv: float = p.distance_to(last[id])
				if mv > 12.0:
					jumps += 1
					if cam and p.distance_to(me) < 110.0 and cam.is_position_in_frustum(o.global_position + Vector3(0, 1, 0)):
						pop_in += 1
				else:
					dist_sum += mv
					time_sum += step
					if mv < 0.03:
						still[id] = float(still.get(id, 0.0)) + step
						max_still[id] = maxf(float(max_still.get(id, 0.0)), still[id])
					else:
						still[id] = 0.0
			elif t > 2.0 and cam and p.distance_to(me) < 110.0 and cam.is_position_in_frustum(o.global_position + Vector3(0, 1, 0)):
				pop_in += 1
			last[id] = p
			if o.get("line") == null:
				if m.world.inside_building_poly(p):
					in_building += 1
				elif not m.world.is_free(p, 0.7):
					in_parked += 1
		var now_pairs := {}
		for i in list.size():
			for j in range(i + 1, list.size()):
				if obb_hit(info[i][0], info[i][1], info[i][2], info[j][0], info[j][1], info[j][2]):
					var key := "%d_%d" % [list[i].get_instance_id(), list[j].get_instance_id()]
					now_pairs[key] = true
					overlap_time += step
					if not pairs.has(key):
						overlap_events += 1
		pairs = now_pairs
	var stuck := 0
	var longest := 0.0
	for id in max_still:
		longest = maxf(longest, max_still[id])
		if float(max_still[id]) > 35.0:
			stuck += 1
	var n := maxi(samples, 1)
	print("TRAFIK sure=%.0f sn  arac(ort)=%.1f  oyuncuya 150 m icinde(ort)=%.1f  farkli arac=%d" % [t, float(count_sum) / n, float(near_sum) / n, seen.size()])
	print("TRAFIK ortalama hiz=%.1f km/sa  ic ice gecme: %d olay, %.1f arac-sn  takilan (35 sn+ kipirtisiz)=%d  en uzun durma=%.0f sn" % [
		dist_sum / maxf(time_sum, 0.001) * 3.6, overlap_events, overlap_time, stuck, longest])
	print("TRAFIK bina icinde=%d ornek  engel/park etmis arac icinde=%d ornek  isinlanma=%d  goz onunde belirme=%d" % [in_building, in_parked, jumps, pop_in])
