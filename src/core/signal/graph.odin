package signal

import "core:fmt"

@(private)
Kind :: enum u8 {
    Source,
    Derived,
    Pre_Effect,
    User_Effect,
}

@(private)
Status :: enum u8 {
    Clean,
    Maybe_Dirty,
    Dirty,
}

// this is node on graph not a real node id
Node_Id :: struct {
    slot: u32,
    gen:  u32,
}

@(private)
Reactive :: struct {
    kind:   Kind,
    status: Status,
    gen:    u32,
    alive:      bool,
    queued:     bool,
    inert:      bool,
    evaluating: bool,

    wv: u64,

    parent:        Node_Id,
    children:      [dynamic]Node_Id,
    pending_child: bool,

    sources:   [dynamic]Node_Id,
    observers: [dynamic]Node_Id,

    flush_id: u32,
    runs:     u16,

    owner:      rawptr,
    run:        proc(owner: rawptr) -> (changed: bool),
    teardown:   proc(owner: rawptr),
    free_owner: proc(owner: rawptr),
}

@(private="file", thread_local)
_slots: [dynamic]^Reactive

@(private="file", thread_local)
_free_slots: [dynamic]u32

@(private="file", thread_local)
_active_reaction: Node_Id

@(private="file", thread_local)
_active_effect: Node_Id

@(private="package", thread_local)
_untracked: bool

@(private="file", thread_local)
_write_version: u64

@(private)
_is_effect :: proc(kind: Kind) -> bool {
    return kind == .Pre_Effect || kind == .User_Effect
}

@(private)
_node :: proc(id: Node_Id) -> ^Reactive {
    if id.gen == 0 || int(id.slot) >= len(_slots) do return nil
    n := _slots[id.slot]
    if n.gen != id.gen || !n.alive do return nil
    return n
}

@(private)
_alloc :: proc(
    kind: Kind,
    owner: rawptr,
    run: proc(owner: rawptr) -> bool,
    free_owner: proc(owner: rawptr),
) -> Node_Id {
    slot: u32
    if len(_free_slots) > 0 {
        slot = pop(&_free_slots)
    } else {
        append(&_slots, new(Reactive))
        slot = u32(len(_slots) - 1)
    }

    n := _slots[slot]
    gen := n.gen + 1
    if gen == 0 do gen = 1

    n.kind = kind
    n.status = .Clean if kind == .Source else .Dirty
    n.gen = gen
    n.wv = _write_version
    n.alive = true
    n.queued = false
    n.inert = false
    n.pending_child = false
    n.runs = 0
    n.parent = {}
    n.owner = owner
    n.run = run
    n.teardown = nil
    n.free_owner = free_owner
    clear(&n.sources)
    clear(&n.observers)
    clear(&n.children)

    id := Node_Id{slot, gen}
    if parent := _node(_active_effect); parent != nil {
        n.parent = _active_effect
        append(&parent.children, id)
    }
    if _is_effect(kind) do _schedule(id)
    return id
}

@(private)
_destroy :: proc(id: Node_Id, unlink_parent := true) {
    n := _node(id)
    if n == nil do return

    _destroy_children(id)
    _clear_sources(id)

    for o in n.observers {
        ob := _node(o)
        if ob == nil do continue
        for i in 0 ..< len(ob.sources) {
            if ob.sources[i] == id {
                unordered_remove(&ob.sources, i)
                break
            }
        }
        _mark(o, .Dirty)
    }
    clear(&n.observers)

    if unlink_parent {
        if p := _node(n.parent); p != nil {
            for i in 0 ..< len(p.children) {
                if p.children[i] == id {
                    unordered_remove(&p.children, i)
                    break
                }
            }
        }
    }
    n.parent = {}

    owner, teardown, free_owner := n.owner, n.teardown, n.free_owner
    n.alive = false
    n.queued = false
    n.owner = nil
    n.teardown = nil
    append(&_free_slots, id.slot)

    if teardown != nil do teardown(owner)
    if free_owner != nil do free_owner(owner)
}

