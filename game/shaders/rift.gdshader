// 上空に裂けた「次元の裂け目」。うねる稲妻状のコアとエネルギーの渦。
shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, shadows_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.15, 0.55);
uniform vec3 edge_color : source_color = vec3(0.35, 0.1, 1.0);
uniform float intensity = 12.0;

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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.1 + vec2(3.7, 1.1);
		a *= 0.55;
	}
	return v;
}

void fragment() {
	vec2 uv = UV - 0.5;
	float t = TIME * 0.4;
	// 中心の裂け目ライン (歪んだ縦の亀裂)
	float warp = fbm(vec2(uv.y * 3.0 + t, t * 0.7)) - 0.5;
	float d = abs(uv.x + warp * 0.35) * (1.4 + 2.2 * abs(uv.y));
	float crack = exp(-d * 8.0) + exp(-d * 30.0) * 0.8;
	float halo = exp(-length(uv * vec2(1.9, 1.0)) * 3.6) * (0.4 + 0.6 * fbm(uv * 6.0 - t));
	float pulse = 0.85 + 0.15 * sin(TIME * 2.3);

	// クアッドの境界が絶対に見えないよう、両軸とも端で完全に0へ落とす
	float edge_mask = smoothstep(0.48, 0.22, abs(uv.x)) * smoothstep(0.5, 0.3, abs(uv.y));

	vec3 col = core_color * crack * 2.0 + edge_color * halo;
	float a = clamp(crack + halo * 0.5, 0.0, 1.0) * edge_mask;
	// unshaded では ALBEDO が最終色 (互換レンダラは EMISSION を出力しない)
	ALBEDO = col * intensity * pulse * edge_mask;
	ALPHA = a;
}
