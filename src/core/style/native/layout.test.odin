#+build !wasm32
package style_native

import "core:testing"
import "core:math"
import style ".."
import "src:core/node"
import "src:core/input"
import YG "src:yoga"

@(test)
cascade_changes_actual_layout_and_removal_resets_constraints :: proc(t: ^testing.T) {
    e := style.create({parent = proc(_: rawptr, n: style.Node_Id) -> style.Node_Id { return 1 if n == 2 else 0 }})
    defer style.destroy(e)
    style.attach_node(e, 1); style.attach_node(e, 2)
    root, child := YG.NodeNew(), YG.NodeNew()
    defer YG.NodeFreeRecursive(root)
    YG.NodeInsertChild(root, child, 0)
    style.set_inline(e, 1, []style.Declaration{
        {property = .Width, value = style.length(200)},
        {property = .Height, value = style.length(100)},
        {property = .Padding_Left, value = style.length(10)},
        {property = .Box_Sizing, value = style.keyword(.Border_Box)},
    })
    style.set_inline(e, 2, []style.Declaration{
        {property = .Width, value = style.length(50, .Percent)},
        {property = .Max_Width, value = style.length(60)},
        {property = .Height, value = style.length(20)},
    })
    // legacy values must not override the new computed physical edges
    YG.NodeStyleSetMargin(child, .Start, 30)
    YG.NodeStyleSetPadding(child, .All, 20)
    changes, err := style.update(e)
    testing.expect_value(t, err, style.Error.None)
    for change in changes { apply_layout(root if change.node == 1 else child, change.style) }
    YG.NodeCalculateLayout(root, 200, 100, .LTR)
    testing.expect_value(t, YG.NodeLayoutGetLeft(child), f32(10))
    testing.expect_value(t, YG.NodeLayoutGetWidth(child), f32(60))
    testing.expect_value(t, YG.NodeLayoutGetHeight(child), f32(20))
    style.set_inline(e, 2, []style.Declaration{{property = .Width, value = style.length(50, .Percent)}})
    changes, err = style.update(e)
    for change in changes { apply_layout(child, change.style) }
    YG.NodeCalculateLayout(root, 200, 100, .LTR)
    testing.expect_value(t, YG.NodeLayoutGetWidth(child), f32(95))
    testing.expect_value(t, YG.NodeLayoutGetHeight(child), f32(100))
    testing.expect(t, math.is_nan(YG.NodeStyleGetMaxWidth(child).value))
    style.set_inline(e, 2, []style.Declaration{{property = .Display, value = style.keyword(.None)}})
    changes, err = style.update(e)
    for change in changes { apply_layout(child, change.style) }
    YG.NodeCalculateLayout(root, 200, 100, .LTR)
    testing.expect_value(t, YG.NodeLayoutGetWidth(child), f32(0))
}

@(test)
min_settles_and_transform_lists_compose :: proc(t: ^testing.T) {
    root, child := node.New(), node.New()
    root->add(child)
    im: input.Input_State
    h := create_host(&im); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    child_id, _ := bind(h, child, "box")
    style.set_inline(h.engine, root_id, []style.Declaration{
        {property = .Width, value = style.length(300)},
        {property = .Height, value = style.length(100)},
    })
    testing.expect_value(t, style.set_inline(h.engine, child_id, []style.Declaration{
        {property = .Width, value = style.MATH, math = []style.Math_Op{
            {kind = .Term, calc = #partial {.Percent = 100}}, {kind = .Term, calc = #partial {.Px = 200}}, {kind = .Min, count = 2},
        }},
        {property = .Height, value = style.length(40)},
        {property = .Transform, value = style.TRANSFORM, transform = []style.Transform_Op{
            {kind = .Translate, x = style.length(10), y = style.length(50, .Percent)},
            {kind = .Rotate, numbers = {0 = 90}},
        }},
    }), style.Error.None)
    flush(h)
    YG.NodeCalculateLayout(root.raw, 500, 500, .LTR)
    testing.expect(t, settle(h))
    YG.NodeCalculateLayout(root.raw, 500, 500, .LTR)
    testing.expect_value(t, YG.NodeLayoutGetWidth(child.raw), f32(200))
    child.rect = {0, 0, 200, 40}
    settle(h)
    transform := node.Resolve_Transform(child)
    testing.expect(t, transform.has_linear)
    testing.expect_value(t, transform.translate, [2]f32{10, 20})
    testing.expect_value(t, transform.origin, [2]f32{100, 20})
    testing.expect(t, abs(transform.linear[0]) < 0.0001 && abs(transform.linear[1]-1) < 0.0001 && abs(transform.linear[2]+1) < 0.0001)
    im.focused = child
    style.add_stylesheet(h.engine, {version = style.IR_VERSION, rules = []style.Rule{{
        selectors = []style.Selector{{steps = []style.Selector_Step{{tests = []style.Selector_Test{{kind = .State, state = .Focus_Within}}}}}},
        declarations = []style.Declaration{{property = .Padding_Left, value = style.length(7)}},
    }}})
    flush(h)
    testing.expect_value(t, YG.NodeStyleGetPadding(root.raw, .Left).value, f32(7))
    root->free()
}

@(test)
calc_settles_against_the_laid_out_parent :: proc(t: ^testing.T) {
    root, child := node.New(), node.New()
    root->add(child)
    h := create_host(); defer destroy_host(h)
    root_id, _ := bind(h, root, "div")
    child_id, _ := bind(h, child, "div")
    style.set_inline(h.engine, root_id, []style.Declaration{
        {property = .Width, value = style.length(300)},
        {property = .Height, value = style.length(100)},
        {property = .Padding_Left, value = style.length(50)},
    })
    style.set_inline(h.engine, child_id, []style.Declaration{
        style.calc(.Width, #partial [style.Unit]f32{.Percent = 100, .Px = -20}),
        {property = .Height, value = style.length(40)},
        {property = .Translate_X, value = style.length(50, .Percent)},
        {property = .Scale_X, value = style.number(2)},
    })
    flush(h)
    YG.NodeCalculateLayout(root.raw, 500, 500, .LTR)
    testing.expect(t, settle(h))
    YG.NodeCalculateLayout(root.raw, 500, 500, .LTR)
    testing.expect_value(t, YG.NodeLayoutGetWidth(child.raw), f32(280))
    testing.expect(t, !settle(h))
    style.set_inline(h.engine, root_id, []style.Declaration{
        {property = .Width, value = style.length(120)},
        {property = .Height, value = style.length(100)},
    })
    flush(h)
    YG.NodeCalculateLayout(root.raw, 500, 500, .LTR)
    testing.expect(t, settle(h))
    YG.NodeCalculateLayout(root.raw, 500, 500, .LTR)
    testing.expect_value(t, YG.NodeLayoutGetWidth(child.raw), f32(100))
    child.rect = {0, 0, 100, 40}
    settle(h)
    testing.expect_value(t, node.Resolve_Transform(child).translate, [2]f32{50, 0})
    testing.expect_value(t, node.Resolve_Transform(child).scale, [2]f32{2, 1})
    testing.expect_value(t, node.Resolve_Transform(child).origin, [2]f32{50, 20})
    root->free()
}
