package text_node

import "core:math"
import "core:strings"
import "core:unicode"
import "src:core/common"
import "src:core/input"
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

SELECTION_COLOR :: common.Color{60, 110, 220, 255}

@(private = "file")
_Text_Data :: struct {
    str:           string, // owned copy
    shaped:        text.Shaped_Text,
    shaped_font:   ^text.Font_Set, // font the current shaping was done with
    shaped_weight: text.FontWeight,
    shaped_transform: node.Text_Transform,
    shaped_spacing: f32,
    shaped_fit:     f32,

    lines:          []text.Line,
    lines_max_w_em: f32,
    lines_valid:    bool,
    measured_w_em:  f32,
    measured_w_valid: bool,

    // Curve quads are expensive to rebuild for large static text.
    quads:          []painter.Glyph_Quad,
    robin_quads:    []painter.Glyph_Quad,
    msdf_quads:     []painter.MSDF_Quad,
    quad_rect:      common.Rect,
    quad_font:      ^text.Font_Set,
    quad_font_size: f32,
    quad_weight:    text.FontWeight,
    quad_line_h:    f32,
    quad_scale_y:   f32,
    quad_align:     f32,
    quads_valid:    bool,
    quad_version:   u64,
    glyph_cache:    painter.Glyph_Cache,
    robin_cache:    painter.Glyph_Cache,
    msdf_cache:     painter.Glyph_Cache,

    // COLR v1 bitmaps bypass the outline caches.
    color_quads: []_Color_Quad,
}

@(private = "file")
_Color_Quad :: struct {
    rect: common.Rect,
    face: ^text.Face,
    gid:  u32,
    size: f32,
}

@(private = "file")
_TEXT_CONTENT_INTERFACE := node.Text_Content_Interface{
    position_at = transmute(proc(self: ^Node, x, y: f32) -> text.Position)_position_at,
    expand      = transmute(proc(self: ^Node, pos: text.Position, g: text.Granularity) -> text.Selection)_expand_selection,
    str         = transmute(proc(self: ^Node) -> string)_get_text,
}

New :: proc(str: string = "", key: Maybe(string) = nil) -> ^Text_Node {
    n := new(Text_Node)
    node.Init(n, key)
    n.set_text = _set_text
    n.get_text = _get_text
    n.data = new(_Text_Data)

    n.draw = transmute(proc(self: ^Node))_draw
    n.on_free = transmute(proc(self: ^Node))_free
    n.measure = transmute(node.MeasureCallback)_measure
    n.min_content = transmute(proc(self: ^Node) -> [2]f32)_min_content
    n.text_content = &_TEXT_CONTENT_INTERFACE
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
    if d.str == s do return
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
    delete(d.robin_quads)
    delete(d.msdf_quads)
    delete(d.color_quads)
    free(self.data)
}

@(private = "file")
_invalidate_layout :: proc(d: ^_Text_Data) {
    delete(d.lines)
    d.lines = nil
    d.lines_valid = false
    d.measured_w_valid = false
    delete(d.quads)
    d.quads = nil
    delete(d.robin_quads)
    d.robin_quads = nil
    delete(d.msdf_quads)
    d.msdf_quads = nil
    delete(d.color_quads)
    d.color_quads = nil
    d.quads_valid = false
}

// Shaping and line-breaking are lazy, so a hit-test arriving before the first
// draw has to bring both up to date itself.
@(private = "file")
_ensure_current :: proc(self: ^Text_Node, laying_out := false) -> (^_Text_Data, node.Text_Style, []text.Line, bool) {
    st := _resolve(self)
    _ensure_shaped(self, st)
    d := _data(self)
    if st.font == nil do return d, st, nil, false

    // While layout settles, `rect` is still the previous layout's: a text that just
    // grew would be wrapped at its old width and reported a line too tall.
    width := YG.NodeLayoutGetWidth(self.raw) if laying_out else self.rect.w
    max_w_em := _resolve_layout_width_em(d.measured_w_em, d.measured_w_valid, width, st.font_size)
    if !_wraps(st) do max_w_em = math.F32_MAX
    return d, st, _ensure_lines(d, max_w_em), true
}

