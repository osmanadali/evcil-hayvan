shader_type spatial;
render_mode specular_disabled;

uniform sampler2D splat_a : filter_linear, repeat_disable;
uniform sampler2D splat_b : filter_linear, repeat_disable;
uniform vec2 splat_center = vec2(0.0);
uniform float splat_extent = 236.0;
uniform vec3 grass_a : source_color = vec3(0.33, 0.52, 0.20);
uniform vec3 grass_b : source_color = vec3(0.47, 0.63, 0.24);
uniform vec3 grass_c : source_color = vec3(0.25, 0.43, 0.18);
uniform vec3 grass_dry : source_color = vec3(0.58, 0.62, 0.30);
uniform vec3 path_a : source_color = vec3(0.71, 0.60, 0.43);
uniform vec3 path_b : source_color = vec3(0.60, 0.49, 0.34);
uniform vec3 sand : source_color = vec3(0.70, 0.61, 0.42);
uniform vec3 mud : source_color = vec3(0.30, 0.42, 0.38);
uniform vec3 asphalt : source_color = vec3(0.25, 0.25, 0.26);
uniform vec3 paving : source_color = vec3(0.66, 0.64, 0.60);
uniform vec3 forest_floor : source_color = vec3(0.26, 0.33, 0.17);
uniform vec3 far_green : source_color = vec3(0.22, 0.38, 0.24);
uniform float street_z = -63.0;
uniform float avenue_x = 64.0;

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
	vec2 uv = (wpos.xz - splat_center) / splat_extent + 0.5;
	vec3 a = texture(splat_a, uv).rgb;
	vec3 b = texture(splat_b, uv).rgb;
	float n1 = vnoise(wpos.xz * 0.06);
	float n2 = vnoise(wpos.xz * 0.7);
	float n3 = vnoise(wpos.xz * 3.5);
	float n4 = vnoise(wpos.xz * 14.0);

	// Cim: buyuk lekeler, kuru yamalar, ince doku
	vec3 col = mix(grass_a, grass_b, smoothstep(0.25, 0.75, n1));
	col = mix(col, grass_c, smoothstep(0.35, 0.8, n2) * 0.55);
	col = mix(col, grass_dry, smoothstep(0.62, 0.9, vnoise(wpos.xz * 0.19 + 7.0)) * 0.35);
	col *= 0.86 + 0.2 * n3 + 0.1 * n4;
	col = mix(col, forest_floor * (0.85 + 0.3 * n3), b.b * 0.8);

	// Toprak yol: cakilli, kenari girintili
	float pv = a.r + (n2 - 0.5) * 0.35;
	col = mix(col, grass_c * 0.8, smoothstep(0.05, 0.35, pv) * 0.5);
	vec3 path = mix(path_a, path_b, n2) * (0.88 + 0.16 * n3) * (0.96 + 0.08 * n4);
	col = mix(col, path, smoothstep(0.4, 0.6, pv));

	col = mix(col, sand * (0.9 + 0.12 * n3 + 0.06 * n4), smoothstep(0.3, 0.7, a.b + (n2 - 0.5) * 0.3));

	// Tas doseme: derzli karolar
	vec2 tile = fract(wpos.xz * 1.25 + vec2(floor(wpos.z * 1.25) * 0.5, 0.0));
	float joint = smoothstep(0.0, 0.06, min(min(tile.x, 1.0 - tile.x), min(tile.y, 1.0 - tile.y)));
	vec3 pave = paving * (0.86 + 0.14 * hash(floor(wpos.xz * 1.25 + vec2(floor(wpos.z * 1.25) * 0.5, 0.0)))) * mix(0.72, 1.0, joint);
	col = mix(col, pave * (0.94 + 0.1 * n3), smoothstep(0.4, 0.6, b.g));

	// Asfalt ve kesikli orta cizgi
	vec3 road = asphalt * (0.88 + 0.16 * n3 + 0.1 * n4);
	float dash = max(
		(1.0 - step(0.09, abs(wpos.z - street_z))) * step(0.5, fract(wpos.x * 0.2)),
		(1.0 - step(0.09, abs(wpos.x - avenue_x))) * step(0.5, fract(wpos.z * 0.2)));
	road = mix(road, vec3(0.85, 0.83, 0.74), dash * step(0.9, b.r));
	col = mix(col, road, smoothstep(0.4, 0.6, b.r));
	// Bordur: asfalt ile kaldirim arasinda acik renkli ince serit
	col = mix(col, vec3(0.62, 0.61, 0.58), (1.0 - smoothstep(0.0, 0.12, abs(b.r - 0.5))) * step(0.3, b.g) * 0.85);

	// Kiyi kumu ve su alti
	float sd = (a.g - 0.5) * 8.0;
	col = mix(col, sand * 0.92, 1.0 - smoothstep(0.3, 1.7, sd + (n2 - 0.5) * 0.7));
	col = mix(col, mud, (1.0 - smoothstep(-0.9, 0.3, sd)) * 0.8);

	col = mix(col, far_green, clamp((wpos.y - 5.0) / 18.0, 0.0, 1.0));

	// Suzulen bulut golgeleri
	float cloud = vnoise(wpos.xz * 0.022 + vec2(TIME * 0.012, TIME * 0.007));
	col *= 1.0 - 0.16 * smoothstep(0.55, 0.8, cloud);

	ALBEDO = col;
	ROUGHNESS = 1.0;
}
