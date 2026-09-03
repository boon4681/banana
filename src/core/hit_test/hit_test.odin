package hit_test

import "src:core/common"
import "src:core/node"
import "src:core/paint"

@(private, thread_local)
_cache_root: ^Node

@(private, thread_local)
_cache: paint.Stacking_Context

@(private, thread_local)
_cache_valid: bool

Hit_Options :: struct {
    ignore_pointer_events: bool,
    //
    skip: ^Node,
}

invalidate :: proc() {
    _cache_valid = false
    _cache_root = nil
}

hit_test :: proc(root: ^Node, x, y: f32, opts := Hit_Options{}) -> ^Node {
    if root == nil || root.freed do return nil
    start := common.profile_begin(.Hit_Test)
    if !_cache_valid || _cache_root != root {
        _cache = paint.build(root)
        _cache_root = root
        _cache_valid = true
    }
    result := hit_ctx(&_cache, x, y, opts)
    common.profile_end(.Hit_Test, start)
    return result
}

@(private)
hit_ctx :: proc(ctx: ^paint.Stacking_Context, x, y: f32, opts: Hit_Options) -> ^Node {
    n := ctx.node
    if n == opts.skip do return nil
    for a in ctx.clips {
        if !transformed_clip_contains(a, ctx.clip_inverse, ctx.clip_invertible, x, y) do return nil
    }
    if n.clip_mode == .None || transformed_clip_contains(n, ctx.inverse, ctx.invertible, x, y) {
        #reverse for &c in ctx.pos {
            if hit := hit_ctx(&c, x, y, opts); hit != nil do return hit
        }
        if hit := hit_flow(n, ctx.inverse, ctx.invertible, x, y, opts); hit != nil do return hit
        #reverse for &c in ctx.neg {
            if hit := hit_ctx(&c, x, y, opts); hit != nil do return hit
        }
    }
    if !opts.ignore_pointer_events && node.Resolve_Pointer_Events(n) == .None do return nil
    if transformed_contains(n, ctx.inverse, ctx.invertible, x, y) do return n
    return nil
}

@(private)
hit_flow :: proc(n: ^Node, inverse: common.Mat3x3, invertible: bool, x, y: f32, opts: Hit_Options) -> ^Node {
    #reverse for c in n.children {
        if c.freed || node.is_hidden(c) || c == opts.skip || paint.is_stacking_context(c) do continue
        if c.clip_mode == .None || transformed_clip_contains(c, inverse, invertible, x, y) {
            if hit := hit_flow(c, inverse, invertible, x, y, opts); hit != nil do return hit
        }
        if !opts.ignore_pointer_events && node.Resolve_Pointer_Events(c) == .None do continue
        if transformed_contains(c, inverse, invertible, x, y) do return c
    }
    return nil
}

@(private)
transformed_contains :: proc(n: ^Node, inverse: common.Mat3x3, invertible: bool, x, y: f32) -> bool {
    if !invertible do return false
    p := common.transform_point(inverse, {x, y})
    return common.rect_intersect(n.rect, p.x, p.y)
}

@(private)
transformed_clip_contains :: proc(n: ^Node, inverse: common.Mat3x3, invertible: bool, x, y: f32) -> bool {
    if !invertible do return false
    p := common.transform_point(inverse, {x, y})
    return common.rect_intersect(paint.clip_rect(n), p.x, p.y)
}

world_matrix :: proc(n: ^Node) -> common.Mat3x3 {
    if n == nil do return common.Mat3X3_IDENTITY
    local := common.transform_at_matrix(n.transform, {n.rect.x, n.rect.y})
    return world_matrix(n.parent) * local
}

to_local :: proc(n: ^Node, x, y: f32) -> (f32, f32) {
    inverse, invertible := common.affine_inverse(world_matrix(n))
    if !invertible do return x, y
    p := common.transform_point(inverse, {x, y})
    return p.x, p.y
}

ancestor_chain :: proc(target: ^Node) -> []^Node {
    depth := 0
    for n := target; n != nil; n = n.parent do depth += 1
    chain := make([]^Node, depth, context.temp_allocator)
    i := depth - 1
    for n := target; n != nil; n = n.parent {
        chain[i] = n
        i -= 1
    }
    return chain
}
