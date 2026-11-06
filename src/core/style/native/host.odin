package style_native

import "base:runtime"
import "core:math"
import "core:slice"
import "core:strings"
import style ".."
import "src:core/node"
import "src:core/common"
import "src:core/text"
import "src:core/input"
import "src:core/hit_test"
import "src:core/scroll"
import YG "src:yoga"

Host :: struct {
    engine: ^style.Engine,
    input: ^input.Input_State, // optional, must outlive the Host
    allocator: runtime.Allocator,
    bindings: map[style.Node_Id]^Binding,
    handles: map[^node.BaseNode]style.Node_Id,
    fonts: map[string]^text.Font_Set, // key is the lowercase family name. we dont own these so they must outlive the Host
    loaded: map[string]^text.Font_Set, // families loaded from @font-face, we own these
    sources: map[string]bool, // key is "family|source" so the same face dont load twice
    font_generation: u64,
    metrics: map[Metric_Key][2]f32,
    reapply: bool,
    next_id: u64,
    scale: f32,
}
@(private)
Metric_Key :: struct { font: ^text.Font_Set, weight: u16 }
// nil if no rule target that pseudo. only valid inside the call, dont keep it
Pseudo_Styles :: [style.Pseudo_Element]^style.Computed_Style
// paint only what the component has, apply_node already did the box
// multiply your colors by alpha, it's the opacity and it's 0 when hidden
Paint_Proc :: proc(n: ^node.BaseNode, c: style.Computed_Style, alpha: f32, pseudo: Pseudo_Styles)
// dom event names the host dispatch for transitions and animations
// the event data is a ^style.Motion_Event, only valid during the dispatch
MOTION_EVENT_TYPES :: [style.Motion_Event_Kind]string{
    .Transition_Run = "transitionrun", .Transition_Start = "transitionstart", .Transition_End = "transitionend", .Transition_Cancel = "transitioncancel",
    .Animation_Start = "animationstart", .Animation_Iteration = "animationiteration", .Animation_End = "animationend", .Animation_Cancel = "animationcancel",
}
// states only the component know, like :disabled and :checked
States_Proc :: proc(n: ^node.BaseNode) -> style.State_Set
Binding :: struct {
    node: ^node.BaseNode,
    paint: Paint_Proc,
    component_states: States_Proc,
    alpha: f32,
    restyled: bool,
    font: ^text.Font_Set,
    basis: Basis,
    calc, transformed, fixed: bool,
    fixed_offsets: [4]f32,
    parent_display: style.Keyword,
    grid, grid_stale, grid_settled: bool,
    grid_size: [2]f32,
    tag, id, class_text: string,
    classes: []string,
    attributes: map[string]string,
    states, input_states: style.State_Set,
    has_text, text_content: bool,
    class_present, id_present: bool,
    parent, previous: style.Node_Id,
}

create_host :: proc(input_state: ^input.Input_State = nil, allocator := context.allocator) -> ^Host {
    context.allocator = allocator
    h := new(Host)
    h.allocator = allocator; h.input = input_state
    h.bindings = make(map[style.Node_Id]^Binding)
    h.handles = make(map[^node.BaseNode]style.Node_Id)
    h.fonts = make(map[string]^text.Font_Set)
    h.loaded = make(map[string]^text.Font_Set)
    h.sources = make(map[string]bool)
    h.metrics = make(map[Metric_Key][2]f32)
    h.engine = style.create({
        data = h,
        parent = proc(d: rawptr, id: style.Node_Id) -> style.Node_Id { return (cast(^Host)d).bindings[id].parent },
        previous_sibling = proc(d: rawptr, id: style.Node_Id) -> style.Node_Id { return (cast(^Host)d).bindings[id].previous },
        tag = proc(d: rawptr, id: style.Node_Id) -> string { return (cast(^Host)d).bindings[id].tag },
        id = proc(d: rawptr, id: style.Node_Id) -> string { return (cast(^Host)d).bindings[id].id },
        classes = proc(d: rawptr, id: style.Node_Id) -> []string { return (cast(^Host)d).bindings[id].classes },
        states = proc(d: rawptr, id: style.Node_Id) -> style.State_Set { b := (cast(^Host)d).bindings[id]; return b.states | b.input_states },
        has_text = proc(d: rawptr, id: style.Node_Id) -> bool { b := (cast(^Host)d).bindings[id]; return b.has_text || b.text_content },
        attribute = proc(d: rawptr, id: style.Node_Id, name: string) -> (string, bool) {
            b := (cast(^Host)d).bindings[id]
            if name == "class" { return b.class_text, b.class_present }
            if name == "id" { return b.id, b.id_present }
            value, present := b.attributes[name]
            return value, present
        },
    }, allocator)
    style.set_font_metrics(h.engine, font_metrics, h)
    return h
}

