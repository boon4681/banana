package text

import "core:c"
import "core:math"
import "core:slice"
import "src:core/common"
import MSDF "src:msdfgen"

MSDF_ATLAS_SIZE     :: #config(BANANA_MSDF_ATLAS_INITIAL, 1024)
MSDF_ATLAS_MAX_SIZE :: #config(BANANA_MSDF_ATLAS_MAX, 4096)
MSDF_EM_PIXELS      :: #config(BANANA_MSDF_EM, 64.0)
MSDF_RANGE_PX       :: 4.0
MSDF_PADDING        :: 5
MSDF_GUTTER         :: 1 // One texel prevents bilinear sampling across packed tiles.

#assert(MSDF_ATLAS_SIZE > 0)
#assert(MSDF_ATLAS_MAX_SIZE >= MSDF_ATLAS_SIZE)

MSDF_Glyph :: struct {
	// Glyph plane bounds in em: left, bottom, right, top.
    plane: [4]f32,
	// Pixel atlas bounds: left, bottom, right, top. Keeping these unnormalized
	// lets existing glyph records survive atlas growth without rewriting them.
    atlas: [4]f32,
}

@(private="package")
_MSDF_Key :: struct {
    face:   ^Face,
    gid:    u32,
    embold: u16,
}

@(private="package")
_msdf_pixels: []u8

@(private="package")
_msdf_size: int = MSDF_ATLAS_SIZE

@(private="package")
_msdf_glyphs: map[_MSDF_Key]MSDF_Glyph

@(private="package")
_msdf_x: int

@(private="package")
_msdf_y: int

@(private="package")
_msdf_row_h: int

@(private="package")
_msdf_version: u64

@(private="package")
_msdf_dirty_lo: int = MSDF_ATLAS_SIZE

@(private="package")
_msdf_dirty_hi: int

msdf_atlas_data :: proc() -> (pixels: []u8, width, height: int, version: u64) {
    return _msdf_pixels, _msdf_size, _msdf_size, _msdf_version
}

// Returns only an already-loaded or already-generated record.
msdf_glyph_cached :: proc(face: ^Face, gid: u32, embold: f32 = 0) -> (MSDF_Glyph, bool) {
    if face == nil || _msdf_glyphs == nil do return {}, false
    return _msdf_glyphs[_MSDF_Key{face, gid, embolden_steps(embold)}]
}

// The atlas packs glyphs from every face into one shared sheet, so it is only released once the whole set goes away.
@(private="package")
_msdf_destroy :: proc() {
    delete(_msdf_pixels)
    _msdf_pixels = nil
    delete(_msdf_glyphs)
    _msdf_glyphs = nil
    _msdf_size = MSDF_ATLAS_SIZE
    _msdf_x, _msdf_y, _msdf_row_h = 0, 0, 0
    _msdf_dirty_lo, _msdf_dirty_hi = MSDF_ATLAS_SIZE, 0
    _msdf_version += 1
}

msdf_atlas_dirty_rows :: proc() -> (lo, hi: int) {
    return _msdf_dirty_lo, _msdf_dirty_hi
}

// Call once per frame, after drawing, so rows stay dirty for every consumer
// that draws this frame rather than only the first one.
msdf_atlas_clear_dirty :: proc() {
    _msdf_dirty_lo = _msdf_size
    _msdf_dirty_hi = 0
}

@(private="file")
_mark_dirty :: proc(lo, hi: int) {
    _msdf_dirty_lo = min(_msdf_dirty_lo, max(lo, 0))
    _msdf_dirty_hi = max(_msdf_dirty_hi, min(hi, _msdf_size))
}

@(private = "package")
_next_atlas_size :: proc(current, required, maximum: int) -> (int, bool) {
    if current <= 0 || current >= maximum || required > maximum do return current, false
    next := current
    for next < required || next == current {
        next = min(next * 2, maximum)
        if next == current do return current, false
    }
    return next, true
}

