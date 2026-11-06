#+build !wasm32
package style

import "core:testing"
import "core:math"

@(private="file")
class_selector :: proc(tests: []Selector_Test, steps: []Selector_Step, selectors: []Selector, name: string) -> []Selector {
    tests[0] = {kind = .Class, name = name}
    steps[0] = {tests = tests}
    selectors[0] = {steps = steps}
    return selectors
}

@(test)
transition_longhands_cascade_independently :: proc(t: ^testing.T) {
    scene: Scene
    scene[1].classes = []string{"btn"}
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    tests: [2][1]Selector_Test; steps: [2][1]Selector_Step; selectors: [2][1]Selector
    _, err := add_stylesheet(e, {version = IR_VERSION, rules = []Rule{
        {selectors = class_selector(tests[0][:], steps[0][:], selectors[0][:], "btn"), motion = []Motion_Declaration{
            {property = .Transition_Property, items = []Motion_Item{{property = .Opacity}, {property = .Width}}},
            {property = .Transition_Duration, items = []Motion_Item{{seconds = 1}, {seconds = 4}}},
            {property = .Transition_Timing_Function, items = []Motion_Item{{}}},
        }},
        {selectors = class_selector(tests[1][:], steps[1][:], selectors[1][:], "slow"), motion = []Motion_Declaration{
            {property = .Transition_Duration, items = []Motion_Item{{seconds = 2}}},
        }},
    }})
    testing.expect_value(t, err, Error.None)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(0)}, {property = .Opacity, value = number(1)}})
    update(e, 0)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(100)}, {property = .Opacity, value = number(0)}})
    update(e, 0); update(e, 0.5)
    c, _ := presented_style(e, 1)
    testing.expect_value(t, c[.Opacity], number(0.5))
    testing.expect_value(t, c[.Width], length(12.5))
    update(e, 10)
    // later rule only override duration, the one entry must repeat for both properties
    scene[1].classes = []string{"btn", "slow"}; classes_changed(e, 1)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(0)}, {property = .Opacity, value = number(1)}})
    update(e, 10); update(e, 11)
    c, _ = presented_style(e, 1)
    testing.expect_value(t, c[.Opacity], number(0.5))
    testing.expect_value(t, c[.Width], length(50))
    update(e, 20)
    testing.expect(t, !is_animating(e))
    // inline beat sheet rules; empty property list = none
    testing.expect_value(t, set_inline_motion(e, 1, []Motion_Declaration{{property = .Transition_Property}}), Error.None)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(100)}})
    update(e, 20)
    c, _ = presented_style(e, 1)
    testing.expect_value(t, c[.Width], length(100))
}

@(test)
animation_name_runs_registry_keyframes :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    set_inline(e, 1, []Declaration{{property = .Font_Size, value = length(10)}})
    hold := Easing{kind = .Steps, steps = 1}
    tests: [1]Selector_Test; steps: [1]Selector_Step; selectors: [1]Selector
    _, err := add_stylesheet(e, {
        version = IR_VERSION,
        rules = []Rule{{selectors = class_selector(tests[:], steps[:], selectors[:], "spin"), motion = []Motion_Declaration{
            {property = .Animation_Name, items = []Motion_Item{{name = "pulse"}, {name = "blink"}, {name = "undefined"}}},
            {property = .Animation_Duration, items = []Motion_Item{{seconds = 2}}},
            {property = .Animation_Timing_Function, items = []Motion_Item{{}}},
            {property = .Animation_Iteration_Count, items = []Motion_Item{{count = math.inf_f32(1)}}},
            {property = .Animation_Direction, items = []Motion_Item{{direction = .Alternate}}},
        }}},
        keyframes = []Keyframes_Desc{
            {name = "pulse", frames = []Keyframe{
                {offset = 0, declarations = []Declaration{{property = .Width, value = length(1, .Em)}}},
                {offset = 1, declarations = []Declaration{{property = .Width, value = length(3, .Em)}}},
            }},
            {name = "blink", frames = []Keyframe{
                {offset = 0, declarations = []Declaration{{property = .Opacity, value = number(0)}}, easing = hold},
                {offset = 1, declarations = []Declaration{{property = .Opacity, value = number(1)}}},
            }},
        },
    })
    testing.expect_value(t, err, Error.None)
    update(e, 0)
    testing.expect(t, !is_animating(e))
    scene[1].classes = []string{"spin"}; classes_changed(e, 1)
    update(e, 0); update(e, 1)
    c, _ := presented_style(e, 1)
    testing.expect_value(t, c[.Width], length(20))
    testing.expect_value(t, c[.Opacity], number(0)) // per-keyframe steps easing hold the first frame
    update(e, 2.5) // alternate, second iteration run backwards
    c, _ = presented_style(e, 1)
    testing.expect_value(t, c[.Width], length(25))
    testing.expect(t, is_animating(e))
    // unrelated restyle must not restart a running animation
    set_inline_motion(e, 1, []Motion_Declaration{{property = .Animation_Play_State, items = []Motion_Item{{paused = true}}}})
    update(e, 3); update(e, 8)
    c, _ = presented_style(e, 1)
    testing.expect_value(t, c[.Width], length(20))
    testing.expect(t, !is_animating(e))
    set_inline_motion(e, 1, nil)
    update(e, 9); update(e, 9.5)
    c, _ = presented_style(e, 1)
    testing.expect_value(t, c[.Width], length(15))
    scene[1].classes = nil; classes_changed(e, 1)
    update(e, 10)
    c, _ = presented_style(e, 1)
    testing.expect_value(t, c[.Width], keyword(.Auto))
    testing.expect_value(t, c[.Opacity], number(1))
    testing.expect_value(t, len(e.nodes[0].animations), 0)
    _, err = add_stylesheet(e, {version = IR_VERSION, rules = []Rule{{selectors = class_selector(tests[:], steps[:], selectors[:], "bad"), motion = []Motion_Declaration{
        {property = .Animation_Iteration_Count, items = []Motion_Item{{count = 0}}},
    }}}})
    testing.expect_value(t, err, Error.Invalid_Motion)
}
