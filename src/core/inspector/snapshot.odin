#+build !js
package inspector

import "base:runtime"
import "src:core/common"
import "src:core/node"
import YG "src:yoga"

Node_Id :: u64

Str :: struct {
    off, len: u32,
}

Len :: struct {
    value: f32,
    unit:  node.unit,
}

Snap_Node :: struct {
    id:          Node_Id,
    parent:      i32,
    depth:       i32,
    child_count: i32,

    name: Str,
    key:  Str,
    text: Str,

    rect: common.Rect,
    margin:  [4]f32,
    border:  [4]f32,
    padding: [4]f32,
    inset: [4]Len,

    display:        node.Display,
    position_type:  node.Position,
    flex_direction: node.FlexDirection,
    justify:        node.Justify,
    align_items:    node.Align,
    align_self:     node.Align,
    align_content:  node.Align,
    wrap:           node.Wrap,
    box_sizing:     node.BoxSizing,
    overflow_x:     node.Overflow,
    overflow_y:     node.Overflow,
    pointer_events: node.Pointer_Events,
    select_mode:    node.User_Select,
    clip_mode:      node.ClipMode,

    flex_grow:   f32,
    flex_shrink: f32,
    flex_basis:  Len,
    width:       Len,
    height:      Len,
    min_width:   Len,
    min_height:  Len,
    max_width:   Len,
    max_height:  Len,
    gap_row:     f32,
    gap_column:  f32,
    aspect:      f32,

    z_index:     i32,
    color:       common.Color,
    font_size:   f32,
    font_weight: node.FontWeight,
    line_height: Len,

    stacking:  bool,
    transform: bool,
    text_like: bool,
}

Snapshot :: struct {
    nodes:    [dynamic]Snap_Node,
    blob:     [dynamic]u8,
    version:  u64,
    viewport: [2]f32,
    scale:    f32,
}

TEXT_PREVIEW_MAX :: 80

snapshot_destroy :: proc(s: ^Snapshot) {
    delete(s.nodes)
    delete(s.blob)
    s^ = {}
}

snap_str :: proc(s: ^Snapshot, v: string) -> Str {
    if len(v) == 0 do return {}
    off := u32(len(s.blob))
    append(&s.blob, v)
    return {off = off, len = u32(len(v))}
}

str :: proc(s: ^Snapshot, r: Str) -> string {
    if r.len == 0 || int(r.off) + int(r.len) > len(s.blob) do return ""
    return string(s.blob[r.off:][:r.len])
}

capture :: proc(snap: ^Snapshot, root: ^node.BaseNode, skip: ^node.BaseNode = nil) {
    clear(&snap.nodes)
    clear(&snap.blob)
    append(&snap.blob, u8(0))
    if root != nil do _capture_node(snap, root, -1, 0, skip)
    snap.version += 1
}

@(private = "file")
_capture_node :: proc(snap: ^Snapshot, n: ^node.BaseNode, parent: i32, depth: i32, skip: ^node.BaseNode) {
    if n == nil || n.freed || n == skip do return

    index := i32(len(snap.nodes))
    entry := Snap_Node {
        id     = Node_Id(uintptr(n)),
        parent = parent,
        depth  = depth,
        name   = snap_str(snap, type_name(n)),
        key    = snap_str(snap, n.key),
        rect   = n.rect,
    }

    raw := n.raw
    entry.margin = _edges(raw, YG.NodeLayoutGetMargin)
    entry.border = _edges(raw, YG.NodeLayoutGetBorder)
    entry.padding = _edges(raw, YG.NodeLayoutGetPadding)

    entry.z_index = n.z_index
    entry.stacking = n.creates_stacking_context
    entry.transform = n.transform != common.IDENTITY_TRANSFORM
    entry.clip_mode = n.clip_mode

    if n.text_content != nil && n.str != nil {
        entry.text_like = true
        entry.text = snap_str(snap, _preview(n->str()))
    }

    if n._internal_style != nil {
        st := cast(^node.Style)n._internal_style
        entry.display = st->get_display()
        entry.position_type = st->get_position_type()
        entry.flex_direction = st->get_flex_direction()
        entry.justify = st->get_justify_content()
        entry.align_items = st->get_align_items()
        entry.align_self = st->get_align_self()
        entry.align_content = st->get_align_content()
        entry.wrap = st->get_wrap()
        entry.box_sizing = st->get_box_sizing()
        entry.overflow_x = st->get_overflow_x()
        entry.overflow_y = st->get_overflow_y()
        entry.pointer_events = st->get_pointer_events()
        entry.select_mode = st->get_select_mode()

        entry.flex_grow = st->get_flex_grow()
        entry.flex_shrink = st->get_flex_shrink()
        entry.flex_basis = _len(st->get_flex_basis())
        entry.width = _len(st->get_width())
        entry.height = _len(st->get_height())
        entry.min_width = _len(st->get_min_width())
        entry.min_height = _len(st->get_min_height())
        entry.max_width = _len(st->get_max_width())
        entry.max_height = _len(st->get_max_height())
        entry.inset = {
            _len(st->get_position_left()),
            _len(st->get_position_top()),
            _len(st->get_position_right()),
            _len(st->get_position_bottom()),
        }
        entry.gap_row, _ = st->get_gap_row()
        entry.gap_column, _ = st->get_gap_column()
        entry.aspect = st->get_aspect_ratio()

        entry.color = st->get_color()
        entry.font_size = st->get_font_size()
        entry.font_weight = st->get_font_weight()
        entry.line_height = _len(st->get_line_height())
    }

    append(&snap.nodes, entry)

    kids := i32(0)
    for c in n.children {
        if c == nil || c.freed || c == skip do continue
        kids += 1
        _capture_node(snap, c, index, depth + 1, skip)
    }
    snap.nodes[index].child_count = kids
}

@(private = "file")
_len :: proc(value: f32, unit: node.unit) -> Len {
    return {value = value, unit = unit}
}

@(private = "file")
_edges :: proc(r: YG.NodeRef, get: proc "c" (n: YG.NodeRef, e: YG.Edge) -> f32) -> [4]f32 {
    return {get(r, .Left), get(r, .Top), get(r, .Right), get(r, .Bottom)}
}

@(private = "file")
_preview :: proc(s: string) -> string {
    if len(s) <= TEXT_PREVIEW_MAX do return s
    cut := TEXT_PREVIEW_MAX
    for cut > 0 && s[cut] & 0xC0 == 0x80 do cut -= 1
    return s[:cut]
}

type_name :: proc(n: ^node.BaseNode) -> string {
    if n == nil do return "?"
    info := type_info_of(n.type_id)
    if info == nil do return "Node"
    named, ok := info.variant.(runtime.Type_Info_Named)
    if !ok do return "Node"
    return named.name
}

// Index of the entry carrying `id`, or -1.
find_index :: proc(snap: ^Snapshot, id: Node_Id) -> int {
    if id == 0 do return -1
    for entry, i in snap.nodes {
        if entry.id == id do return i
    }
    return -1
}
