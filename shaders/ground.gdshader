shader_type spatial;
render_mode specular_disabled;

uniform sampler2D splat : filter_linear, repeat_disable;
uniform float splat_extent = 128.0;
uniform vec3 grass_a : source_color = vec3(0.40, 0.66, 0.26);
uniform vec3 grass_b : source_color = vec3(0.56, 0.78, 0.30);
uniform vec3 grass_c : source_color = vec3(0.30, 0.57, 0.24);
uniform vec3 path_a : source_color = vec3(0.80, 0.68, 0.48);
uniform vec3 path_b : source_color = vec3(0.70, 0.58, 0.40);
uniform vec3 sand : source_color = vec3(0.84, 0.74, 0.50);
uniform vec3 mud : source_color = vec3(0.36, 0.52, 0.47);
uniform vec3 far_green : source_color = vec3(0.24, 0.46, 0.28);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 s = texture(splat, wpos.xz / splat_extent + 0.5).rgb;
	float n1 = vnoise(wpos.xz * 0.07);
	float n2 = vnoise(wpos.xz * 0.8);
	float n3 = vnoise(wpos.xz * 4.0);

	vec3 col = mix(grass_a, grass_b, n1);
	col = mix(col, grass_c, n2 * 0.4);
	col *= 0.93 + 0.14 * n3;

	// Yol: kenari hafif girintili, yanlarinda koyu cim seridi
	float pv = s.r + (n2 - 0.5) * 0.35;
	col = mix(col, grass_c * 0.9, smoothstep(0.05, 0.35, pv) * 0.5);
	vec3 path = mix(path_a, path_b, n2) * (0.94 + 0.12 * n3);
	col = mix(col, path, smoothstep(0.4, 0.6, pv));

	col = mix(col, sand * (0.94 + 0.12 * n3), smoothstep(0.3, 0.7, s.b + (n2 - 0.5) * 0.3));

	// Kiyi kumu ve su alti
	float sd = (s.g - 0.5) * 8.0;
	col = mix(col, sand * 0.95, 1.0 - smoothstep(0.3, 1.7, sd + (n2 - 0.5) * 0.7));
	col = mix(col, mud, (1.0 - smoothstep(-0.9, 0.3, sd)) * 0.8);

	// Cevre tepeleri
	col = mix(col, far_green, clamp((wpos.y - 5.0) / 18.0, 0.0, 1.0));

	// Suzulen bulut golgeleri
	float cloud = vnoise(wpos.xz * 0.025 + vec2(TIME * 0.012, TIME * 0.007));
	col *= 1.0 - 0.14 * smoothstep(0.55, 0.8, cloud);

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
