// トシクイ (巨大怪獣): 厚い皮膚の擬似SSS + 背ビレの発光が皮下から透ける。
shader_type spatial;
render_mode cull_back;

uniform vec3 skin_color : source_color = vec3(0.09, 0.10, 0.115);
uniform vec3 under_glow : source_color = vec3(0.9, 0.12, 0.3);
uniform float glow_strength = 3.0;
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
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = vnoise(wpos * 0.8);
	if (n < dissolve - 0.05) {
		discard;
	}
	// 鱗状の凹凸
	float scale_pat = vnoise(wpos * vec3(3.0, 6.0, 3.0));
	float crevice = smoothstep(0.35, 0.55, scale_pat);

	// 皮下発光: 亀裂部分から漏れる
	float veins = smoothstep(0.12, 0.02, abs(vnoise(wpos * 1.3 + 5.0) - 0.5) * 2.0);
	float breath = 0.65 + 0.35 * sin(TIME * 0.9 + wpos.y * 0.15);

	ALBEDO = skin_color * (0.6 + 0.8 * scale_pat);
	ROUGHNESS = mix(0.9, 0.55, crevice);
	SPECULAR = 0.4;
	NORMAL = normalize(NORMAL + vec3(scale_pat - 0.5) * 0.4);
	EMISSION = under_glow * veins * breath * glow_strength + vec3(1.0) * hit_flash * 2.0;
}
