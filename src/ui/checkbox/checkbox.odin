package checkbox

import "src:core/common"
import "src:core/events"
import "src:core/node"
import "src:core/painter"
import "src:ui/shared/theme"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Checkbox

SIZE :: f32(16)
GAP  :: f32(8)

Checkbox_Style :: struct {
    using base: node.Style,
    mark:       Color,
}

Checkbox :: struct {
    using node: Node,
    style: proc(self: ^Checkbox) -> ^Checkbox_Style,

    checked:  bool,
    disabled: bool,

    onchange: proc(self: ^Checkbox, checked: bool),

    set_checked: proc(self: ^Checkbox, checked: bool),
    _styled:     bool,
}

New :: proc(style: Checkbox_Style = {}, key: Maybe(string) = nil) -> ^Checkbox {
    n := new(Checkbox)
    node.Init(n, key)

    st := style
    if st.border_color == {} do st.border_color = theme.INPUT
    if st.border_width == 0 do st.border_width = 1
    if st.radius == 0 do st.radius = 4
    if st.background == {} do st.background = theme.INPUT_FILL
    if st.mark == {} do st.mark = theme.PRIMARY_FOREGROUND

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
_get_style :: proc(n: ^Checkbox) -> ^Checkbox_Style {
    n->damage()
    return auto_cast(n._internal_style)
}

@(private = "file")
_free :: proc(n: ^Checkbox) {
    free(n._internal_style)
}

@(private = "file")
_set_checked :: proc(n: ^Checkbox, checked: bool) {
    if n.checked != checked do n->damage()
    n.checked = checked
}

@(private = "file")
_toggle :: proc(n: ^Checkbox) {
    if n.disabled do return
    n->damage()
    n.checked = !n.checked
    if n.onchange != nil do n->onchange(n.checked)
}

@(private = "file")
_on_click :: proc(s: ^events.Event_Signal) {
    e := cast(^events.Mouse_Event)s.data
    if e.button == 0 do _toggle(auto_cast(s.current_target))
}

@(private = "file")
_on_key :: proc(s: ^events.Event_Signal) {
    e := cast(^events.Key_Event)s.data
    if s.target != s.current_target || e.repeat || e.code != .Space do return
    _toggle(auto_cast(s.current_target))
    events.prevent_default(s)
}

@(private = "file")
_draw :: proc(n: ^Checkbox) {
    st := n->style()
    p := painter.get()
    r := common.Rect{n.rect.x, n.rect.y + (n.rect.h - SIZE) * 0.5, SIZE, SIZE}
    fill, edge := st.background, st.border_color
    if n.checked && !n._styled do fill, edge = theme.PRIMARY, theme.PRIMARY
    if n.disabled {
        fill.a /= 2
        for &side in edge do side.a /= 2
    }
    radius := common.radii_resolve(st.radius, st.radius_percent, SIZE, SIZE)
    painter.decoration_under(p, r, radius, st.decoration)
    painter.rect(p, r, fill, radius)
    painter.border_sides(p, r, edge, st.border_width, radius)
    painter.decoration_over(p, r, radius, st.decoration)
    if n.checked {
        painter.line(p, {r.x + 4, r.y + 8.5}, {r.x + 7, r.y + 11.5}, st.mark, 1.6)
        painter.line(p, {r.x + 7, r.y + 11.5}, {r.x + 12, r.y + 5}, st.mark, 1.6)
    }
}
