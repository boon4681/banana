package render

import "src:core/common"
import "base:runtime"

@(private="file")
_state_size :: proc() -> int {
    return 0
}

@(private="file")
_init :: proc(
	state:     rawptr,
	render:      Render_Interface,
	width:     int,
	height:    int,
	options:   Init_Options,
	allocator: runtime.Allocator,
) {
    panic("banana render backend 'nil': init() called — set banana_RENDER_BACKEND to a real backend")
}

@(private="file")
_shutdown :: proc() {
    panic("banana render backend 'nil': shutdown()")
}

@(private="file")
_set_active_state :: proc(state: rawptr) {
    panic("banana render backend 'nil': set_internal_state()")
}

@(private="file")
_make_current :: proc() {
    panic("banana render backend 'nil': make_current()")
}

@(private="file")
_clear :: proc(target: Render_Target, color: common.Color) {
    panic("banana render backend 'nil': clear()")
}

@(private="file")
_present :: proc() {
    panic("banana render backend 'nil': present()")
}

@(private="file")
_draw :: proc(
	target:   Render_Target,
	vertices: []Vertex,
	indices:  []u32,
	texture:  Texture,
	scissor:  Maybe(common.Rect),
	blend:    Blend_Mode,
) {
    panic("banana render backend 'nil': draw()")
}

@(private="file")
_draw_mesh :: proc(
    target:Render_Target,
    mesh:^Mesh,
    vertices:[]Vertex,
    indices:[]u32,
    geometry_version:u64,
    transform:common.Mat3x3,
    texture:Texture,
    scissor:Maybe(common.Rect),
    blend:Blend_Mode
) {
    panic("banana render backend 'nil': draw_mesh()")
}

@(private="file")
_draw_glyphs :: proc(
	target:         Render_Target,
	vertices:       []Glyph_Vertex,
	indices:        []u32,
	curves:         [][2]f32,
	curves_version: u64,
	transform:      common.Mat3x3,
	scissor:        Maybe(common.Rect),
) {
    _ = target; _ = vertices; _ = indices; _ = curves; _ = curves_version; _ = scissor
    panic("banana render backend 'nil': draw_glyphs()")
}

@(private="file")
_draw_glyph_mesh :: proc(
    target: Render_Target,
    mesh: ^Glyph_Mesh,
    vertices: []Glyph_Vertex,
    indices: []u32,
    geometry_version: u64,
    transform: common.Mat3x3,
    curves: [][2]f32,
    curves_version: u64,
    scissor: Maybe(common.Rect),
) {
    panic("banana render backend 'nil': draw_glyph_mesh()")
}

@(private="file")
_draw_msdf_mesh :: proc(
    target: Render_Target,
    mesh: ^Glyph_Mesh,
    vertices: []Glyph_Vertex,
    indices: []u32,
    geometry_version: u64,
    transform: common.Mat3x3,
    atlas: Texture,
    pixel_range: f32,
    scissor: Maybe(common.Rect),
) {
    panic("banana render backend 'nil': draw_msdf_mesh()")
}

@(private="file")
_create_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture {
    panic("banana render backend 'nil': create_texture()")
}

@(private="file")
_destroy_texture :: proc(handle: Texture) {
    panic("banana render backend 'nil': destroy_texture()")
}

@(private="file")
_update_texture :: proc(handle: Texture, data: []u8, rect: common.Rect) -> bool {
    panic("banana render backend 'nil': update_texture()")
}

@(private="file")
_set_texture_filter :: proc(handle: Texture, min, mag, mip: Texture_Filter) {
    panic("banana render backend 'nil': set_texture_filter()")
}

@(private="file")
_upload_image :: proc(image: ^Image) -> Texture {
    panic("banana render backend 'nil': upload_image()")
}

@(private="file")
_unload_image :: proc(image: ^Image) {
    panic("banana render backend 'nil': unload_image()")
}

@(private="file")
_create_render_texture :: proc(width: int, height: int) -> (Texture, Render_Target) {
    panic("banana render backend 'nil': create_render_texture()")
}

@(private="file")
_destroy_render_target :: proc(handle: Render_Target) {
    panic("banana render backend 'nil': destroy_render_target()")
}

@(private="file")
_resize :: proc(width, height: int) {
    panic("banana render backend 'nil': resize()")
}

@(private="file")
_swapchain_size :: proc() -> (int, int) {
    panic("banana render backend 'nil': swapchain_size()")
}

@(private="file")
_read_pixels :: proc(target: Render_Target, allocator: runtime.Allocator) -> ([]u8, int, int) {
    panic("banana render backend 'nil': read_pixels()")
}

@(private="file")
_stencil_clear :: proc() {
    panic("banana render backend 'nil': stencil_clear()")
}

@(private="file")
_stencil_push_clip :: proc() {
    panic("banana render backend 'nil': stencil_push_clip()")
}

@(private="file")
_stencil_use_clip :: proc() {
    panic("banana render backend 'nil': stencil_use_clip()")
}

@(private="file")
_stencil_pop_clip :: proc() {
    panic("banana render backend 'nil': stencil_pop_clip()")
}

RENDERER_NIL :: Renderer {
    state_size            = _state_size,
    init                  = _init,
    shutdown              = _shutdown,
    set_active_state      = _set_active_state,
    make_current          = _make_current,
    clear                 = _clear,
    present               = _present,
    draw                  = _draw,
    draw_mesh             = _draw_mesh,
    draw_glyphs           = _draw_glyphs,
    draw_glyph_mesh       = _draw_glyph_mesh,
    draw_msdf_mesh        = _draw_msdf_mesh,
    create_texture        = _create_texture,
    destroy_texture       = _destroy_texture,
    update_texture        = _update_texture,
    set_texture_filter    = _set_texture_filter,
    upload_image          = _upload_image,
    unload_image          = _unload_image,
    create_render_texture = _create_render_texture,
    destroy_render_target = _destroy_render_target,
    resize                = _resize,
    swapchain_size        = _swapchain_size,
    read_pixels           = _read_pixels,
    stencil_clear         = _stencil_clear,
    stencil_push_clip     = _stencil_push_clip,
    stencil_use_clip      = _stencil_use_clip,
    stencil_pop_clip      = _stencil_pop_clip,
}
