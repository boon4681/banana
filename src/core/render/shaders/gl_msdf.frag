#version 330 core
in vec2 v_uv;
in vec4 v_color;
out vec4 frag;
uniform sampler2D u_atlas;
uniform float u_px_range;

float median3(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

void main() {
    vec3 sample_rgb = texture(u_atlas, v_uv).rgb;
    float signed_distance = median3(sample_rgb.r, sample_rgb.g, sample_rgb.b) - 0.5;
    vec2 unit_range = vec2(u_px_range) / vec2(textureSize(u_atlas, 0));
    vec2 screen_tex_size = vec2(1.0) / fwidth(v_uv);
    float screen_px_range = max(0.5 * dot(unit_range, screen_tex_size), 1.0);
    float coverage = clamp(screen_px_range * signed_distance + 0.5, 0.0, 1.0);
    frag = vec4(v_color.rgb, v_color.a * coverage);
}
