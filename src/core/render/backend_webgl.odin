#+build js
package render

import "base:runtime"
import "src:core/common"
import gl "vendor:wasm/WebGL"
import glm "core:math/linalg/glsl"

// WebGL2 backend.

@(private="file")
Web_Texture :: struct {
    id:     gl.Texture,
    format: Pixel_Format,
    width,
    height: int,
}

@(private="file")
Web_Mesh :: struct {
    vao:   gl.VertexArrayObject,
    vbo,
    ibo:   gl.Buffer,
    count: int,
}

@(private="file")
Web_Target :: struct {
    fbo: gl.Framebuffer,
    texture_index,
    width,
    height: int,
}

@(private="file")
WebGL_State :: struct {
    glue:            Render_Interface,
    allocator:       runtime.Allocator,
    program:         gl.Program,
    msdf_program:    gl.Program,
    resolution:      i32,
    has_texture:     i32,
    msdf_resolution: i32,
    msdf_range:      i32,
    vao:             gl.VertexArrayObject,
    vbo:             gl.Buffer,
    ibo:             gl.Buffer,
    textures:        [dynamic]Web_Texture,
    meshes:          [dynamic]Web_Mesh,
    glyph_meshes:    [dynamic]Web_Mesh,
    targets:         [dynamic]Web_Target,
    width:           int,
    height:          int,
    stencil_depth:   int,
}

@(private="file")
_state: ^WebGL_State

