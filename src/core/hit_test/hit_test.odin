package hit_test

import "src:core/common"
import "src:core/paint"

hit_test :: proc(root: ^Node, x, y: f32) -> ^Node {
    if root == nil || root.freed do return nil
    ctx := paint.build(root)
    return hit_ctx(&ctx, x, y)
}

@(private)
hit_ctx :: proc(ctx: ^paint.Stacking_Context, x, y: f32) -> ^Node {
    for a in ctx.clips {
        if !transformed_clip_contains(a, ctx.clip_inverse, ctx.clip_invertible, x, y) do return nil
    }
    n := ctx.node
    if n.clip_mode == .None || transformed_clip_contains(n, ctx.inverse, ctx.invertible, x, y) {
        #reverse for &c in ctx.pos {
            if hit := hit_ctx(&c, x, y); hit != nil do return hit
        }
        if hit := hit_flow(n, ctx.inverse, ctx.invertible, x, y); hit != nil do return hit
        #reverse for &c in ctx.neg {
            if hit := hit_ctx(&c, x, y); hit != nil do return hit
        }
    }
    if transformed_contains(n, ctx.inverse, ctx.invertible, x, y) do return n
    return nil
}

@(private)
hit_flow :: proc(n: ^Node, inverse: common.Mat3x3, invertible: bool, x, y: f32) -> ^Node {
    #reverse for c in n.children {
        if c.freed || paint.is_stacking_context(c) do continue
        if c.clip_mode == .None || transformed_clip_contains(c, inverse, invertible, x, y) {
            if hit := hit_flow(c, inverse, invertible, x, y); hit != nil do return hit
        }
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
