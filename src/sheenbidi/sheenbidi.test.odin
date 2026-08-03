#+build !wasm32
package sheenbidi

import "core:testing"

@(test)
sheenbidi_test :: proc(t: ^testing.T) {
	// "abc " + Hebrew alef-bet-gimel: strong LTR then strong RTL.
	str := [7]rune{'a', 'b', 'c', ' ', 0x05D0, 0x05D1, 0x05D2}
	levels: [7]Level

	base, ok := embedding_levels(str[:], levels[:])

	testing.expect(t, ok)
	testing.expect_value(t, base, Level(0))
	testing.expect(t, !level_is_rtl(levels[0]))
	testing.expect(t, level_is_rtl(levels[4]))
}
