package textarea

import "core:strings"
import "core:time"
import "core:unicode/utf8"
import "src:core/events"
import "src:core/hit_test"
import im "src:core/input"
import "src:core/node"
import "src:core/painter"
import "src:core/text"
import "src:ui/shared/text_edit"
import "src:ui/text_node"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Textarea

@(private = "file") BLINK_INTERVAL :: 0.53
@(private = "file") CARET_WIDTH    :: 2

Textarea_Style :: struct {
    using base:         node.Style,
    background:         Color,
    border_color:       Color,
    border_focus_color: Color,
    border_width:       f32,
    radius:             f32,
    placeholder_color:  Color,
    selection_color:    Color,
    caret_color:        Color,
}

Textarea :: struct {
    using node: Node,
    style: proc(self: ^Textarea) -> ^Textarea_Style,

    placeholder: string, // owned
    disabled:    bool,
    readonly:    bool,
    max_length:  int, // 0 = unlimited (counted in runes)
    // When > 0, the field's height tracks this many lines each frame.
    rows: int,

    oninput:  proc(self: ^Textarea, value: string),
    onchange: proc(self: ^Textarea, value: string),

    get_value: proc(self: ^Textarea) -> string,
    set_value: proc(self: ^Textarea, v: string),
}

@(private = "file")
_Data :: struct {
    ed: text_edit.Editor,

    focused:  bool,
    dragging: bool,

    caret_visible: bool,
    blink_last:    time.Tick,

    scroll_y: f32, // px

    value_at_focus: string, // owned snapshot, for onchange

    content: ^node.Node,
    display: ^node.Node,
    text_n:  ^text_node.Text_Node,
    caret_n: ^node.Node,
}

New :: proc(placeholder: string = "", style: Textarea_Style = {}, key: Maybe(string) = nil) -> ^Textarea {
    n := new(Textarea)
    node.Init(n, key)

    st := style
    if st.background == {} do st.background = {30, 33, 42, 255}
    if st.border_color == {} do st.border_color = {58, 63, 80, 255}
    if st.border_focus_color == {} do st.border_focus_color = {88, 101, 242, 255}
    if st.border_width == 0 do st.border_width = 1
    if st.radius == 0 do st.radius = 6
    if st.placeholder_color == {} do st.placeholder_color = {130, 134, 145, 255}
    if st.selection_color == {} do st.selection_color = {70, 100, 200, 110}
    if st.caret_color == {} do st.caret_color = {230, 230, 235, 255}

    n.style = _get_style
    node.Set_Style(auto_cast(n), new_clone(st))
    node.Init_Style(auto_cast(n))
    _apply_defaults(n)

    d := new(_Data)
    text_edit.init(&d.ed, true)
    n.data = d
    n.placeholder = strings.clone(placeholder)
    n.rows = 4

    d.content = node.New("content")
    d.content->style()->set_flex_shrink(0)
    d.content.data = n
    d.content.draw = transmute(proc(self: ^Node))_draw_content

    d.display = node.New("display")
    d.display->style()->set_flex_shrink(0)

    d.text_n = text_node.New("")

    d.caret_n = node.New("caret")
    d.caret_n.data = n
    d.caret_n.draw = transmute(proc(self: ^Node))_draw_caret

    d.display->add(d.text_n)
    d.content->add(d.display, d.caret_n)
    n->add(d.content)

    n.draw = transmute(proc(self: ^Node))_draw_field
    n.process = transmute(proc(self: ^Node))_process
    n.on_free = transmute(proc(self: ^Node))_free

    n.get_value = _get_value
    n.set_value = _set_value

    n->on(events.FOCUS_EVENT, _on_focus)
    n->on(events.BLUR_EVENT, _on_blur)
    n->on(events.KEY_DOWN_EVENT, _on_key_down)
    n->on(events.TEXT_INPUT_EVENT, _on_text_input)
    n->on(events.MOUSE_DOWN_EVENT, _on_mouse_down)
    n->on(events.MOUSE_MOVE_EVENT, _on_mouse_move)
    n->on(events.MOUSE_UP_EVENT, _on_mouse_up)
    n->on(events.MOUSE_WHEEL_EVENT, _on_wheel)

    return n
}

