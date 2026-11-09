package context_menu

import "core:strings"
import "src:core/events"
import "src:core/node"
import "src:ui/shared/popup"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Context_Menu

Context_Menu :: struct {
    using node: Node,
    style: proc(self: ^Context_Menu) -> ^node.Style,

    disabled: bool,

    onselect: proc(self: ^Context_Menu, item: string),

    set_items: proc(self: ^Context_Menu, items: []string),

    _items: []string,
}

New :: proc(items: []string = nil, key: Maybe(string) = nil) -> ^Context_Menu {
    n := new(Context_Menu)
    node.Init(n, key)
    n.style = _get_style
    node.Set_Style(auto_cast(n), new(node.Style))
    node.Init_Style(auto_cast(n))

    n.set_items = _set_items
    _set_items(n, items)

    n.on_free = transmute(proc(self: ^Node))_free
    n->on(events.MOUSE_DOWN_EVENT, _on_down)
    return n
}

@(private = "file")
_set_items :: proc(n: ^Context_Menu, items: []string) {
    // An open popup shows the old items by index.
    if popup.is_open(n) do popup.close()
    for item in n._items do delete(item)
    delete(n._items)
    n._items = make([]string, len(items))
    for item, i in items do n._items[i] = strings.clone(item)
}

@(private = "file")
_get_style :: proc(n: ^Context_Menu) -> ^node.Style {
    n->damage()
    return auto_cast(n._internal_style)
}

@(private = "file")
_free :: proc(n: ^Context_Menu) {
    if popup.is_open(n) do popup.close()
    for item in n._items do delete(item)
    delete(n._items)
    free(n._internal_style)
}

@(private = "file")
_picked :: proc(owner: ^Node, index: int) {
    n := cast(^Context_Menu)owner
    if index < 0 || index >= len(n._items) do return
    if n.onselect != nil do n->onselect(n._items[index])
}

@(private = "file")
_on_down :: proc(s: ^events.Event_Signal) {
    n := cast(^Context_Menu)s.current_target
    e := cast(^events.Mouse_Event)s.data
    if e.button != 1 || n.disabled do return
    popup.open(n, e.x, e.y, 160, n._items, -1, _picked)
    events.stop_propagation(s)
    events.prevent_default(s)
}
