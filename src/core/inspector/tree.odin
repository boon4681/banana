#+build !js
package inspector

import "base:intrinsics"
import "core:strings"
import "core:time"
import "src:core/common"
import "src:core/events"
import "src:core/hit_test"
import "src:core/node"
import "src:core/painter"
import "src:core/scroll"
import "src:ui/box"
import ui_input "src:ui/input"
import "src:ui/scroll_area"

DEFAULT_OPEN_DEPTH :: 4
ROW_POOL_MAX       :: 256

ROW_SEGMENTS       :: 10

Row_Ref :: struct {
    index:  i32,
    close:  bool,
    inline: bool, // the only child is text, shown on this row
}

Tree_Row :: struct {
    root:      ^box.Box,
    chevron:   ^Icon,
    segments:  [ROW_SEGMENTS]Label,
    base_draw: proc(self: ^node.BaseNode),
    id:        Node_Id,
    entry:     int,
    depth:     int,
    close:     bool,
    used:      bool,
}

Tree_View :: struct {
    scroll:      ^scroll_area.Scroll_Area,
    host:        ^node.Node,
    top_pad:     ^box.Box,
    bottom_pad:  ^box.Box,
    rows:        [dynamic]^Tree_Row,
    order:       [dynamic]Row_Ref,
    folded:      map[Node_Id]bool,
    matched:     map[Node_Id]bool,
    hovered_row: int,

    field:      ^ui_input.Input, // edits text in place, moved into the row it belongs to
    editing:    Node_Id,
    field_row:  ^Tree_Row,
    last_down:  time.Tick,
    last_row:   Node_Id,
}

DOUBLE_CLICK :: 400 * time.Millisecond

// The text a row shows, if it can be edited in place.
@(private = "file")
_row_text :: proc(snap: ^Snapshot, ref: Row_Ref) -> (id: Node_Id, text: string, ok: bool) {
    if ref.close do return
    entry := snap.nodes[ref.index + 1] if ref.inline else snap.nodes[ref.index]
    if !entry.text_like || entry.text_cut do return
    return entry.id, str(snap, entry.text), true
}

tree_edit_begin :: proc(p: ^Panel, row_id: Node_Id) {
    t, snap := &p.tree, p.snap
    if snap == nil do return
    at := tree_row_of(t, snap, row_id)
    if at < 0 do return
    id, text, editable := _row_text(snap, t.order[at])
    if !editable do return
    tree_edit_end(p)
    editor_end(p)
    t.editing = id
    t.field->set_value(text)
    tree_sync(p)
    focus_node(p.win, t.field)
}

tree_edit_end :: proc(p: ^Panel) {
    t := &p.tree
    if t.editing == 0 do return
    t.editing = 0
    if p.win.input.focused == cast(^node.BaseNode)t.field do focus_node(p.win, nil)
    _field_detach(t)
}

@(private = "file")
_field_detach :: proc(t: ^Tree_View) {
    if t.field_row == nil do return
    t.field_row.root->remove(t.field)
    t.field_row = nil
}

@(private = "file")
_field_attach :: proc(t: ^Tree_View, row: ^Tree_Row, segment: int) {
    if t.field_row == row do return
    _field_detach(t)
    row.root->insert(t.field, row.root->index_of(row.segments[segment].root) + 1)
    t.field_row = row
}

@(private = "file")
_field_commit :: proc(self: ^ui_input.Input, value: string) {
    p := _panel
    if p == nil || p.tree.editing == 0 do return
    push_command(p.insp, {kind = .Text, id = p.tree.editing, value = value})
    tree_edit_end(p)
}

// The row showing `id`: its own, or its parent's when the text is shown inline.
tree_row_of :: proc(t: ^Tree_View, snap: ^Snapshot, id: Node_Id) -> int {
    for ref, at in t.order {
        if ref.close do continue
        if snap.nodes[ref.index].id == id do return at
        if ref.inline && snap.nodes[ref.index + 1].id == id do return at
    }
    return -1
}

tree_scroll_to :: proc(t: ^Tree_View, snap: ^Snapshot, id: Node_Id) {
    at := tree_row_of(t, snap, id)
    if at < 0 do return
    top := f32(at) * ROW_HEIGHT
    view := max(t.scroll.rect.h - 8, ROW_HEIGHT)
    at_now := scroll.offset(t.scroll)
    if top < at_now.y {
        scroll.to(t.scroll, at_now.x, top)
    } else if top + ROW_HEIGHT > at_now.y + view {
        scroll.to(t.scroll, at_now.x, top + ROW_HEIGHT - view)
    }
}

