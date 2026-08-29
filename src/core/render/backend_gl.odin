#+build !js
package render

import "core:math/linalg"
import "base:runtime"
import "core:fmt"
import gl "vendor:OpenGL"
import "src:core/common"

GL_ROBIN_ENABLED     :: #config(BANANA_TEXT_ROBIN_GPU_UNSAFE, true)
GL_ROBIN_ATLAS_WIDTH :: 1024

// OpenGL 3.3 core backend. Streams Vertex quads through a single VAO/VBO/IBO
// pair into a colored+textured shader. Stencil clipping uses a bit-stack
// (one GL stencil bit per nesting depth).
@(private="file")
GL_State :: struct {
    render: Render_Interface,

    using gl_program: GL_Program,
    vao, vbo, ibo: u32,

    swapchain_w:    int,
    swapchain_h:    int,
    stencil_depth:  int,
    textures:       [dynamic]GL_Texture,
    render_targets: [dynamic]GL_RT,
    meshes:         [dynamic]GL_Glyph_Mesh,

    using gl_glyph: GL_GLYPH_Program,
    glyph_vao, glyph_vbo, glyph_ibo: u32,
    glyph_meshes:                    [dynamic]GL_Glyph_Mesh,
    curve_buf, curve_tex:            u32,
    curves_version:                  u64,

    using gl_robin: GL_ROBIN_Program,
    robin_tex, robin_upload_buf:           u32,
    robin_atlas_width, robin_atlas_height: int,
    max_texture_size:                      int,
    robin_data_version:                    u64,

    using gl_msdf: GL_MSDF_Program,
}

@(private="file")
GL_Program :: struct #all_or_none {
    program:        u32,
    loc_tex:        i32,
    loc_has_tex:    i32,
    loc_resolution: i32,
    loc_transform:  i32,
}

@(private="file")
GL_MSDF_Program :: struct #all_or_none {
    msdf_program:         u32,
    msdf_loc_resolution:  i32,
    msdf_loc_range:       i32,
    msdf_loc_u_transform: i32,
    msdf_loc_atlas:       i32,
}

@(private="file")
GL_GLYPH_Program :: struct #all_or_none {
    glyph_program:        u32,
    glyph_loc_v_curves:   i32,
    glyph_loc_resolution: i32,
    glyph_loc_transform:  i32,
}

@(private="file")
GL_ROBIN_Program :: struct #all_or_none {
    robin_program:        u32,
    robin_loc_data:       i32,
    robin_loc_data_width: i32,
    robin_loc_resolution: i32,
    robin_loc_transform:  i32,
}

@(private="file")
GL_RT :: struct {
    fbo:       u32,
    tex_index: int,
    width:     int,
    height:    int,
}

@(private="file")
GL_Texture :: struct {
    id:     u32,
    format: Pixel_Format,
    width:  int,
    height: int,
}

@(private="file")
GL_Glyph_Mesh :: struct {
    vao, vbo, ibo: u32,
    index_count:   int,
}

@(private="file", thread_local)
_state: ^GL_State

