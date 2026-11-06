package style

import "core:strings"

@(private)
valid_motion :: proc(decls: []Motion_Declaration, defaults := false) -> bool {
    for d in decls {
        if int(d.property) > int(Motion_Property.Animation_Play_State) || (defaults && d.important) { return false }
        if len(d.items) == 0 && d.property != .Transition_Property && d.property != .Animation_Name { return false }
        for item in d.items {
            switch d.property {
            case .Transition_Property: if !item.all && int(item.property) >= len(Property) { return false }
            case .Transition_Duration, .Animation_Duration: if !finite(item.seconds) || item.seconds < 0 { return false }
            case .Transition_Delay, .Animation_Delay: if !finite(item.seconds) { return false }
            case .Transition_Timing_Function, .Animation_Timing_Function: if !valid_easing(item.easing) { return false }
            case .Animation_Iteration_Count: if !(item.count > 0) { return false }
            case .Animation_Direction: if int(item.direction) > int(Animation_Direction.Alternate_Reverse) { return false }
            case .Animation_Fill_Mode: if int(item.fill) > int(Animation_Fill.Both) { return false }
            case .Animation_Name, .Animation_Play_State:
            }
        }
    }
    return true
}
// true when keyframe offsets go up within 0 to 1 and every declaration can be animated
// computed_only is for host keyframes, they only allow px and percent
@(private)
valid_frames :: proc(frames: []Keyframe, computed_only: bool) -> bool {
    previous: f32 = -1
    for frame in frames {
        if !(frame.offset >= 0 && frame.offset <= 1) || frame.offset < previous || !valid_declarations(frame.declarations) { return false }
        if easing, ok := frame.easing.?; ok && !valid_easing(easing) { return false }
        previous = frame.offset
        for d in frame.declarations {
            v := d.value
            if d.important { return false }
            if v.kind == .Keyword && (v.keyword == .Initial || v.keyword == .Inherit || v.keyword == .Unset) { return false }
            if computed_only && ((v.kind == .Length && v.unit != .Px && v.unit != .Percent && v.unit != .Calc) || (v.kind == .Keyword && v.keyword == .Current_Color)) { return false }
            if computed_only && (d.variable != "" || len(d.vars) > 0) { return false }
            if computed_only && v.unit == .Calc { for coefficient, unit in d.calc { if coefficient != 0 && unit != .Px && unit != .Percent { return false } } }
        }
    }
    return true
}
@(private)
clone_motion :: proc(input: []Motion_Declaration) -> []Motion_Declaration {
    output := make([]Motion_Declaration, len(input))
    for d, i in input {
        output[i] = d
        output[i].source.file = strings.clone(d.source.file)
        output[i].items = make([]Motion_Item, len(d.items))
        for item, j in d.items {
            output[i].items[j] = item
            output[i].items[j].name = strings.clone(item.name)
        }
    }
    return output
}
@(private)
free_motion :: proc(decls: []Motion_Declaration) {
    for d in decls {
        for item in d.items { delete(item.name) }
        delete(d.items); delete(d.source.file)
    }
    delete(decls)
}
@(private)
clone_frames :: proc(e: ^Engine, input: []Keyframe) -> []Keyframe {
    output := make([]Keyframe, len(input))
    for frame, i in input { output[i] = {frame.offset, clone_declarations(e, frame.declarations), frame.easing} }
    return output
}
@(private)
free_frames :: proc(frames: []Keyframe) {
    for frame in frames { free_declarations(frame.declarations) }
    delete(frames)
}

// set the inline transition and animation longhands of a node
// they win over sheet rules, same as set_inline
set_inline_motion :: proc(e: ^Engine, id: Node_Id, declarations: []Motion_Declaration) -> Error {
    i := node_index(e, id)
    if i < 0 { return .Unknown_Node }
    if !valid_motion(declarations) { return .Invalid_Motion }
    context.allocator = e.allocator
    replacement := clone_motion(declarations)
    free_motion(e.nodes[i].inline_motion)
    e.nodes[i].inline_motion = replacement; e.dirty = true
    return .None
}

@(private)
motion_items :: proc(e: ^Engine, node: ^Record, property: Motion_Property) -> (items: []Motion_Item, found: bool) {
    w := node.motion_winners[property]
    if !w.found { return nil, false }
    if w.inline_style { return node.inline_motion[w.declaration].items, true }
    for sheet in e.sheets {
        if sheet.id == w.sheet { return sheet.desc.rules[w.rule].motion[w.declaration].items, true }
    }
    return nil, false
}
@(private)
find_keyframes :: proc(e: ^Engine, name: string) -> (frames: []Keyframe, found: bool) {
    order: i64
    for sheet in e.sheets {
        if found && sheet.options.order < order { continue }
        for k in sheet.desc.keyframes {
            if k.name == name { frames = k.frames; order = sheet.options.order; found = true }
        }
    }
    return
}

