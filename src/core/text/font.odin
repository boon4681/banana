package text

import "core:c"
import "core:slice"
import stbtt "vendor:stb/truetype"
import HB "src:harfbuzz"

Face :: struct {
    data:          []u8, // owned copy of the font file
    info:          stbtt.fontinfo,
    blob:          HB.Blob,
    hb_face:       HB.Face,
    hb:            HB.Font,
    upem:          f32,
    inv_upem:      f32,
    ascent:        f32,
    descent:       f32, // negative (below baseline)
    line_gap:      f32,
    space_advance: f32,
    glyphs:        map[u32]Glyph,
}

// Ordered fallback chain
Font_Set :: struct {
    faces: [dynamic]^Face,
}

set_create :: proc() -> ^Font_Set {
    return new(Font_Set)
}

when ODIN_OS == .JS {
    load_font :: proc {
        _web_load_font
    }
} else {
    load_font :: proc {
        _native_load_font
    }
}

set_register :: proc(set: ^Font_Set, data: []u8, index := 0) -> ^Face {
    off := stbtt.GetFontOffsetForIndex(raw_data(data), c.int(index))
    if off < 0 do return nil

    f := new(Face)
    f.data = slice.clone(data)
    if !stbtt.InitFont(&f.info, raw_data(f.data), off) {
        delete(f.data)
        free(f)
        return nil
    }

    f.blob = HB.blob_create(raw_data(f.data), c.uint(len(f.data)), .Readonly, nil, nil)
    f.hb_face = HB.face_create(f.blob, c.uint(index))
    f.hb = HB.font_create(f.hb_face)
    f.upem = f32(HB.face_get_upem(f.hb_face))
    if f.upem <= 0 do f.upem = 1000
    f.inv_upem = 1.0 / f.upem
    // Scale to upem so hb outputs plain font units; divide by upem for em.
    HB.font_set_scale(f.hb, c.int(f.upem), c.int(f.upem))

    ext: HB.Font_Extents
    if HB.font_get_h_extents(f.hb, &ext) != 0 {
        f.ascent = f32(ext.ascender) * f.inv_upem
        f.descent = f32(ext.descender) * f.inv_upem
        f.line_gap = f32(ext.line_gap) * f.inv_upem
    } else {
        a, d, g: c.int
        stbtt.GetFontVMetrics(&f.info, &a, &d, &g)
        f.ascent = f32(a) * f.inv_upem
        f.descent = f32(d) * f.inv_upem
        f.line_gap = f32(g) * f.inv_upem
    }

    adv, lsb: c.int
    stbtt.GetCodepointHMetrics(&f.info, ' ', &adv, &lsb)
    f.space_advance = f32(adv) * f.inv_upem

    append(&set.faces, f)
    return f
}

set_destroy :: proc(set: ^Font_Set) {
    if set == nil do return
    for f in set.faces {
        delete(f.glyphs)
        HB.font_destroy(f.hb)
        HB.face_destroy(f.hb_face)
        HB.blob_destroy(f.blob)
        delete(f.data)
        free(f)
    }
    delete(set.faces)
    free(set)
}

ascent :: proc(set: ^Font_Set) -> f32 {
    if len(set.faces) == 0 do return 0
    return set.faces[0].ascent
}

descent :: proc(set: ^Font_Set) -> f32 {
    if len(set.faces) == 0 do return 0
    return set.faces[0].descent
}

// CSS `line-height: normal` for the primary face.
line_height :: proc(set: ^Font_Set) -> f32 {
    if len(set.faces) == 0 do return 0
    f := set.faces[0]
    return f.ascent - f.descent + f.line_gap
}