@(private="file")
VS_SOURCE :: string(#load("shaders/gl_quad.vert"))
@(private="file")
FS_SOURCE :: string(#load("shaders/gl_quad.frag"))

// Glyph pipeline: Adapted from GreenLightning/gpu-font-rendering (MIT).
@(private="file")
GLYPH_VS_SOURCE :: string(#load("shaders/gl_glyph.vert"))
@(private="file")
GLYPH_FS_SOURCE :: string(#load("shaders/gl_glyph.frag"))
@(private="file")
ROBIN_VS_SOURCE :: string(#load("shaders/gl_robin.vert"))
@(private="file")
ROBIN_FS_SOURCE :: string(#load("shaders/gl_robin.frag"))
// Mirrors text.ROBIN_GRID, which render cannot import (text depends on render).
// The value is also a #define in gl_robin.frag; all three must agree.
GL_ROBIN_GRID :: 16
@(private="file")
MSDF_VS_SOURCE :: string(#load("shaders/gl_msdf.vert"))
@(private="file")
MSDF_FS_SOURCE :: string(#load("shaders/gl_msdf.frag"))

@(private = "file")
_create_state :: proc(allocator: runtime.Allocator) -> rawptr {
    return new(GL_State, allocator)
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
    _state = cast(^GL_State)(state)
}

@(private="file")
_make_current :: proc() {
    if _state.render.make_current != nil do _state.render.make_current(_state.render.state)
}

@(private="file")
_load_proc :: proc(p: rawptr, name: cstring) {
    fn := _state.render.get_proc_address(_state.render.state, name)
    (cast(^rawptr)p)^ = fn
}

@(private="file")
_init :: proc(
	state:     rawptr,
	render:    Render_Interface,
	width:     int,
	height:    int,
	options:   Init_Options,
	allocator: runtime.Allocator,
) {
    _state = cast(^GL_State)(state)
    _state^ = GL_State{}
    _state.render = render
    _state.swapchain_w = width
    _state.swapchain_h = height
    _state.textures = make([dynamic]GL_Texture, 0, allocator)
    _state.render_targets = make([dynamic]GL_RT, 0, allocator)
    _state.meshes = make([dynamic]GL_Glyph_Mesh, 0, allocator)
    _state.glyph_meshes = make([dynamic]GL_Glyph_Mesh, 0, allocator)

    if !render.make_context(render.state, options) {
        panic("render backend 'gl': glue.make_context failed")
    }
    gl.load_up_to(3, 3, _load_proc)

    program, ok := gl.load_shaders_source(VS_SOURCE, FS_SOURCE)
    if !ok {
        compile_msg, _, link_msg, _ := gl.get_last_error_messages()
        panic(fmt.tprintf("render backend 'gl': shader compile failed\n%s\n%s", compile_msg, link_msg))
    }
    gl.UseProgram(program)
    _state.gl_program = {
        program        = program,
        loc_resolution = gl.GetUniformLocation(program, "u_resolution"),
        loc_transform  = gl.GetUniformLocation(program, "u_transform"),
        loc_has_tex    = gl.GetUniformLocation(program, "u_has_tex"),
        loc_tex        = gl.GetUniformLocation(program, "u_tex")
    }

    vaos: [1]u32
    gl.GenVertexArrays(1, &vaos[0])
    _state.vao = vaos[0]
    gl.BindVertexArray(_state.vao)

    bufs: [2]u32
    gl.GenBuffers(2, &bufs[0])
    _state.vbo = bufs[0]
    _state.ibo = bufs[1]
    gl.BindBuffer(gl.ARRAY_BUFFER, _state.vbo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, _state.ibo)

    stride := i32(size_of(Vertex))
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, stride, 16)
    gl.EnableVertexAttribArray(3)
    gl.VertexAttribIPointer(3, 1, gl.UNSIGNED_INT, stride, 20)

    glyph_program, glyph_ok := gl.load_shaders_source(GLYPH_VS_SOURCE, GLYPH_FS_SOURCE)
    if !glyph_ok {
        compile_msg, _, link_msg, _ := gl.get_last_error_messages()
        panic(fmt.tprintf("render backend 'gl': glyph shader compile failed\n%s\n%s", compile_msg, link_msg))
    }
    _state.gl_glyph = {
        glyph_program        = glyph_program,
        glyph_loc_resolution = gl.GetUniformLocation(glyph_program, "u_resolution"),
        glyph_loc_transform  = gl.GetUniformLocation(glyph_program, "u_transform"),
        glyph_loc_v_curves   = gl.GetUniformLocation(glyph_program, "v_curves")
    }

    when GL_ROBIN_ENABLED {
        robin_program, robin_ok := gl.load_shaders_source(ROBIN_VS_SOURCE, ROBIN_FS_SOURCE)
        if !robin_ok {
            compile_msg, _, link_msg, _ := gl.get_last_error_messages()
            panic(fmt.tprintf("render backend 'gl': ROBIN shader compile failed\n%s\n%s", compile_msg, link_msg))
        }
        _state.gl_robin = {
            robin_program        = robin_program,
            robin_loc_resolution = gl.GetUniformLocation(robin_program, "u_resolution"),
            robin_loc_transform  = gl.GetUniformLocation(robin_program, "u_transform"),
            robin_loc_data       = gl.GetUniformLocation(robin_program, "u_robin_data"),
            robin_loc_data_width = gl.GetUniformLocation(robin_program, "u_robin_data_width"),
        }
    }

    msdf_program, msdf_ok := gl.load_shaders_source(MSDF_VS_SOURCE, MSDF_FS_SOURCE)
    if !msdf_ok {
        compile_msg, _, link_msg, _ := gl.get_last_error_messages()
        panic(fmt.tprintf("render backend 'gl': MSDF shader compile failed\n%s\n%s", compile_msg, link_msg))
    }
    _state.gl_msdf = {
        msdf_program         = msdf_program,
        msdf_loc_resolution  = gl.GetUniformLocation(msdf_program, "u_resolution"),
        msdf_loc_range       = gl.GetUniformLocation(msdf_program, "u_px_range"),
        msdf_loc_u_transform = gl.GetUniformLocation(msdf_program, "u_transform"),
        msdf_loc_atlas       = gl.GetUniformLocation(msdf_program, "u_atlas")
    }

    glyph_vaos: [1]u32
    gl.GenVertexArrays(1, &glyph_vaos[0])
    _state.glyph_vao = glyph_vaos[0]
    gl.BindVertexArray(_state.glyph_vao)

    glyph_bufs: [3]u32
    gl.GenBuffers(3, &glyph_bufs[0])
    _state.glyph_vbo = glyph_bufs[0]
    _state.glyph_ibo = glyph_bufs[1]
    _state.curve_buf = glyph_bufs[2]
    gl.BindBuffer(gl.ARRAY_BUFFER, _state.glyph_vbo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, _state.glyph_ibo)

    glyph_stride := i32(size_of(Glyph_Vertex))
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, false, glyph_stride, 0)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, false, glyph_stride, 8)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, glyph_stride, 16)
    gl.EnableVertexAttribArray(3)
    gl.VertexAttribIPointer(3, 2, gl.UNSIGNED_INT, glyph_stride, 20)

    curve_texs: [1]u32
    gl.GenTextures(1, &curve_texs[0])
    _state.curve_tex = curve_texs[0]
    when GL_ROBIN_ENABLED {
        robin_texs: [1]u32
        robin_upload_bufs: [1]u32
        gl.GenTextures(1, &robin_texs[0])
        gl.GenBuffers(1, &robin_upload_bufs[0])
        _state.robin_tex = robin_texs[0]
        _state.robin_upload_buf = robin_upload_bufs[0]
        gl.BindTexture(gl.TEXTURE_2D, _state.robin_tex)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.NEAREST))
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.NEAREST))
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))
    }

    gl.BindBuffer(gl.TEXTURE_BUFFER, _state.curve_buf)
    gl.BindTexture(gl.TEXTURE_BUFFER, _state.curve_tex)
    gl.TexBuffer(gl.TEXTURE_BUFFER, gl.RG32F, _state.curve_buf)

    gl.BindVertexArray(_state.vao)

    gl.Enable(gl.BLEND)
    _blend_over()
    gl.Enable(gl.STENCIL_TEST)
    if options.msaa_samples > 1 do gl.Enable(gl.MULTISAMPLE)
}

