package scroll_area

import "src:core/common"
import "src:core/events"
import "src:core/input"
import "src:core/node"
import "src:ui/box"
import "core:time"

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
    vertical:       Scroll_Bar_Mode,
    horizontal:     Scroll_Bar_Mode,
}

Scroll_Area :: struct {
    using base: Node,
    style: proc(self: ^Scroll_Area) -> ^Scroll_Area_Style,

    // Children added to a Scroll_Area are placed in this content node.
    content: ^node.Node,

    scroll_x, scroll_y:         f32,
    max_scroll_x, max_scroll_y: f32,

    scroll_to: proc(self: ^Scroll_Area, x, y: f32),
    scroll_by: proc(self: ^Scroll_Area, dx, dy: f32),

    _v_track, _v_thumb: ^box.Box,
    _h_track, _h_thumb: ^box.Box,
    _drag_axis:          _Axis,
    _drag_pointer:       f32,
    _drag_scroll:        f32,
    _track_axis:         _Axis,
    _track_direction:    f32,
    _track_pointer:      [2]f32,
    _track_started:      time.Tick,
    _track_last:         time.Tick,
}

@(private="file")
_Axis :: enum {
    None,
    Horizontal,
    Vertical,
}

New :: proc(style: Scroll_Area_Style = {}, key: Maybe(string) = nil) -> ^Scroll_Area {
    n := new(Scroll_Area)
    node.Init(auto_cast(n), key)

    st := style
    if st.scrollbar_size <= 0 do st.scrollbar_size = 15
    if st.min_thumb_size <= 0 do st.min_thumb_size = 18
    if st.thumb_inset <= 0 do st.thumb_inset = 3
    if st.thumb_radius <= 0 do st.thumb_radius = 4
    if st.track_color == {} do st.track_color = {241, 241, 241, 255}
    if st.thumb_color == {} do st.thumb_color = {193, 193, 193, 255}
    if st.thumb_hover == {} do st.thumb_hover = {168, 168, 168, 255}
    if st.thumb_pressed == {} do st.thumb_pressed = {120, 120, 120, 255}

    n.style = _get_style
    node.Set_Style(auto_cast(n), new_clone(st))
    node.Init_Style(auto_cast(n))
    n->style()->set_overflow(.Auto)

    n.content = node.New("content")
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

    n->add(n.content, n._v_track, n._h_track)
    n.add = _add

    n.scroll_to = _scroll_to
    n.scroll_by = _scroll_by
    n.process = transmute(proc(self: ^Node))_process
    n.on_free = transmute(proc(self: ^Node))_free

    n->on("wheel", _on_wheel)
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
    return n
}

@(private="file")
_get_style :: proc(n: ^Scroll_Area) -> ^Scroll_Area_Style {
    return auto_cast(n._internal_style)
}

@(private="file")
_add :: proc(self: ^Node, kids: ..^Node) -> ^Node {
    n: ^Scroll_Area = auto_cast(self)
    n.content->add(..kids)
    return self
}

@(private="file")
_clamp_offsets :: proc(n: ^Scroll_Area) {
    n.scroll_x = clamp(n.scroll_x, 0, n.max_scroll_x)
    n.scroll_y = clamp(n.scroll_y, 0, n.max_scroll_y)
}

@(private="file")
_scroll_to :: proc(n: ^Scroll_Area, x, y: f32) {
    n.scroll_x = x
    n.scroll_y = y
    _clamp_offsets(n)
}

@(private="file")
_scroll_by :: proc(n: ^Scroll_Area, dx, dy: f32) {
    _scroll_to(n, n.scroll_x + dx, n.scroll_y + dy)
}

@(private="file")
_content_extent :: proc(n: ^Node, right, bottom: ^f32) {
    right^ = max(right^, n.rect.x + n.rect.w)
    bottom^ = max(bottom^, n.rect.y + n.rect.h)
    for c in n.children do _content_extent(c, right, bottom)
}

@(private="file")
_is_visible :: proc(mode: Scroll_Bar_Mode, maximum: f32) -> bool {
    switch mode {
    case .Auto:   return maximum > 0.5
    case .Always: return true
    case .Hidden: return false
    }
    return false
}