@(private="file")
VS_SOURCE :: string(#load("shaders/webgl_quad.vert"))
@(private="file")
FS_SOURCE :: string(#load("shaders/webgl_quad.frag"))

@(private="file")
MSDF_VS_SOURCE :: string(#load("shaders/webgl_msdf.vert"))
@(private="file")
MSDF_FS_SOURCE :: string(#load("shaders/webgl_msdf.frag"))

@(private="file")
_state_size :: proc() -> int {
    return size_of(WebGL_State)
}

@(private="file")
_set_state :: proc(state: rawptr) {
    _state = cast(^WebGL_State)(state)
}

@(private="file")
_make_current :: proc() {
    if _state.glue.make_current != nil do _state.glue.make_current(_state.glue.state)
}

@(private="file")
_program :: proc(vs_source, fs_source: string) -> gl.Program {
    vs := gl.CreateShader(gl.VERTEX_SHADER)
    fs := gl.CreateShader(gl.FRAGMENT_SHADER)
    gl.ShaderSource(vs, []string{vs_source})
    gl.ShaderSource(fs, []string{fs_source})
    gl.CompileShader(vs)
    gl.CompileShader(fs)
    assert(gl.GetShaderiv(vs, gl.COMPILE_STATUS) != 0, "WebGL vertex shader compilation failed")
    assert(gl.GetShaderiv(fs, gl.COMPILE_STATUS) != 0, "WebGL fragment shader compilation failed")

    program := gl.CreateProgram()
    gl.AttachShader(program, vs)
    gl.AttachShader(program, fs)
    gl.LinkProgram(program)
    assert(gl.GetProgramParameter(program, gl.LINK_STATUS) != 0, "WebGL program link failed")

    gl.DeleteShader(vs)
    gl.DeleteShader(fs)
    return program
}

@(private="file")
_init :: proc(
    state:     rawptr,
    glue:      Render_Interface,
    width:     int,
    height:    int,
    options:   Init_Options,
    allocator: runtime.Allocator,
) {
    _state = cast(^WebGL_State)(state)
    _state^ = {}
    _state.glue = glue
    _state.allocator = allocator
    _state.width = width
    _state.height = height
    _state.textures = make([dynamic]Web_Texture, 0, allocator)
    _state.meshes = make([dynamic]Web_Mesh, 0, allocator)
    _state.glyph_meshes = make([dynamic]Web_Mesh, 0, allocator)
    _state.targets = make([dynamic]Web_Target, 0, allocator)

    assert(glue.make_context(glue.state, options), "unable to create WebGL2 context")

    _state.program = _program(VS_SOURCE, FS_SOURCE)
    _state.resolution = gl.GetUniformLocation(_state.program, "u_resolution")
    _state.has_texture = gl.GetUniformLocation(_state.program, "u_has_tex")

    _state.msdf_program = _program(MSDF_VS_SOURCE, MSDF_FS_SOURCE)
    _state.msdf_resolution = gl.GetUniformLocation(_state.msdf_program, "u_resolution")
    _state.msdf_range = gl.GetUniformLocation(_state.msdf_program, "u_px_range")

    _state.vao = gl.CreateVertexArray()
    _state.vbo = gl.CreateBuffer()
    _state.ibo = gl.CreateBuffer()
    gl.BindVertexArray(_state.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, _state.vbo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, _state.ibo)
    _vertex_layout(size_of(Vertex))

    gl.Enable(gl.STENCIL_TEST)
    gl.StencilMask(0)
    gl.Viewport(0, 0, i32(width), i32(height))
}

@(private="file")
_vertex_layout :: proc(stride: int) {
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, stride, 16)
}

@(private="file")
_shutdown :: proc() {
    if _state == nil do return

    for mesh in _state.meshes do _delete_mesh(mesh)
    for mesh in _state.glyph_meshes do _delete_mesh(mesh)
    for texture in _state.textures {
        if texture.id != 0 do gl.DeleteTexture(texture.id)
    }
    for target in _state.targets {
        if target.fbo != 0 do gl.DeleteFramebuffer(target.fbo)
    }

    gl.DeleteBuffer(_state.vbo)
    gl.DeleteBuffer(_state.ibo)
    gl.DeleteVertexArray(_state.vao)
    gl.DeleteProgram(_state.program)
    gl.DeleteProgram(_state.msdf_program)

    delete(_state.textures)
    delete(_state.meshes)
    delete(_state.glyph_meshes)
    delete(_state.targets)
}

@(private="file")
_delete_mesh :: proc(mesh: Web_Mesh) {
    gl.DeleteBuffer(mesh.vbo)
    gl.DeleteBuffer(mesh.ibo)
    gl.DeleteVertexArray(mesh.vao)
}

@(private="file")
_bind_target :: proc(target: Render_Target) -> (width, height: int) {
    if target != INVALID_RENDER_TARGET {
        i := int(target.idx) - 1
        if i >= 0 && i < len(_state.targets) && _state.targets[i].fbo != 0 {
            t := _state.targets[i]
            gl.BindFramebuffer(gl.FRAMEBUFFER, t.fbo)
            gl.Viewport(0, 0, i32(t.width), i32(t.height))
            return t.width, t.height
        }
    }

    // An invalid or destroyed target must not leave an unrelated FBO bound.
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.Viewport(0, 0, i32(_state.width), i32(_state.height))
    return _state.width, _state.height
}

@(private="file")
_scissor :: proc(target_height: int, scissor: Maybe(common.Rect)) {
    r, ok := scissor.?
    if !ok {
        gl.Disable(gl.SCISSOR_TEST)
        return
    }
    y_bottom := i32(target_height) - i32(r.y) - i32(r.h)
    gl.Enable(gl.SCISSOR_TEST)
    gl.Scissor(i32(r.x), max(y_bottom, 0), i32(r.w), i32(r.h))
}

@(private="file")
_blend :: proc(mode: Blend_Mode) {
    switch mode {
    case .Opaque:
        gl.Disable(gl.BLEND)
    case .Alpha:
        gl.Enable(gl.BLEND)
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    case .Additive:
        gl.Enable(gl.BLEND)
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE)
    }
}

@(private="file")
_clear :: proc(target: Render_Target, color: common.Color) {
    _bind_target(target)
    gl.Disable(gl.SCISSOR_TEST)
    gl.ClearColor(f32(color[0]) / 255, f32(color[1]) / 255, f32(color[2]) / 255, f32(color[3]) / 255)
    gl.Clear(u32(gl.COLOR_BUFFER_BIT))
}

@(private="file")
_present :: proc() {
    if _state.glue.present != nil do _state.glue.present(_state.glue.state)
}

// Draws an already-populated VAO through the quad program.
@(private="file")
_draw_bound :: proc(
    target:  Render_Target,
    vao:     gl.VertexArrayObject,
    count:   int,
    texture: Texture,
    scissor: Maybe(common.Rect),
    blend:   Blend_Mode,
    transform: common.Mat3x3 = common.Mat3X3_IDENTITY,
) {
    w, h := _bind_target(target)
    _scissor(h, scissor)
    _blend(blend)

    gl.UseProgram(_state.program)
    gl.Uniform2f(_state.resolution, f32(w), f32(h))
    gl.UniformMatrix3fv(gl.GetUniformLocation(_state.program, "u_transform"), transmute(glm.mat3)transform)

    has_texture := false
    if id, ok := _texture_id(texture); ok {
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, id)
        has_texture = true
    }
    gl.Uniform1i(_state.has_texture, has_texture ? 1 : 0)

    gl.BindVertexArray(vao)
    gl.DrawElements(gl.TRIANGLES, count, gl.UNSIGNED_INT, nil)
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
    if len(vertices) == 0 || len(indices) == 0 do return

    gl.BindVertexArray(_state.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, _state.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(Vertex), raw_data(vertices), gl.STREAM_DRAW)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, _state.ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), raw_data(indices), gl.STREAM_DRAW)

    _draw_bound(target, _state.vao, len(indices), texture, scissor, blend)
}