@(private = "file")
_apply_defaults :: proc(n: ^Textarea) {
    s := n->style()
    s->set_flex_direction(.Column)
    s->set_flex_shrink(0)
    s->set_width(280)
    s->set_height(120)
    s->set_padding_x(10)
    s->set_padding_y(8)
    s->set_overflow(.Hidden)
    s->set_select_mode(.None)
    if s->get_font_size() <= 0 do s->set_font_size(14)
}

@(private = "file")
_get_style :: proc(n: ^Textarea) -> ^Textarea_Style {
    return auto_cast(n._internal_style)
}

@(private = "file")
_data :: proc(n: ^Textarea) -> ^_Data {
    return auto_cast(n.data)
}

@(private = "file")
_from_signal :: proc(s: ^events.Event_Signal) -> ^Textarea {
    return auto_cast(s.current_target)
}

@(private = "file")
_get_value :: proc(n: ^Textarea) -> string {
    return _data(n).ed.str
}

@(private = "file")
_set_value :: proc(n: ^Textarea, v: string) {
    d := _data(n)
    text_edit.set_text(&d.ed, v)
    d.scroll_y = 0
}

@(private = "file")
_metrics :: proc(n: ^Textarea) -> text_edit.Metrics {
    ts := node.Resolve_Text_Style(auto_cast n)
    size := ts.font_size if ts.font_size > 0 else 16
    lh_em: f32
    if ts.line_height > 0 {
        if ts.line_height_unit == node.percent {
            lh_em = ts.line_height
        } else {
            lh_em = ts.line_height / size
        }
    } else {
        lh_em = text.line_height(ts.font, ts.font_weight)
    }
    max_w_em: f32 = 0
    content_w := n->get_rect(.Padding).w
    if size > 0 && content_w > 0 do max_w_em = content_w / size
    return text_edit.Metrics{
        font           = ts.font,
        weight         = ts.font_weight,
        size           = size,
        line_height_em = lh_em > 0 ? lh_em : 1.2,
        max_w_em       = max_w_em,
    }
}

@(private = "file")
_reset_blink :: proc(d: ^_Data) {
    d.caret_visible = true
    d.blink_last = time.tick_now()
}

@(private = "file")
_local_point :: proc(n: ^Textarea, d: ^_Data, wx, wy: f32) -> (x, y: f32) {
    px, py := hit_test.to_local(auto_cast n, wx, wy)
    return px - d.content.rect.x, py - d.content.rect.y + d.scroll_y
}

@(private = "file")
_on_focus :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    if n.disabled do return
    d := _data(n)
    d.focused = true
    delete(d.value_at_focus)
    d.value_at_focus = strings.clone(d.ed.str)
    _reset_blink(d)
}

@(private = "file")
_on_blur :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    d := _data(n)
    d.focused = false
    d.dragging = false
    if n.onchange != nil && d.ed.str != d.value_at_focus {
        n->onchange(d.ed.str)
    }
    delete(d.value_at_focus)
    d.value_at_focus = ""
}

@(private = "file")
_on_mouse_down :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    e := cast(^events.Mouse_Event)s.data
    if n.disabled {
        events.prevent_default(s)
        return
    }
    if e.button != 0 do return
    d := _data(n)
    lx, ly := _local_point(n, d, e.x, e.y)
    text_edit.click(&d.ed, _metrics(n), lx, ly, .Shift in e.mods)
    d.dragging = true
    _reset_blink(d)
    im.capture_pointer(auto_cast n)
    events.stop_propagation(s)
}

