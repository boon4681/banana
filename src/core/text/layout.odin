package text

import "core:slice"
import SB "src:sheenbidi"

Line :: struct {
    start, end: int, // word range [start, end)
    width:      f32, // em, excluding hanging trailing spaces
}

break_lines :: proc(st: ^Shaped_Text, max_w: f32, allocator := context.temp_allocator) -> []Line {
    lines := make([dynamic]Line, allocator)
    words := st.words
    n := len(words)
    if n == 0 do return lines[:]

    // Width of words [from, to), with the leading word's space hanging.
    measure :: proc(st: ^Shaped_Text, from, to: int) -> (w: f32) {
        for k in from ..< to {
            if k > from && st.words[k].space_before do w += st.space_advance
            w += st.words[k].width
        }
        return
    }

    start := 0

    for idx in 0 ..< n {
        word := words[idx]
        if idx > 0 && word.hard_break_before {
            append(&lines, Line{start, idx, measure(st, start, idx)})
            start = idx
            continue
        }
        if idx <= start do continue

        // Prefer locale-aware word/phrase boundaries, but fall back to the
        // latest legal UAX #14 boundary when a phrase itself is too wide.
        for measure(st, start, idx + 1) > max_w {
            legal, preferred := -1, -1
            for k in start + 1 ..= idx {
                if words[k].break_before do legal = k
                if words[k].break_before && words[k].preferred_break_before do preferred = k
            }
            at := preferred if preferred > start else legal
            if at <= start do break
            append(&lines, Line{start, at, measure(st, start, at)})
            start = at
        }
    }
    append(&lines, Line{start, n, measure(st, start, n)})
    return lines[:]
}

// UAX #9 rule L2 over word levels.
// https://www.unicode.org/reports/tr9/tr9-9.html
line_visual_order :: proc(st: ^Shaped_Text, l: Line, order: []int) {
    n := l.end - l.start
    levels := make([]SB.Level, n, context.temp_allocator)
    for i in 0 ..< n do levels[i] = st.words[l.start + i].level
    _bidi_reorder(levels, order)
    for &o in order do o += l.start
}

// UAX #9 rule L2: for each level from the highest down to the lowest odd level, reverse every maximal subsequence at or above that level.
// https://www.unicode.org/reports/tr9/tr9-9.html
@(private)
_bidi_reorder :: proc(levels: []SB.Level, order: []int) {
    n := len(levels)
    for i in 0 ..< n do order[i] = i
    max_l: SB.Level = 0
    min_odd: SB.Level = 127
    for l in levels {
        max_l = max(max_l, l)
        if l & 1 != 0 do min_odd = min(min_odd, l)
    }
    for lev := max_l; lev >= min_odd; lev -= 1 {
        i := 0
        for i < n {
            if levels[i] >= lev {
                j := i
                for j < n && levels[j] >= lev do j += 1
                slice.reverse(order[i:j])
                i = j
            } else {
                i += 1
            }
        }
    }
}
