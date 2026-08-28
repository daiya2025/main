// PLATEAU建物 / 手続き生成ビル用ファサード v2。
// ワールド座標からビルごとのスタイルを導出し、
//  - パンチ窓 / カーテンウォール / リボン窓 の3様式
//  - マリオン(窓枠) / 床スラブ / 窓下の雨だれ汚れ / 基壇部
//  - 1F〜4F の店舗階 (大開口ガラス + 店内光 + 看板色スピル)
//  - 夜間ランダム点灯 (明るさムラ + 色温度ミックス)
// をシェーダーだけで表現する。テクスチャの無い LOD2/LOD1 面を「本物のビル」に見せる要。
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.52, 0.53, 0.56);
uniform float night_factor : hint_range(0.0, 1.0) = 1.0;
uniform float window_emission = 4.0;
uniform vec3 window_warm : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 window_cool : source_color = vec3(0.55, 0.78, 1.0);
uniform float lit_ratio = 0.38;
uniform float storefront_emission = 5.2;

varying vec3 wpos;
varying vec3 wnormal;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 an = abs(wnormal);
	// --- ビル識別ハッシュ (粗いワールドセル) と様式 ---
	vec2 bcell = floor(wpos.xz / 18.0);
	float bvar = hash12(bcell);
	int style = int(floor(fract(bvar * 3.7) * 4.0)); // 0:パンチ窓 1:カーテンウォール 2:リボン窓 3:住宅(バルコニー)
	vec3 tint = mix(vec3(0.90), vec3(1.08), bvar) * base_color;
	tint = mix(tint, tint * vec3(0.80, 0.85, 0.96), step(0.75, fract(bvar * 5.3)));
	tint = mix(tint, tint * vec3(1.05, 1.0, 0.9), step(0.85, fract(bvar * 9.1)));
	tint = mix(tint, tint * vec3(1.14, 1.02, 0.84), step(0.62, fract(bvar * 4.7)) * 0.7); // 温色系
	if (style == 3) { // 住宅棟はレンガ/ベージュ系に寄せる
		tint = mix(tint, vec3(0.52, 0.40, 0.34), 0.55 * step(0.45, fract(bvar * 2.9)));
	}

	if (an.y > 0.6) {
		// --- 屋上: 防水シート + 汚れ ---
		float n = vnoise(wpos.xz * 0.8);
		ALBEDO = tint * (0.32 + 0.12 * n);
		ROUGHNESS = 0.95;
		SPECULAR = 0.15;
	} else {
		vec2 plane = (an.x > an.z) ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
		// 様式ごとの窓ピッチ (+ ビルごとの寸法バリエーション)
		vec2 pitch = vec2(2.6, 3.4);
		vec2 win_half = vec2(0.33, 0.27);       // 窓の半サイズ (セル比)
		if (style == 1) { pitch = vec2(1.6, 3.4); win_half = vec2(0.46, 0.42); }
		if (style == 2) { pitch = vec2(5.0, 3.4); win_half = vec2(0.44, 0.24); }
		if (style == 3) { pitch = vec2(3.4, 2.9); win_half = vec2(0.36, 0.30); }
		pitch *= 0.88 + 0.3 * fract(bvar * 11.3);

		vec2 cellf = plane / pitch;
		vec2 cell = floor(cellf);
		vec2 f = fract(cellf);
		vec2 d = abs(f - vec2(0.5, 0.47));

		float inside = step(d.x, win_half.x) * step(d.y, win_half.y);
		// マリオン: 窓枠 (窓のふち 8cm 相当)
		vec2 edge = win_half - d;
		float frame = inside * step(min(edge.x * pitch.x, edge.y * pitch.y), 0.075);
		// 床スラブ: 各階の帯
		float slab = step(0.92, f.y) + step(f.y, 0.045);

		float rnd = hash12(cell + bcell * 7.7);
		float lit = step(1.0 - lit_ratio, rnd) * night_factor;
		float bright = 0.25 + 0.75 * fract(rnd * 13.7);
		float flicker = 0.85 + 0.15 * sin(TIME * (0.6 + rnd * 2.5) + rnd * 40.0);
		vec3 wcol = mix(window_cool, window_warm, step(0.45, fract(rnd * 7.13)));
		// カーテンウォールは青緑ガラスで点灯少なめ
		if (style == 1) { lit *= 0.55; }

		// 室内光の縦グラデーション (天井照明: 窓の上ほど明るい)
		float win_v = clamp((f.y - (0.47 - win_half.y)) / (2.0 * win_half.y), 0.0, 1.0);
		float interior = mix(0.55, 1.4, win_v);
		// 窓ごとのガラスの微妙な傾き → 反射がパネル単位でばらける
		vec2 tilt = (vec2(hash12(cell + 1.7), hash12(cell + 3.1)) - 0.5) * 0.09 * inside * (1.0 - frame);
		vec3 pert_world = (an.x > an.z) ? vec3(0.0, tilt.y, tilt.x) : vec3(tilt.x, tilt.y, 0.0);
		// 窓下の室外機シルエット (パンチ窓の一部)
		float ac = 0.0;
		if (style == 0) {
			ac = step(abs(f.x - 0.63), 0.10) * step(abs(f.y - 0.30), 0.075)
					* step(0.72, fract(rnd * 3.31)) * inside;
		}
		// 窓下枠の落ち影
		float sill = step(abs(f.y - (0.47 - win_half.y) + 0.02), 0.035) * step(d.x, win_half.x) * (1.0 - inside);
		// 住宅様式: 各階下部のバルコニー帯 (奥まった影 + 手すりの縦桟)
		float balc = 0.0;
		float rail = 0.0;
		if (style == 3) {
			balc = step(f.y, 0.26);
			rail = step(fract(plane.x / 0.42), 0.12) * step(0.05, f.y);
		}
		// ブラインド: 点灯窓の一部は上部が遮られる (生活感)
		float has_blind = step(0.55, fract(rnd * 9.71));
		float blind_frac = 0.25 + 0.45 * fract(rnd * 17.3);
		float blind_cut = mix(1.0, mix(0.12, 1.0, step(win_v, 1.0 - blind_frac)), has_blind);

		// 窓下の雨だれ汚れ (縦ノイズ、窓の下ほど濃い)
		float streak = vnoise(vec2(plane.x * 2.2, plane.y * 0.15)) * vnoise(plane * vec2(3.1, 0.3));
		float dirt = clamp(streak * 0.8, 0.0, 1.0) * (0.35 + 0.65 * step(f.y, 0.45));

		// --- 合成 (壁 / ガラス / 枠 / スラブ) ---
		vec3 glass_col = (style == 1) ? vec3(0.05, 0.075, 0.085) : vec3(0.03, 0.035, 0.045);
		vec3 albedo = mix(tint, glass_col, inside);
		albedo = mix(albedo, tint * 0.55, frame + slab * 0.6);       // 枠とスラブ
		albedo = mix(albedo, vec3(0.32, 0.33, 0.34), ac);            // 室外機
		albedo *= (1.0 - dirt * 0.45) * (1.0 - sill * 0.45);

		float rough = mix(0.78, (style == 1) ? 0.08 : 0.14, inside);
		rough = mix(rough, 0.6, frame + slab * 0.5);
		rough = mix(rough, 0.85, ac);
		rough += dirt * 0.2;

		float metal = inside * ((style == 1) ? 0.6 : 0.35) * (1.0 - ac);
		metal = mix(metal, 0.85, frame);

		// バルコニー帯の合成 (住宅様式)
		albedo = mix(albedo, tint * 0.30, balc * (1.0 - rail));
		albedo = mix(albedo, tint * 0.72, balc * rail);
		rough = mix(rough, 0.85, balc);
		metal *= (1.0 - balc);

		vec3 emit = wcol * window_emission * inside * (1.0 - frame) * (1.0 - ac)
				* lit * bright * flicker * interior * blind_cut * (1.0 - balc * 0.85);

		// --- 店舗階 (地上 0〜4.2m): 大開口ガラス + 店内光 + 看板色 ---
		float sf_zone = step(wpos.y, 4.2) * night_factor;
		if (sf_zone > 0.5) {
			vec2 sf_f = fract(plane / vec2(4.0, 4.4));
			float sf_open = step(abs(sf_f.x - 0.5), 0.42) * step(wpos.y, 3.1) * step(0.35, wpos.y);
			float sf_rnd = hash12(floor(plane / vec2(4.0, 4.4)) + bcell * 3.3);
			vec3 sf_col = mix(vec3(1.0, 0.85, 0.6), mix(vec3(1.0, 0.3, 0.5), vec3(0.3, 0.9, 1.0),
					step(0.5, fract(sf_rnd * 5.7))), step(0.6, sf_rnd));
			float sf_on = step(0.25, sf_rnd); // 75%営業中
			albedo = mix(albedo, vec3(0.04), sf_open);
			rough = mix(rough, 0.1, sf_open);
			emit = mix(emit, sf_col * storefront_emission * (0.7 + 0.3 * sin(TIME * 1.3 + sf_rnd * 20.0)),
					sf_open * sf_on);
			// 日除けオーニング (2.9〜3.2m, 店の色の布地)
			float awning = step(2.9, wpos.y) * step(wpos.y, 3.2) * sf_on;
			float awn_stripe = step(0.5, fract(plane.x / 0.6));
			albedo = mix(albedo, mix(sf_col * 0.5, vec3(0.9), awn_stripe * 0.55), awning * 0.95);
			rough = mix(rough, 0.95, awning);
			emit *= (1.0 - awning);
			// 看板帯 (3.2〜3.9m)
			float sign_band = step(3.25, wpos.y) * step(wpos.y, 3.9) * sf_on;
			emit = mix(emit, sf_col * storefront_emission * 1.4, sign_band * 0.8);
			albedo = mix(albedo, vec3(0.05), sign_band * 0.8);
		}
		// 基壇部 (0〜0.4m) は御影石
		float plinth = step(wpos.y, 0.4);
		albedo = mix(albedo, tint * 0.35, plinth);
		rough = mix(rough, 0.4, plinth);
		emit *= (1.0 - plinth);

		ALBEDO = albedo;
		METALLIC = metal;
		ROUGHNESS = clamp(rough, 0.05, 1.0);
		SPECULAR = mix(0.3, 0.6, inside);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(pert_world, 0.0)).xyz);
		EMISSION = emit;
	}
}
