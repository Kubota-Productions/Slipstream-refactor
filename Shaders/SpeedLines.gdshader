shader_type canvas_item;

uniform sampler2D noise_tex : repeat_enable;

uniform vec3 line_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;   // driven by speed, 0 = no lines, 1 = full PowerSprint
uniform float color_levels : hint_range(2.0, 16.0) = 3.0;
uniform float power : hint_range(0.5, 8.0) = 2.5;

uniform vec2 radial_center = vec2(0.5);
uniform float radial_zoom : hint_range(0.001, 0.2) = 0.03;
uniform float radial_repeat : hint_range(4.0, 64.0) = 20.0;
uniform float radial_min : hint_range(0.0, 1.0) = 0.05;
uniform float radial_max : hint_range(0.0, 1.0) = 0.75;

uniform float speed : hint_range(0.0, 2.0) = 0.3;

// Controls how much of the noise field is "unlocked" by speed.
// At intensity 0, only the very brightest noise peaks (top ~2%) show --
// a couple of lines. At intensity 1, almost the whole range shows.
uniform float density_threshold_max : hint_range(0.0, 1.0) = 0.97; // threshold at zero speed
uniform float density_threshold_min : hint_range(0.0, 1.0) = 0.35; // threshold at full speed
uniform float density_falloff : hint_range(0.001, 0.3) = 0.05;     // softness of the cutoff edge

vec2 polar_coordinates(vec2 uv, vec2 center, float zoom, float repeat, float offset) {
	vec2 dir = uv - center;
	float radius = length(dir) * 2.0;
	float angle = atan(dir.y, dir.x) * 1.0 / TAU;
	return mod(vec2(radius * zoom - offset, angle * repeat), 1.0);
}

void fragment() {
	vec2 dir = UV - radial_center;

	vec2 src_uv = polar_coordinates(UV, radial_center, radial_zoom, radial_repeat, TIME * speed);
	float noi_val = texture(noise_tex, src_uv).r;

	float vig_mask = smoothstep(radial_min, radial_max, length(dir));
	noi_val *= vig_mask;

	noi_val = pow(noi_val, power);

	// Speed-scaled density gate: only noise peaks above the current
	// threshold survive. Higher intensity (speed) lowers the threshold,
	// letting more peaks through -- this is what changes LINE COUNT,
	// not just how bright existing lines are.
	float threshold = mix(density_threshold_max, density_threshold_min, intensity);
	float gated_val = smoothstep(threshold, threshold + density_falloff, noi_val);

	float posterized = floor(gated_val * color_levels) / (color_levels - 1.0);

	// Fade the whole effect in/out at the extremes so it doesn't pop
	// abruptly right at the walk/run boundary.
	float alpha = clamp(posterized, 0.0, 1.0) * smoothstep(0.0, 0.15, intensity);

	COLOR = vec4(line_color, alpha);
}