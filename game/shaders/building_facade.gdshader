// PLATEAU建物 / 手続き生成ビル用ファサード。
// ワールド座標ベースの窓グリッドを生成し、夜はランダムな窓が点灯する。
// テクスチャの無い LOD2/LOD1 面を「本物のビル」に見せるための要。
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.52, 0.53, 0.56);
uniform float night_factor : hint_range(0.0, 1.0) = 1.0;
uniform float window_emission = 5.0;
uniform vec3 window_warm : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 window_cool : source_color = vec3(0.55, 0.78, 1.0);
uniform float window_w = 2.6;   // 窓グリッド横ピッチ [m]
uniform float window_h = 3.4;   // 窓グリッド縦ピッチ [m] (階高)
uniform float lit_ratio = 0.45; // 夜間点灯率

varying vec3 wpos;
varying vec3 wnormal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(wnormal);
	// ビルごとの色バリエーション (粗いワールドセルでハッシュ)
	float bvar = hash12(floor(wpos.xz / 18.0));
	vec3 tint = mix(vec3(0.92), vec3(1.06), bvar) * base_color;
	tint = mix(tint, tint * vec3(0.82, 0.86, 0.95), step(0.75, fract(bvar * 5.3)));

	if (an.y > 0.6) {
		// 屋上・庇
		ALBEDO = tint * 0.4;
		ROUGHNESS = 0.95;
		SPECULAR = 0.15;
	} else {
		vec2 plane = (an.x > an.z) ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
		vec2 pitch = vec2(window_w, window_h);
		vec2 cell = floor(plane / pitch);
		vec2 f = fract(plane / pitch);
		float inside = step(abs(f.x - 0.5), 0.33) * step(abs(f.y - 0.45), 0.27);
		float rnd = hash12(cell + floor(wpos.xz / 18.0) * 7.7);
		float lit = step(1.0 - lit_ratio, rnd) * night_factor;
		float flicker = 0.8 + 0.2 * sin(TIME * (0.6 + rnd * 2.5) + rnd * 40.0);
		vec3 wcol = mix(window_cool, window_warm, step(0.45, fract(rnd * 7.13)));

		ALBEDO = mix(tint, vec3(0.03, 0.035, 0.045), inside * 0.9);
		METALLIC = inside * 0.4;
		ROUGHNESS = mix(0.78, 0.12, inside);
		SPECULAR = mix(0.3, 0.55, inside);
		EMISSION = wcol * window_emission * inside * lit * flicker;
	}
}
