package painter

import "base:runtime"
import "src:core/common"
import "src:core/redraw"
import "src:core/render"
import "core:math"
import "core:math/linalg"

@(private="file")
Clip_Entry :: struct {
    kind:         enum { Scissor, Stencil },
    prev_scissor: Maybe(common.Rect),
}

@(private="file")
Vector_State :: struct {
    verts:                               [dynamic]render.Vertex,
    indices:                             [dynamic]u32,
    texture:                             render.Texture,
    scissor:                             Maybe(common.Rect),
    clips:                               [dynamic]Clip_Entry,
    clip_edges:                          [dynamic]render.Clip_Edge,
    transforms:                          [dynamic]common.Mat3x3,
    msdf_atlas:                          render.Texture,
    msdf_atlas_version:                  u64,
    msdf_atlas_width, msdf_atlas_height: int,
    target:                              render.Render_Target,
    layers:                              [dynamic]Layer,
    layer_slots:                         [dynamic]Layer_Slot,
    // Clip edges of an outer layer are in that layer's pixels and must not reach an inner one.
    edge_base:                           int,
}

// Slots are larger than the layers they hold (rounded up to LAYER_GRID) so that a
// layer whose size changes a little each frame keeps reusing one.
@(private="file")
Layer_Slot :: struct {
    texture: render.Texture,
    target:  render.Render_Target,
    w, h:    int,
    busy:    bool,
    idle:    int,
}

@(private="file")
Layer :: struct {
    slot:      int,
    rect:      common.Rect,
    filter:    common.EffectFilter,
    scale:     f32,
    target:    render.Render_Target,
    scissor:   Maybe(common.Rect),
    edge_base: int,
    token:     int,
}

// A node's rect says nothing of what it draws past it (shadows, outlines, overflow), so a layer keeps a margin.
LAYER_BLEED :: f32(48)
@(private="file") LAYER_GRID :: 64
@(private="file") LAYER_MAX :: 8192
@(private="file") LAYER_IDLE_FRAMES :: 120

@(private="file")
_vs :: proc(p: Painter) -> ^Vector_State {
    return cast(^Vector_State)(p.state)
}

@(private = "file")
_create_state :: proc(allocator: runtime.Allocator) -> rawptr {
    return new(Vector_State, allocator)
}

@(private = "file")
_free_state :: proc(state: rawptr, allocator: runtime.Allocator) {
    if state != nil do runtime.mem_free(state, allocator)
}

@(private="file")
_init :: proc(p: Painter, allocator: runtime.Allocator) {
    v := _vs(p)
    v^ = {}
    v.verts = make([dynamic]render.Vertex, allocator)
    v.indices = make([dynamic]u32, allocator)
    v.clips = make([dynamic]Clip_Entry, allocator)
    v.transforms = make([dynamic]common.Mat3x3, allocator)
    append(&v.transforms, common.Mat3X3_IDENTITY)
}

@(private="file")
_shutdown :: proc(p: Painter) {
    v := _vs(p)
    if v == nil do return
    if v.msdf_atlas != render.INVALID_TEXTURE do render.RENDERER.destroy_texture(v.msdf_atlas)
    for slot in v.layer_slots {
        render.RENDERER.destroy_render_target(slot.target)
        render.RENDERER.destroy_texture(slot.texture)
    }
    delete(v.layer_slots)
    delete(v.layers)
    delete(v.verts)
    delete(v.indices)
    delete(v.clips)
    delete(v.clip_edges)
    delete(v.transforms)
}

@(private="file")
_begin_frame :: proc(p: Painter, color: common.Color) {
    v := _vs(p)
    v.target = render.INVALID_RENDER_TARGET
    // A partial frame keeps this scissor under every clip pushed after it, so nothing
    // drawn in it can touch the pixels kept from the last one.
    kept: Maybe(common.Rect)
    if r, whole := redraw.painted_pixels(); !whole do kept = common.Rect{r[0], r[1], r[2], r[3]}
    render.RENDERER.clear(v.target, color, kept)
    render.RENDERER.stencil_clear()
    clear(&v.verts)
    clear(&v.indices)
    clear(&v.clips)
    clear(&v.clip_edges)
    clear(&v.layers)
    v.edge_base = 0
    render.set_clip_edges(nil)
    resize(&v.transforms, 1)
    v.transforms[0] = common.Mat3X3_IDENTITY
    v.texture = render.INVALID_TEXTURE
    v.scissor = kept
}

@(private="file")
_end_frame :: proc(p: Painter) {
    v := _vs(p)
    for len(v.layers) > 0 do _pop_layer(p)
    _flush(v)
    #reverse for &slot, i in v.layer_slots {
        slot.idle = 0 if slot.busy else slot.idle + 1
        slot.busy = false
        if slot.idle <= LAYER_IDLE_FRAMES do continue
        render.RENDERER.destroy_render_target(slot.target)
        render.RENDERER.destroy_texture(slot.texture)
        unordered_remove(&v.layer_slots, i)
    }
    render.RENDERER.present()
}

@(private="file")
_layer_slot :: proc(v: ^Vector_State, w, h: int) -> int {
    grid_w := (w + LAYER_GRID - 1) / LAYER_GRID * LAYER_GRID
    grid_h := (h + LAYER_GRID - 1) / LAYER_GRID * LAYER_GRID
    for &slot, i in v.layer_slots {
        if slot.busy || slot.w != grid_w || slot.h != grid_h do continue
        slot.busy = true
        return i
    }
    texture, target := render.RENDERER.create_render_texture(grid_w, grid_h)
    append(&v.layer_slots, Layer_Slot{texture = texture, target = target, w = grid_w, h = grid_h, busy = true})
    return len(v.layer_slots) - 1
}

