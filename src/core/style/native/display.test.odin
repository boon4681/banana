#+build !wasm32
package style_native

import "core:testing"
import style ".."
import "src:core/node"
import YG "src:yoga"

@(private = "file")
run :: proc(h: ^Host, root: ^node.BaseNode, width, height: f32) -> int {
    flush(h)
    YG.NodeCalculateLayout(root.raw, width, height, .LTR)
    passes := 0
    for settle(h) {
        passes += 1
        if passes > 8 { break }
        YG.NodeCalculateLayout(root.raw, width, height, .LTR)
    }
    return passes
}

@(private = "file")
rect :: proc(n: ^node.BaseNode) -> [4]f32 {
    return {YG.NodeLayoutGetLeft(n.raw), YG.NodeLayoutGetTop(n.raw), YG.NodeLayoutGetWidth(n.raw), YG.NodeLayoutGetHeight(n.raw)}
}

@(private = "file")
px :: proc(p: style.Property, v: f32) -> style.Declaration { return {property = p, value = style.length(v)} }

@(private = "file")
display :: proc(k: style.Keyword) -> style.Declaration { return {property = .Display, value = style.keyword(k)} }

@(test)
block_children_stack_and_inline_children_share_a_line :: proc(t: ^testing.T) {
    root, a, b, c, d, e := node.New(), node.New(), node.New(), node.New(), node.New(), node.New()
    defer root->free()
    root->add(a); root->add(b); root->add(c); root->add(d); root->add(e)
    h := create_host(); defer destroy_host(h)
    ids: [6]style.Node_Id
    for n, i in ([]^node.BaseNode{root, a, b, c, d, e}) { ids[i], _ = bind(h, n, "box") }
    style.set_inline(h.engine, ids[0], []style.Declaration{display(.Block), px(.Width, 200)})
    style.set_inline(h.engine, ids[1], []style.Declaration{display(.Block), px(.Height, 10), px(.Margin_Left, 20)})
    style.set_inline(h.engine, ids[2], []style.Declaration{display(.Inline_Block), px(.Width, 30), px(.Height, 10)})
    style.set_inline(h.engine, ids[3], []style.Declaration{display(.Inline_Block), px(.Width, 40), px(.Height, 20)})
    style.set_inline(h.engine, ids[4], []style.Declaration{display(.Block), px(.Width, 50), px(.Height, 10)})
    style.set_inline(h.engine, ids[5], []style.Declaration{display(.Inline_Block), px(.Width, 30), px(.Height, 10)})
    run(h, root, 200, 400)

    testing.expect_value(t, rect(a), [4]f32{20, 0, 180, 10})
    testing.expect_value(t, rect(b), [4]f32{0, 10, 30, 10})
    testing.expect_value(t, rect(c), [4]f32{30, 10, 40, 20})
    testing.expect_value(t, rect(d), [4]f32{0, 30, 50, 10})
    testing.expect_value(t, rect(e), [4]f32{0, 40, 30, 10})

    style.set_inline(h.engine, ids[0], []style.Declaration{display(.Flex), px(.Width, 200)})
    run(h, root, 200, 400)
    testing.expect_value(t, rect(b), [4]f32{20, 0, 30, 10})
    testing.expect_value(t, rect(d)[0], f32(90))
}

@(test)
unbound_text_remeasures_when_inherited_font_size_changes :: proc(t: ^testing.T) {
    root, inner, leaf := node.New(), node.New(), node.New()
    defer root->free()
    root->add(inner); inner->add(leaf)
    leaf.measure = proc(self: ^node.Node, w: f32, w_mode: node.MeasureMode, h: f32, h_mode: node.MeasureMode) -> (f32, f32) {
        size := node.Resolve_Text_Style(self).font_size
        return size / 2, size
    }
    leaf->apply_measure()
    h := create_host(); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    bind(h, inner, "box")
    centered := []style.Declaration{
        px(.Width, 24), px(.Height, 24),
        {property = .Justify_Content, value = style.keyword(.Center)},
        {property = .Align_Items, value = style.keyword(.Center)},
    }
    style.set_inline(h.engine, root_id, centered)
    run(h, root, 100, 100)
    testing.expect_value(t, rect(inner), [4]f32{8, 4, 8, 16})

    style.set_inline(h.engine, root_id, []style.Declaration{centered[0], centered[1], centered[2], centered[3], px(.Font_Size, 12)})
    run(h, root, 100, 100)
    testing.expect_value(t, rect(leaf), [4]f32{0, 0, 6, 12})
    testing.expect_value(t, rect(inner), [4]f32{9, 6, 6, 12})
}

