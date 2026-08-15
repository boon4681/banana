package signal

import "base:intrinsics"

Source :: struct($T: typeid) {
    id:     Node_Id,
    value:  T,
    equals: proc(a, b: T) -> bool,
}

Derived :: struct($T: typeid) {
    id:     Node_Id,
    value:  T,
    fn:     proc(ctx: rawptr) -> T,
    ctx:    rawptr,
    equals: proc(a, b: T) -> bool,
    _ran:   bool,
}

Effect :: struct {
    id:       Node_Id,
    fn:       proc(e: ^Effect),
    ctx:      rawptr,
    _cleanup: proc(e: ^Effect),
}

state :: proc(initial: $T) -> ^Source(T) {
    s := new(Source(T))
    s.value = initial
    s.id = _alloc(.Source, s, nil, proc(owner: rawptr) {
            free(cast(^Source(T))owner)
    })
    return s
}

derived :: proc(fn: proc(ctx: rawptr) -> $T, ctx: rawptr = nil) -> ^Derived(T) {
    d := new(Derived(T))
    d.fn = fn
    d.ctx = ctx
    d.id = _alloc(
        .Derived,
        d,
        proc(owner: rawptr) -> bool {
            d := cast(^Derived(T))owner
            if d.fn == nil do return false
            v := d.fn(d.ctx)
            if d._ran && _same(d.equals, d.value, v) do return false
            d.value = v
            d._ran = true
            return true
        },
        proc(owner: rawptr) {
            free(cast(^Derived(T))owner)
        },
    )
    return d
}

// Runs on the next flush, then whenever what it read changes.
effect :: proc(fn: proc(e: ^Effect), ctx: rawptr = nil) -> ^Effect {
    return _effect(.User_Effect, fn, ctx)
}

// Runs before user effects.
pre_effect :: proc(fn: proc(e: ^Effect), ctx: rawptr = nil) -> ^Effect {
    return _effect(.Pre_Effect, fn, ctx)
}

// A context-backed effect with explicit dependencies.
Effect_With_Deps :: struct {
    deps: []Node_Id,
    fn:   proc(r: rawptr),
    ctx:  rawptr,
}

// Re-runs when any dependency changes.
effect_with_deps :: proc(ewd: ^Effect_With_Deps) -> ^Effect {
    return effect(proc(e: ^Effect) {
            wc := cast(^Effect_With_Deps)e.ctx
            for d in wc.deps do _track(d)
            wc.fn(wc.ctx)
    }, ewd)
}

@(private="file")
_effect :: proc(kind: Kind, fn: proc(e: ^Effect), ctx: rawptr) -> ^Effect {
    e := new(Effect)
    e.fn = fn
    e.ctx = ctx
    e.id = _alloc(
        kind,
        e,
        proc(owner: rawptr) -> bool {
            e := cast(^Effect)owner
            if e.fn != nil do e.fn(e)
            return false
        },
        proc(owner: rawptr) {
            free(cast(^Effect)owner)
        },
    )
    return e
}

// Runs before the next effect pass and again when the effect is destroyed.
on_cleanup :: proc(e: ^Effect, fn: proc(e: ^Effect)) {
    if e == nil do return
    e._cleanup = fn
    n := _node(e.id)
    if n == nil do return
    n.teardown = proc(owner: rawptr) {
        e := cast(^Effect)owner
        cleanup := e._cleanup
        e._cleanup = nil
        if cleanup != nil do cleanup(e)
    }
}

get :: proc {
    source_get,
    derived_get,
}

// Reads the current value without subscribing the running reaction to it.
peek :: proc {
    source_peek,
    derived_peek,
}

destroy :: proc {
    source_destroy,
    derived_destroy,
    effect_destroy,
}

source_get :: proc(s: ^Source($T)) -> T {
    if s == nil do return {}
    _track(s.id)
    return s.value
}

source_peek :: proc(s: ^Source($T)) -> T {
    return {} if s == nil else s.value
}

set :: proc(s: ^Source($T), value: T) {
    if s == nil do return
    if _same(s.equals, s.value, value) do return
    s.value = value
    _bump(s.id)
}

update :: proc(s: ^Source($T), fn: proc(old: T) -> T) {
    if s == nil || fn == nil do return
    set(s, fn(s.value))
}

source_destroy :: proc(s: ^Source($T)) {
    if s != nil do _destroy(s.id)
}

derived_get :: proc(d: ^Derived($T)) -> T {
    if d == nil do return {}
    _update_derived(d.id)
    _track(d.id)
    return d.value
}

derived_peek :: proc(d: ^Derived($T)) -> T {
    if d == nil do return {}
    _update_derived(d.id)
    return d.value
}

derived_destroy :: proc(d: ^Derived($T)) {
    if d != nil do _destroy(d.id)
}

effect_destroy :: proc(e: ^Effect) {
    if e != nil do _destroy(e.id)
}

pause :: proc(e: ^Effect) {
    if e == nil do return
    n := _node(e.id)
    if n != nil do n.inert = true
}

resume :: proc(e: ^Effect) {
    if e == nil do return
    n := _node(e.id)
    if n == nil || !n.inert do return
    n.inert = false
    if n.status != .Clean || n.pending_child do _schedule(e.id)
}

// Runs `fn` without recording anything it reads as a dependency.
untrack :: proc(fn: proc(ctx: rawptr), ctx: rawptr = nil) {
    if fn == nil do return
    prev := _untracked
    _untracked = true
    fn(ctx)
    _untracked = prev
}

@(private)
_same :: proc(eq: proc(a, b: $T) -> bool, a, b: T) -> bool {
    if eq != nil do return eq(a, b)
    when intrinsics.type_is_comparable(T) {
        return a == b
    } else {
        return false
    }
}
