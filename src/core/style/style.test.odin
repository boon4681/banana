#+build !wasm32
package style

import "core:testing"

Test_Node :: struct {
    parent, previous: Node_Id,
    tag, id: string,
    classes: []string,
    states: State_Set,
    role: string,
}
Scene :: [5]Test_Node
scene_node :: proc(data: rawptr, id: Node_Id) -> ^Test_Node {
    scene := cast(^Scene)data
    return &scene[id]
}
make_engine :: proc(scene: ^Scene) -> ^Engine {
    return create({
        data = scene,
        parent = proc(d: rawptr, n: Node_Id) -> Node_Id { return scene_node(d, n).parent },
        previous_sibling = proc(d: rawptr, n: Node_Id) -> Node_Id { return scene_node(d, n).previous },
        tag = proc(d: rawptr, n: Node_Id) -> string { return scene_node(d, n).tag },
        id = proc(d: rawptr, n: Node_Id) -> string { return scene_node(d, n).id },
        classes = proc(d: rawptr, n: Node_Id) -> []string { return scene_node(d, n).classes },
        states = proc(d: rawptr, n: Node_Id) -> State_Set { return scene_node(d, n).states },
        attribute = proc(d: rawptr, n: Node_Id, key: string) -> (string, bool) {
            v := scene_node(d, n).role
            return v, key == "role" && v != ""
        },
    })
}
add_rule :: proc(e: ^Engine, tests: []Selector_Test, declarations: []Declaration, options := Sheet_Options{origin = .Author}) -> (Sheet_Id, Error) {
    return add_stylesheet(e, {version = IR_VERSION, rules = []Rule{{
        selectors = []Selector{{steps = []Selector_Step{{tests = tests}}}},
        declarations = declarations,
    }}}, options)
}
expect_color :: proc(t: ^testing.T, e: ^Engine, n: Node_Id, color: Value) {
    computed, ok := computed_style(e, n)
    testing.expect(t, ok)
    testing.expect_value(t, computed[.Color], color)
}
RED :: Value{kind = .Color, color = {1, 0, 0, 1}}
BLUE :: Value{kind = .Color, color = {0, 0, 1, 1}}
BLACK :: Value{kind = .Color, color = {0, 0, 0, 1}}

@(test)
ancestor_hover_and_removal :: proc(t: ^testing.T) {
    scene: Scene
    scene[1] = {classes = []string{"panel"}}
    scene[2] = {parent = 1, classes = []string{"action"}}
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 2); attach_node(e, 1) // deliberately child-first
    _, err := add_stylesheet(e, {version = IR_VERSION, rules = []Rule{{
        selectors = []Selector{{steps = []Selector_Step{
            {tests = []Selector_Test{{kind = .Class, name = "action"}}, next = .Child},
            {tests = []Selector_Test{{kind = .Class, name = "panel"}, {kind = .State, state = .Hover}}},
        }}}, declarations = []Declaration{{property = .Color, value = RED}},
    }}})
    testing.expect_value(t, err, Error.None)
    _, err = update(e); testing.expect_value(t, err, Error.None)
    expect_color(t, e, 2, BLACK)
    scene[1].states = {.Hover}; states_changed(e, 1)
    changes, update_error := update(e)
    testing.expect_value(t, update_error, Error.None)
    testing.expect_value(t, len(changes), 1)
    testing.expect(t, changes[0].affects_paint && !changes[0].affects_layout)
    expect_color(t, e, 2, RED)
    winner, ok := explain(e, 2, .Color)
    testing.expect(t, ok && winner.found)
    testing.expect_value(t, winner.specificity, Specificity{0, 3, 0})
    scene[1].states = {}; states_changed(e, 1)
    update(e); expect_color(t, e, 2, BLACK)
    changes, _ = update(e); testing.expect_value(t, len(changes), 0)
}

