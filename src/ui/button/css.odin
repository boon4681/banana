package button

import "base:runtime"
import css "src:core/style"
import style_native "src:core/style/native"

CSS_TAG :: "button"

css_defaults: css.Stylesheet_Desc

@(init)
_init_default :: proc "contextless" () {
    context = runtime.default_context()
    css_defaults = css.sheet()

    r := css.rule(&css_defaults, CSS_TAG)
    r->set_justify_content(.Center)
    r->set_align_items(.Center)
    r->set_flex_shrink(0)
    r->set_cursor(.Default)
    r->set_user_select(.None)
}

apply_style :: proc(n: ^Node, c: css.Computed_Style, alpha: f32, pseudo: style_native.Pseudo_Styles) {
    s := cast(^Button_Style)n._internal_style
    s.hover = s.background
    s.pressed = s.background
}
