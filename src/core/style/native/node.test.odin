#+build !wasm32
package style_native

import "core:testing"
import style ".."
import "src:core/node"
import "src:core/common"
import YG "src:yoga"

@(test)
computed_zero_text_overrides_legacy_inheritance :: proc(t: ^testing.T) {
    parent, child := node.New(), node.New()
    defer parent->free()
    parent->add(child)
    parent->style()->set_color({255, 0, 0, 255})
    parent->style()->set_font_size(30)
    parent->style()->set_line_height(45)
    e := style.create({parent = proc(_: rawptr, _: style.Node_Id) -> style.Node_Id { return 0 }})
    defer style.destroy(e)
    style.attach_node(e, 1)
    style.set_inline(e, 1, []style.Declaration{
        {property = .Color, value = style.rgba(0, 0, 0, 0)},
        {property = .Font_Size, value = style.length(0)},
        {property = .Line_Height, value = style.length(0)},
        {property = .Pointer_Events, value = style.keyword(.None)},
        {property = .Overflow_X, value = style.keyword(.Hidden)},
    })
    style.update(e)
    c, _ := style.computed_style(e, 1)
    remaining := apply_node(child, c)
    testing.expect(t, .Cursor in remaining && .Translate_X in remaining && .Background_Color not_in remaining && .Text_Align not_in remaining)
    text := node.Resolve_Text_Style(child)
    testing.expect_value(t, text.color, common.Color{})
    testing.expect_value(t, text.font_size, f32(0))
    testing.expect_value(t, text.line_height, f32(0))
    testing.expect_value(t, node.Resolve_Pointer_Events(child), node.Pointer_Events.None)
    testing.expect(t, child.clip_x && child.clip_y)
}

@(test)
setters_author_inline_style_on_a_bound_node :: proc(t: ^testing.T) {
    n := node.New()
    defer n->free()
    h := create_host(); defer destroy_host(h)
    id, _ := bind(h, n, "box")
    style.add_stylesheet(h.engine, {version = style.IR_VERSION, rules = []style.Rule{{
        selectors = []style.Selector{{steps = []style.Selector_Step{{tests = []style.Selector_Test{{kind = .Tag, name = "box"}}}}}},
        declarations = []style.Declaration{
            {property = .Width, value = style.length(40)},
            {property = .Border_Top_Left_Radius, value = style.length(8)},
        },
    }}})
    flush(h)
    s := n->style()
    testing.expect_value(t, YG.NodeStyleGetWidth(n.raw).value, f32(40))
    testing.expect_value(t, s.radius[0], [2]f32{8, 8})

    s->set_width(120)->set_border_radius(0)->set_background_color({255, 0, 0, 255})->set_border_bottom_width(2)
    testing.expect_value(t, YG.NodeStyleGetWidth(n.raw).value, f32(40))
    flush(h)
    testing.expect_value(t, YG.NodeStyleGetWidth(n.raw).value, f32(120))
    testing.expect_value(t, s.radius[0], [2]f32{0, 0})
    testing.expect_value(t, s.background, common.Color{255, 0, 0, 255})
    // same as browser, border width draw nothing while style is none
    testing.expect_value(t, s.border_width, [4]f32{0, 0, 0, 0})
    s->set_border_bottom_style(.Solid)
    flush(h)
    testing.expect_value(t, s.border_width, [4]f32{0, 0, 2, 0})

    s->clear_inline(.Width)
    flush(h)
    testing.expect_value(t, YG.NodeStyleGetWidth(n.raw).value, f32(40))
    testing.expect_value(t, s.radius[0], [2]f32{0, 0})

    s->clear_inline()
    flush(h)
    testing.expect_value(t, s.radius[0], [2]f32{8, 8})
    _ = id
}

