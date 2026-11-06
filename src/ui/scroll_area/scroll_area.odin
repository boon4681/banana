package scroll_area

import "src:core/common"
import "src:core/events"
import "src:core/input"
import "src:core/node"
import "src:core/scroll"
import "src:ui/box"
import "src:ui/svg_node"
import "core:time"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Scroll_Area

@(private="file") ARROW_REPEAT_DELAY :: 0.25
@(private="file") ARROW_REPEAT_RATE :: 0.05

Scroll_Bar_Mode :: enum {
    Auto,
    Always,
    Hidden,
}

Scroll_Area_Style :: struct {
    using base: node.Style,
    scrollbar_size: f32,
    min_thumb_size: f32,
    thumb_inset:    f32,
    thumb_radius:   f32,
    track_color:    Color,
    thumb_color:    Color,
    thumb_hover:    Color,
    thumb_pressed:  Color,
    button_color:   Color,
    button_hover:   Color,
    button_pressed: Color,
    arrow_color:    Color,
    arrow_hover:    Color,
    vertical:       Scroll_Bar_Mode,
    horizontal:     Scroll_Bar_Mode,
}

// Offset and range live on the port: `scroll.to`, `scroll.by`, `scroll.offset` and
// `scroll.range` take the area.
Scroll_Area :: struct {
    using base: Node,
    style: proc(self: ^Scroll_Area) -> ^Scroll_Area_Style,

    // Children added to a Scroll_Area are placed in this content node.
    content: ^node.Node,

    _port:     node.Scroll_Port, // on `content`, whose children scroll
    _own_port: node.Scroll_Port, // on the area: it scrolls nothing itself

    _v_track, _v_thumb: ^box.Box,
    _h_track, _h_thumb: ^box.Box,
    _arrow_up:          _Arrow,
    _arrow_down:        _Arrow,
    _arrow_left:        _Arrow,
    _arrow_right:       _Arrow,
    _drag_axis:         _Axis,
    _drag_grab:         f32,
    _track_axis:        _Axis,
    _track_direction:   f32,
    _track_pointer:     [2]f32,
    _track_started:     time.Tick,
    _track_last:        time.Tick,
    _arrow_axis:        _Axis,
    _arrow_direction:   f32,
    _arrow_started:     time.Tick,
    _arrow_last:        time.Tick,
    _arrow_stepped:     bool,
}

@(private="file")
_Arrow :: struct {
    btn:   ^box.Box,
    glyph: ^svg_node.SVG_Node,
    axis:  _Axis,
    dir:   f32,
}

@(private="file")
_Axis :: enum {
    None,
    Horizontal,
    Vertical,
}

