#+build wasm32
package lunasvg

import "base:intrinsics"
import "core:c"

@(require) import _ "src:polyfill"

// WebAssembly SjLj.
// The LLVM pass replaces setjmp/longjmp calls with these ABI helpers;
// the actual throw is emitted by libc/shim/wasm_sjlj.c because Odin has no wasm.throw.
@(private = "file")
Wasm_Longjmp_Args :: struct {
	env: rawptr,
	value: c.int,
}

@(private = "file")
Wasm_Jmp_Buf :: struct {
	function_invocation_id: rawptr,
	label:                  u32,
	args:                   Wasm_Longjmp_Args,
}

@(export, link_name = "__wasm_setjmp")
shim_wasm_setjmp :: proc "c" (env: rawptr, label: u32, function_invocation_id: rawptr) {
	if env == nil || label == 0 || function_invocation_id == nil do return
	buf := cast(^Wasm_Jmp_Buf)(env)
	buf.function_invocation_id = function_invocation_id
	buf.label = label
}

@(export, link_name = "__wasm_setjmp_test")
shim_wasm_setjmp_test :: proc "c" (env, function_invocation_id: rawptr) -> u32 {
	if env == nil || function_invocation_id == nil do return 0
	buf := cast(^Wasm_Jmp_Buf)(env)
	if buf.label == 0 do return 0
	return buf.function_invocation_id == function_invocation_id ? buf.label : 0
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

@(export, link_name = "wcslen")
shim_wcslen :: proc "c" (text: [^]c.wchar_t) -> c.size_t {
    if text == nil do return 0
    count: c.size_t
    for text[count] != 0 do count += 1
    return count
}
