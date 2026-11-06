package style

import "core:math"

@(private)
finite :: proc(n: f32) -> bool {
    return !math.is_nan(n) && !math.is_inf(n)
}

@(private)
inherited :: proc(p: Property) -> bool {
    if p >= .Text_Transform && p <= .Text_Decoration_Line {
        return true
    }
    if p >= .Scrollbar_Width && p <= .Scrollbar_Track_Color {
        return true
    }
    return p == .Color || p == .Font_Size || p == .Line_Height || p == .Font_Weight || p == .Visibility || p == .Pointer_Events || p == .Direction || p == .Font_Family || p == .Text_Align || p == .Cursor
}

@(private)
is_color :: proc(p: Property) -> bool {
    return p == .Color || p == .Background_Color || p == .Outline_Color || p == .Scrollbar_Thumb_Color || p == .Scrollbar_Track_Color || (p >= .Border_Top_Color && p <= .Border_Left_Color)
}
@(private)
negative_allowed :: proc(p: Property) -> bool {
    if p == .Letter_Spacing || p == .Outline_Offset {
        return true
    }
    return (p >= .Margin_Top && p <= .Margin_Left) || (p >= .Top && p <= .Left) || p == .Translate_X || p == .Translate_Y || p == .Transform_Origin_X || p == .Transform_Origin_Y
}

@(private)
affects_layout :: proc(p: Property) -> bool {
    if is_color(p) || (p >= .Border_Top_Left_Radius && p <= .Border_Bottom_Left_Radius) || (p >= .Translate_X && p <= .Transform_Origin_Y) {
        return false
    }
    if p >= .Text_Decoration_Line && p <= .Outline_Offset {
        return false
    }
    if p >= .Border_Top_Left_Radius_Y && p <= .Scrollbar_Track_Color {
        return false
    }
    return p != .Opacity && p != .Visibility && p != .Pointer_Events && p != .Z_Index && p != .Cursor && p != .User_Select
}

@(private)
used_borders :: proc(c: ^Computed_Style) {
    for i in 0 ..< 4 {
        style := c[Property(int(Property.Border_Top_Style) + i)].keyword
        if style == .None || style == .Hidden {
            c[Property(int(Property.Border_Top_Width) + i)] = length(0)
        }
    }
    if c[.Outline_Style].keyword == .None {
        c[.Outline_Width] = length(0)
    }
}

@(private)
initial :: proc(p: Property) -> Value {
    #partial switch p {
    case .Color: return rgba(0, 0, 0, 1)
    case .Background_Color, .Scrollbar_Thumb_Color, .Scrollbar_Track_Color: return rgba(0, 0, 0, 0)
    case .Scrollbar_Width: return keyword(.Auto)
    case .Border_Top_Color, .Border_Right_Color, .Border_Bottom_Color, .Border_Left_Color: return keyword(.Current_Color)
    case .Border_Top_Style, .Border_Right_Style, .Border_Bottom_Style, .Border_Left_Style: return keyword(.None)
    case .Border_Top_Width, .Border_Right_Width, .Border_Bottom_Width, .Border_Left_Width: return length(3)
    case .Font_Family: return FAMILY
    case .Text_Align: return keyword(.Start)
    case .Cursor: return keyword(.Auto)
    case .Rotate: return number(0)
    case .Scale_X, .Scale_Y: return number(1)
    case .Transform_Origin_X, .Transform_Origin_Y: return length(50, .Percent)
    case .Transform: return keyword(.None)
    case .Opacity, .Flex_Shrink: return number(1)
    case .Flex_Grow: return number(0)
    case .Font_Weight: return number(400)
    case .Font_Size: return length(16)
    case .Line_Height: return keyword(.Normal)
    case .Width, .Height, .Min_Width, .Min_Height, .Flex_Basis, .Top, .Right, .Bottom, .Left, .Z_Index, .Align_Self, .Pointer_Events, .User_Select, .Aspect_Ratio: return keyword(.Auto)
    case .Max_Width, .Max_Height, .Grid_Template_Columns, .Grid_Template_Rows, .Grid_Template_Areas: return keyword(.None)
    case .Text_Transform, .Text_Decoration_Line, .Box_Shadow, .Background_Image, .Outline_Style, .Filter: return keyword(.None)
    case .White_Space: return keyword(.Normal)
    case .Text_Overflow: return keyword(.Clip)
    case .Outline_Color: return keyword(.Current_Color)
    case .Outline_Width: return length(3)
    case .Justify_Items: return keyword(.Stretch)
    case .Justify_Self: return keyword(.Auto)
    case .Grid_Auto_Columns, .Grid_Auto_Rows, .Grid_Column_Start, .Grid_Column_End, .Grid_Row_Start, .Grid_Row_End: return keyword(.Auto)
    // auto not 0, so code that only set the horizontal radius still get round corners
    case .Border_Top_Left_Radius_Y, .Border_Top_Right_Radius_Y, .Border_Bottom_Right_Radius_Y, .Border_Bottom_Left_Radius_Y: return keyword(.Auto)
    case .Display: return keyword(.Flex)
    case .Position: return keyword(.Relative)
    case .Flex_Direction: return keyword(.Row)
    case .Flex_Wrap: return keyword(.No_Wrap)
    case .Justify_Content: return keyword(.Flex_Start)
    case .Align_Items, .Align_Content: return keyword(.Stretch)
    case .Box_Sizing: return keyword(.Content_Box)
    case .Overflow_X, .Overflow_Y, .Visibility: return keyword(.Visible)
    case .Direction: return keyword(.Ltr)
    case: return length(0)
    }
}

