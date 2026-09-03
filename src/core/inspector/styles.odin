#+build !js
package inspector

import "core:fmt"
import "core:math"
import "core:strings"
import "src:core/common"
import "src:core/hit_test"
import "src:core/node"
import "src:ui/box"
import "src:ui/scroll_area"

Band :: struct {
    root:   ^Frame_Box,
    slot:   ^node.Node,
    tag:    Label,
    top:    Label,
    right:  Label,
    bottom: Label,
    left:   Label,
    tint:   Color,
    lit:    bool,
}

Prop :: struct {
    root:  ^box.Box,
    name:  Label,
    value: Label,
}

Style_View :: struct {
    scroll:  ^scroll_area.Scroll_Area,
    heading: Label,
    position: Band,
    margin:   Band,
    border:   Band,
    padding:  Band,
    content:  ^Frame_Box,
    content_lit: bool,
    size:    Label,
    props:   [len(Prop_Key)]Prop,
    swatch:  ^Icon,
}

Prop_Key :: enum {
    Display,
    Position,
    Flex_Direction,
    Flex_Wrap,
    Justify_Content,
    Align_Items,
    Align_Self,
    Align_Content,
    Flex_Grow,
    Flex_Shrink,
    Flex_Basis,
    Width,
    Height,
    Min_Width,
    Min_Height,
    Max_Width,
    Max_Height,
    Aspect_Ratio,
    Gap,
    Box_Sizing,
    Overflow,
    Z_Index,
    Clip,
    Pointer_Events,
    User_Select,
    Color,
    Font_Size,
    Font_Weight,
    Line_Height,
}

PROP_NAMES := [Prop_Key]string {
    .Display         = "display",
    .Position        = "position",
    .Flex_Direction  = "flex-direction",
    .Flex_Wrap       = "flex-wrap",
    .Justify_Content = "justify-content",
    .Align_Items     = "align-items",
    .Align_Self      = "align-self",
    .Align_Content   = "align-content",
    .Flex_Grow       = "flex-grow",
    .Flex_Shrink     = "flex-shrink",
    .Flex_Basis      = "flex-basis",
    .Width           = "width",
    .Height          = "height",
    .Min_Width       = "min-width",
    .Min_Height      = "min-height",
    .Max_Width       = "max-width",
    .Max_Height      = "max-height",
    .Aspect_Ratio    = "aspect-ratio",
    .Gap             = "gap",
    .Box_Sizing      = "box-sizing",
    .Overflow        = "overflow",
    .Z_Index         = "z-index",
    .Clip            = "clip",
    .Pointer_Events  = "pointer-events",
    .User_Select     = "user-select",
    .Color           = "color",
    .Font_Size       = "font-size",
    .Font_Weight     = "font-weight",
    .Line_Height     = "line-height",
}

styles_build :: proc(v: ^Style_View) -> ^scroll_area.Scroll_Area {
    v.scroll = scroll_area.New({vertical = .Auto, horizontal = .Hidden, track_color = PANEL, thumb_color = {75, 78, 82, 255}, thumb_hover = {103, 107, 112, 255}, button_color = PANEL, arrow_color = TEXT_FAINT}, "styles")
    v.scroll->style()->
        set_width(300)->
        set_flex_shrink(0)->
        set_height(100, node.percent)

    header := row_box("styles-header")
    header->style()->set_height(24)->set_padding_left(10)->set_padding_right(SCROLLBAR_GUTTER)->set_width(100, node.percent)
    v.heading = label("no element selected", TEXT_DIM, FONT_SIZE)
    header->add(v.heading.root)
    v.scroll->add(header)

    frame := box.New({}, "box-model")
    frame->style()->
        set_width(100, node.percent)->
        set_flex_shrink(0)->
        set_height(196)->
        set_wrap(.NoWrap)->
        set_align_items(.Stretch)->
        set_padding_left(10)->
        set_padding_right(SCROLLBAR_GUTTER)->
        set_padding_top(4)->
        set_padding_bottom(12)

    v.content_lit = true
    v.position = _band(C_POSITION, "position")
    v.margin = _band(C_MARGIN, "margin")
    v.border = _band(C_BORDER, "border")
    v.padding = _band(C_PADDING, "padding")

    v.content = frame_box(C_CONTENT, BAND_EDGE, "content-box")
    v.content->style()->
        set_flex_grow(1)->
        set_align_items(.Center)->
        set_justify_content(.Center)->
        set_min_height(26)
    v.size = label("-", ON_BAND, FONT_SIZE_SM)
    v.content->add(v.size.root)

    v.padding.slot->add(v.content)
    v.border.slot->add(v.padding.root)
    v.margin.slot->add(v.border.root)
    v.position.slot->add(v.margin.root)
    frame->add(v.position.root)
    v.scroll->add(frame)
    v.scroll->add(divider(false))

    for key in Prop_Key {
        p: Prop
        p.root = row_box()
        p.root->style()->
            set_width(100, node.percent)->
            set_padding_left(10)->
            set_padding_right(SCROLLBAR_GUTTER)->
            set_padding_y(2)->
            set_justify_content(.SpaceBetween)->
            set_gap_all(10)
        p.name = label(PROP_NAMES[key], TEXT_DIM, FONT_SIZE)
        p.value = label("-", TEXT, FONT_SIZE)
        p.root->add(p.name.root)
        if key == .Color {
            v.swatch = icon(.Swatch, 9, Color{})
            v.swatch->style()->set_margin_left(6)->set_margin_right(4)
            spread := spacer()
            p.root->add(spread, v.swatch)
        }
        p.root->add(p.value.root)
        v.props[key] = p
        v.scroll->add(p.root)
    }

    tail := box.New({}, "styles-tail")
    tail->style()->set_height(8)->set_flex_shrink(0)
    v.scroll->add(tail)
    return v.scroll
}