@(private)
free_binding :: proc(b: ^Binding) {
    delete(b.tag); delete(b.id); delete(b.classes); delete(b.class_text)
    for k, v in b.attributes { delete(k); delete(v) }
    delete(b.attributes); free(b)
}
destroy_host :: proc(h: ^Host) {
    if h == nil { return }
    context.allocator = h.allocator
    for _, b in h.bindings {
        b.node->remove_hook(.Before_Free, before_free, h)
        free_binding(b)
    }
    style.destroy(h.engine)
    for name in h.fonts { delete(name) }
    for name, set in h.loaded { delete(name); text.set_destroy(set) }
    for key in h.sources { delete(key) }
    delete(h.bindings); delete(h.handles); delete(h.fonts); delete(h.loaded); delete(h.sources); delete(h.metrics); free(h)
}
// give the x-height and the "0" advance as a ratio of font size
@(private)
font_metrics :: proc(data: rawptr, id: style.Node_Id, families: []string, weight: f32) -> (ex, ch: f32) {
    h := cast(^Host)data
    font: ^text.Font_Set
    for name in families {
        if found, ok := h.fonts[strings.to_lower(name, context.temp_allocator)]; ok { font = found; break }
    }
    if b, bound := h.bindings[id]; font == nil && bound { font = node.Resolve_Text_Style(b.node).font }
    if font == nil { return 0.5, 0.5 }
    key := Metric_Key{font, u16(weight)}
    if cached, ok := h.metrics[key]; ok { return cached[0], cached[1] }
    measured := [2]f32{0.5, 0.5}
    shaped := text.shape(font, "x 0", text.FontWeight(weight), context.temp_allocator)
    if len(shaped.words) == 2 && len(shaped.words[0].glyphs) > 0 {
        g := shaped.words[0].glyphs[0]
        if height := text.glyph(g.face, g.gid, g.embold).max.y; height > 0 { measured[0] = height }
        if shaped.words[1].width > 0 { measured[1] = shaped.words[1].width }
    }
    h.metrics[key] = measured
    return measured[0], measured[1]
}
// load the @font-face sources the sheets declare and make their families usable
// a face that fail to load just get skipped, not an error
@(private)
load_font_faces :: proc(h: ^Host) {
    if h.font_generation == h.engine.font_face_generation { return }
    h.font_generation = h.engine.font_face_generation
    context.allocator = h.allocator
    for face in style.font_faces(h.engine) {
        key := strings.concatenate({face.family, "|", face.source})
        if key in h.sources { delete(key); continue }
        h.sources[key] = true
        family := strings.to_lower(face.family, context.temp_allocator)
        set, known := h.loaded[family]
        if !known {
            set = text.set_create()
            h.loaded[strings.clone(family)] = set
        }
        text.load_font(set, face.source)
        if len(set.faces) > 0 { register_font(h, face.family, set) }
    }
    clear(&h.metrics)
}
// make `font-family: name` pick this font, names match case-insensitive
register_font :: proc(h: ^Host, name: string, font: ^text.Font_Set) {
    context.allocator = h.allocator
    key := strings.to_lower(name)
    if _, known := h.fonts[key]; known {
        h.fonts[key] = font
        delete(key)
    } else { h.fonts[key] = font }
    h.reapply = true
}
@(private)
find_font :: proc(h: ^Host, v: style.Value) -> ^text.Font_Set {
    for name in style.family(h.engine, v) {
        if font, ok := h.fonts[strings.to_lower(name, context.temp_allocator)]; ok { return font }
    }
    return nil
}
@(private)
before_free :: proc(n: ^node.BaseNode, data: rawptr) {
    h := cast(^Host)data
    if h.input != nil {
        if h.input.hovered == n { h.input.hovered = nil }
        if h.input.pressed == n { h.input.pressed = nil }
        if h.input.focused == n { h.input.focused = nil }
    }
    unbind(h, n)
}