New :: proc(style: Scroll_Area_Style = {}, key: Maybe(string) = nil) -> ^Scroll_Area {
    n := new(Scroll_Area)
    node.Init(n, key)

    st := style
    if st.scrollbar_size <= 0 do st.scrollbar_size = 15
    if st.min_thumb_size <= 0 do st.min_thumb_size = 18
    if st.thumb_inset <= 0 do st.thumb_inset = 2
    if st.thumb_radius <= 0 do st.thumb_radius = 0
    if st.track_color == {} do st.track_color = {40, 40, 40, 255}
    if st.thumb_color == {} do st.thumb_color = {96, 96, 96, 255}
    if st.thumb_hover == {} do st.thumb_hover = {128, 128, 128, 255}
    if st.thumb_pressed == {} do st.thumb_pressed = {160, 160, 160, 255}
    if st.button_color == {} do st.button_color = {40, 40, 40, 255}
    if st.button_hover == {} do st.button_hover = {64, 64, 64, 255}
    if st.button_pressed == {} do st.button_pressed = {80, 80, 80, 255}
    if st.arrow_color == {} do st.arrow_color = {160, 160, 160, 255}
    if st.arrow_hover == {} do st.arrow_hover = {225, 225, 225, 255}

    n.style = _get_style
    node.Set_Style(auto_cast(n), new_clone(st))
    node.Init_Style(auto_cast(n))
    n.scroll = &n._own_port
    n._own_port.update = _update
    n->style()->set_overflow(.Auto)

    n.content = node.New("content")
    n.content.scroll = &n._port
    n._own_port.inner = n.content
    n._port.move = scroll.move_clamped
    n.content->on(events.KEY_DOWN_EVENT, scroll.on_key)
    n.content->on(events.FOCUS_EVENT, scroll.on_focus)
    n.content->style()->
        set_flex_direction(.Column)->
        set_align_items(.Stretch)->
        set_flex_shrink(0)->
        set_width(100, node.percent)

    n._v_track = box.New({background = st.track_color}, "vertical-scrollbar")
    n._v_thumb = box.New({background = st.thumb_color, radius = st.thumb_radius}, "thumb")
    n._h_track = box.New({background = st.track_color}, "horizontal-scrollbar")
    n._h_thumb = box.New({background = st.thumb_color, radius = st.thumb_radius}, "thumb")
    n._v_track.z_index = 1
    n._h_track.z_index = 1
    n._v_track->add(n._v_thumb)
    n._h_track->add(n._h_thumb)

    n._arrow_up = _make_arrow(ICON_UP, .Vertical, -1, st.button_color, st.arrow_color)
    n._arrow_down = _make_arrow(ICON_DOWN, .Vertical, 1, st.button_color, st.arrow_color)
    n._arrow_left = _make_arrow(ICON_LEFT, .Horizontal, -1, st.button_color, st.arrow_color)
    n._arrow_right = _make_arrow(ICON_RIGHT, .Horizontal, 1, st.button_color, st.arrow_color)
    n._v_track->add(n._arrow_up.btn, n._arrow_down.btn)
    n._h_track->add(n._arrow_left.btn, n._arrow_right.btn)

    n->add(n.content, n._v_track, n._h_track)
    n.add = _add

    n.process = transmute(proc(self: ^Node))_process
    n.on_free = transmute(proc(self: ^Node))_free

    n->on(events.MOUSE_WHEEL_EVENT, scroll.on_wheel)
    n._v_track->on(events.MOUSE_DOWN_EVENT, _on_track_down)
    n._h_track->on(events.MOUSE_DOWN_EVENT, _on_track_down)
    n._v_thumb->on(events.MOUSE_DOWN_EVENT, _on_thumb_down)
    n._h_thumb->on(events.MOUSE_DOWN_EVENT, _on_thumb_down)
    n->on(events.MOUSE_MOVE_EVENT, _on_pointer_move)
    n->on(events.MOUSE_UP_EVENT, _on_pointer_up)
    n._v_thumb->on(events.MOUSE_ENTER_EVENT, _on_thumb_enter)
    n._h_thumb->on(events.MOUSE_ENTER_EVENT, _on_thumb_enter)
    n._v_thumb->on(events.MOUSE_LEAVE_EVENT, _on_thumb_leave)
    n._h_thumb->on(events.MOUSE_LEAVE_EVENT, _on_thumb_leave)
    for a in ([]^_Arrow{&n._arrow_up, &n._arrow_down, &n._arrow_left, &n._arrow_right}) {
        a.btn->on(events.MOUSE_DOWN_EVENT, _on_arrow_down)
        a.btn->on(events.MOUSE_ENTER_EVENT, _on_arrow_enter)
        a.btn->on(events.MOUSE_LEAVE_EVENT, _on_arrow_leave)
    }
    return n
}

@(private="file")
_make_arrow :: proc(icon: string, axis: _Axis, dir: f32, bg, tint: Color) -> _Arrow {
    btn := box.New({background = bg}, "arrow")
    btn->style()->set_align_items(.Center)->set_justify_content(.Center)
    glyph, _ := svg_node.New(icon, {tint = tint, fit = .Meet}, "arrow-glyph")
    btn->add(glyph)
    return {btn = btn, glyph = glyph, axis = axis, dir = dir}
}

