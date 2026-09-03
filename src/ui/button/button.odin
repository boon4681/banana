package button

import "src:core/events"
import "src:core/node"
import "src:core/painter"
import "src:ui/text_node"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Button

Button_Style :: struct {
    using base:   node.Style,
    background: Color,
    hover:      Color,
    pressed:    Color,
    radius:     f32,
}

Button :: struct {
    using node: Node,
    style: proc(self: ^Button) -> ^Button_Style,

    // Fired on a click.
    onclick: proc(self: ^Button),

    _hovered: bool,
    _pressed: bool,
}

New :: proc(text: string = "", style: Button_Style = {}, key: Maybe(string) = nil) -> ^Button {
    n := new(Button)
    node.Init(n, key)

    st := style
    if st.background == {} do st.background = {250, 250, 250, 255}
    if st.hover == {} do st.hover = {250, 250, 250, 230}
    if st.pressed == {} do st.pressed = {250, 250, 250, 204}
    if st.radius == 0 do st.radius = 6

    n.style = _get_style
    node.Set_Style(auto_cast(n), new_clone(st))
    node.Init_Style(auto_cast(n))
    _apply_defaults(n)

    n.draw = transmute(proc(self: ^Node))_draw
    n.on_free = transmute(proc(self: ^Node))_free

    // A convenience for Odin callers only: markup children come through the
    // normal child path, so this stays empty there.
    if text != "" do n->add(text_node.New(text))

    n->on(events.MOUSE_ENTER_EVENT, _on_enter)
    n->on(events.MOUSE_LEAVE_EVENT, _on_leave)
    n->on(events.MOUSE_DOWN_EVENT, _on_down)
    n->on(events.MOUSE_UP_EVENT, _on_up)
    n->on(events.MOUSE_CLICK_EVENT, _on_click)
    return n
}

@(private="file")
_apply_defaults :: proc(n: ^Button) {
    s := n->style()
    s->set_flex_direction(.Row)
    s->set_justify_content(.Center)
    s->set_align_items(.Center)
    s->set_flex_shrink(0)
    s->set_padding_x(16)
    s->set_padding_y(8)
    s->set_select_mode(.None)
    // primary-foreground: neutral-900 on the light primary fill.
    if s->get_color() == {} do s->set_color({23, 23, 23, 255})
}

@(private="file")
_get_style :: proc(n: ^Button) -> ^Button_Style {
    return auto_cast(n._internal_style)
}

@(private="file")
_from_signal :: proc(s: ^events.Event_Signal) -> ^Button {
    return auto_cast(s.current_target)
}

@(private="file")
_on_enter :: proc(s: ^events.Event_Signal) {
    _from_signal(s)._hovered = true
}

@(private="file")
_on_leave :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    n._hovered = false
    n._pressed = false
}

@(private="file")
_on_down :: proc(s: ^events.Event_Signal) {
    e := cast(^events.Mouse_Event)s.data
    if e.button != 0 do return
    _from_signal(s)._pressed = true
}

@(private="file")
_on_up :: proc(s: ^events.Event_Signal) {
    _from_signal(s)._pressed = false
}

@(private="file")
_on_click :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    e := cast(^events.Mouse_Event)s.data
    if e.button != 0 do return
    if n.onclick != nil do n->onclick()
}

@(private="file")
_draw :: proc(n: ^Button) {
    st := n->style()
    bg := st.background
    if n._pressed {
        bg = st.pressed
    } else if n._hovered {
        bg = st.hover
    }
    painter.rect(painter.get(), n.rect, bg, st.radius)
}

@(private="file")
_free :: proc(n: ^Button) {
    free(n._internal_style)
    free(n.data)
}
