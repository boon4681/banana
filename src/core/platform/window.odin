package platform

import "base:runtime"
import "core:c"
import "src:core/node"
import "src:core/painter"
import "src:core/input"
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

// Context holder for platform; similar to application context
Window :: struct {
    platform_state: []u8,
    renderer_state: []u8,
    painter_state:  []u8,
    painter:        painter.Painter,
    images:         [dynamic]^render.Image,
    allocator:      runtime.Allocator,
    root:           ^node.Node,
    width:          int,
    height:         int,
    scale:          f32,
    awaken:         bool,
    // Application-owned callback context. Window never frees this pointer.
    state:      rawptr,
    on_refresh: proc(w: ^Window),
    input:      input.Input_State,
    queue:      [dynamic]EVENT,
}

New :: proc(opts: Init_Options = DEFAULT_OPTIONS) -> ^Window {
    w := new(Window)
    w.allocator = context.allocator
    w.width = opts.width
    w.height = opts.height
    w.scale = 1
    w.queue = make([dynamic]EVENT)
    w.images = make([dynamic]^render.Image, w.allocator)

    w.platform_state = make([]u8, PLATFORM.state_size())
    PLATFORM.set_active_state(&w.platform_state[0])
    glue := PLATFORM.init(&w.platform_state[0], opts, context.allocator)

    w.renderer_state = make([]u8, render.RENDERER.state_size())
    render.RENDERER.set_active_state(&w.renderer_state[0])
    render.RENDERER.init(
		&w.renderer_state[0],
        glue,
        opts.width,
        opts.height,
		{vsync = opts.vsync, msaa_samples = max(opts.msaa_samples, 1)},
		context.allocator,
    )

    painter_state_size := painter.state_size()
    if painter_state_size > 0 {
        w.painter_state = make([]u8, painter_state_size)
    }
    w.painter = painter.Painter{state = raw_data(w.painter_state)}
    painter.init(w.painter, context.allocator)

    w.scale = PLATFORM.content_scale()

    w.root = node.New()
    input.init(&w.input, w.root)
    input.set_clipboard_procs({get = PLATFORM.clipboard_get, set = PLATFORM.clipboard_set})
    PLATFORM.set_window_user_ptr(&w.platform_state[0], cast(rawptr)(w))
    return w
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

load_image_frames :: proc(w: ^Window, encoded: []u8) -> (frames: []Image_Frame, err: Image_Error) {
    if w == nil do return nil, .Decode_Failed
    if len(encoded) == 0 do return nil, .Empty_Input
    if len(encoded) > int(max(c.int)) do return nil, .Input_Too_Large

    // stb only animates GIF; anything else decodes as a lone frame.
    if !_is_gif(encoded) {
        image := load_image_from_bytes(w, encoded) or_return
        single, alloc_err := make([]Image_Frame, 1, w.allocator)
        if alloc_err != nil {
            free_image(w, image)
            return nil, .Allocation_Failed
        }
        single[0] = {image = image, delay = 0}
        return single, .None
    }

    delays: [^]c.int
    x, y, z, source_channels: c.int
    decoded := stbi.load_gif_from_memory(
        raw_data(encoded),
        c.int(len(encoded)),
        &delays,
        &x,
        &y,
        &z,
        &source_channels,
        4,
    )
    if decoded == nil do return nil, .Decode_Failed
    defer stbi.image_free(decoded)
    defer if delays != nil do stbi.image_free(delays)

    width, height, count := int(x), int(y), int(z)
    if width <= 0 || height <= 0 || count <= 0 do return nil, .Invalid_Dimensions
    if width > max(int) / height / 4 do return nil, .Invalid_Dimensions
    frame_bytes := width * height * 4
    if count > max(int) / frame_bytes do return nil, .Invalid_Dimensions

    out, alloc_err := make([]Image_Frame, count, w.allocator)
    if alloc_err != nil do return nil, .Allocation_Failed

    for i in 0 ..< count {
        pixels, pix_err := make([]u8, frame_bytes, w.allocator)
        if pix_err != nil {
            for j in 0 ..< i do free_image(w, out[j].image)
            delete(out, w.allocator)
            return nil, .Allocation_Failed
        }
        copy(pixels, decoded[i * frame_bytes:][:frame_bytes])

        image := new(render.Image, w.allocator)
        image^ = render.Image {
            data   = pixels,
            w      = u32(width),
            h      = u32(height),
            format = .RGBA8,
        }
        append(&w.images, image)

        ms := c.int(0)
        if delays != nil do ms = delays[i]
        if ms <= 10 do ms = 100
        out[i] = {
            image = image,
            delay = f32(ms) / 1000
        }
    }
    return out, .None
}

@(private="file")
_is_gif :: proc(encoded: []u8) -> bool {
    return len(encoded) >= 6 &&
        encoded[0] == 'G' && encoded[1] == 'I' && encoded[2] == 'F' &&
        encoded[3] == '8' && (encoded[4] == '7' || encoded[4] == '9') && encoded[5] == 'a'
}

// Releases frames returned by load_image_frames, including the slice itself.
free_image_frames :: proc(w: ^Window, frames: []Image_Frame) {
    if w == nil || frames == nil do return
    for f in frames do free_image(w, f.image)
    delete(frames, w.allocator)
}

// Releases one image owned by this window. The window is made current before
// releasing a resident GPU texture.
free_image :: proc(w: ^Window, image: ^render.Image) -> bool {
    if w == nil || image == nil do return false
    for owned, i in w.images {
        if owned != image do continue
        make_current(w)
        _free_image(image, w.allocator)
        unordered_remove(&w.images, i)
        return true
    }
    return false
}

@(private="file")
_free_image :: proc(image: ^render.Image, allocator: runtime.Allocator) {
    if image == nil do return
    if image.texture != render.INVALID_TEXTURE {
        render.RENDERER.unload_image(image)
    }
    delete(image.data, allocator)
    runtime.mem_free(image, allocator)
}

@(private)
_push_event :: proc(w: ^Window, ev: EVENT) {
    if w != nil do append(&w.queue, ev)
}

handle :: proc(w: ^Window, ev: EVENT) {
    #partial switch e in ev {
    case MOUSE_MOVED:
        input.on_mouse_move(&w.input, e.x, e.y)
    case MOUSE_BUTTON:
        if e.action == PRESS {
            input.on_mouse_down(&w.input, e.button, e.mods)
        } else if e.action == RELEASE {
            input.on_mouse_up(&w.input, e.button)
        }
    case MOUSE_WHEEL:
        input.on_wheel(&w.input, e.dx, e.dy)
    case KEY:
        if e.action == PRESS || e.action == REPEAT {
            input.on_key_down(&w.input, e.code, e.key, e.mods, e.action == REPEAT)
        } else if e.action == RELEASE {
            input.on_key_up(&w.input, e.code, e.key, e.mods)
        }
    case TYPED:
        input.on_text(&w.input, e.codepoint)
    }
}