@(private="file")
_gl_max_texture_size :: proc() -> int {
    if _state.max_texture_size == 0 {
        v: i32
        gl.GetIntegerv(gl.MAX_TEXTURE_SIZE, &v)
        _state.max_texture_size = int(v) if v > 0 else 2048
    }
    return _state.max_texture_size
}

@(private="file")
_shutdown :: proc() {
    if _state == nil do return
    gl.Finish()
    gl.UseProgram(0)
    gl.BindVertexArray(0)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, 0)
    gl.BindTexture(gl.TEXTURE_BUFFER, 0)
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)
    gl.BindBuffer(gl.TEXTURE_BUFFER, 0)
    del_vao := [2]u32{_state.vao, _state.glyph_vao}
    gl.DeleteVertexArrays(2, &del_vao[0])
    del_ctex := [2]u32{_state.curve_tex, _state.robin_tex}
    gl.DeleteTextures(2, &del_ctex[0])
    del_buf := [6]u32{_state.vbo, _state.ibo, _state.glyph_vbo, _state.glyph_ibo, _state.curve_buf, _state.robin_upload_buf}
    gl.DeleteBuffers(6, &del_buf[0])
    if _state.program != 0 do gl.DeleteProgram(_state.program)
    if _state.glyph_program != 0 do gl.DeleteProgram(_state.glyph_program)
    if _state.robin_program != 0 do gl.DeleteProgram(_state.robin_program)
    if _state.msdf_program != 0 do gl.DeleteProgram(_state.msdf_program)
    for mesh in _state.glyph_meshes {
        if mesh.vao != 0 {
            ids := [1]u32{mesh.vao}
            gl.DeleteVertexArrays(1, &ids[0])
        }
        ids := [2]u32{mesh.vbo, mesh.ibo}
        gl.DeleteBuffers(2, &ids[0])
    }
    for mesh in _state.meshes {
        if mesh.vao != 0 {
            ids := [1]u32{mesh.vao}
            gl.DeleteVertexArrays(1, &ids[0])
        }
        ids := [2]u32{mesh.vbo, mesh.ibo}
        gl.DeleteBuffers(2, &ids[0])
    }
    for texture in _state.textures {
        if texture.id == 0 do continue
        del := [1]u32{texture.id}
        gl.DeleteTextures(1, &del[0])
    }
    for rt in _state.render_targets {
        del := [1]u32{rt.fbo}
        gl.DeleteFramebuffers(1, &del[0])
    }
    delete(_state.textures)
    delete(_state.render_targets)
    delete(_state.glyph_meshes)
    delete(_state.meshes)
}

@(private="file")
_clear :: proc(target: Render_Target, color: common.Color) {
    _bind_target(target)
    gl.Disable(gl.SCISSOR_TEST)
    gl.ClearColor(f32(color[0]) / 255, f32(color[1]) / 255, f32(color[2]) / 255, f32(color[3]) / 255)
    gl.Clear(gl.COLOR_BUFFER_BIT)
}

@(private="file")
_present :: proc() {
    when common.GPU_SYNC {
        gpu_start := common.profile_begin(.GPU_Wait)
        gl.Finish()
        common.profile_end(.GPU_Wait, gpu_start)
    }
    _state.render.present(_state.render.state)
}

@(private="file")
_stream_buffer :: proc(target: u32, size: int, data: rawptr) {
    if size <= 0 do return
    gl.BufferData(target, size, nil, gl.STREAM_DRAW)
    gl.BufferSubData(target, 0, size, data)
}

@(private="file")
_upload_buffer :: proc(target: u32, size: int, data: rawptr) {
    if size <= 0 do return
    gl.BufferData(target, size, data, gl.STATIC_DRAW)
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
    target_w, target_h := _bind_target(target)

    if r, ok := scissor.?; ok {
        y_bottom := i32(target_h) - i32(r.y) - i32(r.h)
        if y_bottom < 0 do y_bottom = 0
        gl.Enable(gl.SCISSOR_TEST)
        gl.Scissor(i32(r.x), y_bottom, i32(r.w), i32(r.h))
    } else {
        gl.Disable(gl.SCISSOR_TEST)
    }

    switch blend {
    case .Opaque:   gl.Disable(gl.BLEND)
    case .Alpha:    gl.Enable(gl.BLEND); _blend_over()
    case .Additive: gl.Enable(gl.BLEND); _blend_additive()
    }

    gl.UseProgram(_state.program)
    gl.Uniform2f(_state.loc_resolution, f32(target_w), f32(target_h))
    identity := common.Mat3X3_IDENTITY
    gl.UniformMatrix3fv(_state.loc_transform, 1, false, &identity[0,0])

    has_tex: bool
    if texture != INVALID_TEXTURE && int(texture) - 1 < len(_state.textures) {
        tex := _state.textures[int(texture) - 1]
        if tex.id != 0 {
            gl.ActiveTexture(gl.TEXTURE0)
            gl.BindTexture(gl.TEXTURE_2D, tex.id)
            gl.Uniform1i(_state.loc_tex, 0)
            has_tex = true
        }
    }
    gl.Uniform1i(_state.loc_has_tex, has_tex ? 1 : 0)

    gl.BindVertexArray(_state.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, _state.vbo)
    _stream_buffer(gl.ARRAY_BUFFER, len(vertices) * size_of(Vertex), &vertices[0])
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, _state.ibo)
    _stream_buffer(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), &indices[0])
    gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_INT, nil)
}

