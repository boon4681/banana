package text_input

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"
import "src:core/common"
import "src:core/events"
import "src:core/hit_test"
import im "src:core/input"
import "src:core/node"
import "src:core/painter"
import "src:core/platform"
import "src:core/text"
import "src:ui/shared/text_edit"
import "src:ui/text_node"
import YG "src:yoga"

BANANA_COMPONENT      :: true
BANANA_COMPONENT_TYPE :: ^Input

@(private = "file") BLINK_INTERVAL :: 0.53
@(private = "file") CARET_WIDTH    :: 2

Input_Style :: struct {
    using base:         node.Style,
    border_focus_color: Color,
    placeholder_color:  Color,
    selection_color:    Color,
    caret_color:        Color,
}

Input_Type :: enum {
    Text,
    File,
}

File :: platform.Dialog_File

Input :: struct {
    using node: Node,
    style: proc(self: ^Input) -> ^Input_Style,

    type:        Input_Type,
    placeholder: string, // owned
    disabled:    bool,
    readonly:    bool,
    max_length:  int, // 0 = unlimited (counted in runes)
    accept:      string,
    multiple:    bool,
    directory:   bool,

    // fire on every edit, with the current value.
    oninput: proc(self: ^Input, value: string),
    // fire on blur, only if the value changed since focus.
    onchange: proc(self: ^Input, value: string),
    // fire when Enter is pressed.
    onenter: proc(self: ^Input, value: string),

    get_value: proc(self: ^Input) -> string,
    set_value: proc(self: ^Input, v: string),
    set_placeholder: proc(self: ^Input, v: string),
    get_files: proc(self: ^Input) -> []File,
}

@(private = "file")
_Picker :: struct {
    input: ^Input,
}

@(private = "file")
_Data :: struct {
    ed: text_edit.Editor,

    focused:  bool,
    dragging: bool,

    caret_visible: bool,
    blink_last:    time.Tick,

    scroll_x: f32, // px
    line_h:   f32, // px
    // What `display` was last given, so the color is only set when it changes.
    display_color: Maybe(Color),
    // Layout resets the caret node's rect every tick, so the last one given is kept here.
    caret_rect: common.Rect,

    value_at_focus: string, // owned snapshot, for onchange

    content: ^node.Node,
    display: ^node.Node,
    text_n:  ^text_node.Text_Node,
    caret_n: ^node.Node,

    applied_type: Input_Type,
    file_button:  ^node.Node,
    files:        []File, // owned
    picker:       ^_Picker,
}

New :: proc(placeholder: string = "", style: Input_Style = {}, key: Maybe(string) = nil) -> ^Input {
    n := new(Input)
    node.Init(n, key)

    st := style
    if st.background == {} do st.background = {30, 33, 42, 255}
    if st.border_color == {} do st.border_color = Color{58, 63, 80, 255}
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
    text_edit.init(&d.ed, false)
    n.data = d
    n.placeholder = strings.clone(placeholder)

    d.content = node.New("content")
    d.content->style()->set_flex_shrink(0)->set_flex_direction(.Row)
    YG.NodeStyleSetOverflow(d.content.raw, .Scroll)
    d.content.data = n
    d.content.draw = transmute(proc(self: ^Node))_draw_content

    d.display = node.New("display")
    d.display->style()->set_flex_shrink(0)
    (cast(^node.Style)d.display._internal_style).text.align = .Left

    d.text_n = text_node.New(placeholder)

    d.caret_n = node.New("caret")
    d.caret_n.data = n
    d.caret_n.draw = transmute(proc(self: ^Node))_draw_caret

    d.file_button = node.New("file_button")
    d.file_button->style()->set_display(.None)->set_flex_shrink(0)->set_padding_inline(8)->set_padding_block(2)->set_margin_right(8)
    d.file_button.draw = _draw_file_button
    d.file_button->add(text_node.New("Choose file"))

    d.display->add(d.text_n)
    d.content->add(d.display, d.caret_n)
    n->add(d.file_button, d.content)

    n.draw = transmute(proc(self: ^Node))_draw_input
    n.process = transmute(proc(self: ^Node))_process
    n.on_free = transmute(proc(self: ^Node))_free

    n.get_value = _get_value
    n.set_value = _set_value
    n.set_placeholder = _set_placeholder
    n.get_files = _get_files

    n.focusable, n.text_entry = true, true
    n->on(events.FOCUS_EVENT, _on_focus)
    n->on(events.BLUR_EVENT, _on_blur)
    n->on(events.KEY_DOWN_EVENT, _on_key_down)
    n->on(events.TEXT_INPUT_EVENT, _on_text_input)
    n->on(events.MOUSE_DOWN_EVENT, _on_mouse_down)
    n->on(events.MOUSE_MOVE_EVENT, _on_mouse_move)
    n->on(events.MOUSE_UP_EVENT, _on_mouse_up)

    return n
}

