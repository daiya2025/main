shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

// Procedural eye: sclera, limbal ring, fibrous iris, pupil and a clear-coat
// cornea. The mesh is a plain sphere whose UVs were projected before it was
// moved into the socket, so the pupil always sits at UV (0.25, 0.5) = +Z.

uniform vec4 sclera_color : source_color = vec4(0.86, 0.85, 0.83, 1.0);
uniform vec4 iris_color : source_color = vec4(0.29, 0.42, 0.22, 1.0);
uniform vec4 iris_outer : source_color = vec4(0.10, 0.14, 0.09, 1.0);
uniform vec4 vein_color : source_color = vec4(0.72, 0.30, 0.26, 1.0);
uniform float iris_radius : hint_range(0.05, 0.5) = 0.145;
uniform float pupil_radius : hint_range(0.01, 0.4) = 0.052;
uniform float limbal_width : hint_range(0.0, 0.1) = 0.022;
uniform float fiber_density : hint_range(4.0, 120.0) = 54.0;

// project_uv_spherical maps +Z (the gaze direction) to u = 0.75:
// u = atan2(z, x) / TAU + 0.5, and atan2(1, 0) = +PI/2.
const vec2 EYE_FORWARD_UV = vec2(0.75, 0.5);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// Distance from the pupil centre in UV space, corrected for the sphere's
	// horizontal compression near the poles.
	vec2 d = UV - EYE_FORWARD_UV;
	d.x *= 2.0;
	float r = length(d);
	float angle = atan(d.y, d.x);

	vec3 color = sclera_color.rgb;
	float rough = 0.30;

	// Sclera veins, strongest away from the cornea.
	float vein = smoothstep(0.55, 1.0, hash(vec2(floor(angle * 26.0), floor(r * 30.0))));
	color = mix(color, vein_color.rgb, vein * smoothstep(iris_radius, 0.45, r) * 0.30);

	// Iris: radial fibres with a darker outer ring.
	float fiber = hash(vec2(floor(angle * fiber_density), 3.0));
	float iris_t = clamp((r - pupil_radius) / max(iris_radius - pupil_radius, 0.001), 0.0, 1.0);
	vec3 iris = mix(iris_color.rgb, iris_outer.rgb, pow(iris_t, 1.4));
	iris *= 0.75 + 0.5 * fiber;
	// Collarette ridge
	iris *= 1.0 + 0.25 * smoothstep(0.30, 0.36, iris_t) * (1.0 - smoothstep(0.36, 0.44, iris_t));

	float in_iris = 1.0 - smoothstep(iris_radius - 0.006, iris_radius, r);
	color = mix(color, iris, in_iris);

	// Limbal ring — the dark boundary that makes eyes read as alive.
	float limbal = smoothstep(iris_radius - limbal_width, iris_radius - limbal_width * 0.35, r)
		* (1.0 - smoothstep(iris_radius, iris_radius + 0.004, r));
	color *= 1.0 - limbal * 0.85;

	// Pupil
	float pupil = 1.0 - smoothstep(pupil_radius - 0.008, pupil_radius, r);
	color = mix(color, vec3(0.012, 0.010, 0.010), pupil);

	ALBEDO = color;
	METALLIC = 0.0;
	ROUGHNESS = mix(rough, 0.06, in_iris);
	SPECULAR = 0.85;
	// The cornea is a clear layer over everything, which is what gives an eye
	// its wet, sharp catchlight.
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
}
