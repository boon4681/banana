package platform

import "src:core/node"

DEFAULT_RESIZE_BORDER :: 8

Title_Bar :: struct {
    caption_node:    ^node.BaseNode,
    minimize_button: ^node.BaseNode,
    maximize_button: ^node.BaseNode,
    close_button:    ^node.BaseNode,
}

Frame_VTable :: struct #all_or_none {
    // Removes the OS caption and routes drag/hit-testing through `bar`'s nodes.
    // This also strips the OS resize border, so pair it with set_resize_border.
    set_title_bar:        proc(self: ^Frame, bar: Title_Bar) -> ^Frame,
    // Restores the OS caption.
    clear_title_bar:      proc(self: ^Frame) -> ^Frame,
    // Width in logical pixels of the client-area strip acting as a resize grip.
    // Only meaningful once the OS border is gone. Zero disables it.
    set_resize_border:    proc(self: ^Frame, width: int) -> ^Frame,
    // Toggles the DWM drop shadow and the rounded corners that come with it.
    set_shadow:           proc(self: ^Frame, enabled: bool) -> ^Frame,
    // Keeps a maximized window inside the monitor work area. Without this a
    // borderless window overhangs the screen edges when maximized.
    set_clamp_maximized:  proc(self: ^Frame, enabled: bool) -> ^Frame,
    // Suppresses the background erase that otherwise flashes white on resize.
    set_background_erase: proc(self: ^Frame, enabled: bool) -> ^Frame,
    // Pins the window above every non-topmost peer. False restores the default
    // z-order so other windows can cover it again.
    set_top_most:         proc(self: ^Frame, enabled: bool) -> ^Frame,
    // Toggles whether the OS lets the user resize the window by dragging its
    // edges. False locks the current size.
    set_resize:           proc(self: ^Frame, enabled: bool) -> ^Frame,
    // Pins the window above other apps' fullscreen surfaces by re-asserting
    // topmost on a Win32 timer. Heavier than `set_top_most`; intended for
    // picture-in-picture style overlays.
    set_always_top_most:  proc(self: ^Frame, enabled: bool) -> ^Frame,
    // Lets clicks landing on pixels no node claims fall through to the window
    // beneath. Intended for full-screen overlays, whose window covers far more
    // than they paint; pair it with `pointer_events = .None` on the root.
    set_click_through:    proc(self: ^Frame, enabled: bool) -> ^Frame,
}
