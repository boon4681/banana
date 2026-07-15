package fribidi

import "core:c"

when ODIN_ARCH == .wasm32 {
	foreign import fribidi "./libc/wasm/fribidi.o"
} else when ODIN_OS == .Windows {
	foreign import fribidi "./libc/windows/fribidi.lib"
} else when ODIN_OS == .Darwin {
	foreign import fribidi "./libc/macos/libfribidi.a"
} else {
	foreign import fribidi "./libc/linux/libfribidi.a"
}

Char :: u32
Str_Index :: c.int
Level :: i8
Char_Type :: distinct u32
Par_Type :: distinct u32
Bracket_Type :: distinct u32
Flags :: distinct u32

PAR_LTR :: Par_Type(0x00000110)
PAR_RTL :: Par_Type(0x00000111)
PAR_ON :: Par_Type(0x00000040)
PAR_WLTR :: Par_Type(0x00000020)
PAR_WRTL :: Par_Type(0x00000021)

FLAG_SHAPE_MIRRORING :: Flags(0x00000001)
FLAG_REORDER_NSM :: Flags(0x00000002)
FLAG_SHAPE_ARAB_PRES :: Flags(0x00000100)
FLAG_SHAPE_ARAB_LIGA :: Flags(0x00000200)
FLAG_REMOVE_BIDI :: Flags(0x00010000)
FLAG_REMOVE_JOINING :: Flags(0x00020000)
FLAG_REMOVE_SPECIALS :: Flags(0x00040000)
FLAGS_DEFAULT :: FLAG_SHAPE_MIRRORING | FLAG_REORDER_NSM | FLAG_REMOVE_SPECIALS
FLAGS_ARABIC :: FLAG_SHAPE_ARAB_PRES | FLAG_SHAPE_ARAB_LIGA

BRACKET_OPEN_MASK :: Bracket_Type(0x80000000)

level_is_rtl :: proc(level: Level) -> bool {
	return level & 1 != 0
}

@(default_calling_convention = "c", link_prefix = "fribidi_")
foreign fribidi {
	get_bidi_types :: proc(str: [^]Char, len: Str_Index, btypes: [^]Char_Type) ---
	get_bracket_types :: proc(str: [^]Char, len: Str_Index, types: [^]Char_Type, btypes: [^]Bracket_Type) ---
	get_par_direction :: proc(bidi_types: [^]Char_Type, len: Str_Index) -> Par_Type ---
	// returns max_level + 1, or 0 on error
	get_par_embedding_levels_ex :: proc(bidi_types: [^]Char_Type, bracket_types: [^]Bracket_Type, len: Str_Index, pbase_dir: ^Par_Type, embedding_levels: [^]Level) -> Level ---
	// visual_str and map may be nil; map must be initialized to identity by caller
	reorder_line :: proc(flags: Flags, bidi_types: [^]Char_Type, len: Str_Index, off: Str_Index, base_dir: Par_Type, embedding_levels: [^]Level, visual_str: [^]Char, position_L_to_V_map: [^]Str_Index) -> Level ---
	get_mirror_char :: proc(ch: Char, mirrored_ch: ^Char) -> c.bool ---
}
