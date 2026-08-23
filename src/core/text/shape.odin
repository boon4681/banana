package text

import "base:runtime"
import "core:c"
import "core:strings"
import stbtt "vendor:stb/truetype"
import SB "src:sheenbidi"
import HB "src:harfbuzz"
import TB "src:textbreak"

Shaped_Glyph :: struct {
    face:    ^Face,
    gid:     u32,
    offset:  [2]f32,
    advance: f32,
    embold:  f32,
    // Source byte range; caret positions land on cluster boundaries.
    cluster:     int,
    cluster_end: int,
    level:       SB.Level,
}

Word :: struct {
    glyphs:                 []Shaped_Glyph,
    width:                  f32,
    level:                  SB.Level,
    space_before:           bool,
    break_before:           bool,
    preferred_break_before: bool,
    hard_break_before:      bool,
    start, end:             int,
    space_start:            int,
}

Shaped_Text :: struct {
    words:         []Word,
    space_advance: f32,
    text_len:      int,
    allocator:     runtime.Allocator,
}

@(private = "file", thread_local) _buf: HB.Buffer

@(private = "file")
SCRIPT_COMMON :: HB.Script(0x5A797979)

@(private = "file")
SCRIPT_INHERITED :: HB.Script(0x5A696E68)

@(private = "file")
SCRIPT_UNKNOWN :: HB.Script(0x5A7A7A7A)

shape :: proc(set: ^Font_Set, s: string, weight := WEIGHT_NORMAL, allocator := context.allocator, language := "") -> Shaped_Text {
    st: Shaped_Text
    if set == nil do return st
    // Borrow the platform UI face when no primary font is loaded.
    if len(set.faces) == 0 && _ensure_primary(set) == nil do return st
    primary, _ := _resolve_weight(set, set.faces[0], weight)
    st.space_advance = primary.space_advance

    words := make([dynamic]Word, allocator)
    first_par := true
    rest := s
    base := 0
    for {
        nl := strings.index_byte(rest, '\n')
        par := rest if nl < 0 else rest[:nl]
        _shape_paragraph(set, par, &words, !first_par, weight, base, language, allocator)
        first_par = false
        if nl < 0 do break
        base += nl + 1
        rest = rest[nl + 1:]
    }
    st.words = words[:]
    st.text_len = len(s)
    st.allocator = allocator
    return st
}

shaped_destroy :: proc(st: ^Shaped_Text) {
    a := st.allocator if st.allocator.procedure != nil else context.allocator
    for w in st.words do delete(w.glyphs, a)
    delete(st.words, a)
    st^ = {}
}

@(private = "file")
_is_space :: proc(r: rune) -> bool {
    return r == ' ' || r == '\t' || r == '\r'
}

// Resolve coverage per run for language-aware fallback, then select weight.
@(private = "file")
_face_for_run :: proc(set: ^Font_Set, runes: []rune, script: HB.Script, weight: FontWeight) -> (^Face, f32) {
    for f in set.faces {
        if _covers(f, runes) do return _resolve_weight(set, f, weight)
    }
    for r in runes {
        if _is_ignorable(r) do continue
        if f := _fallback_lookup(set, r, u32(script)); f != nil {
            return _resolve_weight(set, f, weight)
        }
        break
    }
    return _resolve_weight(set, set.faces[0], weight)
}

@(private = "file")
_covers :: proc(f: ^Face, runes: []rune) -> bool {
    for r in runes {
        if _is_ignorable(r) do continue
        if stbtt.FindGlyphIndex(&f.info, r) == 0 do return false
    }
    return true
}

// Ignore runes the shaper drops or synthesizes.
@(private = "file")
_is_ignorable :: proc(r: rune) -> bool {
    switch r {
    case 0x00AD, 0x200B ..= 0x200F, 0x2028 ..= 0x202E, 0x2060 ..= 0x2064, 0xFEFF:
        return true
    }
    return false
}

// 0 acts as a wildcard that merges with any concrete script.
@(private = "file")
_script_for :: proc(r: rune) -> HB.Script {
    sc := HB.unicode_script(HB.unicode_funcs_get_default(), HB.Codepoint(r))
    if sc == SCRIPT_COMMON || sc == SCRIPT_INHERITED || sc == SCRIPT_UNKNOWN do return HB.Script(0)
    return sc
}

