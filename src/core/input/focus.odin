package input

import "src:core/events"
import "src:core/node"

focus_target :: proc(target: ^Node) -> ^Node {
    for at := target; at != nil; at = at.parent {
        if at.focusable do return at
    }
    return target
}

focus :: proc(im: ^Input_State, target: ^Node, visible := false) {
    im.focus_visible = visible && target != nil
    if im.focused == target do return
    _active_input_state = im
    ev := events.Mouse_Event{x = im.mouse_x, y = im.mouse_y, mods = im.mods}
    if im.focused != nil do dispatch(im.focused, events.BLUR_EVENT, &ev)
    im.focused = target
    if target != nil do dispatch(target, events.FOCUS_EVENT, &ev)
}

focus_is_visible :: proc() -> bool {
    return _active_input_state != nil && _active_input_state.focus_visible
}

focus_node :: proc(target: ^Node, visible := true) {
    if _active_input_state != nil do focus(_active_input_state, target, visible)
}

@(private = "file")
_collect_focusable :: proc(n: ^Node, out: ^[dynamic]^Node) {
    if n == nil || n.freed || node.is_hidden(n) do return
    if n.focusable do append(out, n)
    for child in n.children do _collect_focusable(child, out)
}

focus_step :: proc(im: ^Input_State, backwards: bool) -> bool {
    order := make([dynamic]^Node, context.temp_allocator)
    _collect_focusable(im.root, &order)
    if len(order) == 0 do return false
    at := -1
    for candidate, i in order {
        if candidate == im.focused || candidate == focus_target(im.focused) do at = i
    }
    next := 0 if !backwards else len(order) - 1
    if at >= 0 do next = (at + (len(order) - 1 if backwards else 1)) % len(order)
    focus(im, order[next], true)
    return true
}
