#+build !wasm32
package style

import "core:testing"

@(test)
missing_callbacks_and_forked_siblings_are_rejected :: proc(t: ^testing.T) {
    bare := create({parent = proc(_: rawptr, _: Node_Id) -> Node_Id { return 0 }})
    defer destroy(bare)
    _, err := add_rule(bare, []Selector_Test{{kind = .Class, name = "a", negate = true}}, []Declaration{{property = .Color, value = RED}})
    testing.expect_value(t, err, Error.Missing_Tree_API)
    scene: Scene
    scene[2].parent = 1; scene[3].parent = 1
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1); attach_node(e, 2); attach_node(e, 3)
    _, err = update(e); testing.expect_value(t, err, Error.Invalid_Tree)
    scene[3].previous = 2
    _, err = update(e); testing.expect_value(t, err, Error.None)
}

@(test)
attribute_operators_and_negation :: proc(t: ^testing.T) {
    scene: Scene
    scene[1].role = "EN-us\t primary\n action"
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    tests := []Selector_Test{
        {kind = .Attribute_Includes, name = "role", value = "primary"},
        {kind = .Attribute_Prefix, name = "role", value = "en-", ascii_insensitive = true},
        {kind = .Attribute_Suffix, name = "role", value = "action"},
        {kind = .Attribute_Substring, name = "role", value = "mary\n"},
        {kind = .Class, name = "excluded", negate = true},
    }
    sheet, err := add_rule(e, tests, []Declaration{{property = .Color, value = RED}})
    testing.expect_value(t, err, Error.None)
    update(e); expect_color(t, e, 1, RED)
    winner, _ := explain(e, 1, .Color)
    testing.expect_value(t, winner.specificity, Specificity{0, 5, 0})
    scene[1].classes = []string{"excluded"}; classes_changed(e, 1)
    update(e); expect_color(t, e, 1, BLACK)
    remove_stylesheet(e, sheet)
    scene[1].role = "en-US"
    add_rule(e, []Selector_Test{{kind = .Attribute_Dash, name = "role", value = "en"}}, []Declaration{{property = .Color, value = BLUE}})
    update(e); expect_color(t, e, 1, BLUE)
    empty_ops := []Test_Kind{.Attribute_Includes, .Attribute_Prefix, .Attribute_Suffix, .Attribute_Substring}
    for op in empty_ops { testing.expect(t, !attribute_matches("anything", {kind = op})) }
    testing.expect(t, attribute_matches("", {kind = .Attribute_Equals}))
    testing.expect(t, !attribute_matches("x\vaction", {kind = .Attribute_Includes, value = "action"}))
}

@(test)
structural_selectors_reorder_and_negative_nth :: proc(t: ^testing.T) {
    scene: Scene
    scene[1].tag = "root"
    scene[2] = {parent = 1, tag = "button"}
    scene[3] = {parent = 1, previous = 2, tag = "text"}
    scene[4] = {parent = 1, previous = 3, tag = "button"}
    e := make_engine(&scene); defer destroy(e)
    for id in 1..<5 { attach_node(e, Node_Id(id)) }
    update(e)
    testing.expect(t, matches_test(e, 1, {kind = .Root}))
    testing.expect(t, !matches_test(e, 1, {kind = .Empty}))
    testing.expect(t, matches_test(e, 3, {kind = .Only_Of_Type}))
    testing.expect(t, matches_test(e, 2, {kind = .First_Child}))
    testing.expect(t, matches_test(e, 4, {kind = .Last_Child}))
    testing.expect(t, matches_test(e, 4, {kind = .Nth_Last_Of_Type, a = 0, b = 1}))
    testing.expect(t, matches_test(e, 2, {kind = .Nth_Child, a = -1, b = 2}))
    testing.expect(t, !matches_test(e, 4, {kind = .Nth_Child, a = -1, b = 2}))
    add_rule(e, []Selector_Test{{kind = .Nth_Of_Type, a = 2, b = 1}}, []Declaration{{property = .Background_Color, value = RED}})
    update(e)
    c, _ := computed_style(e, 2); testing.expect_value(t, c[.Background_Color], RED)
    // move button 4 before 2 without touching attach order, tree order must win
    scene[4].previous = 0; scene[2].previous = 4; scene[3].previous = 2
    children_changed(e, 1); update(e)
    c, _ = computed_style(e, 2); testing.expect_value(t, c[.Background_Color], rgba(0, 0, 0, 0))
    c, _ = computed_style(e, 4); testing.expect_value(t, c[.Background_Color], RED)
    e.tree.has_text = proc(d: rawptr, n: Node_Id) -> bool { return n == 3 }
    testing.expect(t, !matches_test(e, 3, {kind = .Empty}))
    testing.expect(t, matches_test(e, 4, {kind = .Empty}))
}

