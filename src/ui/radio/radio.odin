package radio

import "src:core/common"
import "src:core/events"
import "src:core/input"
import "src:core/node"
import "src:core/painter"
import "src:ui/shared/theme"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Radio

SIZE :: f32(16)
GAP  :: f32(8)

Radio_Style :: struct {
    using base: node.Style,
    mark:       Color,
}

Radio :: struct {
    using node: Node,
    style: proc(self: ^Radio) -> ^Radio_Style,

    name:     string,
    checked:  bool,
    disabled: bool,

    onchange: proc(self: ^Radio, checked: bool),

    set_checked: proc(self: ^Radio, checked: bool),
}

New :: proc(style: Radio_Style = {}, key: Maybe(string) = nil) -> ^Radio {
    n := new(Radio)
    node.Init(n, key)

    st := style
    if st.border_color == {} do st.border_color = theme.INPUT
    if st.border_width == 0 do st.border_width = 1
    if st.background == {} do st.background = theme.INPUT_FILL
    if st.mark == {} do st.mark = theme.PRIMARY

    n.style = _get_style
    node.Set_Style(auto_cast(n), new_clone(st))
    node.Init_Style(auto_cast(n))
    s := n->style()
    s->set_flex_direction(.Row)->set_align_items(.Center)->set_flex_shrink(0)
    s->set_padding_left(SIZE + GAP)->set_min_height(SIZE)->set_min_width(SIZE)
    s->set_user_select(.None)

    n.set_checked = _set_checked
    n.draw = transmute(proc(self: ^Node))_draw
    n.on_free = transmute(proc(self: ^Node))_free
    n.focusable = true
    n->on(events.MOUSE_CLICK_EVENT, _on_click)
    n->on(events.KEY_DOWN_EVENT, _on_key)
    return n
}

@(private = "file")
_get_style :: proc(n: ^Radio) -> ^Radio_Style {
    n->damage()
    return auto_cast(n._internal_style)
}

@(private = "file")
_free :: proc(n: ^Radio) {
    free(n._internal_style)
}

@(private = "file")
_set_checked :: proc(n: ^Radio, checked: bool) {
    if n.checked != checked do n->damage()
    n.checked = checked
}

@(private = "file")
_turn_off_others :: proc(at: ^Node, chosen: ^Radio) {
    if at.type_id == typeid_of(Radio) && at != cast(^Node)chosen {
        other := cast(^Radio)at
        if other.name == chosen.name && other.checked {
            other->damage()
            other.checked = false
            if other.onchange != nil do other->onchange(false)
        }
    }
    for child in at.children do _turn_off_others(child, chosen)
}

@(private = "file")
_choose :: proc(n: ^Radio) {
    if n.disabled || n.checked do return
    n->damage()
    n.checked = true
    if n.name != "" {
        root := cast(^Node)n
        for root.parent != nil do root = root.parent
        _turn_off_others(root, n)
    }
    if n.onchange != nil do n->onchange(true)
}

@(private = "file")
_on_click :: proc(s: ^events.Event_Signal) {
    e := cast(^events.Mouse_Event)s.data
    if e.button == 0 do _choose(auto_cast(s.current_target))
}

@(private = "file")
_on_key :: proc(s: ^events.Event_Signal) {
    e := cast(^events.Key_Event)s.data
    n := cast(^Radio)s.current_target
    if s.target != s.current_target do return
    #partial switch e.code {
    case .Space:
        if e.repeat do return
        _choose(n)
    case .Right, .Down: _step(n, 1)
    case .Left, .Up: _step(n, -1)
    case: return
    }
    events.prevent_default(s)
}

@(private = "file")
_collect_group :: proc(at: ^Node, name: string, out: ^[dynamic]^Radio) {
    if at.type_id == typeid_of(Radio) {
        radio := cast(^Radio)at
        if radio.name == name && !radio.disabled do append(out, radio)
    }
    for child in at.children do _collect_group(child, name, out)
}

@(private = "file")
_step :: proc(n: ^Radio, delta: int) {
    if n.name == "" do return
    root := cast(^Node)n
    for root.parent != nil do root = root.parent
    group := make([dynamic]^Radio, context.temp_allocator)
    _collect_group(root, n.name, &group)
    for radio, i in group {
        if radio != n do continue
        next := group[(i + delta + len(group)) % len(group)]
        input.focus_node(auto_cast next)
        _choose(next)
        return
    }
}

@(private = "file")
_draw :: proc(n: ^Radio) {
    st := n->style()
    p := painter.get()
    r := common.Rect{n.rect.x, n.rect.y + (n.rect.h - SIZE) * 0.5, SIZE, SIZE}
    fill, edge, mark := st.background, st.border_color, st.mark
    if n.disabled {
        fill.a /= 2
        for &side in edge do side.a /= 2
        mark.a /= 2
    }
    round := common.Radii(SIZE / 2)
    painter.decoration_under(p, r, round, st.decoration)
    painter.rect(p, r, fill, round)
    painter.border_sides(p, r, edge, st.border_width, round)
    painter.decoration_over(p, r, round, st.decoration)
    if n.checked do painter.rect(p, {r.x + 4, r.y + 4, SIZE - 8, SIZE - 8}, mark, (SIZE - 8) / 2)
}
