package render

Init_Options :: struct {
    vsync:        bool,
    msaa_samples: u32,
    transparent:  bool,
    retained:     bool, // draw into a target that keep its pixels, so a frame can redraw only part of the window
}

// how the renderer talk to the platform window, see src/platform
Render_Interface :: struct {
    state:            rawptr,
    make_context:     proc(state: rawptr, opts: Init_Options) -> bool,
    make_current:     proc(state: rawptr), // rebind this window's context on the thread for multi-window, can be nil on apis with no context state like D3D11 or Metal
    present:          proc(state: rawptr),
    resize:           proc(state: rawptr, w, h: i32),
    destroy:          proc(state: rawptr),
    get_proc_address: proc(state: rawptr, name: cstring) -> rawptr,
    // the OS window (an HWND on Windows), for backends that present to it themselves
    native_window:    proc(state: rawptr) -> rawptr,
}

// image pixels kept in RAM, with a GPU texture made from them when first needed
// the GPU copy can be uploaded and unloaded without touching data
Image :: struct {
    texture: Texture,
    data:    []u8,
    w:       u32,
    h:       u32,
    format:  Pixel_Format,
}

// a texture you can draw into, or the screen
Render_Target :: struct {
    idx:       Texture,
    w:         u32,
    h:         u32,
    is_screen: bool // the window's default framebuffer
}

// handle to a backend texture, 0 is invalid
Texture               :: distinct u32

Pixel_Format          :: enum { RGBA8, BGRA8, R8, A8 }
Blend_Mode            :: enum { Opaque, Alpha, Additive, Premultiplied }
Texture_Filter        :: enum { Nearest, Linear }

INVALID_TEXTURE       :: Texture{}
INVALID_RENDER_TARGET :: Render_Target{}

pixel_size :: proc(format: Pixel_Format) -> int {
    switch format {
    case .RGBA8, .BGRA8: return 4
    case .R8, .A8:       return 1
    }
    return 0
}
