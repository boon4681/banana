package input

import "src:core/events"

// Current keyboard modifier state.
modifiers :: proc() -> events.Mods {
    return _active_input_state != nil ? _active_input_state.mods : {}
}

// Key pressed and repeated. Dispatched to the focused node (keyboard events are not positional).
// No focused node => dropped.
on_key_down :: proc(im: ^Input_State, code: events.Key, key: rune, mods: events.Mods, repeat: bool) {
    im.mods = mods
    if im.focused == nil do return
    ev := events.Key_Event{code = code, key = key, mods = mods, repeat = repeat}
    dispatch(im.focused, events.KEY_DOWN_EVENT, &ev)
}

on_key_up :: proc(im: ^Input_State, code: events.Key, key: rune, mods: events.Mods) {
    im.mods = mods
    if im.focused == nil do return
    ev := events.Key_Event{code = code, key = key, mods = mods}
    dispatch(im.focused, events.KEY_UP_EVENT, &ev)
}

// A character was typed (already decoded to a rune). Dispatched to the focused node as "input".
on_text :: proc(im: ^Input_State, codepoint: rune) {
    if im.focused == nil do return
    ev := events.Text_Event{codepoint = codepoint}
    dispatch(im.focused, events.TEXT_INPUT_EVENT, &ev)
}
