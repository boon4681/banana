package style_native

import "core:math"
import style ".."
import "src:core/node"
import YG "src:yoga"

// sizes from the last layout, percent resolve against these
Basis :: struct { width, height, main, own_width, own_height: f32 }
@(private)
content_size :: proc(n: YG.NodeRef) -> (width, height: f32) {
    if n == nil { return }
    width = YG.NodeLayoutGetWidth(n) - YG.NodeLayoutGetPadding(n, .Left) - YG.NodeLayoutGetPadding(n, .Right) - YG.NodeLayoutGetBorder(n, .Left) - YG.NodeLayoutGetBorder(n, .Right)
    height = YG.NodeLayoutGetHeight(n) - YG.NodeLayoutGetPadding(n, .Top) - YG.NodeLayoutGetPadding(n, .Bottom) - YG.NodeLayoutGetBorder(n, .Top) - YG.NodeLayoutGetBorder(n, .Bottom)
    if math.is_nan(width) || width < 0 { width = 0 }
    if math.is_nan(height) || height < 0 { height = 0 }
    return
}
layout_basis :: proc(n: YG.NodeRef) -> (b: Basis) {
    parent := YG.NodeGetParent(n)
    b.width, b.height = content_size(parent)
    b.own_width, b.own_height = content_size(n)
    b.main = b.width
    if parent != nil {
        direction := YG.NodeStyleGetFlexDirection(parent)
        if direction == .Column || direction == .ColumnReverse { b.main = b.height }
    }
    return
}
// keep only the sizes this style use, so a change in the others dont count as a change
tracked_basis :: proc(n: YG.NodeRef, c: style.Computed_Style) -> Basis {
    b := layout_basis(n)
    if !deferred(c[.Row_Gap]) && !deferred(c[.Column_Gap]) { b.own_width, b.own_height = 0, 0 }
    return b
}
@(private)
deferred :: proc(v: style.Value) -> bool { return v.kind == .Length && (v.unit == .Calc || v.unit == .Math) }
needs_basis :: proc(c: style.Computed_Style) -> bool {
    for v in c { if deferred(v) { return true } }
    return false
}
// turn calc, min and max into px cuz yoga only take px or percent
@(private)
flatten :: proc(e: ^style.Engine, c: ^style.Computed_Style, b: Basis) {
    for p in style.Property.Width..=style.Property.Flex_Basis {
        if !deferred(c[p]) { continue }
        basis := b.width
        #partial switch p {
        case .Height, .Min_Height, .Max_Height, .Top, .Bottom: basis = b.height
        case .Row_Gap: basis = b.own_height
        case .Column_Gap: basis = b.own_width
        case .Flex_Basis: basis = b.main
        }
        px := style.evaluate(e, c[p], basis)
        negative := (p >= .Margin_Top && p <= .Margin_Left) || (p >= .Top && p <= .Left)
        c[p] = style.length(px if negative else max(0, px))
    }
}
@(private)
dimension :: proc(n: YG.NodeRef, v: style.Value, basis: f32, px, percent: YG.Style_Set_Proc, auto: YG.Style_Set_Auto_Proc = nil) {
    if v.kind == .Keyword {
        if v.keyword == .Auto && auto != nil { auto(n) } else { px(n, YG.UNDEFINED) }
    } else if v.unit == .Percent { percent(n, v.number) }
    else { px(n, max(0, style.resolve_percent(v, basis))) }
}
@(private)
edge :: proc(n: YG.NodeRef, which: YG.Edge, v: style.Value, basis: f32, px, percent: YG.Style_Set_Edge_Proc, auto: YG.Style_Set_Edge_Auto_Proc = nil) {
    if v.kind == .Keyword {
        if auto != nil { auto(n, which) } else { px(n, which, YG.UNDEFINED) }
    } else if v.unit == .Percent { percent(n, which, v.number) }
    else { px(n, which, style.resolve_percent(v, basis)) }
}
@(private)
align :: proc(k: style.Keyword) -> YG.Align {
    #partial switch k {
    case .Auto: return .Auto
    case .Flex_Start: return .FlexStart
    case .Flex_End: return .FlexEnd
    case .Center: return .Center
    case .Stretch: return .Stretch
    case .Baseline: return .Baseline
    case .Space_Between: return .SpaceBetween
    case .Space_Around: return .SpaceAround
    case .Space_Evenly: return .SpaceEvenly
    }
    unreachable()
}

