#+build windows
package render

import "base:runtime"
import "core:fmt"
import "core:mem"
import win32 "core:sys/windows"
import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
import d3dc "vendor:directx/d3d_compiler"
import "src:core/common"

// DirectComposition never scale the visual to a new window size, so resizes dont stretch
foreign import dcomp "system:dcomp.lib"

@(default_calling_convention = "system", private = "file")
foreign dcomp {
    DCompositionCreateDevice :: proc(dxgiDevice: ^dxgi.IUnknown, iid: ^dxgi.IID, device: ^rawptr) -> win32.HRESULT ---
}

@(private = "file")
IID_IDCompositionDevice := dxgi.IID{0xC37EA93A, 0xE7AA, 0x450D, {0xB1, 0x6F, 0x97, 0x46, 0xCB, 0x04, 0x07, 0xF3}}

// get a method out of a COM vtable cuz odin has no binding for dcomp
// the slots we use are Device Commit 3, CreateTargetForHwnd 6, CreateVisual 7, Target SetRoot 3, Visual SetContent 15, IUnknown Release 2
@(private = "file")
_com_slot :: proc(object: rawptr, slot: int) -> rawptr {
    return (cast(^[^]rawptr)object)^[slot]
}

@(private = "file")
_com_release :: proc(object: rawptr) {
    if object != nil do (cast(proc "system" (rawptr) -> u32)_com_slot(object, 2))(object)
}

@(private = "file")
SHADER_SOURCE :: #load("shaders/d3d11.hlsl")

@(private = "file")
D3D_Params :: struct {
    resolution:    [2]f32,
    has_tex:       i32,
    clip_count:    i32,
    transform:     [3][4]f32,
    clip:          [12][4]f32,
    clip_size:     [4][4]f32,
    clip_radius:   [4][4]f32,
    clip_radius_y: [4][4]f32,
    color:         [4][4]f32,
    offset:        [4]f32,
    tint:          [4]f32,
    step:          [2]f32,
    taps:          i32,
    sigma:         f32,
    shadow:        i32,
    robin_width:   i32,
    px_range:      f32,
    samples:       i32,
}

@(private = "file")
D3D_Texture :: struct {
    texture: ^d3d11.ITexture2D,
    srv:     ^d3d11.IShaderResourceView,
    format:  Pixel_Format,
    width:   int,
    height:  int,
    nearest: [2]bool, // nearest for min and for mag
}

@(private = "file")
D3D_RT :: struct {
    rtv:       ^d3d11.IRenderTargetView,
    ds:        ^d3d11.ITexture2D,
    dsv:       ^d3d11.IDepthStencilView,
    tex_index: int,
    width:     int,
    height:    int,
}

@(private = "file")
D3D_Mesh :: struct {
    vb, ib:      ^d3d11.IBuffer,
    index_count: int,
}

@(private = "file")
D3D_Stencil :: struct {
    func:  d3d11.COMPARISON_FUNC,
    ref:   u8,
    read:  u8,
    write: u8,
    pass:  d3d11.STENCIL_OP,
    color: bool,
}

@(private = "file")
STENCIL_IDLE :: D3D_Stencil{func = .ALWAYS, pass = .KEEP, color = true}

@(private = "file")
D3D_State :: struct {
    render:      Render_Interface,
    device:      ^d3d11.IDevice,
    ctx:         ^d3d11.IDeviceContext,
    dxgi_device: ^dxgi.IDevice,
    swapchain:   ^dxgi.ISwapChain1,
    comp, comp_target, comp_visual: rawptr,
    back_rtv:    ^d3d11.IRenderTargetView,
    buffer_w, buffer_h:       int,
    swapchain_w, swapchain_h: int,
    vsync:       bool,

    vs_quad, vs_glyph, vs_full: ^d3d11.IVertexShader,
    ps_quad, ps_effect, ps_glyph, ps_robin, ps_msdf, ps_present, ps_resolve, ps_clear: ^d3d11.IPixelShader,
    layout_quad, layout_glyph: ^d3d11.IInputLayout,
    params:     ^d3d11.IBuffer,
    vbuf, ibuf: ^d3d11.IBuffer,
    vbuf_cap, ibuf_cap: int,
    curve_buf:  ^d3d11.IBuffer,
    curve_srv:  ^d3d11.IShaderResourceView,
    curve_cap:  int,
    curves_version: u64,
    robin_tex:  ^d3d11.ITexture2D,
    robin_srv:  ^d3d11.IShaderResourceView,
    robin_h:    int,
    robin_version: u64,
    raster:     ^d3d11.IRasterizerState,
    samplers:   [2][2]^d3d11.ISamplerState, // indexed by min nearest, then mag nearest
    blend_states:   map[u32]^d3d11.IBlendState,
    stencil_states: map[u32]^d3d11.IDepthStencilState,

    textures:     [dynamic]D3D_Texture,
    targets:      [dynamic]D3D_RT,
    meshes:       [dynamic]D3D_Mesh,
    glyph_meshes: [dynamic]D3D_Mesh,

    screen_texture: Texture,
    screen_target:  Render_Target,
    screen_dirty:   common.Rect,
    samples:        int,
    ms_tex, ms_ds:  ^d3d11.ITexture2D,
    ms_srv:         ^d3d11.IShaderResourceView,
    ms_rtv:         ^d3d11.IRenderTargetView,
    ms_dsv:         ^d3d11.IDepthStencilView,
    encoded:        ^d3d11.ITexture2D,
    encoded_rtv:    ^d3d11.IRenderTargetView,
    encoded_w, encoded_h: int,

    stencil:       D3D_Stencil,
    stencil_depth: int,
    layer:         Render_Target,
    bound_rtv:     ^d3d11.IRenderTargetView,
    bound_dsv:     ^d3d11.IDepthStencilView,
}

@(private = "file", thread_local)
_state: ^D3D_State

@(private = "file")
_check :: proc(hr: win32.HRESULT, what: string, loc := #caller_location) {
    if hr < 0 do panic(fmt.tprintf("render backend 'd3d11': %s failed: 0x%08x", what, u32(hr)), loc)
}

@(private = "file")
_create_state :: proc(allocator: runtime.Allocator) -> rawptr {
    return new(D3D_State, allocator)
}

@(private = "file")
_free_state :: proc(state: rawptr, allocator: runtime.Allocator) {
    if state != nil do runtime.mem_free(state, allocator)
}

@(private = "file")
_get_active_state :: proc() -> rawptr {
    return _state
}

@(private = "file")
_set_active_state :: proc(state: rawptr) {
    _state = cast(^D3D_State)(state)
}

@(private = "file")
_make_current :: proc() {}

@(private = "file")
_compile :: proc(entry, target: cstring) -> ^d3dc.ID3DBlob {
    code, errors: ^d3dc.ID3DBlob
    hr := d3dc.Compile(raw_data(SHADER_SOURCE), uint(len(SHADER_SOURCE)), "d3d11.hlsl", nil, nil, entry, target, 0, 0, &code, &errors)
    if hr < 0 {
        message := string(([^]u8)(errors->GetBufferPointer())[:errors->GetBufferSize()]) if errors != nil else ""
        panic(fmt.tprintf("render backend 'd3d11': shader %s failed to compile\n%s", entry, message))
    }
    if errors != nil do errors->Release()
    return code
}

@(private = "file")
_vertex_shader :: proc(entry: cstring) -> (shader: ^d3d11.IVertexShader, code: ^d3dc.ID3DBlob) {
    code = _compile(entry, "vs_5_0")
    _check(_state.device->CreateVertexShader(code->GetBufferPointer(), code->GetBufferSize(), nil, &shader), "CreateVertexShader")
    return
}

