package node

import "core:fmt"
import "core:c"
import "core:strings"
import "base:runtime"
import "src:core/common"
import "src:core/painter"
import "src:core/events"
import "src:core/redraw"
import YG "src:yoga"

MeasureMode     :: YG.MeasureMode
MeasureCallback :: proc(self: ^Node, w: f32, w_mode: MeasureMode, h: f32, h_mode: MeasureMode) -> (out_w, out_h: f32)
Hook_Callback   :: proc(self: ^BaseNode, ctx: rawptr)

Hooks :: enum {
    After_Awake,
    After_Layout,
    Before_Free,
}

Hook_Entry :: struct {
    callback: Hook_Callback,
    ctx:      rawptr,
}

@(private="file", thread_local)
_measure_ctx: runtime.Context

@(private="file", thread_local)
_measure_ctx_set: bool

ClipMode     :: painter.ClipMode
UNDEFINED    :: YG.UNDEFINED
INFINITY     :: YG.INFINITY
NEG_INFINITY :: YG.NEG_INFINITY

Node_Error :: enum {
    None,
    NODE_PANIC_NOT_AWAKE,
}

Node_Error_Map := [Node_Error]string{
    .None                 = "none",
    .NODE_PANIC_NOT_AWAKE = "error node not awake properly",
}

Scroll_Port :: struct {
    offset:   [2]f32,
    viewport: common.Rect,
    // `offset` can change between layouts; rects stay at `applied` until the next one.
    applied:  [2]f32,
    update:   proc(self: ^BaseNode, laid_out: bool),
    draw:     proc(self: ^BaseNode),
    range:    [2]f32,
    move:     proc(self: ^BaseNode, x, y: f32),
    inner:    ^BaseNode,
}

Flex_Pin :: struct {
    basis:  YG.Value,
    grow:   f32,
    shrink: f32,
    held:   f32,
}

// scroll hook live in this file cuz core/scroll import node
scrollable_changed: proc(n: ^BaseNode, x, y: bool)

