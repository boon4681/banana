package scroll

import "base:runtime"
import "src:core/common"
import "src:core/events"
import "src:core/input"
import "src:core/node"
import "src:core/painter"

Node :: node.BaseNode

LINE_STEP :: f32(40)
THUMB_MIN :: f32(24)

Look :: struct {
    thumb:  common.Color,
    track:  common.Color,
    size:   f32,
    hidden: bool,
}

DEFAULT_SIZE         :: f32(10)
DEFAULT_THUMB        :: common.Color{128, 128, 128, 120}
DEFAULT_THUMB_ACTIVE :: common.Color{128, 128, 128, 200}

@(private)
Scroller :: struct {
    using port: node.Scroll_Port,
    axes:   [2]bool,
    look:   Look,
    hot:    int,
    drag:   int,
    grab:   f32,
}

@(init, private)
_register :: proc "contextless" () {
    node.scrollable_changed = _changed
    input.Selection_Autoscroll = _follow_drag
}

// px per second, per px the pointer is past the edge
DRAG_SCROLL_RATE :: f32(12)
DRAG_SCROLL_MIN  :: f32(80)
DRAG_SCROLL_MAX  :: f32(1600)

@(private)
_follow_drag :: proc(im: ^input.Input_State, from: ^Node, seconds: f32) {
    past :: proc(at, low, high: f32) -> f32 {
        out := at - high if at > high else (at - low if at < low else 0)
        if out == 0 do return 0
        speed := clamp(abs(out) * DRAG_SCROLL_RATE, DRAG_SCROLL_MIN, DRAG_SCROLL_MAX)
        return speed if out > 0 else -speed
    }
    for at := from; at != nil; at = at.parent {
        port := at.scroll
        if port == nil || port.move == nil do continue
        view := port.viewport
        speed := [2]f32{past(im.mouse_x, view.x, view.x + view.w), past(im.mouse_y, view.y, view.y + view.h)}
        if speed == 0 do continue
        if to(at, port.offset.x + speed.x * seconds, port.offset.y + speed.y * seconds) do return
    }
}

// A port can belong to something else, as a scroll_area's does; only one drawn here is a Scroller.
@(private)
of :: proc(n: ^Node) -> ^Scroller {
    if n == nil || n.scroll == nil || n.scroll.draw != _draw do return nil
    return cast(^Scroller)n.scroll
}

@(private)
_changed :: proc(n: ^Node, x, y: bool) {
    s := of(n)
    if !x && !y {
        if s != nil do _detach(n, s)
        return
    }
    if s == nil {
        if n.scroll != nil do return
        s = new(Scroller, runtime.heap_allocator())
        s.hot, s.drag = -1, -1
        s.update, s.draw, s.move = _update, _draw, move_clamped
        n.scroll = &s.port
        n->on(events.MOUSE_WHEEL_EVENT, on_wheel)
        // Capture phase: the bars lie over children, which would take the press first.
        n->on(events.MOUSE_DOWN_EVENT, _on_down, true)
        n->on(events.MOUSE_MOVE_EVENT, _on_move, true)
        n->on(events.MOUSE_UP_EVENT, _on_up, true)
        n->on(events.MOUSE_LEAVE_EVENT, _on_leave, true)
        n->on(events.KEY_DOWN_EVENT, on_key)
        n->on(events.FOCUS_EVENT, on_focus)
        n->add_hook(.Before_Free, _freed)
    }
    s.axes = {x, y}
}

@(private)
_detach :: proc(n: ^Node, s: ^Scroller) {
    n->off(events.MOUSE_WHEEL_EVENT, on_wheel)
    n->off(events.MOUSE_DOWN_EVENT, _on_down)
    n->off(events.MOUSE_MOVE_EVENT, _on_move)
    n->off(events.MOUSE_UP_EVENT, _on_up)
    n->off(events.MOUSE_LEAVE_EVENT, _on_leave)
    n->off(events.KEY_DOWN_EVENT, on_key)
    n->off(events.FOCUS_EVENT, on_focus)
    n->remove_hook(.Before_Free, _freed)
    n.scroll = nil
    free(s, runtime.heap_allocator())
}