@(private = "file")
_pixel_shader :: proc(entry: cstring) -> (shader: ^d3d11.IPixelShader) {
    code := _compile(entry, "ps_5_0")
    defer code->Release()
    _check(_state.device->CreatePixelShader(code->GetBufferPointer(), code->GetBufferSize(), nil, &shader), "CreatePixelShader")
    return
}

@(private = "file")
_init :: proc(
    state:     rawptr,
    render:    Render_Interface,
    width:     int,
    height:    int,
    options:   Init_Options,
    allocator: runtime.Allocator,
) {
    _state = cast(^D3D_State)(state)
    _state^ = D3D_State{}
    _state.render = render
    _state.swapchain_w, _state.swapchain_h = width, height
    _state.vsync = options.vsync
    _state.textures = make([dynamic]D3D_Texture, 0, allocator)
    _state.targets = make([dynamic]D3D_RT, 0, allocator)
    _state.meshes = make([dynamic]D3D_Mesh, 0, allocator)
    _state.glyph_meshes = make([dynamic]D3D_Mesh, 0, allocator)
    _state.blend_states = make(map[u32]^d3d11.IBlendState, allocator)
    _state.stencil_states = make(map[u32]^d3d11.IDepthStencilState, allocator)
    _state.stencil = STENCIL_IDLE

    if !render.make_context(render.state, options) do panic("render backend 'd3d11': glue.make_context failed")
    assert(render.native_window != nil, "render backend 'd3d11' needs the platform's native_window")
    hwnd := win32.HWND(render.native_window(render.state))

    levels := [2]d3d11.FEATURE_LEVEL{._11_0, ._10_0}
    _check(d3d11.CreateDevice(nil, .HARDWARE, nil, {.BGRA_SUPPORT}, &levels[0], len(levels), d3d11.SDK_VERSION, &_state.device, nil, &_state.ctx), "D3D11CreateDevice")
    _check(_state.device->QueryInterface(dxgi.IDevice_UUID, cast(^rawptr)&_state.dxgi_device), "QueryInterface IDXGIDevice")
    adapter: ^dxgi.IAdapter
    _check(_state.dxgi_device->GetAdapter(&adapter), "GetAdapter")
    defer adapter->Release()
    factory: ^dxgi.IFactory2
    _check(adapter->GetParent(dxgi.IFactory2_UUID, cast(^rawptr)&factory), "GetParent IDXGIFactory2")
    defer factory->Release()

    _state.buffer_w, _state.buffer_h = max(width, 1), max(height, 1)
    desc := dxgi.SWAP_CHAIN_DESC1{
        Width = u32(_state.buffer_w), Height = u32(_state.buffer_h), Format = .B8G8R8A8_UNORM,
        SampleDesc = {Count = 1}, BufferUsage = {.RENDER_TARGET_OUTPUT}, BufferCount = 2,
        Scaling = .STRETCH, SwapEffect = .FLIP_SEQUENTIAL,
        AlphaMode = .PREMULTIPLIED if options.transparent else .IGNORE,
    }
    _check(factory->CreateSwapChainForComposition(cast(^dxgi.IUnknown)_state.device, &desc, nil, &_state.swapchain), "CreateSwapChainForComposition")
    _fetch_back_rtv()

    _check(DCompositionCreateDevice(cast(^dxgi.IUnknown)_state.dxgi_device, &IID_IDCompositionDevice, &_state.comp), "DCompositionCreateDevice")
    comp := _state.comp
    _check((cast(proc "system" (rawptr, win32.HWND, win32.BOOL, ^rawptr) -> win32.HRESULT)_com_slot(comp, 6))(comp, hwnd, win32.TRUE, &_state.comp_target), "CreateTargetForHwnd")
    _check((cast(proc "system" (rawptr, ^rawptr) -> win32.HRESULT)_com_slot(comp, 7))(comp, &_state.comp_visual), "CreateVisual")
    visual := _state.comp_visual
    _check((cast(proc "system" (rawptr, rawptr) -> win32.HRESULT)_com_slot(visual, 15))(visual, _state.swapchain), "SetContent")
    _check((cast(proc "system" (rawptr, rawptr) -> win32.HRESULT)_com_slot(_state.comp_target, 3))(_state.comp_target, visual), "SetRoot")
    _check((cast(proc "system" (rawptr) -> win32.HRESULT)_com_slot(comp, 3))(comp), "Commit")

    quad_code, glyph_code: ^d3dc.ID3DBlob
    _state.vs_quad, quad_code = _vertex_shader("vs_quad")
    _state.vs_glyph, glyph_code = _vertex_shader("vs_glyph")
    full_code: ^d3dc.ID3DBlob
    _state.vs_full, full_code = _vertex_shader("vs_fullscreen")
    full_code->Release()
    _state.ps_quad = _pixel_shader("ps_quad")
    _state.ps_effect = _pixel_shader("ps_effect")
    _state.ps_glyph = _pixel_shader("ps_glyph")
    _state.ps_robin = _pixel_shader("ps_robin")
    _state.ps_msdf = _pixel_shader("ps_msdf")
    _state.ps_present = _pixel_shader("ps_present")
    _state.ps_resolve = _pixel_shader("ps_resolve")
    _state.ps_clear = _pixel_shader("ps_clear")

    quad_layout := [4]d3d11.INPUT_ELEMENT_DESC{
        {SemanticName = "POSITION", Format = .R32G32_FLOAT, AlignedByteOffset = 0},
        {SemanticName = "TEXCOORD", Format = .R32G32_FLOAT, AlignedByteOffset = 8},
        {SemanticName = "COLOR", Format = .R8G8B8A8_UNORM, AlignedByteOffset = 16},
        {SemanticName = "MODE", Format = .R32_UINT, AlignedByteOffset = 20},
    }
    _check(_state.device->CreateInputLayout(&quad_layout[0], len(quad_layout), quad_code->GetBufferPointer(), quad_code->GetBufferSize(), &_state.layout_quad), "CreateInputLayout quad")
    quad_code->Release()
    glyph_layout := [4]d3d11.INPUT_ELEMENT_DESC{
        {SemanticName = "POSITION", Format = .R32G32_FLOAT, AlignedByteOffset = 0},
        {SemanticName = "TEXCOORD", Format = .R32G32_FLOAT, AlignedByteOffset = 8},
        {SemanticName = "COLOR", Format = .R8G8B8A8_UNORM, AlignedByteOffset = 16},
        {SemanticName = "CURVES", Format = .R32G32_UINT, AlignedByteOffset = 20},
    }
    _check(_state.device->CreateInputLayout(&glyph_layout[0], len(glyph_layout), glyph_code->GetBufferPointer(), glyph_code->GetBufferSize(), &_state.layout_glyph), "CreateInputLayout glyph")
    glyph_code->Release()

    params_desc := d3d11.BUFFER_DESC{ByteWidth = size_of(D3D_Params), Usage = .DYNAMIC, BindFlags = {.CONSTANT_BUFFER}, CPUAccessFlags = {.WRITE}}
    _check(_state.device->CreateBuffer(&params_desc, nil, &_state.params), "CreateBuffer params")

    raster_desc := d3d11.RASTERIZER_DESC{FillMode = .SOLID, CullMode = .NONE, DepthClipEnable = win32.TRUE, ScissorEnable = win32.TRUE}
    _check(_state.device->CreateRasterizerState(&raster_desc, &_state.raster), "CreateRasterizerState")

    for min_nearest in 0 ..< 2 {
        for mag_nearest in 0 ..< 2 {
            filter: d3d11.FILTER
            switch {
            case min_nearest == 0 && mag_nearest == 0: filter = .MIN_MAG_MIP_LINEAR
            case min_nearest == 0:                     filter = .MIN_LINEAR_MAG_MIP_POINT
            case mag_nearest == 0:                     filter = .MIN_POINT_MAG_LINEAR_MIP_POINT
            case:                                      filter = .MIN_MAG_MIP_POINT
            }
            sampler_desc := d3d11.SAMPLER_DESC{Filter = filter, AddressU = .CLAMP, AddressV = .CLAMP, AddressW = .CLAMP, ComparisonFunc = .NEVER, MaxLOD = max(f32)}
            _check(_state.device->CreateSamplerState(&sampler_desc, &_state.samplers[min_nearest][mag_nearest]), "CreateSamplerState")
        }
    }

    if options.msaa_samples > 1 {
        _state.samples = int(options.msaa_samples)
        for _state.samples > 1 {
            quality: u32
            _state.device->CheckMultisampleQualityLevels(.R8G8B8A8_UNORM_SRGB, u32(_state.samples), &quality)
            if quality > 0 do break
            _state.samples /= 2
        }
    }
}

