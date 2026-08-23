package text

// Select a boundary-analysis locale when the caller did not provide one.
// Han-only text is inherently ambiguous, so it follows set_han_language().
@(private = "package")
_break_language :: proc(runes: []rune, requested: string) -> string {
    if requested != "" do return requested
    has_han := false
    for r in runes {
        switch r {
        case 0x3040 ..= 0x30FF: return "ja"
        case 0x0E00 ..= 0x0E7F: return "th"
        case 0x3100 ..= 0x312F: return "zh-Hant"
        case 0xAC00 ..= 0xD7AF: return "ko"
        case 0x3400 ..= 0x4DBF, 0x4E00 ..= 0x9FFF, 0xF900 ..= 0xFAFF,
             0x20000 ..= 0x2FFFD:
            has_han = true
        }
    }
    return han_language if has_han else ""
}
