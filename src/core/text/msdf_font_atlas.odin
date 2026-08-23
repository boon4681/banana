package text

MSDF_FONT_ATLAS_MAGIC   :: u32(0x42414E41) // "BANA" in file byte order
MSDF_FONT_ATLAS_VERSION :: u32(1)

MSDF_Font_Atlas_Error :: enum {
    None,
    Empty,
    Busy,
    Invalid,
    Unsupported,
    Font_Load,
}

@(private="file")
_MSDF_File_Face :: struct {
    source_index: u32,
    data:         []u8,
}

@(private="file")
_MSDF_File_Glyph :: struct {
    face_index: u32,
    gid:        u32,
    embold:     u16,
    glyph:      MSDF_Glyph,
}

@(private="file")
_append_u16 :: proc(out: ^[dynamic]u8, value: u16) {
    append(out, u8(value >> 8), u8(value))
}

@(private="file")
_append_u32 :: proc(out: ^[dynamic]u8, value: u32) {
    append(out, u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value))
}

@(private="file")
_append_f32 :: proc(out: ^[dynamic]u8, value: f32) {
    _append_u32(out, transmute(u32)value)
}

@(private="file")
_read_u16 :: proc(data: []u8, cursor: ^int) -> (u16, bool) {
    if cursor^ + 2 > len(data) do return 0, false
    out := u16(data[cursor^]) << 8 | u16(data[cursor^ + 1])
    cursor^ += 2
    return out, true
}

@(private="file")
_read_u32 :: proc(data: []u8, cursor: ^int) -> (u32, bool) {
    if cursor^ + 4 > len(data) do return 0, false
    out := u32(data[cursor^]) << 24 |
        u32(data[cursor^ + 1]) << 16 |
        u32(data[cursor^ + 2]) << 8 |
        u32(data[cursor^ + 3])
    cursor^ += 4
    return out, true
}

@(private="file")
_read_f32 :: proc(data: []u8, cursor: ^int) -> (f32, bool) {
    bits, ok := _read_u32(data, cursor)
    return transmute(f32)bits, ok
}

@(private="file")
_append_glyph :: proc(out: ^[dynamic]u8, entry: _MSDF_File_Glyph) {
    _append_u32(out, entry.face_index)
    _append_u32(out, entry.gid)
    _append_u16(out, entry.embold)
    _append_u16(out, 0) // reserved for a future record version
    for v in entry.glyph.plane do _append_f32(out, v)
    for v in entry.glyph.atlas do _append_f32(out, v)
}

@(private="file")
_read_glyph :: proc(data: []u8, cursor: ^int) -> (_MSDF_File_Glyph, bool) {
    out: _MSDF_File_Glyph
    ok: bool
    out.face_index, ok = _read_u32(data, cursor)
    if !ok do return {}, false
    out.gid, ok = _read_u32(data, cursor)
    if !ok do return {}, false
    out.embold, ok = _read_u16(data, cursor)
    if !ok do return {}, false
    _, ok = _read_u16(data, cursor)
    if !ok do return {}, false
    for i in 0 ..< len(out.glyph.plane) {
        out.glyph.plane[i], ok = _read_f32(data, cursor)
        if !ok do return {}, false
    }
    for i in 0 ..< len(out.glyph.atlas) {
        out.glyph.atlas[i], ok = _read_f32(data, cursor)
        if !ok do return {}, false
    }
    return out, true
}

// Encodes all base faces in `set` and the MSDF entries currently in the shared atlas.
// Call msdf_glyph for the glyphs you want before encoding; ordinary fonts otherwise remain ROBIN-only at runtime.
msdf_font_atlas_encode :: proc(set: ^Font_Set, allocator := context.allocator) -> (data: []u8, err: MSDF_Font_Atlas_Error) {
    if set == nil || len(set.faces) == 0 || _msdf_pixels == nil || _msdf_glyphs == nil do return nil, .Empty
    if u64(len(_msdf_pixels)) > u64(max(u32)) do return nil, .Invalid

    face_index := make(map[^Face]u32, len(set.faces), context.temp_allocator)
    for face, i in set.faces {
        if face == nil || u64(len(face.data)) > u64(max(u32)) do return nil, .Invalid
        face_index[face] = u32(i)
    }

    glyphs := make([dynamic]_MSDF_File_Glyph, 0, len(_msdf_glyphs), context.temp_allocator)
    for key, glyph in _msdf_glyphs {
        index, ok := face_index[key.face]
        // Variable instances do not share the base face's state;
        if !ok || key.face.instance_of != nil do continue
        append(&glyphs, _MSDF_File_Glyph{index, key.gid, key.embold, glyph})
    }
    if len(glyphs) == 0 do return nil, .Empty

    header_bytes :: 24
    face_bytes := 0
    for face in set.faces do face_bytes += 8 + len(face.data)
    glyph_bytes := len(glyphs) * 44
    total := header_bytes + face_bytes + glyph_bytes + len(_msdf_pixels)
    if total < 0 do return nil, .Invalid

    out := make([dynamic]u8, 0, total, allocator)
    _append_u32(&out, MSDF_FONT_ATLAS_MAGIC)
    _append_u32(&out, MSDF_FONT_ATLAS_VERSION)
    _append_u32(&out, u32(_msdf_size))
    _append_u32(&out, u32(len(set.faces)))
    _append_u32(&out, u32(len(glyphs)))
    _append_u32(&out, u32(len(_msdf_pixels)))
    for face in set.faces {
        _append_u32(&out, u32(face.source_index))
        _append_u32(&out, u32(len(face.data)))
        append(&out, ..face.data)
    }
    for entry in glyphs do _append_glyph(&out, entry)
    append(&out, .._msdf_pixels)
    return out[:], .None
}