@(private="file")
_target_size :: proc(v: ^Vector_State) -> [2]f32 {
    if len(v.layers) > 0 {
        rect := v.layers[len(v.layers) - 1].rect
        return {rect.w, rect.h}
    }
    w, h := render.RENDERER.swapchain_size()
    return {f32(w), f32(h)}
}

@(private="file")
_sync_clip_edges :: proc(v: ^Vector_State) {
    render.set_clip_edges(v.clip_edges[v.edge_base:])
}

@(private="file")
_filter_reach :: proc(f: common.EffectFilter) -> (reach: f32) {
    reach = f.blur * 3
    for shadow in f.shadows do reach = max(reach, max(abs(shadow.x), abs(shadow.y)) + shadow.blur * 3)
    return
}

@(private="file")
_push_layer :: proc(p: Painter, bounds: common.Rect, f: common.EffectFilter) {
    v := _vs(p)
    _flush(v)
    scale := _pixel_scale(p)
    device_scale := max(scale.x, scale.y, 0.001)
    reach := _filter_reach(f)

    grow := LAYER_BLEED + reach
    corners := [4][2]f32{
        _pt(v, {bounds.x - grow, bounds.y - grow}), _pt(v, {bounds.x + bounds.w + grow, bounds.y - grow}),
        _pt(v, {bounds.x + bounds.w + grow, bounds.y + bounds.h + grow}), _pt(v, {bounds.x - grow, bounds.y + bounds.h + grow}),
    }
    lo, hi := corners[0], corners[0]
    for corner in corners {
        lo = linalg.min(lo, corner)
        hi = linalg.max(hi, corner)
    }
    size := _target_size(v)
    visible := v.scissor.? or_else common.Rect{0, 0, size.x, size.y}
    margin := reach * device_scale
    visible = {visible.x - margin, visible.y - margin, visible.w + 2 * margin, visible.h + 2 * margin}
    rect := _intersect({lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}, visible)
    rect = {math.floor(rect.x), math.floor(rect.y), math.ceil(rect.x + rect.w) - math.floor(rect.x), math.ceil(rect.y + rect.h) - math.floor(rect.y)}
    rect.w = min(rect.w, LAYER_MAX)
    rect.h = min(rect.h, LAYER_MAX)

    layer := Layer{slot = -1, rect = rect, filter = f, scale = device_scale, target = v.target, scissor = v.scissor, edge_base = v.edge_base}
    shift := common.Mat3x3{1, 0, -rect.x, 0, 1, -rect.y, 0, 0, 1}
    append(&v.transforms, shift * _top(v))
    v.edge_base = len(v.clip_edges)
    if rect.w < 1 || rect.h < 1 {
        v.scissor = common.Rect{}
    } else {
        layer.slot = _layer_slot(v, int(rect.w), int(rect.h))
        v.target = v.layer_slots[layer.slot].target
        v.scissor = nil
        render.set_clip_edges(nil)
        layer.token = render.RENDERER.layer_begin(v.target)
    }
    append(&v.layers, layer)
}

@(private="file")
_layer_quad :: proc(rect: common.Rect, offset: [2]f32, slot: Layer_Slot) -> [4]render.Vertex {
    u, t := rect.w / f32(slot.w), rect.h / f32(slot.h)
    white := common.Color{255, 255, 255, 255}
    return {
        {pos = {rect.x + offset.x, rect.y + offset.y}, uv = {0, 1}, color = white},
        {pos = {rect.x + rect.w + offset.x, rect.y + offset.y}, uv = {u, 1}, color = white},
        {pos = {rect.x + rect.w + offset.x, rect.y + rect.h + offset.y}, uv = {u, 1 - t}, color = white},
        {pos = {rect.x + offset.x, rect.y + rect.h + offset.y}, uv = {0, 1 - t}, color = white},
    }
}

// The shader has a fixed tap budget, so a wide blur spaces its taps out instead of adding more.
@(private="file")
_blur_pass :: proc(effect: ^render.Effect, sigma: f32, texel: [2]f32) {
    reach := sigma * 3
    effect.taps = clamp(int(math.ceil(reach)), 1, render.MAX_EFFECT_TAPS)
    spacing := max(reach / f32(effect.taps), 1)
    effect.step = texel * spacing
    effect.sigma = sigma / spacing
}

@(private="file")
_composite :: proc(v: ^Vector_State, layer: Layer, effect: render.Effect, sigma: f32, offset: [2]f32) {
    source := v.layer_slots[layer.slot]
    pass := effect
    if sigma > 0.05 {
        scratch_index := _layer_slot(v, int(layer.rect.w), int(layer.rect.h))
        scratch := v.layer_slots[scratch_index]
        across := render.EFFECT_COPY
        _blur_pass(&across, sigma, {1 / f32(source.w), 0})
        render.set_clip_edges(nil)
        token := render.RENDERER.layer_begin(scratch.target)
        render.RENDERER.draw_effect(scratch.target, source.texture, _layer_quad({0, 0, layer.rect.w, layer.rect.h}, 0, source), across, nil, .Opaque)
        render.RENDERER.layer_end(v.target, token)
        _sync_clip_edges(v)
        _blur_pass(&pass, sigma, {0, 1 / f32(scratch.h)})
        source = scratch
        v.layer_slots[scratch_index].busy = false
        defer v.layer_slots[scratch_index].idle = 0
    }
    render.RENDERER.draw_effect(v.target, source.texture, _layer_quad(layer.rect, offset, source), pass, v.scissor, .Premultiplied)
}

