package events

import "src:core/binding"

BLUR_EVENT        :: "blur"
FOCUS_EVENT       :: "focus"
MOUSE_MOVE_EVENT  :: "mousemove"
MOUSE_LEAVE_EVENT :: "mouseleave"
MOUSE_ENTER_EVENT :: "mouseenter"
MOUSE_DOWN_EVENT  :: "mousedown"
MOUSE_UP_EVENT    :: "mouseup"
MOUSE_CLICK_EVENT :: "click"

KEY_DOWN_EVENT    :: "keydown"
KEY_UP_EVENT      :: "keyup"

TEXT_INPUT_EVENT  :: "input"

// Backends translate their native codes to this; see platform/p_glfw.odin
Key  :: binding.Key
Mod  :: binding.Mod
Mods :: binding.Mods

// This is for "keydown", "keyup".
Key_Event :: struct {
    code:   Key,
    key:    rune,
    mods:   Mods,
    repeat: bool,
}

// "textinput"
Text_Event :: struct {
    codepoint: rune,
}

// "mousedown", "mouseup", "mousemove", "click", "mouseenter", "mouseleave"
Mouse_Event :: struct {
    x, y:   f32,
    button: int, // 0 = left, 1 = right, 2 = middle
}

// "wheel"
Wheel_Event :: struct {
    x, y:             f32, // cursor position
    delta_x, delta_y: f32, // scroll amount this frame
}
