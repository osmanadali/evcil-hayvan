shader_type spatial;


// Zemin: fotograf tabanli dokular, mesafe alani maskeleriyle karistirilir (kenarlar keskin kalir).
// splat_a: R patika, G kiyi (0.5 = kiyi, +-4 m), B kum      splat_b: R asfalt, G asfalt+kaldirim, B sehir zemini (park disi)
// splat_c: R bina yakinligi (0.5 = duvar)
uniform sampler2D splat_a : filter_linear, repeat_disable;
uniform sampler2D splat_b : filter_linear, repeat_disable;
uniform sampler2D splat_c : filter_linear, repeat_disable;
uniform vec2 splat_center = vec2(0.0);
uniform float splat_extent = 1000.0;
uniform sampler2D t_grass : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_asphalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_pavers : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_yard : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D t_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_grass : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_asphalt : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_pavers : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float edge(float v, float w) { return smoothstep(0.5 - w, 0.5 + w, v); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = normalize(cross(vec3(0.0, 0.0, 1.0), NORMAL));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	vec2 uv = (wpos.xz - splat_center) / splat_extent + 0.5;
	vec3 a = texture(splat_a, uv).rgb;
	vec3 b = texture(splat_b, uv).rgb;
	float near_wall = texture(splat_c, uv).r;
	vec2 p = wpos.xz;
	float macro = vnoise(p * 0.045);
	float mid = vnoise(p * 0.35);

	// Cim: iki olcekte ornekle (tekrar belli olmasin), buyuk lekelerle canlilik degissin
	vec3 grass = texture(t_grass, p * 0.27).rgb * 0.6 + texture(t_grass, p * 0.061 + 3.7).rgb * 0.4;
	grass *= mix(vec3(0.82, 1.18, 0.62), vec3(1.08, 1.22, 0.7), macro) * 1.12;
	grass = mix(grass, grass * vec3(1.12, 1.0, 0.72), smoothstep(0.55, 0.9, vnoise(p * 0.12 + 9.0)) * 0.5);

	// Binalar arasi: beton ve toprak karisimi, yer yer ot
	vec3 yard = texture(t_yard, p * 0.19).rgb * vec3(1.25, 1.22, 1.14);
	vec3 dirt = texture(t_gravel, p * 0.13 + 1.3).rgb * vec3(0.95, 0.92, 0.84);
	yard = mix(yard, dirt, smoothstep(0.35, 0.7, vnoise(p * 0.09 + 4.0)));
	yard = mix(yard, grass * 0.92, smoothstep(0.62, 0.8, vnoise(p * 0.16 + 17.0)) * 0.75);
	vec3 col = mix(grass, yard, edge(b.b + (mid - 0.5) * 0.06, 0.03));

	// Patika (cakil) ve kum
	vec3 gravel = texture(t_gravel, p * 0.33).rgb * vec3(1.12, 1.06, 0.95);
	col = mix(col, gravel, edge(a.r + (mid - 0.5) * 0.05, 0.02));
	vec3 sand = texture(t_sand, p * 0.3).rgb * vec3(1.25, 1.18, 1.0);
	col = mix(col, sand, edge(a.b, 0.03));

	// Kaldirim (kilit parke), bordur ve asfalt
	vec3 pave = texture(t_pavers, p * 0.5).rgb * vec3(1.32, 1.3, 1.26);
	col = mix(col, pave, edge(b.g, 0.006));
	vec3 road = texture(t_asphalt, p * 0.16).rgb * 0.55 + texture(t_asphalt, p * 0.047 + 2.1).rgb * 0.45;
	road *= 0.92 + 0.14 * macro;
	float on_road = edge(b.r, 0.006);
	float curb = edge(b.r, 0.006 + 0.0) - edge(b.r - 0.022, 0.006);
	col = mix(col, vec3(0.6, 0.59, 0.56) * (0.9 + 0.2 * mid), clamp(-curb, 0.0, 1.0) * edge(b.g, 0.02));
	col = mix(col, road, on_road);

	// Kiyi kumu
	float sd = (a.g - 0.5) * 8.0;
	col = mix(col, sand * 0.9, 1.0 - smoothstep(0.3, 1.7, sd + (mid - 0.5) * 0.7));
	col = mix(col, vec3(0.2, 0.3, 0.3), (1.0 - smoothstep(-0.9, 0.3, sd)) * 0.8);

	// Duvar dibi golgesi ve suzulen bulut golgeleri
	col *= 1.0 - 0.38 * smoothstep(0.3, 0.5, near_wall) * (1.0 - step(0.52, near_wall));
	float cloud = vnoise(p * 0.012 + vec2(TIME * 0.008, TIME * 0.005));
	col *= 1.0 - 0.18 * smoothstep(0.55, 0.8, cloud);

	// Yuzey kabartisi: cim, kaldirim ve asfalt
	float on_pave = edge(b.g, 0.006);
	vec3 nm = texture(n_grass, p * 0.27).rgb;
	nm = mix(nm, vec3(0.5, 0.5, 1.0), edge(b.b, 0.03) * 0.7);
	nm = mix(nm, texture(n_pavers, p * 0.5).rgb, on_pave);
	nm = mix(nm, texture(n_asphalt, p * 0.16).rgb, on_road);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.2;
	ALBEDO = col;
	ROUGHNESS = mix(1.0, 0.82, on_road);
}
