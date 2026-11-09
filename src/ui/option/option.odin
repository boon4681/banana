package option

import "core:strings"
import "src:core/node"
import "src:ui/text_node"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Option

Option :: struct {
    using node: Node,
    style: proc(self: ^Option) -> ^node.Style,

    set_value: proc(self: ^Option, value: Maybe(string)),

    _value:     string,
    _has_value: bool,
}

New :: proc(value: Maybe(string) = nil, key: Maybe(string) = nil) -> ^Option {
    n := new(Option)
    node.Init(n, key)
    n.style = _get_style
    node.Set_Style(auto_cast(n), new(node.Style))
    node.Init_Style(auto_cast(n))
    // Never laid out where it is written: the enclosing select shows it in its popup.
    n->style()->set_display(.None)

    n.set_value = _set_value
    _set_value(n, value)
    n.on_free = transmute(proc(self: ^Node))_free
    return n
}

@(private = "file")
_set_value :: proc(n: ^Option, value: Maybe(string)) {
    delete(n._value)
    given, ok := value.?
    n._value = strings.clone(given) if ok else ""
    n._has_value = ok
    // The select that holds this option draws the label of the chosen one.
    n->damage()
}

@(private = "file")
_get_style :: proc(n: ^Option) -> ^node.Style {
    n->damage()
    return auto_cast(n._internal_style)
}

@(private = "file")
_free :: proc(n: ^Option) {
    delete(n._value)
    free(n._internal_style)
}

label :: proc(n: ^Option, allocator := context.temp_allocator) -> string {
    only: string
    count := 0
    for child in n.children {
        if child.type_id != typeid_of(text_node.Text_Node) do continue
        only = (cast(^text_node.Text_Node)child)->get_text()
        count += 1
    }
    if count <= 1 do return only

    b := strings.builder_make(allocator)
    for child in n.children {
        if child.type_id != typeid_of(text_node.Text_Node) do continue
        strings.write_string(&b, (cast(^text_node.Text_Node)child)->get_text())
    }
    return strings.to_string(b)
}

// Like HTML, an option without a `value` is worth its text.
value :: proc(n: ^Option, allocator := context.temp_allocator) -> string {
    return n._value if n._has_value else label(n, allocator)
}
