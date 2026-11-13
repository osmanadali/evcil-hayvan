shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;
// Arac govdesi: dokudaki koyu, renksiz cam bolgeleri (bel cizgisinin ustu) yari saydam olur;
// boylece iceride surucu ve hayvan gorunur.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float belt = 0.235;        // model biriminde bel cizgisi (bunun ustu cam olabilir)
uniform float glass_alpha = 0.38;
varying float vy;

void vertex() {
	vy = VERTEX.y;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float glass = step(belt, vy) * (1.0 - smoothstep(0.2, 0.32, lum)) * (1.0 - smoothstep(0.06, 0.14, sat));
	ALBEDO = mix(c, vec3(0.06, 0.08, 0.1), glass * 0.6);
	ROUGHNESS = mix(0.32, 0.04, glass);
	METALLIC = mix(0.25, 0.0, glass);
	SPECULAR = mix(0.5, 0.9, glass);
	ALPHA = mix(1.0, glass_alpha, glass);
}
