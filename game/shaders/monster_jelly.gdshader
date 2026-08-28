// スクランブラー: 半透明ゼリー状の浮遊体。内部コアの脈動が透ける。
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always;

uniform vec3 shell_color : source_color = vec3(0.25, 0.5, 1.0);
uniform vec3 core_color : source_color = vec3(1.0, 0.25, 0.7);
uniform float pulse_speed = 2.4;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;
varying vec3 wnormal;

void vertex() {
	// 呼吸するように波打つ
	VERTEX += NORMAL * sin(TIME * 3.0 + VERTEX.y * 6.0 + VERTEX.x * 4.0) * 0.03;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	float fres = pow(1.0 - clamp(dot(view_dir, normalize(wnormal)), 0.0, 1.0), 2.5);
	float pulse = 0.6 + 0.4 * sin(TIME * pulse_speed);

	// 内部の霧状組織: 視線を少し潜らせた点をサンプルして奥行きを出す
	float wisps = vnoise3((wpos - view_dir * 0.35) * 4.0 + vec3(0.0, TIME * 0.4, 0.0));
	float wisps2 = vnoise3((wpos - view_dir * 0.7) * 2.2 - vec3(0.0, TIME * 0.25, 0.0));
	vec3 internal = core_color * (wisps * 0.7 + wisps2 * 0.5) * (0.6 + 0.6 * pulse);

	// 表面の雨滴ハイライト
	float droplet = step(0.982, hash13(floor(wpos * 60.0)));

	ALBEDO = shell_color * 0.15;
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	EMISSION = mix(core_color * pulse * 1.2 + internal, shell_color * 4.0, fres)
			+ vec3(0.8, 0.95, 1.0) * droplet * 0.7
			+ core_color * hit_flash * 1.4;
	ALPHA = clamp(0.22 + fres * 0.7 + wisps * 0.12, 0.0, 1.0) * (1.0 - dissolve);
}