@(private)
valid_value :: proc(p: Property, v: Value) -> bool {
    if int(p) < 0 || int(p) >= len(Property) {
        return false
    }
    if v.kind == .Keyword {
        k := v.keyword
        if k == .Initial || k == .Inherit || k == .Unset {
            return true
        }
        if is_color(p) {
            return k == .Current_Color
        }
        #partial switch p {
        case .Border_Top_Style, .Border_Right_Style, .Border_Bottom_Style, .Border_Left_Style: return k == .None || k == .Hidden || k == .Solid
        case .Text_Align: return k == .Left || k == .Right || k == .Center || k == .Start || k == .End
        case .Cursor: return k == .Auto || k == .Default || k == .Pointer || k == .Text || k == .Ew_Resize || k == .Ns_Resize || k == .Nwse_Resize || k == .Nesw_Resize
        case .Width, .Height, .Min_Width, .Min_Height, .Margin_Top, .Margin_Right, .Margin_Bottom, .Margin_Left, .Top, .Right, .Bottom, .Left, .Flex_Basis, .Z_Index: return k == .Auto
        case .Max_Width, .Max_Height, .Transform: return k == .None
        case .Border_Top_Left_Radius_Y, .Border_Top_Right_Radius_Y, .Border_Bottom_Right_Radius_Y, .Border_Bottom_Left_Radius_Y: return k == .Auto
        case .User_Select: return k == .Auto || k == .Text || k == .None || k == .All
        case .Aspect_Ratio: return k == .Auto
        case .Display: return k == .Flex || k == .None || (k >= .Block && k <= .Inline_Grid)
        case .Grid_Template_Columns, .Grid_Template_Rows, .Grid_Template_Areas: return k == .None
        case .Grid_Auto_Columns, .Grid_Auto_Rows: return k == .Auto
        case .Grid_Column_Start, .Grid_Column_End, .Grid_Row_Start, .Grid_Row_End:
            return k == .Auto || ((k == .Span || k == .Area) && v.number >= 1 && math.floor(v.number) == v.number)
        case .Position: return k == .Relative || k == .Absolute || k == .Fixed || k == .Sticky
        case .Text_Transform: return k == .None || k == .Uppercase || k == .Lowercase || k == .Capitalize
        case .White_Space: return k == .Normal || k == .No_Wrap || k == .Pre
        case .Text_Decoration_Line: return k == .None || k == .Underline || k == .Line_Through
        case .Text_Overflow: return k == .Clip || k == .Ellipsis
        case .Box_Shadow, .Background_Image, .Filter: return k == .None
        case .Scrollbar_Width: return k == .Auto || k == .Thin || k == .None
        case .Outline_Style: return k == .None || k == .Solid
        case .Justify_Items, .Justify_Self: return k == .Stretch || k == .Flex_Start || k == .Center || k == .Flex_End || (p == .Justify_Self && k == .Auto)
        case .Flex_Direction: return k == .Row || k == .Row_Reverse || k == .Column || k == .Column_Reverse
        case .Flex_Wrap: return k == .No_Wrap || k == .Wrap || k == .Wrap_Reverse
        case .Justify_Content: return k == .Flex_Start || k == .Flex_End || k == .Center || k == .Space_Between || k == .Space_Around || k == .Space_Evenly
        case .Align_Items, .Align_Self: return k == .Flex_Start || k == .Flex_End || k == .Center || k == .Stretch || k == .Baseline || (p == .Align_Self && k == .Auto)
        case .Align_Content: return k == .Flex_Start || k == .Flex_End || k == .Center || k == .Stretch || k == .Space_Between || k == .Space_Around || k == .Space_Evenly
        case .Box_Sizing: return k == .Content_Box || k == .Border_Box
        case .Overflow_X, .Overflow_Y: return k == .Visible || k == .Hidden || k == .Scroll || k == .Auto
        case .Visibility: return k == .Visible || k == .Hidden
        case .Pointer_Events: return k == .Auto || k == .None
        case .Direction: return k == .Ltr || k == .Rtl
        case .Line_Height: return k == .Normal
        case: return false
        }
    }
    if is_color(p) {
        if v.kind != .Color {
            return false
        }
        for c in v.color {
            if !(c >= 0 && c <= 1) {
                return false
            }
        }
        return true
    }
    if p == .Font_Family { return v.kind == .Family }
    if p == .Transform { return v.kind == .Transform }
    if p >= .Grid_Template_Columns && p <= .Grid_Auto_Rows { return v.kind == .Tracks }
    if p == .Grid_Template_Areas { return v.kind == .Areas }
    if p == .Filter { return v.kind == .Filter }
    if p == .Box_Shadow { return v.kind == .Shadows }
    if p == .Background_Image { return v.kind == .Gradient }
    if !finite(v.number) || !finite(v.percent) { return false }
    #partial switch p {
    case .Grid_Column_Start, .Grid_Column_End, .Grid_Row_Start, .Grid_Row_End:
        return v.kind == .Number && v.number != 0 && math.floor(v.number) == v.number
    case .Opacity, .Rotate, .Scale_X, .Scale_Y: return v.kind == .Number
    case .Flex_Grow, .Flex_Shrink: return v.kind == .Number && v.number >= 0
    case .Aspect_Ratio: return v.kind == .Number && v.number > 0
    case .Font_Weight: return v.kind == .Number && v.number >= 100 && v.number <= 900 && math.floor(v.number / 100) * 100 == v.number
    case .Z_Index: return v.kind == .Number && math.floor(v.number) == v.number && v.number >= -2147483648 && v.number < 2147483648
    case .Line_Height: if v.kind == .Number { return v.number >= 0 }
    case .Font_Size, .Width, .Height, .Min_Width, .Min_Height, .Max_Width, .Max_Height,
         .Margin_Top, .Margin_Right, .Margin_Bottom, .Margin_Left,
         .Padding_Top, .Padding_Right, .Padding_Bottom, .Padding_Left,
         .Top, .Right, .Bottom, .Left, .Border_Top_Width, .Border_Right_Width, .Border_Bottom_Width, .Border_Left_Width,
         .Row_Gap, .Column_Gap, .Flex_Basis,
         .Border_Top_Left_Radius, .Border_Top_Right_Radius, .Border_Bottom_Right_Radius, .Border_Bottom_Left_Radius,
         .Border_Top_Left_Radius_Y, .Border_Top_Right_Radius_Y, .Border_Bottom_Right_Radius_Y, .Border_Bottom_Left_Radius_Y,
         .Translate_X, .Translate_Y, .Transform_Origin_X, .Transform_Origin_Y,
         .Letter_Spacing, .Outline_Width, .Outline_Offset:
    case: return false
    }
    if v.kind != .Length || int(v.unit) < 0 || int(v.unit) >= len(Unit) { return false }
    if p >= .Border_Top_Width && p <= .Border_Left_Width && (v.unit == .Percent || v.percent != 0) { return false }
    return negative_allowed(p) || v.unit == .Calc || v.unit == .Math || v.number >= 0
}
// give the engine a way to measure ex and ch from the real font
// without it both fall back to 0.5em
set_font_metrics :: proc(e: ^Engine, metrics: Font_Metrics_Proc, data: rawptr = nil) {
    e.font_metrics, e.font_metrics_data = metrics, data
    e.dirty = true
}

