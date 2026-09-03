package input

import "core:strings"
import "core:time"
import "src:core/hit_test"
import "src:core/node"
import "src:core/text"

MULTI_CLICK_DISTANCE :: f32(4)
MULTI_CLICK_INTERVAL :: 500 * time.Millisecond

Selection_Point :: struct {
    node: ^Node,
    pos:  text.Position,
}

Selection_Range :: struct {
    anchor, focus: Selection_Point,
}

Selection_Unit :: struct {
    start, end: Selection_Point,
}

Selection_Gesture :: struct {
    dragging:    bool,
    granularity: text.Granularity,
    anchor:      Selection_Unit,

    last_click_node: ^Node,
    last_click_time: time.Tick,
    last_click_x:    f32,
    last_click_y:    f32,
    click_count:     int,
}

Selection_State :: struct {
    range:   Selection_Range,
    valid:   bool,
    gesture: Selection_Gesture,
}

selection_begin :: proc(im: ^Input_State, x, y: f32, now: time.Tick) -> bool {
    hit := hit_test.hit_test(im.root, x, y)
    if hit == nil {
        selection_clear(im)
        return false
    }

    g := &im.selection.gesture
    if .Shift in im.mods && im.selection.valid {
        anchor := im.selection.range.anchor
        if node.is_selectable(anchor.node) {
            if unit, ok := _unit_at(im.root, hit, x, y, .Character, false); ok {
                g.dragging = true
                g.granularity = .Character
                g.anchor = {anchor, anchor}
                _extend_to_unit(im.root, &im.selection, unit)
                return true
            }
        }
    }

    near := hit == g.last_click_node &&
            abs(x - g.last_click_x) <= MULTI_CLICK_DISTANCE &&
            abs(y - g.last_click_y) <= MULTI_CLICK_DISTANCE
    recent := g.last_click_time != {} &&
              time.tick_diff(g.last_click_time, now) <= MULTI_CLICK_INTERVAL
    g.click_count = near && recent ? g.click_count + 1 : 1
    g.last_click_node = hit
    g.last_click_time = now
    g.last_click_x = x
    g.last_click_y = y

    switch (g.click_count - 1) % 3 {
    case 0: g.granularity = .Character
    case 1: g.granularity = .Word
    case:   g.granularity = .Line
    }

    unit, ok := _unit_at(im.root, hit, x, y, g.granularity, false)
    if !ok {
        selection_clear(im)
        return false
    }

    g.anchor = unit
    g.dragging = true

    im.selection.range = {
        anchor = unit.start,
        focus  = unit.end,
    }
    im.selection.valid = true
    return true
}

selection_extend :: proc(im: ^Input_State, x, y: f32) {
    s := &im.selection
    g := &s.gesture
    if !g.dragging || !s.valid ||
       !node.is_selectable(g.anchor.start.node) ||
       !node.is_selectable(g.anchor.end.node) {
        return
    }

    hit := hit_test.hit_test(im.root, x, y)
    unit, ok := _unit_at(im.root, hit, x, y, g.granularity, true)
    if ok do _extend_to_unit(im.root, s, unit)
}

selection_end :: proc(im: ^Input_State) {
    im.selection.gesture.dragging = false
}

selection_clear :: proc(im: ^Input_State) {
    im.selection.valid = false
    im.selection.range = {}
    im.selection.gesture.dragging = false
    im.selection.gesture.anchor = {}
}

@(private = "file")
_unit_at :: proc(
    root, hit: ^Node,
    x, y: f32,
    granularity: text.Granularity,
    nearest: bool,
) -> (Selection_Unit, bool) {
    target := hit
    if scope := node.User_Select_All_Scope(target); scope != nil {
        return _scope_unit(scope)
    }
    if !node.is_selectable(target) && nearest {
        target = _nearest_selectable(root, x, y)
    }
    if !node.is_selectable(target) do return {}, false
    if scope := node.User_Select_All_Scope(target); scope != nil {
        return _scope_unit(scope)
    }

    lx, ly := hit_test.to_local(target, x, y)
    pos := target.position_at(target, lx, ly)
    if granularity == .Character {
        point := Selection_Point{target, pos}
        return {point, point}, true
    }

    local := target.expand(target, pos, granularity)
    lo := min(local.anchor.offset, local.focus.offset)
    hi := max(local.anchor.offset, local.focus.offset)
    return {
        start = {target, {lo, false}},
        end   = {target, {hi, true}},
    }, true
}

@(private = "file")
_scope_unit :: proc(scope: ^Node) -> (Selection_Unit, bool) {
    first, last: ^Node
    _selectable_bounds(scope, &first, &last)
    if first == nil || last == nil do return {}, false
    return {
        start = {first, {0, false}},
        end   = {last, {len(last.str(last)), true}},
    }, true
}

@(private = "file")
_extend_to_unit :: proc(root: ^Node, s: ^Selection_State, unit: Selection_Unit) {
    anchor := s.gesture.anchor
    if _point_compare(root, unit.start, anchor.start) < 0 {
        s.range.anchor = anchor.end
        s.range.focus = unit.start
        return
    }
    end := unit.end
    if _point_compare(root, end, anchor.end) < 0 do end = anchor.end
    s.range.anchor = anchor.start
    s.range.focus = end
}

selection_for_node :: proc(im: ^Input_State, n: ^Node) -> (text.Selection, bool) {
    lo, hi, ok := _selection_offsets(im, n)
    if !ok || hi <= lo do return {}, false
    return {{lo, false}, {hi, true}}, true
}

