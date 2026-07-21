package painter

import "src:core/render"
import "base:runtime"
import "src:core/common"

CONFIG_PAINTER_NAME :: #config(banana_PAINTER, "")

// "vector" tessellates on the CPU and draws through render.
DEFAULT_PAINTER_NAME :: "vector"
AVAILABLE_PAINTERS   :: "vector, nil"

when CONFIG_PAINTER_NAME == "" {
    PAINTER_NAME :: DEFAULT_PAINTER_NAME
} else {
    PAINTER_NAME :: CONFIG_PAINTER_NAME
}

when PAINTER_NAME == "vector" {
    PAINTER :: PAINTER_VECTOR
} else when PAINTER_NAME == "nil" {
    PAINTER :: PAINTER_NIL
} else {
    #panic("'" + PAINTER_NAME + "' is not a valid banana_PAINTER. Available: " + AVAILABLE_PAINTERS)
}

init           :: proc(p: Painter, allocator: runtime.Allocator) { PAINTER.init(p, allocator) }
state_size     :: proc() -> int { return PAINTER.state_size() }
shutdown       :: proc(p: Painter) { PAINTER.shutdown(p) }
begin_frame    :: proc(p: Painter, color: common.Color) { PAINTER.begin_frame(p, color) }
end_frame      :: proc(p: Painter) { PAINTER.end_frame(p) }
rect           :: proc(p: Painter, r: common.Rect, color: common.Color, radius: f32 = 0) { PAINTER.rect(p, r, color, radius)}
border         :: proc(p: Painter, r: common.Rect, color: common.Color, width: f32, radius: f32 = 0) { PAINTER.border(p, r, color, width, radius)}
image          :: proc(p: Painter, image: ^render.Image, dst: common.Rect, tint := common.COLOR_WHITE) { PAINTER.image(p, image, dst, tint) }
line           :: proc(p: Painter, a, b: [2]f32, color: common.Color, width: f32) { PAINTER.line(p, a, b, color, width) }
triangles      :: proc(p: Painter, points: [][2]f32, indices: []u32, color: common.Color) { PAINTER.triangles(p, points, indices, color) }
mesh_cached    :: proc(p: Painter, cache: ^Mesh_Cache, source_version: u64, vertices: []render.Vertex, indices: []u32) { PAINTER.mesh_cached(p, cache, source_version, vertices, indices) }
glyphs         :: proc(p: Painter, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) { PAINTER.glyphs(p, curves, version, quads, color)}
glyphs_cached  :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) { PAINTER.glyphs_cached(p, cache, source_version, curves, version, quads, color)}
msdf_cached    :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, atlas_pixels: []u8, atlas_w, atlas_h: int, atlas_version: u64, pixel_range: f32, quads: []MSDF_Quad, color: common.Color) { PAINTER.msdf_cached(p, cache, source_version, atlas_pixels, atlas_w, atlas_h, atlas_version, pixel_range, quads, color)}
pixel_scale    :: proc(p: Painter) -> [2]f32 { return PAINTER.pixel_scale(p) }
push_clip      :: proc(p: Painter, r: common.Rect, mode: ClipMode) { PAINTER.push_clip(p, r, mode) }
pop_clip       :: proc(p: Painter) { PAINTER.pop_clip(p) }
push_transform :: proc(p: Painter, t: common.Transform, at: [2]f32) { PAINTER.push_transform(p, t, at) }
pop_transform  :: proc(p: Painter) { PAINTER.pop_transform(p) }

@(private="file", thread_local)
_active: Painter

set_active :: proc(p: Painter) -> (prev: Painter) {
	prev = _active
	_active = p
	return prev
}

get :: proc(loc := #caller_location) -> Painter {
	assert(_active.state != nil, "painter.get() called outside a draw pass", loc)
	return _active
}