// collect the transition config of every property on a node
// if the host called set_transitions with a list, that list win over css
@(private)
build_transitions :: proc(e: ^Engine, node: ^Record, configs: ^[Property]Transition) -> (has: Property_Set) {
    add :: proc(configs: ^[Property]Transition, has: ^Property_Set, t: Transition) {
        if !t.all { configs[t.property] = t; has^ += {t.property}; return }
        for p in Property { configs[p] = t; configs[p].property = p; has^ += {p} }
    }
    if len(node.transitions) > 0 {
        for t in node.transitions { add(configs, &has, t) }
        return
    }
    durations, _ := motion_items(e, node, .Transition_Duration)
    delays, _ := motion_items(e, node, .Transition_Delay)
    if len(durations) == 0 && len(delays) == 0 { return }
    properties, listed := motion_items(e, node, .Transition_Property)
    easings, _ := motion_items(e, node, .Transition_Timing_Function)
    for i in 0 ..< (len(properties) if listed else 1) {
        t := Transition{all = true, easing = EASE}
        if listed { t.all = properties[i].all; t.property = properties[i].property }
        if len(durations) > 0 { t.duration = f64(durations[i % len(durations)].seconds) }
        if len(delays) > 0 { t.delay = f64(delays[i % len(delays)].seconds) }
        if len(easings) > 0 { t.easing = easings[i % len(easings)].easing }
        add(configs, &has, t)
    }
    return
}

@(private)
sync_animations :: proc(e: ^Engine, node: ^Record, now: f64) {
    names, _ := motion_items(e, node, .Animation_Name)
    running := false
    for playback in node.animations { if playback.cascade { running = true; break } }
    if !running && len(names) == 0 { return }
    durations, _ := motion_items(e, node, .Animation_Duration)
    delays, _ := motion_items(e, node, .Animation_Delay)
    easings, _ := motion_items(e, node, .Animation_Timing_Function)
    counts, _ := motion_items(e, node, .Animation_Iteration_Count)
    directions, _ := motion_items(e, node, .Animation_Direction)
    fills, _ := motion_items(e, node, .Animation_Fill_Mode)
    states, _ := motion_items(e, node, .Animation_Play_State)
    next: [dynamic]Playback
    for item, i in names {
        frames, defined := find_keyframes(e, item.name)
        if item.name == "" || !defined { continue }
        desc := Animation_Desc{frames = frames, iterations = 1, easing = EASE}
        if len(durations) > 0 { desc.duration = f64(durations[i % len(durations)].seconds) }
        if len(delays) > 0 { desc.delay = f64(delays[i % len(delays)].seconds) }
        if len(easings) > 0 { desc.easing = easings[i % len(easings)].easing }
        if len(counts) > 0 { desc.iterations = f64(counts[i % len(counts)].count) }
        if len(directions) > 0 { desc.direction = directions[i % len(directions)].direction }
        if len(fills) > 0 { desc.fill = fills[i % len(fills)].fill }
        paused := len(states) > 0 && states[i % len(states)].paused
        playback := Playback{cascade = true, unstarted = true}
        reused := false
        for &old in node.animations {
            if !old.cascade || old.claimed || old.name != item.name { continue }
            old.claimed = true
            playback = old
            playback.claimed = false
            reused = true
            break
        }
        if !reused { playback.name = strings.clone(item.name) }
        else if !playback.unstarted { playback.start += desc.delay - playback.desc.delay }
        playback.desc = desc
        if paused {
            if playback.resume_pending { playback.resume_pending = false }
            else if !playback.paused { playback.paused_at = now; playback.paused = true }
        } else if playback.paused { playback.resume_pending = true }
        append(&next, playback)
    }
    for old in node.animations {
        if old.claimed { continue }
        if !old.cascade { append(&next, old); continue }
        if old.started && !old.ended { emit(e, {node = node.id, kind = .Animation_Cancel, name = old.name, elapsed = f32(max(0, now - old.start))}) }
        free_playback(old)
    }
    delete(node.animations)
    node.animations = next
}

@(private)
keyframe_value :: proc(e: ^Engine, node, parent: ^Record, d: Declaration, underlying: ^Computed_Style) -> (v: Value, ok: bool) {
    c := Context{e = e, node = node, parent = parent, scope = node, presentation = true}
    v = resolve(c, d.property, d) or_return
    if v.kind == .Keyword && v.keyword == .Current_Color { v = underlying[.Color] }
    return v, d.variable == "" || valid_value(d.property, v)
}

