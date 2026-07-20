package text_node

import "core:math"
import "core:strings"
import "src:core/node"
import "src:core/painter"
import "src:core/text"
import YG "src:yoga"

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
}

New :: proc(str: string = "", key: Maybe(string) = nil) -> ^Text_Node {
    n := new(Text_Node)
    node.Init(auto_cast (n), key)
    n.set_text = _set_text
    n.get_text = _get_text
    n.data = new(_Text_Data)

    n.draw = transmute(proc(self: ^Node))_text_draw
    n.on_free = transmute(proc(self: ^Node))_text_free
    n.measure = transmute(node.MeasureCallback)_text_measure
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
    d.str = strings.clone(s)
    YG.NodeMarkDirty(self.raw)
}

@(private = "file")
_text_free :: proc(self: ^Text_Node) {
    d := _data(self)
    delete(d.str)
    text.shaped_destroy(&d.shaped)
    free(self.data)
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
}

// Line box height in em: style override or CSS `normal`.
@(private = "file")
_line_height_em :: proc(st: node.Text_Style) -> f32 {
    if st.line_height > 0 do return st.line_height / st.font_size
    return text.line_height(st.font)
}

@(private = "file")
_text_measure :: proc(self: ^Text_Node, w: f32, w_mode: node.MeasureMode, h: f32, h_mode: node.MeasureMode) -> (out_w, out_h: f32) {
    st := _resolve(self)
    _ensure_shaped(self, st.font)
    d := _data(self)
    if st.font == nil || len(d.shaped.words) == 0 do return 0, 0

    size := st.font_size
    max_w_em := f32(math.F32_MAX)
    // Half-pixel slack: yoga rounds the box to the pixel grid.
    // if this bug remove + 0.5
    if w_mode != .Undefined && !math.is_nan(w) && w > 0 do max_w_em = (w + 0.5) / size

    lines := text.break_lines(&d.shaped, max_w_em)
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
    return
}

@(private = "file")
_text_draw :: proc(self: ^Text_Node) {
    st := _resolve(self)
    _ensure_shaped(self, st.font)
    d := _data(self)
    if st.font == nil || len(d.shaped.words) == 0 do return

    p := painter.get()
    size := st.font_size
    r := self.rect

    max_w_em := f32(math.F32_MAX)
    // Same half-pixel slack as _text_measure so measure and paint wrap identically.
    if r.w > 0 do max_w_em = (r.w + 0.5) / size
    lines := text.break_lines(&d.shaped, max_w_em)

    total_glyphs := 0
    for word in d.shaped.words do total_glyphs += len(word.glyphs)
    quads := make([dynamic]painter.Glyph_Quad, 0, total_glyphs, context.temp_allocator)

    scale := painter.pixel_scale(p)
    lh := _line_height_em(st)
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
                pen += g.advance * size
            }
        }
        y += lh * size
    }

    if len(quads) == 0 do return
    curves, version := text.curve_data()
    painter.glyphs(p, curves, version, quads[:], st.color)
}