@(private="file")
_get_style :: proc(n: ^Scroll_Area) -> ^Scroll_Area_Style {
    n->damage()
    return auto_cast(n._internal_style)
}

@(private="file")
_add :: proc(self: ^Node, kids: ..^Node) -> ^Node {
    n: ^Scroll_Area = auto_cast(self)
    n.content->add(..kids)
    return self
}

@(private="file")
_scroll_along :: proc(n: ^Scroll_Area, axis: _Axis, delta: f32) {
    if axis == .Vertical {
        scroll.by(n, 0, delta)
    } else {
        scroll.by(n, delta, 0)
    }
}

@(private="file")
_set_along :: proc(n: ^Scroll_Area, axis: _Axis, value: f32) {
    if axis == .Vertical {
        scroll.to(n, n._port.offset.x, value)
    } else {
        scroll.to(n, value, n._port.offset.y)
    }
}

@(private="file")
_track_length :: proc(n: ^Scroll_Area, axis: _Axis) -> f32 {
    return n._v_track.rect.h if axis == .Vertical else n._h_track.rect.w
}

@(private="file")
_thumb_length :: proc(n: ^Scroll_Area, axis: _Axis) -> f32 {
    return n._v_thumb.rect.h if axis == .Vertical else n._h_thumb.rect.w
}

// The stretch of a track its thumb moves in: what the arrow buttons leave.
@(private="file")
_lane :: proc(n: ^Scroll_Area, axis: _Axis) -> (start, length: f32) {
    full := _track_length(n, axis)
    arrow := min((cast(^Scroll_Area_Style)n._internal_style).scrollbar_size, full * 0.5)
    start = n._v_track.rect.y if axis == .Vertical else n._h_track.rect.x
    return start + arrow, max(full - arrow * 2, 0)
}

@(private="file")
_is_visible :: proc(mode: Scroll_Bar_Mode, maximum: f32) -> bool {
    switch mode {
    case .Auto:   return maximum > 0
    case .Always: return true
    case .Hidden: return false
    }
    return false
}

@(private="file")
_set_overlay_rects :: proc(n: ^Scroll_Area, viewport: common.Rect) {
    // Runs every tick: reading through style() would paint every frame.
    st := cast(^Scroll_Area_Style)n._internal_style
    port := &n._port
    size := st.scrollbar_size
    inset := min(st.thumb_inset, size * 0.5)
    thick := max(size - inset * 2, 0)
    show_v := _is_visible(st.vertical, port.range.y)
    show_h := _is_visible(st.horizontal, port.range.x)

    n._v_track.rect = {viewport.x + viewport.w - size, viewport.y, size, viewport.h - (show_h ? size : 0)}
    n._h_track.rect = {viewport.x, viewport.y + viewport.h - size, viewport.w - (show_v ? size : 0), size}

    // Reserve square buttons at both ends.
    arrow := min(size, n._v_track.rect.h * 0.5)
    n._arrow_up.btn.rect = {n._v_track.rect.x, n._v_track.rect.y, size, arrow}
    n._arrow_down.btn.rect = {n._v_track.rect.x, n._v_track.rect.y + n._v_track.rect.h - arrow, size, arrow}
    h_arrow := min(size, n._h_track.rect.w * 0.5)
    n._arrow_left.btn.rect = {n._h_track.rect.x, n._h_track.rect.y, h_arrow, size}
    n._arrow_right.btn.rect = {n._h_track.rect.x + n._h_track.rect.w - h_arrow, n._h_track.rect.y, h_arrow, size}
    _center_glyph(&n._arrow_up, size)
    _center_glyph(&n._arrow_down, size)
    _center_glyph(&n._arrow_left, size)
    _center_glyph(&n._arrow_right, size)

    v_start, v_lane := _lane(n, .Vertical)
    v_thumb, v_at := scroll.thumb_span(v_lane, viewport.h, port.range.y, port.offset.y, st.min_thumb_size)
    n._v_thumb.rect = {n._v_track.rect.x + inset, v_start + v_at, thick, v_thumb}

    h_start, h_lane := _lane(n, .Horizontal)
    h_thumb, h_at := scroll.thumb_span(h_lane, viewport.w, port.range.x, port.offset.x, st.min_thumb_size)
    n._h_thumb.rect = {h_start + h_at, n._h_track.rect.y + inset, h_thumb, thick}

    // Hidden nodes get an empty hit box as well as an empty draw box.
    if !show_v {
        n._v_track.rect = {}
        n._v_thumb.rect = {}
        n._arrow_up.btn.rect = {}
        n._arrow_down.btn.rect = {}
        n._arrow_up.glyph.rect = {}
        n._arrow_down.glyph.rect = {}
    }
    if !show_h {
        n._h_track.rect = {}
        n._h_thumb.rect = {}
        n._arrow_left.btn.rect = {}
        n._arrow_right.btn.rect = {}
        n._arrow_left.glyph.rect = {}
        n._arrow_right.glyph.rect = {}
    }
}

