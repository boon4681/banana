package input

import "base:runtime"
import "src:core/node"
import "src:core/events"

Input_State :: struct {
    root:     ^Node,
    hovered:  ^Node, // node currently under the cursor
    pressed:  ^Node, // node the last mousedown landed on
    focused:  ^Node, // node holding keyboard focus
    captured: ^Node, // node grabbing all pointer events (drag), or nil
    mouse_x:  f32,
    mouse_y:  f32,
    mods:     events.Mods, // latest keyboard modifier state, stamped onto mouse events

    window_bus:    ^events.Bus,
    window_target: rawptr,    // Kept as an event raw pointer to avoid import cycle.

    selection: Selection_State,
}

init :: proc(im: ^Input_State, root: ^Node, window_bus: ^events.Bus = nil, window_target: rawptr = nil) {
    im.root = root
    im.window_bus = window_bus
    im.window_target = window_target
}

@(private, thread_local)
_active_input_state: ^Input_State

set_context :: proc(state: ^Input_State){
    _active_input_state = state
}

get_context :: proc() -> ^Input_State {
    return _active_input_state
}
