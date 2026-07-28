// =====================================================
// UNTESTED CODE NOT SURE IF IT WORK OR NOT
// REQUIRE FURTHER TESTING
// =====================================================
#+build linux
package text

import "core:c"
import "core:os"
import "core:strings"


foreign import fc "system:fontconfig"

FcConfig :: distinct rawptr
FcPattern :: distinct rawptr
FcCharSet :: distinct rawptr
FcResult :: distinct c.int

FC_MATCH_PATTERN :: c.int(0)
FC_RESULT_MATCH :: FcResult(0)

FC_FAMILY :: "family"
FC_FILE   :: "file"
FC_INDEX  :: "index"
FC_LANG   :: "lang"
FC_CHARSET :: "charset"

@(default_calling_convention = "c")
foreign fc {
    FcInit :: proc() -> c.int ---
    FcInitLoadConfigAndFonts :: proc() -> FcConfig ---
    FcPatternCreate :: proc() -> FcPattern ---
    FcPatternDestroy :: proc(p: FcPattern) ---
    FcPatternAddCharSet :: proc(p: FcPattern, obj: cstring, cs: FcCharSet) -> c.int ---
    FcPatternAddString :: proc(p: FcPattern, obj: cstring, s: cstring) -> c.int ---
    FcPatternGetString :: proc(p: FcPattern, obj: cstring, n: c.int, out: ^cstring) -> FcResult ---
    FcPatternGetInteger :: proc(p: FcPattern, obj: cstring, n: c.int, out: ^c.int) -> FcResult ---
    FcCharSetCreate :: proc() -> FcCharSet ---
    FcCharSetDestroy :: proc(cs: FcCharSet) ---
    FcCharSetAddChar :: proc(cs: FcCharSet, ch: u32) -> c.int ---
    FcConfigSubstitute :: proc(cfg: FcConfig, p: FcPattern, kind: c.int) -> c.int ---
    FcDefaultSubstitute :: proc(p: FcPattern) ---
    FcFontMatch :: proc(cfg: FcConfig, p: FcPattern, res: ^FcResult) -> FcPattern ---
}

@(private = "file") _cfg: FcConfig
@(private = "file") _init_failed: bool

@(private = "file")
_ensure_config :: proc() -> bool {
    if _cfg != nil do return true
    if _init_failed do return false
    if FcInit() == 0 {
        _init_failed = true
        return false
    }
    _cfg = FcInitLoadConfigAndFonts()
    if _cfg == nil {
        _init_failed = true
        return false
    }
    return true
}

@(private = "package")
_platform_fallback :: proc(set: ^Font_Set, r: rune, script: u32) -> ^Face {
    if !_ensure_config() do return nil

    pat := FcPatternCreate()
    if pat == nil do return nil
    defer FcPatternDestroy(pat)

    cs := FcCharSetCreate()
    if cs == nil do return nil
    defer FcCharSetDestroy(cs)
    FcCharSetAddChar(cs, u32(r))
    FcPatternAddCharSet(pat, FC_CHARSET, cs)

    // Language disambiguates unified Han.
    if lang := script_language(script); lang != "" {
        clang := strings.clone_to_cstring(lang, context.temp_allocator)
        FcPatternAddString(pat, FC_LANG, clang)
    }

    FcConfigSubstitute(_cfg, pat, FC_MATCH_PATTERN)
    FcDefaultSubstitute(pat)

    res: FcResult
    m := FcFontMatch(_cfg, pat, &res)
    if m == nil do return nil
    defer FcPatternDestroy(m)
    if res != FC_RESULT_MATCH do return nil

    cfile: cstring
    if FcPatternGetString(m, FC_FILE, 0, &cfile) != FC_RESULT_MATCH do return nil

    index: c.int
    if FcPatternGetInteger(m, FC_INDEX, 0, &index) != FC_RESULT_MATCH do index = 0

    data, err := os.read_entire_file_from_path(string(cfile), context.allocator)
    if err != nil do return nil
    defer delete(data)

    family: string
    cfam: cstring
    if FcPatternGetString(m, FC_FAMILY, 0, &cfam) == FC_RESULT_MATCH {
        family = string(cfam)
    }

    return set_register(set, data, int(index), family)
}
