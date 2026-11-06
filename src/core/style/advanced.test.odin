#+build !wasm32
package style

import "core:testing"

class_test :: proc(name: string) -> Selector_Test { return {kind = .Class, name = name} }
one :: proc(tests: []Selector_Test, next := Combinator.None) -> Selector {
    steps := make([]Selector_Step, 1, context.temp_allocator)
    steps[0] = {tests = tests, next = next}
    return {steps = steps}
}

@(test)
is_where_not_list_and_has :: proc(t: ^testing.T) {
    scene: Scene
    scene[1] = {classes = []string{"card"}}
    scene[2] = {parent = 1, classes = []string{"title"}}
    scene[3] = {parent = 1, previous = 2, classes = []string{"body"}}
    scene[4] = {parent = 3, classes = []string{"icon"}}
    e := make_engine(&scene); defer destroy(e)
    for id in 1..<5 { attach_node(e, Node_Id(id)) }
    update(e)
    is_test := Selector_Test{kind = .Is, selectors = []Selector{one({class_test("title")}), one({{kind = .Id, name = "x"}})}}
    testing.expect(t, matches_test(e, 2, is_test))
    testing.expect(t, !matches_test(e, 3, is_test))
    not_list := is_test
    not_list.negate = true
    testing.expect(t, matches_test(e, 3, not_list))
    testing.expect_value(t, specificity(one({is_test})), Specificity{1, 0, 0})
    where_test := is_test
    where_test.kind = .Where
    testing.expect_value(t, specificity(one({where_test})), Specificity{0, 0, 0})
    child_icon := Selector_Test{kind = .Has, selectors = []Selector{one({class_test("icon")}, .Child)}}
    any_icon := Selector_Test{kind = .Has, selectors = []Selector{one({class_test("icon")}, .Descendant)}}
    next_body := Selector_Test{kind = .Has, selectors = []Selector{one({class_test("body")}, .Adjacent_Sibling)}}
    testing.expect(t, !matches_test(e, 1, child_icon))
    testing.expect(t, matches_test(e, 3, child_icon))
    testing.expect(t, matches_test(e, 1, any_icon))
    testing.expect(t, !matches_test(e, 4, any_icon))
    testing.expect(t, matches_test(e, 2, next_body))
    testing.expect(t, !matches_test(e, 3, next_body))
    testing.expect(t, matches_test(e, 1, {kind = .First_Child}) && matches_test(e, 1, {kind = .Only_Child}))
    _, err := add_rule(e, []Selector_Test{class_test("card"), any_icon}, []Declaration{{property = .Color, value = RED}})
    testing.expect_value(t, err, Error.None)
    update(e); expect_color(t, e, 1, RED)
    scene[4].classes = nil; classes_changed(e, 4)
    update(e); expect_color(t, e, 1, BLACK)
    _, err = add_rule(e, []Selector_Test{{kind = .Has}}, nil)
    testing.expect_value(t, err, Error.Invalid_Selector)
    _, err = add_rule(e, []Selector_Test{{kind = .Has, selectors = []Selector{one({class_test("a")})}}}, nil)
    testing.expect_value(t, err, Error.Invalid_Selector)
    scene[1].states = {.Focus_Within}; states_changed(e, 1)
    add_rule(e, []Selector_Test{{kind = .State, state = .Focus_Within}}, []Declaration{{property = .Color, value = BLUE}})
    update(e); expect_color(t, e, 1, BLUE)
}

