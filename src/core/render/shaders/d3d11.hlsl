// SV_Position is top-left, so clip matrices dont need the flip gl_FragCoord need

cbuffer Params : register(b0) {
    float2 u_resolution;
    int    u_has_tex;
    int    u_clip_count;
    float4 u_transform[3];     // mat3 columns
    float4 u_clip[12];         // 4 mat3s, 3 columns each
    float4 u_clip_size[4];
    float4 u_clip_radius[4];
    float4 u_clip_radius_y[4];
    float4 u_color[4];         // rows of the effect color matrix
    float4 u_offset;
    float4 u_tint;
    float2 u_step;
    int    u_taps;
    float  u_sigma;
    int    u_shadow;
    int    u_robin_width;
    float  u_px_range;
    int    u_samples;
};

Texture2D            u_tex      : register(t0);
Buffer<float2>       u_curves   : register(t1);
Texture2D<float2>    u_robin    : register(t2);
Texture2DMS<float4>  u_ms       : register(t3);
SamplerState         u_sampler  : register(s0);

struct Quad_In {
    float2 pos   : POSITION;
    float2 uv    : TEXCOORD0;
    float4 color : COLOR;
    uint   mode  : MODE;
};

struct Glyph_In {
    float2 pos    : POSITION;
    float2 uv     : TEXCOORD0;
    float4 color  : COLOR;
    uint2  curves : CURVES;
};

struct V2P {
    float4 pos   : SV_Position;
    float2 uv    : TEXCOORD0;
    float4 color : COLOR;
    nointerpolation uint2 extra : EXTRA;
};

float4 to_clip(float2 p) {
    float2 pos = u_transform[0].xy * p.x + u_transform[1].xy * p.y + u_transform[2].xy;
    float2 ndc = pos / u_resolution * 2.0 - 1.0;
    return float4(ndc.x, -ndc.y, 0.0, 1.0);
}

V2P vs_quad(Quad_In i) {
    V2P o;
    o.pos = to_clip(i.pos);
    o.uv = i.uv;
    o.color = i.color;
    o.extra = uint2(i.mode & 0xFFFFu, i.mode >> 16);
    return o;
}

V2P vs_glyph(Glyph_In i) {
    V2P o;
    o.pos = to_clip(i.pos);
    o.uv = i.uv;
    o.color = i.color;
    o.extra = i.curves;
    return o;
}

float clip_coverage(float2 frag) {
    float a = 1.0;
    for (int i = 0; i < 4; i++) {
        if (i >= u_clip_count) break;
        float2 q = u_clip[i * 3].xy * frag.x + u_clip[i * 3 + 1].xy * frag.y + u_clip[i * 3 + 2].xy;
        float2 half_size = u_clip_size[i].xy * 0.5;
        float2 c = q - half_size;
        float4 rx = u_clip_radius[i];
        float4 ry = u_clip_radius_y[i];
        float2 r = c.x < 0.0 ? (c.y < 0.0 ? float2(rx.x, ry.x) : float2(rx.w, ry.w)) : (c.y < 0.0 ? float2(rx.y, ry.y) : float2(rx.z, ry.z));
        float2 d = abs(c) - half_size + r;
        float sd = max(d.x - r.x, d.y - r.y);
        if (d.x > 0.0 && d.y > 0.0 && r.x > 0.0 && r.y > 0.0) {
            float2 n = d / r;
            float k = length(n);
            sd = (k - 1.0) * k / max(length(n / r), 1e-6);
        }
        a *= saturate(0.5 - sd);
    }
    return a;
}

float3 srgb_to_linear(float3 c) {
    return lerp(c / 12.92, pow((c + 0.055) / 1.055, 2.4), step(0.04045, c));
}

float3 linear_to_srgb(float3 c) {
    c = max(c, 0.0);
    return lerp(c * 12.92, 1.055 * pow(c, 1.0 / 2.4) - 0.055, step(0.0031308, c));
}