@(private = "file")
_fetch_back_rtv :: proc() {
    back: ^d3d11.ITexture2D
    _check(_state.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, cast(^rawptr)&back), "GetBuffer")
    defer back->Release()
    _check(_state.device->CreateRenderTargetView(cast(^d3d11.IResource)back, nil, &_state.back_rtv), "CreateRenderTargetView back buffer")
}

@(private = "file")
_release :: proc(p: ^$T) {
    if p^ != nil {
        p^->Release()
        p^ = nil
    }
}

@(private = "file")
_shutdown :: proc() {
    if _state == nil do return
    _state.ctx->ClearState()
    for &t in _state.textures {
        _release(&t.srv)
        _release(&t.texture)
    }
    for &rt in _state.targets {
        _release(&rt.rtv)
        _release(&rt.dsv)
        _release(&rt.ds)
    }
    for &m in _state.meshes {
        _release(&m.vb)
        _release(&m.ib)
    }
    for &m in _state.glyph_meshes {
        _release(&m.vb)
        _release(&m.ib)
    }
    for _, s in _state.blend_states do s->Release()
    for _, s in _state.stencil_states do s->Release()
    for row in _state.samplers do for s in row do if s != nil do s->Release()
    _release(&_state.ms_srv)
    _release(&_state.ms_rtv)
    _release(&_state.ms_dsv)
    _release(&_state.ms_tex)
    _release(&_state.ms_ds)
    _release(&_state.encoded_rtv)
    _release(&_state.encoded)
    _release(&_state.curve_srv)
    _release(&_state.curve_buf)
    _release(&_state.robin_srv)
    _release(&_state.robin_tex)
    _release(&_state.vbuf)
    _release(&_state.ibuf)
    _release(&_state.params)
    _release(&_state.raster)
    _release(&_state.layout_quad)
    _release(&_state.layout_glyph)
    _release(&_state.vs_quad)
    _release(&_state.vs_glyph)
    _release(&_state.vs_full)
    _release(&_state.ps_quad)
    _release(&_state.ps_effect)
    _release(&_state.ps_glyph)
    _release(&_state.ps_robin)
    _release(&_state.ps_msdf)
    _release(&_state.ps_present)
    _release(&_state.ps_resolve)
    _release(&_state.ps_clear)
    _release(&_state.back_rtv)
    _com_release(_state.comp_visual)
    _com_release(_state.comp_target)
    _com_release(_state.comp)
    _release(&_state.swapchain)
    _release(&_state.dxgi_device)
    _release(&_state.ctx)
    _release(&_state.device)
    delete(_state.textures)
    delete(_state.targets)
    delete(_state.meshes)
    delete(_state.glyph_meshes)
    delete(_state.blend_states)
    delete(_state.stencil_states)
}

@(private = "file")
_retained :: proc() -> bool {
    return true
}

@(private = "file")
_blend_state :: proc(mode: Blend_Mode, color: bool) -> ^d3d11.IBlendState {
    key := u32(mode) | (u32(color) << 4)
    if s, ok := _state.blend_states[key]; ok do return s
    rt := d3d11.RENDER_TARGET_BLEND_DESC{BlendOp = .ADD, BlendOpAlpha = .ADD, RenderTargetWriteMask = 0xF if color else 0}
    switch mode {
    case .Opaque:
        rt.SrcBlend, rt.DestBlend, rt.SrcBlendAlpha, rt.DestBlendAlpha = .ONE, .ZERO, .ONE, .ZERO
    case .Alpha:
        rt.BlendEnable = win32.TRUE
        rt.SrcBlend, rt.DestBlend, rt.SrcBlendAlpha, rt.DestBlendAlpha = .SRC_ALPHA, .INV_SRC_ALPHA, .ONE, .INV_SRC_ALPHA
    case .Additive:
        rt.BlendEnable = win32.TRUE
        rt.SrcBlend, rt.DestBlend, rt.SrcBlendAlpha, rt.DestBlendAlpha = .SRC_ALPHA, .ONE, .ONE, .INV_SRC_ALPHA
    case .Premultiplied:
        rt.BlendEnable = win32.TRUE
        rt.SrcBlend, rt.DestBlend, rt.SrcBlendAlpha, rt.DestBlendAlpha = .ONE, .INV_SRC_ALPHA, .ONE, .INV_SRC_ALPHA
    }
    desc := d3d11.BLEND_DESC{}
    desc.RenderTarget[0] = rt
    s: ^d3d11.IBlendState
    _check(_state.device->CreateBlendState(&desc, &s), "CreateBlendState")
    _state.blend_states[key] = s
    return s
}

@(private = "file")
_stencil_state :: proc(st: D3D_Stencil) -> ^d3d11.IDepthStencilState {
    key := u32(st.func) | (u32(st.pass) << 4) | (u32(st.read) << 8) | (u32(st.write) << 16)
    if s, ok := _state.stencil_states[key]; ok do return s
    face := d3d11.DEPTH_STENCILOP_DESC{StencilFailOp = .KEEP, StencilDepthFailOp = .KEEP, StencilPassOp = st.pass, StencilFunc = st.func}
    desc := d3d11.DEPTH_STENCIL_DESC{
        DepthEnable = win32.FALSE, DepthWriteMask = .ZERO, DepthFunc = .ALWAYS,
        StencilEnable = win32.TRUE, StencilReadMask = st.read, StencilWriteMask = st.write,
        FrontFace = face, BackFace = face,
    }
    s: ^d3d11.IDepthStencilState
    _check(_state.device->CreateDepthStencilState(&desc, &s), "CreateDepthStencilState")
    _state.stencil_states[key] = s
    return s
}

@(private = "file")
_unbind_resources :: proc() {
    none := [4]^d3d11.IShaderResourceView{}
    _state.ctx->PSSetShaderResources(0, len(none), &none[0])
}

@(private = "file")
_bind_views :: proc(rtv: ^d3d11.IRenderTargetView, dsv: ^d3d11.IDepthStencilView, w, h: int) {
    _unbind_resources()
    views := [1]^d3d11.IRenderTargetView{rtv}
    _state.ctx->OMSetRenderTargets(1, &views[0], dsv)
    viewport := d3d11.VIEWPORT{Width = f32(w), Height = f32(h), MaxDepth = 1}
    _state.ctx->RSSetViewports(1, &viewport)
    _state.bound_rtv, _state.bound_dsv = rtv, dsv
}

@(private = "file")
_bind_target :: proc(target: Render_Target) -> (width, height: int) {
    if target == INVALID_RENDER_TARGET {
        _ensure_screen()
        if _state.ms_rtv != nil {
            w, h := int(_state.screen_target.w), int(_state.screen_target.h)
            _bind_views(_state.ms_rtv, _state.ms_dsv, w, h)
            return w, h
        }
        if _state.screen_target != INVALID_RENDER_TARGET do return _bind_target(_state.screen_target)
        return _state.swapchain_w, _state.swapchain_h
    }
    i := int(target.idx) - 1
    if i >= 0 && i < len(_state.targets) && _state.targets[i].rtv != nil {
        rt := _state.targets[i]
        _bind_views(rt.rtv, rt.dsv, rt.width, rt.height)
        return rt.width, rt.height
    }
    return _state.swapchain_w, _state.swapchain_h
}

