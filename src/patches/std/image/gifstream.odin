package gifstream

import "core:c"

when ODIN_ARCH == .wasm32 {
    foreign import gifstream "./libc/wasm/gifstream.o"
} else when ODIN_OS == .Windows {
    foreign import gifstream "./libc/windows/gifstream.lib"
} else when ODIN_OS == .Darwin {
    foreign import gifstream "./libc/macos/libgifstream.a"
} else {
    foreign import gifstream "./libc/linux/libgifstream.a"
}

Stream :: struct {}

@(default_calling_convention = "c", link_prefix = "banana_gif_")
foreign gifstream {
    // counts frames and collects delays (ms) without decoding.
    // return the frame count, or -1 if the data is a weird GIF.
    scan :: proc(data: [^]byte, len: c.int, delays_ms: [^]c.int, max_delays: c.int) -> c.int ---
    // return data, data must outlive the stream.
    open :: proc(data: [^]byte, len: c.int, w, h: ^c.int) -> ^Stream ---
    // writes one RGBA8 frame into dst, which must hold w*h*4 bytes.
    // return 1 on a decoded frame, 0 at end of animation, -1 on error.
    next :: proc(stream: ^Stream, dst: [^]byte, dst_bytes: c.size_t, delay_ms: ^c.int) -> c.int ---
    close :: proc(stream: ^Stream) ---
}
