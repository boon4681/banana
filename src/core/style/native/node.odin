package style_native

import "core:math"
import style ".."
import "src:core/node"
import "src:core/common"
import YG "src:yoga"

@(private)
overflow :: proc(k: style.Keyword) -> node.Overflow {
    #partial switch k {
    case .Visible: return .Visible
    case .Hidden: return .Hidden
    case .Scroll: return .Scroll
    case .Auto: return .Auto
    }
    unreachable()
}

color :: proc(v: style.Value, alpha: f32 = 1) -> (result: common.Color) {
    for value, i in v.color { result[i] = u8(clamp(value * (alpha if i == 3 else 1) * 255 + 0.5, 0, 255)) }
    return
}

// get the shadows, gradient and outline of a computed style
// the slices inside point into the engine, valid until the engine is destroyed
decoration :: proc(c: style.Computed_Style, alpha: f32 = 1, e: ^style.Engine = nil) -> (d: common.EffectFilterDecoration) {
    d.alpha = alpha
    d.shadows = transmute([]common.EffectShadow)style.shadows(e, c[.Box_Shadow])
    if gradient, ok := style.gradient(e, c[.Background_Image]); ok {
        d.gradient = {kind = common.Gradient_Kind(gradient.kind), angle = gradient.angle, stops = transmute([]common.Gradient_Stop)gradient.stops}
    }
    d.outline_width = c[.Outline_Width].number
    d.outline_offset = c[.Outline_Offset].number
    d.outline_color = color(c[.Outline_Color], alpha)
    return
}

Border :: struct { color: [4]common.Color, width: [4]f32, radius, radius_percent: common.Radii }
border :: proc(c: style.Computed_Style, alpha: f32 = 1) -> (b: Border) {
    for i in 0..<4 {
        b.color[i] = color(c[style.Property(int(style.Property.Border_Top_Color) + i)], alpha)
        b.width[i] = c[style.Property(int(style.Property.Border_Top_Width) + i)].number
        across := c[style.Property(int(style.Property.Border_Top_Left_Radius) + i)]
        down := c[style.Property(int(style.Property.Border_Top_Left_Radius_Y) + i)]
        if down.kind == .Keyword { down = across }
        for radius, axis in ([2]style.Value{across, down}) {
            #partial switch radius.unit {
            case .Percent: b.radius_percent[i][axis] = radius.number
            case .Calc: b.radius[i][axis], b.radius_percent[i][axis] = radius.number, radius.percent
            case: b.radius[i][axis] = radius.number
            }
        }
    }
    return b
}
@(private)
op_matrix :: proc(e: ^style.Engine, op: style.Transform_Op, w, h: f32) -> common.Mat3x3 {
    m := common.Mat3X3_IDENTITY
    n := op.numbers
    switch op.kind {
    case .Translate: m[0, 2], m[1, 2] = style.evaluate(e, op.x, w), style.evaluate(e, op.y, h)
    case .Rotate:
        c, s := math.cos(math.to_radians(n[0])), math.sin(math.to_radians(n[0]))
        m[0, 0], m[0, 1], m[1, 0], m[1, 1] = c, -s, s, c
    case .Scale: m[0, 0], m[1, 1] = n[0], n[1]
    case .Skew: m[0, 1], m[1, 0] = math.tan(math.to_radians(n[0])), math.tan(math.to_radians(n[1]))
    case .Matrix: m[0, 0], m[1, 0], m[0, 1], m[1, 1], m[0, 2], m[1, 2] = n[0], n[1], n[2], n[3], n[4], n[5]
    }
    return m
}
// give the full node transform
// yoga layout must be done, and pass the engine for transform lists and min()/max()
transform :: proc(n: ^node.BaseNode, c: style.Computed_Style, e: ^style.Engine = nil) -> common.Transform {
    // percent and transform-origin are of the laid out size
    w, h := YG.NodeLayoutGetWidth(n.raw), YG.NodeLayoutGetHeight(n.raw)
    if math.is_nan(w) { w = 0 }
    if math.is_nan(h) { h = 0 }
    t := common.Transform{
        translate = {style.evaluate(e, c[.Translate_X], w), style.evaluate(e, c[.Translate_Y], h)},
        rotate = math.to_radians(c[.Rotate].number),
        scale = {c[.Scale_X].number, c[.Scale_Y].number},
    }
    // css order is translate, rotate, scale, then the transform list on top
    if ops := style.transform_ops(e, c[.Transform]); len(ops) > 0 {
        m := common.transform_to_matrix(t)
        for op in ops { m = m * op_matrix(e, op, w, h) }
        t = {translate = {m[0, 2], m[1, 2]}, scale = {1, 1}}
        linear := [4]f32{m[0, 0], m[1, 0], m[0, 1], m[1, 1]}
        identity := [4]f32{1, 0, 0, 1}
        if linear != identity { t.linear, t.has_linear = linear, true }
    }
    if t == common.IDENTITY_TRANSFORM { return t }
    t.origin = {style.evaluate(e, c[.Transform_Origin_X], w), style.evaluate(e, c[.Transform_Origin_Y], h)}
    return t
}