@(private="file")
_draw_mesh :: proc(
    target:           Render_Target,
    mesh:             ^Mesh,
    vertices:         []Vertex,
    indices:          []u32,
    geometry_version: u64,
    transform:        common.Mat3x3,
    texture:          Texture,
    scissor:          Maybe(common.Rect),
    blend:            Blend_Mode,
) {
    if mesh == nil do return

    if mesh.idx == 0 {
        vaos: [1]u32
        bufs: [2]u32
        gl.GenVertexArrays(1, &vaos[0])
        gl.GenBuffers(2, &bufs[0])

        gl.BindVertexArray(vaos[0])
        gl.BindBuffer(gl.ARRAY_BUFFER, bufs[0])
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, bufs[1])

        stride := i32(size_of(Vertex))
        gl.EnableVertexAttribArray(0)
        gl.VertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0)
        gl.EnableVertexAttribArray(1)
        gl.VertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8)
        gl.EnableVertexAttribArray(2)
        gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, stride, 16)
        gl.EnableVertexAttribArray(3)
        gl.VertexAttribIPointer(3, 1, gl.UNSIGNED_INT, stride, 20)

        append(&_state.meshes, GL_Glyph_Mesh{vao = vaos[0], vbo = bufs[0], ibo = bufs[1]})
        mesh.idx = u32(len(_state.meshes))
    }

    mi := int(mesh.idx) - 1
    if mi < 0 || mi >= len(_state.meshes) do return
    gm := &_state.meshes[mi]

    if mesh.version != geometry_version {
        if len(vertices) == 0 || len(indices) == 0 do return

        gl.BindVertexArray(gm.vao)
        gl.BindBuffer(gl.ARRAY_BUFFER, gm.vbo)
        _upload_buffer(gl.ARRAY_BUFFER, len(vertices) * size_of(Vertex), &vertices[0])
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gm.ibo)
        _upload_buffer(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), &indices[0])

        gm.index_count = len(indices)
        mesh.version = geometry_version
    }
    if gm.index_count == 0 do return

    target_w, target_h := _bind_target(target)

    if r, ok := scissor.?; ok {
        y := i32(target_h) - i32(r.y) - i32(r.h)
        if y < 0 do y = 0
        gl.Enable(gl.SCISSOR_TEST)
        gl.Scissor(i32(r.x), y, i32(r.w), i32(r.h))
    } else {
        gl.Disable(gl.SCISSOR_TEST)
    }

    switch blend {
    case .Opaque:
        gl.Disable(gl.BLEND)
    case .Alpha:
        gl.Enable(gl.BLEND)
        _blend_over()
    case .Additive:
        gl.Enable(gl.BLEND)
        _blend_additive()
    }

    gl.UseProgram(_state.program)
    gl.Uniform2f(_state.loc_resolution, f32(target_w), f32(target_h))
    matrix_values := transmute([9]f32)transform
    gl.UniformMatrix3fv(_state.loc_transform, 1, false, &matrix_values[0])

    has_tex := false
    if texture != INVALID_TEXTURE && int(texture) - 1 < len(_state.textures) {
        tex := _state.textures[int(texture) - 1]
        if tex.id != 0 {
            gl.ActiveTexture(gl.TEXTURE0)
            gl.BindTexture(gl.TEXTURE_2D, tex.id)
            gl.Uniform1i(_state.loc_tex, 0)
            has_tex = true
        }
    }
    gl.Uniform1i(_state.loc_has_tex, has_tex ? 1 : 0)

    gl.BindVertexArray(gm.vao)
    gl.DrawElements(gl.TRIANGLES, i32(gm.index_count), gl.UNSIGNED_INT, nil)
    gl.BindVertexArray(_state.vao)
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
    if len(vertices) == 0 || len(indices) == 0 do return
    target_w, target_h := _bind_target(target)

    if r, ok := scissor.?; ok {
        y_bottom := i32(target_h) - i32(r.y) - i32(r.h)
        if y_bottom < 0 do y_bottom = 0
        gl.Enable(gl.SCISSOR_TEST)
        gl.Scissor(i32(r.x), y_bottom, i32(r.w), i32(r.h))
    } else {
        gl.Disable(gl.SCISSOR_TEST)
    }

    gl.Enable(gl.BLEND)
    _blend_over()

    if _state.curves_version != curves_version && len(curves) > 0 {
        gl.BindBuffer(gl.TEXTURE_BUFFER, _state.curve_buf)
        _upload_buffer(gl.TEXTURE_BUFFER, len(curves) * size_of([2]f32), &curves[0])
        // Re-attach: some drivers latch the buffer store present at TexBuffer time.
        gl.BindTexture(gl.TEXTURE_BUFFER, _state.curve_tex)
        gl.TexBuffer(gl.TEXTURE_BUFFER, gl.RG32F, _state.curve_buf)
        _state.curves_version = curves_version
    }

    gl.UseProgram(_state.glyph_program)
    gl.Uniform2f(_state.glyph_loc_resolution, f32(target_w), f32(target_h))
    matrix_values := transmute([9]f32)transform
    gl.UniformMatrix3fv(_state.glyph_loc_transform, 1, false, &matrix_values[0])
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_BUFFER, _state.curve_tex)
    gl.Uniform1i(_state.glyph_loc_v_curves, 0)

    gl.BindVertexArray(_state.glyph_vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, _state.glyph_vbo)
    _stream_buffer(gl.ARRAY_BUFFER, len(vertices) * size_of(Glyph_Vertex), &vertices[0])
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, _state.glyph_ibo)
    _stream_buffer(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), &indices[0])
    gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_INT, nil)
    gl.BindVertexArray(_state.vao)
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
    if mesh == nil do return

    if mesh.idx == 0 {
        vaos: [1]u32
        bufs: [2]u32
        gl.GenVertexArrays(1, &vaos[0])
        gl.GenBuffers(2, &bufs[0])
        gl.BindVertexArray(vaos[0])
        gl.BindBuffer(gl.ARRAY_BUFFER, bufs[0])
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, bufs[1])

        stride := i32(size_of(Glyph_Vertex))
        gl.EnableVertexAttribArray(0)
        gl.VertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0)
        gl.EnableVertexAttribArray(1)
        gl.VertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8)
        gl.EnableVertexAttribArray(2)
        gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, stride, 16)
        gl.EnableVertexAttribArray(3)
        gl.VertexAttribIPointer(3, 2, gl.UNSIGNED_INT, stride, 20)

        append(&_state.glyph_meshes, GL_Glyph_Mesh{vao = vaos[0], vbo = bufs[0], ibo = bufs[1]})
        mesh.idx = u32(len(_state.glyph_meshes))
    }

    mi := int(mesh.idx) - 1
    if mi < 0 || mi >= len(_state.glyph_meshes) do return
    gm := &_state.glyph_meshes[mi]
    if mesh.version != geometry_version {
        if len(vertices) == 0 || len(indices) == 0 do return
        gl.BindVertexArray(gm.vao)
        gl.BindBuffer(gl.ARRAY_BUFFER, gm.vbo)
        _upload_buffer(gl.ARRAY_BUFFER, len(vertices) * size_of(Glyph_Vertex), &vertices[0])
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gm.ibo)
        _upload_buffer(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), &indices[0])
        gm.index_count = len(indices)
        mesh.version = geometry_version
    }
    if gm.index_count == 0 do return

    target_w, target_h := _bind_target(target)
    if r, ok := scissor.?; ok {
        y_bottom := i32(target_h) - i32(r.y) - i32(r.h)
        if y_bottom < 0 do y_bottom = 0
        gl.Enable(gl.SCISSOR_TEST)
        gl.Scissor(i32(r.x), y_bottom, i32(r.w), i32(r.h))
    } else {
        gl.Disable(gl.SCISSOR_TEST)
    }
    gl.Enable(gl.BLEND)
    _blend_over()

    if _state.curves_version != curves_version && len(curves) > 0 {
        gl.BindBuffer(gl.TEXTURE_BUFFER, _state.curve_buf)
        _upload_buffer(gl.TEXTURE_BUFFER, len(curves) * size_of([2]f32), &curves[0])
        gl.BindTexture(gl.TEXTURE_BUFFER, _state.curve_tex)
        gl.TexBuffer(gl.TEXTURE_BUFFER, gl.RG32F, _state.curve_buf)
        _state.curves_version = curves_version
    }

    gl.UseProgram(_state.glyph_program)
    gl.Uniform2f(_state.glyph_loc_resolution, f32(target_w), f32(target_h))
    matrix_values := transmute([9]f32)transform
    gl.UniformMatrix3fv(_state.glyph_loc_transform, 1, false, &matrix_values[0])
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_BUFFER, _state.curve_tex)
    gl.Uniform1i(_state.glyph_loc_v_curves, 0)
    gl.BindVertexArray(gm.vao)
    gl.DrawElements(gl.TRIANGLES, i32(gm.index_count), gl.UNSIGNED_INT, nil)
    gl.BindVertexArray(_state.vao)
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
    if mesh == nil do return
    if !GL_ROBIN_ENABLED do return

    if mesh.idx == 0 {
        vaos: [1]u32
        bufs: [2]u32
        gl.GenVertexArrays(1, &vaos[0])
        gl.GenBuffers(2, &bufs[0])
        gl.BindVertexArray(vaos[0])
        gl.BindBuffer(gl.ARRAY_BUFFER, bufs[0])
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, bufs[1])

        stride := i32(size_of(Glyph_Vertex))
        gl.EnableVertexAttribArray(0)
        gl.VertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0)
        gl.EnableVertexAttribArray(1)
        gl.VertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8)
        gl.EnableVertexAttribArray(2)
        gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, stride, 16)
        gl.EnableVertexAttribArray(3)
        gl.VertexAttribIPointer(3, 2, gl.UNSIGNED_INT, stride, 20)

        append(&_state.glyph_meshes, GL_Glyph_Mesh{vao = vaos[0], vbo = bufs[0], ibo = bufs[1]})
        mesh.idx = u32(len(_state.glyph_meshes))
    }

    mi := int(mesh.idx) - 1
    if mi < 0 || mi >= len(_state.glyph_meshes) do return
    gm := &_state.glyph_meshes[mi]
    if mesh.version != geometry_version {
        if len(vertices) == 0 || len(indices) == 0 do return
        gl.BindVertexArray(gm.vao)
        gl.BindBuffer(gl.ARRAY_BUFFER, gm.vbo)
        _upload_buffer(gl.ARRAY_BUFFER, len(vertices) * size_of(Glyph_Vertex), &vertices[0])
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gm.ibo)
        _upload_buffer(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), &indices[0])
        gm.index_count = len(indices)
        mesh.version = geometry_version
    }
    if gm.index_count == 0 do return

    target_w, target_h := _bind_target(target)
    if r, ok := scissor.?; ok {
        y_bottom := i32(target_h) - i32(r.y) - i32(r.h)
        if y_bottom < 0 do y_bottom = 0
        gl.Enable(gl.SCISSOR_TEST)
        gl.Scissor(i32(r.x), y_bottom, i32(r.w), i32(r.h))
    } else {
        gl.Disable(gl.SCISSOR_TEST)
    }
    gl.Enable(gl.BLEND)
    _blend_over()

    if _state.robin_data_version != data_version && len(data) > 0 {
        required_rows := (len(data) + GL_ROBIN_ATLAS_WIDTH - 1) / GL_ROBIN_ATLAS_WIDTH
        atlas_height := 1
        for atlas_height < required_rows do atlas_height *= 2
        // Growing past GL_MAX_TEXTURE_SIZE makes TexImage2D fail while the
        // TexSubImage2D calls below still write a full-size upload.
        if atlas_height > _gl_max_texture_size() do return
        gl.BindTexture(gl.TEXTURE_2D, _state.robin_tex)
        if _state.robin_atlas_width != GL_ROBIN_ATLAS_WIDTH ||
        _state.robin_atlas_height != atlas_height {
            gl.TexImage2D(
                gl.TEXTURE_2D, 0, i32(gl.RG32F), GL_ROBIN_ATLAS_WIDTH, i32(atlas_height),
                0, gl.RG, gl.FLOAT, nil,
            )
            _state.robin_atlas_width = GL_ROBIN_ATLAS_WIDTH
            _state.robin_atlas_height = atlas_height
        }
        full_rows := len(data) / GL_ROBIN_ATLAS_WIDTH
        if full_rows > 0 {
            gl.TexSubImage2D(
                gl.TEXTURE_2D, 0, 0, 0, GL_ROBIN_ATLAS_WIDTH, i32(full_rows),
                gl.RG, gl.FLOAT, &data[0],
            )
        }
        remainder := len(data) - full_rows * GL_ROBIN_ATLAS_WIDTH
        if remainder > 0 {
            gl.TexSubImage2D(
                gl.TEXTURE_2D, 0, 0, i32(full_rows), i32(remainder), 1,
                gl.RG, gl.FLOAT, &data[full_rows * GL_ROBIN_ATLAS_WIDTH],
            )
        }
        _state.robin_data_version = data_version
    }
    gl.UseProgram(_state.robin_program)
    gl.Uniform2f(_state.robin_loc_resolution, f32(target_w), f32(target_h))
    matrix_values := transmute([9]f32)transform
    gl.UniformMatrix3fv(_state.robin_loc_transform, 1, false, &matrix_values[0])
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, _state.robin_tex)
    gl.Uniform1i(_state.robin_loc_data, 0)
    gl.Uniform1i(_state.robin_loc_data_width, i32(_state.robin_atlas_width))
    gl.BindVertexArray(gm.vao)
    gl.DrawElements(gl.TRIANGLES, i32(gm.index_count), gl.UNSIGNED_INT, nil)
    gl.BindVertexArray(_state.vao)
}