@(private="file")
_pop_layer :: proc(p: Painter) {
    v := _vs(p)
    if len(v.layers) == 0 do return
    _flush(v)
    layer := pop(&v.layers)
    if len(v.transforms) > 1 do pop(&v.transforms)
    resize(&v.clip_edges, v.edge_base)
    v.edge_base = layer.edge_base
    v.scissor = layer.scissor
    if layer.slot < 0 do return

    v.target = layer.target
    render.RENDERER.layer_end(v.target, layer.token)
    _sync_clip_edges(v)

    f := layer.filter
    #reverse for shadow in f.shadows {
        tint := render.Effect{shadow = true}
        alpha := shadow.color[3] * clamp(f.color[3][3], 0, 1)
        tint.tint = {shadow.color[0] * alpha, shadow.color[1] * alpha, shadow.color[2] * alpha, alpha}
        _composite(v, layer, tint, shadow.blur * layer.scale, {shadow.x, shadow.y} * layer.scale)
    }
    _composite(v, layer, render.Effect{color = f.color, offset = f.offset}, f.blur * layer.scale, 0)
    v.layer_slots[layer.slot].busy = false
    v.layer_slots[layer.slot].idle = 0
    when ODIN_OS == .JS do v.texture = render.INVALID_TEXTURE
}

@(private="file")
_rect :: proc(p: Painter, r: common.Rect, color: common.Color, radius: common.Radii = 0) {
    v := _vs(p)
    when ODIN_OS == .JS do _set_texture(v, render.INVALID_TEXTURE)
    rad := common.radii_fit(radius, r.w, r.h)
    if rad == 0 {
        if _axis_aligned(v) {
            _quad(v, {r.x, r.y}, {r.x + r.w, r.y}, {r.x + r.w, r.y + r.h}, {r.x, r.y + r.h}, color)
        } else {
            _edge_quad(v, {r.x, r.y}, {r.w, 0}, {0, r.h}, color, .Edge)
        }
        return
    }
    left, right := max(rad[0].x, rad[3].x), max(rad[1].x, rad[2].x)
    top, bottom := max(rad[0].y, rad[1].y), max(rad[2].y, rad[3].y)
    if left + right <= r.w && top + bottom <= r.h {
        middle := [2]f32{r.x + (left + r.w - right) * 0.5, r.y + (top + r.h - bottom) * 0.5}
        _round_rect(v, r, rad, middle, _half_pixel(p), color)
        return
    }
    h := _half_pixel(p)
    segs := _segs(p, common.radii_max(rad))
    outer := _perimeter(_inset(r, -h), rad + h, segs)
    inner := _perimeter(_inset(r, h), common.radii_inset(rad, h), segs)
    clear := color
    clear.a = 0
    base := u32(len(v.verts))
    n := u32(len(outer))
    for i in 0 ..< n {
        _vert(v, outer[i], {0, 0}, clear)
        _vert(v, inner[i], {0, 0}, color)
    }
    for i in 0 ..< n {
        a := base + 2 * i
        b := base + 2 * ((i + 1) % n)
        append(&v.indices, a, a + 1, b, a + 1, b + 1, b)
        if i > 0 && i + 1 < n do append(&v.indices, base + 1, a + 1, b + 1)
    }
}

@(private="file")
_axis_aligned :: proc(v: ^Vector_State) -> bool {
    m := _top(v)
    return m[1, 0] == 0 && m[0, 1] == 0
}

@(private="file")
_edge_quad :: proc(v: ^Vector_State, origin, ex, ey: [2]f32, color: common.Color, mode: render.Vertex_Mode) {
    lx, ly := linalg.length(ex), linalg.length(ey)
    if lx == 0 || ly == 0 do return
    m := _top(v)
    dx, dy := ex / lx, ey / ly
    px := linalg.length([2]f32{m[0, 0] * dx.x + m[0, 1] * dx.y, m[1, 0] * dx.x + m[1, 1] * dx.y})
    py := linalg.length([2]f32{m[0, 0] * dy.x + m[0, 1] * dy.y, m[1, 0] * dy.x + m[1, 1] * dy.y})
    if px == 0 || py == 0 do return
    hx, hy := dx * (0.5 / px), dy * (0.5 / py)
    ux, uy := 0.5 / px / lx, 0.5 / py / ly
    base := u32(len(v.verts))
    _vert(v, origin - hx - hy, {-ux, -uy}, color, mode)
    _vert(v, origin + ex + hx - hy, {1 + ux, -uy}, color, mode)
    _vert(v, origin + ex + ey + hx + hy, {1 + ux, 1 + uy}, color, mode)
    _vert(v, origin + ey - hx + hy, {-ux, 1 + uy}, color, mode)
    append(&v.indices, base, base + 1, base + 2, base, base + 2, base + 3)
}

@(private="file")
_SHARP_CORNER :: f32(1.0 / 64)

@(private="file")
_corners :: proc(r: common.Rect) -> [4][2][2]f32 {
    return {
        {{r.x, r.y}, {1, 1}},
        {{r.x + r.w, r.y}, {-1, 1}},
        {{r.x + r.w, r.y + r.h}, {-1, -1}},
        {{r.x, r.y + r.h}, {1, -1}},
    }
}

