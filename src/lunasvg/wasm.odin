#+build wasm32
package lunasvg

import "base:intrinsics"
import "core:c"

@(require) import _ "src:polyfill"

@(export, link_name = "setjmp")
shim_setjmp :: proc "c" (env: [^]c.int) -> c.int {
    if env == nil do return 0
    pending := env[0]
    env[0] = 0
    return pending
}

@(export, link_name = "longjmp")
shim_longjmp :: proc "c" (env: [^]c.int, value: c.int) {
    if env == nil do return
    env[0] = value != 0 ? value : 1
}

@(export, link_name = "lroundf")
shim_lroundf :: proc "c" (x: f32) -> c.long {
    return c.long(x + (x < 0 ? -0.5 : 0.5))
}

@(export, link_name = "hypot")
shim_hypot :: proc "c" (x, y: f64) -> f64 {
    return intrinsics.sqrt(x * x + y * y)
}

@(export, link_name = "isxdigit")
shim_isxdigit :: proc "c" (v: c.int) -> c.int {
    ok := (v >= '0' && v <= '9') || (v >= 'a' && v <= 'f') || (v >= 'A' && v <= 'F')
    return ok ? 1 : 0
}

@(export, link_name = "tolower")
shim_tolower :: proc "c" (ch: c.int) -> c.int {
    return ch >= 'A' && ch <= 'Z' ? ch + 32 : ch
}

@(export, link_name = "bsearch")
shim_bsearch :: proc "c" (
	key: rawptr,
	base: rawptr,
	count, size: c.size_t,
	compare: proc "c" (a, b: rawptr) -> c.int,
) -> rawptr {
    if base == nil || compare == nil || count == 0 || size == 0 do return nil
    lo, hi := c.size_t(0), count
    for lo < hi {
        mid := lo + (hi - lo) / 2
        elem := rawptr(uintptr(base) + uintptr(mid * size))
        order := compare(key, elem)
        switch {
        case order == 0:
            return elem
        case order < 0:
            hi = mid
        case:
            lo = mid + 1
        }
    }
    return nil
}

@(export, link_name = "__cxa_atexit")
shim_cxa_atexit :: proc "c" (destructor, object, dso: rawptr) -> c.int {
    return 0
}

@(export, link_name = "fgetc")
shim_fgetc :: proc "c" (stream: rawptr) -> c.int {
    return -1
}

@(export, link_name = "ungetc")
shim_ungetc :: proc "c" (ch: c.int, stream: rawptr) -> c.int {
    return -1
}

@(export, link_name = "feof")
shim_feof :: proc "c" (stream: rawptr) -> c.int {
    return 1
}

@(export, link_name = "ferror")
shim_ferror :: proc "c" (stream: rawptr) -> c.int {
    return 0
}
