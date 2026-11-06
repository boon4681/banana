package button

import "src:core/events"
import "src:core/node"
import "src:core/painter"
import "src:ui/text_node"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Button

Button_Style :: struct {
    using base: node.Style,
    hover:      Color,
    pressed:    Color,
}

Button :: struct {
    using node: Node,
    style: proc(self: ^Button) -> ^Button_Style,

    // Fired on a click.
    onclick: proc(self: ^Button),

    set_text: proc(self: ^Button, text: string),

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
    n.set_text = _set_text

    n->on(events.MOUSE_ENTER_EVENT, _on_enter)
    n->on(events.MOUSE_LEAVE_EVENT, _on_leave)
    n->on(events.MOUSE_DOWN_EVENT, _on_down)
    n->on(events.MOUSE_UP_EVENT, _on_up)
    n->on(events.MOUSE_CLICK_EVENT, _on_click)
    n->on(events.KEY_DOWN_EVENT, _on_key)
    n.focusable = true
    return n
}

// The label `New` was given: the first text child, added if there is none yet.
@(private="file")
_set_text :: proc(n: ^Button, text: string) {
    for child in n.children {
        if child.type_id != typeid_of(text_node.Text_Node) do continue
        (cast(^text_node.Text_Node)child)->set_text(text)
        return
    }
    if text != "" do n->add(text_node.New(text))
}

@(private="file")
_on_key :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    e := cast(^events.Key_Event)s.data
    if s.target != s.current_target || e.repeat do return
    if e.code != .Enter && e.code != .Space && e.code != .KP_Enter do return
    if n.onclick != nil do n->onclick()
    events.prevent_default(s)
}

@(private="file")
_apply_defaults :: proc(n: ^Button) {
    s := n->style()
    s->set_flex_direction(.Row)
    s->set_justify_content(.Center)
    s->set_align_items(.Center)
    s->set_flex_shrink(0)
    s->set_padding_inline(16)
    s->set_padding_block(8)
    s->set_user_select(.None)
    // primary-foreground: neutral-900 on the light primary fill.
    if s->get_color() == {} do s->set_color({23, 23, 23, 255})
}

@(private="file")
_get_style :: proc(n: ^Button) -> ^Button_Style {
    n->damage()
    return auto_cast(n._internal_style)
}

@(private="file")
_from_signal :: proc(s: ^events.Event_Signal) -> ^Button {
    return auto_cast(s.current_target)
}

// The background follows these two, and nothing else says the button looks different.
@(private="file")
_show :: proc(n: ^Button, hovered, pressed: bool) {
    if n._hovered == hovered && n._pressed == pressed do return
    n->damage()
    n._hovered, n._pressed = hovered, pressed
}

@(private="file")
_on_enter :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    _show(n, true, n._pressed)
}

@(private="file")
_on_leave :: proc(s: ^events.Event_Signal) {
    _show(_from_signal(s), false, false)
}

@(private="file")
_on_down :: proc(s: ^events.Event_Signal) {
    e := cast(^events.Mouse_Event)s.data
    if e.button != 0 do return
    n := _from_signal(s)
    _show(n, n._hovered, true)
}

@(private="file")
_on_up :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    _show(n, n._hovered, false)
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
    radius := node.Resolve_Corner_Radius(n)
    p := painter.get()
    painter.decoration_under(p, n.rect, radius, st.decoration)
    painter.rect(p, n.rect, bg, radius)
    painter.decoration_fill(p, n.rect, radius, st.decoration)
    painter.border_sides(p, n.rect, st.border_color, st.border_width, radius)
    painter.decoration_over(p, n.rect, radius, st.decoration)
}

@(private="file")
_free :: proc(n: ^Button) {
    free(n._internal_style)
    free(n.data)
}