BaseNode :: struct {
    raw:                YG.NodeRef,
    window:             rawptr,
    type_id:            typeid,
    key:                string,
    parent:             ^BaseNode,
    children:           [dynamic]^BaseNode, // child elements
    _internal_children: [dynamic]^BaseNode, // what Yoga lays out: `children` plus the fragments mounted here
    structural:         bool,               // fragment: boxless, its members are laid out in `parent` right before it
    owner:              ^BaseNode,          // the fragment this node is a member of
    result:             rawptr,             // the node itself unless its builder exposes another value
    result_type:        typeid,
    rect:               common.Rect,
    data:               rawptr,
    _internal_style:    rawptr, // must not assign directly from node initialization; it should be assigned via Set_Style

    z_index:                  i32,
    creates_stacking_context: bool,

    // Local-space clip rect. Defaults to the node's own padding box when active.
    // `clip_mode` decides how it's enforced (axis-aligned scissor vs stencil).
    clip_mode:     ClipMode,
    clip_rect:     Maybe(common.Rect),
    clip_radius:   common.Radii,
    corner_radius: common.Radii,
    scroll:        ^Scroll_Port,
    focusable:     bool, // takes keyboard focus on click and in Tab order
    text_entry:    bool, // types text, so its focus is always shown
    // Which axes `clip_mode` constrains.
    clip_x:        bool,
    clip_y:        bool,

    bus: events.Bus,

    draw:    proc(self: ^BaseNode), // `draw` is function that user override to render things. Get the active painter with painter.get().
    process: proc(self: ^BaseNode), // this is update method for node logic in user space

    // Optional read-only text capability.
    using text_content: ^Text_Content_Interface,

    add:            proc(self: ^BaseNode, kids: ..^BaseNode) -> ^BaseNode,
    insert:         proc(self: ^BaseNode, kid: ^BaseNode, index: int) -> ^BaseNode,
    remove:         proc(self: ^BaseNode, kid: ^BaseNode) -> ^BaseNode,
    index_of:       proc(self: ^BaseNode, kid: ^BaseNode) -> int,
    add_hook:       proc(self: ^BaseNode, at: Hooks, callback: Hook_Callback, ctx: rawptr = nil),
    remove_hook:    proc(self: ^BaseNode, at: Hooks, callback: Hook_Callback, ctx: rawptr = nil) -> bool,
    run_hooks:      proc(self: ^BaseNode, at: Hooks),
    compute_layout: proc(self: ^BaseNode, width: f32 = UNDEFINED, height: f32 = UNDEFINED, dir: YG.Direction = .LTR),
    find:           proc(self: ^BaseNode, path: string) -> ^BaseNode,
    // first descendant with the key, nearest level first
    get_by_key:     proc(self: ^BaseNode, key: string) -> ^BaseNode,
    // direct child with the key
    child:          proc(self: ^BaseNode, key: string) -> ^BaseNode,
    // nearest ancestor with the key
    closest:        proc(self: ^BaseNode, key: string) -> ^BaseNode,
    // first descendant matching `tag#key.class`, in tree order
    query:          proc(self: ^BaseNode, selector: string) -> ^BaseNode,
    query_all:      proc(self: ^BaseNode, selector: string, allocator := context.temp_allocator) -> []^BaseNode,
    get_rect:       proc(self: ^BaseNode, which: RectType = .Border) -> common.Rect,
    // Frees every child of an element or member of a fragment.
    clear:          proc(self: ^BaseNode),
    // Turns a node into a fragment. Call before it has members or a parent.
    make_fragment:  proc(self: ^BaseNode),
    free:           proc(self: ^BaseNode),
    queue_free:     proc(self: ^BaseNode) -> Node_Error,
    apply_measure:  proc(self: ^BaseNode),
    measure:        MeasureCallback,
    // min_content is here cuz Yoga measure callback clamps to the space on offer, so a squeezed leaf cannot report its content size through it.
    min_content:    proc(self: ^BaseNode) -> [2]f32,
    flex_pin:       ^Flex_Pin,
    free_flex_pin:  proc(self: ^BaseNode),
    dirty:          proc(self: ^BaseNode),
    // What the node shows changed, so its window paints a frame. `style()` calls it.
    // use when you want to make a node repaint.
    damage:         proc(self: ^BaseNode, loc := #caller_location),
    // This is what decides where a frame is repainted and whether `draw` runs.
    // The default is `rect` grown by its shadows and outline.
    paint_box:      proc(self: ^BaseNode) -> common.Rect,
    // Call on a root once its tree is laid out: reports where damaged and moved nodes are now.
    settle_damage:  proc(self: ^BaseNode),
    // `rect` as of the last settle_damage, to tell what layout moved.
    shown:          common.Rect,
    // The redraw epoch this node was damaged in. Nodes under it need no record of their own.
    damage_epoch:   u64,
    on:             proc(self: ^BaseNode, type: string, cb: events.Callback, capture := false, once := false) -> uint,
    off:            proc(self: ^BaseNode, type: string, cb: events.Callback),
    on_awake:       proc(self: ^BaseNode), // EVENT fired after node being awake
    on_free:        proc(self: ^BaseNode), // EVENT CALLBACK fired before free
    on_layout:      proc(self: ^BaseNode), // EVENT CALLBACK fired before layout update

    // Callback context ownership remains with the registering system.
    hooks: map[Hooks][dynamic]Hook_Entry,

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
	Border,  // left/top/width/height as Yoga
	Padding, // border box minus border
	Content, // padding box minus padding
	Margin,  // border box plus margin
}

is_hidden :: proc(n: ^BaseNode) -> bool {
    return n == nil || YG.NodeStyleGetDisplay(n.raw) == .None
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
    self->damage()
    return cast(^Style)self._internal_style
}

@(init, private)
_install_redraw_name :: proc "contextless" () {
    redraw.name_of = _redraw_name
}

@(private="file")
_redraw_name :: proc(raw: rawptr) -> string {
    n := cast(^BaseNode)raw
    parts := make([dynamic]string, context.temp_allocator)
    for at := n; at != nil; at = at.parent {
        inject_at(&parts, 0, at.key if at.key != "" else fmt.tprint(at.type_id))
    }
    return strings.join(parts[:], "/", context.temp_allocator)
}

@(private="file")
_free_base_style :: proc(self: ^BaseNode) {
    free(self._internal_style)
}

Init :: proc(n: ^$T, key: Maybe(string) = nil) {
    n.raw = YG.NodeNew()
    n.type_id = T
    n.result = n
    n.result_type = T
    if key, ok := key.?; ok do n.key = key

    n.draw = _node_draw

    n.add = _node_add
    n.insert = _node_insert
    n.remove = _node_remove
    n.index_of = _node_index_of
    n.add_hook = _add_hook
    n.remove_hook = _remove_hook
    n.run_hooks = _run_hooks
    n.compute_layout = _node_compute_layout
    n.find = _node_find
    n.get_by_key = _node_get_by_key
    n.child = _node_child
    n.closest = _node_closest
    n.query = _node_query
    n.query_all = _node_query_all
    n.get_rect = _node_get_rect
    n.apply_measure = _apply_measure
    n.queue_free = _queue_free
    n.free = _node_free
    n.clear = _node_clear
    n.make_fragment = _node_make_fragment
    n.free_flex_pin = _node_free_flex_pin
    n.dirty = _node_dirty
    n.damage = _node_damage
    n.paint_box = _node_paint_box
    n.settle_damage = _node_settle_damage
    n.on = _on
    n.off = _off
    events.bus_init(&n.bus)

    YG.NodeSetContext(n.raw, n)
}

@(private="file")
_node_draw :: proc(self: ^BaseNode) {
    // @empty
    // for user or component to override
}

@(private="file")
_node_dirty :: proc(self: ^BaseNode) {
    // Content that measures differently is drawn differently, even when it ends up the same size.
    self->damage()
    YG.NodeMarkDirty(self.raw)
}

@(private="file")
_apply_measure :: proc(self: ^BaseNode) {
    _capture_measure_context()
    YG.NodeSetMeasureFunc(self.raw, _measure_trampoline)
}

@(private="file")
_capture_measure_context :: proc() {
    _measure_ctx = context
    _measure_ctx_set = true
}

@(private="file")
_measure_trampoline :: proc "c" (
	node:        YG.NodeRef,
	width:       f32,
	width_mode:  YG.MeasureMode,
	height:      f32,
	height_mode: YG.MeasureMode,
) -> YG.Size {
    context = _measure_ctx if _measure_ctx_set else runtime.default_context()
    n := cast(^Node)YG.NodeGetContext(node)
    if n == nil || n.measure == nil do return YG.Size{0, 0}
    w, h := n.measure(n, width, width_mode, height, height_mode)
    return YG.Size{w, h}
}

@(private="file")
_node_add :: proc (self: ^BaseNode, kids: ..^BaseNode) -> ^BaseNode {
    for k in kids {
        _node_insert(self, k, len(self.children))
    }
    return self
}

@(private="file")
_node_free_flex_pin :: proc(self: ^BaseNode) {
    if self.flex_pin != nil do free(self.flex_pin, runtime.heap_allocator())
    self.flex_pin = nil
}

@(private="file")
_node_make_fragment :: proc(self: ^BaseNode) {
    self.structural = true
    YG.NodeStyleSetDisplay(self.raw, .None)
}

@(private="file")
_node_clear :: proc(self: ^BaseNode) {
    if self == nil do return
    if self.structural {
        for len(self.children) > 0 {
            kid := self.children[len(self.children) - 1]
            _node_remove(self, kid)
            _node_free(kid)
        }
        return
    }
    tops := make([dynamic]^BaseNode, 0, len(self._internal_children), context.temp_allocator)
    for kid in self._internal_children {
        if kid.owner == nil do append(&tops, kid)
    }
    for kid in tops {
        _node_remove(self, kid)
        _node_free(kid)
    }
}

@(private="file")
_first_real :: proc(n: ^BaseNode) -> ^BaseNode {
    if n.structural && len(n.children) > 0 do return _first_real(n.children[0])
    return n
}

@(private="file")
_real_index :: proc(parent, kid: ^BaseNode) -> int {
    #reverse for child, i in parent._internal_children {
        if child == kid do return i
    }
    return -1
}