@(private = "file")
_selection_offsets :: proc(im: ^Input_State, n: ^Node) -> (int, int, bool) {
    if im == nil || !im.selection.valid || !node.is_selectable(n) do return 0, 0, false
    if !node.is_selectable(im.selection.range.anchor.node) ||
       !node.is_selectable(im.selection.range.focus.node) {
        return 0, 0, false
    }
    if !_belongs_to(im.root, n) ||
       !_belongs_to(im.root, im.selection.range.anchor.node) ||
       !_belongs_to(im.root, im.selection.range.focus.node) {
        return 0, 0, false
    }

    start, end := _ordered_points(im.root, im.selection.range)
    if _point_compare(im.root, start, end) == 0 do return 0, 0, false

    start_cmp := _node_compare(start.node, n)
    end_cmp := _node_compare(n, end.node)
    if start_cmp > 0 || end_cmp > 0 do return 0, 0, false

    source := n.str(n)
    lo, hi := 0, len(source)
    if n == start.node do lo = clamp(start.pos.offset, 0, hi)
    if n == end.node do hi = clamp(end.pos.offset, 0, hi)
    return lo, hi, true
}

selection_text :: proc(im: ^Input_State) -> string {
    if im == nil || !im.selection.valid do return ""
    b := strings.builder_make(context.temp_allocator)
    wrote_node := false
    _append_selected_text(im, im.root, &b, &wrote_node)
    return strings.to_string(b)
}

selection_copy :: proc(im: ^Input_State) -> bool {
    s := selection_text(im)
    if s == "" do return false
    set_clipboard_text(s)
    return true
}

selection_select_all :: proc(im: ^Input_State) -> bool {
    if im == nil || im.root == nil do return false
    first, last: ^Node
    _selectable_bounds(im.root, &first, &last)
    if first == nil || last == nil do return false

    start := Selection_Point{first, {0, false}}
    end := Selection_Point{last, {len(last.str(last)), true}}
    im.selection.range = {anchor = start, focus = end}
    im.selection.valid = true
    im.selection.gesture.dragging = false
    im.selection.gesture.anchor = {start, end}
    return true
}

@(private = "file")
_append_selected_text :: proc(im: ^Input_State, n: ^Node, b: ^strings.Builder, wrote_node: ^bool) {
    if n == nil || n.freed do return
    if lo, hi, ok := _selection_offsets(im, n); ok {
        if wrote_node^ do strings.write_byte(b, '\n')
        source := n.str(n)
        if lo < hi do strings.write_string(b, source[lo:hi])
        wrote_node^ = true
    }
    for child in n.children do _append_selected_text(im, child, b, wrote_node)
}

@(private = "file")
_nearest_selectable :: proc(root: ^Node, x, y: f32) -> ^Node {
    best: ^Node
    best_distance := max(f32)
    _nearest_selectable_walk(root, x, y, &best, &best_distance)
    return best
}

@(private = "file")
_nearest_selectable_walk :: proc(n: ^Node, x, y: f32, best: ^^Node, best_distance: ^f32) {
    if n == nil || n.freed do return
    if node.is_selectable(n) {
        lx, ly := hit_test.to_local(n, x, y)
        dx, dy: f32
        if lx < n.rect.x {
            dx = n.rect.x - lx
        } else if lx > n.rect.x + n.rect.w {
            dx = lx - (n.rect.x + n.rect.w)
        }
        if ly < n.rect.y {
            dy = n.rect.y - ly
        } else if ly > n.rect.y + n.rect.h {
            dy = ly - (n.rect.y + n.rect.h)
        }
        distance := dx * dx + dy * dy
        if distance < best_distance^ {
            best^ = n
            best_distance^ = distance
        }
    }
    for child in n.children do _nearest_selectable_walk(child, x, y, best, best_distance)
}

@(private = "file")
_selectable_bounds :: proc(n: ^Node, first, last: ^^Node) {
    if n == nil || n.freed do return
    if node.is_selectable(n) {
        if first^ == nil do first^ = n
        last^ = n
    }
    for child in n.children do _selectable_bounds(child, first, last)
}

@(private = "file")
_ordered_points :: proc(root: ^Node, r: Selection_Range) -> (Selection_Point, Selection_Point) {
    if _point_compare(root, r.anchor, r.focus) <= 0 do return r.anchor, r.focus
    return r.focus, r.anchor
}

@(private = "file")
_point_compare :: proc(root: ^Node, a, b: Selection_Point) -> int {
    _ = root // Node order is intrinsic to the parent/child tree.
    if a.node != b.node do return _node_compare(a.node, b.node)
    if a.pos.offset < b.pos.offset do return -1
    if a.pos.offset > b.pos.offset do return 1
    return 0
}

@(private = "file")
_belongs_to :: proc(root, n: ^Node) -> bool {
    for cur := n; cur != nil; cur = cur.parent {
        if cur == root do return true
    }
    return false
}

@(private = "file")
_node_compare :: proc(a, b: ^Node) -> int {
    if a == b do return 0
    if a == nil do return -1
    if b == nil do return 1

    ac := make([dynamic]^Node, context.temp_allocator)
    bc := make([dynamic]^Node, context.temp_allocator)
    for n := a; n != nil; n = n.parent do append(&ac, n)
    for n := b; n != nil; n = n.parent do append(&bc, n)
    if ac[len(ac) - 1] != bc[len(bc) - 1] do return 0

    ai, bi := len(ac) - 1, len(bc) - 1
    for ai >= 0 && bi >= 0 && ac[ai] == bc[bi] {
        ai -= 1
        bi -= 1
    }
    if ai < 0 do return -1
    if bi < 0 do return 1

    common := ac[ai + 1]
    achild, bchild := ac[ai], bc[bi]
    for child in common.children {
        if child == achild do return -1
        if child == bchild do return 1
    }
    return 0
}
