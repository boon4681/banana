package text

import "core:slice"
import FB "src:fribidi"

Line :: struct {
	start, end: int, // word range [start, end)
	width:      f32, // em, excluding hanging trailing spaces
}

// Greedy line breaking. `max_w` is in em; pass math.F32_MAX for no wrap.
break_lines :: proc(st: ^Shaped_Text, max_w: f32, allocator := context.temp_allocator) -> []Line {
	lines := make([dynamic]Line, allocator)
	words := st.words
	n := len(words)
	if n == 0 do return lines[:]

	start := 0
	w: f32 = 0
	for idx in 0 ..< n {
		word := words[idx]
		if idx > 0 && word.hard_break_before {
			append(&lines, Line{start, idx, w})
			start = idx
			w = 0
		} else if idx > start && word.break_before {
			sp: f32 = st.space_advance if word.space_before else 0
			if w + sp + word.width > max_w {
				// Trailing spaces hang: `w` never includes the space preceding the word that moved to the next line.
				append(&lines, Line{start, idx, w})
				start = idx
				w = 0
			}
		}
		// Leading spaces are stripped: the line-first word's space hangs.
		if idx > start && word.space_before do w += st.space_advance
		w += word.width
	}
	append(&lines, Line{start, n, w})
	return lines[:]
}

// UAX #9 rule L2 over word levels.
// https://www.unicode.org/reports/tr9/tr9-9.html
line_visual_order :: proc(st: ^Shaped_Text, l: Line, order: []int) {
	n := l.end - l.start
	levels := make([]FB.Level, n, context.temp_allocator)
	for i in 0 ..< n do levels[i] = st.words[l.start + i].level
	_bidi_reorder(levels, order)
	for &o in order do o += l.start
}

// UAX #9 rule L2: for each level from the highest down to the lowest odd level, reverse every maximal subsequence at or above that level.
// https://www.unicode.org/reports/tr9/tr9-9.html
@(private = "package")
_bidi_reorder :: proc(levels: []FB.Level, order: []int) {
	n := len(levels)
	for i in 0 ..< n do order[i] = i
	max_l: FB.Level = 0
	min_odd: FB.Level = 127
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
