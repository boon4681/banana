package node

import "core:c"
import "core:strings"
import "base:runtime"
import "src:core/common"
import "src:core/painter"
import "src:core/events"
import YG "src:yoga"

MeasureMode     :: YG.MeasureMode
MeasureCallback :: proc(self: ^Node, w: f32, w_mode: MeasureMode, h: f32, h_mode: MeasureMode) -> (out_w, out_h: f32)
ClipMode        :: painter.ClipMode
UNDEFINED       :: YG.UNDEFINED
INFINITY        :: YG.INFINITY
NEG_INFINITY    :: YG.NEG_INFINITY

Node_Error :: enum {
    None,
    NODE_PANIC_NOT_AWAKE,
}

Node_Error_Map := [Node_Error]string{
    .None                 = "none",
    .NODE_PANIC_NOT_AWAKE = "error node not awake properly",
}

BaseNode :: struct {
    raw:      YG.NodeRef,
    window:   rawptr,
    key:      string,
    parent:   ^BaseNode,
    children: [dynamic]^BaseNode,

    rect:            common.Rect,
    transform:       common.Transform,
    data:            rawptr,
    _internal_style: rawptr, // must not assign directly from node initialization; it should be assigned via Set_Style

    z_index:                  i32,
    creates_stacking_context: bool,

    // Local-space clip rect. Defaults to the node's own padding box when active.
    // `clip_mode` decides how it's enforced (axis-aligned scissor vs stencil).
    clip_mode: ClipMode,
    clip_rect: Maybe(common.Rect),
    // Which axes `clip_mode` constrains.
    clip_x: bool,
    clip_y: bool,

    bus: events.Bus,

    draw:    proc(self: ^BaseNode), // `draw` is function that user override to render things. Get the active painter with painter.get().
    process: proc(self: ^BaseNode), // this is update method for node logic in user space

    add:            proc(self: ^BaseNode, kids: ..^BaseNode) -> ^BaseNode,
    compute_layout: proc(self: ^BaseNode, width: f32 = UNDEFINED, height: f32 = UNDEFINED, dir: YG.Direction = .LTR),
    find:           proc(self: ^BaseNode, path: string) -> ^BaseNode,
    get_rect:       proc(self: ^BaseNode, which: RectType = .Border) -> common.Rect,
    free:           proc(self: ^BaseNode),
    queue_free:     proc(self: ^BaseNode) -> Node_Error,
    apply_measure:  proc(self: ^BaseNode),
    measure:        MeasureCallback,
    dirty:          proc(self: ^BaseNode),

    on:        proc(n: ^BaseNode, type: string, cb: proc(s: ^events.Signal), capture := false, once := false) -> uint,
    off:       proc(n: ^BaseNode, type: string, cb: proc(s: ^events.Signal)),
    on_awake:  proc(self: ^BaseNode), // EVENT fired after node being awake
    on_free:   proc(self: ^BaseNode), // EVENT CALLBACK fired before free
    on_layout: proc(self: ^BaseNode), // EVENT CALLBACK fired before layout update

    awaken:      bool,
    freed:       bool,
    queued_free: bool,
    // Internal awake is for node extend node internal setup
    // So i can do somekind of stupid polymorphism
    _internal_propagate_awake: proc(self: ^BaseNode),
}

Node :: struct {
    using _internal_node: BaseNode,
    style: proc(self: ^Node) -> ^Style
}

RectType :: enum {
	Border,  // the laid-out frame (left/top/width/height as Yoga reports)
	Padding, // border box minus border
	Content, // padding box minus padding
	Margin,  // border box plus margin
}

New :: proc(key: Maybe(string) = nil) -> ^Node {
    n := new(Node)
    Init(n, key)
    Set_Style(n, new(Style))
    Init_Style(n)
    n.style = _get_style
    n.on_free = _free_base_style
    return n
}

@(private="file")
_get_style := proc(self: ^Node) -> ^Style {
    return cast(^Style)self._internal_style
}

@(private="file")
_free_base_style :: proc(self: ^Node) {
    free(self._internal_style)
}

// Initializes an embedded Node in place so widget structs
// can extend Node without re-implementing the method table wiring.
Init :: proc(n: ^Node, key: Maybe(string) = nil) {
    n.raw = YG.NodeNew()
    if key, ok := key.?; ok do n.key = key

    n.transform = common.IDENTITY_TRANSFORM
    n.draw = _node_draw

    n.add = _node_add
    n.compute_layout = _node_compute_layout
    n.find = _node_find
    n.get_rect = _node_get_rect
    n.apply_measure = _apply_measure
    n.queue_free = _queue_free
    n.free = _node_free
    n.dirty = _node_dirty
    n.on = _on
    n.off = _off

    YG.NodeSetContext(n.raw, n)
}

@(private="file")
_node_draw :: proc(self: ^Node) {
    // @empty
    // for user or component to override
}

