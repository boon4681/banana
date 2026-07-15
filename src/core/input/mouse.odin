package input

import "src:core/events"
import "src:core/node"
import "src:core/hit_test"

// Capture the pointer for the node handling the current event.
capture_pointer :: proc(node: ^node.Node) {
    if _active_input_state != nil do _active_input_state.captured = node
}

// Release a capture started with capture_pointer.
release_pointer :: proc() {
    if _active_input_state != nil do _active_input_state.captured = nil
}

set_capture :: proc(im: ^Input_State, node: ^Node) {
    im.captured = node
}

// Release a prior set_capture. Called automatically on mouseup.
release_capture :: proc(im: ^Input_State) {
    im.captured = nil
}

// The node currently capturing the pointer, or nil.
captured_node :: proc(im: ^Input_State) -> ^Node {
    return im.captured
}

// Pointer moved to (x, y). Updates hover (firing enter/leave) and emits
// "mousemove" at the node under the cursor. While the pointer is captured, the
// move goes straight to the capturing node and hover is left untouched.
on_mouse_move :: proc(im: ^Input_State, x, y: f32) {
    _active_input_state = im
    im.mouse_x = x
    im.mouse_y = y

    if im.captured != nil {
        ev := events.Mouse_Event{x = x, y = y}
        dispatch(im.captured, events.MOUSE_MOVE_EVENT, &ev)
        return
    }

    target := hit_test.hit_test(im.root, x, y)

    if target != im.hovered {
        if im.hovered != nil {
            ev := events.Mouse_Event{x = x, y = y}
            dispatch(im.hovered, events.MOUSE_LEAVE_EVENT, &ev)
        }
        if target != nil {
            ev := events.Mouse_Event{x = x, y = y}
            dispatch(target, events.MOUSE_ENTER_EVENT, &ev)
        }
        im.hovered = target
    }

    if target != nil {
        ev := events.Mouse_Event{x = x, y = y}
        dispatch(target, events.MOUSE_MOVE_EVENT, &ev)
    }
}

// Button pressed. Dispatches "mousedown"; tracks the node for click/focus.
// `mods` records the keyboard modifier state at press time so handlers can
// query it via modifiers() (GLFW delivers mods on the button callback).
on_mouse_down :: proc(im: ^Input_State, button: int, mods: events.Mods = {}) {
    _active_input_state = im
    im.mods = mods
    target := hit_test.hit_test(im.root, im.mouse_x, im.mouse_y)
    im.pressed = target

    // Focus change: blur the old, focus the new (only on left button).
    if button == 0 && target != im.focused {
        if im.focused != nil {
            be := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button}
            dispatch(im.focused, events.BLUR_EVENT, &be)
        }
        im.focused = target
        if target != nil {
            fe := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button}
            dispatch(target, events.FOCUS_EVENT, &fe)
        }
    }

    if target != nil {
        ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button}
        dispatch(target, events.MOUSE_DOWN_EVENT, &ev)
    }
}

// Button released. While captured, "mouseup" goes to the capturing node and
// capture is released; a drag isn't a click
on_mouse_up :: proc(im: ^Input_State, button: int) {
    _active_input_state = im
    if im.captured != nil {
        node := im.captured
        ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button}
        dispatch(node, events.MOUSE_UP_EVENT, &ev)
        im.captured = nil
        im.pressed = nil
        return
    }

    target := hit_test.hit_test(im.root, im.mouse_x, im.mouse_y)
    if target != nil {
        ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button}
        dispatch(target, events.MOUSE_UP_EVENT, &ev)
    }
    if button == 0 && target != nil && target == im.pressed {
        ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button}
        dispatch(target, events.MOUSE_CLICK_EVENT, &ev)
    }
    im.pressed = nil
}

// Wheel scrolled. Dispatches "wheel" at the node under the cursor.
on_wheel :: proc(im: ^Input_State, dx, dy: f32) {
    _active_input_state = im
    target := hit_test.hit_test(im.root, im.mouse_x, im.mouse_y)
    if target == nil do return
    ev := events.Wheel_Event{x = im.mouse_x, y = im.mouse_y, delta_x = dx, delta_y = dy}
    dispatch(target, "wheel", &ev)
}
