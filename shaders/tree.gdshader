shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled, world_vertex_coords;

// Dokulu agac modelleri: ruzgarda salinim + ornek basina renk tonu.
// INSTANCE_CUSTOM.x = zemin yuksekligi, .y = agac boyu
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float sway = 0.035;
uniform vec3 focus = vec3(0.0, -1000.0, 0.0);
uniform float see_radius = 3.2;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	float h = clamp((VERTEX.y - INSTANCE_CUSTOM.x) / max(INSTANCE_CUSTOM.y, 0.1), 0.0, 1.0);
	float k = h * h * INSTANCE_CUSTOM.y * sway;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + VERTEX.x * 0.03 + VERTEX.z * 0.05);
	VERTEX.x += (sin(TIME * 1.3 + VERTEX.x * 0.31 + VERTEX.z * 0.17) + 0.4 * sin(TIME * 3.1 + VERTEX.y * 1.7)) * k * gust;
	VERTEX.z += cos(TIME * 1.05 + VERTEX.x * 0.19 - VERTEX.z * 0.27) * k * 0.7 * gust;
	wpos = VERTEX;
}

void fragment() {
	// Oyuncunun onune gecen yapraklari del
	vec3 c = CAMERA_POSITION_WORLD;
	vec3 cf = focus + vec3(0.0, 0.9, 0.0) - c;
	float t = dot(wpos - c, cf) / dot(cf, cf);
	if (t > 0.0 && t < 0.95) {
		float d = length(c + cf * t - wpos);
		if (d < see_radius * (0.35 + 0.65 * t) * (0.7 + 0.3 * hash(floor(FRAGCOORD.xy * 0.5)))) {
			discard;
		}
	}
	ALBEDO = texture(tex, UV).rgb * pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 1.0;
}