@(private="file")
_round_rect :: proc(v: ^Vector_State, r: common.Rect, radii: common.Radii, middle: [2]f32, h: f32, color: common.Color, mode: render.Vertex_Mode = .Round) {
    for corner, i in _corners(r) {
        at, inward := corner[0], corner[1]
        rad := [2]f32{max(radii[i].x, _SHARP_CORNER), max(radii[i].y, _SHARP_CORNER)}
        o := (rad + h) / rad
        xs := [3]f32{at.x - inward.x * h, at.x + inward.x * rad.x, middle.x}
        ys := [3]f32{at.y - inward.y * h, at.y + inward.y * rad.y, middle.y}
        base := u32(len(v.verts))
        for y, j in ys {
            for x, k in xs {
                _vert(v, {x, y}, {o.x if k == 0 else 0, o.y if j == 0 else 0}, color, mode)
            }
        }
        for j in u32(0) ..< 2 {
            for k in u32(0) ..< 2 {
                a := base + j * 3 + k
                append(&v.indices, a, a + 1, a + 4, a, a + 4, a + 3)
            }
        }
    }
}

// Circular corners only: the ring's inner edge is one radius in the shader.
@(private="file")
_round_border :: proc(v: ^Vector_State, r: common.Rect, corners: common.Radii, w, h: f32, color: common.Color) {
    radii := [4]f32{corners[0].x, corners[1].x, corners[2].x, corners[3].x}
    split_x := [4]f32{
        r.x + (radii[0] + r.w - radii[1]) * 0.5, r.x + (radii[0] + r.w - radii[1]) * 0.5,
        r.x + (radii[3] + r.w - radii[2]) * 0.5, r.x + (radii[3] + r.w - radii[2]) * 0.5,
    }
    split_y := [4]f32{
        r.y + (radii[0] + r.h - radii[3]) * 0.5, r.y + (radii[1] + r.h - radii[2]) * 0.5,
        r.y + (radii[1] + r.h - radii[2]) * 0.5, r.y + (radii[0] + r.h - radii[3]) * 0.5,
    }
    d := w + h
    for corner, i in _corners(r) {
        middle := [2]f32{split_x[i], split_y[i]}
        at, inward := corner[0], corner[1]
        rad := radii[i]
        mode := render.Vertex_Mode(u32(render.Vertex_Mode.Round) | u32((rad - w) / rad * 65535) << 16)
        o := (rad + h) / rad
        t := (rad - w - h) / rad
        outer := at - inward * h
        center := at + inward * rad
        base := u32(len(v.verts))
        _vert(v, {center.x, outer.y}, {0, o}, color, mode)
        _vert(v, center, {0, 0}, color, mode)
        _vert(v, {outer.x, center.y}, {o, 0}, color, mode)
        _vert(v, outer, {o, o}, color, mode)
        append(&v.indices, base, base + 1, base + 3, base + 1, base + 2, base + 3)

        base = u32(len(v.verts))
        _vert(v, {center.x, outer.y}, {0, o}, color, mode)
        _vert(v, {middle.x, outer.y}, {0, o}, color, mode)
        _vert(v, {middle.x, at.y + inward.y * d}, {0, t}, color, mode)
        _vert(v, {center.x, at.y + inward.y * d}, {0, t}, color, mode)
        append(&v.indices, base, base + 1, base + 2, base, base + 2, base + 3)

        base = u32(len(v.verts))
        _vert(v, {outer.x, center.y}, {0, o}, color, mode)
        _vert(v, {outer.x, middle.y}, {0, o}, color, mode)
        _vert(v, {at.x + inward.x * d, middle.y}, {0, t}, color, mode)
        _vert(v, {at.x + inward.x * d, center.y}, {0, t}, color, mode)
        append(&v.indices, base, base + 1, base + 2, base, base + 2, base + 3)
    }
}

@(private="file")
_shadow :: proc(p: Painter, r: common.Rect, radius: common.Radii, s: common.EffectShadow, alpha: f32 = 1) {
    color := common.color_from_floats(s.color, alpha)
    if color.a == 0 || s.inset do return
    v := _vs(p)
    when ODIN_OS == .JS do _set_texture(v, render.INVALID_TEXTURE)
    shape := common.Rect{r.x + s.x - s.spread, r.y + s.y - s.spread, r.w + 2 * s.spread, r.h + 2 * s.spread}
    if shape.w <= 0 || shape.h <= 0 do return
    corners := common.radii_grow(common.radii_fit(radius, r.w, r.h), s.spread)

    if s.blur <= 0.01 {
        if s.x == 0 && s.y == 0 && s.spread > 0 {
            _border(p, shape, color, s.spread, corners)
        } else {
            _rect(p, shape, color, corners)
        }
        return
    }

    // The blur falls off along one radius, so an elliptical corner is drawn circular.
    half := s.blur * 0.5
    outer := common.Rect{shape.x - half, shape.y - half, shape.w + s.blur, shape.h + s.blur}
    for &corner in corners do corner = max((corner.x + corner.y) * 0.5, half) + half
    corners = common.radii_fit(corners, outer.w, outer.h)
    smallest := common.radii_min(corners)
    inner := clamp((smallest - s.blur) / smallest, 0, 1) if smallest > 0 else 0
    mode := render.Vertex_Mode(u32(render.Vertex_Mode.Shadow) | u32(inner * 65535) << 16)
    middle := [2]f32{outer.x + outer.w * 0.5, outer.y + outer.h * 0.5}
    _round_rect(v, outer, corners, middle, 0, color, mode)
}

