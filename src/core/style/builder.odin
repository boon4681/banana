package style

Rule_Builder :: struct {
    using _vt: ^Rule_Builder_VTable,
    sheet: ^Stylesheet_Desc,
    index: int,
    declarations: [dynamic]Declaration,
}

Rule_Builder_VTable :: struct {
    set: proc(self: ^Rule_Builder, property: Property, value: Value) -> ^Rule_Builder,

    set_display:         proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_position:        proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_flex_direction:  proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_flex_wrap:       proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_justify_content: proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_align_items:     proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_align_self:      proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_align_content:   proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_box_sizing:      proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_overflow:        proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_overflow_x:      proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_overflow_y:      proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_visibility:      proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_pointer_events:  proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_direction:       proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_text_align:      proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_cursor:          proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_user_select:     proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,
    set_border_style:    proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder,

    set_flex_grow:    proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder,
    set_flex_shrink:  proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder,
    set_opacity:      proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder,
    set_z_index:      proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder,
    set_font_weight:  proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder,
    set_aspect_ratio: proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder,
    set_rotate:       proc(self: ^Rule_Builder, degrees: f32) -> ^Rule_Builder,

    set_width:       proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_height:      proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_min_width:   proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_min_height:  proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_max_width:   proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_max_height:  proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_flex_basis:  proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_font_size:   proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_line_height: proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,

    set_margin:        proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_margin_x:      proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_margin_y:      proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_margin_top:    proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_margin_right:  proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_margin_bottom: proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_margin_left:   proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,

    set_padding:        proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_padding_x:      proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_padding_y:      proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_padding_top:    proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_padding_right:  proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_padding_bottom: proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_padding_left:   proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,

    set_inset:  proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_top:    proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_right:  proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_bottom: proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_left:   proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,

    set_gap:        proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_row_gap:    proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,
    set_column_gap: proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,

    set_border_width:  proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder,
    set_border_radius: proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder,

    set_color:            proc(self: ^Rule_Builder, c: [4]u8) -> ^Rule_Builder,
    set_background_color: proc(self: ^Rule_Builder, c: [4]u8) -> ^Rule_Builder,
    set_border_color:     proc(self: ^Rule_Builder, c: [4]u8) -> ^Rule_Builder,
}

sheet :: proc() -> Stylesheet_Desc {
    return {version = IR_VERSION}
}

rule :: proc(
    s: ^Stylesheet_Desc,
    tag: string,
    states: State_Set = {},
    pseudo: Pseudo_Element = .None,
    allocator := context.allocator,
) -> ^Rule_Builder {
    context.allocator = allocator
    tests := make([dynamic]Selector_Test)
    if tag == "" {
        append(&tests, Selector_Test{kind = .Universal})
    } else {
        append(&tests, Selector_Test{kind = .Tag, name = tag})
    }
    for state in State {
        if state in states do append(&tests, Selector_Test{kind = .State, state = state})
    }
    steps := make([]Selector_Step, 1)
    steps[0] = {tests = tests[:]}
    selectors := make([]Selector, 1)
    selectors[0] = {steps = steps, pseudo = pseudo}

    rules := make([]Rule, len(s.rules) + 1)
    copy(rules, s.rules)
    rules[len(s.rules)] = {selectors = selectors}
    s.rules = rules

    builder := new(Rule_Builder)
    builder._vt = &rule_builder_vtable
    builder.sheet = s
    builder.index = len(rules) - 1
    builder.declarations = make([dynamic]Declaration)
    return builder
}

@(private)
rule_set :: proc(self: ^Rule_Builder, property: Property, value: Value) -> ^Rule_Builder {
    for &declaration in self.declarations {
        if declaration.property == property {
            declaration = {property = property, value = value}
            return self
        }
    }
    append(&self.declarations, Declaration{property = property, value = value})
    self.sheet.rules[self.index].declarations = self.declarations[:]
    return self
}

@(private)
rule_set_run :: proc(self: ^Rule_Builder, first: Property, count: int, value: Value) -> ^Rule_Builder {
    for i in 0..<count do rule_set(self, Property(int(first) + i), value)
    return self
}

@(private)
rule_color :: proc(c: [4]u8) -> Value {
    return rgba(f32(c.r) / 255, f32(c.g) / 255, f32(c.b) / 255, f32(c.a) / 255)
}