@(private = "file")
_ensure_screen :: proc() {
    w, h := _state.swapchain_w, _state.swapchain_h
    if w <= 0 || h <= 0 do return
    if int(_state.screen_target.w) == w && int(_state.screen_target.h) == h do return
    if _state.screen_target != INVALID_RENDER_TARGET {
        // reuse the same slots, or window drags pile up targets
        ti, ri := int(_state.screen_texture) - 1, int(_state.screen_target.idx) - 1
        _destroy_texture(_state.screen_texture)
        _destroy_render_target(_state.screen_target)
        _state.textures[ti], _state.targets[ri] = _render_texture_resources(w, h)
        _state.targets[ri].tex_index = ti
        _state.screen_target.w, _state.screen_target.h = u32(w), u32(h)
    } else {
        _state.screen_texture, _state.screen_target = _create_render_texture(w, h)
    }
    _size_screen_samples(w, h)
}

@(private = "file")
_size_screen_samples :: proc(w, h: int) {
    if _state.samples <= 1 do return
    _release(&_state.ms_srv)
    _release(&_state.ms_rtv)
    _release(&_state.ms_dsv)
    _release(&_state.ms_tex)
    _release(&_state.ms_ds)
    desc := d3d11.TEXTURE2D_DESC{
        Width = u32(w), Height = u32(h), MipLevels = 1, ArraySize = 1, Format = .R8G8B8A8_UNORM_SRGB,
        SampleDesc = {Count = u32(_state.samples)}, Usage = .DEFAULT, BindFlags = {.RENDER_TARGET, .SHADER_RESOURCE},
    }
    _check(_state.device->CreateTexture2D(&desc, nil, &_state.ms_tex), "CreateTexture2D msaa")
    _check(_state.device->CreateRenderTargetView(cast(^d3d11.IResource)_state.ms_tex, nil, &_state.ms_rtv), "CreateRenderTargetView msaa")
    _check(_state.device->CreateShaderResourceView(cast(^d3d11.IResource)_state.ms_tex, nil, &_state.ms_srv), "CreateShaderResourceView msaa")
    desc.Format = .D24_UNORM_S8_UINT
    desc.BindFlags = {.DEPTH_STENCIL}
    _check(_state.device->CreateTexture2D(&desc, nil, &_state.ms_ds), "CreateTexture2D msaa stencil")
    _check(_state.device->CreateDepthStencilView(cast(^d3d11.IResource)_state.ms_ds, nil, &_state.ms_dsv), "CreateDepthStencilView msaa")
}

@(private = "file")
_columns :: proc(m: common.Mat3x3) -> (c: [3][4]f32) {
    for col in 0 ..< 3 do c[col] = {m[0, col], m[1, col], m[2, col], 0}
    return
}

@(private = "file")
_params :: proc(target: Render_Target, w, h: int, transform: common.Mat3x3) -> (p: D3D_Params) {
    p.resolution = {f32(w), f32(h)}
    p.transform = _columns(transform)
    count := clip_edge_count if target == _state.layer else 0
    p.clip_count = i32(count)
    for i in 0 ..< count {
        cols := _columns(clip_edges[i].to_local)
        for c in 0 ..< 3 do p.clip[i * 3 + c] = cols[c]
        p.clip_size[i] = {clip_edges[i].size.x, clip_edges[i].size.y, 0, 0}
        r := clip_edges[i].radius
        p.clip_radius[i] = {r[0].x, r[1].x, r[2].x, r[3].x}
        p.clip_radius_y[i] = {r[0].y, r[1].y, r[2].y, r[3].y}
    }
    return
}

@(private = "file")
_upload_params :: proc(p: ^D3D_Params) {
    mapped: d3d11.MAPPED_SUBRESOURCE
    _check(_state.ctx->Map(cast(^d3d11.IResource)_state.params, 0, .WRITE_DISCARD, {}, &mapped), "Map params")
    mem.copy(mapped.pData, p, size_of(D3D_Params))
    _state.ctx->Unmap(cast(^d3d11.IResource)_state.params, 0)
    buffers := [1]^d3d11.IBuffer{_state.params}
    _state.ctx->VSSetConstantBuffers(0, 1, &buffers[0])
    _state.ctx->PSSetConstantBuffers(0, 1, &buffers[0])
}

@(private = "file")
_stream :: proc(buffer: ^^d3d11.IBuffer, capacity: ^int, bind: d3d11.BIND_FLAG, data: rawptr, size: int) {
    if size > capacity^ {
        _release(buffer)
        capacity^ = max(size, capacity^ * 2, 64 * 1024)
        desc := d3d11.BUFFER_DESC{ByteWidth = u32(capacity^), Usage = .DYNAMIC, BindFlags = {bind}, CPUAccessFlags = {.WRITE}}
        _check(_state.device->CreateBuffer(&desc, nil, buffer), "CreateBuffer stream")
    }
    mapped: d3d11.MAPPED_SUBRESOURCE
    _check(_state.ctx->Map(cast(^d3d11.IResource)buffer^, 0, .WRITE_DISCARD, {}, &mapped), "Map stream")
    mem.copy(mapped.pData, data, size)
    _state.ctx->Unmap(cast(^d3d11.IResource)buffer^, 0)
}

@(private = "file")
_static_buffer :: proc(bind: d3d11.BIND_FLAG, data: rawptr, size: int) -> (buffer: ^d3d11.IBuffer) {
    desc := d3d11.BUFFER_DESC{ByteWidth = u32(size), Usage = .DEFAULT, BindFlags = {bind}}
    init := d3d11.SUBRESOURCE_DATA{pSysMem = data}
    _check(_state.device->CreateBuffer(&desc, &init, &buffer), "CreateBuffer static")
    return
}

@(private = "file")
_prepare :: proc(target: Render_Target, scissor: Maybe(common.Rect), blend: Blend_Mode) -> (w, h: int) {
    w, h = _bind_target(target)
    rect := d3d11.RECT{0, 0, i32(w), i32(h)}
    if r, ok := scissor.?; ok {
        rect = {max(i32(r.x), 0), max(i32(r.y), 0), max(i32(r.x + r.w), 0), max(i32(r.y + r.h), 0)}
    }
    _state.ctx->RSSetScissorRects(1, &rect)
    _state.ctx->RSSetState(_state.raster)
    _state.ctx->OMSetBlendState(_blend_state(blend, _state.stencil.color), nil, 0xFFFF_FFFF)
    _state.ctx->OMSetDepthStencilState(_stencil_state(_state.stencil), u32(_state.stencil.ref))
    _state.ctx->IASetPrimitiveTopology(.TRIANGLELIST)
    return
}

@(private = "file")
_bind_texture :: proc(slot: u32, texture: Texture) -> bool {
    i := int(texture) - 1
    if texture == INVALID_TEXTURE || i < 0 || i >= len(_state.textures) || _state.textures[i].srv == nil do return false
    t := _state.textures[i]
    views := [1]^d3d11.IShaderResourceView{t.srv}
    _state.ctx->PSSetShaderResources(slot, 1, &views[0])
    samplers := [1]^d3d11.ISamplerState{_state.samplers[int(t.nearest[0])][int(t.nearest[1])]}
    _state.ctx->PSSetSamplers(0, 1, &samplers[0])
    return true
}