@(private="file")
_gradient :: proc(p: Painter, r: common.Rect, radius: common.Radii, g: common.Gradient, alpha: f32 = 1) {
    if len(g.stops) == 0 || r.w <= 0 || r.h <= 0 do return
    _push_clip(p, r, .Scissor, radius)
    defer _pop_clip(p)
    v := _vs(p)
    when ODIN_OS == .JS do _set_texture(v, render.INVALID_TEXTURE)

    angle := g.angle * math.PI / 180
    along := [2]f32{math.sin(angle), -math.cos(angle)}
    across := [2]f32{-along.y, along.x} * (r.w + r.h)
    center := [2]f32{r.x + r.w * 0.5, r.y + r.h * 0.5}
    reach := (abs(r.w * along.x) + abs(r.h * along.y)) * 0.5

    strip :: proc(v: ^Vector_State, from, to, across: [2]f32, a, b: common.Color) {
        base := u32(len(v.verts))
        _vert(v, from - across, {0, 0}, a)
        _vert(v, from + across, {0, 0}, a)
        _vert(v, to + across, {0, 0}, b)
        _vert(v, to - across, {0, 0}, b)
        append(&v.indices, base, base + 1, base + 2, base, base + 2, base + 3)
    }
    at :: proc(center, along: [2]f32, reach, position: f32) -> [2]f32 {
        return center + along * ((position * 2 - 1) * reach)
    }

    first, last := g.stops[0], g.stops[len(g.stops) - 1]
    strip(v, at(center, along, reach, -1), at(center, along, reach, first.position), across,
        common.color_from_floats(first.color, alpha), common.color_from_floats(first.color, alpha))
    for i in 1 ..< len(g.stops) {
        a, b := g.stops[i - 1], g.stops[i]
        strip(v, at(center, along, reach, a.position), at(center, along, reach, b.position), across,
            common.color_from_floats(a.color, alpha), common.color_from_floats(b.color, alpha))
    }
    strip(v, at(center, along, reach, last.position), at(center, along, reach, 2), across,
        common.color_from_floats(last.color, alpha), common.color_from_floats(last.color, alpha))
    _flush(v)
}

@(private="file")
_half_pixel :: proc(p: Painter) -> f32 {
    scale := _pixel_scale(p)
    s := max(scale.x, scale.y)
    return 0.5 / s if s > 0 else 0.5
}

@(private="file")
_inset :: proc(r: common.Rect, d: f32) -> common.Rect {
    return {r.x + d, r.y + d, max(r.w - 2 * d, 0), max(r.h - 2 * d, 0)}
}

@(private="file")
_border :: proc(p: Painter, r: common.Rect, color: common.Color, width: f32, radius: common.Radii = 0) {
    if width <= 0 do return
    v := _vs(p)
    when ODIN_OS == .JS do _set_texture(v, render.INVALID_TEXTURE)
    w := min(width, r.w * 0.5, r.h * 0.5)
    rad := common.radii_fit(radius, r.w, r.h)
    segs := _segs(p, max(common.radii_max(rad), 1))
    if rad == 0 {
        outer := _perimeter(r, rad, segs)
        inner := _perimeter(_inset(r, w), 0, segs)
        base := u32(len(v.verts))
        for pt, i in outer {
            _vert(v, pt, {0, 0}, color)
            _vert(v, inner[i], {0, 0}, color)
        }
        n := u32(len(outer))
        for i in 0 ..< n {
            j := (i + 1) % n
            o0 := base + 2 * i
            o1 := base + 2 * j
            append(&v.indices, o0, o0 + 1, o1, o0 + 1, o1 + 1, o1)
        }
        return
    }
    // Subpixel ring coverage can extend a full device pixel beyond either edge.
    border_aa := 2 * _half_pixel(p)
    if common.radii_circular(rad) && common.radii_min(rad) >= w + border_aa {
        _round_border(v, r, rad, w, border_aa, color)
        return
    }
    h := min(_half_pixel(p), w * 0.5)
    rings := [4][][2]f32{
        _perimeter(_inset(r, -h), rad + h, segs),
        _perimeter(_inset(r, h), common.radii_inset(rad, h), segs),
        _perimeter(_inset(r, w - h), common.radii_inset(rad, w - h), segs),
        _perimeter(_inset(r, w + h), common.radii_inset(rad, w + h), segs),
    }
    clear := color
    clear.a = 0
    base := u32(len(v.verts))
    n := u32(len(rings[0]))
    for i in 0 ..< n {
        _vert(v, rings[0][i], {0, 0}, clear)
        _vert(v, rings[1][i], {0, 0}, color)
        _vert(v, rings[2][i], {0, 0}, color)
        _vert(v, rings[3][i], {0, 0}, clear)
    }
    for i in 0 ..< n {
        a := base + 4 * i
        b := base + 4 * ((i + 1) % n)
        for k in u32(0) ..< 3 {
            append(&v.indices, a + k, a + k + 1, b + k, a + k + 1, b + k + 1, b + k)
        }
    }
}

@(private="file")
_image :: proc(p: Painter, image: ^render.Image, r: common.Rect, tint := common.COLOR_WHITE) {
    if image == nil do return
    texture := render.RENDERER.upload_image(image)
    if texture == render.INVALID_TEXTURE do return
    v := _vs(p)
    _set_texture(v, texture)
    if !_axis_aligned(v) {
        _edge_quad(v, {r.x, r.y}, {r.w, 0}, {0, r.h}, tint, .Edge_Texture)
        return
    }
    base := u32(len(v.verts))
    _vert(v, {r.x, r.y}, {0, 0}, tint, .Texture)
    _vert(v, {r.x + r.w, r.y}, {1, 0}, tint, .Texture)
    _vert(v, {r.x + r.w, r.y + r.h}, {1, 1}, tint, .Texture)
    _vert(v, {r.x, r.y + r.h}, {0, 1}, tint, .Texture)
    append(&v.indices, base, base + 1, base + 2, base, base + 2, base + 3)
}