@(private)
_resolve_layout_width_em :: proc(measured_w_em: f32, measured_w_valid: bool, width, size: f32) -> f32 {
    actual := f32(math.F32_MAX)
    if width > 0 do actual = width / size
    // Yoga may measure at a fractional width and pixel-round the final rect.
    // Keep the measured width in that case so line count, node height, drawing,
    // and scroll extent all describe the same layout.
    if measured_w_valid && !math.is_inf(measured_w_em) &&
       abs(measured_w_em * size - width) <= 1 {
        return measured_w_em
    }
    return actual
}

@(private = "file")
_metrics :: proc(st: node.Text_Style, r: common.Rect) -> text.Layout_Metrics {
    return text.Layout_Metrics{
        line_height = _line_height_em(st),
        max_w       = r.w / st.font_size if st.font_size > 0 else 0,
        align       = _align(st),
    }
}

@(private = "file")
_align :: proc(st: node.Text_Style) -> f32 {
    #partial switch st.align {
    case .Center: return 0.5
    case .Right:  return 1
    }
    return 0
}

@(private = "file")
_position_at :: proc(self: ^Text_Node, x, y: f32) -> text.Position {
    d, st, lines, ok := _ensure_current(self)
    if !ok do return {}
    size := st.font_size
    // Node-local px -> em, which is the space the selection layer works in.
    return text.position_at_point(
        &d.shaped, lines, _metrics(st, self.rect),
        (x - self.rect.x) / size, (y - self.rect.y) / size,
    )
}

@(private = "file")
_expand_selection :: proc(self: ^Text_Node, pos: text.Position, g: text.Granularity) -> text.Selection {
    d, _, lines, ok := _ensure_current(self)
    if !ok do return {pos, pos}
    lo, hi := text.expand(&d.shaped, lines, pos, g)
    return {{lo, false}, {hi, true}}
}

@(private = "file")
_resolve :: proc(self: ^Text_Node) -> node.Text_Style {
    out := node.Resolve_Text_Style(self)
    if !out.computed {
        if out.font_size <= 0 do out.font_size = 16
        if out.color == {} do out.color = {255, 255, 255, 255}
    }
    return out
}

// Shaping is lazy: at construction the node has no parent yet, so the font is
// unknown until measure/draw. Re-shapes if the inherited font changed.
@(private = "file")
_ensure_shaped :: proc(self: ^Text_Node, st: node.Text_Style) {
    d := _data(self)
    font, weight := st.font, st.font_weight
    if font == nil do return
    spacing := st.letter_spacing / st.font_size if st.font_size > 0 else 0
    fit := _ellipsis_width_em(self, st)
    if d.shaped_font == font && d.shaped_weight == weight && d.shaped_transform == st.transform &&
       d.shaped_spacing == spacing && d.shaped_fit == fit {
        return
    }
    shown := _transformed(d.str, st.transform)
    text.shaped_destroy(&d.shaped)
    d.shaped = text.shape(font, shown, weight)
    _space_letters(&d.shaped, spacing)
    if fit > 0 && _shaped_width(&d.shaped) > fit {
        dots := text.shape(font, "…", weight, context.temp_allocator)
        _space_letters(&dots, spacing)
        cut := _fit_prefix(&d.shaped, fit - _shaped_width(&dots))
        clipped := strings.concatenate({strings.trim_right_space(shown[:cut]), "…"}, context.temp_allocator)
        text.shaped_destroy(&d.shaped)
        d.shaped = text.shape(font, clipped, weight)
        _space_letters(&d.shaped, spacing)
    }
    d.shaped_font = font
    d.shaped_weight = weight
    d.shaped_transform = st.transform
    d.shaped_spacing = spacing
    d.shaped_fit = fit
    _invalidate_layout(d)
}

@(private = "file")
_min_content :: proc(self: ^Text_Node) -> (size: [2]f32) {
    d, st, lines, ok := _ensure_current(self, true)
    if st.font == nil || st.font_size <= 0 do return
    line := _line_height_em(st) * st.font_size
    if !ok || len(d.shaped.words) == 0 {
        size.y = line if len(d.str) > 0 else 0
        return
    }
    size.y = f32(len(lines)) * line
    if !_wraps(st) {
        if st.overflow != .Ellipsis do size.x = _shaped_width(&d.shaped) * st.font_size
        return
    }
    for word in d.shaped.words do size.x = max(size.x, word.width)
    size.x *= st.font_size
    return
}