@(private="file")
_center_glyph :: proc(a: ^_Arrow, size: f32) {
    // Oversize the chevron's sparse viewBox.
    glyph := size
    b := a.btn.rect
    a.glyph.rect = {b.x + (b.w - glyph) * 0.5, b.y + (b.h - glyph) * 0.5, glyph, glyph}
}

// Layout caches every rect again each frame and after a scroll, which drops where the bars were put.
@(private="file")
_update :: proc(self: ^Node, laid_out: bool) {
    n := cast(^Scroll_Area)self
    port := &n._port
    viewport := scroll.padding_box(n)
    if laid_out {
        inner := n.content.rect
        end := scroll.content_end(n.content, {inner.x + inner.w, inner.y + inner.h}, port.applied)
        scroll.set_range(port, {end.x - (viewport.x + viewport.w), end.y - (viewport.y + viewport.h)})
    }
    _set_overlay_rects(n, viewport)

    st := cast(^Scroll_Area_Style)n._internal_style
    shown := viewport
    if _is_visible(st.vertical, port.range.y) do shown.w -= st.scrollbar_size
    if _is_visible(st.horizontal, port.range.x) do shown.h -= st.scrollbar_size
    port.viewport = shown
    n._own_port.viewport = viewport
}

@(private="file")
_process :: proc(n: ^Scroll_Area) {
    if n._track_axis == .None && n._arrow_axis == .None do return
    // Runs before `_update`: the held repeat reads where the bars are.
    _set_overlay_rects(n, scroll.padding_box(n))
    _advance_track_scroll(n)
    _advance_arrow_scroll(n)
}

@(private="file")
_advance_arrow_scroll :: proc(n: ^Scroll_Area) {
    if n._arrow_axis == .None do return
    now := time.tick_now()
    if time.duration_seconds(time.tick_diff(n._arrow_started, now)) < ARROW_REPEAT_DELAY {
        return
    }
    if time.duration_seconds(time.tick_diff(n._arrow_last, now)) < ARROW_REPEAT_RATE {
        return
    }
    n._arrow_last = now
    _scroll_along(n, n._arrow_axis, n._arrow_direction * scroll.LINE_STEP)
}

@(private="file")
_page_step :: proc(n: ^Scroll_Area, axis: _Axis) -> f32 {
    return max(scroll.page_step(_track_length(n, axis)), 1)
}

@(private="file")
_track_pointer_is_active :: proc(n: ^Scroll_Area) -> bool {
    if n._track_axis == .Vertical {
        if n._track_direction > 0 do return n._track_pointer.y >= n._v_thumb.rect.y + n._v_thumb.rect.h
        return n._track_pointer.y < n._v_thumb.rect.y
    }
    if n._track_axis == .Horizontal {
        if n._track_direction > 0 do return n._track_pointer.x >= n._h_thumb.rect.x + n._h_thumb.rect.w
        return n._track_pointer.x < n._h_thumb.rect.x
    }
    return false
}

