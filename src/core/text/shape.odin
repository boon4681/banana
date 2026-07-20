package text

import "base:runtime"
import "core:c"
import "core:strings"
import stbtt "vendor:stb/truetype"
import FB "src:fribidi"
import HB "src:harfbuzz"

Shaped_Glyph :: struct {
	face:    ^Face,
	gid:     u32,
	offset:  [2]f32,
	advance: f32,
}

Word :: struct {
	glyphs:            []Shaped_Glyph,
	width:             f32,
	level:             FB.Level, // bidi embedding level (odd = RTL)
	space_before:      bool,     // a collapsed space precedes this word
	break_before:      bool,     // soft-wrap opportunity before this word
	hard_break_before: bool,     // '\n' precedes this word
}

Shaped_Text :: struct {
	words:         []Word,
	space_advance: f32,
}

@(private = "file") _buf: HB.Buffer

@(private = "file")
SCRIPT_COMMON :: HB.Script(0x5A797979) // 'Zyyy'
@(private = "file")
SCRIPT_INHERITED :: HB.Script(0x5A696E68) // 'Zinh'
@(private = "file")
SCRIPT_UNKNOWN :: HB.Script(0x5A7A7A7A) // 'Zzzz'

shape :: proc(set: ^Font_Set, s: string, allocator := context.allocator) -> Shaped_Text {
	st: Shaped_Text
	if set == nil || len(set.faces) == 0 do return st
	st.space_advance = set.faces[0].space_advance

	words := make([dynamic]Word, allocator)
	first_par := true
	rest := s
	for {
		nl := strings.index_byte(rest, '\n')
		par := rest if nl < 0 else rest[:nl]
		_shape_paragraph(set, par, &words, !first_par, allocator)
		first_par = false
		if nl < 0 do break
		rest = rest[nl + 1:]
	}
	st.words = words[:]
	return st
}

shaped_destroy :: proc(st: ^Shaped_Text) {
	for w in st.words do delete(w.glyphs)
	delete(st.words)
	st^ = {}
}

@(private = "file")
_is_space :: proc(r: rune) -> bool {
	return r == ' ' || r == '\t' || r == '\r'
}

@(private = "file")
_is_cjk :: proc(r: rune) -> bool {
	switch r {
	case 0x2E80 ..= 0x9FFF,   // radicals, kana, CJK symbols, unified ideographs
	     0xAC00 ..= 0xD7AF,   // hangul syllables
	     0xF900 ..= 0xFAFF,   // compatibility ideographs
	     0xFE30 ..= 0xFE4F,   // vertical forms
	     0xFF00 ..= 0xFF60,   // fullwidth forms
	     0x20000 ..= 0x2FFFD: // ideograph extensions
		return true
	}
	return false
}

@(private = "file")
_face_for :: proc(set: ^Font_Set, r: rune) -> ^Face {
	for f in set.faces {
		if stbtt.FindGlyphIndex(&f.info, r) != 0 do return f
	}
	return set.faces[0]
}

// 0 acts as a wildcard that merges with any concrete script.
@(private = "file")
_script_for :: proc(r: rune) -> HB.Script {
	sc := HB.unicode_script(HB.unicode_funcs_get_default(), HB.Codepoint(r))
	if sc == SCRIPT_COMMON || sc == SCRIPT_INHERITED || sc == SCRIPT_UNKNOWN do return HB.Script(0)
	return sc
}

