package textbreak

import "core:c"
import "core:strings"

when ODIN_ARCH == .wasm32 {
    foreign import textbreak "./libc/wasm/textbreak.o"
} else when ODIN_OS == .Windows {
    foreign import textbreak "./libc/windows/textbreak.lib"
} else when ODIN_OS == .Darwin {
    foreign import textbreak "./libc/macos/libtextbreak.a"
} else {
    foreign import textbreak "./libc/linux/libtextbreak.a"
}

Break_Info :: struct {
    grapheme:  bool, // boundary does not split an extended grapheme cluster
    word:      bool, // UAX #29 word boundary
    line:      bool, // legal UAX #14 line boundary
    mandatory: bool,
    phrase:    bool, // preferred BudouX boundary
}

Budoux_Model :: enum c.int {
	None,
	Japanese,
	Chinese_Simplified,
	Chinese_Traditional,
	Thai,
}

GRAPHEME_BREAK   :: u8(0)
WORD_BREAK       :: u8(0)
LINE_MUST_BREAK  :: u8(0)
LINE_ALLOW_BREAK :: u8(1)

// Populates boundaries-before-codepoint in out[0..len(str)+1].
// The final entry represents the boundary after the last codepoint.
analyze :: proc(str: []rune, language: string, out: []Break_Info) -> (has_phrase_model: bool, ok: bool) {
    n := len(str)
    if len(out) < n + 1 do return false, false
    for &boundary in out[:n + 1] do boundary = {}
    if n == 0 do return false, true

    lang: cstring
    if language != "" do lang = strings.clone_to_cstring(language, context.temp_allocator)
    scratch := make([]u8, n, context.temp_allocator)
    text := cast([^]u32)raw_data(str)

    set_graphemebreaks_utf32(text, c.size_t(n), lang, raw_data(scratch))
    for value, i in scratch do out[i + 1].grapheme = value == GRAPHEME_BREAK

    set_wordbreaks_utf32(text, c.size_t(n), lang, raw_data(scratch))
    for value, i in scratch do out[i + 1].word = value == WORD_BREAK

    set_linebreaks_utf32(text, c.size_t(n), lang, raw_data(scratch))
    for value, i in scratch {
        out[i + 1].mandatory = value == LINE_MUST_BREAK
        out[i + 1].line = value == LINE_MUST_BREAK || value == LINE_ALLOW_BREAK
    }

    model := _model_for_language(language)
    if model != .None {
        phrase := make([]u8, n + 1, context.temp_allocator)
        banana_budoux_breaks_utf32(text, c.size_t(n), model, raw_data(phrase))
        for value, i in phrase {
            // A model is only usable when unicode also permits the break at that position.
            out[i].phrase = value != 0 && out[i].line && out[i].grapheme
        }
        return true, true
    }
    return false, true
}

@(private = "file")
_model_for_language :: proc(language: string) -> Budoux_Model {
    if len(language) < 2 do return .None
    a := language[0] | 0x20
    b := language[1] | 0x20
    if a == 'j' && b == 'a' do return .Japanese
    if a == 't' && b == 'h' do return .Thai
    if a != 'z' || b != 'h' do return .None
    if strings.contains(language, "Hant") || strings.contains(language, "hant") ||
	   strings.contains(language, "-TW") || strings.contains(language, "-tw") ||
	   strings.contains(language, "-HK") || strings.contains(language, "-hk") ||
	   strings.contains(language, "-MO") || strings.contains(language, "-mo") {
        return .Chinese_Traditional
    }
    return .Chinese_Simplified
}

@(default_calling_convention = "c")
foreign textbreak {
    @(link_name = "set_graphemebreaks_utf32")
    set_graphemebreaks_utf32 :: proc(str: [^]u32, len: c.size_t, language: cstring, breaks: [^]u8) ---
    @(link_name = "set_wordbreaks_utf32")
    set_wordbreaks_utf32 :: proc(str: [^]u32, len: c.size_t, language: cstring, breaks: [^]u8) ---
    @(link_name = "set_linebreaks_utf32")
    set_linebreaks_utf32       :: proc(str: [^]u32, len: c.size_t, language: cstring, breaks: [^]u8) ---
    banana_budoux_breaks_utf32 :: proc(str: [^]u32, len: c.size_t, model: Budoux_Model, breaks: [^]u8) ---
}

