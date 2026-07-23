package text

import "core:c"
import "core:math"
import MSDF "src:msdfgen"

MSDF_ATLAS_SIZE :: 2048
MSDF_EM_PIXELS  :: 64.0
MSDF_RANGE_PX   :: 4.0
MSDF_PADDING    :: 5

MSDF_Glyph :: struct {
	// Glyph plane bounds in em: left, bottom, right, top.
    plane: [4]f32,
	// OpenGL-normalized atlas bounds: left, bottom, right, top.
    uv: [4]f32,
}

@(private="file")
_MSDF_Key :: struct {
    face:   ^Face,
    gid:    u32,
    embold: u16,
}

@(private="file")
_msdf_pixels: []u8

@(private="file")
_msdf_glyphs: map[_MSDF_Key]MSDF_Glyph

@(private="file")
_msdf_x: int

@(private="file")
_msdf_y: int

@(private="file")
_msdf_row_h: int

@(private="file")
_msdf_version: u64

msdf_atlas_data :: proc() -> (pixels: []u8, width, height: int, version: u64) {
    return _msdf_pixels, MSDF_ATLAS_SIZE, MSDF_ATLAS_SIZE, _msdf_version
}

// Smallest dimension of any single contour, in em.
@(private = "file")
_thinnest_contour :: proc(g: Glyph) -> f32 {
    curves, _ := curve_data()
    pts := curves[int(g.curve_base) * 3:][:int(g.curve_count) * 3]
    out := f32(math.F32_MAX)
    start := u32(0)
    for e in glyph_contours(g) {
        mn := [2]f32{math.F32_MAX, math.F32_MAX}
        mx := [2]f32{-math.F32_MAX, -math.F32_MAX}
        for p in pts[int(start) * 3:int(e) * 3] {
            mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
            mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
        }
        out = min(out, min(mx.x - mn.x, mx.y - mn.y))
        start = e
    }
    return out
}

msdf_glyph :: proc(face: ^Face, gid: u32, embold: f32 = 0) -> (MSDF_Glyph, bool) {
    if face == nil do return {}, false
    if _msdf_glyphs == nil do _msdf_glyphs = make(map[_MSDF_Key]MSDF_Glyph)
    key := _MSDF_Key{face, gid, embolden_steps(embold)}
    if cached, ok := _msdf_glyphs[key]; ok do return cached, true

    outline := glyph(face, gid, embold)
    if outline.curve_count == 0 || outline.contour_count == 0 do return {}, false
    if embold > 0 && _thinnest_contour(outline) < 3 * f32(MSDF_RANGE_PX) / MSDF_EM_PIXELS {
        return {}, false
    }
    w := int(math.ceil((outline.max.x - outline.min.x) * f32(MSDF_EM_PIXELS))) + 2 * MSDF_PADDING
    h := int(math.ceil((outline.max.y - outline.min.y) * f32(MSDF_EM_PIXELS))) + 2 * MSDF_PADDING
    if w <= 0 || h <= 0 || w > MSDF_ATLAS_SIZE || h > MSDF_ATLAS_SIZE do return {}, false

    if _msdf_pixels == nil {
        _msdf_pixels = make([]u8, MSDF_ATLAS_SIZE * MSDF_ATLAS_SIZE * 4)
    }
    if _msdf_x + w > MSDF_ATLAS_SIZE {
        _msdf_x = 0
        _msdf_y += _msdf_row_h
        _msdf_row_h = 0
    }
    if _msdf_y + h > MSDF_ATLAS_SIZE do return {}, false

    curves, _ := curve_data()
    point_start := int(outline.curve_base) * 3
    points := curves[point_start:][:int(outline.curve_count) * 3]
    contours := glyph_contours(outline)
    tile := make([]u8, w * h * 4, context.temp_allocator)
    translate_x := f64(-outline.min.x) + f64(MSDF_PADDING) / MSDF_EM_PIXELS
    translate_y := f64(-outline.min.y) + f64(MSDF_PADDING) / MSDF_EM_PIXELS
    ok := MSDF.generate(
		cast(^f32)raw_data(points),
		c.int(outline.curve_count),
		raw_data(contours),
		c.int(outline.contour_count),
		c.int(w), c.int(h),
		MSDF_EM_PIXELS, translate_x, translate_y, MSDF_RANGE_PX,
		raw_data(tile),
    )
    if !ok do return {}, false

    for row in 0 ..< h {
        dst := ((_msdf_y + row) * MSDF_ATLAS_SIZE + _msdf_x) * 4
        src := row * w * 4
        copy(_msdf_pixels[dst:][:w * 4], tile[src:][:w * 4])
    }

    inv := 1.0 / f32(MSDF_ATLAS_SIZE)
    pad_em := f32(MSDF_PADDING) / f32(MSDF_EM_PIXELS)
    out := MSDF_Glyph {
        plane = {outline.min.x - pad_em, outline.min.y - pad_em, outline.max.x + pad_em, outline.max.y + pad_em},
        uv = {
            f32(_msdf_x) * inv,
            f32(_msdf_y) * inv,
            f32(_msdf_x + w) * inv,
            f32(_msdf_y + h) * inv,
        },
    }
    _msdf_glyphs[key] = out
    _msdf_x += w
    _msdf_row_h = max(_msdf_row_h, h)
    _msdf_version += 1
    return out, true
}
