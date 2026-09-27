shader_type spatial;

// Texture Uniforms
uniform sampler2D sand_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D snow_texture : source_color, filter_linear_mipmap_anisotropic;

// Height Layer Ranges
uniform float sand_max_height : hint_range(-100.0, 500.0) = 0.0;
uniform float grass_min_height : hint_range(-100.0, 500.0) = -5.0;
uniform float grass_max_height : hint_range(-100.0, 500.0) = 40.0;
uniform float rock_min_height : hint_range(-100.0, 500.0) = 30.0;
uniform float rock_max_height : hint_range(-100.0, 500.0) = 100.0;
uniform float snow_min_height : hint_range(-100.0, 500.0) = 90.0;

// Triplanar Scale & Sharpness
uniform float uv_scale : hint_range(0.001, 1.0) = 0.1;
uniform float triplanar_sharpness : hint_range(1.0, 100.0) = 10.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
    // Pass world coordinates and world normals for triplanar calculation
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = abs(MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

// Helper function to sample any texture using triplanar mapping
vec3 sample_triplanar(sampler2D tex, vec3 pos, vec3 normal) {
    // Project UVs from three axes
    vec3 x_tex = texture(tex, pos.zy * uv_scale).rgb;
    vec3 y_tex = texture(tex, pos.xz * uv_scale).rgb;
    vec3 z_tex = texture(tex, pos.xy * uv_scale).rgb;
    
    // Normalize weights based on surface normal angles
    vec3 weights = pow(normal, vec3(triplanar_sharpness));
    weights /= (weights.x + weights.y + weights.z);
    
    // Blend the projections together
    return x_tex * weights.x + y_tex * weights.y + z_tex * weights.z;
}

void fragment() {
    // Sample all 4 layers with triplanar UVs
    vec3 sand  = sample_triplanar(sand_texture, world_pos, world_normal);
    vec3 grass = sample_triplanar(grass_texture, world_pos, world_normal);
    vec3 rock  = sample_triplanar(rock_texture, world_pos, world_normal);
    vec3 snow  = sample_triplanar(snow_texture, world_pos, world_normal);
    
    // Calculate blending weights based on the Y position (height)
    float height = world_pos.y;
    
    float sand_weight  = smoothstep(sand_max_height, grass_min_height, height);
    float rock_weight  = smoothstep(rock_min_height, grass_max_height, height);
    float snow_weight  = smoothstep(snow_min_height, rock_max_height, height);
    
    // Step 1: Blend sand and grass
    vec3 final_color = mix(grass, sand, sand_weight);
    
    // Step 2: Transition into rock at high elevations
    final_color = mix(final_color, rock, rock_weight);
    
    // Step 3: Transition into snow at the highest peaks (respecting rock_max_height)
    final_color = mix(final_color, snow, snow_weight);
    
    ALBEDO = final_color;
}