@(private="file")
_advance_track_scroll :: proc(n: ^Scroll_Area) {
    if n._track_axis == .None do return
    now := time.tick_now()
    if !_track_pointer_is_active(n) {
        n._track_last = now
        return
    }
    if time.duration_seconds(time.tick_diff(n._track_started, now)) < 0.25 {
        n._track_last = now
        return
    }
    dt := time.duration_seconds(time.tick_diff(n._track_last, now))
    n._track_last = now
    _scroll_along(n, n._track_axis, n._track_direction * _page_step(n, n._track_axis) * 20 * f32(min(dt, 0.05)))
}

@(private="file")
_area_from_signal :: proc(s: ^events.Event_Signal) -> ^Scroll_Area {
    return auto_cast(s.current_target)
}

@(private="file")
_track_area :: proc(target: ^Node) -> (^Scroll_Area, _Axis) {
    if target == nil || target.parent == nil do return nil, .None
    track := target
    if track.parent.parent != nil {
        if track.parent.key == "vertical-scrollbar" || track.parent.key == "horizontal-scrollbar" do track = track.parent
    }
    if track.parent == nil do return nil, .None
    n: ^Scroll_Area = auto_cast(track.parent)
    if track == auto_cast(n._v_track) do return n, .Vertical
    if track == auto_cast(n._h_track) do return n, .Horizontal
    return nil, .None
}

@(private="file")
_on_thumb_down :: proc(s: ^events.Event_Signal) {
    thumb := cast(^Node)s.current_target
    n, axis := _track_area(thumb)
    if n == nil do return
    e := cast(^events.Mouse_Event)s.data
    n._drag_axis = axis
    if axis == .Vertical {
        n._drag_grab = e.y - n._v_thumb.rect.y
        n._v_thumb->style().background = n->style().thumb_pressed
    } else {
        n._drag_grab = e.x - n._h_thumb.rect.x
        n._h_thumb->style().background = n->style().thumb_pressed
    }
    input.capture_pointer(auto_cast(n))
    events.stop_propagation(s)
    events.prevent_default(s)
}

@(private="file")
_drag_to :: proc(n: ^Scroll_Area, axis: _Axis, pointer: f32) {
    start, length := _lane(n, axis)
    travel := length - _thumb_length(n, axis)
    if travel <= 0 do return
    range := n._port.range.y if axis == .Vertical else n._port.range.x
    _set_along(n, axis, scroll.offset_at(pointer - n._drag_grab - start, travel, range))
}

@(private="file")
_on_track_down :: proc(s: ^events.Event_Signal) {
    track := cast(^Node)s.current_target
    n, axis := _track_area(track)
    if n == nil do return
    e := cast(^events.Mouse_Event)s.data
    pointer := e.y if axis == .Vertical else e.x

    if .Shift in e.mods {
        n._drag_axis = axis
        n._drag_grab = _thumb_length(n, axis) * 0.5
        _drag_to(n, axis, pointer)
        input.capture_pointer(auto_cast(n))
        events.stop_propagation(s)
        events.prevent_default(s)
        return
    }

    thumb_start := n._v_thumb.rect.y if axis == .Vertical else n._h_thumb.rect.x
    direction: f32 = -1 if pointer < thumb_start else 1
    _scroll_along(n, axis, direction * _page_step(n, axis))
    n._track_axis = axis
    n._track_direction = direction
    n._track_pointer = {e.x, e.y}
    n._track_started = time.tick_now()
    n._track_last = n._track_started
    input.capture_pointer(auto_cast(n))
    events.stop_propagation(s)
    events.prevent_default(s)
}