// put a node under the style engine so css rules can target it
// tag is the css element name, handles are never reused
bind :: proc(h: ^Host, n: ^node.BaseNode, tag: string, paint: Paint_Proc = nil, states: States_Proc = nil) -> (style.Node_Id, style.Error) {
    if n == nil || n.freed || n.raw == nil || n._internal_style == nil { return 0, .Unknown_Node }
    if id, ok := h.handles[n]; ok { return id, .None }
    context.allocator = h.allocator
    h.next_id += 1
    id := style.Node_Id(h.next_id)
    b := new(Binding)
    b.node = n; b.paint = paint; b.component_states = states; b.tag = strings.clone(tag); b.id = strings.clone(n.key)
    b.id_present = n.key != ""
    b.attributes = make(map[string]string)
    h.bindings[id] = b; h.handles[n] = id
    (cast(^node.Style)n._internal_style).managed = true
    n->add_hook(.Before_Free, before_free, h)
    return id, style.attach_node(h.engine, id)
}
unbind :: proc(h: ^Host, n: ^node.BaseNode) -> style.Error {
    id, ok := h.handles[n]
    if !ok { return .Unknown_Node }
    context.allocator = h.allocator
    if !n.freed {
        n->remove_hook(.Before_Free, before_free, h)
        (cast(^node.Style)n._internal_style).managed = false
    }
    free_binding(h.bindings[id])
    delete_key(&h.bindings, id); delete_key(&h.handles, n)
    return style.detach_node(h.engine, id)
}

set_classes :: proc(h: ^Host, id: style.Node_Id, text: string) -> style.Error {
    b, ok := h.bindings[id]
    if !ok { return .Unknown_Node }
    if b.class_text == text && b.class_present { return .None }
    context.allocator = h.allocator
    replacement := strings.clone(text)
    parts: [dynamic]string
    start := 0
    for i := 0; i <= len(replacement); i += 1 {
        if i == len(replacement) || replacement[i] == ' ' || replacement[i] == '\t' || replacement[i] == '\n' || replacement[i] == '\r' || replacement[i] == '\f' {
            if i > start { append(&parts, replacement[start:i]) }
            start = i+1
        }
    }
    classes := make([]string, len(parts)); copy(classes, parts[:]); delete(parts)
    delete(b.classes); delete(b.class_text)
    b.class_text = replacement; b.classes = classes
    b.class_present = true
    style.classes_changed(h.engine, id)
    return .None
}
set_attribute :: proc(h: ^Host, id: style.Node_Id, name, value: string, present := true) -> style.Error {
    b, ok := h.bindings[id]
    if !ok { return .Unknown_Node }
    context.allocator = h.allocator
    if name == "class" {
        err := set_classes(h, id, value if present else "")
        b.class_present = present
        style.attribute_changed(h.engine, id)
        return err
    }
    if name == "id" {
        replacement := strings.clone(value if present else "")
        delete(b.id); b.id = replacement
        b.id_present = present
    } else {
        new_key, new_value := strings.clone(name), strings.clone(value)
        for key, old in b.attributes {
            if key == name { delete_key(&b.attributes, key); delete(key); delete(old); break }
        }
        if present { b.attributes[new_key] = new_value }
        else { delete(new_key); delete(new_value) }
    }
    style.attribute_changed(h.engine, id)
    return .None
}
set_states :: proc(h: ^Host, id: style.Node_Id, states: style.State_Set) -> style.Error {
    b, ok := h.bindings[id]
    if !ok { return .Unknown_Node }
    if b.states != states { b.states = states; style.states_changed(h.engine, id) }
    return .None
}
set_has_text :: proc(h: ^Host, id: style.Node_Id, has_text: bool) -> style.Error {
    b, ok := h.bindings[id]
    if !ok { return .Unknown_Node }
    if b.has_text != has_text { b.has_text = has_text; style.children_changed(h.engine, id) }
    return .None
}

