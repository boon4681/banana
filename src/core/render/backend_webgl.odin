#+build js
package render

import "base:runtime"
import "src:core/common"
import gl "vendor:wasm/WebGL"
import glm "core:math/linalg/glsl"

// the WebGL2 backend

@(private="file")
Web_Texture :: struct {
    id:     gl.Texture,
    format: Pixel_Format,
    width,
    height: int,
}

@(private="file")
Web_Mesh :: struct {
    vao: gl.VertexArrayObject,
    vbo,
    ibo:   gl.Buffer,
    count: int,
}

@(private="file")
Web_Target :: struct {
    fbo: gl.Framebuffer,
    stencil: gl.Renderbuffer,
    texture_index,
    width,
    height: int,
}

@(private="file")
WebGL_State :: struct {
    glue:             Render_Interface,
    allocator:        runtime.Allocator,
    program:          gl.Program,
    msdf_program:     gl.Program,
    robin_program:    gl.Program,
    resolution:       i32,
    has_texture:      i32,
    msdf_resolution:  i32,
    msdf_range:       i32,
    robin_resolution: i32,
    robin_transform:  i32,
    robin_data:       i32,
    robin_data_width: i32,
    robin_tex:        gl.Texture,
    robin_atlas_width,
    robin_atlas_height: int,
    robin_data_version: u64,
    max_texture_size:   int,
    vao:                gl.VertexArrayObject,
    vbo:                gl.Buffer,
    ibo:                gl.Buffer,
    textures:           [dynamic]Web_Texture,
    meshes:             [dynamic]Web_Mesh,
    glyph_meshes:       [dynamic]Web_Mesh,
    robin_meshes:       [dynamic]Web_Mesh,
    targets:            [dynamic]Web_Target,
    width:              int,
    height:             int,
    stencil_depth:      int,
    present_program:    gl.Program,
    screen_texture:     Texture,
    screen_target:      Render_Target,
    effect_program:     gl.Program,
    layer:              Render_Target,
    clip_count_loc:     [_Clip_Slot]i32,
    clip_loc_ready:     [_Clip_Slot]bool,
    clip_count_sent:    [_Clip_Slot]int,
}

