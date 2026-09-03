#+build !js
package inspector

import "base:intrinsics"
import "core:strings"
import "src:core/common"
import "src:core/events"
import "src:core/hit_test"
import "src:core/node"
import "src:ui/box"
import "src:ui/scroll_area"

DEFAULT_OPEN_DEPTH :: 4
ROW_POOL_MAX       :: 256

Row_Ref :: struct {
    index: i32,
    close: bool,
}

Tree_Row :: struct {
    root:    ^box.Box,
    chevron: ^Icon,
    name:    Label,
    detail:  Label,
    id:      Node_Id,
    entry:   int,
    close:   bool,
    used:    bool,
}

Tree_View :: struct {
    scroll:      ^scroll_area.Scroll_Area,
    host:        ^node.Node,
    top_pad:     ^box.Box,
    bottom_pad:  ^box.Box,
    rows:        [dynamic]^Tree_Row,
    order:       [dynamic]Row_Ref,
    folded:      map[Node_Id]bool,
    hovered_row: int,
}

tree_build :: proc(t: ^Tree_View) -> ^scroll_area.Scroll_Area {
    t.scroll = scroll_area.New({vertical = .Auto, horizontal = .Hidden, track_color = BG, thumb_color = {75, 78, 82, 255}, thumb_hover = {103, 107, 112, 255}, button_color = BG, arrow_color = TEXT_FAINT}, "elements")
    t.scroll->style()->
        set_flex_grow(1)->
        set_flex_shrink(1)->
        set_flex_basis(0, node.percent)->
        set_height(100, node.percent)->
        set_padding_y(4)

    t.top_pad = box.New({}, "pad-top")
    t.top_pad->style()->set_height(0)->set_flex_shrink(0)
    t.bottom_pad = box.New({}, "pad-bottom")
    t.bottom_pad->style()->set_height(0)->set_flex_shrink(0)
    t.host = node.New("rows")
    t.host->style()->set_flex_direction(.Column)->set_align_items(.Stretch)->set_flex_shrink(0)
    t.scroll->add(t.top_pad, t.host, t.bottom_pad)

    t.hovered_row = -1
    t.folded = make(map[Node_Id]bool)
    return t.scroll
}

@(private = "file")
_ensure_rows :: proc(t: ^Tree_View, want: int) {
    target := min(want, ROW_POOL_MAX)
    for len(t.rows) < target {
        row := new(Tree_Row)
        row.root = row_box()
        row.root->style()->set_height(ROW_HEIGHT)->set_padding_left(4)->set_gap_all(0)->set_display(.None)
        row.root.data = row

        row.chevron = icon(.Chevron, 10, TEXT_DIM)
        row.chevron->style()->set_margin_right(2)
        row.chevron.data = row

        row.name = label("", TAG)
        row.detail = label("", ATTR)
        row.root->add(row.chevron, row.name.root, row.detail.root)

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
    append(&t.order, Row_Ref{i32(at), false})

    open := entry.child_count > 0 && !folded(t, entry.id, entry.depth)
    next := at + 1
    for next < len(snap.nodes) && snap.nodes[next].depth > entry.depth {
        if open {
            next = _flatten(t, snap, next)
        } else {
            next += 1
        }
    }
    if open do append(&t.order, Row_Ref{i32(at), true})
    return next
}

tree_sync :: proc(p: ^Panel) {
    t := &p.tree
    snap := p.snap
    total := len(t.order)
    view_h := t.scroll.rect.h
    if view_h <= 0 do view_h = 400

    first := int(t.scroll.scroll_y / ROW_HEIGHT)
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
    rx, ry := hit_test.to_local(auto_cast t.host, mx, my)
    t.hovered_row = -1

    for row, slot in t.rows {
        at := first + slot
        if slot >= last - first || at >= total {
            if row.used {
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

        has_kids := entry.child_count > 0
        row.chevron.open = has_kids && !folded(t, entry.id, entry.depth)
        row.chevron.color = TEXT_DIM if has_kids && !ref.close else Color{0, 0, 0, 0}

        if ref.close {
            label_color(row.name, TAG)
            label_set(row.name, strings.concatenate({"</", str(snap, entry.name), ">"}, context.temp_allocator))
            label_set(row.detail, "")
        } else if entry.text_like {
            label_color(row.name, VALUE)
            label_set(row.name, _quote(str(snap, entry.text)))
            label_set(row.detail, "")
        } else {
            name := str(snap, entry.name)
            label_color(row.name, TAG)
            label_set(row.name, strings.concatenate({"<", name}, context.temp_allocator))

            tail := ">"
            if has_kids {
                if !row.chevron.open do tail = strings.concatenate({">…</", name, ">"}, context.temp_allocator)
            } else {
                tail = strings.concatenate({"></", name, ">"}, context.temp_allocator)
            }

            key := str(snap, entry.key)
            if key == "" {
                label_set(row.detail, tail)
            } else {
                label_set(row.detail, strings.concatenate({"#", key, tail}, context.temp_allocator))
            }
        }

        hit := inside && common.rect_intersect(row.root.rect, rx, ry)
        if hit do t.hovered_row = slot

        bg := Color{0, 0, 0, 0}
        if entry.id == p.selected {
            bg = ROW_SELECT
        } else if hit {
            bg = ROW_HOVER
        }
        row.root->style().background = bg
    }

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
    select_node(p, row.id)
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
