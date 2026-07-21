package msdfgen
import "core:c"
when ODIN_ARCH == .wasm32 {
    foreign import msdf "./libc/wasm/msdfgen.o"
} else when ODIN_OS == .Windows {
    foreign import msdf "./libc/windows/msdfgen.lib"
} else when ODIN_OS == .Darwin {
    foreign import msdf "./libc/macos/libmsdfgen.a"
} else {
    foreign import msdf "./libc/linux/libmsdfgen.a"
}
@(default_calling_convention = "c")
foreign msdf {
    @(link_name = "banana_msdf_generate")
    generate :: proc(curve_points: ^f32, curve_count: c.int, contour_ends: ^u32,
        contour_count: c.int, width, height: c.int, scale, translate_x,
        translate_y, pixel_range: f64, rgba: ^u8) -> bool ---
}
