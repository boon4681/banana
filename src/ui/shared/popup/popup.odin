package popup

import "src:core/common"
import "src:core/events"
import "src:core/node"
import "src:ui/box"
import "src:ui/shared/theme"
import "src:ui/text_node"

Node :: node.BaseNode

Pick :: proc(owner: ^Node, index: int)

@(private = "file")
_State :: struct {
    menu:   ^box.Box,
    root:   ^Node,
    owner:  ^Node,
    pick:   Pick,
    guard:  uint,
    keys:   uint,
    active: int,
}

// Thread-local: the inspector runs a second UI on its own thread.
@(private = "file", thread_local)
_open: _State

is_open :: proc(owner: ^Node) -> bool {
    return _open.menu != nil && _open.owner == owner
}

open :: proc(owner: ^Node, x, y, min_width: f32, labels: []string, selected: int, pick: Pick, anchor: f32 = 0) {
    close()
    if owner == nil || len(labels) == 0 do return
    root := owner
    for root.parent != nil do root = root.parent

    menu := box.New({
        background   = theme.POPOVER,
        border_color = theme.BORDER,
        border_width = 1,
        radius       = theme.RADIUS,
    }, "popup")
    shadows := new([1]common.EffectShadow)
    shadows^ = {{x = 0, y = 4, blur = 12, spread = 0, color = {0, 0, 0, 0.35}}}
    menu->style().decoration = {shadows = shadows[:], alpha = 1}
    menu.data = shadows
    menu->style()->
        set_position(.Absolute)->
        set_flex_direction(.Column)->
        set_flex_wrap(.NoWrap)->
        set_align_items(.Stretch)->
        set_padding(4)->
        set_min_width(max(min_width, 128))->
        set_color(theme.FOREGROUND)->
        set_font_size(14)->
        set_user_select(.None)->
        set_z_index(1000)

    height := f32(len(labels)) * 30 + 10
    left := clamp(x, 4, max(4, root.rect.w - max(min_width, 128) - 4))
    top := y
    if top + height > root.rect.h - 4 {
        above := y - anchor - height
        top = above if anchor > 0 && above >= 4 else max(4, root.rect.h - height - 4)
    }
    menu->style()->set_left(left)->set_top(top)

    for label, index in labels {
        item := box.New({radius = 4, background = theme.ACCENT if index == selected else common.Color{}}, "item")
        item->style()->set_height(30)->set_padding_inline(8)->set_align_items(.Center)->set_flex_wrap(.NoWrap)->set_flex_shrink(0)
        item.data = new_clone(index)
        item->add(text_node.New(label))
        item->on(events.MOUSE_ENTER_EVENT, _item_enter)
        item->on(events.MOUSE_LEAVE_EVENT, _item_leave)
        item->on(events.MOUSE_DOWN_EVENT, _item_down)
        menu->add(item)
    }

    root->add(menu)
    _open = {menu = menu, root = root, owner = owner, pick = pick, active = selected}
    _open.guard = root->on(events.MOUSE_DOWN_EVENT, _outside_down, true)
    _open.keys = root->on(events.KEY_DOWN_EVENT, _key_down, true)
}

close :: proc() {
    state := _open
    if state.menu == nil do return
    _open = {}
    state.root->off(events.MOUSE_DOWN_EVENT, _outside_down)
    state.root->off(events.KEY_DOWN_EVENT, _key_down)
    state.root->remove(state.menu)
    if state.menu.awaken {
        state.menu->queue_free()
    } else {
        state.menu->free()
    }
}

@(private = "file")
_index :: proc(s: ^events.Event_Signal) -> (^box.Box, int) {
    item := cast(^box.Box)s.current_target
    return item, (cast(^int)item.data)^
}

@(private = "file")
_item_enter :: proc(s: ^events.Event_Signal) {
    _, index := _index(s)
    _activate(index)
}

@(private = "file")
_item_leave :: proc(s: ^events.Event_Signal) {
    _activate(-1)
}

@(private = "file")
_activate :: proc(index: int) {
    _open.active = index
    for child, i in _open.menu.children {
        (cast(^box.Box)child)->style().background = theme.ACCENT if i == index else common.Color{}
    }
}

@(private = "file")
_choose :: proc(index: int) {
    owner, pick := _open.owner, _open.pick
    close()
    if pick != nil do pick(owner, index)
}

@(private = "file")
_item_down :: proc(s: ^events.Event_Signal) {
    _, index := _index(s)
    events.stop_propagation(s)
    events.prevent_default(s)
    _choose(index)
}

@(private = "file")
_outside_down :: proc(s: ^events.Event_Signal) {
    if _open.menu == nil do return
    for at := cast(^Node)s.target; at != nil; at = at.parent {
        if at == cast(^Node)_open.menu do return
    }
    close()
}

@(private = "file")
_key_down :: proc(s: ^events.Event_Signal) {
    e := cast(^events.Key_Event)s.data
    if _open.menu == nil do return
    count := len(_open.menu.children)
    #partial switch e.code {
    case .Escape: close()
    case .Down: _activate((_open.active + 1) % count)
    case .Up: _activate((_open.active + count - 1) % count if _open.active >= 0 else count - 1)
    case .Home: _activate(0)
    case .End: _activate(count - 1)
    case .Enter, .Space:
        if _open.active < 0 {
            close()
        } else {
            _choose(_open.active)
        }
    case .Tab: close(); return
    case: return
    }
    events.stop_propagation(s)
    events.prevent_default(s)
}
