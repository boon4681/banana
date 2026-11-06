package render

import "src:core/common"
import "base:runtime"

Vertex :: struct {
    pos:   [2]f32,
    uv:    [2]f32,
    color: common.Color,
    mode:  Vertex_Mode,
}

Vertex_Mode :: enum u32 {
    Solid,
    Texture,
    MSDF,
    Round,
    Edge,
    Edge_Texture,
    Shadow,
}

Clip_Edge :: struct {
    to_local: common.Mat3x3,
    size:     [2]f32,
    radius:   common.Radii,
}

MAX_CLIP_EDGES  :: 4
MAX_EFFECT_TAPS :: 24

@(thread_local)
clip_edges: [MAX_CLIP_EDGES]Clip_Edge

@(thread_local)
clip_edge_count: int

// set the clip shapes the next draws get cut by
// only the innermost MAX_CLIP_EDGES get antialiased edges, the outer ones just clip
set_clip_edges :: proc(edges: []Clip_Edge) {
    first := max(len(edges) - MAX_CLIP_EDGES, 0)
    clip_edge_count = copy(clip_edges[:], edges[first:])
}

Effect :: struct {
    color:  [4][4]f32,
    offset: [4]f32,
    step:   [2]f32,
    taps:   int,
    sigma:  f32,
    tint:   [4]f32,
    shadow: bool,
}

EFFECT_COPY :: Effect{
    color = {
        {1, 0, 0, 0},
        {0, 1, 0, 0},
        {0, 0, 1, 0},
        {0, 0, 0, 1}
    }
}

// a vertex of the GPU glyph pipeline
// uv is in em space and the curve fields point into the bézier store passed to draw_glyphs
Glyph_Vertex :: struct {
    pos:         [2]f32,
    uv:          [2]f32,
    color:       common.Color,
    curve_base:  u32,
    curve_count: u32,
}

// glyph geometry the backend keep on the GPU
// the renderer free every mesh at shutdown, the handle is small enough to keep on a text node
Glyph_Mesh :: struct {
    idx:     u32,
    version: u64,
}

// colored and textured geometry the backend keep on the GPU
Mesh :: struct {
    idx:     u32,
    version: u64,
}

Renderer :: struct #all_or_none {
    create_state:     proc(allocator: runtime.Allocator) -> rawptr,
    free_state:       proc(state: rawptr, allocator: runtime.Allocator),
    get_active_state: proc()->rawptr,

    init: proc(
		state:     rawptr,
		render:    Render_Interface,
		width:     int,
		height:    int,
		options:   Init_Options,
		allocator: runtime.Allocator,
    ),
    shutdown:         proc(),
    set_active_state: proc(state: rawptr),
    make_current:     proc(), // call after set_active_state when switching windows

    clear:    proc(target: Render_Target, color: common.Color, scissor: Maybe(common.Rect) = nil),
    present:  proc(),
    retained: proc() -> bool, // true when the screen keep the last frame's pixels, so the next frame can redraw only part of it

    draw: proc(
		target:   Render_Target,
		vertices: []Vertex,
		indices:  []u32,
		texture:  Texture,
		scissor:  Maybe(common.Rect),
		blend:    Blend_Mode,
    ),

    // draw a retained mesh, it only upload again when geometry_version change
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

	// draw glyph quads straight from quadratic bézier outlines, 3 em space points per curve
	// curves_version let each backend cache the upload, send the full slice again whenever it bump
    draw_glyphs: proc(
		target:         Render_Target,
		vertices:       []Glyph_Vertex,
		indices:        []u32,
		curves:         [][2]f32,
		curves_version: u64,
		transform:      common.Mat3x3,
		scissor:        Maybe(common.Rect),
    ),

    // draw a retained glyph mesh, it only upload again when geometry_version change
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

    // draw a glyph mesh with the experimental ROBIN text path
    // data start with per-cell winding records that point to copies of the local quadratic curves
    draw_robin_mesh: proc(
        target:           Render_Target,
        mesh:             ^Glyph_Mesh,
        vertices:         []Glyph_Vertex,
        indices:          []u32,
        geometry_version: u64,
        transform:        common.Mat3x3,
        data:             [][2]f32,
        data_version:     u64,
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

    // images keep their pixels in RAM, upload make and cache the GPU texture on first visible use
    // unload only free that GPU copy
    upload_image: proc(image: ^Image) -> Texture,
    unload_image: proc(image: ^Image),

    create_render_texture: proc(width: int, height: int) -> (Texture, Render_Target),
    destroy_render_target: proc(handle: Render_Target),

    resize:         proc(width, height: int),
    swapchain_size: proc() -> (int, int),

	// read a target back as RGBA8 with top-left origin, the screen give the last presented frame
    read_pixels: proc(target: Render_Target, allocator: runtime.Allocator) -> (data: []u8, width, height: int),

    stencil_clear:     proc(),
    stencil_push_clip: proc(),
    stencil_use_clip:  proc(),
    stencil_pop_clip:  proc(),

    // start drawing into a layer, pass the returned token to layer_end
    // each target has its own stencil but the clip depth is one counter, so the token save and restore it
    layer_begin: proc(target: Render_Target) -> (token: int),
    layer_end:   proc(parent: Render_Target, token: int),

    draw_effect: proc(
        target:   Render_Target,
        source:   Texture,
        vertices: [4]Vertex,
        effect:   Effect,
        scissor:  Maybe(common.Rect),
        blend:    Blend_Mode,
    ),
}

CONFIG_RENDERER_NAME :: #config(banana_RENDER_BACKEND, "")

when ODIN_OS == .Windows {
    DEFAULT_RENDERER_NAME :: "d3d11"
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
    RENDERER :: RENDERER_D3D11
} else when RENDERER_NAME == "gl" {
    RENDERER :: RENDERER_GL
} else when RENDERER_NAME == "webgl" {
    RENDERER :: RENDERER_WEBGL
} else {
    #panic("'" + RENDERER_NAME + "' is not a valid banana_RENDER_BACKEND on " + ODIN_OS_STRING + ". Available: " + AVAILABLE_RENDERERS)
}
