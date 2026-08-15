package input

import "src:core/events"

// Current keyboard modifier state.
modifiers :: proc() -> events.Mods {
    return _active_input_state != nil ? _active_input_state.mods : {}
}

// Key pressed and repeated. Dispatched to the focused node (keyboard events are not positional).
@(private = "file")
_accel :: proc(mods: events.Mods) -> bool {
    when ODIN_OS == .Darwin {
        return .Super in mods
    } else {
        return .Ctrl in mods
    }
}

on_key_down :: proc(im: ^Input_State, code: events.Key, key: rune, mods: events.Mods, repeat: bool) {
    _active_input_state = im
    im.mods = mods

    if _accel(mods) && !repeat {
        #partial switch code {
        case .C:
            if selection_copy(im) do return
        case .A:
            if selection_select_all(im) do return
        }
    }

    ev := events.Key_Event{code = code, key = key, mods = mods, repeat = repeat}
    dispatch(im.focused, events.KEY_DOWN_EVENT, &ev)
}

on_key_up :: proc(im: ^Input_State, code: events.Key, key: rune, mods: events.Mods) {
    _active_input_state = im
    im.mods = mods
    ev := events.Key_Event{code = code, key = key, mods = mods}
    dispatch(im.focused, events.KEY_UP_EVENT, &ev)
}

// A character was typed (already decoded to a rune). Dispatched to the focused node as "input".
on_text :: proc(im: ^Input_State, codepoint: rune) {
    _active_input_state = im
    ev := events.Text_Event{codepoint = codepoint}
    dispatch(im.focused, events.TEXT_INPUT_EVENT, &ev)
}
