package paint

import "src:core/common"
import "src:core/node"
import "src:core/painter"
import "src:core/render"

// paints a node tree through a painter instance in stacking order.
// Same walk as hit_test, back-to-front.
draw :: proc(p: painter.Painter, root: ^Node) {
    prev := painter.set_active(p)
    defer painter.set_active(prev)
    ctx := build(root)
    draw_ctx(p, &ctx)
}

@(private="file")
draw_ctx :: proc(p: painter.Painter, ctx: ^Stacking_Context) {
    n := ctx.node
    for a in ctx.clips do painter.push_clip(p, _clip_rect(a), a.clip_mode)
    transformed := n.transform != common.IDENTITY_TRANSFORM
    if transformed do painter.push_transform(p, n.transform, {n.rect.x, n.rect.y})

    if n.draw != nil do n->draw()
    clipped := n.clip_mode != .None
    if clipped do painter.push_clip(p, _clip_rect(n), n.clip_mode)
    for &c in ctx.neg do draw_ctx(p, &c)
    draw_flow(p, n)
    for &c in ctx.pos do draw_ctx(p, &c)
    if clipped do painter.pop_clip(p)

    if transformed do painter.pop_transform(p)
    for _ in ctx.clips do painter.pop_clip(p)
}

@(private="file")
draw_flow :: proc(p: painter.Painter, n: ^Node) {
    for c in n.children {
        if c.freed || is_stacking_context(c) do continue
        if c.draw != nil do c->draw()
        if c.clip_mode != .None {
            painter.push_clip(p, _clip_rect(c), c.clip_mode)
            draw_flow(p, c)
            painter.pop_clip(p)
        } else {
            draw_flow(p, c)
        }
    }
}

// clip_rect offsets are node-local; absent means the whole border box.
@(private="file")
_clip_rect :: proc(n: ^Node) -> common.Rect {
    if cr, ok := n.clip_rect.?; ok {
        return {n.rect.x + cr.x, n.rect.y + cr.y, cr.w, cr.h}
    }
    return n.rect
}

