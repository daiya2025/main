// ネオンリッパー: 玉虫色の外殻 + 走査するネオンストライプ。
shader_type spatial;
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.02, 0.03, 0.06);
uniform float stripe_speed = 2.2;
uniform float stripe_freq = 9.0;
uniform vec3 stripe_color : source_color = vec3(0.1, 1.0, 0.85);
uniform float stripe_emission = 6.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;
varying vec3 wnormal;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 hue_rotate(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	return c * cos(a) + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cos(a));
}

void fragment() {
	float n = hash13(floor(wpos * 40.0));
	if (n < dissolve - 0.05) {
		discard;
	}
	// 薄膜干渉風: 視線と法線の角度で色相が回る
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	float fres = pow(1.0 - clamp(dot(view_dir, normalize(wnormal)), 0.0, 1.0), 2.0);
	vec3 iri = hue_rotate(vec3(0.9, 0.2, 0.7), fres * 6.283 + wpos.y * 1.5);

	// 体を走るストライプ
	float stripe = smoothstep(0.75, 0.98, sin(wpos.y * stripe_freq + wpos.x * 2.0 - TIME * stripe_speed));

	// 装甲パネルの継ぎ目 (擬似六角グリッド)
	vec2 g = vec2(wpos.x + wpos.z * 0.5 + wpos.y * 0.3, wpos.z * 0.866 + wpos.y * 0.7) * 5.0;
	vec2 gf = abs(fract(g) - 0.5);
	float seam = smoothstep(0.42, 0.485, max(gf.x, gf.y));
	float panel_var = hash13(vec3(floor(g), 1.0));

	ALBEDO = (base_color + iri * fres * 0.35) * (1.0 - seam * 0.5) * (0.9 + panel_var * 0.2);
	METALLIC = 0.85;
	ROUGHNESS = 0.18 + seam * 0.35 + panel_var * 0.08;
	SPECULAR = 0.7;
	EMISSION = stripe_color * stripe * stripe_emission * (1.0 - seam * 0.7)
			+ stripe_color * seam * 0.25
			+ iri * fres * 1.2
			+ vec3(1.0) * hit_flash * 3.0;
}
