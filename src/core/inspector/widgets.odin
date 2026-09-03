#+build !js
package inspector

import "src:core/common"
import "src:core/node"
import "src:core/painter"
import "src:core/svg"
import "src:ui/box"
import "src:ui/text_node"

Color            :: common.Color

BG               :: Color{32, 33, 36, 255}
PANEL            :: Color{41, 42, 45, 255}
LINE             :: Color{60, 64, 67, 255}
TEXT             :: Color{232, 234, 237, 255}
TEXT_DIM         :: Color{154, 160, 166, 255}
TEXT_FAINT       :: Color{124, 129, 135, 255}
TAG              :: Color{93, 176, 215, 255}
ATTR             :: Color{155, 187, 220, 255}
VALUE            :: Color{242, 151, 102, 255}
ACCENT           :: Color{138, 180, 248, 255}
ROW_HOVER        :: Color{53, 54, 58, 255}
ROW_SELECT       :: Color{29, 60, 97, 255}
BTN_ON           :: Color{26, 115, 232, 255}
BTN_HOVER        :: Color{55, 56, 60, 255}

C_CONTENT        :: Color{111, 168, 220, 255}
C_PADDING        :: Color{147, 196, 125, 255}
C_BORDER         :: Color{255, 229, 153, 255}
C_MARGIN         :: Color{246, 178, 107, 255}
C_POSITION       :: Color{206, 142, 84, 255}
ON_BAND          :: Color{30, 31, 34, 255}
BAND_EDGE        :: Color{92, 95, 99, 255}

SCROLLBAR_GUTTER :: f32(20)

ROW_HEIGHT       :: f32(18)
INDENT_STEP      :: f32(12)
FONT_SIZE        :: f32(11)
FONT_SIZE_SM     :: f32(10)

@(private = "file")
ICON_PICKER_SVG :: `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-square-dashed-mouse-pointer-icon lucide-square-dashed-mouse-pointer"><path d="M12.034 12.681a.498.498 0 0 1 .647-.647l9 3.5a.5.5 0 0 1-.033.943l-3.444 1.068a1 1 0 0 0-.66.66l-1.067 3.443a.5.5 0 0 1-.943.033z"/><path d="M5 3a2 2 0 0 0-2 2"/><path d="M19 3a2 2 0 0 1 2 2"/><path d="M5 21a2 2 0 0 1-2-2"/><path d="M9 3h1"/><path d="M9 21h2"/><path d="M14 3h1"/><path d="M3 9v1"/><path d="M21 9v2"/><path d="M3 14v1"/></svg>`

Label :: struct {
    root: ^node.Node,
    text: ^text_node.Text_Node,
}

label :: proc(value: string, color: Color, size: f32 = FONT_SIZE) -> Label {
    l: Label
    l.root = node.New()
    l.root->style()->
        set_flex_direction(.Row)->
        set_flex_shrink(0)->
        set_color(color)->
        set_font_size(size)
    l.text = text_node.New(value)
    l.root->add(l.text)
    return l
}

label_set :: proc(l: Label, value: string) {
    if l.text != nil do l.text->set_text(value)
}

label_color :: proc(l: Label, color: Color) {
    if l.root != nil do l.root->style()->set_color(color)
}

row_box :: proc(key: string = "") -> ^box.Box {
    b := box.New({}, key)
    b->style()->
        set_flex_direction(.Row)->
        set_wrap(.NoWrap)->
        set_align_items(.Center)->
        set_flex_shrink(0)
    return b
}

spacer :: proc() -> ^node.Node {
    n := node.New()
    n->style()->set_flex_grow(1)->set_flex_shrink(1)
    return n
}

divider :: proc(vertical: bool) -> ^box.Box {
    d := box.New({background = LINE})
    if vertical {
        d->style()->set_width(1)->set_height(16)->set_flex_shrink(0)->set_margin_x(4)
    } else {
        d->style()->set_height(1)->set_width(100, node.percent)->set_flex_shrink(0)
    }
    return d
}

own_style :: proc(n: ^node.Node) {
    node.Set_Style(n, new(node.Style))
    node.Init_Style(n)
    n.style = _base_style
}

@(private = "file")
_base_style :: proc(self: ^node.Node) -> ^node.Style {
    return cast(^node.Style)self._internal_style
}

Frame_Box :: struct {
    using base: node.Node,
    fill:    Color,
    outline: Color,
    hole:    ^node.BaseNode,
}

