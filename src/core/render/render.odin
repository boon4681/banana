package render

Init_Options :: struct {
    vsync:        bool,
    msaa_samples: u32,
}

// Unify api for renderer to interact with platform state; see src/platform
Render_Interface :: struct {
    state:            rawptr,
    make_context:     proc(state: rawptr, opts: Init_Options) -> bool,
    make_current:     proc(state: rawptr), // Re-binds this window's context on the thread (multi-window). May be nil on APIs without context state (D3D11/Metal).
    present:          proc(state: rawptr),
    resize:           proc(state: rawptr, w, h: i32),
    destroy:          proc(state: rawptr),
    get_proc_address: proc(state: rawptr, name: cstring) -> rawptr,
}

// CPU-resident image data with an optional lazily-created GPU texture.
// Window-owned images keep `data` alive while their GPU texture may be
// uploaded and unloaded independently.
Image :: struct {
    texture: Texture,
    data:    []u8,
    w:       u32,
    h:       u32,
    format:  Pixel_Format,
}

// Render Target data;
Render_Target :: struct {
    idx:       Texture,
    w:         u32,
    h:         u32,
    is_screen: bool // fbo 0
}

// Texture index;
Texture               :: distinct u32

Pixel_Format          :: enum { RGBA8, BGRA8, R8, A8 }
Blend_Mode            :: enum { Opaque, Alpha, Additive }
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
