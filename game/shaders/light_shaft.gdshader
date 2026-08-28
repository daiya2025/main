// 街灯の光芒コーン (雨夜のフェイクボリュームライト)。
// 上端 (光源) が明るく、下端とシルエット縁で柔らかく消える加算コーン。
shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, shadows_disabled, depth_draw_never;

uniform vec3 color : source_color = vec3(1.0, 0.85, 0.6);
uniform float intensity = 0.55;

varying vec3 wnormal;
varying vec3 wpos;

void vertex() {
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 縦方向: 上 (UV.y=0) が濃く下で消える
	float vfade = pow(1.0 - UV.y, 1.8);
	// 縁で柔らかく (視線と法線が直交する縁ほど薄く)
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - wpos);
	float edge = pow(abs(dot(view_dir, normalize(wnormal))), 1.4);
	// カメラが近い時はフェードアウト (通過時のホワイトアウトで被写体が消えるのを防ぐ)
	float cam_d = length(CAMERA_POSITION_WORLD - wpos);
	float near_fade = smoothstep(2.5, 8.0, cam_d);
	float a = vfade * edge * intensity * near_fade;
	ALBEDO = color * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
