package text_edit

import "core:math"
import "core:strings"
import "core:unicode/utf8"
import "src:core/text"

Editor :: struct {
    str:       string, // owned clone
    multiline: bool,

    shaped:        text.Shaped_Text,
    shaped_font:   ^text.Font_Set,
    shaped_weight: text.FontWeight,

    lines:        []text.Line,
    lines_max_w:  f32, // em
    lines_valid:  bool,

    caret:      int, // byte offset
    sel_anchor: int, // byte offset
    has_sel:    bool,
}

Metrics :: struct {
    font:           ^text.Font_Set,
    weight:         text.FontWeight,
    size:           f32, // px
    line_height_em: f32,
    max_w_em:       f32, // wrap width; ignored when !multiline
}

init :: proc(e: ^Editor, multiline: bool) {
    e.multiline = multiline
}

destroy :: proc(e: ^Editor) {
    delete(e.str)
    text.shaped_destroy(&e.shaped)
    delete(e.lines)
    e^ = {}
}

set_text :: proc(e: ^Editor, s: string) {
    if e.str == s do return
    delete(e.str)
    e.str = strings.clone(s)
    e.caret = len(e.str)
    e.sel_anchor = e.caret
    e.has_sel = false
    _invalidate(e)
}

has_selection :: proc(e: ^Editor) -> bool {
    return e.has_sel && e.sel_anchor != e.caret
}

selection_range :: proc(e: ^Editor) -> (lo, hi: int, ok: bool) {
    if !has_selection(e) do return 0, 0, false
    if e.sel_anchor < e.caret do return e.sel_anchor, e.caret, true
    return e.caret, e.sel_anchor, true
}

selected_text :: proc(e: ^Editor) -> string {
    lo, hi, ok := selection_range(e)
    if !ok do return ""
    return e.str[lo:hi]
}

select_all :: proc(e: ^Editor) {
    e.sel_anchor = 0
    e.caret = len(e.str)
    e.has_sel = true
}

@(private = "file")
_caret_range :: proc(e: ^Editor) -> (lo, hi: int) {
    if lo, hi, ok := selection_range(e); ok do return lo, hi
    return e.caret, e.caret
}

@(private = "file")
_set_caret :: proc(e: ^Editor, offset: int, extend: bool) {
    o := clamp(offset, 0, len(e.str))
    if extend {
        if !e.has_sel {
            e.sel_anchor = e.caret
            e.has_sel = true
        }
        e.caret = o
    } else {
        e.caret = o
        e.sel_anchor = o
        e.has_sel = false
    }
}

@(private = "file")
_invalidate :: proc(e: ^Editor) {
    text.shaped_destroy(&e.shaped)
    e.shaped_font = nil
    delete(e.lines)
    e.lines = nil
    e.lines_valid = false
}

@(private = "file")
_replace_range :: proc(e: ^Editor, lo, hi: int, insert: string) -> bool {
    if lo == hi && insert == "" do return false
    new_str := strings.concatenate({e.str[:lo], insert, e.str[hi:]})
    delete(e.str)
    e.str = new_str
    e.caret = lo + len(insert)
    e.sel_anchor = e.caret
    e.has_sel = false
    _invalidate(e)
    return true
}

@(private = "file")
_sanitize :: proc(e: ^Editor, s: string) -> (out: string, owned: bool) {
    if e.multiline || (strings.index_byte(s, '\n') < 0 && strings.index_byte(s, '\r') < 0) {
        return s, false
    }
    b := strings.builder_make(context.temp_allocator)
    for r in s {
        if r == '\n' || r == '\r' do continue
        strings.write_rune(&b, r)
    }
    return strings.to_string(b), false
}

insert_text :: proc(e: ^Editor, s: string) -> bool {
    if s == "" do return false
    ins, _ := _sanitize(e, s)
    if ins == "" do return false
    lo, hi := _caret_range(e)
    return _replace_range(e, lo, hi, ins)
}

delete_backward :: proc(e: ^Editor) -> bool {
    lo, hi := _caret_range(e)
    if lo != hi do return _replace_range(e, lo, hi, "")
    if lo == 0 do return false
    _, size := utf8.decode_last_rune_in_string(e.str[:lo])
    return _replace_range(e, lo - size, lo, "")
}

