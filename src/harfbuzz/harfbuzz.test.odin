#+build !wasm32
package harfbuzz

import "core:testing"

@(test)
harfbuzz_test :: proc(t: ^testing.T) {
	buf := buffer_create()
	defer buffer_destroy(buf)

	text := "שלום עולם"
	buffer_add_utf8(buf, raw_data(text), i32(len(text)), 0, i32(len(text)))
	buffer_guess_segment_properties(buf)

	props: Segment_Properties
	buffer_get_segment_properties(buf, &props)

	testing.expect_value(t, props.direction, Direction.RTL)
	testing.expect_value(t, props.script, Script(tag('H', 'e', 'b', 'r')))

	length: u32
	infos := buffer_get_glyph_infos(buf, &length)
	testing.expect_value(t, length, 9)
	testing.expect_value(t, infos[0].codepoint, 0x05E9)
}
