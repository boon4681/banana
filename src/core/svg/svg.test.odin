#+build !wasm32
package svg
import "core:testing"

@(test)
parse_and_size :: proc(t: ^testing.T) {
	doc, err := parse(`<svg viewBox="0 0 24 24"><rect width="24" height="24" fill="#f00"/></svg>`)
	defer destroy(&doc)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, doc.view_box.w, f32(24))
	testing.expect_value(t, doc.view_box.h, f32(24))
}

@(test)
reject_non_svg :: proc(t: ^testing.T) {
	doc, err := parse(`<html/>`)
	defer destroy(&doc)
	testing.expect_value(t, err, Error.Invalid_Document)
}
