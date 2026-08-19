package platform

import "base:runtime"
import "src:core/render"
import "src:core/events"

Init_Options :: struct {
    width:        int,
    height:       int,
    title:        cstring,  // cstring so literals auto-coerce; passed straight to the OS
    vsync:        bool,
    msaa_samples: u32,
    decorated:    Maybe(bool),
    transparent:  bool,
    // Web only: id of the <canvas> this window renders into.
    // Empty falls back to "banana-canvas".
    canvas: string,
}

DEFAULT_OPTIONS :: Init_Options{width = 800, height = 600, title = "banana", vsync = true, msaa_samples = 4, decorated = true}

is_decorated :: proc(opts: Init_Options) -> bool {
    return opts.decorated.? or_else true
}

Platform_Interface :: struct #all_or_none {
    create_state:        proc(allocator: runtime.Allocator) -> rawptr,
    free_state:          proc(state: rawptr, allocator: runtime.Allocator),
    get_active_state:    proc() -> rawptr,
    set_active_state:    proc(state: rawptr),
    init:                proc(state: rawptr, opts: Init_Options, allocator: runtime.Allocator,) -> render.Render_Interface,
    shutdown:            proc(),
    should_close:        proc() -> bool,
    poll_events:         proc(),
    poll_size:           proc() -> (w, h: int),
    content_scale:       proc() -> f32, // browser devicePixelRatio equivalent
    request_close:       proc(),
    cancel_close:        proc(),
    set_title:           proc(title: string),
    get_position:        proc() -> (x, y: int),
    set_position:        proc(x, y: int),
    set_size:            proc(w, h: int),
    set_size_limits:     proc(min_w, min_h, max_w, max_h: int),
    set_cursor:          proc(shape: Cursor),
    minimize:            proc(),
    is_maximized:        proc() -> bool,
    toggle_maximize:     proc(), // Toggles between maximized and restored.
    set_window_user_ptr: proc(state: rawptr, ptr: rawptr),
    clipboard_get:       proc(allocator: runtime.Allocator) -> string,
    clipboard_set:       proc(text: string),
}

RESIZED       :: struct { fb_w, fb_h: i32, width, height: f32 }
MOUSE_MOVED   :: struct { x, y: f32 }
MOUSE_LEFT    :: struct {} // left node, not left click
MOUSE_BUTTON  :: struct { button, action: int, mods: events.Mods, x, y: f32 }
MOUSE_WHEEL   :: struct { dx, dy, x, y: f32 }
KEY           :: struct { code: events.Key, key: rune, scancode, action: int, mods: events.Mods }
TYPED         :: struct { codepoint: rune }
FOCUS_CHANGED :: struct { focused: bool }

EVENT :: union {
	RESIZED,
	MOUSE_MOVED,
	MOUSE_LEFT,
	MOUSE_BUTTON,
	MOUSE_WHEEL,
	KEY,
	TYPED,
	FOCUS_CHANGED,
}
