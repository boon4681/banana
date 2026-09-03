package platform

import "base:runtime"
import "core:c"
import "src:core/render"
import stbi "vendor:stb/image"

Image_Error :: enum {
    None,
    Empty_Input,
    Input_Too_Large,
    File_Read_Failed,
    Decode_Failed,
    Invalid_Dimensions,
    Allocation_Failed,
}

Image_Frame :: struct {
    image: ^render.Image,
    delay: f32, // seconds to hold this frame
}

// Decoder used by file loading, browser fetches, and embedded assets. STB always expands the result to RGBA8.
load_image_from_bytes :: proc(w: ^Window, encoded: []u8) -> (image: ^render.Image, err: Image_Error) {
    if w == nil do return nil, .Decode_Failed
    if len(encoded) == 0 do return nil, .Empty_Input
    if len(encoded) > int(max(c.int)) do return nil, .Input_Too_Large

    x, y, source_channels: c.int
    decoded := stbi.load_from_memory(
        raw_data(encoded),
        c.int(len(encoded)),
        &x,
        &y,
        &source_channels,
        4,
    )
    if decoded == nil do return nil, .Decode_Failed
    defer stbi.image_free(decoded)

    width, height := int(x), int(y)
    if width <= 0 || height <= 0 do return nil, .Invalid_Dimensions
    if width > max(int) / height / 4 do return nil, .Invalid_Dimensions

    byte_count := width * height * 4
    pixels, alloc_err := make([]u8, byte_count, w.allocator)
    if alloc_err != nil do return nil, .Allocation_Failed
    copy(pixels, decoded[:byte_count])

    image = new(render.Image, w.allocator)
    image^ = render.Image {
        data   = pixels,
        w      = u32(width),
        h      = u32(height),
        format = .RGBA8,
    }
    append(&w.images, image)
    return image, .None
}

// Releases GPU texture, keeping its CPU pixels.
// Used when frame contents are overwritten in place and must be re-uploaded.
free_image_texture :: proc(w: ^Window, image: ^render.Image) {
    if w == nil || image == nil do return
    if image.texture == render.INVALID_TEXTURE do return
    prev := scoped_current(w)
    defer restore_current(prev)
    render.RENDERER.unload_image(image)
}

// Releases one image owned by this window.
// The window is made current before releasing a resident GPU texture.
free_image :: proc(w: ^Window, image: ^render.Image) -> bool {
    if w == nil || image == nil do return false
    for owned, i in w.images {
        if owned != image do continue
        prev := scoped_current(w)
        defer restore_current(prev)
        _free_image(image, w.allocator)
        unordered_remove(&w.images, i)
        return true
    }
    return false
}

@(private)
_free_image :: proc(image: ^render.Image, allocator: runtime.Allocator) {
    if image == nil do return
    if image.texture != render.INVALID_TEXTURE {
        render.RENDERER.unload_image(image)
    }
    delete(image.data, allocator)
    runtime.mem_free(image, allocator)
}
