#+build !windows
package platform

import "core:fmt"

Frame :: struct {
    window: ^Window,
    using _internal_vt: ^Frame_VTable,
}

@(private = "file", thread_local)
_frame: Frame

enable_native_frame :: proc(w: ^Window) -> ^Frame {
    fmt.println("warning: enable_native_frame is unsupported on this platform and has no-op")
    if w == nil do return nil
    _frame = Frame{window = w, _internal_vt = &frame_vtable}
    return &_frame
}

disable_native_frame :: proc(w: ^Window) {
    if w != nil do w.frame = nil
    _frame = {}
}

sync_click_through  :: proc(w: ^Window) {}
set_pointer_capture :: proc(enabled: bool) {}
begin_self_hide     :: proc(w: ^Window) {}
end_self_hide       :: proc(w: ^Window) {}

@(private = "file")
frame_vtable := Frame_VTable {
    set_title_bar = proc(self: ^Frame, bar: Title_Bar) -> ^Frame {
        fmt.println("This platform is not support set_title_bar")
        return self
    },
    clear_title_bar = proc(self: ^Frame) -> ^Frame {
        fmt.println("This platform is not support clear_title_bar")
        return self
    },
    set_resize_border = proc(self: ^Frame, width: int) -> ^Frame {
        fmt.println("This platform is not support set_resize_border")
        return self
    },
    set_shadow = proc(self: ^Frame, enabled: bool) -> ^Frame {
        fmt.println("This platform is not support set_shadow")
        return self
    },
    set_clamp_maximized = proc(self: ^Frame, enabled: bool) -> ^Frame {
        fmt.println("This platform is not support set_clamp_maximized")
        return self
    },
    set_background_erase = proc(self: ^Frame, enabled: bool) -> ^Frame {
        fmt.println("This platform is not support set_background_erase")
        return self
    },
    set_top_most = proc(self: ^Frame, enabled: bool) -> ^Frame {
        fmt.println("This platform is not support set_top_most")
        return self
    },
    set_resize = proc(self: ^Frame, enabled: bool) -> ^Frame {
        fmt.println("This platform is not support set_resize")
        return self
    },
    set_always_top_most = proc(self: ^Frame, enabled: bool) -> ^Frame {
        fmt.println("This platform is not support set_always_top_most")
        return self
    },
    set_click_through = proc(self: ^Frame, enabled: bool) -> ^Frame {
        fmt.println("This platform is not support set_always_top_most")
        return self
    },
}
