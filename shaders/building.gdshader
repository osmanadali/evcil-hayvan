shader_type spatial;

// Apartmanlar: sivali duvar dokusu, kat kat pencere ve balkonlar, kiremit ya da beton cati.
// UV = (duvar boyunca metre, yukseklik metre), UV2 = (bina yuksekligi, rastgele tohum), COLOR = cephe rengi.
// Oyuncu ile kamera arasina giren duvarlar delinir (focus).
uniform vec3 focus = vec3(0.0, -1000.0, 0.0);
uniform float see_radius = 5.5;
uniform float night = 0.0;
// Evdeyken: bu kutunun icinde ve evin zemininden yukarida kalan bina parcalari cizilmez (ust katlar ve cati)
uniform vec2 hide_c = vec2(0.0, 1e6);
uniform vec2 hide_axis = vec2(1.0, 0.0);
uniform vec2 hide_half = vec2(0.0, 0.0);
uniform float hide_y = 1e6;       // 0 gunduz, 1 gece: pencerelerde isik yanar
uniform sampler2D t_wall : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_roof : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_flat : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_wall : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_roof : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wpos;
varying vec3 wnormal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float box(vec2 p, vec2 lo, vec2 hi) { return step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = NORMAL;
	// Kabarti dokulari icin teget: duvarda yatay, catida egim boyunca
	vec3 t = abs(NORMAL.y) < 0.95 ? cross(vec3(0.0, 1.0, 0.0), NORMAL) : vec3(1.0, 0.0, 0.0);
	TANGENT = normalize(t);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	vec2 hd = wpos.xz - hide_c;
	if (wpos.y > hide_y && abs(dot(hd, hide_axis)) < hide_half.x && abs(dot(hd, vec2(-hide_axis.y, hide_axis.x))) < hide_half.y) {
		discard;
	}
	// Kameradan oyuncuya giden cizginin cevresini bosalt
	vec3 c = CAMERA_POSITION_WORLD;
	vec3 cf = focus + vec3(0.0, 0.9, 0.0) - c;
	float t = dot(wpos - c, cf) / dot(cf, cf);
	if (t > 0.0 && t < 0.97) {
		float d = length(c + cf * t - wpos);
		float r = see_radius * (0.35 + 0.65 * t);
		if (d < r * (0.8 + 0.2 * hash(floor(FRAGCOORD.xy * 0.5)))) {
			discard;
		}
	}

	vec3 tint = pow(COLOR.rgb, vec3(2.2));
	float seed = UV2.y;
	float h = UV2.x;
	if (h < 0.0 && h > -1.5) {
		// Balkon parcalari: duz renk
		ALBEDO = tint * (0.9 + 0.1 * texture(t_wall, wpos.xz * 0.3).r);
		ROUGHNESS = 0.9;
	} else if (h >= 0.0 && wnormal.y > 0.5) {
		if (seed < 0.5) {
			// Kiremit: sira yonu egime gore
			vec2 dir = normalize(wnormal.xz + vec2(0.0001));
			vec2 ruv = vec2(dot(wpos.xz, vec2(-dir.y, dir.x)), dot(wpos.xz, dir) * 1.15) * 0.42;
			ALBEDO = texture(t_roof, ruv).rgb * vec3(0.95, 0.82, 0.78) * (0.85 + 0.3 * hash(vec2(seed * 91.0, 3.0)));
			NORMAL_MAP = texture(n_roof, ruv).rgb;
			NORMAL_MAP_DEPTH = 1.5;
		} else {
			ALBEDO = texture(t_flat, wpos.xz * 0.2).rgb * vec3(1.15, 1.13, 1.1);
		}
		ROUGHNESS = 0.95;
	} else {
		vec3 plaster = texture(t_wall, UV * vec2(0.22, 0.22) + seed * 7.0).rgb * 1.45;
		vec3 wall = plaster * tint;
		vec2 cellf = vec2(UV.x / 3.1, UV.y / 3.0);
		vec2 id = floor(cellf);
		vec2 cell = fract(cellf);
		bool ground = UV.y < 3.0;
		float r = hash(id * 1.7 + seed * 31.0);
		float col_r = hash(vec2(id.x, seed * 57.0));
		// Kat silmesi, zemin kat (tas kaplama), sacak alti
		wall *= 1.0 - 0.22 * (smoothstep(0.045, 0.0, cell.y) + smoothstep(0.955, 1.0, cell.y));
		if (ground) {
			wall = plaster * mix(tint, vec3(0.42, 0.4, 0.38), 0.7);
		}
		wall *= mix(0.72, 1.0, smoothstep(h - 0.35, h - 0.7, UV.y));
		// Yagmur izi: pencere altlarinda hafif kararma
		wall *= 1.0 - 0.1 * box(cell, vec2(0.26, 0.0), vec2(0.74, 0.26)) * (1.0 - cell.y * 3.0);

		float top_ok = step(UV.y, h - 0.7) * step(0.0, UV.y);   // bodrum kaidesinde (UV.y < 0) pencere yok
		if (UV.y < 0.0) {
			// Bodrum kaidesi: koyu tas kaplama, yatay derzler
			wall = plaster * vec3(0.5, 0.48, 0.45) * (1.0 - 0.18 * smoothstep(0.06, 0.0, fract(UV.y / 0.5)));
		}
		vec3 col = wall;
		float rough = 0.92;
		bool balcony = !ground && mod(id.x, 3.0) == 1.0;
		vec2 lo = ground ? vec2(0.16, 0.1) : (balcony ? vec2(0.2, 0.12) : vec2(0.26, 0.32));
		vec2 hi = ground ? vec2(0.84, 0.8) : (balcony ? vec2(0.8, 0.82) : vec2(0.74, 0.8));
		float win = box(cell, lo, hi) * top_ok;
		float lit = 0.0;
		// Bina basina pencere dogramasi: beyaz PVC, kahve PVC ya da eski ahsap
		float fr = hash(vec2(seed * 13.0, 7.0));
		vec3 frame_c = fr < 0.55 ? vec3(0.9, 0.9, 0.88) : (fr < 0.85 ? vec3(0.32, 0.2, 0.13) : vec3(0.55, 0.42, 0.3));
		if (win > 0.5) {
			// Gomme pencere (paralaks): dunyada duvar boyunca yon, bakis yonu, 18 cm derinlik
			vec3 nrm = normalize(wnormal);
			vec3 along = normalize(vec3(-nrm.z, 0.0, nrm.x));
			vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
			float vz = max(dot(V, nrm), 0.08);
			vec2 vt = vec2(dot(V, along), V.y);
			float depth = 0.18;
			vec2 uv_in = UV - vt * depth / vz;
			vec2 cell_in = vec2(uv_in.x / 3.1, uv_in.y / 3.0) - id;
			vec2 q = (cell_in - lo) / (hi - lo);
			if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) {
				// Pervaz: yan yuzler golgede, ust yuz (lento) daha koyu, alt yuz (denizlik) acik
				float shade = q.y > 1.0 ? 0.5 : (q.y < 0.0 ? 0.95 : 0.68);
				col = plaster * tint * shade;
				if (q.y < 0.0) {
					col = vec3(0.82, 0.8, 0.76);
				}
				rough = 0.9;
			} else {
				float frame = 1.0 - box(q, vec2(0.05, 0.06), vec2(0.95, 0.94));
				float mull = step(abs(q.x - 0.5), 0.02) + (ground ? 0.0 : step(abs(q.y - 0.68), 0.018));
				// Camin arkasi: 3 m derinlikte oda (tavan, arka duvar, zemin)
				vec2 uv_room = UV - vt * 3.0 / vz;
				vec2 rq = (vec2(uv_room.x / 3.1, uv_room.y / 3.0) - id - lo) / (hi - lo);
				float wall_hue = hash(id + seed * 3.0);
				vec3 room = mix(vec3(0.26, 0.23, 0.2), vec3(0.46, 0.42, 0.37), wall_hue);
				room = rq.y > 0.92 ? vec3(0.34, 0.33, 0.31) : (rq.y < 0.04 ? vec3(0.2, 0.13, 0.08) : room);
				room *= 0.55 + 0.45 * smoothstep(-0.6, 0.6, rq.x) * smoothstep(1.6, 0.4, rq.x);
				// Yansima: aciya gore gokyuzu ve karsidaki binalar
				float fres = 0.18 + 0.75 * pow(1.0 - vz, 3.0);
				vec3 refl = mix(vec3(0.42, 0.5, 0.56), vec3(0.62, 0.74, 0.86), smoothstep(-0.2, 0.6, -V.y + q.y * 0.4));
				vec3 glass = mix(room, refl, fres);
				if (r > 0.72) {
					// Tul perde (bazi pencerelerde yarim cekili)
					float cur = step(q.x, 0.35 + 0.6 * hash(id + 9.0)) * (0.75 + 0.1 * sin(q.x * 90.0));
					glass = mix(glass, vec3(0.86, 0.83, 0.76) * (0.75 + 0.25 * (1.0 - fres)), cur * 0.85);
				} else if (r < 0.18) {
					// Yarim inik panjur
					float sh = step(1.0 - 0.6 * hash(id + 4.0), q.y);
					glass = mix(glass, vec3(0.7, 0.69, 0.66) * (0.9 + 0.1 * step(0.5, fract(q.y * 26.0))), sh);
				}
				if (ground) {
					glass = mix(vec3(0.09, 0.1, 0.12), vec3(0.3, 0.36, 0.42), q.y * 0.7);
				}
				col = mix(glass, frame_c, clamp(frame + mull, 0.0, 1.0));
				rough = mix(0.08, 0.6, clamp(frame + mull, 0.0, 1.0));
				lit = step(hash(id + 31.0), 0.25 + 0.5 * night) * step(0.35, night + 0.3 * hash(id + 17.0) - 0.15) * (1.0 - clamp(frame + mull, 0.0, 1.0));
			}
		}
		// Panjur kutusu (pencerenin ustunde), pervaz golgesi
		if (!ground && !balcony) {
			col = mix(col, frame_c * 0.92, box(cell, vec2(lo.x, hi.y), vec2(hi.x, hi.y + 0.05)) * top_ok);
		}
		col *= 1.0 - 0.25 * (box(cell, vec2(lo.x - 0.04, lo.y - 0.05), vec2(hi.x + 0.04, hi.y + 0.06)) * (1.0 - win)) * top_ok;
		NORMAL_MAP = mix(texture(n_wall, UV * vec2(0.22, 0.22) + seed * 7.0).rgb, vec3(0.5, 0.5, 1.0), win);
		NORMAL_MAP_DEPTH = 1.3;
		if (h < -1.5) {
			// Korkuluk: dikey cubuklar arasi bos, ust kupeste ve alt kusak dolu
			float bar = step(fract(UV.x * 8.5), 0.18) + step(0.9, UV.y) + step(UV.y, 0.08);
			if (bar < 0.5) {
				discard;
			}
			col = tint * 0.55;
			rough = 0.4;
		}
		ALBEDO = col;
		EMISSION = mix(vec3(1.0, 0.74, 0.4), vec3(0.85, 0.9, 1.0), step(0.8, hash(id + 3.0))) * lit * night * 1.3;
		ROUGHNESS = rough;
		SPECULAR = 0.4;
	}
}