@(test)
the_engine_accepts_what_every_setter_authors :: proc(t: ^testing.T) {
    n := node.New()
    defer n->free()
    h := create_host(); defer destroy_host(h)
    bind(h, n, "box")
    s := n->style()
    s->set_z_index(2)->set_direction(.RTL)->set_flex_direction(.RowReverse)->set_justify_content(.SpaceEvenly)
    s->set_align_content(.Stretch)->set_align_items(.Baseline)->set_align_self(.Auto)->set_position(.Absolute)
    s->set_justify_items(.Center)->set_justify_self(.Stretch)
    s->set_flex_wrap(.WrapReverse)->set_display(.Flex)->set_user_select(.All)->set_pointer_events(.None)
    s->set_visibility(.Visible)->set_cursor(.Pointer)->set_opacity(0.5)
    s->set_overflow(.Hidden)->set_overflow_x(.Scroll)->set_overflow_y(.Auto)->set_box_sizing(.ContentBox)
    s->set_flex(1)->set_flex_grow(2)->set_flex_shrink(0)->set_aspect_ratio(1.5)
    s->set_width(10)->set_height(50, node.percent)->set_min_width(0, node.auto)->set_min_height(1)
    s->set_max_width(node.UNDEFINED)->set_max_height(9)->set_flex_basis(0, node.auto)
    s->set_margin(1)->set_margin_inline(0, node.auto)->set_margin_block(2)->set_margin_inline_start(3)->set_margin_inline_end(4)
    s->set_margin_left(1)->set_margin_top(1)->set_margin_right(1)->set_margin_bottom(1)
    s->set_padding(1)->set_padding_inline(2)->set_padding_block(2)->set_padding_inline_start(3)->set_padding_inline_end(4)
    s->set_padding_left(1)->set_padding_top(1)->set_padding_right(1)->set_padding_bottom(1)
    s->set_inset(0)->set_inset_inline(1)->set_inset_block(1)->set_inset_inline_start(2)->set_inset_inline_end(2)
    s->set_left(1)->set_top(1)->set_right(1)->set_bottom(0, node.auto)
    s->set_border_inline_width(2)->set_border_block_width(0)->set_border_inline_start_width(1)->set_border_inline_end_width(1)
    s->set_border_left_width(1)->set_border_top_width(1)->set_border_right_width(1)->set_border_bottom_width(1)->set_border_width(3)
    s->set_border_top_style(.None)->set_border_right_style(.Solid)->set_border_bottom_style(.Solid)->set_border_left_style(.Solid)->set_border_style(.Solid)
    s->set_border_top_color({1, 1, 1, 255})->set_border_right_color({2, 2, 2, 255})->set_border_bottom_color({3, 3, 3, 255})->set_border_left_color({4, 4, 4, 255})
    s->set_border_top_left_radius(1)->set_border_top_right_radius({2, 3})->set_border_bottom_right_radius(0)->set_border_bottom_left_radius(4)
    s->set_gap(4)->set_row_gap(5)->set_column_gap(6)
    s->set_color({1, 2, 3, 255})->set_font_size(14)->set_font_weight(700)
    s->set_line_height(20)->set_line_height(1.5, node.percent)->set_line_height(0)
    s->set_text_align(.Center)->set_text_transform(.Uppercase)->set_white_space(.No_Wrap)->set_text_decoration_line(.Underline)->set_text_overflow(.Ellipsis)->set_letter_spacing(1)
    s->set_translate_x(4)->set_translate_y(50, node.percent)->set_rotate(45)->set_scale_x(2)->set_scale_y(0.5)->set_transform_origin_x(0)->set_transform_origin_y(100, node.percent)
    s->set_outline_width(2)->set_outline_style(.Solid)->set_outline_color({5, 5, 5, 255})->set_outline_offset(1)
    s->set_scrollbar_width(.Thin)->set_scrollbar_thumb_color({6, 6, 6, 255})->set_scrollbar_track_color({7, 7, 7, 255})
    s->set_grid_column_start(1)->set_grid_column_end(3)->set_grid_row_start(1)->set_grid_row_end(2)
    s->set_background_color({9, 9, 9, 255})->set_border_color({1, 1, 1, 255})->set_border_radius({{4, 8}, {4, 4}, {0, 0}, {2, 2}})
    _, err := flush(h)
    testing.expect_value(t, err, style.Error.None)
    testing.expect_value(t, s.border_width, [4]f32{3, 3, 3, 3})
    testing.expect_value(t, s.radius[0], [2]f32{4, 8})
    testing.expect_value(t, s.text.align, node.Text_Align.Center)
    testing.expect_value(t, s.decoration.outline_width, f32(2))
    testing.expect_value(t, YG.NodeStyleGetFlexGrow(n.raw), f32(2))
}

