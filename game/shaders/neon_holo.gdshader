// 渋谷のネオン / ホログラム広告。スキャンライン + グリフ列 + 縁のフレネル発光。
shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, shadows_disabled;

uniform vec3 color_a : source_color = vec3(1.0, 0.05, 0.45);
uniform vec3 color_b : source_color = vec3(0.1, 0.85, 1.0);
uniform float intensity = 8.0;
uniform float scroll_speed = 0.35;
uniform float glyph_density = 9.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = UV;
	// 縦に流れるグリフ (カタカナ的なブロックノイズ)
	vec2 guv = vec2(uv.x * glyph_density, uv.y * glyph_density * 1.6 + TIME * scroll_speed * glyph_density);
	vec2 gid = floor(guv);
	float g = step(0.45, hash12(gid + floor(TIME * vec2(0.0, 1.3))));
	vec2 gf = fract(guv);
	float cellmask = step(abs(gf.x - 0.5), 0.36) * step(abs(gf.y - 0.5), 0.4);

	float scan = 0.75 + 0.25 * sin(uv.y * 240.0 + TIME * 6.0);
	float band = 0.6 + 0.4 * sin(uv.y * 3.0 - TIME * 1.2);
	vec3 col = mix(color_a, color_b, band);

	float edge = smoothstep(0.0, 0.06, uv.x) * smoothstep(1.0, 0.94, uv.x)
			* smoothstep(0.0, 0.06, uv.y) * smoothstep(1.0, 0.94, uv.y);
	float frame = 1.0 - edge; // 外枠は常時発光

	float glow = g * cellmask * scan * edge + frame * 0.9;
	float flicker = 0.9 + 0.1 * sin(TIME * 17.0 + hash12(vec2(floor(TIME * 2.0))) * 20.0);

	// unshaded では ALBEDO が最終色 (互換レンダラは EMISSION を出力しない)
	ALBEDO = col * glow * intensity * flicker;
	ALPHA = clamp(glow, 0.0, 1.0);
}