@(private="file")
_place :: proc(parent, k, before: ^BaseNode) {
    real := len(parent._internal_children)
    if before != nil {
        if found := _real_index(parent, before); found >= 0 do real = found
    }
    k.parent = parent
    parent->damage()
    YG.NodeInsertChild(parent.raw, k.raw, c.size_t(real))
    if !k.structural {
        public := len(parent.children)
        if real < len(parent._internal_children) {
            public = 0
            for sibling in parent._internal_children[:real] {
                if !sibling.structural do public += 1
            }
        }
        inject_at(&parent.children, public, k)
    }
    inject_at(&parent._internal_children, real, k)

    if k.structural {
        k.window = parent.window
        k._internal_propagate_awake = parent._internal_propagate_awake
        if parent.awaken && !k.awaken && k._internal_propagate_awake != nil do k->_internal_propagate_awake()
        return
    }
    if k.window != nil && !k.awaken {
        if k._internal_propagate_awake == nil {
            panic("EXIT ERROR NODE IS NOT SETUP PROPERLY")
        }
        k->_internal_propagate_awake()
    }
    if parent.window != nil && parent._internal_propagate_awake != nil && !k.awaken {
        k.window = parent.window
        k._internal_propagate_awake = parent._internal_propagate_awake
        k->_internal_propagate_awake()
    }
}

