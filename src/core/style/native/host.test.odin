#+build !wasm32
package style_native

import "core:testing"
import style ".."
import "src:core/common"
import "src:core/node"
import "src:core/input"
import YG "src:yoga"

@(test)
live_host_hover_class_composition_and_destruction :: proc(t: ^testing.T) {
    root, child := node.New(), node.New()
    root->add(child)
    im: input.Input_State
    h := create_host(&im); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    child_id, _ := bind(h, child, "button")
    set_classes(h, root_id, "scoped_panel flex")
    set_classes(h, child_id, "scoped_action\tprimary")
    _, err := style.add_stylesheet(h.engine, {version = style.IR_VERSION, rules = []style.Rule{{
        selectors = []style.Selector{{steps = []style.Selector_Step{
            {tests = []style.Selector_Test{{kind = .Class, name = "scoped_action"}}, next = .Child},
            {tests = []style.Selector_Test{{kind = .Class, name = "scoped_panel"}, {kind = .State, state = .Hover}}},
        }}}, declarations = []style.Declaration{{property = .Width, value = style.length(120)}},
    }}})
    testing.expect_value(t, err, style.Error.None)
    flush(h)
    testing.expect_value(t, YG.NodeStyleGetWidth(child.raw).unit, YG.Unit.Auto)
    im.hovered = child // ancestor hover must come from the actual native target
    _, err = flush(h); testing.expect_value(t, err, style.Error.None)
    testing.expect_value(t, YG.NodeStyleGetWidth(child.raw).value, f32(120))
    set_classes(h, root_id, "flex scoped_panel")
    changes, _ := flush(h); testing.expect_value(t, len(changes), 0)
    im.hovered = nil
    flush(h)
    testing.expect_value(t, YG.NodeStyleGetWidth(child.raw).unit, YG.Unit.Auto)
    set_attribute(h, child_id, "role", "action")
    set_attribute(h, child_id, "role", "primary")
    set_attribute(h, child_id, "role", "", false)
    set_attribute(h, child_id, "class", "")
    _, present := h.engine.tree.attribute(h, child_id, "class")
    testing.expect(t, present)
    set_attribute(h, child_id, "class", "", false)
    _, present = h.engine.tree.attribute(h, child_id, "class")
    testing.expect(t, !present)
    im.hovered = child; im.focused = child
    root->free() // callbacks detach both nodes without dangling hooks or tracks
    testing.expect_value(t, len(h.bindings), 0)
    testing.expect(t, im.hovered == nil && im.focused == nil)
    _, err = flush(h); testing.expect_value(t, err, style.Error.None)
}

@(test)
opacity_flattens_through_ancestors :: proc(t: ^testing.T) {
    filter_of :: proc(n: ^node.Node) -> Maybe(common.EffectFilter) {
        return (cast(^node.Style)n._internal_style).filter
    }
    root, child := node.New(), node.New()
    root->add(child)
    h := create_host(); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    child_id, _ := bind(h, child, "box")
    style.set_inline(h.engine, root_id, []style.Declaration{{property = .Opacity, value = style.number(0.5)}})
    style.set_inline(h.engine, child_id, []style.Declaration{{property = .Opacity, value = style.number(0.5)}, {property = .Color, value = style.rgba(1, 1, 1, 1)}})
    flush(h)
    // translucent box with a child box draw as one image and fade there, not per child
    testing.expect_value(t, h.bindings[child_id].alpha, f32(0.5))
    testing.expect_value(t, node.Resolve_Text_Style(child).color, [4]u8{255, 255, 255, 128})
    testing.expect(t, filter_of(root) != nil && filter_of(root).?.color[3][3] == 0.5 && filter_of(child) == nil)
    // only the ancestor change, child must still get repainted
    style.set_inline(h.engine, root_id, []style.Declaration{{property = .Opacity, value = style.number(1)}})
    flush(h)
    testing.expect_value(t, h.bindings[child_id].alpha, f32(0.5))
    testing.expect(t, filter_of(root) == nil)
    shadows := []style.Shadow{{x = 2, y = 3, blur = 4, color = {0, 0, 0, 1}}}
    blur := style.FILTER_IDENTITY
    blur.blur, blur.shadows = 6, shadows
    style.set_inline(h.engine, child_id, []style.Declaration{
        {property = .Opacity, value = style.number(0.5)}, {property = .Color, value = style.rgba(1, 1, 1, 1)},
        {property = .Filter, value = style.FILTER, filter = blur},
    })
    flush(h)
    testing.expect_value(t, h.bindings[child_id].alpha, f32(1))
    testing.expect(t, filter_of(child) != nil && filter_of(child).?.blur == 6 && filter_of(child).?.color[3][3] == 0.5 && len(filter_of(child).?.shadows) == 1)
    style.set_inline(h.engine, child_id, []style.Declaration{{property = .Opacity, value = style.number(0.5)}, {property = .Color, value = style.rgba(1, 1, 1, 1)}})
    flush(h)
    testing.expect(t, filter_of(child) == nil)
    style.set_inline(h.engine, child_id, []style.Declaration{{property = .Visibility, value = style.keyword(.Hidden)}})
    flush(h)
    testing.expect_value(t, h.bindings[child_id].alpha, f32(0))
    testing.expect_value(t, node.Resolve_Pointer_Events(child), node.Pointer_Events.None)
    root->free()
}

@(test)
unbound_wrappers_are_transparent :: proc(t: ^testing.T) {
    root, first, wrapper, inner, last := node.New(), node.New(), node.New(), node.New(), node.New()
    root->add(first); root->add(wrapper); wrapper->add(inner); root->add(last)
    h := create_host(); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    first_id, _ := bind(h, first, "item")
    inner_id, _ := bind(h, inner, "item")
    last_id, _ := bind(h, last, "item")
    _, err := style.add_stylesheet(h.engine, {version = style.IR_VERSION, rules = []style.Rule{{
        selectors = []style.Selector{{steps = []style.Selector_Step{
            {tests = []style.Selector_Test{{kind = .Tag, name = "item"}, {kind = .Nth_Child, b = 2}}, next = .Child},
            {tests = []style.Selector_Test{{kind = .Tag, name = "box"}}},
        }}}, declarations = []style.Declaration{{property = .Width, value = style.length(50)}},
    }}})
    testing.expect_value(t, err, style.Error.None)
    _, err = flush(h); testing.expect_value(t, err, style.Error.None)
    testing.expect_value(t, h.bindings[inner_id].parent, root_id)
    testing.expect_value(t, h.bindings[inner_id].previous, first_id)
    testing.expect_value(t, h.bindings[last_id].previous, inner_id)
    testing.expect_value(t, YG.NodeStyleGetWidth(inner.raw).value, f32(50))
    testing.expect_value(t, YG.NodeStyleGetWidth(last.raw).unit, YG.Unit.Auto)
    root->free()
}
