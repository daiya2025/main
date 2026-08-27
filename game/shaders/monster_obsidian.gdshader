// カゲオニ: 黒曜石の肌にマグマの亀裂が脈動する。dissolve で消滅演出。
shader_type spatial;
render_mode cull_back;

uniform vec3 rock_color : source_color = vec3(0.035, 0.03, 0.04);
uniform vec3 magma_color : source_color = vec3(1.0, 0.32, 0.05);
uniform float magma_emission = 7.0;
uniform float crack_scale = 2.2;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1, 0, 0));
	float n010 = hash13(i + vec3(0, 1, 0));
	float n110 = hash13(i + vec3(1, 1, 0));
	float n001 = hash13(i + vec3(0, 0, 1));
	float n101 = hash13(i + vec3(1, 0, 1));
	float n011 = hash13(i + vec3(0, 1, 1));
	float n111 = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = fbm(wpos * crack_scale);
	// 消滅: ノイズしきい値で焼き切れる
	if (n < dissolve - 0.04) {
		discard;
	}
	float burn_edge = smoothstep(dissolve + 0.06, dissolve - 0.04, n);

	// マグマ亀裂: リッジノイズ
	float ridge = abs(fbm(wpos * crack_scale * 1.7 + 10.0) - 0.5) * 2.0;
	float crack = smoothstep(0.12, 0.02, ridge);
	float pulse = 0.7 + 0.3 * sin(TIME * 1.8 + wpos.y * 0.8);

	ALBEDO = mix(rock_color * (0.7 + 0.6 * n), vec3(0.01), crack);
	ROUGHNESS = mix(0.35, 0.9, crack);
	METALLIC = 0.1;
	SPECULAR = 0.6;
	EMISSION = magma_color * (crack * pulse + burn_edge * 2.5) * magma_emission
			+ vec3(1.0) * hit_flash * 3.0;
}