@(private="file")
_draw_msdf_mesh :: proc(
    target:           Render_Target,
    mesh:             ^Glyph_Mesh,
    vertices:         []Glyph_Vertex,
    indices:          []u32,
    geometry_version: u64,
    transform:        common.Mat3x3,
    atlas:            Texture,
    pixel_range:      f32,
    scissor:          Maybe(common.Rect),
) {
    if mesh == nil || atlas == INVALID_TEXTURE do return
    ti := int(atlas) - 1
    if ti < 0 || ti >= len(_state.textures) || _state.textures[ti].id == 0 do return

    if mesh.idx == 0 {
        vaos: [1]u32
        bufs: [2]u32
        gl.GenVertexArrays(1, &vaos[0])
        gl.GenBuffers(2, &bufs[0])
        gl.BindVertexArray(vaos[0])
        gl.BindBuffer(gl.ARRAY_BUFFER, bufs[0])
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, bufs[1])
        stride := i32(size_of(Glyph_Vertex))
        gl.EnableVertexAttribArray(0)
        gl.VertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0)
        gl.EnableVertexAttribArray(1)
        gl.VertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8)
        gl.EnableVertexAttribArray(2)
        gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, stride, 16)
        append(&_state.glyph_meshes, GL_Glyph_Mesh{vao = vaos[0], vbo = bufs[0], ibo = bufs[1]})
        mesh.idx = u32(len(_state.glyph_meshes))
    }

    mi := int(mesh.idx) - 1
    if mi < 0 || mi >= len(_state.glyph_meshes) do return
    gm := &_state.glyph_meshes[mi]
    if mesh.version != geometry_version {
        if len(vertices) == 0 || len(indices) == 0 do return
        gl.BindVertexArray(gm.vao)
        gl.BindBuffer(gl.ARRAY_BUFFER, gm.vbo)
        _upload_buffer(gl.ARRAY_BUFFER, len(vertices) * size_of(Glyph_Vertex), &vertices[0])
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gm.ibo)
        _upload_buffer(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), &indices[0])
        gm.index_count = len(indices)
        mesh.version = geometry_version
    }
    if gm.index_count == 0 do return

    target_w, target_h := _bind_target(target)
    if r, ok := scissor.?; ok {
        y_bottom := i32(target_h) - i32(r.y) - i32(r.h)
        if y_bottom < 0 do y_bottom = 0
        gl.Enable(gl.SCISSOR_TEST)
        gl.Scissor(i32(r.x), y_bottom, i32(r.w), i32(r.h))
    } else {
        gl.Disable(gl.SCISSOR_TEST)
    }
    gl.Enable(gl.BLEND)
    _blend_over()
    gl.UseProgram(_state.msdf_program)
    gl.Uniform2f(_state.msdf_loc_resolution, f32(target_w), f32(target_h))
    matrix_values := linalg.matrix_flatten(transform)
    gl.UniformMatrix3fv(_state.msdf_loc_u_transform, 1, false, &matrix_values[0])
    gl.Uniform1f(_state.msdf_loc_range, pixel_range)
    gl.ActiveTexture(gl.TEXTURE0)
    gl.BindTexture(gl.TEXTURE_2D, _state.textures[ti].id)
    gl.Uniform1i(_state.msdf_loc_atlas, 0)
    gl.BindVertexArray(gm.vao)
    gl.DrawElements(gl.TRIANGLES, i32(gm.index_count), gl.UNSIGNED_INT, nil)
    gl.BindVertexArray(_state.vao)
}

