shader_type sky;

// Layered atmosphere: Rayleigh-ish gradient, a hot sun disc with haze,
// two FBM cloud decks that catch sunset colour from below, a star field and a
// horizon city-glow. Drives the whole mood once the HDRI is absent, and is
// tuned to hand over smoothly between day, golden hour and night.

uniform vec3 sun_direction = vec3(0.0, 0.25, -0.97);
uniform float day_night : hint_range(0.0, 1.0) = 0.15;      // 0 = day, 1 = night
uniform float horizon_warmth : hint_range(0.0, 1.0) = 0.85; // sunset saturation

uniform vec4 zenith_day : source_color = vec4(0.14, 0.28, 0.55, 1.0);
uniform vec4 horizon_day : source_color = vec4(0.78, 0.62, 0.45, 1.0);
uniform vec4 zenith_night : source_color = vec4(0.012, 0.018, 0.045, 1.0);
uniform vec4 horizon_night : source_color = vec4(0.10, 0.075, 0.085, 1.0);
uniform vec4 sun_tint : source_color = vec4(1.0, 0.62, 0.28, 1.0);
uniform vec4 city_glow : source_color = vec4(1.0, 0.52, 0.22, 1.0);

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.008;
uniform float star_density : hint_range(0.0, 1.0) = 0.5;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise2(p);
		p = p * 2.13 + vec2(17.0, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = clamp(dir.y, -1.0, 1.0);
	float sun_dot = dot(dir, normalize(sun_direction));

	// --- base gradient ------------------------------------------------------
	float h = pow(1.0 - max(up, 0.0), 2.6);
	vec3 day_col = mix(zenith_day.rgb, horizon_day.rgb, h);
	vec3 night_col = mix(zenith_night.rgb, horizon_night.rgb, h);
	vec3 col = mix(day_col, night_col, day_night);

	// Warm wedge around the sun's azimuth at the horizon.
	float sun_azimuth = pow(clamp(sun_dot * 0.5 + 0.5, 0.0, 1.0), 3.0);
	col = mix(col, sun_tint.rgb, sun_azimuth * h * horizon_warmth * (1.0 - day_night * 0.85));

	// --- sun ---------------------------------------------------------------
	float disc = smoothstep(0.9996, 0.99995, sun_dot);
	float halo = pow(clamp(sun_dot, 0.0, 1.0), 64.0) * 0.5
		+ pow(clamp(sun_dot, 0.0, 1.0), 8.0) * 0.12;
	col += sun_tint.rgb * (disc * 30.0 + halo * 2.2) * (1.0 - day_night);

	// --- clouds ------------------------------------------------------------
	if (up > 0.005) {
		// project onto two planes for parallax between the decks
		vec2 uv_hi = dir.xz / (up + 0.12) * 0.9 + TIME * cloud_speed * vec2(1.0, 0.35);
		vec2 uv_lo = dir.xz / (up + 0.25) * 2.1 + TIME * cloud_speed * vec2(1.8, 0.6);
		float deck_hi = fbm(uv_hi);
		float deck_lo = fbm(uv_lo + deck_hi * 0.7);
		float clouds = smoothstep(1.0 - cloud_coverage, 1.35 - cloud_coverage, deck_hi * 0.65 + deck_lo * 0.5);
		// lit from the sun side, shaded on top; underlit at sunset
		float sun_face = clamp(sun_dot * 0.5 + 0.5, 0.0, 1.0);
		vec3 lit = mix(vec3(0.9, 0.88, 0.9), sun_tint.rgb * 1.25, horizon_warmth * h * 0.9 + sun_face * 0.35);
		vec3 shadow = mix(vec3(0.25, 0.27, 0.34), vec3(0.05, 0.05, 0.09), day_night);
		vec3 cloud_col = mix(shadow, lit, clamp(deck_lo * 1.2, 0.0, 1.0)) * (1.0 - day_night * 0.75);
		float fade = smoothstep(0.0, 0.18, up);   // thin out at the horizon line
		col = mix(col, cloud_col, clouds * fade * 0.9);

		// --- stars (only through cloud gaps, only at night) ----------------
		float star_gate = (1.0 - clouds) * day_night * smoothstep(0.03, 0.2, up);
		if (star_gate > 0.001) {
			vec2 cell = dir.xz / (up + 0.3) * 160.0;
			float star = step(1.0 - star_density * 0.03, hash21(floor(cell)));
			float twinkle = 0.6 + 0.4 * sin(TIME * 2.0 + hash21(floor(cell)) * 40.0);
			col += vec3(0.9, 0.93, 1.0) * star * twinkle * star_gate;
		}
	}

	// --- city glow along the whole horizon at night -------------------------
	float glow_band = exp(-abs(up) * 9.0);
	col += city_glow.rgb * glow_band * (0.12 + day_night * 0.5);

	// below the horizon: ground haze, never pure black
	col = mix(col, mix(horizon_day.rgb * 0.35, vec3(0.02, 0.015, 0.02), day_night), smoothstep(0.0, -0.25, up));

	COLOR = col;
}
