package text

import "core:math"
import "core:math/linalg"
import "core:slice"
import "src:core/common"
import "src:core/render"

// Coverage supersampling per axis.
COLOR_RASTER_SS :: 4

Color_Bitmap :: struct {
    pixels: []u8, // RGBA8, straight alpha
    width:  int,
    height: int,
    plane:  [4]f32,        // Bitmap bounds in em units.
    image:  ^render.Image, // texture holder
}

@(private = "file")
_inv_transform :: proc(m: common.Mat3x3) -> (out: common.Mat3x3, ok: bool) {
    if abs(linalg.determinant(m)) < 1e-12 do return {}, false
    return linalg.inverse(m), true
}

@(private = "file")
_apply :: proc(m: common.Mat3x3, p: [2]f32) -> [2]f32 {
    v := m * [3]f32{p.x, p.y, 1}
    return {v.x, v.y}
}

@(private = "file")
_scale_mat :: proc(sx, sy: f32) -> common.Mat3x3 {
    return {sx, 0, 0, 0, sy, 0, 0, 0, 1}
}

@(private = "file")
_extend_t :: proc(t: f32, mode: Gradient_Extend) -> f32 {
    switch mode {
    case .Pad:
        return clamp(t, 0, 1)
    case .Repeat:
        f := t - math.floor(t)
        return f
    case .Reflect:
        f := math.mod(abs(t), 2)
        return 2 - f if f > 1 else f
    }
    return clamp(t, 0, 1)
}

@(private = "file")
_sample_stops :: proc(stops: []Color_Stop, t_in: f32, mode: Gradient_Extend) -> [4]f32 {
    if len(stops) == 0 do return {}
    t := _extend_t(t_in, mode)
    if t <= stops[0].offset {
        c := stops[0].color
        return {f32(c[0]), f32(c[1]), f32(c[2]), f32(c[3])}
    }
    last := stops[len(stops) - 1]
    if t >= last.offset {
        return {f32(last.color[0]), f32(last.color[1]), f32(last.color[2]), f32(last.color[3])}
    }
    for i in 1 ..< len(stops) {
        a, b := stops[i - 1], stops[i]
        if t > b.offset do continue
        span := b.offset - a.offset
        k := f32(0) if span <= 0 else (t - a.offset) / span
        out: [4]f32
        for ch in 0 ..< 4 {
            out[ch] = f32(a.color[ch]) + (f32(b.color[ch]) - f32(a.color[ch])) * k
        }
        return out
    }
    return {}
}

// Gradient parameter at `p`, in the gradient's own (pre-transform) space.
@(private = "file")
_gradient_t :: proc(l: ^Paint_Layer, p: [2]f32) -> (f32, bool) {
    switch l.kind {
    case .Linear:
        d := l.p1 - l.p0
        den := d.x * d.x + d.y * d.y
        if den <= 0 do return 0, false
        v := p - l.p0
        return (v.x * d.x + v.y * d.y) / den, true

    case .Radial:
        // Solve |p - c(s)| = r(s) for the largest s.
        cd := l.p1 - l.p0
        dr := l.r1 - l.r0
        pd := p - l.p0
        a := cd.x * cd.x + cd.y * cd.y - dr * dr
        b := pd.x * cd.x + pd.y * cd.y + l.r0 * dr
        c := pd.x * pd.x + pd.y * pd.y - l.r0 * l.r0
        if abs(a) < 1e-6 {
            // Concentric or degenerate: reduces to a linear equation in s.
            if abs(b) < 1e-12 do return 0, false
            s := c / (2 * b)
            if l.r0 + s * dr < 0 do return 0, false
            return s, true
        }
        disc := b * b - a * c
        if disc < 0 do return 0, false
        sq := math.sqrt(disc)
        s0 := (b + sq) / a
        s1 := (b - sq) / a
        if l.r0 + s0 * dr >= 0 do return s0, true
        if l.r0 + s1 * dr >= 0 do return s1, true
        return 0, false

    case .Solid:
        return 0, true
    }
    return 0, false
}

@(private = "file")
_Crossing :: struct {
    x:   f32,
    dir: i32,
}

@(private = "file")
_Cover :: struct {
    // Accumulated per-subsample winding for one glyph shape.
    winding: []i32,
    width:   int,
    height:  int,
}

