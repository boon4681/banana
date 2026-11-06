package input

import "base:runtime"
import "src:core/node"
import "src:core/events"

Input_State :: struct {
    root:     ^Node,
    hovered:  ^Node, // node currently under the cursor
    pressed:  ^Node, // node the last mousedown landed on
    focused:  ^Node, // node holding keyboard focus
    focus_visible: bool, // focus arrived by keyboard
    captured: ^Node, // node grabbing all pointer events while dragging, nil if none
    mouse_x:  f32,
    mouse_y:  f32,
    mods:     events.Mods, // latest keyboard modifier state, stamped onto mouse events

    window_bus:    ^events.Bus,
    window_target: rawptr,    // rawptr cuz importing the window type here would make an import cycle

    selection: Selection_State,
}

init :: proc(im: ^Input_State, root: ^Node, window_bus: ^events.Bus = nil, window_target: rawptr = nil) {
    im.root = root
    im.window_bus = window_bus
    im.window_target = window_target
}

// call this before you free a node, or input keeps a pointer to it and you get use after free
forget :: proc(im: ^Input_State, n: ^Node) {
    if im == nil || n == nil do return
    if im.hovered == n do im.hovered = nil
    if im.pressed == n do im.pressed = nil
    if im.focused == n do im.focused = nil
    if im.captured == n do im.captured = nil

    s := &im.selection
    g := &s.gesture
    if g.last_click_node == n {
        g.last_click_node = nil
        g.click_count = 0
    }
    if s.range.anchor.node == n || s.range.focus.node == n ||
       g.anchor.start.node == n || g.anchor.end.node == n {
        selection_clear(im)
    }
}

@(private, thread_local)
_active_input_state: ^Input_State

set_context :: proc(state: ^Input_State){
    _active_input_state = state
}

get_context :: proc() -> ^Input_State {
    return _active_input_state
}
