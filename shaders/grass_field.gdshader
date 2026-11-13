shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
// Sik cim tutamlari: konum MultiMesh'ten; renk tonu INSTANCE_CUSTOM.r, ruzgar dunya konumundan.
uniform float wind_t = 0.0;
varying float v_shade;
varying float v_hue;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = clamp(VERTEX.y / 0.18, 0.0, 1.0);
	VERTEX.x += sin(wind_t * 1.7 + wp.x * 0.35 + wp.z * 0.2) * 0.05 * k;
	v_shade = k;
	v_hue = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 tint = mix(vec3(0.36, 0.42, 0.14), vec3(0.55, 0.6, 0.24), v_hue);
	ALBEDO = tint * mix(0.55, 1.05, v_shade);
	ROUGHNESS = 0.85;
	BACKLIGHT = vec3(0.25, 0.35, 0.1);
}
