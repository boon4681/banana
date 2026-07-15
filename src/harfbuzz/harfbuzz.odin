package harfbuzz

import "core:c"

when ODIN_ARCH == .wasm32 {
	foreign import hb "./libc/wasm/harfbuzz.o"
} else when ODIN_OS == .Windows {
	foreign import hb "./libc/windows/harfbuzz.lib"
} else when ODIN_OS == .Darwin {
	foreign import hb "./libc/macos/libharfbuzz.a"
} else {
	foreign import hb "./libc/linux/libharfbuzz.a"
}

Blob :: distinct rawptr
Face :: distinct rawptr
Font :: distinct rawptr
Buffer :: distinct rawptr
Language :: distinct rawptr
Unicode_Funcs :: distinct rawptr

Tag :: distinct u32
Script :: distinct u32
Codepoint :: u32
Position :: i32 // 26.6 fixed point when font scale is size * 64, or px when scale is px
Mask :: u32
Bool :: c.int

tag :: proc(a, b, c, d: u8) -> Tag {
	return Tag(u32(a) << 24 | u32(b) << 16 | u32(c) << 8 | u32(d))
}

Direction :: enum c.int {
	Invalid = 0,
	LTR     = 4,
	RTL     = 5,
	TTB     = 6,
	BTT     = 7,
}

Memory_Mode :: enum c.int {
	Duplicate,
	Readonly,
	Writable,
	Readonly_May_Make_Writable,
}

Cluster_Level :: enum c.int {
	Monotone_Graphemes,
	Monotone_Characters,
	Characters,
}

Glyph_Info :: struct {
	codepoint: Codepoint, // glyph index after shaping
	mask:      Mask,
	cluster:   u32, // byte index into the original UTF-8 run
	var1:      u32,
	var2:      u32,
}

Glyph_Position :: struct {
	x_advance: Position,
	y_advance: Position,
	x_offset:  Position,
	y_offset:  Position,
	var:       u32,
}

Feature :: struct {
	tag:   Tag,
	value: u32,
	start: c.uint,
	end:   c.uint,
}

Segment_Properties :: struct {
	direction: Direction,
	script:    Script,
	language:  Language,
	reserved1: rawptr,
	reserved2: rawptr,
}

Blob_Destroy_Proc :: proc "c" (user_data: rawptr)

@(default_calling_convention = "c", link_prefix = "hb_")
foreign hb {
	blob_create :: proc(data: [^]u8, length: c.uint, mode: Memory_Mode, user_data: rawptr, destroy: Blob_Destroy_Proc) -> Blob ---
	blob_destroy :: proc(blob: Blob) ---

	face_create :: proc(blob: Blob, index: c.uint) -> Face ---
	face_destroy :: proc(face: Face) ---
	face_get_upem :: proc(face: Face) -> c.uint ---

	font_create :: proc(face: Face) -> Font ---
	font_destroy :: proc(font: Font) ---
	font_set_scale :: proc(font: Font, x_scale, y_scale: c.int) ---

	buffer_create :: proc() -> Buffer ---
	buffer_destroy :: proc(buffer: Buffer) ---
	buffer_clear_contents :: proc(buffer: Buffer) ---
	buffer_add_utf8 :: proc(buffer: Buffer, text: [^]u8, text_length: c.int, item_offset: c.uint, item_length: c.int) ---
	buffer_set_direction :: proc(buffer: Buffer, direction: Direction) ---
	buffer_set_script :: proc(buffer: Buffer, script: Script) ---
	buffer_set_language :: proc(buffer: Buffer, language: Language) ---
	buffer_set_cluster_level :: proc(buffer: Buffer, level: Cluster_Level) ---
	buffer_guess_segment_properties :: proc(buffer: Buffer) ---
	buffer_get_segment_properties :: proc(buffer: Buffer, props: ^Segment_Properties) ---
	buffer_get_length :: proc(buffer: Buffer) -> c.uint ---
	buffer_get_glyph_infos :: proc(buffer: Buffer, length: ^c.uint) -> [^]Glyph_Info ---
	buffer_get_glyph_positions :: proc(buffer: Buffer, length: ^c.uint) -> [^]Glyph_Position ---

	shape :: proc(font: Font, buffer: Buffer, features: [^]Feature, num_features: c.uint) ---

	script_from_string :: proc(str: [^]u8, len: c.int) -> Script ---
	language_from_string :: proc(str: [^]u8, len: c.int) -> Language ---
	language_get_default :: proc() -> Language ---

	unicode_funcs_get_default :: proc() -> Unicode_Funcs ---
	unicode_script :: proc(funcs: Unicode_Funcs, unicode: Codepoint) -> Script ---
}