@(private = "package")
_copy_atlas_rows :: proc(dst: []u8, dst_size: int, src: []u8, src_size: int) {
    old_row := src_size * 4
    new_row := dst_size * 4
    for y in 0 ..< src_size {
        copy(dst[y * new_row:][:old_row], src[y * old_row:][:old_row])
    }
}

// Grows synchronously.
@(private = "file")
_grow_atlas :: proc(required: int = 0) -> bool {
    next, ok := _next_atlas_size(_msdf_size, required, MSDF_ATLAS_MAX_SIZE)
    if !ok do return false

    pixels := make([]u8, next * next * 4)
    if _msdf_pixels != nil {
        _copy_atlas_rows(pixels, next, _msdf_pixels, _msdf_size)
        delete(_msdf_pixels)
    }

    _msdf_pixels = pixels
    _msdf_size = next
    _msdf_version += 1
    _msdf_dirty_lo = 0
    _msdf_dirty_hi = next
    return true
}

@(private = "file")
_reserve_slot :: proc(w, h: int) -> (at_x, at_y, row_h: int, ok: bool) {
    for {
        if w > _msdf_size || h > _msdf_size {
            if !_grow_atlas(max(w, h)) do return
            continue
        }

        // Continue the current shelf when possible.
        if _msdf_x + w <= _msdf_size && _msdf_y + h <= _msdf_size {
            return _msdf_x, _msdf_y, _msdf_row_h, true
        }

        // Otherwise start a new shelf before growing.
        next_y := _msdf_y + _msdf_row_h
        if next_y + h <= _msdf_size {
            return 0, next_y, 0, true
        }

        if !_grow_atlas() do return
    }
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
    msdf_zone := common.profile_begin(.MSDF_Generate)
    defer common.profile_end(.MSDF_Generate, msdf_zone)

    outline := glyph(face, gid, embold)
    if outline.curve_count == 0 || outline.contour_count == 0 do return {}, false
    if embold > 0 && _thinnest_contour(outline) < 3 * f32(MSDF_RANGE_PX) / MSDF_EM_PIXELS {
        return {}, false
    }
    w := int(math.ceil((outline.max.x - outline.min.x) * f32(MSDF_EM_PIXELS))) + 2 * MSDF_PADDING
    h := int(math.ceil((outline.max.y - outline.min.y) * f32(MSDF_EM_PIXELS))) + 2 * MSDF_PADDING
    if w <= 0 || h <= 0 || w > MSDF_ATLAS_MAX_SIZE || h > MSDF_ATLAS_MAX_SIZE do return {}, false

    if _msdf_pixels == nil {
        _msdf_pixels = make([]u8, _msdf_size * _msdf_size * 4)
    }
    // Commit packing only after all failure paths pass.
    at_x, at_y, row_h, slot_ok := _reserve_slot(w, h)
    if !slot_ok do return {}, false

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

    // Clear gutters when reusing atlas slots.
    for row in 0 ..< h + MSDF_GUTTER {
        y := at_y + row
        if y >= _msdf_size do break
        span := min(w + MSDF_GUTTER, _msdf_size - at_x)
        dst := (y * _msdf_size + at_x) * 4
        if row < h {
            copy(_msdf_pixels[dst:][:w * 4], tile[row * w * 4:][:w * 4])
            slice.zero(_msdf_pixels[dst + w * 4:][:(span - w) * 4])
        } else {
            slice.zero(_msdf_pixels[dst:][:span * 4])
        }
    }

    _mark_dirty(at_y, at_y + h + MSDF_GUTTER)

    pad_em := f32(MSDF_PADDING) / f32(MSDF_EM_PIXELS)
    out := MSDF_Glyph {
        plane = {outline.min.x - pad_em, outline.min.y - pad_em, outline.max.x + pad_em, outline.max.y + pad_em},
        atlas = {
            f32(at_x),
            f32(at_y),
            f32(at_x + w),
            f32(at_y + h),
        },
    }
    _msdf_glyphs[key] = out
    // Atlas borders sample the gutter outside MSDF_PADDING.
    _msdf_x = at_x + w + MSDF_GUTTER
    _msdf_y = at_y
    _msdf_row_h = max(row_h, h)
    _msdf_version += 1
    return out, true
}