@(test)
setters_apply_at_once_without_an_engine :: proc(t: ^testing.T) {
    n := node.New()
    defer n->free()
    n->style()->set_width(120)->set_border_radius(6)->set_border_bottom_width(2)->set_text_align(.Right)->set_rotate(90)
    testing.expect_value(t, YG.NodeStyleGetWidth(n.raw).value, f32(120))
    testing.expect_value(t, n->style().radius[0], [2]f32{6, 6})
    testing.expect_value(t, n->style().border_width, [4]f32{0, 0, 2, 0})
    testing.expect_value(t, YG.NodeStyleGetBorder(n.raw, .Bottom), f32(2))
    testing.expect_value(t, n->style().text.align, node.Text_Align.Right)
    testing.expect(t, abs(n->style().transform.rotate - 1.5707964) < 0.0001)
    testing.expect_value(t, len(n->style().inline), 0)
}

@(test)
each_border_side_reaches_the_node_style :: proc(t: ^testing.T) {
    n := node.New()
    defer n->free()
    e := style.create({parent = proc(_: rawptr, _: style.Node_Id) -> style.Node_Id { return 0 }})
    defer style.destroy(e)
    style.attach_node(e, 1)
    style.set_inline(e, 1, []style.Declaration{
        {property = .Border_Bottom_Style, value = style.keyword(.Solid)},
        {property = .Border_Bottom_Width, value = style.length(2)},
        {property = .Border_Bottom_Color, value = style.rgba(1, 0, 0, 1)},
        {property = .Border_Left_Width, value = style.length(5)},
        {property = .Border_Top_Left_Radius, value = style.length(8)},
        {property = .Border_Bottom_Left_Radius, value = style.length(8)},
    })
    style.update(e)
    c, _ := style.computed_style(e, 1)
    apply_node(n, c)
    s := n->style()
    testing.expect_value(t, s.border_width, [4]f32{0, 0, 2, 0})
    testing.expect_value(t, s.border_color[2], common.Color{255, 0, 0, 255})

    n.rect = {0, 0, 100, 40}
    node.Resolve_Corner_Radius(n)
    testing.expect_value(t, n.clip_radius, common.Radii{{8, 8}, {0, 0}, {0, 0}, {8, 6}})
}

@(test)
vertical_radius_follows_the_horizontal_one_unless_set :: proc(t: ^testing.T) {
    e := style.create({parent = proc(_: rawptr, _: style.Node_Id) -> style.Node_Id { return 0 }})
    defer style.destroy(e)
    style.attach_node(e, 1)
    style.set_inline(e, 1, []style.Declaration{
        {property = .Border_Top_Left_Radius, value = style.length(8)},
        {property = .Border_Top_Right_Radius, value = style.length(50, .Percent)},
        {property = .Border_Bottom_Right_Radius, value = style.length(20)},
        {property = .Border_Bottom_Right_Radius_Y, value = style.length(25, .Percent)},
    })
    style.update(e)
    c, _ := style.computed_style(e, 1)
    b := border(c)
    testing.expect_value(t, b.radius, common.Radii{{8, 8}, {0, 0}, {20, 0}, {0, 0}})
    testing.expect_value(t, b.radius_percent, common.Radii{{0, 0}, {50, 50}, {0, 25}, {0, 0}})
    testing.expect_value(t, common.radii_resolve(b.radius, b.radius_percent, 200, 100), common.Radii{{8, 8}, {100, 50}, {20, 25}, {0, 0}})
    testing.expect_value(t, common.radii_fit({{100, 50}, {100, 50}, {100, 50}, {100, 50}}, 200, 100), common.Radii{{100, 50}, {100, 50}, {100, 50}, {100, 50}})
    testing.expect_value(t, common.radii_fit(80, 100, 200), common.Radii(50))
}
