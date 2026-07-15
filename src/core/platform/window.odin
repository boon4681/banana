package platform

import "base:runtime"
import "core:c"
import "core:os"
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
		&w.renderer_state[0], glue, opts.width, opts.height,
		{vsync = opts.vsync, msaa_samples = 1},
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

// Loads an image from a filesystem path into window-owned RAM.
// On targets without filesystem access, use load_image_from_bytes with fetched data.
load_image :: proc(w: ^Window, path: string) -> (image: ^render.Image, err: Image_Error) {
    if w == nil do return nil, .File_Read_Failed
    encoded, read_err := os.read_entire_file(path, w.allocator)
    if read_err != nil do return nil, .File_Read_Failed
    defer delete(encoded, w.allocator)
    return load_image_from_bytes(w, encoded)
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