@(private)
rule_builder_vtable := Rule_Builder_VTable{
    set = rule_set,

    set_display         = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Display, keyword(k)) },
    set_position        = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Position, keyword(k)) },
    set_flex_direction  = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Flex_Direction, keyword(k)) },
    set_flex_wrap       = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Flex_Wrap, keyword(k)) },
    set_justify_content = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Justify_Content, keyword(k)) },
    set_align_items     = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Align_Items, keyword(k)) },
    set_align_self      = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Align_Self, keyword(k)) },
    set_align_content   = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Align_Content, keyword(k)) },
    set_box_sizing      = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Box_Sizing, keyword(k)) },
    set_overflow        = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set_run(self, .Overflow_X, 2, keyword(k)) },
    set_overflow_x      = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Overflow_X, keyword(k)) },
    set_overflow_y      = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Overflow_Y, keyword(k)) },
    set_visibility      = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Visibility, keyword(k)) },
    set_pointer_events  = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Pointer_Events, keyword(k)) },
    set_direction       = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Direction, keyword(k)) },
    set_text_align      = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Text_Align, keyword(k)) },
    set_cursor          = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .Cursor, keyword(k)) },
    set_user_select     = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set(self, .User_Select, keyword(k)) },
    set_border_style    = proc(self: ^Rule_Builder, k: Keyword) -> ^Rule_Builder { return rule_set_run(self, .Border_Top_Style, 4, keyword(k)) },

    set_flex_grow    = proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder { return rule_set(self, .Flex_Grow, number(v)) },
    set_flex_shrink  = proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder { return rule_set(self, .Flex_Shrink, number(v)) },
    set_opacity      = proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder { return rule_set(self, .Opacity, number(v)) },
    set_z_index      = proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder { return rule_set(self, .Z_Index, number(v)) },
    set_font_weight  = proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder { return rule_set(self, .Font_Weight, number(v)) },
    set_aspect_ratio = proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder { return rule_set(self, .Aspect_Ratio, number(v)) },
    set_rotate       = proc(self: ^Rule_Builder, degrees: f32) -> ^Rule_Builder { return rule_set(self, .Rotate, number(degrees)) },

    set_width       = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Width, length(v, u)) },
    set_height      = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Height, length(v, u)) },
    set_min_width   = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Min_Width, length(v, u)) },
    set_min_height  = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Min_Height, length(v, u)) },
    set_max_width   = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Max_Width, length(v, u)) },
    set_max_height  = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Max_Height, length(v, u)) },
    set_flex_basis  = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Flex_Basis, length(v, u)) },
    set_font_size   = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Font_Size, length(v, u)) },
    set_line_height = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Line_Height, length(v, u)) },

    set_margin        = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set_run(self, .Margin_Top, 4, length(v, u)) },
    set_margin_x      = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { rule_set(self, .Margin_Left, length(v, u)); return rule_set(self, .Margin_Right, length(v, u)) },
    set_margin_y      = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { rule_set(self, .Margin_Top, length(v, u)); return rule_set(self, .Margin_Bottom, length(v, u)) },
    set_margin_top    = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Margin_Top, length(v, u)) },
    set_margin_right  = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Margin_Right, length(v, u)) },
    set_margin_bottom = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Margin_Bottom, length(v, u)) },
    set_margin_left   = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Margin_Left, length(v, u)) },

    set_padding        = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set_run(self, .Padding_Top, 4, length(v, u)) },
    set_padding_x      = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { rule_set(self, .Padding_Left, length(v, u)); return rule_set(self, .Padding_Right, length(v, u)) },
    set_padding_y      = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { rule_set(self, .Padding_Top, length(v, u)); return rule_set(self, .Padding_Bottom, length(v, u)) },
    set_padding_top    = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Padding_Top, length(v, u)) },
    set_padding_right  = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Padding_Right, length(v, u)) },
    set_padding_bottom = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Padding_Bottom, length(v, u)) },
    set_padding_left   = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Padding_Left, length(v, u)) },

    set_inset  = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set_run(self, .Top, 4, length(v, u)) },
    set_top    = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Top, length(v, u)) },
    set_right  = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Right, length(v, u)) },
    set_bottom = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Bottom, length(v, u)) },
    set_left   = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Left, length(v, u)) },

    set_gap        = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set_run(self, .Row_Gap, 2, length(v, u)) },
    set_row_gap    = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Row_Gap, length(v, u)) },
    set_column_gap = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set(self, .Column_Gap, length(v, u)) },

    set_border_width  = proc(self: ^Rule_Builder, v: f32) -> ^Rule_Builder { return rule_set_run(self, .Border_Top_Width, 4, length(v)) },
    set_border_radius = proc(self: ^Rule_Builder, v: f32, u: Unit = .Px) -> ^Rule_Builder { return rule_set_run(self, .Border_Top_Left_Radius, 4, length(v, u)) },

    set_color            = proc(self: ^Rule_Builder, c: [4]u8) -> ^Rule_Builder { return rule_set(self, .Color, rule_color(c)) },
    set_background_color = proc(self: ^Rule_Builder, c: [4]u8) -> ^Rule_Builder { return rule_set(self, .Background_Color, rule_color(c)) },
    set_border_color     = proc(self: ^Rule_Builder, c: [4]u8) -> ^Rule_Builder { return rule_set_run(self, .Border_Top_Color, 4, rule_color(c)) },
}