@(private)
last_bound :: proc(h: ^Host, n: ^node.BaseNode) -> style.Node_Id {
    if id, ok := h.handles[n]; ok { return id }
    #reverse for child in n.children { if id := last_bound(h, child); id != 0 { return id } }
    return 0
}
// find the nearest styled parent and previous sibling, nodes never passed to bind get skipped
@(private)
relations :: proc(h: ^Host, n: ^node.BaseNode) -> (parent, previous: style.Node_Id, ok: bool) {
    // climb through unbound nodes (compiler wrappers, bookkeeping) as if they were not there
    for at := n; at.parent != nil; at = at.parent {
        if previous == 0 {
            index := -1
            for child, i in at.parent.children { if child == at { index = i; break } }
            if index < 0 { return 0, 0, false }
            #reverse for child in at.parent.children[:index] {
                if previous = last_bound(h, child); previous != 0 { break }
            }
        }
        if id, bound := h.handles[at.parent]; bound { return id, previous, true }
    }
    return 0, previous, true
}
// true when n has text under it, only text before the next bound element count
@(private)
contains_text :: proc(h: ^Host, n: ^node.BaseNode) -> bool {
    for child in n.children {
        if _, bound := h.handles[child]; bound { continue }
        if child.text_content != nil && child.str != nil && child->str() != "" { return true }
        if contains_text(h, child) { return true }
    }
    return false
}
// the text style fields that change measurement
@(private)
measured_text :: proc(t: node.Text_Style) -> node.Text_Style {
    t := t
    // leave color out or a color transition relayout the text every frame
    t.color = {}
    return t
}
// remeasure unbound text under n after its text style change
@(private)
remeasure_inherited :: proc(h: ^Host, n: ^node.BaseNode) {
    for child in n.children {
        // bound ones get apply_node but unbound never do, so yoga keep the old measurement
        if _, bound := h.handles[child]; bound { continue }
        if YG.NodeHasMeasureFunc(child.raw) { child->dirty() }
        remeasure_inherited(h, child)
    }
}
@(private)
contains_target :: proc(n, target: ^node.BaseNode) -> bool {
    for p := target; p != nil; p = p.parent { if p == n { return true } }
    return false
}