@(test)
cascade_class_order_importance_and_inheritance :: proc(t: ^testing.T) {
    scene: Scene
    scene[1] = {id = "root", classes = []string{"a", "b"}}
    scene[2].parent = 1
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1); attach_node(e, 2)
    first, _ := add_rule(e, []Selector_Test{{kind = .Class, name = "a"}}, []Declaration{{property = .Color, value = RED}})
    second, _ := add_rule(e, []Selector_Test{{kind = .Class, name = "b"}}, []Declaration{{property = .Color, value = BLUE}})
    update(e); expect_color(t, e, 1, BLUE); expect_color(t, e, 2, BLUE)
    scene[1].classes = []string{"b", "a", "b"}; classes_changed(e, 1)
    changes, _ := update(e); testing.expect_value(t, len(changes), 0)
    set_inline(e, 1, []Declaration{{property = .Color, value = RED}})
    update(e); expect_color(t, e, 1, RED)
    important, _ := add_rule(e, []Selector_Test{{kind = .Class, name = "b"}}, []Declaration{{property = .Color, value = BLUE, important = true}})
    update(e); expect_color(t, e, 1, BLUE)
    set_inline(e, 1, []Declaration{{property = .Color, value = RED, important = true}})
    update(e); expect_color(t, e, 1, RED)
    clear_inline(e, 1); remove_stylesheet(e, important)
    remove_stylesheet(e, second)
    update(e); expect_color(t, e, 2, RED)
    remove_stylesheet(e, first)
    update(e); expect_color(t, e, 1, BLACK); expect_color(t, e, 2, BLACK)
}

@(test)
specificity_source_order_defaults_and_keywords :: proc(t: ^testing.T) {
    scene: Scene
    scene[1] = {tag = "box", id = "root", classes = []string{"a"}}
    scene[2].parent = 1
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1); attach_node(e, 2)
    add_rule(e, []Selector_Test{{kind = .Id, name = "root"}}, []Declaration{{property = .Color, value = BLUE}}, {origin = .Defaults, order = 100})
    author, _ := add_rule(e, []Selector_Test{{kind = .Tag, name = "box"}}, []Declaration{{property = .Color, value = RED}})
    update(e); expect_color(t, e, 1, RED)
    high, _ := add_rule(e, []Selector_Test{{kind = .Id, name = "root"}}, []Declaration{{property = .Color, value = BLUE}}, {origin = .Author, order = -10})
    update(e); expect_color(t, e, 1, BLUE)
    remove_stylesheet(e, high)
    add_rule(e, []Selector_Test{{kind = .Tag, name = "box"}}, []Declaration{{property = .Color, value = BLUE}}, {origin = .Author, order = -1})
    update(e); expect_color(t, e, 1, RED) // explicit order beats registration order
    set_inline(e, 2, []Declaration{
        {property = .Color, value = keyword(.Initial)},
        {property = .Width, value = length(50, .Percent)},
        {property = .Opacity, value = number(2)},
    })
    update(e); expect_color(t, e, 2, BLACK)
    computed, _ := computed_style(e, 2)
    testing.expect_value(t, computed[.Width], length(50, .Percent))
    testing.expect_value(t, computed[.Opacity], number(1))
    set_inline(e, 2, []Declaration{{property = .Color, value = keyword(.Inherit)}})
    update(e); expect_color(t, e, 2, RED)
    remove_stylesheet(e, author); update(e); expect_color(t, e, 2, BLUE)
}

