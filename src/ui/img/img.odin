package img

import "core:strings"
import "core:time"
import "src:core/common"
import "src:core/layout"
import "src:core/node"
import "src:core/painter"
import "src:core/platform"
import "src:core/render"
import "src:core/svg"

// Mirrors CSS object-fit.
Fit :: enum {
    Fill,       // stretch to the layout rect, ignoring aspect ratio
    Contain,    // scale down to fit entirely, centered
    Cover,      // scale up to cover, cropping the overflow
    None,       // intrinsic size, centered
    Scale_Down, // the smaller of None and Contain
}

Img_Style :: struct {
    using base: Style,
    tint: Color,
    fit:  Fit,
}

Error :: enum {
    None,
    Empty_Input,
    Input_Too_Large,
    File_Read_Failed,
    Decode_Failed,
    Invalid_Dimensions,
    Allocation_Failed,
    Invalid_Svg,
}

Img_Node :: struct {
    using node: Node,
    style:     proc(self: ^Img_Node) -> ^Img_Style,
    set_src:   proc(self: ^Img_Node, src: string),
    set_bytes: proc(self: ^Img_Node, encoded: []u8) -> Error,
    get_src:   proc(self: ^Img_Node) -> string,
    // Result of the most recent decode; .None until a pending src is resolved.
    get_error: proc(self: ^Img_Node) -> Error,
    type:      proc(self: ^Img_Node) -> _Kind,

    // Animation. A still image reports one frame and ignores play/pause.
    frame_count: proc(self: ^Img_Node) -> int,
    play:        proc(self: ^Img_Node),
    pause:       proc(self: ^Img_Node),
    is_paused:   proc(self: ^Img_Node) -> bool,
    seek:        proc(self: ^Img_Node, frame: int),
}

@(private="file")
_Kind :: enum {
    Empty,
    Raster,
    Vector,
}

@(private="file")
_Img_Data :: struct {
    src:     string,
    kind:    _Kind,
    pending: bool, // src set but not decoded yet
    err:     Error,

    window: ^platform.Window,       // window the raster frames belong to
    frames: []platform.Image_Frame, // .Raster; length 1 for still images
    frame:  int,
    clock:  f32, // seconds accumulated on the current frame
    last:   time.Tick,
    paused: bool,
    doc:    svg.Document,      // .Vector
    cache:  svg.Cache,
}

New :: proc(src: string = "", style: Img_Style = {}, key: Maybe(string) = nil) -> ^Img_Node {
    n := new(Img_Node)
    node.Init(auto_cast(n), key)
    n.style = _get_style
    n.set_src = _set_src
    n.set_bytes = _set_bytes
    n.get_src = _get_src
    n.get_error = _get_error
    n.type = _type
    n.frame_count = _frame_count
    n.play = _play
    n.pause = _pause
    n.is_paused = _is_paused
    n.seek = _seek
    n.data = new(_Img_Data)
    st := style
    if st.tint == {} do st.tint = common.COLOR_WHITE
    node.Set_Style(auto_cast(n), new_clone(st))
    node.Init_Style(auto_cast(n))
    n.draw = transmute(proc(self: ^Node))_draw
    n.process = transmute(proc(self: ^Node))_process
    n.on_awake = transmute(proc(self: ^Node))_awake
    n.on_free = transmute(proc(self: ^Node))_free
    n.measure = transmute(node.MeasureCallback)_measure
    n->apply_measure()
    _set_src(n, src)
    return n
}

@(private="file")
_data :: proc(n: ^Img_Node) -> ^_Img_Data {
    return auto_cast(n.data)
}

@(private="file")
_get_style :: proc(n: ^Img_Node) -> ^Img_Style {
    return auto_cast(n._internal_style)
}

@(private="file")
_get_src :: proc(n: ^Img_Node) -> string {
    return _data(n).src
}

@(private="file")
_get_error :: proc(n: ^Img_Node) -> Error {
    return _data(n).err
}

@(private="file")
_type :: proc(n: ^Img_Node) -> _Kind {
    return _data(n).kind
}