@(private = "file")
_wraps :: proc(st: node.Text_Style) -> bool {
    return st.white_space != .No_Wrap && st.white_space != .Pre
}

@(private = "file")
_ellipsis_width_em :: proc(self: ^Text_Node, st: node.Text_Style) -> f32 {
    if st.overflow != .Ellipsis || _wraps(st) || self.parent == nil || st.font_size <= 0 do return 0
    width := self.parent->get_rect(.Content).w
    return width / st.font_size if width > 0 else 0
}

@(private = "file")
_transformed :: proc(s: string, transform: node.Text_Transform) -> string {
    #partial switch transform {
    case .Uppercase: return strings.to_upper(s, context.temp_allocator)
    case .Lowercase: return strings.to_lower(s, context.temp_allocator)
    case .Capitalize:
        out := strings.builder_make(0, len(s), context.temp_allocator)
        start := true
        for r in s {
            strings.write_rune(&out, unicode.to_upper(r) if start else r)
            start = unicode.is_space(r)
        }
        return strings.to_string(out)
    }
    return s
}

@(private = "file")
_space_letters :: proc(shaped: ^text.Shaped_Text, spacing: f32) {
    if spacing == 0 do return
    for &word in shaped.words {
        for &glyph in word.glyphs do glyph.advance += spacing
        word.width += spacing * f32(len(word.glyphs))
    }
    shaped.space_advance += spacing
}

@(private = "file")
_shaped_width :: proc(shaped: ^text.Shaped_Text) -> (width: f32) {
    for word, i in shaped.words {
        if i > 0 && word.space_before do width += shaped.space_advance
        width += word.width
    }
    return
}

@(private = "file")
_fit_prefix :: proc(shaped: ^text.Shaped_Text, limit: f32) -> (cut: int) {
    width: f32
    for word, i in shaped.words {
        if i > 0 && word.space_before do width += shaped.space_advance
        for glyph in word.glyphs {
            if width + glyph.advance > limit do return
            width += glyph.advance
            cut = max(cut, glyph.cluster_end)
        }
    }
    return
}

@(private = "file")
_draw_decoration :: proc(d: ^_Text_Data, p: painter.Painter, st: node.Text_Style, r: common.Rect, lines: []text.Line, lh: f32) {
    if st.decoration != .Underline && st.decoration != .Line_Through do return
    size := st.font_size
    ascent := text.ascent(st.font, st.font_weight)
    descent := text.descent(st.font, st.font_weight)
    thickness := max(1, math.round(size / 14))
    shift := size * 0.12 if st.decoration == .Underline else -size * 0.3
    for l, i in lines {
        baseline := r.y + (f32(i) * lh + (lh - (ascent - descent)) * 0.5 + ascent) * size
        x := r.x + text.line_offset(l, _metrics(st, r)) * size
        painter.rect(p, {x, math.round(baseline + shift), l.width * size, thickness}, st.color)
    }
}

@(private = "file")
_ensure_lines :: proc(d: ^_Text_Data, max_w_em: f32) -> []text.Line {
    if d.lines_valid && d.lines_max_w_em == max_w_em do return d.lines
    when common.FRAME_PROFILE {
        if d.lines_valid {
            common.profile_count(.Reline_Width)
            common.profile_note("reline w_em", f64(d.lines_max_w_em), f64(max_w_em))
        } else {
            common.profile_count(.Reline_Invalid)
        }
    }
    delete(d.lines)
    d.lines = text.break_lines(&d.shaped, max_w_em, context.allocator)
    d.lines_max_w_em = max_w_em
    d.lines_valid = true
    d.quads_valid = false
    return d.lines
}

