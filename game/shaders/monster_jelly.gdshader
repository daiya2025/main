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

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	float fres = pow(1.0 - clamp(dot(view_dir, normalize(wnormal)), 0.0, 1.0), 2.5);
	float pulse = 0.6 + 0.4 * sin(TIME * pulse_speed);

	ALBEDO = shell_color * 0.15;
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	EMISSION = mix(core_color * pulse * 1.6, shell_color * 4.0, fres)
			+ vec3(1.0) * hit_flash * 3.0;
	ALPHA = clamp(0.25 + fres * 0.7, 0.0, 1.0) * (1.0 - dissolve);
}