@(private="file")
_frame_count :: proc(n: ^Img_Node) -> int {
    return len(_data(n).frames)
}

@(private="file")
_is_animated :: proc(n: ^Img_Node) -> bool {
    return len(_data(n).frames) > 1
}

@(private="file")
_play :: proc(n: ^Img_Node) {
    d := _data(n)
    if !d.paused do return
    d.paused = false
    // Drop the tick from before the pause so the gap isn't credited to the clock.
    d.last = {}
}

@(private="file")
_pause :: proc(n: ^Img_Node) {
    _data(n).paused = true
}

@(private="file")
_is_paused :: proc(n: ^Img_Node) -> bool {
    return _data(n).paused
}

@(private="file")
_seek :: proc(n: ^Img_Node, frame: int) {
    d := _data(n)
    if len(d.frames) == 0 do return
    next := frame %% len(d.frames)
    if next == d.frame do return
    d.frame = next
    d.clock = 0
}

@(private="file")
_release :: proc(d: ^_Img_Data) {
    switch d.kind {
    case .Raster:
        platform.free_image_frames(d.window, d.frames)
    case .Vector:
        svg.cache_destroy(&d.cache)
        svg.destroy(&d.doc)
    case .Empty:
    }
    d.frames = nil
    d.frame = 0
    d.clock = 0
    d.last = {}
    d.window = nil
    d.kind = .Empty
}

@(private="file")
_current :: proc(d: ^_Img_Data) -> ^render.Image {
    if d.kind != .Raster || len(d.frames) == 0 do return nil
    return d.frames[d.frame].image
}

// Guessing is it svg, mu hahahhahhahaha
@(private)
_looks_like_svg :: proc(encoded: []u8) -> bool {
    s := strings.trim_left_space(string(encoded))
    if strings.has_prefix(s, "<svg") do return true
    // An XML prolog or DOCTYPE may precede the root element.
    if strings.has_prefix(s, "<?xml") || strings.has_prefix(s, "<!DOCTYPE") || strings.has_prefix(s, "<!--") {
        return strings.contains(s, "<svg")
    }
    return false
}

@(private="file")
_load :: proc(n: ^Img_Node, encoded: []u8) -> Error {
    d := _data(n)

    if _looks_like_svg(encoded) {
        doc, err := svg.parse(string(encoded))
        if err != .None do return .Invalid_Svg
        _release(d)
        d.doc = doc
        d.kind = .Vector
        n->dirty()
        return .None
    }

    w := layout.get_window(auto_cast(n))
    if w == nil do return .Decode_Failed
    frames, err := platform.load_image_frames(w, encoded)
    if err != .None do return _raster_error(err)
    _release(d)
    d.frames = frames
    d.window = w
    d.kind = .Raster
    n->dirty()
    return .None
}

@(private="file")
_raster_error :: proc(err: platform.Image_Error) -> Error {
    switch err {
    case .None:               return .None
    case .Empty_Input:        return .Empty_Input
    case .Input_Too_Large:    return .Input_Too_Large
    case .File_Read_Failed:   return .File_Read_Failed
    case .Decode_Failed:      return .Decode_Failed
    case .Invalid_Dimensions: return .Invalid_Dimensions
    case .Allocation_Failed:  return .Allocation_Failed
    }
    return .Decode_Failed
}

@(private="file")
_awake :: proc(n: ^Img_Node){
    d := _data(n)
    if !d.pending do return
    if layout.get_window(auto_cast(n)) == nil do return
    d.pending = false

    encoded, ok := _read_source(d.src)
    if !ok {
        d.err = .File_Read_Failed
        return
    }
    defer delete(encoded)
    d.err = _load(n, encoded)
}

@(private="file")
_set_src :: proc(n: ^Img_Node, src: string) {
    d := _data(n)
    delete(d.src)
    d.err = .None
    if src == "" {
        d.src = ""
        d.pending = false
        _release(d)
        n->dirty()
        return
    }
    d.src = strings.clone(src)
    d.pending = true
    n->dirty()
}

