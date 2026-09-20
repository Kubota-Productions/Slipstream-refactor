shader_type spatial;

render_mode
    unshaded,
    blend_mix,
    depth_draw_never,
    depth_test_disabled,
    cull_disabled,
    fog_disabled;


// ============================================================
// DITHER
// ============================================================

uniform sampler2D dither_tex : repeat_enable, filter_nearest;

uniform float dither_size : hint_range(1.0, 32.0) = 3.0;


// ============================================================
// PALETTE
// ============================================================

// IMPORTANT:
// This should be a horizontal gradient.
// Left = dark colour
// Right = bright colour
uniform sampler2D color_tex : source_color, filter_linear, repeat_disable;


// How strongly the palette replaces the original colours.
// 1.0 = completely use the gradient
// 0.0 = original screen colour
uniform float palette_strength : hint_range(0.0, 1.0) = 1.0;


// ============================================================
// COLOUR
// ============================================================

uniform int bit_depth : hint_range(1, 256) = 8;

uniform float contrast : hint_range(0.0, 3.0) = 1.0;

uniform float offset : hint_range(-1.0, 1.0) = 0.0;


// ============================================================
// SCREEN
// ============================================================

uniform sampler2D SCREEN_TEXTURE :
    hint_screen_texture,
    filter_nearest,
    repeat_disable;


// ============================================================
// VERTEX
// ============================================================

void vertex()
{
    POSITION = vec4(VERTEX, 1.0);
}


// ============================================================
// FRAGMENT
// ============================================================

void fragment()
{
    vec2 screen_size = VIEWPORT_SIZE;


    // ========================================================
    // PIXELATION
    // ========================================================

    vec2 pixel_grid =
        floor(
            SCREEN_UV * screen_size / dither_size
        );

    vec2 pixel_uv =
        (pixel_grid + 0.5)
        * dither_size
        / screen_size;


    // ========================================================
    // SCREEN COLOUR
    // ========================================================

    vec4 screen =
        texture(
            SCREEN_TEXTURE,
            pixel_uv
        );

    vec3 screen_color =
        screen.rgb;

    float source_alpha =
        screen.a;


    // ========================================================
    // DITHER UV
    // ========================================================

    ivec2 noise_size =
        textureSize(
            dither_tex,
            0
        );

    vec2 dither_pixel =
        mod(
            pixel_grid,
            vec2(noise_size)
        );

    vec2 dither_uv =
        (dither_pixel + 0.5)
        / vec2(noise_size);

    float threshold =
        texture(
            dither_tex,
            dither_uv
        ).r;


    // ========================================================
    // LUMINANCE
    // ========================================================

    float luminance =
        dot(
            screen_color,
            vec3(
                0.299,
                0.587,
                0.114
            )
        );


    // ========================================================
    // CONTRAST
    // ========================================================

    luminance =
        (luminance - 0.5 + offset)
        * contrast
        + 0.5;

    luminance =
        clamp(
            luminance,
            0.0,
            1.0
        );


    // ========================================================
    // BIT DEPTH
    // ========================================================

    float levels =
        max(
            float(bit_depth),
            1.0
        );

    float scaled =
        luminance * levels;

    float band =
        floor(scaled);

    float fraction =
        fract(scaled);


    // ========================================================
    // DITHER BETWEEN BANDS
    // ========================================================

    float dithered_band =
        band
        + step(
            threshold,
            fraction
        );

    float dithered_luminance =
        dithered_band
        / levels;

    dithered_luminance =
        clamp(
            dithered_luminance,
            0.0,
            1.0
        );


    // ========================================================
    // PALETTE LOOKUP
    // ========================================================

    // The gradient is sampled horizontally:
    //
    // 0.0 -------------------------- 1.0
    // dark                         bright

    vec3 palette_color =
        texture(
            color_tex,
            vec2(
                dithered_luminance,
                0.5
            )
        ).rgb;


    // ========================================================
    // PALETTE MIX
    // ========================================================

    vec3 final_color =
        mix(
            screen_color,
            palette_color,
            palette_strength
        );


    // ========================================================
    // ALPHA DITHER
    // ========================================================

    float final_alpha =
        step(
            threshold,
            source_alpha
        );


    // ========================================================
    // OUTPUT
    // ========================================================

    ALBEDO =
        final_color;

    ALPHA =
        final_alpha;
}