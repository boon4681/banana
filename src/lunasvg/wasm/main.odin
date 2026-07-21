package wasm_test

import "core:c"
import "core:fmt"
import "core:os"
import luna "src:lunasvg"

failed: bool

expect :: proc(ok: bool, what: string) {
	if !ok {
		fmt.eprintfln("FAIL: %s", what)
		failed = true
	}
}

expect_value :: proc(what: string, got, want: $T) {
	if got != want {
		fmt.eprintfln("FAIL: %s: got %v, want %v", what, got, want)
		failed = true
	}
}

SOLID : string : `<svg viewBox="0 0 8 8"><rect x="0" y="0" width="8" height="8" fill="#ff0000"/></svg>`

STYLED : string : `<svg viewBox="0 0 8 8"><style>.fill{fill:#00ff00}</style><rect class="fill" x="0" y="0" width="8" height="8"/></svg>`

BAD : string : `<html/>`

main :: proc() {
	{
		handle := luna.parse(raw_data(SOLID), c.size_t(len(SOLID)))
		expect(handle != nil, "parse solid")
		defer luna.destroy(handle)

		w, h: f32
		expect(luna.size(handle, &w, &h), "size query")
		expect_value("view width", w, f32(8))
		expect_value("view height", h, f32(8))

		pixels := make([]u8, 8 * 8 * 4)
		defer delete(pixels)
		expect(luna.render(handle, raw_data(pixels), 8, 8, 8 * 4, 1, 1), "render solid")

		// RGBA8 after convertToRGBA; opaque red everywhere.
		expect_value("pixel r", pixels[0], u8(255))
		expect_value("pixel g", pixels[1], u8(0))
		expect_value("pixel b", pixels[2], u8(0))
		expect_value("pixel a", pixels[3], u8(255))

		center := (4 * 8 + 4) * 4
		expect_value("center r", pixels[center], u8(255))
		expect_value("center a", pixels[center + 3], u8(255))
	}

	{
		handle := luna.parse(raw_data(STYLED), c.size_t(len(STYLED)))
		expect(handle != nil, "parse styled")
		defer luna.destroy(handle)

		pixels := make([]u8, 8 * 8 * 4)
		defer delete(pixels)
		expect(luna.render(handle, raw_data(pixels), 8, 8, 8 * 4, 1, 1), "render styled")

		expect_value("css fill r", pixels[0], u8(0))
		expect_value("css fill g", pixels[1], u8(255))
		expect_value("css fill b", pixels[2], u8(0))
		expect_value("css fill a", pixels[3], u8(255))
	}

	{
		handle := luna.parse(raw_data(SOLID), c.size_t(len(SOLID)))
		defer luna.destroy(handle)

		SIZE :: 512
		pixels := make([]u8, SIZE * SIZE * 4)
		defer delete(pixels)
		expect(
			luna.render(handle, raw_data(pixels), SIZE, SIZE, SIZE * 4, SIZE / 8, SIZE / 8),
			"render large",
		)
		last := (SIZE * SIZE - 1) * 4
		expect_value("large last a", pixels[last + 3], u8(255))
	}

	expect(luna.parse(raw_data(BAD), c.size_t(len(BAD))) == nil, "reject non-svg")

	if failed {
		os.exit(1)
	}
	fmt.println("lunasvg wasm test passed")
}
