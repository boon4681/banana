// SVG document parsing and rasterization, backed by lunasvg/plutovg. The
// document owns an opaque native handle; rasterization happens in `cache.odin`
// at device resolution and is drawn as a tinted textured quad.
package svg

import "core:c"
import "src:core/common"
import "src:lunasvg"

Error :: enum {
	None,
	Invalid_Document,
}

Document :: struct {
	raw:   rawptr,
	view_box: common.Rect,
}

parse :: proc(source: string) -> (Document, Error) {
	if len(source) == 0 do return {}, .Invalid_Document
	raw := lunasvg.parse(raw_data(source), c.size_t(len(source)))
	if raw == nil do return {}, .Invalid_Document

	doc := Document{raw = raw}
	w, h: f32
	if !lunasvg.size(raw, &w, &h) {
		lunasvg.destroy(raw)
		return {}, .Invalid_Document
	}
	doc.view_box = {0, 0, w, h}
	return doc, .None
}

destroy :: proc(doc: ^Document) {
	if doc == nil || doc.raw == nil do return
	lunasvg.destroy(doc.raw)
	doc^ = {}
}