set_scale :: proc(h: ^Host, scale: f32) {
    if h.scale == scale { return }
    h.scale = scale
    h.reapply = true
}
@(private)
snap_borders :: proc(h: ^Host, c: ^style.Computed_Style) {
    scale := h.scale if h.scale > 0 else 1
    for p in style.Property.Border_Top_Width..=style.Property.Border_Left_Width {
        if width := c[p].number; width > 0 { c[p].number = max(1, math.floor(width * scale + 0.001)) / scale }
    }
}
// restyle the bound nodes from input, tree and css changes
// call it before layout and paint, and every frame while is_animating or animations freeze
flush :: proc(h: ^Host, now: f64 = 0) -> ([]style.Change, style.Error) {
    for id, b in h.bindings {
        if authored := cast(^node.Style)b.node._internal_style; authored.inline_changed {
            authored.inline_changed = false
            if err := style.set_inline(h.engine, id, authored.inline[:]); err != .None { return nil, err }
        }
        parent, previous, ok := relations(h, b.node)
        if !ok { return nil, .Invalid_Tree }
        if b.parent != parent || b.previous != previous {
            b.parent = parent; b.previous = previous
            style.children_changed(h.engine, id)
        }
        states: style.State_Set
        if h.input != nil {
            if contains_target(b.node, h.input.hovered) { states += {.Hover} }
            if contains_target(b.node, h.input.pressed) { states += {.Active} }
            if b.node == h.input.focused {
                states += {.Focus}
                if h.input.focus_visible || b.node.text_entry { states += {.Focus_Visible} }
            }
            if contains_target(b.node, h.input.focused) { states += {.Focus_Within} }
        }
        if b.component_states != nil { states += b.component_states(b.node) }
        if b.input_states != states { b.input_states = states; style.states_changed(h.engine, id) }
        if text := contains_text(h, b.node); b.text_content != text { b.text_content = text; style.children_changed(h.engine, id) }
    }
    load_font_faces(h)
    changes, err := style.update(h.engine, now)
    if err != .None { return nil, err }
    events := slice.clone(style.motion_events(h.engine), context.temp_allocator)
    if len(changes) > 0 || h.reapply {
        for change in changes { h.bindings[change.node].restyled = true }
        for id, b in h.bindings {
            alpha := flattened_alpha(h, id)
            parent_display := display_of_parent(h, b)
            if !b.restyled && !h.reapply && alpha == b.alpha && parent_display == b.parent_display { continue }
            c, _ := style.presented_style(h.engine, id)
            snap_borders(h, &c)
            // damage before the style land so the rect where it's drawn now get repainted
            b.node->damage()
            applied := cast(^node.Style)b.node._internal_style
            measured_before := measured_text(applied.text)
            apply_node(b.node, c, alpha, h.engine, parent_display)
            b.parent_display = parent_display
            b.grid_stale = true
            if parent, bound := h.bindings[b.parent]; bound { parent.grid_stale = true }
            if b.grid && !grid_container(c[.Display].keyword) {
                release_grid(h, b)
                b.grid = false
            }
            font := find_font(h, c[.Font_Family])
            if font != nil || b.font != nil { applied.text.font = font }
            b.font = font
            if measured_text(applied.text) != measured_before { remeasure_inherited(h, b.node) }
            b.calc = needs_basis(c) || fills_line(c, parent_display)
            b.fixed = c[.Position].keyword == .Fixed
            applied.fixed = b.fixed
            b.fixed_offsets = max(f32)
            if applied.sticky != nil || c[.Position].keyword == .Sticky { applied->set_sticky(sticky(c)) }
            b.basis = tracked_basis(b.node.raw, c)
            apply_transform(h, b, c)
            apply_filter(h, id, b, c)
            scroll.set_look(b.node, {
                thumb  = color(c[.Scrollbar_Thumb_Color], alpha),
                track  = color(c[.Scrollbar_Track_Color], alpha),
                size   = 6 if c[.Scrollbar_Width].keyword == .Thin else 0,
                hidden = c[.Scrollbar_Width].keyword == .None,
            })
            if b.paint != nil {
                pseudo: Pseudo_Styles
                for &pseudo_style, which in pseudo { pseudo_style = style.pseudo_style(h.engine, id, which) }
                b.paint(b.node, c, alpha, pseudo)
            }
            b.alpha = alpha; b.restyled = false
        }
        h.reapply = false
        hit_test.invalidate()
    }
    types := MOTION_EVENT_TYPES
    for &event in events {
        if b, bound := h.bindings[event.node]; bound { input.dispatch(b.node, types[event.kind], &event) }
    }
    return changes, .None
}
@(private)
apply_transform :: proc(h: ^Host, b: ^Binding, c: style.Computed_Style) -> (moved: bool) {
    t := transform(b.node, c, h.engine)
    identity := t == common.IDENTITY_TRANSFORM
    if identity && !b.transformed { return false }
    applied := cast(^node.Style)b.node._internal_style
    moved = applied.transform != t
    applied.transform = t
    b.transformed = !identity
    return
}
// fix up styles that need laid out sizes, like calc() with percent and transforms
// call after layout. true means some sizes moved, so run layout again
settle :: proc(h: ^Host) -> (relayout: bool) {
    moved := false
    for id, b in h.bindings {
        display, _ := style.presented_value(h.engine, id, .Display)
        if grid_container(display.keyword) && settle_grid(h, id, b) { relayout = true }
        if !b.calc && !b.transformed && !b.fixed { continue }
        c, _ := style.presented_style(h.engine, id)
        snap_borders(h, &c)
        if b.fixed && settle_fixed(b.node.raw, c, &b.fixed_offsets) { relayout = true }
        if b.calc {
            if basis := tracked_basis(b.node.raw, c); basis != b.basis {
                b.basis = basis
                apply_layout(b.node.raw, c, h.engine, b.parent_display)
                b.grid_stale = true
                if parent, bound := h.bindings[b.parent]; bound { parent.grid_stale = true }
                relayout = true
            }
        }
        if b.transformed {
            applied := cast(^node.Style)b.node._internal_style
            was := applied.transform
            if apply_transform(h, b, c) {
                moved = true
                // damage rect is where it was drawn, so take it under the old transform
                now := applied.transform
                applied.transform = was
                b.node->damage()
                applied.transform = now
            }
        }
    }
    if moved || relayout { hit_test.invalidate() }
    return
}
@(private)
settle_grid :: proc(h: ^Host, id: style.Node_Id, b: ^Binding) -> bool {
    raw := b.node.raw
    width, height := content_size(raw)
    fresh := YG.NodeGetHasNewLayout(raw)
    if !b.grid_stale && !fresh { return false }
    YG.NodeSetHasNewLayout(raw, false)
    if !b.grid_stale && b.grid_settled && b.grid_size == {width, height} {
        b.grid_settled = false
        return false
    }
    c, _ := style.presented_style(h.engine, id)
    snap_borders(h, &c)
    expected, relayout := layout_grid(h, b, c)
    b.grid, b.grid_stale, b.grid_settled = true, false, relayout
    b.grid_size = {width, expected}
    return relayout
}
// give the display of the parent box that lay b out
@(private)
display_of_parent :: proc(h: ^Host, b: ^Binding) -> style.Keyword {
    parent, bound := h.bindings[b.parent]
    if !bound || b.node.parent != parent.node { return .Flex } // a wrapper sit in between and wrappers are flex
    v, _ := style.presented_value(h.engine, b.parent, .Display)
    return v.keyword
}
// get resolve current styles of cursor
cursor :: proc(h: ^Host) -> common.Cursor {
    if h.input == nil || h.input.hovered == nil { return .Arrow }
    hovered := h.input.hovered
    for at := hovered; at != nil; at = at.parent {
        id, bound := h.handles[at]
        if !bound { continue }
        v, _ := style.presented_value(h.engine, id, .Cursor)
        #partial switch v.keyword {
        case .Pointer: return .Hand
        case .Text: return .Text
        case .Ew_Resize: return .Resize_EW
        case .Ns_Resize: return .Resize_NS
        case .Nwse_Resize: return .Resize_NWSE
        case .Nesw_Resize: return .Resize_NESW
        case .Auto:
            if hovered.text_content != nil && node.Resolve_User_Select(hovered) != .None { return .Text }
        }
        break
    }
    return .Arrow
}
@(private)
flattened_alpha :: proc(h: ^Host, id: style.Node_Id) -> f32 {
    if v, _ := style.presented_value(h.engine, id, .Visibility); v.keyword == .Hidden { return 0 }
    alpha: f32 = 1
    for at := id; at != 0; at = h.bindings[at].parent {
        if layered(h, at) { continue }
        v, _ := style.presented_value(h.engine, at, .Opacity)
        alpha *= v.number
    }
    return alpha
}
// true means render this node into its own offscreen layer for apply effect filter
@(private)
layered :: proc(h: ^Host, id: style.Node_Id) -> bool {
    if v, _ := style.presented_value(h.engine, id, .Filter); v.kind == .Filter { return true }
    if v, _ := style.presented_value(h.engine, id, .Opacity); v.number >= 1 { return false }
    b := h.bindings[id]
    if b == nil { return false }
    for child in b.node.children {
        if !child.freed && child.text_content == nil { return true }
    }
    return false
}
@(private)
apply_filter :: proc(h: ^Host, id: style.Node_Id, b: ^Binding, c: style.Computed_Style) {
    applied := cast(^node.Style)b.node._internal_style
    if !layered(h, id) {
        applied->set_filter(nil)
        return
    }
    out := common.EFFECT_FILTER_NONE
    if f, ok := style.filter(h.engine, c[.Filter]); ok {
        out = {blur = f.blur, color = f.color, offset = f.offset, shadows = transmute([]common.EffectShadow)f.shadows}
    }
    opacity := clamp(c[.Opacity].number, 0, 1)
    if c[.Visibility].keyword == .Hidden { opacity = 0 }
    fade := common.EFFECT_FILTER_NONE.color
    fade[3][3] = opacity
    applied->set_filter(common.filter_then(out, fade, 0))
}
