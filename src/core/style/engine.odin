package style

import "base:runtime"
import "core:strings"
import "core:math"

create :: proc(tree: Tree_API, allocator := context.allocator) -> ^Engine {
    e := new(Engine, allocator)
    e.tree = tree
    e.allocator = allocator
    e.node_lookup = make(map[Node_Id]int, allocator)
    e.custom_names = make(map[string]int, allocator)
    e.families = make([dynamic][]string, allocator)
    e.expressions = make([dynamic]Expression, allocator)
    e.transforms = make([dynamic]Transform_List, allocator)
    e.events = make([dynamic]Motion_Event, allocator)
    append(&e.families, nil)
    append(&e.expressions, Expression{})
    append(&e.transforms, Transform_List{})
    e.tracks = make([dynamic][]Track, allocator)
    append(&e.tracks, nil)
    e.shadows = make([dynamic][]Shadow, allocator)
    append(&e.shadows, nil)
    e.gradients = make([dynamic]Gradient, allocator)
    append(&e.gradients, Gradient{})
    e.areas = make([dynamic][]Area, allocator)
    append(&e.areas, nil)
    e.filters = make([dynamic]Filter, allocator)
    append(&e.filters, Filter{})
    e.next_sheet = 1
    e.dirty = true
    e.environment.root_font_size = 16
    return e
}
@(private)
free_record :: proc(node: Record) {
    free_declarations(node.inline); delete(node.transitions); delete(node.tweens)
    free_motion(node.inline_motion)
    free_custom(node.inline_custom)
    delete(node.custom)
    for style in node.pseudo { free(style) }
    for playback in node.animations { free_playback(playback) }
    delete(node.animations)
}
destroy :: proc(e: ^Engine) {
    if e == nil { return }
    context.allocator = e.allocator
    for sheet in e.sheets { free_sheet(sheet.desc) }
    for node in e.nodes { free_record(node) }
    for names in e.families {
        for name in names { delete(name) }
        delete(names)
    }
    for slot in e.expressions { delete(slot.ops) }
    for slot in e.transforms { delete(slot.ops) }
    for name in e.custom_names { delete(name) }
    for list in e.tracks { delete(list) }
    delete(e.tracks)
    for list in e.shadows { delete(list) }
    delete(e.shadows)
    for gradient in e.gradients { delete(gradient.stops) }
    delete(e.gradients)
    for list in e.areas { delete(list) }
    delete(e.areas)
    for filter in e.filters { delete(filter.shadows) }
    delete(e.filters)
    clear_events(e)
    delete(e.sheets); delete(e.nodes); delete(e.changes); delete(e.families)
    delete(e.expressions); delete(e.transforms); delete(e.custom_names); delete(e.events)
    delete(e.node_lookup)
    free(e)
}
@(private)
intern_family :: proc(e: ^Engine, names: []string) -> f32 {
    search: for known, i in e.families {
        if len(known) != len(names) { continue }
        for name, j in names { if known[j] != name { continue search } }
        return f32(i)
    }
    owned := make([]string, len(names))
    for name, i in names { owned[i] = strings.clone(name) }
    append(&e.families, owned)
    return f32(len(e.families)-1)
}
@(private)
intern_tracks :: proc(e: ^Engine, list: []Track) -> f32 {
    search: for known, i in e.tracks {
        if len(known) != len(list) { continue }
        for track, j in list { if known[j] != track { continue search } }
        return f32(i)
    }
    owned := make([]Track, len(list))
    copy(owned, list)
    append(&e.tracks, owned)
    return f32(len(e.tracks)-1)
}
@(private)
intern_shadows :: proc(e: ^Engine, list: []Shadow) -> f32 {
    search: for known, i in e.shadows {
        if len(known) != len(list) { continue }
        for shadow, j in list { if known[j] != shadow { continue search } }
        return f32(i)
    }
    owned := make([]Shadow, len(list))
    copy(owned, list)
    append(&e.shadows, owned)
    return f32(len(e.shadows)-1)
}
shadows :: proc(e: ^Engine, v: Value) -> []Shadow {
    i := int(v.number)
    return e.shadows[i] if e != nil && v.kind == .Shadows && i >= 0 && i < len(e.shadows) else nil
}
@(private)
intern_gradient :: proc(e: ^Engine, g: Gradient) -> f32 {
    search: for known, i in e.gradients {
        if known.kind != g.kind || known.angle != g.angle || len(known.stops) != len(g.stops) { continue }
        for stop, j in g.stops { if known.stops[j] != stop { continue search } }
        return f32(i)
    }
    owned := g
    owned.stops = make([]Gradient_Stop, len(g.stops))
    copy(owned.stops, g.stops)
    append(&e.gradients, owned)
    return f32(len(e.gradients)-1)
}
gradient :: proc(e: ^Engine, v: Value) -> (Gradient, bool) {
    i := int(v.number)
    if e == nil || v.kind != .Gradient || i <= 0 || i >= len(e.gradients) { return {}, false }
    return e.gradients[i], true
}
@(private)
intern_filter :: proc(e: ^Engine, f: Filter) -> f32 {
    search: for known, i in e.filters {
        if i == 0 || known.blur != f.blur || known.color != f.color || known.offset != f.offset || len(known.shadows) != len(f.shadows) { continue }
        for shadow, j in f.shadows { if known.shadows[j] != shadow { continue search } }
        return f32(i)
    }
    owned := f
    owned.shadows = make([]Shadow, len(f.shadows))
    copy(owned.shadows, f.shadows)
    append(&e.filters, owned)
    return f32(len(e.filters)-1)
}
// get the filter of a computed value
// the shadows belong to the engine, dont free them. they live until destroy
filter :: proc(e: ^Engine, v: Value) -> (Filter, bool) {
    i := int(v.number)
    if e == nil || v.kind != .Filter || i <= 0 || i >= len(e.filters) { return {}, false }
    return e.filters[i], true
}
@(private)
intern_areas :: proc(e: ^Engine, list: []Area) -> f32 {
    search: for known, i in e.areas {
        if len(known) != len(list) { continue }
        for area, j in list { if known[j] != area { continue search } }
        return f32(i)
    }
    owned := make([]Area, len(list))
    copy(owned, list)
    append(&e.areas, owned)
    return f32(len(e.areas)-1)
}
// get the named areas of a computed grid-template-areas
// they belong to the engine, dont free them. they live until destroy
areas :: proc(e: ^Engine, v: Value) -> []Area {
    i := int(v.number)
    return e.areas[i] if e != nil && v.kind == .Areas && i >= 0 && i < len(e.areas) else nil
}
// get the track list of a computed grid value
// it belong to the engine, dont free it. it live until destroy
tracks :: proc(e: ^Engine, v: Value) -> []Track {
    i := int(v.number)
    return e.tracks[i] if e != nil && v.kind == .Tracks && i >= 0 && i < len(e.tracks) else nil
}
// get the font-family names of a computed value
// they belong to the engine, dont free them. they live until destroy
family :: proc(e: ^Engine, v: Value) -> []string {
    i := int(v.number)
    return e.families[i] if v.kind == .Family && i >= 0 && i < len(e.families) else nil
}
@(private)
validate :: proc(desc: Stylesheet_Desc, options: Sheet_Options) -> Error {
    if desc.version != IR_VERSION { return .Invalid_Version }
    if options.origin != .Defaults && options.origin != .Author { return .Invalid_Declaration }
    defaults := options.origin == .Defaults
    for rule in desc.rules {
        for condition in rule.conditions {
            if int(condition.feature) < 0 || int(condition.feature) > 6 || !finite(condition.value) || condition.value < 0 { return .Invalid_Declaration }
        }
        if len(rule.selectors) == 0 { return .Invalid_Selector }
        for selector in rule.selectors { if !valid_selector(selector) { return .Invalid_Selector } }
        if !valid_declarations(rule.declarations, defaults) || !valid_custom(rule.custom, defaults) { return .Invalid_Declaration }
        if !valid_motion(rule.motion, defaults) { return .Invalid_Motion }
    }
    for k in desc.keyframes {
        if k.name == "" || !valid_frames(k.frames, false) { return .Invalid_Motion }
    }
    for face in desc.font_faces { if face.family == "" || face.source == "" { return .Invalid_Declaration } }
    return .None
}
@(private)
clone_sheet :: proc(e: ^Engine, input: Stylesheet_Desc) -> Stylesheet_Desc {
    output := Stylesheet_Desc{version = input.version, rules = make([]Rule, len(input.rules))}
    for rule, i in input.rules {
        output.rules[i].conditions = make([]Media_Test, len(rule.conditions))
        copy(output.rules[i].conditions, rule.conditions)
        output.rules[i].declarations = clone_declarations(e, rule.declarations)
        output.rules[i].custom = clone_custom(e, rule.custom)
        output.rules[i].motion = clone_motion(rule.motion)
        output.rules[i].selectors = clone_selectors(rule.selectors)
    }
    output.keyframes = make([]Keyframes_Desc, len(input.keyframes))
    for k, i in input.keyframes { output.keyframes[i] = {strings.clone(k.name), clone_frames(e, k.frames)} }
    output.font_faces = make([]Font_Face, len(input.font_faces))
    for face, i in input.font_faces { output.font_faces[i] = {strings.clone(face.family), strings.clone(face.source)} }
    if len(input.font_faces) > 0 { e.font_face_generation += 1 }
    return output
}
@(private)
free_sheet :: proc(desc: Stylesheet_Desc) {
    for rule in desc.rules {
        delete(rule.conditions)
        free_declarations(rule.declarations)
        free_custom(rule.custom)
        free_motion(rule.motion)
        free_selectors(rule.selectors)
    }
    for k in desc.keyframes { delete(k.name); free_frames(k.frames) }
    for face in desc.font_faces { delete(face.family); delete(face.source) }
    delete(desc.rules); delete(desc.keyframes); delete(desc.font_faces)
}
// list every @font-face of the registered sheets
// the strings die after any sheet change, watch font_face_generation to know when new ones come in
font_faces :: proc(e: ^Engine, allocator := context.temp_allocator) -> []Font_Face {
    faces := make([dynamic]Font_Face, allocator)
    for sheet in e.sheets { append(&faces, ..sheet.desc.font_faces) }
    return faces[:]
}
add_stylesheet :: proc(e: ^Engine, desc: Stylesheet_Desc, options := Sheet_Options{origin = .Author}) -> (Sheet_Id, Error) {
    if err := validate(desc, options); err != .None { return 0, err }
    if err := validate_callbacks(e, desc); err != .None { return 0, err }
    context.allocator = e.allocator
    id := Sheet_Id(e.next_sheet); e.next_sheet += 1
    append(&e.sheets, Sheet{id, clone_sheet(e, desc), options})
    e.dirty = true
    return id, .None
}
replace_stylesheet :: proc(e: ^Engine, id: Sheet_Id, desc: Stylesheet_Desc) -> Error {
    context.allocator = e.allocator
    for &sheet in e.sheets {
        if sheet.id != id { continue }
        if err := validate(desc, sheet.options); err != .None { return err }
        if err := validate_callbacks(e, desc); err != .None { return err }
        replacement := clone_sheet(e, desc)
        free_sheet(sheet.desc)
        sheet.desc = replacement
        e.dirty = true
        return .None
    }
    return .Unknown_Sheet
}
remove_stylesheet :: proc(e: ^Engine, id: Sheet_Id) -> Error {
    context.allocator = e.allocator
    for sheet, i in e.sheets {
        if sheet.id != id { continue }
        free_sheet(sheet.desc)
        ordered_remove(&e.sheets, i)
        e.dirty = true
        return .None
    }
    return .Unknown_Sheet
}
@(private)
node_index :: proc(e: ^Engine, id: Node_Id) -> int {
    i, ok := e.node_lookup[id]
    return i if ok else -1
}
attach_node :: proc(e: ^Engine, id: Node_Id) -> Error {
    if id == 0 { return .Unknown_Node }
    if node_index(e, id) >= 0 { return .None }
    context.allocator = e.allocator
    e.node_lookup[id] = len(e.nodes)
    append(&e.nodes, Record{id = id}); e.dirty = true
    return .None
}
detach_node :: proc(e: ^Engine, id: Node_Id) -> Error {
    i := node_index(e, id)
    if i < 0 { return .Unknown_Node }
    context.allocator = e.allocator
    free_record(e.nodes[i])
    ordered_remove(&e.nodes, i); e.dirty = true
    delete_key(&e.node_lookup, id)
    for j in i..<len(e.nodes) { e.node_lookup[e.nodes[j].id] = j }
    return .None
}
set_inline :: proc(e: ^Engine, id: Node_Id, declarations: []Declaration) -> Error {
    i := node_index(e, id)
    if i < 0 { return .Unknown_Node }
    if !valid_declarations(declarations) { return .Invalid_Declaration }
    context.allocator = e.allocator
    replacement := clone_declarations(e, declarations)
    free_declarations(e.nodes[i].inline)
    e.nodes[i].inline = replacement; e.dirty = true
    return .None
}
clear_inline :: proc(e: ^Engine, id: Node_Id) -> Error { return set_inline(e, id, nil) }
// tell the engine this node changed, next update restyle it
changed :: proc(e: ^Engine, id: Node_Id) { e.dirty = true } // restyle the whole tree on purpose cuz :has and sibling selectors can hit other nodes
classes_changed :: changed
attribute_changed :: changed
states_changed :: changed
children_changed :: changed