@(private="file")
_set_overlay_rects :: proc(n: ^Scroll_Area, viewport: common.Rect) {
    st := n->style()
    size := st.scrollbar_size
    inset := min(st.thumb_inset, size * 0.5)
    show_v := _is_visible(st.vertical, n.max_scroll_y)
    show_h := _is_visible(st.horizontal, n.max_scroll_x)

    n._v_track.rect = {viewport.x + viewport.w - size, viewport.y, size, viewport.h - (show_h ? size : 0)}
    n._h_track.rect = {viewport.x, viewport.y + viewport.h - size, viewport.w - (show_v ? size : 0), size}

    v_len := n._v_track.rect.h
    v_thumb := v_len
    if n.max_scroll_y > 0 {
        content_h := viewport.h + n.max_scroll_y
        v_thumb = clamp(v_len * viewport.h / content_h, min(st.min_thumb_size, v_len), v_len)
    }
    v_travel := max(v_len - v_thumb, 0)
    v_pos: f32 = 0
    if n.max_scroll_y > 0 do v_pos = v_travel * n.scroll_y / n.max_scroll_y
    n._v_thumb.rect = {n._v_track.rect.x + inset, n._v_track.rect.y + v_pos, max(size - inset * 2, 0), v_thumb}

    h_len := n._h_track.rect.w
    h_thumb := h_len
    if n.max_scroll_x > 0 {
        content_w := viewport.w + n.max_scroll_x
        h_thumb = clamp(h_len * viewport.w / content_w, min(st.min_thumb_size, h_len), h_len)
    }
    h_travel := max(h_len - h_thumb, 0)
    h_pos: f32 = 0
    if n.max_scroll_x > 0 do h_pos = h_travel * n.scroll_x / n.max_scroll_x
    n._h_thumb.rect = {n._h_track.rect.x + h_pos, n._h_track.rect.y + inset, h_thumb, max(size - inset * 2, 0)}

    // Hidden nodes get an empty hit box as well as an empty draw box.
    if !show_v {
        n._v_track.rect = {}
        n._v_thumb.rect = {}
    }
    if !show_h {
        n._h_track.rect = {}
        n._h_thumb.rect = {}
    }
}

@(private="file")
_process :: proc(n: ^Scroll_Area) {
    viewport := n.rect
    border := n->get_rect(.Border)
    padding := n->get_rect(.Padding)
    viewport.x += padding.x - border.x
    viewport.y += padding.y - border.y
    viewport.w = padding.w
    viewport.h = padding.h

    right := n.content.rect.x + n.content.rect.w
    bottom := n.content.rect.y + n.content.rect.h
    _content_extent(n.content, &right, &bottom)
    n.max_scroll_x = max(right - (viewport.x + viewport.w), 0)
    n.max_scroll_y = max(bottom - (viewport.y + viewport.h), 0)
    _clamp_offsets(n)
    _set_overlay_rects(n, viewport)
    _advance_track_scroll(n)
    n.content.transform.translate = {-n.scroll_x, -n.scroll_y}
    _set_overlay_rects(n, viewport)
}

@(private="file")
_page_step :: proc(n: ^Scroll_Area, axis: _Axis) -> f32 {
    length := n._v_track.rect.h if axis == .Vertical else n._h_track.rect.w
    return max(length * 0.875, length - 40, 1)
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
    delta := n._track_direction * _page_step(n, n._track_axis) * 20 * f32(min(dt, 0.05))
    if n._track_axis == .Vertical {
        n->scroll_by(0, delta)
    } else {
        n->scroll_by(delta, 0)
    }
}

@(private="file")
_area_from_signal :: proc(s: ^events.Signal) -> ^Scroll_Area {
    return auto_cast(s.current_target)
}