@(private)
_destroy_children :: proc(id: Node_Id) {
    n := _node(id)
    if n == nil do return
    for len(n.children) > 0 {
        child := pop(&n.children)
        _destroy(child, unlink_parent = false)
        n = _node(id)
        if n == nil do return
    }
}

@(private)
_track :: proc(source: Node_Id) {
    if _untracked do return
    obs := _node(_active_reaction)
    if obs == nil do return
    src := _node(source)
    if src == nil do return

    for s in obs.sources {
        if s == source do return
    }
    append(&obs.sources, source)
    append(&src.observers, _active_reaction)
}

@(private)
_clear_sources :: proc(id: Node_Id) {
    n := _node(id)
    if n == nil do return
    for s in n.sources {
        src := _node(s)
        if src == nil do continue
        for i in 0 ..< len(src.observers) {
            if src.observers[i] == id {
                unordered_remove(&src.observers, i)
                break
            }
        }
    }
    clear(&n.sources)
}

@(private)
_bump :: proc(id: Node_Id) {
    n := _node(id)
    if n == nil do return
    _write_version += 1
    n.wv = _write_version
    for o in n.observers do _mark(o, .Dirty)
}

@(private)
_mark :: proc(id: Node_Id, status: Status) {
    n := _node(id)
    if n == nil || n.status >= status do return
    was_clean := n.status == .Clean
    n.status = status

    if _is_effect(n.kind) {
        if was_clean do _schedule(id)
        return
    }
    if was_clean {
        for o in n.observers do _mark(o, .Maybe_Dirty)
    }
}

@(private)
_check_dirty :: proc(id: Node_Id) -> bool {
    n := _node(id)
    if n == nil do return false
    if n.status == .Dirty do return true
    if n.status != .Maybe_Dirty do return false

    for i := 0; i < len(n.sources); i += 1 {
        dep := n.sources[i]
        if d := _node(dep); d != nil && d.kind == .Derived {
            _update_derived(dep)
        }

        n = _node(id)
        if n == nil do return false
        if n.status == .Dirty do return true

        d := _node(dep)
        if d != nil && d.wv > n.wv do return true
    }

    n = _node(id)
    if n == nil do return false
    n.status = .Clean
    return false
}

@(private)
_update_derived :: proc(id: Node_Id) {
    n := _node(id)
    if n != nil && n.evaluating {
        fmt.eprintf("signal: cyclic dependency detected at derived node (slot=%d gen=%d)\n", id.slot, id.gen)
    }
    if _check_dirty(id) do _run(id)
}

@(private)
_run :: proc(id: Node_Id) {
    n := _node(id)
    if n == nil || n.run == nil do return
    is_effect := _is_effect(n.kind)

    if is_effect {
        _destroy_children(id)
        n = _node(id)
        if n == nil do return
        if teardown := n.teardown; teardown != nil {
            n.teardown = nil
            teardown(n.owner)
            n = _node(id)
            if n == nil do return
        }
    }

    _clear_sources(id)
    n.status = .Clean
    n.evaluating = true

    prev_reaction := _active_reaction
    prev_effect := _active_effect
    prev_untracked := _untracked
    _active_reaction = id
    _untracked = false
    if is_effect do _active_effect = id

    changed := n.run(n.owner)

    _active_reaction = prev_reaction
    _active_effect = prev_effect
    _untracked = prev_untracked

    if n = _node(id); n != nil do n.evaluating = false

    n = _node(id)
    if n == nil do return

    if n.kind == .Derived {
        if changed {
            _write_version += 1
            n.wv = _write_version
            for o in n.observers do _mark(o, .Dirty)
        }
    } else {
        n.wv = _write_version
    }
}

free_graph :: proc() {
    for n, slot in _slots {
        if n.alive do _destroy(Node_Id{u32(slot), n.gen})
    }
    for n in _slots {
        delete(n.sources)
        delete(n.observers)
        delete(n.children)
        free(n)
    }
    delete(_slots)
    delete(_free_slots)
    delete(_queue)
    _slots, _free_slots, _queue = nil, nil, nil
    _active_reaction, _active_effect = {}, {}
}