@(private = "file")
_set_vertices :: proc(layout: ^d3d11.IInputLayout, vb, ib: ^d3d11.IBuffer, stride: u32) {
    _state.ctx->IASetInputLayout(layout)
    buffers := [1]^d3d11.IBuffer{vb}
    strides := [1]u32{stride}
    offsets := [1]u32{0}
    _state.ctx->IASetVertexBuffers(0, 1, &buffers[0], &strides[0], &offsets[0])
    _state.ctx->IASetIndexBuffer(ib, .R32_UINT, 0)
}

@(private = "file")
_clear :: proc(target: Render_Target, color: common.Color, scissor: Maybe(common.Rect) = nil) {
    w, h := _bind_target(target)
    // a resolve only copy what was cleared
    if target == INVALID_RENDER_TARGET {
        _state.screen_dirty = scissor.? or_else common.Rect{0, 0, f32(w), f32(h)}
    }
    alpha := f32(color[3]) / 255
    linear := [4]f32{
        common.srgb_to_linear(f32(color[0]) / 255) * alpha,
        common.srgb_to_linear(f32(color[1]) / 255) * alpha,
        common.srgb_to_linear(f32(color[2]) / 255) * alpha,
        alpha,
    }
    if _, ok := scissor.?; !ok {
        if _state.bound_rtv != nil do _state.ctx->ClearRenderTargetView(_state.bound_rtv, &linear)
        return
    }
    saved := _state.stencil
    _state.stencil = STENCIL_IDLE
    _prepare(target, scissor, .Opaque)
    _state.stencil = saved
    p: D3D_Params
    p.tint = linear
    _upload_params(&p)
    _state.ctx->IASetInputLayout(nil)
    _state.ctx->VSSetShader(_state.vs_full, nil, 0)
    _state.ctx->PSSetShader(_state.ps_clear, nil, 0)
    _state.ctx->Draw(3, 0)
}

@(private = "file")
_resolve_screen :: proc() {
    if _state.ms_rtv == nil do return
    r := _state.screen_dirty
    _state.screen_dirty = {}
    rt := _state.targets[int(_state.screen_target.idx) - 1]
    x0 := clamp(i32(r.x), 0, i32(rt.width))
    y0 := clamp(i32(r.y), 0, i32(rt.height))
    x1 := clamp(i32(r.x + r.w), 0, i32(rt.width))
    y1 := clamp(i32(r.y + r.h), 0, i32(rt.height))
    if x1 <= x0 || y1 <= y0 do return
    _fullscreen_pass(rt.rtv, rt.width, rt.height, {x0, y0, x1, y1}, _state.ps_resolve, _state.ms_srv)
}

@(private = "file")
_fullscreen_pass :: proc(rtv: ^d3d11.IRenderTargetView, w, h: int, rect: d3d11.RECT, ps: ^d3d11.IPixelShader, source: ^d3d11.IShaderResourceView) {
    _bind_views(rtv, nil, w, h)
    rect := rect
    _state.ctx->RSSetScissorRects(1, &rect)
    _state.ctx->RSSetState(_state.raster)
    _state.ctx->OMSetBlendState(_blend_state(.Opaque, true), nil, 0xFFFF_FFFF)
    _state.ctx->OMSetDepthStencilState(_stencil_state(STENCIL_IDLE), 0)
    _state.ctx->IASetPrimitiveTopology(.TRIANGLELIST)
    _state.ctx->IASetInputLayout(nil)
    p: D3D_Params
    p.samples = i32(_state.samples)
    _upload_params(&p)
    _state.ctx->VSSetShader(_state.vs_full, nil, 0)
    _state.ctx->PSSetShader(ps, nil, 0)
    views := [1]^d3d11.IShaderResourceView{source}
    slot: u32 = 3 if ps == _state.ps_resolve else 0
    _state.ctx->PSSetShaderResources(slot, 1, &views[0])
    _state.ctx->Draw(3, 0)
    _unbind_resources()
}

@(private = "file")
_screen_srv :: proc() -> ^d3d11.IShaderResourceView {
    return _state.textures[int(_state.screen_texture) - 1].srv
}

@(private = "file")
_present :: proc() {
    _ensure_screen()
    if _state.screen_target == INVALID_RENDER_TARGET do return
    _resolve_screen()

    w, h := _state.swapchain_w, _state.swapchain_h
    if w != _state.buffer_w || h != _state.buffer_h {
        _state.ctx->OMSetRenderTargets(0, nil, nil)
        _release(&_state.back_rtv)
        _check(_state.swapchain->ResizeBuffers(0, u32(w), u32(h), .UNKNOWN, {}), "ResizeBuffers")
        _state.buffer_w, _state.buffer_h = w, h
        _fetch_back_rtv()
    }
    _fullscreen_pass(_state.back_rtv, w, h, {0, 0, i32(w), i32(h)}, _state.ps_present, _screen_srv())
    swap_start := common.profile_begin(.Swap)
    _state.swapchain->Present(1 if _state.vsync else 0, {})
    common.profile_end(.Swap, swap_start)
    _state.render.present(_state.render.state)
}

@(private = "file")
_draw :: proc(target: Render_Target, vertices: []Vertex, indices: []u32, texture: Texture, scissor: Maybe(common.Rect), blend: Blend_Mode) {
    if len(vertices) == 0 || len(indices) == 0 do return
    w, h := _prepare(target, scissor, blend)
    p := _params(target, w, h, common.Mat3X3_IDENTITY)
    p.has_tex = i32(_bind_texture(0, texture))
    _upload_params(&p)
    _stream(&_state.vbuf, &_state.vbuf_cap, .VERTEX_BUFFER, raw_data(vertices), len(vertices) * size_of(Vertex))
    _stream(&_state.ibuf, &_state.ibuf_cap, .INDEX_BUFFER, raw_data(indices), len(indices) * size_of(u32))
    _set_vertices(_state.layout_quad, _state.vbuf, _state.ibuf, size_of(Vertex))
    _state.ctx->VSSetShader(_state.vs_quad, nil, 0)
    _state.ctx->PSSetShader(_state.ps_quad, nil, 0)
    _state.ctx->DrawIndexed(u32(len(indices)), 0, 0)
}

@(private = "file")
_mesh :: proc(list: ^[dynamic]D3D_Mesh, idx: ^u32, version: ^u64, geometry_version: u64, vertices: rawptr, vertex_size: int, indices: []u32) -> ^D3D_Mesh {
    if idx^ == 0 {
        append(list, D3D_Mesh{})
        idx^ = u32(len(list))
    }
    i := int(idx^) - 1
    if i < 0 || i >= len(list) do return nil
    m := &list[i]
    if version^ != geometry_version {
        if vertex_size == 0 || len(indices) == 0 do return nil
        _release(&m.vb)
        _release(&m.ib)
        m.vb = _static_buffer(.VERTEX_BUFFER, vertices, vertex_size)
        m.ib = _static_buffer(.INDEX_BUFFER, raw_data(indices), len(indices) * size_of(u32))
        m.index_count = len(indices)
        version^ = geometry_version
    }
    if m.index_count == 0 do return nil
    return m
}

@(private = "file")
_draw_mesh :: proc(target: Render_Target, mesh: ^Mesh, vertices: []Vertex, indices: []u32, geometry_version: u64, transform: common.Mat3x3, texture: Texture, scissor: Maybe(common.Rect), blend: Blend_Mode) {
    if mesh == nil do return
    m := _mesh(&_state.meshes, &mesh.idx, &mesh.version, geometry_version, raw_data(vertices), len(vertices) * size_of(Vertex), indices)
    if m == nil do return
    w, h := _prepare(target, scissor, blend)
    p := _params(target, w, h, transform)
    p.has_tex = i32(_bind_texture(0, texture))
    _upload_params(&p)
    _set_vertices(_state.layout_quad, m.vb, m.ib, size_of(Vertex))
    _state.ctx->VSSetShader(_state.vs_quad, nil, 0)
    _state.ctx->PSSetShader(_state.ps_quad, nil, 0)
    _state.ctx->DrawIndexed(u32(m.index_count), 0, 0)
}

