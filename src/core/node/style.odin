package node;

import YG "src:yoga"
import "base:intrinsics"
import "core:reflect"
import "base:runtime"
import "src:core/common"
import "src:core/text"

unit          :: YG.Unit
px            :: YG.Unit.Point
percent       :: YG.Unit.Percent
auto          :: YG.Unit.Auto
Edge          :: YG.Edge
Direction     :: YG.Direction
FlexDirection :: YG.FlexDirection
Justify       :: YG.Justify
Align         :: YG.Align
Position      :: YG.PositionType
Wrap          :: YG.Wrap
Display       :: YG.Display
BoxSizing     :: YG.BoxSizing
// CSS `overflow`, which unlike Yoga's enum has a distinct `auto`. Kept per-axis;
// see _set_overflow for how the pair collapses to Yoga's single node-wide value.
Overflow :: enum {
    Visible,
    Hidden,
    Scroll,
    Auto,
}
Font :: text.Font_Set

Text_Style :: struct {
    color:            common.Color,
    font_size:        f32,
    line_height:      f32,
    line_height_unit: unit,
    font:             ^Font,
}

Style :: struct {
    owner: ^Node,
    v:     map[string]any, // holder for any value (for extending)
    text:  Text_Style,
    // Not Yoga-backed: Yoga stores one node-wide overflow, CSS one per axis.
    overflow_x: Overflow,
    overflow_y: Overflow,
    using _internal_vt: ^Style_VTable,
}

@(private="file")
_set_value :: proc(n: YG.NodeRef, v: f32, u: unit, pt: YG.Style_Set_Proc, pct: YG.Style_Set_Proc, aut: YG.Style_Set_Auto_Proc = nil) {
    #partial switch u {
    case .Point:   pt(n, v)
    case .Percent: pct(n, v)
    case .Auto:    if aut != nil do aut(n)
    }
}

@(private="file")
_set_edge :: proc(n: YG.NodeRef, e: Edge, v: f32, u: unit, pt: YG.Style_Set_Edge_Proc, pct: YG.Style_Set_Edge_Proc, aut: YG.Style_Set_Edge_Auto_Proc = nil) {
    #partial switch u {
    case .Point:   pt(n, e, v)
    case .Percent: pct(n, e, v)
    case .Auto:    if aut != nil do aut(n, e)
    }
}

