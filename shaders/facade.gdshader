shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Building facade with interior-mapped windows.
//
// The windows are not geometry and not a flat texture: a ray is traced in
// tangent space against a virtual room box behind the glass, so every window
// shows a parallax-correct interior with its own depth, floor, ceiling and back
// wall. It is the single cheapest way to make a procedural city stop looking
// like flat boxes.

group_uniforms Wall;
uniform sampler2D wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 wall_tint : source_color = vec4(0.62, 0.60, 0.58, 1.0);
uniform float wall_uv_scale : hint_range(0.05, 8.0) = 0.9;
uniform float wall_normal_depth : hint_range(0.0, 3.0) = 1.0;

group_uniforms Windows;
uniform float floor_height : hint_range(0.5, 8.0) = 3.2;
uniform float bay_width : hint_range(0.5, 8.0) = 2.6;
uniform vec2 window_size = vec2(0.62, 0.60);   // fraction of the bay
uniform float room_depth : hint_range(0.2, 8.0) = 2.4;
uniform vec4 room_color : source_color = vec4(0.10, 0.10, 0.12, 1.0);
uniform vec4 room_floor : source_color = vec4(0.16, 0.14, 0.13, 1.0);
uniform vec4 room_ceiling : source_color = vec4(0.22, 0.22, 0.24, 1.0);
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.05;

group_uniforms Lights;
uniform vec4 room_light : source_color = vec4(1.0, 0.66, 0.32, 1.0);
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.35;
uniform float light_energy : hint_range(0.0, 24.0) = 4.5;

group_uniforms Weathering;
uniform vec4 streak_color : source_color = vec4(0.20, 0.19, 0.18, 1.0);
uniform float streak_amount : hint_range(0.0, 1.0) = 0.45;
uniform float grime_amount : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_world_pos;
varying vec3 v_local_pos;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.1))) * 43758.5453);
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
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
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local_pos = VERTEX;
}

void fragment() {
	// --- lay the facade out in bays ---------------------------------------
	// UV.x runs around the building's perimeter in metres, UV.y is height in
	// metres, both set by the generator.
	vec2 metres = UV;
	vec2 cell = vec2(metres.x / bay_width, metres.y / floor_height);
	vec2 cell_id = floor(cell);
	vec2 cell_uv = fract(cell);

	vec2 half_win = window_size * 0.5;
	vec2 d = abs(cell_uv - vec2(0.5, 0.55));
	float in_window = step(d.x, half_win.x) * step(d.y, half_win.y);
	// Ground floor gets shopfronts: taller glazing, no sill.
	if (cell_id.y < 1.0) {
		in_window = step(d.x, half_win.x * 1.25) * step(d.y, half_win.y * 1.4);
	}

	vec3 wall = texture(wall_albedo, metres * wall_uv_scale).rgb * wall_tint.rgb;
	float wall_r = texture(wall_rough, metres * wall_uv_scale).r;
	vec3 wall_n = texture(wall_normal, metres * wall_uv_scale).rgb;

	// Dirt streaks running down from every sill.
	float streak = vnoise(vec3(metres.x * 24.0, metres.y * 0.6, 0.0));
	float below_sill = clamp(1.0 - fract(cell.y - 0.25), 0.0, 1.0);
	streak = smoothstep(0.45, 0.95, streak) * below_sill * streak_amount;
	wall = mix(wall, streak_color.rgb, streak);
	float grime = vnoise(v_world_pos * 0.35);
	wall *= mix(1.0, 0.7 + 0.3 * grime, grime_amount);

	vec3 out_albedo = wall;
	float out_rough = clamp(wall_r + streak * 0.2, 0.15, 1.0);
	float out_spec = 0.4;
	vec3 out_normal = wall_n;
	float out_normal_depth = wall_normal_depth;
	vec3 out_emission = vec3(0.0);

	if (in_window >= 0.5) {
		// --- interior mapping ---------------------------------------------
		// Tangent-space view direction; the room box spans [0,1] in the
		// window's own UV and one unit into the wall.
		vec3 tangent_view = normalize(vec3(
			dot(-VIEW, TANGENT),
			dot(-VIEW, BINORMAL),
			dot(-VIEW, NORMAL)));
		// Godot's tangent basis runs V down the surface; flip it so "up" in
		// the room matches "up" in the world.
		tangent_view.y = -tangent_view.y;

		vec2 win_uv = (cell_uv - vec2(0.5, 0.55)) / window_size + 0.5;
		vec3 ro = vec3(win_uv, 0.0);
		vec3 rd = tangent_view;
		// Always travel into the wall, and never divide by zero.
		rd.z = -max(abs(rd.z), 0.0001);
		// Room depth is expressed in wall units, so a deeper room simply
		// stretches the box along -Z.
		rd.z /= max(room_depth, 0.001);

		vec3 box_min = vec3(0.0, 0.0, -1.0);
		vec3 box_max = vec3(1.0, 1.0, 0.0);
		vec3 t1 = (box_min - ro) / rd;
		vec3 t2 = (box_max - ro) / rd;
		vec3 tmax = max(t1, t2);
		float t = min(min(tmax.x, tmax.y), tmax.z);
		vec3 hit = ro + rd * t;

		float room_seed = hash21(cell_id + 0.5);
		vec3 interior = room_color.rgb * (0.6 + 0.8 * room_seed);
		if (abs(hit.z + 1.0) < 0.002) {
			interior *= 0.9 + 0.3 * hash21(cell_id * 3.3);   // back wall
		} else if (hit.y < 0.002) {
			interior = room_floor.rgb;
		} else if (hit.y > 0.998) {
			interior = room_ceiling.rgb;
		} else {
			interior *= 0.55;                                 // side walls
		}
		// The back of the room falls off; the window plane stays brightest.
		interior *= mix(1.0, 0.35, clamp(-hit.z, 0.0, 1.0));

		// Some rooms are lit, and those spill warm light back out.
		float lit = step(1.0 - lit_ratio, room_seed);
		out_emission = room_light.rgb * lit * light_energy * (0.35 + 0.65 * (1.0 + hit.z));

		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		out_albedo = mix(interior, vec3(0.02, 0.025, 0.03), 0.25 + fres * 0.5);
		out_rough = glass_roughness + grime * 0.06;
		out_spec = 0.9;
		out_normal = vec3(0.5, 0.5, 1.0);
		out_normal_depth = 0.0;
	}

	ALBEDO = out_albedo;
	EMISSION = out_emission;
	ROUGHNESS = out_rough;
	METALLIC = 0.0;
	SPECULAR = out_spec;
	NORMAL_MAP = out_normal;
	NORMAL_MAP_DEPTH = out_normal_depth;
}
