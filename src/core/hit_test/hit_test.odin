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
        if !clip_contains(a, x, y) do return nil
    }
    n := ctx.node
    if n.clip_mode == .None || clip_contains(n, x, y) {
        #reverse for &c in ctx.pos {
            if hit := hit_ctx(&c, x, y); hit != nil do return hit
        }
        if hit := hit_flow(n, x, y); hit != nil do return hit
        #reverse for &c in ctx.neg {
            if hit := hit_ctx(&c, x, y); hit != nil do return hit
        }
    }
    if contains(n, x, y) do return n
    return nil
}

@(private)
hit_flow :: proc(n: ^Node, x, y: f32) -> ^Node {
    #reverse for c in n.children {
        if c.freed || paint.is_stacking_context(c) do continue
        if c.clip_mode == .None || clip_contains(c, x, y) {
            if hit := hit_flow(c, x, y); hit != nil do return hit
        }
        if contains(c, x, y) do return c
    }
    return nil
}

@(private)
contains :: proc(n: ^Node, x, y: f32) -> bool {
    return common.rect_intersect(n.rect, x, y)
}

@(private)
clip_contains :: proc(n: ^Node, x, y: f32) -> bool {
    if cr, ok := n.clip_rect.?; ok {
        return common.rect_intersect(Rect{n.rect.x + cr.x, n.rect.y + cr.y, cr.w, cr.h}, x, y)
    }
    return contains(n, x, y)
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
