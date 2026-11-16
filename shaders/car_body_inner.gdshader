shader_type spatial;
render_mode cull_front;
// Arac govdesinin ic yuzu (dis kabugun arka yuzleri): iceriden bakinca gercek A/B direkleri, tavan ve
// kapi saci gorunur. Bel cizgisinin ustu acik gri tavan kumasi, alti koyu doseme; camlar atilir.
#include "res://shaders/car_common.gdshaderinc"
uniform vec3 liner : source_color = vec3(0.62, 0.61, 0.58);
uniform vec3 lower_col : source_color = vec3(0.12, 0.125, 0.135);
varying vec3 mp;
varying float side_n;
varying float outward;

void vertex() {
	mp = VERTEX;
	side_n = abs(NORMAL.x);
	outward = dot(NORMAL, normalize(VERTEX - vec3(0.0, 0.2, 0.0)));
}

void fragment() {
	if (outward < 0.0 || door_cut(mp)) {
		discard;       // modelin ice bakan parcalari (ayna ici, davlumbaz)
	}
	vec3 c = tex_raw(UV);
	if (glass_mask(c, mp, side_n) > 0.5) {
		discard;
	}
	NORMAL = -NORMAL;
	ALBEDO = mix(lower_col, liner, smoothstep(belt - 0.004, belt + 0.012, mp.y));
	ROUGHNESS = 0.96;
	SPECULAR = 0.1;
}
