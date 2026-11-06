package node;

import YG "src:yoga"
import "base:intrinsics"
import "base:runtime"
import "core:math"
import "src:core/common"
import css "src:core/style"
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
Wrap          :: YG.Wrap
Display       :: YG.Display
BoxSizing     :: YG.BoxSizing
Keyword       :: css.Keyword
User_Select :: enum {
    Auto,
    Text,
    None,
    All,
}
// CSS `pointer-events`. `None` makes a node transparent to hit testing without
// affecting its children, which is what lets a full-screen overlay root pass
// clicks through everywhere except over its painted content. `Inherit` takes
// the parent's resolved mode, so a subtree can opt back into it explicitly.
Pointer_Events :: enum {
    Auto,
    None,
    Inherit,
}
// CSS `overflow`, which unlike Yoga's enum has a distinct `auto`. Kept per-axis;
// see _set_overflow for how the pair collapses to Yoga's single node-wide value.
Overflow :: enum {
    Visible,
    Hidden,
    Scroll,
    Auto,
}
Position :: enum {
    Static,
    Relative,
    Absolute,
    Fixed,
    Sticky,
}
Sticky :: struct {
    set:     [4]bool,
    inset:   [4]f32,
    percent: [4]f32,
}
Font       :: text.Font_Set
FontWeight :: text.FontWeight
Text_Align :: enum {
    Inherit,
    Left,
    Center,
    Right,
}

Text_Transform  :: enum u8 { Inherit, None, Uppercase, Lowercase, Capitalize }
White_Space     :: enum u8 { Inherit, Normal, No_Wrap, Pre }
Text_Decoration :: enum u8 { Inherit, None, Underline, Line_Through }
Text_Overflow   :: enum u8 { Inherit, Clip, Ellipsis }

Text_Style :: struct {
    align:                 Text_Align,
    transform:             Text_Transform,
    white_space:           White_Space,
    decoration:            Text_Decoration,
    overflow:              Text_Overflow,
    letter_spacing:        f32,
    letter_spacing_set:    bool,
    computed:              bool,
    line_height_specified: bool,
    color:                 common.Color,
    font_size:             f32,
    line_height:           f32,
    line_height_unit:      unit,
    font:                  ^Font,
    font_weight:           FontWeight,
}

Style :: struct {
    owner:          ^Node,
    v:              map[string]any, // holder for any value (for extending)
    text:           Text_Style,
    computed_text:  bool, // CSS computed values may legitimately be zero/transparent.
    select_mode:    User_Select,
    pointer_events: Pointer_Events,
    // Not Yoga-backed: Yoga stores one node-wide overflow, CSS one per axis.
    overflow_x:     Overflow,
    overflow_y:     Overflow,
    background:     Color,
    border_color:   [4]Color, // top, right, bottom, left
    border_width:   [4]f32,
    radius:         common.Radii,
    radius_percent: common.Radii, // of the width and the height, added to radius
    decoration:     common.EffectFilterDecoration,
    transform:      common.Transform,
    sticky:         Maybe(Sticky),
    filter:         Maybe(Filter), // owns its shadows
    fixed:          bool,
    inline:         [dynamic]css.Declaration,
    inline_changed: bool,
    managed:        bool,
    // The node keeps the declarations as given: lists inside them must outlive it.
    set_inline:     proc(self: ^Style, declarations: ..css.Declaration),
    // No property clears them all.
    clear_inline:   proc(self: ^Style, properties: ..css.Property),
    // What `set_overflow` does on a node no engine manages; an engine applies its computed value with it.
    apply_overflow: proc(self: ^Style, x, y: Overflow),
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
    _clear_subsumed_edges(n, e, pt)
    #partial switch u {
    case .Point:   pt(n, e, v)
    case .Percent: pct(n, e, v)
    case .Auto:    if aut != nil do aut(n, e)
    }
}

// Yoga resolves an edge as specific → axis → .All and .All is the lowest priority fallback.
// so i need to clear it first before apply the value.
@(private="file")
_clear_subsumed_edges :: proc(n: YG.NodeRef, e: Edge, pt: YG.Style_Set_Edge_Proc) {
    all := [?]Edge{.Left, .Top, .Right, .Bottom, .Start, .End, .Horizontal, .Vertical}
    horizontal := [?]Edge{.Left, .Right, .Start, .End}
    vertical := [?]Edge{.Top, .Bottom}

    subsumed: []Edge
    #partial switch e {
    case .All:        subsumed = all[:]
    case .Horizontal: subsumed = horizontal[:]
    case .Vertical:   subsumed = vertical[:]
    case:             return
    }
    for c in subsumed do pt(n, c, NAN)
}

@(private="file")
NAN :: f32(0h7fc0_0000)

// Text properties aren't yoga-backed; they live on the node's stored Style.
// `self` is a by-value copy, so writes must go through the owner's pointer.
@(private="file")
_stored :: proc(self: ^Style) -> ^Style {
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
    if scrollable_changed != nil {
        scrollable_changed(n, ox == .Scroll || ox == .Auto, oy == .Scroll || oy == .Auto)
    }

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

@(private="file")
_style_set_inline :: proc(self: ^Style, declarations: ..css.Declaration) {
    s := _stored(self)
    for declaration in declarations do _put(s, declaration)
}

@(private="file")
_style_clear_inline :: proc(self: ^Style, properties: ..css.Property) {
    s := _stored(self)
    if len(properties) == 0 {
        s.inline_changed = s.inline_changed || len(s.inline) > 0
        clear(&s.inline)
        return
    }
    #reverse for declaration, i in s.inline {
        for property in properties {
            if declaration.property != property do continue
            ordered_remove(&s.inline, i)
            s.inline_changed = true
            break
        }
    }
}

@(private="file")
_style_apply_overflow :: proc(self: ^Style, x, y: Overflow) {
    _set_overflow(self.owner, x, y)
}

@(private="file")
_put :: proc(s: ^Style, declaration: css.Declaration) {
    s.inline_changed = true
    for &known in s.inline {
        if known.property == declaration.property {
            known = declaration
            return
        }
    }
    append(&s.inline, declaration)
}

// False on a node no style engine manages: the caller then applies the value itself.
@(private="file")
_author :: proc(self: ^Style, first: css.Property, value: css.Value, count := 1) -> bool {
    s := _stored(self)
    if !s.managed do return false
    for i in 0 ..< count do _put(s, {property = css.Property(int(first) + i), value = value})
    return true
}

@(private="file")
_author_sides :: proc(self: ^Style, top: css.Property, value: css.Value, sides: ..int) -> bool {
    for side in sides {
        if !_author(self, css.Property(int(top) + side), value) do return false
    }
    return true
}

// Yoga's undefined is how a caller unsets a size.
@(private="file")
_size :: proc(v: f32, u: unit, unset := css.Keyword.Auto) -> css.Value {
    if u == .Auto do return css.keyword(.Auto)
    if v != v do return css.keyword(unset)
    return css.length(v, .Percent if u == .Percent else .Px)
}

