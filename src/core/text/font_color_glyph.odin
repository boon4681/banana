package text

import "base:runtime"
import "core:c"
import "core:math"
import "src:core/common"
import HB "src:harfbuzz"

COLR :: HB.Tag(0x434F4C52) // 'COLR'
CPAL :: HB.Tag(0x4350414C) // 'CPAL'

// One flat-filled layer of a COLR glyph, painted back to front.
Color_Layer :: struct {
    gid:   u32,
    color: [4]u8,
}

// Palette index 0xFFFF uses the text color.
COLOR_LAYER_FOREGROUND :: 0xFFFF

@(private = "file")
_Color_Table :: struct {
    // Parsed once on first use.
    loaded:    bool,
    base:      []u8, // COLR base glyph records, 6 bytes each
    layers:    []u8, // COLR layer records, 4 bytes each
    palette:   [][4]u8,
    colr_blob: HB.Blob,
    cpal_blob: HB.Blob,

    // offsets resolve against the full COLR table.
    colr:       []u8,
    base_list:  int, // offset of BaseGlyphList, 0 when absent
    layer_list: int, // offset of LayerList
}

@(private = "file")
_color_tables: map[^Face]_Color_Table

@(private = "file")
_u16be :: proc(b: []u8, off: int) -> u16 {
    if off + 2 > len(b) do return 0
    return u16(b[off]) << 8 | u16(b[off + 1])
}

@(private = "file")
_u32be :: proc(b: []u8, off: int) -> u32 {
    if off + 4 > len(b) do return 0
    return u32(b[off]) << 24 | u32(b[off + 1]) << 16 | u32(b[off + 2]) << 8 | u32(b[off + 3])
}

@(private = "file")
_color_table :: proc(f: ^Face) -> ^_Color_Table {
    // Instances share parent tables.
    key := f.instance_of if f.instance_of != nil else f
    if t, ok := &_color_tables[key]; ok do return t

    _color_tables[key] = _Color_Table{loaded = true}
    t := &_color_tables[key]

    colr := HB.face_reference_table(key.hb_face, COLR)
    cpal := HB.face_reference_table(key.hb_face, CPAL)
    n_colr, n_cpal: c.uint
    colr_ptr := HB.blob_get_data(colr, &n_colr)
    cpal_ptr := HB.blob_get_data(cpal, &n_cpal)
    if colr_ptr == nil || cpal_ptr == nil || n_colr < 14 || n_cpal < 12 {
        HB.blob_destroy(colr)
        HB.blob_destroy(cpal)
        return t
    }
    c_data := colr_ptr[:n_colr]
    p_data := cpal_ptr[:n_cpal]

    // V1 reuses the v0 header.
    num_base := int(_u16be(c_data, 2))
    base_off := int(_u32be(c_data, 4))
    layer_off := int(_u32be(c_data, 8))
    num_layers := int(_u16be(c_data, 12))
    if base_off + num_base * 6 > len(c_data) || layer_off + num_layers * 4 > len(c_data) {
        HB.blob_destroy(colr)
        HB.blob_destroy(cpal)
        return t
    }

    num_entries := int(_u16be(p_data, 2))
    colors_off := int(_u32be(p_data, 8))
    if num_entries <= 0 || colors_off + num_entries * 4 > len(p_data) {
        HB.blob_destroy(colr)
        HB.blob_destroy(cpal)
        return t
    }

    palette := make([][4]u8, num_entries)
    for i in 0 ..< num_entries {
        o := colors_off + i * 4
        // CPAL stores BGRA.
        palette[i] = {p_data[o + 2], p_data[o + 1], p_data[o], p_data[o + 3]}
    }

    t.base = c_data[base_off:][:num_base * 6]
    t.layers = c_data[layer_off:][:num_layers * 4]
    t.palette = palette
    t.colr_blob = colr
    t.cpal_blob = cpal
    t.colr = c_data

    version := _u16be(c_data, 0)
    if version >= 1 && len(c_data) >= 34 {
        base_list := int(_u32be(c_data, 14))
        layer_list := int(_u32be(c_data, 18))
        if base_list > 0 && base_list + 4 <= len(c_data) {
            t.base_list = base_list
            t.layer_list = layer_list
        }
    }
    return t
}

has_color_glyphs :: proc(f: ^Face) -> bool {
    if f == nil do return false
    return len(_color_table(f).base) > 0
}