@(private="file")
_create_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture {
    ids: [1]u32
    gl.GenTextures(1, &ids[0])
    tex := ids[0]
    gl.BindTexture(gl.TEXTURE_2D, tex)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(gl.LINEAR))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(gl.LINEAR))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, i32(gl.CLAMP_TO_EDGE))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, i32(gl.CLAMP_TO_EDGE))

    internal, layout_fmt, _ := _texture_format(format)
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    if format == .A8 {
        // GL_R8 samples as (r, 0, 0, 1); expose it as an alpha mask.
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_R, i32(gl.ONE))
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_G, i32(gl.ONE))
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_B, i32(gl.ONE))
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_A, i32(gl.RED))
    }
    pixels := len(data) > 0 ? &data[0] : nil
    gl.TexImage2D(gl.TEXTURE_2D, 0, i32(internal), i32(width), i32(height), 0, layout_fmt, gl.UNSIGNED_BYTE, pixels)
    append(&_state.textures, GL_Texture{id = tex, format = format, width = width, height = height})
    return Texture(len(_state.textures))
}

@(private="file")
_destroy_texture :: proc(handle: Texture) {
    i := int(handle) - 1
    if i < 0 || i >= len(_state.textures) do return
    if _state.textures[i].id == 0 do return
    del := [1]u32{_state.textures[i].id}
    gl.DeleteTextures(1, &del[0])
    _state.textures[i].id = 0
}