// true for displays we lay out as block or inline flow
flow_container :: proc(display: style.Keyword) -> bool {
    return display == .Block || display == .Flow_Root || display == .Inline_Block || display == .Inline
}
grid_container :: proc(display: style.Keyword) -> bool { return display == .Grid || display == .Inline_Grid }
out_of_flow :: proc(c: style.Computed_Style) -> bool {
    return c[.Position].keyword == .Absolute || c[.Position].keyword == .Fixed
}

// get the sticky insets of a style, nil when not sticky
sticky :: proc(c: style.Computed_Style) -> Maybe(node.Sticky) {
    if c[.Position].keyword != .Sticky { return nil }
    s: node.Sticky
    for i in 0..<4 {
        v := c[style.Property(int(style.Property.Top) + i)]
        if v.kind != .Length { continue }
        s.set[i] = true
        #partial switch v.unit {
        case .Percent: s.percent[i] = v.number
        case .Calc: s.inset[i], s.percent[i] = v.number, v.percent // keep both parts cuz the percent is of the scroll port, unknown here
        case: s.inset[i] = v.number
        }
    }
    return s
}

// call after layout to pin a fixed node to the window
// true means the offsets changed, so run layout again
settle_fixed :: proc(n: YG.NodeRef, c: style.Computed_Style, applied: ^[4]f32) -> (changed: bool) {
    parent := YG.NodeGetParent(n)
    if parent == nil { return false }
    origin: [2]f32
    top := parent
    for at := parent; at != nil; at = YG.NodeGetParent(at) {
        origin += {YG.NodeLayoutGetLeft(at), YG.NodeLayoutGetTop(at)}
        top = at
    }
    window := [2]f32{YG.NodeLayoutGetWidth(top), YG.NodeLayoutGetHeight(top)}
    size := [2]f32{YG.NodeLayoutGetWidth(parent), YG.NodeLayoutGetHeight(parent)}
    edges := [4]YG.Edge{.Top, .Right, .Bottom, .Left}
    for which, i in edges {
        v := c[style.Property(int(style.Property.Top) + i)]
        if v.kind != .Length { continue }
        axis := 1 if i % 2 == 0 else 0
        want := style.resolve_percent(v, window[axis])
        border := YG.NodeLayoutGetBorder(parent, which)
        // css offset is from the window but yoga's is from the parent padding box
        offset := want - origin[axis] - border if i == 0 || i == 3 else want - (window[axis] - origin[axis] - size[axis]) - border
        if applied[i] == offset { continue }
        applied[i] = offset
        YG.NodeStyleSetPosition(n, which, offset)
        changed = true
    }
    return
}
@(private)
inline_level :: proc(display: style.Keyword) -> bool {
    return display == .Inline || display == .Inline_Block || display == .Inline_Flex || display == .Inline_Grid
}
// true when a sized block in flow need its right margin stretched to fill the line
fills_line :: proc(c: style.Computed_Style, parent: style.Keyword) -> bool {
    return flow_container(parent) && !inline_level(c[.Display].keyword) && c[.Width].kind != .Keyword &&
        c[.Margin_Left].kind != .Keyword && c[.Margin_Right].kind != .Keyword && !out_of_flow(c)
}
@(private)
line_fill :: proc(c: style.Computed_Style, parent_width: f32) -> f32 {
    own := style.resolve_percent(c[.Width], parent_width)
    if c[.Box_Sizing].keyword != .Border_Box {
        own += style.resolve_percent(c[.Padding_Left], parent_width) + style.resolve_percent(c[.Padding_Right], parent_width)
        own += c[.Border_Left_Width].number + c[.Border_Right_Width].number
    }
    own += style.resolve_percent(c[.Margin_Left], parent_width) + style.resolve_percent(c[.Margin_Right], parent_width)
    return max(0, parent_width - own)
}

