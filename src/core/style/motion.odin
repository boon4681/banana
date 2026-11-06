package style

import "core:math"
import "core:strings"

// set the transitions of a node from code, a non-empty list override its css transitions
// times are seconds on the same clock you pass to update
set_transitions :: proc(e: ^Engine, id: Node_Id, transitions: []Transition) -> Error {
    i := node_index(e, id)
    if i < 0 { return .Unknown_Node }
    for t in transitions {
        if int(t.property) >= len(Property) || math.is_nan(t.duration) || math.is_inf(t.duration) || t.duration < 0 || math.is_nan(t.delay) || math.is_inf(t.delay) || !valid_easing(t.easing) { return .Invalid_Motion }
    }
    context.allocator = e.allocator
    replacement := make([]Transition, len(transitions))
    copy(replacement, transitions)
    delete(e.nodes[i].transitions)
    e.nodes[i].transitions = replacement
    e.dirty = true
    return .None
}

@(private)
valid_easing :: proc(e: Easing) -> bool {
    switch e.kind {
    case .Linear: return true
    case .Cubic_Bezier: return finite(e.x1) && finite(e.x2) && finite(e.y1) && finite(e.y2) && e.x1 >= 0 && e.x1 <= 1 && e.x2 >= 0 && e.x2 <= 1
    case .Steps: return e.steps > 0
    }
    return false
}
@(private)
bezier :: proc(t, a, b: f32) -> f32 { return 3*(1-t)*(1-t)*t*a + 3*(1-t)*t*t*b + t*t*t }
@(private)
ease :: proc(e: Easing, progress: f32) -> f32 {
    x := clamp(progress, 0, 1)
    switch e.kind {
    case .Linear: return x
    case .Steps: return min(1, (math.floor(x*f32(e.steps)) + (1 if e.step_start else 0))/f32(e.steps))
    case .Cubic_Bezier:
        if x == 0 || x == 1 { return x }
        low, high: f32 = 0, 1
        for _ in 0..<24 {
            mid := (low+high)/2
            if bezier(mid, e.x1, e.x2) < x { low = mid } else { high = mid }
        }
        return bezier((low+high)/2, e.y1, e.y2)
    }
    return x
}
@(private)
interpolable :: proc(e: ^Engine, p: Property, a, b: Value) -> bool {
    if p == .Transform { return transforms_interpolable(e, a, b) }
    if a.kind != b.kind { return false }
    if p == .Font_Weight || p == .Z_Index || (p >= .Grid_Template_Columns && p <= .Grid_Row_End) { return false }
    switch a.kind {
    case .Color, .Number: return true
    case .Length: return a.unit != .Math && b.unit != .Math
    case .Keyword, .Family, .Transform, .Tracks, .Shadows, .Gradient, .Areas, .Filter: return false
    }
    return false
}
@(private)
interpolate :: proc(e: ^Engine, a, b: Value, t: f32) -> Value {
    v := b
    if a.kind == .Transform || b.kind == .Transform { return interpolate_transform(e, a, b, t) }
    if a.kind == .Length && (a.unit != b.unit || a.unit == .Calc) {
        a_px, a_percent := length_parts(a)
        b_px, b_percent := length_parts(b)
        return mixed(a_px + (b_px-a_px)*t, a_percent + (b_percent-a_percent)*t)
    }
    if a.kind == .Color {
        // interpolate premultiplied or fading to transparent get a dark fringe
        alpha := a.color[3] + (b.color[3]-a.color[3])*t
        v.color[3] = clamp(alpha, 0, 1)
        for i in 0..<3 {
            component := a.color[i]*a.color[3] + (b.color[i]*b.color[3]-a.color[i]*a.color[3])*t
            v.color[i] = clamp(component/alpha, 0, 1) if alpha > 0 else 0
        }
    } else { v.number = a.number + (b.number-a.number)*t }
    return v
}
@(private)
sample_tween :: proc(e: ^Engine, t: ^Tween, now: f64) -> Value {
    if now < t.start { return t.from }
    if t.duration == 0 || now >= t.start+t.duration { t.active = false; return t.to }
    return interpolate(e, t.from, t.to, ease(t.easing, f32((now-t.start)/t.duration)))
}
@(private)
clear_events :: proc(e: ^Engine) {
    for event in e.events { delete(event.name) }
    clear(&e.events)
}
@(private)
emit :: proc(e: ^Engine, event: Motion_Event) {
    owned := event
    owned.name = strings.clone(event.name)
    append(&e.events, owned)
}
// list the transition and animation events of the last update, in order
// the list die on the next update
motion_events :: proc(e: ^Engine) -> []Motion_Event { return e.events[:] }

is_animating :: proc(e: ^Engine) -> bool {
    for node in e.nodes {
        if node.tweening != {} { return true }
        if !e.environment.reduced_motion {
            for playback in node.animations {
                if playback.unstarted || playback.resume_pending { return true }
                if !playback.paused && e.last_time < playback.start+active_duration(playback.desc) { return true }
            }
        }
    }
    return false
}
presented_style :: proc(e: ^Engine, id: Node_Id) -> (Computed_Style, bool) {
    i := node_index(e, id)
    if i < 0 || !e.nodes[i].initialized { return {}, false }
    return e.nodes[i].presented, true
}

