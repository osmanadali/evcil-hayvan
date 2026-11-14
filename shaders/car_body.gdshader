shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;
// Arac govdesi: dokudaki koyu, renksiz cam bolgeleri (bel cizgisinin ustu) yari saydam olur;
// boylece iceride koltuklar, surucu ve hayvan gorunur (cam koyu degil, berrak).
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float belt = 0.235;        // model biriminde bel cizgisi (bunun ustu cam olabilir)
uniform float glass_alpha = 0.16;      // berrak cam: ic mekan (koltuklar, surucu) net gorunur
varying float vy;
varying float outward;
varying float side_n;

void vertex() {
	vy = VERTEX.y;
	side_n = abs(NORMAL.x);
	// Tripo modelinde camlarin icinde ikinci (ice bakan) koyu bir kabuk var: disaridan bakinca karsi
	// taraftaki camlar opak gorunuyordu. Normali arac merkezine donuk yuzler cam hizasinda atilir.
	outward = dot(NORMAL, normalize(VERTEX - vec3(0.0, 0.2, 0.0)));
}

void fragment() {
	if (vy > belt && outward < 0.0) {
		discard;
	}
	vec3 c = texture(albedo_tex, UV).rgb;
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	// Dokuda yan camlar orta gri (0.35-0.6), on/arka camlar koyu; koyu yan cerceve ve direkler opak kalir
	float side = smoothstep(0.55, 0.75, side_n);
	float lower = mix(1.0, smoothstep(0.24, 0.32, lum), side);
	float glass = step(belt, vy) * lower * (1.0 - smoothstep(0.58, 0.68, lum))
			* (1.0 - smoothstep(0.08, 0.16, sat));
	ALBEDO = mix(c, vec3(0.55, 0.62, 0.66), glass * 0.85);
	ROUGHNESS = mix(0.32, 0.04, glass);
	METALLIC = mix(0.25, 0.0, glass);
	SPECULAR = mix(0.5, 0.9, glass);
	ALPHA = mix(1.0, glass_alpha, glass);
}