delete_forward :: proc(e: ^Editor) -> bool {
    lo, hi := _caret_range(e)
    if lo != hi do return _replace_range(e, lo, hi, "")
    if hi >= len(e.str) do return false
    _, size := utf8.decode_rune_in_string(e.str[hi:])
    return _replace_range(e, hi, hi + size, "")
}

ensure_shaped :: proc(e: ^Editor, font: ^text.Font_Set, weight: text.FontWeight) {
    if font == nil do return
    if e.shaped_font == font && e.shaped_weight == weight do return
    text.shaped_destroy(&e.shaped)
    e.shaped = text.shape(font, e.str, weight)
    e.shaped_font = font
    e.shaped_weight = weight
    delete(e.lines)
    e.lines = nil
    e.lines_valid = false
}

ensure_lines :: proc(e: ^Editor, max_w_em: f32) -> []text.Line {
    w := max_w_em if e.multiline else math.F32_MAX
    if e.lines_valid && e.lines_max_w == w do return e.lines
    delete(e.lines)
    e.lines = text.break_lines(&e.shaped, w, context.allocator)
    e.lines_max_w = w
    e.lines_valid = true
    return e.lines
}

@(private = "file")
_prepare :: proc(e: ^Editor, m: Metrics) -> []text.Line {
    ensure_shaped(e, m.font, m.weight)
    return ensure_lines(e, m.max_w_em)
}

line_count :: proc(e: ^Editor, m: Metrics) -> int {
    lines := _prepare(e, m)
    return max(len(lines), 1)
}

@(private = "file")
_line_index_for_offset :: proc(e: ^Editor, lines: []text.Line) -> int {
    if len(lines) == 0 do return 0
    return text.line_index_for_offset(&e.shaped, lines, text.Position{e.caret, false})
}

@(private = "file")
_offset_x_in_word :: proc(w: text.Word, offset: int) -> f32 {
    if len(w.glyphs) == 0 || offset <= w.start do return 0
    pen: f32 = 0
    i := 0
    for i < len(w.glyphs) {
        g := w.glyphs[i]
        cl := g.cluster
        adv := g.advance
        j := i + 1
        for j < len(w.glyphs) && w.glyphs[j].cluster == cl {
            adv += w.glyphs[j].advance
            j += 1
        }
        lo := min(g.cluster, g.cluster_end)
        hi := max(g.cluster, g.cluster_end)
        if offset <= lo do return pen
        if offset < hi do return pen
        pen += adv
        i = j
    }
    return pen
}

@(private = "file")
_offset_x_in_line :: proc(st: ^text.Shaped_Text, l: text.Line, offset: int) -> f32 {
    runs := text.line_runs(st, l)
    if len(runs) == 0 do return 0
    first := st.words[runs[0].word]
    if offset <= first.start do return runs[0].x0
    for r in runs {
        w := st.words[r.word]
        if offset <= w.end do return r.x0 + _offset_x_in_word(w, offset)
    }
    last := runs[len(runs) - 1]
    return last.x1
}

// pixel position of the caret, top-left of its glyph cell.
caret_xy_px :: proc(e: ^Editor, m: Metrics) -> (x, y: f32) {
    lines := _prepare(e, m)
    if len(lines) == 0 do return 0, 0
    li := _line_index_for_offset(e, lines)
    x_em := _offset_x_in_line(&e.shaped, lines[li], e.caret)
    return x_em * m.size, f32(li) * m.line_height_em * m.size
}

selection_rects_px :: proc(e: ^Editor, m: Metrics, allocator := context.temp_allocator) -> []text.Highlight_Rect {
    lo, hi, ok := selection_range(e)
    if !ok do return nil
    lines := _prepare(e, m)
    if len(lines) == 0 do return nil
    metrics := text.Layout_Metrics{line_height = m.line_height_em, max_w = m.max_w_em}
    sel := text.Selection{{lo, false}, {hi, true}}
    rects := text.selection_rects(&e.shaped, lines, metrics, sel, allocator)
    for &r in rects {
        r.x *= m.size
        r.y *= m.size
        r.w *= m.size
        r.h *= m.size
    }
    return rects
}

// byte offset under a point local to the text origin (px).
offset_at_point :: proc(e: ^Editor, m: Metrics, x_px, y_px: f32) -> int {
    lines := _prepare(e, m)
    if len(lines) == 0 do return 0
    size := m.size if m.size > 0 else 1
    metrics := text.Layout_Metrics{line_height = m.line_height_em, max_w = m.max_w_em}
    pos := text.position_at_point(&e.shaped, lines, metrics, x_px / size, y_px / size)
    return pos.offset
}

