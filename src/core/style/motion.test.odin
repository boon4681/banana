#+build !wasm32
package style

import "core:testing"

@(test)
animated_inheritance_and_font_relative_dependents :: proc(t: ^testing.T) {
    scene: Scene
    scene[2].parent = 1
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 2); attach_node(e, 1)
    set_inline(e, 1, []Declaration{{property = .Font_Size, value = length(10)}, {property = .Padding_Left, value = length(1, .Em)}})
    set_inline(e, 2, []Declaration{{property = .Padding_Left, value = length(2, .Em)}})
    set_transitions(e, 1, []Transition{{property = .Font_Size, duration = 1}})
    update(e, 0)
    set_inline(e, 1, []Declaration{{property = .Font_Size, value = length(20)}, {property = .Padding_Left, value = length(1, .Em)}})
    update(e, 0); update(e, 0.5)
    parent, _ := presented_style(e, 1)
    child, _ := presented_style(e, 2)
    testing.expect_value(t, parent[.Font_Size], length(15))
    testing.expect_value(t, parent[.Padding_Left], length(15))
    testing.expect_value(t, child[.Font_Size], length(15))
    testing.expect_value(t, child[.Padding_Left], length(30))
}

@(test)
transition_interruption_reversal_and_cleanup :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(0)}})
    set_transitions(e, 1, []Transition{{property = .Width, duration = 1}})
    update(e, 0)
    testing.expect(t, !is_animating(e)) // first style does not transition
    set_inline(e, 1, []Declaration{{property = .Width, value = length(100)}})
    update(e, 0)
    update(e, 0.4)
    c, _ := presented_style(e, 1)
    testing.expect(t, abs(c[.Width].number-40) < 0.001)
    target, _ := computed_style(e, 1)
    testing.expect_value(t, target[.Width], length(100))
    set_inline(e, 1, []Declaration{{property = .Width, value = length(0)}})
    update(e, 0.4)
    c, _ = presented_style(e, 1); testing.expect(t, abs(c[.Width].number-40) < 0.001)
    update(e, 0.6)
    c, _ = presented_style(e, 1); testing.expect(t, abs(c[.Width].number-20) < 0.001)
    update(e, 0.81)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Width], length(0))
    testing.expect(t, !is_animating(e))
    set_inline(e, 1, []Declaration{{property = .Width, value = length(100)}})
    update(e, 1)
    detach_node(e, 1)
    testing.expect(t, !is_animating(e))
    _, err := update(e, 0.9); testing.expect_value(t, err, Error.Invalid_Time)
}

@(test)
transition_delay_reduced_motion_and_easing :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    set_inline(e, 1, []Declaration{{property = .Opacity, value = number(0)}})
    set_transitions(e, 1, []Transition{{property = .Opacity, duration = 2, delay = 1}})
    update(e, 0)
    set_inline(e, 1, []Declaration{{property = .Opacity, value = number(1)}})
    update(e, 0); update(e, 0.5)
    c, _ := presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0))
    update(e, 2)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0.5))
    set_environment(e, {root_font_size = 16, reduced_motion = true})
    update(e, 2)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(1))
    testing.expect(t, !is_animating(e))
    testing.expect(t, abs(ease({kind = .Cubic_Bezier, x1 = 0.42, x2 = 0.58, y2 = 1}, 0.5)-0.5) < 0.0001)
    testing.expect_value(t, ease({kind = .Steps, steps = 4}, 0.49), f32(0.25))
    testing.expect_value(t, ease({kind = .Steps, steps = 4, step_start = true}, 0), f32(0.25))
    middle := interpolate(e, rgba(1, 0, 0, 1), rgba(0, 0, 0, 0), 0.5)
    testing.expect_value(t, middle, rgba(1, 0, 0, 0.5))
    testing.expect_value(t, set_transitions(e, 1, []Transition{{property = .Width, duration = -1}}), Error.Invalid_Motion)
}

