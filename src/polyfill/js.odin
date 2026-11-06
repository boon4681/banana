#+build js
package polyfill

foreign import banana_env "banana_env"

Picked_File :: struct {
    name: string,
    data: []byte,
}

Files_Picked_Proc :: proc(files: []Picked_File, user: rawptr)

@(private="file")
Pending_Pick :: struct {
    callback: Files_Picked_Proc,
    user:     rawptr,
    files:    [dynamic]Picked_File,
}

@(private="file")
_picks: map[u32]Pending_Pick

@(private="file")
_next_pick: u32

@(default_calling_convention = "contextless")
foreign banana_env {
    @(private="file")
    asset_size :: proc(path: string) -> i32 ---

    @(private="file")
    asset_read :: proc(path: string, dst: [^]byte) ---

    @(private="file")
    file_dialog_open :: proc(id: u32, folder: bool, multiple: bool, accept: string) ---
}

load_asset :: proc(path: string, allocator := context.allocator) -> []byte {
    size := asset_size(path)
    if size < 0 do return nil
    data := make([]byte, size, allocator)
    asset_read(path, raw_data(data))
    return data
}

pick_files :: proc(folder, multiple: bool, accept: string, callback: Files_Picked_Proc, user: rawptr = nil) {
    _next_pick += 1
    _picks[_next_pick] = {callback = callback, user = user}
    file_dialog_open(_next_pick, folder, multiple, accept)
}

@(export)
banana_file_dialog_file :: proc(id: u32, name_len: i32, data_len: i32) -> rawptr {
    pick, ok := &_picks[id]
    if !ok || name_len < 0 || data_len < 0 do return nil
    buf := make([]byte, name_len + data_len)
    append(&pick.files, Picked_File{name = string(buf[:name_len]), data = buf[name_len:]})
    return raw_data(buf)
}

@(export)
banana_file_dialog_done :: proc(id: u32) {
    pick, ok := _picks[id]
    if !ok do return
    delete_key(&_picks, id)
    defer {
        for file in pick.files do delete(raw_data(file.name)[:len(file.name) + len(file.data)])
        delete(pick.files)
    }
    pick.callback(pick.files[:], pick.user)
}