presented_value :: proc(e: ^Engine, id: Node_Id, property: Property) -> (Value, bool) {
    i := node_index(e, id)
    if i < 0 || !e.nodes[i].initialized { return {}, false }
    return e.nodes[i].presented[property], true
}

@(private)
present :: proc(e: ^Engine, node, parent: ^Record, previous: ^Computed_Style, now: f64) -> Computed_Style {
    result := node.presented
    if !e.environment.reduced_motion { result = apply_animations(e, node, parent, now, result) }
    configs: [Property]Transition
    configured := build_transitions(e, node, &configs)
    for p in Property {
        index := -1
        if p in node.tweening { for t, i in node.tweens { if t.property == p { index = i; break } } }
        state: Tween
        if index >= 0 { state = node.tweens[index] }
        tween := &state
        previous_tween := state
        current := previous[p]
        if tween.active { current = sample_tween(e, tween, now) }
        finished := previous_tween.active && !tween.active
        config := configs[p]
        found := p in configured
        if !found || e.environment.reduced_motion { tween.active = false }
        created := false
        if node.initialized && p in node.changed {
            tween.active = false
            if found && !e.environment.reduced_motion && config.duration+config.delay > 0 && interpolable(e, p, current, node.pending[p]) && current != node.pending[p] {
                duration, delay := config.duration, config.delay
                shortening: f64 = 1
                reversing_start := current
                if previous_tween.active && previous_tween.duration > 0 && previous_tween.reversing_start == node.pending[p] {
                    progress := ease(previous_tween.easing, f32((now-previous_tween.start)/previous_tween.duration))
                    shortening = clamp(abs(f64(progress)*previous_tween.shortening + 1-previous_tween.shortening), 0, 1)
                    duration *= shortening
                    if delay < 0 { delay *= shortening }
                    reversing_start = previous_tween.to
                }
                tween^ = {active = true, from = current, to = node.pending[p], reversing_start = reversing_start, start = now+delay, duration = duration, shortening = shortening, easing = config.easing}
                created = true
            }
        }
        if finished {
            if !previous_tween.started { emit(e, {node = node.id, kind = .Transition_Start, property = p}) }
            emit(e, {node = node.id, kind = .Transition_End, property = p, elapsed = f32(previous_tween.duration)})
        } else if previous_tween.active && (!tween.active || created) {
            emit(e, {node = node.id, kind = .Transition_Cancel, property = p, elapsed = f32(max(0, now-previous_tween.start))})
        }
        if created { emit(e, {node = node.id, kind = .Transition_Run, property = p}) }
        if tween.active && !tween.started && now >= tween.start {
            tween.started = true
            emit(e, {node = node.id, kind = .Transition_Start, property = p})
        }
        if tween.active {
            result[p] = sample_tween(e, tween, now)
            if !tween.active { emit(e, {node = node.id, kind = .Transition_End, property = p, elapsed = f32(tween.duration)}) }
        }
        if state.active {
            state.property = p
            if index >= 0 { node.tweens[index] = state } else { append(&node.tweens, state); node.tweening += {p} }
        } else if index >= 0 { unordered_remove(&node.tweens, index); node.tweening -= {p} }
        if p == .Opacity { result[p].number = clamp(result[p].number, 0, 1) }
        if p == .Flex_Grow || p == .Flex_Shrink || (p == .Line_Height && result[p].kind == .Number) { result[p].number = max(0, result[p].number) }
        // overshoot easing can go below 0 but sizes and padding cant
        if result[p].kind == .Length && result[p].unit != .Calc && !negative_allowed(p) { result[p].number = max(0, result[p].number) }
    }
    return result
}

@(private)
present_frame :: proc(e: ^Engine, i: int, now: f64) {
    n := &e.nodes[i]
    if n.visit == 2 { return }
    parent: ^Record
    parent_id := e.tree.parent(e.tree.data, n.id)
    if parent_id != 0 {
        pi := node_index(e, parent_id)
        present_frame(e, pi, now)
        parent = &e.nodes[pi]
    }
    previous := n.presented
    n.presented = n.pending
    for p in Property {
        if p in n.inherited_properties && parent != nil { n.presented[p] = parent.presented[p] }
        else if p in n.relative { resolve_presented(e, n, parent, p) }
    }
    n.presented = present(e, n, parent, &previous, now)
    for p in Property {
        has_effect := p in n.tweening || (!e.environment.reduced_motion && animation_affects(n, p, now))
        if has_effect { continue }
        if p != .Font_Size && p in n.relative { resolve_presented(e, n, parent, p) }
        if p in n.current_color { n.presented[p] = n.presented[.Color] }
    }
    used_borders(&n.presented)
    n.restyled = {}
    for p in Property { if !n.initialized || previous[p] != n.presented[p] { n.restyled += {p} } }
    n.visit = 2
}
@(private)
resolve_presented :: proc(e: ^Engine, n, parent: ^Record, p: Property) {
    d, ok := winning_declaration(e, n, n.winners[p])
    if !ok { return }
    c := Context{e = e, node = n, parent = parent, scope = n, presentation = true}
    if v, valid := resolve(c, p, d); valid && v.kind == .Length { n.presented[p] = v }
}
