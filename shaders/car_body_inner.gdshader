shader_type spatial;
render_mode cull_front, depth_draw_opaque;
// Arac govdesinin ic yuzu (dis kabugun arka yuzleri): iceriden bakinca gercek A/B direkleri, tavan ve
// kapi sacı gorunur. Bel cizgisinin ustu acik gri tavan kumasi, alti koyu doseme; camlar atilir.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float belt = 0.235;
uniform vec3 liner : source_color = vec3(0.62, 0.61, 0.58);
uniform vec3 lower_col : source_color = vec3(0.12, 0.125, 0.135);
varying float vy;
varying float outward;
varying float side_n;

void vertex() {
	vy = VERTEX.y;
	side_n = abs(NORMAL.x);
	outward = dot(NORMAL, normalize(VERTEX - vec3(0.0, 0.2, 0.0)));
}

void fragment() {
	if (outward < 0.0) {
		discard;       // modelin ice bakan ikinci kabugu
	}
	vec3 c = texture(albedo_tex, UV).rgb;
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float side = smoothstep(0.55, 0.75, side_n);
	float lower = mix(1.0, smoothstep(0.24, 0.32, lum), side);
	float glass = step(belt, vy) * lower * (1.0 - smoothstep(0.58, 0.68, lum))
			* (1.0 - smoothstep(0.08, 0.16, sat));
	if (glass > 0.4) {
		discard;
	}
	NORMAL = -NORMAL;
	ALBEDO = mix(lower_col, liner, smoothstep(belt - 0.004, belt + 0.012, vy));
	ROUGHNESS = 0.96;
	SPECULAR = 0.1;
}
