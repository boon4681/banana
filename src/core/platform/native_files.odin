#+build !js
package platform

import "core:c"
import "core:os"
import "core:strings"
import "src:core/render"
import stbi "vendor:stb/image"

// Loads an image from a filesystem path.
load_image :: proc(w: ^Window, path: string) -> (image: ^render.Image, err: Image_Error) {
    if w == nil {
        return nil, .File_Read_Failed
    }
    encoded, read_err := os.read_entire_file(path, w.allocator)
    if read_err != nil {
        return nil, .File_Read_Failed
    }
    defer delete(encoded, w.allocator)
    return load_image_from_bytes(w, encoded)
}

// Saves the presented frame as a PNG.
capture :: proc(w: ^Window, path: string) -> bool {
    if w == nil {
        return false
    }
    make_current(w)
    data, width, height := render.RENDERER.read_pixels(render.INVALID_RENDER_TARGET, context.temp_allocator)
    if len(data) == 0 || width <= 0 || height <= 0 {
        return false
    }
    cpath := strings.clone_to_cstring(path, context.temp_allocator)
    return stbi.write_png(cpath, c.int(width), c.int(height), 4, raw_data(data), c.int(width * 4)) != 0
}
