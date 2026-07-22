#+build js
package text

foreign import banana_env "banana_env"

@(default_calling_convention = "contextless")
foreign banana_env {
    @(private="file")
    asset_size :: proc(path: string) -> i32 ---

    @(private="file")
    asset_read :: proc(path: string, dst: [^]byte) ---
}

@(private="file")
load_asset :: proc(path: string, allocator := context.allocator) -> []byte {
    size := asset_size(path)
    if size < 0 do return nil
    data := make([]byte, size, allocator)
    asset_read(path, raw_data(data))
    return data
}

@(private)
_web_load_font :: proc(set: ^Font_Set, path: string, index := 0) -> ^Face {
    data := load_asset(path, context.temp_allocator)
    if data == nil do return nil
    return set_register(set, data, index) // it clones the bytes it keeps
}