WEB_ROBIN_ENABLED     :: #config(BANANA_TEXT_ROBIN_GPU_UNSAFE, true)
WEB_ROBIN_GRID        :: 16
WEB_ROBIN_ATLAS_WIDTH :: 1024

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
ROBIN_VS_SOURCE :: string(#load("shaders/webgl_robin.vert"))
@(private="file")
ROBIN_FS_SOURCE :: string(#load("shaders/webgl_robin.frag"))
@(private="file")
EFFECT_FS_SOURCE :: string(#load("shaders/webgl_effect.frag"))

@(private = "file")
_create_state :: proc(allocator: runtime.Allocator) -> rawptr {
    return new(WebGL_State, allocator)
}

@(private = "file")
_free_state :: proc(state: rawptr, allocator: runtime.Allocator) {
    if state != nil do runtime.mem_free(state, allocator)
}

@(private="file")
_get_active_state :: proc() -> rawptr {
    return _state
}

@(private="file")
_set_active_state :: proc(state: rawptr) {
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
    _state.robin_meshes = make([dynamic]Web_Mesh, 0, allocator)
    _state.targets = make([dynamic]Web_Target, 0, allocator)

    assert(glue.make_context(glue.state, options), "unable to create WebGL2 context")

    _state.program = _program(VS_SOURCE, FS_SOURCE)
    _state.resolution = gl.GetUniformLocation(_state.program, "u_resolution")
    _state.has_texture = gl.GetUniformLocation(_state.program, "u_has_tex")

    _state.msdf_program = _program(MSDF_VS_SOURCE, MSDF_FS_SOURCE)
    _state.msdf_resolution = gl.GetUniformLocation(_state.msdf_program, "u_resolution")
    _state.msdf_range = gl.GetUniformLocation(_state.msdf_program, "u_px_range")
    _state.effect_program = _program(VS_SOURCE, EFFECT_FS_SOURCE)
    _state.present_program = _program(string(#load("shaders/webgl_present.vert")), string(#load("shaders/webgl_present.frag")))

    when WEB_ROBIN_ENABLED {
        if gl.IsExtensionSupported("EXT_color_buffer_float") {
            gl.GetExtension("EXT_color_buffer_float")
        }
        _state.robin_program = _program(ROBIN_VS_SOURCE, ROBIN_FS_SOURCE)
        _state.robin_resolution = gl.GetUniformLocation(_state.robin_program, "u_resolution")
        _state.robin_transform = gl.GetUniformLocation(_state.robin_program, "u_transform")
        _state.robin_data = gl.GetUniformLocation(_state.robin_program, "u_robin_data")
        _state.robin_data_width = gl.GetUniformLocation(_state.robin_program, "u_robin_data_width")

        _state.robin_tex = gl.CreateTexture()
        gl.BindTexture(gl.TEXTURE_2D, _state.robin_tex)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))
    }

    _state.vao = gl.CreateVertexArray()
    _state.vbo = gl.CreateBuffer()
    _state.ibo = gl.CreateBuffer()
    gl.BindVertexArray(_state.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, _state.vbo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, _state.ibo)
    _quad_vertex_layout(size_of(Vertex))

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
_quad_vertex_layout :: proc(stride: int) {
    _vertex_layout(stride)
    gl.EnableVertexAttribArray(3)
    gl.VertexAttribIPointer(3, 1, gl.UNSIGNED_INT, stride, 20)
}

// set the vertex layout of the ROBIN program
// only ROBIN read curve_base and curve_count of Glyph_Vertex
@(private="file")
_robin_vertex_layout :: proc(stride: int) {
    _vertex_layout(stride)
    gl.EnableVertexAttribArray(3)
    gl.VertexAttribIPointer(3, 2, gl.UNSIGNED_INT, stride, 20)
}

@(private="file")
_shutdown :: proc() {
    if _state == nil do return

    for mesh in _state.meshes do _delete_mesh(mesh)
    for mesh in _state.glyph_meshes do _delete_mesh(mesh)
    for mesh in _state.robin_meshes do _delete_mesh(mesh)
    if _state.robin_tex != 0 do gl.DeleteTexture(_state.robin_tex)
    for texture in _state.textures {
        if texture.id != 0 do gl.DeleteTexture(texture.id)
    }
    for target in _state.targets {
        if target.fbo != 0 do gl.DeleteFramebuffer(target.fbo)
        if target.stencil != 0 do gl.DeleteRenderbuffer(target.stencil)
    }
    gl.DeleteProgram(_state.effect_program)
    gl.DeleteProgram(_state.present_program)

    gl.DeleteBuffer(_state.vbo)
    gl.DeleteBuffer(_state.ibo)
    gl.DeleteVertexArray(_state.vao)
    gl.DeleteProgram(_state.program)
    gl.DeleteProgram(_state.msdf_program)
    if _state.robin_program != 0 do gl.DeleteProgram(_state.robin_program)

    delete(_state.textures)
    delete(_state.meshes)
    delete(_state.glyph_meshes)
    delete(_state.robin_meshes)
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
    if target == INVALID_RENDER_TARGET {
        _ensure_screen()
        if _state.screen_target != INVALID_RENDER_TARGET do return _bind_target(_state.screen_target)
    }
    if target != INVALID_RENDER_TARGET {
        i := int(target.idx) - 1
        if i >= 0 && i < len(_state.targets) && _state.targets[i].fbo != 0 {
            t := _state.targets[i]
            gl.BindFramebuffer(gl.FRAMEBUFFER, t.fbo)
            gl.Viewport(0, 0, i32(t.width), i32(t.height))
            return t.width, t.height
        }
    }

    // bind fbo 0 first so an invalid or destroyed target cant leave some other FBO bound
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
        _blend_over()
    case .Additive:
        gl.Enable(gl.BLEND)
        _blend_additive()
    case .Premultiplied:
        gl.Enable(gl.BLEND)
        gl.BlendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
    }
}

@(private="file")
_retained :: proc() -> bool {
    return true
}

@(private="file")
_clear :: proc(target: Render_Target, color: common.Color, scissor: Maybe(common.Rect) = nil) {
    _, target_h := _bind_target(target)
    if r, ok := scissor.?; ok {
        gl.Enable(gl.SCISSOR_TEST)
        gl.Scissor(i32(r.x), max(i32(target_h) - i32(r.y) - i32(r.h), 0), i32(r.w), i32(r.h))
    } else {
        gl.Disable(gl.SCISSOR_TEST)
    }
    alpha := f32(color[3]) / 255
    gl.ClearColor(common.srgb_to_linear(f32(color[0]) / 255) * alpha, common.srgb_to_linear(f32(color[1]) / 255) * alpha, common.srgb_to_linear(f32(color[2]) / 255) * alpha, alpha)
    gl.Clear(u32(gl.COLOR_BUFFER_BIT))
}

@(private="file")
_ensure_screen :: proc() {
    w, h := _state.width, _state.height
    if w <= 0 || h <= 0 do return
    if int(_state.screen_target.w) == w && int(_state.screen_target.h) == h do return
    if _state.screen_target != INVALID_RENDER_TARGET {
        // reuse the handles while resizing, or window drags pile up target slots
        tex := &_state.textures[int(_state.screen_texture) - 1]
        rt := &_state.targets[int(_state.screen_target.idx) - 1]
        gl.BindTexture(gl.TEXTURE_2D, tex.id)
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.SRGB8_ALPHA8, i32(w), i32(h), 0, gl.RGBA, gl.UNSIGNED_BYTE, 0, nil)
        gl.BindRenderbuffer(gl.RENDERBUFFER, rt.stencil)
        gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, i32(w), i32(h))
        tex.width, tex.height = w, h
        rt.width, rt.height = w, h
        _state.screen_target.w, _state.screen_target.h = u32(w), u32(h)
        return
    }
    _state.screen_texture, _state.screen_target = _create_target(w, h)
}

@(private="file")
_present :: proc() {
    _ensure_screen()
    if _state.screen_target != INVALID_RENDER_TARGET {
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Viewport(0, 0, i32(_state.width), i32(_state.height))
        gl.Disable(gl.SCISSOR_TEST)
        gl.Disable(gl.STENCIL_TEST)
        gl.Disable(gl.BLEND)
        gl.ColorMask(true, true, true, true)
        gl.UseProgram(_state.present_program)
        gl.ActiveTexture(gl.TEXTURE0)
        gl.BindTexture(gl.TEXTURE_2D, _state.textures[int(_state.screen_texture) - 1].id)
        gl.Uniform1i(gl.GetUniformLocation(_state.present_program, "u_tex"), 0)
        gl.BindVertexArray(_state.vao)
        gl.DrawArrays(gl.TRIANGLES, 0, 3)
        gl.Enable(gl.STENCIL_TEST)
        _blend(.Alpha)
    }
    if _state.glue.present != nil do _state.glue.present(_state.glue.state)
}

@(private="file")
_Clip_Slot :: enum { Quad, Robin, MSDF, Effect }
@(private="file")
_CLIP_UNIFORMS := [MAX_CLIP_EDGES][4]string{
    {"u_clip[0]", "u_clip_size[0]", "u_clip_radius[0]", "u_clip_radius_y[0]"}, {"u_clip[1]", "u_clip_size[1]", "u_clip_radius[1]", "u_clip_radius_y[1]"},
    {"u_clip[2]", "u_clip_size[2]", "u_clip_radius[2]", "u_clip_radius_y[2]"}, {"u_clip[3]", "u_clip_size[3]", "u_clip_radius[3]", "u_clip_radius_y[3]"},
}

@(private="file")
_apply_clip_edges :: proc(slot: _Clip_Slot, program: gl.Program, target: Render_Target, target_h: int) {
    if !_state.clip_loc_ready[slot] {
        _state.clip_count_loc[slot] = gl.GetUniformLocation(program, "u_clip_count")
        _state.clip_loc_ready[slot] = true
    }
    count := clip_edge_count if target == _state.layer else 0
    if count == 0 && _state.clip_count_sent[slot] == 0 do return
    _state.clip_count_sent[slot] = count
    gl.Uniform1i(_state.clip_count_loc[slot], i32(count))
    flip := common.Mat3x3{1, 0, 0, 0, -1, f32(target_h), 0, 0, 1}
    for i in 0 ..< count {
        gl.UniformMatrix3fv(gl.GetUniformLocation(program, _CLIP_UNIFORMS[i][0]), transmute(glm.mat3)(clip_edges[i].to_local * flip))
        gl.Uniform2f(gl.GetUniformLocation(program, _CLIP_UNIFORMS[i][1]), clip_edges[i].size.x, clip_edges[i].size.y)
        radius := clip_edges[i].radius
        gl.Uniform4f(gl.GetUniformLocation(program, _CLIP_UNIFORMS[i][2]), radius[0].x, radius[1].x, radius[2].x, radius[3].x)
        gl.Uniform4f(gl.GetUniformLocation(program, _CLIP_UNIFORMS[i][3]), radius[0].y, radius[1].y, radius[2].y, radius[3].y)
    }
}

// draw an already filled VAO with the quad program
@(private="file")
_draw_bound :: proc(
    target:    Render_Target,
    vao:       gl.VertexArrayObject,
    count:     int,
    texture:   Texture,
    scissor:   Maybe(common.Rect),
    blend:     Blend_Mode,
    transform: common.Mat3x3 = common.Mat3X3_IDENTITY,
) {
    w, h := _bind_target(target)
    _scissor(h, scissor)
    _blend(blend)

    gl.UseProgram(_state.program)
    _apply_clip_edges(.Quad, _state.program, target, int(h))
    gl.Uniform2f(_state.resolution, f32(w), f32(h))
    gl.UniformMatrix3fv(gl.GetUniformLocation(_state.program, "u_transform"), transmute(glm.mat3)transform)

    has_texture := false
    gl.ActiveTexture(gl.TEXTURE0)
    if id, ok := _texture_id(texture); ok {
        gl.BindTexture(gl.TEXTURE_2D, id)
        has_texture = true
    } else {
        // presentation leave the screen texture bound, unbind it so we never sample a bound draw attachment
        gl.BindTexture(gl.TEXTURE_2D, 0)
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

// get the backend storage of a mesh, made on first use
@(private="file")
_resolve_mesh :: proc(
    idx:    ^u32,
    meshes: ^[dynamic]Web_Mesh,
    stride: int,
    layout: proc(stride: int) = _vertex_layout,
) -> ^Web_Mesh {
    if idx^ == 0 {
        mesh := Web_Mesh{
            vao = gl.CreateVertexArray(),
            vbo = gl.CreateBuffer(),
            ibo = gl.CreateBuffer(),
        }
        gl.BindVertexArray(mesh.vao)
        gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ibo)
        layout(stride)

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
    target:    Render_Target,
    mesh:      ^Mesh,
    vertices:  []Vertex,
    indices:   []u32,
    version:   u64,
    transform: common.Mat3x3,
    texture:   Texture,
    scissor:   Maybe(common.Rect),
    blend:     Blend_Mode,
) {
    if mesh == nil do return

    m := _resolve_mesh(&mesh.idx, &_state.meshes, size_of(Vertex), _quad_vertex_layout)
    if m == nil do return

    if mesh.version != version {
        if len(vertices) == 0 || len(indices) == 0 do return
        _upload_mesh(m, raw_data(vertices), len(vertices) * size_of(Vertex), indices)
        mesh.version = version
    }
    if m.count == 0 do return

    _draw_bound(target, m.vao, m.count, texture, scissor, blend, transform)
}

// the desktop curve renderer need samplerBuffer which WebGL2 dont have
// browser text use the MSDF path below, so these entries do nothing

@(private="file")
_draw_glyphs :: proc(
    target:    Render_Target,
    vertices:  []Glyph_Vertex,
    indices:   []u32,
    curves:    [][2]f32,
    version:   u64,
    transform: common.Mat3x3,
    scissor:   Maybe(common.Rect),
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
_draw_robin_mesh :: proc(
    target:           Render_Target,
    mesh:             ^Glyph_Mesh,
    vertices:         []Glyph_Vertex,
    indices:          []u32,
    geometry_version: u64,
    transform:        common.Mat3x3,
    data:             [][2]f32,
    data_version:     u64,
    scissor:          Maybe(common.Rect),
) {
    when !WEB_ROBIN_ENABLED do return
    if mesh == nil do return

    m := _resolve_mesh(&mesh.idx, &_state.robin_meshes, size_of(Glyph_Vertex), _robin_vertex_layout)
    if m == nil do return

    if mesh.version != geometry_version {
        if len(vertices) == 0 || len(indices) == 0 do return
        _upload_mesh(m, raw_data(vertices), len(vertices) * size_of(Glyph_Vertex), indices)
        mesh.version = geometry_version
    }
    if m.count == 0 do return

    w, h := _bind_target(target)
    _scissor(h, scissor)
    _blend(.Alpha)

    if _state.robin_data_version != data_version && len(data) > 0 {
        required_rows := (len(data) + WEB_ROBIN_ATLAS_WIDTH - 1) / WEB_ROBIN_ATLAS_WIDTH
        atlas_height := 1
        for atlas_height < required_rows do atlas_height *= 2
        if atlas_height > _max_texture_size() do return

        gl.BindTexture(gl.TEXTURE_2D, _state.robin_tex)
        if _state.robin_atlas_width != WEB_ROBIN_ATLAS_WIDTH ||
           _state.robin_atlas_height != atlas_height {
            gl.TexImage2D(
                gl.TEXTURE_2D, 0, gl.RG32F, WEB_ROBIN_ATLAS_WIDTH, i32(atlas_height),
                0, gl.RG, gl.FLOAT, 0, nil,
            )
            _state.robin_atlas_width = WEB_ROBIN_ATLAS_WIDTH
            _state.robin_atlas_height = atlas_height
        }
        padded := make([][2]f32, WEB_ROBIN_ATLAS_WIDTH * atlas_height, context.temp_allocator)
        copy(padded, data)
        gl.TexSubImage2D(
            gl.TEXTURE_2D, 0, 0, 0, WEB_ROBIN_ATLAS_WIDTH, i32(atlas_height),
            gl.RG, gl.FLOAT, len(padded) * size_of([2]f32), raw_data(padded),
        )
        _state.robin_data_version = data_version
    }

    gl.UseProgram(_state.robin_program)
    _apply_clip_edges(.Robin, _state.robin_program, target, int(h))
    gl.Uniform2f(_state.robin_resolution, f32(w), f32(h))
    gl.UniformMatrix3fv(_state.robin_transform, transmute(glm.mat3)transform)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, _state.robin_tex)
    gl.Uniform1i(_state.robin_data, 0)
    gl.Uniform1i(_state.robin_data_width, i32(_state.robin_atlas_width))

    gl.BindVertexArray(m.vao)
    gl.DrawElements(gl.TRIANGLES, m.count, gl.UNSIGNED_INT, nil)
}

@(private="file")
_max_texture_size :: proc() -> int {
    if _state.max_texture_size == 0 {
        v := gl.GetParameter(gl.MAX_TEXTURE_SIZE)
        _state.max_texture_size = int(v) if v > 0 else 2048
    }
    return _state.max_texture_size
}

@(private="file")
_draw_msdf :: proc(
    target:      Render_Target,
    mesh:        ^Glyph_Mesh,
    vertices:    []Glyph_Vertex,
    indices:     []u32,
    version:     u64,
    transform:   common.Mat3x3,
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
    _apply_clip_edges(.MSDF, _state.msdf_program, target, int(h))
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

// get the live GL texture behind a handle
// ok is false when the handle is out of range or already destroyed
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
    // WebGL2 sRGB attachments decode for sampling and blend in linear light by themselves
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.SRGB8_ALPHA8, i32(width), i32(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, 0, nil)

    fbo := gl.CreateFramebuffer()
    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, _state.textures[int(tex) - 1].id, 0)
    stencil := gl.CreateRenderbuffer()
    gl.BindRenderbuffer(gl.RENDERBUFFER, stencil)
    gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, i32(width), i32(height))
    gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, stencil)
    assert(gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE, "incomplete sRGB render target")

    append(&_state.targets, Web_Target{
        fbo           = fbo,
        stencil       = stencil,
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
    if _state.targets[i].stencil != 0 do gl.DeleteRenderbuffer(_state.targets[i].stencil)
    _state.targets[i].fbo = 0
    _state.targets[i].stencil = 0
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
    // read the encoded premultiplied frame the canvas got
    if target == INVALID_RENDER_TARGET do gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    data := make([]u8, w * h * 4, allocator)
    gl.ReadnPixels(0, 0, i32(w), i32(h), gl.RGBA, gl.UNSIGNED_BYTE, len(data), raw_data(data))

    // GL rows are bottom-up, flip them to top-left origin
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
    // the frame's clear may have left a scissor on, and the stencil must be cleared whole
    gl.Disable(gl.SCISSOR_TEST)
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

@(private="file")
_layer_begin :: proc(target: Render_Target) -> int {
    token := _state.stencil_depth
    _state.stencil_depth = 0
    _state.layer = target
    _bind_target(target)
    gl.Disable(gl.SCISSOR_TEST)
    gl.ColorMask(true, true, true, true)
    gl.StencilMask(0xff)
    gl.ClearColor(0, 0, 0, 0)
    gl.ClearStencil(0)
    gl.Clear(u32(gl.COLOR_BUFFER_BIT) | u32(gl.STENCIL_BUFFER_BIT))
    gl.StencilMask(0)
    gl.StencilFunc(gl.ALWAYS, 0, 0)
    return token
}

@(private="file")
_layer_end :: proc(parent: Render_Target, token: int) {
    _state.layer = parent
    _state.stencil_depth = token + 1
    _bind_target(parent)
    _stencil_pop()
}

@(private="file")
_draw_effect :: proc(
    target:   Render_Target,
    source:   Texture,
    vertices: [4]Vertex,
    effect:   Effect,
    scissor:  Maybe(common.Rect),
    blend:    Blend_Mode,
) {
    id, ok := _texture_id(source)
    if !ok do return
    w, h := _bind_target(target)
    _scissor(h, scissor)
    _blend(blend)

    program := _state.effect_program
    gl.UseProgram(program)
    _apply_clip_edges(.Effect, program, target, int(h))
    gl.Uniform2f(gl.GetUniformLocation(program, "u_resolution"), f32(w), f32(h))
    gl.UniformMatrix3fv(gl.GetUniformLocation(program, "u_transform"), transmute(glm.mat3)common.Mat3X3_IDENTITY)
    color: glm.mat4
    for row in 0 ..< 4 {
        for column in 0 ..< 4 do color[row, column] = effect.color[row][column]
    }
    gl.UniformMatrix4fv(gl.GetUniformLocation(program, "u_color"), color)
    gl.Uniform4f(gl.GetUniformLocation(program, "u_offset"), effect.offset[0], effect.offset[1], effect.offset[2], effect.offset[3])
    gl.Uniform2f(gl.GetUniformLocation(program, "u_step"), effect.step.x, effect.step.y)
    gl.Uniform1i(gl.GetUniformLocation(program, "u_taps"), i32(min(effect.taps, MAX_EFFECT_TAPS)))
    gl.Uniform1f(gl.GetUniformLocation(program, "u_sigma"), max(effect.sigma, 0.001))
    gl.Uniform4f(gl.GetUniformLocation(program, "u_tint"), effect.tint[0], effect.tint[1], effect.tint[2], effect.tint[3])
    gl.Uniform1i(gl.GetUniformLocation(program, "u_shadow"), 1 if effect.shadow else 0)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, id)
    gl.Uniform1i(gl.GetUniformLocation(program, "u_tex"), 0)

    quad := vertices
    indices := [6]u32{0, 1, 2, 0, 2, 3}
    gl.BindVertexArray(_state.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, _state.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(quad), &quad[0], gl.STREAM_DRAW)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, _state.ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices[0], gl.STREAM_DRAW)
    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)
    _blend(.Alpha)
}

RENDERER_WEBGL :: Renderer {
    layer_begin           = _layer_begin,
    layer_end             = _layer_end,
    draw_effect           = _draw_effect,
    create_state          = _create_state,
    free_state            = _free_state,
    init                  = _init,
    shutdown              = _shutdown,
    get_active_state      = _get_active_state,
    set_active_state      = _set_active_state,
    make_current          = _make_current,
    clear                 = _clear,
    retained              = _retained,
    present               = _present,
    draw                  = _draw,
    draw_mesh             = _draw_mesh,
    draw_glyphs           = _draw_glyphs,
    draw_glyph_mesh       = _draw_glyph_mesh,
    draw_robin_mesh       = _draw_robin_mesh,
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

@(private = "file")
_blend_over :: proc() {
    gl.BlendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
}

@(private = "file")
_blend_additive :: proc() {
    gl.BlendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
}
