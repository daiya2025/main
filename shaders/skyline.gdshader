shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

// Distant tower silhouettes. Unshaded on purpose: at 300 m+ through haze,
// direct lighting on a box reads as CG; a dark mass with a grid of lit
// windows and aerial-perspective fade reads as a city.

uniform vec4 mass_color : source_color = vec4(0.045, 0.045, 0.06, 1.0);
uniform vec4 haze_color : source_color = vec4(0.42, 0.30, 0.24, 1.0);
uniform vec4 window_warm : source_color = vec4(1.0, 0.72, 0.38, 1.0);
uniform vec4 window_cool : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float window_density : hint_range(0.0, 1.0) = 0.35;
uniform float haze_start : hint_range(0.0, 1000.0) = 220.0;
uniform float haze_full : hint_range(0.0, 2000.0) = 900.0;

varying vec3 v_local;
varying vec4 v_custom;
varying vec3 v_scale;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void vertex() {
	v_local = VERTEX;                       // unit box, -0.5..0.5
	v_custom = INSTANCE_CUSTOM;
	v_scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
}

void fragment() {
	// Window grid in metres on the box's own faces. Face selection must come
	// from the local position, not NORMAL — fragment NORMAL is view-space.
	vec3 world_size = v_scale;
	vec2 face_uv;
	vec3 a = abs(v_local);
	if (a.y > a.x && a.y > a.z) {
		face_uv = vec2(-1.0);               // roof: no windows
	} else {
		// the coordinate that runs along this face is the non-dominant one
		float along = (a.z > a.x) ? v_local.x * world_size.x : v_local.z * world_size.z;
		face_uv = vec2(along / 6.0, v_local.y * world_size.y / 3.4);
	}

	vec3 col = mass_color.rgb;
	if (face_uv.x > -0.5) {
		vec2 cell = floor(face_uv + v_custom.x * 61.7);
		vec2 f = fract(face_uv);
		float lit = step(1.0 - window_density * v_custom.y, hash21(cell));
		float pane = step(0.25, f.x) * step(f.x, 0.75) * step(0.2, f.y) * step(f.y, 0.7);
		vec3 wcol = mix(window_warm.rgb, window_cool.rgb, step(0.8, hash21(cell + 7.7)));
		col += wcol * lit * pane * (0.7 + 0.6 * hash21(cell + 3.3));
	}

	// aerial perspective: fade the mass into the horizon haze with distance
	float dist = length(VERTEX);
	float haze = smoothstep(haze_start, haze_full, dist);
	col = mix(col, haze_color.rgb, haze * 0.82);

	ALBEDO = col;
}
