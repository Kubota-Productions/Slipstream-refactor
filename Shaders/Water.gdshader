shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 WATER_COL : source_color = vec4(0.04, 0.38, 0.88, 1.0);
uniform vec4 WATER2_COL : source_color = vec4(0.04, 0.35, 0.78, 1.0);
uniform vec4 FOAM_COL : source_color = vec4(0.8125, 0.9609, 0.9648, 1.0);

uniform float distortion_speed = 2.0;
uniform vec2 tile = vec2(5.0, 5.0);
uniform float height = 2.0;
uniform vec2 wave_size = vec2(2.0, 2.0);
uniform float wave_speed = 1.5;

const float M_2PI = 6.283185307;
const float M_6PI = 18.84955592;
const float PERIOD = 8.0;

float random(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Tileable noise
float noise_periodic(vec2 uv, float period) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);

    vec2 i00 = mod(i, period);
    vec2 i10 = mod(i + vec2(1.0, 0.0), period);
    vec2 i01 = mod(i + vec2(0.0, 1.0), period);
    vec2 i11 = mod(i + vec2(1.0, 1.0), period);

    float a = random(i00);
    float b = random(i10);
    float c = random(i01);
    float d = random(i11);

    vec2 u = f * f * (3.0 - 2.0 * f);

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 uv) {
    float value = 0.0;
    float amp = 0.5;
    float freq = 1.0;

    for (int i = 0; i < 5; i++) {
        value += amp * noise_periodic(uv * freq, PERIOD * freq);
        amp *= 0.5;
        freq *= 2.0;
    }

    return value;
}

float circ(vec2 pos, vec2 c, float s) {
    c = abs(pos - c);
    c = min(c, 1.0 - c);
    return smoothstep(0.0, 0.002, sqrt(s) - sqrt(dot(c, c))) * -1.0;
}

// ORIGINAL Wind Waker foam pattern
float waterlayer(vec2 uv) {
    uv = mod(uv, 1.0);

    float ret = 1.0;
    ret += circ(uv, vec2(0.37378, 0.277169), 0.0268181);
    ret += circ(uv, vec2(0.0317477, 0.540372), 0.0193742);
    ret += circ(uv, vec2(0.430044, 0.882218), 0.0232337);
    ret += circ(uv, vec2(0.641033, 0.695106), 0.0117864);
    ret += circ(uv, vec2(0.0146398, 0.0791346), 0.0299458);
    ret += circ(uv, vec2(0.43871, 0.394445), 0.0289087);
    ret += circ(uv, vec2(0.909446, 0.878141), 0.028466);
    ret += circ(uv, vec2(0.310149, 0.686637), 0.0128496);
    ret += circ(uv, vec2(0.928617, 0.195986), 0.0152041);
    ret += circ(uv, vec2(0.0438506, 0.868153), 0.0268601);
    ret += circ(uv, vec2(0.308619, 0.194937), 0.00806102);
    ret += circ(uv, vec2(0.349922, 0.449714), 0.00928667);
    ret += circ(uv, vec2(0.0449556, 0.953415), 0.023126);
    ret += circ(uv, vec2(0.117761, 0.503309), 0.0151272);
    ret += circ(uv, vec2(0.563517, 0.244991), 0.0292322);
    ret += circ(uv, vec2(0.566936, 0.954457), 0.00981141);
    ret += circ(uv, vec2(0.0489944, 0.200931), 0.0178746);
    ret += circ(uv, vec2(0.569297, 0.624893), 0.0132408);
    ret += circ(uv, vec2(0.298347, 0.710972), 0.0114426);
    ret += circ(uv, vec2(0.878141, 0.771279), 0.00322719);
    return max(ret, 0.0);
}

vec3 water(vec2 uv, vec3 cdir, float iTime) {
    uv *= 0.25;

    // Tileable FBM distortion only
    uv += fbm(uv * 3.0) * 0.2;

    // Original parallax distortion
    vec2 a = 0.025 * cdir.xz / cdir.y;

    float h = sin(uv.x + iTime);
    uv += a * h;

    h = sin(0.841471 * uv.x - 0.540302 * uv.y + iTime);
    uv += a * h;

    // Original texture distortion
    float d1 = mod(uv.x + uv.y, M_2PI);
    float d2 = mod((uv.x + uv.y + 0.25) * 1.3, M_6PI);

    d1 = iTime * 0.07 + d1;
    d2 = iTime * 0.5 + d2;

    vec2 dist = vec2(
        sin(d1) * 0.15 + sin(d2) * 0.05,
        cos(d1) * 0.15 + cos(d2) * 0.05
    );

    vec3 ret = mix(WATER_COL.rgb, WATER2_COL.rgb, waterlayer(uv + dist.xy));
    ret = mix(ret, FOAM_COL.rgb, waterlayer(vec2(1.0) - uv - dist.yx));

    return ret;
}

void vertex() {
    float time = TIME * wave_speed;
    vec2 uv = UV * wave_size;

    float d1 = mod(uv.x + uv.y, M_2PI);
    float d2 = mod((uv.x + uv.y + 0.25) * 1.3, M_6PI);

    d1 = time * 0.07 + d1;
    d2 = time * 0.5 + d2;

    vec2 dist = vec2(
        sin(d1) * 0.15 + sin(d2) * 0.05,
        cos(d1) * 0.15 + cos(d2) * 0.05
    );

    VERTEX.y += dist.y * height;
}

void fragment() {
    vec2 uv = UV * tile;

    ALBEDO = water(uv, vec3(0.0, 1.0, 0.0), TIME * distortion_speed);
    ROUGHNESS = 0.05;
    METALLIC = 0.0;
}