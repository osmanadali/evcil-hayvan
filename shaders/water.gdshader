shader_type spatial;

uniform sampler2D splat : filter_linear, repeat_disable;
uniform sampler2D splat_b : filter_linear, repeat_disable;
uniform vec2 splat_center = vec2(0.0);
uniform float splat_extent = 236.0;
uniform vec3 shallow : source_color = vec3(0.38, 0.70, 0.72);
uniform vec3 deep : source_color = vec3(0.12, 0.40, 0.58);

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
	float sd = (texture(splat, (wpos.xz - splat_center) / splat_extent + 0.5).g - 0.5) * 8.0;
	vec2 suv = (wpos.xz - splat_center) / splat_extent + 0.5;
	if (sd > 0.35 || texture(splat_b, suv).r > 0.45 || texture(splat, suv).r > 0.45) {
		discard;   // kiyinin disi, kopru ve gecitler
	}
	float depth = clamp(-sd / 3.5, 0.0, 1.0);
	vec3 col = mix(shallow, deep, depth);

	float n = vnoise(wpos.xz * 1.4 + vec2(TIME * 0.25, TIME * 0.18));
	// Kiyi kopugu ve iceri dogru yayilan halka
	float foam = smoothstep(-0.15, 0.3, sd + n * 0.3 + 0.08 * sin(TIME * 1.5));
	float ring = smoothstep(0.42, 0.5, fract(sd * 0.7 + TIME * 0.12 + n * 0.25))
			* smoothstep(-2.2, -0.4, sd) * (1.0 - smoothstep(-0.4, 0.0, sd));
	// Isiltilar
	float spark = smoothstep(0.86, 0.93, vnoise(wpos.xz * 2.6 - vec2(TIME * 0.35, TIME * 0.2)) * (0.6 + 0.4 * n));

	col = mix(col, vec3(1.0), clamp(foam * 0.9 + ring * 0.35 + spark * 0.45, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.18;
	SPECULAR = 0.6;
}
