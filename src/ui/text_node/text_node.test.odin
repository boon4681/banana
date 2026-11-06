#+build !wasm32
package text_node

import "core:testing"
import "src:core/node"

@(test)
computed_zero_text_is_not_replaced_by_native_defaults :: proc(t: ^testing.T) {
    st := node.Text_Style{computed = true, font_size = 16, line_height_specified = true, line_height = 0, line_height_unit = .Point}
    testing.expect_value(t, _line_height_em(st), f32(0))
    st.line_height = 24
    testing.expect_value(t, _line_height_em(st), f32(1.5))
    st.font_size = 0
    testing.expect_value(t, _line_height_em(st), f32(0))
}

@(test)
test_layout_width_preserves_fractional_measurement :: proc(t: ^testing.T) {
    // Yoga measured at 59.5 px but rounded the final rectangle to 60 px.
    // Drawing must keep the measured wrapping width so its line count still
    // agrees with the height returned to layout.
    testing.expect_value(t, _resolve_layout_width_em(5.95, true, 60, 10), f32(5.95))

    // A real resize is not pixel rounding and must use the new rectangle.
    testing.expect_value(t, _resolve_layout_width_em(5.95, true, 80, 10), f32(8))
}
