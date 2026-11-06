package painter

import "src:core/render"
import "base:runtime"
import "core:math"
import "src:core/common"
import "src:core/redraw"

CONFIG_PAINTER_NAME :: #config(banana_PAINTER, "")

// "vector" tessellates on the CPU and draws through render.
DEFAULT_PAINTER_NAME :: "vector"
AVAILABLE_PAINTERS   :: "vector, nil"

when CONFIG_PAINTER_NAME == "" {
    PAINTER_NAME :: DEFAULT_PAINTER_NAME
} else {
    PAINTER_NAME :: CONFIG_PAINTER_NAME
}

when PAINTER_NAME == "vector" {
    PAINTER :: PAINTER_VECTOR
} else when PAINTER_NAME == "nil" {
    PAINTER :: PAINTER_NIL
} else {
    #panic("'" + PAINTER_NAME + "' is not a valid banana_PAINTER. Available: " + AVAILABLE_PAINTERS)
}

@(private="file", thread_local)
_active: Painter

init :: proc(p: Painter, allocator: runtime.Allocator) {
    PAINTER.init(p, allocator)
}

create_state :: proc(allocator: runtime.Allocator) -> rawptr {
    return PAINTER.create_state(allocator)
}

free_state :: proc(state: rawptr, allocator: runtime.Allocator) {
    PAINTER.free_state(state, allocator)
}

shutdown :: proc(p: Painter) {
    PAINTER.shutdown(p)
}

begin_frame :: proc(p: Painter, color: common.Color) {
    redraw.begin_paint()
    redraw.hash(color)
    PAINTER.begin_frame(p, color)
}

end_frame :: proc(p: Painter) {
    PAINTER.end_frame(p)
    redraw.end_paint()
}

rect :: proc(p: Painter, r: common.Rect, color: common.Color, radius: common.Radii = 0) {
    redraw.hash(r); redraw.hash(color); redraw.hash(radius)
    PAINTER.rect(p, r, color, radius)
}

border :: proc(p: Painter, r: common.Rect, color: common.Color, width: f32, radius: common.Radii = 0) {
    redraw.hash(r); redraw.hash(color); redraw.hash(width); redraw.hash(radius)
    PAINTER.border(p, r, color, width, radius)
}

// `colors` and `widths` are top, right, bottom, left.
border_sides :: proc(p: Painter, r: common.Rect, colors: [4]common.Color, widths: [4]f32, radius: common.Radii = 0) {
    if widths == 0 do return
    redraw.hash(r); redraw.hash(colors); redraw.hash(widths); redraw.hash(radius)
    uniform := true
    for i in 1 ..< 4 do uniform = uniform && widths[i] == widths[0] && colors[i] == colors[0]
    if uniform {
        PAINTER.border(p, r, colors[0], widths[0], radius)
        return
    }

    w := widths
    if across := w[1] + w[3]; across > r.w do w[1], w[3] = w[1] * r.w / across, w[3] * r.w / across
    if down := w[0] + w[2]; down > r.h do w[0], w[2] = w[0] * r.h / down, w[2] * r.h / down
    rad := common.radii_fit(radius, r.w, r.h)
    scale := PAINTER.pixel_scale(p)
    segs := clamp(int(math.ceil(math.sqrt(common.radii_max(rad) * max(scale.x, scale.y)))) * 2, 2, 32)

    ring :: proc(pts: ^[dynamic][2]f32, r: common.Rect, rad: common.Radii, segs: int) {
        corners := [4][2][2]f32{
            {{r.x, r.y}, {1, 1}}, {{r.x + r.w, r.y}, {-1, 1}},
            {{r.x + r.w, r.y + r.h}, {-1, -1}}, {{r.x, r.y + r.h}, {1, -1}},
        }
        starts := [4]f32{math.PI, math.PI * 1.5, 0, math.PI * 0.5}
        for corner, c in corners {
            center := corner[0] + corner[1] * rad[c]
            for i in 0 ..= segs {
                angle := starts[c] + f32(i) / f32(segs) * math.PI * 0.5
                append(pts, center + [2]f32{math.cos(angle), math.sin(angle)} * rad[c])
            }
        }
    }
    per := segs + 1
    count := per * 4
    pts := make([dynamic][2]f32, 0, count * 2, context.temp_allocator)
    ring(&pts, r, rad, segs)
    ring(&pts, {r.x + w[3], r.y + w[0], r.w - w[1] - w[3], r.h - w[0] - w[2]}, common.radii_inset_sides(rad, w), segs)

    indices: [4][dynamic]u32
    for &list in indices do list = make([dynamic]u32, context.temp_allocator)
    for k in 0 ..< count {
        corner, step := k / per, k % per
        // A corner's arc is split between the side it leaves and the side it enters.
        side := corner if step == segs || 2 * step + 1 > segs else (corner + 3) % 4
        a, b := u32(k), u32((k + 1) % count)
        append(&indices[side], a, b, b + u32(count), a, b + u32(count), a + u32(count))
    }
    for list, side in indices {
        if w[side] > 0 && colors[side].a > 0 do PAINTER.triangles(p, pts[:], list[:], colors[side])
    }
}

