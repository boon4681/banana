package eventloop

import "core:time"

Callback :: proc(ctx: rawptr)

Timer :: struct {
    id:       u64,
    deadline: time.Tick,
    interval: time.Duration,
    callback: Callback,
    ctx:      rawptr,
    cancelled: bool,
}

Budget :: struct {
    duration: time.Duration, // zero is unlimited
    max_fires: int,          // zero is unlimited
}

DEFAULT_BUDGET :: Budget {
    duration  = 4 * time.Millisecond,
    max_fires = 64,
}

STALL_INTERVALS :: time.Duration(4)

Loop :: struct {
    timers:  [dynamic]^Timer,
    next_id: u64,
    firing:  ^Timer,

    set_timeout: proc(self: ^Loop, callback: Callback, delay: time.Duration, ctx: rawptr = nil) -> u64,
    set_interval: proc(self: ^Loop, callback: Callback, interval: time.Duration, ctx: rawptr = nil) -> u64,
    clear_timeout:  proc(self: ^Loop, id: u64),
    clear_interval: proc(self: ^Loop, id: u64),
    pending:        proc(self: ^Loop) -> int,
    update: proc(self: ^Loop, now: Maybe(time.Tick) = nil, budget := DEFAULT_BUDGET),
}

create :: proc(allocator := context.allocator) -> ^Loop {
    l := new(Loop, allocator)
    l.timers = make([dynamic]^Timer, allocator)
    l.set_timeout = _set_timeout
    l.set_interval = _set_interval
    l.clear_timeout = _clear_timeout
    l.clear_interval = _clear_interval
    l.pending = _pending
    l.update = _update
    return l
}

destroy :: proc(l: ^Loop) {
    if l == nil do return
    for t in l.timers do free(t)
    delete(l.timers)
    free(l)
}

@(private = "file")
_set_timeout :: proc(self: ^Loop, callback: Callback, delay: time.Duration, ctx: rawptr = nil) -> u64 {
    return _schedule(self, callback, delay, 0, ctx)
}

@(private = "file")
_set_interval :: proc(self: ^Loop, callback: Callback, interval: time.Duration, ctx: rawptr = nil) -> u64 {
    return _schedule(self, callback, interval, interval, ctx)
}

@(private = "file")
_clear_timeout :: proc(self: ^Loop, id: u64) {
    _cancel(self, id)
}

@(private = "file")
_clear_interval :: proc(self: ^Loop, id: u64) {
    _cancel(self, id)
}

@(private = "file")
_pending :: proc(self: ^Loop) -> int {
    return len(self.timers)
}

@(private = "file")
_update :: proc(self: ^Loop, now: Maybe(time.Tick) = nil, budget := DEFAULT_BUDGET) {
    if len(self.timers) == 0 do return

    start := time.tick_now()
    now := now.? or_else start

    if time.tick_diff(self.timers[0].deadline, now) < 0 do return

    fired := 0

    for len(self.timers) > 0 {
        if _over_budget(budget, start, fired) do break

        next := self.timers[0]
        if time.tick_diff(next.deadline, now) < 0 do break

        ordered_remove(&self.timers, 0)

        if next.callback != nil {
            self.firing = next
            next.callback(next.ctx)
            self.firing = nil
            fired += 1
        }

        if next.cancelled {
            free(next)
            continue
        }

        if next.interval > 0 {
            deadline := time.tick_add(next.deadline, next.interval)
            if time.tick_diff(deadline, now) >= next.interval * STALL_INTERVALS {
                deadline = time.tick_add(now, next.interval)
            }
            next.deadline = deadline
            _insert_sorted(self, next)
        } else {
            free(next)
        }
    }
}

@(private = "file")
_schedule :: proc(l: ^Loop, callback: Callback, delay: time.Duration, interval: time.Duration, ctx: rawptr) -> u64 {
    l.next_id += 1
    id := l.next_id

    t := new(Timer)
    t.id = id
    t.deadline = time.tick_add(time.tick_now(), delay)
    t.interval = interval
    t.callback = callback
    t.ctx = ctx
    _insert_sorted(l, t)
    return id
}

@(private = "file")
_cancel :: proc(l: ^Loop, id: u64) {
    if l.firing != nil && l.firing.id == id {
        l.firing.cancelled = true
        return
    }
    for t, i in l.timers {
        if t.id == id {
            ordered_remove(&l.timers, i)
            free(t)
            return
        }
    }
}

@(private = "file")
_insert_sorted :: proc(l: ^Loop, t: ^Timer) {
    lo, hi := 0, len(l.timers)
    for lo < hi {
        mid := (lo + hi) / 2
        if time.tick_diff(l.timers[mid].deadline, t.deadline) >= 0 {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    inject_at(&l.timers, lo, t)
}

@(private = "file")
_over_budget :: proc(budget: Budget, start: time.Tick, fired: int) -> bool {
    if budget.max_fires > 0 && fired >= budget.max_fires do return true
    if budget.duration > 0 && fired > 0 {
        return time.tick_since(start) >= budget.duration
    }
    return false
}
