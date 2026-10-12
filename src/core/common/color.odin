package common

import "core:math"

srgb_to_linear :: proc(c: f32) -> f32 {
    if c <= 0.04045 do return c / 12.92
    return math.pow((c + 0.055) / 1.055, 2.4)
}

Color       :: [4]u8  // RGBA, non-premultiplied, 0..255

COLOR_WHITE :: Color{255, 255, 255, 255}
COLOR_BLACK :: Color{0, 0, 0, 255}
