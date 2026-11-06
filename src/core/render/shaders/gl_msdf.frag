#version 330 core
in vec2 v_uv;
in vec4 v_color;
out vec4 frag;
uniform sampler2D u_atlas;
uniform float u_px_range;

float median3(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

uniform int u_clip_count;
uniform mat3 u_clip[4];
uniform vec2 u_clip_size[4];
uniform vec4 u_clip_radius[4];
uniform vec4 u_clip_radius_y[4];
float clip_coverage() {
    float a = 1.0;
    for (int i = 0; i < 4; i++) {
        if (i >= u_clip_count) break;
        vec2 q = (u_clip[i] * vec3(gl_FragCoord.xy, 1.0)).xy;
        vec2 half_size = u_clip_size[i] * 0.5;
        vec2 c = q - half_size;
        vec4 rx = u_clip_radius[i];
        vec4 ry = u_clip_radius_y[i];
        vec2 r = c.x < 0.0 ? (c.y < 0.0 ? vec2(rx.x, ry.x) : vec2(rx.w, ry.w)) : (c.y < 0.0 ? vec2(rx.y, ry.y) : vec2(rx.z, ry.z));
        vec2 d = abs(c) - half_size + r;
        float sd = max(d.x - r.x, d.y - r.y);
        if (d.x > 0.0 && d.y > 0.0 && r.x > 0.0 && r.y > 0.0) {
            vec2 n = d / r;
            float k = length(n);
            sd = (k - 1.0) * k / max(length(n / r), 1e-6);
        }
        a *= clamp(0.5 - sd, 0.0, 1.0);
    }
    return a;
}

// convert an sRGB color to linear, alpha and coverage are already linear
vec3 srgb_to_linear(vec3 c) {
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void main() {
    vec3 sample_rgb = texture(u_atlas, v_uv).rgb;
    float signed_distance = median3(sample_rgb.r, sample_rgb.g, sample_rgb.b) - 0.5;
    vec2 unit_range = vec2(u_px_range) / vec2(textureSize(u_atlas, 0));
    vec2 screen_tex_size = vec2(1.0) / fwidth(v_uv);
    float screen_px_range = max(0.5 * dot(unit_range, screen_tex_size), 1.0);
    float coverage = clamp(screen_px_range * signed_distance + 0.5, 0.0, 1.0);
    frag = vec4(srgb_to_linear(v_color.rgb), v_color.a * coverage * clip_coverage());
}