// Resolves `idx` into backend mesh storage, allocating on first use.
@(private="file")
_resolve_mesh :: proc(idx: ^u32, meshes: ^[dynamic]Web_Mesh, stride: int) -> ^Web_Mesh {
    if idx^ == 0 {
        mesh := Web_Mesh{
            vao = gl.CreateVertexArray(),
            vbo = gl.CreateBuffer(),
            ibo = gl.CreateBuffer(),
        }
        gl.BindVertexArray(mesh.vao)
        gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ibo)
        _vertex_layout(stride)

        append(meshes, mesh)
        idx^ = u32(len(meshes))
    }

    i := int(idx^) - 1
    if i < 0 || i >= len(meshes) do return nil
    return &meshes[i]
}

@(private="file")
_upload_mesh :: proc(mesh: ^Web_Mesh, vertices: rawptr, vertices_size: int, indices: []u32) {
    gl.BindVertexArray(mesh.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, vertices_size, vertices, gl.STATIC_DRAW)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)
    mesh.count = len(indices)
}

@(private="file")
_draw_mesh :: proc(
    target:   Render_Target,
    mesh:     ^Mesh,
    vertices: []Vertex,
    indices:  []u32,
    version:  u64,
    transform: common.Mat3x3,
    texture:  Texture,
    scissor:  Maybe(common.Rect),
    blend:    Blend_Mode,
) {
    if mesh == nil do return

    m := _resolve_mesh(&mesh.idx, &_state.meshes, size_of(Vertex))
    if m == nil do return

    if mesh.version != version {
        if len(vertices) == 0 || len(indices) == 0 do return
        _upload_mesh(m, raw_data(vertices), len(vertices) * size_of(Vertex), indices)
        mesh.version = version
    }
    if m.count == 0 do return

    _draw_bound(target, m.vao, m.count, texture, scissor, blend, transform)
}

// The desktop curve renderer uses samplerBuffer, which WebGL2 does not expose.
// Browser text uses the MSDF path below, so these compatibility entries are no-ops.

@(private="file")
_draw_glyphs :: proc(
    target:   Render_Target,
    vertices: []Glyph_Vertex,
    indices:  []u32,
    curves:   [][2]f32,
    version:  u64,
    transform: common.Mat3x3,
    scissor:  Maybe(common.Rect),
) {
}

@(private="file")
_draw_glyph_mesh :: proc(
    target:           Render_Target,
    mesh:             ^Glyph_Mesh,
    vertices:         []Glyph_Vertex,
    indices:          []u32,
    geometry_version: u64,
    transform:        common.Mat3x3,
    curves:           [][2]f32,
    curves_version:   u64,
    scissor:          Maybe(common.Rect),
) {
}

