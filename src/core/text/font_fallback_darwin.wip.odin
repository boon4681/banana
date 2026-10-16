// =====================================================
// UNTESTED CODE NOT SURE IF IT WORK OR NOT
// REQUIRE FURTHER TESTING
// =====================================================
#+build darwin
package text

import "core:os"
import "core:unicode/utf8"
import CF "core:sys/darwin/CoreFoundation"

foreign import cf "system:CoreFoundation.framework"
foreign import ct "system:CoreText.framework"

CFRef   :: CF.TypeRef
CFIndex :: CF.Index
CFRange :: CF.Range

kCFStringEncodingUTF8 :: u32(0x08000100)

@(default_calling_convention = "c")
foreign cf {
    CFStringCreateWithBytes :: proc(alloc: CFRef, bytes: [^]u8, len: CFIndex, enc: u32, bom: b8) -> CFRef ---
    CFURLGetFileSystemRepresentation :: proc(url: CFRef, resolve: b8, buf: [^]u8, size: CFIndex) -> b8 ---
    CFDictionaryCreate :: proc(alloc: CFRef, keys: [^]rawptr, vals: [^]rawptr, n: CFIndex, kcb: rawptr, vcb: rawptr) -> CFRef ---
}

@(default_calling_convention = "c")
foreign ct {
    CTFontCreateWithName :: proc(name: CFRef, size: f64, mtx: rawptr) -> CFRef ---
    CTFontCreateForString :: proc(font: CFRef, str: CFRef, range: CFRange) -> CFRef ---
    CTFontCopyAttribute :: proc(font: CFRef, attr: CFRef) -> CFRef ---
    CTFontCopyFamilyName :: proc(font: CFRef) -> CFRef ---
    kCTFontURLAttribute: CFRef
}

@(private = "file")
_cfstr :: proc(s: string) -> CFRef {
    return CFStringCreateWithBytes(nil, raw_data(s), CFIndex(len(s)), kCFStringEncodingUTF8, false)
}

@(private = "file")
_gostr :: proc(s: CFRef, allocator := context.allocator) -> string {
    if s == nil do return ""
    return CF.StringCopyToOdinString(CF.String(s), allocator)
}

@(private)
_platform_fallback :: proc(set: ^Font_Set, r: rune, script: u32) -> ^Face {
    b, n := utf8.encode_rune(r)
    str := CFStringCreateWithBytes(nil, raw_data(b[:]), CFIndex(n), kCFStringEncodingUTF8, false)
    if str == nil do return nil
    defer CF.CFRelease(str)

    // The system resolves missing characters away from this base font.
    base_name := _cfstr("Helvetica")
    defer CF.CFRelease(base_name)
    base := CTFontCreateWithName(base_name, 12, nil)
    if base == nil do return nil
    defer CF.CFRelease(base)

    font := CTFontCreateForString(base, str, CFRange{0, CF.StringGetLength(CF.String(str))})
    if font == nil do return nil
    defer CF.CFRelease(font)

    url := CTFontCopyAttribute(font, kCTFontURLAttribute)
    if url == nil do return nil
    defer CF.CFRelease(url)

    pbuf: [1024]u8
    if !CFURLGetFileSystemRepresentation(url, true, raw_data(pbuf[:]), CFIndex(len(pbuf))) do return nil
    path := string(cstring(raw_data(pbuf[:])))

    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil do return nil
    defer delete(data)

    fam_ref := CTFontCopyFamilyName(font)
    fam := _gostr(fam_ref, context.temp_allocator)
    if fam_ref != nil do CF.CFRelease(fam_ref)

    return set_register(set, data, 0, fam)
}