// Returns temp-allocated layers back to front.
color_layers :: proc(f: ^Face, gid: u32, allocator := context.temp_allocator) -> []Color_Layer {
    if f == nil do return nil
    t := _color_table(f)
    if len(t.base) == 0 do return nil

    // baseGlyphRecords are sorted by glyph id.
    lo, hi := 0, len(t.base) / 6
    rec := -1
    for lo < hi {
        mid := (lo + hi) / 2
        g := u32(_u16be(t.base, mid * 6))
        switch {
        case g < gid:
            lo = mid + 1
        case g > gid:
            hi = mid
        case:
            rec = mid
            lo = hi
        }
    }
    if rec < 0 do return nil

    first := int(_u16be(t.base, rec * 6 + 2))
    count := int(_u16be(t.base, rec * 6 + 4))
    if count <= 0 || (first + count) * 4 > len(t.layers) do return nil

    out := make([]Color_Layer, count, allocator)
    for i in 0 ..< count {
        o := (first + i) * 4
        idx := int(_u16be(t.layers, o + 2))
        color := [4]u8{0, 0, 0, 255}
        if idx != COLOR_LAYER_FOREGROUND && idx < len(t.palette) {
            color = t.palette[idx]
        }
        out[i] = Color_Layer{gid = u32(_u16be(t.layers, o)), color = color}
    }
    return out
}

Gradient_Kind :: enum {
    Solid,
    Linear,
    Radial,
}

Gradient_Extend :: enum u8 {
    Pad     = 0,
    Repeat  = 1,
    Reflect = 2,
}

Color_Stop :: struct {
    offset: f32,
    color:  [4]u8,
}

// COLR v1 layer with separate outline and paint transforms.
Paint_Layer :: struct {
    gid:       u32,
    shape:     common.Mat3x3, // outline placement, font units
    transform: common.Mat3x3, // gradient placement, font units
    kind:      Gradient_Kind,
    color:     [4]u8,  // Solid only
    p0, p1:    [2]f32, // Linear: start/end. Radial: circle centres.
    r0, r1:    f32,    // Radial only
    extend:    Gradient_Extend,
    stops:     []Color_Stop,
}

// COLR states affines as (xx, yx, xy, yy, dx, dy) in column-major pairs.
@(private = "file")
_affine :: proc(xx, yx, xy, yy, dx, dy: f32) -> common.Mat3x3 {
    return {xx, xy, dx, yx, yy, dy, 0, 0, 1}
}

@(private = "file")
_u24be :: proc(b: []u8, off: int) -> int {
    if off + 3 > len(b) do return 0
    return int(b[off]) << 16 | int(b[off + 1]) << 8 | int(b[off + 2])
}

@(private = "file")
_f2dot14 :: proc(b: []u8, off: int) -> f32 {
    return f32(i16(_u16be(b, off))) / 16384.0
}

@(private = "file")
_fixed :: proc(b: []u8, off: int) -> f32 {
    return f32(i32(_u32be(b, off))) / 65536.0
}

@(private = "file")
_i16 :: proc(b: []u8, off: int) -> f32 {
    return f32(i16(_u16be(b, off)))
}

@(private = "file")
_palette_color :: proc(t: ^_Color_Table, index: u16, alpha: f32, fg: [4]u8) -> [4]u8 {
    c := fg
    if index != COLOR_LAYER_FOREGROUND {
        if int(index) >= len(t.palette) do return {0, 0, 0, 0}
        c = t.palette[index]
    }
    c[3] = u8(clamp(f32(c[3]) * alpha, 0, 255))
    return c
}

@(private = "file")
_read_color_line :: proc(
    t:         ^_Color_Table,
    off:       int,
    fg:        [4]u8,
    allocator: runtime.Allocator,
) -> (
    stops: []Color_Stop,
    extend: Gradient_Extend,
) {
    b := t.colr
    if off + 3 > len(b) do return nil, .Pad
    extend = Gradient_Extend(b[off])
    if extend > .Reflect do extend = .Pad
    n := int(_u16be(b, off + 1))
    if n == 0 || off + 3 + n * 6 > len(b) do return nil, extend

    out := make([]Color_Stop, n, allocator)
    for i in 0 ..< n {
        o := off + 3 + i * 6
        out[i] = Color_Stop {
            offset = _f2dot14(b, o),
            color  = _palette_color(t, _u16be(b, o + 2), _f2dot14(b, o + 4), fg),
        }
    }
    return out, extend
}

@(private = "file")
_Paint_Ctx :: struct {
    t:         ^_Color_Table,
    fg:        [4]u8,
    out:       ^[dynamic]Paint_Layer,
    allocator: runtime.Allocator,
    budget:    int,
}

