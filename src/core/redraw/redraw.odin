package redraw

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:time"

// -define:BANANA_REDRAW_LOG=true prints ticks and painted frames once a second.
LOG :: #config(BANANA_REDRAW_LOG, false)

Mode :: enum {
    Continuous,
    On_Demand,
}

Stats :: struct {
    ticks:      u64,
    painted:    u64,
    // How many of `painted` redrew only part of the window.
    partial:    u64,
    tick_cost:  time.Duration,
    paint_cost: time.Duration,
}

// Left, top, right, bottom.
Box :: [4]f32

State :: struct {
    mode:       Mode,
    dirty:      bool,
    painting:   bool,
    partial:    bool, // The screen keeps the last frame, so a paint may redraw only `box`.
    scale:      f32,  // Device pixels per layout unit.
    full:       bool, // The whole window is to be painted, whatever `box` says.
    box:        Box,  // Union of what was damaged since the last paint, in layout units.
    boxed:      bool,
    pending:    bool, // A damaged node waits for layout to say where it ended up.
    ticked:     u64,
    paint_full: bool, // What the paint under way covers.
    paint_box:  Box,
    again:      bool, // Set during a paint that must be followed by another one.
    requested:  bool, // Written by other threads.

    stats:       Stats,
    tick_start:  time.Tick,
    paint_start: time.Tick,
    last_paint:  time.Tick,

    log_start:   time.Tick,
    log_ticks:   u64,
    log_painted: u64,
    log_partial: u64,
    log_slowest: time.Duration,
    log_marker:  runtime.Source_Code_Location,

    check: Check_State,
}

@(private, thread_local)
_current: ^State

set_current :: proc(s: ^State) {
    _current = s
}

current :: proc() -> ^State {
    return _current
}

destroy :: proc(s: ^State) {
    if _current == s do _current = nil
    _check_destroy(s)
}

// Something visible changed in the current window.
// A draw proc reads state and must not change it, so a mark made while painting is dropped.
mark :: proc(loc := #caller_location) {
    s := _current
    if s == nil || s.painting do return
    s.dirty = true
    s.full = true
    when LOG do s.log_marker = loc
}

// Something visible changed inside `box` only.
damage :: proc(box: Box, loc := #caller_location) {
    s := _current
    if s == nil || s.painting do return
    if box[2] <= box[0] || box[3] <= box[1] do return
    s.dirty = true
    if s.boxed {
        s.box = {min(s.box[0], box[0]), min(s.box[1], box[1]), max(s.box[2], box[2]), max(s.box[3], box[3])}
    } else {
        s.box = box
        s.boxed = true
    }
    when LOG do s.log_marker = loc
}

painting :: proc() -> bool {
    s := _current
    return s != nil && s.painting
}

// The next paint covers the whole window anyway, so a box would add nothing.
whole :: proc() -> bool {
    s := _current
    return s == nil || !s.partial || s.mode == .Continuous || CHECK || s.full
}

// Names the stretch between two layouts. A record made in an earlier one is stale.
epoch :: proc() -> u64 {
    s := _current
    return s.ticked + 1 if s != nil else 0
}

end_epoch :: proc() {
    if s := _current; s != nil do s.ticked += 1
}

// A node was damaged and its place after layout is not known yet.
wait_for_layout :: proc() {
    if s := _current; s != nil && !s.painting do s.pending = true
}

// True once per tick in which a damaged node waits for layout.
take_pending :: proc() -> bool {
    s := _current
    if s == nil || !s.pending do return false
    s.pending = false
    return true
}

// What the paint under way covers: the whole window, or `box` in layout units.
painted :: proc() -> (box: Box, whole: bool) {
    s := _current
    if s == nil || !s.painting || s.paint_full do return {}, true
    return s.paint_box, false
}

// The same in device pixels as x, y, width, height, grown to whole pixels.
painted_pixels :: proc() -> (rect: [4]f32, whole: bool) {
    box, all := painted()
    if all do return {}, true
    s := _current
    scale := s.scale if s.scale > 0 else 1
    x0, y0 := math.floor(box[0] * scale), math.floor(box[1] * scale)
    x1, y1 := math.ceil(box[2] * scale), math.ceil(box[3] * scale)
    x0, y0 = max(x0, 0), max(y0, 0)
    return {x0, y0, max(x1 - x0, 0), max(y1 - y0, 0)}, false
}

// During a paint: what was just drawn is already stale, so paint once more.
again :: proc() {
    if s := _current; s != nil && s.painting do s.again = true
}

// Safe from any thread.
request :: proc(s: ^State) {
    if s != nil do intrinsics.atomic_store(&s.requested, true)
}

dirty :: proc() -> bool {
    s := _current
    if s == nil || s.mode == .Continuous || CHECK do return true
    return s.dirty || intrinsics.atomic_load(&s.requested)
}

begin_paint :: proc() {
    s := _current
    if s == nil do return
    _check_begin(s)
    asked := intrinsics.atomic_load(&s.requested)
    s.paint_full = !s.partial || s.mode == .Continuous || CHECK || s.full || asked || !s.boxed
    // A pixel either side: an antialiased edge reaches half a pixel past its shape.
    pad := 1 / (s.scale if s.scale > 0 else 1)
    s.paint_box = {s.box[0] - pad, s.box[1] - pad, s.box[2] + pad, s.box[3] + pad}
    s.painting = true
    s.again = false
    s.paint_start = time.tick_now()
}

end_paint :: proc() {
    s := _current
    if s == nil do return
    _check_end(s)
    now := time.tick_now()
    s.painting = false
    s.dirty = s.again
    s.full = s.again
    s.boxed = false
    s.again = false
    intrinsics.atomic_store(&s.requested, false)
    s.stats.painted += 1
    if !s.paint_full do s.stats.partial += 1
    s.stats.paint_cost = time.tick_diff(s.paint_start, now)
    s.last_paint = now
}

tick_begin :: proc() {
    if s := _current; s != nil do s.tick_start = time.tick_now()
}

tick_end :: proc() {
    s := _current
    if s == nil do return
    now := time.tick_now()
    s.stats.ticks += 1
    s.stats.tick_cost = time.tick_diff(s.tick_start, now)
    when LOG {
        if s.log_start == {} do s.log_start = now
        s.log_slowest = max(s.log_slowest, s.stats.tick_cost)
        if time.tick_diff(s.log_start, now) < time.Second do return
        fmt.printfln(
            "redraw: ticks=%d painted=%d in part=%d tick=%.3fms slowest=%.3fms paint=%.3fms last mark %s:%d",
            s.stats.ticks - s.log_ticks,
            s.stats.painted - s.log_painted,
            s.stats.partial - s.log_partial,
            time.duration_milliseconds(s.stats.tick_cost),
            time.duration_milliseconds(s.log_slowest),
            time.duration_milliseconds(s.stats.paint_cost),
            s.log_marker.file_path,
            s.log_marker.line,
        )
        s.log_start = now
        s.log_ticks = s.stats.ticks
        s.log_painted = s.stats.painted
        s.log_partial = s.stats.partial
        s.log_slowest = 0
    }
}
