#+build !js
package inspector

import "core:fmt"
import "src:core/common"
import "src:core/node"
import "src:core/painter"
import "src:ui/box"
import YG "src:yoga"

OVERLAY_Z :: i32(1 << 24)

Metrics :: struct {
    border_box: common.Rect,
    margin:     [4]f32,
    border:     [4]f32,
    padding:    [4]f32,
    valid:      bool,
}

Highlight :: struct {
    using base: node.Node,
    hover: Metrics,
}

Overlay :: struct {
    root:      ^node.Node,
    paint:     ^Highlight,
    tip:       ^box.Box,
    tip_name:  Label,
    tip_size:  Label,
    tip_shown: bool,
}

overlay_build :: proc(ov: ^Overlay, font: ^node.Font) {
    ov.root = node.New("banana:inspector-overlay")
    ov.root.z_index = OVERLAY_Z
    ov.root.creates_stacking_context = true
    ov.root->style()->
        set_position_type(.Absolute)->
        set_position_left(0)->
        set_position_top(0)->
        set_width(100, node.percent)->
        set_height(100, node.percent)->
        set_pointer_events(.None)

    ov.paint = new(Highlight)
    node.Init(ov.paint, "highlight")
    own_style(auto_cast(ov.paint))
    ov.paint.draw = transmute(proc(self: ^node.BaseNode))_highlight_draw
    ov.paint.on_free = transmute(proc(self: ^node.BaseNode))_highlight_free
    ov.paint->style()->
        set_position_type(.Absolute)->
        set_position_left(0)->
        set_position_top(0)->
        set_width(0)->
        set_height(0)

    ov.tip = box.New({background = Color{28, 29, 32, 244}, radius = 4}, "tip")
    ov.tip->style()->
        set_position_type(.Absolute)->
        set_position_left(0)->
        set_position_top(0)->
        set_flex_direction(.Row)->
        set_align_items(.Center)->
        set_gap_all(8)->
        set_padding_x(8)->
        set_padding_y(4)->
        set_display(.None)->
        set_font(font)->
        set_font_size(11)

    ov.tip_name = label("", ACCENT, 11)
    ov.tip_size = label("", TEXT_DIM, 11)
    ov.tip->add(ov.tip_name.root, ov.tip_size.root)

    ov.root->add(ov.paint, ov.tip)
}

@(private = "file")
_highlight_free :: proc(self: ^Highlight) {
    free(self._internal_style)
}

metrics_of :: proc(n: ^node.BaseNode) -> (m: Metrics) {
    if n == nil || n.freed do return
    m.border_box = n.rect
    m.margin = {
        YG.NodeLayoutGetMargin(n.raw, .Left),
        YG.NodeLayoutGetMargin(n.raw, .Top),
        YG.NodeLayoutGetMargin(n.raw, .Right),
        YG.NodeLayoutGetMargin(n.raw, .Bottom),
    }
    m.border = {
        YG.NodeLayoutGetBorder(n.raw, .Left),
        YG.NodeLayoutGetBorder(n.raw, .Top),
        YG.NodeLayoutGetBorder(n.raw, .Right),
        YG.NodeLayoutGetBorder(n.raw, .Bottom),
    }
    m.padding = {
        YG.NodeLayoutGetPadding(n.raw, .Left),
        YG.NodeLayoutGetPadding(n.raw, .Top),
        YG.NodeLayoutGetPadding(n.raw, .Right),
        YG.NodeLayoutGetPadding(n.raw, .Bottom),
    }
    m.valid = true
    return
}

overlay_set_tip :: proc(ov: ^Overlay, name: string, m: Metrics, viewport: [2]f32) {
    if !m.valid {
        if ov.tip_shown {
            ov.tip->style()->set_display(.None)
            ov.tip_shown = false
        }
        return
    }
    label_set(ov.tip_name, name)
    label_set(ov.tip_size, fmt.tprintf("%.0f x %.0f", m.border_box.w, m.border_box.h))
    if !ov.tip_shown {
        ov.tip->style()->set_display(.Flex)
        ov.tip_shown = true
    }

    w := max(ov.tip.rect.w, 60)
    h := max(ov.tip.rect.h, 20)
    x := m.border_box.x - m.margin[0]
    y := m.border_box.y + m.border_box.h + m.margin[3] + 4
    if y + h > viewport.y do y = m.border_box.y - m.margin[1] - h - 4
    if y < 0 do y = m.border_box.y + 4
    x = clamp(x, 2, max(2, viewport.x - w - 2))
    ov.tip->style()->set_position_left(x)->set_position_top(y)
}

@(private = "file")
_highlight_draw :: proc(self: ^Highlight) {
    p := painter.get()
    if self.hover.valid do _draw_metrics(p, self.hover, 0.55, true)
}

@(private = "file")
_draw_metrics :: proc(p: painter.Painter, m: Metrics, alpha: f32, outline: bool) {
    b := m.border_box
    margin_box := common.Rect {
        b.x - m.margin[0],
        b.y - m.margin[1],
        b.w + m.margin[0] + m.margin[2],
        b.h + m.margin[1] + m.margin[3],
    }
    padding_box := common.Rect {
        b.x + m.border[0],
        b.y + m.border[1],
        b.w - m.border[0] - m.border[2],
        b.h - m.border[1] - m.border[3],
    }
    content_box := common.Rect {
        padding_box.x + m.padding[0],
        padding_box.y + m.padding[1],
        padding_box.w - m.padding[0] - m.padding[2],
        padding_box.h - m.padding[1] - m.padding[3],
    }

    _band(p, margin_box, b, _fade(C_MARGIN, alpha))
    _band(p, b, padding_box, _fade(C_BORDER, alpha))
    _band(p, padding_box, content_box, _fade(C_PADDING, alpha))
    painter.rect(p, content_box, _fade(C_CONTENT, alpha))
    if outline do painter.border(p, b, _fade(ACCENT, 0.9), 1)
}

// Chrome color band for css layout display
@(private = "file")
_band :: proc(p: painter.Painter, outer, inner: common.Rect, color: Color) {
    if outer.w <= 0 || outer.h <= 0 do return
    top := max(0, inner.y - outer.y)
    left := max(0, inner.x - outer.x)
    right := max(0, (outer.x + outer.w) - (inner.x + inner.w))
    bottom := max(0, (outer.y + outer.h) - (inner.y + inner.h))

    if top > 0 do painter.rect(p, {outer.x, outer.y, outer.w, top}, color)
    if bottom > 0 do painter.rect(p, {outer.x, outer.y + outer.h - bottom, outer.w, bottom}, color)
    mid_h := outer.h - top - bottom
    if mid_h > 0 {
        if left > 0 do painter.rect(p, {outer.x, outer.y + top, left, mid_h}, color)
        if right > 0 do painter.rect(p, {outer.x + outer.w - right, outer.y + top, right, mid_h}, color)
    }
}

@(private = "file")
_fade :: proc(c: Color, a: f32) -> Color {
    out := c
    out.a = u8(clamp(a, 0, 1) * 255)
    return out
}
