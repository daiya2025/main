// カゲオニ: 黒曜石の肌にマグマの亀裂が脈動する。dissolve で消滅演出。
shader_type spatial;
render_mode cull_back;

uniform vec3 rock_color : source_color = vec3(0.055, 0.05, 0.06);
uniform vec3 magma_color : source_color = vec3(1.0, 0.32, 0.05);
uniform float magma_emission = 5.0;
uniform float crack_scale = 2.2;
uniform float wetness : hint_range(0.0, 1.0) = 0.7;   // 雨濡れの艶
uniform float rim_strength = 0.5;                      // 輪郭の環境リム (夜の視認性)
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;
varying vec3 wnormal;

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
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = fbm(wpos * crack_scale);
	// 消滅: ノイズしきい値で焼き切れる
	if (n < dissolve - 0.04) {
		discard;
	}
	float burn_edge = smoothstep(dissolve + 0.06, dissolve - 0.04, n);

	// マグマ亀裂: リッジノイズ (大域マスクで「冷えた溶岩」風の疎らな亀裂にする)
	float ridge = abs(fbm(wpos * crack_scale * 1.7 + 10.0) - 0.5) * 2.0;
	float patch = smoothstep(0.35, 0.62, fbm(wpos * 0.45 + 3.0));
	float crack = smoothstep(0.055, 0.015, ridge) * patch;
	float pulse = 0.7 + 0.3 * sin(TIME * 1.8 + wpos.y * 0.8);

	// 2スケールの岩肌ディテール (中スケールの起伏 + 微細な粒)
	float meso = fbm(wpos * crack_scale * 1.6 + 21.0);
	float micro = fbm(wpos * crack_scale * 7.0);
	float glint = step(0.992, hash13(floor(wpos * 42.0) + floor(TIME * 0.5)));

	// 割れ目の底は熱の名残の赤茶、面は冷えた黒曜石
	vec3 base = rock_color * (0.7 + 0.6 * n) * (0.85 + 0.3 * micro);
	base = mix(base * vec3(1.25, 0.85, 0.7), base, smoothstep(0.1, 0.35, ridge));
	ALBEDO = mix(base, vec3(0.01), crack);

	// 雨濡れ: 上向き面ほど水膜でラフネス低下・スペキュラ上昇
	float up = clamp(wnormal.y, 0.0, 1.0);
	float wet = wetness * (0.35 + 0.65 * up);
	float rough = mix(0.32 + micro * 0.3 + meso * 0.15, 0.9, crack);
	ROUGHNESS = mix(rough, rough * 0.35, wet);
	METALLIC = 0.12;
	SPECULAR = mix(0.55, 0.95, wet);
	NORMAL = normalize(NORMAL
			+ vec3(meso - 0.5, meso * 0.8 - 0.4, 0.0) * 0.45
			+ vec3(micro - 0.5, micro * 0.7 - 0.35, 0.0) * 0.25);

	// 環境リム: 夜景の照り返しが輪郭を縁取り、暗色の巨体を読ませる
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	float rim = pow(1.0 - clamp(dot(view_dir, normalize(wnormal)), 0.0, 1.0), 3.0);
	vec3 rim_col = mix(vec3(0.45, 0.55, 0.85), magma_color, clamp(crack * 3.0, 0.0, 0.6));

	EMISSION = magma_color * (crack * pulse + burn_edge * 2.5) * magma_emission
			+ magma_color * glint * 1.5
			+ rim_col * rim * rim_strength
			+ magma_color * hit_flash * 1.4;
}