// Arrow keys: up and down walk rows, left folds or goes to the parent, right unfolds or steps in.
tree_navigate :: proc(p: ^Panel, key: events.Key) -> bool {
    t, snap := &p.tree, p.snap
    if snap == nil || len(t.order) == 0 do return false
    at := tree_row_of(t, snap, p.selected)
    if at < 0 {
        select_node(p, snap.nodes[t.order[0].index].id)
        return true
    }
    entry := snap.nodes[t.order[at].index]
    open := entry.child_count > 0 && !t.order[at].inline && !folded(t, entry.id, entry.depth)
    step := 0
    #partial switch key {
    case .Up: step = -1
    case .Down: step = 1
    case .Left:
        if open {
            tree_toggle(t, entry.id, entry.depth)
            tree_flatten(t, snap)
        } else if entry.parent >= 0 {
            select_node(p, snap.nodes[entry.parent].id)
        }
    case .Right:
        if entry.child_count > 0 && !t.order[at].inline && !open {
            tree_toggle(t, entry.id, entry.depth)
            tree_flatten(t, snap)
        } else {
            step = 1
        }
    case: return false
    }
    for next := at + step; step != 0 && next >= 0 && next < len(t.order); next += step {
        if t.order[next].close do continue
        select_node(p, snap.nodes[t.order[next].index].id)
        break
    }
    tree_scroll_to(t, snap, p.selected)
    return true
}

tree_build :: proc(t: ^Tree_View) -> ^scroll_area.Scroll_Area {
    t.scroll = scroll_area.New({vertical = .Auto, horizontal = .Hidden, track_color = BG, thumb_color = {75, 78, 82, 255}, thumb_hover = {103, 107, 112, 255}, button_color = BG, arrow_color = TEXT_FAINT}, "elements")
    t.scroll->style()->
        set_flex_grow(1)->
        set_flex_shrink(1)->
        set_flex_basis(0, node.percent)->
        set_height(100, node.percent)->
        set_padding_block(4)

    t.top_pad = box.New({}, "pad-top")
    t.top_pad->style()->set_height(0)->set_flex_shrink(0)
    t.bottom_pad = box.New({}, "pad-bottom")
    t.bottom_pad->style()->set_height(0)->set_flex_shrink(0)
    t.host = node.New("rows")
    t.host->style()->set_flex_direction(.Column)->set_align_items(.Stretch)->set_flex_shrink(0)
    t.scroll->add(t.top_pad, t.host, t.bottom_pad)

    t.hovered_row = -1
    t.folded = make(map[Node_Id]bool)
    t.field = input_field("", "tree-edit")
    t.field->style()->set_height(ROW_HEIGHT - 2)->set_min_width(80)->set_flex_grow(1)->set_flex_shrink(1)->set_margin_right(8)
    t.field.onenter = _field_commit
    t.field.onchange = _field_commit
    return t.scroll
}

@(private = "file")
_ensure_rows :: proc(t: ^Tree_View, want: int) {
    target := min(want, ROW_POOL_MAX)
    for len(t.rows) < target {
        row := new(Tree_Row)
        row.root = row_box()
        row.root->style()->set_height(ROW_HEIGHT)->set_padding_left(4)->set_gap(0)->set_display(.None)
        row.root.data = row

        row.chevron = icon(.Chevron, 10, TEXT_DIM)
        row.chevron->style()->set_margin_right(2)
        row.chevron.data = row

        row.root->add(row.chevron)
        for &segment in row.segments {
            segment = label("", TAG)
            row.root->add(segment.root)
        }
        row.base_draw = row.root.draw
        row.root.draw = _row_draw

        row.root->on(events.MOUSE_DOWN_EVENT, _row_down)
        row.chevron->on(events.MOUSE_DOWN_EVENT, _chevron_down)

        t.host->add(row.root)
        append(&t.rows, row)
    }
}

folded :: proc(t: ^Tree_View, id: Node_Id, depth: i32) -> bool {
    if v, ok := t.folded[id]; ok do return v
    return depth >= DEFAULT_OPEN_DEPTH
}

tree_toggle :: proc(t: ^Tree_View, id: Node_Id, depth: i32) {
    t.folded[id] = !folded(t, id, depth)
}

tree_reveal :: proc(t: ^Tree_View, snap: ^Snapshot, id: Node_Id) {
    index := find_index(snap, id)
    if index < 0 do return
    for parent := snap.nodes[index].parent; parent >= 0; parent = snap.nodes[parent].parent {
        t.folded[snap.nodes[parent].id] = false
    }
}