// Yoga-backed style implementation. Every proc reads/writes the Yoga node
// directly; `Style.v` is reserved for non-yoga style values only.
@(private="file")
style_vtable := Style_VTable{
    get_direction       = proc(self: Style, v: Direction) -> Direction { return YG.NodeStyleGetDirection(self.owner.raw) },
    get_flex_direction  = proc(self: Style, v: FlexDirection) -> FlexDirection { return YG.NodeStyleGetFlexDirection(self.owner.raw) },
    get_justify_content = proc(self: Style, v: Justify) -> Justify { return YG.NodeStyleGetJustifyContent(self.owner.raw) },
    get_align_content   = proc(self: Style, v: Align) -> Align { return YG.NodeStyleGetAlignContent(self.owner.raw) },
    get_align_items     = proc(self: Style, v: Align) -> Align { return YG.NodeStyleGetAlignItems(self.owner.raw) },
    get_align_self      = proc(self: Style, v: Align) -> Align { return YG.NodeStyleGetAlignSelf(self.owner.raw) },
    get_position_type   = proc(self: Style, v: Position) -> Position { return YG.NodeStyleGetPositionType(self.owner.raw) },
    get_wrap            = proc(self: Style, v: Wrap) -> Wrap { return YG.NodeStyleGetFlexWrap(self.owner.raw) },
    get_display         = proc(self: Style, v: Display) -> Display { return YG.NodeStyleGetDisplay(self.owner.raw) },
    // `overflow` reads back the x axis, mirroring how CSS shorthands resolve.
    get_overflow     = proc(self: Style, v: Overflow) -> Overflow { return _stored(self).overflow_x },
    get_overflow_x   = proc(self: Style, v: Overflow) -> Overflow { return _stored(self).overflow_x },
    get_overflow_y   = proc(self: Style, v: Overflow) -> Overflow { return _stored(self).overflow_y },
    get_box_sizing   = proc(self: Style, v: BoxSizing) -> BoxSizing { return YG.NodeStyleGetBoxSizing(self.owner.raw) },
    get_flex         = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetFlex(self.owner.raw) },
    get_flex_grow    = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetFlexGrow(self.owner.raw) },
    get_flex_shrink  = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetFlexShrink(self.owner.raw) },
    get_aspect_ratio = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetAspectRatio(self.owner.raw) },

    get_width      = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetWidth(self.owner.raw); return r.value, r.unit },
    get_height     = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetHeight(self.owner.raw); return r.value, r.unit },
    get_min_width  = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMinWidth(self.owner.raw); return r.value, r.unit },
    get_min_height = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMinHeight(self.owner.raw); return r.value, r.unit },
    get_max_width  = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMaxWidth(self.owner.raw); return r.value, r.unit },
    get_max_height = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMaxHeight(self.owner.raw); return r.value, r.unit },
    get_flex_basis = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetFlexBasis(self.owner.raw); return r.value, r.unit },

    get_margin_left       = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMargin(self.owner.raw, .Left); return r.value, r.unit },
    get_margin_top        = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMargin(self.owner.raw, .Top); return r.value, r.unit },
    get_margin_right      = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMargin(self.owner.raw, .Right); return r.value, r.unit },
    get_margin_bottom     = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMargin(self.owner.raw, .Bottom); return r.value, r.unit },
    get_margin_start      = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMargin(self.owner.raw, .Start); return r.value, r.unit },
    get_margin_end        = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMargin(self.owner.raw, .End); return r.value, r.unit },
    get_margin_horizontal = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMargin(self.owner.raw, .Horizontal); return r.value, r.unit },
    get_margin_vertical   = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMargin(self.owner.raw, .Vertical); return r.value, r.unit },
    get_margin_all        = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetMargin(self.owner.raw, .All); return r.value, r.unit },

    get_padding_left       = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPadding(self.owner.raw, .Left); return r.value, r.unit },
    get_padding_top        = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPadding(self.owner.raw, .Top); return r.value, r.unit },
    get_padding_right      = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPadding(self.owner.raw, .Right); return r.value, r.unit },
    get_padding_bottom     = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPadding(self.owner.raw, .Bottom); return r.value, r.unit },
    get_padding_start      = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPadding(self.owner.raw, .Start); return r.value, r.unit },
    get_padding_end        = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPadding(self.owner.raw, .End); return r.value, r.unit },
    get_padding_horizontal = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPadding(self.owner.raw, .Horizontal); return r.value, r.unit },
    get_padding_vertical   = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPadding(self.owner.raw, .Vertical); return r.value, r.unit },
    get_padding_all        = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPadding(self.owner.raw, .All); return r.value, r.unit },

    get_position_left       = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPosition(self.owner.raw, .Left); return r.value, r.unit },
    get_position_top        = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPosition(self.owner.raw, .Top); return r.value, r.unit },
    get_position_right      = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPosition(self.owner.raw, .Right); return r.value, r.unit },
    get_position_bottom     = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPosition(self.owner.raw, .Bottom); return r.value, r.unit },
    get_position_start      = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPosition(self.owner.raw, .Start); return r.value, r.unit },
    get_position_end        = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPosition(self.owner.raw, .End); return r.value, r.unit },
    get_position_horizontal = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPosition(self.owner.raw, .Horizontal); return r.value, r.unit },
    get_position_vertical   = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPosition(self.owner.raw, .Vertical); return r.value, r.unit },
    get_position_all        = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetPosition(self.owner.raw, .All); return r.value, r.unit },

    get_border_left       = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Left) },
    get_border_top        = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Top) },
    get_border_right      = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Right) },
    get_border_bottom     = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Bottom) },
    get_border_start      = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Start) },
    get_border_end        = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .End) },
    get_border_horizontal = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Horizontal) },
    get_border_vertical   = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Vertical) },
    get_border_all        = proc(self: Style, v: f32) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .All) },

    get_gap_column = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetGap(self.owner.raw, .Column); return r.value, r.unit },
    get_gap_row    = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetGap(self.owner.raw, .Row); return r.value, r.unit },
    get_gap_all    = proc(self: Style, v: f32, u := px) -> (f32, unit) { r := YG.NodeStyleGetGap(self.owner.raw, .All); return r.value, r.unit },

    get_color       = proc(self: Style, v: Color) -> Color { return Resolve_Text_Style(self.owner).color },
    get_font_size   = proc(self: Style, v: f32) -> f32 { return Resolve_Text_Style(self.owner).font_size },
    get_font        = proc(self: Style, v: ^Font) -> ^Font { return Resolve_Text_Style(self.owner).font },
    get_line_height = proc(self: Style, v: f32, u := px) -> (f32, unit) { st := Resolve_Text_Style(self.owner); return st.line_height, st.line_height_unit },

    set_direction       = proc(self: Style, val: Direction) -> Style { YG.NodeStyleSetDirection(self.owner.raw, val); return self },
    set_flex_direction  = proc(self: Style, val: FlexDirection) -> Style { YG.NodeStyleSetFlexDirection(self.owner.raw, val); return self },
    set_justify_content = proc(self: Style, val: Justify) -> Style { YG.NodeStyleSetJustifyContent(self.owner.raw, val); return self },
    set_align_content   = proc(self: Style, val: Align) -> Style { YG.NodeStyleSetAlignContent(self.owner.raw, val); return self },
    set_align_items     = proc(self: Style, val: Align) -> Style { YG.NodeStyleSetAlignItems(self.owner.raw, val); return self },
    set_align_self      = proc(self: Style, val: Align) -> Style { YG.NodeStyleSetAlignSelf(self.owner.raw, val); return self },
    set_position_type   = proc(self: Style, val: Position) -> Style { YG.NodeStyleSetPositionType(self.owner.raw, val); return self },
    set_wrap            = proc(self: Style, val: Wrap) -> Style { YG.NodeStyleSetFlexWrap(self.owner.raw, val); return self },
    set_display         = proc(self: Style, val: Display) -> Style { YG.NodeStyleSetDisplay(self.owner.raw, val); return self },
    set_overflow        = proc(self: Style, val: Overflow) -> Style { _set_overflow(self.owner, val, val); return self },
    set_overflow_x      = proc(self: Style, val: Overflow) -> Style { s := _stored(self); _set_overflow(self.owner, val, s.overflow_y); return self },
    set_overflow_y      = proc(self: Style, val: Overflow) -> Style { s := _stored(self); _set_overflow(self.owner, s.overflow_x, val); return self },
    set_box_sizing      = proc(self: Style, val: BoxSizing) -> Style { YG.NodeStyleSetBoxSizing(self.owner.raw, val); return self },
    set_flex            = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetFlex(self.owner.raw, v); return self },
    set_flex_grow       = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetFlexGrow(self.owner.raw, v); return self },
    set_flex_shrink     = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetFlexShrink(self.owner.raw, v); return self },
    set_aspect_ratio    = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetAspectRatio(self.owner.raw, v); return self },

    set_width      = proc(self: Style, v: f32, u := px) -> Style { _set_value(self.owner.raw, v, u, YG.NodeStyleSetWidth, YG.NodeStyleSetWidthPercent, YG.NodeStyleSetWidthAuto); return self },
    set_height     = proc(self: Style, v: f32, u := px) -> Style { _set_value(self.owner.raw, v, u, YG.NodeStyleSetHeight, YG.NodeStyleSetHeightPercent, YG.NodeStyleSetHeightAuto); return self },
    set_min_width  = proc(self: Style, v: f32, u := px) -> Style { _set_value(self.owner.raw, v, u, YG.NodeStyleSetMinWidth, YG.NodeStyleSetMinWidthPercent); return self },
    set_min_height = proc(self: Style, v: f32, u := px) -> Style { _set_value(self.owner.raw, v, u, YG.NodeStyleSetMinHeight, YG.NodeStyleSetMinHeightPercent); return self },
    set_max_width  = proc(self: Style, v: f32, u := px) -> Style { _set_value(self.owner.raw, v, u, YG.NodeStyleSetMaxWidth, YG.NodeStyleSetMaxWidthPercent); return self },
    set_max_height = proc(self: Style, v: f32, u := px) -> Style { _set_value(self.owner.raw, v, u, YG.NodeStyleSetMaxHeight, YG.NodeStyleSetMaxHeightPercent); return self },
    set_flex_basis = proc(self: Style, v: f32, u := px) -> Style { _set_value(self.owner.raw, v, u, YG.NodeStyleSetFlexBasis, YG.NodeStyleSetFlexBasisPercent, YG.NodeStyleSetFlexBasisAuto); return self },

    set_margin_left       = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Left, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto); return self },
    set_margin_top        = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Top, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto); return self },
    set_margin_right      = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Right, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto); return self },
    set_margin_bottom     = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Bottom, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto); return self },
    set_margin_start      = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Start, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto); return self },
    set_margin_end        = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .End, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto); return self },
    set_margin_horizontal = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Horizontal, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto); return self },
    set_margin_vertical   = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Vertical, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto); return self },
    set_margin_all        = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .All, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto); return self },

    set_padding_left       = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Left, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent); return self },
    set_padding_top        = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Top, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent); return self },
    set_padding_right      = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Right, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent); return self },
    set_padding_bottom     = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Bottom, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent); return self },
    set_padding_start      = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Start, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent); return self },
    set_padding_end        = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .End, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent); return self },
    set_padding_horizontal = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Horizontal, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent); return self },
    set_padding_vertical   = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Vertical, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent); return self },
    set_padding_all        = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .All, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent); return self },

    set_position_left       = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Left, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto); return self },
    set_position_top        = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Top, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto); return self },
    set_position_right      = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Right, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto); return self },
    set_position_bottom     = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Bottom, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto); return self },
    set_position_start      = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Start, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto); return self },
    set_position_end        = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .End, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto); return self },
    set_position_horizontal = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Horizontal, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto); return self },
    set_position_vertical   = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .Vertical, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto); return self },
    set_position_all        = proc(self: Style, v: f32, u := px) -> Style { _set_edge(self.owner.raw, .All, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto); return self },

    set_border_left       = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetBorder(self.owner.raw, .Left, v); return self },
    set_border_top        = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetBorder(self.owner.raw, .Top, v); return self },
    set_border_right      = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetBorder(self.owner.raw, .Right, v); return self },
    set_border_bottom     = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetBorder(self.owner.raw, .Bottom, v); return self },
    set_border_start      = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetBorder(self.owner.raw, .Start, v); return self },
    set_border_end        = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetBorder(self.owner.raw, .End, v); return self },
    set_border_horizontal = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetBorder(self.owner.raw, .Horizontal, v); return self },
    set_border_vertical   = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetBorder(self.owner.raw, .Vertical, v); return self },
    set_border_all        = proc(self: Style, v: f32) -> Style { YG.NodeStyleSetBorder(self.owner.raw, .All, v); return self },
    set_gap_column        = proc(self: Style, v: f32, u := px) -> Style { _set_value_gutter(self.owner.raw, .Column, v, u); return self },
    set_gap_row           = proc(self: Style, v: f32, u := px) -> Style { _set_value_gutter(self.owner.raw, .Row, v, u); return self },
    set_gap_all           = proc(self: Style, v: f32, u := px) -> Style { _set_value_gutter(self.owner.raw, .All, v, u); return self },

    set_color       = proc(self: Style, v: Color) -> Style { _stored(self).text.color = v; return self },
    set_font_size   = proc(self: Style, v: f32) -> Style { _stored(self).text.font_size = v; return self },
    set_line_height = proc(self: Style, v: f32, u := px) -> Style { s := _stored(self); s.text.line_height = v; s.text.line_height_unit = u; return self },
    set_font        = proc(self: Style, v: ^Font) -> Style { _stored(self).text.font = v; return self },
}

