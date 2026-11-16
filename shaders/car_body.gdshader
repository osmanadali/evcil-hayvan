shader_type spatial;
render_mode cull_back;
// Arac govdesinin opak kismi (boya, direkler, farlar). Camlar atilir: onlari car_glass.gdshader cizer,
// govdenin ic yuzunu car_body_inner.gdshader. Golgede de pencereler bos kalir.
#include "res://shaders/car_common.gdshaderinc"
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
	if (glass_mask(c, mp, side_n) > 0.5) {
		discard;
	}
	ALBEDO = to_linear(c);
	ROUGHNESS = 0.32;
	METALLIC = 0.25;
	SPECULAR = 0.5;
	EMISSION = lamp_glow(c, mp);
}
