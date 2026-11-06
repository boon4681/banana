#+build js
package platform

import "base:runtime"
import "core:fmt"
import "core:strings"
import "src:polyfill"

@(private = "file")
Pending_Dialog :: struct {
    window:   ^Window,
    callback: File_Dialog_Callback,
    user:     rawptr,
}

@(private = "file")
_file_dialog :: proc(w: ^Window, opts: File_Dialog_Options, callback: File_Dialog_Callback, user: rawptr) {
    if opts.mode == .Save {
        fmt.println("warning: file_dialog .Save is unsupported on web")
        callback(w, nil, user)
        return
    }
    accept := make([dynamic]string, context.temp_allocator)
    if opts.mode == .Open {
        for filter in opts.filters {
            for ext in filter.extensions do append(&accept, strings.concatenate({".", ext}, context.temp_allocator))
        }
    }
    pending := new(Pending_Dialog)
    pending^ = {window = w, callback = callback, user = user}
    polyfill.pick_files(opts.mode == .Open_Folder, opts.multiple, strings.join(accept[:], ",", context.temp_allocator), _on_picked, pending)
}

@(private = "file")
_on_picked :: proc(picked: []polyfill.Picked_File, user: rawptr) {
    pending := cast(^Pending_Dialog)user
    defer runtime.mem_free(pending)
    files := make([]Dialog_File, len(picked), context.temp_allocator)
    for file, i in picked do files[i] = {name = file.name, data = file.data}

    prev := scoped_current(pending.window)
    defer restore_current(prev)
    pending.callback(pending.window, files, pending.user)
}


FILE_DIALOG :: File_Dialog_Interface {
    file_dialog = _file_dialog
}
