package sheenbidi

when ODIN_ARCH == .wasm32 {
	foreign import sheenbidi "./libc/wasm/sheenbidi.o"
} else when ODIN_OS == .Windows {
	foreign import sheenbidi "./libc/windows/sheenbidi.lib"
} else when ODIN_OS == .Darwin {
	foreign import sheenbidi "./libc/macos/libsheenbidi.a"
} else {
	foreign import sheenbidi "./libc/linux/libsheenbidi.a"
}

Algorithm :: distinct rawptr
Paragraph :: distinct rawptr

Level :: u8

STRING_ENCODING_UTF32 :: u32(2)
LEVEL_DEFAULT_LTR :: Level(0xFE)

Codepoint_Sequence :: struct {
	string_encoding: u32,
	string_buffer:   rawptr,
	string_length:   uintptr,
}

level_is_rtl :: proc(level: Level) -> bool {
	return level & 1 != 0
}

// Resolves the embedding level of each UTF-32 code point.
// The caller owns the output buffer; SheenBidi objects remain internal to this convenience wrapper.
embedding_levels :: proc(str: []rune, levels: []Level) -> (base: Level, ok: bool) {
	if len(str) == 0 || len(levels) < len(str) do return 0, len(str) == 0

	sequence := Codepoint_Sequence {
		string_encoding = STRING_ENCODING_UTF32,
		string_buffer   = raw_data(str),
		string_length   = uintptr(len(str)),
	}
	algorithm := AlgorithmCreate(&sequence)
	if algorithm == nil do return
	defer AlgorithmRelease(algorithm)

	paragraph := AlgorithmCreateParagraph(algorithm, 0, uintptr(len(str)), LEVEL_DEFAULT_LTR)
	if paragraph == nil do return
	defer ParagraphRelease(paragraph)

	resolved := ParagraphGetLevelsPtr(paragraph)
	if resolved == nil do return
	copy(levels[:len(str)], resolved[:len(str)])
	return ParagraphGetBaseLevel(paragraph), true
}

@(default_calling_convention = "c", link_prefix = "SB")
foreign sheenbidi {
	AlgorithmCreate          :: proc(sequence: ^Codepoint_Sequence) -> Algorithm ---
	AlgorithmCreateParagraph :: proc(algorithm: Algorithm, offset, length: uintptr, base_level: Level) -> Paragraph ---
	AlgorithmRelease         :: proc(algorithm: Algorithm) ---
	ParagraphGetBaseLevel    :: proc(paragraph: Paragraph) -> Level ---
	ParagraphGetLevelsPtr    :: proc(paragraph: Paragraph) -> [^]Level ---
	ParagraphRelease         :: proc(paragraph: Paragraph) ---
}