@(private="file")
_mount :: proc(parent, k, before: ^BaseNode) {
    if k.structural {
        for member in k.children do _mount(parent, member, before)
    }
    _place(parent, k, before)
}

@(private="file")
_unmount :: proc(k: ^BaseNode) {
    parent := k.parent
    if parent == nil do return
    if k.structural {
        for member in k.children do _unmount(member)
    }
    parent->damage()
    YG.NodeRemoveChild(parent.raw, k.raw)
    if at := _real_index(parent, k); at >= 0 do ordered_remove(&parent._internal_children, at)
    if !k.structural {
        #reverse for child, i in parent.children {
            if child == k {
                ordered_remove(&parent.children, i)
                break
            }
        }
    }
    k.parent = nil
}

@(private="file")
_node_insert :: proc(self: ^BaseNode, k: ^BaseNode, index: int) -> ^BaseNode {
    if k == nil do fmt.println("warning: node inserted is nil")
    if self == nil || k == nil do return self
    if k.parent != nil || k.owner != nil do panic("node is already mounted; remove it before inserting it elsewhere")

    at := index
    if at < 0 do at = 0
    if at > len(self.children) do at = len(self.children)

    if self.structural {
        before := self
        if at < len(self.children) do before = _first_real(self.children[at])
        k.owner = self
        inject_at(&self.children, at, k)
        if self.parent != nil do _mount(self.parent, k, before)
        return self
    }

    before: ^BaseNode
    if at < len(self.children) do before = self.children[at]
    _mount(self, k, before)
    return self
}

@(private="file")
_node_remove :: proc(self: ^BaseNode, kid: ^BaseNode) -> ^BaseNode {
    if self == nil || kid == nil do return self

    if self.structural {
        at := _node_index_of(self, kid)
        if at < 0 do return self
        ordered_remove(&self.children, at)
        kid.owner = nil
        _unmount(kid)
        return self
    }

    if kid.parent != self do return self
    if owner := kid.owner; owner != nil {
        if at := _node_index_of(owner, kid); at >= 0 do ordered_remove(&owner.children, at)
        kid.owner = nil
    }
    _unmount(kid)
    return self
}

