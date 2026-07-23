package text

// Line breaking after UAX #14 (https://www.unicode.org/reports/tr14/).
Break_Class :: enum u8 {
	AL, // ordinary letter
	ID, // ideographic: may break on either side
	CL, // closing punctuation: no break before
	CP, // closing parenthesis: no break before
	OP, // opening punctuation: no break after
	EX, // exclamation/interrogation: no break before
	IS, // infix separator (, .): no break before
	SY, // symbol allowing break after (/)
	NS, // nonstarter (small kana, iteration marks): no break before
	BA, // break after
	BB, // break before
	HY, // hyphen
	NU, // numeric
	PR, // prefix numeric
	PO, // postfix numeric
	QU, // ambiguous quotation
	SP, // space
	ZW, // zero-width space
	CM, // combining mark
	WJ, // word joiner: no break either side
	GL, // non-breaking glue
	IN, // inseparable (ellipsis)
	SA, // complex-context (Thai, Lao, Khmer): needs dictionary segmentation
	B2, // break opportunity before and after (em dash)
}

// Classes whose runs are broken per character rather than per word. Ideographs
// break freely; SA (Thai et al.) needs a dictionary, handled separately.
is_ideographic :: proc(c: Break_Class) -> bool {
    return c == .ID || c == .NS || c == .CL || c == .CP || c == .EX || c == .OP
}

// Scripts that need dictionary segmentation: Thai, Lao, Khmer, Myanmar.
is_complex_context :: proc(r: rune) -> bool {
    switch r {
    case 0x0E00 ..= 0x0E7F, // Thai
	     0x0E80 ..= 0x0EFF, // Lao
	     0x1000 ..= 0x109F, // Myanmar
	     0x1780 ..= 0x17FF: // Khmer
        return true
    }
    return false
}

break_class :: proc(r: rune) -> Break_Class {
    switch r {
    case ' ':
        return .SP
    case 0x200B:
        return .ZW
    case 0x2060, 0xFEFF:
        return .WJ
    case 0x00A0, 0x202F:
        return .GL
    case '-':
        return .HY
    case '/':
        return .SY
    case '0' ..= '9':
        return .NU
    case ',', '.':
        return .IS
    case ';', ':', '?', '!':
        return .EX
    case '(', '[', '{':
        return .OP
    case ')', ']', '}':
        return .CP
    case '"', '\'':
        return .QU
    case '$', '+', '<', '=', '>', '^', '|', '~', '#':
        return .PR
    case '%':
        return .PO
    case 0x2013, 0x2014: // en/em dash
        return .B2
    case 0x2026: // horizontal ellipsis
        return .IN
    }

    if is_complex_context(r) do return .SA

    switch r {
    // Closing punctuation: never starts a line.
    case 0x3001, 0x3002, // ideographic comma, full stop
	     0xFF0C, 0xFF0E, // fullwidth comma, full stop
	     0xFF64, 0xFF61, // halfwidth ideographic comma, full stop
	     0x301C:
        return .CL
    case 0xFF01, 0xFF1F, 0xFF1A, 0xFF1B: // fullwidth ! ? : ;
        return .EX
        // Opening brackets: never ends a line.
    case 0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3014, 0x3016, 0x3018, 0x301A,
	     0xFF08, 0xFF3B, 0xFF5B, 0x201C, 0x2018:
        return .OP
        // Closing brackets.
    case 0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3015, 0x3017, 0x3019, 0x301B,
	     0xFF09, 0xFF3D, 0xFF5D, 0x201D, 0x2019:
        return .CL
        // Nonstarters: small kana, prolonged sound mark, iteration marks.
    case 0x3005, 0x303B, 0x309D, 0x309E, 0x30FD, 0x30FE, 0x30FC,
	     0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, 0x3083, 0x3085, 0x3087, 0x308E,
	     0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30C3, 0x30E3, 0x30E5, 0x30E7, 0x30EE,
	     0xFF67 ..= 0xFF70:
        return .NS
    }

    if _is_ideograph(r) do return .ID

    // Combining marks attach to the preceding character (LB9).
    switch r {
    case 0x0300 ..= 0x036F, 0x1AB0 ..= 0x1AFF, 0x20D0 ..= 0x20FF, 0xFE20 ..= 0xFE2F:
        return .CM
    }
    return .AL
}

@(private = "file")
_is_ideograph :: proc(r: rune) -> bool {
    switch r {
    case 0x2E80 ..= 0x2FFF, // radicals, kangxi
	     0x3040 ..= 0x30FF, // kana
	     0x3400 ..= 0x4DBF, // ext A
	     0x4E00 ..= 0x9FFF, // unified ideographs
	     0xAC00 ..= 0xD7AF, // hangul
	     0xF900 ..= 0xFAFF, // compatibility
	     0xFE30 ..= 0xFE4F, // vertical forms
	     0xFF00 ..= 0xFF60, // fullwidth
	     0x20000 ..= 0x2FFFD:
        return true
    }
    return false
}

// Whether a line may break between `a` and `b`, per the UAX #14 pair table.
// Both are resolved classes; callers handle SP runs and mandatory breaks.
can_break_between :: proc(a, b: Break_Class) -> bool {
    // LB7: never break before a space or zero-width space.
    if b == .SP || b == .ZW do return false
    // LB8: always break after a zero-width space.
    if a == .ZW do return true
    // LB11: word joiner glues both sides.
    if a == .WJ || b == .WJ do return false
    // LB9: a combining mark never starts a line.
    if b == .CM do return false
    // LB12: non-breaking glue.
    if a == .GL || b == .GL do return false

    // LB13: never break before closing punctuation or infix separators.
    if b == .CL || b == .CP || b == .EX || b == .IS || b == .SY do return false
    // LB14: never break after opening punctuation.
    if a == .OP do return false
    // LB15/LB19: quotation marks bind to what follows/precedes.
    if b == .QU do return false
    if a == .QU do return false
    // LB16: closing punctuation followed by a nonstarter stays together.
    if (a == .CL || a == .CP) && b == .NS do return false
    // LB17: em dash pairs stay together.
    if a == .B2 && b == .B2 do return false
    // LB18: break after a space.
    if a == .SP do return true

    // LB21: no break before a nonstarter, or around hyphens.
    if b == .NS do return false
    if a == .BB do return false
    if b == .BA || b == .HY do return false
    // LB22: inseparable.
    if b == .IN do return false

    // LB23-25: keep numeric sequences intact.
    if a == .NU && b == .NU do return false
    if a == .AL && b == .NU do return false
    if a == .NU && b == .AL do return false
    if a == .PR && b == .NU do return false
    if a == .NU && b == .PO do return false
    if a == .HY && b == .NU do return false
    if a == .IS && b == .NU do return false
    if a == .SY && b == .NU do return false

    // LB26: keep Hangul syllable sequences together.
    // LB28: do not break between letters.
    if a == .AL && b == .AL do return false

    // LB29: infix separator followed by a letter.
    if a == .IS && b == .AL do return false

    // LB30: no break between a letter/number and an opening bracket.
    if (a == .AL || a == .NU) && b == .OP do return false
    if a == .CP && (b == .AL || b == .NU) do return false

    // LB31: ideographs break freely against everything else.
    return true
}
