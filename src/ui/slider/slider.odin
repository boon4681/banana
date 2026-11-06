package slider

import "core:math"
import "src:core/common"
import "src:core/events"
import "src:core/hit_test"
import "src:core/input"
import "src:core/node"
import "src:core/painter"
import "src:ui/shared/theme"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Slider

Node  :: node.BaseNode
Color :: common.Color

TRACK :: f32(6)
THUMB :: f32(16)

Slider_Style :: struct {
    using base:   node.Style,
    track:        Color,
    range:        Color,
    thumb:        Color,
    thumb_border: Color,
}

Slider :: struct {
    using node: Node,
    style: proc(self: ^Slider) -> ^Slider_Style,

    value:    f32,
    min:      f32,
    max:      f32,
    step:     f32,
    disabled: bool,

    oninput: proc(self: ^Slider, value: f32),

    set_value: proc(self: ^Slider, value: f32),
    _dragging: bool,
}

New :: proc(style: Slider_Style = {}, key: Maybe(string) = nil) -> ^Slider {
    n := new(Slider)
    node.Init(n, key)
    n.max = 100

    st := style
    if st.track == {} do st.track = theme.MUTED
    if st.range == {} do st.range = theme.PRIMARY
    if st.thumb == {} do st.thumb = theme.FOREGROUND
    if st.thumb_border == {} do st.thumb_border = theme.PRIMARY

    n.style = _get_style
    node.Set_Style(auto_cast(n), new_clone(st))
    node.Init_Style(auto_cast(n))
    n->style()->set_width(200)->set_height(THUMB)->set_flex_shrink(0)->set_user_select(.None)

    n.set_value = _set_value
    n.draw = transmute(proc(self: ^Node))_draw
    n.on_free = transmute(proc(self: ^Node))_free
    n.focusable = true
    n->on(events.MOUSE_DOWN_EVENT, _on_down)
    n->on(events.MOUSE_MOVE_EVENT, _on_move)
    n->on(events.MOUSE_UP_EVENT, _on_up)
    n->on(events.KEY_DOWN_EVENT, _on_key)
    return n
}

@(private = "file")
_get_style :: proc(n: ^Slider) -> ^Slider_Style {
    n->damage()
    return auto_cast(n._internal_style)
}

@(private = "file")
_free :: proc(n: ^Slider) {
    free(n._internal_style)
}

@(private = "file")
_snap :: proc(n: ^Slider, value: f32) -> f32 {
    v := clamp(value, n.min, max(n.min, n.max))
    if n.step > 0 do v = n.min + math.round((v - n.min) / n.step) * n.step
    return clamp(v, n.min, max(n.min, n.max))
}

@(private = "file")
_set_value :: proc(n: ^Slider, value: f32) {
    next := _snap(n, value)
    if next != n.value do n->damage()
    n.value = next
}

@(private = "file")
_commit :: proc(n: ^Slider, value: f32) {
    next := _snap(n, value)
    if next == n.value do return
    n.value = next
    n->damage()
    if n.oninput != nil do n->oninput(next)
}

@(private = "file")
_at_pointer :: proc(n: ^Slider, e: ^events.Mouse_Event) {
    x, _ := hit_test.to_local(n, e.x, e.y)
    span := max(n.rect.w - THUMB, 1)
    _commit(n, n.min + clamp((x - n.rect.x - THUMB * 0.5) / span, 0, 1) * (n.max - n.min))
}

@(private = "file")
_on_down :: proc(s: ^events.Event_Signal) {
    n := cast(^Slider)s.current_target
    e := cast(^events.Mouse_Event)s.data
    if e.button != 0 || n.disabled do return
    n._dragging = true
    input.capture_pointer(auto_cast n)
    _at_pointer(n, e)
}

@(private = "file")
_on_move :: proc(s: ^events.Event_Signal) {
    n := cast(^Slider)s.current_target
    if n._dragging do _at_pointer(n, cast(^events.Mouse_Event)s.data)
}

@(private = "file")
_on_up :: proc(s: ^events.Event_Signal) {
    n := cast(^Slider)s.current_target
    if !n._dragging do return
    n._dragging = false
    input.release_pointer()
}

@(private = "file")
_on_key :: proc(s: ^events.Event_Signal) {
    n := cast(^Slider)s.current_target
    e := cast(^events.Key_Event)s.data
    if s.target != s.current_target || n.disabled do return
    unit := n.step if n.step > 0 else (n.max - n.min) / 100
    #partial switch e.code {
    case .Left, .Down: _commit(n, n.value - unit)
    case .Right, .Up: _commit(n, n.value + unit)
    case .Home: _commit(n, n.min)
    case .End: _commit(n, n.max)
    case: return
    }
    events.prevent_default(s)
}

@(private = "file")
_draw :: proc(n: ^Slider) {
    st := n->style()
    p := painter.get()
    r := n.rect
    track, range, thumb, ring := st.track, st.range, st.thumb, st.thumb_border
    if n.disabled {
        track.a /= 2
        range.a /= 2
        thumb.a /= 2
        ring.a /= 2
    }
    amount := (n.value - n.min) / (n.max - n.min) if n.max > n.min else 0
    center := r.x + THUMB * 0.5 + clamp(amount, 0, 1) * max(r.w - THUMB, 0)
    line := common.Rect{r.x, r.y + (r.h - TRACK) * 0.5, r.w, TRACK}
    painter.rect(p, line, track, TRACK / 2)
    painter.rect(p, {line.x, line.y, center - line.x, TRACK}, range, TRACK / 2)
    knob := common.Rect{center - THUMB * 0.5, r.y + (r.h - THUMB) * 0.5, THUMB, THUMB}
    painter.decoration_under(p, knob, THUMB / 2, st.decoration)
    painter.rect(p, knob, thumb, THUMB / 2)
    painter.border(p, knob, ring, 1, THUMB / 2)
    painter.decoration_over(p, knob, THUMB / 2, st.decoration)
}