@(private = "file")
_apply_defaults :: proc(n: ^Input) {
    s := n->style()
    s->set_flex_direction(.Row)
    s->set_align_items(.Center)
    s->set_flex_shrink(0)
    s->set_width(200)
    s->set_max_width(100, node.percent)
    s->set_padding_inline(10)
    s->set_padding_block(6)
    s->set_overflow(.Hidden)
    s->set_user_select(.None)
    if s->get_font_size() <= 0 do s->set_font_size(14)
}

@(private = "file")
_get_style :: proc(n: ^Input) -> ^Input_Style {
    n->damage()
    return auto_cast(n._internal_style)
}

@(private = "file")
_data :: proc(n: ^Input) -> ^_Data {
    return auto_cast(n.data)
}

@(private = "file")
_from_signal :: proc(s: ^events.Event_Signal) -> ^Input {
    return auto_cast(s.current_target)
}

@(private = "file")
_get_value :: proc(n: ^Input) -> string {
    return _data(n).ed.str
}

@(private = "file")
_set_value :: proc(n: ^Input, v: string) {
    if n.type == .File do return
    d := _data(n)
    text_edit.set_text(&d.ed, v)
    d.scroll_x = 0
    n->damage()
}

@(private = "file")
_metrics :: proc(n: ^Input, max_w_em: f32 = 0) -> text_edit.Metrics {
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
_local_point :: proc(n: ^Input, d: ^_Data, wx, wy: f32) -> (x, y: f32) {
    px, py := hit_test.to_local(auto_cast n, wx, wy)
    return px - d.content.rect.x + d.scroll_x, py - d.content.rect.y
}

@(private = "file")
_on_focus :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    if n.disabled do return
    d := _data(n)
    // The border and the caret are drawn from this, with no style in between.
    n->damage()
    d.focused = true
    delete(d.value_at_focus)
    d.value_at_focus = strings.clone(d.ed.str)
    _reset_blink(d)
}

@(private = "file")
_on_blur :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    d := _data(n)
    n->damage()
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
    if n.type == .File {
        _open_picker(n)
        events.stop_propagation(s)
        return
    }
    d := _data(n)
    lx, ly := _local_point(n, d, e.x, e.y)
    n->damage()
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
    n->damage()
}

@(private = "file")
_on_mouse_up :: proc(s: ^events.Event_Signal) {
    n := _from_signal(s)
    d := _data(n)
    d.dragging = false
    im.release_pointer()
}

@(private = "file")
_within_max_length :: proc(n: ^Input, d: ^_Data, added: int) -> bool {
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
    if n.type == .File {
        #partial switch e.code {
        case .Enter, .KP_Enter, .Space:
            if !n.disabled do _open_picker(n)
            events.stop_propagation(s)
            events.prevent_default(s)
        }
        return
    }
    ctrl := .Ctrl in e.mods || .Super in e.mods
    shift := .Shift in e.mods

    changed := false
    moved := false

    #partial switch e.code {
    case .Left:
        moved = ctrl ? text_edit.move_word_left(&d.ed, shift) : text_edit.move_left(&d.ed, shift)
    case .Right:
        moved = ctrl ? text_edit.move_word_right(&d.ed, shift) : text_edit.move_right(&d.ed, shift)
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
        if n.onenter != nil do n->onenter(d.ed.str)
        events.prevent_default(s)
    }

    // The selection and the caret are drawn from the editor, which the keys above just changed.
    if changed || moved do n->damage()
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
    if n.readonly || n.disabled || n.type == .File do return
    d := _data(n)
    e := cast(^events.Text_Event)s.data
    if e.codepoint < 0x20 || e.codepoint == 0x7f do return
    buf, size := utf8.encode_rune(e.codepoint)
    if !_within_max_length(n, d, 1) do return
    if text_edit.insert_text(&d.ed, string(buf[:size])) {
        n->damage()
        _reset_blink(d)
        if n.oninput != nil do n->oninput(d.ed.str)
        events.stop_propagation(s)
    }
}

@(private = "file")
_draw_input :: proc(n: ^Input) {
    st := n->style()
    d := _data(n)
    p := painter.get()
    radius := node.Resolve_Corner_Radius(n)
    painter.decoration_under(p, n.rect, radius, st.decoration)
    painter.rect(p, n.rect, st.background, radius)
    painter.decoration_fill(p, n.rect, radius, st.decoration)
    edge := st.border_color
    if d.focused && st.border_focus_color != {} do edge = st.border_focus_color
    painter.border_sides(p, n.rect, edge, st.border_width, radius)
    painter.decoration_over(p, n.rect, radius, st.decoration)
}

@(private = "file")
_draw_content :: proc(c: ^Node) {
    owner := cast(^Input)c.data
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
    owner := cast(^Input)c.data
    d := _data(owner)
    if !d.focused || !d.caret_visible || owner.disabled || owner.type == .File do return
    st := owner->style()
    painter.rect(painter.get(), c.rect, st.caret_color)
}

