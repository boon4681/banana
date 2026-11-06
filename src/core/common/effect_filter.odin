package common

EffectShadow  :: struct { x, y, blur, spread: f32, color: [4]f32, inset: bool }

Gradient_Stop :: struct { color: [4]f32, position: f32 }
Gradient_Kind :: enum u8 { Linear, Radial }
Gradient      :: struct { kind: Gradient_Kind, angle: f32, stops: []Gradient_Stop }

EffectFilterDecoration :: struct {
    shadows:        []EffectShadow,
    gradient:       Gradient,
    outline_color:  Color,
    outline_width:  f32,
    outline_offset: f32,
    alpha:          f32,
}

// `blur` and a shadow blur here are gaussian deviations.
EffectFilter :: struct {
    blur:    f32,
    color:   [4][4]f32,
    offset:  [4]f32,
    shadows: []EffectShadow,
}

EFFECT_FILTER_NONE :: EffectFilter{color = {{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}}}

filter_then :: proc(first: EffectFilter, color: [4][4]f32, offset: [4]f32) -> EffectFilter {
    out := first
    for row in 0 ..< 4 {
        out.offset[row] = offset[row]
        for column in 0 ..< 4 {
            out.color[row][column] = 0
            for k in 0 ..< 4 do out.color[row][column] += color[row][k] * first.color[k][column]
            out.offset[row] += color[row][column] * first.offset[column]
        }
    }
    return out
}

color_from_floats :: proc(c: [4]f32, alpha: f32 = 1) -> Color {
    return {
        u8(clamp(c[0] * 255 + 0.5, 0, 255)),
        u8(clamp(c[1] * 255 + 0.5, 0, 255)),
        u8(clamp(c[2] * 255 + 0.5, 0, 255)),
        u8(clamp(c[3] * alpha * 255 + 0.5, 0, 255)),
    }
}