// Scanline-fill flattened contours with nonzero winding.
@(private = "file")
_accumulate :: proc(cov: ^_Cover, pts: [][2]f32, contours: []u32, to_px: common.Mat3x3) {
    edges := make([dynamic][4]f32, 0, len(pts), context.temp_allocator)
    start := u32(0)
    for end in contours {
        seg := pts[int(start) * 3:int(end) * 3]
        for i := 0; i < len(seg); i += 3 {
            p0 := _apply(to_px, seg[i])
            p1 := _apply(to_px, seg[i + 1])
            p2 := _apply(to_px, seg[i + 2])
            // Flatten the quadratic.
            d := p0 - 2 * p1 + p2
            dev := math.sqrt(d.x * d.x + d.y * d.y)
            n := clamp(int(math.ceil(math.sqrt(dev * 2))), 1, 32)
            prev := p0
            for k in 1 ..= n {
                t := f32(k) / f32(n)
                u := 1 - t
                q := u * u * p0 + 2 * u * t * p1 + t * t * p2
                append(&edges, [4]f32{prev.x, prev.y, q.x, q.y})
                prev = q
            }
        }
        start = end
    }
    if len(edges) == 0 do return

    xs := make([dynamic]_Crossing, 0, 32, context.temp_allocator)
    for y in 0 ..< cov.height {
        sy := f32(y) + 0.5
        clear(&xs)
        for e in edges {
            y0, y1 := e[1], e[3]
            if y0 == y1 {
                continue
            }
            dir: i32 = 1
            a, b := e[0], e[2]
            if y0 > y1 {
                y0, y1 = y1, y0
                a, b = b, a
                dir = -1
            }
            if sy < y0 || sy >= y1 {
                continue
            }
            x := a + (b - a) * (sy - y0) / (y1 - y0)
            append(&xs, _Crossing{x, dir})
        }
        if len(xs) == 0 do continue
        slice.sort_by(xs[:], proc(p, q: _Crossing) -> bool {return p.x < q.x})

        wind: i32 = 0
        row := y * cov.width
        for i in 0 ..< len(xs) - 1 {
            wind += xs[i].dir
            if wind == 0 do continue
            x0 := int(math.ceil(xs[i].x - 0.5))
            x1 := int(math.ceil(xs[i + 1].x - 0.5))
            x0 = max(x0, 0)
            x1 = min(x1, cov.width)
            for x in x0 ..< x1 {
                cov.winding[row + x] = 1
            }
        }
    }
}

@(private = "file")
_Bitmap_Key :: struct {
    face: ^Face,
    gid:  u32,
    // Quantized size prevents per-frame cache.
    size: u16,
}

@(private = "file")
_bitmaps: map[_Bitmap_Key]Color_Bitmap

COLOR_BITMAP_MAX_PX :: 160

// Returns a cache-owned bitmap.
color_bitmap_cached :: proc(f: ^Face, gid: u32, px_per_em: f32) -> (Color_Bitmap, bool) {
    if f == nil || px_per_em <= 0 do return {}, false
    // Cap raster size and scale larger glyphs.
    size := min(px_per_em, COLOR_BITMAP_MAX_PX)
    key := _Bitmap_Key{f, gid, u16(math.ceil(size))}
    if bm, ok := _bitmaps[key]; ok do return bm, bm.pixels != nil

    bm, ok := color_bitmap(f, gid, f32(key.size))
    if !ok {
        // Cache misses to avoid repeated paint-graph walks.
        _bitmaps[key] = Color_Bitmap{}
        return {}, false
    }
    img := new(render.Image)
    img^ = render.Image {
        data   = bm.pixels,
        w      = u32(bm.width),
        h      = u32(bm.height),
        format = .RGBA8,
    }
    bm.image = img
    _bitmaps[key] = bm
    return bm, true
}

@(private = "package")
_color_bitmaps_destroy :: proc(f: ^Face) {
    for key, bm in _bitmaps {
        if key.face != f do continue
        if bm.image != nil {
            render.RENDERER.unload_image(bm.image)
            free(bm.image)
        }
        delete(bm.pixels)
        delete_key(&_bitmaps, key)
    }
}

