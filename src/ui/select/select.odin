package select

import "core:strings"
import "src:core/common"
import "src:core/events"
import "src:core/node"
import "src:core/painter"
import "src:ui/option"
import "src:ui/shared/popup"
import "src:ui/shared/theme"
import "src:ui/text_node"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Select

Node  :: node.BaseNode
Color :: common.Color

Select_Style :: struct {
    using base: node.Style,
}

Select :: struct {
    using node: Node,
    style: proc(self: ^Select) -> ^Select_Style,

    value:       string,
    placeholder: string,
    disabled:    bool,

    oninput: proc(self: ^Select, value: string),

    set_value: proc(self: ^Select, value: string),

    _owned: string,
    _label: ^text_node.Text_Node,
    _shown: string,
}

New :: proc(style: Select_Style = {}, key: Maybe(string) = nil) -> ^Select {
    n := new(Select)
    node.Init(n, key)

    st := style
    if st.background == {} do st.background = theme.INPUT_FILL
    if st.border_color == {} do st.border_color = theme.INPUT
    if st.border_width == 0 do st.border_width = 1
    if st.radius == 0 do st.radius = theme.RADIUS

    n.style = _get_style
    node.Set_Style(auto_cast(n), new_clone(st))
    node.Init_Style(auto_cast(n))
    s := n->style()
    s->set_flex_direction(.Row)->set_align_items(.Center)->set_flex_wrap(.NoWrap)->set_flex_shrink(0)
    s->set_height(36)->set_min_width(140)->set_padding_left(12)->set_padding_right(32)
    s->set_user_select(.None)
    if s->get_color() == {} do s->set_color(theme.FOREGROUND)

    n._label = text_node.New("")
    n->add(n._label)

    n.set_value = _set_value
    n.draw = transmute(proc(self: ^Node))_draw
    n.on_free = transmute(proc(self: ^Node))_free
    n.focusable = true
    n->on(events.MOUSE_CLICK_EVENT, _on_click)
    n->on(events.KEY_DOWN_EVENT, _on_key)
    return n
}

@(private = "file")
_get_style :: proc(n: ^Select) -> ^Select_Style {
    n->damage()
    return auto_cast(n._internal_style)
}

@(private = "file")
_free :: proc(n: ^Select) {
    if popup.is_open(n) do popup.close()
    delete(n._owned)
    delete(n._shown)
    free(n._internal_style)
}

// `children` already holds the members of every `if`, `for` and component
// written inside the select, so its options are all found at this one level.
@(private = "file")
_options :: proc(n: ^Select) -> []^option.Option {
    found := make([dynamic]^option.Option, context.temp_allocator)
    for child in n.children {
        if child.type_id == typeid_of(option.Option) do append(&found, cast(^option.Option)child)
    }
    return found[:]
}

// Kept as given even when no option matches: a bound value arrives before the options are added.
@(private = "file")
_set_value :: proc(n: ^Select, value: string) {
    if value == n.value do return
    kept := strings.clone(value)
    delete(n._owned)
    n._owned = kept
    n.value = kept
    n->damage()
}

@(private = "file")
_picked :: proc(owner: ^Node, index: int) {
    n := cast(^Select)owner
    options := _options(n)
    if index < 0 || index >= len(options) do return
    _set_value(n, option.value(options[index]))
    if n.oninput != nil do n->oninput(n.value)
}

@(private = "file")
_toggle :: proc(n: ^Select) {
    if n.disabled do return
    if popup.is_open(n) {
        popup.close()
        return
    }
    options := _options(n)
    labels := make([]string, len(options), context.temp_allocator)
    selected := -1
    for o, i in options {
        labels[i] = option.label(o)
        if selected < 0 && option.value(o) == n.value do selected = i
    }
    popup.open(n, n.rect.x, n.rect.y + n.rect.h + 4, n.rect.w, labels, selected, _picked, n.rect.h + 8)
}

@(private = "file")
_on_click :: proc(s: ^events.Event_Signal) {
    e := cast(^events.Mouse_Event)s.data
    if e.button == 0 do _toggle(auto_cast(s.current_target))
}

@(private = "file")
_on_key :: proc(s: ^events.Event_Signal) {
    e := cast(^events.Key_Event)s.data
    if s.target != s.current_target || e.repeat do return
    if e.code != .Enter && e.code != .Space && e.code != .Down do return
    _toggle(auto_cast(s.current_target))
    events.prevent_default(s)
}

@(private = "file")
_draw :: proc(n: ^Select) {
    st := n->style()
    p := painter.get()
    text := n.placeholder
    for o in _options(n) {
        if option.value(o) == n.value {
            text = option.label(o)
            break
        }
    }
    if text != n._shown {
        delete(n._shown)
        n._shown = strings.clone(text)
        n._label->set_text(text)
    }
    radius := node.Resolve_Corner_Radius(n)
    painter.decoration_under(p, n.rect, radius, st.decoration)
    painter.rect(p, n.rect, st.background, radius)
    painter.decoration_fill(p, n.rect, radius, st.decoration)
    painter.border_sides(p, n.rect, st.border_color, st.border_width, radius)
    painter.decoration_over(p, n.rect, radius, st.decoration)

    x, y := n.rect.x + n.rect.w - 20, n.rect.y + n.rect.h * 0.5
    painter.line(p, {x - 4, y - 2}, {x, y + 2}, theme.MUTED_FOREGROUND, 1.5)
    painter.line(p, {x, y + 2}, {x + 4, y - 2}, theme.MUTED_FOREGROUND, 1.5)
}
