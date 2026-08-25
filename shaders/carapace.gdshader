shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Corrupted-data creature hide: a hard chitin shell over translucent flesh,
// with a thin-film iridescence on the plates and veins that glow brighter as
// the creature takes damage.

group_uniforms Shell;
uniform vec4 shell_color : source_color = vec4(0.055, 0.052, 0.062, 1.0);
uniform vec4 shell_deep : source_color = vec4(0.020, 0.019, 0.026, 1.0);
uniform float shell_roughness : hint_range(0.0, 1.0) = 0.34;
uniform float plate_scale : hint_range(1.0, 60.0) = 13.0;
uniform float plate_depth : hint_range(0.0, 2.0) = 0.75;

group_uniforms Flesh;
uniform vec4 flesh_color : source_color = vec4(0.32, 0.09, 0.07, 1.0);
uniform float flesh_amount : hint_range(0.0, 1.0) = 0.35;
uniform float sss_strength : hint_range(0.0, 1.0) = 0.45;

group_uniforms Iridescence;
uniform vec4 film_a : source_color = vec4(0.18, 0.42, 0.85, 1.0);
uniform vec4 film_b : source_color = vec4(0.85, 0.30, 0.55, 1.0);
uniform float film_strength : hint_range(0.0, 2.0) = 0.55;

group_uniforms Veins;
uniform vec4 vein_color : source_color = vec4(1.0, 0.38, 0.06, 1.0);
uniform float vein_emission : hint_range(0.0, 40.0) = 9.0;
uniform float vein_scale : hint_range(1.0, 40.0) = 7.5;
uniform float rage : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed : hint_range(0.0, 12.0) = 2.0;
uniform float cavity_strength : hint_range(0.0, 2.0) = 1.0;

varying vec3 v_object_pos;
varying float v_cavity;

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

// Worley-ish cell distance, used both for the plate mosaic and the vein web.
vec2 cells(vec3 p, float scale) {
	vec3 sp = p * scale;
	vec3 base = floor(sp);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 cell = base + vec3(float(x), float(y), float(z));
				vec3 point = cell + vec3(hash13(cell), hash13(cell + 11.3), hash13(cell + 27.7));
				float d = length(point - sp);
				if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
			}
		}
	}
	return vec2(d1, d2);
}

void vertex() {
	v_object_pos = VERTEX;
	v_cavity = mix(1.0, COLOR.r, cavity_strength);
}

void fragment() {
	vec3 p = v_object_pos;
	vec2 plate = cells(p, plate_scale);
	float seam = clamp((plate.y - plate.x) * 2.2, 0.0, 1.0);   // 0 at plate borders

	vec3 shell = mix(shell_deep.rgb, shell_color.rgb, seam);
	float grain = vnoise(p * 60.0);
	shell *= 0.85 + 0.3 * grain;

	// Exposed flesh between the plates.
	float exposure = (1.0 - seam) * flesh_amount;
	vec3 base = mix(shell, flesh_color.rgb, exposure);

	// Thin-film interference over the hard plates.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 film = mix(film_a.rgb, film_b.rgb, fract(fres * 3.0 + grain * 0.6));
	base += film * film_strength * fres * seam * 0.5;

	ALBEDO = base * mix(0.6, 1.0, v_cavity);
	METALLIC = 0.0;
	ROUGHNESS = clamp(mix(0.85, shell_roughness, seam) + grain * 0.08, 0.05, 1.0);
	SPECULAR = 0.55;

	// Plate edges push the normal so the mosaic reads in silhouette light.
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	NORMAL_MAP_DEPTH = plate_depth;

	SSS_STRENGTH = sss_strength * exposure;
	SSS_TRANSMITTANCE_COLOR = vec4(flesh_color.rgb, 1.0);
	SSS_TRANSMITTANCE_DEPTH = 0.25;

	// Vein web: brighter where the shell is thin, and it floods with rage.
	vec2 vein_cells = cells(p + vec3(3.1, 0.0, 7.7), vein_scale);
	float vein = 1.0 - smoothstep(0.0, 0.09, vein_cells.y - vein_cells.x);
	float pulse = 0.55 + 0.45 * sin(TIME * pulse_speed - p.y * 4.0);
	EMISSION = vein_color.rgb * vein * vein_emission * pulse * (0.25 + 0.75 * rage) * (1.0 - seam * 0.4);

	AO = v_cavity;
	AO_LIGHT_AFFECT = 0.8;
}