@(test)
fixed_offsets_are_from_the_window :: proc(t: ^testing.T) {
    root, panel, badge := node.New(), node.New(), node.New()
    defer root->free()
    root->add(panel); panel->add(badge)
    h := create_host(); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    panel_id, _ := bind(h, panel, "box")
    badge_id, _ := bind(h, badge, "box")
    style.set_inline(h.engine, root_id, []style.Declaration{px(.Padding_Left, 40), px(.Padding_Top, 30)})
    style.set_inline(h.engine, panel_id, []style.Declaration{px(.Width, 100), px(.Height, 100), px(.Margin_Left, 10)})
    style.set_inline(h.engine, badge_id, []style.Declaration{
        {property = .Position, value = style.keyword(.Fixed)}, px(.Right, 8), px(.Top, 6), px(.Width, 20), px(.Height, 20),
    })
    run(h, root, 300, 200)
    testing.expect_value(t, rect(panel)[0], f32(50))
    testing.expect_value(t, rect(panel)[0] + rect(badge)[0], f32(300 - 8 - 20))
    testing.expect_value(t, rect(panel)[1] + rect(badge)[1], f32(6))
}

@(test)
contents_lifts_children_into_the_parent:: proc(t: ^testing.T) {
    root, wrapper, a, b := node.New(), node.New(), node.New(), node.New()
    defer root->free()
    root->add(wrapper); wrapper->add(a); wrapper->add(b)
    h := create_host(); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    wrapper_id, _ := bind(h, wrapper, "box")
    a_id, _ := bind(h, a, "box")
    b_id, _ := bind(h, b, "box")
    style.set_inline(h.engine, root_id, []style.Declaration{px(.Width, 200), px(.Height, 50)})
    style.set_inline(h.engine, wrapper_id, []style.Declaration{display(.Contents), {property = .Flex_Direction, value = style.keyword(.Column)}})
    style.set_inline(h.engine, a_id, []style.Declaration{px(.Width, 30)})
    style.set_inline(h.engine, b_id, []style.Declaration{px(.Width, 40)})
    run(h, root, 200, 50)
    testing.expect_value(t, rect(a)[0], f32(0))
    testing.expect_value(t, rect(b)[0], f32(30))
}

@(test)
grid_sizes_tracks_and_places_items :: proc(t: ^testing.T) {
    root, grid := node.New(), node.New()
    items: [5]^node.BaseNode
    defer root->free()
    root->add(grid)
    h := create_host(); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    grid_id, _ := bind(h, grid, "box")
    item_ids: [5]style.Node_Id
    for &item, i in items {
        item = node.New()
        grid->add(item)
        item_ids[i], _ = bind(h, item, "box")
    }
    style.set_inline(h.engine, root_id, []style.Declaration{px(.Width, 320), {property = .Flex_Direction, value = style.keyword(.Column)}})
    style.set_inline(h.engine, grid_id, []style.Declaration{
        display(.Grid), px(.Padding_Left, 10), px(.Padding_Top, 10), px(.Padding_Right, 10), px(.Padding_Bottom, 10),
        px(.Row_Gap, 10), px(.Column_Gap, 10),
        style.grid_tracks(.Grid_Template_Columns, []style.Track{{kind = .Px, value = 100}, {kind = .Fr, value = 1}, {kind = .Fr, value = 1}}),
        style.grid_tracks(.Grid_Template_Rows, []style.Track{{kind = .Px, value = 40}}),
        style.grid_tracks(.Grid_Auto_Rows, []style.Track{{kind = .Px, value = 30}}),
    })
    style.set_inline(h.engine, item_ids[1], []style.Declaration{
        {property = .Grid_Column_Start, value = style.number(2)}, {property = .Grid_Column_End, value = style.span(2)},
    })
    style.set_inline(h.engine, item_ids[4], []style.Declaration{
        {property = .Grid_Column_Start, value = style.number(1)}, {property = .Grid_Column_End, value = style.number(-1)},
        px(.Margin_Left, 5),
    })
    passes := run(h, root, 320, 600)

    testing.expect_value(t, rect(grid), [4]f32{0, 0, 320, 140})
    testing.expect_value(t, rect(items[0]), [4]f32{10, 10, 100, 40})
    testing.expect_value(t, rect(items[1]), [4]f32{120, 10, 190, 40})
    testing.expect_value(t, rect(items[2]), [4]f32{10, 60, 100, 30})
    testing.expect_value(t, rect(items[3]), [4]f32{120, 60, 90, 30})
    testing.expect_value(t, rect(items[4]), [4]f32{15, 100, 295, 30})
    testing.expect(t, passes <= 2)
    testing.expect_value(t, run(h, root, 320, 600), 0)

    style.set_inline(h.engine, grid_id, []style.Declaration{
        display(.Grid),
        style.grid_tracks(.Grid_Template_Columns, []style.Track{{kind = .Fr, value = 1, min = 100, repeat = .Auto_Fill}}),
        style.grid_tracks(.Grid_Auto_Rows, []style.Track{{kind = .Px, value = 20}}),
    })
    for id in item_ids { style.set_inline(h.engine, id, nil) }
    run(h, root, 320, 600)
    testing.expect_value(t, rect(items[2]), [4]f32{213, 0, 107, 20})
    testing.expect_value(t, rect(items[3]), [4]f32{0, 20, 107, 20})
    testing.expect_value(t, YG.NodeLayoutGetHeight(grid.raw), f32(40))
}