float median3(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

float edge_coverage(float2 uv) {
    float2 e = min(uv, 1.0 - uv) / max(fwidth(uv), 1e-6) + 0.5;
    return saturate(e.x) * saturate(e.y);
}

float4 ps_quad(V2P i) : SV_Target {
    float4 c = i.color;
    uint mode = i.extra.x;
    float inner = float(i.extra.y) / 65535.0;
    if (mode == 1) {
        c *= u_tex.Sample(u_sampler, i.uv);
    } else if (mode == 2) {
        float3 s = u_tex.Sample(u_sampler, i.uv).rgb;
        float signed_distance = median3(s.r, s.g, s.b) - 0.5;
        float w, h;
        u_tex.GetDimensions(w, h);
        float2 unit_range = 4.0 / float2(w, h);
        float2 screen_tex_size = 1.0 / fwidth(i.uv);
        float screen_px_range = max(0.5 * dot(unit_range, screen_tex_size), 1.0);
        c.a *= saturate(screen_px_range * signed_distance + 0.5);
    } else if (mode == 3) {
        float d = length(i.uv);
        float2 normal = i.uv / max(d, 1e-6);
        float2 gradient = float2(dot(normal, ddx(i.uv)), dot(normal, ddy(i.uv)));
        float px = max(length(gradient), 1e-6);
        float dist = (1.0 - d) / px;
        float coverage;
        if (inner > 0.0) {
            dist = min(dist, (d - inner) / px);
            float width = min((1.0 - inner) / px, 1.0);
            coverage = saturate(width * (dist + 1.0 - 0.5 * width));
        } else {
            coverage = saturate(dist + 0.5);
        }
        c.a *= coverage;
    } else if (mode == 4) {
        c.a *= edge_coverage(i.uv);
    } else if (mode == 5) {
        c *= u_tex.Sample(u_sampler, saturate(i.uv));
        c.a *= edge_coverage(i.uv);
    } else if (mode == 6) {
        c.a *= 1.0 - smoothstep(inner, 1.0, length(i.uv));
    }
    if (u_clip_count > 0) c.a *= clip_coverage(i.pos.xy);
    c.rgb = srgb_to_linear(c.rgb);
    return c;
}

float4 ps_effect(V2P i) : SV_Target {
    float4 sum = u_tex.Sample(u_sampler, i.uv);
    if (u_taps > 0) {
        float total = 1.0;
        for (int t = 1; t <= 24; t++) {
            if (t > u_taps) break;
            float w = exp(-0.5 * float(t * t) / (u_sigma * u_sigma));
            sum += (u_tex.Sample(u_sampler, i.uv + u_step * float(t)) + u_tex.Sample(u_sampler, i.uv - u_step * float(t))) * w;
            total += 2.0 * w;
        }
        sum /= total;
    }
    float4 c;
    if (u_shadow != 0) {
        float3 tint = u_tint.a > 0.0 ? srgb_to_linear(u_tint.rgb / u_tint.a) * u_tint.a : 0.0;
        c = float4(tint, u_tint.a) * sum.a;
    } else {
        float4 straight = sum.a > 0.0 ? float4(sum.rgb / sum.a, sum.a) : 0.0;
        straight.rgb = linear_to_srgb(straight.rgb);
        c = saturate(float4(dot(u_color[0], straight), dot(u_color[1], straight), dot(u_color[2], straight), dot(u_color[3], straight)) + u_offset);
        c.rgb = srgb_to_linear(c.rgb);
        c.rgb *= c.a;
    }
    c *= i.color.a;
    if (u_clip_count > 0) c *= clip_coverage(i.pos.xy);
    return c;
}

// glyph pipeline adapted from GreenLightning/gpu-font-rendering (MIT)
float compute_coverage(float inverse_diameter, float2 p0, float2 p1, float2 p2) {
    uint code = (0x2E74u >> (((p0.y > 0.0) ? 2u : 0u) + ((p1.y > 0.0) ? 4u : 0u) + ((p2.y > 0.0) ? 8u : 0u))) & 3u;
    if (code == 0u) return 0.0;
    float2 a = p0 - 2.0 * p1 + p2;
    float2 b = p0 - p1;
    float2 c = p0;
    float t0, t1;
    if (abs(a.y) >= 1e-5) {
        float s = sqrt(max(b.y * b.y - a.y * c.y, 0.0));
        t0 = (b.y - s) / a.y;
        t1 = (b.y + s) / a.y;
    } else {
        t0 = c.y / (2.0 * b.y);
        t1 = t0;
    }
    float alpha = 0.0;
    if ((code & 1u) != 0u) {
        float x = (a.x * t0 - 2.0 * b.x) * t0 + c.x;
        alpha += saturate(x * inverse_diameter + 0.5);
    }
    if (code > 1u) {
        float x = (a.x * t1 - 2.0 * b.x) * t1 + c.x;
        alpha -= saturate(x * inverse_diameter + 0.5);
    }
    return alpha;
}

float2 rotate90(float2 v) { return float2(v.y, -v.x); }

float4 ps_glyph(V2P i) : SV_Target {
    float alpha = 0.0;
    float2 inverse_diameter = 1.0 / fwidth(i.uv);
    int base = int(i.extra.x) * 3;
    int count = int(i.extra.y);
    for (int k = 0; k < count; k++) {
        float2 p0 = u_curves.Load(base + 3 * k) - i.uv;
        float2 p1 = u_curves.Load(base + 3 * k + 1) - i.uv;
        float2 p2 = u_curves.Load(base + 3 * k + 2) - i.uv;
        alpha += compute_coverage(inverse_diameter.x, p0, p1, p2);
        alpha += compute_coverage(inverse_diameter.y, rotate90(p0), rotate90(p1), rotate90(p2));
    }
    alpha = saturate(alpha * 0.5);
    return float4(srgb_to_linear(i.color.rgb), i.color.a * alpha * clip_coverage(i.pos.xy));
}

// port of jamesthomasgriffin/robin
float2 data_point(int i) {
    return u_robin.Load(int3(i % u_robin_width, i / u_robin_width, 0));
}

float step_below(float edge, float x) { return x < edge ? 1.0 : 0.0; }
float closest(float a, float b) { return abs(a) < abs(b) ? a : b; }

uint eligibility(float y1, float y2, float y3, float y) {
    uint shift = uint(y > y1) | (uint(y > y2) << 1) | (uint(y > y3) << 2);
    return (0x2E74u >> shift) & 0x0101u;
}

bool solve_quadratic(float a, float b, float c, out float2 roots, out bool double_root) {
    roots = 0.0;
    double_root = false;
    if (abs(a) < 1.0 / 65536.0) {
        if (abs(b) < 1e-12) return false;
        roots = -c / b;
        return true;
    }
    float d = sqrt(max(b * b - 4.0 * a * c, 0.0));
    roots = float2(-b - d, -b + d) / (2.0 * a);
    double_root = d == 0.0;
    return true;
}

float3 curve_crossing(float2 p1, float2 p2, float2 p3, float line_y, float2 q) {
    float2 a = p1 - 2.0 * p2 + p3;
    float2 b = 2.0 * (p2 - p1);
    float2 c = p1;
    float change = step_below(q.x, p1.x) * step_below(line_y, p1.y) - step_below(q.x, p3.x) * step_below(line_y, p3.y);
    float prox_x = 3.4e38;
    float prox_y = 3.4e38;
    uint v_code = eligibility(p1.x, p2.x, p3.x, q.x);
    if (v_code != 0u) {
        float2 roots; bool dbl;
        if (solve_quadratic(a.x, b.x, c.x - q.x, roots, dbl)) {
            float2 y = (a.y * roots + b.y) * roots + c.y;
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
        float2 roots; bool dbl;
        if (solve_quadratic(a.y, b.y, c.y - q.y, roots, dbl) && !dbl) {
            float2 x = (a.x * roots + b.x) * roots + c.x;
            if ((h_code & 1u) != 0u) prox_x = closest(prox_x, q.x - x.x);
            if (h_code > 1u)         prox_x = closest(prox_x, x.y - q.x);
        }
    }
    return float3(change, prox_x, prox_y);
}

float text_coverage(float a, float3 rgb) {
    float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    return lerp(1.0 - pow(1.0 - a, 1.8), pow(a, 1.8), luma);
}

float4 ps_robin(V2P i) : SV_Target {
    int2 cell = int2(floor(clamp(i.uv, 0.0, 15.999)));
    int cell_index = int(i.extra.x) + cell.y * 16 + cell.x;
    float2 record = data_point(cell_index);
    uint encoded = uint(round(record.x));
    float winding = float(int((encoded >> 8) & 255u) - 128);
    int count = int(encoded & 255u);
    int start = int(round(record.y));
    float line_y = float(cell.y);
    float2 pixels_per_unit = 1.2 / fwidth(i.uv);
    float prox_x = 3.4e38;
    float prox_y = 3.4e38;
    for (int k = 0; k < count; k++) {
        int base = start + k * 3;
        float3 cnb = curve_crossing(data_point(base), data_point(base + 1), data_point(base + 2), line_y, i.uv);
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
    return float4(srgb_to_linear(i.color.rgb), i.color.a * text_coverage(alpha, i.color.rgb) * clip_coverage(i.pos.xy));
}

float4 ps_msdf(V2P i) : SV_Target {
    float3 s = u_tex.Sample(u_sampler, i.uv).rgb;
    float signed_distance = median3(s.r, s.g, s.b) - 0.5;
    float w, h;
    u_tex.GetDimensions(w, h);
    float2 unit_range = u_px_range / float2(w, h);
    float2 screen_tex_size = 1.0 / fwidth(i.uv);
    float screen_px_range = max(0.5 * dot(unit_range, screen_tex_size), 1.0);
    float coverage = saturate(screen_px_range * signed_distance + 0.5);
    return float4(srgb_to_linear(i.color.rgb), i.color.a * coverage * clip_coverage(i.pos.xy));
}

// a clear that respect the scissor, ClearRenderTargetView ignore it
float4 ps_clear(float4 pos : SV_Position) : SV_Target {
    return u_tint;
}

float4 vs_fullscreen(uint id : SV_VertexID) : SV_Position {
    float2 p = float2((id << 1) & 2, id & 2);
    return float4(p * 2.0 - 1.0, 0.0, 1.0);
}

// present through an sRGB view, so loads come back linear and premultiplied
float4 ps_present(float4 pos : SV_Position) : SV_Target {
    float4 c = u_tex.Load(int3(pos.xy, 0));
    float3 straight = c.a > 0.0 ? c.rgb / c.a : 0.0;
    return float4(linear_to_srgb(straight) * c.a, c.a);
}

// resolve averaged as light, a hardware resolve is up to the driver
float4 ps_resolve(float4 pos : SV_Position) : SV_Target {
    int2 at = int2(pos.xy);
    float4 sum = 0.0;
    for (int s = 0; s < u_samples; s++) sum += u_ms.Load(at, s);
    return sum / float(u_samples);
}
