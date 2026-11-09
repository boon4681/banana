#version 330 core
// port of jamesthomasgriffin/robin
in vec2 v_uv;
in vec4 v_color;
flat in uvec2 v_robin;
out vec4 frag;
uniform sampler2D u_robin_data;
uniform int u_robin_data_width;

vec2 data_point(int i) {
    return texelFetch(u_robin_data, ivec2(i % u_robin_data_width, i / u_robin_data_width), 0).xy;
}

float step_below(float edge, float x) { return x < edge ? 1.0 : 0.0; }
float closest(float a, float b) { return abs(a) < abs(b) ? a : b; }

uint eligibility(float y1, float y2, float y3, float y) {
    uint shift = uint(y > y1) | (uint(y > y2) << 1) | (uint(y > y3) << 2);
    return (0x2E74u >> shift) & 0x0101u;
}

bool solve_quadratic(float a, float b, float c, out vec2 roots, out bool double_root) {
    if (abs(a) < 1.0 / 65536.0) {
        if (abs(b) < 1e-12) return false;
        roots = vec2(-c / b);
        double_root = false;
        return true;
    }
    float d = sqrt(max(b * b - 4.0 * a * c, 0.0));
    roots = vec2(-b - d, -b + d) / (2.0 * a);
    double_root = d == 0.0;
    return true;
}

vec3 curve_crossing(vec2 p1, vec2 p2, vec2 p3, float line_y, vec2 q) {
    vec2 a = p1 - 2.0 * p2 + p3;
    vec2 b = 2.0 * (p2 - p1);
    vec2 c = p1;
    float change = step_below(q.x, p1.x) * step_below(line_y, p1.y)
                 - step_below(q.x, p3.x) * step_below(line_y, p3.y);
    float prox_x = 3.4e38;
    float prox_y = 3.4e38;
    uint v_code = eligibility(p1.x, p2.x, p3.x, q.x);
    if (v_code != 0u) {
        vec2 roots; bool dbl;
        if (solve_quadratic(a.x, b.x, c.x - q.x, roots, dbl)) {
            vec2 y = (a.y * roots + b.y) * roots + c.y;
            if ((v_code & 1u) != 0u) {
                change += step_below(q.y, y.x);
                if (!dbl) prox_y = closest(prox_y, q.y - y.x);
            }
            if (v_code > 1u) {
                change -= step_below(q.y, y.y);
                if (!dbl) prox_y = closest(prox_y, y.y - q.y);
            }
        }
    }
    uint h_code = eligibility(p1.y, p2.y, p3.y, q.y);
    if (h_code != 0u) {
        vec2 roots; bool dbl;
        if (solve_quadratic(a.y, b.y, c.y - q.y, roots, dbl) && !dbl) {
            vec2 x = (a.x * roots + b.x) * roots + c.x;
            if ((h_code & 1u) != 0u) prox_x = closest(prox_x, q.x - x.x);
            if (h_code > 1u)         prox_x = closest(prox_x, x.y - q.x);
        }
    }
    return vec3(change, prox_x, prox_y);
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

float text_coverage(float a, vec3 rgb) {
    float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    return mix(1.0 - pow(1.0 - a, 1.8), pow(a, 1.8), luma);
}

void main() {
    ivec2 cell = ivec2(floor(clamp(v_uv, vec2(0.0), vec2(15.999))));
    int cell_index = int(v_robin.x) + cell.y * 16 + cell.x;
    vec2 record = data_point(cell_index);
    uint encoded = uint(round(record.x));
    float winding = float(int((encoded >> 8) & 255u) - 128);
    int count = int(encoded & 255u);
    int start = int(round(record.y));
    float line_y = float(cell.y);
    vec2 pixels_per_unit = 1.2 / fwidth(v_uv);
    float prox_x = 3.4e38;
    float prox_y = 3.4e38;
    for (int i = 0; i < count; i++) {
        int base = start + i * 3;
        vec3 cnb = curve_crossing(
            data_point(base), data_point(base + 1), data_point(base + 2),
            line_y, v_uv);
        winding += cnb.x;
        prox_x = closest(prox_x, cnb.y);
        prox_y = closest(prox_y, cnb.z);
    }
    float proximity = closest(prox_x * pixels_per_unit.x, -prox_y * pixels_per_unit.y);
    float alpha;
    if (winding == 0.0)       alpha = max(0.5 - 0.5 * abs(proximity), 0.0);
    else if (winding == 1.0)  alpha = (proximity > 0.0) ? 1.0 : min(0.5 - proximity, 1.0);
    else if (winding == -1.0) alpha = (proximity < 0.0) ? 1.0 : min(0.5 + proximity, 1.0);
    else                      alpha = 1.0;
    frag = vec4(srgb_to_linear(v_color.rgb), v_color.a * text_coverage(alpha, v_color.rgb) * clip_coverage());
}
