package paint

import "base:runtime"
import "core:slice"
import "src:core/node"
import "src:core/common"

Node :: node.BaseNode

Stacking_Context :: struct {
    node: ^Node,
    // the transforms from the root down to this context, for this frame
    local:      common.Mat3x3,
    world:      common.Mat3x3,
    inverse:    common.Mat3x3,
    invertible: bool,

    clip_inverse:    common.Mat3x3,
    clip_invertible: bool,
    clips: []^Node,
    neg:   []Stacking_Context,
    pos:   []Stacking_Context,
    bars:  []Pending,
}

is_stacking_context :: proc(n: ^Node) -> bool {
    if n.parent == nil do return true
    if n.creates_stacking_context || n.z_index != 0 do return true
    if n._internal_style == nil do return false
    s := cast(^node.Style)n._internal_style
    return s.filter != nil || s.sticky != nil || s.fixed || s.transform != common.IDENTITY_TRANSFORM
}

build :: proc(root: ^Node, allocator := context.temp_allocator) -> Stacking_Context {
    return build_ctx(root, nil, common.Mat3X3_IDENTITY, allocator)
}

@(private)
Pending :: struct {
    node:  ^Node,
    clips: []^Node,
}

@(private)
build_ctx :: proc(n: ^Node, clips: []^Node, parent_world: common.Mat3x3, allocator: runtime.Allocator) -> Stacking_Context {
    local := common.transform_at_matrix(node.Resolve_Transform(n),{n.rect.x, n.rect.y})
    world := parent_world * local
    inverse, invertible := common.affine_inverse(world)
    clip_inverse, clip_invertible := common.affine_inverse(parent_world)
    ctx := Stacking_Context{
        node = n,
        local = local,
        world = world,
        inverse = inverse,
        invertible = invertible,
        clip_inverse = clip_inverse,
        clip_invertible = clip_invertible,
        clips = clips,
    }

    neg := make([dynamic]Pending, context.temp_allocator)
    pos := make([dynamic]Pending, context.temp_allocator)
    clip_stack := make([dynamic]^Node, context.temp_allocator)
    bars := make([dynamic]Pending, allocator)
    collect(n, &clip_stack, &neg, &pos, &bars, allocator)
    ctx.bars = bars[:]

    // stable sort cuz css keep tree order for equal z-index
    slice.stable_sort_by(neg[:], less_z)
    slice.stable_sort_by(pos[:], less_z)

    ctx.neg = make([]Stacking_Context, len(neg), allocator)
    for p, i in neg do ctx.neg[i] = build_ctx(p.node, p.clips, world, allocator)
    ctx.pos = make([]Stacking_Context, len(pos), allocator)
    for p, i in pos do ctx.pos[i] = build_ctx(p.node, p.clips, world, allocator)
    return ctx
}

@(private)
collect :: proc(
    n: ^Node,
    clip_stack: ^[dynamic]^Node,
    neg, pos, bars: ^[dynamic]Pending,
    allocator: runtime.Allocator
) {
    for c in n.children {
        if c.freed || node.is_hidden(c) do continue
        if is_stacking_context(c) {
            // a fixed node is placed from the window, so the boxes around it dont clip it
            p := Pending{node = c, clips = nil if node.Resolve_Fixed(c) else slice.clone(clip_stack[:], allocator)}
            append(c.z_index < 0 ? neg : pos, p)
        } else {
            pushed := c.clip_mode != .None
            if pushed do append(clip_stack, c)
            if c.scroll != nil && c.scroll.draw != nil {
                append(bars, Pending{node = c, clips = slice.clone(clip_stack[:], allocator)})
            }
            collect(c, clip_stack, neg, pos, bars, allocator)
            if pushed do pop(clip_stack)
        }
    }
}

@(private)
less_z :: proc(a, b: Pending) -> bool {
    return a.node.z_index < b.node.z_index
}
