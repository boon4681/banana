package mouse

import "core:time"
import "src:core/signal"

Delta :: struct {
    dx, dy: f64,
}

Sample :: struct {
    dx, dy: f64,
    // seconds on the monotonic clock, samples read in one batch share the same time
    time:   f64,
}

// One reader's view of mouse motion, created by `motion`.
// Readers don't affect each other.
Motion :: struct {
    take:      proc(m: ^Motion) -> Delta,
    drain:     proc(m: ^Motion) -> []Sample,
    _read:     u64,
    _notified: u64,
    _total:    Delta,
    _source:   ^signal.Source(^Motion),
}

@(private)
RING :: 4096

@(private)
_Entry :: struct {
    sample: Sample,
    // running total up to and including this sample
    total:  Delta,
}

@(private, thread_local)
_ring: []_Entry

@(private, thread_local)
_head: u64

@(private, thread_local)
_total: Delta

@(private, thread_local)
_readers: [dynamic]^Motion

// gives a source of raw mouse motion, notified once per frame if the mouse moved.
// raw input stay on while any reader is alive, destroy the source when you're done.
motion :: proc() -> ^signal.Source(^Motion) {
    m := new(Motion)
    m.take = _take
    m.drain = _drain
    m._read = _head
    m._notified = _head
    m._total = _total
    // detach so the running effect dont own the reader, whoever hold the source does
    saved := signal.detach()
    m._source = signal.state(m)
    signal.attach(saved)
    signal.on_destroy(m._source, proc(source: rawptr) {
        s := cast(^signal.Source(^Motion))source
        _forget(s.value)
    })
    append(&_readers, m)
    return m._source
}

wanted :: proc() -> bool {
    return len(_readers) > 0
}

push :: proc(dx, dy: f64, at: time.Tick) {
    if len(_readers) == 0 do return
    if _ring == nil do _ring = make([]_Entry, RING)
    _total.dx += dx
    _total.dy += dy
    // buffered raw input has no timestamp of its own, so `at` is when the batch was read
    _ring[_head % RING] = {
        sample = {dx = dx, dy = dy, time = time.duration_seconds(time.Duration(at._nsec))},
        total  = _total,
    }
    _head += 1
}

// notifies the readers that got new motion, call it once per frame after input is read.
publish :: proc() {
    for m in _readers {
        if m._notified == _head do continue
        m._notified = _head
        signal.notify(m._source)
    }
}

@(private)
_take :: proc(m: ^Motion) -> Delta {
    d := Delta{_total.dx - m._total.dx, _total.dy - m._total.dy}
    m._read = _head
    m._total = _total
    return d
}

@(private)
_drain :: proc(m: ^Motion) -> []Sample {
    from := max(m._read, _head - min(_head, RING))
    out := make([]Sample, int(_head - from), context.temp_allocator)
    for &sample, i in out do sample = _ring[(from + u64(i)) % RING].sample
    // the reader fell so far behind that the ring overwrote some samples
    // add the motion it missed into the first sample, using the running totals
    if from > m._read && len(out) > 0 {
        first := _ring[from % RING]
        out[0].dx += first.total.dx - first.sample.dx - m._total.dx
        out[0].dy += first.total.dy - first.sample.dy - m._total.dy
    }
    m._read = _head
    m._total = _total
    return out
}

@(private)
_forget :: proc(m: ^Motion) {
    for reader, i in _readers {
        if reader != m do continue
        unordered_remove(&_readers, i)
        break
    }
    free(m)
    if len(_readers) == 0 {
        delete(_readers)
        delete(_ring)
        _readers, _ring = nil, nil
    }
}
