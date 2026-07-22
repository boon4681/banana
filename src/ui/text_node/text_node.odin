package text_node

import "core:math"
import "core:strings"
import "src:core/common"
import "src:core/node"
import "src:core/painter"
import "src:core/text"

// A DOM-like text node
Text_Node :: struct {
    using node: Node,
    set_text: proc(self: ^Text_Node, s: string),
    get_text: proc(self: ^Text_Node) -> string,
}

@(private = "file")
_Text_Data :: struct {
    str:         string, // owned copy
    shaped:      text.Shaped_Text,
    shaped_font: ^text.Font_Set, // font the current shaping was done with

    lines:          []text.Line,
    lines_max_w_em: f32,
    lines_valid:    bool,

    // Curve quads are expensive to rebuild for large static text.
    quads:          []painter.Glyph_Quad,
    msdf_quads:     []painter.MSDF_Quad,
    quad_rect:      common.Rect,
    quad_font:      ^text.Font_Set,
    quad_font_size: f32,
    quad_line_h:    f32,
    quad_scale_y:   f32,
    quads_valid:    bool,
    quad_version:   u64,
    glyph_cache:    painter.Glyph_Cache,
    msdf_cache:     painter.Glyph_Cache,
}

New :: proc(str: string = "", key: Maybe(string) = nil) -> ^Text_Node {
    n := new(Text_Node)
    node.Init(auto_cast (n), key)
    n.set_text = _set_text
    n.get_text = _get_text
    n.data = new(_Text_Data)

    n.draw = transmute(proc(self: ^Node))_draw
    n.on_free = transmute(proc(self: ^Node))_free
    n.measure = transmute(node.MeasureCallback)_measure
    n->apply_measure()

    _set_text(n, str)
    return n
}

@(private = "file")
_data :: proc(self: ^Text_Node) -> ^_Text_Data {
    return auto_cast (self.data)
}

@(private = "file")
_get_text :: proc(self: ^Text_Node) -> string {
    return _data(self).str
}

@(private = "file")
_set_text :: proc(self: ^Text_Node, s: string) {
    d := _data(self)
    delete(d.str)
    text.shaped_destroy(&d.shaped)
    d.shaped_font = nil
    _invalidate_layout(d)
    d.str = strings.clone(s)
    self->dirty()
}

@(private = "file")
_free :: proc(self: ^Text_Node) {
    d := _data(self)
    delete(d.str)
    text.shaped_destroy(&d.shaped)
    delete(d.lines)
    delete(d.quads)
    delete(d.msdf_quads)
    free(self.data)
}

@(private = "file")
_invalidate_layout :: proc(d: ^_Text_Data) {
    delete(d.lines)
    d.lines = nil
    d.lines_valid = false
    delete(d.quads)
    d.quads = nil
    delete(d.msdf_quads)
    d.msdf_quads = nil
    d.quads_valid = false
}

@(private = "file")
_resolve :: proc(self: ^Text_Node) -> node.Text_Style {
    out := node.Resolve_Text_Style(self)
    if out.font_size <= 0 do out.font_size = 16
    if out.color == {} do out.color = {255, 255, 255, 255}
    return out
}

// Shaping is lazy: at construction the node has no parent yet, so the font is
// unknown until measure/draw. Re-shapes if the inherited font changed.
@(private = "file")
_ensure_shaped :: proc(self: ^Text_Node, font: ^text.Font_Set) {
    d := _data(self)
    if font == nil || d.shaped_font == font do return
    text.shaped_destroy(&d.shaped)
    d.shaped = text.shape(font, d.str)
    d.shaped_font = font
    _invalidate_layout(d)
}

@(private = "file")
_ensure_lines :: proc(d: ^_Text_Data, max_w_em: f32) -> []text.Line {
    if d.lines_valid && d.lines_max_w_em == max_w_em do return d.lines
    delete(d.lines)
    d.lines = text.break_lines(&d.shaped, max_w_em, context.allocator)
    d.lines_max_w_em = max_w_em
    d.lines_valid = true
    d.quads_valid = false
    return d.lines
}

// CSS: a length resolves against font-size.
@(private = "file")
_line_height_em :: proc(st: node.Text_Style) -> f32 {
    if st.line_height > 0 {
        #partial switch st.line_height_unit {
        case .Point:   return st.line_height / st.font_size
        case .Percent: return st.line_height
        }
    }
    return text.line_height(st.font)
}

@(private="file")
_draw_cached :: proc(d: ^_Text_Data, p: painter.Painter, st: node.Text_Style) {
    if len(d.msdf_quads) > 0 {
        pixels, aw, ah, atlas_version := text.msdf_atlas_data()
        painter.msdf_cached(p, &d.msdf_cache, d.quad_version, pixels, aw, ah, atlas_version, f32(text.MSDF_RANGE_PX), d.msdf_quads, st.color)
    }
    if len(d.quads) > 0 {
        curves, version := text.curve_data()
        painter.glyphs_cached(p, &d.glyph_cache, d.quad_version, curves, version, d.quads, st.color)
    }
}