@(private = "file")
_upload_curves :: proc(curves: [][2]f32, curves_version: u64) {
    if _state.curves_version == curves_version || len(curves) == 0 do return
    if len(curves) > _state.curve_cap {
        _release(&_state.curve_srv)
        _release(&_state.curve_buf)
        _state.curve_cap = max(len(curves), _state.curve_cap * 2, 4096)
        desc := d3d11.BUFFER_DESC{ByteWidth = u32(_state.curve_cap * size_of([2]f32)), Usage = .DYNAMIC, BindFlags = {.SHADER_RESOURCE}, CPUAccessFlags = {.WRITE}}
        _check(_state.device->CreateBuffer(&desc, nil, &_state.curve_buf), "CreateBuffer curves")
        srv_desc := d3d11.SHADER_RESOURCE_VIEW_DESC{Format = .R32G32_FLOAT, ViewDimension = .BUFFER}
        srv_desc.Buffer.NumElements = u32(_state.curve_cap)
        _check(_state.device->CreateShaderResourceView(cast(^d3d11.IResource)_state.curve_buf, &srv_desc, &_state.curve_srv), "CreateShaderResourceView curves")
    }
    mapped: d3d11.MAPPED_SUBRESOURCE
    _check(_state.ctx->Map(cast(^d3d11.IResource)_state.curve_buf, 0, .WRITE_DISCARD, {}, &mapped), "Map curves")
    mem.copy(mapped.pData, raw_data(curves), len(curves) * size_of([2]f32))
    _state.ctx->Unmap(cast(^d3d11.IResource)_state.curve_buf, 0)
    _state.curves_version = curves_version
}

@(private = "file")
_glyph_pass :: proc(target: Render_Target, scissor: Maybe(common.Rect), transform: common.Mat3x3, ps: ^d3d11.IPixelShader) -> D3D_Params {
    w, h := _prepare(target, scissor, .Alpha)
    _state.ctx->VSSetShader(_state.vs_glyph, nil, 0)
    _state.ctx->PSSetShader(ps, nil, 0)
    return _params(target, w, h, transform)
}

@(private = "file")
_draw_glyphs :: proc(target: Render_Target, vertices: []Glyph_Vertex, indices: []u32, curves: [][2]f32, curves_version: u64, transform: common.Mat3x3, scissor: Maybe(common.Rect)) {
    if len(vertices) == 0 || len(indices) == 0 do return
    _upload_curves(curves, curves_version)
    if _state.curve_srv == nil do return
    p := _glyph_pass(target, scissor, transform, _state.ps_glyph)
    _upload_params(&p)
    views := [1]^d3d11.IShaderResourceView{_state.curve_srv}
    _state.ctx->PSSetShaderResources(1, 1, &views[0])
    _stream(&_state.vbuf, &_state.vbuf_cap, .VERTEX_BUFFER, raw_data(vertices), len(vertices) * size_of(Glyph_Vertex))
    _stream(&_state.ibuf, &_state.ibuf_cap, .INDEX_BUFFER, raw_data(indices), len(indices) * size_of(u32))
    _set_vertices(_state.layout_glyph, _state.vbuf, _state.ibuf, size_of(Glyph_Vertex))
    _state.ctx->DrawIndexed(u32(len(indices)), 0, 0)
}

@(private = "file")
_draw_glyph_mesh :: proc(target: Render_Target, mesh: ^Glyph_Mesh, vertices: []Glyph_Vertex, indices: []u32, geometry_version: u64, transform: common.Mat3x3, curves: [][2]f32, curves_version: u64, scissor: Maybe(common.Rect)) {
    if mesh == nil do return
    m := _mesh(&_state.glyph_meshes, &mesh.idx, &mesh.version, geometry_version, raw_data(vertices), len(vertices) * size_of(Glyph_Vertex), indices)
    if m == nil do return
    _upload_curves(curves, curves_version)
    if _state.curve_srv == nil do return
    p := _glyph_pass(target, scissor, transform, _state.ps_glyph)
    _upload_params(&p)
    views := [1]^d3d11.IShaderResourceView{_state.curve_srv}
    _state.ctx->PSSetShaderResources(1, 1, &views[0])
    _set_vertices(_state.layout_glyph, m.vb, m.ib, size_of(Glyph_Vertex))
    _state.ctx->DrawIndexed(u32(m.index_count), 0, 0)
}

@(private = "file")
_draw_robin_mesh :: proc(target: Render_Target, mesh: ^Glyph_Mesh, vertices: []Glyph_Vertex, indices: []u32, geometry_version: u64, transform: common.Mat3x3, data: [][2]f32, data_version: u64, scissor: Maybe(common.Rect)) {
    if mesh == nil || !GL_ROBIN_ENABLED do return
    m := _mesh(&_state.glyph_meshes, &mesh.idx, &mesh.version, geometry_version, raw_data(vertices), len(vertices) * size_of(Glyph_Vertex), indices)
    if m == nil do return

    if _state.robin_version != data_version && len(data) > 0 {
        rows := (len(data) + GL_ROBIN_ATLAS_WIDTH - 1) / GL_ROBIN_ATLAS_WIDTH
        height := 1
        for height < rows do height *= 2
        if height > 16384 do return // D3D11 texture size limit
        if _state.robin_h != height {
            _release(&_state.robin_srv)
            _release(&_state.robin_tex)
            desc := d3d11.TEXTURE2D_DESC{
                Width = GL_ROBIN_ATLAS_WIDTH, Height = u32(height), MipLevels = 1, ArraySize = 1,
                Format = .R32G32_FLOAT, SampleDesc = {Count = 1}, Usage = .DEFAULT, BindFlags = {.SHADER_RESOURCE},
            }
            _check(_state.device->CreateTexture2D(&desc, nil, &_state.robin_tex), "CreateTexture2D robin")
            _check(_state.device->CreateShaderResourceView(cast(^d3d11.IResource)_state.robin_tex, nil, &_state.robin_srv), "CreateShaderResourceView robin")
            _state.robin_h = height
        }
        row_bytes := u32(GL_ROBIN_ATLAS_WIDTH * size_of([2]f32))
        full_rows := len(data) / GL_ROBIN_ATLAS_WIDTH
        if full_rows > 0 {
            box := d3d11.BOX{right = GL_ROBIN_ATLAS_WIDTH, bottom = u32(full_rows), back = 1}
            _state.ctx->UpdateSubresource(cast(^d3d11.IResource)_state.robin_tex, 0, &box, raw_data(data), row_bytes, 0)
        }
        if remainder := len(data) - full_rows * GL_ROBIN_ATLAS_WIDTH; remainder > 0 {
            box := d3d11.BOX{top = u32(full_rows), right = u32(remainder), bottom = u32(full_rows + 1), back = 1}
            _state.ctx->UpdateSubresource(cast(^d3d11.IResource)_state.robin_tex, 0, &box, &data[full_rows * GL_ROBIN_ATLAS_WIDTH], row_bytes, 0)
        }
        _state.robin_version = data_version
    }
    if _state.robin_srv == nil do return

    p := _glyph_pass(target, scissor, transform, _state.ps_robin)
    p.robin_width = GL_ROBIN_ATLAS_WIDTH
    _upload_params(&p)
    views := [1]^d3d11.IShaderResourceView{_state.robin_srv}
    _state.ctx->PSSetShaderResources(2, 1, &views[0])
    _set_vertices(_state.layout_glyph, m.vb, m.ib, size_of(Glyph_Vertex))
    _state.ctx->DrawIndexed(u32(m.index_count), 0, 0)
}