@(private="file")
_draw_msdf :: proc(
    target:      Render_Target,
    mesh:        ^Glyph_Mesh,
    vertices:    []Glyph_Vertex,
    indices:     []u32,
    version:     u64,
    transform: common.Mat3x3,
    atlas:       Texture,
    pixel_range: f32,
    scissor:     Maybe(common.Rect),
) {
    if mesh == nil do return
    atlas_id, atlas_ok := _texture_id(atlas)
    if !atlas_ok do return

    m := _resolve_mesh(&mesh.idx, &_state.glyph_meshes, size_of(Glyph_Vertex))
    if m == nil do return

    if mesh.version != version {
        if len(vertices) == 0 || len(indices) == 0 do return
        _upload_mesh(m, raw_data(vertices), len(vertices) * size_of(Glyph_Vertex), indices)
        mesh.version = version
    }
    if m.count == 0 do return

    w, h := _bind_target(target)
    _scissor(h, scissor)
    _blend(.Alpha)

    gl.UseProgram(_state.msdf_program)
    gl.Uniform2f(_state.msdf_resolution, f32(w), f32(h))
    gl.UniformMatrix3fv(gl.GetUniformLocation(_state.msdf_program, "u_transform"), transmute(glm.mat3)transform)
    gl.Uniform1f(_state.msdf_range, pixel_range)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, atlas_id)

    gl.BindVertexArray(m.vao)
    gl.DrawElements(gl.TRIANGLES, m.count, gl.UNSIGNED_INT, nil)
}

@(private="file")
_format :: proc(format: Pixel_Format) -> (layout: gl.Enum, channels: int) {
    switch format {
    case .RGBA8, .BGRA8: return gl.RGBA, 4
    case .R8, .A8:       return gl.RED, 1
    }
    return gl.RGBA, 4
}

// Returns the live GL texture behind a handle; ok=false when the handle is out
// of range or its texture has already been destroyed.
@(private="file")
_texture_id :: proc(handle: Texture) -> (id: gl.Texture, ok: bool) {
    i := int(handle) - 1
    if i < 0 || i >= len(_state.textures) do return 0, false
    id = _state.textures[i].id
    return id, id != 0
}

@(private="file")
_create_texture :: proc(data: []u8, width, height: int, format: Pixel_Format) -> Texture {
    id := gl.CreateTexture()
    gl.BindTexture(gl.TEXTURE_2D, id)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))

    layout, _ := _format(format)
    pixels := len(data) > 0 ? raw_data(data) : nil
    gl.TexImage2D(gl.TEXTURE_2D, 0, layout, i32(width), i32(height), 0, layout, gl.UNSIGNED_BYTE, len(data), pixels)

    append(&_state.textures, Web_Texture{id = id, format = format, width = width, height = height})
    return Texture(len(_state.textures))
}

@(private="file")
_destroy_texture :: proc(handle: Texture) {
    id, ok := _texture_id(handle)
    if !ok do return
    gl.DeleteTexture(id)
    _state.textures[int(handle) - 1].id = 0
}

@(private="file")
_update_texture :: proc(handle: Texture, data: []u8, rect: common.Rect) -> bool {
    if len(data) == 0 do return false
    id := _texture_id(handle) or_return
    texture := _state.textures[int(handle) - 1]

    x, y := int(rect.x), int(rect.y)
    width, height := int(rect.w), int(rect.h)
    if x < 0 || y < 0 || width <= 0 || height <= 0 do return false
    if x + width > texture.width || y + height > texture.height do return false

    layout, channels := _format(texture.format)
    size := width * height * channels
    if len(data) < size do return false

    gl.BindTexture(gl.TEXTURE_2D, id)
    gl.TexSubImage2D(gl.TEXTURE_2D, 0, i32(x), i32(y), i32(width), i32(height), layout, gl.UNSIGNED_BYTE, size, raw_data(data))
    return true
}

@(private="file")
_filter :: proc(handle: Texture, min, mag, mip: Texture_Filter) {
    id, ok := _texture_id(handle)
    if !ok do return
    gl.BindTexture(gl.TEXTURE_2D, id)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(min == .Nearest ? gl.NEAREST : gl.LINEAR))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(mag == .Nearest ? gl.NEAREST : gl.LINEAR))
}

@(private="file")
_upload :: proc(image: ^Image) -> Texture {
    if image == nil do return INVALID_TEXTURE
    if image.texture != INVALID_TEXTURE do return image.texture

    width, height := int(image.w), int(image.h)
    required := width * height * pixel_size(image.format)
    if width <= 0 || height <= 0 || required <= 0 || len(image.data) < required {
        return INVALID_TEXTURE
    }

    image.texture = _create_texture(image.data[:required], width, height, image.format)
    return image.texture
}

@(private="file")
_unload :: proc(image: ^Image) {
    if image == nil || image.texture == INVALID_TEXTURE do return
    _destroy_texture(image.texture)
    image.texture = INVALID_TEXTURE
}