@(private="file")
_update_texture :: proc(handle: Texture, data: []u8, rect: common.Rect) -> bool {
    i := int(handle) - 1
    if len(data) == 0 do return false
    if i < 0 || i >= len(_state.textures) do return false
    texture := _state.textures[i]
    if texture.id == 0 do return false

    x, y := int(rect.x), int(rect.y)
    width, height := int(rect.w), int(rect.h)
    if x < 0 || y < 0 || width <= 0 || height <= 0 do return false
    if x + width > texture.width || y + height > texture.height do return false

    _, layout_fmt, channels := _texture_format(texture.format)
    if len(data) < width * height * channels do return false
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    gl.BindTexture(gl.TEXTURE_2D, texture.id)
    gl.TexSubImage2D(gl.TEXTURE_2D, 0, i32(x), i32(y), i32(width), i32(height), layout_fmt, gl.UNSIGNED_BYTE, &data[0])
    return true
}

@(private="file")
_set_texture_filter :: proc(handle: Texture, min, mag, mip: Texture_Filter) {
    i := int(handle) - 1
    if i < 0 || i >= len(_state.textures) do return
    if _state.textures[i].id == 0 do return
    gl.BindTexture(gl.TEXTURE_2D, _state.textures[i].id)
    min_v: u32 = min == .Nearest ? gl.NEAREST : gl.LINEAR
    mag_v: u32 = mag == .Nearest ? gl.NEAREST : gl.LINEAR
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, i32(min_v))
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, i32(mag_v))
}

@(private="file")
_upload_image :: proc(image: ^Image) -> Texture {
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
_unload_image :: proc(image: ^Image) {
    if image == nil || image.texture == INVALID_TEXTURE do return
    _destroy_texture(image.texture)
    image.texture = INVALID_TEXTURE
}

@(private="file")
_create_render_texture :: proc(width: int, height: int) -> (Texture, Render_Target) {
    tex_handle := _create_texture({}, width, height, .RGBA8)

    fbos: [1]u32
    gl.GenFramebuffers(1, &fbos[0])
    fbo := fbos[0]
    gl.BindFramebuffer(gl.FRAMEBUFFER, fbo)
    gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, _state.textures[int(tex_handle) - 1].id, 0)

    append(&_state.render_targets, GL_RT{
        fbo       = fbo,
        tex_index = int(tex_handle) - 1,
        width     = width,
        height    = height,
    })
    return tex_handle, Render_Target{
        idx = Texture(len(_state.render_targets)),
        w   = u32(width),
        h   = u32(height),
    }
}

@(private="file")
_destroy_render_target :: proc(handle: Render_Target) {
    i := int(handle.idx) - 1
    if i < 0 || i >= len(_state.render_targets) do return
    del := [1]u32{_state.render_targets[i].fbo}
    gl.DeleteFramebuffers(1, &del[0])
    _state.render_targets[i].fbo = 0
}

@(private="file")
_resize :: proc(width, height: int) {
    _state.swapchain_w = width
    _state.swapchain_h = height
    gl.Viewport(0, 0, i32(width), i32(height))
}

@(private="file")
_swapchain_size :: proc() -> (int, int) {
    return _state.swapchain_w, _state.swapchain_h
}