@(test)
relative_values_inheritance_and_responsive_changes :: proc(t: ^testing.T) {
    scene: Scene
    scene[2].parent = 1; scene[3].parent = 2
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 3); attach_node(e, 2); attach_node(e, 1)
    testing.expect_value(t, set_environment(e, {width = 1000, height = 500, root_font_size = 16}), Error.None)
    set_inline(e, 1, []Declaration{{property = .Font_Size, value = length(2, .Rem)}, {property = .Line_Height, value = number(1.5)}})
    set_inline(e, 2, []Declaration{
        {property = .Font_Size, value = length(50, .Percent)},
        {property = .Padding_Left, value = length(2, .Em)},
        {property = .Margin_Top, value = length(-1, .Rem)},
        {property = .Width, value = length(50, .Vw)},
        {property = .Height, value = length(1, .In)},
    })
    _, err := update(e); testing.expect_value(t, err, Error.None)
    c, _ := computed_style(e, 2)
    testing.expect_value(t, c[.Font_Size], length(16))
    testing.expect_value(t, c[.Padding_Left], length(32))
    testing.expect_value(t, c[.Margin_Top], length(-32))
    testing.expect_value(t, c[.Width], length(500))
    testing.expect_value(t, c[.Height], length(96))
    c, _ = computed_style(e, 3)
    testing.expect_value(t, c[.Font_Size], length(16))
    testing.expect_value(t, c[.Line_Height], number(1.5))
    add_stylesheet(e, {version = IR_VERSION, rules = []Rule{{
        selectors = []Selector{{steps = []Selector_Step{{tests = []Selector_Test{{kind = .Root}}}}}},
        declarations = []Declaration{{property = .Color, value = RED}},
        conditions = []Media_Test{{feature = .Min_Width, value = 800}, {feature = .Landscape}},
    }}})
    update(e); expect_color(t, e, 3, RED)
    set_environment(e, {width = 400, height = 600, root_font_size = 16})
    changes, _ := update(e); testing.expect(t, len(changes) > 0)
    expect_color(t, e, 3, BLACK)
    c, _ = computed_style(e, 2); testing.expect_value(t, c[.Width], length(200))
    testing.expect_value(t, set_environment(e, {width = -1, root_font_size = 16}), Error.Invalid_Environment)
}

@(test)
property_validation_currentcolor_and_reset :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    for p in Property { testing.expect(t, valid_value(p, initial(p))) }
    invalid := []Declaration{
        {property = .Padding_Top, value = length(-1)},
        {property = .Border_Left_Width, value = length(10, .Percent)},
        {property = .Font_Weight, value = number(350)},
        {property = .Flex_Grow, value = number(-1)},
        {property = .Display, value = length(10)},
    }
    for d in invalid { testing.expect_value(t, set_inline(e, 1, []Declaration{d}), Error.Invalid_Declaration) }
    set_inline(e, 1, []Declaration{
        {property = .Color, value = RED},
        {property = .Background_Color, value = keyword(.Current_Color)},
        {property = .Overflow_Y, value = keyword(.Hidden)},
        {property = .Line_Height, value = length(150, .Percent)},
    })
    update(e)
    c, _ := computed_style(e, 1)
    testing.expect_value(t, c[.Background_Color], RED)
    testing.expect_value(t, c[.Overflow_X], keyword(.Auto))
    testing.expect_value(t, c[.Line_Height], length(24))
    clear_inline(e, 1); update(e)
    c, _ = computed_style(e, 1)
    testing.expect_value(t, c[.Overflow_X], keyword(.Visible))
    testing.expect_value(t, c[.Background_Color], rgba(0, 0, 0, 0))
}
