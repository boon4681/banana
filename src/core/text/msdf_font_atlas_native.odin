#+build !js
package text

import "core:os"

save_msdf_font_atlas :: proc(set: ^Font_Set, path: string) -> MSDF_Font_Atlas_Error {
    data, err := msdf_font_atlas_encode(set)
    defer delete(data)
    if err != .None do return err
    if os.write_entire_file(path, data) != nil do return .Invalid
    return .None
}

load_font_from_msdf_atlas :: proc(set: ^Font_Set, path: string) -> MSDF_Font_Atlas_Error {
    data, read_err := os.read_entire_file_from_path(path, context.temp_allocator)
    if read_err != nil do return .Invalid
    return load_font_from_msdf_atlas_data(set, data)
}
