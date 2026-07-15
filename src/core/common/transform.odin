package common

import "core:math"

Transform :: struct {
    translate: [2]f32,
    rotate:    f32, // radians
    scale:     [2]f32,
    origin:    [2]f32, // transform pivot in local px
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

transform_to_matrix :: proc(t: Transform) -> Mat3x3 {
    c := math.cos(t.rotate)
    s := math.sin(t.rotate)
    sx, sy := t.scale.x, t.scale.y
    ox, oy := t.origin.x, t.origin.y
    return Mat3x3 {
        c * sx, -s * sy, t.translate.x + ox - (c * sx * ox - s * sy * oy),
        s * sx, c * sy, t.translate.y + oy - (s * sx * ox + c * sy * oy),
        0, 0, 1,
    }
}
