#version 300 es
precision highp float;
in vec2 v_uv;
in vec4 v_color;
flat in uvec2 v_curves;
out vec4 frag;
uniform sampler2D u_curves;

vec2 curve_point(int i) {
    return texelFetch(u_curves, ivec2(i & 1023, i >> 10), 0).xy;
}

float compute_coverage(float inverse_diameter, vec2 p0, vec2 p1, vec2 p2) {
    uint code = (0x2E74u >> (((p0.y > 0.0f) ? 2u : 0u) +
        ((p1.y > 0.0f) ? 4u : 0u) +
        ((p2.y > 0.0f) ? 8u : 0u))) & 3u;
    if(code == 0u)
        return 0.0f;

    vec2 a = p0 - 2.0f * p1 + p2;
    vec2 b = p0 - p1;
    vec2 c = p0;

    float t0, t1;
    if(abs(a.y) >= 1e-5f) {
        float s = sqrt(max(b.y * b.y - a.y * c.y, 0.0f));
        t0 = (b.y - s) / a.y;
        t1 = (b.y + s) / a.y;
    } else {
        t0 = c.y / (2.0f * b.y);
        t1 = t0;
    }

    float alpha = 0.0f;
    if((code & 1u) != 0u) {
        float x = (a.x * t0 - 2.0f * b.x) * t0 + c.x;
        alpha += clamp(x * inverse_diameter + 0.5f, 0.0f, 1.0f);
    }
    if(code > 1u) {
        float x = (a.x * t1 - 2.0f * b.x) * t1 + c.x;
        alpha -= clamp(x * inverse_diameter + 0.5f, 0.0f, 1.0f);
    }
    return alpha;
}

vec2 rotate90(vec2 v) {
    return vec2(v.y, -v.x);
}

void main() {
    float alpha = 0.0f;
    vec2 inverse_diameter = 1.0f / fwidth(v_uv);
    int base = int(v_curves.x) * 3;
    int count = int(v_curves.y);
    for(int i = 0; i < count; i++) {
        vec2 p0 = curve_point(base + 3 * i) - v_uv;
        vec2 p1 = curve_point(base + 3 * i + 1) - v_uv;
        vec2 p2 = curve_point(base + 3 * i + 2) - v_uv;
        alpha += compute_coverage(inverse_diameter.x, p0, p1, p2);
        alpha += compute_coverage(inverse_diameter.y, rotate90(p0), rotate90(p1), rotate90(p2));
    }
    alpha = clamp(alpha * 0.5f, 0.0f, 1.0f);
    frag = vec4(v_color.rgb, v_color.a * alpha);
}
