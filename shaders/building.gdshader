shader_type spatial;

// Apartmanlar: sivali duvar dokusu, kat kat pencere ve balkonlar, kiremit ya da beton cati.
// UV = (duvar boyunca metre, yukseklik metre), UV2 = (bina yuksekligi, rastgele tohum), COLOR = cephe rengi.
// Oyuncu ile kamera arasina giren duvarlar delinir (focus).
uniform vec3 focus = vec3(0.0, -1000.0, 0.0);
uniform float see_radius = 5.5;
uniform float night = 0.0;       // 0 gunduz, 1 gece: pencerelerde isik yanar
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
	if (h < 0.0) {
		// Balkon parcalari: duz renk
		ALBEDO = tint * (0.9 + 0.1 * texture(t_wall, wpos.xz * 0.3).r);
		ROUGHNESS = 0.9;
	} else if (wnormal.y > 0.5) {
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

		float top_ok = step(UV.y, h - 0.7);
		vec3 col = wall;
		float rough = 0.92;
		bool balcony = !ground && mod(id.x, 3.0) == 1.0;
		// Pencere / balkon kapisi
		vec2 lo = ground ? vec2(0.16, 0.1) : (balcony ? vec2(0.2, 0.12) : vec2(0.26, 0.32));
		vec2 hi = ground ? vec2(0.84, 0.8) : (balcony ? vec2(0.8, 0.82) : vec2(0.74, 0.8));
		float win = box(cell, lo, hi) * top_ok;
		float lit = 0.0;
		if (win > 0.5) {
			vec2 q = (cell - lo) / (hi - lo);
			float frame = 1.0 - box(q, vec2(0.06, 0.07), vec2(0.94, 0.93));
			float mull = step(abs(q.x - 0.5), 0.022) + (ground ? 0.0 : step(abs(q.y - 0.68), 0.02));
			// Cam: ustte gokyuzu yansimasi, altta ic karanligi; bazi pencerelerde perde ya da storlu
			vec3 glass = mix(vec3(0.07, 0.09, 0.12), vec3(0.34, 0.46, 0.58), smoothstep(0.1, 1.0, q.y) * (0.55 + 0.45 * r));
			if (r > 0.72) {
				glass = mix(glass, vec3(0.82, 0.78, 0.7) * (0.8 + 0.2 * hash(id + 5.0)), step(q.y, 0.25 + 0.6 * hash(id + 9.0)) > 0.5 ? 0.0 : 0.85);
			} else if (r < 0.18) {
				glass = mix(glass, vec3(0.75, 0.74, 0.72), step(0.55, q.y) * 0.9);
			}
			if (ground) {
				glass = mix(vec3(0.09, 0.1, 0.12), vec3(0.3, 0.36, 0.42), q.y * 0.7);
			}
			col = mix(glass, vec3(0.9, 0.9, 0.88), clamp(frame + mull, 0.0, 1.0));
			rough = mix(0.3, 0.8, clamp(frame + mull, 0.0, 1.0));
			// Gece: evlerin bir kismi isik yakar (her pencerenin kendi saati var)
			lit = step(hash(id + 31.0), 0.25 + 0.5 * night) * step(0.35, night + 0.3 * hash(id + 17.0) - 0.15) * (1.0 - clamp(frame + mull, 0.0, 1.0));
		}
		// Pencere denizligi
		col = mix(col, vec3(0.8, 0.79, 0.76), box(cell, vec2(lo.x - 0.03, lo.y - 0.035), vec2(hi.x + 0.03, lo.y)) * top_ok * (balcony ? 0.0 : 1.0));
		NORMAL_MAP = mix(texture(n_wall, UV * vec2(0.22, 0.22) + seed * 7.0).rgb, vec3(0.5, 0.5, 1.0), win);
		NORMAL_MAP_DEPTH = 1.3;
		ALBEDO = col;
		EMISSION = mix(vec3(1.0, 0.74, 0.4), vec3(0.85, 0.9, 1.0), step(0.8, hash(id + 3.0))) * lit * night * 1.3;
		ROUGHNESS = rough;
		SPECULAR = 0.4;
	}
}