// write the COMPLETE computed style into yoga, parent is the display of the direct parent
// return what the host still need to apply for text, paint and hit test
apply_layout :: proc(n: YG.NodeRef, computed: style.Computed_Style, e: ^style.Engine = nil, parent: style.Keyword = .Flex) -> style.Property_Set {
    b := layout_basis(n)
    c := computed
    flatten(e, &c, b)
    display := c[.Display].keyword
    in_flow := flow_container(parent) && !out_of_flow(c)
    dimension(n, c[.Width], b.width, YG.NodeStyleSetWidth, YG.NodeStyleSetWidthPercent, YG.NodeStyleSetWidthAuto)
    dimension(n, c[.Height], b.height, YG.NodeStyleSetHeight, YG.NodeStyleSetHeightPercent, YG.NodeStyleSetHeightAuto)
    dimension(n, c[.Min_Width], b.width, YG.NodeStyleSetMinWidth, YG.NodeStyleSetMinWidthPercent)
    dimension(n, c[.Min_Height], b.height, YG.NodeStyleSetMinHeight, YG.NodeStyleSetMinHeightPercent)
    dimension(n, c[.Max_Width], b.width, YG.NodeStyleSetMaxWidth, YG.NodeStyleSetMaxWidthPercent)
    dimension(n, c[.Max_Height], b.height, YG.NodeStyleSetMaxHeight, YG.NodeStyleSetMaxHeightPercent)
    YG.NodeStyleSetFlex(n, YG.UNDEFINED)
    if in_flow {
        whole_line := !inline_level(display) && c[.Width].kind == .Keyword
        if whole_line { YG.NodeStyleSetFlexBasisPercent(n, 100) } else { YG.NodeStyleSetFlexBasisAuto(n) }
        YG.NodeStyleSetFlexGrow(n, 1 if whole_line else 0)
        YG.NodeStyleSetFlexShrink(n, 1 if whole_line || inline_level(display) else 0)
    } else {
        dimension(n, c[.Flex_Basis], b.main, YG.NodeStyleSetFlexBasis, YG.NodeStyleSetFlexBasisPercent, YG.NodeStyleSetFlexBasisAuto)
        YG.NodeStyleSetFlexGrow(n, c[.Flex_Grow].number)
        YG.NodeStyleSetFlexShrink(n, c[.Flex_Shrink].number)
    }
    YG.NodeStyleSetAspectRatio(n, c[.Aspect_Ratio].number if c[.Aspect_Ratio].kind == .Number else YG.UNDEFINED)
    // clear legacy shorthand and logical edges or a removed rule never reset
    clear_edges := []YG.Edge{.Start, .End, .Horizontal, .Vertical, .All}
    for which in clear_edges {
        YG.NodeStyleSetMargin(n, which, YG.UNDEFINED)
        YG.NodeStyleSetPadding(n, which, YG.UNDEFINED)
        YG.NodeStyleSetPosition(n, which, YG.UNDEFINED)
        YG.NodeStyleSetBorder(n, which, YG.UNDEFINED)
    }
    edges := []YG.Edge{.Top, .Right, .Bottom, .Left}
    for which, i in edges {
        edge(n, which, c[style.Property(int(style.Property.Margin_Top)+i)], b.width, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto)
        edge(n, which, c[style.Property(int(style.Property.Padding_Top)+i)], b.width, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent)
        inset := c[style.Property(int(style.Property.Top)+i)]
        if c[.Position].keyword == .Sticky { inset = style.keyword(.Auto) }
        edge(n, which, inset, b.height if i % 2 == 0 else b.width, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto)
        YG.NodeStyleSetBorder(n, which, c[style.Property(int(style.Property.Border_Top_Width)+i)].number)
    }
    if fills_line(c, parent) {
        YG.NodeStyleSetMargin(n, .Right, style.resolve_percent(c[.Margin_Right], b.width) + line_fill(c, b.width))
    }
    YG.NodeStyleSetGap(n, .All, YG.UNDEFINED)
    gaps := []YG.Gutter{.Row, .Column}
    for gutter, i in gaps {
        v := c[style.Property(int(style.Property.Row_Gap)+i)]
        if v.unit == .Percent { YG.NodeStyleSetGapPercent(n, gutter, v.number) }
        else { YG.NodeStyleSetGap(n, gutter, max(0, style.resolve_percent(v, b.own_height if i == 0 else b.own_width))) }
    }
    YG.NodeStyleSetDisplay(n, .None if display == .None else .Contents if display == .Contents else .Flex)
    YG.NodeStyleSetPositionType(n, .Absolute if out_of_flow(c) else .Relative)
    YG.NodeStyleSetBoxSizing(n, .BorderBox if c[.Box_Sizing].keyword == .Border_Box else .ContentBox)
    YG.NodeStyleSetDirection(n, .RTL if c[.Direction].keyword == .Rtl else .LTR)
    if flow_container(display) {
        // yoga has no block flow, so fake it with a wrapping row
        // a block child take a whole line and an inline child sit in it
        c[.Flex_Direction] = style.keyword(.Row)
        c[.Flex_Wrap] = style.keyword(.Wrap)
        c[.Align_Items] = style.keyword(.Flex_Start)
        c[.Align_Content] = style.keyword(.Flex_Start)
        c[.Justify_Content] = style.keyword(.Flex_Start)
        #partial switch c[.Text_Align].keyword {
        case .Center: c[.Justify_Content] = style.keyword(.Center)
        case .Right, .End: c[.Justify_Content] = style.keyword(.Flex_End)
        }
    }
    #partial switch c[.Flex_Direction].keyword {
    case .Row: YG.NodeStyleSetFlexDirection(n, .Row)
    case .Row_Reverse: YG.NodeStyleSetFlexDirection(n, .RowReverse)
    case .Column: YG.NodeStyleSetFlexDirection(n, .Column)
    case .Column_Reverse: YG.NodeStyleSetFlexDirection(n, .ColumnReverse)
    }
    #partial switch c[.Flex_Wrap].keyword {
    case .No_Wrap: YG.NodeStyleSetFlexWrap(n, .NoWrap)
    case .Wrap: YG.NodeStyleSetFlexWrap(n, .Wrap)
    case .Wrap_Reverse: YG.NodeStyleSetFlexWrap(n, .WrapReverse)
    }
    #partial switch c[.Justify_Content].keyword {
    case .Flex_Start: YG.NodeStyleSetJustifyContent(n, .FlexStart)
    case .Flex_End: YG.NodeStyleSetJustifyContent(n, .FlexEnd)
    case .Center: YG.NodeStyleSetJustifyContent(n, .Center)
    case .Space_Between: YG.NodeStyleSetJustifyContent(n, .SpaceBetween)
    case .Space_Around: YG.NodeStyleSetJustifyContent(n, .SpaceAround)
    case .Space_Evenly: YG.NodeStyleSetJustifyContent(n, .SpaceEvenly)
    }
    YG.NodeStyleSetAlignItems(n, align(c[.Align_Items].keyword))
    YG.NodeStyleSetAlignSelf(n, align(c[.Align_Self].keyword))
    YG.NodeStyleSetAlignContent(n, align(c[.Align_Content].keyword))
    overflow: YG.Overflow = .Visible
    x, y := c[.Overflow_X].keyword, c[.Overflow_Y].keyword
    if x == .Hidden || y == .Hidden { overflow = .Hidden }
    if x == .Auto || y == .Auto || x == .Scroll || y == .Scroll { overflow = .Scroll }
    YG.NodeStyleSetOverflow(n, overflow)
    remaining: style.Property_Set = {.Color, .Background_Color, .Opacity, .Font_Size, .Line_Height, .Font_Weight, .Visibility, .Pointer_Events, .Z_Index, .Overflow_X, .Overflow_Y}
    for p in style.Property.Border_Top_Color..=style.Property.Transform { remaining += {p} }
    return remaining
}
