package input

import "base:runtime"

// how banana reaches the OS clipboard, the platform fills this in when the window is created.
// if get or set is nil, copy and paste just do nothing.
Clipboard :: struct {
    get: proc(allocator: runtime.Allocator) -> string,
    set: proc(text: string),
}

@(private, thread_local)
_active_clipboard: Clipboard

set_clipboard_procs :: proc(cb: Clipboard) {
    _active_clipboard = cb
}

clipboard_text :: proc(allocator := context.temp_allocator) -> string {
    return _active_clipboard.get != nil ? _active_clipboard.get(allocator) : ""
}

set_clipboard_text :: proc(text: string) {
    if _active_clipboard.set != nil do _active_clipboard.set(text)
}