// CSS: a length resolves against font-size.
@(private)
_line_height_em :: proc(st: node.Text_Style) -> f32 {
    if st.line_height_specified || st.line_height > 0 {
        #partial switch st.line_height_unit {
        case .Point:   return st.line_height / st.font_size if st.font_size > 0 else 0
        case .Percent: return st.line_height
        }
    }
    return text.line_height(st.font, st.font_weight)
}

@(private = "file")
_draw_selection :: proc(self: ^Text_Node, d: ^_Text_Data, p: painter.Painter, st: node.Text_Style, r: common.Rect, im: ^input.Input_State) {
    sel, ok := input.selection_for_node(im, self)
    if !ok || text.sel_empty(sel) || len(d.lines) == 0 do return
    size := st.font_size
    rects := text.selection_rects(&d.shaped, d.lines, _metrics(st, r), sel)
    for hr in rects {
        painter.rect(p, common.Rect{
            r.x + hr.x * size,
            r.y + hr.y * size,
            hr.w * size,
            hr.h * size,
        }, SELECTION_COLOR)
    }
}

@(private="file")
_draw_cached :: proc(d: ^_Text_Data, p: painter.Painter, st: node.Text_Style) {
    when text.ROBIN_TEXT_ACTIVE {
        if len(d.robin_quads) > 0 {
            data, version := text.robin_render_data()
            painter.robin_cached(p, &d.robin_cache, d.quad_version, data, version, d.robin_quads, st.color)
        }
    }
    if len(d.msdf_quads) > 0 {
        pixels, aw, ah, atlas_version := text.msdf_atlas_data()
        lo, hi := text.msdf_atlas_dirty_rows()
        painter.msdf_cached(p, &d.msdf_cache, d.quad_version, painter.MSDF_Atlas{
            pixels      = pixels,
            width       = aw,
            height      = ah,
            version     = atlas_version,
            dirty_lo    = lo,
            dirty_hi    = hi,
            pixel_range = f32(text.MSDF_RANGE_PX),
        }, d.msdf_quads, st.color)
    }
    if len(d.quads) > 0 {
        curves, version := text.curve_data()
        painter.glyphs_cached(p, &d.glyph_cache, d.quad_version, curves, version, d.quads, st.color)
    }
    for q in d.color_quads {
        bm, ok := text.color_bitmap_cached(q.face, q.gid, q.size)
        if !ok || bm.image == nil do continue
        painter.image(p, bm.image, q.rect)
    }
}

