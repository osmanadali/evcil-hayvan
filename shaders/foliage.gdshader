shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

// Yaprak, cali ve cim icin: ruzgarda salinim + asagidan yukari renk gecisi.
uniform vec3 tint : source_color = vec3(1.0);
uniform float y0 = 0.0;
uniform float y1 = 1.0;
uniform float sway = 0.05;

varying float grad;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	grad = clamp((VERTEX.y - y0) / (y1 - y0), 0.0, 1.0);
	float k = max(VERTEX.y - y0 * 0.5, 0.0) * sway;
	float gust = 0.6 + 0.4 * sin(TIME * 0.35 + w.x * 0.03 + w.z * 0.05);
	VERTEX.x += (sin(TIME * 1.4 + w.x * 0.35 + w.z * 0.25) + 0.3 * sin(TIME * 3.3 + w.x * 1.1)) * k * gust;
	VERTEX.z += cos(TIME * 1.1 + w.x * 0.2 - w.z * 0.3) * k * 0.7 * gust;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2)) * tint;
	vec3 top = base * 1.18 + vec3(0.05, 0.05, 0.0);
	ALBEDO = mix(base * 0.62, top, grad);
	ROUGHNESS = 1.0;
}
