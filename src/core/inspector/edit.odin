#+build !js
package inspector

import "base:intrinsics"
import "core:strconv"
import "core:strings"
import "core:sync"
import "src:core/events"
import "src:core/hit_test"
import core_input "src:core/input"
import "src:core/node"
import "src:core/platform"
import "src:ui/box"
import ui_input "src:ui/input"
import "src:ui/text_node"

Command_Kind :: enum u8 { Text, Style }

Command :: struct {
    kind:  Command_Kind,
    id:    Node_Id,
    prop:  Prop_Key,
    value: string,
}

Editor :: struct {
    row:      ^box.Box,
    name:     Label,
    field:    ^ui_input.Input,
    active:   bool,
    kind:     Command_Kind,
    prop:     Prop_Key,
    target:   Node_Id,
    text_id:  Node_Id,
}

// Panel thread: asks the app thread to change a node.
push_command :: proc(insp: ^Inspector, command: Command) {
    queued := command
    queued.value = strings.clone(command.value)
    sync.lock(&insp.mu)
    append(&insp.commands, queued)
    sync.unlock(&insp.mu)
}

// App thread.
run_commands :: proc(insp: ^Inspector) {
    sync.lock(&insp.mu)
    pending := insp.commands
    insp.commands = nil
    sync.unlock(&insp.mu)
    if len(pending) == 0 do return

    for command in pending {
        target := _resolve(insp.app.root, insp.overlay.root, command.id)
        if target != nil {
            switch command.kind {
            case .Text:
                if target.type_id == typeid_of(text_node.Text_Node) {
                    text := cast(^text_node.Text_Node)target
                    text->set_text(command.value)
                }
            case .Style:
                apply_style(target, command.prop, command.value)
            }
        }
        delete(command.value)
    }
    delete(pending)
    hit_test.invalidate()
    intrinsics.atomic_store(&insp.want_snapshot, 1)
}

input_field :: proc(placeholder: string, key: string) -> ^ui_input.Input {
    field := ui_input.New(placeholder, {
        background         = BG,
        border_color       = LINE,
        border_focus_color = ACCENT,
        border_width       = 1,
        radius             = 3,
        placeholder_color  = TEXT_FAINT,
        caret_color        = TEXT,
    }, key)
    field->style()->
        set_height(20)->
        set_padding_inline(6)->
        set_padding_block(0)->
        set_font_size(FONT_SIZE)->
        set_color(TEXT)
    return field
}

focus_node :: proc(w: ^platform.Window, target: ^node.BaseNode) {
    im := &w.input
    if im.focused == target do return
    ev := events.Mouse_Event{}
    if im.focused != nil do core_input.dispatch(im.focused, events.BLUR_EVENT, &ev)
    im.focused = target
    if target != nil do core_input.dispatch(target, events.FOCUS_EVENT, &ev)
}

editor_build :: proc(e: ^Editor) -> ^box.Box {
    e.row = row_box("edit")
    e.row->style()->
        set_width(100, node.percent)->
        set_padding_left(10)->
        set_padding_right(SCROLLBAR_GUTTER)->
        set_padding_block(3)->
        set_gap(8)->
        set_display(.None)
    e.row->style().background = ROW_SELECT
    e.name = label("", ACCENT, FONT_SIZE)
    e.field = input_field("value, then Enter", "edit-value")
    e.field->style()->set_flex_grow(1)->set_flex_shrink(1)->set_width(0, node.auto)
    e.field.onenter = _edit_commit
    e.row->add(e.name.root, e.field)
    return e.row
}

editor_begin :: proc(p: ^Panel, kind: Command_Kind, prop: Prop_Key, target: Node_Id, current: string) {
    e := &p.styles.editor
    if target == 0 do return
    e.active, e.kind, e.prop, e.target = true, kind, prop, target
    label_set(e.name, "text" if kind == .Text else PROP_NAMES[prop])
    e.field->set_value("" if current == "-" else current)
    e.row->style()->set_display(.Flex)
    focus_node(p.win, e.field)
}

editor_end :: proc(p: ^Panel) {
    e := &p.styles.editor
    if !e.active do return
    e.active = false
    e.row->style()->set_display(.None)
    if p.win.input.focused == cast(^node.BaseNode)e.field do focus_node(p.win, nil)
}

@(private = "file")
_edit_commit :: proc(self: ^ui_input.Input, value: string) {
    p := _panel
    if p == nil || !p.styles.editor.active do return
    e := &p.styles.editor
    push_command(p.insp, {kind = e.kind, id = e.target, prop = e.prop, value = value})
    editor_end(p)
}