@(private="file")
_read_pixels :: proc(target: Render_Target, allocator: runtime.Allocator) -> ([]u8, int, int) {
    w, h := _bind_target(target)
    // After SwapBuffers the back buffer is undefined; the presented frame
    // lives in the front buffer.
    if target == INVALID_RENDER_TARGET do gl.ReadBuffer(gl.FRONT)
    data := make([]u8, w * h * 4, allocator)
    gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
    gl.ReadPixels(0, 0, i32(w), i32(h), gl.RGBA, gl.UNSIGNED_BYTE, raw_data(data))
    if target == INVALID_RENDER_TARGET do gl.ReadBuffer(gl.BACK)

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
    gl.Clear(gl.STENCIL_BUFFER_BIT)
}

@(private="file")
_stencil_push_clip :: proc() {
    _state.stencil_depth += 1
    bit := u32(1) << u32(_state.stencil_depth)

    fullscreen := [4]Vertex{
        {pos = {0, 0}},
        {pos = {f32(_state.swapchain_w), 0}},
        {pos = {f32(_state.swapchain_w), f32(_state.swapchain_h)}},
        {pos = {0, f32(_state.swapchain_h)}},
    }
    indices := [6]u32{0, 1, 2, 0, 2, 3}

    _bind_target(INVALID_RENDER_TARGET)
    gl.ColorMask(false, false, false, false)
    gl.StencilMask(bit)
    gl.StencilFunc(gl.ALWAYS, 0, 0)
    gl.StencilOp(gl.KEEP, gl.KEEP, gl.ZERO)
    gl.Disable(gl.SCISSOR_TEST)
    gl.UseProgram(_state.program)
    gl.Uniform2f(_state.loc_resolution, f32(_state.swapchain_w), f32(_state.swapchain_h))
    identity := common.Mat3X3_IDENTITY
    gl.UniformMatrix3fv(_state.loc_transform, 1, false, &identity[0,0])
    gl.Uniform1i(_state.loc_has_tex, 0)
    gl.BindVertexArray(_state.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, _state.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of([4]Vertex), &fullscreen[0], gl.DYNAMIC_DRAW)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, _state.ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of([6]u32), &indices[0], gl.DYNAMIC_DRAW)
    gl.DrawElements(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil)

    gl.StencilFunc(gl.ALWAYS, i32(bit), bit)
    gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE)
}

@(private="file")
_stencil_use_clip :: proc() {
    bit := u32(1) << u32(_state.stencil_depth)
    gl.ColorMask(true, true, true, true)
    gl.StencilMask(0)
    gl.StencilFunc(gl.EQUAL, i32(bit), bit)
    gl.StencilOp(gl.KEEP, gl.KEEP, gl.KEEP)
}

@(private="file")
_stencil_pop_clip :: proc() {
    if _state.stencil_depth > 0 do _state.stencil_depth -= 1
    if _state.stencil_depth == 0 {
        gl.StencilMask(0)
        gl.StencilFunc(gl.ALWAYS, 0, 0)
    } else {
        bit := u32(1) << u32(_state.stencil_depth)
        gl.StencilMask(0)
        gl.StencilFunc(gl.EQUAL, i32(bit), bit)
    }
    gl.ColorMask(true, true, true, true)
}

@(private="file")
_bind_target :: proc(target: Render_Target) -> (width, height: int) {
    if target == INVALID_RENDER_TARGET {
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        gl.Viewport(0, 0, i32(_state.swapchain_w), i32(_state.swapchain_h))
        return _state.swapchain_w, _state.swapchain_h
    } else {
        i := int(target.idx) - 1
        if i >= 0 && i < len(_state.render_targets) {
            rt := _state.render_targets[i]
            if rt.fbo != 0 {
                gl.BindFramebuffer(gl.FRAMEBUFFER, rt.fbo)
                gl.Viewport(0, 0, i32(rt.width), i32(rt.height))
                return rt.width, rt.height
            }
        }
    }

    // An invalid or destroyed target must not leave an unrelated FBO bound.
    gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
    gl.Viewport(0, 0, i32(_state.swapchain_w), i32(_state.swapchain_h))
    return _state.swapchain_w, _state.swapchain_h
}

@(private="file")
_texture_format :: proc(format: Pixel_Format) -> (internal, layout: u32, channels: int) {
    switch format {
    case .RGBA8: return gl.RGBA8, gl.RGBA, 4
    case .BGRA8: return gl.RGBA8, gl.BGRA, 4
    case .R8:    return gl.R8, gl.RED, 1
    case .A8:    return gl.R8, gl.RED, 1
    }
    return gl.RGBA8, gl.RGBA, 4
}

RENDERER_GL :: Renderer {
    create_state          = _create_state,
    free_state            = _free_state,
    init                  = _init,
    shutdown              = _shutdown,
    get_active_state      = _get_active_state,
    set_active_state      = _set_active_state,
    make_current          = _make_current,
    clear                 = _clear,
    present               = _present,
    draw                  = _draw,
    draw_mesh             = _draw_mesh,
    draw_glyphs           = _draw_glyphs,
    draw_glyph_mesh       = _draw_glyph_mesh,
    draw_robin_mesh       = _draw_robin_mesh,
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

@(private = "file")
_blend_over :: proc() {
    gl.BlendFuncSeparate(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA, gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
}

@(private = "file")
_blend_additive :: proc() {
    gl.BlendFuncSeparate(gl.SRC_ALPHA, gl.ONE, gl.ONE, gl.ONE_MINUS_SRC_ALPHA)
}