@(private)
_freed :: proc(n: ^Node, _: rawptr) {
    if s := of(n); s != nil {
        n.scroll = nil
        free(s, runtime.heap_allocator())
    }
}

move_clamped :: proc(n: ^Node, x, y: f32) {
    port := n.scroll
    port.offset = {clamp(x, 0, port.range.x), clamp(y, 0, port.range.y)}
}

@(private)
_holder :: proc(n: ^Node) -> ^Node {
    if n == nil || n.scroll == nil do return nil
    return n.scroll.inner if n.scroll.inner != nil else n
}

offset :: proc(n: ^Node) -> [2]f32 {
    holder := _holder(n)
    return holder.scroll.offset if holder != nil else {}
}

range :: proc(n: ^Node) -> [2]f32 {
    holder := _holder(n)
    return holder.scroll.range if holder != nil else {}
}

to :: proc(n: ^Node, x, y: f32) -> (moved: bool) {
    holder := _holder(n)
    if holder == nil || holder.scroll == nil || holder.scroll.move == nil do return false
    before := holder.scroll.offset
    holder.scroll.move(holder, x, y)
    moved = holder.scroll.offset != before
    if moved do holder->damage()
    return
}

by :: proc(n: ^Node, dx, dy: f32) -> (moved: bool) {
    at := offset(n)
    return to(n, at.x + dx, at.y + dy)
}

set_look :: proc(n: ^Node, look: Look) {
    s := of(n)
    if s == nil || s.look == look do return
    s.look = look
    n->damage()
}

reveal :: proc(target, holder: ^Node) -> (moved: bool) {
    if target == nil || holder == nil || holder.scroll == nil do return false
    port := holder.scroll
    rect := target.rect
    // Rects date from the last layout; a port moved since then has not shifted them yet.
    for at := target.parent; at != nil && at != holder; at = at.parent {
        if at.scroll == nil do continue
        rect.x -= at.scroll.offset.x - at.scroll.applied.x
        rect.y -= at.scroll.offset.y - at.scroll.applied.y
    }
    rect.x -= port.offset.x - port.applied.x
    rect.y -= port.offset.y - port.applied.y

    view := port.viewport
    shift: [2]f32
    if rect.x < view.x || rect.w > view.w {
        shift.x = rect.x - view.x
    } else if rect.x + rect.w > view.x + view.w {
        shift.x = rect.x + rect.w - (view.x + view.w)
    }
    if rect.y < view.y || rect.h > view.h {
        shift.y = rect.y - view.y
    } else if rect.y + rect.h > view.y + view.h {
        shift.y = rect.y + rect.h - (view.y + view.h)
    }
    if shift == 0 do return false
    return to(holder, port.offset.x + shift.x, port.offset.y + shift.y)
}

into_view :: proc(target: ^Node) {
    if target == nil do return
    for at := target.parent; at != nil; at = at.parent {
        if at.scroll != nil do reveal(target, at)
    }
}

on_key :: proc(sig: ^events.Event_Signal) {
    n := cast(^Node)sig.current_target
    e := cast(^events.Key_Event)sig.data
    if n == nil || n.scroll == nil || sig.cancelled do return
    port := n.scroll
    // A text field moves its caret with the arrows, Home, End and Space.
    typing := false
    if target := cast(^Node)sig.target; target != nil do typing = target.text_entry
    page := [2]f32{page_step(port.viewport.w), page_step(port.viewport.h)}
    wanted := port.offset
    #partial switch e.code {
    case .Page_Down: wanted.y += page.y
    case .Page_Up:   wanted.y -= page.y
    case .Down:  if typing do return; wanted.y += LINE_STEP
    case .Up:    if typing do return; wanted.y -= LINE_STEP
    case .Right: if typing do return; wanted.x += LINE_STEP
    case .Left:  if typing do return; wanted.x -= LINE_STEP
    case .Home:  if typing do return; wanted.y = 0
    case .End:   if typing do return; wanted.y = port.range.y
    case .Space: if typing do return; wanted.y += -page.y if .Shift in e.mods else page.y
    case: return
    }
    if to(n, wanted.x, wanted.y) {
        events.prevent_default(sig)
        events.stop_propagation(sig)
    }
}

