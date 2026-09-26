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
// TRANSPARENCY
// ============================================================

// This surface's own opacity. Drive it directly, or via
// vertex colours / a GeometryInstance3D modulate (COLOR.a
// picks that up automatically). This replaces trying to read
// alpha back out of SCREEN_TEXTURE, which can't work: once a
// transparent object is blended onto an opaque framebuffer,
// the buffer's alpha is mathematically pinned back to 1.0
// (dst_a' = src_a + dst_a*(1-src_a) == 1.0 when dst_a == 1.0),
// no matter what src_a was. SCREEN_TEXTURE's alpha is not a
// usable transparency signal here.
uniform float alpha : hint_range(0.0, 1.0) = 1.0;


// ============================================================
// SCREEN
// ============================================================

uniform sampler2D SCREEN_TEXTURE :
    hint_screen_texture,
    filter_linear_mipmap,
    repeat_disable;


// ============================================================
// DEPTH
// ============================================================

uniform sampler2D DEPTH_TEXTURE :
    hint_depth_texture,
    filter_nearest,
    repeat_disable;

// Enables depth-based fading of the effect. When off, the
// shader behaves exactly as before.
uniform bool depth_fade_enabled = false;

// Linear (view-space) distance, in world units, at which the
// effect is fully applied / fully faded out.
uniform float depth_fade_near : hint_range(0.0, 1000.0) = 1.0;
uniform float depth_fade_far  : hint_range(0.0, 1000.0) = 50.0;

// If true, the fade is inverted: the effect is strong far away
// and fades out up close, instead of the default (strong near,
// fades out far away).
uniform bool depth_fade_invert = false;


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

    vec3 screen_color =
        texture(
            SCREEN_TEXTURE,
            pixel_uv
        ).rgb;


    // ========================================================
    // DEPTH -> LINEAR VIEW DISTANCE
    // ========================================================

    // Sample the depth buffer at the same (pixelated) UV so the
    // depth-based fade steps in sync with the dither grid rather
    // than sampling per-screen-pixel.
    float raw_depth =
        texture(
            DEPTH_TEXTURE,
            pixel_uv
        ).r;

    // Reconstruct view-space position from depth, then take its
    // (positive) distance from the camera along the view axis.
    vec3 ndc =
        vec3(
            pixel_uv * 2.0 - 1.0,
            raw_depth
        );

    vec4 view_pos =
        INV_PROJECTION_MATRIX * vec4(ndc, 1.0);

    view_pos.xyz /= view_pos.w;

    float linear_depth = -view_pos.z;

    // Normalised 0..1 fade factor across [depth_fade_near, depth_fade_far].
    float depth_fade =
        clamp(
            (linear_depth - depth_fade_near)
                / max(depth_fade_far - depth_fade_near, 0.0001),
            0.0,
            1.0
        );

    if (depth_fade_invert)
    {
        depth_fade = 1.0 - depth_fade;
    }

    // When disabled, force full strength so nothing changes.
    float depth_mix =
        depth_fade_enabled ? depth_fade : 1.0;


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

    // Depth fade scales how strongly the dithered/palette effect
    // is applied vs. the plain screen colour, on top of the
    // existing palette_strength control.
    vec3 dithered_result =
        mix(
            screen_color,
            palette_color,
            palette_strength
        );

    vec3 final_color =
        mix(
            screen_color,
            dithered_result,
            depth_mix
        );


    // ========================================================
    // ALPHA DITHER
    // ========================================================

    // Dither this surface's own opacity (uniform * vertex
    // alpha) using the same threshold pattern as the colour
    // banding above, so transparency reads as a stable
    // stipple instead of a hard cutoff.
    float source_alpha =
        clamp(
            alpha * COLOR.a,
            0.0,
            1.0
        );

    // Also fold the depth fade into alpha, so a fully faded-out
    // region becomes fully transparent rather than just losing
    // its colour treatment.
    source_alpha *= depth_mix;

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
