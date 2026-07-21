package render

import "src:core/common"
import "base:runtime"

_nil_state_size :: proc() -> int { return 0 }

_nil_init :: proc(
	state:     rawptr,
	render:      Render_Interface,
	width:     int,
	height:    int,
	options:   Init_Options,
	allocator: runtime.Allocator,
) {
    _ = state; _ = render; _ = width; _ = height; _ = options; _ = allocator
    panic("banana render backend 'nil': init() called — set banana_RENDER_BACKEND to a real backend")
}

_nil_shutdown :: proc() {
    panic("banana render backend 'nil': shutdown()")
}

_nil_set_active_state :: proc(state: rawptr) {
    _ = state
    panic("banana render backend 'nil': set_internal_state()")
}

_nil_make_current :: proc() {
    panic("banana render backend 'nil': make_current()")
}

_nil_clear :: proc(target: Render_Target, color: common.Color) {
    _ = target; _ = color
    panic("banana render backend 'nil': clear()")
}

_nil_present :: proc() {
    panic("banana render backend 'nil': present()")
}

_nil_draw :: proc(
	target:   Render_Target,
	vertices: []Vertex,
	indices:  []u32,
	texture:  Texture,
	scissor:  Maybe(common.Rect),
	blend:    Blend_Mode,
) {
    _ = target; _ = vertices; _ = indices; _ = texture; _ = scissor; _ = blend
    panic("banana render backend 'nil': draw()")
}

_nil_draw_mesh :: proc(target:Render_Target,mesh:^Mesh,vertices:[]Vertex,indices:[]u32,geometry_version:u64,texture:Texture,scissor:Maybe(common.Rect),blend:Blend_Mode) {
    _=target;_=mesh;_=vertices;_=indices;_=geometry_version;_=texture;_=scissor;_=blend
    panic("banana render backend 'nil': draw_mesh()")
}

_nil_draw_glyphs :: proc(
	target:         Render_Target,
	vertices:       []Glyph_Vertex,
	indices:        []u32,
	curves:         [][2]f32,
	curves_version: u64,
	scissor:        Maybe(common.Rect),
) {
    _ = target; _ = vertices; _ = indices; _ = curves; _ = curves_version; _ = scissor
    panic("banana render backend 'nil': draw_glyphs()")
}

_nil_draw_glyph_mesh :: proc(
    target: Render_Target,
    mesh: ^Glyph_Mesh,
    vertices: []Glyph_Vertex,
    indices: []u32,
    geometry_version: u64,
    curves: [][2]f32,
    curves_version: u64,
    scissor: Maybe(common.Rect),
) {
    _ = target; _ = mesh; _ = vertices; _ = indices; _ = geometry_version; _ = curves; _ = curves_version; _ = scissor
    panic("banana render backend 'nil': draw_glyph_mesh()")
}

_nil_draw_msdf_mesh :: proc(
    target: Render_Target,
    mesh: ^Glyph_Mesh,
    vertices: []Glyph_Vertex,
    indices: []u32,
    geometry_version: u64,
    atlas: Texture,
    pixel_range: f32,
    scissor: Maybe(common.Rect),
) {
    _ = target; _ = mesh; _ = vertices; _ = indices; _ = geometry_version; _ = atlas; _ = pixel_range; _ = scissor
    panic("banana render backend 'nil': draw_msdf_mesh()")
}

_nil_create_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture {
    _ = data; _ = width; _ = height; _ = format
    panic("banana render backend 'nil': create_texture()")
}

_nil_destroy_texture :: proc(handle: Texture) {
    _ = handle
    panic("banana render backend 'nil': destroy_texture()")
}

_nil_update_texture :: proc(handle: Texture, data: []u8, rect: common.Rect) -> bool {
    _ = handle; _ = data; _ = rect
    panic("banana render backend 'nil': update_texture()")
}

_nil_set_texture_filter :: proc(handle: Texture, min, mag, mip: Texture_Filter) {
    _ = handle; _ = min; _ = mag; _ = mip
    panic("banana render backend 'nil': set_texture_filter()")
}

_nil_upload_image :: proc(image: ^Image) -> Texture {
    _ = image
    panic("banana render backend 'nil': upload_image()")
}

_nil_unload_image :: proc(image: ^Image) {
    _ = image
    panic("banana render backend 'nil': unload_image()")
}

_nil_create_render_texture :: proc(width: int, height: int) -> (Texture, Render_Target) {
    _ = width; _ = height
    panic("banana render backend 'nil': create_render_texture()")
}

_nil_destroy_render_target :: proc(handle: Render_Target) {
    _ = handle
    panic("banana render backend 'nil': destroy_render_target()")
}

_nil_resize :: proc(width, height: int) {
    _ = width; _ = height
    panic("banana render backend 'nil': resize()")
}

_nil_swapchain_size :: proc() -> (int, int) {
    panic("banana render backend 'nil': swapchain_size()")
}

_nil_read_pixels :: proc(target: Render_Target, allocator: runtime.Allocator) -> ([]u8, int, int) {
    _ = target; _ = allocator
    panic("banana render backend 'nil': read_pixels()")
}

_nil_stencil_clear :: proc() {
    panic("banana render backend 'nil': stencil_clear()")
}

_nil_stencil_push_clip :: proc() {
    panic("banana render backend 'nil': stencil_push_clip()")
}

_nil_stencil_use_clip :: proc() {
    panic("banana render backend 'nil': stencil_use_clip()")
}

_nil_stencil_pop_clip :: proc() {
    panic("banana render backend 'nil': stencil_pop_clip()")
}

RENDERER_NIL :: Renderer {
    state_size            = _nil_state_size,
    init                  = _nil_init,
    shutdown              = _nil_shutdown,
    set_active_state      = _nil_set_active_state,
    make_current          = _nil_make_current,
    clear                 = _nil_clear,
    present               = _nil_present,
    draw                  = _nil_draw,
    draw_mesh             = _nil_draw_mesh,
    draw_glyphs           = _nil_draw_glyphs,
    draw_glyph_mesh       = _nil_draw_glyph_mesh,
    draw_msdf_mesh        = _nil_draw_msdf_mesh,
    create_texture        = _nil_create_texture,
    destroy_texture       = _nil_destroy_texture,
    update_texture        = _nil_update_texture,
    set_texture_filter    = _nil_set_texture_filter,
    upload_image          = _nil_upload_image,
    unload_image          = _nil_unload_image,
    create_render_texture = _nil_create_render_texture,
    destroy_render_target = _nil_destroy_render_target,
    resize                = _nil_resize,
    swapchain_size        = _nil_swapchain_size,
    read_pixels           = _nil_read_pixels,
    stencil_clear         = _nil_stencil_clear,
    stencil_push_clip     = _nil_stencil_push_clip,
    stencil_use_clip      = _nil_stencil_use_clip,
    stencil_pop_clip      = _nil_stencil_pop_clip,
}
