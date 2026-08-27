// 雨に濡れた路面。Poly Haven のアスファルトPBRを下地に、
// 水たまり (ノイズマスク) + 雨滴リップル + SSR映えする低ラフネスを合成する。
shader_type spatial;
render_mode cull_back;

uniform bool use_textures = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 fallback_color : source_color = vec3(0.15, 0.15, 0.16);
uniform float uv_scale = 0.09;
uniform float wetness : hint_range(0.0, 1.0) = 0.85;
uniform float puddle_scale = 0.035;
uniform float ripple_strength = 0.35;
uniform bool markings = true;  // スクランブル交差点の横断歩道 / 車線

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x),
			mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// 雨滴の同心円リップル法線
vec2 ripple(vec2 p, float t) {
	vec2 acc = vec2(0.0);
	for (int i = 0; i < 3; i++) {
		vec2 cellp = p * 0.9 + vec2(float(i) * 13.7, float(i) * 7.3);
		vec2 id = floor(cellp);
		vec2 f = fract(cellp) - 0.5;
		float rnd = hash12(id);
		float phase = fract(t * (0.6 + rnd * 0.5) + rnd);
		float r = length(f);
		float wave = sin(30.0 * r - phase * 18.0) * exp(-5.0 * r) * exp(-3.0 * phase);
		acc += normalize(f + 1e-5) * wave;
	}
	return acc;
}

// 渋谷スクランブル交差点の路面ペイント (0..1)
float road_marks(vec2 p) {
	if (!markings) {
		return 0.0;
	}
	float m = 0.0;
	// 横断歩道 (十字4方向, 縞幅0.9m)
	float zebra_x = step(0.5, fract(p.y / 1.8)) * step(10.0, abs(p.x)) * step(abs(p.x), 21.0)
			* step(abs(p.y), 8.5);
	float zebra_z = step(0.5, fract(p.x / 1.8)) * step(10.0, abs(p.y)) * step(abs(p.y), 21.0)
			* step(abs(p.x), 8.5);
	// 斜め横断帯 (スクランブルの対角線)
	vec2 d = vec2(p.x + p.y, p.x - p.y) * 0.7071;
	float zebra_d = step(0.5, fract(d.y / 1.8)) * step(abs(d.x), 1.6)
			* step(abs(p.x), 15.0) * step(abs(p.y), 15.0);
	// 交差点の外は車線 (破線センターライン)
	float lane_x = step(abs(p.y), 0.18) * step(21.0, abs(p.x)) * step(fract(p.x / 8.0), 0.55);
	float lane_z = step(abs(p.x), 0.18) * step(21.0, abs(p.y)) * step(fract(p.y / 8.0), 0.55);
	// 停止線
	float stop_x = step(abs(abs(p.x) - 23.0), 0.5) * step(abs(p.y), 7.0);
	float stop_z = step(abs(abs(p.y) - 23.0), 0.5) * step(abs(p.x), 7.0);
	m = max(max(max(zebra_x, zebra_z), zebra_d), max(max(lane_x, lane_z), max(stop_x, stop_z)));
	// 塗装の擦り切れ
	m *= 0.55 + 0.45 * vnoise(p * 1.7);
	return m;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * uv_scale;
	vec3 alb = use_textures ? texture(albedo_tex, uv).rgb : fallback_color * (0.85 + 0.3 * fbm(wpos.xz * 0.5));
	float rough = use_textures ? texture(rough_tex, uv).r : 0.9;
	float ao = use_textures ? texture(ao_tex, uv).r : 1.0;

	// 路面ペイント
	float paint = road_marks(wpos.xz);
	alb = mix(alb, vec3(0.85, 0.85, 0.82), paint * 0.85);
	rough = mix(rough, 0.45, paint);

	float puddle = smoothstep(0.52, 0.62, fbm(wpos.xz * puddle_scale)) * wetness;
	float damp = wetness * 0.6; // 全体的な湿り

	vec3 wet_alb = alb * (1.0 - 0.45 * damp) * (1.0 - 0.55 * puddle);
	float wet_rough = mix(mix(rough, rough * 0.35, damp), 0.03, puddle);

	vec2 rip = ripple(wpos.xz * 1.4, TIME) * ripple_strength * puddle;
	vec3 nrm = vec3(rip.x, 1.0, rip.y);
	if (use_textures) {
		vec3 tn = texture(normal_tex, uv).rgb * 2.0 - 1.0;
		nrm.xz += tn.xy * (1.0 - puddle) * 0.8;
	}
	nrm = normalize(nrm);

	ALBEDO = wet_alb;
	ROUGHNESS = clamp(wet_rough, 0.02, 1.0);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.9, puddle);
	AO = ao;
	// ワールド法線 → ビュー空間法線
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
}