// tell the engine the viewport size, root font size and reduced motion that css resolve against
// safe to call every frame, it only restyle when something actually change
set_environment :: proc(e: ^Engine, environment: Environment) -> Error {
    // NaN, inf or a negative size would poison every vw, vh, rem and media query
    if !finite(environment.width) || !finite(environment.height) || !finite(environment.root_font_size) || environment.width < 0 || environment.height < 0 || environment.root_font_size <= 0 { return .Invalid_Environment }
    // runtime call this every flush, going dirty every call would restyle the whole tree every frame
    if e.environment != environment { e.environment = environment; e.dirty = true }
    return .None
}

@(private)
media_matches :: proc(env: Environment, tests: []Media_Test) -> bool {
    for test in tests {
        matches := false
        #partial switch test.feature {
        case .Min_Width: matches = env.width >= test.value
        case .Max_Width: matches = env.width <= test.value
        case .Min_Height: matches = env.height >= test.value
        case .Max_Height: matches = env.height <= test.value
        case .Portrait: matches = env.height >= env.width
        case .Landscape: matches = env.width > env.height
        case .Reduced_Motion: matches = env.reduced_motion
        }
        if matches == test.negate { return false }
    }
    return true
}

@(private)
resolve_value :: proc(e: ^Engine, node, parent: ^Record, p: Property, v: Value, presentation := false) -> Value {
    if v.kind != .Length { return v }
    font := e.environment.root_font_size
    root_font := font
    if parent != nil {
        root := parent
        for e.tree.parent(e.tree.data, root.id) != 0 { root = &e.nodes[node_index(e, e.tree.parent(e.tree.data, root.id))] }
        root_font = root.presented[.Font_Size].number if presentation else root.pending[.Font_Size].number
    }
    if p == .Font_Size {
        if parent != nil { font = parent.presented[.Font_Size].number if presentation else parent.pending[.Font_Size].number }
    } else { font = node.presented[.Font_Size].number if presentation else node.pending[.Font_Size].number; if parent == nil { root_font = font } }
    scale: f32 = 1
    #partial switch v.unit {
    case .Px: return v
    case .Percent:
        if p != .Font_Size && p != .Line_Height { return v }
        scale = font / 100
    case .Em: scale = font
    case .Rem: scale = root_font
    case .Vw: scale = e.environment.width / 100
    case .Vh: scale = e.environment.height / 100
    case .Vmin: scale = min(e.environment.width, e.environment.height) / 100
    case .Vmax: scale = max(e.environment.width, e.environment.height) / 100
    case .Pt: scale = 96.0 / 72
    case .Pc: scale = 16
    case .In: scale = 96
    case .Cm: scale = 96.0 / 2.54
    case .Mm: scale = 96.0 / 25.4
    case .Q: scale = 96.0 / 101.6
    case .Ex, .Ch:
        source := parent if p == .Font_Size else node
        ex, ch: f32 = 0.5, 0.5
        if e.font_metrics != nil && source != nil {
            style := &source.presented if presentation else &source.pending
            ex, ch = e.font_metrics(e.font_metrics_data, source.id, family(e, style[.Font_Family]), style[.Font_Weight].number)
        }
        scale = font * (ex if v.unit == .Ex else ch)
    case .Calc, .Math: return v
    }
    return length(v.number * scale)
}