@(private="file")
_set_bytes :: proc(n: ^Img_Node, encoded: []u8) -> Error {
    d := _data(n)
    if len(encoded) == 0 {
        d.err = .Empty_Input
        return d.err
    }
    err := _load(n, encoded)
    d.err = err
    if err != .None do return err
    delete(d.src)
    d.src = ""
    d.pending = false
    return .None
}

@(private="file")
_intrinsic :: proc(d: ^_Img_Data) -> (w, h: f32) {
    switch d.kind {
    case .Raster:
        if img := _current(d); img != nil do return f32(img.w), f32(img.h)
    case .Vector:
        return max(d.doc.view_box.w, 0), max(d.doc.view_box.h, 0)
    case .Empty:
    }
    return 0, 0
}

@(private="file")
_process :: proc(n: ^Img_Node) {
    d := _data(n)
    if d.kind != .Raster || len(d.frames) < 2 || d.paused do return

    now := time.tick_now()
    if d.last != {} {
        dt := f32(time.duration_seconds(time.tick_diff(d.last, now)))
        d.clock += min(dt, 0.25)
    }
    d.last = now
    _step(d.frames, &d.frame, &d.clock)
}

@(private)
_step :: proc(frames: []platform.Image_Frame, frame: ^int, clock: ^f32) -> bool {
    advanced := false
    // `for` rather than `if`: delays shorter than one frame time would
    // otherwise fall permanently behind.
    for clock^ >= frames[frame^].delay {
        delay := frames[frame^].delay
        if delay <= 0 do break
        clock^ -= delay
        frame^ = (frame^ + 1) % len(frames)
        advanced = true
    }
    return advanced
}

@(private="file")
_measure :: proc(n: ^Img_Node, w: f32, wm: node.MeasureMode, h: f32, hm: node.MeasureMode) -> (ow, oh: f32) {
    iw, ih := _intrinsic(_data(n))
    ow, oh = iw, ih
    if wm == .Exactly do ow = w
    if hm == .Exactly do oh = h
    if wm == .AtMost do ow = min(ow, w)
    if hm == .AtMost do oh = min(oh, h)

    if iw <= 0 || ih <= 0 do return ow, oh

    w_fixed := wm != .Undefined
    h_fixed := hm != .Undefined
    if w_fixed && !h_fixed {
        oh = ow * ih / iw
    } else if h_fixed && !w_fixed {
        ow = oh * iw / ih
    }
    return ow, oh
}

@(private)
_fit_rect :: proc(dst: common.Rect, iw, ih: f32, fit: Fit) -> common.Rect {
    if iw <= 0 || ih <= 0 do return dst

    s: f32
    switch fit {
    case .Fill:       return dst
    case .Contain:    s = min(dst.w / iw, dst.h / ih)
    case .Cover:      s = max(dst.w / iw, dst.h / ih)
    case .None:       s = 1
    case .Scale_Down: s = min(1, min(dst.w / iw, dst.h / ih))
    }

    r := dst
    r.w = iw * s
    r.h = ih * s
    r.x += (dst.w - r.w) * 0.5
    r.y += (dst.h - r.h) * 0.5
    return r
}

@(private="file")
_draw :: proc(n: ^Img_Node) {
    d := _data(n)
    if d.kind == .Empty do return

    iw, ih := _intrinsic(d)
    if iw <= 0 || ih <= 0 do return

    st := n->style()
    dst := _fit_rect(n.rect, iw, ih, st.fit)
    p := painter.get()

    crop := dst.w > n.rect.w + 0.5 || dst.h > n.rect.h + 0.5
    if crop do painter.push_clip(p, n.rect, .Scissor)
    switch d.kind {
    case .Raster:
        painter.image(p, _current(d), dst, st.tint)
    case .Vector:
        svg.draw_cached(&d.doc, p, &d.cache, dst, false, st.tint)
    case .Empty:
    }
    if crop do painter.pop_clip(p)
}

@(private="file")
_free :: proc(n: ^Img_Node) {
    d := _data(n)
    _release(d)
    delete(d.src)
    free(d)
    free(n._internal_style)
}
