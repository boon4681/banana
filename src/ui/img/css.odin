package img

import "base:runtime"
import css "src:core/style"
import style_native "src:core/style/native"

CSS_TAG :: "img"

css_defaults: css.Stylesheet_Desc

@(init)
_init_default :: proc "contextless" () {
    context = runtime.default_context()
    css_defaults = css.sheet()

    css.rule(&css_defaults, CSS_TAG)->set_max_width(100, .Percent)
}

apply_style :: proc(n: ^Node, c: css.Computed_Style, alpha: f32, pseudo: style_native.Pseudo_Styles) {
    s := cast(^Img_Style)n._internal_style
    s.tint.a = u8(clamp(alpha * 255 + 0.5, 0, 255))
}