@(private = "file")
_on_mouse_move :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    d := _data(n)
    if !d.dragging do return
    e := cast(^events.Mouse_Event)s.data
    lx, ly := _local_point(n, d, e.x, e.y)
    text_edit.click(&d.ed, _metrics(n), lx, ly, true)
    _reset_blink(d)
}

@(private = "file")
_on_mouse_up :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    d := _data(n)
    d.dragging = false
    im.release_pointer()
}

@(private = "file")
_max_scroll_y :: proc(n: ^Textarea, d: ^_Data) -> f32 {
    _, content_h := text_edit.content_extent_px(&d.ed, _metrics(n))
    viewport := n->get_rect(.Padding)
    return max(content_h - viewport.h, 0)
}

@(private = "file")
_on_wheel :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    d := _data(n)
    e := cast(^events.Wheel_Event)s.data
    max_scroll := _max_scroll_y(n, d)
    before := d.scroll_y
    d.scroll_y = clamp(d.scroll_y - e.delta_y, 0, max_scroll)
    if d.scroll_y != before {
        events.stop_propagation(s)
        events.prevent_default(s)
    }
}

@(private = "file")
_within_max_length :: proc(n: ^Textarea, d: ^_Data, added: int) -> bool {
    if n.max_length <= 0 do return true
    sel_len := 0
    if lo, hi, ok := text_edit.selection_range(&d.ed); ok do sel_len = strings.rune_count(d.ed.str[lo:hi])
    return strings.rune_count(d.ed.str) - sel_len + added <= n.max_length
}

@(private = "file")
_copy :: proc(d: ^_Data) {
    s := text_edit.selected_text(&d.ed)
    if s != "" do im.set_clipboard_text(s)
}

@(private = "file")
_on_key_down :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    d := _data(n)
    e := cast(^events.Key_Event)s.data
    ctrl := .Ctrl in e.mods || .Super in e.mods
    shift := .Shift in e.mods

    changed := false
    moved := false

    #partial switch e.code {
    case .Left:
        moved = ctrl ? text_edit.move_word_left(&d.ed, shift) : text_edit.move_left(&d.ed, shift)
    case .Right:
        moved = ctrl ? text_edit.move_word_right(&d.ed, shift) : text_edit.move_right(&d.ed, shift)
    case .Up:
        moved = text_edit.move_up(&d.ed, shift, _metrics(n))
    case .Down:
        moved = text_edit.move_down(&d.ed, shift, _metrics(n))
    case .Home:
        moved = text_edit.move_home(&d.ed, shift)
    case .End:
        moved = text_edit.move_end(&d.ed, shift)
    case .Backspace:
        if !n.readonly && !n.disabled do changed = text_edit.delete_backward(&d.ed)
    case .Delete:
        if !n.readonly && !n.disabled do changed = text_edit.delete_forward(&d.ed)
    case .A:
        if ctrl {
            text_edit.select_all(&d.ed)
            moved = true
        }
    case .C:
        if ctrl {
            _copy(d)
            events.stop_propagation(s)
            events.prevent_default(s)
        }
    case .X:
        if ctrl && !n.readonly && !n.disabled {
            _copy(d)
            changed = text_edit.delete_forward(&d.ed)
        }
    case .V:
        if ctrl && !n.readonly && !n.disabled {
            paste := im.clipboard_text()
            if paste != "" && _within_max_length(n, d, strings.rune_count(paste)) {
                changed = text_edit.insert_text(&d.ed, paste)
            }
        }
    case .Enter, .KP_Enter:
        if !n.readonly && !n.disabled && _within_max_length(n, d, 1) {
            changed = text_edit.insert_text(&d.ed, "\n")
        }
    }

    if changed {
        _reset_blink(d)
        if n.oninput != nil do n->oninput(d.ed.str)
        events.stop_propagation(s)
        events.prevent_default(s)
    } else if moved {
        _reset_blink(d)
        events.stop_propagation(s)
        events.prevent_default(s)
    }
}

