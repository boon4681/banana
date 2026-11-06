#+build !wasm32
package style

import "core:testing"

@(test)
calc_resolves_relative_terms_and_keeps_percentages :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    set_environment(e, {width = 1000, height = 500, root_font_size = 16})
    testing.expect_value(t, set_inline(e, 1, []Declaration{
        {property = .Font_Size, value = length(10)},
        calc(.Width, #partial [Unit]f32{.Percent = 100, .Px = -20}),
        calc(.Height, #partial [Unit]f32{.Em = 2, .Px = 4, .Vw = 1}),
        calc(.Padding_Left, #partial [Unit]f32{.Px = 4, .Rem = -1}),
        calc(.Max_Width, #partial [Unit]f32{.Percent = 50}),
    }), Error.None)
    update(e)
    c, _ := computed_style(e, 1)
    testing.expect_value(t, c[.Width], mixed(-20, 100))
    testing.expect_value(t, c[.Width].unit, Unit.Calc)
    testing.expect_value(t, resolve_percent(c[.Width], 300), f32(280))
    testing.expect_value(t, c[.Height], length(34))
    testing.expect_value(t, c[.Padding_Left], length(0))
    testing.expect_value(t, c[.Max_Width], length(50, .Percent))
    testing.expect_value(t, set_inline(e, 1, []Declaration{calc(.Border_Top_Width, #partial [Unit]f32{.Percent = 10, .Px = 1})}), Error.Invalid_Declaration)
}

@(test)
lengths_and_percentages_interpolate_as_calc :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(100)}})
    set_transitions(e, 1, []Transition{{property = .Width, duration = 1, easing = {kind = .Linear}}})
    update(e, 0)
    set_inline(e, 1, []Declaration{{property = .Width, value = length(50, .Percent)}})
    update(e, 0); update(e, 0.5)
    c, _ := presented_style(e, 1)
    testing.expect_value(t, c[.Width], mixed(50, 25))
    update(e, 1)
    c, _ = presented_style(e, 1)
    testing.expect_value(t, c[.Width], length(50, .Percent))
}

@(test)
border_style_color_and_radius :: proc(t: ^testing.T) {
    scene: Scene
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1)
    set_inline(e, 1, []Declaration{{property = .Color, value = RED}, {property = .Border_Top_Width, value = length(4)}})
    update(e)
    c, _ := computed_style(e, 1)
    testing.expect_value(t, c[.Border_Top_Width], length(0))
    testing.expect_value(t, c[.Border_Top_Color], RED)
    set_inline(e, 1, []Declaration{
        {property = .Color, value = RED},
        {property = .Border_Top_Width, value = length(4)},
        {property = .Border_Top_Style, value = keyword(.Solid)},
        {property = .Border_Left_Style, value = keyword(.Solid)},
        {property = .Border_Left_Color, value = BLUE},
        {property = .Border_Top_Left_Radius, value = length(50, .Percent)},
    })
    update(e)
    c, _ = computed_style(e, 1)
    testing.expect_value(t, c[.Border_Top_Width], length(4))
    testing.expect_value(t, c[.Border_Left_Width], length(3))
    testing.expect_value(t, c[.Border_Right_Width], length(0))
    testing.expect_value(t, c[.Border_Left_Color], BLUE)
    testing.expect_value(t, c[.Border_Top_Left_Radius], length(50, .Percent))
    testing.expect_value(t, set_inline(e, 1, []Declaration{{property = .Border_Top_Style, value = keyword(.Wrap)}}), Error.Invalid_Declaration)
    testing.expect_value(t, set_inline(e, 1, []Declaration{{property = .Border_Top_Left_Radius, value = length(-1)}}), Error.Invalid_Declaration)
}

@(test)
font_family_text_align_cursor_and_transform :: proc(t: ^testing.T) {
    scene: Scene
    scene[2].parent = 1
    e := make_engine(&scene); defer destroy(e)
    attach_node(e, 1); attach_node(e, 2)
    names := []string{"Inter", "sans-serif"}
    set_inline(e, 1, []Declaration{
        font_family(names),
        {property = .Text_Align, value = keyword(.Center)},
        {property = .Cursor, value = keyword(.Pointer)},
        {property = .Translate_X, value = length(-50, .Percent)},
        {property = .Rotate, value = number(45)},
    })
    names[0] = "mutated"
    update(e)
    parent, _ := computed_style(e, 1)
    child, _ := computed_style(e, 2)
    testing.expect_value(t, len(family(e, child[.Font_Family])), 2)
    testing.expect_value(t, family(e, child[.Font_Family])[0], "Inter")
    testing.expect_value(t, child[.Font_Family], parent[.Font_Family])
    testing.expect_value(t, child[.Text_Align], keyword(.Center))
    testing.expect_value(t, child[.Cursor], keyword(.Pointer))
    testing.expect_value(t, parent[.Translate_X], length(-50, .Percent))
    testing.expect_value(t, child[.Translate_X], length(0))
    testing.expect_value(t, child[.Rotate], number(0))
    testing.expect_value(t, child[.Scale_X], number(1))
    testing.expect_value(t, len(family(e, initial(.Font_Family))), 0)
    testing.expect_value(t, set_inline(e, 2, []Declaration{{property = .Font_Family, value = length(1)}}), Error.Invalid_Declaration)
    set_inline(e, 2, []Declaration{font_family([]string{"Inter", "sans-serif"})})
    update(e)
    child, _ = computed_style(e, 2)
    testing.expect_value(t, child[.Font_Family], parent[.Font_Family])
}