image :: proc(p: Painter, image: ^render.Image, dst: common.Rect, tint := common.COLOR_WHITE) {
    redraw.hash(image); redraw.hash(dst); redraw.hash(tint)
    PAINTER.image(p, image, dst, tint)
}

line :: proc(p: Painter, a, b: [2]f32, color: common.Color, width: f32) {
    redraw.hash(a); redraw.hash(b); redraw.hash(color); redraw.hash(width)
    PAINTER.line(p, a, b, color, width)
}

triangles :: proc(p: Painter, points: [][2]f32, indices: []u32, color: common.Color) {
    redraw.hash_slice(points); redraw.hash_slice(indices); redraw.hash(color)
    PAINTER.triangles(p, points, indices, color)
}

// A cached mesh is named by its cache and version: its vertices are only read when that pair changes.
mesh_cached :: proc(p: Painter, cache: ^Mesh_Cache, source_version: u64, vertices: []render.Vertex, indices: []u32) {
    redraw.hash(cache); redraw.hash(source_version)
    PAINTER.mesh_cached(p, cache, source_version, vertices, indices)
}

glyphs :: proc(p: Painter, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    redraw.hash_slice(quads); redraw.hash(color)
    PAINTER.glyphs(p, curves, version, quads, color)
}

glyphs_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, curves: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    redraw.hash(source_version); redraw.hash_slice(quads); redraw.hash(color)
    PAINTER.glyphs_cached(p, cache, source_version, curves, version, quads, color)
}

robin_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, data: [][2]f32, version: u64, quads: []Glyph_Quad, color: common.Color) {
    redraw.hash(source_version); redraw.hash_slice(quads); redraw.hash(color)
    PAINTER.robin_cached(p, cache, source_version, data, version, quads, color)
}

msdf_cached :: proc(p: Painter, cache: ^Glyph_Cache, source_version: u64, atlas: MSDF_Atlas, quads: []MSDF_Quad, color: common.Color) {
    redraw.hash(source_version); _hash_msdf(quads); redraw.hash(color)
    PAINTER.msdf_cached(p, cache, source_version, atlas, quads, color)
}

pixel_scale :: proc(p: Painter) -> [2]f32 {
    return PAINTER.pixel_scale(p)
}

// Shadows go under a box, the gradient over its background color, the outline on top.
decoration_under :: proc(p: Painter, r: common.Rect, radius: common.Radii, d: common.EffectFilterDecoration) {
    #reverse for s in d.shadows do shadow(p, r, radius, s, d.alpha)
}

decoration_fill :: proc(p: Painter, r: common.Rect, radius: common.Radii, d: common.EffectFilterDecoration) {
    if len(d.gradient.stops) > 0 do gradient(p, r, radius, d.gradient, d.alpha)
}

decoration_over :: proc(p: Painter, r: common.Rect, radius: common.Radii, d: common.EffectFilterDecoration) {
    if d.outline_width <= 0 || d.outline_color.a == 0 do return
    grow := d.outline_offset + d.outline_width
    outer := common.Rect{r.x - grow, r.y - grow, r.w + 2 * grow, r.h + 2 * grow}
    corners := common.radii_grow(common.radii_fit(radius, r.w, r.h), grow)
    border(p, outer, d.outline_color, d.outline_width, corners)
}

shadow :: proc(p: Painter, r: common.Rect, radius: common.Radii, s: common.EffectShadow, alpha: f32 = 1) {
    redraw.hash(r); redraw.hash(radius); _hash_shadow(s); redraw.hash(alpha)
    PAINTER.shadow(p, r, radius, s, alpha)
}

gradient :: proc(p: Painter, r: common.Rect, radius: common.Radii, g: common.Gradient, alpha: f32 = 1) {
    redraw.hash(r); redraw.hash(radius); _hash_gradient(g); redraw.hash(alpha)
    PAINTER.gradient(p, r, radius, g, alpha)
}

push_layer :: proc(p: Painter, bounds: common.Rect, f: common.EffectFilter) {
    redraw.hash(bounds); _hash_filter(f)
    PAINTER.push_layer(p, bounds, f)
}

pop_layer :: proc(p: Painter) {
    redraw.hash(u8(1))
    PAINTER.pop_layer(p)
}

push_clip :: proc(p: Painter, r: common.Rect, mode: ClipMode, radius: common.Radii = 0) {
    redraw.hash(r); redraw.hash(u8(mode)); redraw.hash(radius)
    PAINTER.push_clip(p, r, mode, radius)
}

pop_clip :: proc(p: Painter) {
    redraw.hash(u8(2))
    PAINTER.pop_clip(p)
}

push_transform :: proc(p: Painter, t: common.Transform, at: [2]f32) {
    _hash_transform(t); redraw.hash(at)
    PAINTER.push_transform(p, t, at)
}

pop_transform :: proc(p: Painter) {
    redraw.hash(u8(3))
    PAINTER.pop_transform(p)
}

set_active :: proc(p: Painter) -> (prev: Painter) {
    prev = _active
    _active = p
    return prev
}

get :: proc(loc := #caller_location) -> Painter {
    assert(_active.state != nil, "painter.get() called outside a draw pass", loc)
    return _active
}