@(private="file")
_node_index_of :: proc(self: ^BaseNode, kid: ^BaseNode) -> int {
    if self == nil do return -1
    for child, i in self.children {
        if child == kid do return i
    }
    return -1
}

@(private="file")
_node_compute_layout :: proc(self: ^BaseNode, width: f32 = UNDEFINED, height: f32 = UNDEFINED, dir: YG.Direction = .LTR) {
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
_node_get_by_key :: proc(self: ^BaseNode, key: string) -> ^BaseNode {
    if self == nil || key == "" do return nil
    return _find_descendant_by_key(self, key)
}

@(private="file")
_node_child :: proc(self: ^BaseNode, key: string) -> ^BaseNode {
    if self == nil || key == "" do return nil
    if !self.structural {
        for c in self._internal_children {
            if c.key == key do return c
        }
        return nil
    }
    for c in self.children {
        if c.key == key do return c
    }
    for c in self.children {
        if !c.structural do continue
        if hit := _node_child(c, key); hit != nil do return hit
    }
    return nil
}

@(private="file")
_node_closest :: proc(self: ^BaseNode, key: string) -> ^BaseNode {
    if self == nil || key == "" do return nil
    for at := self; at != nil; at = at.parent {
        if at != self && at.key == key do return at
        for owner := at.owner; owner != nil; owner = owner.owner {
            if owner.key == key do return owner
        }
    }
    return nil
}

@(private="file")
_parse_query :: proc(selector: string) -> (q: Query, ok: bool) {
    start, kind := 0, u8(0)
    for i := 0; i <= len(selector); i += 1 {
        if i < len(selector) {
            c := selector[i]
            if c != '.' && c != '#' {
                name := c == '-' || c == '_' || c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= 0x80
                if !name do return {}, false
                continue
            }
        }
        part := selector[start:i]
        switch kind {
        case 0: q.tag = part
        case '#':
            if part == "" || q.key != "" do return {}, false
            q.key = part
        case '.':
            if part == "" || q.count == len(q.classes) do return {}, false
            q.classes[q.count] = part
            q.count += 1
        }
        if i < len(selector) do kind = selector[i]
        start = i + 1
    }
    return q, q.tag != "" || q.key != "" || q.count > 0
}

@(private="file")
_query_matches :: proc(n: ^BaseNode, q: ^Query) -> bool {
    if q.key != "" && n.key != q.key do return false
    if q.tag == "" && q.count == 0 do return true
    return query_match != nil && query_match(n, q.tag, q.classes[:q.count])
}

@(private="file")
_query_walk :: proc(n: ^BaseNode, q: ^Query, out: ^[dynamic]^BaseNode, first: bool) -> bool {
    for c in n.children if n.structural else n._internal_children {
        if _query_matches(c, q) {
            append(out, c)
            if first do return true
        }
        if c.structural && !n.structural do continue
        if _query_walk(c, q, out, first) do return true
    }
    return false
}

@(private="file")
_run_query :: proc(self: ^BaseNode, selector: string, allocator: runtime.Allocator, first: bool) -> []^BaseNode {
    q, ok := _parse_query(selector)
    if self == nil || !ok do return nil
    out := make([dynamic]^BaseNode, allocator)
    _query_walk(self, &q, &out, first)
    return out[:]
}

@(private="file")
_node_query :: proc(self: ^BaseNode, selector: string) -> ^BaseNode {
    found := _run_query(self, selector, context.temp_allocator, true)
    return found[0] if len(found) > 0 else nil
}

@(private="file")
_node_query_all :: proc(self: ^BaseNode, selector: string, allocator := context.temp_allocator) -> []^BaseNode {
    return _run_query(self, selector, allocator, false)
}

@(private="file")
_node_inset :: proc(r: YG.NodeRef, get: proc "c" (n: YG.NodeRef, e: YG.Edge) -> f32) -> (l, t, right, b: f32) {
    return get(r, .Left), get(r, .Top), get(r, .Right), get(r, .Bottom)
}

@(private="file")
_node_get_rect :: proc(self: ^BaseNode, which: RectType = .Border) -> common.Rect {
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
_queue_free :: proc(self: ^BaseNode) -> Node_Error {
    return Node_Error.NODE_PANIC_NOT_AWAKE
}

@(private="file")
_node_free :: proc(self: ^BaseNode) {
    if self == nil || self.freed do return
    self.freed = true

    if owner := self.owner; owner != nil {
        if at := _node_index_of(owner, self); at >= 0 do ordered_remove(&owner.children, at)
        self.owner = nil
    }
    if self.structural {
        if self.parent != nil && !self.parent.freed do _unmount(self)
        for member in self.children {
            member.owner = nil
            _node_free(member)
        }
    } else {
        tops := make([dynamic]^BaseNode, 0, len(self._internal_children))
        for kid in self._internal_children {
            if kid.owner == nil do append(&tops, kid)
        }
        for kid in tops do _node_free(kid)
        delete(tops)
        delete(self._internal_children)
    }
    delete(self.children)

    self->run_hooks(.Before_Free)
    _destroy_hooks(self)
    if self.on_free != nil do self.on_free(self)
    events.bus_destroy(&self.bus)
    _node_free_flex_pin(self)

    if self.parent == nil {
        YG.NodeFreeRecursive(self.raw)
    }
    free(self)
}

@(private="file")
_add_hook :: proc(self: ^BaseNode, at: Hooks, callback: Hook_Callback, ctx: rawptr = nil) {
    if self == nil || callback == nil do return
    if self.hooks == nil do self.hooks = make(map[Hooks][dynamic]Hook_Entry)

    entries := self.hooks[at]
    append(&entries, Hook_Entry{callback, ctx})
    self.hooks[at] = entries
}

@(private="file")
_remove_hook :: proc(self: ^BaseNode, at: Hooks, callback: Hook_Callback, ctx: rawptr = nil) -> bool {
    if self == nil || self.hooks == nil || callback == nil do return false
    entries, ok := self.hooks[at]
    if !ok do return false

    for entry, index in entries {
        if entry.callback != callback || entry.ctx != ctx do continue
        ordered_remove(&entries, index)
        if len(entries) == 0 {
            delete(entries)
            delete_key(&self.hooks, at)
            if len(self.hooks) == 0 {
                delete(self.hooks)
                self.hooks = nil
            }
        } else {
            self.hooks[at] = entries
        }
        return true
    }
    return false
}

@(private="file")
_run_hooks :: proc(self: ^BaseNode, at: Hooks) {
    if self == nil || self.hooks == nil do return
    entries, ok := self.hooks[at]
    if !ok do return
    for entry in entries {
        if entry.callback != nil do entry.callback(self, entry.ctx)
    }
}

@(private="file")
_destroy_hooks :: proc(self: ^BaseNode) {
    if self == nil || self.hooks == nil do return
    for _, entries in self.hooks {
        delete(entries)
    }
    delete(self.hooks)
}

@(private="file")
_on :: proc(self: ^BaseNode, type: string, cb: events.Callback, capture := false, once := false) -> uint {
    return events.on(&self.bus, type, cb, capture, once)
}

@(private="file")
_off :: proc(self: ^BaseNode, type: string, cb: events.Callback) {
    events.off(&self.bus, type, cb)
}

@(private="file")
_find_descendant_by_key :: proc(root: ^BaseNode, key: string) -> ^BaseNode {
    level := root.children if root.structural else root._internal_children
    for c in level {
        if c.key == key do return c
    }
    for c in level {
        if c.structural && !root.structural do continue
        if hit := _find_descendant_by_key(c, key); hit != nil do return hit
    }
    return nil
}
