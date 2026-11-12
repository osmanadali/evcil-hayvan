shader_type spatial;
// Insan giysisi: dokunun ust kismi (tisort) renklendirilir, kot pantolon oldugu gibi kalir.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 shirt : source_color = vec3(0.9, 0.9, 0.9);
uniform vec3 shirt2 : source_color = vec3(1.0, 1.0, 1.0);   // desenin ikinci rengi
uniform int pattern = 0;        // 0 duz, 1 cizgili, 2 kareli
uniform vec4 pants : source_color = vec4(0.0);   // a > 0: pantolonu bu renge boya

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float top = step(UV.y, 0.42) + step(0.7, UV.x) * step(UV.y, 0.87);
	top = clamp(top, 0.0, 1.0);
	vec3 sc = shirt;
	if (pattern == 1) {
		sc = mix(shirt, shirt2, step(0.5, fract(UV.y * 38.0)));
	} else if (pattern == 2) {
		float a = step(0.5, fract(UV.x * 26.0));
		float b = step(0.5, fract(UV.y * 26.0));
		sc = mix(shirt, shirt2, abs(a - b) * 0.55);
	}
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	vec3 bottom = mix(c, vec3(lum) * pants.rgb * 1.5, pants.a);
	ALBEDO = mix(bottom, c * sc, top);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