// Flattens the paint graph into back-to-front layers.
@(private = "file")
_walk_paint :: proc(
    ctx:         ^_Paint_Ctx,
    off:         int,
    xform:       common.Mat3x3,
    shape:       u32,
    shape_xform: common.Mat3x3,
    depth:       int,
) -> bool {
    if depth > 16 || ctx.budget <= 0 do return false
    ctx.budget -= 1
    b := ctx.t.colr
    if off < 0 || off >= len(b) do return false

    format := b[off]
    switch format {
    case 1: // PaintColrLayers
        count := int(b[off + 1])
        first := int(_u32be(b, off + 2))
        ll := ctx.t.layer_list
        if ll <= 0 || ll + 4 > len(b) do return false
        total := int(_u32be(b, ll))
        for i in 0 ..< count {
            idx := first + i
            if idx >= total do break
            po := int(_u32be(b, ll + 4 + idx * 4))
            if !_walk_paint(ctx, ll + po, xform, shape, shape_xform, depth + 1) do return false
        }
        return true

    case 2, 3: // PaintSolid, PaintVarSolid
        if shape == 0 do return true
        append(ctx.out, Paint_Layer {
            gid       = shape,
            shape     = shape_xform,
            transform = xform,
            kind      = .Solid,
            color     = _palette_color(ctx.t, _u16be(b, off + 1), _f2dot14(b, off + 3), ctx.fg),
        })
        return true

    case 4, 5: // PaintLinearGradient, PaintVarLinearGradient
        if shape == 0 do return true
        stops, extend := _read_color_line(ctx.t, off + _u24be(b, off + 1), ctx.fg, ctx.allocator)
        if len(stops) == 0 do return true
        // Project p1 to reduce the rotated gradient to two points.
        p0 := [2]f32{_i16(b, off + 4), _i16(b, off + 6)}
        p1 := [2]f32{_i16(b, off + 8), _i16(b, off + 10)}
        p2 := [2]f32{_i16(b, off + 12), _i16(b, off + 14)}
        d1 := p1 - p0
        d2 := p2 - p0
        den := d2.x * d2.x + d2.y * d2.y
        if den > 0 {
            k := (d1.x * d2.x + d1.y * d2.y) / den
            p1 = p0 + d1 - d2 * k
        }
        append(ctx.out, Paint_Layer {
            gid       = shape,
            shape     = shape_xform,
            transform = xform,
            kind      = .Linear,
            p0        = p0,
            p1        = p1,
            extend    = extend,
            stops     = stops,
        })
        return true

    case 6, 7: // PaintRadialGradient, PaintVarRadialGradient
        if shape == 0 do return true
        stops, extend := _read_color_line(ctx.t, off + _u24be(b, off + 1), ctx.fg, ctx.allocator)
        if len(stops) == 0 do return true
        append(ctx.out, Paint_Layer {
            gid       = shape,
            shape     = shape_xform,
            transform = xform,
            kind      = .Radial,
            p0        = {_i16(b, off + 4), _i16(b, off + 6)},
            r0        = f32(_u16be(b, off + 8)),
            p1        = {_i16(b, off + 10), _i16(b, off + 12)},
            r1        = f32(_u16be(b, off + 14)),
            extend    = extend,
            stops     = stops,
        })
        return true

    case 10: // PaintGlyph
        // This transform places the outline; descendants affect paint.
        return _walk_paint(ctx, off + _u24be(b, off + 1), common.Mat3X3_IDENTITY, u32(_u16be(b, off + 4)), xform, depth + 1)

    case 11: // PaintColrGlyph
        gid := u32(_u16be(b, off + 1))
        rec := _v1_record(ctx.t, gid)
        if rec < 0 do return true
        return _walk_paint(ctx, rec, xform, shape, shape_xform, depth + 1)

    case 12, 13: // PaintTransform, PaintVarTransform
        to := off + _u24be(b, off + 4)
        if to + 24 > len(b) do return false
        m := _affine(
            _fixed(b, to),
            _fixed(b, to + 4),
            _fixed(b, to + 8),
            _fixed(b, to + 12),
            _fixed(b, to + 16),
            _fixed(b, to + 20),
        )
        return _walk_paint(ctx, off + _u24be(b, off + 1), xform * m, shape, shape_xform, depth + 1)

    case 14, 15: // PaintTranslate, PaintVarTranslate
        m := _affine(1, 0, 0, 1, _i16(b, off + 4), _i16(b, off + 6))
        return _walk_paint(ctx, off + _u24be(b, off + 1), xform * m, shape, shape_xform, depth + 1)

    case 16 ..= 23: // Paint(Var)Scale variants
        sx, sy: f32 = 1, 1
        cx, cy: f32 = 0, 0
        switch format {
        case 16, 17:
            sx, sy = _f2dot14(b, off + 4), _f2dot14(b, off + 6)
        case 18, 19:
            sx, sy = _f2dot14(b, off + 4), _f2dot14(b, off + 6)
            cx, cy = _i16(b, off + 8), _i16(b, off + 10)
        case 20, 21:
            sx = _f2dot14(b, off + 4)
            sy = sx
        case 22, 23:
            sx = _f2dot14(b, off + 4)
            sy = sx
            cx, cy = _i16(b, off + 6), _i16(b, off + 8)
        }
        m := _affine(1, 0, 0, 1, cx, cy) * _affine(sx, 0, 0, sy, 0, 0) * _affine(1, 0, 0, 1, -cx, -cy)
        return _walk_paint(ctx, off + _u24be(b, off + 1), xform * m, shape, shape_xform, depth + 1)

    case 24 ..= 27: // Paint(Var)Rotate variants
        angle := _f2dot14(b, off + 4) * math.PI
        cx, cy: f32 = 0, 0
        if format == 26 || format == 27 {
            cx, cy = _i16(b, off + 6), _i16(b, off + 8)
        }
        s, c := math.sin(angle), math.cos(angle)
        m := _affine(1, 0, 0, 1, cx, cy) * _affine(c, s, -s, c, 0, 0) * _affine(1, 0, 0, 1, -cx, -cy)
        return _walk_paint(ctx, off + _u24be(b, off + 1), xform * m, shape, shape_xform, depth + 1)

    case 28 ..= 31: // Paint(Var)Skew variants
        ax := _f2dot14(b, off + 4) * math.PI
        ay := _f2dot14(b, off + 6) * math.PI
        cx, cy: f32 = 0, 0
        if format == 30 || format == 31 {
            cx, cy = _i16(b, off + 8), _i16(b, off + 10)
        }
        m := _affine(1, 0, 0, 1, cx, cy) *
            _affine(1, math.tan(ay), math.tan(ax), 1, 0, 0) *
            _affine(1, 0, 0, 1, -cx, -cy)
        return _walk_paint(ctx, off + _u24be(b, off + 1), xform * m, shape, shape_xform, depth + 1)
    }

    // Unsupported paints fall back to v0 layers.
    return false
}

