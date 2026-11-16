shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
// Arac camlari (on, arka ve yan): berrak, hafif mavi-yesil; disaridan icerisi (surucu, koltuklar),
// iceriden disarisi gorunur. Iceriden bakarken (inside = 1) neredeyse gorunmez.
#include "res://shaders/car_common.gdshaderinc"
uniform float glass_alpha = 0.14;
uniform float inside = 0.0;
varying vec3 mp;
varying float side_n;

void vertex() {
	mp = VERTEX;
	side_n = abs(NORMAL.x);
}

void fragment() {
	if (door_cut(mp)) {
		discard;
	}
	vec3 c = tex_raw(UV);
	if (glass_mask(c, mp, side_n) <= 0.5) {
		discard;
	}
	ALBEDO = vec3(0.50, 0.60, 0.64);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = mix(0.7, 0.15, inside);
	ALPHA = mix(glass_alpha, 0.03, inside);
}