@(private = "file")
_measure :: proc(self: ^Text_Node, w: f32, w_mode: node.MeasureMode, h: f32, h_mode: node.MeasureMode) -> (out_w, out_h: f32) {
    st := _resolve(self)
    _ensure_shaped(self, st)
    d := _data(self)
    if st.font == nil do return 0, 0

    size := st.font_size
    // Give all-space inline separators one collapsed advance.
    if size <= 0 {
        out_w = w if w_mode == .Exactly else 0
        out_h = st.line_height if st.line_height_specified && st.line_height_unit == .Point else 0
        if h_mode == .Exactly { out_h = h }
        else if h_mode == .AtMost { out_h = min(out_h, h) }
        return
    }
    if len(d.shaped.words) == 0 {
        if len(d.str) == 0 do return 0, 0
        out_w = d.shaped.space_advance * size
        out_h = _line_height_em(st) * size
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

    max_w_em := f32(math.F32_MAX)
    if _wraps(st) && w_mode != .Undefined && !math.is_nan(w) && w > 0 do max_w_em = w / size
    d.measured_w_em = max_w_em
    d.measured_w_valid = true

    lines := _ensure_lines(d, max_w_em)
    widest: f32 = 0
    for l in lines do widest = max(widest, l.width)

    out_w = widest * size
    out_h = f32(len(lines)) * _line_height_em(st) * size
    if w_mode == .AtMost && _align(st) > 0 && !math.is_nan(w) && !math.is_inf(w) do out_w = max(out_w, w)

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
    text_start := common.profile_begin(.Text_Draw)
    defer common.profile_end(.Text_Draw, text_start)
    st := _resolve(self)
    es_start := common.profile_begin(.Ensure_Shaped)
    _ensure_shaped(self, st)
    common.profile_end(.Ensure_Shaped, es_start)
    d := _data(self)
    if st.font == nil || st.font_size <= 0 || len(d.shaped.words) == 0 do return

    p := painter.get()
    size := st.font_size
    r := self.rect

    max_w_em := _resolve_layout_width_em(d.measured_w_em, d.measured_w_valid, r.w, size)
    if !_wraps(st) do max_w_em = math.F32_MAX
    el_start := common.profile_begin(.Ensure_Lines)
    lines := _ensure_lines(d, max_w_em)
    common.profile_end(.Ensure_Lines, el_start)

    scale := painter.pixel_scale(p)
    lh := _line_height_em(st)
    geometry_matches := d.quads_valid &&
    d.quad_rect.w == r.w &&
    d.quad_font == st.font &&
    d.quad_font_size == size &&
    d.quad_weight == st.font_weight &&
    d.quad_line_h == lh &&
    d.quad_scale_y == scale.y &&
    d.quad_align == _align(st)

    when common.FRAME_PROFILE {
        if !d.quads_valid                   do common.profile_count(.Miss_Valid)
        else if d.quad_rect.w != r.w        do common.profile_count(.Miss_Rect_W)
        else if d.quad_font != st.font      do common.profile_count(.Miss_Font)
        else if d.quad_font_size != size    do common.profile_count(.Miss_Size)
        else if d.quad_weight != st.font_weight do common.profile_count(.Miss_Weight)
        else if d.quad_line_h != lh         do common.profile_count(.Miss_Line_H)
        else if d.quad_scale_y != scale.y   do common.profile_count(.Miss_Scale)
        else                                do common.profile_count(.Cache_Hit)
    }

    // Selection is drawn behind glyphs and does not affect their cache.
    im := input.get_context()
    if im != nil && im.selection.valid {
        _draw_selection(self, d, p, st, r, im)
    }

    _draw_decoration(d, p, st, r, lines, lh)

    // Skip rebuilding if the geometry is the same.
    if geometry_matches {
        moved := d.quad_rect.x != r.x || d.quad_rect.y != r.y
        if moved {
            painter.push_transform(p, common.Transform{
                translate = {r.x - d.quad_rect.x, r.y - d.quad_rect.y},
                scale     = {1, 1},
            }, {0, 0})
        }
        _draw_cached(d, p, st)
        if moved do painter.pop_transform(p)
        return
    }

    total_glyphs := 0
    for word in d.shaped.words {
        total_glyphs += len(word.glyphs)
    }
    delete(d.quads)
    quads := make([dynamic]painter.Glyph_Quad, 0, total_glyphs, context.allocator)
    delete(d.robin_quads)
    robin_quads: [dynamic]painter.Glyph_Quad
    when text.ROBIN_TEXT_ACTIVE {
        robin_quads = make([dynamic]painter.Glyph_Quad, 0, total_glyphs, context.allocator)
    }
    delete(d.msdf_quads)
    msdf_quads := make([dynamic]painter.MSDF_Quad, 0, total_glyphs, context.allocator)
    delete(d.color_quads)
    color_quads := make([dynamic]_Color_Quad, 0, 0, context.allocator)

    // Half-leading: extra leading splits evenly above and below the text.
    ascent := text.ascent(st.font, st.font_weight)
    descent := text.descent(st.font, st.font_weight)
    half_leading := (lh - (ascent - descent)) * 0.5
    // 1 layout px of dilation so shader anti-aliasing isn't clipped at quad edges.
    pad := 1.0 / size

    y := r.y
    for l in lines {
        baseline := y + (half_leading + ascent) * size
        if scale.y > 0 do baseline = math.round(baseline * scale.y) / scale.y

        order := make([]int, l.end - l.start, context.temp_allocator)
        text.line_visual_order(&d.shaped, l, order)

        pen := r.x + text.line_offset(l, _metrics(st, r)) * size
        for wi in order {
            word := d.shaped.words[wi]
            if wi != l.start && word.space_before do pen += d.shaped.space_advance * size
            for g in word.glyphs {
                gx := pen + g.offset.x * size
                gy := baseline - g.offset.y * size
                // Prefer v1; fall back to v0.
                if bm, ok := text.color_bitmap_cached(g.face, g.gid, size * max(scale.y, 1));
                   ok {
                    append(&color_quads, _Color_Quad{
                        rect = {
                            gx + bm.plane[0] * size,
                            gy - bm.plane[3] * size,
                            (bm.plane[2] - bm.plane[0]) * size,
                            (bm.plane[3] - bm.plane[1]) * size,
                        },
                        face = g.face,
                        gid  = g.gid,
                        size = size * max(scale.y, 1),
                    })
                    pen += g.advance * size
                    continue
                }
                // Resolve layers before testing the empty base outline.
                if layers := text.color_layers(g.face, g.gid); len(layers) > 0 {
                    for layer in layers {
                        lg := text.glyph(g.face, layer.gid, 0)
                        if lg.curve_count == 0 do continue
                        mg, ok := text.msdf_glyph(g.face, layer.gid, 0)
                        if !ok do continue
                        append(&msdf_quads, painter.MSDF_Quad{
                            rect = {
                                gx + mg.plane[0] * size,
                                gy - mg.plane[3] * size,
                                (mg.plane[2] - mg.plane[0]) * size,
                                (mg.plane[3] - mg.plane[1]) * size,
                            },
                            atlas    = mg.atlas,
                            tint     = {layer.color[0], layer.color[1], layer.color[2], layer.color[3]},
                            has_tint = true,
                        })
                    }
                    pen += g.advance * size
                    continue
                }
                gl := text.glyph(g.face, g.gid, g.embold)
                if gl.curve_count > 0 {
                    // An atlas-backed face uses MSDF only when its bundle
                    // contains this exact glyph/style. It otherwise follows
                    // the normal ROBIN path without generating a new MSDF.
                    used_msdf := false
                    if g.face.prefer_msdf {
                        if mg, ok := text.msdf_glyph_cached(g.face, g.gid, g.embold); ok {
                            append(&msdf_quads, painter.MSDF_Quad{
                                rect = {
                                    gx + mg.plane[0] * size,
                                    gy - mg.plane[3] * size,
                                    (mg.plane[2] - mg.plane[0]) * size,
                                    (mg.plane[3] - mg.plane[1]) * size,
                                },
                                atlas = mg.atlas,
                            })
                            used_msdf = true
                        }
                    }
                    if used_msdf {
                        pen += g.advance * size
                        continue
                    }
                    used_robin := false
                    when text.ROBIN_TEXT_ACTIVE {
                        if rg, ok := text.robin_glyph(g.face, g.gid, g.embold); ok {
                            append(&robin_quads, painter.Glyph_Quad{
                                rect = {
                                    gx + rg.plane[0] * size,
                                    gy - rg.plane[3] * size,
                                    (rg.plane[2] - rg.plane[0]) * size,
                                    (rg.plane[3] - rg.plane[1]) * size,
                                },
                                uv0         = {0, text.ROBIN_GRID},
                                uv1         = {text.ROBIN_GRID, 0},
                                curve_base  = rg.cell_base,
                                curve_count = 0,
                            })
                            used_robin = true
                        }
                    }
                    if !used_robin {
                        if mg, ok := text.msdf_glyph(g.face, g.gid, g.embold); ok {
                            append(&msdf_quads, painter.MSDF_Quad{
                                rect = {
                                    gx + mg.plane[0] * size,
                                    gy - mg.plane[3] * size,
                                    (mg.plane[2] - mg.plane[0]) * size,
                                    (mg.plane[3] - mg.plane[1]) * size,
                                },
                                atlas = mg.atlas,
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
                }
                pen += g.advance * size
            }
        }
        y += lh * size
    }

    d.quads = quads[:]
    d.robin_quads = robin_quads[:]
    d.msdf_quads = msdf_quads[:]
    d.color_quads = color_quads[:]
    d.quad_rect = r
    d.quad_font = st.font
    d.quad_font_size = size
    d.quad_weight = st.font_weight
    d.quad_line_h = lh
    d.quad_scale_y = scale.y
    d.quad_align = _align(st)
    d.quads_valid = true
    d.quad_version += 1

    _draw_cached(d, p, st)
}
