shader_type canvas_item;
render_mode unshaded;

// Final image pass, applied to a full-screen rect above the 3D viewport.
//
// Everything here is a lens/sensor artefact rather than a scene effect: they
// exist to make a rendered frame read as *photographed*. The strengths are
// deliberately small — the moment any of these becomes noticeable on its own it
// has been overdone.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

group_uniforms Lens;
uniform float chromatic_aberration : hint_range(0.0, 4.0) = 0.45;
uniform float distortion : hint_range(-0.4, 0.4) = 0.02;
uniform float vignette : hint_range(0.0, 2.0) = 0.42;
uniform float vignette_roundness : hint_range(0.2, 3.0) = 1.1;

group_uniforms Sensor;
uniform float film_grain : hint_range(0.0, 2.0) = 0.35;
uniform float grain_size : hint_range(0.5, 6.0) = 1.6;
uniform float exposure : hint_range(0.0, 4.0) = 1.0;
uniform float contrast : hint_range(0.5, 2.0) = 1.04;
uniform float saturation : hint_range(0.0, 2.0) = 1.06;

group_uniforms Grade;
uniform vec4 lift : source_color = vec4(0.010, 0.008, 0.014, 1.0);
uniform vec4 gain : source_color = vec4(1.03, 1.00, 0.96, 1.0);
uniform float orange_teal : hint_range(0.0, 1.0) = 0.22;

group_uniforms Effects;
uniform float sharpen : hint_range(0.0, 2.0) = 0.35;
uniform float lens_dirt : hint_range(0.0, 2.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 hit_flash_color : source_color = vec4(1.0, 0.25, 0.12, 1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 apply_grade(vec3 c) {
	c = (c - 0.5) * contrast + 0.5;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	c = c * gain.rgb + lift.rgb;
	// Push shadows cool and highlights warm — the standard cinematic split.
	vec3 warm = vec3(1.06, 0.99, 0.90);
	vec3 cool = vec3(0.92, 0.98, 1.08);
	c *= mix(vec3(1.0), mix(cool, warm, smoothstep(0.15, 0.75, luma)), orange_teal);
	return c;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - 0.5;
	float r2 = dot(centered, centered);

	// Barrel distortion, then chromatic aberration scaled by radius so the
	// centre of frame stays clean.
	vec2 duv = uv + centered * r2 * distortion;
	float ca = chromatic_aberration * 0.0015 * (0.25 + r2 * 3.0);
	vec3 color;
	color.r = texture(screen_tex, duv + centered * ca).r;
	color.g = texture(screen_tex, duv).g;
	color.b = texture(screen_tex, duv - centered * ca).b;

	// Unsharp mask against a slightly blurred tap of the same buffer.
	if (sharpen > 0.001) {
		vec2 texel = SCREEN_PIXEL_SIZE;
		vec3 blur = texture(screen_tex, duv + vec2(texel.x, 0.0)).rgb
			+ texture(screen_tex, duv - vec2(texel.x, 0.0)).rgb
			+ texture(screen_tex, duv + vec2(0.0, texel.y)).rgb
			+ texture(screen_tex, duv - vec2(0.0, texel.y)).rgb;
		blur *= 0.25;
		color += (color - blur) * sharpen;
	}

	color *= exposure;
	color = apply_grade(color);

	// Lens dirt lifts the bloom that already came out of the 3D pass.
	if (lens_dirt > 0.001) {
		float dirt = hash12(floor(uv * 220.0));
		dirt = smoothstep(0.86, 1.0, dirt);
		float bright = smoothstep(0.75, 2.0, dot(color, vec3(0.2126, 0.7152, 0.0722)));
		color += dirt * bright * lens_dirt * vec3(1.0, 0.72, 0.42);
	}

	// Vignette
	float v = 1.0 - vignette * pow(clamp(r2 * 2.0, 0.0, 1.0), vignette_roundness);
	color *= v;

	// Grain, scaled down in the highlights the way real film behaves.
	if (film_grain > 0.001) {
		float g = hash12(floor(FRAGCOORD.xy / grain_size) + fract(TIME) * 91.7);
		float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
		color += (g - 0.5) * film_grain * 0.06 * (1.0 - smoothstep(0.4, 1.4, luma));
	}

	color = mix(color, hit_flash_color.rgb, hit_flash * 0.55);

	COLOR = vec4(max(color, vec3(0.0)), 1.0);
}
