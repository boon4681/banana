package lunasvg
import "core:c"

when ODIN_ARCH == .wasm32 {
    foreign import luna "./libc/wasm/lunasvg.o"
} else when ODIN_OS == .Windows {
    foreign import luna "./libc/windows/lunasvg.lib"
} else when ODIN_OS == .Darwin {
    foreign import luna "./libc/macos/liblunasvg.a"
} else {
    foreign import luna "./libc/linux/liblunasvg.a"
}

@(default_calling_convention = "c", link_prefix = "banana_svg_")
foreign luna {
    parse   :: proc(data: rawptr, length: c.size_t) -> rawptr ---
    destroy :: proc(handle: rawptr) ---
    size    :: proc(handle: rawptr, width, height: ^f32) -> bool ---
    render  :: proc(handle: rawptr, pixels: ^u8, width, height, stride: c.int,scale_x, scale_y: f32) -> bool ---
}
