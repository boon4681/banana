#+build !wasm32
package hit_test

import "core:testing"
import "src:core/common"
import "src:core/node"

// Rects are assigned directly rather than run through layout: the layout
// package imports platform, which imports back into hit_test, so a test here
// cannot pull layout in. Hit testing only reads the cached rect anyway.
@(private = "file")
build :: proc(x, y, w, h: f32) -> ^node.Node {
    n := node.New()
    n.rect = common.Rect{x = x, y = y, w = w, h = h}
    return n
}

@(test)
pointer_events_none_skips_node_but_keeps_children :: proc(t: ^testing.T) {
    root := build(0, 0, 100, 100)
    defer root->free()
    child := build(0, 0, 50, 50)
    root->add(child)
    root->style()->set_pointer_events(.None)

    // pointer-events inherits; descendants must explicitly opt back in.
    child->style()->set_pointer_events(.Auto)

    invalidate()
    testing.expect_value(t, hit_test(root, 10, 10), cast(^node.BaseNode)child)

    // Outside the child, the None root must claim nothing.
    invalidate()
    testing.expect_value(t, hit_test(root, 80, 80), nil)
}

@(test)
rounded_corners_are_not_part_of_the_node :: proc(t: ^testing.T) {
    root := build(0, 0, 200, 200)
    defer root->free()
    card := build(50, 50, 100, 100)
    inner := build(50, 50, 100, 100)
    root->add(card)
    card->add(inner)
    card->style()->set_border_width(2)->set_corner_radius({40, 0, 40, 0})

    invalidate()
    testing.expect_value(t, hit_test(root, 100, 100), cast(^node.BaseNode)inner)
    testing.expect_value(t, hit_test(root, 148, 52), cast(^node.BaseNode)inner)
    testing.expect_value(t, hit_test(root, 80, 52), cast(^node.BaseNode)inner)

    card.clip_x, card.clip_y, card.clip_mode = true, true, .Scissor
    card.clip_rect = common.Rect{2, 2, 96, 96}
    invalidate()
    testing.expect_value(t, hit_test(root, 100, 100), cast(^node.BaseNode)inner)
    testing.expect_value(t, hit_test(root, 146, 54), cast(^node.BaseNode)inner)
    testing.expect_value(t, hit_test(root, 53, 53), cast(^node.BaseNode)root)
    testing.expect_value(t, hit_test(root, 147, 147), cast(^node.BaseNode)root)
    testing.expect_value(t, hit_test(root, 62.5, 62.5), cast(^node.BaseNode)card)
}

@(test)
elliptical_corners_follow_the_ellipse :: proc(t: ^testing.T) {
    root := build(0, 0, 300, 200)
    defer root->free()
    oval := build(50, 50, 200, 100)
    root->add(oval)
    oval->style()->set_corner_radius(common.Radii{{100, 50}, {100, 50}, {100, 50}, {100, 50}})

    invalidate()
    testing.expect_value(t, hit_test(root, 150, 100), cast(^node.BaseNode)oval)
    testing.expect_value(t, hit_test(root, 150, 52), cast(^node.BaseNode)oval)
    testing.expect_value(t, hit_test(root, 52, 100), cast(^node.BaseNode)oval)
    testing.expect_value(t, hit_test(root, 85, 68), cast(^node.BaseNode)oval)
    testing.expect_value(t, hit_test(root, 70, 60), cast(^node.BaseNode)root)
    testing.expect_value(t, hit_test(root, 240, 142), cast(^node.BaseNode)root)
}

@(test)
pointer_events_none_on_child_falls_through_to_parent:: proc(t: ^testing.T) {
    root := build(0, 0, 100, 100)
    defer root->free()
    child := build(0, 0, 50, 50)
    root->add(child)
    child->style()->set_pointer_events(.None)

    invalidate()
    testing.expect_value(t, hit_test(root, 10, 10), cast(^node.BaseNode)root)
}

@(test)
pointer_events_inherit_walks_to_parent :: proc(t: ^testing.T) {
    root := build(0, 0, 100, 100)
    defer root->free()
    child := build(0, 0, 50, 50)
    root->add(child)
    root->style()->set_pointer_events(.None)
    child->style()->set_pointer_events(.Inherit)

    invalidate()
    testing.expect_value(t, hit_test(root, 10, 10), nil)
}

@(test)
pointer_events_auto_descendant_under_none_stays_hittable :: proc(t: ^testing.T) {
    root := build(0, 0, 100, 100)
    defer root->free()
    wrapper := build(0, 0, 100, 100)
    root->add(wrapper)
    leaf := build(0, 0, 20, 20)
    wrapper->add(leaf)
    // Only the wrapper opts out; the leaf inside it must still be reachable.
    wrapper->style()->set_pointer_events(.None)
    leaf->style()->set_pointer_events(.Auto)

    invalidate()
    testing.expect_value(t, hit_test(root, 5, 5), cast(^node.BaseNode)leaf)

    // Over the wrapper but outside the leaf, the wrapper declines and the
    // root behind it takes the hit.
    invalidate()
    testing.expect_value(t, hit_test(root, 60, 60), cast(^node.BaseNode)root)
}

@(test)
pointer_events_auto_descendant_under_clipping_none_stays_hittable :: proc(t: ^testing.T) {
    root := build(0, 0, 100, 100)
    defer root->free()
    wrapper := build(0, 0, 50, 50)
    wrapper.clip_mode = .Scissor
    wrapper.clip_x = true
    wrapper.clip_y = true
    // Explicit, because the derived fallback reads Yoga layout and these tests
    // assign rects directly.
    wrapper.clip_rect = common.Rect{0, 0, 50, 50}
    root->add(wrapper)
    leaf := build(0, 0, 20, 20)
    wrapper->add(leaf)
    wrapper->style()->set_pointer_events(.None)

    leaf->style()->set_pointer_events(.Auto)

    invalidate()
    testing.expect_value(t, hit_test(root, 5, 5), cast(^node.BaseNode)leaf)
}

// A non-clipping root does not bound its children: an overlay root sized to the
// window still has to route clicks to content laid out past its own rect.
@(test)
leaf_outside_a_non_clipping_root_is_hittable :: proc(t: ^testing.T) {
    root := build(0, 0, 100, 100)
    defer root->free()
    leaf := build(150, 150, 20, 20)
    root->add(leaf)

    invalidate()
    testing.expect_value(t, hit_test(root, 155, 155), cast(^node.BaseNode)leaf)
}

@(test)
leaf_outside_a_none_root_is_hittable :: proc(t: ^testing.T) {
    root := build(0, 0, 100, 100)
    defer root->free()
    leaf := build(150, 150, 20, 20)
    root->add(leaf)
    root->style()->set_pointer_events(.None)
    leaf->style()->set_pointer_events(.Auto)

    invalidate()
    testing.expect_value(t, hit_test(root, 155, 155), cast(^node.BaseNode)leaf)

    // Empty overlay space claims nothing, so the click can pass through.
    invalidate()
    testing.expect_value(t, hit_test(root, 300, 300), nil)
}

@(test)
pointer_events_auto_is_the_default :: proc(t: ^testing.T) {
    root := build(0, 0, 100, 100)
    defer root->free()

    invalidate()
    testing.expect_value(t, hit_test(root, 10, 10), cast(^node.BaseNode)root)
}