@(private="file")
_length :: proc(v: f32, u: unit) -> css.Value {
    return css.length(v, .Percent if u == .Percent else .Px)
}

@(private="file")
_rgba :: proc(c: Color) -> css.Value {
    return css.rgba(f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255)
}

@(private="file")
_align :: proc(a: Align) -> css.Value {
    switch a {
    case .Auto:              return css.keyword(.Auto)
    case .FlexStart, .Start: return css.keyword(.Flex_Start)
    case .Center:            return css.keyword(.Center)
    case .FlexEnd, .End:     return css.keyword(.Flex_End)
    case .Stretch:           return css.keyword(.Stretch)
    case .Baseline:          return css.keyword(.Baseline)
    case .SpaceBetween:      return css.keyword(.Space_Between)
    case .SpaceAround:       return css.keyword(.Space_Around)
    case .SpaceEvenly:       return css.keyword(.Space_Evenly)
    }
    return css.keyword(.Auto)
}

@(private="file")
_overflow :: proc(o: Overflow) -> css.Value {
    switch o {
    case .Visible: return css.keyword(.Visible)
    case .Hidden:  return css.keyword(.Hidden)
    case .Scroll:  return css.keyword(.Scroll)
    case .Auto:    return css.keyword(.Auto)
    }
    return css.keyword(.Visible)
}

@(private="file")
_author_corner :: proc(self: ^Style, corner: int, v: [2]f32) -> bool {
    if !_author(self, css.Property(int(css.Property.Border_Top_Left_Radius) + corner), css.length(v.x)) do return false
    return _author(self, css.Property(int(css.Property.Border_Top_Left_Radius_Y) + corner), css.keyword(.Auto) if v.y == v.x else css.length(v.y))
}

@(private="file")
_pair :: proc(v: YG.Value) -> (f32, unit) {
    return v.value, v.unit
}

@(private="file")
_SIDES :: [4]Edge{.Top, .Right, .Bottom, .Left}

@(private="file")
_margin :: proc(self: ^Style, e: Edge, v: f32, u: unit) {
    _set_edge(self.owner.raw, e, v, u, YG.NodeStyleSetMargin, YG.NodeStyleSetMarginPercent, YG.NodeStyleSetMarginAuto)
}

@(private="file")
_padding :: proc(self: ^Style, e: Edge, v: f32, u: unit) {
    _set_edge(self.owner.raw, e, v, u, YG.NodeStyleSetPadding, YG.NodeStyleSetPaddingPercent)
}

// A sticky node keeps its insets off Yoga, which would offset it by them.
@(private="file")
_inset :: proc(self: ^Style, e: Edge, v: f32, u: unit) {
    s := _stored(self)
    sticky, on := s.sticky.?
    if !on {
        _set_edge(self.owner.raw, e, v, u, YG.NodeStyleSetPosition, YG.NodeStyleSetPositionPercent, YG.NodeStyleSetPositionAuto)
        return
    }
    for i in 0 ..< 4 {
        if !_covers(e, i) do continue
        sticky.set[i] = u != .Auto && v == v
        sticky.inset[i] = v if sticky.set[i] && u != .Percent else 0
        sticky.percent[i] = v if sticky.set[i] && u == .Percent else 0
    }
    _set_sticky(s, sticky)
}

@(private="file")
_covers :: proc(e: Edge, side: int) -> bool {
    #partial switch e {
    case .Top:           return side == 0
    case .Right, .End:   return side == 1
    case .Bottom:        return side == 2
    case .Left, .Start:  return side == 3
    case .Vertical:      return side % 2 == 0
    case .Horizontal:    return side % 2 == 1
    case .All:           return true
    }
    return false
}

@(private="file")
_get_inset :: proc(self: ^Style, side: int) -> (f32, unit) {
    sides := _SIDES
    sticky, on := _stored(self).sticky.?
    if !on do return _pair(YG.NodeStyleGetPosition(self.owner.raw, sides[side]))
    if !sticky.set[side] do return 0, auto
    if sticky.percent[side] != 0 do return sticky.percent[side], percent
    return sticky.inset[side], px
}

// Yoga has no fixed or sticky: a fixed node is absolute to it and a sticky one relative.
@(private="file")
_set_position :: proc(self: ^Style, v: Position) {
    s := _stored(self)
    raw := self.owner.raw
    sides := _SIDES
    was, stuck := s.sticky.?
    if stuck && v != .Sticky {
        _set_sticky(s, nil)
        for side, i in sides {
            if !was.set[i] do continue
            if was.percent[i] != 0 {
                YG.NodeStyleSetPositionPercent(raw, side, was.percent[i])
            } else {
                YG.NodeStyleSetPosition(raw, side, was.inset[i])
            }
        }
    }
    if !stuck && v == .Sticky {
        now: Sticky
        for side, i in sides {
            inset := YG.NodeStyleGetPosition(raw, side)
            #partial switch inset.unit {
            case .Point:   now.set[i], now.inset[i] = true, inset.value
            case .Percent: now.set[i], now.percent[i] = true, inset.value
            }
            YG.NodeStyleSetPositionAuto(raw, side)
        }
        _set_sticky(s, now)
    }
    s.fixed = v == .Fixed
    YG.NodeStyleSetPositionType(raw, .Static if v == .Static else (.Absolute if v == .Absolute || v == .Fixed else .Relative))
}

@(private="file")
_border_width :: proc(self: ^Style, v: f32, sides: ..int) {
    s := _stored(self)
    edges := _SIDES
    for side in sides {
        s.border_width[side] = v
        YG.NodeStyleSetBorder(self.owner.raw, edges[side], v)
    }
}

@(private="file")
_text_align :: proc(k: Keyword) -> Text_Align {
    #partial switch k {
    case .Left, .Start: return .Left
    case .Center:       return .Center
    case .Right, .End:  return .Right
    }
    return .Inherit
}

@(private="file")
_text_transform :: proc(k: Keyword) -> Text_Transform {
    #partial switch k {
    case .None:       return .None
    case .Uppercase:  return .Uppercase
    case .Lowercase:  return .Lowercase
    case .Capitalize: return .Capitalize
    }
    return .Inherit
}

@(private="file")
_white_space :: proc(k: Keyword) -> White_Space {
    #partial switch k {
    case .Normal:  return .Normal
    case .No_Wrap: return .No_Wrap
    case .Pre:     return .Pre
    }
    return .Inherit
}

@(private="file")
_text_decoration :: proc(k: Keyword) -> Text_Decoration {
    #partial switch k {
    case .None:         return .None
    case .Underline:    return .Underline
    case .Line_Through: return .Line_Through
    }
    return .Inherit
}

