// =====================================================
// NOT SURE IF IT GONNA DO SOME SEQ-FUALT OR NOT
// REQUIRE FURTHER TESTING
// =====================================================

#+build windows
package text

import "core:os"
import win "core:sys/windows"

// Keep the DirectWrite surface file-scoped.
foreign import dwrite "system:dwrite.lib"

@(private = "file", default_calling_convention = "system")
foreign dwrite {
    DWriteCreateFactory :: proc(type: u32, iid: ^win.IID, factory: ^rawptr) -> win.HRESULT ---
}

@(private = "file") DWRITE_FACTORY_SHARED :: 0

@(private = "file") DWRITE_FONT_STYLE_NORMAL   :: u32(0)
@(private = "file") DWRITE_FONT_STRETCH_NORMAL :: u32(5)

@(private = "file") E_POINTER     :: win.HRESULT(-2147467261)
@(private = "file") E_NOINTERFACE :: win.HRESULT(-2147467262)

// IDWriteFactory2 is the earliest with GetSystemFontFallback (Win 8.1).
@(private = "file")
IID_IDWriteFactory2 := win.IID{0x0439fc60, 0xca44, 0x4994, {0x8d, 0xee, 0x3a, 0x9a, 0xf7, 0xb7, 0x32, 0xec}}