update :: proc(w: ^Window) -> bool {
    make_current(w)
    if PLATFORM.should_close() do return false
    PLATFORM.poll_events()
    sync_size(w)
    input.set_context(&w.input)
    for ev in w.queue do handle(w, ev)
    clear(&w.queue)
    return true
}

make_current :: proc(w: ^Window) {
    PLATFORM.set_active_state(&w.platform_state[0])
    render.RENDERER.set_active_state(&w.renderer_state[0])
    render.RENDERER.make_current()
}

@(private="file")
sync_size :: proc(w: ^Window) {
    nw, nh := PLATFORM.poll_size()
    if nw != w.width || nh != w.height {
        w.width = nw
        w.height = nh
        render.RENDERER.resize(nw, nh)
    }
    w.scale = PLATFORM.content_scale()
}

// Called by the platform during window resize
refresh :: proc(w: ^Window) {
    make_current(w)
    sync_size(w)
    if w.on_refresh != nil do w.on_refresh(w)
}

close :: proc(w: ^Window) {
    PLATFORM.set_active_state(&w.platform_state[0])
    PLATFORM.request_close()
}

set_title :: proc(w: ^Window, title: string) {
    if w == nil do return
    PLATFORM.set_active_state(&w.platform_state[0])
    PLATFORM.set_title(title)
}

free :: proc(w: ^Window) {
    if w == nil do return
    make_current(w)
    painter.shutdown(w.painter)
    for image in w.images do _free_image(image, w.allocator)
    clear(&w.images)
    render.RENDERER.shutdown()
    PLATFORM.set_active_state(&w.platform_state[0])
    PLATFORM.shutdown()
    delete(w.queue)
    delete(w.images)
    delete(w.platform_state)
    delete(w.renderer_state)
    delete(w.painter_state)
    if w.root != nil do w.root->free()
    runtime.mem_free(w)
}