@(private="file")
_line :: proc(p: Painter, a, b: [2]f32, color: common.Color, width: f32) {
    d := b - a
    length := linalg.length(d)
    if length == 0 || width <= 0 do return
    v := _vs(p)
    when ODIN_OS == .JS do _set_texture(v, render.INVALID_TEXTURE)
    n := swizzle(d, 1, 0) * [2]f32{-1, 1} / length * (width * 0.5)
    if _axis_aligned(v) && (d.x == 0 || d.y == 0) {
        _quad(v, a + n, b + n, b - n, a - n, color)
    } else {
        _edge_quad(v, a + n, d, -2 * n, color, .Edge)
    }
}

@(private="file")
_triangles :: proc(p: Painter, points: [][2]f32, indices: []u32, color: common.Color) {
    if len(points) == 0 || len(indices) < 3 do return
    v := _vs(p)
    when ODIN_OS == .JS do _set_texture(v, render.INVALID_TEXTURE)
    base := u32(len(v.verts))
    for point in points do _vert(v, point, {0, 0}, color)
    for index in indices {
        if int(index) < len(points) do append(&v.indices, base + index)
    }
}

@(private="file")
_mesh_cached :: proc(p: Painter,cache: ^Mesh_Cache,source_version: u64,vertices: []render.Vertex,indices: []u32) {
    if cache == nil do return
    v := _vs(p);_flush(v)
    m := _top(v);rebuild := !cache.valid || cache.source_version != source_version
    geometry_version := cache.mesh.version
    if rebuild {
        if len(vertices) == 0 || len(indices) == 0 do return
        cache.source_version = source_version;cache.valid = true;geometry_version += 1
    }
    submit_start := common.profile_begin(.Submit)
    render.RENDERER.draw_mesh(v.target,&cache.mesh, vertices, indices, geometry_version, m, render.INVALID_TEXTURE, v.scissor, .Alpha)
    common.profile_end(.Submit, submit_start)
}

@(private="file")
_glyphs :: proc(p: Painter, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    if len(quads) == 0 do return
    v := _vs(p)
    _flush(v)
    verts, indices := _glyph_geometry(quads, color)
    submit_start := common.profile_begin(.Submit)
    render.RENDERER.draw_glyphs(v.target,verts, indices, curves, version, _top(v), v.scissor)
    common.profile_end(.Submit, submit_start)
}

@(private="file")
_glyph_geometry :: proc(quads: []Glyph_Quad, color: common.Color) -> ([]render.Glyph_Vertex, []u32) {
    verts := make([dynamic]render.Glyph_Vertex, 0, len(quads) * 4, context.temp_allocator)
    indices := make([dynamic]u32, 0, len(quads) * 6, context.temp_allocator)
    for q in quads {
        base := u32(len(verts))
        corners := [4]struct {
            pos: [2]f32,
            uv:  [2]f32,
        } {
            {{q.rect.x, q.rect.y}, q.uv0},
            {{q.rect.x + q.rect.w, q.rect.y}, {q.uv1.x, q.uv0.y}},
            {{q.rect.x + q.rect.w, q.rect.y + q.rect.h}, q.uv1},
            {{q.rect.x, q.rect.y + q.rect.h}, {q.uv0.x, q.uv1.y}},
        }
        for c in corners {
            append(&verts, render.Glyph_Vertex{
                pos         = c.pos,
                uv          = c.uv,
                color       = color,
                curve_base  = q.curve_base,
                curve_count = q.curve_count,
            })
        }
        append(&indices, base, base + 1, base + 2, base, base + 2, base + 3)
    }
    return verts[:], indices[:]
}

@(private="file")
_glyphs_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    if cache == nil || len(quads) == 0 do return
    v := _vs(p)
    _flush(v)

    m := _top(v)
    rebuild := !cache.valid || cache.source_version != source_version || cache.color != color
    vertices: []render.Glyph_Vertex
    indices: []u32
    geometry_version := cache.mesh.version
    if rebuild {
        vertices, indices = _glyph_geometry(quads, color)
        cache.source_version = source_version
        cache.color = color
        cache.valid = true
        geometry_version += 1
    }
    submit_start := common.profile_begin(.Submit)
    render.RENDERER.draw_glyph_mesh(v.target,&cache.mesh, vertices, indices, geometry_version, m, curves, version, v.scissor)
    common.profile_end(.Submit, submit_start)
}

@(private="file")
_robin_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, data: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    if cache == nil || len(quads) == 0 || len(data) == 0 do return
    v := _vs(p)
    _flush(v)
    m := _top(v)
    rebuild := !cache.valid || cache.source_version != source_version || cache.color != color
    vertices: []render.Glyph_Vertex
    indices: []u32
    geometry_version := cache.mesh.version
    if rebuild {
        vertices, indices = _glyph_geometry(quads, color)
        cache.source_version = source_version
        cache.color = color
        cache.valid = true
        geometry_version += 1
    }
    submit_start := common.profile_begin(.Submit)
    render.RENDERER.draw_robin_mesh(v.target,&cache.mesh, vertices, indices, geometry_version, m, data, version, v.scissor)
    common.profile_end(.Submit, submit_start)
}

@(private="file")
_msdf_geometry :: proc(quads: []MSDF_Quad, color: common.Color, atlas_w, atlas_h: int) -> ([]render.Glyph_Vertex, []u32) {
    verts := make([dynamic]render.Glyph_Vertex, 0, len(quads) * 4, context.temp_allocator)
    indices := make([dynamic]u32, 0, len(quads) * 6, context.temp_allocator)
    inv_w := 1.0 / f32(atlas_w)
    inv_h := 1.0 / f32(atlas_h)
    for q in quads {
        base := u32(len(verts))
        uv := [4]f32{q.atlas[0] * inv_w, q.atlas[1] * inv_h, q.atlas[2] * inv_w, q.atlas[3] * inv_h}
        corners := [4]struct { pos, uv: [2]f32 } {
            {{q.rect.x, q.rect.y}, {uv[0], uv[3]}},
            {{q.rect.x + q.rect.w, q.rect.y}, {uv[2], uv[3]}},
            {{q.rect.x + q.rect.w, q.rect.y + q.rect.h}, {uv[2], uv[1]}},
            {{q.rect.x, q.rect.y + q.rect.h}, {uv[0], uv[1]}},
        }
        quad_color := q.tint if q.has_tint else color
        for c in corners {
            append(&verts, render.Glyph_Vertex{pos = c.pos, uv = c.uv, color = quad_color})
        }
        append(&indices, base, base + 1, base + 2, base, base + 2, base + 3)
    }
    return verts[:], indices[:]
}