// A setter authors inline style on a managed node and applies its value at once
// on any other. Without an engine a few properties have nothing to apply to:
// visibility, cursor, opacity, justify-items/-self, border and outline style,
// the scrollbar properties and grid lines.
@(private="file")
style_vtable := Style_VTable{
    get_z_index         = proc(self: ^Style) -> i32 { return self.owner.z_index },
    get_direction       = proc(self: ^Style) -> Direction { return YG.NodeStyleGetDirection(self.owner.raw) },
    get_flex_direction  = proc(self: ^Style) -> FlexDirection { return YG.NodeStyleGetFlexDirection(self.owner.raw) },
    get_justify_content = proc(self: ^Style) -> Justify { return YG.NodeStyleGetJustifyContent(self.owner.raw) },
    get_align_content   = proc(self: ^Style) -> Align { return YG.NodeStyleGetAlignContent(self.owner.raw) },
    get_align_items     = proc(self: ^Style) -> Align { return YG.NodeStyleGetAlignItems(self.owner.raw) },
    get_align_self      = proc(self: ^Style) -> Align { return YG.NodeStyleGetAlignSelf(self.owner.raw) },
    get_justify_items   = proc(self: ^Style) -> Align { return .Auto },
    get_justify_self    = proc(self: ^Style) -> Align { return .Auto },
    get_position = proc(self: ^Style) -> Position {
        s := _stored(self)
        if s.fixed do return .Fixed
        if s.sticky != nil do return .Sticky
        #partial switch YG.NodeStyleGetPositionType(self.owner.raw) {
        case .Static:   return .Static
        case .Absolute: return .Absolute
        }
        return .Relative
    },
    get_flex_wrap      = proc(self: ^Style) -> Wrap { return YG.NodeStyleGetFlexWrap(self.owner.raw) },
    get_display        = proc(self: ^Style) -> Display { return YG.NodeStyleGetDisplay(self.owner.raw) },
    get_user_select    = proc(self: ^Style) -> User_Select { return Resolve_User_Select(self.owner) },
    get_pointer_events = proc(self: ^Style) -> Pointer_Events { return Resolve_Pointer_Events(self.owner) },
    get_visibility     = proc(self: ^Style) -> Keyword { return .Visible },
    // `overflow` reads back the x axis, mirroring how CSS shorthands resolve.
    get_overflow     = proc(self: ^Style) -> Overflow { return _stored(self).overflow_x },
    get_overflow_x   = proc(self: ^Style) -> Overflow { return _stored(self).overflow_x },
    get_overflow_y   = proc(self: ^Style) -> Overflow { return _stored(self).overflow_y },
    get_box_sizing   = proc(self: ^Style) -> BoxSizing { return YG.NodeStyleGetBoxSizing(self.owner.raw) },
    get_cursor       = proc(self: ^Style) -> Keyword { return .Auto },
    get_opacity      = proc(self: ^Style) -> f32 { return 1 },
    get_flex         = proc(self: ^Style) -> f32 { return YG.NodeStyleGetFlex(self.owner.raw) },
    get_flex_grow    = proc(self: ^Style) -> f32 { return YG.NodeStyleGetFlexGrow(self.owner.raw) },
    get_flex_shrink  = proc(self: ^Style) -> f32 { return YG.NodeStyleGetFlexShrink(self.owner.raw) },
    get_aspect_ratio = proc(self: ^Style) -> f32 { return YG.NodeStyleGetAspectRatio(self.owner.raw) },

    get_width      = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetWidth(self.owner.raw)) },
    get_height     = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetHeight(self.owner.raw)) },
    get_min_width  = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMinWidth(self.owner.raw)) },
    get_min_height = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMinHeight(self.owner.raw)) },
    get_max_width  = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMaxWidth(self.owner.raw)) },
    get_max_height = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMaxHeight(self.owner.raw)) },
    get_flex_basis = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetFlexBasis(self.owner.raw)) },

    get_margin_top          = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMargin(self.owner.raw, .Top)) },
    get_margin_right        = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMargin(self.owner.raw, .Right)) },
    get_margin_bottom       = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMargin(self.owner.raw, .Bottom)) },
    get_margin_left         = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMargin(self.owner.raw, .Left)) },
    get_margin_inline_start = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMargin(self.owner.raw, .Start)) },
    get_margin_inline_end   = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMargin(self.owner.raw, .End)) },
    get_margin_inline       = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMargin(self.owner.raw, .Horizontal)) },
    get_margin_block        = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMargin(self.owner.raw, .Vertical)) },
    get_margin              = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetMargin(self.owner.raw, .All)) },

    get_padding_top          = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPadding(self.owner.raw, .Top)) },
    get_padding_right        = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPadding(self.owner.raw, .Right)) },
    get_padding_bottom       = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPadding(self.owner.raw, .Bottom)) },
    get_padding_left         = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPadding(self.owner.raw, .Left)) },
    get_padding_inline_start = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPadding(self.owner.raw, .Start)) },
    get_padding_inline_end   = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPadding(self.owner.raw, .End)) },
    get_padding_inline       = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPadding(self.owner.raw, .Horizontal)) },
    get_padding_block        = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPadding(self.owner.raw, .Vertical)) },
    get_padding              = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPadding(self.owner.raw, .All)) },

    get_top                = proc(self: ^Style) -> (f32, unit) { return _get_inset(self, 0) },
    get_right              = proc(self: ^Style) -> (f32, unit) { return _get_inset(self, 1) },
    get_bottom             = proc(self: ^Style) -> (f32, unit) { return _get_inset(self, 2) },
    get_left               = proc(self: ^Style) -> (f32, unit) { return _get_inset(self, 3) },
    get_inset_inline_start = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPosition(self.owner.raw, .Start)) },
    get_inset_inline_end   = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPosition(self.owner.raw, .End)) },
    get_inset_inline       = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPosition(self.owner.raw, .Horizontal)) },
    get_inset_block        = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPosition(self.owner.raw, .Vertical)) },
    get_inset              = proc(self: ^Style) -> (f32, unit) { return _pair(YG.NodeStyleGetPosition(self.owner.raw, .All)) },

    get_border_top_width          = proc(self: ^Style) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Top) },
    get_border_right_width        = proc(self: ^Style) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Right) },
    get_border_bottom_width       = proc(self: ^Style) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Bottom) },
    get_border_left_width         = proc(self: ^Style) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Left) },
    get_border_inline_start_width = proc(self: ^Style) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Left) },
    get_border_inline_end_width   = proc(self: ^Style) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Right) },
    get_border_inline_width       = proc(self: ^Style) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Left) },
    get_border_block_width        = proc(self: ^Style) -> f32 { return YG.NodeStyleGetBorder(self.owner.raw, .Top) },
    get_border_width              = proc(self: ^Style) -> f32 { return _stored(self).border_width[0] },

    get_border_top_style    = proc(self: ^Style) -> Keyword { return .Solid if _stored(self).border_width[0] > 0 else .None },
    get_border_right_style  = proc(self: ^Style) -> Keyword { return .Solid if _stored(self).border_width[1] > 0 else .None },
    get_border_bottom_style = proc(self: ^Style) -> Keyword { return .Solid if _stored(self).border_width[2] > 0 else .None },
    get_border_left_style   = proc(self: ^Style) -> Keyword { return .Solid if _stored(self).border_width[3] > 0 else .None },
    get_border_style        = proc(self: ^Style) -> Keyword { return .Solid if _stored(self).border_width[0] > 0 else .None },

    get_border_top_color    = proc(self: ^Style) -> Color { return _stored(self).border_color[0] },
    get_border_right_color  = proc(self: ^Style) -> Color { return _stored(self).border_color[1] },
    get_border_bottom_color = proc(self: ^Style) -> Color { return _stored(self).border_color[2] },
    get_border_left_color   = proc(self: ^Style) -> Color { return _stored(self).border_color[3] },
    get_border_color        = proc(self: ^Style) -> Color { return _stored(self).border_color[0] },

    get_border_top_left_radius     = proc(self: ^Style) -> [2]f32 { return _stored(self).radius[0] },
    get_border_top_right_radius    = proc(self: ^Style) -> [2]f32 { return _stored(self).radius[1] },
    get_border_bottom_right_radius = proc(self: ^Style) -> [2]f32 { return _stored(self).radius[2] },
    get_border_bottom_left_radius  = proc(self: ^Style) -> [2]f32 { return _stored(self).radius[3] },
    get_border_radius              = proc(self: ^Style) -> Radii { return _stored(self).radius },

    get_row_gap    = proc(self: ^Style) -> (f32, unit) { return YG.NodeStyleGetGap(self.owner.raw, .Row), px },
    get_column_gap = proc(self: ^Style) -> (f32, unit) { return YG.NodeStyleGetGap(self.owner.raw, .Column), px },
    get_gap        = proc(self: ^Style) -> (f32, unit) { return YG.NodeStyleGetGap(self.owner.raw, .All), px },

    get_color            = proc(self: ^Style) -> Color { return Resolve_Text_Style(self.owner).color },
    get_background_color = proc(self: ^Style) -> Color { return _stored(self).background },
    get_font_size        = proc(self: ^Style) -> f32 { return Resolve_Text_Style(self.owner).font_size },
    get_line_height      = proc(self: ^Style) -> (f32, unit) { st := Resolve_Text_Style(self.owner); return st.line_height, st.line_height_unit },
    get_font             = proc(self: ^Style) -> ^Font { return Resolve_Text_Style(self.owner).font },
    get_font_weight      = proc(self: ^Style) -> FontWeight { return Resolve_Text_Style(self.owner).font_weight },

    get_text_align = proc(self: ^Style) -> Keyword {
        #partial switch Resolve_Text_Style(self.owner).align {
        case .Center: return .Center
        case .Right:  return .Right
        }
        return .Left
    },
    get_text_transform = proc(self: ^Style) -> Keyword {
        #partial switch Resolve_Text_Style(self.owner).transform {
        case .Uppercase:  return .Uppercase
        case .Lowercase:  return .Lowercase
        case .Capitalize: return .Capitalize
        }
        return .None
    },
    get_white_space = proc(self: ^Style) -> Keyword {
        #partial switch Resolve_Text_Style(self.owner).white_space {
        case .No_Wrap: return .No_Wrap
        case .Pre:     return .Pre
        }
        return .Normal
    },
    get_text_decoration_line = proc(self: ^Style) -> Keyword {
        #partial switch Resolve_Text_Style(self.owner).decoration {
        case .Underline:    return .Underline
        case .Line_Through: return .Line_Through
        }
        return .None
    },
    get_text_overflow  = proc(self: ^Style) -> Keyword { return .Ellipsis if Resolve_Text_Style(self.owner).overflow == .Ellipsis else .Clip },
    get_letter_spacing = proc(self: ^Style) -> f32 { return Resolve_Text_Style(self.owner).letter_spacing },

    get_translate_x        = proc(self: ^Style) -> (f32, unit) { return _stored(self).transform.translate.x, px },
    get_translate_y        = proc(self: ^Style) -> (f32, unit) { return _stored(self).transform.translate.y, px },
    get_rotate             = proc(self: ^Style) -> f32 { return math.to_degrees(_stored(self).transform.rotate) },
    get_scale_x            = proc(self: ^Style) -> f32 { return _stored(self).transform.scale.x },
    get_scale_y            = proc(self: ^Style) -> f32 { return _stored(self).transform.scale.y },
    get_transform_origin_x = proc(self: ^Style) -> (f32, unit) { return _stored(self).transform.origin.x, px },
    get_transform_origin_y = proc(self: ^Style) -> (f32, unit) { return _stored(self).transform.origin.y, px },

    get_outline_width  = proc(self: ^Style) -> f32 { return _stored(self).decoration.outline_width },
    get_outline_style  = proc(self: ^Style) -> Keyword { return .Solid if _stored(self).decoration.outline_width > 0 else .None },
    get_outline_color  = proc(self: ^Style) -> Color { return _stored(self).decoration.outline_color },
    get_outline_offset = proc(self: ^Style) -> f32 { return _stored(self).decoration.outline_offset },

    get_scrollbar_width       = proc(self: ^Style) -> Keyword { return .Auto },
    get_scrollbar_thumb_color = proc(self: ^Style) -> Color { return {} },
    get_scrollbar_track_color = proc(self: ^Style) -> Color { return {} },
    get_grid_column_start     = proc(self: ^Style) -> i32 { return 0 },
    get_grid_column_end       = proc(self: ^Style) -> i32 { return 0 },
    get_grid_row_start        = proc(self: ^Style) -> i32 { return 0 },
    get_grid_row_end          = proc(self: ^Style) -> i32 { return 0 },

    get_sticky        = proc(self: ^Style) -> Maybe(Sticky) { return _stored(self).sticky },
    get_filter        = proc(self: ^Style) -> Maybe(Filter) { return _stored(self).filter },
    get_corner_radius = proc(self: ^Style) -> Radii { return self.owner.corner_radius },

    set_z_index = proc(self: ^Style, v: i32) -> ^Style {
        if !_author(self, .Z_Index, css.number(f32(v))) do self.owner.z_index = v
        return self
    },
    set_direction = proc(self: ^Style, v: Direction) -> ^Style {
        k := css.Keyword.Inherit if v == .Inherit else (.Rtl if v == .RTL else .Ltr)
        if !_author(self, .Direction, css.keyword(k)) do YG.NodeStyleSetDirection(self.owner.raw, v)
        return self
    },
    set_flex_direction = proc(self: ^Style, v: FlexDirection) -> ^Style {
        ks := [FlexDirection]css.Keyword{.Column = .Column, .ColumnReverse = .Column_Reverse, .Row = .Row, .RowReverse = .Row_Reverse}
        if !_author(self, .Flex_Direction, css.keyword(ks[v])) do YG.NodeStyleSetFlexDirection(self.owner.raw, v)
        return self
    },
    set_justify_content = proc(self: ^Style, v: Justify) -> ^Style {
        ks := [Justify]css.Keyword{.FlexStart = .Flex_Start, .Center = .Center, .FlexEnd = .Flex_End, .SpaceBetween = .Space_Between, .SpaceAround = .Space_Around, .SpaceEvenly = .Space_Evenly}
        if !_author(self, .Justify_Content, css.keyword(ks[v])) do YG.NodeStyleSetJustifyContent(self.owner.raw, v)
        return self
    },
    set_align_content = proc(self: ^Style, v: Align) -> ^Style { if !_author(self, .Align_Content, _align(v)) do YG.NodeStyleSetAlignContent(self.owner.raw, v); return self },
    set_align_items   = proc(self: ^Style, v: Align) -> ^Style { if !_author(self, .Align_Items, _align(v)) do YG.NodeStyleSetAlignItems(self.owner.raw, v); return self },
    set_align_self    = proc(self: ^Style, v: Align) -> ^Style { if !_author(self, .Align_Self, _align(v)) do YG.NodeStyleSetAlignSelf(self.owner.raw, v); return self },
    set_justify_items = proc(self: ^Style, v: Align) -> ^Style { _author(self, .Justify_Items, _align(v)); return self },
    set_justify_self  = proc(self: ^Style, v: Align) -> ^Style { _author(self, .Justify_Self, _align(v)); return self },
    set_position = proc(self: ^Style, v: Position) -> ^Style {
        ks := [Position]css.Keyword{.Static = .Relative, .Relative = .Relative, .Absolute = .Absolute, .Fixed = .Fixed, .Sticky = .Sticky}
        if !_author(self, .Position, css.keyword(ks[v])) do _set_position(self, v)
        return self
    },
    set_flex_wrap = proc(self: ^Style, v: Wrap) -> ^Style {
        ks := [Wrap]css.Keyword{.NoWrap = .No_Wrap, .Wrap = .Wrap, .WrapReverse = .Wrap_Reverse}
        if !_author(self, .Flex_Wrap, css.keyword(ks[v])) do YG.NodeStyleSetFlexWrap(self.owner.raw, v)
        return self
    },
    set_display = proc(self: ^Style, v: Display) -> ^Style {
        ks := [Display]css.Keyword{.Flex = .Flex, .None = .None, .Contents = .Contents, .Grid = .Grid}
        if !_author(self, .Display, css.keyword(ks[v])) do YG.NodeStyleSetDisplay(self.owner.raw, v)
        return self
    },
    set_user_select = proc(self: ^Style, v: User_Select) -> ^Style {
        ks := [User_Select]css.Keyword{.Auto = .Auto, .Text = .Text, .None = .None, .All = .All}
        if !_author(self, .User_Select, css.keyword(ks[v])) do _stored(self).select_mode = v
        return self
    },
    set_pointer_events = proc(self: ^Style, v: Pointer_Events) -> ^Style {
        ks := [Pointer_Events]css.Keyword{.Auto = .Auto, .None = .None, .Inherit = .Inherit}
        if !_author(self, .Pointer_Events, css.keyword(ks[v])) do _stored(self).pointer_events = v
        return self
    },
    set_visibility = proc(self: ^Style, v: Keyword) -> ^Style { _author(self, .Visibility, css.keyword(v)); return self },
    set_overflow   = proc(self: ^Style, v: Overflow) -> ^Style { if !_author(self, .Overflow_X, _overflow(v), 2) do _set_overflow(self.owner, v, v); return self },
    set_overflow_x = proc(self: ^Style, v: Overflow) -> ^Style { if !_author(self, .Overflow_X, _overflow(v)) do _set_overflow(self.owner, v, _stored(self).overflow_y); return self },
    set_overflow_y = proc(self: ^Style, v: Overflow) -> ^Style { if !_author(self, .Overflow_Y, _overflow(v)) do _set_overflow(self.owner, _stored(self).overflow_x, v); return self },
    set_box_sizing = proc(self: ^Style, v: BoxSizing) -> ^Style {
        if !_author(self, .Box_Sizing, css.keyword(.Border_Box if v == .BorderBox else .Content_Box)) do YG.NodeStyleSetBoxSizing(self.owner.raw, v)
        return self
    },
    set_cursor  = proc(self: ^Style, v: Keyword) -> ^Style { _author(self, .Cursor, css.keyword(v)); return self },
    set_opacity = proc(self: ^Style, v: f32) -> ^Style { _author(self, .Opacity, css.number(v)); return self },
    set_flex = proc(self: ^Style, v: f32) -> ^Style {
        if !_author(self, .Flex_Grow, css.number(v)) {
            YG.NodeStyleSetFlex(self.owner.raw, v)
            return self
        }
        _author(self, .Flex_Shrink, css.number(1))
        _author(self, .Flex_Basis, css.length(0))
        return self
    },
    set_flex_grow   = proc(self: ^Style, v: f32) -> ^Style { if !_author(self, .Flex_Grow, css.number(v)) do YG.NodeStyleSetFlexGrow(self.owner.raw, v); return self },
    set_flex_shrink = proc(self: ^Style, v: f32) -> ^Style { if !_author(self, .Flex_Shrink, css.number(v)) do YG.NodeStyleSetFlexShrink(self.owner.raw, v); return self },
    set_aspect_ratio = proc(self: ^Style, v: f32) -> ^Style {
        if !_author(self, .Aspect_Ratio, css.keyword(.Auto) if v != v else css.number(v)) do YG.NodeStyleSetAspectRatio(self.owner.raw, v)
        return self
    },

    set_width      = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Width, _size(v, u)) do _set_value(self.owner.raw, v, u, YG.NodeStyleSetWidth, YG.NodeStyleSetWidthPercent, YG.NodeStyleSetWidthAuto); return self },
    set_height     = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Height, _size(v, u)) do _set_value(self.owner.raw, v, u, YG.NodeStyleSetHeight, YG.NodeStyleSetHeightPercent, YG.NodeStyleSetHeightAuto); return self },
    set_min_width  = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Min_Width, _size(v, u)) do _set_value(self.owner.raw, v, u, YG.NodeStyleSetMinWidth, YG.NodeStyleSetMinWidthPercent); return self },
    set_min_height = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Min_Height, _size(v, u)) do _set_value(self.owner.raw, v, u, YG.NodeStyleSetMinHeight, YG.NodeStyleSetMinHeightPercent); return self },
    set_max_width  = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Max_Width, _size(v, u, .None)) do _set_value(self.owner.raw, v, u, YG.NodeStyleSetMaxWidth, YG.NodeStyleSetMaxWidthPercent); return self },
    set_max_height = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Max_Height, _size(v, u, .None)) do _set_value(self.owner.raw, v, u, YG.NodeStyleSetMaxHeight, YG.NodeStyleSetMaxHeightPercent); return self },
    set_flex_basis = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Flex_Basis, _size(v, u)) do _set_value(self.owner.raw, v, u, YG.NodeStyleSetFlexBasis, YG.NodeStyleSetFlexBasisPercent, YG.NodeStyleSetFlexBasisAuto); return self },

    set_margin_top          = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Margin_Top, _size(v, u)) do _margin(self, .Top, v, u); return self },
    set_margin_right        = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Margin_Right, _size(v, u)) do _margin(self, .Right, v, u); return self },
    set_margin_bottom       = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Margin_Bottom, _size(v, u)) do _margin(self, .Bottom, v, u); return self },
    set_margin_left         = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Margin_Left, _size(v, u)) do _margin(self, .Left, v, u); return self },
    set_margin_inline_start = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Margin_Left, _size(v, u)) do _margin(self, .Start, v, u); return self },
    set_margin_inline_end   = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Margin_Right, _size(v, u)) do _margin(self, .End, v, u); return self },
    set_margin_inline       = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author_sides(self, .Margin_Top, _size(v, u), 1, 3) do _margin(self, .Horizontal, v, u); return self },
    set_margin_block        = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author_sides(self, .Margin_Top, _size(v, u), 0, 2) do _margin(self, .Vertical, v, u); return self },
    set_margin              = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Margin_Top, _size(v, u), 4) do _margin(self, .All, v, u); return self },

    set_padding_top          = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Padding_Top, _length(v, u)) do _padding(self, .Top, v, u); return self },
    set_padding_right        = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Padding_Right, _length(v, u)) do _padding(self, .Right, v, u); return self },
    set_padding_bottom       = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Padding_Bottom, _length(v, u)) do _padding(self, .Bottom, v, u); return self },
    set_padding_left         = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Padding_Left, _length(v, u)) do _padding(self, .Left, v, u); return self },
    set_padding_inline_start = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Padding_Left, _length(v, u)) do _padding(self, .Start, v, u); return self },
    set_padding_inline_end   = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Padding_Right, _length(v, u)) do _padding(self, .End, v, u); return self },
    set_padding_inline       = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author_sides(self, .Padding_Top, _length(v, u), 1, 3) do _padding(self, .Horizontal, v, u); return self },
    set_padding_block        = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author_sides(self, .Padding_Top, _length(v, u), 0, 2) do _padding(self, .Vertical, v, u); return self },
    set_padding              = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Padding_Top, _length(v, u), 4) do _padding(self, .All, v, u); return self },

    set_top                = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Top, _size(v, u)) do _inset(self, .Top, v, u); return self },
    set_right              = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Right, _size(v, u)) do _inset(self, .Right, v, u); return self },
    set_bottom             = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Bottom, _size(v, u)) do _inset(self, .Bottom, v, u); return self },
    set_left               = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Left, _size(v, u)) do _inset(self, .Left, v, u); return self },
    set_inset_inline_start = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Left, _size(v, u)) do _inset(self, .Start, v, u); return self },
    set_inset_inline_end   = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Right, _size(v, u)) do _inset(self, .End, v, u); return self },
    set_inset_inline       = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author_sides(self, .Top, _size(v, u), 1, 3) do _inset(self, .Horizontal, v, u); return self },
    set_inset_block        = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author_sides(self, .Top, _size(v, u), 0, 2) do _inset(self, .Vertical, v, u); return self },
    set_inset              = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Top, _size(v, u), 4) do _inset(self, .All, v, u); return self },

    set_border_top_width          = proc(self: ^Style, v: f32) -> ^Style { if !_author_sides(self, .Border_Top_Width, css.length(v), 0) do _border_width(self, v, 0); return self },
    set_border_right_width        = proc(self: ^Style, v: f32) -> ^Style { if !_author_sides(self, .Border_Top_Width, css.length(v), 1) do _border_width(self, v, 1); return self },
    set_border_bottom_width       = proc(self: ^Style, v: f32) -> ^Style { if !_author_sides(self, .Border_Top_Width, css.length(v), 2) do _border_width(self, v, 2); return self },
    set_border_left_width         = proc(self: ^Style, v: f32) -> ^Style { if !_author_sides(self, .Border_Top_Width, css.length(v), 3) do _border_width(self, v, 3); return self },
    set_border_inline_start_width = proc(self: ^Style, v: f32) -> ^Style { if !_author_sides(self, .Border_Top_Width, css.length(v), 3) do _border_width(self, v, 3); return self },
    set_border_inline_end_width   = proc(self: ^Style, v: f32) -> ^Style { if !_author_sides(self, .Border_Top_Width, css.length(v), 1) do _border_width(self, v, 1); return self },
    set_border_inline_width       = proc(self: ^Style, v: f32) -> ^Style { if !_author_sides(self, .Border_Top_Width, css.length(v), 1, 3) do _border_width(self, v, 1, 3); return self },
    set_border_block_width        = proc(self: ^Style, v: f32) -> ^Style { if !_author_sides(self, .Border_Top_Width, css.length(v), 0, 2) do _border_width(self, v, 0, 2); return self },
    set_border_width              = proc(self: ^Style, v: f32) -> ^Style { if !_author(self, .Border_Top_Width, css.length(v), 4) do _border_width(self, v, 0, 1, 2, 3); return self },

    set_border_top_style    = proc(self: ^Style, v: Keyword) -> ^Style { _author(self, .Border_Top_Style, css.keyword(v)); return self },
    set_border_right_style  = proc(self: ^Style, v: Keyword) -> ^Style { _author(self, .Border_Right_Style, css.keyword(v)); return self },
    set_border_bottom_style = proc(self: ^Style, v: Keyword) -> ^Style { _author(self, .Border_Bottom_Style, css.keyword(v)); return self },
    set_border_left_style   = proc(self: ^Style, v: Keyword) -> ^Style { _author(self, .Border_Left_Style, css.keyword(v)); return self },
    set_border_style        = proc(self: ^Style, v: Keyword) -> ^Style { _author(self, .Border_Top_Style, css.keyword(v), 4); return self },

    set_border_top_color    = proc(self: ^Style, v: Color) -> ^Style { if !_author(self, .Border_Top_Color, _rgba(v)) do _stored(self).border_color[0] = v; return self },
    set_border_right_color  = proc(self: ^Style, v: Color) -> ^Style { if !_author(self, .Border_Right_Color, _rgba(v)) do _stored(self).border_color[1] = v; return self },
    set_border_bottom_color = proc(self: ^Style, v: Color) -> ^Style { if !_author(self, .Border_Bottom_Color, _rgba(v)) do _stored(self).border_color[2] = v; return self },
    set_border_left_color   = proc(self: ^Style, v: Color) -> ^Style { if !_author(self, .Border_Left_Color, _rgba(v)) do _stored(self).border_color[3] = v; return self },
    set_border_color        = proc(self: ^Style, v: Color) -> ^Style { if !_author(self, .Border_Top_Color, _rgba(v), 4) do _stored(self).border_color = v; return self },

    set_border_top_left_radius     = proc(self: ^Style, v: [2]f32) -> ^Style { if !_author_corner(self, 0, v) { s := _stored(self); s.radius[0], s.radius_percent[0] = v, 0 }; return self },
    set_border_top_right_radius    = proc(self: ^Style, v: [2]f32) -> ^Style { if !_author_corner(self, 1, v) { s := _stored(self); s.radius[1], s.radius_percent[1] = v, 0 }; return self },
    set_border_bottom_right_radius = proc(self: ^Style, v: [2]f32) -> ^Style { if !_author_corner(self, 2, v) { s := _stored(self); s.radius[2], s.radius_percent[2] = v, 0 }; return self },
    set_border_bottom_left_radius  = proc(self: ^Style, v: [2]f32) -> ^Style { if !_author_corner(self, 3, v) { s := _stored(self); s.radius[3], s.radius_percent[3] = v, 0 }; return self },
    set_border_radius = proc(self: ^Style, v: Radii) -> ^Style {
        s := _stored(self)
        if !s.managed {
            s.radius, s.radius_percent = v, 0
            return self
        }
        for corner, i in v do _author_corner(self, i, corner)
        return self
    },

    set_row_gap    = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Row_Gap, _length(v, u)) do _set_value_gutter(self.owner.raw, .Row, v, u); return self },
    set_column_gap = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Column_Gap, _length(v, u)) do _set_value_gutter(self.owner.raw, .Column, v, u); return self },
    set_gap        = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Row_Gap, _length(v, u), 2) do _set_value_gutter(self.owner.raw, .All, v, u); return self },

    set_color            = proc(self: ^Style, v: Color) -> ^Style { if !_author(self, .Color, _rgba(v)) do _stored(self).text.color = v; return self },
    set_background_color = proc(self: ^Style, v: Color) -> ^Style { if !_author(self, .Background_Color, _rgba(v)) do _stored(self).background = v; return self },
    set_font_size        = proc(self: ^Style, v: f32) -> ^Style { if !_author(self, .Font_Size, css.length(v)) do _stored(self).text.font_size = v; return self },
    set_line_height = proc(self: ^Style, v: f32, u := px) -> ^Style {
        value := css.number(v) if u == .Percent else (css.keyword(.Normal) if u == .Auto || v <= 0 else css.length(v))
        if !_author(self, .Line_Height, value) {
            s := _stored(self)
            s.text.line_height, s.text.line_height_unit = v, u
        }
        return self
    },
    set_font        = proc(self: ^Style, v: ^Font) -> ^Style { _stored(self).text.font = v; return self },
    set_font_weight = proc(self: ^Style, v: FontWeight) -> ^Style { if !_author(self, .Font_Weight, css.number(f32(v))) do _stored(self).text.font_weight = v; return self },

    set_text_align           = proc(self: ^Style, v: Keyword) -> ^Style { if !_author(self, .Text_Align, css.keyword(v)) do _stored(self).text.align = _text_align(v); return self },
    set_text_transform       = proc(self: ^Style, v: Keyword) -> ^Style { if !_author(self, .Text_Transform, css.keyword(v)) do _stored(self).text.transform = _text_transform(v); return self },
    set_white_space          = proc(self: ^Style, v: Keyword) -> ^Style { if !_author(self, .White_Space, css.keyword(v)) do _stored(self).text.white_space = _white_space(v); return self },
    set_text_decoration_line = proc(self: ^Style, v: Keyword) -> ^Style { if !_author(self, .Text_Decoration_Line, css.keyword(v)) do _stored(self).text.decoration = _text_decoration(v); return self },
    set_text_overflow        = proc(self: ^Style, v: Keyword) -> ^Style { if !_author(self, .Text_Overflow, css.keyword(v)) do _stored(self).text.overflow = .Ellipsis if v == .Ellipsis else .Clip; return self },
    set_letter_spacing = proc(self: ^Style, v: f32) -> ^Style {
        if !_author(self, .Letter_Spacing, css.length(v)) {
            s := _stored(self)
            s.text.letter_spacing, s.text.letter_spacing_set = v, true
        }
        return self
    },

    set_translate_x        = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Translate_X, _length(v, u)) do _stored(self).transform.translate.x = v; return self },
    set_translate_y        = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Translate_Y, _length(v, u)) do _stored(self).transform.translate.y = v; return self },
    set_rotate             = proc(self: ^Style, v: f32) -> ^Style { if !_author(self, .Rotate, css.number(v)) do _stored(self).transform.rotate = math.to_radians(v); return self },
    set_scale_x            = proc(self: ^Style, v: f32) -> ^Style { if !_author(self, .Scale_X, css.number(v)) do _stored(self).transform.scale.x = v; return self },
    set_scale_y            = proc(self: ^Style, v: f32) -> ^Style { if !_author(self, .Scale_Y, css.number(v)) do _stored(self).transform.scale.y = v; return self },
    set_transform_origin_x = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Transform_Origin_X, _length(v, u)) do _stored(self).transform.origin.x = v; return self },
    set_transform_origin_y = proc(self: ^Style, v: f32, u := px) -> ^Style { if !_author(self, .Transform_Origin_Y, _length(v, u)) do _stored(self).transform.origin.y = v; return self },

    set_outline_width  = proc(self: ^Style, v: f32) -> ^Style { if !_author(self, .Outline_Width, css.length(v)) do _stored(self).decoration.outline_width = v; return self },
    set_outline_style  = proc(self: ^Style, v: Keyword) -> ^Style { _author(self, .Outline_Style, css.keyword(v)); return self },
    set_outline_color  = proc(self: ^Style, v: Color) -> ^Style { if !_author(self, .Outline_Color, _rgba(v)) do _stored(self).decoration.outline_color = v; return self },
    set_outline_offset = proc(self: ^Style, v: f32) -> ^Style { if !_author(self, .Outline_Offset, css.length(v)) do _stored(self).decoration.outline_offset = v; return self },

    set_scrollbar_width       = proc(self: ^Style, v: Keyword) -> ^Style { _author(self, .Scrollbar_Width, css.keyword(v)); return self },
    set_scrollbar_thumb_color = proc(self: ^Style, v: Color) -> ^Style { _author(self, .Scrollbar_Thumb_Color, _rgba(v)); return self },
    set_scrollbar_track_color = proc(self: ^Style, v: Color) -> ^Style { _author(self, .Scrollbar_Track_Color, _rgba(v)); return self },
    set_grid_column_start     = proc(self: ^Style, v: i32) -> ^Style { _author(self, .Grid_Column_Start, css.number(f32(v))); return self },
    set_grid_column_end       = proc(self: ^Style, v: i32) -> ^Style { _author(self, .Grid_Column_End, css.number(f32(v))); return self },
    set_grid_row_start        = proc(self: ^Style, v: i32) -> ^Style { _author(self, .Grid_Row_Start, css.number(f32(v))); return self },
    set_grid_row_end          = proc(self: ^Style, v: i32) -> ^Style { _author(self, .Grid_Row_End, css.number(f32(v))); return self },

    set_sticky = proc(self: ^Style, v: Maybe(Sticky)) -> ^Style { _set_sticky(_stored(self), v); return self },
    // The shadows are copied: the caller's slice belongs to the style engine and can go away.
    set_filter = proc(self: ^Style, v: Maybe(Filter)) -> ^Style { _set_filter(_stored(self), v); return self },
    // Records the rounded shape a component draws, for clipping and hit-testing.
    set_corner_radius = proc(self: ^Style, v: Radii) -> ^Style {
        n := self.owner
        n.corner_radius = common.radii_fit(v, n.rect.w, n.rect.h)
        n.clip_radius = common.radii_inset_sides(n.corner_radius, _stored(self).border_width)
        return self
    },
}