// Text properties aren't yoga-backed; they live on the node's stored Style.
// `self` is a by-value copy, so writes must go through the owner's pointer.
@(private="file")
_stored :: proc(self: Style) -> ^Style {
    return cast(^Style)self.owner._internal_style
}

@(private="file")
_stored_base :: proc(n: ^Node) -> ^Style {
    return cast(^Style)n._internal_style
}

// `overflow` is both a layout input (Yoga) and a paint input: anything other
// than `visible` clips descendants to this node's padding box, per CSS.
@(private="file")
_set_overflow :: proc(n: ^Node, x, y: Overflow) {
    ox, oy := x, y
    if ox == .Visible && oy != .Visible do ox = .Auto
    if oy == .Visible && ox != .Visible do oy = .Auto

    s := _stored_base(n)
    s.overflow_x = ox
    s.overflow_y = oy

    n.clip_x = ox != .Visible
    n.clip_y = oy != .Visible
    n.clip_mode = .None if !n.clip_x && !n.clip_y else .Scissor

    stronger := ox if oy == .Visible else oy
    YG.NodeStyleSetOverflow(n.raw, _yoga_overflow(stronger))
}

// Convert style overflow to yoga overflow
@(private="file")
_yoga_overflow :: proc(o: Overflow) -> YG.Overflow {
    switch o {
    case .Visible: return .Visible
    case .Hidden:  return .Hidden
    case .Scroll, .Auto: return .Scroll
    }
    return .Visible
}

