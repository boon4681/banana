package paint

import "src:core/common"
import "src:core/node"
import "src:core/painter"
import "src:core/redraw"
import "src:core/render"
import "src:core/text"

// paints a node tree in stacking order, back to front.
// hit_test walk the same order front to back, change both together.
draw :: proc(p: painter.Painter, root: ^Node) {
    prev := painter.set_active(p)
    defer painter.set_active(prev)
    box, whole := redraw.painted()
    // new glyph atlas rows only reach the GPU when text is drawn,
    // so a frame with new rows repaint everything or a skipped text node lose its glyphs
    lo, hi := text.msdf_atlas_dirty_rows()
    _part = nil if whole || hi > lo else box
    build_start := common.profile_begin(.Build_Ctx)
    ctx := build(root)
    common.profile_end(.Build_Ctx, build_start)
    draw_ctx(p, &ctx)
    // clear only after the whole walk, text drawn later in this frame still need to see the new rows as dirty
    text.msdf_atlas_clear_dirty()
}

// the part of the window this frame repaint, nil when it's the whole window
@(private="file", thread_local)
_part: Maybe(redraw.Box)

// true when something drawn in r can touch the part being repainted
@(private="file")
_reaches :: proc(world: common.Mat3x3, r: common.Rect) -> bool {
    part, partial := _part.?
    if !partial do return true
    if r.w <= 0 || r.h <= 0 do return false
    // the painter clip every draw anyway, this only skip the ones that would be cut away whole
    lo, hi := [2]f32{max(f32), max(f32)}, [2]f32{min(f32), min(f32)}
    for corner in ([4][2]f32{{r.x, r.y}, {r.x + r.w, r.y}, {r.x + r.w, r.y + r.h}, {r.x, r.y + r.h}}) {
        at := world * [3]f32{corner.x, corner.y, 1}
        lo = {min(lo.x, at.x), min(lo.y, at.y)}
        hi = {max(hi.x, at.x), max(hi.y, at.y)}
    }
    return lo.x < part[2] && hi.x > part[0] && lo.y < part[3] && hi.y > part[1]
}

@(private="file")
draw_ctx :: proc(p: painter.Painter, ctx: ^Stacking_Context) {
    n := ctx.node
    for a in ctx.clips do painter.push_clip(p, node.Clip_Rect(a), a.clip_mode, a.clip_radius)
    transform := node.Resolve_Transform(n)
    transformed := transform != common.IDENTITY_TRANSFORM
    if transformed do painter.push_transform(p, transform, {n.rect.x, n.rect.y})
    filter, layered := node.Resolve_Filter(n)
    if layered do painter.push_layer(p, extent(n, n.rect), filter)

    redraw.check_node(n)
    if n.draw != nil && _reaches(ctx.world, n->paint_box()) {
        draw_start := common.profile_begin(.Node_Draw)
        n->draw()
        common.profile_end(.Node_Draw, draw_start)
    }
    clipped := n.clip_mode != .None
    if clipped do painter.push_clip(p, node.Clip_Rect(n), n.clip_mode, n.clip_radius)
    for &c in ctx.neg do draw_ctx(p, &c)
    draw_flow(p, n, ctx.world)
    draw_bars(p, ctx, 0)
    for &c, i in ctx.pos {
        draw_ctx(p, &c)
        draw_bars(p, ctx, i + 1)
    }
    if n.scroll != nil && n.scroll.draw != nil do n.scroll.draw(n)
    if clipped do painter.pop_clip(p)

    if layered do painter.pop_layer(p)
    if transformed do painter.pop_transform(p)
    for _ in ctx.clips do painter.pop_clip(p)
}

// draw the scrollbars that sit between positive z-index layers, drawn is how many of those layers are already painted
@(private="file")
draw_bars :: proc(p: painter.Painter, ctx: ^Stacking_Context, drawn: int) {
    for bar in ctx.bars {
        // not simply last, a bar must cover its scroller's sticky children
        // but stay under later layers, like a sticky bar of the page
        after := 0
        for layer, i in ctx.pos {
            for at := layer.node.parent; at != nil && at != ctx.node; at = at.parent {
                if at == bar.node do after = i + 1
            }
        }
        if after != drawn do continue
        for a in bar.clips do painter.push_clip(p, node.Clip_Rect(a), a.clip_mode, a.clip_radius)
        bar.node.scroll.draw(bar.node)
        for _ in bar.clips do painter.pop_clip(p)
    }
}

@(private="file")
extent :: proc(n: ^Node, around: common.Rect) -> common.Rect {
    out := around
    if n.clip_mode != .None && n.clip_x && n.clip_y do return out
    for c in n.children {
        if c.freed || node.is_hidden(c) do continue
        lo := [2]f32{min(out.x, c.rect.x), min(out.y, c.rect.y)}
        hi := [2]f32{max(out.x + out.w, c.rect.x + c.rect.w), max(out.y + out.h, c.rect.y + c.rect.h)}
        out = extent(c, {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y})
    }
    return out
}

@(private="file")
draw_flow :: proc(p: painter.Painter, n: ^Node, world: common.Mat3x3) {
    for c in n.children {
        if c.freed || node.is_hidden(c) || is_stacking_context(c) do continue
        redraw.check_node(c)
        if c.draw != nil && _reaches(world, c->paint_box()) {
            draw_start := common.profile_begin(.Node_Draw)
            c->draw()
            common.profile_end(.Node_Draw, draw_start)
        }
        if c.clip_mode != .None {
            // nothing under a clip draw outside it, so skip the subtree when the clip miss the repaint
            // fixed position children are their own stacking context, so they still get drawn elsewhere
            if !_reaches(world, node.Clip_Rect(c)) do continue
            painter.push_clip(p, node.Clip_Rect(c), c.clip_mode, c.clip_radius)
            draw_flow(p, c, world)
            painter.pop_clip(p)
        } else {
            draw_flow(p, c, world)
        }
    }
}