@(private = "file")
_shape_paragraph :: proc(set: ^Font_Set, par: string, words: ^[dynamic]Word, hard_break: bool, allocator: runtime.Allocator) {
	runes := make([dynamic]rune, context.temp_allocator)
	offs := make([dynamic]int, context.temp_allocator)
	for r, off in par {
		append(&runes, r)
		append(&offs, off)
	}
	append(&offs, len(par))
	n := len(runes)

	levels := make([]FB.Level, max(n, 1), context.temp_allocator)
	if n > 0 {
		types := make([]FB.Char_Type, n, context.temp_allocator)
		btypes := make([]FB.Bracket_Type, n, context.temp_allocator)
		str := cast([^]FB.Char)raw_data(runes)
		FB.get_bidi_types(str, FB.Str_Index(n), raw_data(types))
		FB.get_bracket_types(str, FB.Str_Index(n), raw_data(types), raw_data(btypes))
		base := FB.PAR_ON
		if FB.get_par_embedding_levels_ex(raw_data(types), raw_data(btypes), FB.Str_Index(n), &base, raw_data(levels)) == 0 {
			for &l in levels do l = 0
		}
	}

	first_word := true
	pending_space := false
	prev_cjk := false
	i := 0
	for i < n {
		if _is_space(runes[i]) {
			pending_space = true
			i += 1
			continue
		}
		start := i
		cjk := _is_cjk(runes[i])
		if cjk {
			i += 1
		} else {
			for i < n && !_is_space(runes[i]) && !_is_cjk(runes[i]) do i += 1
		}

		word := Word {
			level             = levels[start],
			space_before      = pending_space,
			break_before      = pending_space || cjk || prev_cjk,
			hard_break_before = first_word && hard_break,
		}
		_shape_word(set, par, runes[:], offs[:], levels, start, i, &word, allocator)
		append(words, word)

		first_word = false
		pending_space = false
		prev_cjk = cjk
	}
	// Blank (or all-space) paragraph still occupies a line.
	if first_word && hard_break {
		append(words, Word{hard_break_before = true})
	}
}

@(private = "file")
_Run :: struct {
	start, end: int, // rune range
	level:      FB.Level,
	script:     HB.Script,
	face:       ^Face,
}

@(private = "file")
_shape_word :: proc(set: ^Font_Set, par: string, runes: []rune, offs: []int, levels: []FB.Level, start, end: int, word: ^Word, allocator: runtime.Allocator) {
	// Itemize into runs of uniform (level, script, face).
	runs := make([dynamic]_Run, context.temp_allocator)
	for k in start ..< end {
		r := runes[k]
		lv := levels[k]
		fc := _face_for(set, r)
		sc := _script_for(r)
		if len(runs) > 0 {
			last := &runs[len(runs) - 1]
			if last.level == lv && last.face == fc &&
			   (sc == HB.Script(0) || last.script == HB.Script(0) || sc == last.script) {
				if last.script == HB.Script(0) do last.script = sc
				last.end = k + 1
				continue
			}
		}
		append(&runs, _Run{k, k + 1, lv, sc, fc})
	}

	run_levels := make([]FB.Level, len(runs), context.temp_allocator)
	for run, ri in runs do run_levels[ri] = run.level
	order := make([]int, len(runs), context.temp_allocator)
	_bidi_reorder(run_levels, order)

	if _buf == nil do _buf = HB.buffer_create()

	glyphs := make([dynamic]Shaped_Glyph, allocator)
	width: f32 = 0
	for oi in order {
		run := runs[oi]
		seg := par[offs[run.start]:offs[run.end]]

		HB.buffer_clear_contents(_buf)
		HB.buffer_add_utf8(_buf, raw_data(seg), c.int(len(seg)), 0, c.int(len(seg)))
		HB.buffer_set_direction(_buf, .RTL if FB.level_is_rtl(run.level) else .LTR)
		if run.script != HB.Script(0) do HB.buffer_set_script(_buf, run.script)
		HB.buffer_guess_segment_properties(_buf)
		HB.shape(run.face.hb, _buf, nil, 0)

		count: c.uint
		infos := HB.buffer_get_glyph_infos(_buf, &count)
		pos := HB.buffer_get_glyph_positions(_buf, &count)
		inv := run.face.inv_upem
		for gi in 0 ..< int(count) {
			adv := f32(pos[gi].x_advance) * inv
			append(&glyphs, Shaped_Glyph{
				face    = run.face,
				gid     = infos[gi].codepoint,
				offset  = {f32(pos[gi].x_offset) * inv, f32(pos[gi].y_offset) * inv},
				advance = adv,
			})
			width += adv
		}
	}
	word.glyphs = glyphs[:]
	word.width = width
}
