package paint

import "base:runtime"
import "core:slice"
import "src:core/node"
import "src:core/common"

Node :: node.Node

// Stacking-context tree per CSS 2.1 Appendix E (+ flexbox z-index rules).
// z-index hoisting reorders whole groups; a hoisted group stays inside its
// ancestors' clips and transforms. Painter and hit testing both consume this.
// Paint order, with `clips` then node's transform wrapping everything:
// node's background, then (gated by node's own clip_mode) neg contexts,
// in-flow descendants in tree order, pos contexts.
Stacking_Context :: struct {
    node: ^Node,
	// Clipping in-flow ancestors between the parent context
    clips: []^Node,
    neg:   []Stacking_Context,
    pos:   []Stacking_Context,
}

is_stacking_context :: proc(n: ^Node) -> bool {
    if n.parent == nil do return true
    if n.creates_stacking_context do return true
    if n.z_index != 0 do return true
    if n.transform != common.IDENTITY_TRANSFORM do return true
    return false
}

build :: proc(root: ^Node, allocator := context.temp_allocator) -> Stacking_Context {
    return build_ctx(root, nil, allocator)
}

@(private)
Pending :: struct {
    node:  ^Node,
    clips: []^Node,
}

@(private)
build_ctx :: proc(n: ^Node, clips: []^Node, allocator: runtime.Allocator) -> Stacking_Context {
    ctx := Stacking_Context{node = n, clips = clips}

    neg := make([dynamic]Pending, context.temp_allocator)
    pos := make([dynamic]Pending, context.temp_allocator)
    clip_stack := make([dynamic]^Node, context.temp_allocator)
    collect(n, &clip_stack, &neg, &pos, allocator)

    // Stable: CSS keeps tree order for equal z-index.
    slice.stable_sort_by(neg[:], less_z)
    slice.stable_sort_by(pos[:], less_z)

    ctx.neg = make([]Stacking_Context, len(neg), allocator)
    for p, i in neg do ctx.neg[i] = build_ctx(p.node, p.clips, allocator)
    ctx.pos = make([]Stacking_Context, len(pos), allocator)
    for p, i in pos do ctx.pos[i] = build_ctx(p.node, p.clips, allocator)
    return ctx
}

@(private)
collect :: proc(
    n: ^Node,
    clip_stack: ^[dynamic]^Node,
    neg, pos: ^[dynamic]Pending,
    allocator: runtime.Allocator
) {
    for c in n.children {
        if c.freed do continue
        if is_stacking_context(c) {
            p := Pending{node = c, clips = slice.clone(clip_stack[:], allocator)}
            append(c.z_index < 0 ? neg : pos, p)
        } else {
            pushed := c.clip_mode != .None
            if pushed do append(clip_stack, c)
            collect(c, clip_stack, neg, pos, allocator)
            if pushed do pop(clip_stack)
        }
    }
}

@(private)
less_z :: proc(a, b: Pending) -> bool {
    return a.node.z_index < b.node.z_index
}
