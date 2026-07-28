package text

import "core:c"
import "core:slice"
import "core:strings"
import stbtt "vendor:stb/truetype"
import HB "src:harfbuzz"

FontWeight         :: distinct u16

WEIGHT_THIN        :: FontWeight(100)
WEIGHT_EXTRA_LIGHT :: FontWeight(200)
WEIGHT_LIGHT       :: FontWeight(300)
WEIGHT_NORMAL      :: FontWeight(400)
WEIGHT_MEDIUM      :: FontWeight(500)
WEIGHT_SEMI_BOLD   :: FontWeight(600)
WEIGHT_BOLD        :: FontWeight(700)
WEIGHT_EXTRA_BOLD  :: FontWeight(800)
WEIGHT_BLACK       :: FontWeight(900)

@(private) SYNTHETIC_BOLD_MAX :: 0.035
@(private) SYNTHETIC_BOLD_SPAN :: 300.0

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
    glyphs:        map[Glyph_Key]Glyph,

    weight: FontWeight, // as authored by the file, or the variable default
    // A variable face covers [wght_min, wght_max] by instancing rather than by
    // being one fixed weight; nil `hb` instances are cut from it on demand.
    variable:  bool,
    wght_min:  FontWeight,
    wght_max:  FontWeight,
    instances: map[FontWeight]^Face, // variable faces only; owned
    // Set on instances so they aren't re-instanced or re-registered.
    instance_of: ^Face,

    family: string, // owned; weight matching only ever ranges within one family
}

// Ordered fallback chain. Faces are grouped by family.
Font_Set :: struct {
    faces: [dynamic]^Face,

    // Cached platform fallback for an uncovered run.
    on_missing: proc(set: ^Font_Set, r: rune, script: u32) -> ^Face,
    resolved:   map[Fallback_Key]^Face,
}

Fallback_Key :: struct {
    r:      rune,
    script: u32,
}

