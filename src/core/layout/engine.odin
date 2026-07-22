package layout

import YG "src:yoga"

import "src:core/node"
import "src:core/platform"

Node :: node.BaseNode

Deferred :: struct {
    callback: proc(state: rawptr),
    state:    rawptr
}

@(private)
_deferred: [dynamic]Deferred

@(private)
_pending_free: [dynamic]^Node

@(private)
_last_avail: map[^Node][2]f32

Defer :: proc(callback: proc(state: rawptr), state: rawptr = nil) {
    append(&_deferred, Deferred{callback = callback, state = state})
}

scheduler_setup :: proc() {
    _deferred = make([dynamic]Deferred)
    _pending_free = make([dynamic]^Node)
    _last_avail = make(map[^Node][2]f32)
}

scheduler_shutdown :: proc() {
    delete(_deferred)
    delete(_pending_free)
    delete(_last_avail)
}

update :: proc(root: ^Node, avail_w, avail_h: f32) {
    run_deferred()
    flush_pending_free()

    prev, seen := _last_avail[root]
    size_changed := !seen || prev != [2]f32{avail_w, avail_h}
    changed := size_changed || YG.NodeIsDirty(root.raw)
    _last_avail[root] = {avail_w, avail_h}

    if changed {
        apply_auto_min_size(root)
        YG.NodeCalculateLayout(root.raw, avail_w, avail_h, .LTR)
    }
    cache_rects(root, 0, 0)

    if changed do notify_layout(root)

    process(root)
}

// CSS automatic minimum size.
@(private)
apply_auto_min_size :: proc(n: ^Node) {
    for c in n.children do apply_auto_min_size(c)
    if n.freed do return

    row := false
    #partial switch YG.NodeStyleGetFlexDirection(n.raw) {
    case .Row, .RowReverse: row = true
    }

    for c in n.children {
        if c.freed do continue
        if YG.NodeStyleGetPositionType(c.raw) == .Absolute do continue
        // Only shrinkable items are at risk of collapsing below their size.
        if YG.NodeStyleGetFlexShrink(c.raw) == 0 do continue

        scrollable := c.clip_x if row else c.clip_y
        size := YG.NodeStyleGetWidth(c.raw) if row else YG.NodeStyleGetHeight(c.raw)
        if !scrollable && size.unit == .Point && size.value > 0 {
            if row {
                YG.NodeStyleSetMinWidth(c.raw, size.value)
            } else {
                YG.NodeStyleSetMinHeight(c.raw, size.value)
            }
        }
    }
}

@(private)
notify_layout :: proc(n: ^Node) {
    if n.freed do return
    if n.on_layout != nil do n.on_layout(n)
    for c in n.children do notify_layout(c)
}

@(private)
process :: proc(n: ^Node) {
    if n.freed do return
    if n.process != nil do n.process(n)
    for c in n.children do process(c)
}

@(private)
run_deferred :: proc() {
    if len(_deferred) == 0 do return
    batch := _deferred
    _deferred = make([dynamic]Deferred)
    for d in batch do d.callback(d.state)
    delete(batch)
}

@(private)
flush_pending_free :: proc() {
    if len(_pending_free) == 0 do return
    for n in _pending_free do n->free()
    clear(&_pending_free)
}

@(private)
cache_rects :: proc(n: ^Node, ox, oy: f32) {
    n.rect = n->get_rect(.Border)
    n.rect.x += ox
    n.rect.y += oy

    for c in n.children do cache_rects(c, n.rect.x, n.rect.y)
}

get_window :: proc(n: ^Node) -> ^platform.Window {
    return cast(^platform.Window)(n.window)
}

awake_window :: proc(w: ^platform.Window) {
    w.awaken = true
    w.root.window = w
    _awake_node(w.root)
}

// This get auto propagate when add child in node if node is setup properly
// This cannot be access outside engine cuz every node must have window ctx
@(private="file")
_awake_node :: proc(n: ^Node){
    if n == nil || n.awaken do return
    for c in n.children {
        c._internal_propagate_awake = _awake_node
        c.window = n.window
        c->_internal_propagate_awake()
    }
    n._internal_propagate_awake = _awake_node
    n.queue_free = _queue_free_node
    n.awaken = true
}

@(private="file")
_queue_free_node :: proc(self: ^Node) -> node.Node_Error {
    if self == nil || self.queued_free do return node.Node_Error.None
    self.queued_free = true
    append(&_pending_free, self)
    return node.Node_Error.None
}