@(private = "file")
_band :: proc(color: Color, name: string) -> (b: Band) {
    b.tint = color
    b.lit = true
    b.root = frame_box(color, BAND_EDGE, "band")
    b.root->style()->set_flex_grow(1)->set_padding_all(1)

    b.tag = label(name, ON_BAND, FONT_SIZE_SM)
    b.tag.root->style()->
        set_position_type(.Absolute)->
        set_position_left(6)->
        set_position_top(3)

    top := row_box()
    top->style()->set_height(17)->set_justify_content(.Center)->set_align_items(.Center)
    b.top = label("-", ON_BAND, FONT_SIZE_SM)
    top->add(b.top.root)

    middle := row_box()
    middle->style()->set_flex_grow(1)->set_align_items(.Stretch)

    left := row_box()
    left->style()->set_width(26)->set_justify_content(.Center)->set_align_items(.Center)
    b.left = label("-", ON_BAND, FONT_SIZE_SM)
    left->add(b.left.root)

    b.slot = node.New("slot")
    b.slot->style()->
        set_flex_grow(1)->
        set_flex_shrink(1)->
        set_flex_basis(0, node.percent)->
        set_flex_direction(.Column)->
        set_justify_content(.Center)->
        set_align_items(.Stretch)

    right := row_box()
    right->style()->set_width(26)->set_justify_content(.Center)->set_align_items(.Center)
    b.right = label("-", ON_BAND, FONT_SIZE_SM)
    right->add(b.right.root)

    b.root.hole = auto_cast(b.slot)
    middle->add(left, b.slot, right)

    bottom := row_box()
    bottom->style()->set_height(17)->set_justify_content(.Center)->set_align_items(.Center)
    b.bottom = label("-", ON_BAND, FONT_SIZE_SM)
    bottom->add(b.bottom.root)

    b.root->add(b.tag.root, top, middle, bottom)
    return
}

styles_update :: proc(v: ^Style_View, snap: ^Snapshot, id: Node_Id) {
    index := find_index(snap, id)
    if index < 0 {
        label_set(v.heading, "no element selected")
        label_color(v.heading, TEXT_DIM)
        _band_set(v.margin, {})
        _band_set(v.border, {})
        _band_set(v.padding, {})
        _band_set_inset(v.position, {})
        label_set(v.size, "-")
        for key in Prop_Key do label_set(v.props[key].value, "-")
        v.swatch.color = Color{}
        return
    }

    e := snap.nodes[index]
    key := str(snap, e.key)
    name := str(snap, e.name)
    if key == "" {
        label_set(v.heading, name)
    } else {
        label_set(v.heading, strings.concatenate({name, " #", key}, context.temp_allocator))
    }
    label_color(v.heading, TAG)

    _band_set(v.margin, e.margin)
    _band_set(v.border, e.border)
    _band_set(v.padding, e.padding)
    _band_set_inset(v.position, e.inset)

    content_w := e.rect.w - e.border[0] - e.border[2] - e.padding[0] - e.padding[2]
    content_h := e.rect.h - e.border[1] - e.border[3] - e.padding[1] - e.padding[3]
    label_set(v.size, fmt.tprintf("%s×%s", _num(content_w), _num(content_h)))

    set :: proc(v: ^Style_View, key: Prop_Key, value: string) {
        label_set(v.props[key].value, value)
        label_color(v.props[key].value, TEXT_FAINT if value == "-" else TEXT)
    }

    set(v, .Display, _css(e.display))
    set(v, .Position, _css(e.position_type))
    set(v, .Flex_Direction, _css(e.flex_direction))
    set(v, .Flex_Wrap, _css(e.wrap))
    set(v, .Justify_Content, _css(e.justify))
    set(v, .Align_Items, _css(e.align_items))
    set(v, .Align_Self, _css(e.align_self))
    set(v, .Align_Content, _css(e.align_content))
    set(v, .Flex_Grow, _num(e.flex_grow))
    set(v, .Flex_Shrink, _num(e.flex_shrink))
    set(v, .Flex_Basis, _len_str(e.flex_basis))
    set(v, .Width, _len_str(e.width))
    set(v, .Height, _len_str(e.height))
    set(v, .Min_Width, _len_str(e.min_width))
    set(v, .Min_Height, _len_str(e.min_height))
    set(v, .Max_Width, _len_str(e.max_width))
    set(v, .Max_Height, _len_str(e.max_height))
    set(v, .Aspect_Ratio, "-" if math.is_nan(e.aspect) || e.aspect == 0 else _num(e.aspect))
    set(v, .Gap, fmt.tprintf("%s / %s", _num(e.gap_row), _num(e.gap_column)))
    set(v, .Box_Sizing, _css(e.box_sizing))
    set(v, .Overflow, fmt.tprintf("%s / %s", _css(e.overflow_x), _css(e.overflow_y)))
    set(v, .Z_Index, fmt.tprintf("%d", e.z_index))
    set(v, .Clip, _css(e.clip_mode))
    set(v, .Pointer_Events, _css(e.pointer_events))
    set(v, .User_Select, _css(e.select_mode))
    set(v, .Color, fmt.tprintf("%d %d %d %d", e.color.r, e.color.g, e.color.b, e.color.a))
    v.swatch.color = e.color
    set(v, .Font_Size, _num(e.font_size))
    set(v, .Font_Weight, fmt.tprintf("%d", int(e.font_weight)))
    set(v, .Line_Height, _len_str(e.line_height))
}

