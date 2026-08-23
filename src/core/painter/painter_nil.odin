// Headless painter. It owns no state and intentionally draws nothing.

package painter

import "base:runtime"
import "src:core/render"
import "src:core/common"

@(private = "file")
_create_state :: proc(allocator: runtime.Allocator) -> rawptr {
    return nil
}

@(private = "file")
_free_state :: proc(state: rawptr, allocator: runtime.Allocator) {
    if state != nil do runtime.mem_free(state, allocator)
}

@(private="file")
_init :: proc(p: Painter, allocator: runtime.Allocator) {
    panic("nil painter")
}

@(private="file")
_shutdown :: proc(p: Painter) {
    panic("nil painter")
}

@(private="file")
_begin_frame :: proc(p: Painter, color: common.Color) {
    panic("nil painter")
}

@(private="file")
_end_frame :: proc(p: Painter) {
    panic("nil painter")
}

@(private="file")
_rect :: proc(p: Painter, r: common.Rect, color: common.Color, radius: f32 = 0) {
    panic("nil painter")
}

@(private="file")
_border :: proc(p: Painter, r: common.Rect, color: common.Color, width: f32, radius: f32 = 0) {
    panic("nil painter")
}

@(private="file")
_image :: proc(p: Painter, image: ^render.Image, dst: common.Rect, tint := common.COLOR_WHITE) {
    panic("nil painter")
}

@(private="file")
_line :: proc(p: Painter, a, b: [2]f32, color: common.Color, width: f32) {
    panic("nil painter")
}

@(private="file")
_triangles :: proc(p: Painter, points: [][2]f32, indices: []u32, color: common.Color) {
    panic("nil painter")
}

@(private="file")
_mesh_cached :: proc(p: Painter, cache: ^Mesh_Cache, source_version: u64, vertices: []render.Vertex, indices: []u32) {
    panic("nil painter")
}

@(private="file")
_glyphs :: proc(p: Painter, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    panic("nil painter")
}

@(private="file")
_glyphs_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    panic("nil painter")
}

@(private="file")
_robin_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, data: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    panic("nil painter")
}

@(private="file")
_msdf_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, atlas: MSDF_Atlas, quads: []MSDF_Quad, color: common.Color) {
    panic("nil painter")
}

@(private="file")
_pixel_scale :: proc(p: Painter) -> [2]f32 {
    panic("nil painter")
}

@(private="file")
_push_clip :: proc(p: Painter, r: common.Rect, mode: ClipMode) {
    panic("nil painter")
}

@(private="file")
_pop_clip :: proc(p: Painter) {
    panic("nil painter")
}

@(private="file")
_push_transform :: proc(p: Painter, t: common.Transform, at: [2]f32) {
    panic("nil painter")
}

@(private="file")
_pop_transform :: proc(p: Painter) {
    panic("nil painter")
}

PAINTER_NIL :: Painter_Interface {
    create_state   = _create_state,
    free_state     = _free_state,
    init           = _init,
    shutdown       = _shutdown,
    begin_frame    = _begin_frame,
    end_frame      = _end_frame,
    rect           = _rect,
    border         = _border,
    image          = _image,
    line           = _line,
    triangles      = _triangles,
    mesh_cached    = _mesh_cached,
    glyphs         = _glyphs,
    glyphs_cached  = _glyphs_cached,
    robin_cached   = _robin_cached,
    msdf_cached    = _msdf_cached,
    pixel_scale    = _pixel_scale,
    push_clip      = _push_clip,
    pop_clip       = _pop_clip,
    push_transform = _push_transform,
    pop_transform  = _pop_transform,
}