prop_row_click :: proc(s: ^events.Event_Signal) {
    p := _panel
    row := cast(^node.BaseNode)s.current_target
    if p == nil || row == nil || p.selected == 0 do return
    for key in Prop_Key {
        if cast(^node.BaseNode)p.styles.props[key].root != row || key == .Clip do continue
        editor_begin(p, .Style, key, p.selected, p.styles.props[key].value.text->get_text())
        return
    }
}

@(private = "file")
_length :: proc(text: string) -> (value: f32, unit: node.unit, ok: bool) {
    if text == "auto" do return 0, node.auto, true
    number := text
    unit = node.px
    if strings.has_suffix(number, "%") {
        number, unit = number[:len(number) - 1], node.percent
    } else if strings.has_suffix(number, "px") {
        number = number[:len(number) - 2]
    }
    value, ok = strconv.parse_f32(strings.trim_space(number))
    return
}

@(private = "file")
_color :: proc(text: string) -> (c: Color, ok: bool) {
    if strings.has_prefix(text, "#") {
        hex := text[1:]
        if len(hex) != 6 && len(hex) != 8 do return {}, false
        c.a = 255
        for i in 0 ..< len(hex) / 2 {
            part := strconv.parse_uint(hex[i * 2:][:2], 16) or_return
            c[i] = u8(part)
        }
        return c, true
    }
    parts := strings.fields(text, context.temp_allocator)
    if len(parts) != 3 && len(parts) != 4 do return {}, false
    c.a = 255
    for part, i in parts {
        channel := strconv.parse_uint(part, 10) or_return
        c[i] = u8(min(channel, 255))
    }
    return c, true
}

apply_style :: proc(n: ^node.BaseNode, key: Prop_Key, input: string) -> bool {
    if n == nil || n._internal_style == nil do return false
    st := cast(^node.Style)n._internal_style
    text := strings.trim_space(input)
    if slash := strings.index_byte(text, '/'); slash >= 0 do text = strings.trim_space(text[:slash])
    number, numeric := strconv.parse_f32(text)

    switch key {
    case .Display:         st->set_display(css_keyword(node.Display, text) or_return)
    case .Position:        st->set_position(css_keyword(node.Position, text) or_return)
    case .Flex_Direction:  st->set_flex_direction(css_keyword(node.FlexDirection, text) or_return)
    case .Flex_Wrap:       st->set_flex_wrap(css_keyword(node.Wrap, text) or_return)
    case .Justify_Content: st->set_justify_content(css_keyword(node.Justify, text) or_return)
    case .Align_Items:     st->set_align_items(css_keyword(node.Align, text) or_return)
    case .Align_Self:      st->set_align_self(css_keyword(node.Align, text) or_return)
    case .Align_Content:   st->set_align_content(css_keyword(node.Align, text) or_return)
    case .Box_Sizing:      st->set_box_sizing(css_keyword(node.BoxSizing, text) or_return)
    case .Overflow:        st->set_overflow(css_keyword(node.Overflow, text) or_return)
    case .Pointer_Events:  st->set_pointer_events(css_keyword(node.Pointer_Events, text) or_return)
    case .User_Select:     st->set_user_select(css_keyword(node.User_Select, text) or_return)
    case .Flex_Grow:       if !numeric do return false; st->set_flex_grow(number)
    case .Flex_Shrink:     if !numeric do return false; st->set_flex_shrink(number)
    case .Aspect_Ratio:    if !numeric do return false; st->set_aspect_ratio(number)
    case .Gap:             if !numeric do return false; st->set_gap(number)
    case .Z_Index:         if !numeric do return false; st->set_z_index(i32(number))
    case .Font_Size:       if !numeric do return false; st->set_font_size(number)
    case .Font_Weight:     if !numeric do return false; st->set_font_weight(node.FontWeight(int(number)))
    case .Color:           st->set_color(_color(text) or_return)
    case .Flex_Basis:      v, u := _length(text) or_return; st->set_flex_basis(v, u)
    case .Width:           v, u := _length(text) or_return; st->set_width(v, u)
    case .Height:          v, u := _length(text) or_return; st->set_height(v, u)
    case .Min_Width:       v, u := _length(text) or_return; st->set_min_width(v, u)
    case .Min_Height:      v, u := _length(text) or_return; st->set_min_height(v, u)
    case .Max_Width:       v, u := _length(text) or_return; st->set_max_width(v, u)
    case .Max_Height:      v, u := _length(text) or_return; st->set_max_height(v, u)
    case .Line_Height:     v, u := _length(text) or_return; st->set_line_height(v, u)
    case .Clip:            return false
    }
    return true
}
