package input

import "base:runtime"

// Backed by the platform; wired at window creation.
// the OS clipboard is process-wide state.
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