@(private = "file")
_on_text_input :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    if n.readonly || n.disabled do return
    d := _data(n)
    e := cast(^events.Text_Event)s.data
    if e.codepoint < 0x20 || e.codepoint == 0x7f do return
    buf, size := utf8.encode_rune(e.codepoint)
    if !_within_max_length(n, d, 1) do return
    if text_edit.insert_text(&d.ed, string(buf[:size])) {
        _reset_blink(d)
        if n.oninput != nil do n->oninput(d.ed.str)
        events.stop_propagation(s)
    }
}

@(private = "file")
_draw_field :: proc(n: ^Textarea) {
    st := n->style()
    d := _data(n)
    p := painter.get()
    painter.rect(p, n.rect, st.background, st.radius)
    if st.border_width > 0 {
        bc := d.focused ? st.border_focus_color : st.border_color
        painter.border(p, n.rect, bc, st.border_width, st.radius)
    }
}

@(private = "file")
_draw_content :: proc(c: ^Node) {
    owner := cast(^Textarea)c.data
    d := _data(owner)
    if !text_edit.has_selection(&d.ed) do return
    st := owner->style()
    p := painter.get()
    rects := text_edit.selection_rects_px(&d.ed, _metrics(owner))
    for r in rects {
        painter.rect(p, {c.rect.x + r.x, c.rect.y + r.y, r.w, r.h}, st.selection_color)
    }
}

@(private = "file")
_draw_caret :: proc(c: ^Node) {
    owner := cast(^Textarea)c.data
    d := _data(owner)
    if !d.focused || !d.caret_visible || owner.disabled do return
    st := owner->style()
    painter.rect(painter.get(), c.rect, st.caret_color)
}

@(private = "file")
_process :: proc(n: ^Textarea) {
    d := _data(n)
    st := n->style()

    now := time.tick_now()
    if d.focused {
        if time.duration_seconds(time.tick_diff(d.blink_last, now)) >= BLINK_INTERVAL {
            d.blink_last = now
            d.caret_visible = !d.caret_visible
        }
    } else {
        d.caret_visible = false
    }

    show_placeholder := len(d.ed.str) == 0
    desired := show_placeholder ? n.placeholder : d.ed.str
    if d.text_n->get_text() != desired do d.text_n->set_text(desired)
    d.display->style()->set_color(show_placeholder ? st.placeholder_color : Color{})

    if n.rows > 0 {
        m := _metrics(n)
        line_h_px := m.line_height_em * m.size
        pt, _ := st->get_padding_top()
        pb, _ := st->get_padding_bottom()
        chrome := st->get_border_top() + st->get_border_bottom() + pt + pb
        target := f32(n.rows) * line_h_px + chrome
        cur, _ := st->get_height()
        if abs(cur - target) > 0.5 do st->set_height(target)
    }

    m := _metrics(n)
    caret_x, caret_y := text_edit.caret_xy_px(&d.ed, m)
    line_h_px := m.line_height_em * m.size

    viewport := n->get_rect(.Padding)
    if caret_y + line_h_px - d.scroll_y > viewport.h do d.scroll_y = caret_y + line_h_px - viewport.h
    if caret_y - d.scroll_y < 0 do d.scroll_y = caret_y
    d.scroll_y = clamp(d.scroll_y, 0, _max_scroll_y(n, d))
    d.content.transform.translate = {0, -d.scroll_y}

    d.caret_n.rect = {
        d.content.rect.x + caret_x,
        d.content.rect.y + caret_y,
        CARET_WIDTH,
        max(line_h_px, 1),
    }
}

@(private = "file")
_free :: proc(n: ^Textarea) {
    d := _data(n)
    text_edit.destroy(&d.ed)
    delete(d.value_at_focus)
    delete(n.placeholder)
    free(d)
    free(n._internal_style)
}