@(private="file")
_create_target :: proc(width, height: int) -> (Texture, Render_Target) {
    tex := _create_texture({}, width, height, .RGBA8)

    fbo := gl.CreateFramebuffer()
    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, _state.textures[int(tex) - 1].id, 0)

    append(&_state.targets, Web_Target{
        fbo           = fbo,
        texture_index = int(tex) - 1,
        width         = width,
        height        = height,
    })
    return tex, Render_Target{
        idx = Texture(len(_state.targets)),
        w   = u32(width),
        h   = u32(height),
    }
}

@(private="file")
_destroy_target :: proc(target: Render_Target) {
    i := int(target.idx) - 1
    if i < 0 || i >= len(_state.targets) do return
    gl.DeleteFramebuffer(_state.targets[i].fbo)
    _state.targets[i].fbo = 0
}

@(private="file")
_resize :: proc(width, height: int) {
    _state.width = width
    _state.height = height
    gl.Viewport(0, 0, i32(width), i32(height))
}

@(private="file")
_size :: proc() -> (int, int) {
    return _state.width, _state.height
}

@(private="file")
_read :: proc(target: Render_Target, allocator: runtime.Allocator) -> ([]u8, int, int) {
    w, h := _bind_target(target)
    data := make([]u8, w * h * 4, allocator)
    gl.ReadnPixels(0, 0, i32(w), i32(h), gl.RGBA, gl.UNSIGNED_BYTE, len(data), raw_data(data))

    // GL rows are bottom-up; flip to top-left origin.
    row := w * 4
    tmp := make([]u8, row, context.temp_allocator)
    for y in 0 ..< h / 2 {
        top := data[y * row:][:row]
        bot := data[(h - 1 - y) * row:][:row]
        copy(tmp, top)
        copy(top, bot)
        copy(bot, tmp)
    }
    return data, w, h
}

@(private="file")
_stencil_clear :: proc() {
    gl.ClearStencil(0)
    gl.StencilMask(0xff)
    gl.Clear(u32(gl.STENCIL_BUFFER_BIT))
    gl.StencilMask(0)
    _state.stencil_depth = 0
}

@(private="file")
_stencil_push :: proc() {
    _state.stencil_depth += 1
    bit := u32(1) << u32(_state.stencil_depth)
    gl.ColorMask(false, false, false, false)
    gl.StencilMask(bit)
    gl.StencilFunc(gl.ALWAYS, i32(bit), bit)
    gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE)
}

@(private="file")
_stencil_use :: proc() {
    bit := u32(1) << u32(_state.stencil_depth)
    gl.ColorMask(true, true, true, true)
    gl.StencilMask(0)
    gl.StencilFunc(gl.EQUAL, i32(bit), bit)
    gl.StencilOp(gl.KEEP, gl.KEEP, gl.KEEP)
}

@(private="file")
_stencil_pop :: proc() {
    if _state.stencil_depth > 0 do _state.stencil_depth -= 1
    gl.ColorMask(true, true, true, true)
    gl.StencilMask(0)
    if _state.stencil_depth == 0 {
        gl.StencilFunc(gl.ALWAYS, 0, 0)
    } else {
        bit := u32(1) << u32(_state.stencil_depth)
        gl.StencilFunc(gl.EQUAL, i32(bit), bit)
    }
}

RENDERER_WEBGL :: Renderer {
    state_size            = _state_size,
    init                  = _init,
    shutdown              = _shutdown,
    set_active_state      = _set_state,
    make_current          = _make_current,
    clear                 = _clear,
    present               = _present,
    draw                  = _draw,
    draw_mesh             = _draw_mesh,
    draw_glyphs           = _draw_glyphs,
    draw_glyph_mesh       = _draw_glyph_mesh,
    draw_msdf_mesh        = _draw_msdf,
    create_texture        = _create_texture,
    destroy_texture       = _destroy_texture,
    update_texture        = _update_texture,
    set_texture_filter    = _filter,
    upload_image          = _upload,
    unload_image          = _unload,
    create_render_texture = _create_target,
    destroy_render_target = _destroy_target,
    resize                = _resize,
    swapchain_size        = _size,
    read_pixels           = _read,
    stencil_clear         = _stencil_clear,
    stencil_push_clip     = _stencil_push,
    stencil_use_clip      = _stencil_use,
    stencil_pop_clip      = _stencil_pop,
}