@(private="file")
_msdf_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, atlas: MSDF_Atlas, quads: []MSDF_Quad, color: common.Color) {
    if cache == nil || len(quads) == 0 || len(atlas.pixels) == 0 do return
    v := _vs(p)
    _flush(v)
    if v.msdf_atlas != render.INVALID_TEXTURE &&
    (v.msdf_atlas_width != atlas.width || v.msdf_atlas_height != atlas.height) {
        render.RENDERER.destroy_texture(v.msdf_atlas)
        v.msdf_atlas = render.INVALID_TEXTURE
    }
    if v.msdf_atlas == render.INVALID_TEXTURE {
        v.msdf_atlas = render.RENDERER.create_texture(atlas.pixels, atlas.width, atlas.height, .RGBA8)
        render.RENDERER.set_texture_filter(v.msdf_atlas, .Linear, .Linear, .Linear)
        v.msdf_atlas_version = atlas.version
        v.msdf_atlas_width = atlas.width
        v.msdf_atlas_height = atlas.height
    } else if v.msdf_atlas_version != atlas.version {
        lo := clamp(atlas.dirty_lo, 0, atlas.height)
        hi := clamp(atlas.dirty_hi, 0, atlas.height)
        if hi > lo {
            row := atlas.width * 4
            band := atlas.pixels[lo * row:][:(hi - lo) * row]
            if render.RENDERER.update_texture(v.msdf_atlas, band, {0, f32(lo), f32(atlas.width), f32(hi - lo)}) {
                v.msdf_atlas_version = atlas.version
            }
        } else {
            v.msdf_atlas_version = atlas.version
        }
    }
    m := _top(v)
    rebuild := !cache.valid || cache.source_version != source_version || cache.color != color ||
    cache.atlas_width != atlas.width || cache.atlas_height != atlas.height
    vertices: []render.Glyph_Vertex
    indices: []u32
    geometry_version := cache.mesh.version
    if rebuild {
        vertices, indices = _msdf_geometry(quads, color, atlas.width, atlas.height)
        cache.source_version = source_version
        cache.color = color
        cache.atlas_width = atlas.width
        cache.atlas_height = atlas.height
        cache.valid = true
        geometry_version += 1
    }
    submit_start := common.profile_begin(.Submit)
    render.RENDERER.draw_msdf_mesh(v.target,&cache.mesh, vertices, indices, geometry_version, m, v.msdf_atlas, atlas.pixel_range, v.scissor)
    common.profile_end(.Submit, submit_start)
}

@(private="file")
_push_clip :: proc(p: Painter, r: common.Rect, mode: ClipMode, radius: common.Radii = 0) {
    v := _vs(p)
    _flush(v)
    m := _top(v)
    rad := common.radii_fit(radius, r.w, r.h)
    // Scissor is axis-aligned only; rotated/skewed transforms fall back to stencil.
    if mode == .Scissor && rad == 0 && m[1, 0] == 0 && m[0, 1] == 0 {
        sr := _xform_rect(v, r)
        if cur, ok := v.scissor.?; ok do sr = _intersect(cur, sr)
        append(&v.clips, Clip_Entry{kind = .Scissor, prev_scissor = v.scissor})
        v.scissor = sr
    } else {
        render.RENDERER.stencil_push_clip()
        scale := _pixel_scale(p)
        hx := 0.5 / scale.x if scale.x > 0 else 0
        hy := 0.5 / scale.y if scale.y > 0 else 0
        verts := [4]render.Vertex{
            {pos = _pt(v, {r.x - hx, r.y - hy})},
            {pos = _pt(v, {r.x + r.w + hx, r.y - hy})},
            {pos = _pt(v, {r.x + r.w + hx, r.y + r.h + hy})},
            {pos = _pt(v, {r.x - hx, r.y + r.h + hy})},
        }
        inverse, _ := common.affine_inverse(m)
        to_local := common.Mat3x3{scale.x, 0, -r.x * scale.x, 0, scale.y, -r.y * scale.y, 0, 0, 1} * inverse
        for &corner in rad do corner *= scale
        append(&v.clip_edges, render.Clip_Edge{to_local, {r.w * scale.x, r.h * scale.y}, rad})
        indices := [6]u32{0, 1, 2, 0, 2, 3}
        submit_start := common.profile_begin(.Submit)
        render.RENDERER.draw(v.target,verts[:], indices[:], render.INVALID_TEXTURE, nil, .Opaque)
        common.profile_end(.Submit, submit_start)
        render.RENDERER.stencil_use_clip()
        _sync_clip_edges(v)
        append(&v.clips, Clip_Entry{kind = .Stencil, prev_scissor = v.scissor})
    }
}

@(private="file")
_pop_clip :: proc(p: Painter) {
    v := _vs(p)
    if len(v.clips) == 0 do return
    _flush(v)
    e := pop(&v.clips)
    switch e.kind {
    case .Scissor: v.scissor = e.prev_scissor
    case .Stencil:
        render.RENDERER.stencil_pop_clip()
        pop(&v.clip_edges)
        _sync_clip_edges(v)
    }
}