@(private = "file")
_draw_msdf_mesh :: proc(target: Render_Target, mesh: ^Glyph_Mesh, vertices: []Glyph_Vertex, indices: []u32, geometry_version: u64, transform: common.Mat3x3, atlas: Texture, pixel_range: f32, scissor: Maybe(common.Rect)) {
    if mesh == nil || atlas == INVALID_TEXTURE do return
    m := _mesh(&_state.glyph_meshes, &mesh.idx, &mesh.version, geometry_version, raw_data(vertices), len(vertices) * size_of(Glyph_Vertex), indices)
    if m == nil do return
    p := _glyph_pass(target, scissor, transform, _state.ps_msdf)
    if !_bind_texture(0, atlas) do return
    p.px_range = pixel_range
    _upload_params(&p)
    _set_vertices(_state.layout_glyph, m.vb, m.ib, size_of(Glyph_Vertex))
    _state.ctx->DrawIndexed(u32(m.index_count), 0, 0)
}

@(private = "file")
_draw_effect :: proc(target: Render_Target, source: Texture, vertices: [4]Vertex, effect: Effect, scissor: Maybe(common.Rect), blend: Blend_Mode) {
    w, h := _prepare(target, scissor, blend)
    if !_bind_texture(0, source) do return
    p := _params(target, w, h, common.Mat3X3_IDENTITY)
    p.color = effect.color
    p.offset = effect.offset
    p.step = effect.step
    p.taps = i32(min(effect.taps, MAX_EFFECT_TAPS))
    p.sigma = max(effect.sigma, 0.001)
    p.tint = effect.tint
    p.shadow = i32(effect.shadow)
    _upload_params(&p)
    // the painter use GL's bottom-up layer rows, so flip v
    quad := vertices
    for &v in quad do v.uv.y = 1 - v.uv.y
    indices := [6]u32{0, 1, 2, 0, 2, 3}
    _stream(&_state.vbuf, &_state.vbuf_cap, .VERTEX_BUFFER, &quad[0], size_of(quad))
    _stream(&_state.ibuf, &_state.ibuf_cap, .INDEX_BUFFER, &indices[0], size_of(indices))
    _set_vertices(_state.layout_quad, _state.vbuf, _state.ibuf, size_of(Vertex))
    _state.ctx->VSSetShader(_state.vs_quad, nil, 0)
    _state.ctx->PSSetShader(_state.ps_effect, nil, 0)
    _state.ctx->DrawIndexed(6, 0, 0)
}

@(private = "file")
_dxgi_format :: proc(format: Pixel_Format) -> (dxgi.FORMAT, int) {
    switch format {
    case .RGBA8: return .R8G8B8A8_UNORM, 4
    case .BGRA8: return .B8G8R8A8_UNORM, 4
    case .R8:    return .R8_UNORM, 1
    // D3D11 has no swizzle to (1, 1, 1, a) like GL, so A8 is stored expanded
    case .A8:    return .R8G8B8A8_UNORM, 4
    }
    return .R8G8B8A8_UNORM, 4
}

@(private = "file")
_expand_alpha :: proc(data: []u8, allocator := context.temp_allocator) -> []u8 {
    out := make([]u8, len(data) * 4, allocator)
    for a, i in data do out[i * 4 + 0], out[i * 4 + 1], out[i * 4 + 2], out[i * 4 + 3] = 255, 255, 255, a
    return out
}

@(private = "file")
_create_texture :: proc(data: []u8, width: int, height: int, format: Pixel_Format) -> Texture {
    dxgi_format, channels := _dxgi_format(format)
    pixels := _expand_alpha(data) if format == .A8 && len(data) > 0 else data
    desc := d3d11.TEXTURE2D_DESC{
        Width = u32(max(width, 1)), Height = u32(max(height, 1)), MipLevels = 1, ArraySize = 1,
        Format = dxgi_format, SampleDesc = {Count = 1}, Usage = .DEFAULT, BindFlags = {.SHADER_RESOURCE},
    }
    init := d3d11.SUBRESOURCE_DATA{pSysMem = raw_data(pixels), SysMemPitch = u32(width * channels)}
    t: D3D_Texture
    _check(_state.device->CreateTexture2D(&desc, &init if len(pixels) > 0 else nil, &t.texture), "CreateTexture2D")
    _check(_state.device->CreateShaderResourceView(cast(^d3d11.IResource)t.texture, nil, &t.srv), "CreateShaderResourceView")
    t.format, t.width, t.height = format, width, height
    append(&_state.textures, t)
    return Texture(len(_state.textures))
}

@(private = "file")
_destroy_texture :: proc(handle: Texture) {
    i := int(handle) - 1
    if i < 0 || i >= len(_state.textures) do return
    _release(&_state.textures[i].srv)
    _release(&_state.textures[i].texture)
}

@(private = "file")
_update_texture :: proc(handle: Texture, data: []u8, rect: common.Rect) -> bool {
    i := int(handle) - 1
    if len(data) == 0 || i < 0 || i >= len(_state.textures) do return false
    t := _state.textures[i]
    if t.texture == nil do return false
    x, y, w, h := int(rect.x), int(rect.y), int(rect.w), int(rect.h)
    if x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > t.width || y + h > t.height do return false
    _, channels := _dxgi_format(t.format)
    source_channels := 1 if t.format == .A8 else channels
    if len(data) < w * h * source_channels do return false
    pixels := _expand_alpha(data[:w * h]) if t.format == .A8 else data
    box := d3d11.BOX{left = u32(x), top = u32(y), right = u32(x + w), bottom = u32(y + h), back = 1}
    _state.ctx->UpdateSubresource(cast(^d3d11.IResource)t.texture, 0, &box, raw_data(pixels), u32(w * channels), 0)
    return true
}

@(private = "file")
_set_texture_filter :: proc(handle: Texture, min, mag, mip: Texture_Filter) {
    i := int(handle) - 1
    if i < 0 || i >= len(_state.textures) do return
    _state.textures[i].nearest = {min == .Nearest, mag == .Nearest}
}

@(private = "file")
_upload_image :: proc(image: ^Image) -> Texture {
    if image == nil do return INVALID_TEXTURE
    if image.texture != INVALID_TEXTURE do return image.texture
    width, height := int(image.w), int(image.h)
    required := width * height * pixel_size(image.format)
    if width <= 0 || height <= 0 || required <= 0 || len(image.data) < required do return INVALID_TEXTURE
    image.texture = _create_texture(image.data[:required], width, height, image.format)
    return image.texture
}

@(private = "file")
_unload_image :: proc(image: ^Image) {
    if image == nil || image.texture == INVALID_TEXTURE do return
    _destroy_texture(image.texture)
    image.texture = INVALID_TEXTURE
}

// make a render texture with sRGB storage, so sampling and blending happen in linear light
@(private = "file")
_render_texture_resources :: proc(width, height: int) -> (t: D3D_Texture, rt: D3D_RT) {
    desc := d3d11.TEXTURE2D_DESC{
        Width = u32(max(width, 1)), Height = u32(max(height, 1)), MipLevels = 1, ArraySize = 1,
        Format = .R8G8B8A8_UNORM_SRGB, SampleDesc = {Count = 1}, Usage = .DEFAULT, BindFlags = {.RENDER_TARGET, .SHADER_RESOURCE},
    }
    _check(_state.device->CreateTexture2D(&desc, nil, &t.texture), "CreateTexture2D render target")
    _check(_state.device->CreateShaderResourceView(cast(^d3d11.IResource)t.texture, nil, &t.srv), "CreateShaderResourceView render target")
    t.format, t.width, t.height = .RGBA8, width, height
    rt.width, rt.height = width, height
    _check(_state.device->CreateRenderTargetView(cast(^d3d11.IResource)t.texture, nil, &rt.rtv), "CreateRenderTargetView")
    desc.Format = .D24_UNORM_S8_UINT
    desc.BindFlags = {.DEPTH_STENCIL}
    _check(_state.device->CreateTexture2D(&desc, nil, &rt.ds), "CreateTexture2D stencil")
    _check(_state.device->CreateDepthStencilView(cast(^d3d11.IResource)rt.ds, nil, &rt.dsv), "CreateDepthStencilView")
    return
}

