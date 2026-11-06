#version 330 core
in vec2 v_uv;
in vec4 v_color;
flat in uvec2 v_curves;
out vec4 frag;
uniform samplerBuffer u_curves;

vec2 curve_point(int i) {
    return texelFetch(u_curves, i).xy;
}
float compute_coverage(float inverse_diameter, vec2 p0, vec2 p1, vec2 p2) {
    uint code = (0x2E74u >> (((p0.y > 0.0) ? 2u : 0u) +
        ((p1.y > 0.0) ? 4u : 0u) +
        ((p2.y > 0.0) ? 8u : 0u))) & 3u;
    if(code == 0u) return 0.0;

    vec2 a = p0 - 2.0 * p1 + p2;
    vec2 b = p0 - p1;
    vec2 c = p0;

    float t0, t1;
    if(abs(a.y) >= 1e-5) {
        float s = sqrt(max(b.y * b.y - a.y * c.y, 0.0));
        t0 = (b.y - s) / a.y;
        t1 = (b.y + s) / a.y;
    } else {
        t0 = c.y / (2.0 * b.y);
        t1 = t0;
    }

    float alpha = 0.0;
    if((code & 1u) != 0u) {
        float x = (a.x * t0 - 2.0 * b.x) * t0 + c.x;
        alpha += clamp(x * inverse_diameter + 0.5, 0.0, 1.0);
    }
    if(code > 1u) {
        float x = (a.x * t1 - 2.0 * b.x) * t1 + c.x;
        alpha -= clamp(x * inverse_diameter + 0.5, 0.0, 1.0);
    }
    return alpha;
}

vec2 rotate90(vec2 v) {
    return vec2(v.y, -v.x);
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
    float alpha = 0.0;
    vec2 inverse_diameter = 1.0 / fwidth(v_uv);
    int base = int(v_curves.x) * 3;
    int count = int(v_curves.y);
    for(int i = 0; i < count; i++) {
        vec2 p0 = curve_point(base + 3 * i) - v_uv;
        vec2 p1 = curve_point(base + 3 * i + 1) - v_uv;
        vec2 p2 = curve_point(base + 3 * i + 2) - v_uv;
        alpha += compute_coverage(inverse_diameter.x, p0, p1, p2);
        alpha += compute_coverage(inverse_diameter.y, rotate90(p0), rotate90(p1), rotate90(p2));
    }
    alpha = clamp(alpha * 0.5, 0.0, 1.0);
    frag = vec4(srgb_to_linear(v_color.rgb), v_color.a * alpha * clip_coverage());
}