@(private = "file")
_shape_paragraph :: proc(set: ^Font_Set, par: string, words: ^[dynamic]Word, hard_break: bool, weight: FontWeight, base: int, language: string, allocator: runtime.Allocator) {
    runes := make([dynamic]rune, context.temp_allocator)
    offs := make([dynamic]int, context.temp_allocator)
    for r, off in par {
        append(&runes, r)
        append(&offs, off)
    }
    append(&offs, len(par))
    n := len(runes)

    levels := make([]SB.Level, max(n, 1), context.temp_allocator)
    if n > 0 {
        _, ok := SB.embedding_levels(runes[:], levels)
        if !ok {
            for &l in levels {
                l = 0
            }
        }
    }

    boundaries := make([]TB.Break_Info, n + 1, context.temp_allocator)
    phrase_model := false
    if n > 0 {
        lang := _break_language(runes[:], language)
        phrase_model, _ = TB.analyze(runes[:], lang, boundaries)
    }

    first_word := true
    pending_space := false
    space_start := 0
    i := 0
    for i < n {
        if _is_space(runes[i]) {
            if !pending_space do space_start = offs[i]
            pending_space = true
            i += 1
            continue
        }
        start := i
        i += 1
        for i < n && !_is_space(runes[i]) && !boundaries[i].line do i += 1
        brk := pending_space || boundaries[start].line
        preferred := pending_space || (boundaries[start].phrase if phrase_model else boundaries[start].word)

        word := Word {
            level                  = levels[start],
            space_before           = pending_space,
            break_before           = brk,
            preferred_break_before = preferred,
            hard_break_before      = first_word && hard_break,
            start                  = base + offs[start],
            end                    = base + offs[i],
            space_start            = base + (space_start if pending_space else offs[start]),
        }
        _shape_word(set, par, runes[:], offs[:], levels, start, i, &word, weight, base, allocator)
        append(words, word)

        first_word = false
        pending_space = false
    }
    if first_word && hard_break {
        off := base + (space_start if pending_space else 0)
        append(words, Word{
            hard_break_before = true,
            start             = off,
            end               = off,
            space_start       = base if pending_space else off,
        })
    }
}

@(private = "file")
_Run :: struct {
    start, end: int,
    level:      SB.Level,
    script:     HB.Script,
    face:       ^Face,
    embold:     f32,
}

@(private = "file")
_shape_word :: proc(set: ^Font_Set, par: string, runes: []rune, offs: []int, levels: []SB.Level, start, end: int, word: ^Word, weight: FontWeight, base: int, allocator: runtime.Allocator) {
    runs := make([dynamic]_Run, context.temp_allocator)
    for k in start ..< end {
        lv := levels[k]
        sc := _script_for(runes[k])
        if len(runs) > 0 {
            last := &runs[len(runs) - 1]
            if last.level == lv &&
			   (sc == HB.Script(0) || last.script == HB.Script(0) || sc == last.script) {
                if last.script == HB.Script(0) {
                    last.script = sc
                }
                last.end = k + 1
                continue
            }
        }
        append(&runs, _Run{k, k + 1, lv, sc, nil, 0})
    }

    split := make([dynamic]_Run, context.temp_allocator)
    for run in runs {
        k := run.start
        for k < run.end {
            fc, eb := _face_for_run(set, runes[k:run.end], run.script, weight)
            j := k + 1
            for j < run.end && _covers(fc, runes[j:j + 1]) do j += 1
            if len(split) > 0 {
                last := &split[len(split) - 1]
                if last.level == run.level && last.script == run.script && last.face == fc {
                    last.end = j
                    k = j
                    continue
                }
            }
            append(&split, _Run{k, j, run.level, run.script, fc, eb})
            k = j
        }
    }
    runs = split

    run_levels := make([]SB.Level, len(runs), context.temp_allocator)
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
        HB.buffer_set_direction(_buf, .RTL if SB.level_is_rtl(run.level) else .LTR)
        if run.script != HB.Script(0) {
            HB.buffer_set_script(_buf, run.script)
            if tag := script_language(u32(run.script)); tag != "" {
                HB.buffer_set_language(_buf, HB.language_from_string(raw_data(tag), c.int(len(tag))))
            }
        }
        HB.buffer_guess_segment_properties(_buf)
        HB.shape(run.face.hb, _buf, nil, 0)

        count: c.uint
        infos := HB.buffer_get_glyph_infos(_buf, &count)
        pos := HB.buffer_get_glyph_positions(_buf, &count)
        inv := run.face.inv_upem
        seg_base := base + offs[run.start]
        rtl := SB.level_is_rtl(run.level)
        first := len(glyphs)
        for gi in 0 ..< int(count) {
            adv := f32(pos[gi].x_advance) * inv
            if adv > 0 do adv += run.embold * 2
            append(&glyphs, Shaped_Glyph{
                face        = run.face,
                gid         = infos[gi].codepoint,
                offset      = {f32(pos[gi].x_offset) * inv, f32(pos[gi].y_offset) * inv},
                advance     = adv,
                embold      = run.embold,
                cluster     = seg_base + int(infos[gi].cluster),
                cluster_end = seg_base + int(infos[gi].cluster),
                level       = run.level,
            })
            width += adv
        }
        // HarfBuzz reports cluster starts only; derive logical ends below.
        seg_end := base + offs[run.end]
        if rtl {
            run_end := seg_end
            gi := first
            for gi < len(glyphs) {
                cl := glyphs[gi].cluster
                j := gi
                for j < len(glyphs) && glyphs[j].cluster == cl do j += 1
                for k in gi ..< j do glyphs[k].cluster_end = run_end
                run_end = cl
                gi = j
            }
        } else {
            gi := first
            for gi < len(glyphs) {
                cl := glyphs[gi].cluster
                j := gi
                for j < len(glyphs) && glyphs[j].cluster == cl do j += 1
                end_off := seg_end if j >= len(glyphs) else glyphs[j].cluster
                for k in gi ..< j do glyphs[k].cluster_end = end_off
                gi = j
            }
        }
    }
    word.glyphs = glyphs[:]
    word.width = width
}