@(private="file")
_set_value_gutter :: proc(n: YG.NodeRef, g: YG.Gutter, v: f32, u: unit) {
    #partial switch u {
    case .Point:   YG.NodeStyleSetGap(n, g, v)
    case .Percent: YG.NodeStyleSetGapPercent(n, g, v)
    }
}

Init_Style :: proc(n: ^Node){
    if n._internal_style == nil {
        panic("node is not initialized properly.")
    }
    style := cast(^Style)n._internal_style
    style.owner = n
    style._internal_vt = &style_vtable
}

Set_Style :: proc(n: ^Node, style: ^$T) where intrinsics.type_is_subtype_of(T, Style)
{
    n._internal_style = style
}

// Computed text style: mirroring the DOM's inherited computed style.
Resolve_Text_Style :: proc(n: ^BaseNode) -> (out: Text_Style) {
    for p := n; p != nil; p = p.parent {
        if p._internal_style == nil {
            continue
        }
        t := (cast(^Style)p._internal_style).text
        if out.color == {} {
            out.color = t.color
        }
        if out.font_size <= 0 {
            out.font_size = t.font_size
        }
        if out.line_height <= 0 {
            out.line_height = t.line_height
            out.line_height_unit = t.line_height_unit
        }
        if out.font == nil do out.font = t.font
    }
    return
}