Init_Style :: proc(n: ^Node) {
    if n._internal_style == nil {
        panic("node is not initialized properly.")
    }
    style := cast(^Style)n._internal_style
    style.owner = n
    style._internal_vt = &style_vtable
    style.set_inline = _style_set_inline
    style.clear_inline = _style_clear_inline
    style.apply_overflow = _style_apply_overflow
    style.pointer_events = .Inherit
    style.transform = common.IDENTITY_TRANSFORM
}

// What a style owns beyond its own memory. A component frees the style itself in `on_free`.
@(private)
_style_release :: proc(s: ^Style) {
    delete(s.inline)
    if filter, on := s.filter.?; on do delete(filter.shadows, runtime.heap_allocator())
}

Set_Style :: proc(n: ^Node, style: ^$T) where intrinsics.type_is_subtype_of(T, Style)
{
    n._internal_style = style
}

// Computed text style: mirroring the DOM's inherited computed style.
Resolve_Text_Style :: proc(n: ^BaseNode) -> (out: Text_Style) {
    color_found, size_found, line_found, weight_found := false, false, false, false
    for p := n; p != nil; p = p.parent {
        if p._internal_style == nil {
            continue
        }
        stored := cast(^Style)p._internal_style
        t := stored.text
        out.computed = out.computed || stored.computed_text
        if !color_found && (stored.computed_text || t.color != {}) {
            out.color = t.color
            color_found = true
        }
        if !size_found && (stored.computed_text || t.font_size > 0) {
            out.font_size = t.font_size
            size_found = true
        }
        if !line_found && (stored.computed_text || t.line_height > 0) {
            out.line_height = t.line_height
            out.line_height_unit = t.line_height_unit
            out.line_height_specified = t.line_height_specified
            line_found = true
        }
        if out.font == nil do out.font = t.font
        if out.align == .Inherit do out.align = t.align
        if out.transform == .Inherit do out.transform = t.transform
        if out.white_space == .Inherit do out.white_space = t.white_space
        if out.decoration == .Inherit do out.decoration = t.decoration
        if out.overflow == .Inherit do out.overflow = t.overflow
        if !out.letter_spacing_set && t.letter_spacing_set {
            out.letter_spacing = t.letter_spacing
            out.letter_spacing_set = true
        }
        if !weight_found && (stored.computed_text || t.font_weight != 0) {
            out.font_weight = t.font_weight
            weight_found = true
        }
    }
    if out.font_weight == 0 do out.font_weight = text.WEIGHT_NORMAL
    return
}

