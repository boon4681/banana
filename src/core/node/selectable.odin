package node

import "src:core/text"

// Shared read-only operations for text-producing nodes.
Text_Content_Interface :: struct {
    position_at: proc(self: ^BaseNode, x, y: f32) -> text.Position,
    expand:      proc(self: ^BaseNode, pos: text.Position, g: text.Granularity) -> text.Selection,
    str:         proc(self: ^BaseNode) -> string,
}

is_selectable :: #force_inline proc(n: ^BaseNode) -> bool {
    return n != nil && !n.freed && n.text_content != nil &&
           n.position_at != nil && Resolve_User_Select(n) != .None
}
