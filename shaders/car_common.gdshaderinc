// Arac govdesi ortak kisim (Polo, tek parca model): cam maskesi, surucu kapisi bolgesi, far / stop isiklari.
// Model uzayi: govde 1.0 birim uzun, +Z on, +X surucu tarafi, y = 0 zemin.
// Doku bilerek ham (sRGB kodlu) okunur: cam esikleri her cizicide (Forward+ / Uyumluluk) ayni sonucu versin.
// Onceden 'source_color' ile okunuyordu; esikler bir cizicide tutuyor, digerinde yan camlar opak kaliyordu.
uniform sampler2D albedo_tex : filter_linear_mipmap;

// Ham doku rengi (sRGB): maskeler bununla hesaplanir
vec3 tex_raw(vec2 uv) {
	return texture(albedo_tex, uv).rgb;
}

// Isiklandirma icin dogrusal renk
vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}
uniform float belt = 0.235;          // bel cizgisi: bunun ustundeki koyu, renksiz yuzeyler cam
uniform int door_mode = 0;           // 0: govde (kapi bolgesi atilir), 1: yalniz surucu kapisi, 2: hepsi
uniform float head_on = 0.0;         // on farlar (0..1)
uniform float tail_on = 0.0;         // arka lambalar: 0.35 park, 1.0 fren
uniform float rev_on = 0.0;          // geri vites lambasi

const int DOOR_N = 11;
// Surucu kapisinin yandan gorunusu (z, y): esik, on kenar, ayna, cam cercevesi, B diregi
const vec2 DOOR[DOOR_N] = vec2[](vec2(-0.086, 0.074), vec2(0.150, 0.074), vec2(0.168, 0.115), vec2(0.170, 0.232),
	vec2(0.203, 0.250), vec2(0.200, 0.262), vec2(0.150, 0.297), vec2(0.100, 0.333), vec2(0.050, 0.362),
	vec2(0.000, 0.377), vec2(-0.086, 0.383));

bool in_door(vec3 p) {
	if (p.x < 0.12) {
		return false;
	}
	vec2 q = p.zy;
	bool inside = false;
	for (int i = 0, j = DOOR_N - 1; i < DOOR_N; j = i++) {
		vec2 a = DOOR[i];
		vec2 b = DOOR[j];
		if (((a.y > q.y) != (b.y > q.y)) && (q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x)) {
			inside = !inside;
		}
	}
	return inside;
}

// Kapi kipi: bu parca cizilmeyecekse true
bool door_cut(vec3 p) {
	if (door_mode == 2) {
		return false;
	}
	return in_door(p) != (door_mode == 1);
}

// Cam mi? (ham sRGB renk) Yan camlar orta gri (0.42-0.50), on / arka cam koyu (0.25-0.35), boya acik (> 0.66);
// yanlardaki siyah direkler (< 0.26) opak kalir.
float glass_mask(vec3 c, vec3 p, float side_n) {
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float side = smoothstep(0.55, 0.75, side_n);
	float pillar = side * (1.0 - smoothstep(0.26, 0.31, lum));
	return step(belt, p.y) * (1.0 - pillar) * (1.0 - smoothstep(0.57, 0.63, lum)) * (1.0 - smoothstep(0.10, 0.18, sat));
}

// Far cami, stop ve geri vites lambasi isimasi (c: ham sRGB renk)
vec3 lamp_glow(vec3 c, vec3 p) {
	vec3 e = vec3(0.0);
	float lum = dot(c, vec3(0.3, 0.55, 0.15));
	float ax = abs(p.x);
	if (p.z > 0.385 && p.y > 0.165 && p.y < 0.214 && ax > 0.095) {
		e += vec3(1.0, 0.96, 0.84) * head_on * (1.0 - smoothstep(0.72, 0.84, lum)) * (0.5 + 2.4 * lum);
	}
	if (p.z < -0.40 && p.y > 0.203 && p.y < 0.27 && ax > 0.145) {
		float red = step(c.g * 1.6, c.r) * step(0.22, c.r);
		float low = 1.0 - smoothstep(0.218, 0.224, p.y);
		e += vec3(1.0, 0.015, 0.008) * red * tail_on * 1.0 * (1.0 - low * step(0.5, rev_on));   // kirmizi kalsin (parlakta turuncuya kaymasin)
		e += vec3(1.0, 0.98, 0.92) * red * low * rev_on * 1.5;
	}
	return e;
}
