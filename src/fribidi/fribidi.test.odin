#+build !wasm32
package fribidi

import "core:testing"

@(test)
fribidi_test :: proc(t: ^testing.T) {
	// "abc " + Hebrew alef-bet-gimel: strong LTR then strong RTL
	str := [7]Char{'a', 'b', 'c', ' ', 0x05D0, 0x05D1, 0x05D2}
	types: [7]Char_Type
	btypes: [7]Bracket_Type
	levels: [7]Level

	get_bidi_types(&str[0], 7, &types[0])
	get_bracket_types(&str[0], 7, &types[0], &btypes[0])

	base := PAR_ON
	max_level := get_par_embedding_levels_ex(&types[0], &btypes[0], 7, &base, &levels[0])

	testing.expect(t, max_level > 0)
	testing.expect_value(t, base, PAR_LTR)
	testing.expect(t, !level_is_rtl(levels[0]))
	testing.expect(t, level_is_rtl(levels[4]))
}
