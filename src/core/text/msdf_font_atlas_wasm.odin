#+build js
package text

import "src:polyfill"

load_font_from_msdf_atlas :: proc(set: ^Font_Set, path: string) -> MSDF_Font_Atlas_Error {
    data := polyfill.load_asset(path, context.temp_allocator)
    if data == nil do return .Invalid
    return load_font_from_msdf_atlas_data(set, data)
}
