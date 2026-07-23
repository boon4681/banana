package render

import "src:core/common"
import "base:runtime"

Vertex :: struct {
    pos:   [2]f32,
    uv:    [2]f32,
    color: common.Color,
}


// Vertex for the GPU glyph pipeline: `uv` is an em-space position and the curve fields window into the quadratic
// bézier store passed to draw_glyphs.
Glyph_Vertex :: struct {
    pos:         [2]f32,
    uv:          [2]f32,
    color:       common.Color,
    curve_base:  u32,
    curve_count: u32,
}

// Backend-owned retained glyph geometry. The renderer releases every mesh at
// context shutdown; callers may keep this lightweight handle on a text node.
Glyph_Mesh :: struct {
    idx:     u32,
    version: u64,
}

// Backend-owned retained geometry for the regular colored/textured pipeline.
Mesh :: struct {
    idx:     u32,
    version: u64,
}

Renderer :: struct #all_or_none {
    state_size: proc() -> int,

    init: proc(
		state:     rawptr,
		render:    Render_Interface,
		width:     int,
		height:    int,
		options:   Init_Options,
		allocator: runtime.Allocator,
    ),
    shutdown:           proc(),
    set_active_state: proc(state: rawptr),
    make_current:       proc(), // Call after set_active_state when switching windows.

    clear:   proc(target: Render_Target, color: common.Color),
    present: proc(),

    draw: proc(
		target:   Render_Target,
		vertices: []Vertex,
		indices:  []u32,
		texture:  Texture,
		scissor:  Maybe(common.Rect),
		blend:    Blend_Mode,
    ),

    // Uploads only when the geometry version changes, then reuses the
    // backend-owned vertex/index buffers on subsequent frames.
    draw_mesh: proc(
        target:           Render_Target,
        mesh:             ^Mesh,
        vertices:         []Vertex,
        indices:          []u32,
        geometry_version: u64,
        transform:        common.Mat3x3,
        texture:          Texture,
        scissor:          Maybe(common.Rect),
        blend:            Blend_Mode,
    ),

	// Renders glyph quads straight from quadratic bézier outlines: 3 points
	// per curve in em space. `curves_version` lets each backend context cache the upload;
    // re-send the full slice whenever the version bumps.
    draw_glyphs: proc(
		target:         Render_Target,
		vertices:       []Glyph_Vertex,
		indices:        []u32,
		curves:         [][2]f32,
		curves_version: u64,
		transform:      common.Mat3x3,
		scissor:        Maybe(common.Rect),
    ),

    // Uploads when `mesh.version` differs from `geometry_version`, otherwise
    // draws the retained VAO/VBO/IBO without touching CPU geometry.
    draw_glyph_mesh: proc(
        target:           Render_Target,
        mesh:             ^Glyph_Mesh,
        vertices:         []Glyph_Vertex,
        indices:          []u32,
        geometry_version: u64,
        transform:        common.Mat3x3,
        curves:           [][2]f32,
        curves_version:   u64,
        scissor:          Maybe(common.Rect),
    ),

    draw_msdf_mesh: proc(
        target:           Render_Target,
        mesh:             ^Glyph_Mesh,
        vertices:         []Glyph_Vertex,
        indices:          []u32,
        geometry_version: u64,
        transform:        common.Mat3x3,
        atlas:            Texture,
        pixel_range:      f32,
        scissor:          Maybe(common.Rect),
    ),

    create_texture:     proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture,
    destroy_texture:    proc(handle: Texture),
    update_texture:     proc(handle: Texture, data: []u8, rect: common.Rect) -> bool,
    set_texture_filter: proc(handle: Texture, min, mag, mip: Texture_Filter),

    // Images keep their pixels in RAM. Upload creates and caches the GPU
    // texture on first visible use; unload releases only that GPU copy.
    upload_image: proc(image: ^Image) -> Texture,
    unload_image: proc(image: ^Image),

    create_render_texture: proc(width: int, height: int) -> (Texture, Render_Target),
    destroy_render_target: proc(handle: Render_Target),

    resize:         proc(width, height: int),
    swapchain_size: proc() -> (int, int),

	// RGBA8, top-left origin. Screen target reads the last presented frame.
    read_pixels: proc(target: Render_Target, allocator: runtime.Allocator) -> (data: []u8, width, height: int),

    stencil_clear:     proc(),
    stencil_push_clip: proc(),
    stencil_use_clip:  proc(),
    stencil_pop_clip:  proc(),
}

CONFIG_RENDERER_NAME :: #config(banana_RENDER_BACKEND, "")

when ODIN_OS == .Windows {
	DEFAULT_RENDERER_NAME :: "gl"
	AVAILABLE_RENDERERS   :: "d3d11, gl, nil"
} else when ODIN_OS == .Linux || ODIN_OS == .Darwin {
	DEFAULT_RENDERER_NAME :: "gl"
	AVAILABLE_RENDERERS   :: "gl, nil"
} else when ODIN_OS == .JS {
	DEFAULT_RENDERER_NAME :: "webgl"
	AVAILABLE_RENDERERS   :: "webgl, nil"
} else {
	DEFAULT_RENDERER_NAME :: "nil"
	AVAILABLE_RENDERERS   :: "nil"
}

when CONFIG_RENDERER_NAME == "" {
	RENDERER_NAME :: DEFAULT_RENDERER_NAME
} else {
	RENDERER_NAME :: CONFIG_RENDERER_NAME
}

when RENDERER_NAME == "nil" {
	RENDERER :: RENDERER_NIL
} else when RENDERER_NAME == "d3d11" {
	#panic("banana: 'd3d11' render backend not implemented yet. Set banana_RENDER_BACKEND=nil for a headless build.")
} else when RENDERER_NAME == "gl" {
	RENDERER :: RENDERER_GL
} else when RENDERER_NAME == "webgl" {
	RENDERER :: RENDERER_WEBGL
} else {
	#panic("'" + RENDERER_NAME + "' is not a valid banana_RENDER_BACKEND on " + ODIN_OS_STRING + ". Available: " + AVAILABLE_RENDERERS)
}