@(private)
Rank :: struct { tier: int, spec: Specificity, order: i64, sheet: Sheet_Id, rule, declaration: int }
@(private)
wins :: proc(a, b: Rank) -> bool {
    if a.tier != b.tier { return a.tier > b.tier }
    if n := compare_specificity(a.spec, b.spec); n != 0 { return n > 0 }
    if a.order != b.order { return a.order > b.order }
    if a.sheet != b.sheet { return a.sheet > b.sheet }
    if a.rule != b.rule { return a.rule > b.rule }
    return a.declaration >= b.declaration
}
// compute target.pending from the winning declarations
// for a pseudo-element, target is a temporary record and parent is the element it belong to
@(private)
compute_values :: proc(e: ^Engine, target, parent: ^Record, winning: ^[Property]^Declaration) {
    target.inherited_properties = {}
    target.relative = {}
    target.current_color = {}
    c := Context{e = e, node = target, parent = parent, scope = target}
    // font go first cuz ex and ch need the family and weight, and every relative length need the size
    order: [len(Property)]Property
    order[0], order[1], order[2] = .Font_Family, .Font_Weight, .Font_Size
    count := 3
    for p in Property {
        if p == .Font_Family || p == .Font_Weight || p == .Font_Size { continue }
        order[count] = p
        count += 1
    }
    for p in order {
        v := keyword(.Unset)
        if d := winning[p]; d != nil {
            if resolved, ok := resolve(c, p, d^); ok && (d.variable == "" && len(d.vars) == 0 || valid_value(p, resolved)) {
                v = resolved
                if v.kind == .Length && (d.variable != "" || d.value.unit != .Px) { target.relative += {p} }
            }
        }
        if v.kind == .Keyword && (v.keyword == .Initial || v.keyword == .Inherit || v.keyword == .Unset) {
            inherit := v.keyword == .Inherit || (v.keyword == .Unset && inherited(p))
            v = parent.pending[p] if inherit && parent != nil else initial(p)
            if inherit && parent != nil { target.inherited_properties += {p} }
            else if p == .Font_Size { v = length(e.environment.root_font_size) }
        }
        if p == .Opacity { v.number = clamp(v.number, 0, 1) }
        target.pending[p] = v
    }
    if target.pending[.Color].kind == .Keyword {
        target.pending[.Color] = parent.pending[.Color] if parent != nil else initial(.Color)
        if parent != nil { target.inherited_properties += {.Color} }
    }
    for p in Property {
        if p == .Color || !is_color(p) || target.pending[p].kind != .Keyword { continue }
        target.current_color += {p}
        target.pending[p] = target.pending[.Color]
    }
    used_borders(&target.pending)
    // css spec say visible become auto when the other axis isnt visible
    if target.pending[.Overflow_X].keyword == .Visible && target.pending[.Overflow_Y].keyword != .Visible { target.pending[.Overflow_X] = keyword(.Auto) }
    if target.pending[.Overflow_Y].keyword == .Visible && target.pending[.Overflow_X].keyword != .Visible { target.pending[.Overflow_Y] = keyword(.Auto) }
}
@(private)
compute :: proc(e: ^Engine, i: int) -> Error {
    node := &e.nodes[i]
    if node.visit == 2 { return .None }
    if node.visit == 1 { return .Invalid_Tree }
    node.visit = 1
    parent_id := e.tree.parent(e.tree.data, node.id)
    parent: ^Record
    if parent_id != 0 {
        pi := node_index(e, parent_id)
        if pi < 0 { return .Invalid_Tree }
        if err := compute(e, pi); err != .None { return err }
        parent = &e.nodes[pi]
    }
    ranks: [Pseudo_Element][Property]Rank
    winning: [Pseudo_Element][Property]^Declaration
    styled: [Pseudo_Element]bool
    motion_ranks: [Motion_Property]Rank
    node.winners = {}
    node.motion_winners = {}
    for pseudo in Pseudo_Element { for p in Property { ranks[pseudo][p].tier = -1 } }
    for p in Motion_Property { motion_ranks[p].tier = -1 }

    names := len(e.custom_names)
    if len(node.custom) != names {
        delete(node.custom)
        node.custom = make([]Custom_Ref, names)
    }
    custom_ranks := make([]Rank, names)
    custom_winning := make([]^Declaration, names)
    defer { delete(custom_ranks); delete(custom_winning) }
    for &rank in custom_ranks { rank.tier = -1 }
    for &ref, index in node.custom { ref = parent.custom[index] if parent != nil && index < len(parent.custom) else Custom_Ref{} }

    for sheet in e.sheets {
        for rule, ri in sheet.desc.rules {
            if !media_matches(e.environment, rule.conditions) { continue }
            matched: [Pseudo_Element]bool
            spec: [Pseudo_Element]Specificity
            for selector in rule.selectors {
                if matches(e, node.id, selector.steps) {
                    candidate := specificity(selector)
                    if !matched[selector.pseudo] || compare_specificity(candidate, spec[selector.pseudo]) > 0 { spec[selector.pseudo] = candidate }
                    matched[selector.pseudo] = true
                }
            }
            for pseudo in Pseudo_Element {
                if !matched[pseudo] { continue }
                for d, di in rule.declarations {
                    tier := 0 if sheet.options.origin == .Defaults else (3 if d.important else 1)
                    rank := Rank{tier, spec[pseudo], sheet.options.order, sheet.id, ri, di}
                    if wins(rank, ranks[pseudo][d.property]) {
                        ranks[pseudo][d.property] = rank; winning[pseudo][d.property] = &rule.declarations[di]
                        styled[pseudo] = true
                        if pseudo == .None { node.winners[d.property] = {sheet.id, i32(ri), i32(di), spec[pseudo], true, d.important, false} }
                    }
                }
            }
            if !matched[.None] { continue }
            for d, di in rule.custom {
                tier := 0 if sheet.options.origin == .Defaults else (3 if d.declaration.important else 1)
                rank := Rank{tier, spec[.None], sheet.options.order, sheet.id, ri, di}
                index := e.custom_names[d.name]
                if wins(rank, custom_ranks[index]) { custom_ranks[index] = rank; custom_winning[index] = &rule.custom[di].declaration }
            }
            for d, di in rule.motion {
                tier := 0 if sheet.options.origin == .Defaults else (3 if d.important else 1)
                rank := Rank{tier, spec[.None], sheet.options.order, sheet.id, ri, di}
                if wins(rank, motion_ranks[d.property]) {
                    motion_ranks[d.property] = rank
                    node.motion_winners[d.property] = {sheet.id, i32(ri), i32(di), spec[.None], true, d.important, false}
                }
            }
        }
    }
    for d, di in node.inline_motion {
        rank := Rank{tier = 4 if d.important else 2, declaration = di}
        if wins(rank, motion_ranks[d.property]) {
            motion_ranks[d.property] = rank
            node.motion_winners[d.property] = {found = true, declaration = i32(di), important = d.important, inline_style = true}
        }
    }
    for d, di in node.inline_custom {
        rank := Rank{tier = 4 if d.declaration.important else 2, declaration = di}
        index := e.custom_names[d.name]
        if wins(rank, custom_ranks[index]) { custom_ranks[index] = rank; custom_winning[index] = &node.inline_custom[di].declaration }
    }
    for d, di in node.inline {
        rank := Rank{tier = 4 if d.important else 2, declaration = di}
        if wins(rank, ranks[.None][d.property]) {
            ranks[.None][d.property] = rank; winning[.None][d.property] = &node.inline[di]
            node.winners[d.property] = {found = true, declaration = i32(di), important = d.important, inline_style = true}
        }
    }
    for d, index in custom_winning {
        if d == nil { continue }
        wide := d.variable == "" && d.value.kind == .Keyword
        if wide && d.value.keyword == .Initial { node.custom[index] = {} }
        else if !(wide && (d.value.keyword == .Inherit || d.value.keyword == .Unset)) { node.custom[index] = {d, i32(i)} }
    }

    previous := node.pending
    compute_values(e, node, parent, &winning[.None])
    node.changed = {}
    for p in Property { if previous[p] != node.pending[p] { node.changed += {p} } }

    node.pseudo_changed = false
    for pseudo in Pseudo_Element {
        if pseudo == .None { continue }
        if !styled[pseudo] {
            if node.pseudo[pseudo] != nil { free(node.pseudo[pseudo]); node.pseudo[pseudo] = nil; node.pseudo_changed = true }
            continue
        }
        scratch := Record{id = node.id, custom = node.custom}
        compute_values(e, &scratch, node, &winning[pseudo])
        if node.pseudo[pseudo] == nil {
            node.pseudo[pseudo] = new(Computed_Style)
            node.pseudo_changed = true
        } else if node.pseudo[pseudo]^ != scratch.pending { node.pseudo_changed = true }
        node.pseudo[pseudo]^ = scratch.pending
    }
    node.visit = 2
    return .None
}
@(private)
winning_declaration :: proc(e: ^Engine, node: ^Record, w: Winner_Ref) -> (Declaration, bool) {
    if !w.found { return {}, false }
    if w.inline_style { return node.inline[w.declaration], true }
    for sheet in e.sheets {
        if sheet.id == w.sheet { return sheet.desc.rules[w.rule].declarations[w.declaration], true }
    }
    return {}, false
}
// restyle what changed and advance motion to now, return the nodes whose style changed
// the slice belong to the engine and die on the next update or destroy, so dont hold on to it
update :: proc(e: ^Engine, now: f64 = 0) -> ([]Change, Error) {
    context.allocator = e.allocator
    clear(&e.changes)
    clear_events(e)
    if math.is_nan(now) || math.is_inf(now) || now < e.last_time { return nil, .Invalid_Time }
    if !e.dirty && !is_animating(e) { e.last_time = now; return e.changes[:], .None }
    if e.tree.parent == nil { return nil, .Invalid_Tree }
    order: [dynamic]int
    defer delete(order)
    if err := tree_order(e, &order); err != .None { return nil, err }
    if err := tree_order(e, &order, true); err != .None { return nil, err }
    if e.dirty {
        for &node in e.nodes { node.visit = 0 }
        for i in order { if err := compute(e, i); err != .None { return nil, err } }
        for &node in e.nodes { sync_animations(e, &node, now) }
    }
    for &node in e.nodes { node.visit = 0 }
    resolve_playback_times(e, now)
    for i in order { present_frame(e, i, now) }
    for &node in e.nodes {
        if node.restyled != {} || node.pseudo_changed {
            change := Change{node = node.id, style = node.presented, properties = node.restyled, affects_paint = true, pseudo = node.pseudo_changed}
            for p in node.restyled { if affects_layout(p) { change.affects_layout = true; break } }
            append(&e.changes, change)
        }
        node.initialized = true
        node.changed = {}
        node.pseudo_changed = false
        animation_events(e, &node, now)
        prune_animations(&node, now)
    }
    collect(e)
    e.dirty = false
    e.last_time = now
    return e.changes[:], .None
}
computed_style :: proc(e: ^Engine, id: Node_Id) -> (Computed_Style, bool) {
    i := node_index(e, id)
    if i < 0 || !e.nodes[i].initialized { return {}, false }
    return e.nodes[i].pending, true
}
// get the style of a pseudo-element, nil when no rule target it
// it has no motion and die on the next update
pseudo_style :: proc(e: ^Engine, id: Node_Id, pseudo: Pseudo_Element) -> ^Computed_Style {
    i := node_index(e, id)
    if i < 0 || !e.nodes[i].initialized || pseudo == .None { return nil }
    return e.nodes[i].pseudo[pseudo]
}
// find which declaration won this property and where it was written
// source strings are borrowed, they die on any sheet or inline change or destroy
explain :: proc(e: ^Engine, id: Node_Id, property: Property) -> (Winner, bool) {
    i := node_index(e, id)
    if e.dirty || i < 0 || !e.nodes[i].initialized { return {}, false }
    w := e.nodes[i].winners[property]
    winner := Winner{found = w.found, sheet = w.sheet, rule_index = int(w.rule), declaration_index = int(w.declaration), specificity = w.specificity, important = w.important, inline_style = w.inline_style}
    if d, ok := winning_declaration(e, &e.nodes[i], w); ok { winner.source = d.source }
    return winner, true
}
