package box

import "src:core/node"
import "src:core/painter"

Box_Style :: struct {
    using base: node.Style,
    background: Color,
    radius:     f32,
}

Box :: struct {
    using node: Node,
    style: proc(self: ^Box) -> ^Box_Style
}

New :: proc(style: Box_Style = {}, key: Maybe(string) = nil) -> ^Box {
    n := new(Box)
    node.Init(auto_cast(n), key)
    n.style = _get_style
    node.Set_Style(auto_cast(n), new_clone(style))
    node.Init_Style(auto_cast(n))
    _apply_div_defaults(n)
    n.draw = transmute(proc(self: ^Node))_box_draw
    n.on_free = transmute(proc(self: ^Node))_box_free
    return n
}

// Yoga's defaults (flex-shrink 0, align-content flex-start) don't match CSS.
@(private="file")
_apply_div_defaults :: proc(n: ^Box) {
    s := n->style()
    s->set_flex_direction(.Column)
    s->set_align_items(.Stretch)
    s->set_align_content(.Stretch)
    s->set_flex_shrink(1)
    s->set_width(0, node.auto)
    s->set_height(0, node.auto)
}

@(private="file")
_get_style:: proc(self: ^Box) -> ^Box_Style {
    return auto_cast(self._internal_style)
}

@(private="file")
_box_draw :: proc(self: ^Box) {
    style := self->style()
    painter.rect(painter.get(), self.rect, style.background, style.radius)
}

@(private="file")
_box_free :: proc(self: ^Box) {
    free(self._internal_style)
    free(self.data)
}
