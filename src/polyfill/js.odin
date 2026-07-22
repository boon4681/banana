#+build js
package polyfill

foreign import banana_env "banana_env"

@(default_calling_convention = "contextless")
foreign banana_env {
    @(private="file")
    asset_size :: proc(path: string) -> i32 ---

    @(private="file")
    asset_read :: proc(path: string, dst: [^]byte) ---
}

load_asset :: proc(path: string, allocator := context.allocator) -> []byte {
    size := asset_size(path)
    if size < 0 do return nil
    data := make([]byte, size, allocator)
    asset_read(path, raw_data(data))
    return data
}
