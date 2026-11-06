package layout

import "base:runtime"
import "core:math"
import "src:core/node"
import YG "src:yoga"

@(private = "file")
Need :: struct {
    content: [2]f32,
    outer:   [2]f32,
}

@(private = "file")
ABSURD :: f32(1e6)

@(private = "file")
EDGES :: [2][2]YG.Edge{{.Left, .Right}, {.Top, .Bottom}}

@(private = "file")
frame :: proc(raw: YG.NodeRef, axis: int) -> f32 {
    edges := EDGES
    return YG.NodeLayoutGetPadding(raw, edges[axis][0]) + YG.NodeLayoutGetPadding(raw, edges[axis][1]) +
        YG.NodeLayoutGetBorder(raw, edges[axis][0]) + YG.NodeLayoutGetBorder(raw, edges[axis][1])
}

@(private = "file")
points :: proc(v: YG.Value) -> (f32, bool) {
    if v.unit != .Point || math.is_nan(v.value) do return 0, false
    return v.value, true
}

@(private = "file")
style_size :: proc(raw: YG.NodeRef, axis: int, which: enum { Size, Min, Max }) -> YG.Value {
    switch which {
    case .Size: return YG.NodeStyleGetWidth(raw) if axis == 0 else YG.NodeStyleGetHeight(raw)
    case .Min:  return YG.NodeStyleGetMinWidth(raw) if axis == 0 else YG.NodeStyleGetMinHeight(raw)
    case .Max:  return YG.NodeStyleGetMaxWidth(raw) if axis == 0 else YG.NodeStyleGetMaxHeight(raw)
    }
    return {}
}

@(private = "file")
border_box :: proc(raw: YG.NodeRef, axis: int, value: f32) -> f32 {
    return value + frame(raw, axis) if YG.NodeStyleGetBoxSizing(raw) == .ContentBox else value
}

// true when the node's flex basis, grow and shrink are still what pin wrote
// a restyle can overwrite them, so n.flex_pin being set alone doesnt mean it's still pinned
@(private = "file")
pinned :: proc(n: ^Node) -> bool {
    pin := n.flex_pin
    if pin == nil do return false
    basis, set := points(YG.NodeStyleGetFlexBasis(n.raw))
    return set && abs(basis - pin.held) < 0.01 && YG.NodeStyleGetFlexGrow(n.raw) == 0 && YG.NodeStyleGetFlexShrink(n.raw) == 0
}

@(private = "file")
pin :: proc(n: ^Node, axis: int, size: f32) {
    raw := n.raw
    held := size
    if YG.NodeStyleGetBoxSizing(raw) == .ContentBox do held = max(held - frame(raw, axis), 0)
    if !pinned(n) {
        if n.flex_pin == nil do n.flex_pin = new(node.Flex_Pin, runtime.heap_allocator())
        n.flex_pin.basis = YG.NodeStyleGetFlexBasis(raw)
        n.flex_pin.grow = YG.NodeStyleGetFlexGrow(raw)
        n.flex_pin.shrink = YG.NodeStyleGetFlexShrink(raw)
    }
    n.flex_pin.held = held
    // lock the item at this size with a fixed basis and no grow or shrink
    // a yoga min size cant do it, when every item of a line sit at its minimum yoga sizes blow up
    YG.NodeStyleSetFlexBasis(raw, held)
    YG.NodeStyleSetFlexGrow(raw, 0)
    YG.NodeStyleSetFlexShrink(raw, 0)
}

// give every pinned node under n its own flex style back
// call it before each layout cuz you can only see an item is squeezed in a layout without pins
release_pins :: proc(n: ^Node) {
    if n == nil || n.freed || n.raw == nil do return
    if n.flex_pin != nil {
        if pinned(n) {
            saved := n.flex_pin
            #partial switch saved.basis.unit {
            case .Point:   YG.NodeStyleSetFlexBasis(n.raw, saved.basis.value)
            case .Percent: YG.NodeStyleSetFlexBasisPercent(n.raw, saved.basis.value)
            case .Auto:    YG.NodeStyleSetFlexBasisAuto(n.raw)
            case:          YG.NodeStyleSetFlexBasis(n.raw, YG.UNDEFINED)
            }
            YG.NodeStyleSetFlexGrow(n.raw, saved.grow)
            YG.NodeStyleSetFlexShrink(n.raw, saved.shrink)
        }
        n->free_flex_pin()
    }
    for c in n._internal_children do release_pins(c)
}

