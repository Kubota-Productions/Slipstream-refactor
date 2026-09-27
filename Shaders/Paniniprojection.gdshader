shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float panini_amount : hint_range(0.0, 1.0) = 0.0;

const float SAFETY_MARGIN = 0.82; // shrink factor -- guarantees no out-of-bounds sampling at amount = 1.0

void fragment() {
	vec2 ndc = (SCREEN_UV * 2.0 - 1.0) * SAFETY_MARGIN;
	float x = ndc.x;
	float y = ndc.y;

	float d = panini_amount;

	float A = x * x + (d + 1.0) * (d + 1.0);
	float B = 2.0 * x * x * d;
	float C = x * x * d * d - (d + 1.0) * (d + 1.0);

	float disc = max(B * B - 4.0 * A * C, 0.0);
	float c = (-B + sqrt(disc)) / (2.0 * A);
	c = clamp(c, -1.0, 1.0);

	float s = x * (d + c) / (d + 1.0);
	float phi = atan(s, c);
	float S = (d + 1.0) / (d + c);

	float x_src = tan(phi);
	float y_src = (S > 0.0001) ? (y / S) : y;

	vec2 src_uv = (vec2(x_src, y_src) * 0.5) + 0.5;
	src_uv = clamp(src_uv, 0.0, 1.0);

	COLOR = texture(screen_tex, src_uv);
}