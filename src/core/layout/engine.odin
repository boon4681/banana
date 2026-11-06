package layout

import YG "src:yoga"

import "src:core/common"
import _ "src:core/scroll"
import "src:core/node"
import "src:core/platform"
import "src:core/redraw"
import "src:core/signal"

Node :: node.BaseNode

Deferred :: struct {
    callback: proc(state: rawptr),
    state:    rawptr
}

// where a style system plug into update
// flush run before layout, settle run after and return true when layout must run again
Style_Hooks :: struct {
    flush:  proc(root: ^Node, avail_w, avail_h: f32),
    settle: proc(root: ^Node) -> bool,
}

@(private, thread_local)
_deferred: [dynamic]Deferred

@(private, thread_local)
_pending_free: [dynamic]^Node

@(private, thread_local)
_last_avail: map[^Node][2]f32

@(thread_local)
style_hooks: Style_Hooks

@(private, thread_local)
_point_scale: f32

SETTLE_PASSES :: 6

Defer :: proc(callback: proc(state: rawptr), state: rawptr = nil) {
    append(&_deferred, Deferred{callback = callback, state = state})
}

scheduler_setup :: proc() {
    _deferred = make([dynamic]Deferred)
    _pending_free = make([dynamic]^Node)
    _last_avail = make(map[^Node][2]f32)
}

scheduler_shutdown :: proc() {
    signal.free_graph()
    delete(_deferred)
    delete(_pending_free)
    delete(_last_avail)
    // a root freed after this still run _forget_avail, so leave the map nil not dangling
    _last_avail = nil
}

// forget the last size of a freed root
// a new root can get the same address and must not inherit the old size
@(private)
_forget_avail :: proc(root: ^Node, _: rawptr) {
    delete_key(&_last_avail, root)
}

update :: proc(root: ^Node, avail_w, avail_h: f32) {
    redraw.tick_begin()
    defer redraw.tick_end()
    if w := get_window(root); w != nil && w.loop != nil {
        // do event loop if window contain one
        w.loop->update()
    }
    signal.flush()
    run_deferred()
    flush_pending_free()
    if style_hooks.flush != nil do style_hooks.flush(root, avail_w, avail_h)

    scale: f32 = 1
    if w := get_window(root); w != nil && w.scale > 0 do scale = w.scale
    scale_changed := scale != _point_scale
    if scale_changed {
        _point_scale = scale
        YG.ConfigSetPointScaleFactor(cast(YG.ConfigRef)YG.ConfigGetDefault(), scale)
    }

    prev, seen := _last_avail[root]
    size_changed := !seen || prev != [2]f32{avail_w, avail_h}
    changed := size_changed || scale_changed || YG.NodeIsDirty(root.raw)
    if !seen do root->add_hook(.Before_Free, _forget_avail, nil)
    _last_avail[root] = {avail_w, avail_h}

    nodes := make([dynamic]^Node, 0, 4096)
    defer delete(nodes)
    if changed {
        release_pins(root)
        YG.NodeCalculateLayout(root.raw, avail_w, avail_h, .LTR)
    }
    for _ in 0 ..< SETTLE_PASSES {
        again := style_hooks.settle != nil && style_hooks.settle(root)
        if (changed || again) && apply_auto_min(root) do again = true
        if !again do break
        changed = true
        YG.NodeCalculateLayout(root.raw, avail_w, avail_h, .LTR)
    }
    cache_rects(&nodes, root, 0)

    if changed {
        for n in nodes do notify_layout(n)
    }

    for n in nodes do process(n)

    scrolled := false
    for n in nodes {
        port := n.scroll
        if port == nil || n.freed do continue
        if port.update != nil do port.update(n, changed)
        if port.offset != port.applied do scrolled = true
    }
    if scrolled {
        clear(&nodes)
        cache_rects(&nodes, root, 0)
        for n in nodes {
            if port := n.scroll; port != nil && port.update != nil && !n.freed do port.update(n, false)
        }
    }

    for n in nodes {
        if !n.freed do stick(n)
    }

    // rects are final here, so damage can be recorded now
    // a node that moved repaint its old and new spot, and damage asked for before layout use the final spot
    waiting := redraw.take_pending()
    // a window that always repaint whole only need to know something moved, not where
    if (changed || scrolled) && redraw.whole() do redraw.mark()
    if changed || scrolled || waiting do root->settle_damage()
    redraw.end_epoch()
}

@(private)
stick :: proc(n: ^Node) {
    parent := n.parent
    if _, sticky := node.Resolve_Sticky(n); !sticky || parent == nil do return
    port: ^node.Scroll_Port
    for at := parent; at != nil && port == nil; at = at.parent do port = at.scroll
    if port == nil do return
    border, content := parent->get_rect(.Border), parent->get_rect(.Content)
    box := common.Rect{parent.rect.x + content.x - border.x, parent.rect.y + content.y - border.y, content.w, content.h}
    shift := node.Resolve_Sticky_Shift(n, box, port^)
    if shift != 0 do shift_rects(n, shift)
}

@(private)
shift_rects :: proc(n: ^Node, by: [2]f32) {
    n.rect.x += by.x
    n.rect.y += by.y
    for c in n.children do shift_rects(c, by)
}

@(private)
notify_layout :: proc(n: ^Node) {
    if n.freed do return
    if n.on_layout != nil do n.on_layout(n)
    if n.hooks != nil do n->run_hooks(.After_Layout)
}

@(private)
process :: proc(n: ^Node) {
    if n.freed do return
    if n.process != nil do n.process(n)
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
cache_rects :: proc(nodes: ^[dynamic]^Node, n: ^Node, origin: [2]f32, scrolled: [2]f32 = 0) {
    if n.freed do return
    shown := origin
    behind := scrolled
    if node.Resolve_Fixed(n) {
        shown += scrolled
        behind = 0
    }
    // read straight from yoga, this run for every node every tick and get_rect cost several times the reads
    raw := n.raw
    n.rect = {
        YG.NodeLayoutGetLeft(raw) + shown.x, YG.NodeLayoutGetTop(raw) + shown.y,
        YG.NodeLayoutGetWidth(raw), YG.NodeLayoutGetHeight(raw),
    }
    append(nodes, n)
    at := [2]f32{n.rect.x, n.rect.y}
    if port := n.scroll; port != nil {
        at -= port.offset
        behind += port.offset
        port.applied = port.offset
    }
    for c in n.children do cache_rects(nodes, c, at, behind)
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
_awake_node :: proc(n: ^Node) {
    if n == nil do return
    if n.awaken do panic("Runtime error: cannot awake node more than one times")
    for c in n.children {
        if n.structural do break
        c._internal_propagate_awake = _awake_node
        c.window = n.window
        c->_internal_propagate_awake()
    }
    for c in n._internal_children {
        if !c.structural || c.awaken do continue
        c._internal_propagate_awake = _awake_node
        c.window = n.window
        c->_internal_propagate_awake()
    }
    n._internal_propagate_awake = _awake_node
    n.queue_free = _queue_free_node
    n.awaken = true
    if n.on_awake != nil {
        n->on_awake()
    }
    n->run_hooks(.After_Awake)
}

@(private="file")
_queue_free_node :: proc(self: ^Node) -> node.Node_Error {
    if self == nil || self.queued_free do return node.Node_Error.None
    self.queued_free = true
    append(&_pending_free, self)
    return node.Node_Error.None
}
