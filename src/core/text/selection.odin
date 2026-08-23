package text

import "core:slice"
import SB "src:sheenbidi"

// `after` disambiguates the visual caret edge at bidi boundaries.
Position :: struct {
    offset: int,
    after:  bool,
}

// Anchor stays fixed while focus moves.
Selection :: struct {
    anchor, focus: Position,
}

Granularity :: enum {
    Character,
    Word,
    Line,
}

sel_empty :: proc(s: Selection) -> bool {
    return s.anchor.offset == s.focus.offset
}

sel_range :: proc(s: Selection) -> (start, end: int) {
    if s.anchor.offset <= s.focus.offset do return s.anchor.offset, s.focus.offset
    return s.focus.offset, s.anchor.offset
}

// All measurements are in em.
Layout_Metrics :: struct {
    line_height: f32,
    max_w: f32,
}

@(private = "file")
_line_of :: proc(lines: []Line, i: int) -> int {
    return clamp(i, 0, len(lines) - 1)
}

line_index_for_offset :: proc(st: ^Shaped_Text, lines: []Line, pos: Position) -> int {
    for l, li in lines {
        if l.start == l.end do continue
        w_end := st.words[l.end - 1].end
        if pos.offset < w_end do return li
        if pos.offset == w_end {
            if pos.after || li == len(lines) - 1 do return li
            next := lines[li + 1]
            if next.start == next.end do return li
            if st.words[next.start].space_start > pos.offset do return li
            return li + 1
        }
    }
    return max(len(lines) - 1, 0)
}

Visual_Run :: struct {
    word:  int,
    x0,x1: f32,
}

line_runs :: proc(st: ^Shaped_Text, l: Line, allocator := context.temp_allocator) -> []Visual_Run {
    n := l.end - l.start
    if n <= 0 do return nil
    order := make([]int, n, context.temp_allocator)
    line_visual_order(st, l, order)

    runs := make([dynamic]Visual_Run, 0, n, allocator)
    pen: f32 = 0
    for wi in order {
        word := st.words[wi]
        if wi != l.start && word.space_before do pen += st.space_advance
        append(&runs, Visual_Run{word = wi, x0 = pen, x1 = pen + word.width})
        pen += word.width
    }
    return runs[:]
}

position_in_line :: proc(st: ^Shaped_Text, l: Line, x: f32) -> Position {
    runs := line_runs(st, l)
    if len(runs) == 0 {
        if l.start < len(st.words) do return {st.words[l.start].start, false}
        return {st.text_len, false}
    }

    if x <= runs[0].x0 {
        return _edge_position(st, st.words[runs[0].word], leading = true)
    }
    last := runs[len(runs) - 1]
    if x >= last.x1 {
        return _edge_position(st, st.words[last.word], leading = false)
    }

    for r in runs {
        if x < r.x0 {
            return _edge_position(st, st.words[r.word], leading = true)
        }
        if x <= r.x1 do return _position_in_word(st.words[r.word], x - r.x0)
    }
    return _edge_position(st, st.words[last.word], leading = false)
}

@(private = "file")
_edge_position :: proc(st: ^Shaped_Text, w: Word, leading: bool) -> Position {
    if len(w.glyphs) == 0 do return {w.start, false}
    g := w.glyphs[0] if leading else w.glyphs[len(w.glyphs) - 1]
    rtl := SB.level_is_rtl(g.level)
    if leading do return {_visual_leading(g, rtl), false}
    return {_visual_trailing(g, rtl), true}
}

@(private = "file")
_position_in_word :: proc(w: Word, x: f32) -> Position {
    pen: f32 = 0
    for g, i in w.glyphs {
        if i > 0 && g.cluster == w.glyphs[i - 1].cluster {
            pen += g.advance
            continue
        }
        adv := g.advance
        for j in i + 1 ..< len(w.glyphs) {
            if w.glyphs[j].cluster != g.cluster do break
            adv += w.glyphs[j].advance
        }
        if x < pen + adv {
            grtl := SB.level_is_rtl(g.level)
            if x < pen + adv * 0.5 do return {_visual_leading(g, grtl), false}
            return {_visual_trailing(g, grtl), true}
        }
        pen += adv
    }
    if len(w.glyphs) == 0 do return {w.start, false}
    last := w.glyphs[len(w.glyphs) - 1]
    return {_visual_trailing(last, SB.level_is_rtl(last.level)), true}
}