@(private="file")
_on_pointer_move :: proc(s: ^events.Event_Signal) {
    n := _area_from_signal(s)
    e := cast(^events.Mouse_Event)s.data
    if n._track_axis != .None {
        n._track_pointer = {e.x, e.y}
        events.prevent_default(s)
        return
    }
    if n._drag_axis == .None do return
    _drag_to(n, n._drag_axis, e.y if n._drag_axis == .Vertical else e.x)
    events.prevent_default(s)
}

@(private="file")
_on_pointer_up :: proc(s: ^events.Event_Signal) {
    n := _area_from_signal(s)
    if n._drag_axis == .Vertical do n._v_thumb->style().background = n->style().thumb_color
    if n._drag_axis == .Horizontal do n._h_thumb->style().background = n->style().thumb_color
    if n._arrow_axis != .None {
        for a in ([]^_Arrow{&n._arrow_up, &n._arrow_down, &n._arrow_left, &n._arrow_right}) {
            a.btn->style().background = n->style().button_color
            a.glyph->style().tint = n->style().arrow_color
        }
    }
    n._drag_axis = .None
    n._track_axis = .None
    n._arrow_axis = .None
    input.release_pointer()
    events.prevent_default(s)
}

@(private="file")
_arrow_from_btn :: proc(n: ^Scroll_Area, btn: ^box.Box) -> ^_Arrow {
    switch btn {
    case n._arrow_up.btn:    return &n._arrow_up
    case n._arrow_down.btn:  return &n._arrow_down
    case n._arrow_left.btn:  return &n._arrow_left
    case n._arrow_right.btn: return &n._arrow_right
    }
    return nil
}

@(private="file")
_area_from_arrow :: proc(btn: ^Node) -> ^Scroll_Area {
    if btn == nil || btn.parent == nil || btn.parent.parent == nil do return nil
    return auto_cast(btn.parent.parent)
}

@(private="file")
_on_arrow_down :: proc(s: ^events.Event_Signal) {
    btn := cast(^box.Box)s.current_target
    n := _area_from_arrow(auto_cast(btn))
    if n == nil do return
    a := _arrow_from_btn(n, btn)
    if a == nil do return
    e := cast(^events.Mouse_Event)s.data
    if e.button != 0 do return

    _scroll_along(n, a.axis, a.dir * scroll.LINE_STEP)
    n._arrow_axis = a.axis
    n._arrow_direction = a.dir
    n._arrow_started = time.tick_now()
    n._arrow_last = n._arrow_started
    a.btn->style().background = n->style().button_pressed
    a.glyph->style().tint = n->style().arrow_hover
    input.capture_pointer(auto_cast(n))
    events.stop_propagation(s)
    events.prevent_default(s)
}

@(private="file")
_on_arrow_enter :: proc(s: ^events.Event_Signal) {
    btn := cast(^box.Box)s.current_target
    n := _area_from_arrow(auto_cast(btn))
    if n == nil do return
    if a := _arrow_from_btn(n, btn); a != nil {
        a.btn->style().background = n->style().button_hover
        a.glyph->style().tint = n->style().arrow_hover
    }
}

@(private="file")
_on_arrow_leave :: proc(s: ^events.Event_Signal) {
    btn := cast(^box.Box)s.current_target
    n := _area_from_arrow(auto_cast(btn))
    if n == nil do return
    if a := _arrow_from_btn(n, btn); a != nil {
        a.btn->style().background = n->style().button_color
        a.glyph->style().tint = n->style().arrow_color
    }
}

@(private="file")
_on_thumb_enter :: proc(s: ^events.Event_Signal) {
    thumb := cast(^box.Box)s.current_target
    n, _ := _track_area(auto_cast(thumb))
    if n != nil do thumb->style().background = n->style().thumb_hover
}

@(private="file")
_on_thumb_leave :: proc(s: ^events.Event_Signal) {
    thumb := cast(^box.Box)s.current_target
    n, _ := _track_area(auto_cast(thumb))
    if n != nil do thumb->style().background = n->style().thumb_color
}

@(private="file")
_free :: proc(n: ^Scroll_Area) {
    free(n._internal_style)
}