frame_box :: proc(fill, outline: Color, key: string = "") -> ^Frame_Box {
    n := new(Frame_Box)
    node.Init(n, key)
    own_style(auto_cast(n))
    n.fill = fill
    n.outline = outline
    n.draw = transmute(proc(self: ^node.BaseNode))_frame_draw
    n.on_free = transmute(proc(self: ^node.BaseNode))_frame_free
    n->style()->set_flex_direction(.Column)->set_align_items(.Stretch)->set_wrap(.NoWrap)
    return n
}

@(private = "file")
_frame_free :: proc(self: ^Frame_Box) {
    free(self._internal_style)
}

@(private = "file")
_frame_draw :: proc(self: ^Frame_Box) {
    p := painter.get()
    if self.fill.a > 0 {
        if self.hole != nil {
            _ring(p, self.rect, self.hole.rect, self.fill)
        } else {
            painter.rect(p, self.rect, self.fill)
        }
    }
    if self.outline.a > 0 do painter.border(p, self.rect, self.outline, 1)
}

@(private = "file")
_ring :: proc(p: painter.Painter, outer, inner: common.Rect, color: Color) {
    if outer.w <= 0 || outer.h <= 0 do return
    if inner.w <= 0 || inner.h <= 0 {
        painter.rect(p, outer, color)
        return
    }
    top := max(0, inner.y - outer.y)
    left := max(0, inner.x - outer.x)
    right := max(0, (outer.x + outer.w) - (inner.x + inner.w))
    bottom := max(0, (outer.y + outer.h) - (inner.y + inner.h))

    if top > 0 do painter.rect(p, {outer.x, outer.y, outer.w, top}, color)
    if bottom > 0 do painter.rect(p, {outer.x, outer.y + outer.h - bottom, outer.w, bottom}, color)
    mid := outer.h - top - bottom
    if mid > 0 {
        if left > 0 do painter.rect(p, {outer.x, outer.y + top, left, mid}, color)
        if right > 0 do painter.rect(p, {outer.x + outer.w - right, outer.y + top, right, mid}, color)
    }
}

Icon_Kind :: enum {
    Picker,
    Chevron,
    Swatch,
}

Icon :: struct {
    using base: node.Node,
    kind:      Icon_Kind,
    color:     Color,
    open:      bool,
    svg_doc:   svg.Document,
    svg_cache: svg.Cache,
}

icon :: proc(kind: Icon_Kind, size: f32, color: Color) -> ^Icon {
    n := new(Icon)
    node.Init(n, "icon")
    own_style(auto_cast(n))
    n.kind = kind
    n.color = color
    if kind == .Picker {
        n.svg_doc, _ = svg.parse(ICON_PICKER_SVG)
    }
    n.draw = transmute(proc(self: ^node.BaseNode))_icon_draw
    n.on_free = transmute(proc(self: ^node.BaseNode))_icon_free
    n->style()->set_width(size)->set_height(size)->set_flex_shrink(0)
    return n
}

@(private = "file")
_icon_free :: proc(self: ^Icon) {
    svg.cache_destroy(&self.svg_cache)
    svg.destroy(&self.svg_doc)
    free(self._internal_style)
}

@(private = "file")
_icon_draw :: proc(self: ^Icon) {
    p := painter.get()
    r := self.rect
    switch self.kind {
    case .Picker:
        svg.draw_cached(&self.svg_doc, p, &self.svg_cache, r, true, self.color)
    case .Chevron:
        _draw_chevron(p, r, self.color, self.open)
    case .Swatch:
        painter.rect(p, r, self.color, 2)
        painter.border(p, r, Color{0, 0, 0, 120}, 1, 2)
    }
}

@(private = "file")
_draw_chevron :: proc(p: painter.Painter, r: common.Rect, color: Color, open: bool) {
    s := min(r.w, r.h) * 0.56
    cx := r.x + r.w * 0.5
    cy := r.y + r.h * 0.5
    points: [][2]f32
    if open {
        points = {{cx - s * 0.62, cy - s * 0.34}, {cx + s * 0.62, cy - s * 0.34}, {cx, cy + s * 0.46}}
    } else {
        points = {{cx - s * 0.34, cy - s * 0.62}, {cx + s * 0.46, cy}, {cx - s * 0.34, cy + s * 0.62}}
    }
    painter.triangles(p, points, []u32{0, 1, 2}, color)
}
