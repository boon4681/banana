#+build windows
package text

import "core:fmt"
import "core:testing"

@(test)
test_platform_fallback :: proc(t: ^testing.T) {
    cases := []struct {
        name:   string,
        r:      rune,
        script: u32,
    } {
        {"latin",  'A',      0},
        {"han",    0x4E00,   SCRIPT_HAN},
        {"kana",   0x3042,   SCRIPT_HIRA},
        {"hangul", 0xAC00,   SCRIPT_HANG},
        {"emoji",  0x1F600,  0}, // astral plane: exercises the surrogate pair
        {"arabic", 0x0627,   0},
    }

    for c in cases {
        set := set_create()
        defer set_destroy(set)

        f := _platform_fallback(set, c.r, c.script)
        testing.expectf(t, f != nil, "%s (U+%04X): no fallback face", c.name, c.r)
        if f == nil do continue
        testing.expectf(t, f.hb != nil, "%s: face has no hb font", c.name)
        fmt.printfln("[fallback] %-7s U+%04X -> %q", c.name, c.r, f.family)
    }
}

@(test)
test_shape_uses_platform_fallback :: proc(t: ^testing.T) {
    set := set_create()
    defer set_destroy(set)

    // Segoe UI forces CJK and emoji through platform fallback.
    _native_load_font(set, "C:/Windows/Fonts/segoeui.ttf")
    if !testing.expect(t, len(set.faces) > 0, "no base font loaded") do return
    base := set.faces[0]

    sh := shape(set, "hello 世界 안녕 😀")
    defer shaped_destroy(&sh)

    seen: map[^Face]bool
    defer delete(seen)
    for w in sh.words {
        for g in w.glyphs do seen[g.face] = true
    }

    testing.expect(t, len(seen) > 1, "everything shaped with one face; no fallback happened")
    for f in seen {
        testing.expect(t, f != nil, "glyph with nil face")
        if f != base do fmt.printfln("[shape] fallback face -> %q", f.family)
    }

    // No .notdef anywhere means every script found real coverage.
    for w in sh.words {
        for g in w.glyphs {
            testing.expectf(t, g.gid != 0, "unresolved glyph (.notdef) in shaped output")
        }
    }
}