Resolve_User_Select :: proc(n: ^BaseNode) -> User_Select {
    if n == nil do return .Text
    if n._internal_style != nil {
        specified := (cast(^Style)n._internal_style).select_mode
        if specified != .Auto do return specified
    }
    if n.parent == nil do return .Text
    parent := Resolve_User_Select(n.parent)
    if parent == .None || parent == .All do return parent
    return .Text
}

// Unlike user-select, a `None` here does not force descendants: children stay
// hittable on `Auto`, matching CSS. `Inherit` is the opt-in that walks up.
Resolve_Pointer_Events :: proc(n: ^BaseNode) -> Pointer_Events {
    if n == nil do return .Auto
    if n._internal_style != nil {
        specified := (cast(^Style)n._internal_style).pointer_events
        if specified != .Inherit do return specified
    }
    if n.parent == nil do return .Auto
    return Resolve_Pointer_Events(n.parent)
}

@(private="file")
_set_sticky :: proc(s: ^Style, sticky: Maybe(Sticky)) {
    if s.sticky == sticky do return
    s.owner->damage()
    s.sticky = sticky
}

@(private="file")
_set_filter :: proc(s: ^Style, filter: Maybe(Filter)) {
    heap := runtime.heap_allocator()
    value, on := filter.?
    old, had := s.filter.?
    if !on && !had do return
    s.owner->damage()
    if on {
        shadows := make([]common.EffectShadow, len(value.shadows), heap)
        copy(shadows, value.shadows)
        value.shadows = shadows
    }
    if had do delete(old.shadows, heap)
    s.filter = value if on else nil
}

