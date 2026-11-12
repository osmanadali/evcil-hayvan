shader_type spatial;
// Insan giysisi: dokunun ust kismi (tisort) renklendirilir, kot pantolon oldugu gibi kalir.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 shirt : source_color = vec3(0.9, 0.9, 0.9);

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float top = step(UV.y, 0.42) + step(0.7, UV.x) * step(UV.y, 0.87);
	ALBEDO = c * mix(vec3(1.0), shirt, clamp(top, 0.0, 1.0));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