click :: proc(e: ^Editor, m: Metrics, x_px, y_px: f32, extend: bool) {
    _set_caret(e, offset_at_point(e, m, x_px, y_px), extend)
}

content_extent_px :: proc(e: ^Editor, m: Metrics) -> (w, h: f32) {
    lines := _prepare(e, m)
    widest: f32 = 0
    for l in lines do widest = max(widest, l.width)
    return widest * m.size, f32(max(len(lines), 1)) * m.line_height_em * m.size
}

move_left :: proc(e: ^Editor, extend: bool) -> bool {
    before := e.caret
    if !extend && has_selection(e) {
        lo, hi, _ := selection_range(e)
        _ = hi
        _set_caret(e, lo, false)
        return before != e.caret
    }
    target := e.caret
    if target > 0 {
        _, size := utf8.decode_last_rune_in_string(e.str[:target])
        target -= size
    }
    _set_caret(e, target, extend)
    return before != e.caret || (extend && has_selection(e))
}

move_right :: proc(e: ^Editor, extend: bool) -> bool {
    before := e.caret
    if !extend && has_selection(e) {
        _, hi, _ := selection_range(e)
        _set_caret(e, hi, false)
        return before != e.caret
    }
    target := e.caret
    if target < len(e.str) {
        _, size := utf8.decode_rune_in_string(e.str[target:])
        target += size
    }
    _set_caret(e, target, extend)
    return before != e.caret || (extend && has_selection(e))
}

@(private = "file")
_is_space :: proc(r: rune) -> bool {
    return r == ' ' || r == '\t' || r == '\n' || r == '\r'
}

move_word_left :: proc(e: ^Editor, extend: bool) -> bool {
    before := e.caret
    i := e.caret
    for i > 0 {
        r, size := utf8.decode_last_rune_in_string(e.str[:i])
        if !_is_space(r) do break
        i -= size
    }
    for i > 0 {
        r, size := utf8.decode_last_rune_in_string(e.str[:i])
        if _is_space(r) do break
        i -= size
    }
    _set_caret(e, i, extend)
    return before != e.caret
}

move_word_right :: proc(e: ^Editor, extend: bool) -> bool {
    before := e.caret
    i := e.caret
    n := len(e.str)
    for i < n {
        r, size := utf8.decode_rune_in_string(e.str[i:])
        if !_is_space(r) do break
        i += size
    }
    for i < n {
        r, size := utf8.decode_rune_in_string(e.str[i:])
        if _is_space(r) do break
        i += size
    }
    _set_caret(e, i, extend)
    return before != e.caret
}

move_home :: proc(e: ^Editor, extend: bool) -> bool {
    before := e.caret
    i := e.caret
    for i > 0 {
        r, size := utf8.decode_last_rune_in_string(e.str[:i])
        if r == '\n' do break
        i -= size
    }
    _set_caret(e, i, extend)
    return before != e.caret
}

move_end :: proc(e: ^Editor, extend: bool) -> bool {
    before := e.caret
    i := e.caret
    n := len(e.str)
    for i < n {
        r, size := utf8.decode_rune_in_string(e.str[i:])
        if r == '\n' do break
        i += size
    }
    _set_caret(e, i, extend)
    return before != e.caret
}

move_up :: proc(e: ^Editor, extend: bool, m: Metrics) -> bool {
    before := e.caret
    lines := _prepare(e, m)
    if len(lines) == 0 do return false
    li := _line_index_for_offset(e, lines)
    if li <= 0 {
        _set_caret(e, 0, extend)
        return before != e.caret
    }
    x := _offset_x_in_line(&e.shaped, lines[li], e.caret)
    pos := text.position_in_line(&e.shaped, lines[li - 1], x)
    _set_caret(e, pos.offset, extend)
    return before != e.caret
}

move_down :: proc(e: ^Editor, extend: bool, m: Metrics) -> bool {
    before := e.caret
    lines := _prepare(e, m)
    if len(lines) == 0 do return false
    li := _line_index_for_offset(e, lines)
    if li >= len(lines) - 1 {
        _set_caret(e, len(e.str), extend)
        return before != e.caret
    }
    x := _offset_x_in_line(&e.shaped, lines[li], e.caret)
    pos := text.position_in_line(&e.shaped, lines[li + 1], x)
    _set_caret(e, pos.offset, extend)
    return before != e.caret
}