tree_flatten :: proc(t: ^Tree_View, snap: ^Snapshot) {
    clear(&t.order)
    if snap == nil || len(snap.nodes) == 0 do return
    _flatten(t, snap, 0)
}

@(private = "file")
_flatten :: proc(t: ^Tree_View, snap: ^Snapshot, at: int) -> int {
    entry := snap.nodes[at]
    if entry.child_count == 1 && at + 1 < len(snap.nodes) {
        only := snap.nodes[at + 1]
        if only.text_like && only.child_count == 0 {
            append(&t.order, Row_Ref{i32(at), false, true})
            return at + 2
        }
    }
    append(&t.order, Row_Ref{i32(at), false, false})

    open := entry.child_count > 0 && !folded(t, entry.id, entry.depth)
    next := at + 1
    for next < len(snap.nodes) && snap.nodes[next].depth > entry.depth {
        if open {
            next = _flatten(t, snap, next)
        } else {
            next += 1
        }
    }
    if open do append(&t.order, Row_Ref{i32(at), true, false})
    return next
}

tree_sync :: proc(p: ^Panel) {
    t := &p.tree
    snap := p.snap
    total := len(t.order)
    view_h := t.scroll.rect.h
    if view_h <= 0 do view_h = 400

    first := int(scroll.offset(t.scroll).y / ROW_HEIGHT)
    first = clamp(first, 0, max(0, total - 1))
    span := int(view_h / ROW_HEIGHT) + 2
    _ensure_rows(t, span)
    span = min(span, len(t.rows))
    last := min(total, first + span)

    t.top_pad->style()->set_height(f32(first) * ROW_HEIGHT)
    t.bottom_pad->style()->set_height(f32(max(0, total - last)) * ROW_HEIGHT)

    mx, my := p.win.input.mouse_x, p.win.input.mouse_y
    pscale := p.win.scale if p.win.scale > 0 else 1
    inside := mx >= 0 && my >= 0 && mx < f32(p.win.width) / pscale && my < f32(p.win.height) / pscale
    inside = inside && p.win.input.hovered != nil
    rx, ry := hit_test.to_local(auto_cast t.host, mx, my)
    t.hovered_row = -1
    shown := false
    if t.editing != 0 && t.field_row != nil && p.win.input.focused != cast(^node.BaseNode)t.field do tree_edit_end(p)

    for row, slot in t.rows {
        at := first + slot
        if slot >= last - first || at >= total {
            if row.used {
                if t.field_row == row do _field_detach(t)
                row.root->style()->set_display(.None)
                row.used = false
                row.id = 0
                row.entry = -1
            }
            continue
        }
        ref := t.order[at]
        index := int(ref.index)
        entry := &snap.nodes[index]
        if !row.used {
            row.root->style()->set_display(.Flex)
            row.used = true
        }
        row.id = entry.id
        row.entry = index
        row.close = ref.close

        row.root->style()->set_padding_left(4 + f32(entry.depth) * INDENT_STEP)
        row.depth = int(entry.depth)

        has_kids := entry.child_count > 0 && !ref.inline
        row.chevron.open = has_kids && !folded(t, entry.id, entry.depth)
        row.chevron.color = TEXT_DIM if has_kids && !ref.close else Color{0, 0, 0, 0}

        selected := entry.id == p.selected || (ref.inline && snap.nodes[index + 1].id == p.selected)
        edited := false
        if t.editing != 0 {
            if id, _, ok := _row_text(snap, ref); ok && id == t.editing do edited = true
        }
        text_segment := _fill_row(row, snap, entry, ref, has_kids, selected && !ref.close, edited)
        if edited && text_segment >= 0 {
            _field_attach(t, row, text_segment)
            shown = true
        } else if t.field_row == row {
            _field_detach(t)
        }

        hit := inside && common.rect_intersect(row.root.rect, rx, ry)
        if hit do t.hovered_row = slot

        bg := Color{0, 0, 0, 0}
        if selected {
            bg = ROW_SELECT
        } else if !ref.close && (t.matched[entry.id] || (ref.inline && t.matched[snap.nodes[index + 1].id])) {
            bg = ROW_MATCH
        } else if hit {
            bg = ROW_HOVER
        }
        row.root->style().background = bg
    }

    if t.editing != 0 && !shown do tree_edit_end(p)

    if intrinsics.atomic_load(&p.insp.pick_mode) == 0 {
        id := Node_Id(0)
        if t.hovered_row >= 0 do id = t.rows[t.hovered_row].id
        intrinsics.atomic_store(&p.insp.hover_id, id)
    }
}

@(private = "file")
_quote :: proc(s: string) -> string {
    return strings.concatenate({"\"", s, "\""}, context.temp_allocator)
}

