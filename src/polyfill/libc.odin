#+build wasm32
package polyfill

import "core:c"
import "base:intrinsics"

@(require) import odin_libc "vendor:libc-shim"

@(export, link_name = "calloc")
shim_calloc :: proc "c" (n, size: c.size_t) -> rawptr {
	total := n * size
	if size != 0 && total / size != n do return nil
	p := odin_libc.malloc(uint(total))
	if p != nil do intrinsics.mem_zero_volatile(p, int(total))
	return p
}

@(export, link_name = "snprintf")
shim_snprintf :: proc "c" (buf: [^]u8, n: c.size_t, fmt: cstring, #c_vararg args: ..any) -> c.int {
	if buf != nil && n > 0 do buf[0] = 0
	return 0
}

@(export, link_name = "vprintf")
shim_vprintf :: proc "c" (fmt: cstring, args: rawptr) -> c.int {
	return 0
}

@(export, link_name = "fputc")
shim_fputc :: proc "c" (ch: c.int, stream: rawptr) -> c.int {
	return ch
}

@(export, link_name = "getenv")
shim_getenv :: proc "c" (name: cstring) -> cstring {
	return nil
}

@(export, link_name = "hypotf")
shim_hypotf :: proc "c" (x, y: f32) -> f32 {
	return intrinsics.sqrt(x*x + y*y)
}

@(export, link_name = "wmemchr")
shim_wmemchr :: proc "c" (s: [^]c.wchar_t, ch: c.wchar_t, n: c.size_t) -> [^]c.wchar_t {
	for i in 0 ..< n {
		if s[i] == ch do return s[i:]
	}
	return nil
}
