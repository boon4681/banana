package input

import "core:time"
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
        ev := events.Mouse_Event{x = x, y = y, mods = im.mods}
        dispatch(im.captured, events.MOUSE_MOVE_EVENT, &ev)
        return
    }

    target := hit_test.hit_test(im.root, x, y)

    if target != im.hovered {
        if im.hovered != nil {
            ev := events.Mouse_Event{x = x, y = y, mods = im.mods}
            dispatch(im.hovered, events.MOUSE_LEAVE_EVENT, &ev)
        }
        if target != nil {
            ev := events.Mouse_Event{x = x, y = y, mods = im.mods}
            dispatch(target, events.MOUSE_ENTER_EVENT, &ev)
        }
        im.hovered = target
    }

    ev := events.Mouse_Event{x = x, y = y, mods = im.mods}
    result := dispatch(target, events.MOUSE_MOVE_EVENT, &ev)
    move_cancelled := result.cancelled

    if im.selection.gesture.dragging && !move_cancelled do selection_extend(im, x, y)
}

// Pointer left the window.
on_mouse_leave :: proc(im: ^Input_State) {
    _active_input_state = im
    if im.captured != nil {
        ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, mods = im.mods}
        dispatch(nil, events.MOUSE_LEAVE_EVENT, &ev)
        return
    }
    ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, mods = im.mods}
    dispatch(im.hovered, events.MOUSE_LEAVE_EVENT, &ev)
    im.hovered = nil
}

// Button pressed. Dispatches "mousedown"; tracks the node for click/focus.
// `mods` records the keyboard modifier state at press time so handlers can
// query it via modifiers() (GLFW delivers mods on the button callback).
on_mouse_down :: proc(im: ^Input_State, button: int, mods: events.Mods = {}) {
    _active_input_state = im
    im.mods = mods
    target := hit_test.hit_test(im.root, im.mouse_x, im.mouse_y)
    im.pressed = target

    ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button, mods = im.mods}
    result := dispatch(target, events.MOUSE_DOWN_EVENT, &ev)
    down_cancelled := result.cancelled

    if button == 0 && !down_cancelled && target != im.focused {
        if im.focused != nil {
            be := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button, mods = im.mods}
            dispatch(im.focused, events.BLUR_EVENT, &be)
        }
        im.focused = target
        if target != nil {
            fe := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button, mods = im.mods}
            dispatch(target, events.FOCUS_EVENT, &fe)
        }
    }

    if button == 0 && !down_cancelled && im.captured == nil {
        selection_begin(im, im.mouse_x, im.mouse_y, time.tick_now())
    }
}

on_mouse_up :: proc(im: ^Input_State, button: int) {
    _active_input_state = im
    if button == 0 && im.selection.gesture.dragging {
        selection_extend(im, im.mouse_x, im.mouse_y)
        selection_end(im)
    }

    captured := im.captured
    target := captured
    if target == nil do target = hit_test.hit_test(im.root, im.mouse_x, im.mouse_y)
    ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button, mods = im.mods}
    dispatch(target, events.MOUSE_UP_EVENT, &ev)

    click_target := target if captured != nil else _common_ancestor(im.pressed, target)
    if button == 0 && (click_target != nil || (im.pressed == nil && target == nil)) {
        ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, button = button, mods = im.mods}
        dispatch(click_target, events.MOUSE_CLICK_EVENT, &ev)
    }
    im.captured = nil
    im.pressed = nil
}

@(private = "file")
_common_ancestor :: proc(a, b: ^Node) -> ^Node {
    if a == nil || b == nil do return nil
    for x := a; x != nil; x = x.parent {
        for y := b; y != nil; y = y.parent {
            if x == y do return x
        }
    }
    return nil
}

// Wheel scrolled. Dispatches "wheel" at the node under the cursor.
on_wheel :: proc(im: ^Input_State, dx, dy: f32) {
    _active_input_state = im
    target := hit_test.hit_test(im.root, im.mouse_x, im.mouse_y)
    ev := events.Wheel_Event{x = im.mouse_x, y = im.mouse_y, delta_x = dx, delta_y = dy}
    dispatch(target, events.MOUSE_WHEEL_EVENT, &ev)
}
