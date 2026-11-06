package option

import "base:runtime"
import css "src:core/style"

CSS_TAG :: "option"

css_defaults: css.Stylesheet_Desc

@(init)
_init_default :: proc "contextless" () {
    context = runtime.default_context()
    css_defaults = css.sheet()
    css.rule(&css_defaults, CSS_TAG)->set_display(.None)
}
