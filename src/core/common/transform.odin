package common

import "core:math"

Transform :: struct {
    translate:  [2]f32,
    rotate:     f32, // radians
    scale:      [2]f32,
    origin:     [2]f32, // transform pivot in local px
    linear:     [4]f32, // With has_linear, CSS matrix(a, b, c, d, e, f) replace rotate and scale.
    has_linear: bool,
}

transform_linear :: #force_inline proc "contextless"(t: Transform) -> matrix[2, 2]f32 {
    if t.has_linear {
        return {
            t.linear[0], t.linear[2],
            t.linear[1], t.linear[3],
        }
    }
    c := math.cos(t.rotate)
    s := math.sin(t.rotate)
    return {
        c * t.scale.x, -s * t.scale.y,
        s * t.scale.x, c * t.scale.y,
    }
}

IDENTITY_TRANSFORM :: Transform {
    scale = {1, 1},
}

Mat3x3 :: matrix[3, 3]f32

Mat3X3_IDENTITY :: Mat3x3{
    1, 0, 0,
    0, 1, 0,
    0, 0, 1,
}

transform_to_matrix :: proc "contextless"(t: Transform) -> Mat3x3 {
    lin := transform_linear(t)
    tr := t.translate + t.origin - lin * t.origin
    return Mat3x3 {
        lin[0, 0], lin[0, 1], tr.x,
        lin[1, 0], lin[1, 1], tr.y,
        0, 0, 1,
    }
}

transform_at_matrix :: proc(t: Transform, at: [2]f32) -> Mat3x3 {
    adjusted := t
    adjusted.origin += at
    return transform_to_matrix(adjusted)
}

affine_inverse :: proc(m: Mat3x3) -> (Mat3x3, bool) {
    det := m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0]
    if math.abs(det) <= 1e-8 do return Mat3X3_IDENTITY, false

    inv_det := 1 / det
    a  :=  m[1, 1] * inv_det
    b  := -m[0, 1] * inv_det
    c  := -m[1, 0] * inv_det
    d  :=  m[0, 0] * inv_det
    tx := -(a * m[0, 2] + b * m[1, 2])
    ty := -(c * m[0, 2] + d * m[1, 2])
    return Mat3x3{
        a, b, tx,
        c, d, ty,
        0, 0, 1,
    }, true
}

transform_point :: proc(m: Mat3x3, p: [2]f32) -> [2]f32 {
    q := m * [3]f32{p.x, p.y, 1}
    return {q.x, q.y}
}
