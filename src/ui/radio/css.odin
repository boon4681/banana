package radio

import "base:runtime"
import css "src:core/style"
import style_native "src:core/style/native"
import "src:ui/shared/theme"

CSS_TAG :: "radio"

css_defaults: css.Stylesheet_Desc

@(init)
_init_default :: proc "contextless" () {
    context = runtime.default_context()
    css_defaults = css.sheet()

    r := css.rule(&css_defaults, CSS_TAG)
    r->set_align_items(.Center)
    r->set_flex_shrink(0)
    r->set_padding_left(SIZE + GAP)
    r->set_min_height(SIZE)
    r->set_min_width(SIZE)
    r->set_user_select(.None)
    r->set_background_color(theme.INPUT_FILL)
    r->set_border_width(1)
    r->set_border_color(theme.INPUT)

    css.rule(&css_defaults, CSS_TAG, {.Checked})->set_border_color(theme.PRIMARY)

    ring := css.rule(&css_defaults, CSS_TAG, {.Focus_Visible})
    ring->set(.Outline_Style, css.keyword(.Solid))
    ring->set(.Outline_Width, css.length(3))
    ring->set(.Outline_Color, css.rgba(115.0/255, 115.0/255, 115.0/255, 0.5))

    css.rule(&css_defaults, CSS_TAG, {.Disabled})->set_opacity(0.5)
}

css_states :: proc(n: ^Node) -> css.State_Set {
    choice := cast(^Radio)n
    states: css.State_Set = {.Disabled} if choice.disabled else {.Enabled}
    if choice.checked do states += {.Checked}
    return states
}

apply_style :: proc(n: ^Node, c: css.Computed_Style, alpha: f32, pseudo: style_native.Pseudo_Styles) {
    s := cast(^Radio_Style)n._internal_style
    s.mark = theme.PRIMARY
    s.mark.a = u8(clamp(alpha * 255, 0, 255))
}