on_focus :: proc(sig: ^events.Event_Signal) {
    holder := cast(^Node)sig.current_target
    target := cast(^Node)sig.target
    if holder == nil || target == nil || target == holder || !input.focus_is_visible() do return
    reveal(target, holder)
}

page_step :: proc(length: f32) -> f32 {
    return max(length * 0.875, length - LINE_STEP)
}

padding_box :: proc(n: ^Node) -> common.Rect {
    border, padding := n->get_rect(.Border), n->get_rect(.Padding)
    return {n.rect.x + padding.x - border.x, n.rect.y + padding.y - border.y, padding.w, padding.h}
}

@(private)
_extent :: proc(n: ^Node, end: ^[2]f32) {
    for c in n.children {
        if c.freed || node.Resolve_Fixed(c) || node.is_hidden(c) do continue
        end.x = max(end.x, c.rect.x + c.rect.w)
        end.y = max(end.y, c.rect.y + c.rect.h)
        if c.clip_mode == .None do _extent(c, end)
    }
}

// Where what `n` holds ends once unscrolled, and no sooner than `floor`. The rects
// below `n` are shifted by `applied`; `floor` is not.
content_end :: proc(n: ^Node, floor, applied: [2]f32) -> [2]f32 {
    end := floor - applied
    _extent(n, &end)
    return end + applied
}

set_range :: proc(port: ^node.Scroll_Port, range: [2]f32) {
    for axis in 0 ..< 2 {
        port.range[axis] = range[axis] if range[axis] >= 0.5 else 0
        port.offset[axis] = clamp(port.offset[axis], 0, port.range[axis])
    }
}

// A thumb's length and place along a track `length` long, for a view showing `shown` of `shown + range`.
thumb_span :: proc(length, shown, range, offset, least: f32) -> (extent, at: f32) {
    if range <= 0 do return length, 0
    extent = clamp(length * shown / (shown + range), min(least, length), length)
    return extent, (length - extent) * offset / range
}

// The offset that puts a thumb `at` along the `travel` its track leaves it.
offset_at :: proc(at, travel, range: f32) -> f32 {
    if travel <= 0 do return 0
    return clamp(at, 0, travel) * range / travel
}

@(private)
_update :: proc(n: ^Node, laid_out: bool) {
    s := of(n)
    if s == nil do return
    s.viewport = padding_box(n)
    if !laid_out do return
    border, content := n->get_rect(.Border), n->get_rect(.Content)
    inner_end := [2]f32{
        n.rect.x + content.x - border.x + content.w,
        n.rect.y + content.y - border.y + content.h,
    }
    reach := content_end(n, inner_end, s.applied) - inner_end
    set_range(&s.port, {reach.x if s.axes[0] else 0, reach.y if s.axes[1] else 0})
}

@(private)
_bar :: proc(s: ^Scroller, axis: int) -> (track, thumb: common.Rect, ok: bool) {
    if s.range[axis] <= 0 || s.look.hidden do return
    size := s.look.size if s.look.size > 0 else DEFAULT_SIZE
    inset := min(size * 0.2, 2)
    view := s.viewport
    other := size if s.range[1 - axis] > 0 else 0
    length := (view.w if axis == 0 else view.h) - other - inset * 2
    if length <= 0 do return
    extent, at := thumb_span(length, view.w if axis == 0 else view.h, s.range[axis], s.offset[axis], THUMB_MIN)
    thick := size - inset * 2
    if axis == 0 {
        track = {view.x + inset, view.y + view.h - size, length, size}
        thumb = {track.x + at, track.y + inset, extent, thick}
    } else {
        track = {view.x + view.w - size, view.y + inset, size, length}
        thumb = {track.x + inset, track.y + at, thick, extent}
    }
    return track, thumb, true
}

