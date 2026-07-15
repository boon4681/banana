package painter

import "base:runtime"
import "src:core/render"
import "src:core/common"

ClipMode :: enum {
	None,
	Scissor,
	Stencil,
}

// Instance handle: `state` points at a properly aligned State_Layout block
// owned by the window. Stateless painters use nil.
Painter :: struct {
    state: rawptr,
}

// One glyph quad: `rect` in absolute layout px, uv0/uv1 the em-space (y-up)
// outline coordinates at the rect's top-left/bottom-right corners.
Glyph_Quad :: struct {
    rect:        common.Rect,
    uv0, uv1:    [2]f32,
    curve_base:  u32,
    curve_count: u32,
}

Painter_Interface :: struct #all_or_none {
    state_size: proc() -> int,
    init:       proc(p: Painter, allocator: runtime.Allocator),
    shutdown:   proc(p: Painter),

    begin_frame: proc(p: Painter, color: common.Color),
    end_frame:   proc(p: Painter),

    rect:   proc(p: Painter, r: common.Rect, color: common.Color, radius: f32 = 0),
    border: proc(p: Painter, r: common.Rect, color: common.Color, width: f32, radius: f32 = 0),
    image:  proc(p: Painter, image: ^render.Image, dst: common.Rect, tint := common.Color{255, 255, 255, 255}),
    line:   proc(p: Painter, a, b: [2]f32, color: common.Color, width: f32),
	// `curves`/`version` come from text.curve_data(); quads reference into it.
    glyphs: proc(p: Painter, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color),

	// Device px per local px under the current transform stack; lets text snap
	// baselines to physical pixels at fractional display scales.
    pixel_scale: proc(p: Painter) -> [2]f32,

    push_clip: proc(p: Painter, r: common.Rect, mode: ClipMode),
    pop_clip:  proc(p: Painter),
	// `at` is the node's absolute origin; t.origin pivots relative to it.
    push_transform: proc(p: Painter, t: common.Transform, at: [2]f32),
    pop_transform:  proc(p: Painter),
}
