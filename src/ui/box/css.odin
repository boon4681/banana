package box

import "base:runtime"
import css "src:core/style"

CSS_TAG :: "box"

css_defaults: css.Stylesheet_Desc

@(init)
_init_default :: proc "contextless" () {
    context = runtime.default_context()
    css_defaults = css.sheet()

    r := css.rule(&css_defaults, CSS_TAG)
    r->set_flex_wrap(.Wrap)
    r->set_align_items(.Flex_Start)
    r->set_align_content(.Flex_Start)
}