@(test)
selectors_follow_sibling_changes_and_reparenting :: proc(t: ^testing.T) {
    scene: Scene
    scene[1].classes = []string{"panel"}
    scene[2] = {parent = 1, classes = []string{"lead"}}
    scene[3] = {parent = 1, previous = 2, tag = "button", role = "action"}
    scene[4] = {parent = 3}
    e := make_engine(&scene); defer destroy(e)
    for id in 1..<5 { attach_node(e, Node_Id(id)) }
    combinators := []Combinator{.Adjacent_Sibling, .General_Sibling}
    for combinator in combinators {
        sheet, err := add_stylesheet(e, {version = IR_VERSION, rules = []Rule{{
            selectors = []Selector{{steps = []Selector_Step{
                {tests = []Selector_Test{{kind = .Tag, name = "button"}, {kind = .Attribute_Equals, name = "role", value = "action"}}, next = combinator},
                {tests = []Selector_Test{{kind = .Class, name = "lead"}}},
            }}}, declarations = []Declaration{{property = .Background_Color, value = RED}},
        }}})
        testing.expect_value(t, err, Error.None)
        update(e)
        computed, _ := computed_style(e, 3); testing.expect_value(t, computed[.Background_Color], RED)
        scene[3].previous = 0; scene[2].previous = 3
        children_changed(e, 1); update(e)
        computed, _ = computed_style(e, 3); testing.expect_value(t, computed[.Background_Color], rgba(0, 0, 0, 0))
        remove_stylesheet(e, sheet); scene[3].previous = 2; scene[2].previous = 0
    }
    add_stylesheet(e, {version = IR_VERSION, rules = []Rule{{
        selectors = []Selector{{steps = []Selector_Step{
            {tests = []Selector_Test{{kind = .Universal}}, next = .Descendant},
            {tests = []Selector_Test{{kind = .Class, name = "panel"}}},
        }}}, declarations = []Declaration{{property = .Color, value = RED}},
    }}})
    update(e); expect_color(t, e, 4, RED)
    scene[4].parent = 0; children_changed(e, 3); update(e)
    expect_color(t, e, 4, BLACK)
}

@(test)
stylesheet_ownership_atomic_replacement_and_invalid_tree :: proc(t: ^testing.T) {
    scene: Scene
    scene[1].classes = []string{"a"}
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    declarations := []Declaration{{property = .Color, value = RED, source = {file = "panel.css", line = 2}}}
    tests := []Selector_Test{{kind = .Class, name = "a"}}
    sheet, _ := add_rule(e, tests, declarations)
    tests[0].name = "other"; declarations[0].value = BLUE
    update(e); expect_color(t, e, 1, RED)
    testing.expect_value(t, replace_stylesheet(e, sheet, {version = 999}), Error.Invalid_Version)
    update(e); expect_color(t, e, 1, RED)
    scene[1].parent = 1; children_changed(e, 1)
    _, err := update(e); testing.expect_value(t, err, Error.Invalid_Tree)
    expect_color(t, e, 1, RED) // last committed result survives a bad update
    scene[1].parent = 0
    testing.expect_value(t, replace_stylesheet(e, sheet, {version = IR_VERSION}), Error.None)
    update(e); expect_color(t, e, 1, BLACK)
    detach_node(e, 1)
    _, ok := computed_style(e, 1); testing.expect(t, !ok)
    testing.expect_value(t, set_inline(e, 1, nil), Error.Unknown_Node)
    _, err = add_rule(e, []Selector_Test{{kind = .Universal}}, []Declaration{{property = .Width, value = RED}})
    testing.expect_value(t, err, Error.Invalid_Declaration)
}

@(test)
selector_lists_use_only_matching_specificity :: proc(t: ^testing.T) {
    scene: Scene
    scene[1] = {tag = "button", classes = []string{"a", "b"}}
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    add_stylesheet(e, {version = IR_VERSION, rules = []Rule{{
        selectors = []Selector{
            {steps = []Selector_Step{{tests = []Selector_Test{{kind = .Id, name = "absent"}}}}},
            {steps = []Selector_Step{{tests = []Selector_Test{{kind = .Class, name = "a"}}}}},
        }, declarations = []Declaration{{property = .Color, value = RED}},
    }}})
    add_rule(e, []Selector_Test{{kind = .Class, name = "b"}, {kind = .Tag, name = "button"}}, []Declaration{{property = .Color, value = BLUE}})
    update(e); expect_color(t, e, 1, BLUE)
    scene[1].id = "absent"; attribute_changed(e, 1)
    update(e); expect_color(t, e, 1, RED)
    winner, _ := explain(e, 1, .Color)
    testing.expect_value(t, winner.specificity, Specificity{1, 0, 0})
    scene[1].previous = 1; children_changed(e, 1)
    _, err := update(e); testing.expect_value(t, err, Error.Invalid_Tree)
}
