package redraw

import "base:intrinsics"
import "core:fmt"
import "core:mem"

// -define:BANANA_REDRAW_CHECK=true paints every frame and reports a frame whose output changed although nothing was marked.
CHECK :: #config(BANANA_REDRAW_CHECK, false)

@(private)
Node_Hash :: struct {
    node: rawptr,
    hash: u64,
}

Check_State :: struct {
    marked:   bool,
    running:  u64,
    now:      [dynamic]Node_Hash,
    before:   [dynamic]Node_Hash,
    compared: bool,
    reported: map[rawptr]bool,
}

// Names a node in a report; set by the package that owns the tree.
name_of: proc(node: rawptr) -> string

@(private)
FNV_OFFSET :: u64(0xcbf29ce484222325)

@(private)
FNV_PRIME :: u64(0x100000001b3)

hash :: proc(value: $T) {
    when CHECK {
        value := value
        hash_bytes(mem.ptr_to_bytes(&value))
    }
}

hash_slice :: proc(values: $S/[]$T) {
    when CHECK do hash_bytes(mem.slice_to_bytes(values))
}

hash_bytes :: proc(bytes: []u8) {
    when CHECK {
        s := _current
        if s == nil || !s.painting do return
        h := s.check.running
        for b in bytes do h = (h ~ u64(b)) * FNV_PRIME
        s.check.running = h
    }
}

check_node :: proc(node: rawptr) {
    when CHECK {
        s := _current
        if s == nil || !s.painting do return
        append(&s.check.now, Node_Hash{node = node, hash = s.check.running})
    }
}

@(private)
_check_begin :: proc(s: ^State) {
    when CHECK {
        s.check.marked = s.mode == .Continuous || s.dirty || intrinsics.atomic_load(&s.requested)
        s.check.running = FNV_OFFSET
        clear(&s.check.now)
    }
}

@(private)
_check_end :: proc(s: ^State) {
    when CHECK {
        c := &s.check
        append(&c.now, Node_Hash{hash = c.running})
        if !c.marked && c.compared do _report(c)
        c.now, c.before = c.before, c.now
        c.compared = true
    }
}

@(private)
_report :: proc(c: ^Check_State) {
    culprit: rawptr
    differs := len(c.now) != len(c.before)
    for entry, i in c.now {
        if i >= len(c.before) do break
        if entry.hash != c.before[i].hash || entry.node != c.before[i].node {
            differs = true
            if i > 0 do culprit = c.now[i - 1].node
            break
        }
    }
    if !differs || c.reported[culprit] do return
    c.reported[culprit] = true
    name := "the tree"
    if culprit != nil do name = name_of(culprit) if name_of != nil else fmt.tprintf("%p", culprit)
    fmt.eprintfln("redraw: %s changed with no mark", name)
}

@(private)
_check_destroy :: proc(s: ^State) {
    delete(s.check.now)
    delete(s.check.before)
    delete(s.check.reported)
}