// The readers below are for a node that may have no style at all.
Resolve_Transform :: proc(n: ^BaseNode) -> common.Transform {
    if n._internal_style == nil do return common.IDENTITY_TRANSFORM
    return (cast(^Style)n._internal_style).transform
}

Resolve_Filter :: proc(n: ^BaseNode) -> (Filter, bool) {
    if n._internal_style == nil do return {}, false
    return (cast(^Style)n._internal_style).filter.?
}

Resolve_Sticky :: proc(n: ^BaseNode) -> (Sticky, bool) {
    if n._internal_style == nil do return {}, false
    return (cast(^Style)n._internal_style).sticky.?
}

Resolve_Fixed :: proc(n: ^BaseNode) -> bool {
    return n._internal_style != nil && (cast(^Style)n._internal_style).fixed
}

Resolve_Corner_Radius :: proc(n: ^BaseNode) -> Radii {
    s := cast(^Style)n._internal_style
    s->set_corner_radius(common.radii_resolve(s.radius, s.radius_percent, n.rect.w, n.rect.h))
    return n.corner_radius
}

// How far a sticky node moves off its laid out `rect` to stay stuck, kept inside `parent`.
Resolve_Sticky_Shift :: proc(n: ^BaseNode, parent: common.Rect, port: Scroll_Port) -> (shift: [2]f32) {
    s, on := Resolve_Sticky(n)
    if !on do return
    rect := n.rect
    view := port.viewport
    inset := [4]f32{
        s.inset[0] + s.percent[0] * view.h / 100, s.inset[1] + s.percent[1] * view.w / 100,
        s.inset[2] + s.percent[2] * view.h / 100, s.inset[3] + s.percent[3] * view.w / 100,
    }
    if s.set[2] do shift.y = clamp(view.y + view.h - inset[2] - (rect.y + rect.h), min(parent.y - rect.y, 0), 0)
    if s.set[0] {
        if down := view.y + inset[0] - rect.y; down > 0 do shift.y = clamp(down, 0, max(parent.y + parent.h - (rect.y + rect.h), 0))
    }
    if s.set[1] do shift.x = clamp(view.x + view.w - inset[1] - (rect.x + rect.w), min(parent.x - rect.x, 0), 0)
    if s.set[3] {
        if right := view.x + inset[3] - rect.x; right > 0 do shift.x = clamp(right, 0, max(parent.x + parent.w - (rect.x + rect.w), 0))
    }
    return
}

Resolve_User_Select_All_Scope :: proc(n: ^BaseNode) -> ^BaseNode {
    if Resolve_User_Select(n) != .All do return nil
    scope := n
    for p := n.parent; p != nil && Resolve_User_Select(p) == .All; p = p.parent {
        scope = p
    }
    return scope
}