@(private = "file")
_measure :: proc(self: ^Text_Node, w: f32, w_mode: node.MeasureMode, h: f32, h_mode: node.MeasureMode) -> (out_w, out_h: f32) {
    st := _resolve(self)
    _ensure_shaped(self, st.font)
    d := _data(self)
    if st.font == nil || len(d.shaped.words) == 0 do return 0, 0

    size := st.font_size
    max_w_em := f32(math.F32_MAX)
    if w_mode != .Undefined && !math.is_nan(w) && w > 0 do max_w_em = w / size

    lines := _ensure_lines(d, max_w_em)
    widest: f32 = 0
    for l in lines do widest = max(widest, l.width)

    out_w = widest * size
    out_h = f32(len(lines)) * _line_height_em(st) * size

    switch w_mode {
    case .Exactly: out_w = w
    case .AtMost:  out_w = min(out_w, w)
    case .Undefined:
    }
    switch h_mode {
    case .Exactly: out_h = h
    case .AtMost:  out_h = min(out_h, h)
    case .Undefined:
    }
    return out_w, out_h
}

@(private = "file")
_draw :: proc(self: ^Text_Node) {
    st := _resolve(self)
    _ensure_shaped(self, st.font)
    d := _data(self)
    if st.font == nil || len(d.shaped.words) == 0 do return

    p := painter.get()
    size := st.font_size
    r := self.rect

    max_w_em := f32(math.F32_MAX)
    if r.w > 0 do max_w_em = r.w / size
    lines := _ensure_lines(d, max_w_em)

    scale := painter.pixel_scale(p)
    lh := _line_height_em(st)
    geometry_matches := d.quads_valid &&
        d.quad_rect == r &&
        d.quad_font == st.font &&
        d.quad_font_size == size &&
        d.quad_line_h == lh &&
        d.quad_scale_y == scale.y

    // skip if the geometry is the same
    if geometry_matches {
        _draw_cached(d, p, st)
        return
    }

    total_glyphs := 0
    for word in d.shaped.words {
        total_glyphs += len(word.glyphs)
    }
    delete(d.quads)
    quads := make([dynamic]painter.Glyph_Quad, 0, total_glyphs, context.allocator)
    delete(d.msdf_quads)
    msdf_quads := make([dynamic]painter.MSDF_Quad, 0, total_glyphs, context.allocator)

    // Half-leading: extra leading splits evenly above and below the text.
    ascent := text.ascent(st.font)
    descent := text.descent(st.font)
    half_leading := (lh - (ascent - descent)) * 0.5
    // 1 layout px of dilation so shader anti-aliasing isn't clipped at quad edges.
    pad := 1.0 / size

    y := r.y
    for l in lines {
        baseline := y + (half_leading + ascent) * size
        if scale.y > 0 do baseline = math.round(baseline * scale.y) / scale.y

        order := make([]int, l.end - l.start, context.temp_allocator)
        text.line_visual_order(&d.shaped, l, order)

        pen := r.x
        for wi in order {
            word := d.shaped.words[wi]
            if wi != l.start && word.space_before do pen += d.shaped.space_advance * size
            for g in word.glyphs {
                gl := text.glyph(g.face, g.gid)
                if gl.curve_count > 0 {
                    gx := pen + g.offset.x * size
                    gy := baseline - g.offset.y * size
                    if mg, ok := text.msdf_glyph(g.face, g.gid); ok {
                        append(&msdf_quads, painter.MSDF_Quad{
                            rect = {
                                gx + mg.plane[0] * size,
                                gy - mg.plane[3] * size,
                                (mg.plane[2] - mg.plane[0]) * size,
                                (mg.plane[3] - mg.plane[1]) * size,
                            },
                            uv = mg.uv,
                        })
                    } else {
                        lo := gl.min - pad
                        hi := gl.max + pad
                        append(&quads, painter.Glyph_Quad{
                            rect = {
                                gx + lo.x * size,
                                gy - hi.y * size,
                                (hi.x - lo.x) * size,
                                (hi.y - lo.y) * size,
                            },
                            uv0         = {lo.x, hi.y},
                            uv1         = {hi.x, lo.y},
                            curve_base  = gl.curve_base,
                            curve_count = gl.curve_count,
                        })
                    }
                }
                pen += g.advance * size
            }
        }
        y += lh * size
    }

    d.quads = quads[:]
    d.msdf_quads = msdf_quads[:]
    d.quad_rect = r
    d.quad_font = st.font
    d.quad_font_size = size
    d.quad_line_h = lh
    d.quad_scale_y = scale.y
    d.quads_valid = true
    d.quad_version += 1

    _draw_cached(d, p, st)
}