@(private = "file")
_process :: proc(n: ^Input) {
    d := _data(n)
    // Runs every tick: reading through style() would paint every frame.
    st := cast(^Input_Style)n._internal_style

    now := time.tick_now()
    caret_shown := d.caret_visible
    if d.focused {
        if time.duration_seconds(time.tick_diff(d.blink_last, now)) >= BLINK_INTERVAL {
            d.blink_last = now
            d.caret_visible = !d.caret_visible
        }
    } else {
        d.caret_visible = false
    }
    if d.caret_visible != caret_shown do n->damage()

    if n.type != d.applied_type do _apply_type(n, d)

    show_placeholder := n.type == .Text && len(d.ed.str) == 0
    desired := show_placeholder ? n.placeholder : d.ed.str
    if n.type == .File do desired = _file_label(d)
    if d.text_n->get_text() != desired do d.text_n->set_text(desired)
    color := show_placeholder ? st.placeholder_color : Color{}
    if shown, set := d.display_color.?; !set || shown != color {
        d.display_color = color
        d.display->style()->set_color(color)
    }

    m := _metrics(n)
    caret_x, caret_y := text_edit.caret_xy_px(&d.ed, m)
    line_h_px := m.line_height_em * m.size
    if d.line_h != line_h_px {
        d.line_h = line_h_px
        d.content->style()->set_min_height(line_h_px)
    }

    viewport := n->get_rect(.Padding)
    if caret_x - d.scroll_x > viewport.w do d.scroll_x = caret_x - viewport.w
    if caret_x - d.scroll_x < 0 do d.scroll_x = caret_x
    d.scroll_x = max(d.scroll_x, 0)
    shift := [2]f32{-d.scroll_x, 0}
    caret := common.Rect{
        d.content.rect.x + caret_x,
        d.content.rect.y + caret_y,
        CARET_WIDTH,
        max(line_h_px, 1),
    }
    content := cast(^node.Style)d.content._internal_style
    if content.transform.translate != shift || d.caret_rect != caret do n->damage()
    d.caret_rect = caret
    content.transform.translate = shift
    d.caret_n.rect = caret
}

@(private = "file")
_apply_type :: proc(n: ^Input, d: ^_Data) {
    d.applied_type = n.type
    file := n.type == .File
    n.text_entry = !file
    d.file_button->style()->set_display(file ? .Flex : .None)
    n->style()->set_cursor(file ? .Default : .Text)
    text_edit.set_text(&d.ed, "")
    d.scroll_x = 0
}

@(private = "file")
_file_label :: proc(d: ^_Data) -> string {
    switch len(d.files) {
    case 0: return "No file chosen"
    case 1: return d.files[0].name
    }
    return fmt.tprintf("%d files", len(d.files))
}

@(private = "file")
_draw_file_button :: proc(c: ^Node) {
    painter.rect(painter.get(), c.rect, Color{58, 63, 80, 255}, 4)
}

@(private = "file")
_get_files :: proc(n: ^Input) -> []File {
    return _data(n).files
}

@(private = "file")
_open_picker :: proc(n: ^Input) {
    d := _data(n)
    if d.picker != nil do return
    ctx := im.get_context()
    if ctx == nil || ctx.window_target == nil do return

    extensions := make([dynamic]string, context.temp_allocator)
    accept := n.accept
    for part in strings.split_iterator(&accept, ",") {
        ext := strings.trim_space(part)
        if len(ext) > 1 && ext[0] == '.' do append(&extensions, ext[1:])
    }
    filters: []platform.File_Filter
    if len(extensions) > 0 {
        filters = make([]platform.File_Filter, 1, context.temp_allocator)
        filters[0] = {name = n.accept, extensions = extensions[:]}
    }

    d.picker = new(_Picker)
    d.picker.input = n
    platform.file_dialog(cast(^platform.Window)ctx.window_target, {
        mode     = .Open_Folder if n.directory else .Open,
        multiple = n.multiple,
        filters  = filters,
    }, _on_picked, d.picker)
}

@(private = "file")
_on_picked :: proc(w: ^platform.Window, files: []platform.Dialog_File, user: rawptr) {
    picker := cast(^_Picker)user
    defer free(picker)
    n := picker.input
    if n == nil do return
    d := _data(n)
    d.picker = nil
    if len(files) == 0 do return

    _delete_files(d)
    d.files = make([]File, len(files))
    for f, i in files {
        d.files[i] = {
            path = strings.clone(f.path),
            name = strings.clone(f.name),
            data = slice.clone(f.data) if len(f.data) > 0 else nil,
        }
    }
    n->damage()
    if n.onchange != nil do n->onchange("")
}

@(private = "file")
_delete_files :: proc(d: ^_Data) {
    for f in d.files {
        delete(f.path)
        delete(f.name)
        delete(f.data)
    }
    delete(d.files)
    d.files = nil
}

@(private = "file")
_free :: proc(n: ^Input) {
    d := _data(n)
    // a web picker answers later; its callback frees the picker
    if d.picker != nil do d.picker.input = nil
    _delete_files(d)
    text_edit.destroy(&d.ed)
    delete(d.value_at_focus)
    delete(n.placeholder)
    free(d)
    free(n._internal_style)
}

@(private = "file")
_set_placeholder :: proc(n: ^Input, v: string) {
    delete(n.placeholder)
    n.placeholder = strings.clone(v)
    n->damage()
}