@(private = "file")
_create_render_texture :: proc(width: int, height: int) -> (Texture, Render_Target) {
    t, rt := _render_texture_resources(width, height)
    append(&_state.textures, t)
    rt.tex_index = len(_state.textures) - 1
    append(&_state.targets, rt)
    return Texture(len(_state.textures)), Render_Target{idx = Texture(len(_state.targets)), w = u32(width), h = u32(height)}
}

@(private = "file")
_destroy_render_target :: proc(handle: Render_Target) {
    i := int(handle.idx) - 1
    if i < 0 || i >= len(_state.targets) do return
    _release(&_state.targets[i].rtv)
    _release(&_state.targets[i].dsv)
    _release(&_state.targets[i].ds)
}

@(private = "file")
_resize :: proc(width, height: int) {
    _state.swapchain_w, _state.swapchain_h = width, height
}

@(private = "file")
_swapchain_size :: proc() -> (int, int) {
    return _state.swapchain_w, _state.swapchain_h
}

@(private = "file")
_read_pixels :: proc(target: Render_Target, allocator: runtime.Allocator) -> ([]u8, int, int) {
    source: ^d3d11.ITexture2D
    w, h: int
    format: dxgi.FORMAT
    if target == INVALID_RENDER_TARGET {
        _ensure_screen()
        if _state.screen_target == INVALID_RENDER_TARGET do return nil, 0, 0
        dirty := _state.screen_dirty
        _resolve_screen()
        // the next present still has to show this frame
        _state.screen_dirty = dirty
        w, h = _state.swapchain_w, _state.swapchain_h
        if _state.encoded_w != w || _state.encoded_h != h {
            _release(&_state.encoded_rtv)
            _release(&_state.encoded)
            desc := d3d11.TEXTURE2D_DESC{
                Width = u32(w), Height = u32(h), MipLevels = 1, ArraySize = 1, Format = .R8G8B8A8_UNORM,
                SampleDesc = {Count = 1}, Usage = .DEFAULT, BindFlags = {.RENDER_TARGET},
            }
            _check(_state.device->CreateTexture2D(&desc, nil, &_state.encoded), "CreateTexture2D encoded")
            _check(_state.device->CreateRenderTargetView(cast(^d3d11.IResource)_state.encoded, nil, &_state.encoded_rtv), "CreateRenderTargetView encoded")
            _state.encoded_w, _state.encoded_h = w, h
        }
        _fullscreen_pass(_state.encoded_rtv, w, h, {0, 0, i32(w), i32(h)}, _state.ps_present, _screen_srv())
        source, format = _state.encoded, .R8G8B8A8_UNORM
    } else {
        i := int(target.idx) - 1
        if i < 0 || i >= len(_state.targets) || _state.targets[i].rtv == nil do return nil, 0, 0
        rt := _state.targets[i]
        source, w, h, format = _state.textures[rt.tex_index].texture, rt.width, rt.height, .R8G8B8A8_UNORM_SRGB
    }

    staging: ^d3d11.ITexture2D
    desc := d3d11.TEXTURE2D_DESC{
        Width = u32(w), Height = u32(h), MipLevels = 1, ArraySize = 1, Format = format,
        SampleDesc = {Count = 1}, Usage = .STAGING, CPUAccessFlags = {.READ},
    }
    _check(_state.device->CreateTexture2D(&desc, nil, &staging), "CreateTexture2D staging")
    defer staging->Release()
    _state.ctx->CopyResource(cast(^d3d11.IResource)staging, cast(^d3d11.IResource)source)
    mapped: d3d11.MAPPED_SUBRESOURCE
    _check(_state.ctx->Map(cast(^d3d11.IResource)staging, 0, .READ, {}, &mapped), "Map staging")
    defer _state.ctx->Unmap(cast(^d3d11.IResource)staging, 0)
    data := make([]u8, w * h * 4, allocator)
    for y in 0 ..< h {
        mem.copy(&data[y * w * 4], rawptr(uintptr(mapped.pData) + uintptr(y * int(mapped.RowPitch))), w * 4)
    }
    return data, w, h
}

@(private = "file")
_stencil_clear :: proc() {
    if _state.bound_dsv != nil do _state.ctx->ClearDepthStencilView(_state.bound_dsv, {.STENCIL}, 1, 0)
}

@(private = "file")
_stencil_push_clip :: proc() {
    _state.stencil_depth += 1
    bit := u8(1) << u8(_state.stencil_depth)
    _state.stencil = {func = .ALWAYS, write = bit, pass = .ZERO, color = false}
    w, h := _prepare(_state.layer, nil, .Opaque)
    fullscreen := [4]Vertex{{pos = {0, 0}}, {pos = {f32(w), 0}}, {pos = {f32(w), f32(h)}}, {pos = {0, f32(h)}}}
    indices := [6]u32{0, 1, 2, 0, 2, 3}
    p := D3D_Params{resolution = {f32(w), f32(h)}, transform = _columns(common.Mat3X3_IDENTITY)}
    _upload_params(&p)
    _stream(&_state.vbuf, &_state.vbuf_cap, .VERTEX_BUFFER, &fullscreen[0], size_of(fullscreen))
    _stream(&_state.ibuf, &_state.ibuf_cap, .INDEX_BUFFER, &indices[0], size_of(indices))
    _set_vertices(_state.layout_quad, _state.vbuf, _state.ibuf, size_of(Vertex))
    _state.ctx->VSSetShader(_state.vs_quad, nil, 0)
    _state.ctx->PSSetShader(_state.ps_quad, nil, 0)
    _state.ctx->DrawIndexed(6, 0, 0)
    _state.stencil = {func = .ALWAYS, ref = bit, read = bit, write = bit, pass = .REPLACE, color = false}
}

@(private = "file")
_stencil_use_clip :: proc() {
    bit := u8(1) << u8(_state.stencil_depth)
    _state.stencil = {func = .EQUAL, ref = bit, read = bit, pass = .KEEP, color = true}
}

@(private = "file")
_stencil_pop_clip :: proc() {
    if _state.stencil_depth > 0 do _state.stencil_depth -= 1
    if _state.stencil_depth == 0 {
        _state.stencil = STENCIL_IDLE
    } else {
        bit := u8(1) << u8(_state.stencil_depth)
        _state.stencil = {func = .EQUAL, ref = bit, read = bit, pass = .KEEP, color = true}
    }
}

@(private = "file")
_layer_begin :: proc(target: Render_Target) -> int {
    token := _state.stencil_depth
    _state.stencil_depth = 0
    _state.layer = target
    _bind_target(target)
    clear := [4]f32{}
    if _state.bound_rtv != nil do _state.ctx->ClearRenderTargetView(_state.bound_rtv, &clear)
    if _state.bound_dsv != nil do _state.ctx->ClearDepthStencilView(_state.bound_dsv, {.STENCIL}, 1, 0)
    _state.stencil = STENCIL_IDLE
    return token
}

@(private = "file")
_layer_end :: proc(parent: Render_Target, token: int) {
    _state.layer = parent
    _state.stencil_depth = token + 1
    _bind_target(parent)
    _stencil_pop_clip()
}

RENDERER_D3D11 :: Renderer {
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
    layer_begin           = _layer_begin,
    layer_end             = _layer_end,
    draw_effect           = _draw_effect,
}
