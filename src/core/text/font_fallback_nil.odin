#+build js, freebsd, openbsd, netbsd
package text

@(private)
_platform_fallback :: proc(set: ^Font_Set, r: rune, script: u32) -> ^Face {
    return nil
}