@(private = "file")
IID_IUnknown := win.IID{0x00000000, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
@(private = "file")
IID_IDWriteTextAnalysisSource := win.IID{0x688e1a58, 0x5094, 0x47c8, {0xad, 0xc8, 0xfb, 0xce, 0xa6, 0x0a, 0xe9, 0x2b}}

// Unused slots preserve the COM vtable layout.
@(private = "file")
IDWriteFactory2_VTable :: struct {
    QueryInterface: proc "system" (this: rawptr, iid: ^win.IID, out: ^rawptr) -> win.HRESULT,
    AddRef:         proc "system" (this: rawptr) -> u32,
    Release:        proc "system" (this: rawptr) -> u32,
    _factory:  [21]rawptr, // GetSystemFontCollection..CreateGlyphRunAnalysis
    _factory1: [2]rawptr,  // GetEudcFontCollection, CreateCustomRenderingParams
    GetSystemFontFallback: proc "system" (this: rawptr, out: ^rawptr) -> win.HRESULT,
}

@(private = "file")
IDWriteFontFallback_VTable :: struct {
    QueryInterface: proc "system" (this: rawptr, iid: ^win.IID, out: ^rawptr) -> win.HRESULT,
    AddRef:         proc "system" (this: rawptr) -> u32,
    Release:        proc "system" (this: rawptr) -> u32,
    MapCharacters:  proc "system" (
        this: rawptr,
        source: rawptr,
        text_pos: u32,
        text_len: u32,
        collection: rawptr,
        family: [^]u16,
        weight: u32,
        style: u32,
        stretch: u32,
        mapped_len: ^u32,
        font: ^rawptr,
        scale: ^f32,
    ) -> win.HRESULT,
}

@(private = "file")
IDWriteFont_VTable :: struct {
    QueryInterface: proc "system" (this: rawptr, iid: ^win.IID, out: ^rawptr) -> win.HRESULT,
    AddRef:         proc "system" (this: rawptr) -> u32,
    Release:        proc "system" (this: rawptr) -> u32,
    GetFontFamily:  proc "system" (this: rawptr, out: ^rawptr) -> win.HRESULT,
    _pad:           [9]rawptr, // GetWeight..HasCharacter
    CreateFontFace: proc "system" (this: rawptr, out: ^rawptr) -> win.HRESULT,
}

@(private = "file")
IDWriteFontFace_VTable :: struct {
    QueryInterface: proc "system" (this: rawptr, iid: ^win.IID, out: ^rawptr) -> win.HRESULT,
    AddRef:         proc "system" (this: rawptr) -> u32,
    Release:        proc "system" (this: rawptr) -> u32,
    GetType:        proc "system" (this: rawptr) -> u32,
    GetFiles:       proc "system" (this: rawptr, count: ^u32, files: [^]rawptr) -> win.HRESULT,
    GetIndex:       proc "system" (this: rawptr) -> u32,
}

@(private = "file")
IDWriteFontFile_VTable :: struct {
    QueryInterface:    proc "system" (this: rawptr, iid: ^win.IID, out: ^rawptr) -> win.HRESULT,
    AddRef:            proc "system" (this: rawptr) -> u32,
    Release:           proc "system" (this: rawptr) -> u32,
    GetReferenceKey:   proc "system" (this: rawptr, key: ^rawptr, size: ^u32) -> win.HRESULT,
    GetLoader:         proc "system" (this: rawptr, out: ^rawptr) -> win.HRESULT,
    Analyze:           proc "system" (this: rawptr, supported: ^win.BOOL, file_type: ^u32, face_type: ^u32, faces: ^u32) -> win.HRESULT,
}

@(private = "file")
IID_IDWriteLocalFontFileLoader := win.IID{0xb2d9f3ec, 0xc9fe, 0x4a11, {0xa2, 0xec, 0xd8, 0x62, 0x08, 0xf7, 0xc0, 0xa2}}

@(private = "file")
IDWriteLocalFontFileLoader_VTable :: struct {
    QueryInterface:        proc "system" (this: rawptr, iid: ^win.IID, out: ^rawptr) -> win.HRESULT,
    AddRef:                proc "system" (this: rawptr) -> u32,
    Release:               proc "system" (this: rawptr) -> u32,
    CreateStreamFromKey:   proc "system" (this: rawptr, key: rawptr, size: u32, out: ^rawptr) -> win.HRESULT,
    GetFilePathLengthFromKey: proc "system" (this: rawptr, key: rawptr, size: u32, len: ^u32) -> win.HRESULT,
    GetFilePathFromKey:    proc "system" (this: rawptr, key: rawptr, size: u32, path: [^]u16, path_len: u32) -> win.HRESULT,
}

@(private = "file")
_iid_eq :: proc "system" (a, b: ^win.IID) -> bool {
    return a.Data1 == b.Data1 && a.Data2 == b.Data2 && a.Data3 == b.Data3 && a.Data4 == b.Data4
}

// Provide MapCharacters a single-run UTF-16 source.
@(private = "file")
_Source :: struct {
    vtbl:    ^IDWriteTextAnalysisSource_VTable,
    refs:    u32,
    text:    [^]u16,
    text_n:  u32,
    locale:  [^]u16,
}

@(private = "file")
IDWriteTextAnalysisSource_VTable :: struct {
    QueryInterface:        proc "system" (this: rawptr, iid: ^win.IID, out: ^rawptr) -> win.HRESULT,
    AddRef:                proc "system" (this: rawptr) -> u32,
    Release:               proc "system" (this: rawptr) -> u32,
    GetTextAtPosition:     proc "system" (this: rawptr, pos: u32, text: ^[^]u16, len: ^u32) -> win.HRESULT,
    GetTextBeforePosition: proc "system" (this: rawptr, pos: u32, text: ^[^]u16, len: ^u32) -> win.HRESULT,
    GetParagraphReadingDirection: proc "system" (this: rawptr) -> u32,
    GetLocaleName:         proc "system" (this: rawptr, pos: u32, len: ^u32, locale: ^[^]u16) -> win.HRESULT,
    GetNumberSubstitution: proc "system" (this: rawptr, pos: u32, len: ^u32, sub: ^rawptr) -> win.HRESULT,
}

// Reject unsupported interfaces to prevent invalid vtable calls.
@(private = "file")
_src_query :: proc "system" (this: rawptr, iid: ^win.IID, out: ^rawptr) -> win.HRESULT {
    if out == nil do return E_POINTER
    if !_iid_eq(iid, &IID_IUnknown) && !_iid_eq(iid, &IID_IDWriteTextAnalysisSource) {
        out^ = nil
        return E_NOINTERFACE
    }
    s := cast(^_Source)this
    s.refs += 1
    out^ = this
    return 0
}
// The stack-owned source outlives this call.
@(private = "file")
_src_addref :: proc "system" (this: rawptr) -> u32 {
    s := cast(^_Source)this
    s.refs += 1
    return s.refs
}
@(private = "file")
_src_release :: proc "system" (this: rawptr) -> u32 {
    s := cast(^_Source)this
    if s.refs > 0 do s.refs -= 1
    return s.refs
}
@(private = "file")
_src_text_at :: proc "system" (this: rawptr, pos: u32, text: ^[^]u16, len: ^u32) -> win.HRESULT {
    s := cast(^_Source)this
    if pos >= s.text_n {
        text^, len^ = nil, 0
        return 0
    }
    text^ = s.text[pos:]
    len^ = s.text_n - pos
    return 0
}
@(private = "file")
_src_text_before :: proc "system" (this: rawptr, pos: u32, text: ^[^]u16, len: ^u32) -> win.HRESULT {
    s := cast(^_Source)this
    if pos == 0 || pos > s.text_n {
        text^, len^ = nil, 0
        return 0
    }
    text^ = s.text
    len^ = pos
    return 0
}
@(private = "file")
_src_direction :: proc "system" (this: rawptr) -> u32 { return 0 }
@(private = "file")
_src_locale :: proc "system" (this: rawptr, pos: u32, len: ^u32, locale: ^[^]u16) -> win.HRESULT {
    s := cast(^_Source)this
    len^ = s.text_n - min(pos, s.text_n)
    locale^ = s.locale
    return 0
}
@(private = "file")
_src_number_sub :: proc "system" (this: rawptr, pos: u32, len: ^u32, sub: ^rawptr) -> win.HRESULT {
    s := cast(^_Source)this
    len^ = s.text_n - min(pos, s.text_n)
    sub^ = nil
    return 0
}

@(private = "file")
_source_vtbl := IDWriteTextAnalysisSource_VTable {
    QueryInterface               = _src_query,
    AddRef                       = _src_addref,
    Release                      = _src_release,
    GetTextAtPosition            = _src_text_at,
    GetTextBeforePosition        = _src_text_before,
    GetParagraphReadingDirection = _src_direction,
    GetLocaleName                = _src_locale,
    GetNumberSubstitution        = _src_number_sub,
}

@(private = "file") _factory: rawptr
@(private = "file") _fallback: rawptr
@(private = "file") _init_failed: bool

@(private = "file")
_ensure_fallback :: proc() -> rawptr {
    if _fallback != nil do return _fallback
    if _init_failed do return nil

    if _factory == nil {
        if DWriteCreateFactory(DWRITE_FACTORY_SHARED, &IID_IDWriteFactory2, &_factory) != 0 || _factory == nil {
            _init_failed = true
            return nil
        }
    }
    fv := (cast(^^IDWriteFactory2_VTable)_factory)^
    if fv.GetSystemFontFallback(_factory, &_fallback) != 0 || _fallback == nil {
        _init_failed = true
        _fallback = nil
        return nil
    }
    return _fallback
}

@(private = "package")
_platform_fallback :: proc(set: ^Font_Set, r: rune, script: u32) -> ^Face {
    fb := _ensure_fallback()
    if fb == nil do return nil

    buf: [2]u16
    n := 0
    if r > 0xFFFF {
        v := u32(r) - 0x10000
        buf[0] = u16(0xD800 + (v >> 10))
        buf[1] = u16(0xDC00 + (v & 0x3FF))
        n = 2
    } else {
        buf[0] = u16(r)
        n = 1
    }

    lang := script_language(script)
    if lang == "" do lang = "en-US"
    locale := win.utf8_to_wstring(lang, context.temp_allocator)

    src := _Source {
        vtbl   = &_source_vtbl,
        refs   = 1,
        text   = raw_data(buf[:]),
        text_n = u32(n),
        locale = cast([^]u16)locale,
    }

    mapped: u32
    font: rawptr
    scale: f32
    fv := (cast(^^IDWriteFontFallback_VTable)fb)^
    base_family := win.utf8_to_wstring("Segoe UI", context.temp_allocator)
    hr := fv.MapCharacters(
        fb, &src, 0, u32(n), nil, cast([^]u16)base_family,
        u32(WEIGHT_NORMAL), DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
        &mapped, &font, &scale,
    )
    // Zero-length or nil mappings are normal misses.
    if hr != 0 || font == nil do return nil
    defer (cast(^^IDWriteFont_VTable)font)^.Release(font)

    path, index, ok := _font_file_path(font)
    if !ok do return nil
    defer delete(path)

    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil do return nil
    defer delete(data)

    return set_register(set, data, index)
}

@(private = "file")
_font_file_path :: proc(font: rawptr) -> (path: string, index: int, ok: bool) {
    face: rawptr
    if (cast(^^IDWriteFont_VTable)font)^.CreateFontFace(font, &face) != 0 || face == nil do return
    fav := (cast(^^IDWriteFontFace_VTable)face)^
    defer fav.Release(face)

    index = int(fav.GetIndex(face))

    count: u32 = 1
    file: rawptr
    if fav.GetFiles(face, &count, &file) != 0 || count == 0 || file == nil do return
    flv := (cast(^^IDWriteFontFile_VTable)file)^
    defer flv.Release(file)

    key: rawptr
    key_size: u32
    if flv.GetReferenceKey(file, &key, &key_size) != 0 do return

    loader: rawptr
    if flv.GetLoader(file, &loader) != 0 || loader == nil do return
    lv := (cast(^^IDWriteLocalFontFileLoader_VTable)loader)^
    defer lv.Release(loader)

    // Custom loaders may not expose a local path.
    local: rawptr
    if lv.QueryInterface(loader, &IID_IDWriteLocalFontFileLoader, &local) != 0 || local == nil do return
    llv := (cast(^^IDWriteLocalFontFileLoader_VTable)local)^
    defer llv.Release(local)

    n: u32
    if llv.GetFilePathLengthFromKey(local, key, key_size, &n) != 0 do return

    w := make([]u16, n + 1, context.temp_allocator)
    if llv.GetFilePathFromKey(local, key, key_size, raw_data(w), n + 1) != 0 do return

    p, cerr := win.utf16_to_utf8(w[:n], context.allocator)
    if cerr != nil do return
    return p, index, true
}
