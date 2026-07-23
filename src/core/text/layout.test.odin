#+build !wasm32
package text

import "core:testing"

@(private = "file")
_Spec :: struct {
    w:            f32,
    space_before: bool,
    break_before: bool,
}

// Words of a fixed width, so line capacity is easy to reason about.
@(private = "file")
_mk :: proc(specs: []_Spec) -> Shaped_Text {
    words := make([]Word, len(specs), context.temp_allocator)
    for s, i in specs {
        words[i] = Word {
            width        = s.w,
            space_before = s.space_before,
            break_before = s.break_before,
        }
    }
    return Shaped_Text{words = words, space_advance = 1}
}

// A word that may not start a line must pull back to the previous opportunity
// rather than overflowing onto the next line by itself (UAX #14 LB13).
@(test)
test_retreats_to_last_opportunity :: proc(t: ^testing.T) {
    // "AA" "BB" then an unbreakable-before "." — capacity fits only two units.
    st := _mk({{2, false, false}, {2, true, true}, {1, false, false}})
    lines := break_lines(&st, 5, context.temp_allocator)

    testing.expect_value(t, len(lines), 2)
    // The '.' must stay with "BB" on the second line, not start line 2 alone.
    testing.expect_value(t, lines[0].end, 1)
    testing.expect_value(t, lines[1].start, 1)
}

@(test)
test_hard_break_starts_new_line :: proc(t: ^testing.T) {
    st := _mk({{1, false, false}, {1, false, false}})
    st.words[1].hard_break_before = true
    lines := break_lines(&st, 100, context.temp_allocator)
    testing.expect_value(t, len(lines), 2)
}

@(test)
test_no_wrap_when_it_fits :: proc(t: ^testing.T) {
    st := _mk({{1, false, false}, {1, true, true}, {1, true, true}})
    lines := break_lines(&st, 100, context.temp_allocator)
    testing.expect_value(t, len(lines), 1)
    testing.expect_value(t, lines[0].end, 3)
}

// An unbreakable run wider than the line still emits one line rather than
// looping or dropping words.
@(test)
test_overlong_unbreakable_word :: proc(t: ^testing.T) {
    st := _mk({{50, false, false}})
    lines := break_lines(&st, 5, context.temp_allocator)
    testing.expect_value(t, len(lines), 1)
    testing.expect_value(t, lines[0].end, 1)
}

// Every word must appear on exactly one line, with no gaps or overlaps.
@(test)
test_lines_cover_all_words :: proc(t: ^testing.T) {
    st := _mk({
        {2, false, false},
        {2, true, true},
        {2, true, true},
        {2, true, true},
        {2, true, true},
    })
    lines := break_lines(&st, 5, context.temp_allocator)
    testing.expect(t, len(lines) > 1, "expected wrapping")
    testing.expect_value(t, lines[0].start, 0)
    testing.expect_value(t, lines[len(lines) - 1].end, len(st.words))
    for i in 1 ..< len(lines) {
        testing.expect_value(t, lines[i].start, lines[i - 1].end)
    }
}

@(test)
test_no_line_exceeds_max_width :: proc(t: ^testing.T) {
    // Mimics "word word 你好世界，こんにちは。" — a Latin run, then a CJK run of
    // per-character words, ending in punctuation that cannot start a line.
    specs := make([dynamic]_Spec, context.temp_allocator)
    append(&specs, _Spec{3, false, false}, _Spec{3, true, true}, _Spec{3, true, true})
    for i in 0 ..< 12 do append(&specs, _Spec{1, i == 0, true})
    append(&specs, _Spec{1, false, false}) // trailing '。'

    st := _mk(specs[:])
    for step in 0 ..< 40 {
        max_w := 4 + f32(step) * 0.5
        lines := break_lines(&st, max_w, context.temp_allocator)

        covered := 0
        for l in lines {
            testing.expect_value(t, l.start, covered)
            covered = l.end

            actual: f32 = 0
            for k in l.start ..< l.end {
                if k > l.start && st.words[k].space_before do actual += st.space_advance
                actual += st.words[k].width
            }
            testing.expectf(t, abs(actual - l.width) < 0.001,
				"max_w=%v line %v..%v reported width %v but measured %v",
				max_w, l.start, l.end, l.width, actual)
            if l.end - l.start > 1 {
                testing.expectf(t, actual <= max_w + 0.001,
					"max_w=%v line %v..%v overflows at width %v",
					max_w, l.start, l.end, actual)
            }
        }
        testing.expect_value(t, covered, len(st.words))
    }
}

@(test)
test_retreat_over_run_keeps_every_word :: proc(t: ^testing.T) {
    // Ideograph-like: each breakable before, then a trailing unbreakable '。'.
    st := _mk({
        {1, false, true},
        {1, false, true},
        {1, false, true},
        {1, false, true},
        {1, false, true},
        {1, false, false}, // must not start a line
    })
    lines := break_lines(&st, 3.5, context.temp_allocator)

    testing.expect_value(t, lines[0].start, 0)
    testing.expect_value(t, lines[len(lines) - 1].end, len(st.words))
    for i in 1 ..< len(lines) {
        testing.expect_value(t, lines[i].start, lines[i - 1].end)
    }
    // No line may exceed the limit except one holding a single word.
    for l in lines {
        if l.end - l.start > 1 {
            testing.expect(t, l.width <= 3.5, "line exceeds max width")
        }
    }
}