@(private="file")
_on_wheel :: proc(s: ^events.Signal) {
    n := _area_from_signal(s)
    e := cast(^events.Wheel_Event)s.data
    old_x, old_y := n.scroll_x, n.scroll_y
    dx, dy := -e.delta_x, -e.delta_y
    dx = clamp(dx, -n.rect.w, n.rect.w)
    dy = clamp(dy, -n.rect.h, n.rect.h)
    n->scroll_by(dx, dy)
    if n.scroll_x != old_x || n.scroll_y != old_y {
        events.prevent_default(s)
        events.stop_propagation(s)
    }
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
_on_thumb_down :: proc(s: ^events.Signal) {
    thumb := cast(^Node)s.current_target
    n, axis := _track_area(thumb)
    if n == nil do return
    e := cast(^events.Mouse_Event)s.data
    n._drag_axis = axis
    n._drag_pointer = e.y if axis == .Vertical else e.x
    n._drag_scroll = n.scroll_y if axis == .Vertical else n.scroll_x
    if axis == .Vertical {
        n._v_thumb->style().background = n->style().thumb_pressed
    } else {
        n._h_thumb->style().background = n->style().thumb_pressed
    }
    input.capture_pointer(auto_cast(n))
    events.stop_propagation(s)
    events.prevent_default(s)
}

@(private="file")
_on_track_down :: proc(s: ^events.Signal) {
    track := cast(^Node)s.current_target
    n, axis := _track_area(track)
    if n == nil do return
    e := cast(^events.Mouse_Event)s.data
    pointer := e.y if axis == .Vertical else e.x
    thumb_start := n._v_thumb.rect.y if axis == .Vertical else n._h_thumb.rect.x
    thumb_length := n._v_thumb.rect.h if axis == .Vertical else n._h_thumb.rect.w
    track_start := n._v_track.rect.y if axis == .Vertical else n._h_track.rect.x
    track_length := n._v_track.rect.h if axis == .Vertical else n._h_track.rect.w
    maximum := n.max_scroll_y if axis == .Vertical else n.max_scroll_x

    if .Shift in e.mods {
        travel := max(track_length - thumb_length, 0)
        offset := clamp(pointer - track_start - thumb_length * 0.5, 0, travel)
        value: f32 = 0
        if travel > 0 do value = offset * maximum / travel
        if axis == .Vertical {
            n->scroll_to(n.scroll_x, value)
        } else {
            n->scroll_to(value, n.scroll_y)
        }
        n._drag_axis = axis
        n._drag_pointer = pointer
        n._drag_scroll = value
        input.capture_pointer(auto_cast(n))
        events.stop_propagation(s)
        events.prevent_default(s)
        return
    }

    direction: f32 = -1 if pointer < thumb_start else 1
    if axis == .Vertical {
        n->scroll_by(0, direction * _page_step(n, axis))
    } else {
        n->scroll_by(direction * _page_step(n, axis), 0)
    }
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
_on_pointer_move :: proc(s: ^events.Signal) {
    n := _area_from_signal(s)
    e := cast(^events.Mouse_Event)s.data
    if n._track_axis != .None {
        n._track_pointer = {e.x, e.y}
        events.prevent_default(s)
        return
    }
    if n._drag_axis == .None do return
    if n._drag_axis == .Vertical {
        travel := n._v_track.rect.h - n._v_thumb.rect.h
        if travel > 0 do n->scroll_to(n.scroll_x, n._drag_scroll + (e.y - n._drag_pointer) * n.max_scroll_y / travel)
    } else {
        travel := n._h_track.rect.w - n._h_thumb.rect.w
        if travel > 0 do n->scroll_to(n._drag_scroll + (e.x - n._drag_pointer) * n.max_scroll_x / travel, n.scroll_y)
    }
    events.prevent_default(s)
}

@(private="file")
_on_pointer_up :: proc(s: ^events.Signal) {
    n := _area_from_signal(s)
    if n._drag_axis == .Vertical do n._v_thumb->style().background = n->style().thumb_color
    if n._drag_axis == .Horizontal do n._h_thumb->style().background = n->style().thumb_color
    n._drag_axis = .None
    n._track_axis = .None
    input.release_pointer()
    events.prevent_default(s)
}

@(private="file")
_on_thumb_enter :: proc(s: ^events.Signal) {
    thumb := cast(^box.Box)s.current_target
    n, _ := _track_area(auto_cast(thumb))
    if n != nil do thumb->style().background = n->style().thumb_hover
}

@(private="file")
_on_thumb_leave :: proc(s: ^events.Signal) {
    thumb := cast(^box.Box)s.current_target
    n, _ := _track_area(auto_cast(thumb))
    if n != nil do thumb->style().background = n->style().thumb_color
}

@(private="file")
_free :: proc(n: ^Scroll_Area) {
    free(n._internal_style)
}