@(private = "file")
_visual_leading :: proc(g: Shaped_Glyph, rtl: bool) -> int {
    return g.cluster_end if rtl else g.cluster
}

@(private = "file")
_visual_trailing :: proc(g: Shaped_Glyph, rtl: bool) -> int {
    return g.cluster if rtl else g.cluster_end
}

position_at_point :: proc(st: ^Shaped_Text, lines: []Line, m: Layout_Metrics, x, y: f32) -> Position {
    if len(lines) == 0 do return {0, false}
    li := int(y / max(m.line_height, 0.0001))
    li = _line_of(lines, li)
    return position_in_line(st, lines[li], x)
}

Highlight_Rect :: struct {
    x, y, w, h: f32,
}

selection_rects :: proc(
    st: ^Shaped_Text,
    lines: []Line,
    m: Layout_Metrics,
    sel: Selection,
    allocator := context.temp_allocator,
) -> []Highlight_Rect {
    out := make([dynamic]Highlight_Rect, allocator)
    lo, hi := sel_range(sel)
    if lo == hi do return out[:]

    y: f32 = 0
    for l in lines {
        runs := line_runs(st, l)
        spans := make([dynamic][2]f32, context.temp_allocator)
        for r in runs {
            w := st.words[r.word]
            if w.end <= lo || w.start >= hi {
                if w.space_before && w.space_start >= lo && w.start <= hi && w.space_start < hi {
                    append(&spans, [2]f32{r.x0 - st.space_advance, r.x0})
                }
                continue
            }
            if w.space_before && w.space_start >= lo {
                append(&spans, [2]f32{r.x0 - st.space_advance, r.x0})
            }
            a, b := _word_span(w, lo, hi)
            if b > a do append(&spans, [2]f32{r.x0 + a, r.x0 + b})
        }
        if len(spans) > 0 {
            slice.sort_by(spans[:], proc(a, b: [2]f32) -> bool { return a[0] < b[0] })
            cur := spans[0]
            for s in spans[1:] {
                if s[0] <= cur[1] + 0.001 {
                    cur[1] = max(cur[1], s[1])
                    continue
                }
                append(&out, Highlight_Rect{cur[0], y, cur[1] - cur[0], m.line_height})
                cur = s
            }
            append(&out, Highlight_Rect{cur[0], y, cur[1] - cur[0], m.line_height})
        }
        y += m.line_height
    }
    return out[:]
}

@(private = "file")
_word_span :: proc(w: Word, lo, hi: int) -> (a, b: f32) {
    if len(w.glyphs) == 0 do return 0, 0
    a = max(f32)
    b = 0
    pen: f32 = 0
    for g in w.glyphs {
        s := min(g.cluster, g.cluster_end)
        e := max(g.cluster, g.cluster_end)
        if s < hi && e > lo {
            a = min(a, pen)
            b = max(b, pen + g.advance)
        }
        pen += g.advance
    }
    if a > b do return 0, 0
    return a, b
}

expand :: proc(st: ^Shaped_Text, lines: []Line, pos: Position, g: Granularity) -> (start, end: int) {
    switch g {
    case .Character:
        return pos.offset, pos.offset
    case .Word:
        for w in st.words {
            if pos.offset >= w.start && pos.offset <= w.end do return w.start, w.end
        }
        return pos.offset, pos.offset
    case .Line:
        li := line_index_for_offset(st, lines, pos)
        if li < 0 || li >= len(lines) do return pos.offset, pos.offset
        l := lines[li]
        if l.start == l.end do return pos.offset, pos.offset
        return st.words[l.start].start, st.words[l.end - 1].end
    }
    return pos.offset, pos.offset
}

extend :: proc(st: ^Shaped_Text, lines: []Line, sel: Selection, pos: Position, g: Granularity) -> Selection {
    if g == .Character do return {sel.anchor, pos}

    a0, a1 := expand(st, lines, sel.anchor, g)
    f0, f1 := expand(st, lines, pos, g)
    if f0 < a0 do return {{a1, true}, {f0, false}}
    return {{a0, false}, {f1, true}}
}
