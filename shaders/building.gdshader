shader_type spatial;

// Apartmanlar: duvarlarda kat kat pencereler, ustte cati.
// UV = (duvar boyunca metre, yukseklik metre), UV2 = (bina yuksekligi, rastgele tohum), COLOR = cephe rengi.
// Oyuncu ile kamera arasina giren duvarlar delinir (focus).
uniform vec3 focus = vec3(0.0, -1000.0, 0.0);
uniform float see_radius = 5.5;

varying vec3 wpos;
varying float up;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up = NORMAL.y;
}

void fragment() {
	// Kameradan oyuncuya giden cizginin cevresini bosalt
	vec3 c = CAMERA_POSITION_WORLD;
	vec3 cf = focus + vec3(0.0, 0.9, 0.0) - c;
	float t = dot(wpos - c, cf) / dot(cf, cf);
	if (t > 0.0 && t < 0.97) {
		float d = length(c + cf * t - wpos);
		float r = see_radius * (0.35 + 0.65 * t);
		float n = hash(floor(FRAGCOORD.xy * 0.5));
		if (d < r * (0.75 + 0.25 * n)) {
			discard;
		}
	}

	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float seed = UV2.y;
	if (up > 0.5) {
		// Cati: kiremit ya da gri, kenarda parapet
		vec3 roof = mix(vec3(0.42, 0.20, 0.14), vec3(0.33, 0.33, 0.35), step(0.55, seed));
		float tile = 0.9 + 0.1 * sin(wpos.x * 5.0 + wpos.z * 3.0) * sin(wpos.z * 6.0);
		ALBEDO = roof * tile * (0.9 + 0.2 * hash(floor(wpos.xz * 0.7)));
		ROUGHNESS = 0.95;
	} else {
		float h = UV2.x;
		vec2 cellf = vec2(UV.x / 2.9, UV.y / 3.0);
		vec2 id = floor(cellf);
		vec2 cell = fract(cellf);
		bool ground = UV.y < 3.0;
		vec3 wall = base * (0.94 + 0.08 * hash(id + seed * 13.0));
		// Kat silmeleri ve zemin kat bandi
		wall *= mix(1.0, 0.86, smoothstep(0.06, 0.0, cell.y) + smoothstep(0.94, 1.0, cell.y));
		if (ground) {
			wall = mix(wall, base * 0.62, 0.6);
		}
		wall *= mix(0.8, 1.0, smoothstep(h - 0.5, h - 0.75, UV.y));
		// Pencere
		float wx0 = ground ? 0.14 : 0.24;
		float wy0 = ground ? 0.08 : 0.3;
		float in_x = step(wx0, cell.x) * step(cell.x, 1.0 - wx0);
		float in_y = step(wy0, cell.y) * step(cell.y, 0.8);
		float win = in_x * in_y * step(UV.y, h - 0.6);
		float frame = win * (1.0 - step(wx0 + 0.035, cell.x) * step(cell.x, 1.0 - wx0 - 0.035) * step(wy0 + 0.045, cell.y) * step(cell.y, 0.755));
		float r = hash(id * 1.7 + seed * 31.0);
		vec3 glass = mix(vec3(0.16, 0.22, 0.30), vec3(0.42, 0.52, 0.60), r);
		glass = mix(glass, vec3(0.85, 0.80, 0.68), step(0.82, r));          // perde
		glass *= 0.8 + 0.4 * cell.y;
		// Balkon korkulugu (her iki pencereden biri)
		float balcony = (1.0 - step(3.0, UV.y)) * 0.0 + step(0.5, hash(vec2(id.x, seed))) * step(3.0, UV.y) * step(cell.y, 0.3) * step(0.1, cell.y) * in_x;
		vec3 col = mix(wall, glass, win);
		col = mix(col, vec3(0.9, 0.9, 0.88), frame);
		col = mix(col, base * 0.72, balcony);
		ALBEDO = col;
		ROUGHNESS = mix(0.92, 0.25, win * (1.0 - frame));
		SPECULAR = mix(0.3, 0.6, win);
	}
}