// write the computed style into the node's own style, node.Style must be initialized
// return what's left for Paint_Proc and the host, like font family, cursor and transform
apply_node :: proc(n: ^node.BaseNode, c: style.Computed_Style, alpha: f32 = 1, e: ^style.Engine = nil, parent: style.Keyword = .Flex) -> style.Property_Set {
    assert(n != nil && n.raw != nil && n._internal_style != nil)
    apply_layout(n.raw, c, e, parent)
    s := cast(^node.Style)n._internal_style
    b := border(c, alpha)
    s.background = color(c[.Background_Color], alpha)
    s.border_color, s.border_width = b.color, b.width
    s.radius, s.radius_percent = b.radius, b.radius_percent
    s.decoration = decoration(c, alpha, e)
    s.computed_text = true
    // write the fields directly cuz on a styled node the setters would add inline style instead
    s.text.color = color(c[.Color], alpha)
    s.text.font_size = c[.Font_Size].number
    s.text.font_weight = node.FontWeight(c[.Font_Weight].number)
    line := c[.Line_Height]
    s.text.line_height_unit = .Percent if line.kind == .Number else .Point
    s.text.line_height = 0 if line.kind == .Keyword else line.number // 0 means normal, use the native font metrics
    s.text.line_height_specified = line.kind != .Keyword
    align := c[.Text_Align].keyword
    rtl := c[.Direction].keyword == .Rtl
    if align == .Start { align = .Right if rtl else .Left }
    if align == .End { align = .Left if rtl else .Right }
    s.text.align = .Center if align == .Center else (.Right if align == .Right else .Left)
    #partial switch c[.Text_Transform].keyword {
    case .Uppercase: s.text.transform = .Uppercase
    case .Lowercase: s.text.transform = .Lowercase
    case .Capitalize: s.text.transform = .Capitalize
    case: s.text.transform = .None
    }
    #partial switch c[.White_Space].keyword {
    case .No_Wrap: s.text.white_space = .No_Wrap
    case .Pre: s.text.white_space = .Pre
    case: s.text.white_space = .Normal
    }
    #partial switch c[.Text_Decoration_Line].keyword {
    case .Underline: s.text.decoration = .Underline
    case .Line_Through: s.text.decoration = .Line_Through
    case: s.text.decoration = .None
    }
    s.text.overflow = .Ellipsis if c[.Text_Overflow].keyword == .Ellipsis else .Clip
    s.text.letter_spacing, s.text.letter_spacing_set = c[.Letter_Spacing].number, true
    hidden := c[.Visibility].keyword == .Hidden
    s.pointer_events = .None if hidden || c[.Pointer_Events].keyword == .None else .Auto
    n.z_index = 0 if c[.Z_Index].kind == .Keyword else i32(c[.Z_Index].number)
    #partial switch c[.User_Select].keyword {
    case .Text: s.select_mode = .Text
    case .None: s.select_mode = .None
    case .All: s.select_mode = .All
    case: s.select_mode = .Auto
    }
    s->apply_overflow(overflow(c[.Overflow_X].keyword), overflow(c[.Overflow_Y].keyword))
    if YG.NodeHasMeasureFunc(n.raw) { YG.NodeMarkDirty(n.raw) }
    remaining: style.Property_Set = {.Opacity, .Visibility, .Font_Family, .Cursor}
    for p in style.Property.Translate_X..=style.Property.Transform { remaining += {p} }
    return remaining
}