@(private="file")
_node_dirty :: proc(self: ^Node) {
    YG.NodeMarkDirty(self.raw)
}

@(private="file")
_apply_measure :: proc(self: ^Node) {
    YG.NodeSetMeasureFunc(self.raw, _measure_trampoline)
}

@(private="file")
_measure_trampoline :: proc "c" (
	node: YG.NodeRef,
	width: f32,
	width_mode: YG.MeasureMode,
	height: f32,
	height_mode: YG.MeasureMode,
) -> YG.Size {
    context = runtime.default_context()
    n := cast(^Node)YG.NodeGetContext(node)
    if n == nil || n.measure == nil do return YG.Size{0, 0}
    w, h := n.measure(n, width, width_mode, height, height_mode)
    return YG.Size{w, h}
}

@(private="file")
_node_add :: proc (self: ^BaseNode, kids: ..^BaseNode) -> ^BaseNode {
    for k in kids {
        k.parent = self
        YG.NodeInsertChild(self.raw, k.raw, c.size_t(len(self.children)))
        if k.window != nil {
            if k._internal_propagate_awake == nil {
                panic("EXIT ERROR NODE IS NOT SETUP PROPERLY")
            }
            k->_internal_propagate_awake()
        }
        append(&self.children, k)
    }
    return self
}

@(private="file")
_node_compute_layout :: proc(self: ^Node, width: f32 = UNDEFINED, height: f32 = UNDEFINED, dir: YG.Direction = .LTR) {
    w := width
    h := height
    if YG.IsNaN(w) do w = YG.NodeStyleGetWidth(self.raw).value
    if YG.IsNaN(h) do h = YG.NodeStyleGetHeight(self.raw).value
    YG.NodeCalculateLayout(self.raw, w, h, dir)
}

@(private="file")
_node_find :: proc(self: ^BaseNode, path: string) -> ^BaseNode {
    p := strings.trim_prefix(path, "/")
    if p == "" do return self

    segments := strings.split(p, "/")
    defer delete(segments)

    cur := self
    outer: for seg in segments {
        found := _find_descendant_by_key(cur, seg)
        if found == nil do return nil
        cur = found
    }
    return cur
}

@(private="file")
_node_inset :: proc(r: YG.NodeRef, get: proc "c" (n: YG.NodeRef, e: YG.Edge) -> f32) -> (l, t, right, b: f32) {
    return get(r, .Left), get(r, .Top), get(r, .Right), get(r, .Bottom)
}

@(private="file")
_node_get_rect :: proc(self: ^Node, which: RectType = .Border) -> common.Rect {
    r := self.raw
    left   := YG.NodeLayoutGetLeft(r)
    top    := YG.NodeLayoutGetTop(r)
    width  := YG.NodeLayoutGetWidth(r)
    height := YG.NodeLayoutGetHeight(r)

    switch which {
    case .Border:
        // As reported by the border box.
    case .Padding:
        bl, bt, br, bb := _node_inset(r, YG.NodeLayoutGetBorder)
        left += bl; top += bt; width -= bl + br; height -= bt + bb
    case .Content:
        bl, bt, br, bb := _node_inset(r, YG.NodeLayoutGetBorder)
        pl, pt, pr, pb := _node_inset(r, YG.NodeLayoutGetPadding)
        left += bl + pl; top += bt + pt
        width  -= bl + br + pl + pr
        height -= bt + bb + pt + pb
    case .Margin:
        ml, mt, mr, mb := _node_inset(r, YG.NodeLayoutGetMargin)
        left -= ml; top -= mt; width += ml + mr; height += mt + mb
    }
    return common.Rect{x = left, y = top, w = width, h = height}
}

@(private="file")
_queue_free :: proc(self: ^BaseNode) -> Node_Error{
    return Node_Error.NODE_PANIC_NOT_AWAKE
}

@(private="file")
_node_free :: proc(self: ^BaseNode) {
    if self == nil || self.freed do return
    self.freed = true

    for c in self.children do _node_free(c)
    delete(self.children)

    if self.on_free != nil do self.on_free(self)
    events.bus_destroy(&self.bus)

    if self.parent == nil {
        YG.NodeFreeRecursive(self.raw)
    }
    free(self)
}

@(private="file")
_on :: proc(n: ^Node, type: string, cb: proc(s: ^events.Signal), capture := false, once := false) -> uint {
    return events.on(&n.bus, type, cb, capture, once)
}

@(private="file")
_off :: proc(n: ^Node, type: string, cb: proc(s: ^events.Signal)) {
    events.off(&n.bus, type, cb)
}

@(private="file")
_find_descendant_by_key :: proc(root: ^BaseNode, key: string) -> ^BaseNode {
    for c in root.children {
        if c.key == key do return c
    }
    for c in root.children {
        if hit := _find_descendant_by_key(c, key); hit != nil do return hit
    }
    return nil
}