@(private = "file")
_Row_Writer :: struct {
    row:  ^Tree_Row,
    used: int,
    dim:  bool,
}

@(private = "file")
_put :: proc(w: ^_Row_Writer, text: string, color: Color, gap: f32 = 0) {
    if w.used >= ROW_SEGMENTS || text == "" do return
    shown := color
    if w.dim do shown.a = 110
    segment := w.row.segments[w.used]
    label_color(segment, shown)
    label_set(segment, text)
    segment.root->style()->set_margin_left(gap)
    w.used += 1
}

@(private = "file")
_attribute :: proc(w: ^_Row_Writer, name, value: string) {
    if value == "" do return
    _put(w, strings.concatenate({name, "="}, context.temp_allocator), ATTR, 5)
    _put(w, _quote(value), VALUE)
}

@(private = "file")
_fill_row :: proc(row: ^Tree_Row, snap: ^Snapshot, entry: ^Snap_Node, ref: Row_Ref, has_kids, selected, edited: bool) -> (text_segment: int) {
    text_segment = -1
    w := _Row_Writer{row = row, dim = entry.display == .None && entry.kind == .Element && !entry.text_like}
    name := str(snap, entry.name)
    block := entry.kind == .If || entry.kind == .Each || entry.kind == .Render
    tag := COMPONENT if entry.kind == .Component else TAG
    close := strings.concatenate({"{/", name, "}"} if block else {"</", name, ">"}, context.temp_allocator)

    switch {
    case ref.close:
        _put(&w, close, BLOCK if block else tag)
    case entry.text_like:
        text_segment = w.used
        _put(&w, " " if edited else _quote(str(snap, entry.text)), TEXT)
    case block:
        _put(&w, strings.concatenate({"{#" if entry.kind != .Render else "{@", name, "}"}, context.temp_allocator), BLOCK)
        if !has_kids || !row.chevron.open {
            if has_kids do _put(&w, "…", TEXT_DIM)
            if entry.kind != .Render do _put(&w, close, BLOCK)
        }
    case:
        _put(&w, strings.concatenate({"<", name}, context.temp_allocator), tag)
        _attribute(&w, "key", str(snap, entry.key))
        _attribute(&w, "class", str(snap, entry.classes))
        _put(&w, ">", tag)
        if ref.inline {
            text_segment = w.used
            _put(&w, " " if edited else str(snap, snap.nodes[row.entry + 1].text), TEXT)
            _put(&w, close, tag)
        } else if !has_kids || !row.chevron.open {
            if has_kids do _put(&w, "…", TEXT_DIM)
            _put(&w, close, tag)
        }
    }
    if selected && !edited do _put(&w, "== $0", TEXT_FAINT, 8)
    for i in w.used ..< ROW_SEGMENTS do label_set(row.segments[i], "")
    return
}

@(private = "file")
_row_draw :: proc(self: ^node.BaseNode) {
    row := cast(^Tree_Row)self.data
    if row == nil do return
    if row.base_draw != nil do row.base_draw(self)
    if !row.used do return
    for level in 0 ..< row.depth {
        x := self.rect.x + 9 + f32(level) * INDENT_STEP
        painter.rect(painter.get(), {x, self.rect.y, 1, self.rect.h}, GUIDE)
    }
}

@(private = "file")
_row_of :: proc(s: ^events.Event_Signal) -> ^Tree_Row {
    n := cast(^node.BaseNode)s.current_target
    if n == nil do return nil
    return cast(^Tree_Row)n.data
}

@(private = "file")
_row_down :: proc(s: ^events.Event_Signal) {
    p := _panel
    row := _row_of(s)
    if p == nil || row == nil || !row.used do return
    t := &p.tree
    if t.field_row == row do return
    now := time.tick_now()
    again := t.last_row == row.id && time.tick_diff(t.last_down, now) < DOUBLE_CLICK
    t.last_down, t.last_row = now, row.id
    select_node(p, row.id)
    if again && !row.close {
        tree_edit_begin(p, row.id)
        events.prevent_default(s)
    }
}

@(private = "file")
_chevron_down :: proc(s: ^events.Event_Signal) {
    p := _panel
    row := _row_of(s)
    if p == nil || row == nil || !row.used || row.close || p.snap == nil do return
    if row.entry < 0 || row.entry >= len(p.snap.nodes) do return
    entry := p.snap.nodes[row.entry]
    if entry.child_count == 0 do return
    tree_toggle(&p.tree, entry.id, entry.depth)
    tree_flatten(&p.tree, p.snap)
    events.stop_propagation(s)
}
