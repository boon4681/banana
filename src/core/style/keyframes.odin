package style

import "core:math"

// play an animation from the host, it dont go through the cascade
// keyframes must already be computed values like px or percent
play_animation :: proc(e: ^Engine, id: Node_Id, desc: Animation_Desc) -> (Animation_Id, Error) {
    i := node_index(e, id)
    if i < 0 { return 0, .Unknown_Node }
    if len(desc.frames) == 0 || math.is_nan(desc.duration) || math.is_inf(desc.duration) || desc.duration < 0 || math.is_nan(desc.delay) || math.is_inf(desc.delay) || !(desc.iterations > 0) || !valid_easing(desc.easing) || int(desc.direction) > 3 || int(desc.fill) > 3 { return 0, .Invalid_Motion }
    if !math.is_inf(desc.iterations) && math.is_inf(desc.duration*desc.iterations) { return 0, .Invalid_Motion }
    if !valid_frames(desc.frames, true) { return 0, .Invalid_Motion }
    context.allocator = e.allocator
    playback := Playback{id = Animation_Id(e.next_animation+1), desc = desc, unstarted = true}
    e.next_animation += 1
    playback.desc.frames = clone_frames(e, desc.frames)
    append(&e.nodes[i].animations, playback)
    e.dirty = true
    return playback.id, .None
}
@(private)
free_playback :: proc(playback: Playback) {
    if playback.cascade { delete(playback.name); return }
    free_frames(playback.desc.frames)
}
@(private)
active_duration :: proc(d: Animation_Desc) -> f64 { return 0 if d.duration == 0 else d.duration*d.iterations }
cancel_animation :: proc(e: ^Engine, id: Node_Id, animation: Animation_Id) -> Error {
    i := node_index(e, id)
    if i < 0 { return .Unknown_Node }
    context.allocator = e.allocator
    for playback, j in e.nodes[i].animations {
        if playback.id == animation && !playback.cascade {
            if playback.started && !playback.ended { emit(e, {node = id, kind = .Animation_Cancel, animation = animation, elapsed = f32(max(0, e.last_time-playback.start))}) }
            free_playback(playback)
            ordered_remove(&e.nodes[i].animations, j)
            e.dirty = true
            return .None
        }
    }
    return .Invalid_Motion
}
pause_animation :: proc(e: ^Engine, id: Node_Id, animation: Animation_Id, paused: bool) -> Error {
    i := node_index(e, id)
    if i < 0 { return .Unknown_Node }
    for &playback in e.nodes[i].animations {
        if playback.id != animation || playback.cascade { continue }
        if paused {
            if playback.resume_pending { playback.resume_pending = false }
            else if !playback.paused { playback.paused_at = e.last_time; playback.paused = true }
        } else if playback.paused { playback.resume_pending = true }
        e.dirty = true
        return .None
    }
    return .Invalid_Motion
}
@(private)
resolve_playback_times :: proc(e: ^Engine, now: f64) {
    for &node in e.nodes {
        for &playback in node.animations {
            if playback.unstarted {
                playback.start = now+playback.desc.delay
                playback.paused_at = now
                playback.unstarted = false
            }
            if playback.resume_pending {
                playback.start += now-playback.paused_at
                playback.paused = false
                playback.resume_pending = false
            }
        }
    }
}
@(private)
animation_events :: proc(e: ^Engine, node: ^Record, now: f64) {
    if e.environment.reduced_motion { return }
    for &playback in node.animations {
        if playback.unstarted || playback.ended { continue }
        d := playback.desc
        time := (playback.paused_at if playback.paused else now)-playback.start
        if time < 0 { continue }
        event := Motion_Event{node = node.id, name = playback.name, animation = playback.id}
        if !playback.started {
            playback.started = true
            event.kind = .Animation_Start
            emit(e, event)
        }
        total := active_duration(d)
        if time >= total {
            playback.ended = true
            event.kind, event.elapsed = .Animation_End, f32(total)
            emit(e, event)
        } else if iteration := math.floor(time/d.duration); iteration > playback.iteration {
            playback.iteration = iteration
            event.kind, event.elapsed = .Animation_Iteration, f32(iteration*d.duration)
            emit(e, event)
        }
    }
}
@(private)
prune_animations :: proc(node: ^Record, now: f64) {
    #reverse for playback, i in node.animations {
        d := playback.desc
        if playback.cascade || playback.paused || d.fill == .Forwards || d.fill == .Both || now < playback.start+active_duration(d) { continue }
        free_playback(playback)
        ordered_remove(&node.animations, i)
    }
}
@(private)
animation_progress :: proc(playback: Playback, now: f64) -> (f32, bool) {
    d := playback.desc
    time := (playback.paused_at if playback.paused else now)-playback.start
    total := active_duration(d)
    before, after := time < 0, time >= total
    if before && d.fill != .Backwards && d.fill != .Both { return 0, false }
    if after && d.fill != .Forwards && d.fill != .Both { return 0, false }
    iteration, fraction: f64
    if before { iteration, fraction = 0, 0 }
    else if after {
        iteration = math.ceil(d.iterations)-1
        fraction = d.iterations-iteration
    } else {
        iteration = math.floor(time/d.duration)
        fraction = time/d.duration-iteration
    }
    reverse := d.direction == .Reverse || d.direction == .Alternate_Reverse
    if (d.direction == .Alternate || d.direction == .Alternate_Reverse) && math.mod(iteration, 2) == 1 { reverse = !reverse }
    if reverse { fraction = 1-fraction }
    return f32(fraction), true
}
@(private)
apply_animations :: proc(e: ^Engine, node, parent: ^Record, now: f64, base: Computed_Style) -> Computed_Style {
    result := base
    for playback in node.animations {
        progress, applies := animation_progress(playback, now)
        if !applies { continue }
        for p in Property {
            // author !important win over animation, that's the css spec
            if node.winners[p].important { continue }
            from, to := result[p], result[p]
            low, high: f32 = 0, 1
            touched, next_found := false, false
            easing := playback.desc.easing
            for frame in playback.desc.frames {
                for d in frame.declarations {
                    if d.property != p { continue }
                    value, ok := keyframe_value(e, node, parent, d, &result)
                    if !ok { continue }
                    touched = true
                    if frame.offset <= progress { from = value; low = frame.offset; easing = frame.easing.? or_else playback.desc.easing }
                    else if !next_found || frame.offset == high { to = value; high = frame.offset; next_found = true }
                }
            }
            if !touched { continue }
            if high == low { result[p] = from; continue }
            fraction := ease(easing, (progress-low)/(high-low))
            if interpolable(e, p, from, to) { result[p] = interpolate(e, from, to, fraction) }
            else { result[p] = from if fraction < 0.5 else to }
        }
    }
    return result
}

@(private)
animation_affects :: proc(node: ^Record, p: Property, now: f64) -> bool {
    if node.winners[p].important { return false }
    for playback in node.animations {
        _, applies := animation_progress(playback, now)
        if applies {
            for frame in playback.desc.frames { for d in frame.declarations { if d.property == p { return true } } }
        }
    }
    return false
}
