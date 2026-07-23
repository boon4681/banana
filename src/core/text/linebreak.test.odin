#+build !wasm32
package text

import "core:testing"

@(test)
test_break_class_cjk_punctuation :: proc(t: ^testing.T) {
    testing.expect_value(t, break_class(0x3002), Break_Class.CL) // 。
    testing.expect_value(t, break_class(0xFF0C), Break_Class.CL) // ，
    testing.expect_value(t, break_class(0x4E00), Break_Class.ID) // 一
    testing.expect_value(t, break_class(0x3053), Break_Class.ID) // こ
    testing.expect_value(t, break_class(0x0E01), Break_Class.SA) // Thai ก
}

// LB13: never break before closing punctuation.
@(test)
test_no_break_before_closing :: proc(t: ^testing.T) {
    testing.expect(t, !can_break_between(.ID, .CL), "ID x CL must not break")
    testing.expect(t, !can_break_between(.ID, .EX), "ID x EX must not break")
}

// LB14: never break after opening punctuation.
@(test)
test_no_break_after_opening :: proc(t: ^testing.T) {
    testing.expect(t, !can_break_between(.OP, .ID), "OP x ID must not break")
}

// Ideographs break freely against each other.
@(test)
test_ideograph_breaks :: proc(t: ^testing.T) {
    testing.expect(t, can_break_between(.ID, .ID), "ID / ID must break")
}

// The classes that get segmented per character must include the punctuation
// ones, or the pair table never sees them as separate words.
@(test)
test_is_ideographic_covers_punctuation :: proc(t: ^testing.T) {
    testing.expect(t, is_ideographic(.CL), "CL must be per-character segmented")
    testing.expect(t, is_ideographic(.ID), "ID must be per-character segmented")
}