@(private = "file")
flex_items :: proc(n: ^Node, out: ^[dynamic]^Node) {
    for c in n._internal_children {
        if c == nil || c.freed || c.structural || c.raw == nil do continue
        #partial switch YG.NodeStyleGetDisplay(c.raw) {
        case .None:
        case .Contents: flex_items(c, out)
        case: append(out, c)
        }
    }
}

@(private = "file")
visit :: proc(n: ^Node, changed: ^bool) -> Need {
    raw := n.raw
    row := false
    #partial switch YG.NodeStyleGetFlexDirection(raw) {
    case .Row, .RowReverse: row = true
    }
    main := 0 if row else 1
    wraps := YG.NodeStyleGetFlexWrap(raw) != .NoWrap
    gap := YG.NodeStyleGetGap(raw, .Column if row else .Row)
    if math.is_nan(gap) do gap = 0
    edges := EDGES
    // measure between the first and last item, not from the container edge, cuz alignment offsets are not content
    lines_from, lines_to: f32

    items := make([dynamic]^Node, context.temp_allocator)
    flex_items(n, &items)
    inner: [2]f32
    in_flow := 0
    for c in items {
        need := visit(c, changed)
        if YG.NodeStyleGetPositionType(c.raw) == .Absolute do continue

        floor := need.content[main]
        if size, set := points(style_size(c.raw, main, .Size)); set do floor = min(floor, border_box(c.raw, main, size))
        if limit, set := points(style_size(c.raw, main, .Max)); set do floor = min(floor, border_box(c.raw, main, limit))
        clips := c.clip_x if main == 0 else c.clip_y
        _, own_minimum := points(style_size(c.raw, main, .Min))
        actual := YG.NodeLayoutGetWidth(c.raw) if main == 0 else YG.NodeLayoutGetHeight(c.raw)
        // when every item of a line is squeezed yoga can blow their sizes up into the millions
        // so a size that big count as squeezed too
        if !clips && !own_minimum && (actual < floor - 0.5 || actual > ABSURD) {
            pin(c, main, floor)
            changed^ = true
        }

        for axis in 0 ..< 2 {
            margin := YG.NodeLayoutGetMargin(c.raw, edges[axis][0]) + YG.NodeLayoutGetMargin(c.raw, edges[axis][1])
            size := need.outer[axis] + margin
            switch {
            case axis == main && !wraps:
                inner[axis] += size + (gap if in_flow > 0 else 0)
            case axis != main && wraps:
                at := YG.NodeLayoutGetLeft(c.raw) if axis == 0 else YG.NodeLayoutGetTop(c.raw)
                extent := YG.NodeLayoutGetWidth(c.raw) if axis == 0 else YG.NodeLayoutGetHeight(c.raw)
                from := at - YG.NodeLayoutGetMargin(c.raw, edges[axis][0])
                to := at + max(extent, need.outer[axis]) + YG.NodeLayoutGetMargin(c.raw, edges[axis][1])
                lines_from = from if in_flow == 0 else min(lines_from, from)
                lines_to = to if in_flow == 0 else max(lines_to, to)
                inner[axis] = lines_to - lines_from
            case:
                inner[axis] = max(inner[axis], size)
            }
        }
        in_flow += 1
    }

    out: Need
    for axis in 0 ..< 2 {
        content := inner[axis] + frame(raw, axis)
        if in_flow == 0 {
            if n.min_content != nil {
                content = n.min_content(n)[axis] + frame(raw, axis)
            } else if axis == 1 && YG.NodeHasMeasureFunc(raw) {
                content = YG.NodeLayoutGetHeight(raw)
            }
        }
        out.content[axis] = content

        asked := content
        if (n.clip_x if axis == 0 else n.clip_y) do asked = frame(raw, axis)
        if size, set := points(style_size(raw, axis, .Size)); set do asked = border_box(raw, axis, size)
        if floor, set := points(style_size(raw, axis, .Min)); set do asked = max(asked, border_box(raw, axis, floor))
        if limit, set := points(style_size(raw, axis, .Max)); set do asked = min(asked, border_box(raw, axis, limit))
        out.outer[axis] = asked
    }
    return out
}

// stop flex items from shrinking below their content like css automatic minimum size, yoga dont have that
// true means some items got pinned to a bigger size, so run layout again
apply_auto_min :: proc(root: ^Node) -> (changed: bool) {
    if root == nil || root.freed || root.raw == nil do return false
    visit(root, &changed)
    return
}