// Rasterizes a COLR v1 glyph to premultiplied RGBA.
color_bitmap :: proc(
    f: ^Face,
    gid: u32,
    px_per_em: f32,
    fg: [4]u8 = {0, 0, 0, 255},
    allocator := context.allocator,
) -> (
    Color_Bitmap,
    bool,
) {
    layers := paint_layers(f, gid, fg)
    if len(layers) == 0 do return {}, false

    // Convert the font-unit shape transform to em.
    to_em := _scale_mat(f.inv_upem, f.inv_upem)
    to_units := _scale_mat(f.upem, f.upem)
    shape_em := make([]common.Mat3x3, len(layers), context.temp_allocator)
    for &l, i in layers {
        shape_em[i] = to_em * l.shape * to_units
    }

    mn := [2]f32{math.F32_MAX, math.F32_MAX}
    mx := [2]f32{-math.F32_MAX, -math.F32_MAX}
    for &l, i in layers {
        g := glyph(f, l.gid, 0)
        if g.curve_count == 0 do continue
        corners := [4][2]f32 {
            {g.min.x, g.min.y},
            {g.max.x, g.min.y},
            {g.max.x, g.max.y},
            {g.min.x, g.max.y},
        }
        for cpt in corners {
            p := _apply(shape_em[i], cpt)
            mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
            mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
        }
    }
    if mn.x > mx.x || mn.y > mx.y do return {}, false

    PAD :: 1
    w := int(math.ceil((mx.x - mn.x) * px_per_em)) + 2 * PAD
    h := int(math.ceil((mx.y - mn.y) * px_per_em)) + 2 * PAD
    if w <= 0 || h <= 0 || w > 4096 || h > 4096 do return {}, false

    ss := COLOR_RASTER_SS
    cw, ch := w * ss, h * ss
    cov := _Cover {
        winding = make([]i32, cw * ch, context.temp_allocator),
        width   = cw,
        height  = ch,
    }
    accum := make([][4]f32, w * h, context.temp_allocator)

    curves, _ := curve_data()
    // subsample px, with y flipped.
    to_px := common.Mat3x3 {
        f32(ss) * px_per_em, 0, f32(PAD * ss) - mn.x * px_per_em * f32(ss),
        0, -f32(ss) * px_per_em, f32(PAD * ss) + mx.y * px_per_em * f32(ss),
        0, 0, 1,
    }
    px_to_em, px_ok := _inv_transform(to_px)
    if !px_ok do return {}, false

    for &l, li in layers {
        g := glyph(f, l.gid, 0)
        if g.curve_count == 0 do continue
        slice.zero(cov.winding)

        shape_to_px := to_px * shape_em[li]
        pts := curves[int(g.curve_base) * 3:][:int(g.curve_count) * 3]
        _accumulate(&cov, pts, glyph_contours(g), shape_to_px)

        // Map pixels back into the gradient's font-unit space.
        shape_px_to_em, shape_ok := _inv_transform(shape_to_px)
        if !shape_ok do continue
        inv_paint, inv_ok := _inv_transform(l.transform)
        if !inv_ok && l.kind != .Solid do continue
        inv_px := inv_paint * to_units * shape_px_to_em

        for y in 0 ..< h {
            for x in 0 ..< w {
                hits := 0
                sum := [4]f32{}
                for sy in 0 ..< ss {
                    row := (y * ss + sy) * cw + x * ss
                    for sx in 0 ..< ss {
                        if cov.winding[row + sx] == 0 do continue
                        hits += 1
                        if l.kind == .Solid {
                            c := l.color
                            sum += {f32(c[0]), f32(c[1]), f32(c[2]), f32(c[3])}
                            continue
                        }
                        // Back to gradient space to evaluate the ramp.
                        gp := _apply(inv_px, {f32(x * ss + sx) + 0.5, f32(y * ss + sy) + 0.5})
                        t, ok := _gradient_t(&l, gp)
                        if !ok do continue
                        sum += _sample_stops(l.stops, t, l.extend)
                    }
                }
                if hits == 0 do continue
                total := f32(ss * ss)
                src := sum / f32(hits)
                a := src[3] / 255 * (f32(hits) / total)
                if a <= 0 do continue
                dst := &accum[y * w + x]
                // Premultiplied source-over.
                for ch2 in 0 ..< 3 {
                    dst[ch2] = src[ch2] * a + dst[ch2] * (1 - a)
                }
                dst[3] = a * 255 + dst[3] * (1 - a)
            }
        }
    }

    out := make([]u8, w * h * 4, allocator)
    for i in 0 ..< w * h {
        p := accum[i]
        alpha := clamp(p[3], 0, 255)
        // The renderer expects straight (non-premultiplied) RGBA.
        inv := f32(0) if alpha <= 0 else 255 / alpha
        out[i * 4 + 0] = u8(clamp(p[0] * inv, 0, 255))
        out[i * 4 + 1] = u8(clamp(p[1] * inv, 0, 255))
        out[i * 4 + 2] = u8(clamp(p[2] * inv, 0, 255))
        out[i * 4 + 3] = u8(alpha)
    }

    pad_em := f32(PAD) / px_per_em
    return Color_Bitmap {
        pixels = out,
        width  = w,
        height = h,
        plane  = {mn.x - pad_em, mn.y - pad_em, mx.x + pad_em, mx.y + pad_em},
    }, true
}