set_create :: proc() -> ^Font_Set {
    set := new(Font_Set)
    set.on_missing = _platform_fallback
    return set
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

set_register :: proc(set: ^Font_Set, data: []u8, index := 0, family := "") -> ^Face {
    f := _face_create(data, index)
    if f == nil do return nil
    if family != "" {
        delete(f.family)
        f.family = strings.clone(family)
    }
    append(&set.faces, f)
    return f
}

WGHT :: HB.Tag(0x77676874) // 'wght'

@(private)
_face_create :: proc(data: []u8, index: int) -> ^Face {
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
    _face_init_metrics(f)

    f.weight = _os2_weight(f)
    f.family = _name_family(f)
    axis: HB.OT_Var_Axis_Info
    if HB.ot_var_has_data(f.hb_face) != 0 && HB.ot_var_find_axis_info(f.hb_face, WGHT, &axis) != 0 {
        f.variable = true
        f.wght_min = FontWeight(clamp(axis.min_value, 1, 1000))
        f.wght_max = FontWeight(clamp(axis.max_value, 1, 1000))
        f.weight = FontWeight(clamp(axis.default_value, 1, 1000))
    }
    return f
}

NAME :: HB.Tag(0x6E616D65) // 'name'

NAME_ID_FAMILY            :: 1
NAME_ID_TYPOGRAPHIC_FAMILY :: 16

// Prefer typographic family names so weights remain grouped.
@(private = "file")
_name_family :: proc(f: ^Face) -> string {
    blob := HB.face_reference_table(f.hb_face, NAME)
    defer HB.blob_destroy(blob)
    n: c.uint
    data := HB.blob_get_data(blob, &n)
    if data == nil || n < 6 do return ""

    be16 :: proc(d: [^]u8, off: u32, n: c.uint) -> (u16, bool) {
        if u32(n) < off + 2 do return 0, false
        return u16(d[off]) << 8 | u16(d[off + 1]), true
    }

    count, ok1 := be16(data, 2, n)
    str_off, ok2 := be16(data, 4, n)
    if !ok1 || !ok2 do return ""

    best_off, best_len: u32
    best_id := max(u16)
    for i in 0 ..< u32(count) {
        rec := 6 + i * 12
        plat, k1 := be16(data, rec, n)
        enc, k2 := be16(data, rec + 2, n)
        name_id, k3 := be16(data, rec + 6, n)
        slen, k4 := be16(data, rec + 8, n)
        soff, k5 := be16(data, rec + 10, n)
        if !k1 || !k2 || !k3 || !k4 || !k5 do break
        if name_id != NAME_ID_FAMILY && name_id != NAME_ID_TYPOGRAPHIC_FAMILY do continue
        // Windows/Unicode BMP encodings are UTF-16BE; skip Mac Roman entries.
        if !(plat == 3 && (enc == 1 || enc == 0)) && plat != 0 do continue
        if name_id < best_id || (name_id == best_id && best_len == 0) {
            best_id = name_id
            best_off = u32(str_off) + u32(soff)
            best_len = u32(slen)
        }
        if name_id == NAME_ID_TYPOGRAPHIC_FAMILY do break
    }
    if best_len == 0 || best_off + best_len > u32(n) do return ""

    b := strings.builder_make()
    for i := u32(0); i + 1 < best_len; i += 2 {
        cp := rune(u16(data[best_off + i]) << 8 | u16(data[best_off + i + 1]))
        if cp == 0 do continue
        strings.write_rune(&b, cp)
    }
    return strings.to_string(b)
}

@(private)
_face_init_metrics :: proc(f: ^Face) {
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
}

OS2 :: HB.Tag(0x4F532F32) // 'OS/2'

// usWeightClass lives at OS/2 offset 4, big-endian.
@(private)
_os2_weight :: proc(f: ^Face) -> FontWeight {
    blob := HB.face_reference_table(f.hb_face, OS2)
    defer HB.blob_destroy(blob)
    n: c.uint
    data := HB.blob_get_data(blob, &n)
    if data == nil || n < 6 do return WEIGHT_NORMAL
    w := u16(data[4]) << 8 | u16(data[5])
    // Legacy 1-9 scale (some old fonts) and out-of-range values.
    if w >= 1 && w <= 9 do w *= 100
    if w < 1 || w > 1000 do return WEIGHT_NORMAL
    return FontWeight(w)
}

@(private)
_face_instance :: proc(base: ^Face, w: FontWeight) -> ^Face {
    if inst, ok := base.instances[w]; ok do return inst
    f := new(Face)
    f.data = base.data
    f.info = base.info
    f.blob = base.blob
    f.hb_face = base.hb_face
    f.hb = HB.font_create(base.hb_face)
    f.instance_of = base
    f.weight = w
    f.variable = true
    f.wght_min = base.wght_min
    f.wght_max = base.wght_max

    v := HB.Variation{tag = WGHT, value = f32(w)}
    HB.font_set_variations(f.hb, &v, 1)
    _face_init_metrics(f)

    if base.instances == nil do base.instances = make(map[FontWeight]^Face)
    base.instances[w] = f
    return f
}

// CSS Fonts weight matching, over one coverage group.
// https://www.w3.org/TR/css-fonts-4/#font-style-matching
@(private)
_match_weight :: proc(faces: []^Face, want: FontWeight) -> ^Face {
    if len(faces) == 0 do return nil

    best: ^Face
    best_key: [2]int = {max(int), max(int)}
    for f in faces {
        // A variable face can hit `want` exactly anywhere in its axis range.
        d: int
        if f.variable && want >= f.wght_min && want <= f.wght_max {
            d = 0
        } else {
            fw := f.weight
            if f.variable do fw = clamp(want, f.wght_min, f.wght_max)
            d = abs(int(fw) - int(want))
        }
        f_eff := f.weight
        if f.variable do f_eff = clamp(want, f.wght_min, f.wght_max)
        wrong_way: int
        if want < WEIGHT_NORMAL {
            wrong_way = 1 if f_eff > want else 0
        } else if want > WEIGHT_MEDIUM {
            wrong_way = 1 if f_eff < want else 0
        } else {
            wrong_way = 1 if f_eff > WEIGHT_MEDIUM else 0
        }
        key := [2]int{wrong_way, d}
        if key.x < best_key.x || (key.x == best_key.x && key.y < best_key.y) {
            best, best_key = f, key
        }
    }
    return best
}

@(private = "package")
_resolve_weight :: proc(set: ^Font_Set, base: ^Face, want: FontWeight) -> (face: ^Face, extra_bold: f32) {
    group := make([dynamic]^Face, context.temp_allocator)
    for f in set.faces {
        if _same_coverage(f, base) do append(&group, f)
    }
    if len(group) == 0 do append(&group, base)

    face = _match_weight(group[:], want)
    if face == nil do face = base
    if face.variable {
        w := clamp(want, face.wght_min, face.wght_max)
        if w != face.weight || face.instance_of != nil {
            root := face.instance_of if face.instance_of != nil else face
            face = _face_instance(root, w)
        }
    }
    // Nothing in the family is heavy enough: fake the remainder.
    if want > face.weight {
        t := f32(want - face.weight) / SYNTHETIC_BOLD_SPAN
        extra_bold = min(t, 1) * SYNTHETIC_BOLD_MAX
    }
    return
}

@(private = "file")
_same_coverage :: proc(a, b: ^Face) -> bool {
    if a == b do return true
    if a.instance_of != nil || b.instance_of != nil do return false
    if a.family == "" || b.family == "" do return false
    return a.family == b.family
}

set_destroy :: proc(set: ^Font_Set) {
    if set == nil do return
    for f in set.faces {
        // Instances borrow the parent's blob/face/data; only `hb` is theirs.
        for _, inst in f.instances {
            delete(inst.glyphs)
            HB.font_destroy(inst.hb)
            free(inst)
        }
        delete(f.instances)
        delete(f.glyphs)
        delete(f.family)
        _color_tables_destroy(f)
        _color_bitmaps_destroy(f)
        HB.font_destroy(f.hb)
        HB.face_destroy(f.hb_face)
        HB.blob_destroy(f.blob)
        delete(f.data)
        free(f)
    }
    delete(set.faces)
    delete(set.resolved)
    free(set)
}

// Seed an empty set from the platform's default UI face.
@(private = "package")
_ensure_primary :: proc(set: ^Font_Set) -> ^Face {
    if set == nil do return nil
    if len(set.faces) > 0 do return set.faces[0]
    return _fallback_lookup(set, 'A', 0)
}

// Cache platform faces in the fallback chain.
@(private = "package")
_fallback_lookup :: proc(set: ^Font_Set, r: rune, script: u32) -> ^Face {
    key := Fallback_Key{r, script}
    if f, ok := set.resolved[key]; ok do return f
    f: ^Face
    if set.on_missing != nil do f = set.on_missing(set, r, script)
    set.resolved[key] = f
    return f
}

// Vertical metrics come from the weight actually used, since a bold or a
// variable instance can differ from the regular face.
@(private = "file")
_primary :: proc(set: ^Font_Set, w: FontWeight) -> ^Face {
    if set == nil do return nil
    if _ensure_primary(set) == nil do return nil
    face, _ := _resolve_weight(set, set.faces[0], w)
    return face
}

ascent :: proc(set: ^Font_Set, w := WEIGHT_NORMAL) -> f32 {
    f := _primary(set, w)
    return f.ascent if f != nil else 0
}

descent :: proc(set: ^Font_Set, w := WEIGHT_NORMAL) -> f32 {
    f := _primary(set, w)
    return f.descent if f != nil else 0
}

// CSS `line-height: normal` for the primary face.
line_height :: proc(set: ^Font_Set, w := WEIGHT_NORMAL) -> f32 {
    f := _primary(set, w)
    if f == nil do return 0
    return f.ascent - f.descent + f.line_gap
}
