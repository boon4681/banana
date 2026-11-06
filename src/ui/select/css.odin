package select

import "base:runtime"
import css "src:core/style"
import "src:ui/shared/theme"

CSS_TAG :: "select"

css_defaults: css.Stylesheet_Desc

@(init)
_init_default :: proc "contextless" () {
    context = runtime.default_context()
    css_defaults = css.sheet()

    r := css.rule(&css_defaults, CSS_TAG)
    r->set_align_items(.Center)
    r->set_flex_wrap(.No_Wrap)
    r->set_flex_shrink(0)
    r->set_height(36)
    r->set_min_width(140)
    r->set_padding_left(12)
    r->set_padding_right(32)
    r->set_user_select(.None)
    r->set_cursor(.Default)
    r->set_font_size(14)
    r->set_color(theme.FOREGROUND)
    r->set_background_color(theme.INPUT_FILL)
    r->set_border_width(1)
    r->set_border_color(theme.INPUT)
    r->set_border_radius(theme.RADIUS)

    ring := css.rule(&css_defaults, CSS_TAG, {.Focus_Visible})
    ring->set(.Outline_Style, css.keyword(.Solid))
    ring->set(.Outline_Width, css.length(3))
    ring->set(.Outline_Color, css.rgba(115.0/255, 115.0/255, 115.0/255, 0.5))

    css.rule(&css_defaults, CSS_TAG, {.Disabled})->set_opacity(0.5)
}

css_states :: proc(n: ^Node) -> css.State_Set {
    return {.Disabled} if (cast(^Select)n).disabled else {.Enabled}
}
