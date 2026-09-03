package signal

import "core:time"

MAX_RUNS_PER_EFFECT :: 8

@(private)
BUDGET_CHECK_INTERVAL :: 16

Budget :: struct {
    duration:    time.Duration, // zero is unlimited
    max_effects: int,           // zero is unlimited
}

DEFAULT_BUDGET :: Budget {
    duration = 4 * time.Millisecond,
}

Flush_Stats :: struct {
    ran:       int,
    remaining: int,
    exhausted: bool,
    starved:   bool,
}

@(private, thread_local)
_queue: [dynamic]Node_Id

@(private="file", thread_local)
_flushing: bool

@(private="file", thread_local)
_flush_id: u32

pending :: proc() -> int {
    return len(_queue)
}

flush :: proc(budget := DEFAULT_BUDGET) -> (stats: Flush_Stats) {
    if _flushing {
        stats.remaining = len(_queue)
        return
    }
    _flushing = true
    _flush_id += 1
    start := time.tick_now()

    roots, pre, user, held: [dynamic]Node_Id

    for len(_queue) > 0 {
        if _over_budget(budget, start, stats.ran) {
            stats.exhausted = true
            break
        }
        roots, _queue = _queue, roots
        clear(&_queue)

        clear(&pre)
        clear(&user)
        for root in roots {
            if r := _node(root); r != nil do r.queued = false
            _collect(root, &pre, &user)
        }

        if !_run_batch(pre[:], budget, start, &stats, &held) {
            for id in user do append(&held, id)
            break
        }
        if !_run_batch(user[:], budget, start, &stats, &held) do break
    }

    for id in held do _schedule(id)

    delete(roots)
    delete(pre)
    delete(user)
    delete(held)

    _flushing = false
    stats.remaining = len(_queue)
    return
}

flush_sync :: proc() -> Flush_Stats {
    return flush(Budget{})
}

@(private)
_run_batch :: proc(
    ids: []Node_Id,
    budget: Budget,
    start: time.Tick,
    stats: ^Flush_Stats,
    held: ^[dynamic]Node_Id,
) -> (completed: bool) {
    for id, i in ids {
        if _over_budget(budget, start, stats.ran) {
            stats.exhausted = true
            for rest in ids[i:] do append(held, rest)
            return false
        }

        n := _node(id)
        if n == nil do continue
        if n.flush_id != _flush_id {
            n.flush_id = _flush_id
            n.runs = 0
        }
        if n.runs >= MAX_RUNS_PER_EFFECT {
            stats.starved = true
            append(held, id)
            continue
        }
        if !_check_dirty(id) do continue

        n = _node(id)
        if n == nil do continue
        n.runs += 1
        stats.ran += 1
        _run(id)
    }
    return true
}

@(private)
_over_budget :: proc(budget: Budget, start: time.Tick, ran: int) -> bool {
    if budget.max_effects > 0 && ran >= budget.max_effects do return true
    if budget.duration > 0 && ran > 0 && ran % BUDGET_CHECK_INTERVAL == 0 {
        return time.tick_since(start) >= budget.duration
    }
    return false
}

@(private)
_schedule :: proc(id: Node_Id) {
    n := _node(id)
    if n == nil || n.inert do return

    root := id
    for {
        parent := n.parent
        p := _node(parent)
        if p == nil do break
        if p.inert do return
        p.pending_child = true
        root, n = parent, p
    }

    if n.queued do return
    n.queued = true
    append(&_queue, root)
}

@(private)
_collect :: proc(id: Node_Id, pre, user: ^[dynamic]Node_Id) {
    n := _node(id)
    if n == nil || n.inert do return

    if _is_effect(n.kind) && n.status != .Clean {
        if _check_dirty(id) {
            n = _node(id)
            if n == nil do return
            n.pending_child = false
            append(pre if n.kind == .Pre_Effect else user, id)
            return
        }
        n = _node(id)
        if n == nil do return
    }

    if !n.pending_child do return
    n.pending_child = false
    for i := 0; i < len(n.children); i += 1 {
        child := n.children[i]
        _collect(child, pre, user)
        n = _node(id)
        if n == nil do return
    }
}
