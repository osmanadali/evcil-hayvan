shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, world_vertex_coords;

// Dokulu agac modelleri: ruzgarda salinim + ornek basina renk tonu.
// INSTANCE_CUSTOM.x = zemin yuksekligi, .y = agac boyu
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float sway = 0.035;

void vertex() {
	float h = clamp((VERTEX.y - INSTANCE_CUSTOM.x) / max(INSTANCE_CUSTOM.y, 0.1), 0.0, 1.0);
	float k = h * h * INSTANCE_CUSTOM.y * sway;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + VERTEX.x * 0.03 + VERTEX.z * 0.05);
	VERTEX.x += (sin(TIME * 1.3 + VERTEX.x * 0.31 + VERTEX.z * 0.17) + 0.4 * sin(TIME * 3.1 + VERTEX.y * 1.7)) * k * gust;
	VERTEX.z += cos(TIME * 1.05 + VERTEX.x * 0.19 - VERTEX.z * 0.27) * k * 0.7 * gust;
}

void fragment() {
	ALBEDO = texture(tex, UV).rgb * pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 1.0;
}
