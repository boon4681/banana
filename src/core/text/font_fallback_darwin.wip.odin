// =====================================================
// UNTESTED CODE NOT SURE IF IT WORK OR NOT
// REQUIRE FURTHER TESTING
// =====================================================
#+build darwin
package text

import "core:c"
import "core:os"
import "core:strings"
import "core:unicode/utf8"

foreign import cf "system:CoreFoundation.framework"
foreign import ct "system:CoreText.framework"

CFRef :: distinct rawptr
CFIndex :: c.long

CFRange :: struct {
    location: CFIndex,
    length:   CFIndex,
}

kCFStringEncodingUTF8 :: u32(0x08000100)

@(default_calling_convention = "c")
foreign cf {
    CFRelease :: proc(ref: CFRef) ---
    CFStringCreateWithBytes :: proc(alloc: CFRef, bytes: [^]u8, len: CFIndex, enc: u32, bom: b8) -> CFRef ---
    CFStringGetLength :: proc(s: CFRef) -> CFIndex ---
    CFStringGetCString :: proc(s: CFRef, buf: [^]u8, size: CFIndex, enc: u32) -> b8 ---
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
    n := CFStringGetLength(s) * 4 + 1
    buf := make([]u8, int(n), context.temp_allocator)
    if !CFStringGetCString(s, raw_data(buf), n, kCFStringEncodingUTF8) do return ""
    return strings.clone(string(cstring(raw_data(buf))), allocator)
}

@(private = "package")
_platform_fallback :: proc(set: ^Font_Set, r: rune, script: u32) -> ^Face {
    b, n := utf8.encode_rune(r)
    str := CFStringCreateWithBytes(nil, raw_data(b[:]), CFIndex(n), kCFStringEncodingUTF8, false)
    if str == nil do return nil
    defer CFRelease(str)

    // The system resolves missing characters away from this base font.
    base_name := _cfstr("Helvetica")
    defer CFRelease(base_name)
    base := CTFontCreateWithName(base_name, 12, nil)
    if base == nil do return nil
    defer CFRelease(base)

    font := CTFontCreateForString(base, str, CFRange{0, CFStringGetLength(str)})
    if font == nil do return nil
    defer CFRelease(font)

    url := CTFontCopyAttribute(font, kCTFontURLAttribute)
    if url == nil do return nil
    defer CFRelease(url)

    pbuf: [1024]u8
    if !CFURLGetFileSystemRepresentation(url, true, raw_data(pbuf[:]), CFIndex(len(pbuf))) do return nil
    path := string(cstring(raw_data(pbuf[:])))

    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil do return nil
    defer delete(data)

    fam_ref := CTFontCopyFamilyName(font)
    fam := _gostr(fam_ref, context.temp_allocator)
    if fam_ref != nil do CFRelease(fam_ref)

    return set_register(set, data, 0, fam)
}
