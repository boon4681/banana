package text_input

import "base:runtime"
import css "src:core/style"
import style_native "src:core/style/native"

CSS_TAG :: "input"

css_defaults: css.Stylesheet_Desc

@(init)
_init_default :: proc "contextless" () {
    context = runtime.default_context()
    css_defaults = css.sheet()

    r := css.rule(&css_defaults, CSS_TAG)
    r->set_align_items(.Center)
    r->set_flex_shrink(0)
    r->set_width(200)
    r->set_overflow(.Hidden)
    r->set_cursor(.Text)
    r->set_user_select(.None)

    css.rule(&css_defaults, CSS_TAG, pseudo = .Selection)->set_background_color({70, 100, 200, 110})
}

css_states :: proc(n: ^Node) -> css.State_Set {
    return {.Disabled} if (cast(^Input)n).disabled else {.Enabled}
}

apply_style :: proc(n: ^Node, c: css.Computed_Style, alpha: f32, pseudo: style_native.Pseudo_Styles) {
    s := cast(^Input_Style)n._internal_style
    s.placeholder_color = style_native.color(c[.Color], alpha * 0.5)
    if placeholder := pseudo[.Placeholder]; placeholder != nil { s.placeholder_color = style_native.color(placeholder[.Color], alpha) }
    if selection := pseudo[.Selection]; selection != nil { s.selection_color = style_native.color(selection[.Background_Color], alpha) }
    s.caret_color = style_native.color(c[.Color], alpha)
    s.border_focus_color = {}
}