@(test)
keyframes_delay_alternate_fill_pause_and_cancel :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1); update(e, 0)
    frames := []Keyframe{
        {offset = 0, declarations = []Declaration{{property = .Opacity, value = number(0)}}},
        {offset = 1, declarations = []Declaration{{property = .Opacity, value = number(1)}}},
    }
    id, err := play_animation(e, 1, {frames = frames, duration = 1, delay = 1, iterations = 2, direction = .Alternate, fill = .Both})
    testing.expect_value(t, err, Error.None)
    frames[0].declarations[0].value = number(0.8) // engine owns the original
    update(e, 0)
    update(e, 0.5)
    c, _ := presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0))
    update(e, 1.5)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0.5))
    pause_animation(e, 1, id, true); update(e, 2.5)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0.5))
    pause_animation(e, 1, id, false); update(e, 3)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0.5)) // resumes from the paused frame
    update(e, 3.5)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(1))
    update(e, 4)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0.5))
    update(e, 4.5)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0))
    testing.expect(t, !is_animating(e))
    cancel_animation(e, 1, id); update(e, 4.5)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(1))
}

@(test)
animation_starts_at_next_update_and_finished_playbacks_are_pruned :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1); update(e, 0)
    frames := []Keyframe{
        {offset = 0, declarations = []Declaration{{property = .Opacity, value = number(0)}}},
        {offset = 1, declarations = []Declaration{{property = .Opacity, value = number(1)}}},
    }
    // host idle until t=10, animation must not start in the past
    id, _ := play_animation(e, 1, {frames = frames, duration = 1, iterations = 1})
    testing.expect(t, is_animating(e))
    update(e, 10)
    c, _ := presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0))
    testing.expect(t, is_animating(e))
    update(e, 10.5)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0.5))
    pause_animation(e, 1, id, true); update(e, 10.5)
    testing.expect(t, !is_animating(e))
    pause_animation(e, 1, id, false)
    update(e, 50) // idle while paused
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(0.5))
    update(e, 51)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Opacity], number(1))
    testing.expect_value(t, len(e.nodes[0].animations), 0)
    testing.expect_value(t, cancel_animation(e, 1, id), Error.Invalid_Motion)
    kept, _ := play_animation(e, 1, {frames = frames, duration = 1, iterations = 1, fill = .Forwards})
    update(e, 51); update(e, 60)
    testing.expect_value(t, len(e.nodes[0].animations), 1)
    testing.expect_value(t, cancel_animation(e, 1, kept), Error.None)
}

@(test)
overflowing_relative_length_falls_back_without_failing_update :: proc(t: ^testing.T) {
    scene: Scene
    scene[2].parent = 1
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1); attach_node(e, 2)
    set_inline(e, 1, []Declaration{{property = .Font_Size, value = length(20)}})
    set_inline(e, 2, []Declaration{
        {property = .Width, value = length(3e38, .Em)},
        {property = .Font_Size, value = length(3e38, .Em)},
        {property = .Height, value = length(2, .Em)},
    })
    _, err := update(e, 0); testing.expect_value(t, err, Error.None)
    c, _ := presented_style(e, 2)
    testing.expect_value(t, c[.Width], keyword(.Auto))
    testing.expect_value(t, c[.Font_Size], length(20))
    testing.expect_value(t, c[.Height], length(40))
}

@(test)
keyframe_implicit_endpoints_importance_and_negative_delay :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(20)}})
    update(e, 0)
    id, err := play_animation(e, 1, {
        frames = []Keyframe{{offset = 0.5, declarations = []Declaration{{property = .Width, value = length(100)}}}},
        duration = 2, delay = -0.5, iterations = 1, fill = .Forwards,
    })
    testing.expect_value(t, err, Error.None)
    update(e, 0)
    c, _ := presented_style(e, 1); testing.expect_value(t, c[.Width], length(60))
    set_inline(e, 1, []Declaration{{property = .Width, value = length(30), important = true}})
    update(e, 0.5)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Width], length(30))
    set_inline(e, 1, []Declaration{{property = .Width, value = length(20)}})
    update(e, 1.5)
    c, _ = presented_style(e, 1); testing.expect_value(t, c[.Width], length(20))
    cancel_animation(e, 1, id)
    _, err = play_animation(e, 1, {duration = f64(0h7ff0_0000_0000_0000)})
    testing.expect_value(t, err, Error.Invalid_Motion)
}
