// Headless painter. It owns no state and intentionally draws nothing.

package painter

import "base:runtime"
import "src:core/render"
import "src:core/common"

_pnil_state_size :: proc() -> int {
    return 0
}

_pnil_init :: proc(p: Painter, allocator: runtime.Allocator) {
    _ = p; _ = allocator
}

_pnil_shutdown :: proc(p: Painter) {
    _ = p
}

_pnil_begin_frame :: proc(p: Painter, color: common.Color) {
    _ = p; _ = color
}

_pnil_end_frame :: proc(p: Painter) {
    _ = p
}

_pnil_rect :: proc(p: Painter, r: common.Rect, color: common.Color, radius: f32 = 0) {
    _ = p; _ = r; _ = color; _ = radius
}

_pnil_border :: proc(p: Painter, r: common.Rect, color: common.Color, width: f32, radius: f32 = 0) {
    _ = p; _ = r; _ = color; _ = width; _ = radius
}

_pnil_image :: proc(p: Painter, image: ^render.Image, dst: common.Rect, tint := common.COLOR_WHITE) {
    _ = p; _ = image; _ = dst; _ = tint
}

_pnil_line :: proc(p: Painter, a, b: [2]f32, color: common.Color, width: f32) {
    _ = p; _ = a; _ = b; _ = color; _ = width
}

_pnil_glyphs :: proc(p: Painter, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    _ = p; _ = curves; _ = version; _ = quads; _ = color
}

_pnil_pixel_scale :: proc(p: Painter) -> [2]f32 {
    _ = p
    return {1, 1}
}

_pnil_push_clip :: proc(p: Painter, r: common.Rect, mode: ClipMode) {
    _ = p; _ = r; _ = mode
}

_pnil_pop_clip :: proc(p: Painter) {
    _ = p
}

_pnil_push_transform :: proc(p: Painter, t: common.Transform, at: [2]f32) {
    _ = p; _ = t; _ = at
}

_pnil_pop_transform :: proc(p: Painter) {
    _ = p
}

PAINTER_NIL :: Painter_Interface {
    state_size     = _pnil_state_size,
    init           = _pnil_init,
    shutdown       = _pnil_shutdown,
    begin_frame    = _pnil_begin_frame,
    end_frame      = _pnil_end_frame,
    rect           = _pnil_rect,
    border         = _pnil_border,
    image          = _pnil_image,
    line           = _pnil_line,
    glyphs         = _pnil_glyphs,
    pixel_scale    = _pnil_pixel_scale,
    push_clip      = _pnil_push_clip,
    pop_clip       = _pnil_pop_clip,
    push_transform = _pnil_push_transform,
    pop_transform  = _pnil_pop_transform,
}
