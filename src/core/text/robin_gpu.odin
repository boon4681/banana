package text

import "core:math"

ROBIN_TEXT_ENABLED :: #config(BANANA_TEXT_ROBIN, true)            // ENABLE by default
ROBIN_GPU_UNSAFE   :: #config(BANANA_TEXT_ROBIN_GPU_UNSAFE, true) // ENABLE by default
// backend_gl and backend_webgl both implement the ROBIN program; the WebGL2
// path needs EXT_color_buffer_float for its RG32F cell texture.
ROBIN_TEXT_ACTIVE :: ROBIN_TEXT_ENABLED && ROBIN_GPU_UNSAFE
ROBIN_GRID        :: 16
// Must stay 0: no sampling border is needed, and
// any padding overlaps neighbouring glyph quads.
ROBIN_PADDING_EM :: 0.0

Robin_Glyph :: struct {
    // Padded glyph bounds in em: left, bottom, right, top.
    plane: [4]f32,
    // Index of the first of ROBIN_GRID^2 cell records in robin_render_data.
    cell_base: u32,
}

@(private="file")
_Robin_Key :: struct {
    face:   ^Face,
    gid:    u32,
    embold: u16,
}

@(private="file") _robin_glyphs: map[_Robin_Key]Robin_Glyph
@(private="file") _robin_gpu_data: [dynamic][2]f32
@(private="file") _robin_gpu_version: u64

robin_render_data :: proc() -> ([][2]f32, u64) {
    return _robin_gpu_data[:], _robin_gpu_version
}

// Glyph entries are keyed by face, but the packed cell/curve buffer is shared across every face,
// so this only runs once the whole set is going away.
@(private="package")
_robin_destroy :: proc() {
    delete(_robin_glyphs)
    _robin_glyphs = nil
    delete(_robin_gpu_data)
    _robin_gpu_data = nil
    _robin_gpu_version += 1
}

// Generates synchronously, just like the MSDF cache.
robin_glyph :: proc(face: ^Face, gid: u32, embold: f32 = 0) -> (Robin_Glyph, bool) {
    when !ROBIN_TEXT_ACTIVE do return {}, false
    if face == nil do return {}, false
    if _robin_glyphs == nil do _robin_glyphs = make(map[_Robin_Key]Robin_Glyph)
    key := _Robin_Key{face, gid, embolden_steps(embold)}
    if cached, ok := _robin_glyphs[key]; ok do return cached, true

    g := glyph(face, gid, embold)
    if g.curve_count == 0 do return {}, false
    curves, _ := curve_data()
    source := curves[int(g.curve_base) * 3:][:int(g.curve_count) * 3]

    plane_min := g.min - ROBIN_PADDING_EM
    plane_max := g.max + ROBIN_PADDING_EM
    span := plane_max - plane_min
    if span.x <= 0 || span.y <= 0 do return {}, false

    transformed := make([][2]f32, len(source), context.temp_allocator)
    for p, i in source {
        t := (p - plane_min) / span * f32(ROBIN_GRID)
        if abs(t.y - math.round(t.y)) < 1e-5 do t.y += 3e-5
        transformed[i] = t
    }
    raster := robin_build_raster(
        transformed, {0, 0}, {ROBIN_GRID, ROBIN_GRID},
        ROBIN_GRID, ROBIN_GRID, context.temp_allocator,
    )

    cell_count := ROBIN_GRID * ROBIN_GRID
    encoded := make([dynamic][2]f32, cell_count, cell_count + len(raster.memberships) * 3, context.temp_allocator)
    global_base := len(_robin_gpu_data)
    for cell, ci in raster.cells {
        if int(cell.count) > 255 do return {}, false
        count := int(cell.count)
        start := global_base + len(encoded)
        if start + count * 3 >= 1 << 24 do return {}, false
        members := raster.memberships[cell.first:][:count]
        for curve in members {
            i := int(curve) * 3
            append(&encoded, transformed[i], transformed[i + 1], transformed[i + 2])
        }
        packed := int(clamp(i32(cell.partial_winding), -128, 127) + 128) * 256 + count
        encoded[ci] = {f32(packed), f32(start)}
    }

    if _robin_gpu_data == nil do _robin_gpu_data = make([dynamic][2]f32)
    append(&_robin_gpu_data, ..encoded[:])
    out := Robin_Glyph{
        plane     = {plane_min.x, plane_min.y, plane_max.x, plane_max.y},
        cell_base = u32(global_base),
    }
    _robin_glyphs[key] = out
    _robin_gpu_version += 1
    return out, true
}
