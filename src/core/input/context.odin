package input

import "base:runtime"
import "src:core/node"
import "src:core/events"

Node :: node.Node

Input_State :: struct {
    root:     ^Node,
    hovered:  ^Node, // node currently under the cursor
    pressed:  ^Node, // node the last mousedown landed on
    focused:  ^Node, // node holding keyboard focus
    captured: ^Node, // node grabbing all pointer events (drag), or nil
    mouse_x:  f32,
    mouse_y:  f32,
    mods:     events.Mods, // latest keyboard modifier state, stamped onto mouse events
}

init :: proc(im: ^Input_State, root: ^Node) {
    im.root = root
}

@(private, thread_local)
_active_input_state: ^Input_State

set_context :: proc(state: ^Input_State){
    _active_input_state = state
}

get_context :: proc() -> ^Input_State {
    return _active_input_state
}