@(test)
pseudo_elements_have_their_own_style :: proc(t: ^testing.T) {
    scene: Scene
    scene[1] = {tag = "input"}
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    set_inline(e, 1, []Declaration{{property = .Color, value = RED}, {property = .Font_Size, value = length(20)}})
    update(e)
    testing.expect(t, pseudo_style(e, 1, .Placeholder) == nil)
    sheet, err := add_stylesheet(e, {version = IR_VERSION, rules = []Rule{{
        selectors = []Selector{{steps = []Selector_Step{{tests = []Selector_Test{{kind = .Tag, name = "input"}}}}, pseudo = .Placeholder}},
        declarations = []Declaration{{property = .Background_Color, value = BLUE}, {property = .Width, value = length(2, .Em)}},
    }}})
    testing.expect_value(t, err, Error.None)
    changes, _ := update(e)
    testing.expect(t, len(changes) == 1 && changes[0].pseudo && changes[0].properties == {})
    placeholder := pseudo_style(e, 1, .Placeholder)
    testing.expect(t, placeholder != nil)
    testing.expect_value(t, placeholder[.Background_Color], BLUE)
    testing.expect_value(t, placeholder[.Color], RED)
    testing.expect_value(t, placeholder[.Width], length(40))
    own, _ := computed_style(e, 1)
    testing.expect_value(t, own[.Background_Color], rgba(0, 0, 0, 0))
    remove_stylesheet(e, sheet)
    changes, _ = update(e)
    testing.expect(t, len(changes) == 1 && pseudo_style(e, 1, .Placeholder) == nil)
}

@(test)
custom_properties_inherit_substitute_and_fail_safely :: proc(t: ^testing.T) {
    scene: Scene
    scene[2].parent = 1
    scene[3].parent = 2
    e := make_engine(&scene); defer destroy(e)
    for id in 1..<4 { attach_node(e, Node_Id(id)) }
    testing.expect_value(t, set_inline_custom(e, 1, []Custom_Declaration{
        {name = "--gap", declaration = {value = length(2, .Em)}},
        {name = "--accent", declaration = {value = RED}},
        {name = "--double", declaration = calc(.Width, {}, false)},
        {name = "--n", declaration = {value = number(3)}},
        {name = "--loop-a", declaration = {variable = "--loop-b"}},
        {name = "--loop-b", declaration = {variable = "--loop-a"}},
    }), Error.None)
    set_inline_custom(e, 2, []Custom_Declaration{{name = "--gap", declaration = {value = length(10)}}})
    set_inline(e, 1, []Declaration{{property = .Font_Size, value = length(10)}})
    doubled := calc(.Padding_Left, {})
    doubled.vars = []Calc_Var{{name = "--gap", factor = 2}, {name = "--n", factor = 1, unit = .Px, numeric = true}}
    set_inline(e, 3, []Declaration{
        {property = .Font_Size, value = length(30)},
        {property = .Color, variable = "--accent"},
        {property = .Width, variable = "--gap"},
        {property = .Height, variable = "--missing", has_fallback = true, value = length(7)},
        {property = .Min_Width, variable = "--missing"},
        {property = .Max_Width, variable = "--accent"},
        {property = .Margin_Left, variable = "--loop-a", has_fallback = true, value = length(4)},
        doubled,
    })
    update(e)
    c, _ := computed_style(e, 3)
    testing.expect_value(t, c[.Color], RED)
    testing.expect_value(t, c[.Width], length(10))
    testing.expect_value(t, c[.Height], length(7))
    testing.expect_value(t, c[.Min_Width], keyword(.Auto))
    testing.expect_value(t, c[.Max_Width], keyword(.None))
    testing.expect_value(t, c[.Margin_Left], length(4))
    testing.expect_value(t, c[.Padding_Left], length(23))
    set_inline(e, 2, []Declaration{{property = .Font_Size, value = length(5)}, {property = .Width, variable = "--gap"}})
    clear_inline(e, 3)
    set_inline_custom(e, 2, nil)
    set_inline(e, 3, []Declaration{{property = .Font_Size, value = length(30)}, {property = .Width, variable = "--gap"}})
    update(e)
    c, _ = computed_style(e, 2); testing.expect_value(t, c[.Width], length(10))
    c, _ = computed_style(e, 3); testing.expect_value(t, c[.Width], length(60))
    v, ok := custom_value(e, 3, "--n")
    testing.expect(t, ok && v == number(3))
    _, ok = custom_value(e, 3, "--loop-a")
    testing.expect(t, !ok)
    testing.expect_value(t, set_inline_custom(e, 1, []Custom_Declaration{{name = "gap"}}), Error.Invalid_Declaration)
}