@(private="file")
_pixel_scale :: proc(p: Painter) -> [2]f32 {
    m := _top(_vs(p))
    return {
        linalg.length([2]f32{m[0, 0], m[1, 0]}),
        linalg.length([2]f32{m[0, 1], m[1, 1]}),
    }
}

@(private="file")
_push_transform :: proc(p: Painter, t: common.Transform, at: [2]f32) {
    v := _vs(p)
    origin := at + t.origin
    lin := common.transform_linear(t)
    tr := origin + t.translate - lin * origin
    m := common.Mat3x3{
        lin[0, 0], lin[0, 1], tr.x,
        lin[1, 0], lin[1, 1], tr.y,
        0, 0, 1,
    }
    append(&v.transforms, _top(v) * m)
}

@(private="file")
_pop_transform :: proc(p: Painter) {
    v := _vs(p)
    if len(v.transforms) > 1 do pop(&v.transforms)
}

@(private="file")
_flush :: proc(v: ^Vector_State) {
    if len(v.indices) > 0 {
        submit_start := common.profile_begin(.Submit)
        render.RENDERER.draw(v.target,v.verts[:], v.indices[:], v.texture, v.scissor, .Alpha)
        common.profile_end(.Submit, submit_start)
    }
    clear(&v.verts)
    clear(&v.indices)
}

@(private="file")
_set_texture :: proc(v: ^Vector_State, t: render.Texture) {
    if v.texture != t {
        when ODIN_OS == .JS {
            _flush(v)
        } else {
            if v.texture != render.INVALID_TEXTURE do _flush(v)
        }
        v.texture = t
    }
}

@(private="file")
_top :: proc(v: ^Vector_State) -> common.Mat3x3 {
    return v.transforms[len(v.transforms) - 1]
}

@(private="file")
_pt :: proc(v: ^Vector_State, p: [2]f32) -> [2]f32 {
    return swizzle(_top(v) * [3]f32{p.x, p.y, 1}, 0, 1)
}

@(private="file")
_vert :: #force_inline proc(v: ^Vector_State, p: [2]f32, uv: [2]f32, color: common.Color, mode: render.Vertex_Mode = .Solid) {
    append(&v.verts, render.Vertex{pos = _pt(v, p), uv = uv, color = color, mode = mode})
}

@(private="file")
_quad :: proc(v: ^Vector_State, p0, p1, p2, p3: [2]f32, color: common.Color) {
    base := u32(len(v.verts))
    _vert(v, p0, {0, 0}, color)
    _vert(v, p1, {0, 0}, color)
    _vert(v, p2, {0, 0}, color)
    _vert(v, p3, {0, 0}, color)
    append(&v.indices, base, base + 1, base + 2, base, base + 2, base + 3)
}

@(private="file")
_segs :: proc(p: Painter, radius: f32) -> int {
    TOLERANCE :: 0.2
    scale := _pixel_scale(p)
    radius_px := radius * max(scale.x, scale.y)
    if radius_px <= TOLERANCE do return 3
    return clamp(int(math.ceil(math.PI * 0.5 / math.acos(1 - TOLERANCE / radius_px))), 3, 32)
}

@(private="file")
_perimeter :: proc(r: common.Rect, radius: common.Radii, segs: int) -> [][2]f32 {
    pts := make([dynamic][2]f32, 0, (segs + 1) * 4, context.temp_allocator)
    starts := [4]f32{math.PI, math.PI * 1.5, 0, math.PI * 0.5}
    for corner, c in _corners(r) {
        center := corner[0] + corner[1] * radius[c]
        for i in 0 ..= segs {
            ang := starts[c] + (f32(i) / f32(segs)) * math.PI * 0.5
            append(&pts, center + [2]f32{math.cos(ang), math.sin(ang)} * radius[c])
        }
    }
    return pts[:]
}

@(private="file")
_xform_rect :: proc(v: ^Vector_State, r: common.Rect) -> common.Rect {
    p0 := _pt(v, {r.x, r.y})
    p1 := _pt(v, {r.x + r.w, r.y + r.h})
    lo := linalg.min(p0, p1)
    hi := linalg.max(p0, p1)
    return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
}

@(private="file")
_intersect :: proc(a, b: common.Rect) -> common.Rect {
    lo := linalg.max([2]f32{a.x, a.y}, [2]f32{b.x, b.y})
    hi := linalg.min([2]f32{a.x + a.w, a.y + a.h}, [2]f32{b.x + b.w, b.y + b.h})
    size := linalg.max(hi - lo, [2]f32{0, 0})
    return {lo.x, lo.y, size.x, size.y}
}

PAINTER_VECTOR :: Painter_Interface {
    create_state   = _create_state,
    free_state     = _free_state,
    init           = _init,
    shutdown       = _shutdown,
    begin_frame    = _begin_frame,
    end_frame      = _end_frame,
    rect           = _rect,
    border         = _border,
    shadow         = _shadow,
    gradient       = _gradient,
    image          = _image,
    line           = _line,
    triangles      = _triangles,
    mesh_cached    = _mesh_cached,
    glyphs         = _glyphs,
    glyphs_cached  = _glyphs_cached,
    robin_cached   = _robin_cached,
    msdf_cached    = _msdf_cached,
    pixel_scale    = _pixel_scale,
    push_clip      = _push_clip,
    pop_clip       = _pop_clip,
    push_transform = _push_transform,
    pop_transform  = _pop_transform,
    push_layer     = _push_layer,
    pop_layer      = _pop_layer,
}
