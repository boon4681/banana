package webp

import "core:c"

when ODIN_ARCH == .wasm32 {
    foreign import webp "./libc/wasm/webp.o"
} else when ODIN_OS == .Windows {
    foreign import webp "./libc/windows/webp.lib"
} else when ODIN_OS == .Darwin {
    foreign import webp "./libc/macos/libwebp.a"
} else {
    foreign import webp "./libc/linux/libwebp.a"
}

Stream :: struct {}

@(default_calling_convention = "c", link_prefix = "banana_webp_")
foreign webp {
    is_webp :: proc(data: [^]byte, len: c.int) -> c.int ---
    // counts frames and collects delays (ms) without decoding.
    // return the frame count, or -1 if the data is not a WebP.
    scan :: proc(data: [^]byte, len: c.int, delays_ms: [^]c.int, max_delays: c.int) -> c.int ---
    // decodes a still image as RGBA8 into dst; a nil dst only reports w and h.
    // return 1 on success, -1 on error or short buffer.
    decode :: proc(data: [^]byte, len: c.int, dst: [^]byte, dst_bytes: c.size_t, w, h: ^c.int) -> c.int ---
    // return nil on failure, data must outlive the stream.
    open :: proc(data: [^]byte, len: c.int, w, h: ^c.int) -> ^Stream ---
    // writes one composited RGBA8 frame into dst, which must hold w*h*4 bytes.
    // return 1 on a decoded frame, 0 at end of animation, -1 on error.
    next :: proc(stream: ^Stream, dst: [^]byte, dst_bytes: c.size_t, delay_ms: ^c.int) -> c.int ---
    rewind :: proc(stream: ^Stream) ---
    close :: proc(stream: ^Stream) ---
}