styles_hover :: proc(v: ^Style_View, mx, my: f32) {
    x, y := hit_test.to_local(auto_cast v.content, mx, my)
    on_content := common.rect_intersect(v.content.rect, x, y)
    hot: ^Band
    if !on_content {
        for b in ([]^Band{&v.padding, &v.border, &v.margin, &v.position}) {
            if common.rect_intersect(b.root.rect, x, y) {
                hot = b
                break
            }
        }
    }
    idle := !on_content && hot == nil

    _band_light(&v.position, idle || hot == &v.position)
    _band_light(&v.margin, idle || hot == &v.margin)
    _band_light(&v.border, idle || hot == &v.border)
    _band_light(&v.padding, idle || hot == &v.padding)

    lit := idle || on_content
    if lit != v.content_lit {
        v.content_lit = lit
        v.content.fill = C_CONTENT if lit else Color{}
        label_color(v.size, ON_BAND if lit else TEXT_DIM)
    }
}

@(private = "file")
_band_light :: proc(b: ^Band, on: bool) {
    if b.lit == on do return
    b.lit = on
    b.root.fill = b.tint if on else Color{}
    ink := ON_BAND if on else TEXT_DIM
    label_color(b.tag, ink)
    label_color(b.top, ink)
    label_color(b.left, ink)
    label_color(b.right, ink)
    label_color(b.bottom, ink)
}

@(private = "file")
_band_set_inset :: proc(b: Band, edges: [4]Len) {
    label_set(b.left, _len_str(edges[0]))
    label_set(b.top, _len_str(edges[1]))
    label_set(b.right, _len_str(edges[2]))
    label_set(b.bottom, _len_str(edges[3]))
}

@(private = "file")
_band_set :: proc(b: Band, edges: [4]f32) {
    label_set(b.left, _edge(edges[0]))
    label_set(b.top, _edge(edges[1]))
    label_set(b.right, _edge(edges[2]))
    label_set(b.bottom, _edge(edges[3]))
}

@(private = "file")
_edge :: proc(v: f32) -> string {
    if math.is_nan(v) do return "-"
    return _num(v)
}

@(private = "file")
_num :: proc(v: f32) -> string {
    if math.is_nan(v) do return "-"
    if v == math.trunc(v) && abs(v) < 1e9 do return fmt.tprintf("%d", int(v))
    out := fmt.tprintf("%.3f", v)
    for len(out) > 0 && out[len(out) - 1] == '0' do out = out[:len(out) - 1]
    if len(out) > 0 && out[len(out) - 1] == '.' do out = out[:len(out) - 1]
    return out
}

@(private = "file")
_len_str :: proc(l: Len) -> string {
    #partial switch l.unit {
    case .Auto:    return "auto"
    case .Percent: return fmt.tprintf("%s%%", _num(l.value))
    case .Point:   return _num(l.value)
    }
    return "-"
}

@(private = "file")
_css :: proc(value: any) -> string {
    raw := fmt.tprintf("%v", value)
    b := strings.builder_make(0, len(raw) + 8, context.temp_allocator)
    for i in 0 ..< len(raw) {
        c := raw[i]
        if c >= 'A' && c <= 'Z' {
            if i > 0 do strings.write_byte(&b, '-')
            strings.write_byte(&b, c + 32)
        } else if c == '_' {
            strings.write_byte(&b, '-')
        } else {
            strings.write_byte(&b, c)
        }
    }
    return strings.to_string(b)
}