@(test)
custom_property_dependencies_use_the_declaring_scope :: proc(t: ^testing.T) {
    scene: Scene
    scene[2].parent = 1
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1); attach_node(e, 2)
    set_inline_custom(e, 1, []Custom_Declaration{
        {name = "--base", declaration = {value = length(10)}},
        {name = "--size", declaration = {variable = "--base"}},
    })
    set_inline_custom(e, 2, []Custom_Declaration{{name = "--base", declaration = {value = length(99)}}})
    set_inline(e, 2, []Declaration{{property = .Width, variable = "--size"}, {property = .Height, variable = "--base"}})
    update(e)
    c, _ := computed_style(e, 2)
    testing.expect_value(t, c[.Width], length(10))
    testing.expect_value(t, c[.Height], length(99))
}

@(test)
min_max_clamp_and_font_relative_units :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    set_environment(e, {width = 1000, height = 500, root_font_size = 16})
    clamped := Declaration{property = .Font_Size, value = MATH, math = []Math_Op{
        {kind = .Term, calc = #partial {.Px = 12}}, {kind = .Term, calc = #partial {.Vw = 5}}, {kind = .Term, calc = #partial {.Px = 40}}, {kind = .Clamp},
    }}
    fluid := Declaration{property = .Width, value = MATH, math = []Math_Op{
        {kind = .Term, calc = #partial {.Percent = 100}}, {kind = .Term, calc = #partial {.Px = 500}}, {kind = .Min, count = 2},
        {kind = .Term, calc = #partial {.Px = 20}}, {kind = .Sub},
    }}
    testing.expect_value(t, set_inline(e, 1, []Declaration{
        clamped, fluid,
        {property = .Height, value = length(2, .Ch)},
        {property = .Padding_Top, value = length(2, .Ex)},
    }), Error.None)
    update(e)
    c, _ := computed_style(e, 1)
    testing.expect_value(t, c[.Font_Size], length(40))
    testing.expect_value(t, c[.Width].unit, Unit.Math)
    testing.expect_value(t, evaluate(e, c[.Width], 300), f32(280))
    testing.expect_value(t, evaluate(e, c[.Width], 900), f32(480))
    testing.expect_value(t, c[.Height], length(40))
    set_font_metrics(e, proc(_: rawptr, _: Node_Id, _: []string, weight: f32) -> (ex, ch: f32) { return 0.25, weight/1000 })
    update(e)
    c, _ = computed_style(e, 1)
    testing.expect_value(t, c[.Height], length(32))
    testing.expect_value(t, c[.Padding_Top], length(20))
    first := c[.Width]
    update(e)
    c, _ = computed_style(e, 1)
    testing.expect_value(t, c[.Width], first)
    clear_inline(e, 1); update(e)
    testing.expect(t, !e.expressions[int(first.number)].used)
    broken := fluid
    broken.math = fluid.math[:3]
    testing.expect_value(t, set_inline(e, 1, []Declaration{broken}), Error.None)
    broken.math = fluid.math[2:]
    testing.expect_value(t, set_inline(e, 1, []Declaration{broken}), Error.Invalid_Declaration)
}

@(test)
transform_lists_resolve_and_interpolate :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    list := proc(x: f32, degrees: f32) -> Declaration {
        @(static) ops: [2]Transform_Op
        ops = {{kind = .Translate, x = length(x, .Em), y = length(50, .Percent)}, {kind = .Rotate, numbers = {0 = degrees}}}
        return {property = .Transform, value = TRANSFORM, transform = ops[:]}
    }
    set_inline(e, 1, []Declaration{{property = .Font_Size, value = length(10)}, list(1, 0)})
    set_transitions(e, 1, []Transition{{property = .Transform, duration = 1, easing = {kind = .Linear}}})
    update(e, 0)
    c, _ := computed_style(e, 1)
    ops := transform_ops(e, c[.Transform])
    testing.expect_value(t, len(ops), 2)
    testing.expect_value(t, ops[0].x, length(10))
    testing.expect_value(t, ops[0].y, length(50, .Percent))
    set_inline(e, 1, []Declaration{{property = .Font_Size, value = length(10)}, list(3, 90)})
    update(e, 0); update(e, 0.5)
    c, _ = presented_style(e, 1)
    ops = transform_ops(e, c[.Transform])
    testing.expect_value(t, ops[0].x, length(20))
    testing.expect_value(t, ops[1].numbers[0], f32(45))
    update(e, 1)
    set_inline(e, 1, nil)
    update(e, 1); update(e, 1.5)
    c, _ = presented_style(e, 1)
    ops = transform_ops(e, c[.Transform])
    testing.expect_value(t, ops[1].numbers[0], f32(45))
    update(e, 2)
    c, _ = presented_style(e, 1)
    testing.expect_value(t, c[.Transform], keyword(.None))
}

@(test)
motion_events_and_font_faces :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    kinds := proc(e: ^Engine) -> (set: bit_set[Motion_Event_Kind]) {
        for event in motion_events(e) { set += {event.kind} }
        return
    }
    set_inline(e, 1, []Declaration{{property = .Width, value = length(0)}})
    set_transitions(e, 1, []Transition{{property = .Width, duration = 1, delay = 1}})
    update(e, 0)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(100)}})
    update(e, 0)
    testing.expect_value(t, kinds(e), bit_set[Motion_Event_Kind]{.Transition_Run})
    update(e, 1.5)
    testing.expect_value(t, kinds(e), bit_set[Motion_Event_Kind]{.Transition_Start})
    update(e, 1.6)
    testing.expect_value(t, len(motion_events(e)), 0)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(0)}})
    update(e, 1.6)
    testing.expect_value(t, kinds(e), bit_set[Motion_Event_Kind]{.Transition_Cancel, .Transition_Run})
    update(e, 10)
    testing.expect(t, .Transition_End in kinds(e))
    sheet, err := add_stylesheet(e, {
        version = IR_VERSION,
        rules = []Rule{{
            selectors = []Selector{one({{kind = .Universal}})},
            motion = []Motion_Declaration{
                {property = .Animation_Name, items = []Motion_Item{{name = "pulse"}}},
                {property = .Animation_Duration, items = []Motion_Item{{seconds = 1}}},
                {property = .Animation_Iteration_Count, items = []Motion_Item{{count = 2}}},
            },
        }},
        keyframes = []Keyframes_Desc{{name = "pulse", frames = []Keyframe{
            {offset = 0, declarations = []Declaration{{property = .Opacity, value = number(0)}}},
            {offset = 1, declarations = []Declaration{{property = .Opacity, value = number(1)}}},
        }}},
        font_faces = []Font_Face{{family = "Inter", source = "fonts/inter.ttf"}},
    })
    testing.expect_value(t, err, Error.None)
    testing.expect_value(t, e.font_face_generation, u64(1))
    faces := font_faces(e)
    testing.expect(t, len(faces) == 1 && faces[0].family == "Inter")
    update(e, 10)
    testing.expect_value(t, kinds(e), bit_set[Motion_Event_Kind]{.Animation_Start})
    testing.expect_value(t, motion_events(e)[0].name, "pulse")
    update(e, 11.5)
    testing.expect_value(t, kinds(e), bit_set[Motion_Event_Kind]{.Animation_Iteration})
    update(e, 12.5)
    testing.expect_value(t, kinds(e), bit_set[Motion_Event_Kind]{.Animation_End})
    update(e, 13)
    testing.expect_value(t, len(motion_events(e)), 0)
    remove_stylesheet(e, sheet)
    update(e, 13)
}
