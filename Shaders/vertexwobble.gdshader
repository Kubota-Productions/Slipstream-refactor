shader_type spatial;
render_mode vertex_lighting, diffuse_lambert, specular_schlick_ggx;

// PS1 Resolution Settings
uniform vec2 target_resolution = vec2(320.0, 240.0);
uniform float wobble_strength : hint_range(0.0, 1.0) = 1.0;

// Texture Channels
uniform sampler2D texture_albedo : source_color, filter_nearest;
uniform sampler2D texture_normal : hint_roughness_normal, filter_nearest;
uniform sampler2D texture_roughness : hint_roughness_gray, filter_nearest;
uniform sampler2D texture_metallic : hint_default_black, filter_nearest;

// Material Properties
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness_scale : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_scale : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	// 1. Transform vertex to View space, then Projection (Clip) space
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip_pos = PROJECTION_MATRIX * view_pos;

	// 2. Convert to Normalized Device Coordinates (NDC) (-1 to 1)
	vec2 ndc = clip_pos.xy / clip_pos.w;

	// 3. Convert to Screen Pixel space, round/snap to grid, then scale back
	vec2 screen_pos = ((ndc * 0.5) + 0.5) * target_resolution;
	screen_pos = floor(screen_pos + 0.5);

	vec2 snapped_ndc = ((screen_pos / target_resolution) - 0.5) * 2.0;

	// 4. Blend between the true NDC and the snapped NDC -- at strength 1.0
	// this is identical to the original hard snap, at 0.0 it's a smooth
	// unsnapped vertex, and in between the wobble is proportionally softer.
	vec2 final_ndc = mix(ndc, snapped_ndc, wobble_strength);

	clip_pos.xy = final_ndc * clip_pos.w;
	POSITION = clip_pos;
}

void fragment() {
	// Sample texture channels using the object's UV coordinates
	vec4 albedo_tex = texture(texture_albedo, UV);
	vec4 normal_tex = texture(texture_normal, UV);
	vec4 roughness_tex = texture(texture_roughness, UV);
	vec4 metallic_tex = texture(texture_metallic, UV);

	// Assign values to Godot's built-in PBR output channels
	ALBEDO = albedo_color.rgb * albedo_tex.rgb;
	NORMAL_MAP = normal_tex.rgb;
	ROUGHNESS = roughness_tex.r * roughness_scale;
	METALLIC = metallic_tex.r * metallic_scale;
}