// Loads source faces and prebuilt MSDF records into `set`.
load_font_from_msdf_atlas_data :: proc(set: ^Font_Set, data: []u8) -> MSDF_Font_Atlas_Error {
    if set == nil || len(data) < 24 do return .Invalid
    if _msdf_pixels != nil || _msdf_glyphs != nil do return .Busy

    cursor := 0
    ok: bool
    magic: u32
    magic, ok = _read_u32(data, &cursor); if !ok || magic != MSDF_FONT_ATLAS_MAGIC do return .Invalid
    version: u32
    version, ok = _read_u32(data, &cursor); if !ok do return .Invalid
    if version != MSDF_FONT_ATLAS_VERSION do return .Unsupported
    atlas_size: u32
    atlas_size, ok = _read_u32(data, &cursor); if !ok || atlas_size == 0 || atlas_size > u32(MSDF_ATLAS_MAX_SIZE) do return .Invalid
    face_count: u32
    face_count, ok = _read_u32(data, &cursor); if !ok || face_count == 0 do return .Invalid
    glyph_count: u32
    glyph_count, ok = _read_u32(data, &cursor); if !ok || glyph_count == 0 do return .Invalid
    pixel_len: u32
    pixel_len, ok = _read_u32(data, &cursor); if !ok do return .Invalid

    atlas_pixels := int(atlas_size) * int(atlas_size) * 4
    if atlas_pixels != int(pixel_len) || atlas_pixels < 0 || atlas_pixels > len(data) do return .Invalid

    faces := make([]_MSDF_File_Face, int(face_count), context.temp_allocator)
    for i in 0 ..< len(faces) {
        faces[i].source_index, ok = _read_u32(data, &cursor); if !ok do return .Invalid
        byte_count, read_ok := _read_u32(data, &cursor)
        if !read_ok || byte_count > u32(len(data) - cursor) do return .Invalid
        faces[i].data = data[cursor:][:int(byte_count)]
        cursor += int(byte_count)
    }

    glyphs := make([]_MSDF_File_Glyph, int(glyph_count), context.temp_allocator)
    for i in 0 ..< len(glyphs) {
        glyphs[i], ok = _read_glyph(data, &cursor)
        record := glyphs[i]
        if !ok || record.face_index >= face_count ||
           record.glyph.atlas[0] < 0 || record.glyph.atlas[1] < 0 ||
           record.glyph.atlas[2] > f32(atlas_size) || record.glyph.atlas[3] > f32(atlas_size) ||
           record.glyph.atlas[0] >= record.glyph.atlas[2] || record.glyph.atlas[1] >= record.glyph.atlas[3] {
            return .Invalid
        }
    }
    if len(data) - cursor != atlas_pixels do return .Invalid

    loaded := make([]^Face, len(faces), context.temp_allocator)
    for record, i in faces {
        face := set_register(set, record.data, int(record.source_index))
        if face == nil do return .Font_Load
        face.prefer_msdf = true
        loaded[i] = face
    }

    _msdf_size = int(atlas_size)
    _msdf_pixels = make([]u8, atlas_pixels)
    copy(_msdf_pixels, data[cursor:])
    _msdf_glyphs = make(map[_MSDF_Key]MSDF_Glyph, len(glyphs))
    for record in glyphs {
        _msdf_glyphs[_MSDF_Key{loaded[record.face_index], record.gid, record.embold}] = record.glyph
    }
    // The imported sheet is full from the packer's perspective.
    _msdf_x, _msdf_y, _msdf_row_h = 0, _msdf_size, 0
    _msdf_dirty_lo, _msdf_dirty_hi = 0, _msdf_size
    _msdf_version += 1
    return .None
}