// Offset of `gid`'s root paint within the COLR table, or -1.
@(private = "file")
_v1_record :: proc(t: ^_Color_Table, gid: u32) -> int {
    if t.base_list <= 0 do return -1
    b := t.colr
    bl := t.base_list
    if bl + 4 > len(b) do return -1
    n := int(_u32be(b, bl))
    if bl + 4 + n * 6 > len(b) do return -1

    lo, hi := 0, n
    for lo < hi {
        mid := (lo + hi) / 2
        g := u32(_u16be(b, bl + 4 + mid * 6))
        switch {
        case g < gid:
            lo = mid + 1
        case g > gid:
            hi = mid
        case:
            return bl + int(_u32be(b, bl + 4 + mid * 6 + 2))
        }
    }
    return -1
}

// Returns flattened v1 layers or nil to request the v0 fallback.
paint_layers :: proc(
    f:   ^Face,
    gid: u32,
    fg:  [4]u8 = {0, 0, 0, 255},
    allocator := context.temp_allocator,
) -> []Paint_Layer {
    if f == nil do return nil
    t := _color_table(f)
    if t.base_list <= 0 do return nil
    rec := _v1_record(t, gid)
    if rec < 0 do return nil

    out := make([dynamic]Paint_Layer, 0, 32, allocator)
    ctx := _Paint_Ctx {
        t         = t,
        fg        = fg,
        out       = &out,
        allocator = allocator,
        budget    = 4096,
    }
    if !_walk_paint(&ctx, rec, common.Mat3X3_IDENTITY, 0, common.Mat3X3_IDENTITY, 0) do return nil
    return out[:]
}

@(private = "package")
_color_tables_destroy :: proc(f: ^Face) {
    if t, ok := &_color_tables[f]; ok {
        delete(t.palette)
        if t.colr_blob != nil do HB.blob_destroy(t.colr_blob)
        if t.cpal_blob != nil do HB.blob_destroy(t.cpal_blob)
        delete_key(&_color_tables, f)
    }
}

@(private = "package")
_color_tables_destroy_all :: proc() {
    delete(_color_tables)
    _color_tables = nil
}