@(test)
grid_items_fill_named_areas :: proc(t: ^testing.T) {
    root, grid, header, side, body := node.New(), node.New(), node.New(), node.New(), node.New()
    defer root->free()
    root->add(grid); grid->add(body); grid->add(side); grid->add(header)
    h := create_host(); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    grid_id, _ := bind(h, grid, "box")
    style.set_inline(h.engine, root_id, []style.Declaration{px(.Width, 300), {property = .Flex_Direction, value = style.keyword(.Column)}})
    style.set_inline(h.engine, grid_id, []style.Declaration{
        display(.Grid), px(.Column_Gap, 10),
        style.grid_tracks(.Grid_Template_Columns, []style.Track{{kind = .Px, value = 80}, {kind = .Fr, value = 1}}),
        style.grid_tracks(.Grid_Template_Rows, []style.Track{{kind = .Px, value = 30}, {kind = .Px, value = 60}}),
        style.grid_areas([]style.Area{
            {name = style.area_name("header"), row = 0, column = 0, row_span = 1, column_span = 2},
            {name = style.area_name("side"), row = 1, column = 0, row_span = 1, column_span = 1},
            {name = style.area_name("body"), row = 1, column = 1, row_span = 1, column_span = 1},
        }),
    })
    names := [3]string{"header", "side", "body"}
    for n, i in ([]^node.BaseNode{header, side, body}) {
        id, _ := bind(h, n, "box")
        name := style.area(names[i])
        style.set_inline(h.engine, id, []style.Declaration{
            {property = .Grid_Row_Start, value = name}, {property = .Grid_Column_Start, value = name},
            {property = .Grid_Row_End, value = name}, {property = .Grid_Column_End, value = name},
        })
    }
    run(h, root, 300, 600)
    testing.expect_value(t, rect(header), [4]f32{0, 0, 300, 30})
    testing.expect_value(t, rect(side), [4]f32{0, 30, 80, 60})
    testing.expect_value(t, rect(body), [4]f32{90, 30, 210, 60})
}

@(test)
grid_auto_tracks_take_their_content :: proc(t: ^testing.T) {
    root, grid, a, b, inner := node.New(), node.New(), node.New(), node.New(), node.New()
    defer root->free()
    root->add(grid); grid->add(a); grid->add(b); a->add(inner)
    h := create_host(); defer destroy_host(h)
    root_id, _ := bind(h, root, "box")
    grid_id, _ := bind(h, grid, "box")
    a_id, _ := bind(h, a, "box")
    bind(h, b, "box")
    inner_id, _ := bind(h, inner, "box")
    style.set_inline(h.engine, root_id, []style.Declaration{px(.Width, 300), {property = .Flex_Direction, value = style.keyword(.Column)}})
    style.set_inline(h.engine, grid_id, []style.Declaration{
        display(.Grid),
        style.grid_tracks(.Grid_Template_Columns, []style.Track{{kind = .Max_Content}, {kind = .Fr, value = 1}}),
    })
    style.set_inline(h.engine, a_id, []style.Declaration{px(.Padding_Left, 4)})
    style.set_inline(h.engine, inner_id, []style.Declaration{px(.Width, 60), px(.Height, 25)})
    run(h, root, 300, 600)
    testing.expect_value(t, rect(a), [4]f32{0, 0, 64, 25})
    testing.expect_value(t, rect(b), [4]f32{64, 0, 236, 25})
    testing.expect_value(t, rect(inner), [4]f32{4, 0, 60, 25})
    testing.expect_value(t, run(h, root, 300, 600), 0)

    style.set_inline(h.engine, inner_id, []style.Declaration{px(.Width, 80), px(.Height, 35)})
    run(h, root, 300, 600)
    testing.expect_value(t, rect(a), [4]f32{0, 0, 84, 35})
    testing.expect_value(t, YG.NodeLayoutGetHeight(grid.raw), f32(35))

    style.set_inline(h.engine, grid_id, []style.Declaration{
        display(.Grid),
        style.grid_tracks(.Grid_Template_Columns, []style.Track{{kind = .Px, value = 200}, {kind = .Fr, value = 1}}),
        {property = .Justify_Items, value = style.keyword(.Center)},
    })
    run(h, root, 300, 600)
    testing.expect_value(t, rect(a), [4]f32{58, 0, 84, 35})
}
