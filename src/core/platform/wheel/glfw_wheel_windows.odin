#+build windows
package glfw_wheel

import win "core:sys/windows"

_normalize_wheel :: proc(dx, dy: f64, viewport_w, viewport_h: f32) -> (x, y: f32) {
    chars: win.UINT = 3
    lines: win.UINT = 3
    win.SystemParametersInfoW(win.SPI_GETWHEELSCROLLCHARS, 0, &chars, 0)
    win.SystemParametersInfoW(win.SPI_GETWHEELSCROLLLINES, 0, &lines, 0)

    if chars == win.WHEEL_PAGESCROLL {
        x = f32(dx) * viewport_w * 0.875
    } else {
        x = f32(dx * f64(chars)) * (100.0 / 3.0)
    }
    if lines == win.WHEEL_PAGESCROLL {
        y = f32(dy) * viewport_h * 0.875
    } else {
        y = f32(dy * f64(lines)) * (100.0 / 3.0)
    }
    return x, y
}