@(private)
_inside :: proc(r: common.Rect, x, y: f32) -> bool {
    return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}

@(private)
_draw :: proc(n: ^Node) {
    s := of(n)
    if s == nil do return
    p := painter.get()
    for axis in 0 ..< 2 {
        track, thumb, ok := _bar(s, axis)
        if !ok do continue
        active := s.drag == axis || s.hot == axis
        if s.look.track.a > 0 do painter.rect(p, track, s.look.track)
        color := DEFAULT_THUMB_ACTIVE if active else DEFAULT_THUMB
        if s.look.thumb.a > 0 {
            color = s.look.thumb
            if !active do color.a = u8(f32(color.a) * 0.75)
        }
        painter.rect(p, thumb, color, min(thumb.w, thumb.h) * 0.5)
    }
}

on_wheel :: proc(sig: ^events.Event_Signal) {
    n := cast(^Node)sig.current_target
    e := cast(^events.Wheel_Event)sig.data
    if n == nil || n.scroll == nil do return
    view := n.scroll.viewport
    dx := clamp(-e.delta_x, -view.w, view.w)
    dy := clamp(-e.delta_y, -view.h, view.h)
    if by(n, dx, dy) {
        events.prevent_default(sig)
        events.stop_propagation(sig)
    }
}

@(private)
_drag_to :: proc(n: ^Node, s: ^Scroller, axis: int, pointer: f32) {
    track, thumb, ok := _bar(s, axis)
    if !ok do return
    start := track.x if axis == 0 else track.y
    length := track.w if axis == 0 else track.h
    extent := thumb.w if axis == 0 else thumb.h
    travel := length - extent
    if travel <= 0 do return
    wanted := offset_at(pointer - s.grab - start, travel, s.range[axis])
    if axis == 0 {
        to(n, wanted, s.offset.y)
    } else {
        to(n, s.offset.x, wanted)
    }
}

@(private)
_on_down :: proc(sig: ^events.Event_Signal) {
    n := cast(^Node)sig.current_target
    e := cast(^events.Mouse_Event)sig.data
    s := of(n)
    if s == nil || e.button != 0 do return
    for axis in 0 ..< 2 {
        track, thumb, ok := _bar(s, axis)
        if !ok || !_inside(track, e.x, e.y) do continue
        pointer := e.x if axis == 0 else e.y
        if _inside(thumb, e.x, e.y) {
            s.grab = pointer - (thumb.x if axis == 0 else thumb.y)
        } else {
            s.grab = (thumb.w if axis == 0 else thumb.h) * 0.5
        }
        // A held thumb is drawn brighter.
        n->damage()
        s.drag = axis
        _drag_to(n, s, axis, pointer)
        input.capture_pointer(auto_cast n)
        events.prevent_default(sig)
        events.stop_propagation(sig)
        return
    }
}

@(private)
_on_move :: proc(sig: ^events.Event_Signal) {
    n := cast(^Node)sig.current_target
    e := cast(^events.Mouse_Event)sig.data
    s := of(n)
    if s == nil do return
    if s.drag >= 0 {
        _drag_to(n, s, s.drag, e.x if s.drag == 0 else e.y)
        events.stop_propagation(sig)
        return
    }
    hot := -1
    for axis in 0 ..< 2 {
        if track, _, ok := _bar(s, axis); ok && _inside(track, e.x, e.y) do hot = axis
    }
    if hot != s.hot do n->damage()
    s.hot = hot
}

@(private)
_on_up :: proc(sig: ^events.Event_Signal) {
    n := cast(^Node)sig.current_target
    s := of(n)
    if s == nil || s.drag < 0 do return
    n->damage()
    s.drag = -1
    input.release_pointer()
    events.stop_propagation(sig)
}

@(private)
_on_leave :: proc(sig: ^events.Event_Signal) {
    n := cast(^Node)sig.current_target
    s := of(n)
    if s == nil || s.hot < 0 do return
    n->damage()
    s.hot = -1
}
