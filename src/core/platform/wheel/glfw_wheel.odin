#+build !windows
package glfw_wheel

_normalize_wheel :: proc(dx, dy: f64, viewport_w, viewport_h: f32) -> (x, y: f32) {
    return f32(dx * 100), f32(dy * 100)
}
